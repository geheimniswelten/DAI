unit h5u.DAI.OTA.Files;

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.JSON;

type
  TDAIFileService = class sealed
  public
    class function OpenFiles: TJSONArray; static;
    class function Projects: TJSONArray; static;
    class function ProjectFiles(const AProjectNameOrPath: string): TJSONArray; static;
    class function DirectoryFiles(const ADirectory: string; const ASearchPattern: string; const ARecursive: Boolean; const AMaximumCount: Integer;
      const AFilenameRegex: string = ''; const AContentQuery: string = ''; const AContentUseRegex: Boolean = False;
      const ACaseSensitive: Boolean = False; const AWholeWord: Boolean = False): TJSONArray; static;
    class function ReferenceRoots: TJSONArray; static;
    class function ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean = True): TJSONObject; static;
    class function WriteFile(const AFileName: string; const AContent: string; const AExpectedSha256: string; const ASave: Boolean; out AUsedEditorBuffer: Boolean):
      TJSONObject; static;
  end;

implementation

uses
  System.Character,
  System.Classes,
  System.Generics.Collections,
  System.Hash,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.ProjectSummary,
  h5u.DAI.Settings,
  h5u.DAI.Source.Regex,
  h5u.DAI.Source.View,
  h5u.DAI.Text.Encoding,
  h5u.DAI.Types;

function PrepareFormEditorText(const AFileName, AText: string): string;
var
  LBinary: TMemoryStream;
  LCharacter: Char;
  LIndex: Integer;
  LInString: Boolean;
  LInput, LOutput: TStringStream;
  LPrepared: TStringBuilder;
  LPreparedText: string;
  LUnicode: Boolean;
