procedure CheckHealth(AExpected: TDAIRegistrationHealth; const AName: string);
var
  LDetails, LSettings: string;
  LVersion: Integer;
begin
  LSettings := CleanupSettingsFingerprint;
  LVersion := TDAIClientRegistration.ChangeVersion;
  Check(TDAIClientRegistration.Health(LDetails) = AExpected, AName);
  Check(LDetails <> '', AName + ' explains status');
  Check(Pos(TDAISettings.Instance.Token, LDetails) = 0, AName + ' excludes credentials');
  Check(TDAIClientRegistration.ChangeVersion = LVersion, AName + ' read keeps mutation revision');
  Check(CleanupSettingsFingerprint = LSettings, AName + ' read keeps settings and SaveCount');
end;

procedure RegistrationHealthTests;
const
  CEnvironmentNames: array[0..10] of string = ('USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'CODEX_HOME', 'CLAUDE_CONFIG_DIR',
    'GEMINI_CLI_HOME', 'HERMES_HOME', 'OPENCLAW_STATE_DIR', 'OPENCLAW_CONFIG_PATH', 'DAI_LM_STUDIO_CONFIG', 'DAI_CLAUDE_DESKTOP_CONFIG');
var
  LEnvironment: array[0..10] of string;
  LRoot, LPath, LOriginal, LLegacyPath, LBridge, LBridgeText, LCodexText: string;
  LOldToken, LOldRegistryRoot, LSettings: string;
  LIndex, LVersion, LOldPort, LCount: Integer;
  LOldShared: Boolean;
  LJson, LCandidate: TJSONObject;
