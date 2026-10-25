program TestClientRegistration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  h5u.DAI.Localization,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Hash,
  System.Generics.Collections,
  Winapi.Windows,
  h5u.DAI.Settings in 'RegistrationTests\h5u.DAI.Settings.pas',
  h5u.DAI.Consts in '..\Source\h5u.DAI.Consts.pas',
  h5u.DAI.Clients.SafeFiles in '..\Source\h5u.DAI.Clients.SafeFiles.pas',
  h5u.DAI.Clients.ConfigText in '..\Source\h5u.DAI.Clients.ConfigText.pas',
  h5u.DAI.Codex.Registration in '..\Source\h5u.DAI.Codex.Registration.pas',
  h5u.DAI.Clients.Registration in '..\Source\h5u.DAI.Clients.Registration.pas';

var
  GCount: Integer;
  GRoot: string;

procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    raise Exception.Create('FAILED: ' + AName);
  Inc(GCount);
end;

procedure CheckLauncherVersion(const AArguments: TJSONArray; const AName: string);
var
  LIndex, LMatches: Integer;
begin
  Check(Assigned(AArguments), AName + ' argument array present');
  LMatches := 0;
  for LIndex := 0 to AArguments.Count - 1 do
    if AArguments.Items[LIndex].Value = '--dai-version' then
    begin
      Inc(LMatches);
      Check((LIndex + 1 < AArguments.Count) and (AArguments.Items[LIndex + 1].Value = CDAIVersion),
        AName + ' registered version matches current DAI');
    end;
  Check(LMatches = 1, AName + ' version argument occurs exactly once');
end;

procedure CheckTextLauncherVersion(const AText, APrefix, AName: string);
var
  LLine: string;
  LValue: TJSONValue;
begin
  for LLine in AText.Split([#10]) do
    if LLine.Trim.StartsWith(APrefix) then
    begin
      LValue := TJSONObject.ParseJSONValue(Copy(LLine.Trim, Length(APrefix) + 1, MaxInt));
      try
        Check(LValue is TJSONArray, AName + ' argument array parses');
        CheckLauncherVersion(TJSONArray(LValue), AName);
      finally
        LValue.Free;
      end;
      Exit;
    end;
  Check(False, AName + ' arguments present');
end;

procedure CheckBridgeArguments(const AArguments: TJSONArray; const AURL, AName: string);
begin
  Check(Assigned(AArguments), AName + ' argument array present');
  Check(AArguments.Count = 2, AName + ' plain bridge accepts exactly two arguments');
  Check(AArguments.Items[0].Value = '--url', AName + ' plain bridge URL option');
  Check(AArguments.Items[1].Value = AURL, AName + ' plain bridge target');
end;

procedure ExpectConflict(const AText, AFormat: string; const AName: string);
var
  LEntry: string;
  LConflict: Boolean;
begin
  LConflict := False;
  try
    TDAIClientConfigText.ExtractEntry(AText, AFormat, ['mcpServers', 'dai'], LEntry);
  except
    on E: EDAIClientConfigConflict do LConflict := True;
  end;
  Check(LConflict, AName);
end;

function ClientStatus(const AJson: TJSONObject): string;
begin
  Result := TJSONObject(TJSONArray(AJson.GetValue('clients')).Items[0]).GetValue<string>('status');
end;

procedure ParserTests;
var
  LText: string;
  LNext: string;
  LEntry: string;
begin
  LText := '{"other": [1, true, null], "mcpServers":{"first":{"url":"x"},"last":{"command":"z"}}}';
  LNext := TDAIClientConfigText.Merge(LText, 'json', ['mcpServers', 'dai'], '{"url":"local"}', False);
  Check(Pos('"other": [1, true, null]', LNext) > 0, 'JSON unrelated text preserved');
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'json', ['mcpServers', 'dai'], LEntry), 'JSON insertion parses');
  Check(LEntry = '{"url":"local"}', 'JSON generated value exact');
  LNext := TDAIClientConfigText.Merge(LNext, 'json', ['mcpServers', 'dai'], '{"url":"updated"}', False);
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'json', ['mcpServers', 'dai'], LEntry) and
    (LEntry = '{"url":"updated"}'), 'JSON replace');
  LNext := TDAIClientConfigText.Merge(LNext, 'json', ['mcpServers', 'dai'], '', True);
  Check(not TDAIClientConfigText.ExtractEntry(LNext, 'json', ['mcpServers', 'dai'], LEntry), 'JSON removal');
  Check(Pos('"last":{"command":"z"}', LNext) > 0, 'JSON sibling retained');
  LNext := TDAIClientConfigText.Merge('{}', 'json', ['mcp', 'servers', 'dai'], '{"url":"x"}', False);
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'json', ['mcp', 'servers', 'dai'], LEntry), 'JSON nested missing keys');
  LText := '{ // retained comment' + #10 + ' mcp: {servers: {other: {url: ''http://else''},}}, trailing: true,}';
  LNext := TDAIClientConfigText.Merge(LText, 'json5', ['mcp', 'servers', 'dai'], '{"url":"x"}', False);
  Check(Pos('// retained comment', LNext) > 0, 'JSON5 comment retained');
  Check(Pos('url: ''http://else''', LNext) > 0, 'JSON5 single quote retained');
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'json5', ['mcp', 'servers', 'dai'], LEntry), 'JSON5 insertion');
  LNext := TDAIClientConfigText.Merge(LNext, 'json5', ['mcp', 'servers', 'dai'], '', True);
  Check(not TDAIClientConfigText.ExtractEntry(LNext, 'json5', ['mcp', 'servers', 'dai'], LEntry), 'JSON5 removal with trailing comma');
  LNext := TDAIClientConfigText.Merge('{"mcpServers":{"dai":{},"other":{}}}', 'json', ['mcpServers','dai'], '', True);
  Check(not TDAIClientConfigText.ExtractEntry(LNext, 'json', ['mcpServers','dai'], LEntry), 'JSON remove first property');
  LNext := TDAIClientConfigText.Merge('{"mcpServers":{"dai":{}}}', 'json', ['mcpServers','dai'], '', True);
  Check(not TDAIClientConfigText.ExtractEntry(LNext, 'json', ['mcpServers','dai'], LEntry), 'JSON remove only property');
  ExpectConflict('{"mcpServers":{},"mcpServers":{}}', 'json', 'JSON duplicate keys rejected');
  ExpectConflict('{mcpServers:{dai:doEvil()}}', 'json5', 'JSON5 executable input rejected');
  ExpectConflict('{"mcpServers":{}} extra', 'json', 'JSON trailing input rejected');
  ExpectConflict('{"a":1,}', 'json', 'JSON trailing comma rejected');
  ExpectConflict('{"a":"unterminated}', 'json', 'JSON broken string rejected');
  ExpectConflict('{"mcpServers":false}', 'json', 'JSON nonobject MCP rejected');
  LText := 'model: "sample"' + #13#10 + 'mcp_servers:' + #13#10 + '  other:' + #13#10 + '    url: "http://else"' + #13#10 +
    'features:' + #13#10 + '  tools: true' + #13#10;
  LNext := TDAIClientConfigText.Merge(LText, 'yaml', ['mcp_servers','dai'], 'dai:' + #10 + '  url: "http://local"', False);
  Check(Pos('    url: "http://else"', LNext) > 0, 'YAML foreign entry retained');
  Check(Pos('features:' + #13#10 + '  tools: true', LNext) > 0, 'YAML following root retained');
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'yaml', ['mcp_servers','dai'], LEntry), 'YAML insertion');
  LNext := TDAIClientConfigText.Merge(LNext, 'yaml', ['mcp_servers','dai_start'],
    'dai_start:' + #10 + '  command: "launcher.exe"' + #10 + '  args: ["--launcher"]', False);
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'yaml', ['mcp_servers','dai_start'], LEntry) and
    (Pos('launcher.exe', LEntry) > 0), 'YAML launcher independent insertion');
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'yaml', ['mcp_servers','dai'], LEntry) and
    (Pos('http://local', LEntry) > 0), 'YAML HTTP retained beside launcher');
  LNext := TDAIClientConfigText.Merge(LNext, 'yaml', ['mcp_servers','dai_start'], '', True);
  Check(not TDAIClientConfigText.ExtractEntry(LNext, 'yaml', ['mcp_servers','dai_start'], LEntry), 'YAML launcher independent removal');
  LNext := TDAIClientConfigText.Merge(LNext, 'yaml', ['mcp_servers','dai'], '', True);
  Check(not TDAIClientConfigText.ExtractEntry(LNext, 'yaml', ['mcp_servers','dai'], LEntry), 'YAML removal');
  LNext := TDAIClientConfigText.Merge('mcp_servers: {}' + #10, 'yaml', ['mcp_servers','dai'], 'dai:' + #10 + '  url: "x"', False);
  Check(TDAIClientConfigText.ExtractEntry(LNext, 'yaml', ['mcp_servers','dai'], LEntry), 'YAML empty mapping');
  LNext := TDAIClientConfigText.Merge('mcp_servers: {} # keep this comment' + #10, 'yaml',
    ['mcp_servers','dai'], 'dai:' + #10 + '  url: "x"', False);
  Check(Pos('# keep this comment', LNext) > 0, 'YAML header comment retained');
  TFile.WriteAllText(TPath.Combine(GRoot, 'yaml-generated-fixture.yaml'), LNext, TEncoding.UTF8);
  ExpectConflict('mcp_servers:' + #10 + '  dai: {}' + #10 + '  dai: {}', 'yaml', 'YAML duplicate server rejected');
  ExpectConflict('mcp_servers: *servers', 'yaml', 'YAML alias rejected');
  ExpectConflict('mcp_servers:' + #10 + #9 + 'dai: {}', 'yaml', 'YAML tabs rejected');
  ExpectConflict('prompt: "hello' + #10 + 'mcp_servers:' + #10 + '  dai: {}' + #10 + 'end: "', 'yaml', 'YAML multiline string cannot mask mapping');
  ExpectConflict('mcp_servers: {}' + #10 + '  dai: {}', 'yaml', 'YAML inline mapping with children rejected');
end;

procedure SafeFileTests;
var
  LPath: string;
  LBackup: string;
  LConflict: Boolean;
  LBytes: TBytes;
  LHardLink: string;
  LSecuritySize: DWORD;
  LSecurity: TBytes;
  LDacl: PACL;
  LDaclPresent, LDaclDefault: BOOL;
  LControl: SECURITY_DESCRIPTOR_CONTROL;
  LRevision: DWORD;
begin
  LPath := TPath.Combine(GRoot, 'safe.json');
  TDAIClientSafeFiles.WriteTextWithBackup(LPath, '{"keep":1}');
  LBackup := TDAIClientSafeFiles.WriteTextWithBackup(LPath, '{"keep":2}', '{"keep":1}', True);
  Check(TFile.Exists(LBackup), 'backup created');
  Check(TDAIClientSafeFiles.ReadTextIfExists(LBackup) = '{"keep":1}', 'backup exact');
  LConflict := False;
  try
    TDAIClientSafeFiles.WriteTextWithBackup(LPath, '{"lost":1}', '{"keep":1}', True);
  except
    on E: EDAIClientConfigConflict do LConflict := True;
  end;
  Check(LConflict, 'stale source rejected');
  Check(TDAIClientSafeFiles.ReadTextIfExists(LPath) = '{"keep":2}', 'concurrent contents retained');
  LConflict := False;
  try
    TDAIClientSafeFiles.DeleteFileWithBackup(LPath, '{"keep":1}', True);
  except
    on E: EDAIClientConfigConflict do LConflict := True;
  end;
  Check(LConflict and TFile.Exists(LPath), 'stale delete refused');
  LHardLink := TPath.Combine(GRoot, 'linked.json');
  if not CreateHardLink(PChar(LHardLink), PChar(LPath), nil) then
    RaiseLastOSError;
  LConflict := False;
  try
    TDAIClientSafeFiles.WriteTextWithBackup(LPath, '{}');
  except
    on E: EDAIClientConfigConflict do LConflict := True;
  end;
  TFile.Delete(LHardLink);
  Check(LConflict, 'hardlinked configuration refused');
  LSecuritySize := 0;
  GetFileSecurity(PChar(LBackup), DACL_SECURITY_INFORMATION, nil, 0, LSecuritySize);
  SetLength(LSecurity, LSecuritySize);
  if not GetFileSecurity(PChar(LBackup), DACL_SECURITY_INFORMATION, @LSecurity[0], LSecuritySize, LSecuritySize) then
    RaiseLastOSError;
  if not GetSecurityDescriptorDacl(@LSecurity[0], LDaclPresent, LDacl, LDaclDefault) then
    RaiseLastOSError;
  if not GetSecurityDescriptorControl(@LSecurity[0], LControl, LRevision) then
    RaiseLastOSError;
  Check(LDaclPresent and (LDacl <> nil) and (LDacl.AceCount = 2) and ((LControl and SE_DACL_PROTECTED) <> 0), 'backup DACL private and protected');
  SetFileAttributes(PChar(LPath), FILE_ATTRIBUTE_READONLY);
  LConflict := False;
  try
    TDAIClientSafeFiles.WriteTextWithBackup(LPath, '{}');
  except
    on E: EDAIClientConfigConflict do LConflict := True;
  end;
  SetFileAttributes(PChar(LPath), FILE_ATTRIBUTE_NORMAL);
  Check(LConflict, 'read-only file rejected');
  LPath := TPath.Combine(GRoot, 'invalid-utf8.json');
  TFile.WriteAllBytes(LPath, TBytes.Create($C3, $28));
  LConflict := False;
  try
    TDAIClientSafeFiles.ReadTextIfExists(LPath);
  except
    on E: EDAIClientConfigConflict do LConflict := True;
  end;
  Check(LConflict, 'invalid UTF8 rejected');
  LPath := TPath.Combine(GRoot, 'bom.json');
  TFile.WriteAllBytes(LPath, TBytes.Create($EF, $BB, $BF, $7B, $7D));
  TDAIClientSafeFiles.WriteTextWithBackup(LPath, '{"bom":true}');
  LBytes := TFile.ReadAllBytes(LPath);
  Check((LBytes[0] = $EF) and (LBytes[1] = $BB) and (LBytes[2] = $BF), 'UTF8 BOM retained');
end;

procedure RegistrationTests;
var
  LClient: string;
  LJson: TJSONObject;
  LStatusText: string;
  LPath: string;
  LText: string;
  LBridge: string;
begin
  LBridge := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'DAI.McpBridge.exe');
  if TFile.Exists(LBridge) then
  begin
    if TFile.ReadAllText(LBridge, TEncoding.UTF8) <> 'test fixture, never executed' then
      raise Exception.Create('The isolated test bridge fixture path is occupied by a foreign file.');
    TFile.Delete(LBridge);
  end;
  SetEnvironmentVariable('USERPROFILE', PChar(GRoot));
  SetEnvironmentVariable('APPDATA', PChar(TPath.Combine(GRoot, 'AppData\Roaming')));
  SetEnvironmentVariable('LOCALAPPDATA', PChar(TPath.Combine(GRoot, 'AppData\Local')));
  SetEnvironmentVariable('CODEX_HOME', PChar(TPath.Combine(GRoot, '.codex')));
  SetEnvironmentVariable('CLAUDE_CONFIG_DIR', PChar(TPath.Combine(GRoot, '.claude')));
  SetEnvironmentVariable('GEMINI_CLI_HOME', PChar(GRoot));
  SetEnvironmentVariable('HERMES_HOME', PChar(TPath.Combine(GRoot, '.hermes')));
  SetEnvironmentVariable('OPENCLAW_STATE_DIR', PChar(TPath.Combine(GRoot, '.openclaw')));
  SetEnvironmentVariable('OPENCLAW_CONFIG_PATH', PChar(TPath.Combine(GRoot, '.openclaw\openclaw.json')));
  SetEnvironmentVariable('OPENCLAW_CONFIG_READONLY', nil);
  SetEnvironmentVariable('OPENCLAW_NIX_MODE', nil);
  SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(TPath.Combine(GRoot, '.lmstudio\mcp.json')));
  SetEnvironmentVariable('DAI_CLAUDE_DESKTOP_CONFIG', PChar(TPath.Combine(GRoot, 'Claude\claude_desktop_config.json')));
  LJson := TDAIClientRegistration.RegisterFiles('claude-desktop');
  try
    Check(ClientStatus(LJson) = 'missing_bridge', 'Desktop requires native bridge');
    Check(not TFile.Exists(TPath.Combine(GRoot, 'Claude\claude_desktop_config.json')), 'missing bridge makes no invalid config');
  finally
    LJson.Free;
  end;
  LBridge := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'DAI.McpBridge.exe');
  // This file proves only presence detection; the native bridge is exercised separately by the bridge smoke test.
  TFile.WriteAllText(LBridge, 'test fixture, never executed', TEncoding.UTF8);
  LJson := TDAIClientRegistration.RegisterFiles('claude-desktop');
  try
    Check(ClientStatus(LJson) = 'configured', 'Desktop stdio bridge registered');
    Check(Pos(TDAISettings.Instance.Token, LJson.ToJSON) = 0, 'Desktop status token redacted');
  finally
    LJson.Free;
  end;
  LText := TFile.ReadAllText(TPath.Combine(GRoot, 'Claude\claude_desktop_config.json'), TEncoding.UTF8);
  Check(Pos('DAI_MCP_TOKEN', LText) > 0, 'Desktop token passed through environment');
  Check(Pos('--url', LText) > 0, 'Desktop bridge URL argument');
  LJson := TDAIClientRegistration.UnregisterFiles('claude-desktop');
  try
    Check(ClientStatus(LJson) = 'removed', 'Desktop bridge registration removed');
  finally
    LJson.Free;
  end;
  for LClient in ['claude-code','gemini','hermes','lm-studio','openclaw'] do
  begin
    LJson := TDAIClientRegistration.RegisterFiles(LClient);
    try
      Check(ClientStatus(LJson) = 'configured', LClient + ' register');
      Check(Pos(TDAISettings.Instance.Token, LJson.ToJSON) = 0, LClient + ' token redacted');
    finally
      LJson.Free;
    end;
    LJson := TDAIClientRegistration.Status(LClient);
    try
      Check(ClientStatus(LJson) = 'registered', LClient + ' ownership status');
    finally
      LJson.Free;
    end;
    LJson := TDAIClientRegistration.RegisterFiles(LClient);
    try
      Check(ClientStatus(LJson) = 'unchanged', LClient + ' idempotent registration');
    finally
      LJson.Free;
    end;
    TDAISettings.Instance.Token := TDAISettings.Instance.Token + '-rotated';
    LJson := TDAIClientRegistration.RegisterFiles(LClient);
    try
      Check(ClientStatus(LJson) = 'configured', LClient + ' token rotation');
    finally
      LJson.Free;
    end;
    LJson := TDAIClientRegistration.UnregisterFiles(LClient);
    try
      Check(ClientStatus(LJson) = 'removed', LClient + ' unregister');
    finally
      LJson.Free;
    end;
  end;
  LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
  LJson.Free;
  LPath := TPath.Combine(GRoot, '.lmstudio\mcp.json');
  LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  LText := StringReplace(LText, '7331', '7332', []);
  TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
  LJson := TDAIClientRegistration.UnregisterFiles('lm-studio');
  try
    Check(ClientStatus(LJson) = 'conflict', 'modified owned entry is retained');
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'manual edit bytes retained');
  finally
    LJson.Free;
  end;
  LJson := TDAIClientRegistration.RegisterFiles('codex');
  try
    Check(ClientStatus(LJson) = 'registered', 'Codex delegation');
    LStatusText := LJson.ToJSON;
    Check(Pos(TDAISettings.Instance.Token, LStatusText) = 0, 'Codex status redacted');
  finally
    LJson.Free;
  end;
  LJson := TDAIClientRegistration.UnregisterFiles('codex');
  LJson.Free;
  LJson := TDAIClientRegistration.Status('eigent');
  try
    Check(ClientStatus(LJson) = 'manual_configuration', 'Eigent uses documented manual route');
  finally
    LJson.Free;
  end;
  LPath := TPath.Combine(GRoot, '.gemini\settings.json');
  TFile.WriteAllText(LPath, '{}', TEncoding.UTF8);
  TFile.WriteAllText(LPath + '.dai-registration.json', '{"owner":"other"}', TEncoding.UTF8);
  LJson := TDAIClientRegistration.RegisterFiles('gemini');
  try
    Check(ClientStatus(LJson) = 'conflict', 'foreign sidecar without entry is retained');
    Check(TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8) = '{"owner":"other"}', 'foreign sidecar text retained');
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = '{}', 'foreign sidecar blocks config write');
  finally
    LJson.Free;
  end;
