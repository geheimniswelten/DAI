program TestProjectOptions;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  ToolsAPI,
  DAI.ProjectOptions.Fixture,
  h5u.DAI.OTA.ProjectOptions,
  h5u.DAI.OTA.Helpers;

var
  CheckCount: Integer;
  FixtureRoot: string;
  Configs: TArray<IOTABuildConfiguration>;
  Nodes: array[0..8] of TTestConfiguration;
  ProjectObject, OtherProjectObject: TTestProject;
  OptionsObject, OtherOptionsObject: TTestProjectOptions;
  GroupObject: TTestGroup;
  ProjectInterface, OtherProjectInterface: IOTAProject;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure Discard(AJson: TJSONObject);
begin
  AJson.Free;
end;

procedure ExpectRejected(const AProc: TProc; const ADescription: string);
var
  LRejected: Boolean;
begin
  LRejected := False;
  try
    AProc();
  except
    on E: Exception do
      LRejected := True;
  end;
  Check(LRejected, ADescription);
  Check(TDAIOTA.DispatchDepth = 0, 'exception releases IDE dispatcher scope');
end;

procedure ResetFixture;
const
  CKeys: array[0..8] of string = ('Base', 'Cfg_1', 'Cfg_2', 'Base_Win32', 'Base_Win64', 'Cfg_1_Win32', 'Cfg_1_Win64', 'Cfg_2_Win32', 'Cfg_2_Win64');
  CNames: array[0..8] of string = ('Base', 'Debug', 'Release', 'Base', 'Base', 'Debug', 'Debug', 'Release', 'Release');
var
  LIndex, LParent: Integer;
  LPlatform: string;
  LOtherBase, LOtherRelease: TTestConfiguration;
begin
  TDAIOTA.TestGroup := nil;
  ProjectInterface := nil;
  OtherProjectInterface := nil;
  Configs := nil;
  TDAIOTA.DeniedReferencePrefix := '';
  TDAIOTA.DeniedReparsePrefix := '';
  TDAIOTA.WritePreflightCount := 0;
  Check(TDAIOTA.DispatchDepth = 0, 'fixture begins outside IDE dispatcher');
  SetLength(Configs, Length(Nodes));
  for LIndex := 0 to High(Nodes) do
  begin
    LParent := 0;
    LPlatform := '';
    if LIndex >= 3 then
    begin
      LParent := (LIndex - 3) div 2;
      if Odd(LIndex) then
        LPlatform := 'Win32'
      else
        LPlatform := 'Win64';
    end;
    if LIndex = 0 then
      Nodes[LIndex] := TTestConfiguration.Create(CKeys[LIndex], CNames[LIndex], LPlatform, nil)
    else
      Nodes[LIndex] := TTestConfiguration.Create(CKeys[LIndex], CNames[LIndex], LPlatform, Nodes[LParent]);
    Configs[LIndex] := Nodes[LIndex];
  end;
  Nodes[0].ChildrenValue := [Nodes[1], Nodes[2], Nodes[3], Nodes[4]];
  Nodes[1].ChildrenValue := [Nodes[5], Nodes[6]];
  Nodes[2].ChildrenValue := [Nodes[7], Nodes[8]];
  for LIndex := 0 to 2 do
  begin
    Nodes[LIndex].LinkPlatform('Win32', Nodes[3 + LIndex * 2]);
    Nodes[LIndex].LinkPlatform('Win64', Nodes[4 + LIndex * 2]);
  end;
  Nodes[0].Define('DCC_Optimize', 'true');
  Nodes[0].Define('DCC_ExeOutput', 'basebin');
  Nodes[0].Define('DCC_UnitSearchPath', 'base');
  Nodes[0].Define('DCC_Define', 'BASE');
  Nodes[1].Define('DCC_Optimize', 'false');
  Nodes[1].Define('DCC_ExeOutput', '');
  Nodes[1].Define('DCC_UnitSearchPath', 'debug', True);
  Nodes[5].Define('DCC_Define', 'WIN32');
  OptionsObject := TTestProjectOptions.Create;
  OptionsObject.ConfigurationsValue := [Configs[1], Configs[2]];
  OptionsObject.BaseConfigurationValue := Configs[0];
  OptionsObject.ActiveConfigurationValue := Configs[5];
  OptionsObject.CurrentConfigurationValue := 'Debug';
  OptionsObject.CurrentPlatformValue := 'Win32';
  ProjectObject := TTestProject.Create;
  ProjectObject.OptionsValue := OptionsObject;
  ProjectObject.FileNameValue := TPath.Combine(FixtureRoot, 'Main.dpr');
  ProjectObject.ConfigurationValue := 'Debug';
  ProjectObject.PlatformValue := 'Win32';
  ProjectInterface := ProjectObject;
  OtherOptionsObject := TTestProjectOptions.Create;
  LOtherBase := TTestConfiguration.Create('Base', 'Base', '', nil);
  LOtherBase.Define('DCC_Optimize', 'true');
  LOtherRelease := TTestConfiguration.Create('Cfg_2', 'Release', '', LOtherBase);
  LOtherBase.ChildrenValue := [LOtherRelease];
  OtherOptionsObject.ConfigurationsValue := [LOtherBase, LOtherRelease];
  OtherOptionsObject.BaseConfigurationValue := LOtherBase;
  OtherOptionsObject.ActiveConfigurationValue := LOtherRelease;
  OtherOptionsObject.CurrentConfigurationValue := 'Release';
  OtherOptionsObject.CurrentPlatformValue := 'Win64';
  OtherProjectObject := TTestProject.Create;
  OtherProjectObject.OptionsValue := OtherOptionsObject;
  OtherProjectObject.FileNameValue := TPath.Combine(FixtureRoot, 'Other.dpr');
  OtherProjectObject.ConfigurationValue := 'Release';
  OtherProjectObject.PlatformValue := 'Win64';
  OtherProjectInterface := OtherProjectObject;
  GroupObject := TTestGroup.Create;
  GroupObject.FileNameValue := TPath.Combine(FixtureRoot, 'Fixture.groupproj');
  GroupObject.ProjectsValue := [ProjectInterface, OtherProjectInterface];
  GroupObject.ActiveProjectValue := ProjectInterface;
  TDAIOTA.TestGroup := GroupObject;
