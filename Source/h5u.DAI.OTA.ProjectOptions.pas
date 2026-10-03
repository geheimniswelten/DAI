unit h5u.DAI.OTA.ProjectOptions;

interface

uses
  System.JSON;

type
  TDAIProjectOptionsService = class sealed
  public
    class function Configurations(const AProject: string): TJSONObject; static;
    class function ReadOptions(const AProject, AConfiguration, APlatform: string; const ANames: TArray<string>; const AMaximumOptions: Integer): TJSONObject; static;
    class function SetOption(const AProject, AConfiguration, APlatform, AName, AValue, AMergeMode: string): TJSONObject; static;
    class function RemoveOption(const AProject, AConfiguration, APlatform, AName: string): TJSONObject; static;
    class function ActivateProject(const AProject: string): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Types;

const
  CMaximumConfigurations = 1000;
  CMaximumParentDepth = 128;
  CMaximumOptionNameLength = 256;
  CMaximumOptionValueLength = 65536;
  CMaximumRequestedOptions = 1000;
  CMaximumEnumeratedOptions = 10000;

type
  TConfigurationList = TList<IOTABuildConfiguration>;

function SameConfiguration(const ALeft, ARight: IOTABuildConfiguration): Boolean;
begin
  Result := ALeft = ARight;
  if not Result and Assigned(ALeft) and Assigned(ARight) then
    Result := (ALeft.Key <> '') and SameText(ALeft.Key, ARight.Key) and SameText(ALeft.Platform, ARight.Platform);
end;

function ConfigurationIndex(const AItems: TConfigurationList; const AItem: IOTABuildConfiguration): Integer;
var
  LIndex: Integer;
begin
  for LIndex := 0 to AItems.Count - 1 do
    if SameConfiguration(AItems[LIndex], AItem) then
      Exit(LIndex);
  Result := -1;
end;

function ParentChain(const AConfiguration: IOTABuildConfiguration): TConfigurationList;
var
  LCurrent: IOTABuildConfiguration;
begin
  Result := TConfigurationList.Create;
  try
    LCurrent := AConfiguration;
    while Assigned(LCurrent) do
    begin
      if ConfigurationIndex(Result, LCurrent) >= 0 then
        raise EInvalidOperation.Create('Die ToolsAPI meldet eine zyklische Konfigurationsvererbung.');
      if Result.Count >= CMaximumParentDepth then
        raise EInvalidOperation.Create('Die Konfigurationsvererbung überschreitet das Limit von 128 Ebenen.');
      Result.Add(LCurrent);
      LCurrent := LCurrent.Parent;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure AddScopeCandidate(const AItems: TConfigurationList; const AConfiguration: IOTABuildConfiguration);
var
  LChain: TConfigurationList;
begin
  if not Assigned(AConfiguration) or (ConfigurationIndex(AItems, AConfiguration) >= 0) then
    Exit;
  if AItems.Count >= CMaximumConfigurations then
    raise EInvalidOperation.Create('Die relevanten Konfigurationsbereiche überschreiten das Prüflimit von 1000 Knoten.');
  LChain := ParentChain(AConfiguration);
  try
    AItems.Add(AConfiguration);
  finally
    LChain.Free;
  end;
end;

function RelevantScopes(const AConfiguration: IOTABuildConfiguration): TConfigurationList;
var
  LChain: TConfigurationList;
  LCurrent, LCompanion: IOTABuildConfiguration;
  LPlatform: string;
begin
  LChain := ParentChain(AConfiguration);
  try
    Result := TConfigurationList.Create;
    try
      for LCurrent in LChain do
      begin
        // The SDK can evaluate platform ancestors that its logical Parent property does not enumerate.
        // The companions are candidates; this enumeration does not prove their effective precedence.
        if (AConfiguration.Platform <> '') and (LCurrent.Platform = '') then
          for LPlatform in LCurrent.Platforms do
            if SameText(LPlatform, AConfiguration.Platform) then
            begin
              LCompanion := LCurrent.PlatformConfiguration[LPlatform];
              if Assigned(LCompanion) then
                if SameText(LCompanion.Platform, AConfiguration.Platform) then
                  AddScopeCandidate(Result, LCompanion);
              Break;
            end;
        AddScopeCandidate(Result, LCurrent);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    LChain.Free;
  end;
