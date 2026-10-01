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

procedure CodexPreservationTests;
var
  LPath: string;
  LText: string;
  LJson: TJSONObject;
  LConflict: Boolean;
begin
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