end;

function FirstOption(AJson: TJSONObject): TJSONObject;
begin
  Check(AJson.GetValue<TJSONArray>('options').Count = 1, 'named read returns exactly one requested property');
  Result := AJson.GetValue<TJSONArray>('options').Items[0] as TJSONObject;
end;

procedure ReadCheck(const AConfiguration, APlatform, AName, AValue, AOrigin, AOriginKey: string; const AHasLocal: Boolean);
var
  LJson, LOption, LOrigin: TJSONObject;
begin
  LJson := TDAIProjectOptionsService.ReadOptions('', AConfiguration, APlatform, [AName], 50);
  try
    LOption := FirstOption(LJson);
    Check(LOption.GetValue<string>('name') = AName, 'property name is preserved');
    Check(LOption.GetValue<string>('effective_value') = AValue, 'effective value: ' + AName + '/' + AConfiguration + '/' + APlatform);
    Check(LOption.GetValue<Boolean>('has_local_value') = AHasLocal, 'local membership distinguishes empty values from missing properties');
    Check(LOption.GetValue<string>('origin') = AOrigin, 'origin is explicit');
    if AHasLocal then
      Check(LOption.GetValue('local_value') is TJSONString, 'local empty or nonempty value is represented as a string')
    else
      Check(LOption.GetValue('local_value') is TJSONNull, 'missing local value is represented as JSON null');
    if AOriginKey = '' then
      Check(LOption.GetValue('origin_configuration') is TJSONNull, 'unset default has no invented origin configuration')
    else
    begin
      LOrigin := LOption.GetValue<TJSONObject>('origin_configuration');
      Check(LOrigin.GetValue<string>('key') = AOriginKey, 'origin configuration key is identified');
    end;
  finally
    LJson.Free;
  end;
end;

procedure ReadCases;
var
  LJson, LOption, LSource: TJSONObject;
  LItems: TJSONArray;
  LBefore: Integer;
begin
  ResetFixture;
  LJson := TDAIProjectOptionsService.Configurations('');
  try
    Check(LJson.GetValue<string>('project') = ProjectObject.FileNameValue, 'configuration listing identifies active project');
    Check(LJson.GetValue<TJSONObject>('active_configuration').GetValue<string>('key') = 'Cfg_1_Win32', 'active configuration is already platform scoped');
    Check(LJson.GetValue<string>('active_platform') = 'Win32', 'active platform is preserved');
    Check(LJson.GetValue<TJSONArray>('configurations').Count = 9, 'listing includes Base, named configurations and platform children exactly once');
    Check(LJson.GetValue<TJSONArray>('platforms').Count = 2, 'listing exposes both supported platforms');
  finally
    LJson.Free;
  end;
  LBefore := Nodes[5].PlatformGetterCount;
  ReadCheck('active', 'active', 'DCC_Define', 'WIN32', 'local', 'Cfg_1_Win32', True);
  Check(Nodes[5].PlatformGetterCount = LBefore, 'active platform configuration is not selected for a second time');
  ReadCheck('active', 'active', 'DCC_Optimize', 'false', 'inherited', 'Cfg_1', False);
  ReadCheck('Base', '', 'DCC_Optimize', 'true', 'local', 'Base', True);
  ReadCheck('Release', '', 'DCC_Optimize', 'true', 'inherited', 'Base', False);
  ReadCheck('Cfg_1', '', 'DCC_ExeOutput', '', 'local', 'Cfg_1', True);
  ReadCheck('Cfg_1', 'Win64', 'DCC_ExeOutput', '', 'inherited', 'Cfg_1', False);
  ReadCheck('Base', '', 'DCC_Unset', '', 'default_or_unset', '', False);
  ReadCheck('active', '', 'DCC_Optimize', 'false', 'local', 'Cfg_1', True);
  ReadCheck('Cfg_1', '', 'DCC_UnitSearchPath', 'debug;base', 'local', 'Cfg_1', True);
  LJson := TDAIProjectOptionsService.ReadOptions('', 'active', 'active', ['DCC_UnitSearchPath'], 20);
  try
    LOption := FirstOption(LJson);
    Check(LOption.GetValue<string>('inherited_value') = 'debug;base', 'inherited value includes ancestor merge');
    LItems := LOption.GetValue<TJSONArray>('sources');
    Check(LItems.Count = 2, 'source chain reports both local ancestor values');
    LSource := LItems.Items[0] as TJSONObject;
    Check(LSource.GetValue<TJSONObject>('configuration').GetValue<string>('key') = 'Cfg_1', 'nearest ancestor is reported first');
    Check(LSource.GetValue<string>('value') = 'debug', 'source chain retains unmerged local ancestor text');
    Check(LSource.GetValue<Boolean>('merged'), 'source chain retains ancestor merge flag');
    Check((LItems.Items[1] as TJSONObject).GetValue<TJSONObject>('configuration').GetValue<string>('key') = 'Base', 'source chain identifies Base');
  finally
    LJson.Free;
  end;
  Check(not OptionsObject.ModifiedValue and (ProjectObject.ModifiedCount = 0), 'all reads leave project and options unmodified');
  Check(TDAIOTA.WritePreflightCount = 0, 'read operations need no write-path preflight');