end;

function RegistrationFileSnapshot: string;
var
  LFiles: TStringList;
  LFile: string;
begin
  LFiles := TStringList.Create;
  try
    for LFile in TDirectory.GetFiles(GRoot, '*', TSearchOption.soAllDirectories) do
      LFiles.Add(LFile + '=' + THashSHA2.GetHashStringFromFile(LFile));
    LFiles.Sort;
    Result := LFiles.Text;
  finally
    LFiles.Free;
  end;
end;

procedure ManualLocalizationTests;
var
  LLanguage: TDAILanguage;
  LText, LMarker, LConfig, LExpectedConfig: string;
  LPosition: Integer;
begin
  LExpectedConfig := '';
  try
    for LLanguage := Low(TDAILanguage) to High(TDAILanguage) do
    begin
      DAISetLanguageForTests(LLanguage);
      LText := TDAIClientRegistration.ManualRegistrationInfo('codex', 18475, 'unicode-ä-日本語', True);
      LMarker := DAIText('Konfiguration zum Übernehmen:', 'Configuration to copy:', 'Configuration à copier :', 'コピーする設定:') + sLineBreak;
      LPosition := Pos(LMarker, LText);
      Check(LPosition > 0, 'manual registration heading follows selected IDE language');
      Check(Pos(DAIText('Manuelle MCP-Registrierung', 'Manual MCP registration', 'Inscription MCP manuelle', 'MCP の手動登録'), LText) = 1,
        'manual registration title follows selected IDE language');
      LConfig := Copy(LText, LPosition + Length(LMarker), MaxInt);
      if LExpectedConfig = '' then
        LExpectedConfig := LConfig
      else
        Check(LConfig = LExpectedConfig, 'localization preserves the complete machine configuration verbatim');
    end;
  finally
    DAISetLanguageForTests(dlGerman);
  end;
end;

procedure ManualRegistrationInfoTests;
const
  CPort = 18475;
  CToken = 'manual-test-"quoted"-\backslash';
  CMarker = 'Konfiguration zum Übernehmen:' + sLineBreak;
var
  LSnapshot, LText, LConfig, LEntry, LLauncher, LClient, LScopeName, LToken: string;
  LOldPort, LOldSaves, LOldVersion, LMarkerPosition: Integer;
  LOldShared, LRejected: Boolean;
  LKeys: TArray<string>;
  LJson: TJSONObject;
  LArgs: TJSONArray;
  LIndex: Integer;
