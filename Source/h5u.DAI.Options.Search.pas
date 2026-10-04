unit h5u.DAI.Options.Search;

interface

uses
  System.JSON;

type
  TDAIOptionsSearchService = class sealed
  public
    class function Search(const AQuery, AScope, AProject: string; const AMaximumResults: Integer): TJSONObject; static;
    class function OptionLabels(const AName: string): TArray<string>; static;
  end;

implementation

uses
  System.Character,
  System.Classes,
  System.Generics.Collections,
  System.Hash,
  System.IOUtils,
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  ToolsAPI,
  h5u.DAI.OTA.Helpers;

const
  CMaximumCatalogEntries = 10000;
  CMaximumQueryLength = 256;
  CMaximumCaptionLength = 4096;
  CMaximumDescriptionLength = 8192;

function NormalizeText(const AText: string): string;
begin
  Result := LowerCase(AText);
  Result := StringReplace(Result, 'ä', 'a', [rfReplaceAll]);
  Result := StringReplace(Result, 'ö', 'o', [rfReplaceAll]);
  Result := StringReplace(Result, 'ü', 'u', [rfReplaceAll]);
  Result := StringReplace(Result, 'ß', 'ss', [rfReplaceAll]);
  Result := StringReplace(Result, '&', '', [rfReplaceAll]);
end;

function QueryTokens(const AQuery: string): TArray<string>;
var
  LCharacter: Char;
  LToken, LNormalized: string;
  LTokens: TList<string>;
begin
  LTokens := TList<string>.Create;
  try
    LNormalized := NormalizeText(AQuery);
    LToken := '';
    for LCharacter in LNormalized do
      if LCharacter.IsLetterOrDigit or (LCharacter = '_') then
        LToken := LToken + LCharacter
      else if LToken <> '' then
      begin
        LTokens.Add(LToken);
        LToken := '';
      end;
    if LToken <> '' then
      LTokens.Add(LToken);
    Result := LTokens.ToArray;
  finally
    LTokens.Free;
  end;
end;

function TextMatches(const ATokens: TArray<string>; const AText: string): Boolean;
var
  LToken, LText: string;
begin
  LText := NormalizeText(AText);
  for LToken in ATokens do
    if not LText.Contains(LToken) then
      Exit(False);
  Result := True;
end;

function JsonLabels(const ALabels: TArray<string>): TJSONArray;
var
  LLabel: string;
begin
  Result := TJSONArray.Create;
  for LLabel in ALabels do
    Result.Add(LLabel);
end;

function OptionType(const AKind: TTypeKind): string;
begin
  if (Ord(AKind) < Ord(Low(TTypeKind))) or (Ord(AKind) > Ord(High(TTypeKind))) then
    Exit('unknown');
  Result := GetEnumName(TypeInfo(TTypeKind), Ord(AKind));
end;

procedure AddMatchingEntry(const AEntry: TJSONObject; const ASearchText: string; const ATokens: TArray<string>;
  const AResults: TJSONArray; const AMaximumResults: Integer; var AMatchedCount: Integer);
begin
  if TextMatches(ATokens, ASearchText) then
  begin
    Inc(AMatchedCount);
    if AResults.Count < AMaximumResults then
    begin
      AResults.AddElement(AEntry);
      Exit;
    end;
  end;
  AEntry.Free;
end;