end;

procedure ConfigurationDiscoveryCases;
var
  LJson: TJSONObject;
begin
  ResetFixture;
  Nodes[0].NameValue := 'Basiskonfiguration';
  ReadCheck('Base', '', 'DCC_Optimize', 'true', 'local', 'Base', True);
  Discard(TDAIProjectOptionsService.SetOption('', 'Base', '', 'DCC_LocalizedBase', 'value', 'replace'));
  Check(Nodes[0].SetValueCount = 1, 'reserved Base selection works independently of translated configuration name');
  ResetFixture;
  // Model SDK providers that enumerate platform nodes only through Platforms/PlatformConfiguration.
  Nodes[0].ChildrenValue := [Nodes[1], Nodes[2]];
  Nodes[1].ChildrenValue := nil;
  Nodes[2].ChildrenValue := nil;
  OptionsObject.ConfigurationsValue := [Configs[1], Configs[1], Configs[2]];
  LJson := TDAIProjectOptionsService.Configurations('');
  try
    Check(LJson.GetValue<TJSONArray>('configurations').Count = 9, 'platform-only nodes are included while duplicate config roots are collapsed');
    Check(Nodes[5].PlatformGetterCount = 0, 'discovery never asks an already specialized node for another platform configuration');
  finally
    LJson.Free;
  end;
  Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1_Win32', 'Win32', 'DCC_TestScope', 'specific', 'replace'));
  Check(Nodes[5].SetValueCount = 1, 'explicit platform SDK key selects exactly the matching platform node');
  Check(Nodes[1].SetValueCount = 0, 'explicit platform SDK key does not mutate its neutral parent');
end;

procedure EmptyValueAndDefaultMergeCases;
var
  LJson, LOption: TJSONObject;
  LName, LMode: string;
