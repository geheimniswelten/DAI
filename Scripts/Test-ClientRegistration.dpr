program TestClientRegistration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
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
    end;
    LKeys[High(LKeys)] := 'dai';
    Check(TDAIClientConfigText.ExtractEntry(LText, LFormat, LKeys, LEntry), LClient + ' original dai retained');
    if LClient = 'claude-desktop' then
      Check((Pos('--launcher', LEntry) = 0) and (Pos('--url', LEntry) > 0), 'Desktop dai remains plain STDIO bridge')
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

begin
  try
    if ParamCount <> 1 then
      raise Exception.Create('Pass the isolated test directory.');
    GRoot := TPath.GetFullPath(ParamStr(1));
    ForceDirectories(GRoot);
    ParserTests;
    SafeFileTests;
    RegistrationTests;
    LauncherRegistrationTests;
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