begin
  Result := AText;
  if not (SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx')) then
    Exit;
  LUnicode := False;
  for LCharacter in AText do
    if Ord(LCharacter) > 127 then
    begin
      LUnicode := True;
      Break;
    end;
  if not LUnicode then
    Exit;
  // TParser's wide-token branch treats raw UTF-8 bytes as separate characters
  // when a quoted string is adjacent to #nnnn. Escape only literal characters
  // first; doubled quotes, existing escapes and Unicode identifiers stay intact.
  LPrepared := TStringBuilder.Create;
  try
    LInString := False;
    LIndex := 1;
    while LIndex <= Length(AText) do
    begin
      LCharacter := AText[LIndex];
      if LCharacter = '''' then
      begin
        LPrepared.Append(LCharacter);
        if LInString and (LIndex < Length(AText)) then
          if AText[LIndex + 1] = '''' then
          begin
            LPrepared.Append('''');
            Inc(LIndex, 2);
            Continue;
          end;
        LInString := not LInString;
      end
      else if LInString and (Ord(LCharacter) > 127) then
        LPrepared.Append('''#').Append(Ord(LCharacter)).Append('''')
      else
        LPrepared.Append(LCharacter);
      Inc(LIndex);
    end;
    LPreparedText := LPrepared.ToString;
  finally
    LPrepared.Free;
  end;
  // OTA accepts UTF-8, but the native form parser assumes ANSI without a BOM.
  // Let the RTL serialize Unicode string values as unambiguous #nnnn escapes.
  // Unicode identifiers retain the UTF-8 BOM emitted by ObjectBinaryToText.
  if LPreparedText.StartsWith(#$FEFF) then
    LInput := TStringStream.Create(LPreparedText, TEncoding.UTF8)
  else
    LInput := TStringStream.Create(#$FEFF + LPreparedText, TEncoding.UTF8);
  LBinary := TMemoryStream.Create;
  LOutput := TStringStream.Create('', TEncoding.UTF8);
  try
    ObjectTextToBinary(LInput, LBinary);
    LBinary.Position := 0;
    ObjectBinaryToText(LBinary, LOutput);
    // TStringStream.DataString strips the preamble; retain it for identifiers.
    Result := TEncoding.UTF8.GetString(LOutput.Bytes, 0, LOutput.Size);
  finally
    LOutput.Free;
    LBinary.Free;
    LInput.Free;
  end;
end;

procedure AddUniqueFile(const AFiles: TDictionary<string, Boolean>; const AFileName: string);
var
  LFileName: string;
begin
  if Trim(AFileName) = '' then
    Exit;
  try
    LFileName := TDAIOTA.NormalizeFileName(AFileName);
  except
    Exit;
  end;
  AFiles.AddOrSetValue(LFileName, True);
end;

function FileAllowedForRead(const AFileName: string): Boolean;
begin
  Result := TDAIOTA.IsWorkspaceFile(AFileName) or TDAIOTA.IsReadOnlyReferenceFile(AFileName);
end;

function DirectoryAllowedForRead(const ADirectory: string): Boolean;
var
  LRoot: string;
begin
  Result := False;
  for LRoot in TDAIOTA.WorkspaceRoots do
    if TDAIOTA.IsPathWithin(ADirectory, LRoot) or TDAIOTA.SameFile(ADirectory, LRoot) then
      Exit(True);
  for LRoot in TDAISettings.Instance.ReadOnlyRootDirectories do
    if TDAIOTA.IsPathWithin(ADirectory, LRoot) or TDAIOTA.SameFile(ADirectory, LRoot) then
      Exit(True);
end;

function ReadCompleteText(const AFileName: string; out AFromEditor: Boolean; out AFormat: TDAITextFileFormat; out AFromDesigner: Boolean;
  const ARequireAvailableBuffer: Boolean = False): string;
var
  LResult: string;
  LSourceEditor: IOTASourceEditor;
begin
  AFromEditor := False;
  AFromDesigner := False;
  LSourceEditor := TDAIOTA.FindSourceEditor(AFileName);
  if Assigned(LSourceEditor) then
  begin
    AFromEditor := True;
    LResult := '';
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        if ARequireAvailableBuffer then
          if not Assigned(LSourceEditor.CreateReader) then
            raise EInvalidOperation.Create('Der aktuelle Editorpuffer ist nicht lesbar.');
        LResult := TDAIOTA.ReadEditorText(LSourceEditor);
      end);
    AFormat.EncodingKind := tekIDEBuffer;
    AFormat.LineEndingKind := TDAITextEncoding.DetectLineEnding(LResult);
    Exit(LResult);
  end;

  if (SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx')) and
    TDAIOTA.ReadFormText(AFileName, CDAIMaxTextFileBytes, LResult) then
  begin
    AFromEditor := True;
    AFromDesigner := True;
    AFormat.EncodingKind := tekIDEBuffer;
    AFormat.LineEndingKind := TDAITextEncoding.DetectLineEnding(LResult);
    Exit(LResult);
  end;

  if ARequireAvailableBuffer then
    if TDAIOTA.IsFormLoadedForFile(AFileName) then
      raise EInvalidOperation.Create('Der aktuelle Designerpuffer ist nicht lesbar.');

  if not TFile.Exists(AFileName) then
    raise EDAIFileNotFound.CreateFmt('Datei nicht gefunden: %s', [AFileName]);
  if TFile.GetSize(AFileName) > CDAIMaxTextFileBytes then
    raise EInvalidOperation.CreateFmt('Die Datei überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);
  Result := TDAITextEncoding.ReadFile(AFileName, AFormat);
end;

procedure RequireNoReparseReadPath(const APath: string);
var
  LAttributes: DWORD;
  LCurrent, LParent: string;
begin
  LCurrent := TDAIOTA.NormalizeFileName(APath);
  while LCurrent <> '' do
  begin
    LAttributes := GetFileAttributesW(PWideChar(LCurrent));
    if LAttributes = INVALID_FILE_ATTRIBUTES then
      raise EInvalidOperation.CreateFmt('Der Lesepfad konnte nicht geprüft werden: %s (%s).', [LCurrent, SysErrorMessage(GetLastError)]);
    if (LAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
      raise EDAIAccessDenied.CreateFmt('Inhaltsfilter dürfen nicht über Verknüpfungen oder Reparse-Punkte lesen: %s', [LCurrent]);
    LParent := TPath.GetDirectoryName(LCurrent);
    if (LParent = '') or TDAIOTA.SameFile(LCurrent, LParent) then
      Break;
    LCurrent := LParent;
  end;
end;

function DirectoryFilterWordCharacter(const AContent: string; APosition: Integer): Boolean;
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

function DirectoryFilterMatches(const AContent, AQuery: string; const ACaseSensitive, AWholeWord: Boolean; const ARegex: TDAIRegex): Boolean;
var
  LMatch: TDAIRegexMatch;
  LPosition: Integer;
begin
  if Assigned(ARegex) then
  begin
    if not AWholeWord then
      Exit(ARegex.IsMatch(AContent));
    LPosition := 1;
    while LPosition <= Length(AContent) + 1 do
    begin
      LMatch := ARegex.Match(AContent, LPosition);
      if not LMatch.Success then
        Exit(False);
      if not DirectoryFilterWordCharacter(AContent, LMatch.Index - 1) and
        not DirectoryFilterWordCharacter(AContent, LMatch.Index + LMatch.Length) then
        Exit(True);
      // A boundary-rejected match may cover a later valid alternative. Resume
      // after its start, like source_search, including zero-length matches.
      LPosition := LMatch.Index + 1;
      if LPosition <= Length(AContent) then
        if AContent[LPosition].IsLowSurrogate then
          Inc(LPosition);
    end;
    Exit(False);
  end;
  for LPosition := 1 to Length(AContent) - Length(AQuery) + 1 do
    if CompareStringOrdinal(PChar(AContent) + LPosition - 1, Length(AQuery), PChar(AQuery), Length(AQuery),
      {$IF CompilerVersion >= 37}DWORD{$ELSE}BOOL{$IFEND}(Ord(not ACaseSensitive))) = CSTR_EQUAL then
      if not AWholeWord or (not DirectoryFilterWordCharacter(AContent, LPosition - 1) and
        not DirectoryFilterWordCharacter(AContent, LPosition + Length(AQuery))) then
        Exit(True);
  Result := False;
end;

function ContentFilterFiles(const ADirectory, APattern: string; const ARecursive: Boolean; const AFilenameRegex: TDAIRegex): TArray<string>;
var
  LDirectory, LFileName: string;
  LFiles: TList<string>;
  LFindResult: Integer;
  LSearch: TSearchRec;
  LStack: TStack<string>;
begin
  LFiles := TList<string>.Create;
  LStack := TStack<string>.Create;
  try
    LStack.Push(ADirectory);
    while LStack.Count > 0 do
    begin
      LDirectory := LStack.Pop;
      RequireNoReparseReadPath(LDirectory);
      LFindResult := FindFirst(IncludeTrailingPathDelimiter(LDirectory) + '*', faAnyFile, LSearch);
      if LFindResult <> 0 then
      begin
        if (LFindResult <> ERROR_FILE_NOT_FOUND) and (LFindResult <> ERROR_NO_MORE_FILES) then
          raise EInvalidOperation.CreateFmt('Das Verzeichnis konnte nicht durchsucht werden: %s (%s).', [LDirectory, SysErrorMessage(LFindResult)]);
        Continue;
      end;
      try
        repeat
          if (LSearch.Name <> '.') and (LSearch.Name <> '..') then
          begin
            LFileName := TDAIOTA.NormalizeFileName(TPath.Combine(LDirectory, LSearch.Name));
            if not TDAIOTA.IsPathWithin(LFileName, ADirectory) then
              raise EDAIAccessDenied.CreateFmt('Der Suchpfad liegt außerhalb des angegebenen Verzeichnisses: %s', [LFileName]);
            if (LSearch.Attr and faDirectory) <> 0 then
            begin
              if ARecursive then
                LStack.Push(LFileName);
            end
            else if TPath.MatchesPattern(LSearch.Name, APattern, False) then
            begin
              if Assigned(AFilenameRegex) then
              begin
                if AFilenameRegex.IsMatch(LSearch.Name) then
                  LFiles.Add(LFileName);
              end
              else
                LFiles.Add(LFileName);
            end;
          end;
          LFindResult := System.SysUtils.FindNext(LSearch);
        until LFindResult <> 0;
        if LFindResult <> ERROR_NO_MORE_FILES then
          raise EInvalidOperation.CreateFmt('Das Verzeichnis konnte nicht vollständig durchsucht werden: %s (%s).', [LDirectory, SysErrorMessage(LFindResult)]);
      finally
        System.SysUtils.FindClose(LSearch);
      end;
    end;
    Result := LFiles.ToArray;
  finally
    LStack.Free;
    LFiles.Free;
  end;
end;

function ReadDirectoryFilterText(const AFileName: string): string;
var
  LFormat: TDAITextFileFormat;
  LFromDesigner, LFromEditor, LHasBuffer: Boolean;
  LInformation: TByHandleFileInformation;
  LReadGuard: THandle;
  LSourceEditor: IOTASourceEditor;
begin
  if not FileAllowedForRead(AFileName) then
    raise EDAIAccessDenied.CreateFmt('Lesezugriff außerhalb des Workspace und freigegebener Referenzpfade: %s', [AFileName]);
  RequireNoReparseReadPath(AFileName);
  LSourceEditor := TDAIOTA.FindSourceEditor(AFileName);
  LHasBuffer := Assigned(LSourceEditor) or TDAIOTA.IsFormLoadedForFile(AFileName);
  if LHasBuffer then
  begin
    Result := ReadCompleteText(AFileName, LFromEditor, LFormat, LFromDesigner, True);
    if not LFromEditor then
      raise EInvalidOperation.Create('Der aktuelle Editor- oder Designerpuffer ist nicht lesbar.');
  end
  else
  begin
    // Keep disk changes out while the existing encoding-aware reader reads the file.
    LReadGuard := CreateFileW(PWideChar(AFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, 0);
    if LReadGuard = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    try
      if not GetFileInformationByHandle(LReadGuard, LInformation) then
        RaiseLastOSError;
      if (LInformation.dwFileAttributes and (FILE_ATTRIBUTE_REPARSE_POINT or FILE_ATTRIBUTE_DIRECTORY)) <> 0 then
        raise EDAIAccessDenied.Create('Der Inhaltsfilter kann keine Verknüpfung oder Verzeichnisressource lesen.');
      if ((UInt64(LInformation.nFileSizeHigh) shl 32) or LInformation.nFileSizeLow) > CDAIMaxTextFileBytes then
        raise EInvalidOperation.CreateFmt('Die Datei überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);
      Result := ReadCompleteText(AFileName, LFromEditor, LFormat, LFromDesigner, True);
    finally
      CloseHandle(LReadGuard);
    end;
  end;
  if Length(Result) > CDAIMaxTextFileBytes then
    raise EInvalidOperation.CreateFmt('Der Text überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);
  if Pos(#0, Result) <> 0 then
    raise EInvalidOperation.Create('Binärinhalt mit NUL-Zeichen kann nicht als Text gefiltert werden.');
end;

class function TDAIFileService.DirectoryFiles(const ADirectory: string; const ASearchPattern: string; const ARecursive: Boolean; const AMaximumCount: Integer;
  const AFilenameRegex, AContentQuery: string; const AContentUseRegex, ACaseSensitive, AWholeWord: Boolean): TJSONArray;
var
  LContent: string;
  LContentRegex, LFilenameRegex: TDAIRegex;
  LCount: Integer;
  LDirectory: string;
  LFileName: string;
  LFiles: TArray<string>;
  LLimit: Integer;
  LPattern: string;
  LPredicate: TDirectory.TFilterPredicate;
  LSearchOption: TSearchOption;
begin
  LPattern := Trim(ASearchPattern);
  if LPattern = '' then
    LPattern := '*';
  if LPattern.Contains('\') or LPattern.Contains('/') or LPattern.Contains('..') then
    raise EArgumentException.Create('Das Suchmuster darf keinen Verzeichnispfad enthalten.');
  if not TPath.HasValidFileNameChars(LPattern, True) then
    raise EArgumentException.Create('Das Suchmuster enthält ungültige Dateinamenzeichen.');
  if (Length(AContentQuery) > 256) or (Pos(#0, AContentQuery) <> 0) or (Pos(#10, AContentQuery) <> 0) or (Pos(#13, AContentQuery) <> 0) then
    raise EArgumentException.Create('content_query darf höchstens 256 Zeichen ohne NUL oder Zeilenumbrüche enthalten.');
  if AContentUseRegex and (AContentQuery = '') then
    raise EArgumentException.Create('content_use_regex=true erfordert eine nicht leere content_query.');

  if ARecursive then
    LSearchOption := TSearchOption.soAllDirectories
  else
    LSearchOption := TSearchOption.soTopDirectoryOnly;

  LLimit := AMaximumCount;
  if LLimit <= 0 then
    LLimit := 5000;
  LLimit := EnsureRange(LLimit, 1, 50000);

  LFilenameRegex := nil;
  LContentRegex := nil;
  try
    if AFilenameRegex <> '' then
      LFilenameRegex := TDAIRegex.Create(AFilenameRegex, ACaseSensitive);
    if AContentUseRegex then
      LContentRegex := TDAIRegex.Create(AContentQuery, ACaseSensitive);
    LDirectory := TDAISettings.Instance.ExpandPath(ADirectory);
    if not TDirectory.Exists(LDirectory) then
      raise EDirectoryNotFoundException.CreateFmt('Verzeichnis nicht gefunden: %s', [LDirectory]);
    if not DirectoryAllowedForRead(LDirectory) then
      raise EDAIAccessDenied.Create('Das Verzeichnis gehört weder zum Workspace noch zu einem freigegebenen Referenzpfad.');
    if AContentQuery <> '' then
      LFiles := ContentFilterFiles(LDirectory, LPattern, ARecursive, LFilenameRegex)
    else if Assigned(LFilenameRegex) then
    begin
      LPredicate :=
        function(const Path: string; const SearchRec: TSearchRec): Boolean
        begin
          Result := LFilenameRegex.IsMatch(SearchRec.Name);
        end;
      LFiles := TDirectory.GetFiles(LDirectory, LPattern, LSearchOption, LPredicate);
    end
    else
      LFiles := TDirectory.GetFiles(LDirectory, LPattern, LSearchOption);
    TArray.Sort<string>(LFiles);
    Result := TJSONArray.Create;
    try
      LCount := 0;
      for LFileName in LFiles do
      begin
        if AContentQuery <> '' then
        begin
          try
            LContent := ReadDirectoryFilterText(LFileName);
            if not DirectoryFilterMatches(LContent, AContentQuery, ACaseSensitive, AWholeWord, LContentRegex) then
              Continue;
          except
            on E: Exception do
              raise EInvalidOperation.CreateFmt('Der Inhaltsfilter konnte die Datei nicht prüfen: %s (%s).', [LFileName, E.Message]);
          end;
        end;
        Result.Add(TDAIOTA.NormalizeFileName(LFileName));
        Inc(LCount);
        if LCount >= LLimit then
          Break;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    LContentRegex.Free;
    LFilenameRegex.Free;
  end;
end;

class function TDAIFileService.OpenFiles: TJSONArray;
var
  LFileName: string;
  LFiles: TDictionary<string, Boolean>;
begin
  Result := TJSONArray.Create;
  LFiles := TDictionary<string, Boolean>.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure var LEditorIndex: Integer;
        LModuleIndex: Integer;
        LModuleServices: IOTAModuleServices;
        LModule: IOTAModule;
      begin
        if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
          Exit;

        for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
        begin
          LModule := LModuleServices.Modules[LModuleIndex];
          if not Assigned(LModule) then
            Continue;
          AddUniqueFile(LFiles, LModule.FileName);
          for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
            if Assigned(LModule.ModuleFileEditors[LEditorIndex]) then
              AddUniqueFile(LFiles, LModule.ModuleFileEditors[LEditorIndex].FileName);
        end;
      end);

    for LFileName in LFiles.Keys do
      Result.Add(LFileName);
  finally
    LFiles.Free;
  end;
end;

class function TDAIFileService.ProjectFiles(const AProjectNameOrPath: string): TJSONArray;
var
  LFiles: TDictionary<string, Boolean>;
  LFileName: string;
  LProject: IOTAProject;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');
  Result := TJSONArray.Create;
  LFiles := TDictionary<string, Boolean>.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LAdditionalFiles: TStringList;
        LFileName: string;
        LIndex: Integer;
        LModuleInfo: IOTAModuleInfo;
      begin
        AddUniqueFile(LFiles, TDAIOTA.ProjectFileName(LProject));
        for LIndex := 0 to LProject.GetModuleCount - 1 do
        begin
          LModuleInfo := LProject.GetModule(LIndex);
          if not Assigned(LModuleInfo) then
            Continue;
          AddUniqueFile(LFiles, LModuleInfo.FileName);

          LAdditionalFiles := TStringList.Create;
          try
            LModuleInfo.GetAdditionalFiles(LAdditionalFiles);
            for LFileName in LAdditionalFiles do
              AddUniqueFile(LFiles, LFileName);
          finally
            LAdditionalFiles.Free;
          end;
        end;
      end);

    for LFileName in LFiles.Keys do
      Result.Add(LFileName);
  finally
    LFiles.Free;
  end;
end;

class function TDAIFileService.Projects: TJSONArray;
begin
  Result := TDAIProjectSummaryService.Projects;
end;

class function TDAIFileService.ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean): TJSONObject;
var
  LContent: string;
  LFileName: string;
  LFormat: TDAITextFileFormat;
  LFromDesigner: Boolean;
  LFromEditor: Boolean;
  LHash: string;
  LOriginalLength: Integer;
  LImplementationOmitted: Boolean;
  LTruncated: Boolean;
  LViewLength: Integer;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if not FileAllowedForRead(LFileName) then
    raise EDAIAccessDenied.Create('Lesezugriff ist nur auf Workspace- und freigegebene Referenzdateien erlaubt.');

  LContent := ReadCompleteText(LFileName, LFromEditor, LFormat, LFromDesigner);
  LOriginalLength := Length(LContent);
  LHash := THashSHA2.GetHashString(LContent);
  LImplementationOmitted := False;
  if AInterfacesOnly then
    LContent := TDAISourceView.InterfaceText(LFileName, LContent, LImplementationOmitted);
  LViewLength := Length(LContent);
  LTruncated := (AMaximumCharacters > 0) and (Length(LContent) > AMaximumCharacters);
  if LTruncated then
    SetLength(LContent, AMaximumCharacters);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('content', LContent);
  if LFromDesigner then
    Result.AddPair('source', 'designer_buffer')
  else
    Result.AddPair('source', IfThen(LFromEditor, 'editor_buffer', 'disk'));
  Result.AddPair('encoding', TDAITextEncoding.EncodingName(LFormat.EncodingKind));
  Result.AddPair('line_ending', TDAITextEncoding.LineEndingName(LFormat.LineEndingKind));
  Result.AddPair('sha256', LHash);
  Result.AddPair('sha256_scope', 'complete_content');
  Result.AddPair('interfaces_only', TJSONBool.Create(AInterfacesOnly));
  Result.AddPair('implementation_omitted', TJSONBool.Create(LImplementationOmitted));
  Result.AddPair('view_characters', TJSONNumber.Create(LViewLength));
  Result.AddPair('content_complete', TJSONBool.Create(not LImplementationOmitted and not LTruncated));
  Result.AddPair('original_characters', TJSONNumber.Create(LOriginalLength));
  Result.AddPair('truncated', TJSONBool.Create(LTruncated));
  Result.AddPair('read_only_reference', TJSONBool.Create(TDAIOTA.IsReadOnlyReferenceFile(LFileName)));
end;

class function TDAIFileService.ReferenceRoots: TJSONArray;
var
  LAlias: string;
  LDirectory: string;
begin
  Result := TJSONArray.Create;
  for LDirectory in TDAISettings.Instance.ReadOnlyRootDirectories do
  begin
    LAlias := '';
    if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.DelphiSourceDirectory) then
      LAlias := '%BDS%\source'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.ToolsAPIDirectory) then
      LAlias := '%BDS%\source\ToolsAPI'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.SamplesDirectory) then
      LAlias := '%BDS%\Samples'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.CatalogRepositoryAllUsersDirectory) then
      LAlias := '%BDSCatalogRepositoryAllUsers%'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.CatalogRepositoryDirectory) then
      LAlias := '%BDSCatalogRepository%';
    Result.AddElement(
      TJSONObject.Create
        .AddPair('directory', LDirectory)
        .AddPair('alias', LAlias)
        .AddPair('exists', TJSONBool.Create(TDirectory.Exists(LDirectory)))
        .AddPair('read_only', TJSONBool.Create(True))
    );
  end;
end;

class function TDAIFileService.WriteFile(const AFileName: string; const AContent: string; const AExpectedSha256: string; const ASave: Boolean; out AUsedEditorBuffer: Boolean):
  TJSONObject;
var
  LActionServices: IOTAActionServices;
  LActualContent: string;
  LBytes: TBytes;
  LCurrentContent: string;
  LCurrentFormat: TDAITextFileFormat;
  LCurrentHash: string;
  LFileName: string;
  LFromDesigner: Boolean;
  LHasCurrentContent: Boolean;
  LOriginalEncoding: string;
  LOriginalLineEnding: string;
  LProjectSidecar: string;
  LFormat: TDAITextFileFormat;
  LSourceEditor: IOTASourceEditor;
  LWrittenContent: string;
begin
  AUsedEditorBuffer := False;
  LFromDesigner := False;
  LHasCurrentContent := False;
  LOriginalEncoding := '';
  LOriginalLineEnding := '';
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  TDAIOTA.RequireNoReparseWritePath(LFileName);
  if SameText(TPath.GetExtension(LFileName), '.dpr') or SameText(TPath.GetExtension(LFileName), '.dpk') then
    LProjectSidecar := ChangeFileExt(LFileName, '.dproj')
  else if SameText(TPath.GetExtension(LFileName), '.dproj') then
    LProjectSidecar := LFileName
  else
    LProjectSidecar := '';
  if LProjectSidecar <> '' then
  begin
    TDAIOTA.RequireNoReparseWritePath(LProjectSidecar);
    TDAIOTA.RequireNoReparseWritePath(LProjectSidecar + '.local');
  end;

  if TDAIOTA.IsReadOnlyReferenceFile(LFileName) then
    raise EDAIAccessDenied.Create('Delphi-Sourcen, Demos, GetIt-Pakete und zusätzliche Referenzverzeichnisse sind schreibgeschützt.');
  if not TDAIOTA.IsWorkspaceFile(LFileName) then
    raise EDAIAccessDenied.Create('Schreibzugriff ist nur innerhalb geöffneter Workspaces erlaubt.');

  if TFile.Exists(LFileName) or TDAIOTA.IsFileOpenInEditor(LFileName) or TDAIOTA.IsFormLoadedForFile(LFileName) then
  begin
    LCurrentContent := ReadCompleteText(LFileName, AUsedEditorBuffer, LCurrentFormat, LFromDesigner);
    LHasCurrentContent := True;
    LCurrentHash := THashSHA2.GetHashString(LCurrentContent);
    LOriginalEncoding := TDAITextEncoding.EncodingName(LCurrentFormat.EncodingKind);
    LOriginalLineEnding := TDAITextEncoding.LineEndingName(LCurrentFormat.LineEndingKind);
    if (Trim(AExpectedSha256) <> '') and not SameText(LCurrentHash, Trim(AExpectedSha256)) then
      raise EInvalidOperation.CreateFmt('Die Datei wurde zwischenzeitlich geändert. Erwartet: %s; aktuell: %s.', [AExpectedSha256, LCurrentHash]);
  end
  else if Trim(AExpectedSha256) <> '' then
    raise EInvalidOperation.Create('Die Datei existiert nicht mehr; expected_sha256 kann nicht erfüllt werden.');

  TDAISourceView.RequireCompleteUnit(LFileName, AContent);
  LSourceEditor := TDAIOTA.EnsureFormTextEditor(LFileName);
  if Assigned(LSourceEditor) then
  begin
    if LHasCurrentContent then
      LWrittenContent := TDAITextEncoding.PrepareText(LFileName, AContent, LCurrentFormat.LineEndingKind)
    else
      LWrittenContent := TDAITextEncoding.PrepareText(LFileName, AContent, lekNone);
    LWrittenContent := PrepareFormEditorText(LFileName, LWrittenContent);
    if TEncoding.UTF8.GetByteCount(LWrittenContent) > CDAIMaxTextFileBytes then
      raise EInvalidOperation.CreateFmt('Der neue Inhalt überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);

    AUsedEditorBuffer := True;
    LFormat.EncodingKind := tekIDEBuffer;
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        if LHasCurrentContent and (TDAIOTA.ReadEditorText(LSourceEditor) <> LCurrentContent) then
        begin
          if LFromDesigner then
            raise EInvalidOperation.Create('Der Formulartext wurde in einen Textpuffer übertragen. Lesen Sie den aktuellen IDE-Textpuffer erneut.');
          raise EInvalidOperation.Create('Der Editorpuffer wurde während der Schreibanforderung geändert. Lesen Sie die Datei erneut.');
        end;
        if not TDAIOTA.ReplaceEditorText(LSourceEditor, LWrittenContent, LActualContent) then
          raise EInvalidOperation.Create('Der Editorpuffer konnte nicht ersetzt werden.');
        LWrittenContent := LActualContent;
        if ASave then
        begin
          if not Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
            raise EInvalidOperation.Create('Der Editorpuffer wurde geändert; IOTAActionServices zum Speichern ist nicht verfügbar.');
          if not LActionServices.SaveFile(LFileName) then
            raise EInvalidOperation.Create('Der Editorpuffer wurde geändert, konnte aber nicht gespeichert werden.');
          LWrittenContent := TDAIOTA.ReadEditorText(LSourceEditor);
        end;
        LFormat.LineEndingKind := TDAITextEncoding.DetectLineEnding(LWrittenContent);
      end);
  end
  else
  begin
    if SameText(TPath.GetExtension(LFileName), '.dfm') or SameText(TPath.GetExtension(LFileName), '.fmx') then
      raise EInvalidOperation.Create('Der native IDE-Textmodus für dieses Formular ist nicht verfügbar. ' +
        'Formulardateien werden ausschließlich über einen verfügbaren IDE-Textpuffer geändert.');
    if not ASave then
      raise EInvalidOperation.Create('save=false erfordert einen geöffneten IDE-Textpuffer. Öffnen Sie die Datei zuerst mit file_open.');
    if TDAIOTA.IsFormLoadedForFile(LFileName) then
      raise EInvalidOperation.Create('Das Formular ist im Designer geladen. Wechseln Sie zuerst mit form_show_as_text in den Textmodus.');

    LBytes := TDAITextEncoding.PrepareWrite(LFileName, AContent, LWrittenContent, LFormat);
    if Length(LBytes) > CDAIMaxTextFileBytes then
      raise EInvalidOperation.CreateFmt('Der neue Inhalt überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);
    ForceDirectories(TPath.GetDirectoryName(LFileName));
    TFile.WriteAllBytes(LFileName, LBytes);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('target', IfThen(AUsedEditorBuffer, 'editor_buffer', 'disk'));
  Result.AddPair('saved', TJSONBool.Create((not AUsedEditorBuffer) or ASave));
  Result.AddPair('encoding', TDAITextEncoding.EncodingName(LFormat.EncodingKind));
  Result.AddPair('original_encoding', LOriginalEncoding);
  Result.AddPair('line_ending', TDAITextEncoding.LineEndingName(LFormat.LineEndingKind));
  Result.AddPair('original_line_ending', LOriginalLineEnding);
  Result.AddPair('sha256', THashSHA2.GetHashString(LWrittenContent));
end;

end.