begin
  ResetFixture;
  Nodes[1].EmptyStringRemoves := True;
  for LName in ['DCC_Optimize', 'DAI_UnsupportedScalar'] do
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', LName, '', 'replace'));
      end, 'unsupported scalar empty value is rejected before a native setter can delete an override');
  for LMode in ['', 'preserve', 'merge'] do
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DCC_Define', '', LMode));
      end, 'empty list values require an explicit replace mode');
  Check((Nodes[1].SetValueCount = 0) and (Nodes[1].RemoveCount = 0), 'rejected empty string inputs precede every native mutation');
  Check(Nodes[1].SetMergedCount = 0, 'rejected empty string inputs preserve merge flags');
  Check(TDAIOTA.WritePreflightCount = 0, 'unsupported empty inputs are rejected before OTA write-path processing');
  Check(not OptionsObject.ModifiedValue and (ProjectObject.ModifiedCount = 0), 'rejected empty string inputs preserve unmodified project state');
  ReadCheck('Cfg_1', '', 'DCC_Optimize', 'false', 'local', 'Cfg_1', True);
  ReadCheck('Cfg_1', '', 'DCC_UnitSearchPath', 'debug;base', 'local', 'Cfg_1', True);
  // Existing empty properties remain readable, regardless of whether their setters accept empties.
  ReadCheck('Cfg_1', '', 'DCC_ExeOutput', '', 'local', 'Cfg_1', True);
  for LName in ['DCC_Define', 'DCC_UnitSearchPath', 'DCC_Namespace', 'DCC_IncludePath', 'DCC_ResourcePath',
    'DCC_ObjPath', 'DCC_UnitAlias', 'DCC_UsePackage', 'DCC_LibraryPath'] do
  begin
    ResetFixture;
    Nodes[1].EmptyStringRemoves := True;
    Nodes[1].EmptyMergeValueNames := [LName];
    Nodes[0].Define(LName, 'ancestor');
    // SetMerged(false) must execute even when the native getter reports false on the missing property.
    LJson := TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', LName, '', 'replace');
    try
      LOption := LJson.GetValue<TJSONObject>('option');
      Check(LOption.GetValue<Boolean>('has_local_value'), 'known native list accepts a real own empty override');
      Check(LOption.GetValue('local_value') is TJSONString, 'known native empty override is returned as a string');
      Check(LOption.GetValue<string>('local_value') = '', 'known native list local value remains empty');
      Check(LOption.GetValue<string>('effective_value') = '', 'empty replace suppresses inherited list values');
      Check(not LOption.GetValue<Boolean>('merged'), 'known native empty replacement disables merging');
      Check(LOption.GetValue<string>('origin') = 'local', 'known native empty replacement is local');
      Check(LJson.GetValue<Boolean>('merge_mode_applied'), 'known list reports the requested replacement mode as applied');
      Check((Nodes[1].SetValueCount = 1) and (Nodes[1].SetMergedCount = 1), 'known native list materializes empty through both value and merge setter');
      Check(Nodes[1].RemoveCount = 0, 'known empty replace is not reported or executed as Remove');
    finally
      LJson.Free;
    end;
    LJson := TDAIProjectOptionsService.RemoveOption('', 'Cfg_1', '', LName);
    try
      LOption := LJson.GetValue<TJSONObject>('option');
      Check(LJson.GetValue<Boolean>('removed'), 'explicit native empty override can later be removed');
      Check(LOption.GetValue<string>('effective_value') = 'ancestor', 'removing explicit native empty restores inherited list values');
      Check(Nodes[1].SetMergedCount = 1, 'Remove never rematerializes a typed-list empty through SetMerged');
    finally
      LJson.Free;
    end;
  end;
  ResetFixture;
  Nodes[1].EmptyStringRemoves := True;
  Nodes[1].IgnoredMergeValueNames := ['DCC_Define'];
  Nodes[1].Define('DCC_Define', 'prior-local');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DCC_Define', '', 'replace'));
    end, 'native providers unable to materialize known empty lists report failure instead of false success');
  Check((Nodes[1].SetValueCount = 1) and (Nodes[1].SetMergedCount = 1), 'unsupported native empty list provider was validated after both required calls');
  Check(OptionsObject.ModifiedValue and (ProjectObject.ModifiedCount = 1), 'native mutation before failed empty verification is honestly marked modified');
  Check(ProjectObject.SaveCount = 0, 'failed native empty verification never saves a project automatically');
  ResetFixture;
  LJson := TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DCC_UnitSearchPath', 'default-mode', '');
  try
    LOption := LJson.GetValue<TJSONObject>('option');
    Check(LOption.GetValue<Boolean>('merged'), 'empty merge_mode uses preserve default for nonempty text');
    Check(LOption.GetValue<string>('effective_value') = 'default-mode;base', 'default preserve keeps ancestor list values');
    Check(LJson.GetValue<Boolean>('merge_mode_applied'), 'default preserve confirms actual native merge mode');
  finally
    LJson.Free;
  end;
end;

procedure UnsupportedMergeModeCases;
var
  LJson, LOption: TJSONObject;
begin
  ResetFixture;
  Nodes[1].IgnoredMergeValueNames := ['DAI_UnsupportedScalar'];
  LJson := TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DAI_UnsupportedScalar', 'custom-value', 'merge');
  try
    LOption := LJson.GetValue<TJSONObject>('option');
    Check(LOption.GetValue<string>('effective_value') = 'custom-value', 'unsupported scalar still accepts the nonempty value');
    Check(not LOption.GetValue<Boolean>('merged'), 'actual ignored merge flag remains visible');
    Check(not LJson.GetValue<Boolean>('merge_mode_applied'), 'ignored native merge mode is not falsely reported as successful');
    Check((Nodes[1].SetValueCount = 1) and (Nodes[1].SetMergedCount = 1), 'service attempts native merge flag once and verifies its actual result');
  finally
    LJson.Free;
  end;
  LJson := TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DAI_UnsupportedScalar', 'next-value', 'preserve');
  try
    Check(LJson.GetValue<Boolean>('merge_mode_applied'), 'preserve is applied when the existing actual flag remains unchanged');
    Check(LJson.GetValue<TJSONObject>('option').GetValue<string>('effective_value') = 'next-value', 'preserve still updates the selected custom scalar');
  finally
    LJson.Free;
  end;
end;

procedure NativePlatformProvenanceCases;
var
  LJson, LOption, LSource: TJSONObject;
  LSources: TJSONArray;
  LValue, LNeutralValue: string;
  LIndex, LDirectCount, LCandidateCount: Integer;