end;

function ConfigurationIdentity(const AConfiguration: IOTABuildConfiguration): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('key', AConfiguration.Key);
    Result.AddPair('name', AConfiguration.Name);
    Result.AddPair('platform', AConfiguration.Platform);
  except
    Result.Free;
    raise;
  end;
end;

function ConfigurationJson(const AConfiguration: IOTABuildConfiguration): TJSONValue;
var
  LObject: TJSONObject;
  LParent: IOTABuildConfiguration;
begin
  if not Assigned(AConfiguration) then
    Exit(TJSONNull.Create);
  LObject := ConfigurationIdentity(AConfiguration);
  try
    LParent := AConfiguration.Parent;
    if Assigned(LParent) then
      LObject.AddPair('parent', ConfigurationIdentity(LParent))
    else
      LObject.AddPair('parent', TJSONNull.Create);
    Result := LObject;
  except
    LObject.Free;
    raise;
  end;
end;

function ProjectMatches(const AProject: IOTAProject; const AQuery: string): Boolean;
var
  LFileName: string;
begin
  LFileName := TDAIOTA.ProjectFileName(AProject);
  if TPath.IsPathRooted(AQuery) then
    Result := TDAIOTA.SameFile(LFileName, AQuery) or
      TDAIOTA.SameFile(ChangeFileExt(LFileName, ''), ChangeFileExt(AQuery, ''))
  else
    Result := SameText(TPath.GetFileName(LFileName), AQuery) or SameText(TPath.GetFileNameWithoutExtension(LFileName), AQuery);
end;

function FindGroupProject(const AGroup: IOTAProjectGroup; const AQuery: string): IOTAProject;
var
  LIndex: Integer;
  LProject: IOTAProject;
begin
  Result := nil;
  if not Assigned(AGroup) then
    Exit;
  if AGroup.ProjectCount > CMaximumConfigurations then
    raise EInvalidOperation.Create('Die Projektgruppe überschreitet das Prüflimit von 1000 Projekten.');
  for LIndex := 0 to AGroup.ProjectCount - 1 do
  begin
    LProject := AGroup.Projects[LIndex];
    if not Assigned(LProject) then
      Continue;
    if ProjectMatches(LProject, AQuery) then
    begin
      if Assigned(Result) then
        raise EArgumentException.Create('Der Projektname ist nicht eindeutig; bitte den vollständigen Projektpfad verwenden.');
      Result := LProject;
    end;
  end;
end;

function RequireActiveProject(const AQuery: string): IOTAProject;
var
  LRequested: IOTAProject;
begin
  Result := TDAIOTA.ActiveProject;
  if not Assigned(Result) then
    raise EInvalidOperation.Create('In der Delphi-IDE ist kein Projekt aktiv.');
  if Trim(AQuery) = '' then
    Exit;
  LRequested := FindGroupProject(TDAIOTA.MainProjectGroup, Trim(AQuery));
  if not Assigned(LRequested) then
  begin
    if ProjectMatches(Result, Trim(AQuery)) then
      Exit;
    raise EArgumentException.Create('Das angegebene Projekt ist nicht in der aktiven Projektgruppe geöffnet.');
  end;
  if not TDAIOTA.SameFile(TDAIOTA.ProjectFileName(Result), TDAIOTA.ProjectFileName(LRequested)) then
    raise EInvalidOperation.Create('Projektoptionen stehen nur für das aktive Projekt bereit. Zuerst project_activate für dieses Projekt aufrufen.');
end;

function ConfigurationServices(const AProject: IOTAProject): IOTAProjectOptionsConfigurations;
begin
  if not Assigned(AProject.ProjectOptions) or
    not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, Result) then
    raise EInvalidOperation.Create('Dieses aktive Projekt bietet keine Build-Konfigurationen über die ToolsAPI an.');
end;

procedure AddConfiguration(const AItems: TConfigurationList; const AConfiguration: IOTABuildConfiguration);
var
  LChain: TConfigurationList;