begin
  LSnapshot := RegistrationFileSnapshot;
  LOldPort := TDAISettings.Instance.Port;
  LToken := TDAISettings.Instance.Token;
  LOldShared := TDAISettings.Instance.UseSharedConnectionSettings;
  LOldSaves := TDAISettings.Instance.SaveCount;
  LOldVersion := TDAIClientRegistration.ChangeVersion;
  for LClient in ['codex', 'claude-code', 'claude-desktop', 'gemini', 'hermes', 'lm-studio', 'openclaw', 'eigent', 'gemini-desktop', 'other-client', ''] do
  begin
    LText := TDAIClientRegistration.ManualRegistrationInfo(LClient, CPort, CToken, False);
    LScopeName := DAIRegistrationServerName(False, TDAISettings.Instance.RegistryRoot);
    Check(Pos('http://127.0.0.1:' + IntToStr(CPort) + '/mcp', LText) > 0, LClient + ' manual HTTP uses draft port');
    Check(Pos('Authorization: Bearer ' + CToken, LText) > 0, LClient + ' manual bearer uses draft token');
    Check(Pos('Servername: ' + LScopeName + sLineBreak, LText) > 0, LClient + ' manual server uses draft scope');
    Check(Pos(LScopeName + '_start', LText) > 0, LClient + ' manual launcher uses draft scope');
    Check(Pos(TDAICodexRegistration.HostIDEExecutable, LText) > 0, LClient + ' manual launcher identifies host IDE');
    LMarkerPosition := Pos(CMarker, LText);
    Check(LMarkerPosition > 0, LClient + ' manual configuration is copyable');
    LConfig := Copy(LText, LMarkerPosition + Length(CMarker), MaxInt);
    if LClient = 'codex' then
    begin
      Check(Pos('[mcp_servers.' + LScopeName + ']', LConfig) > 0, 'manual Codex HTTP TOML section');
      Check(Pos('[mcp_servers.' + LScopeName + '_start]', LConfig) > 0, 'manual Codex launcher TOML section');
      Check(Pos('http_headers = { Authorization = ', LConfig) > 0, 'manual Codex HTTP header native schema');
      Check(Pos('env = { DAI_MCP_TOKEN = ', LConfig) > 0, 'manual Codex launcher environment native schema');
      Check(Pos('\"quoted\"', LConfig) > 0, 'manual Codex TOML escapes token quotes');
      CheckTextLauncherVersion(LConfig, 'args = ', 'manual Codex launcher');
      Continue;
    end;
    if LClient = 'hermes' then
      LKeys := ['mcp_servers', LScopeName]
    else if LClient = 'openclaw' then
      LKeys := ['mcp', 'servers', LScopeName]
    else
      LKeys := ['mcpServers', LScopeName];
    if LClient = 'hermes' then
    begin
      Check(TDAIClientConfigText.ExtractEntry(LConfig, 'yaml', LKeys, LEntry), 'manual Hermes HTTP YAML parses');
      Check(Pos('Authorization: ', LEntry) > 0, 'manual Hermes HTTP header native schema');
      LKeys[High(LKeys)] := LScopeName + '_start';
      Check(TDAIClientConfigText.ExtractEntry(LConfig, 'yaml', LKeys, LLauncher), 'manual Hermes launcher YAML parses');
      Check(Pos('DAI_MCP_TOKEN: ', LLauncher) > 0, 'manual Hermes launcher environment native schema');
      CheckTextLauncherVersion(LLauncher, 'args: ', 'manual Hermes launcher');
      Continue;
    end;
    Check(TDAIClientConfigText.ExtractEntry(LConfig, 'json', LKeys, LEntry), LClient + ' manual native JSON parses');
    LJson := TJSONObject.ParseJSONValue(LEntry) as TJSONObject;
    try
      if LClient = 'gemini' then
        Check(LJson.GetValue<string>('httpUrl') = 'http://127.0.0.1:18475/mcp', 'manual Gemini httpUrl native schema')
      else if (LClient = 'claude-code') or (LClient = 'lm-studio') or (LClient = 'openclaw') then
        Check(LJson.GetValue<TJSONObject>('headers').GetValue<string>('Authorization') = 'Bearer ' + CToken,
          LClient + ' manual HTTP token roundtrips')
      else
      begin
        Check(LJson.GetValue<string>('command') = TDAICodexRegistration.BridgeFileName, LClient + ' manual STDIO bridge path');
        Check(LJson.GetValue<TJSONObject>('env').GetValue<string>('DAI_MCP_TOKEN') = CToken, LClient + ' manual STDIO token roundtrips');
        CheckBridgeArguments(LJson.GetValue<TJSONArray>('args'), 'http://127.0.0.1:18475/mcp', LClient + ' manual bridge');
      end;
    finally
      LJson.Free;
    end;
    LKeys[High(LKeys)] := LScopeName + '_start';
    Check(TDAIClientConfigText.ExtractEntry(LConfig, 'json', LKeys, LLauncher), LClient + ' manual launcher JSON parses');
    LJson := TJSONObject.ParseJSONValue(LLauncher) as TJSONObject;
    try
      LArgs := LJson.GetValue<TJSONArray>('args');
      CheckLauncherVersion(LArgs, LClient + ' manual launcher');
      Check(LArgs.Items[0].Value = '--launcher', LClient + ' manual launcher uses launcher mode');
      Check(LArgs.Items[2].Value = 'http://127.0.0.1:18475/mcp', LClient + ' manual launcher uses draft URL');
      Check(LJson.GetValue<TJSONObject>('env').GetValue<string>('DAI_MCP_TOKEN') = CToken, LClient + ' manual launcher token roundtrips');
    finally
      LJson.Free;
    end;
  end;
  LText := TDAIClientRegistration.ManualRegistrationInfo('claude', CPort, CToken, True);
  Check(Pos('Servername: dai' + sLineBreak, LText) > 0, 'manual shared scope keeps dai name');
  Check(Pos('"type":"http"', LText) > 0, 'manual client alias selects actual schema');
  for LIndex := 0 to 3 do
  begin
    LRejected := False;
    try
      case LIndex of
        0: TDAIClientRegistration.ManualRegistrationInfo('', 80, CToken, True);
        1: TDAIClientRegistration.ManualRegistrationInfo('', 65536, CToken, True);
        2: TDAIClientRegistration.ManualRegistrationInfo('', CPort, '', True);
        3: TDAIClientRegistration.ManualRegistrationInfo('', CPort, 'unsafe' + #13#10 + 'header', True);
      end;
    except
      on E: EDAIClientConfigConflict do LRejected := True;
    end;
    Check(LRejected, 'manual invalid credentials rejected without output ' + IntToStr(LIndex));
  end;
  Check(TDAISettings.Instance.Port = LOldPort, 'manual info leaves actual port unchanged');
  Check(TDAISettings.Instance.Token = LToken, 'manual info leaves actual token unchanged');
  Check(TDAISettings.Instance.UseSharedConnectionSettings = LOldShared, 'manual info leaves actual scope unchanged');
  Check(TDAISettings.Instance.SaveCount = LOldSaves, 'manual info never saves settings');
  Check(TDAIClientRegistration.ChangeVersion = LOldVersion, 'manual info never changes registration revision');
  Check(RegistrationFileSnapshot = LSnapshot, 'manual info creates or changes no configuration or ownership files');
end;

procedure LauncherRegistrationTests;
var
  LJson: TJSONObject;
  LLauncher: TJSONObject;
  LValue: TJSONValue;
  LArguments: TJSONArray;
  LExpectedArguments: TArray<string>;
  LText: string;
  LEntry: string;
  LPath: string;
  LClient: string;
  LFormat: string;
  LKeys: TArray<string>;
  LIndex: Integer;
  LBuffer: array[0..32767] of Char;
  LHostLength: DWORD;
  LProfileConflict: Boolean;
  LOwnership: TJSONObject;
  LOwnershipText: string;
  LInvalidOwnership: string;
  LOldLmStudioPath: string;
  LOldCodexHome: string;
  LOldPort: Integer;
  LOldToken: string;
  LBridge: string;
begin
  LHostLength := GetModuleFileName(0, LBuffer, Length(LBuffer));
  Check((LHostLength > 0) and (TDAICodexRegistration.HostIDEExecutable = string(LBuffer)), 'launcher host is process EXE, not package');
  Check(TDAICodexRegistration.IDEProfileFromCommandLine('"C:\Studio\bin\bds.exe" -pDelphi project.dproj') = '',
    'default IDE has no inferred profile');
  Check(TDAICodexRegistration.IDEProfileFromCommandLine('"C:\Studio\bin\bds.exe" -rDAITest -pDelphi') = 'DAITest',
    'attached explicit IDE profile');
  Check(TDAICodexRegistration.IDEProfileFromCommandLine('"C:\Studio\bin\bds.exe" -r "Test Profile" project.dproj') = 'Test Profile',
    'quoted separate IDE profile');
  Check(TDAICodexRegistration.IDEProfileFromCommandLine('bds.exe -RCaseProfile') = 'CaseProfile',
    'profile value casing retained');
  LProfileConflict := False;
  try
    TDAICodexRegistration.IDEProfileFromCommandLine('bds.exe -rOne -rTwo');
  except
    on E: EInvalidOperation do LProfileConflict := True;
  end;
  Check(LProfileConflict, 'ambiguous explicit profiles refused');
  LProfileConflict := False;
  try
    TDAICodexRegistration.IDEProfileFromCommandLine('bds.exe -r -pDelphi');
  except
    on E: EInvalidOperation do LProfileConflict := True;
  end;
  Check(LProfileConflict, 'missing explicit profile refused');
  LExpectedArguments := TDAICodexRegistration.LauncherArguments;
  Check((Length(LExpectedArguments) = 7) and (LExpectedArguments[0] = '--launcher') and
    (LExpectedArguments[3] = '--ide') and (LExpectedArguments[4] = string(LBuffer)) and
    (LExpectedArguments[5] = '--dai-version') and (LExpectedArguments[6] = CDAIVersion),
    'launcher exact host/version arguments');
  for LClient in ['claude-code','claude-desktop','gemini','hermes','lm-studio','openclaw'] do
  begin
    if LClient = 'claude-code' then LPath := TPath.Combine(GRoot, '.claude\.claude.json')
    else if LClient = 'claude-desktop' then LPath := TPath.Combine(GRoot, 'Claude\claude_desktop_config.json')
    else if LClient = 'gemini' then LPath := TPath.Combine(GRoot, '.gemini\settings.json')
    else if LClient = 'hermes' then LPath := TPath.Combine(GRoot, '.hermes\config.yaml')
    else if LClient = 'lm-studio' then LPath := TPath.Combine(GRoot, '.lmstudio\mcp.json')
    else LPath := TPath.Combine(GRoot, '.openclaw\openclaw.json');
    // Reset only isolated test fixtures left by preceding conflict tests.
    TFile.Delete(LPath);
    TFile.Delete(LPath + '.dai-registration.json');
    LFormat := 'json';
    LKeys := ['mcpServers','dai_start'];
    if LClient = 'hermes' then
    begin
      LFormat := 'yaml';
      LKeys := ['mcp_servers','dai_start'];
    end
    else if LClient = 'openclaw' then
    begin
      LFormat := 'json5';
      LKeys := ['mcp','servers','dai_start'];
    end;
    LJson := TDAIClientRegistration.RegisterFiles(LClient);
    try
      Check(ClientStatus(LJson) = 'configured', LClient + ' launcher configured');
      Check(Pos(TDAISettings.Instance.Token, LJson.ToJSON) = 0, LClient + ' launcher status token redacted');
    finally
      LJson.Free;
    end;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Check(TDAIClientConfigText.ExtractEntry(LText, LFormat, LKeys, LEntry), LClient + ' dai_start exists');
    Check((Pos('--launcher', LEntry) > 0) and (Pos('DAI_MCP_TOKEN', LEntry) > 0) and
      (Pos('Authorization', LEntry) = 0), LClient + ' launcher token environment only');
    if LFormat <> 'yaml' then
    begin
      LValue := TJSONObject.ParseJSONValue(LEntry);
      try
        Check(LValue is TJSONObject, LClient + ' launcher JSON object');
        LLauncher := TJSONObject(LValue);
        Check(LLauncher.GetValue<string>('command') = TDAICodexRegistration.BridgeFileName, LClient + ' adjacent bridge path');
        LArguments := LLauncher.GetValue<TJSONArray>('args');
        CheckLauncherVersion(LArguments, LClient + ' registered launcher');
        Check(LArguments.Count = Length(LExpectedArguments), LClient + ' launcher argument count');
        for LIndex := 0 to LArguments.Count - 1 do
          Check(LArguments.Items[LIndex].Value = LExpectedArguments[LIndex], LClient + ' launcher argument ' + IntToStr(LIndex));
        Check(LLauncher.GetValue<TJSONObject>('env').GetValue<string>('DAI_MCP_TOKEN') = TDAISettings.Instance.Token,
          LClient + ' launcher token environment');
        if LClient = 'claude-code' then
          Check(LLauncher.GetValue<string>('type') = 'stdio', 'Claude Code launcher transport');
        if LClient = 'openclaw' then
          Check(LLauncher.GetValue<string>('transport') = 'stdio', 'OpenClaw launcher transport');
      finally
        LValue.Free;
      end;
    end
    else
      CheckTextLauncherVersion(LEntry, 'args: ', LClient + ' registered launcher');
    LKeys[High(LKeys)] := 'dai';
    Check(TDAIClientConfigText.ExtractEntry(LText, LFormat, LKeys, LEntry), LClient + ' original dai retained');
    if LClient = 'claude-desktop' then
    begin
      LValue := TJSONObject.ParseJSONValue(LEntry);
      try
        Check(LValue is TJSONObject, 'Desktop dai plain bridge JSON object');
        CheckBridgeArguments(TJSONObject(LValue).GetValue<TJSONArray>('args'), 'http://127.0.0.1:7331/mcp', 'Desktop registered bridge');
      finally
        LValue.Free;
      end;
    end
    else
      Check((Pos('7331', LEntry) > 0) and (Pos('Authorization', LEntry) > 0), LClient + ' dai remains HTTP');
    LJson := TDAIClientRegistration.UnregisterFiles(LClient);
    try
      Check(ClientStatus(LJson) = 'removed', LClient + ' both entries removed');
    finally
      LJson.Free;
    end;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Check(not TDAIClientConfigText.ExtractEntry(LText, LFormat, LKeys, LEntry), LClient + ' dai removal');
    LKeys[High(LKeys)] := 'dai_start';
    Check(not TDAIClientConfigText.ExtractEntry(LText, LFormat, LKeys, LEntry), LClient + ' launcher removal');
  end;
  LOldLmStudioPath := GetEnvironmentVariable('DAI_LM_STUDIO_CONFIG');
  LOldCodexHome := GetEnvironmentVariable('CODEX_HOME');
  LOldPort := TDAISettings.Instance.Port;
  LOldToken := TDAISettings.Instance.Token;
  try
    LPath := TPath.Combine(GRoot, 'launcher-migration\mcp.json');
    SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(LPath));
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    LJson.Free;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    LText := TDAIClientConfigText.Merge(LText, 'json', ['mcpServers','dai_start'], '', True);
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    LOwnership := TJSONObject.ParseJSONValue(TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8)) as TJSONObject;
    try
      LOwnership.RemovePair('launcher_entry_sha256').Free;
      LOwnership.RemovePair('launcher_pending_sha256').Free;
      LOwnership.RemovePair('server_name').Free;
      LOwnership.RemovePair('launcher_server').Free;
      LOwnership.RemovePair('connection_scope').Free;
      LOwnership.RemovePair('registry_root').Free;
      LOwnershipText := LOwnership.ToJSON + sLineBreak;
      TFile.WriteAllText(LPath + '.dai-registration.json', LOwnershipText, TEncoding.UTF8);
    finally
      LOwnership.Free;
    end;
    LJson := TDAIClientRegistration.Status('lm-studio');
    try
      Check(ClientStatus(LJson) = 'needs_update', 'v1 sidecar with dai only needs launcher migration');
    finally
      LJson.Free;
    end;
    LText := TDAIClientConfigText.Merge(LText, 'json', ['mcpServers','dai_start'], '{"command":"foreign-launcher"}', False);
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    for LClient in ['register','unregister'] do
    begin
      if LClient = 'register' then LJson := TDAIClientRegistration.RegisterFiles('lm-studio')
      else LJson := TDAIClientRegistration.UnregisterFiles('lm-studio');
      try
        Check(ClientStatus(LJson) = 'conflict', 'v1 sidecar never owns foreign launcher ' + LClient);
        Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'foreign launcher blocks partial ' + LClient);
        Check(TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8) = LOwnershipText,
          'foreign launcher preserves ownership ' + LClient);
      finally
        LJson.Free;
      end;
    end;
    LText := TDAIClientConfigText.Merge(LText, 'json', ['mcpServers','dai_start'], '', True);
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    TDAIClientConfigText.ExtractEntry(LText, 'json', ['mcpServers','dai'], LEntry);
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'configured', 'v1 sidecar migrates without taking foreign entry');
    finally
      LJson.Free;
    end;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Check(Pos(LEntry, LText) > 0, 'v1 migration preserves original HTTP entry');
    TDAISettings.Instance.Port := 7456;
    TDAISettings.Instance.Token := 'second-test-token';
    LJson := TDAIClientRegistration.Status('lm-studio');
    try
      Check(ClientStatus(LJson) = 'needs_update', 'changed target needs update');
    finally
      LJson.Free;
    end;
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'configured', 'last explicit registration wins');
    finally
      LJson.Free;
    end;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    TDAIClientConfigText.ExtractEntry(LText, 'json', ['mcpServers','dai_start'], LEntry);
    Check((Pos('7456', LEntry) > 0) and (Pos('second-test-token', LEntry) > 0), 'launcher receives new port/token');
    TDAIClientConfigText.ExtractEntry(LText, 'json', ['mcpServers','dai'], LEntry);
    Check((Pos('7456', LEntry) > 0) and (Pos('second-test-token', LEntry) > 0), 'HTTP receives new port/token');
    LOwnership := TJSONObject.ParseJSONValue(TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8)) as TJSONObject;
    try
      LEntry := LOwnership.GetValue<string>('entry_sha256');
      LOwnership.RemovePair('pending_sha256').Free;
      LOwnership.AddPair('pending_sha256', LEntry);
      LOwnership.RemovePair('entry_sha256').Free;
      LOwnership.AddPair('entry_sha256', StringOfChar('a', 64));
      LEntry := LOwnership.GetValue<string>('launcher_entry_sha256');
      LOwnership.RemovePair('launcher_pending_sha256').Free;
      LOwnership.AddPair('launcher_pending_sha256', LEntry);
      LOwnership.RemovePair('launcher_entry_sha256').Free;
      LOwnership.AddPair('launcher_entry_sha256', StringOfChar('b', 64));
      LOwnership.RemovePair('state').Free;
      LOwnership.AddPair('state', 'pending');
      TFile.WriteAllText(LPath + '.dai-registration.json', LOwnership.ToJSON, TEncoding.UTF8);
    finally
      LOwnership.Free;
    end;
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'unchanged', 'both pending hashes recover committed config');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'pending recovery preserves config bytes');
    finally
      LJson.Free;
    end;
    LOwnership := TJSONObject.ParseJSONValue(TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8)) as TJSONObject;
    try
      Check((LOwnership.GetValue<string>('state') = 'registered') and
        (LOwnership.GetValue<string>('pending_sha256') = '') and
        (LOwnership.GetValue<string>('launcher_pending_sha256') = ''), 'pending recovery closes both ownership records');
    finally
      LOwnership.Free;
    end;
    LOwnershipText := TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8);
    LOwnership := TJSONObject.ParseJSONValue(LOwnershipText) as TJSONObject;
    try
      LOwnership.RemovePair('launcher_entry_sha256').Free;
      LOwnership.AddPair('launcher_entry_sha256', TJSONNumber.Create(7));
      LInvalidOwnership := LOwnership.ToJSON;
      TFile.WriteAllText(LPath + '.dai-registration.json', LInvalidOwnership, TEncoding.UTF8);
    finally
      LOwnership.Free;
    end;
    TFile.WriteAllText(LPath, TDAIClientConfigText.Merge(LText, 'json', ['mcpServers','dai_start'], '', True), TEncoding.UTF8);
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'conflict', 'invalid typed launcher ownership refused');
      Check(TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8) = LInvalidOwnership,
        'invalid launcher ownership exact bytes retained');
      Check(not TDAIClientConfigText.ExtractEntry(TFile.ReadAllText(LPath, TEncoding.UTF8), 'json',
        ['mcpServers','dai_start'], LEntry), 'invalid ownership creates no launcher');
    finally
      LJson.Free;
    end;
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    TFile.WriteAllText(LPath + '.dai-registration.json', LOwnershipText, TEncoding.UTF8);
    LText := TDAIClientConfigText.Merge(LText, 'json', ['mcpServers','dai_start'], '{"command":"edited-owned-launcher"}', False);
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    LJson := TDAIClientRegistration.UnregisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'conflict', 'edited owned launcher retained');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'edited launcher retains both entries');
      Check(TFile.ReadAllText(LPath + '.dai-registration.json', TEncoding.UTF8) = LOwnershipText, 'edited launcher retains sidecar');
    finally
      LJson.Free;
    end;
    LPath := TPath.Combine(GRoot, 'launcher-foreign\mcp.json');
    ForceDirectories(TPath.GetDirectoryName(LPath));
    SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(LPath));
    LText := '{"keep":true,"mcpServers":{"dai_start":{"command":"user"}}}';
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'conflict', 'foreign launcher without sidecar refused');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'foreign launcher exact bytes retained');
      Check(not TFile.Exists(LPath + '.dai-registration.json'), 'foreign launcher creates no sidecar');
    finally
      LJson.Free;
    end;
    SetEnvironmentVariable('CODEX_HOME', PChar(TPath.Combine(GRoot, 'launcher-codex')));
    TDAICodexRegistration.RegisterFiles;
    LPath := TDAICodexRegistration.CodexConfigFileName;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Check((Pos('[mcp_servers.dai]', LText) > 0) and (Pos('[mcp_servers.dai_start]', LText) > 0),
      'Codex managed block has HTTP and launcher');
    Check((Pos('--launcher', LText) > 0) and (Pos('DAI_MCP_TOKEN', LText) > 0), 'Codex launcher command/environment');
    CheckTextLauncherVersion(LText, 'args = ', 'Codex registered launcher');
    LJson := TDAICodexRegistration.Status;
    try
      Check(LJson.GetValue<Boolean>('launcher_entry_registered') and not LJson.GetValue<Boolean>('needs_update'),
        'Codex launcher registration current');
      Check(Pos(TDAISettings.Instance.Token, LJson.ToJSON) = 0, 'Codex launcher status redacted');
    finally
      LJson.Free;
    end;
    TDAISettings.Instance.Port := 7457;
    LJson := TDAICodexRegistration.Status;
    try
      Check(LJson.GetValue<Boolean>('needs_update'), 'Codex changed target detected');
    finally
      LJson.Free;
    end;
    TDAICodexRegistration.RegisterFiles;
    Check(Pos('7457', TFile.ReadAllText(LPath, TEncoding.UTF8)) > 0, 'Codex last registration target wins');
    TDAICodexRegistration.UnregisterFiles;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Check((Pos('[mcp_servers.dai]', LText) = 0) and (Pos('[mcp_servers.dai_start]', LText) = 0), 'Codex removes both managed tables');
    LText := CDAIManagedBlockBegin + sLineBreak + '[mcp_servers.dai]' + sLineBreak +
      'url = "old-target"' + sLineBreak + CDAIManagedBlockEnd + sLineBreak +
      '[mcp_servers.dai_start]' + sLineBreak + 'command = "foreign.exe"' + sLineBreak;
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    LJson := TDAICodexRegistration.Status;
    try
      Check(LJson.GetValue<Boolean>('codex_entry_registered') and
        not LJson.GetValue<Boolean>('launcher_entry_registered'), 'foreign launcher never reported as marker-owned');
    finally
      LJson.Free;
    end;
    TDAICodexRegistration.UnregisterFiles;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    Check(Pos('foreign.exe', LText) > 0, 'Codex unregister keeps unmarked foreign launcher');
    TFile.WriteAllText(LPath, '', TEncoding.UTF8);
    LText := '';
    Check((Pos('`dai_start.delphi_status`', TDAICodexRegistration.BuildSkillContent) > 0) and
      (Pos('`dai.ide_window_control`', TDAICodexRegistration.BuildSkillContent) > 0) and
      (Pos('keine erzwungene Terminierung', TDAICodexRegistration.BuildSkillContent) > 0), 'skill lifecycle and no automatic termination');
    LBridge := TDAICodexRegistration.BridgeFileName;
    TFile.Delete(LBridge);
    LJson := TDAIClientRegistration.RegisterFiles('codex');
    try
      Check(ClientStatus(LJson) = 'missing_bridge', 'Codex launcher requires bridge');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'missing Codex bridge writes no config');
    finally
      LJson.Free;
    end;
    TFile.WriteAllText(LBridge, 'test fixture, never executed', TEncoding.UTF8);
  finally
    SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(LOldLmStudioPath));
    SetEnvironmentVariable('CODEX_HOME', PChar(LOldCodexHome));
    TDAISettings.Instance.Port := LOldPort;
    TDAISettings.Instance.Token := LOldToken;
  end;
