function CleanupSettingsFingerprint: string;
begin
  Result := BoolToStr(TDAISettings.Instance.UseSharedConnectionSettings, True) + '|' +
    TDAISettings.Instance.RegistryRoot + '|' + IntToStr(TDAISettings.Instance.Port) + '|' +
    TDAISettings.Instance.Token + '|' + IntToStr(TDAISettings.Instance.SaveCount);
end;

procedure SelectCleanupScope(AIndex: Integer);
begin
  SelectRegistrationScope(AIndex);
  if AIndex = 3 then
    TDAISettings.Instance.RegistryRoot := 'Software\Embarcadero\DAICleanupAbsentProfile\37.0\DAI';
  TDAISettings.Instance.Token := 'cleanup-private-token-' + IntToStr(AIndex);
end;

procedure SetCleanupString(AObject: TJSONObject; const AName, AValue: string);
begin
  AObject.RemovePair(AName).Free;
  AObject.AddPair(AName, AValue);
end;

function CloneCleanupCandidate(ACandidate: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(ACandidate.ToJSON) as TJSONObject;
end;

procedure CheckCleanupRedacted(const AText, AName: string);
var
  LIndex: Integer;
begin
  for LIndex := 0 to 3 do
    Check(Pos('cleanup-private-token-' + IntToStr(LIndex), AText) = 0, AName + ' excludes credential');
  Check(Pos('Bearer ', AText) = 0, AName + ' excludes authorization value');
end;

function FindCleanupCandidate(const AClient, APath, AServer: string; ARequired: Boolean = True): TJSONObject;
var
  LScan: TJSONObject;
  LCandidates: TJSONArray;
  LItem: TJSONValue;
  LObject: TJSONObject;
begin
  Result := nil;
  LScan := TDAIClientRegistration.FindRegistrations(AClient);
  try
    CheckCleanupRedacted(LScan.ToJSON, AClient + ' inventory');
    LCandidates := LScan.GetValue<TJSONArray>('registrations');
    for LItem in LCandidates do
    begin
      LObject := LItem as TJSONObject;
      if (LObject.GetValue<string>('server_name') = AServer) and SameText(LObject.GetValue<string>('path'), APath) then
      begin
        Check(Result = nil, AClient + ' inventory has unique path and scope');
        Result := CloneCleanupCandidate(LObject);
      end;
    end;
    if ARequired then
      Check(Result <> nil, AClient + ' inventory discovers ' + AServer);
  finally
    LScan.Free;
  end;
end;

procedure RejectCleanupRemoval(ACandidate: TJSONObject; const AName: string);
var
  LResult: TJSONObject;
  LRejected: Boolean;
begin
  LRejected := False;
  LResult := nil;
  try
    LResult := TDAIClientRegistration.RemoveFoundRegistration(ACandidate);
  except
    on E: Exception do LRejected := True;
  end;
  if LResult <> nil then
  begin
    try
      CheckCleanupRedacted(LResult.ToJSON, AName);
      LRejected := not LResult.GetValue<Boolean>('removed');
    finally
      LResult.Free;
    end;
  end;
  Check(LRejected, AName);
end;

procedure CleanupForgedCandidateTests(ACandidate: TJSONObject; const APath, AText: string);
const
  CFields: array[0..4] of string = ('path', 'client', 'server_name', 'connection_scope', 'registry_root');
  CValues: array[0..4] of string = ('C:\DAI-cleanup-forged-path\config.json', 'foreign-client',
    'other_server', 'invalid-scope', 'Software\Embarcadero\BDS\37.0\DAI');
var
  LIndex: Integer;
  LCandidate: TJSONObject;
  LSettings: string;
begin
  LSettings := CleanupSettingsFingerprint;
  for LIndex := 0 to High(CFields) do
  begin
    LCandidate := CloneCleanupCandidate(ACandidate);
    try
      SetCleanupString(LCandidate, CFields[LIndex], CValues[LIndex]);
      RejectCleanupRemoval(LCandidate, 'forged cleanup ' + CFields[LIndex] + ' denied');
      Check(TFile.ReadAllText(APath, TEncoding.UTF8) = AText, 'forged cleanup retains exact config bytes');
      Check(CleanupSettingsFingerprint = LSettings, 'forged cleanup leaves settings and SaveCount unchanged');
    finally
      LCandidate.Free;
    end;
  end;
end;

procedure CleanupClientTests(const AClient, APath, AFormat: string; const AKeys: TArray<string>);
var
  LNames, LEntries, LLaunchers, LSidecars, LOwnerships: array[0..3] of string;
  LIndex, LCount: Integer;
  LJson, LCandidate, LEdited: TJSONObject;
  LText, LSettings, LForeign, LChanged, LBridge: string;
begin
  if AFormat = 'yaml' then
    LText := 'keep: true' + sLineBreak + 'mcp_servers:' + sLineBreak + '  other:' + sLineBreak + '    url: "http://foreign"' + sLineBreak
  else if AFormat = 'json5' then
    LText := '{keep:true, mcp:{servers:{other:{url:''http://foreign''}}}}'
  else
    LText := '{"keep":true,"mcpServers":{"other":{"url":"http://foreign"}}}';
  WriteFixture(APath, LText);
  LForeign := ScopedFixtureEntry(LText, AFormat, AKeys, 'other');
  for LIndex := 0 to 3 do
  begin
    SelectCleanupScope(LIndex);
    LNames[LIndex] := TDAICodexRegistration.ServerName;
    LJson := TDAIClientRegistration.RegisterFiles(AClient);
    try
      Check(ClientStatus(LJson) = 'configured', AClient + ' cleanup fixture registered: ' + ClientStatus(LJson));
      LSidecars[LIndex] := TJSONObject(TJSONArray(LJson.GetValue('clients')).Items[0]).GetValue<string>('ownership_file');
    finally
      LJson.Free;
    end;
    LOwnerships[LIndex] := TFile.ReadAllText(LSidecars[LIndex], TEncoding.UTF8);
  end;
  LText := TFile.ReadAllText(APath, TEncoding.UTF8);
  for LIndex := 0 to 3 do
  begin
    LEntries[LIndex] := ScopedFixtureEntry(LText, AFormat, AKeys, LNames[LIndex]);
    LLaunchers[LIndex] := ScopedFixtureEntry(LText, AFormat, AKeys, LNames[LIndex] + '_start');
  end;
  SelectCleanupScope(2);
  LSettings := CleanupSettingsFingerprint;
  LCount := Length(TDirectory.GetFiles(TPath.GetDirectoryName(APath), '*', TSearchOption.soAllDirectories));
  for LIndex := 0 to 3 do
  begin
    LCandidate := FindCleanupCandidate(AClient, APath, LNames[LIndex]);
    try
      Check(LCandidate.GetValue<Boolean>('removable'), AClient + ' untouched scope safely removable');
      Check(LCandidate.GetValue<Boolean>('current_scope') = (LIndex = 2), AClient + ' scope relative to active Delphi 13');
      Check(LCandidate.GetValue<string>('client') = AClient, AClient + ' inventory client metadata');
      Check(LCandidate.GetValue<string>('launcher_server') = LNames[LIndex] + '_start', AClient + ' inventory paired launcher metadata');
      Check(LCandidate.GetValue<string>('config_sha256') <> '', AClient + ' inventory pins config snapshot');
      Check(LCandidate.GetValue<string>('ownership_sha256') <> '', AClient + ' inventory pins sidecar snapshot');
    finally
      LCandidate.Free;
    end;
    Check(TFile.ReadAllText(LSidecars[LIndex], TEncoding.UTF8) = LOwnerships[LIndex], AClient + ' scan never rewrites ownership');
  end;
  Check(TFile.ReadAllText(APath, TEncoding.UTF8) = LText, AClient + ' scan retains all config bytes');
  Check(Length(TDirectory.GetFiles(TPath.GetDirectoryName(APath), '*', TSearchOption.soAllDirectories)) = LCount,
    AClient + ' scan creates no files or backups');
  Check(CleanupSettingsFingerprint = LSettings, AClient + ' scan leaves settings and SaveCount unchanged');
  LCandidate := FindCleanupCandidate(AClient, APath, LNames[1]);
  try
    CleanupForgedCandidateTests(LCandidate, APath, LText);
    if AFormat = 'yaml' then LChanged := LText + '# concurrent unrelated edit' + sLineBreak
    else LChanged := LText + sLineBreak;
    TFile.WriteAllText(APath, LChanged, TEncoding.UTF8);
    RejectCleanupRemoval(LCandidate, AClient + ' changed config after scan denied');
    Check(TFile.ReadAllText(APath, TEncoding.UTF8) = LChanged, AClient + ' stale removal retains concurrent edit');
    TFile.WriteAllText(APath, LText, TEncoding.UTF8);
    TFile.WriteAllText(LSidecars[1], LOwnerships[1] + sLineBreak, TEncoding.UTF8);
    RejectCleanupRemoval(LCandidate, AClient + ' changed sidecar after scan denied');
    Check(TFile.ReadAllText(APath, TEncoding.UTF8) = LText, AClient + ' stale ownership removal retains config');
    TFile.WriteAllText(LSidecars[1], LOwnerships[1], TEncoding.UTF8);
  finally
    LCandidate.Free;
  end;
  LEdited := TJSONObject.ParseJSONValue(LOwnerships[1]) as TJSONObject;
  try
    SetCleanupString(LEdited, 'entry_sha256', StringOfChar('a', 64));
    TFile.WriteAllText(LSidecars[1], LEdited.ToJSON, TEncoding.UTF8);
  finally
    LEdited.Free;
  end;
  LCandidate := FindCleanupCandidate(AClient, APath, LNames[1]);
  try
    Check(not LCandidate.GetValue<Boolean>('removable'), AClient + ' changed owned entry blocks cleanup');
    RejectCleanupRemoval(LCandidate, AClient + ' changed ownership never removes entry');
    Check(TFile.ReadAllText(APath, TEncoding.UTF8) = LText, AClient + ' changed ownership preserves both entries');
  finally
    LCandidate.Free;
  end;
  TFile.WriteAllText(LSidecars[1], LOwnerships[1], TEncoding.UTF8);
  LCandidate := FindCleanupCandidate(AClient, APath, LNames[1]);
  try
    // Cleanup must work after the old IDE/bridge has been uninstalled.
    LBridge := TDAICodexRegistration.BridgeFileName;
    TFile.Delete(LBridge);
    try
      LJson := TDAIClientRegistration.RemoveFoundRegistration(LCandidate);
      try
        Check(LJson.GetValue<Boolean>('removed'), AClient + ' Delphi 13 removes old Delphi 11 without bridge');
        CheckCleanupRedacted(LJson.ToJSON, AClient + ' cleanup result');
      finally
        LJson.Free;
      end;
    finally
      TFile.WriteAllText(LBridge, 'test fixture, never executed', TEncoding.UTF8);
    end;
  finally
    LCandidate.Free;
  end;
  LText := TFile.ReadAllText(APath, TEncoding.UTF8);
  Check(not ScopedFixtureHasEntry(LText, AFormat, AKeys, LNames[1]) and
    not ScopedFixtureHasEntry(LText, AFormat, AKeys, LNames[1] + '_start'), AClient + ' only chosen old pair removed');
  Check(ScopedFixtureEntry(LText, AFormat, AKeys, 'other') = LForeign, AClient + ' cleanup retains foreign MCP server');
  for LIndex in [0, 2, 3] do
  begin
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, LNames[LIndex]) = LEntries[LIndex], AClient + ' cleanup retains other HTTP bytes');
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, LNames[LIndex] + '_start') = LLaunchers[LIndex],
      AClient + ' cleanup retains other launcher bytes');
    Check(TFile.ReadAllText(LSidecars[LIndex], TEncoding.UTF8) = LOwnerships[LIndex], AClient + ' cleanup retains other sidecar bytes');
  end;
  Check(CleanupSettingsFingerprint = LSettings, AClient + ' cleanup never switches scope or saves settings');
  LCandidate := FindCleanupCandidate(AClient, APath, LNames[1], False);
  try
    Check(LCandidate = nil, AClient + ' removed scope disappears on rescan');
  finally
    LCandidate.Free;
  end;