begin
  if not Assigned(AConfiguration) or (ConfigurationIndex(AItems, AConfiguration) >= 0) then
    Exit;
  if AItems.Count >= CMaximumConfigurations then
    raise EInvalidOperation.Create('Die ToolsAPI-Konfigurationen überschreiten das Prüflimit von 1000 Knoten.');
  LChain := ParentChain(AConfiguration);
  try
    AItems.Add(AConfiguration);
  finally
    LChain.Free;
  end;
end;

function AllConfigurations(const AServices: IOTAProjectOptionsConfigurations): TConfigurationList;
var
  LIndex, LChildIndex: Integer;
  LConfiguration: IOTABuildConfiguration;
  LPlatform: string;
begin
  Result := TConfigurationList.Create;
  try
    AddConfiguration(Result, AServices.BaseConfiguration);
    if AServices.ConfigurationCount > CMaximumConfigurations then
      raise EInvalidOperation.Create('Die ToolsAPI-Konfigurationen überschreiten das Prüflimit von 1000 Knoten.');
    for LIndex := 0 to AServices.ConfigurationCount - 1 do
      AddConfiguration(Result, AServices.Configurations[LIndex]);
    AddConfiguration(Result, AServices.ActiveConfiguration);
    LIndex := 0;
    while LIndex < Result.Count do
    begin
      LConfiguration := Result[LIndex];
      if LConfiguration.ChildCount > CMaximumConfigurations then
        raise EInvalidOperation.Create('Die ToolsAPI-Konfiguration enthält mehr als 1000 direkte Nachfahren.');
      for LChildIndex := 0 to LConfiguration.ChildCount - 1 do
        AddConfiguration(Result, LConfiguration.Children[LChildIndex]);
      // Platforms is the SDK's own enumeration. Do not manufacture nodes from project-wide supported platforms.
      if LConfiguration.Platform = '' then
        for LPlatform in LConfiguration.Platforms do
          if LPlatform <> '' then
            AddConfiguration(Result, LConfiguration.PlatformConfiguration[LPlatform]);
      AddConfiguration(Result, LConfiguration.Parent);
      Inc(LIndex);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function FindConfiguration(const AItems: TConfigurationList; const AQuery: string): IOTABuildConfiguration;
var
  LConfiguration: IOTABuildConfiguration;
begin
  Result := nil;
  // SDK keys are the stable identity. Do not reconstruct or split them.
  for LConfiguration in AItems do
    if SameText(LConfiguration.Key, AQuery) then
    begin
      if Assigned(Result) and not SameConfiguration(Result, LConfiguration) then
        raise EArgumentException.Create('Der Konfigurationsschlüssel ist nicht eindeutig.');
      Result := LConfiguration;
    end;
  if Assigned(Result) then
    Exit;
  // A named configuration means its platform-neutral node, not similarly named platform children.
  for LConfiguration in AItems do
    if (LConfiguration.Platform = '') and SameText(LConfiguration.Name, AQuery) then
    begin
      if Assigned(Result) then
        raise EArgumentException.Create('Der Konfigurationsname ist nicht eindeutig; bitte den SDK-Schlüssel verwenden.');
      Result := LConfiguration;
    end;
end;

function ResolveConfiguration(const AProject: IOTAProject; const AConfiguration, APlatform: string; const AForWriting: Boolean): IOTABuildConfiguration;
var
  LConfigurationQuery, LPlatform, LSupportedPlatform: string;
  LConfigurations, LChain: TConfigurationList;
  LIndex: Integer;
  LServices: IOTAProjectOptionsConfigurations;
  LActive, LPlatformConfiguration: IOTABuildConfiguration;
  LIsActive, LPlatformSupported: Boolean;