begin
  ResetFixture;
  Nodes[3].Define('DCC_NativeScope', 'native-platform');
  Nodes[5].DefineNativeEffectiveValue('DCC_NativeScope', 'native-platform');
  LJson := TDAIProjectOptionsService.ReadOptions('', 'active', 'active', ['DCC_NativeScope'], 20);
  try
    LOption := FirstOption(LJson);
    Check(LOption.GetValue<string>('effective_value') = 'native-platform', 'effective value comes from native SDK evaluation including hidden platform inheritance');
    Check(LOption.GetValue<string>('origin') = 'inherited', 'a single platform candidate is inherited');
    Check(LOption.GetValue<TJSONObject>('origin_configuration').GetValue<string>('key') = 'Base_Win32', 'single explicit platform source identifies its configuration');
    Check(LOption.GetValue<string>('source_resolution') = 'single_explicit_source', 'single platform source has explicit provenance certainty');
    Check(LOption.GetValue<string>('provenance_scope') = 'sdk_parent_and_platform_candidates', 'provenance scope states SDK parents and platform candidates');
    LSources := LOption.GetValue<TJSONArray>('sources');
    Check(LSources.Count = 1, 'hidden platform ancestor appears as a source');
    Check((LSources.Items[0] as TJSONObject).GetValue<string>('scope') = 'platform_candidate', 'hidden platform source is distinguished from native Parent');
    Check(LJson.GetValue<TJSONObject>('configuration').GetValue<TJSONObject>('parent').GetValue<string>('key') = 'Cfg_1', 'native Parent metadata remains neutral Debug');
  finally
    LJson.Free;
  end;
  LJson := TDAIProjectOptionsService.ReadOptions('', 'active', 'active', nil, 100);
  try
    LSources := LJson.GetValue<TJSONArray>('options');
    LIndex := 0;
    while LIndex < LSources.Count do
    begin
      LOption := LSources.Items[LIndex] as TJSONObject;
      if LOption.GetValue<string>('name') = 'DCC_NativeScope' then
        Break;
      Inc(LIndex);
    end;
    Check(LIndex < LSources.Count, 'enumeration includes properties defined only in a hidden platform companion');
    Check(LJson.GetValue<string>('enumeration_scope') = 'explicit_properties_in_parent_and_platform_scopes', 'enumeration declares its extended scope');
  finally
    LJson.Free;
  end;
  for LNeutralValue in ['native-platform', 'different-neutral'] do
  begin
    ResetFixture;
    LValue := 'native-platform';
    Nodes[0].Define('DCC_NativeScope', LNeutralValue);
    Nodes[3].Define('DCC_NativeScope', LValue);
    Nodes[5].DefineNativeEffectiveValue('DCC_NativeScope', LValue);
    LJson := TDAIProjectOptionsService.ReadOptions('', 'active', 'active', ['DCC_NativeScope'], 20);
    try
      LOption := FirstOption(LJson);
      Check(LOption.GetValue<string>('effective_value') = LValue, 'ambiguity never replaces the native effective value');
      Check(LOption.GetValue<string>('origin') = 'inherited', 'multiple platform-related sources remain inherited');
      Check(LOption.GetValue('origin_configuration') is TJSONNull, 'multiple sources do not invent a precise origin through value equality');
      Check(LOption.GetValue<string>('source_resolution') = 'unknown', 'ambiguous native platform precedence is disclosed');
      Check(LOption.GetValue<string>('source_resolution_reason') = 'platform_resolution_ambiguous', 'ambiguous platform reason is explicit');
      LSources := LOption.GetValue<TJSONArray>('sources');
      Check(LSources.Count = 2, 'both global and platform-specific explicit sources are exposed');
      LDirectCount := 0;
      LCandidateCount := 0;
      for LIndex := 0 to LSources.Count - 1 do
      begin
        LSource := LSources.Items[LIndex] as TJSONObject;
        if LSource.GetValue<string>('scope') = 'direct_parent' then
          Inc(LDirectCount)
        else if LSource.GetValue<string>('scope') = 'platform_candidate' then
          Inc(LCandidateCount);
      end;
      Check((LDirectCount = 1) and (LCandidateCount = 1), 'candidate scopes retain their native Parent distinction');
    finally
      LJson.Free;
    end;
    Nodes[1].Define('DCC_NativeScope', LNeutralValue);
    LJson := TDAIProjectOptionsService.ReadOptions('', 'active', 'active', ['DCC_NativeScope'], 20);
    try
      LOption := FirstOption(LJson);
      Check(LOption.GetValue('origin_configuration') is TJSONNull, 'additional Debug neutral source does not imply a unique platform origin');
      Check(LOption.GetValue<string>('source_resolution') = 'unknown', 'equal or different Debug neutral text leaves platform precedence uncertain');
      Check(LOption.GetValue<TJSONArray>('sources').Count = 3, 'all three explicit sources remain visible');
    finally
      LJson.Free;
    end;
    Nodes[5].Define('DCC_NativeScope', 'local');
    LJson := TDAIProjectOptionsService.ReadOptions('', 'active', 'active', ['DCC_NativeScope'], 20);
    try
      LOption := FirstOption(LJson);
      Check(LOption.GetValue<string>('source_resolution') = 'local', 'local membership remains certain despite candidate ancestors');
      Check(LOption.GetValue<string>('origin') = 'local', 'local override remains local');
      Check(LOption.GetValue<TJSONObject>('origin_configuration').GetValue<string>('key') = 'Cfg_1_Win32', 'local override identifies selected platform scope');
    finally
      LJson.Free;
    end;
  end;
end;