end;

procedure CleanupCodexTests;
var
  LIndex: Integer;
  LNames: array[0..3] of string;
  LPath, LText, LSkill, LSettings, LBridge, LChanged: string;
  LCandidate, LJson: TJSONObject;
begin
  LPath := TDAICodexRegistration.CodexConfigFileName;
  WriteFixture(LPath, 'model="preserved"' + sLineBreak + '[mcp_servers.other]' + sLineBreak + 'url="http://foreign"' + sLineBreak);
  for LIndex := 0 to 3 do
  begin
    SelectCleanupScope(LIndex);
    LNames[LIndex] := TDAICodexRegistration.ServerName;
    TDAICodexRegistration.RegisterFiles;
  end;
  SelectCleanupScope(2);
  LSettings := CleanupSettingsFingerprint;
  LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  LSkill := TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8);
  for LIndex := 0 to 3 do
  begin
    LCandidate := FindCleanupCandidate('codex', LPath, LNames[LIndex]);
    try
      Check(LCandidate.GetValue<Boolean>('removable'), 'Codex managed scope safely removable');
      Check(LCandidate.GetValue<Boolean>('current_scope') = (LIndex = 2), 'Codex current scope identified');
      Check(LCandidate.GetValue<string>('block_sha256') <> '', 'Codex pins managed block snapshot');
    finally
      LCandidate.Free;
    end;
  end;
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'Codex scan retains complete config');
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = LSkill, 'Codex scan retains skill bytes');
  Check(CleanupSettingsFingerprint = LSettings, 'Codex scan leaves settings and SaveCount unchanged');
  LCandidate := FindCleanupCandidate('codex', LPath, LNames[1]);
  try
    CleanupForgedCandidateTests(LCandidate, LPath, LText);
    LChanged := LText + '# user changed after search' + sLineBreak;
    TFile.WriteAllText(LPath, LChanged, TEncoding.UTF8);
    RejectCleanupRemoval(LCandidate, 'Codex stale full config rejected');
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LChanged, 'Codex stale removal retains user change');
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    LBridge := TDAICodexRegistration.BridgeFileName;
    TFile.Delete(LBridge);
    try
      LJson := TDAIClientRegistration.RemoveFoundRegistration(LCandidate);
      try
        Check(LJson.GetValue<Boolean>('removed'), 'Codex removes old 11 while current 13 remains selected and bridge absent');
      finally
        LJson.Free;
      end;
    finally
      TFile.WriteAllText(LBridge, 'test fixture, never executed', TEncoding.UTF8);
    end;
  finally
    LCandidate.Free;
  end;
  LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  Check((Pos('[mcp_servers.dai_bds22_0]', LText) = 0) and (Pos('[mcp_servers.dai_bds22_0_start]', LText) = 0),
    'Codex removes chosen old pair');
  Check((Pos('model="preserved"', LText) > 0) and (Pos('[mcp_servers.other]', LText) > 0), 'Codex retains user config and foreign server');
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = LSkill, 'Codex keeps shared skill while other scopes remain');
  Check(CleanupSettingsFingerprint = LSettings, 'Codex cleanup leaves current connection settings unchanged');
  LCandidate := FindCleanupCandidate('codex', LPath, LNames[1], False);
  try
    Check(LCandidate = nil, 'Codex removed scope disappears on rescan');
  finally
    LCandidate.Free;
  end;
  for LIndex in [0, 2, 3] do
  begin
    LCandidate := FindCleanupCandidate('codex', LPath, LNames[LIndex]);
    try
      LJson := TDAIClientRegistration.RemoveFoundRegistration(LCandidate);
      try
        Check(LJson.GetValue<Boolean>('removed'), 'Codex remaining chosen scope removed');
      finally
        LJson.Free;
      end;
      if LIndex <> 3 then
        Check(TFile.Exists(TDAICodexRegistration.SkillFileName), 'Codex shared skill survives until last owned registration');
    finally
      LCandidate.Free;
    end;
  end;
  Check(not TFile.Exists(TDAICodexRegistration.SkillFileName), 'Codex last discovered scope removal cleans managed skill');