begin
  LConfigurationQuery := Trim(AConfiguration);
  LIsActive := (LConfigurationQuery = '') or SameText(LConfigurationQuery, 'active');
  if AForWriting and LIsActive then
    raise EArgumentException.Create('Zum Ändern muss configuration ausdrücklich einen Konfigurationsnamen oder SDK-Schlüssel nennen.');
  if AForWriting and SameText(Trim(APlatform), 'active') then
    raise EArgumentException.Create('Zum Ändern muss platform ausdrücklich angegeben werden; leer bedeutet alle Plattformen.');
  LServices := ConfigurationServices(AProject);
  LConfigurations := AllConfigurations(LServices);
  try
    if LIsActive then
      Result := LServices.ActiveConfiguration
    else if SameText(LConfigurationQuery, 'Base') then
      Result := LServices.BaseConfiguration
    else
      Result := FindConfiguration(LConfigurations, LConfigurationQuery);
    if not Assigned(Result) then
      raise EArgumentException.Create('Die gewünschte Build-Konfiguration ist in diesem Projekt nicht vorhanden.');
    LPlatform := Trim(APlatform);
    if SameText(LPlatform, 'active') then
      LPlatform := AProject.CurrentPlatform;
    if (LPlatform = '') and (Result.Platform <> '') then
    begin
      if not LIsActive then
        raise EArgumentException.Create('Der SDK-Schlüssel bezeichnet einen Plattformknoten; platform muss diese Plattform ausdrücklich nennen.');
      LActive := Result;
      Result := FindConfiguration(LConfigurations, AProject.CurrentConfiguration);
      if Assigned(Result) then
        if Result.Platform <> '' then
          Result := nil;
      if not Assigned(Result) then
      begin
        Result := nil;
        LChain := ParentChain(LActive);
        try
          for LIndex := 1 to LChain.Count - 1 do
            if LChain[LIndex].Platform = '' then
            begin
              Result := LChain[LIndex];
              Break;
            end;
        finally
          LChain.Free;
        end;
      end;
      if not Assigned(Result) then
        raise EInvalidOperation.Create('Die aktive Konfiguration besitzt keinen zugänglichen plattformneutralen Vorfahren.');
    end;
    if LPlatform = '' then
      Exit;
    LPlatformSupported := False;
    for LSupportedPlatform in AProject.SupportedPlatforms do
      if SameText(LSupportedPlatform, LPlatform) then
      begin
        LPlatform := LSupportedPlatform;
        LPlatformSupported := True;
        Break;
      end;
    if not LPlatformSupported then
      raise EArgumentException.Create('Die gewünschte Plattform wird von diesem Projekt nicht unterstützt.');
    if Result.Platform <> '' then
    begin
      if not SameText(Result.Platform, LPlatform) then
        raise EArgumentException.Create('Der SDK-Schlüssel und die gewünschte Plattform bezeichnen unterschiedliche Plattformen.');
      Exit;
    end;
    LPlatformConfiguration := Result.PlatformConfiguration[LPlatform];
    if not Assigned(LPlatformConfiguration) then
      raise EInvalidOperation.Create('Die ToolsAPI bietet für diese Konfiguration keinen passenden Plattformknoten.');
    if not SameText(LPlatformConfiguration.Platform, LPlatform) then
      raise EInvalidOperation.Create('Die ToolsAPI bietet für diese Konfiguration keinen passenden Plattformknoten.');
    Result := LPlatformConfiguration;
    LChain := ParentChain(Result);
    LChain.Free;
  finally
    LConfigurations.Free;
  end;
end;

procedure ValidateOptionName(const AName: string);
var
  LIndex: Integer;
  LCharacter: Char;
begin
  if (Length(AName) = 0) or (Length(AName) > CMaximumOptionNameLength) then
    raise EArgumentException.Create('Der Optionsname muss 1 bis 256 Zeichen lang sein.');
  for LIndex := 1 to Length(AName) do
  begin
    LCharacter := AName[LIndex];
    if not CharInSet(LCharacter, ['A'..'Z', 'a'..'z', '_']) and
      not ((LIndex > 1) and CharInSet(LCharacter, ['0'..'9'])) then
      raise EArgumentException.Create('Der Optionsname muss ein MSBuild-Bezeichner aus Buchstaben, Ziffern und Unterstrichen sein.');
  end;
end;

function IsKnownNativeListOption(const AName: string): Boolean;
var
  LName: string;
begin
  // There is no public OTA list-type query. These nine native list options were verified in the Delphi 13 Win32 IDE.
  // SetMerged(False) materializes their explicit empty override; older IDEs still need native verification.
  for LName in ['DCC_Define', 'DCC_UnitSearchPath', 'DCC_Namespace', 'DCC_IncludePath', 'DCC_ResourcePath',
    'DCC_ObjPath', 'DCC_UnitAlias', 'DCC_UsePackage', 'DCC_LibraryPath'] do
    if SameText(LName, AName) then
      Exit(True);
  Result := False;