end;

procedure CodexConflict(const AText, AName: string);
var
  LConflict: Boolean;
  LPath: string;
begin
  LPath := TDAICodexRegistration.CodexConfigFileName;
  TFile.WriteAllText(LPath, AText, TEncoding.UTF8);
  LConflict := False;
  try
    TDAICodexRegistration.RegisterFiles;
  except
    on E: EInvalidOperation do LConflict := True;
  end;
  Check(LConflict, AName);
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = AText, AName + ' contents retained');
end;

procedure WriteFixture(const AFileName, AText: string);
begin
  ForceDirectories(TPath.GetDirectoryName(AFileName));
  TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
end;

procedure CodexMigrationTests;
const
  CLegacySkill = '---' + #13#10 + 'name: delphi-ide' + #13#10 + 'description: legacy DAI skill' + #13#10 +
    '---' + #13#10 + '<!-- DAI managed skill -->' + #13#10 + 'Historical generated content.' + #13#10;
var
  LProfileLegacy: string;
  LAppDataLegacy: string;
  LForeignSibling: string;
  LFileName: string;
  LConfigPath: string;
  LConfigText: string;
  LLegacyConfigPath: string;
  LLegacyConfigText: string;
  LSkillText: string;
  LBackupCount: Integer;
  LConflict: Boolean;
  LJson: TJSONObject;