procedure ScopeWriteCases;
const
  CConfigurations: array[0..2] of string = ('Base', 'Cfg_1', 'Release');
  CPlatforms: array[0..2] of string = ('', 'Win32', 'Win64');
var
  LConfig, LPlatform, LTarget, LIndex: Integer;
  LJson, LOption: TJSONObject;
begin
  for LConfig := 0 to 2 do
    for LPlatform := 0 to 2 do
    begin
      ResetFixture;
      LTarget := LConfig;
      if LPlatform > 0 then
        LTarget := 2 + LConfig * 2 + LPlatform;
      LJson := TDAIProjectOptionsService.SetOption('', CConfigurations[LConfig], CPlatforms[LPlatform], 'DCC_TestScope', 'scope-value', 'replace');
      try
        Check(LJson.GetValue<TJSONObject>('configuration').GetValue<string>('key') = Nodes[LTarget].KeyValue, 'write resolves explicitly requested config/platform');
        LOption := LJson.GetValue<TJSONObject>('option');
        Check(LOption.GetValue<string>('local_value') = 'scope-value', 'write returns the new local value');
        Check(LJson.GetValue<Boolean>('changed'), 'new property reports a mutation');
        Check(LJson.GetValue<Boolean>('modified'), 'new property reports modified options');
        Check(not LJson.GetValue<Boolean>('saved'), 'mutation explicitly reports no automatic persistence');
        for LIndex := 0 to High(Nodes) do
          Check(Nodes[LIndex].SetValueCount = Ord(LIndex = LTarget), 'only selected configuration receives SetValue');
        Check(OptionsObject.ModifiedValue and (OptionsObject.ModifiedSetterCount = 1), 'project options modified state is set');
        Check(ProjectObject.ModifiedCount = 1, 'project module is marked modified once');
        Check(ProjectObject.SaveCount = 0, 'project is never saved automatically');
        Check(OptionsObject.ActiveConfigurationValue = Configs[5], 'scope write preserves active build configuration');
        Check(GroupObject.ActiveProjectValue = ProjectInterface, 'scope write preserves active project');
        Check(TDAIOTA.WritePreflightCount > 0, 'scope mutation validates writable project paths');
      finally
        LJson.Free;
      end;
      LJson := TDAIProjectOptionsService.RemoveOption('', CConfigurations[LConfig], CPlatforms[LPlatform], 'DCC_TestScope');
      try
        Check(LJson.GetValue<Boolean>('removed'), 'scope removal deletes the selected property');
        Check(not LJson.GetValue<TJSONObject>('option').GetValue<Boolean>('has_local_value'), 'scope removal leaves no empty override');
        for LIndex := 0 to High(Nodes) do
        begin
          Check(Nodes[LIndex].RemoveCount = Ord(LIndex = LTarget), 'only selected configuration receives Remove');
          Check(Nodes[LIndex].SetValueCount = Ord(LIndex = LTarget), 'scope removal never rewrites the property through SetValue');
        end;
        Check(not LJson.GetValue<Boolean>('saved'), 'scope removal never persists project files automatically');
      finally
        LJson.Free;
      end;
    end;
end;

procedure RemovalAndMergeCases;
var
  LJson, LOption: TJSONObject;
  LMode: string;
  LBeforeSet, LBeforeMerge: Integer;
begin
  ResetFixture;
  LJson := TDAIProjectOptionsService.RemoveOption('', 'Cfg_1', '', 'DCC_ExeOutput');
  try
    Check(LJson.GetValue<Boolean>('removed'), 'Remove deletes an explicit empty override');
    LOption := LJson.GetValue<TJSONObject>('option');
    Check(not LOption.GetValue<Boolean>('has_local_value'), 'removed property is absent locally');
    Check(LOption.GetValue<string>('effective_value') = 'basebin', 'Remove restores ancestor value rather than overriding with empty');
    Check(LOption.GetValue<string>('origin') = 'inherited', 'Remove reports restored inheritance');
    Check(Nodes[1].RemoveCount = 1, 'Remove uses native property removal exactly once');
    Check((Nodes[1].SetValueCount = 0) and (Nodes[1].SetMergedCount = 0), 'Remove never recreates the deleted property through setters');
    Check((LJson.GetValue<TJSONObject>('previous').GetValue('local_value') as TJSONString).Value = '', 'previous empty override remains distinguishable');
  finally
    LJson.Free;
  end;
  LJson := TDAIProjectOptionsService.RemoveOption('', 'Cfg_1', '', 'DCC_Unset');
  try
    Check(not LJson.GetValue<Boolean>('removed'), 'removing an absent override is an explicit no-op');
    Check(Nodes[1].RemoveCount = 1, 'absent Remove does not touch native configuration');
  finally
    LJson.Free;
  end;
  for LMode in ['preserve', 'merge', 'replace'] do
  begin
    ResetFixture;
    LJson := TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DCC_UnitSearchPath', 'new', LMode);
    try
      LOption := LJson.GetValue<TJSONObject>('option');
      Check(LOption.GetValue<Boolean>('merged') = (LMode <> 'replace'), 'merge mode updates or preserves native merging');
      if LMode = 'replace' then
        Check(LOption.GetValue<string>('effective_value') = 'new', 'replace omits inherited list values')
      else
        Check(LOption.GetValue<string>('effective_value') = 'new;base', 'merge and preserve restore inherited list values after native SetValue');
      Check(LJson.GetValue<TJSONObject>('previous').GetValue<string>('effective_value') = 'debug;base', 'setter returns previous effective value');
    finally
      LJson.Free;
    end;
  end;
  LBeforeSet := Nodes[1].SetValueCount;
  LBeforeMerge := Nodes[1].SetMergedCount;
  LJson := TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DCC_UnitSearchPath', 'new', 'replace');
  try
    Check(LJson.GetValue<Boolean>('changed'), 'repeated Set transparently reports its native setter mutation');
    Check(Nodes[1].SetValueCount = LBeforeSet + 1, 'repeated Set writes only the explicitly selected configuration');
    Check(Nodes[1].SetMergedCount = LBeforeMerge, 'unchanged native merge flag needs no redundant setter');
  finally
    LJson.Free;
  end;