function SourceStatus(const AScope: string; const ACached: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('scope', AScope);
  Result.AddPair('available', TJSONBool.Create(False));
  Result.AddPair('cached', TJSONBool.Create(ACached));
  Result.AddPair('complete', TJSONBool.Create(False));
end;

procedure MarkAvailable(const AStatus: TJSONObject);
begin
  AStatus.RemovePair('available').Free;
  AStatus.AddPair('available', TJSONBool.Create(True));
end;

procedure EnumerateOptions(const ANames: TOTAOptionNameArray; const AScope, AProject, AConfiguration, APlatform: string;
  const ATokens: TArray<string>; const AResults: TJSONArray; const AMaximumResults: Integer; var ACatalogCount, AMatchedCount: Integer;
  var ACatalogLimitReached: Boolean);
var
  LEntry: TJSONObject;
  LLabels: TArray<string>;
  LName: TOTAOptionName;
  LLabel, LSearchText: string;
  LScanned: Integer;
  LSeen: TDictionary<string, Boolean>;
begin
  LSeen := TDictionary<string, Boolean>.Create;
  try
    LScanned := 0;
    for LName in ANames do
    begin
      if LScanned >= CMaximumCatalogEntries then
      begin
        ACatalogLimitReached := True;
        Exit;
      end;
      Inc(LScanned);
      if (LName.Name = '') or (Length(LName.Name) > CMaximumQueryLength) or LName.Name.Contains(#0) then
        Continue;
      if LSeen.ContainsKey(LowerCase(LName.Name)) then
        Continue;
      LSeen.Add(LowerCase(LName.Name), True);
      if ACatalogCount >= CMaximumCatalogEntries then
      begin
        ACatalogLimitReached := True;
        Exit;
      end;
      Inc(ACatalogCount);
      LLabels := TDAIOptionsSearchService.OptionLabels(LName.Name);
      LSearchText := LName.Name;
      for LLabel in LLabels do
        LSearchText := LSearchText + ' ' + LLabel;
      LEntry := TJSONObject.Create;
      try
        LEntry.AddPair('id', AScope + ':' + LName.Name);
        LEntry.AddPair('name', LName.Name);
        LEntry.AddPair('scope', AScope);
        LEntry.AddPair('title', LLabels[0]);
        LEntry.AddPair('aliases', JsonLabels(LLabels));
        LEntry.AddPair('option_type', OptionType(LName.Kind));
        LEntry.AddPair('navigation_mode', 'dialog');
        LEntry.AddPair('focus_supported', TJSONNull.Create);
        if AScope = 'project' then
        begin
          LEntry.AddPair('project', AProject);
          LEntry.AddPair('configuration', AConfiguration);
          LEntry.AddPair('platform', APlatform);
        end;
      except
        LEntry.Free;
        raise;
      end;
      AddMatchingEntry(LEntry, LSearchText, ATokens, AResults, AMaximumResults, AMatchedCount);
    end;
  finally
    LSeen.Free;
  end;
end;

procedure EnumerateInsight(const AService: IOTAIDEInsightService; const ATokens: TArray<string>; const AResults: TJSONArray;
  const AMaximumResults: Integer; var ACatalogCount, AMatchedCount: Integer; var ACatalogLimitReached: Boolean);
var
  LCategory: IOTAIDEInsightCategory;
  LCategoryCount, LCategoryIndex, LItemCount, LItemIndex: Integer;
  LCategoryDisabled, LVisible, LOptionsCategory: Boolean;
  LCaption, LDescription, LTitle: string;
  LEntry: TJSONObject;
  LItem: INTAIDEInsightItem;
begin
  LCategoryCount := AService.CategoryCount;
  if LCategoryCount < 0 then
    raise EInvalidOperation.Create('IDE Insight meldet eine ungültige Kategorieanzahl.');
  if LCategoryCount > CMaximumCatalogEntries then
  begin
    LCategoryCount := CMaximumCatalogEntries;
    ACatalogLimitReached := True;
  end;
  for LCategoryIndex := 0 to LCategoryCount - 1 do
  begin
    LCategory := AService.GetCategory(Variant(LCategoryIndex));
    if not Assigned(LCategory) then
      Continue;
    LCaption := Copy(LCategory.Caption, 1, CMaximumCaptionLength);
    LCategoryDisabled := LCategory.Disabled;
    LOptionsCategory := SameText(LCaption, 'Preferences') or SameText(LCaption, 'Project Options') or
      SameText(LCaption, 'Einstellungen') or SameText(LCaption, 'Voreinstellungen') or SameText(LCaption, 'Projektoptionen');
    LItemCount := LCategory.ItemCount;
    if LItemCount < 0 then
      raise EInvalidOperation.Create('IDE Insight meldet eine ungültige Eintragsanzahl.');
    for LItemIndex := 0 to LItemCount - 1 do
    begin
      if ACatalogCount >= CMaximumCatalogEntries then
      begin
        ACatalogLimitReached := True;
        Exit;
      end;
      // This is the already cached SDK catalog, not the popup's current result list.
      // Reading it must never invoke providers, Update, Filter, Execute or the popup.
      LItem := LCategory.Items[LItemIndex];
      Inc(ACatalogCount);
      if not Assigned(LItem) then
        Continue;
      LTitle := Copy(LItem.Title, 1, CMaximumCaptionLength);
      LDescription := Copy(LItem.Description, 1, CMaximumDescriptionLength);
      LVisible := LItem.Visible;
      LEntry := TJSONObject.Create;
      try
        LEntry.AddPair('id', 'insight:' + THashSHA2.GetHashString(LCaption + #0 + LTitle + #0 + LDescription));
        LEntry.AddPair('name', LTitle);
        LEntry.AddPair('scope', 'insight');
        LEntry.AddPair('title', LTitle);
        LEntry.AddPair('description', LDescription);
        LEntry.AddPair('category', LCaption);
        LEntry.AddPair('visible', TJSONBool.Create(LVisible));
        LEntry.AddPair('category_disabled', TJSONBool.Create(LCategoryDisabled));
        LEntry.AddPair('cached', TJSONBool.Create(True));
        if LOptionsCategory and LVisible and not LCategoryDisabled then
        begin
          LEntry.AddPair('navigation_mode', 'insight_option');
          LEntry.AddPair('focus_supported', TJSONNull.Create);
        end
        else
        begin
          LEntry.AddPair('navigation_mode', TJSONNull.Create);
          LEntry.AddPair('focus_supported', TJSONBool.Create(False));
        end;
      except
        LEntry.Free;
        raise;
      end;
      AddMatchingEntry(LEntry, LCaption + ' ' + LTitle + ' ' + LDescription, ATokens, AResults, AMaximumResults, AMatchedCount);
    end;
  end;
end;

class function TDAIOptionsSearchService.OptionLabels(const AName: string): TArray<string>;
begin
  if AName = '' then
    Exit(nil);
  // Legacy keys are labels only; they are never fabricated as catalog entries.
  if SameText(AName, 'DCC_ExeOutput') or SameText(AName, 'OutputDir') or SameText(AName, 'FinalOutputDir') then
    Exit(TArray<string>.Create('Executable output directory', 'EXE-Ausgabeverzeichnis', 'Ausgabepfad EXE', AName));
  if SameText(AName, 'DCC_DcuOutput') or SameText(AName, 'DCUOutputDir') then
    Exit(TArray<string>.Create('Unit output directory', 'DCU-Ausgabeverzeichnis', 'Ausgabepfad DCU', AName));
  if SameText(AName, 'DCC_BplOutput') or SameText(AName, 'BplOutputDir') then
    Exit(TArray<string>.Create('Package output directory', 'BPL-Ausgabeverzeichnis', 'Ausgabepfad BPL', AName));
  if SameText(AName, 'DCC_DcpOutput') or SameText(AName, 'DcpOutputDir') then
    Exit(TArray<string>.Create('DCP output directory', 'DCP-Ausgabeverzeichnis', 'Ausgabepfad DCP', AName));
  if SameText(AName, 'DCC_UnitSearchPath') or SameText(AName, 'SearchPath') then
    Exit(TArray<string>.Create('Search path', 'Unit search path', 'Suchpfad', 'Unit-Suchpfad', AName));
  if SameText(AName, 'DCC_IncludePath') or SameText(AName, 'IncludePath') then
    Exit(TArray<string>.Create('Include file search path', 'Include-Pfad', 'Include-Suchpfad', AName));
  if SameText(AName, 'DCC_ResourcePath') or SameText(AName, 'ResourcePath') then
    Exit(TArray<string>.Create('Resource file search path', 'Ressourcenpfad', 'Ressourcen-Suchpfad', AName));
  if SameText(AName, 'DCC_Define') or SameText(AName, 'Conditionals') or SameText(AName, 'Defines') then
    Exit(TArray<string>.Create('Conditional defines', 'Conditional symbols', 'Bedingte Symbole', 'Compiler-Defines', AName));
  if SameText(AName, 'DCC_Namespace') or SameText(AName, 'Namespace') then
    Exit(TArray<string>.Create('Unit scope names', 'Namespaces', 'Unit-Bereichsnamen', AName));
  if SameText(AName, 'DCC_UnitAlias') or SameText(AName, 'UnitAliases') then
    Exit(TArray<string>.Create('Unit aliases', 'Unit-Aliase', AName));
  if SameText(AName, 'DCC_UsePackage') or SameText(AName, 'RuntimePackages') or SameText(AName, 'UsePackages') then
    Exit(TArray<string>.Create('Runtime packages', 'Laufzeit-Packages', 'Laufzeitpakete', AName));
  if SameText(AName, 'DCC_LibraryPath') or SameText(AName, 'LibraryPath') then
    Exit(TArray<string>.Create('Library path', 'Bibliothekspfad', 'Bibliotheks-Suchpfad', AName));
  Result := [AName];
end;

class function TDAIOptionsSearchService.Search(const AQuery, AScope, AProject: string; const AMaximumResults: Integer): TJSONObject;
var
  LQuery, LScope: string;
  LResult: TJSONObject;
  LTokens: TArray<string>;
begin
  if (Length(AQuery) > CMaximumQueryLength) or AQuery.Contains(#0) then
    raise EArgumentException.Create('query muss 1 bis 256 Zeichen ohne NUL enthalten.');
  LQuery := Trim(AQuery);
  if LQuery = '' then
    raise EArgumentException.Create('query muss 1 bis 256 Zeichen ohne NUL enthalten.');
  LTokens := QueryTokens(LQuery);
  if Length(LTokens) = 0 then
    raise EArgumentException.Create('query muss mindestens ein Suchwort enthalten.');
  LScope := LowerCase(Trim(AScope));
  if LScope = '' then
    LScope := 'all';
  if (LScope <> 'all') and (LScope <> 'ide') and (LScope <> 'project') and (LScope <> 'insight') then
    raise EArgumentException.Create('scope muss all, ide, project oder insight sein.');
  if (AMaximumResults < 1) or (AMaximumResults > 500) then
    raise EArgumentException.Create('maximum_results muss zwischen 1 und 500 liegen.');
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LCatalogCount, LMatchedCount: Integer;
      LCatalogLimitReached: Boolean;
      LConfiguration, LPlatform, LProjectFile: string;
      LEnvironment: IOTAEnvironmentOptions;
      LInsight: IOTAIDEInsightService;
      LProject: IOTAProject;
      LResults, LSources: TJSONArray;
      LServices: IOTAServices;
      LStatus: TJSONObject;
    begin
      LProject := nil;
      if (AProject <> '') or (LScope = 'all') or (LScope = 'project') then
      begin
        LProject := TDAIOTA.ProjectByNameOrPath(AProject);
        if (AProject <> '') and not Assigned(LProject) then
          raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');
      end;
      LResult := TJSONObject.Create;
      try
        LResults := TJSONArray.Create;
        LResult.AddPair('results', LResults);
        LSources := TJSONArray.Create;
        LResult.AddPair('sources', LSources);
        LResult.AddPair('query', LQuery);
        LResult.AddPair('scope', LScope);
        LResult.AddPair('complete', TJSONBool.Create(False));
        LCatalogCount := 0;
        LMatchedCount := 0;
        LCatalogLimitReached := False;
        if (LScope = 'all') or (LScope = 'ide') then
        begin
          LStatus := SourceStatus('ide', False);
          LSources.AddElement(LStatus);
          try
            if Supports(BorlandIDEServices, IOTAServices, LServices) then
            begin
              LEnvironment := LServices.GetEnvironmentOptions;
              if Assigned(LEnvironment) then
              begin
                EnumerateOptions(LEnvironment.GetOptionNames, 'ide', '', '', '', LTokens, LResults,
                  AMaximumResults, LCatalogCount, LMatchedCount, LCatalogLimitReached);
                MarkAvailable(LStatus);
              end;
            end;
          except
            on E: Exception do LStatus.AddPair('error', E.Message);
          end;
        end;
        if (LScope = 'all') or (LScope = 'project') then
        begin
          LStatus := SourceStatus('project', False);
          LSources.AddElement(LStatus);
          try
            if Assigned(LProject) then
              if Assigned(LProject.ProjectOptions) then
              begin
                LProjectFile := TDAIOTA.NormalizeFileName(LProject.FileName);
                LConfiguration := LProject.CurrentConfiguration;
                LPlatform := LProject.CurrentPlatform;
                EnumerateOptions(LProject.ProjectOptions.GetOptionNames, 'project', LProjectFile, LConfiguration, LPlatform,
                  LTokens, LResults, AMaximumResults, LCatalogCount, LMatchedCount, LCatalogLimitReached);
                MarkAvailable(LStatus);
              end;
          except
            on E: Exception do LStatus.AddPair('error', E.Message);
          end;
        end;
        if (LScope = 'all') or (LScope = 'insight') then
        begin
          LStatus := SourceStatus('insight', True);
          LSources.AddElement(LStatus);
          try
            if Supports(BorlandIDEServices, IOTAIDEInsightService, LInsight) then
            begin
              EnumerateInsight(LInsight, LTokens, LResults, AMaximumResults, LCatalogCount, LMatchedCount, LCatalogLimitReached);
              MarkAvailable(LStatus);
            end;
          except
            on E: Exception do LStatus.AddPair('error', E.Message);
          end;
        end;
        LResult.AddPair('catalog_count', TJSONNumber.Create(LCatalogCount));
        LResult.AddPair('matched_count', TJSONNumber.Create(LMatchedCount));
        LResult.AddPair('result_count', TJSONNumber.Create(LResults.Count));
        LResult.AddPair('catalog_limit_reached', TJSONBool.Create(LCatalogLimitReached));
        LResult.AddPair('truncated', TJSONBool.Create((LMatchedCount > LResults.Count) or LCatalogLimitReached));
      except
        FreeAndNil(LResult);
        raise;
      end;
    end);
  Result := LResult;
end;

end.