end;

function OptionJson(const AConfiguration: IOTABuildConfiguration; const AName: string): TJSONObject;
var
  LChain, LParents: TConfigurationList;
  LIndex, LExplicitCount: Integer;
  LHasLocal, LHasPlatformCandidate, LAmbiguous: Boolean;
  LOrigin: IOTABuildConfiguration;
  LSource: TJSONObject;
  LSources: TJSONArray;
begin
  LParents := ParentChain(AConfiguration);
  try
    LChain := RelevantScopes(AConfiguration);
    try
      Result := TJSONObject.Create;
      try
        LHasLocal := AConfiguration.PropertyExists(AName);
        LOrigin := nil;
        LExplicitCount := 0;
        LHasPlatformCandidate := False;
        for LIndex := 0 to LChain.Count - 1 do
          if LChain[LIndex].PropertyExists(AName) then
          begin
            Inc(LExplicitCount);
            if not Assigned(LOrigin) then
              LOrigin := LChain[LIndex];
            if ConfigurationIndex(LParents, LChain[LIndex]) < 0 then
              LHasPlatformCandidate := True;
          end;
        LAmbiguous := not LHasLocal and (LExplicitCount > 1) and LHasPlatformCandidate;
        Result.AddPair('name', AName);
        Result.AddPair('effective_value', AConfiguration.GetValue(AName, True));
        Result.AddPair('has_local_value', TJSONBool.Create(LHasLocal));
        if LHasLocal then
          Result.AddPair('local_value', AConfiguration.GetValue(AName, False))
        else
          Result.AddPair('local_value', TJSONNull.Create);
        if LHasLocal then
          Result.AddPair('origin', 'local')
        else if Assigned(LOrigin) then
          Result.AddPair('origin', 'inherited')
        else
          Result.AddPair('origin', 'default_or_unset');
        if LAmbiguous then
        begin
          Result.AddPair('origin_configuration', TJSONNull.Create);
          Result.AddPair('source_resolution', 'unknown');
          Result.AddPair('source_resolution_reason', 'platform_resolution_ambiguous');
        end
        else
        begin
          Result.AddPair('origin_configuration', ConfigurationJson(LOrigin));
          if LHasLocal then
            Result.AddPair('source_resolution', 'local')
          else if LExplicitCount = 1 then
            Result.AddPair('source_resolution', 'single_explicit_source')
          else if LExplicitCount > 1 then
            Result.AddPair('source_resolution', 'direct_parent_chain')
          else
            Result.AddPair('source_resolution', 'default_or_unset');
        end;
        Result.AddPair('provenance_scope', 'sdk_parent_and_platform_candidates');
        Result.AddPair('merged', TJSONBool.Create(AConfiguration.GetMerged(AName)));
        Result.AddPair('inherited_value', AConfiguration.InheritedValue(AName));
        LSources := TJSONArray.Create;
        Result.AddPair('sources', LSources);
        for LIndex := 0 to LChain.Count - 1 do
          if not SameConfiguration(LChain[LIndex], AConfiguration) and LChain[LIndex].PropertyExists(AName) then
          begin
            LSource := TJSONObject.Create;
            LSources.AddElement(LSource);
            LSource.AddPair('configuration', ConfigurationJson(LChain[LIndex]));
            LSource.AddPair('value', LChain[LIndex].GetValue(AName, False));
            LSource.AddPair('merged', TJSONBool.Create(LChain[LIndex].GetMerged(AName)));
            if ConfigurationIndex(LParents, LChain[LIndex]) >= 0 then
              LSource.AddPair('scope', 'direct_parent')
            else
              LSource.AddPair('scope', 'platform_candidate');
          end;
      except
        Result.Free;
        raise;
      end;
    finally
      LChain.Free;
    end;
  finally
    LParents.Free;
  end;
end;