begin
  LProfileLegacy := TPath.Combine(GRoot, '.agents\skills\delphi-ide\SKILL.md');
  LAppDataLegacy := TPath.Combine(GetEnvironmentVariable('APPDATA'), '.agents\skills\delphi-ide\SKILL.md');
  LForeignSibling := TPath.Combine(TPath.GetDirectoryName(LProfileLegacy), 'user-resources\notes.txt');
  LConfigPath := TDAICodexRegistration.CodexConfigFileName;
  Check(TDAICodexRegistration.SkillFileName = TPath.Combine(GRoot, '.agents\skills\dai-delphi-ide\SKILL.md'), 'DAI-prefixed skill directory');
  Check(TDAICodexRegistration.BuildSkillContent.StartsWith('---' + sLineBreak + 'name: ' + CDAISkillDirectoryName + sLineBreak),
    'skill frontmatter uses DAI name constant');
  WriteFixture(LProfileLegacy, CLegacySkill);
  WriteFixture(LAppDataLegacy, CLegacySkill);
  WriteFixture(LForeignSibling, 'foreign resource');
  LJson := TDAICodexRegistration.Status;
  try
    Check(LJson.GetValue<Boolean>('legacy_user_profile_skill_registered'), 'profile legacy skill detected');
    Check(LJson.GetValue<Boolean>('legacy_application_data_skill_registered'), 'AppData legacy skill detected');
    Check(LJson.GetValue<Boolean>('legacy_skill_registered'), 'legacy skill status aggregates both roots');
    Check(LJson.GetValue<string>('legacy_user_profile_skill_file') = LProfileLegacy, 'profile legacy path exposed');
    Check(LJson.GetValue<string>('legacy_skill_file') = LAppDataLegacy, 'AppData legacy path exposed');
  finally
    LJson.Free;
  end;
  LConfigText := TFile.ReadAllText(LConfigPath, TEncoding.UTF8);
  LLegacyConfigPath := TPath.Combine(GetEnvironmentVariable('APPDATA'), '.codex\config.toml');
  LLegacyConfigText := CDAIManagedBlockBegin + #13#10 + '[mcp_servers.dai]' + #13#10 + 'url = "http://legacy"' + #13#10 +
    CDAIManagedBlockEnd + #13#10;
  WriteFixture(LLegacyConfigPath, LLegacyConfigText);
  TDAICodexRegistration.MigrateSkillFiles;
  Check(TFile.ReadAllText(LConfigPath, TEncoding.UTF8) = LConfigText, 'skill-only migration retains current shared config');
  Check(TFile.ReadAllText(LLegacyConfigPath, TEncoding.UTF8) = LLegacyConfigText, 'skill-only migration retains legacy shared config');
  Check(not TFile.Exists(LProfileLegacy) and not TFile.Exists(LAppDataLegacy), 'skill-only migration cleans both own legacy roots');
  LJson := TDAIClientRegistration.RegisterFiles('codex');
  try
    Check(ClientStatus(LJson) = 'registered', 'generic registration migrates Codex skill');
  finally
    LJson.Free;
  end;
  LSkillText := TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8);
  Check(LSkillText = TDAICodexRegistration.BuildSkillContent, 'new skill receives current generated content');
  Check(not TFile.Exists(LProfileLegacy), 'profile legacy own skill removed after write');
  Check(not TFile.Exists(LAppDataLegacy), 'AppData legacy own skill removed after write');
  Check(TFile.ReadAllText(LForeignSibling, TEncoding.UTF8) = 'foreign resource', 'legacy foreign subdirectory retained');
  for LFileName in [LProfileLegacy, LAppDataLegacy] do
  begin
    Check(Length(TDirectory.GetFiles(TPath.GetDirectoryName(LFileName), 'SKILL.md.dai-*.bak')) = 1, 'legacy migration makes DAI-prefixed backup');
    Check(TFile.ReadAllText(TDirectory.GetFiles(TPath.GetDirectoryName(LFileName), 'SKILL.md.dai-*.bak')[0], TEncoding.UTF8) = CLegacySkill,
      'legacy migration backup contains original skill');
  end;
  LBackupCount := Length(TDirectory.GetFiles(GRoot, '*.bak', TSearchOption.soAllDirectories));
  TDAICodexRegistration.RegisterFiles;
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = LSkillText, 'migrated registration idempotent content');
  Check(Length(TDirectory.GetFiles(GRoot, '*.bak', TSearchOption.soAllDirectories)) = LBackupCount, 'idempotent registration creates no backups');
  LJson := TDAICodexRegistration.Status;
  try
    Check(LJson.GetValue<Boolean>('skill_registered'), 'new metadata and marker recognized');
    Check(not LJson.GetValue<Boolean>('legacy_skill_registered'), 'legacy status clear after migration');
  finally
    LJson.Free;
  end;
  TDAICodexRegistration.UnregisterFiles;
  Check(not TFile.Exists(TDAICodexRegistration.SkillFileName), 'new own skill removed');
  Check(TFile.Exists(LForeignSibling), 'unregister keeps legacy foreign resource');
  WriteFixture(LProfileLegacy, 'foreign profile skill');
  WriteFixture(LAppDataLegacy, 'foreign AppData skill');
  TDAICodexRegistration.RegisterFiles;
  Check(TFile.ReadAllText(LProfileLegacy, TEncoding.UTF8) = 'foreign profile skill', 'foreign profile legacy remains');
  Check(TFile.ReadAllText(LAppDataLegacy, TEncoding.UTF8) = 'foreign AppData skill', 'foreign AppData legacy remains');
  LJson := TDAICodexRegistration.Status;
  try
    Check(not LJson.GetValue<Boolean>('legacy_skill_registered'), 'foreign legacy is not owned');
  finally
    LJson.Free;
  end;
  TDAICodexRegistration.UnregisterFiles;
  Check(TFile.Exists(LProfileLegacy) and TFile.Exists(LAppDataLegacy), 'unregister retains both foreign legacy skills');
  WriteFixture(LProfileLegacy, CLegacySkill);
  WriteFixture(LAppDataLegacy, CLegacySkill);
  WriteFixture(TDAICodexRegistration.SkillFileName, 'foreign new skill');
  LConfigText := TFile.ReadAllText(LConfigPath, TEncoding.UTF8);
  LConflict := False;
  try
    TDAICodexRegistration.RegisterFiles;
  except
    on E: EInvalidOperation do LConflict := True;
  end;
  Check(LConflict, 'foreign new skill blocks migration');
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = 'foreign new skill', 'foreign new target is not overwritten');
  Check(TFile.ReadAllText(LConfigPath, TEncoding.UTF8) = LConfigText, 'new skill collision retains Codex config');
  Check(TFile.ReadAllText(LProfileLegacy, TEncoding.UTF8) = CLegacySkill, 'target collision retains old profile skill');
  Check(TFile.ReadAllText(LAppDataLegacy, TEncoding.UTF8) = CLegacySkill, 'target collision retains old AppData skill');
  LConflict := False;
  try
    TDAICodexRegistration.MigrateSkillFiles;
  except
    on E: EInvalidOperation do LConflict := True;
  end;
  Check(LConflict, 'skill-only migration also blocks foreign destination');
  Check(TFile.ReadAllText(LProfileLegacy, TEncoding.UTF8) = CLegacySkill, 'skill-only target collision retains old skill');
  WriteFixture(TDAICodexRegistration.SkillFileName, CLegacySkill);
  TDAICodexRegistration.RegisterFiles;
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = TDAICodexRegistration.BuildSkillContent,
    'owned destination with historical metadata is refreshed');
  WriteFixture(LProfileLegacy, CLegacySkill);
  WriteFixture(LAppDataLegacy, CLegacySkill);
  TDAICodexRegistration.UnregisterFiles;
  Check(not TFile.Exists(TDAICodexRegistration.SkillFileName), 'unregister removes current own destination');
  Check(not TFile.Exists(LProfileLegacy) and not TFile.Exists(LAppDataLegacy), 'unregister removes both old own skills');
  Check(TFile.Exists(LForeignSibling), 'unregister never deletes foreign subdirectories');
  WriteFixture(LProfileLegacy, CLegacySkill);
  SetFileAttributes(PChar(LProfileLegacy), FILE_ATTRIBUTE_READONLY);
  LConflict := False;
  try
    TDAICodexRegistration.RegisterFiles;
  except
    on E: EInvalidOperation do LConflict := True;
  end;
  SetFileAttributes(PChar(LProfileLegacy), FILE_ATTRIBUTE_NORMAL);
  Check(LConflict, 'read-only legacy prevents partial migration');
  Check(not TFile.Exists(TDAICodexRegistration.SkillFileName), 'failed legacy preflight creates no new skill');
  Check(TFile.ReadAllText(LConfigPath, TEncoding.UTF8) = LConfigText, 'failed legacy preflight retains config');
  Check(TFile.ReadAllText(LProfileLegacy, TEncoding.UTF8) = CLegacySkill, 'failed legacy preflight retains own source');
  WriteFixture(TDAICodexRegistration.SkillFileName, 'foreign new skill');
  TDAICodexRegistration.UnregisterFiles;
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = 'foreign new skill', 'unregister retains foreign new target');
  Check(not TFile.Exists(LProfileLegacy), 'unregister still cleans old own skill with foreign destination');
  TFile.Delete(TDAICodexRegistration.SkillFileName);