end;

procedure CleanupCodexLegacyTests;
var
  LPath, LLegacy, LText, LSkill, LSettings, LLegacyText: string;
  LCandidate, LJson: TJSONObject;
begin
  SelectCleanupScope(2);
  TDAICodexRegistration.RegisterFiles;
  LPath := TDAICodexRegistration.CodexConfigFileName;
  LLegacy := TPath.Combine(GetEnvironmentVariable('APPDATA'), '.codex\config.toml');
  LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  LSkill := TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8);
  LLegacyText := 'model="legacy-preserved"' + sLineBreak + CDAIManagedBlockBegin + sLineBreak +
    '[mcp_servers.dai]' + sLineBreak + 'url="http://127.0.0.1:7999/mcp"' + sLineBreak +
    CDAIManagedBlockEnd + sLineBreak;
  WriteFixture(LLegacy, LLegacyText);
  LSettings := CleanupSettingsFingerprint;
  LCandidate := FindCleanupCandidate('codex', LLegacy, 'dai');
  try
    Check(LCandidate.GetValue<Boolean>('removable'), 'Codex legacy AppData registration safely removable');
    Check(not LCandidate.GetValue<Boolean>('current_scope'), 'Codex legacy shared scope differs from active local 13');
    Check(TFile.ReadAllText(LLegacy, TEncoding.UTF8) = LLegacyText, 'Codex legacy scan never migrates config');
    LJson := TDAIClientRegistration.RemoveFoundRegistration(LCandidate);
    try
      Check(LJson.GetValue<Boolean>('removed'), 'Codex cleanup removes legacy AppData registration');
    finally
      LJson.Free;
    end;
  finally
    LCandidate.Free;
  end;
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'Codex legacy cleanup retains current config byte for byte');
  Check(Pos('model="legacy-preserved"', TFile.ReadAllText(LLegacy, TEncoding.UTF8)) > 0, 'Codex legacy cleanup retains user options');
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = LSkill, 'Codex legacy cleanup retains current scope shared skill');
  Check(CleanupSettingsFingerprint = LSettings, 'Codex legacy cleanup never switches current scope');
  LCandidate := FindCleanupCandidate('codex', LLegacy, 'dai', False);
  try
    Check(LCandidate = nil, 'Codex removed legacy registration disappears on rescan');
  finally
    LCandidate.Free;
  end;
end;

procedure CleanupRegistrationTests;
var
  LRoot: string;
begin
  // All supported clients resolve into this already isolated environment, never actual user files.
  LRoot := GetEnvironmentVariable('USERPROFILE');
  CleanupClientTests('claude-code', TPath.Combine(LRoot, '.claude\.claude.json'), 'json', ['mcpServers', '']);
  CleanupClientTests('claude-desktop', TPath.Combine(LRoot, 'Claude\claude_desktop_config.json'), 'json', ['mcpServers', '']);
  CleanupClientTests('gemini', TPath.Combine(LRoot, '.gemini\settings.json'), 'json', ['mcpServers', '']);
  CleanupClientTests('hermes', TPath.Combine(LRoot, '.hermes\config.yaml'), 'yaml', ['mcp_servers', '']);
  CleanupClientTests('lm-studio', TPath.Combine(LRoot, '.lmstudio\mcp.json'), 'json', ['mcpServers', '']);
  CleanupClientTests('openclaw', TPath.Combine(LRoot, '.openclaw\openclaw.json'), 'json5', ['mcp', 'servers', '']);
  CleanupCodexTests;
  CleanupCodexLegacyTests;
end;