end;

procedure SelectionRejectionCases;
var
  LConfig, LPlatform, LMode, LName: string;
  LIndex: Integer;
begin
  ResetFixture;
  for LConfig in ['', 'active', 'Unknown', 'debug-missing'] do
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.SetOption('', LConfig, '', 'DCC_TestScope', 'value', 'replace'));
      end, 'writes require a concrete existing configuration: ' + LConfig);
  for LPlatform in ['active', 'Linux', 'WinARM64'] do
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1', LPlatform, 'DCC_TestScope', 'value', 'replace'));
      end, 'writes require a supported explicit platform or the all-platform scope: ' + LPlatform);
  for LPlatform in ['', 'Win64'] do
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1_Win32', LPlatform, 'DCC_TestScope', 'value', 'replace'));
      end, 'platform SDK key cannot silently redirect the write to another scope');
  for LMode in ['inherit', 'unsupported'] do
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DCC_TestScope', 'value', LMode));
      end, 'unknown merge mode is rejected');
  for LName in ['', 'DCC Bad', '$(DCC_Define)', 'DCC<Bad', StringOfChar('x', 257)] do
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', LName, 'value', 'replace'));
      end, 'invalid property name is rejected');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.SetOption('', 'Cfg_1', '', 'DCC_TestScope', StringOfChar('x', 65537), 'replace'));
    end, 'oversize option values are rejected');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.RemoveOption('', 'active', '', 'DCC_Optimize'));
    end, 'Remove requires an explicit configuration too');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.ReadOptions('', 'Unknown', '', ['DCC_Optimize'], 10));
    end, 'unknown read configuration is rejected');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.ReadOptions('', 'Base', 'Linux', ['DCC_Optimize'], 10));
    end, 'unknown read platform is rejected');
  for LIndex := 0 to High(Nodes) do
    Check((Nodes[LIndex].SetValueCount = 0) and (Nodes[LIndex].SetMergedCount = 0) and (Nodes[LIndex].RemoveCount = 0), 'invalid inputs cannot mutate a configuration');
  Check(not OptionsObject.ModifiedValue and (ProjectObject.ModifiedCount = 0), 'invalid inputs preserve project modified state');
end;

procedure AccessAndActivationCases;
var
  LJson: TJSONObject;
begin
  ResetFixture;
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.ReadOptions(OtherProjectObject.FileNameValue, 'Release', '', ['DCC_Optimize'], 10));
    end, 'another group project must be activated before reading options');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.SetOption(OtherProjectObject.FileNameValue, 'Release', '', 'DCC_TestScope', 'value', 'replace'));
    end, 'another group project must be activated before writing options');
  Check(GroupObject.ActivationCount = 0, 'option requests never switch projects implicitly');
  LJson := TDAIProjectOptionsService.ActivateProject(OtherProjectObject.FileNameValue);
  try
    Check(LJson.GetValue<Boolean>('activated'), 'explicit project activation succeeds');
    Check(LJson.GetValue<string>('previous_project') = ProjectObject.FileNameValue, 'activation reports previous project');
    Check(GroupObject.ActiveProjectValue = OtherProjectInterface, 'activation selects requested group project');
  finally
    LJson.Free;
  end;
  Discard(TDAIProjectOptionsService.ReadOptions(OtherProjectObject.FileNameValue, 'Release', '', ['DCC_Optimize'], 10));
  Discard(TDAIProjectOptionsService.SetOption(OtherProjectObject.FileNameValue, 'Release', '', 'DCC_TestScope', 'value', 'replace'));
  Check(OtherProjectObject.ModifiedCount = 1, 'newly activated project is mutated');
  Check(ProjectObject.ModifiedCount = 0, 'previous project remains unmodified');
  Check(Nodes[2].SetValueCount = 0, 'previous project configuration data remains untouched after activation');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.ActivateProject(TPath.Combine(FixtureRoot, 'NotInGroup.dpr')));
    end, 'activation rejects projects outside the current group');
  ResetFixture;
  TDAIOTA.DeniedReferencePrefix := FixtureRoot;
  Discard(TDAIProjectOptionsService.ReadOptions('', 'Base', '', ['DCC_Optimize'], 10));
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.ActivateProject(OtherProjectObject.FileNameValue));
    end, 'reference project-group paths cannot be changed by activation');
  Check(GroupObject.ActivationCount = 0, 'denied group activation never calls the native setter');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.SetOption('', 'Base', '', 'DCC_TestScope', 'value', 'replace'));
    end, 'reference source project cannot be written');
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.RemoveOption('', 'Base', '', 'DCC_Optimize'));
    end, 'reference source project cannot remove options');
  Check((Nodes[0].SetValueCount = 0) and (Nodes[0].RemoveCount = 0), 'reference write denial happens before native mutation');
  TDAIOTA.DeniedReferencePrefix := '';
  TDAIOTA.DeniedReparsePrefix := FixtureRoot;
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.SetOption('', 'Base', '', 'DCC_TestScope', 'value', 'replace'));
    end, 'reparse write denial happens before native mutation');
  Check(Nodes[0].SetValueCount = 0, 'reparse denied scope remains untouched');