procedure RequireWritablePath(const AFileName: string);
begin
  if Trim(AFileName) = '' then
    Exit;
  TDAIOTA.RequireNoReparseWritePath(AFileName);
  if TDAIOTA.IsReadOnlyReferenceFile(AFileName) then
    raise EDAIAccessDenied.CreateFmt('Referenzverzeichnisse sind schreibgeschützt. Projektoptionen dürfen diese Datei nicht ändern: %s', [AFileName]);
end;

procedure RequireWritableProject(const AProject: IOTAProject);
var
  LFileName, LExtension, LProjectFile: string;
begin
  LFileName := AProject.FileName;
  RequireWritablePath(LFileName);
  LProjectFile := TDAIOTA.ProjectFileName(AProject);
  RequireWritablePath(LProjectFile);
  LExtension := TPath.GetExtension(LProjectFile);
  if SameText(LExtension, '.dpr') or SameText(LExtension, '.dpk') then
    LProjectFile := ChangeFileExt(LProjectFile, '.dproj');
  RequireWritablePath(LProjectFile);
  if LProjectFile <> '' then
    RequireWritablePath(LProjectFile + '.local');
end;

procedure MarkProjectModified(const AProject: IOTAProject);
begin
  AProject.ProjectOptions.ModifiedState := True;
  AProject.MarkModified;
end;

function ChangeResult(const AProject: IOTAProject; const AConfiguration: IOTABuildConfiguration; const AName: string; const APrevious: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('previous', APrevious);
    Result.AddPair('project', TDAIOTA.ProjectFileName(AProject));
    Result.AddPair('configuration', ConfigurationJson(AConfiguration));
    Result.AddPair('option', OptionJson(AConfiguration, AName));
    Result.AddPair('modified', TJSONBool.Create(AProject.ProjectOptions.ModifiedState));
    Result.AddPair('saved', TJSONBool.Create(False));
    Result.AddPair('value_semantics', 'toolsapi_evaluated');
  except
    Result.Free;
    raise;
  end;
end;

class function TDAIProjectOptionsService.Configurations(const AProject: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LProject: IOTAProject;
      LServices: IOTAProjectOptionsConfigurations;
      LItems: TConfigurationList;
      LConfiguration: IOTABuildConfiguration;
      LConfigurations, LPlatforms: TJSONArray;
      LPlatform: string;
    begin
      LProject := RequireActiveProject(AProject);
      LServices := ConfigurationServices(LProject);
      LItems := AllConfigurations(LServices);
      try
        LResult := TJSONObject.Create;
        try
          LResult.AddPair('project', TDAIOTA.ProjectFileName(LProject));
          LResult.AddPair('active_configuration', ConfigurationJson(LServices.ActiveConfiguration));
          LResult.AddPair('active_platform', LProject.CurrentPlatform);
          LConfigurations := TJSONArray.Create;
          LResult.AddPair('configurations', LConfigurations);
          for LConfiguration in LItems do
            LConfigurations.AddElement(ConfigurationJson(LConfiguration));
          LPlatforms := TJSONArray.Create;
          LResult.AddPair('platforms', LPlatforms);
          for LPlatform in LProject.SupportedPlatforms do
            LPlatforms.Add(LPlatform);
        except
          FreeAndNil(LResult);
          raise;
        end;
      finally
        LItems.Free;
      end;
    end);
  Result := LResult;
end;

class function TDAIProjectOptionsService.ReadOptions(const AProject, AConfiguration, APlatform: string; const ANames: TArray<string>; const AMaximumOptions: Integer): TJSONObject;
var
  LResult: TJSONObject;
begin
  if Length(ANames) > CMaximumRequestedOptions then
    raise EArgumentException.Create('Pro Aufruf dürfen höchstens 1000 Optionsnamen angefordert werden.');
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LProject: IOTAProject;
      LConfiguration, LAncestor: IOTABuildConfiguration;
      LChain: TConfigurationList;
      LNames: TStringList;
      LName: string;
      LIndex, LLimit: Integer;
      LOptions: TJSONArray;
    begin
      LProject := RequireActiveProject(AProject);
      LConfiguration := ResolveConfiguration(LProject, AConfiguration, APlatform, False);
      LNames := TStringList.Create;
      try
        LNames.Sorted := True;
        LNames.CaseSensitive := False;
        LNames.Duplicates := dupIgnore;
        if Length(ANames) <> 0 then
          for LName in ANames do
          begin
            ValidateOptionName(LName);
            LNames.Add(LName);
          end
        else
        begin
          LChain := RelevantScopes(LConfiguration);
          try
            for LAncestor in LChain do
            begin
              if LAncestor.PropertyCount > CMaximumEnumeratedOptions then
                raise EInvalidOperation.Create('Die ToolsAPI-Konfiguration enthält mehr als 10000 explizite Eigenschaften.');
              for LIndex := 0 to LAncestor.PropertyCount - 1 do
              begin
                LNames.Add(LAncestor.Properties[LIndex]);
                if LNames.Count > CMaximumEnumeratedOptions then
                  raise EInvalidOperation.Create('Die expliziten Projektoptionen überschreiten das Prüflimit von 10000 Eigenschaften.');
              end;
            end;
          finally
            LChain.Free;
          end;
        end;
        LLimit := EnsureRange(AMaximumOptions, 1, CMaximumRequestedOptions);
        LResult := TJSONObject.Create;
        try
          LResult.AddPair('project', TDAIOTA.ProjectFileName(LProject));
          LResult.AddPair('configuration', ConfigurationJson(LConfiguration));
          LOptions := TJSONArray.Create;
          LResult.AddPair('options', LOptions);
          for LIndex := 0 to Min(LNames.Count, LLimit) - 1 do
            LOptions.AddElement(OptionJson(LConfiguration, LNames[LIndex]));
          LResult.AddPair('option_count', TJSONNumber.Create(LNames.Count));
          LResult.AddPair('truncated', TJSONBool.Create(LNames.Count > LLimit));
          LResult.AddPair('value_semantics', 'toolsapi_evaluated');
          LResult.AddPair('enumeration_scope', 'explicit_properties_in_parent_and_platform_scopes');
        except
          FreeAndNil(LResult);
          raise;
        end;
      finally
        LNames.Free;
      end;
    end);
  Result := LResult;