begin
  for LIndex := 0 to High(CEnvironmentNames) do
    LEnvironment[LIndex] := GetEnvironmentVariable(CEnvironmentNames[LIndex]);
  LOldToken := TDAISettings.Instance.Token;
  LOldPort := TDAISettings.Instance.Port;
  LOldRegistryRoot := TDAISettings.Instance.RegistryRoot;
  LOldShared := TDAISettings.Instance.UseSharedConnectionSettings;
  LRoot := TPath.Combine(GRoot, 'health');
  ForceDirectories(LRoot);
  LBridge := TDAICodexRegistration.BridgeFileName;
  LBridgeText := TFile.ReadAllText(LBridge, TEncoding.UTF8);
  try
    SetEnvironmentVariable('USERPROFILE', PChar(LRoot));
    SetEnvironmentVariable('APPDATA', PChar(TPath.Combine(LRoot, 'AppData\Roaming')));
    SetEnvironmentVariable('LOCALAPPDATA', PChar(TPath.Combine(LRoot, 'AppData\Local')));
    SetEnvironmentVariable('CODEX_HOME', PChar(TPath.Combine(LRoot, '.codex')));
    SetEnvironmentVariable('CLAUDE_CONFIG_DIR', PChar(TPath.Combine(LRoot, '.claude')));
    SetEnvironmentVariable('GEMINI_CLI_HOME', PChar(LRoot));
    SetEnvironmentVariable('HERMES_HOME', PChar(TPath.Combine(LRoot, '.hermes')));
    SetEnvironmentVariable('OPENCLAW_STATE_DIR', PChar(TPath.Combine(LRoot, '.openclaw')));
    SetEnvironmentVariable('OPENCLAW_CONFIG_PATH', PChar(TPath.Combine(LRoot, '.openclaw\openclaw.json')));
    SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(TPath.Combine(LRoot, '.lmstudio\mcp.json')));
    SetEnvironmentVariable('DAI_CLAUDE_DESKTOP_CONFIG', PChar(TPath.Combine(LRoot, 'Claude\claude_desktop_config.json')));
    SelectRegistrationScope(0);
    TDAISettings.Instance.Token := 'health-private-original';
    LSettings := CleanupSettingsFingerprint;
    LCount := Length(TDirectory.GetFiles(LRoot, '*', TSearchOption.soAllDirectories));
    CheckHealth(rhNotRegistered, 'empty client inventory is not registered');
    Check(Length(TDirectory.GetFiles(LRoot, '*', TSearchOption.soAllDirectories)) = LCount,
      'health creates no configuration, sidecar, skill or backup');
    Check(CleanupSettingsFingerprint = LSettings, 'empty health does not persist options');

    LVersion := TDAIClientRegistration.ChangeVersion;
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    LJson.Free;
    Check(TDAIClientRegistration.ChangeVersion > LVersion, 'register invalidates cached health');
    CheckHealth(rhCurrent, 'one matching client sufficient despite missing other clients');
    LPath := GetEnvironmentVariable('DAI_LM_STUDIO_CONFIG');
    TDAISettings.Instance.Token := 'health-private-new';
    LJson := TDAIClientRegistration.RegisterFiles('claude-code');
    LJson.Free;
    CheckHealth(rhUpdateRecommended, 'old owned registration wins over another current client');
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    LJson.Free;
    CheckHealth(rhCurrent, 're-register repairs old connection settings');
    LOriginal := TFile.ReadAllText(LPath, TEncoding.UTF8);
    WriteFixture(LPath, StringReplace(LOriginal, 'health-private-new', 'health-secret-manual-edit', []));
    CheckHealth(rhCheckRecommended, 'modified owned registration wins over current other client');
    WriteFixture(LPath, LOriginal);
    CheckHealth(rhCurrent, 'restored owned registration is current');
    LVersion := TDAIClientRegistration.ChangeVersion;
    LJson := TDAIClientRegistration.UnregisterFiles('lm-studio');
    LJson.Free;
    Check(TDAIClientRegistration.ChangeVersion > LVersion, 'unregister invalidates cached health');
    LCandidate := FindCleanupCandidate('claude-code', TPath.Combine(LRoot, '.claude\.claude.json'), 'dai');
    try
      LVersion := TDAIClientRegistration.ChangeVersion;
      LJson := TDAIClientRegistration.RemoveFoundRegistration(LCandidate);
      LJson.Free;
      Check(TDAIClientRegistration.ChangeVersion > LVersion, 'cleanup invalidates cached health');
    finally
      LCandidate.Free;
    end;
    CheckHealth(rhNotRegistered, 'no selected scope registrations remain after cleanup');
    LVersion := TDAIClientRegistration.ChangeVersion;
    LJson := TDAIClientRegistration.RemoveFoundRegistration(nil);
    LJson.Free;
    Check(TDAIClientRegistration.ChangeVersion > LVersion, 'failed cleanup attempt also invalidates health');

    LVersion := TDAIClientRegistration.ChangeVersion;
    TDAICodexRegistration.RegisterFiles;
    Check(TDAIClientRegistration.ChangeVersion > LVersion, 'direct Codex register invalidates aggregate health');
    CheckHealth(rhCurrent, 'current Codex registration and skill are current');
    LOriginal := TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8);
    WriteFixture(TDAICodexRegistration.SkillFileName, LOriginal + 'Historical skill text.' + sLineBreak);
    CheckHealth(rhUpdateRecommended, 'historical managed Codex skill recommends update');
    LVersion := TDAIClientRegistration.ChangeVersion;
    TDAICodexRegistration.MigrateSkillFiles;
    Check(TDAIClientRegistration.ChangeVersion > LVersion, 'skill migration invalidates health');
    CheckHealth(rhCurrent, 'skill migration repairs current Codex registration');
    WriteFixture(TDAICodexRegistration.SkillFileName, 'foreign skill health-secret-manual-edit');
    CheckHealth(rhCheckRecommended, 'foreign skill beside owned Codex registration requires check');
    LVersion := TDAIClientRegistration.ChangeVersion;
    try
      TDAICodexRegistration.RegisterFiles;
    except
      on E: EInvalidOperation do ;
    end;
    Check(TDAIClientRegistration.ChangeVersion > LVersion, 'failed direct register invalidates health');
    WriteFixture(TDAICodexRegistration.SkillFileName, LOriginal);
    TFile.Delete(LBridge);
    CheckHealth(rhUpdateRecommended, 'missing bridge for existing registration recommends update');
    LVersion := TDAIClientRegistration.ChangeVersion;
    TDAICodexRegistration.UnregisterFiles;
    Check(TDAIClientRegistration.ChangeVersion > LVersion, 'direct unregister invalidates aggregate health');
    CheckHealth(rhNotRegistered, 'missing bridge with no registrations stays not registered');
    WriteFixture(LBridge, LBridgeText);

    LLegacyPath := TPath.Combine(GetEnvironmentVariable('APPDATA'), '.codex\config.toml');
    WriteFixture(LLegacyPath, CDAIManagedBlockBegin + sLineBreak + '[mcp_servers.dai]' + sLineBreak +
      'url = "http://legacy"' + sLineBreak + CDAIManagedBlockEnd + sLineBreak);
    CheckHealth(rhUpdateRecommended, 'legacy managed shared Codex entry recommends migration');
    SelectRegistrationScope(2);
    CheckHealth(rhNotRegistered, 'legacy shared registration does not apply to local scope');
    TFile.Delete(LLegacyPath);
    SelectRegistrationScope(1);
    TDAICodexRegistration.RegisterFiles;
    SelectRegistrationScope(2);
    CheckHealth(rhNotRegistered, 'other IDE scope registration does not imply active scope registered');
    LPath := TDAICodexRegistration.CodexConfigFileName;
    LCodexText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    WriteFixture(LPath, LCodexText + '[mcp_servers.dai_bds37_0]' + sLineBreak + 'url = "http://manual"' + sLineBreak);
    CheckHealth(rhCheckRecommended, 'unmarked active scope Codex registration requires check');
    WriteFixture(LPath, LCodexText);
    WriteFixture(LPath, LCodexText + '# >>> DAI managed: dai_bds37_0 >>>' + sLineBreak +
      '[mcp_servers.dai_bds37_0]' + sLineBreak + 'url="health-secret-manual-edit"' + sLineBreak);
    CheckHealth(rhCheckRecommended, 'incomplete active Codex marker requires check');
    WriteFixture(LPath, LCodexText);
    LCandidate := FindCleanupCandidate('codex', LPath, 'dai_bds22_0');
    try
      LVersion := TDAIClientRegistration.ChangeVersion;
      LJson := TDAICodexRegistration.RemoveFoundRegistration(LCandidate);
      LJson.Free;
      Check(TDAIClientRegistration.ChangeVersion > LVersion, 'direct Codex cleanup invalidates health');
    finally
      LCandidate.Free;
    end;
    CheckHealth(rhNotRegistered, 'cleanup of other Codex scope keeps active scope unregistered');
  finally
    WriteFixture(LBridge, LBridgeText);
    for LIndex := 0 to High(CEnvironmentNames) do
      SetEnvironmentVariable(PChar(CEnvironmentNames[LIndex]), PChar(LEnvironment[LIndex]));
    TDAISettings.Instance.Port := LOldPort;
    TDAISettings.Instance.Token := LOldToken;
    TDAISettings.Instance.RegistryRoot := LOldRegistryRoot;
    TDAISettings.Instance.UseSharedConnectionSettings := LOldShared;
  end;
end;