end;

procedure CodexPreservationTests;
var
  LPath: string;
  LText: string;
  LJson: TJSONObject;
  LConflict: Boolean;
begin
  CodexConflict('["mcp_servers"."dai_start"]' + #10 + 'command="user.exe"', 'Codex quoted foreign launcher');
  CodexConflict('[mcp_servers]' + #10 + 'dai_start = { command="user.exe" }', 'Codex nested inline launcher');
  CodexConflict('mcp_servers.dai_start.command = "user.exe"', 'Codex dotted launcher');
  CodexConflict(CDAIManagedBlockBegin + #10 + '[mcp_servers.dai]' + #10 + 'url="old"' + #10 +
    CDAIManagedBlockEnd + #10 + '[mcp_servers.dai_start]' + #10 + 'command="user.exe"', 'foreign launcher blocks old managed migration');
  CodexConflict('["mcp_servers"."dai"]' + #10 + 'url="http://user"', 'Codex quoted foreign section');
  CodexConflict('mcp_servers = { dai = { url="http://user" } }', 'Codex inline mapping');
  CodexConflict('[mcp_servers]' + #10 + 'dai = { url="http://user" }', 'Codex nested inline mapping');
  CodexConflict(CDAIManagedBlockBegin + #10 + '[mcp_servers.dai]', 'Codex incomplete marker');
  LPath := TDAICodexRegistration.CodexConfigFileName;
  LText := 'notes = """' + #13#10 + CDAIManagedBlockBegin + #13#10 + 'text in a literal' + #13#10 +
    CDAIManagedBlockEnd + #13#10 + '"""' + #13#10 + 'model = "preserve"' + #13#10;
  TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
  TDAICodexRegistration.RegisterFiles;
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8).StartsWith(LText), 'Codex markers in TOML multiline string retained');
  LJson := TDAICodexRegistration.Status;
  try
    Check(LJson.GetValue<Boolean>('skill_metadata_valid'), 'Codex generated skill has valid frontmatter');
  finally
    LJson.Free;
  end;
  TDAICodexRegistration.UnregisterFiles;
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'Codex unregister preserves multiline user text exactly');
  ForceDirectories(TPath.GetDirectoryName(TDAICodexRegistration.SkillFileName));
  TFile.WriteAllText(TDAICodexRegistration.SkillFileName, 'user skill content', TEncoding.UTF8);
  LConflict := False;
  try
    TDAICodexRegistration.RegisterFiles;
  except
    on E: EInvalidOperation do LConflict := True;
  end;
  Check(LConflict, 'foreign skill prevents Codex registration');
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'skill preflight keeps Codex config unchanged');
end;

procedure SelectRegistrationScope(AIndex: Integer);
begin
  TDAISettings.Instance.UseSharedConnectionSettings := AIndex = 0;
  if AIndex = 1 then
    TDAISettings.Instance.RegistryRoot := 'Software\Embarcadero\BDS\22.0\DAI'
  else
    TDAISettings.Instance.RegistryRoot := 'Software\Embarcadero\BDS\37.0\DAI';
  TDAISettings.Instance.Port := 7700 + AIndex;
  TDAISettings.Instance.Token := 'isolated-scope-fixture-' + IntToStr(AIndex);
end;

procedure RegistrationScopeNameTests;
var
  LName, LOtherName, LRoot: string;
  LRejected: Boolean;
begin
  Check(DAIRegistrationServerName(True, '') = 'dai', 'shared registration does not need an IDE root');
  Check(DAIRegistrationLauncherName(True, '') = 'dai_start', 'shared launcher keeps legacy name');
  Check(DAIRegistrationServerName(False, 'Software\Embarcadero\BDS\22.0\DAI') = 'dai_bds22_0', 'Delphi 11 BDS registration name');
  Check(DAIRegistrationServerName(False, 'Software\Embarcadero\BDS\23.0\DAI') = 'dai_bds23_0', 'Delphi 12 BDS registration name');
  Check(DAIRegistrationServerName(False, 'Software\Embarcadero\BDS\37.0\DAI') = 'dai_bds37_0', 'Delphi 13 BDS registration name');
  Check(DAIRegistrationServerName(False, 'software/EMBARCADERO//bds/37.0/dai/') = 'dai_bds37_0',
    'IDE root slash casing and trailing separator normalize');
  LName := DAIRegistrationServerName(False, 'Software\Embarcadero\DAITest\37.0\DAI');
  Check(LName.StartsWith('dai_bds37_0_p') and (Length(LName) = Length('dai_bds37_0_p') + 16), 'custom profile hash suffix bounded');
  Check(LName = DAIRegistrationServerName(False, 'software/embarcadero/daitest/37.0/dai/'), 'profile suffix stable for normalized root');
  LOtherName := DAIRegistrationServerName(False, 'Software\Embarcadero\OtherProfile\37.0\DAI');
  Check(LName <> LOtherName, 'different IDE profiles have independent names');
  Check(DAIRegistrationLauncherName(False, 'Software\Embarcadero\DAITest\37.0\DAI') = LName + '_start',
    'custom profile launcher follows scoped server');
  Check(DAIRegistrationServerName(False, 'Software\Embarcadero\BDS\37.0_DAITest\DAI') <> 'dai_bds37_0',
    'profile suffix on IDE version remains independent');
  for LRoot in ['', 'Software\Embarcadero\BDS\37.0', 'Software\Embarcadero\BDS\invalid\DAI',
    'Software\Embarcadero\BDS\37.0\DAI' + #10] do
  begin
    LRejected := False;
    try
      DAIRegistrationServerName(False, LRoot);
    except
      on E: EArgumentException do LRejected := True;
    end;
    Check(LRejected, 'invalid local registry scope fails closed');
  end;
end;

function ScopedFixtureEntry(const AText, AFormat: string; const AKeys: TArray<string>;
  const AServerName: string): string;
var
  LKeys: TArray<string>;
begin
  LKeys := Copy(AKeys);
  LKeys[High(LKeys)] := AServerName;
  Check(TDAIClientConfigText.ExtractEntry(AText, AFormat, LKeys, Result), 'scoped entry exists: ' + AServerName);
end;

function ScopedFixtureHasEntry(const AText, AFormat: string; const AKeys: TArray<string>;
  const AServerName: string): Boolean;
var
  LKeys: TArray<string>;
  LIgnored: string;
begin
  LKeys := Copy(AKeys);
  LKeys[High(LKeys)] := AServerName;
  Result := TDAIClientConfigText.ExtractEntry(AText, AFormat, LKeys, LIgnored);
end;

procedure ScopedClientTests(const AClient, APath, AFormat: string; const AKeys: TArray<string>);
const
  CNames: array[0..2] of string = ('dai', 'dai_bds22_0', 'dai_bds37_0');
var
  LJson: TJSONObject;
  LIndex: Integer;
  LText, LEntry, LSavedText, LEditedEntry: string;
  LEntries, LLaunchers, LOwnerships: array[0..2] of string;
  LSidecars: array[0..2] of string;
  LKeys: TArray<string>;
begin
  for LIndex := 0 to 2 do
  begin
    SelectRegistrationScope(LIndex);
    Check(TDAICodexRegistration.ServerName = CNames[LIndex], AClient + ' scoped server name');
    Check(TDAICodexRegistration.LauncherServerName = CNames[LIndex] + '_start', AClient + ' scoped launcher name');
    LJson := TDAIClientRegistration.RegisterFiles(AClient);
    try
      Check(ClientStatus(LJson) = 'configured', AClient + ' registers scope ' + IntToStr(LIndex));
      Check(Pos(TDAISettings.Instance.Token, LJson.ToJSON) = 0, AClient + ' scoped status redacts credential');
      LSidecars[LIndex] := TJSONObject(TJSONArray(LJson.GetValue('clients')).Items[0]).GetValue<string>('ownership_file');
    finally
      LJson.Free;
    end;
    Check(LSidecars[LIndex] = APath + '.' + CNames[LIndex] + '-registration.json', AClient + ' isolated ownership filename');
    LText := TFile.ReadAllText(APath, TEncoding.UTF8);
    LEntries[LIndex] := ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex]);
    LLaunchers[LIndex] := ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex] + '_start');
    Check((Pos(IntToStr(7700 + LIndex), LEntries[LIndex]) > 0) and
      (Pos(TDAISettings.Instance.Token, LEntries[LIndex]) > 0), AClient + ' own HTTP or proxy endpoint/credential');
    Check((Pos(IntToStr(7700 + LIndex), LLaunchers[LIndex]) > 0) and
      (Pos(TDAISettings.Instance.Token, LLaunchers[LIndex]) > 0), AClient + ' own launcher endpoint/credential');
    LOwnerships[LIndex] := TFile.ReadAllText(LSidecars[LIndex], TEncoding.UTF8);
  end;
  LText := TFile.ReadAllText(APath, TEncoding.UTF8);
  SelectRegistrationScope(0);
  TDAISettings.Instance.RegistryRoot := 'Software\Embarcadero\BDS\22.0\DAI';
  LJson := TDAIClientRegistration.Status(AClient);
  try
    Check(ClientStatus(LJson) = 'registered', AClient + ' shared ownership survives registering IDE version change');
  finally
    LJson.Free;
  end;
  LJson := TDAIClientRegistration.RegisterFiles(AClient);
  try
    Check(ClientStatus(LJson) = 'unchanged', AClient + ' same shared endpoint from another IDE is idempotent');
    Check(TFile.ReadAllText(APath, TEncoding.UTF8) = LText, AClient + ' shared IDE version change preserves config bytes');
    Check(TFile.ReadAllText(LSidecars[0], TEncoding.UTF8) = LOwnerships[0], AClient + ' shared IDE version change preserves global sidecar');
  finally
    LJson.Free;
  end;
  for LIndex := 0 to 2 do
  begin
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex]) = LEntries[LIndex], AClient + ' all HTTP scopes coexist');
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex] + '_start') = LLaunchers[LIndex],
      AClient + ' all launcher scopes coexist');
    SelectRegistrationScope(LIndex);
    LJson := TDAIClientRegistration.Status(AClient);
    try
      Check(ClientStatus(LJson) = 'registered', AClient + ' independent scope ownership status');
    finally
      LJson.Free;
    end;
  end;
  SelectRegistrationScope(1);
  TDAISettings.Instance.Port := 7801;
  TDAISettings.Instance.Token := 'isolated-local-scope-rotated';
  LJson := TDAIClientRegistration.Status(AClient);
  try
    Check(ClientStatus(LJson) = 'needs_update', AClient + ' changed local target detected');
  finally
    LJson.Free;
  end;
  LJson := TDAIClientRegistration.RegisterFiles(AClient);
  try
    Check(ClientStatus(LJson) = 'configured', AClient + ' updates selected local scope');
  finally
    LJson.Free;
  end;
  LText := TFile.ReadAllText(APath, TEncoding.UTF8);
  for LIndex in [0, 2] do
  begin
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex]) = LEntries[LIndex], AClient + ' update retains other HTTP bytes');
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex] + '_start') = LLaunchers[LIndex],
      AClient + ' update retains other launcher bytes');
    Check(TFile.ReadAllText(LSidecars[LIndex], TEncoding.UTF8) = LOwnerships[LIndex], AClient + ' update retains other sidecar bytes');
  end;
  LEntry := ScopedFixtureEntry(LText, AFormat, AKeys, CNames[1]);
  Check(Pos('7801', LEntry) > 0, AClient + ' selected target updated');
  LJson := TDAIClientRegistration.UnregisterFiles(AClient);
  try
    Check(ClientStatus(LJson) = 'removed', AClient + ' unregister selected local scope');
  finally
    LJson.Free;
  end;
  LText := TFile.ReadAllText(APath, TEncoding.UTF8);
  Check(not ScopedFixtureHasEntry(LText, AFormat, AKeys, CNames[1]) and
    not ScopedFixtureHasEntry(LText, AFormat, AKeys, CNames[1] + '_start'), AClient + ' selected local pair removed');
  for LIndex in [0, 2] do
  begin
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex]) = LEntries[LIndex], AClient + ' unregister retains other HTTP bytes');
    Check(ScopedFixtureEntry(LText, AFormat, AKeys, CNames[LIndex] + '_start') = LLaunchers[LIndex],
      AClient + ' unregister retains other launcher bytes');
  end;
  SelectRegistrationScope(2);
  LSavedText := LText;
  LKeys := Copy(AKeys);
  LKeys[High(LKeys)] := CNames[2] + '_start';
  if AFormat = 'yaml' then LEditedEntry := CNames[2] + '_start:' + #10 + '  command: "user-edited.exe"'
  else LEditedEntry := '{"command":"user-edited.exe"}';
  LText := TDAIClientConfigText.Merge(LText, AFormat, LKeys, LEditedEntry, False);
  TFile.WriteAllText(APath, LText, TEncoding.UTF8);
  LJson := TDAIClientRegistration.RegisterFiles(AClient);
  try
    Check(ClientStatus(LJson) = 'conflict', AClient + ' edited local launcher blocks replacement');
    Check(TFile.ReadAllText(APath, TEncoding.UTF8) = LText, AClient + ' conflict retains all config bytes');
  finally
    LJson.Free;
  end;
  LJson := TDAIClientRegistration.UnregisterFiles(AClient);
  try
    Check(ClientStatus(LJson) = 'conflict', AClient + ' edited local launcher blocks partial removal');
    Check(TFile.ReadAllText(APath, TEncoding.UTF8) = LText, AClient + ' conflict retains both local entries');
    Check(TFile.ReadAllText(LSidecars[2], TEncoding.UTF8) = LOwnerships[2], AClient + ' conflict retains local ownership');
  finally
    LJson.Free;
  end;
  TFile.WriteAllText(APath, LSavedText, TEncoding.UTF8);
  LJson := TDAIClientRegistration.UnregisterFiles(AClient);
  try
    Check(ClientStatus(LJson) = 'removed', AClient + ' restored local scope can be removed');
  finally
    LJson.Free;
  end;
  SelectRegistrationScope(0);
  LText := TFile.ReadAllText(APath, TEncoding.UTF8);
  Check(ScopedFixtureEntry(LText, AFormat, AKeys, CNames[0]) = LEntries[0], AClient + ' shared survives both local removals');
  LJson := TDAIClientRegistration.UnregisterFiles(AClient);
  try
    Check(ClientStatus(LJson) = 'removed', AClient + ' shared removal independent');
  finally
    LJson.Free;
  end;