end;

class function TDAIProjectOptionsService.SetOption(const AProject, AConfiguration, APlatform, AName, AValue, AMergeMode: string): TJSONObject;
var
  LResult: TJSONObject;
  LMergeMode: string;
begin
  ValidateOptionName(AName);
  if Length(AValue) > CMaximumOptionValueLength then
    raise EArgumentException.Create('Der Optionswert darf höchstens 65536 Zeichen enthalten.');
  LMergeMode := LowerCase(Trim(AMergeMode));
  if LMergeMode = '' then
    LMergeMode := 'preserve';
  if (LMergeMode <> 'preserve') and (LMergeMode <> 'merge') and (LMergeMode <> 'replace') then
    raise EArgumentException.Create('merge_mode muss preserve, merge oder replace sein.');
  if AValue = '' then
  begin
    if LMergeMode <> 'replace' then
      raise EArgumentException.Create('Ein eigener leerer Listenwert erfordert merge_mode=replace. Zum Entfernen der Option project_option_remove verwenden.');
    if not IsKnownNativeListOption(AName) then
      raise EArgumentException.Create('Leere eigene Werte sind über die ToolsAPI nur für bekannte native Delphi-Listenoptionen sicher setzbar.');
  end;
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LProject: IOTAProject;
      LConfiguration: IOTABuildConfiguration;
      LPrevious: TJSONObject;
      LMerged, LMergeModeApplied: Boolean;
    begin
      LProject := RequireActiveProject(AProject);
      RequireWritableProject(LProject);
      LConfiguration := ResolveConfiguration(LProject, AConfiguration, APlatform, True);
      LPrevious := OptionJson(LConfiguration, AName);
      try
        LMerged := LConfiguration.GetMerged(AName);
        if LMergeMode = 'merge' then
          LMerged := True
        else if LMergeMode = 'replace' then
          LMerged := False;
        LConfiguration.SetValue(AName, AValue);
        // SetValue('') can remove the property. For native lists SetMerged(False) creates an explicit empty override.
        if (AValue = '') or (LConfiguration.GetMerged(AName) <> LMerged) then
          LConfiguration.SetMerged(AName, LMerged);
        MarkProjectModified(LProject);
        LMergeModeApplied := LConfiguration.GetMerged(AName) = LMerged;
        if AValue = '' then
          if not LConfiguration.PropertyExists(AName) or not LMergeModeApplied then
            raise EInvalidOperation.Create('Die ToolsAPI hat keinen eigenen leeren Listenwert behalten. Der aktuelle Optionszustand muss erneut ausgelesen werden.');
      except
        LPrevious.Free;
        raise;
      end;
      LResult := ChangeResult(LProject, LConfiguration, AName, LPrevious);
      LResult.AddPair('changed', TJSONBool.Create(True));
      LResult.AddPair('merge_mode', LMergeMode);
      LResult.AddPair('merge_mode_applied', TJSONBool.Create(LMergeModeApplied));
    end);
  Result := LResult;
