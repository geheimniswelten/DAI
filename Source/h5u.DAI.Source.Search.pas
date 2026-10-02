unit h5u.DAI.Source.Search;

interface

uses
  System.Generics.Collections,
  System.JSON;

type
  TDAISourceSnapshot = record
    Content: string;
    Source: string;
  end;

  TDAISourceSearchOptions = record
    FilePatterns: TArray<string>;
    CaseSensitive: Boolean;
    WholeWord: Boolean;
    InterfacesOnly: Boolean;
    MaximumResults: Integer;
    MaximumFiles: Integer;
    TimeoutMs: Integer;
  end;

  TDAISourceSearch = class sealed
  public
    class function MatchesFilePatterns(const AFileName: string; const APatterns: TArray<string>): Boolean; static;
    class function Search(const AQuery: string; const ARootDirectories, AExplicitFileNames, AReadOnlyRoots: TArray<string>;
      const ASnapshots: TDictionary<string, TDAISourceSnapshot>; const AOptions: TDAISourceSearchOptions): TJSONObject; static;
  end;

implementation

uses
  System.Character,
  System.Diagnostics,
  System.Generics.Defaults,
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Source.View,
  h5u.DAI.Text.Encoding;

const
  CMaximumFileSize = 2 * 1024 * 1024;
  CMaximumExcerptLength = 240;
  CMaximumErrors = 20;

type
  TSourceSearchRun = class
  strict private
    FQuery: string;
    FOptions: TDAISourceSearchOptions;
    FClock: TStopwatch;
    FResult: TJSONObject;
    FMatches: TJSONArray;
    FErrors: TJSONArray;
    FErrorsTruncated: Boolean;
    FFilesScanned: Integer;
    FFilesSkipped: Integer;
    FImplementationFilesOmitted: Integer;
    FStopped: Boolean;
    FLimitReason: string;
    FRoots: TList<string>;
    FReadOnlyRoots: TList<string>;
    FVisited: TDictionary<string, Boolean>;
    FVisitedDirectories: TDictionary<string, Boolean>;
    FSnapshots: TDictionary<string, TDAISourceSnapshot>;
    FCheckBudget: TFunc<Boolean>;
    function BudgetAvailable: Boolean;
    function NormalizePath(const APath: string; out ANormalized: string): Boolean;
    function DiskPathAllowed(const APath: string; out AReason: string): Boolean;
    function IsReadOnlyReference(const AFileName: string): Boolean;
    function MatchAt(const AContent: string; APosition: Integer): Boolean;
    function MatchesFileName(const AFileName: string): Boolean;
    function RootForFile(const AFileName: string): string;
    procedure AddError(const AFileName, AReason: string);
    procedure AddRoots(const APaths: TArray<string>; const ATarget: TList<string>);
    procedure AddMatch(const AFileName, AContent, ASource: string; APosition, ALine, ALineStart: Integer);
    procedure SearchContent(const AFileName, AContent, ASource: string);
    procedure SearchFile(const AFileName: string);
    procedure SearchRoot(const ARoot: string);
    procedure Stop(const AReason: string);
  public
    constructor Create(const AQuery: string; const AOptions: TDAISourceSearchOptions);
    destructor Destroy; override;
    function Execute(const ARootDirectories, AExplicitFileNames, AReadOnlyRoots: TArray<string>; const ASnapshots: TDictionary<string, TDAISourceSnapshot>): TJSONObject;
  end;

function DefaultFilePatterns: TArray<string>;
begin
  Result := TArray<string>.Create('*.pas', '*.inc', '*.dpr', '*.dpk');
end;

function ValidatedFilePatterns(const APatterns: TArray<string>): TArray<string>;
var
  LPattern: string;
  LCharacter: Char;