end;

procedure ScopedCodexTests;
const
  CNames: array[0..2] of string = ('dai', 'dai_bds22_0', 'dai_bds37_0');
var
  LIndex: Integer;
  LPath, LText, LSkill, LRetained: string;
  LJson: TJSONObject;
  LConflict: Boolean;
begin
  LPath := TDAICodexRegistration.CodexConfigFileName;
  for LIndex := 0 to 2 do
  begin
    SelectRegistrationScope(LIndex);
    TDAICodexRegistration.RegisterFiles;
    LJson := TDAICodexRegistration.Status;
    try
      Check(LJson.GetValue<Boolean>('codex_entry_registered') and LJson.GetValue<Boolean>('launcher_entry_registered'),
        'Codex selected scope pair registered');
      Check(not LJson.GetValue<Boolean>('needs_update'), 'Codex selected scope current');
      Check(Pos(TDAISettings.Instance.Token, LJson.ToJSON) = 0, 'Codex scoped status redacts credential');
    finally
      LJson.Free;
    end;
  end;
  LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  for LIndex := 0 to 2 do
    Check((Pos('[mcp_servers.' + CNames[LIndex] + ']', LText) > 0) and
      (Pos('[mcp_servers.' + CNames[LIndex] + '_start]', LText) > 0), 'Codex all versioned pairs coexist');
  for LIndex := 0 to 2 do
  begin
    SelectRegistrationScope(LIndex);
    LJson := TDAICodexRegistration.Status;
    try
      Check(not LJson.GetValue<Boolean>('needs_update'), 'Codex earlier blocks remain current after adding later scopes');
    finally
      LJson.Free;
    end;
    TDAICodexRegistration.RegisterFiles;
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'Codex repeated scope registration preserves full file bytes and ordering');
  end;
  Check(Pos('# >>> DAI managed: dai_bds22_0 >>>', LText) > 0, 'Codex local scope owns a separate marker');
  LSkill := TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8);
  Check(LSkill = TDAICodexRegistration.BuildSkillContent, 'Codex one current shared routing skill');
  Check((Pos('dai_bds', LSkill) > 0), 'Codex skill explains version-specific server routing');
  SelectRegistrationScope(1);
  TDAISettings.Instance.Port := 7801;
  TDAISettings.Instance.Token := 'isolated-local-scope-rotated';
  TDAICodexRegistration.RegisterFiles;
  LRetained := TFile.ReadAllText(LPath, TEncoding.UTF8);
  Check(Pos('7801', LRetained) > 0, 'Codex selected local endpoint updated');
  Check((Pos('7700', LRetained) > 0) and (Pos('7702', LRetained) > 0), 'Codex update retains shared and other local endpoint');
  Check((Pos('isolated-scope-fixture-0', LRetained) > 0) and (Pos('isolated-scope-fixture-2', LRetained) > 0),
    'Codex update retains other scope credentials');
  TDAICodexRegistration.UnregisterFiles;
  LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  Check((Pos('[mcp_servers.dai_bds22_0]', LText) = 0) and (Pos('[mcp_servers.dai_bds22_0_start]', LText) = 0),
    'Codex unregister removes only selected local pair');
  Check((Pos('[mcp_servers.dai]', LText) > 0) and (Pos('[mcp_servers.dai_bds37_0]', LText) > 0),
    'Codex unregister retains other scope blocks');
  Check(TFile.ReadAllText(TDAICodexRegistration.SkillFileName, TEncoding.UTF8) = LSkill, 'Codex shared skill survives selected scope removal');
  LJson := TDAICodexRegistration.Status;
  try
    Check(not LJson.GetValue<Boolean>('codex_entry_registered') and not LJson.GetValue<Boolean>('launcher_entry_registered') and
      not LJson.GetValue<Boolean>('needs_update'), 'Codex removed scope status excludes remaining other scopes');
  finally
    LJson.Free;
  end;
  TDAICodexRegistration.UnregisterFiles;
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'Codex repeated removed-scope unregister preserves other blocks');
  SelectRegistrationScope(1);
  LRetained := LText + sLineBreak + '[mcp_servers."dai_bds22_0_start"]' + sLineBreak + 'command = "user.exe"' + sLineBreak;
  TFile.WriteAllText(LPath, LRetained, TEncoding.UTF8);
  LConflict := False;
  try
    TDAICodexRegistration.RegisterFiles;
  except
    on E: EInvalidOperation do LConflict := True;
  end;
  Check(LConflict, 'Codex foreign scoped launcher blocks selected registration');
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LRetained, 'Codex foreign local launcher preserves all blocks');
  TDAICodexRegistration.UnregisterFiles;
  Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LRetained, 'Codex unregister never takes foreign scoped launcher');
  Check(TFile.Exists(TDAICodexRegistration.SkillFileName), 'Codex shared skill remains with other owned blocks and foreign launcher');
  TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
  SelectRegistrationScope(0);
  TDAICodexRegistration.UnregisterFiles;
  Check(TFile.Exists(TDAICodexRegistration.SkillFileName), 'Codex shared skill remains while only one local scope is owned');
  LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
  Check((Pos('[mcp_servers.dai]', LText) = 0) and (Pos('[mcp_servers.dai_bds37_0]', LText) > 0),
    'Codex shared unregister retains final local scope');
  SelectRegistrationScope(2);
  TDAICodexRegistration.UnregisterFiles;
  Check(not TFile.Exists(TDAICodexRegistration.SkillFileName), 'Codex last own scope removal cleans shared skill');
end;

procedure ScopedOwnershipRecoveryTests;
var
  LOldPath, LPath, LSidecar11, LSidecar13, LText, LOwnership11, LOwnership13, LHash: string;
  LJson, LOwnership: TJSONObject;
begin
  LOldPath := GetEnvironmentVariable('DAI_LM_STUDIO_CONFIG');
  LPath := TPath.Combine(TPath.GetDirectoryName(LOldPath), 'scope-recovery.json');
  SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(LPath));
  try
    SelectRegistrationScope(1);
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    LJson.Free;
    SelectRegistrationScope(2);
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    LJson.Free;
    LSidecar11 := LPath + '.dai_bds22_0-registration.json';
    LSidecar13 := LPath + '.dai_bds37_0-registration.json';
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    LOwnership13 := TFile.ReadAllText(LSidecar13, TEncoding.UTF8);
    LOwnership := TJSONObject.ParseJSONValue(TFile.ReadAllText(LSidecar11, TEncoding.UTF8)) as TJSONObject;
    try
      LHash := LOwnership.GetValue<string>('entry_sha256');
      LOwnership.RemovePair('entry_sha256').Free;
      LOwnership.AddPair('entry_sha256', StringOfChar('a', 64));
      LOwnership.RemovePair('pending_sha256').Free;
      LOwnership.AddPair('pending_sha256', LHash);
      LHash := LOwnership.GetValue<string>('launcher_entry_sha256');
      LOwnership.RemovePair('launcher_entry_sha256').Free;
      LOwnership.AddPair('launcher_entry_sha256', StringOfChar('b', 64));
      LOwnership.RemovePair('launcher_pending_sha256').Free;
      LOwnership.AddPair('launcher_pending_sha256', LHash);
      LOwnership.RemovePair('state').Free;
      LOwnership.AddPair('state', 'pending');
      TFile.WriteAllText(LSidecar11, LOwnership.ToJSON, TEncoding.UTF8);
    finally
      LOwnership.Free;
    end;
    SelectRegistrationScope(1);
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'unchanged', 'local pending pair recovers only its selected ownership');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'local pending recovery keeps complete config bytes');
      Check(TFile.ReadAllText(LSidecar13, TEncoding.UTF8) = LOwnership13, 'local pending recovery preserves other scope sidecar');
    finally
      LJson.Free;
    end;
    LOwnership11 := TFile.ReadAllText(LSidecar11, TEncoding.UTF8);
    LOwnership := TJSONObject.ParseJSONValue(LOwnership11) as TJSONObject;
    try
      Check((LOwnership.GetValue<string>('state') = 'registered') and (LOwnership.GetValue<string>('pending_sha256') = '') and
        (LOwnership.GetValue<string>('launcher_pending_sha256') = ''), 'local pending recovery commits both hashes');
      LOwnership.RemovePair('registry_root').Free;
      LOwnership.AddPair('registry_root', 'Software\Embarcadero\BDS\37.0\DAI');
      TFile.WriteAllText(LSidecar11, LOwnership.ToJSON, TEncoding.UTF8);
    finally
      LOwnership.Free;
    end;
    LJson := TDAIClientRegistration.UnregisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'conflict', 'local sidecar from other registry profile rejected');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'wrong-profile ownership removes no config');
      Check(TFile.ReadAllText(LSidecar13, TEncoding.UTF8) = LOwnership13, 'wrong-profile ownership does not touch matching other scope');
    finally
      LJson.Free;
    end;
    TFile.WriteAllText(LSidecar11, '{"owner":"user"}', TEncoding.UTF8);
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'conflict', 'foreign local sidecar cannot be adopted');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'foreign local sidecar retains all config bytes');
    finally
      LJson.Free;
    end;
    SelectRegistrationScope(2);
    LJson := TDAIClientRegistration.Status('lm-studio');
    try
      Check(ClientStatus(LJson) = 'registered', 'foreign other-scope sidecar does not block selected scope status');
    finally
      LJson.Free;
    end;
    LJson := TDAIClientRegistration.UnregisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'removed', 'selected scope remains independently removable beside foreign local sidecar');
      Check(TFile.ReadAllText(LSidecar11, TEncoding.UTF8) = '{"owner":"user"}', 'foreign other sidecar retained verbatim');
    finally
      LJson.Free;
    end;
  finally
    SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(LOldPath));
  end;