end;

procedure BoundsAndCycleCases;
var
  LJson: TJSONObject;
  LIndex: Integer;
  LChain: TArray<IOTABuildConfiguration>;
  LRequested: TArray<string>;
  LNode, LPrevious: TTestConfiguration;
begin
  ResetFixture;
  SetLength(LRequested, 1001);
  for LIndex := 0 to High(LRequested) do
    LRequested[LIndex] := 'DCC_Request' + LIndex.ToString;
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.ReadOptions('', 'Base', '', LRequested, 1000));
    end, 'oversize explicit options-name arrays are rejected before enumeration');
  for LIndex := 0 to 4 do
    Nodes[0].Define('DCC_Bound' + LIndex.ToString, LIndex.ToString);
  LJson := TDAIProjectOptionsService.ReadOptions('', 'Base', '', nil, 2);
  try
    Check(LJson.GetValue<TJSONArray>('options').Count = 2, 'maximum option count limits returned items');
    Check(LJson.GetValue<Boolean>('truncated'), 'bounded read exposes truncation');
    Check(LJson.GetValue<Integer>('option_count') >= 9, 'bounded read exposes available option count');
  finally
    LJson.Free;
  end;
  LJson := TDAIProjectOptionsService.ReadOptions('', 'Base', '', nil, 0);
  try
    Check(LJson.GetValue<TJSONArray>('options').Count = 1, 'nonpositive maximum clamps to one bounded result');
    Check(LJson.GetValue<Boolean>('truncated'), 'clamped result still reports omitted options');
  finally
    LJson.Free;
  end;
  Nodes[0].ParentValue := Nodes[1];
  try
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.ReadOptions('', 'Cfg_1', '', ['DCC_Optimize'], 10));
      end, 'cyclic parent inheritance fails instead of hanging');
  finally
    Nodes[0].ParentValue := nil;
  end;
  SetLength(LChain, 130);
  LPrevious := nil;
  for LIndex := 0 to High(LChain) do
  begin
    LNode := TTestConfiguration.Create('Deep_' + LIndex.ToString, 'Deep_' + LIndex.ToString, '', LPrevious);
    LChain[LIndex] := LNode;
    LPrevious := LNode;
  end;
  OptionsObject.ConfigurationsValue := [LChain[High(LChain)]];
  OptionsObject.ActiveConfigurationValue := LChain[High(LChain)];
  OptionsObject.BaseConfigurationValue := LChain[0];
  try
    ExpectRejected(
      procedure
      begin
        Discard(TDAIProjectOptionsService.ReadOptions('', 'active', '', ['DCC_Optimize'], 10));
      end, 'excessive inheritance depth fails within the documented bound');
  finally
    OptionsObject.ConfigurationsValue := nil;
    OptionsObject.ActiveConfigurationValue := nil;
    OptionsObject.BaseConfigurationValue := nil;
    LChain := nil;
  end;
  ResetFixture;
  TDAIOTA.TestGroup := nil;
  ExpectRejected(
    procedure
    begin
      Discard(TDAIProjectOptionsService.Configurations(''));
    end, 'absence of active project is reported clearly');
end;

begin
  try
    Check(BorlandIDEServices = nil, 'isolated options tests do not use a live IDE host');
    FixtureRoot := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'VirtualWorkspaceNotCreated');
    Check(not TDirectory.Exists(FixtureRoot), 'synthetic project workspace does not exist');
    ReadCases;
    ConfigurationDiscoveryCases;
    EmptyValueAndDefaultMergeCases;
    UnsupportedMergeModeCases;
    NativePlatformProvenanceCases;
    ScopeWriteCases;
    RemovalAndMergeCases;
    SelectionRejectionCases;
    AccessAndActivationCases;
    BoundsAndCycleCases;
    TDAIOTA.TestGroup := nil;
    ProjectInterface := nil;
    OtherProjectInterface := nil;
    Configs := nil;
    Check(not TDirectory.Exists(FixtureRoot), 'options tests never create or persist project files');
    Writeln('OK: ', CheckCount, ' native project options checks (', SizeOf(Pointer) * 8, '-bit)');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