end;

class function TDAIProjectOptionsService.RemoveOption(const AProject, AConfiguration, APlatform, AName: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  ValidateOptionName(AName);
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LProject: IOTAProject;
      LConfiguration: IOTABuildConfiguration;
      LPrevious: TJSONObject;
      LRemoved: Boolean;
    begin
      LProject := RequireActiveProject(AProject);
      RequireWritableProject(LProject);
      LConfiguration := ResolveConfiguration(LProject, AConfiguration, APlatform, True);
      LPrevious := OptionJson(LConfiguration, AName);
      try
        LRemoved := LConfiguration.PropertyExists(AName);
        if LRemoved then
        begin
          LConfiguration.Remove(AName);
          if LConfiguration.PropertyExists(AName) then
            raise EInvalidOperation.Create('Die ToolsAPI hat die eigene Option nicht entfernt.');
          MarkProjectModified(LProject);
        end;
      except
        LPrevious.Free;
        raise;
      end;
      // Reading the effective result must not recreate the removed property or a merge marker.
      LResult := ChangeResult(LProject, LConfiguration, AName, LPrevious);
      LResult.AddPair('removed', TJSONBool.Create(LRemoved));
      LResult.AddPair('changed', TJSONBool.Create(LRemoved));
    end);
  Result := LResult;
end;

class function TDAIProjectOptionsService.ActivateProject(const AProject: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  if Trim(AProject) = '' then
    raise EArgumentException.Create('project_activate benötigt einen Projektnamen oder vollständigen Projektpfad.');
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LGroup: IOTAProjectGroup;
      LProject, LActive: IOTAProject;
      LPrevious: string;
    begin
      LGroup := TDAIOTA.MainProjectGroup;
      if not Assigned(LGroup) then
        raise EInvalidOperation.Create('Es ist keine Projektgruppe geöffnet; nur bereits geöffnete Gruppenprojekte können aktiviert werden.');
      LProject := FindGroupProject(LGroup, Trim(AProject));
      if not Assigned(LProject) then
        raise EArgumentException.Create('Das angegebene Projekt ist nicht in der aktiven Projektgruppe geöffnet.');
      LActive := LGroup.ActiveProject;
      LPrevious := '';
      if Assigned(LActive) then
        LPrevious := TDAIOTA.ProjectFileName(LActive);
      RequireWritablePath(LGroup.FileName);
      if LGroup.FileName <> '' then
        RequireWritablePath(LGroup.FileName + '.local');
      LGroup.ActiveProject := LProject;
      LActive := LGroup.ActiveProject;
      if not Assigned(LActive) then
        raise EInvalidOperation.Create('Die IDE hat das angeforderte Projekt nicht als aktives Gruppenprojekt übernommen.');
      if not TDAIOTA.SameFile(TDAIOTA.ProjectFileName(LActive), TDAIOTA.ProjectFileName(LProject)) then
        raise EInvalidOperation.Create('Die IDE hat das angeforderte Projekt nicht als aktives Gruppenprojekt übernommen.');
      LResult := TJSONObject.Create;
      try
        LResult.AddPair('project', TDAIOTA.ProjectFileName(LActive));
        LResult.AddPair('previous_project', LPrevious);
        LResult.AddPair('activated', TJSONBool.Create(True));
      except
        FreeAndNil(LResult);
        raise;
      end;
    end);
  Result := LResult;
end;

end.