end;

procedure ScopedProfileRegistrationTests;
const
  CRoots: array[0..2] of string = ('Software\Embarcadero\BDS\37.0\DAI',
    'Software\Embarcadero\DAITest\37.0\DAI', 'Software\Embarcadero\BDS\37.0_DAITest\DAI');
var
  LOldPath, LPath, LOldCodexHome, LText, LProfileText, LSkillPath: string;
  LNames: array[0..2] of string;
  LIndex: Integer;
  LJson: TJSONObject;
begin
  LOldPath := GetEnvironmentVariable('DAI_LM_STUDIO_CONFIG');
  LOldCodexHome := GetEnvironmentVariable('CODEX_HOME');
  LPath := TPath.Combine(TPath.GetDirectoryName(LOldPath), 'profiles.json');
  SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(LPath));
  SetEnvironmentVariable('CODEX_HOME', PChar(TPath.Combine(LOldCodexHome, 'profile-fixture')));
  try
    TDAISettings.Instance.UseSharedConnectionSettings := False;
    for LIndex := 0 to 2 do
    begin
      TDAISettings.Instance.RegistryRoot := CRoots[LIndex];
      TDAISettings.Instance.Port := 7900 + LIndex;
      TDAISettings.Instance.Token := 'isolated-profile-fixture-' + IntToStr(LIndex);
      LNames[LIndex] := TDAICodexRegistration.ServerName;
      LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
      try
        Check(ClientStatus(LJson) = 'configured', 'custom IDE profile registers independent JSON pair: ' + ClientStatus(LJson));
      finally
        LJson.Free;
      end;
      TDAICodexRegistration.RegisterFiles;
    end;
    LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    LProfileText := TFile.ReadAllText(TDAICodexRegistration.CodexConfigFileName, TEncoding.UTF8);
    Check((LNames[0] <> LNames[1]) and (LNames[0] <> LNames[2]) and (LNames[1] <> LNames[2]),
      'default and both custom profile root formats have distinct names');
    for LIndex := 0 to 2 do
    begin
      Check(ScopedFixtureHasEntry(LText, 'json', ['mcpServers', ''], LNames[LIndex]) and
        ScopedFixtureHasEntry(LText, 'json', ['mcpServers', ''], LNames[LIndex] + '_start'), 'custom JSON profile pairs coexist');
      Check((Pos('[mcp_servers.' + LNames[LIndex] + ']', LProfileText) > 0) and
        (Pos('[mcp_servers.' + LNames[LIndex] + '_start]', LProfileText) > 0), 'custom Codex profile pairs coexist');
    end;
    TDAISettings.Instance.RegistryRoot := 'software/EMBARCADERO//daitest/37.0/dai/';
    TDAISettings.Instance.Port := 7901;
    TDAISettings.Instance.Token := 'isolated-profile-fixture-1';
    LJson := TDAIClientRegistration.RegisterFiles('lm-studio');
    try
      Check(ClientStatus(LJson) = 'unchanged', 'normalized profile root preserves local sidecar ownership');
      Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'normalized profile registration changes no JSON bytes');
    finally
      LJson.Free;
    end;
    TDAICodexRegistration.RegisterFiles;
    Check(TFile.ReadAllText(TDAICodexRegistration.CodexConfigFileName, TEncoding.UTF8) = LProfileText,
      'normalized profile registration changes no Codex bytes');
    LSkillPath := TDAICodexRegistration.SkillFileName;
    for LIndex := 0 to 2 do
    begin
      TDAISettings.Instance.RegistryRoot := CRoots[LIndex];
      LJson := TDAIClientRegistration.UnregisterFiles('lm-studio');
      try
        Check(ClientStatus(LJson) = 'removed', 'custom profile unregister removes selected JSON pair');
      finally
        LJson.Free;
      end;
      TDAICodexRegistration.UnregisterFiles;
      if LIndex < 2 then
        Check(TFile.Exists(LSkillPath), 'shared routing skill retained by remaining custom profile');
    end;
    Check(not TFile.Exists(LSkillPath), 'last custom profile removal clears shared routing skill');
  finally
    SetEnvironmentVariable('DAI_LM_STUDIO_CONFIG', PChar(LOldPath));
    SetEnvironmentVariable('CODEX_HOME', PChar(LOldCodexHome));
  end;
end;

procedure ScopedCodexMarkerTests;
var
  LOldHome, LPath, LText, LNewline, LBegin, LEnd: string;
  LConflict: Boolean;
begin
  LOldHome := GetEnvironmentVariable('CODEX_HOME');
  SetEnvironmentVariable('CODEX_HOME', PChar(TPath.Combine(LOldHome, 'marker-fixture')));
  try
    SelectRegistrationScope(1);
    LPath := TDAICodexRegistration.CodexConfigFileName;
    LNewline := sLineBreak;
    LBegin := '# >>> DAI managed: dai_bds22_0 >>>';
    LEnd := '# <<< DAI managed: dai_bds22_0 <<<';
    LText := 'notes = """' + LNewline + LBegin + LNewline + '[mcp_servers.dai_bds22_0]' + LNewline +
      'url="literal-user-text"' + LNewline + LEnd + LNewline + '"""' + LNewline;
    WriteFixture(LPath, LText);
    TDAICodexRegistration.RegisterFiles;
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8).StartsWith(LText), 'local marker in TOML multiline string retained during register');
    TDAICodexRegistration.UnregisterFiles;
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'local marker in TOML multiline string retained during unregister');
    LText := LBegin + LNewline + '[mcp_servers.dai_bds22_0]' + LNewline + 'url="own"' + LNewline +
      '# >>> DAI managed: dai_bds37_0 >>>' + LNewline + '[mcp_servers.dai_bds37_0]' + LNewline +
      'url="other"' + LNewline + '# <<< DAI managed: dai_bds37_0 <<<' + LNewline + LEnd + LNewline;
    TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
    LConflict := False;
    try
      TDAICodexRegistration.RegisterFiles;
    except
      on E: EInvalidOperation do LConflict := True;
    end;
    Check(LConflict, 'nested other-scope marker blocks replacing selected block');
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'nested marker registration conflict retains full bytes');
    LConflict := False;
    try
      TDAICodexRegistration.UnregisterFiles;
    except
      on E: EInvalidOperation do LConflict := True;
    end;
    Check(LConflict, 'nested other-scope marker blocks removing selected block');
    Check(TFile.ReadAllText(LPath, TEncoding.UTF8) = LText, 'nested marker removal conflict retains full bytes');
  finally
    SetEnvironmentVariable('CODEX_HOME', PChar(LOldHome));
  end;
end;

{$I RegistrationTests\CleanupTests.inc}
{$I RegistrationTests\HealthTests.inc}

procedure ScopedRegistrationTests;
const
  CEnvironmentNames: array[0..10] of string = ('USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'CODEX_HOME', 'CLAUDE_CONFIG_DIR',
    'GEMINI_CLI_HOME', 'HERMES_HOME', 'OPENCLAW_STATE_DIR', 'OPENCLAW_CONFIG_PATH', 'DAI_LM_STUDIO_CONFIG', 'DAI_CLAUDE_DESKTOP_CONFIG');
var
  LEnvironment: array[0..10] of string;
  LIndex, LOldPort: Integer;
  LRoot, LOldToken, LOldRegistryRoot: string;
  LOldShared: Boolean;
begin
  for LIndex := 0 to High(CEnvironmentNames) do
    LEnvironment[LIndex] := GetEnvironmentVariable(CEnvironmentNames[LIndex]);
  LOldPort := TDAISettings.Instance.Port;
  LOldToken := TDAISettings.Instance.Token;
  LOldRegistryRoot := TDAISettings.Instance.RegistryRoot;
  LOldShared := TDAISettings.Instance.UseSharedConnectionSettings;
  // Leave room for the profile hash, sidecar ownership suffix and private GUID backup names.
  LRoot := TPath.Combine(GRoot, 'scoped');
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
    ScopedClientTests('claude-code', TPath.Combine(LRoot, '.claude\.claude.json'), 'json', ['mcpServers', '']);
    ScopedClientTests('claude-desktop', TPath.Combine(LRoot, 'Claude\claude_desktop_config.json'), 'json', ['mcpServers', '']);
    ScopedClientTests('gemini', TPath.Combine(LRoot, '.gemini\settings.json'), 'json', ['mcpServers', '']);
    ScopedClientTests('hermes', TPath.Combine(LRoot, '.hermes\config.yaml'), 'yaml', ['mcp_servers', '']);
    ScopedClientTests('lm-studio', TPath.Combine(LRoot, '.lmstudio\mcp.json'), 'json', ['mcpServers', '']);
    ScopedClientTests('openclaw', TPath.Combine(LRoot, '.openclaw\openclaw.json'), 'json5', ['mcp', 'servers', '']);
    ScopedOwnershipRecoveryTests;
    ScopedProfileRegistrationTests;
    ScopedCodexMarkerTests;
    ScopedCodexTests;
    CleanupRegistrationTests;
  finally
    for LIndex := 0 to High(CEnvironmentNames) do
      SetEnvironmentVariable(PChar(CEnvironmentNames[LIndex]), PChar(LEnvironment[LIndex]));
    TDAISettings.Instance.Port := LOldPort;
    TDAISettings.Instance.Token := LOldToken;
    TDAISettings.Instance.RegistryRoot := LOldRegistryRoot;
    TDAISettings.Instance.UseSharedConnectionSettings := LOldShared;
  end;
end;

begin
  DAISetLanguageForTests(dlGerman);
  try
    if ParamCount <> 1 then
      raise Exception.Create('Pass the isolated test directory.');
    GRoot := TPath.GetFullPath(ParamStr(1));
    ForceDirectories(GRoot);
    ParserTests;
    SafeFileTests;
    RegistrationTests;
    LauncherRegistrationTests;
    ManualRegistrationInfoTests;
    ManualLocalizationTests;
    RegistrationScopeNameTests;
    ScopedRegistrationTests;
    RegistrationHealthTests;
    CodexMigrationTests;
    CodexPreservationTests;
    Writeln('OK: ', GCount, ' isolated registration/parser/file checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