begin
  if Length(APatterns) > 100 then
    raise EArgumentException.Create('file_patterns must contain at most 100 patterns.');
  Result := APatterns;
  if Length(Result) = 0 then
    Result := DefaultFilePatterns;
  for LPattern in Result do
  begin
    if (Length(LPattern) = 0) or (Length(LPattern) > 256) then
      raise EArgumentException.Create('Each file pattern must contain 1 to 256 characters.');
    for LCharacter in LPattern do
      if CharInSet(LCharacter, [#0, #10, #13, '[', ']', '\', '/']) then
        raise EArgumentException.Create('File patterns support only filename literals, * and ?; NUL, line breaks, paths and character classes are unsupported.');
  end;
end;

function UnicodeCharacterWidth(const AText: string; APosition: Integer): Integer;
begin
  Result := 1;
  if (APosition < Length(AText)) and AText[APosition].IsHighSurrogate then
    if AText[APosition + 1].IsLowSurrogate then
      Result := 2;
end;

function GlobMatches(const AFileName, APattern: string; const ACheckBudget: TFunc<Boolean>): Boolean;
var
  LNameIndex: Integer;
  LPatternIndex: Integer;
  LStarIndex: Integer;
  LRetryIndex: Integer;
  LNameWidth: Integer;
  LPatternWidth: Integer;
  LSteps: Integer;
  LMatched: Boolean;
begin
  LNameIndex := 1;
  LPatternIndex := 1;
  LStarIndex := 0;
  LRetryIndex := 1;
  LSteps := 0;
  // The last-star retry has no recursive/exponential backtracking. Both inputs are bounded.
  while LNameIndex <= Length(AFileName) do
  begin
    Inc(LSteps);
    if (LSteps and 255) = 0 then
      if Assigned(ACheckBudget) then
        if not ACheckBudget() then
          Exit(False);
    LNameWidth := UnicodeCharacterWidth(AFileName, LNameIndex);
    LPatternWidth := 1;
    LMatched := False;
    if LPatternIndex <= Length(APattern) then
    begin
      if APattern[LPatternIndex] = '*' then
      begin
        LStarIndex := LPatternIndex;
        Inc(LPatternIndex);
        LRetryIndex := LNameIndex;
        Continue;
      end;
      if APattern[LPatternIndex] = '?' then
      begin
        Inc(LPatternIndex);
        Inc(LNameIndex, LNameWidth);
        Continue;
      end;
      LPatternWidth := UnicodeCharacterWidth(APattern, LPatternIndex);
      if LNameWidth = LPatternWidth then
        LMatched := CompareStringOrdinal(PChar(AFileName) + LNameIndex - 1, LNameWidth,
          PChar(APattern) + LPatternIndex - 1, LPatternWidth, {$IF CompilerVersion >= 37}Ord{$IFEND}(True)) = CSTR_EQUAL;
    end;
    if LMatched then
    begin
      Inc(LPatternIndex, LPatternWidth);
      Inc(LNameIndex, LNameWidth);
    end
    else if LStarIndex <> 0 then
    begin
      Inc(LRetryIndex, UnicodeCharacterWidth(AFileName, LRetryIndex));
      LNameIndex := LRetryIndex;
      LPatternIndex := LStarIndex + 1;
    end
    else
      Exit(False);
  end;
  while LPatternIndex <= Length(APattern) do
  begin
    if APattern[LPatternIndex] <> '*' then
      Exit(False);
    Inc(LPatternIndex);
  end;
  Result := True;
end;

function BoundedOption(AValue, ADefault, AMaximum: Integer): Integer;
begin
  if AValue <= 0 then
    Result := ADefault
  else if AValue > AMaximum then
    Result := AMaximum
  else
    Result := AValue;
end;

function PathIsWithin(const AFileName, ARoot: string): Boolean;
var
  LPrefix: string;
begin
  if SameText(AFileName, ARoot) then
    Exit(True);
  LPrefix := IncludeTrailingPathDelimiter(ARoot);
  Result := (Length(AFileName) >= Length(LPrefix)) and SameText(Copy(AFileName, 1, Length(LPrefix)), LPrefix);
end;

function IsWordCharacter(const AContent: string; APosition: Integer): Boolean;
var
  LCategory: TUnicodeCategory;
begin
  if (APosition < 1) or (APosition > Length(AContent)) then
    Exit(False);
  if (APosition > 1) and AContent[APosition].IsLowSurrogate then
    if AContent[APosition - 1].IsHighSurrogate then
      Dec(APosition);
  LCategory := Char.GetUnicodeCategory(AContent, APosition - 1);
  Result := (AContent[APosition] = '_') or Char.IsLetterOrDigit(AContent, APosition - 1) or
    (LCategory in [TUnicodeCategory.ucCombiningMark, TUnicodeCategory.ucEnclosingMark, TUnicodeCategory.ucNonSpacingMark]);
end;

class function TDAISourceSearch.MatchesFilePatterns(const AFileName: string; const APatterns: TArray<string>): Boolean;
var
  LName: string;
  LPattern: string;
  LPatterns: TArray<string>;
begin
  LName := TPath.GetFileName(AFileName);
  LPatterns := ValidatedFilePatterns(APatterns);
  if Length(LName) > 255 then
    Exit(False);
  for LPattern in LPatterns do
    if GlobMatches(LName, LPattern, nil) then
      Exit(True);
  Result := False;
end;

class function TDAISourceSearch.Search(const AQuery: string; const ARootDirectories, AExplicitFileNames, AReadOnlyRoots: TArray<string>;
  const ASnapshots: TDictionary<string, TDAISourceSnapshot>; const AOptions: TDAISourceSearchOptions): TJSONObject;
var
  LRun: TSourceSearchRun;
  LOptions: TDAISourceSearchOptions;
begin
  if (AQuery = '') or (Length(AQuery) > 256) or (Pos(#0, AQuery) <> 0) or (Pos(#10, AQuery) <> 0) or (Pos(#13, AQuery) <> 0) then
    raise EArgumentException.Create('query must contain 1 to 256 characters without NUL or line breaks.');
  LOptions := AOptions;
  LOptions.FilePatterns := ValidatedFilePatterns(AOptions.FilePatterns);
  LRun := TSourceSearchRun.Create(AQuery, LOptions);
  try
    Result := LRun.Execute(ARootDirectories, AExplicitFileNames, AReadOnlyRoots, ASnapshots);
  finally
    LRun.Free;
  end;
end;

constructor TSourceSearchRun.Create(const AQuery: string; const AOptions: TDAISourceSearchOptions);
begin
  inherited Create;
  FClock := TStopwatch.StartNew;
  FQuery := AQuery;
  FOptions := AOptions;
  FOptions.MaximumResults := BoundedOption(FOptions.MaximumResults, 200, 1000);
  FOptions.MaximumFiles := BoundedOption(FOptions.MaximumFiles, 10000, 100000);
  FOptions.TimeoutMs := BoundedOption(FOptions.TimeoutMs, 5000, 30000);
  FCheckBudget := function: Boolean
    begin
      Result := BudgetAvailable;
    end;
  FRoots := TList<string>.Create;
  FReadOnlyRoots := TList<string>.Create;
  FVisited := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FVisitedDirectories := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FSnapshots := TDictionary<string, TDAISourceSnapshot>.Create(TIStringComparer.Ordinal);
  FResult := TJSONObject.Create;
  FMatches := TJSONArray.Create;
  FErrors := TJSONArray.Create;
  FResult.AddPair('matches', FMatches);
  FResult.AddPair('errors', FErrors);
end;

destructor TSourceSearchRun.Destroy;
begin
  FCheckBudget := nil;
  FResult.Free;
  FSnapshots.Free;
  FVisitedDirectories.Free;
  FVisited.Free;
  FReadOnlyRoots.Free;
  FRoots.Free;
  inherited;
end;

procedure TSourceSearchRun.Stop(const AReason: string);
begin
  if not FStopped then
  begin
    FStopped := True;
    FLimitReason := AReason;
  end;
end;

function TSourceSearchRun.BudgetAvailable: Boolean;
begin
  if not FStopped and (FClock.ElapsedMilliseconds >= FOptions.TimeoutMs) then
    Stop('timeout');
  Result := not FStopped;
end;

procedure TSourceSearchRun.AddError(const AFileName, AReason: string);
var
  LError: TJSONObject;
begin
  if FErrors.Count >= CMaximumErrors then
  begin
    FErrorsTruncated := True;
    Exit;
  end;
  LError := TJSONObject.Create;
  LError.AddPair('file', AFileName);
  LError.AddPair('reason', Copy(AReason, 1, 512));
  FErrors.AddElement(LError);
end;

function TSourceSearchRun.NormalizePath(const APath: string; out ANormalized: string): Boolean;
begin
  Result := False;
  if APath = '' then
  begin
    AddError(APath, 'Empty path.');
    Exit;
  end;
  try
    ANormalized := StringReplace(TPath.GetFullPath(APath), '/', '\', [rfReplaceAll]);
    if Length(ANormalized) > 3 then
      ANormalized := ExcludeTrailingPathDelimiter(ANormalized);
    Result := True;
  except
    on E: Exception do
      AddError(APath, E.Message);
  end;
end;

procedure TSourceSearchRun.AddRoots(const APaths: TArray<string>; const ATarget: TList<string>);
var
  LPath: string;
  LNormalized: string;
  LExisting: string;
  LDuplicate: Boolean;
begin
  for LPath in APaths do
  begin
    if not BudgetAvailable then
      Exit;
    if not NormalizePath(LPath, LNormalized) then
      Continue;
    LDuplicate := False;
    for LExisting in ATarget do
      if SameText(LExisting, LNormalized) then
      begin
        LDuplicate := True;
        Break;
      end;
    if not LDuplicate then
      ATarget.Add(LNormalized);
  end;
end;

function TSourceSearchRun.DiskPathAllowed(const APath: string; out AReason: string): Boolean;
var
  LPath: string;
  LParent: string;
  LAttributes: DWORD;
begin
  // Check parents too: an explicit filename must not bypass a junction above it.
  LPath := APath;
  repeat
    if not BudgetAvailable then
    begin
      AReason := 'Search timeout.';
      Exit(False);
    end;
    LAttributes := GetFileAttributes(PChar(LPath));
    if LAttributes = INVALID_FILE_ATTRIBUTES then
    begin
      AReason := 'Path cannot be inspected: ' + SysErrorMessage(GetLastError);
      Exit(False);
    end;
    if (LAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
    begin
      AReason := 'Reparse point skipped.';
      Exit(False);
    end;
    LParent := TPath.GetDirectoryName(LPath);
    if (LParent = '') or SameText(LPath, LParent) then
      Break;
    LPath := LParent;
  until False;
  AReason := '';
  Result := True;
end;

function TSourceSearchRun.RootForFile(const AFileName: string): string;
var
  LRoot: string;
begin
  Result := '';
  for LRoot in FRoots do
    if (Length(LRoot) > Length(Result)) and PathIsWithin(AFileName, LRoot) then
      Result := LRoot;
  for LRoot in FReadOnlyRoots do
    if (Length(LRoot) > Length(Result)) and PathIsWithin(AFileName, LRoot) then
      Result := LRoot;
  if Result = '' then
    Result := TPath.GetDirectoryName(AFileName);
end;

function TSourceSearchRun.IsReadOnlyReference(const AFileName: string): Boolean;
var
  LRoot: string;
begin
  for LRoot in FReadOnlyRoots do
    if PathIsWithin(AFileName, LRoot) then
      Exit(True);
  Result := False;
end;

function TSourceSearchRun.MatchAt(const AContent: string; APosition: Integer): Boolean;
begin
  Result := CompareStringOrdinal(PChar(AContent) + APosition - 1, Length(FQuery), PChar(FQuery), Length(FQuery),
    {$IF CompilerVersion >= 37}Ord{$IFEND}(not FOptions.CaseSensitive)) = CSTR_EQUAL;
  if Result and FOptions.WholeWord then
    Result := not IsWordCharacter(AContent, APosition - 1) and not IsWordCharacter(AContent, APosition + Length(FQuery));
end;

function TSourceSearchRun.MatchesFileName(const AFileName: string): Boolean;
var
  LName: string;
  LPattern: string;
begin
  LName := TPath.GetFileName(AFileName);
  if Length(LName) > 255 then
    Exit(False);
  for LPattern in FOptions.FilePatterns do
  begin
    if not BudgetAvailable then
      Exit(False);
    if GlobMatches(LName, LPattern, FCheckBudget) then
      Exit(True);
  end;
  Result := False;
end;

procedure TSourceSearchRun.AddMatch(const AFileName, AContent, ASource: string; APosition, ALine, ALineStart: Integer);
var
  LMatch: TJSONObject;
  LStart: Integer;
  LFinish: Integer;
  LMaximumFinish: Integer;
  LTruncated: Boolean;
begin
  LStart := APosition;
  while (LStart > ALineStart) and (APosition - LStart < CMaximumExcerptLength div 3) do
    Dec(LStart);
  // Never cut a UTF-16 surrogate pair at an excerpt boundary.
  if (LStart > ALineStart) and AContent[LStart].IsLowSurrogate then
    if AContent[LStart - 1].IsHighSurrogate then
      Dec(LStart);
  LMaximumFinish := LStart + CMaximumExcerptLength - 1;
  LFinish := LStart;
  while (LFinish <= Length(AContent)) and (LFinish <= LMaximumFinish) do
  begin
    if CharInSet(AContent[LFinish], [#13, #10]) then
      Break;
    Inc(LFinish);
  end;
  Dec(LFinish);
  if (LFinish >= LStart) and (LFinish < Length(AContent)) then
    if AContent[LFinish].IsHighSurrogate and AContent[LFinish + 1].IsLowSurrogate then
      Dec(LFinish);
  LTruncated := LStart > ALineStart;
  if LFinish < Length(AContent) then
    LTruncated := LTruncated or not CharInSet(AContent[LFinish + 1], [#13, #10]);
  LMatch := TJSONObject.Create;
  LMatch.AddPair('file', AFileName);
  LMatch.AddPair('line', TJSONNumber.Create(ALine));
  LMatch.AddPair('column', TJSONNumber.Create(APosition - ALineStart + 1));
  LMatch.AddPair('excerpt', Copy(AContent, LStart, LFinish - LStart + 1));
  LMatch.AddPair('excerpt_column', TJSONNumber.Create(LStart - ALineStart + 1));
  LMatch.AddPair('excerpt_truncated', TJSONBool.Create(LTruncated));
  LMatch.AddPair('source', ASource);
  LMatch.AddPair('root', RootForFile(AFileName));
  LMatch.AddPair('read_only_reference', TJSONBool.Create(IsReadOnlyReference(AFileName)));
  FMatches.AddElement(LMatch);
  if FMatches.Count >= FOptions.MaximumResults then
    Stop('maximum_results');
end;

procedure TSourceSearchRun.SearchContent(const AFileName, AContent, ASource: string);
var
  LContent: string;
  LImplementationOmitted: Boolean;
  LPosition: Integer;
  LLine: Integer;
  LLineStart: Integer;
  LLastMatchStart: Integer;
begin
  if (Length(AContent) > CMaximumFileSize) or (Pos(#0, AContent) <> 0) then
  begin
    Inc(FFilesSkipped);
    AddError(AFileName, 'Binary, unavailable or oversized source skipped.');
    Exit;
  end;
  LContent := AContent;
  if FOptions.InterfacesOnly then
  begin
    LContent := TDAISourceView.InterfaceText(AFileName, AContent, LImplementationOmitted);
    if LImplementationOmitted then
      Inc(FImplementationFilesOmitted);
  end;
  if not BudgetAvailable then
    Exit;
  LPosition := 1;
  LLine := 1;
  LLineStart := 1;
  LLastMatchStart := Length(LContent) - Length(FQuery) + 1;
  while LPosition <= Length(LContent) do
  begin
    if ((LPosition and 1023) = 1) and not BudgetAvailable then
      Exit;
    if LContent[LPosition] = #13 then
    begin
      if LPosition < Length(LContent) then
        if LContent[LPosition + 1] = #10 then
          Inc(LPosition);
      Inc(LLine);
      LLineStart := LPosition + 1;
    end
    else if LContent[LPosition] = #10 then
    begin
      Inc(LLine);
      LLineStart := LPosition + 1;
    end
    else if LPosition <= LLastMatchStart then
      if MatchAt(LContent, LPosition) then
      begin
        AddMatch(AFileName, LContent, ASource, LPosition, LLine, LLineStart);
        if FStopped then
          Exit;
      end;
    Inc(LPosition);
  end;
end;

procedure TSourceSearchRun.SearchFile(const AFileName: string);
var
  LFileName: string;
  LSnapshot: TDAISourceSnapshot;
  LContent: string;
  LReason: string;
  LFormat: TDAITextFileFormat;
  LReadGuard: THandle;
  LInformation: TByHandleFileInformation;
  LSize: UInt64;
begin
  if not BudgetAvailable or not NormalizePath(AFileName, LFileName) then
    Exit;
  if FVisited.ContainsKey(LFileName) or not MatchesFileName(LFileName) then
    Exit;
  if FFilesScanned >= FOptions.MaximumFiles then
  begin
    Stop('maximum_files');
    Exit;
  end;
  FVisited.Add(LFileName, True);
  Inc(FFilesScanned);
  if FSnapshots.TryGetValue(LFileName, LSnapshot) then
  begin
    // A supplied IDE snapshot is authoritative, including unavailable/oversized content.
    if LSnapshot.Source = '' then
      LSnapshot.Source := 'editor_buffer';
    SearchContent(LFileName, LSnapshot.Content, LSnapshot.Source);
    Exit;
  end;
  try
    if not DiskPathAllowed(LFileName, LReason) then
    begin
      Inc(FFilesSkipped);
      AddError(LFileName, LReason);
      Exit;
    end;
    // Keep writers/deletion out while the existing decoding policy reads this file.
    LReadGuard := CreateFile(PChar(LFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, 0);
    if LReadGuard = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    try
      if not GetFileInformationByHandle(LReadGuard, LInformation) then
        RaiseLastOSError;
      if (LInformation.dwFileAttributes and (FILE_ATTRIBUTE_REPARSE_POINT or FILE_ATTRIBUTE_DIRECTORY)) <> 0 then
      begin
        Inc(FFilesSkipped);
        AddError(LFileName, 'Reparse or non-file source skipped.');
        Exit;
      end;
      LSize := (UInt64(LInformation.nFileSizeHigh) shl 32) or LInformation.nFileSizeLow;
      if LSize > CMaximumFileSize then
      begin
        Inc(FFilesSkipped);
        AddError(LFileName, 'Source exceeds the 2 MiB disk file limit.');
        Exit;
      end;
      LContent := TDAITextEncoding.ReadFile(LFileName, LFormat);
    finally
      CloseHandle(LReadGuard);
    end;
    if BudgetAvailable then
      SearchContent(LFileName, LContent, 'disk');
  except
    on E: Exception do
    begin
      Inc(FFilesSkipped);
      AddError(LFileName, E.Message);
    end;
  end;
end;

procedure TSourceSearchRun.SearchRoot(const ARoot: string);
var
  LStack: TStack<string>;
  LDirectory: string;
  LFileName: string;
  LReason: string;
  LSearch: TSearchRec;
  LFindResult: Integer;
begin
  if not BudgetAvailable then
    Exit;
  if not DiskPathAllowed(ARoot, LReason) then
  begin
    AddError(ARoot, LReason);
    Exit;
  end;
  LStack := TStack<string>.Create;
  try
    LStack.Push(ARoot);
    while (LStack.Count > 0) and BudgetAvailable do
    begin
      LDirectory := LStack.Pop;
      if FVisitedDirectories.ContainsKey(LDirectory) then
        Continue;
      FVisitedDirectories.Add(LDirectory, True);
      LFindResult := FindFirst(IncludeTrailingPathDelimiter(LDirectory) + '*', faAnyFile, LSearch);
      if LFindResult <> 0 then
      begin
        if LFindResult <> ERROR_FILE_NOT_FOUND then
          AddError(LDirectory, SysErrorMessage(LFindResult));
        Continue;
      end;
      try
        repeat
          if not BudgetAvailable then
            Break;
          if (LSearch.Name = '.') or (LSearch.Name = '..') then
            Continue;
          LFileName := IncludeTrailingPathDelimiter(LDirectory) + LSearch.Name;
          if (LSearch.FindData.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
          begin
            if (LSearch.Attr and faDirectory) = 0 then
              SearchFile(LFileName)
            else
              AddError(LFileName, 'Reparse directory skipped.');
            Continue;
          end;
          if (LSearch.Attr and faDirectory) <> 0 then
            LStack.Push(LFileName)
          else
            SearchFile(LFileName);
        until System.SysUtils.FindNext(LSearch) <> 0;
      finally
        System.SysUtils.FindClose(LSearch);
      end;
    end;
  finally
    LStack.Free;
  end;
end;

function TSourceSearchRun.Execute(const ARootDirectories, AExplicitFileNames, AReadOnlyRoots: TArray<string>;
  const ASnapshots: TDictionary<string, TDAISourceSnapshot>): TJSONObject;
var
  LPair: TPair<string, TDAISourceSnapshot>;
  LPath: string;
  LNormalized: string;
begin
  AddRoots(ARootDirectories, FRoots);
  AddRoots(AReadOnlyRoots, FReadOnlyRoots);
  if Assigned(ASnapshots) then
    for LPair in ASnapshots do
    begin
      if not BudgetAvailable then
        Break;
      if NormalizePath(LPair.Key, LNormalized) then
        FSnapshots.AddOrSetValue(LNormalized, LPair.Value);
    end;
  for LPath in AExplicitFileNames do
  begin
    if not BudgetAvailable then
      Break;
    SearchFile(LPath);
  end;
  for LPath in FSnapshots.Keys do
  begin
    if not BudgetAvailable then
      Break;
    SearchFile(LPath);
  end;
  for LPath in FRoots do
  begin
    if not BudgetAvailable then
      Break;
    SearchRoot(LPath);
  end;
  FResult.AddPair('files_scanned', TJSONNumber.Create(FFilesScanned));
  FResult.AddPair('files_skipped', TJSONNumber.Create(FFilesSkipped));
  FResult.AddPair('interfaces_only', TJSONBool.Create(FOptions.InterfacesOnly));
  FResult.AddPair('implementation_files_omitted', TJSONNumber.Create(FImplementationFilesOmitted));
  FResult.AddPair('truncated', TJSONBool.Create(FStopped));
  FResult.AddPair('limit_reason', FLimitReason);
  FResult.AddPair('elapsed_ms', TJSONNumber.Create(FClock.ElapsedMilliseconds));
  FResult.AddPair('errors_truncated', TJSONBool.Create(FErrorsTruncated));
  Result := FResult;
  FResult := nil;
end;

end.
