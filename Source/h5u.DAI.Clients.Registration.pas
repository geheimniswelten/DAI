unit h5u.DAI.Clients.Registration;

{$IF CompilerVersion >= 36.0}  // Delphi 12+
{$TEXTBLOCK CRLF}
{$IFEND}

interface

uses
  System.JSON;

type
  TDAIClientRegistration = class sealed
  public
    class function Status(const AClient: string = ''): TJSONObject; static;
    class function RegisterFiles(const AClient: string = ''): TJSONObject; static;
    class function UnregisterFiles(const AClient: string = ''): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Hash,
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils,
  h5u.DAI.Clients.ConfigText,
  h5u.DAI.Clients.SafeFiles,
  h5u.DAI.Codex.Registration,
  h5u.DAI.Consts,
  h5u.DAI.Settings;

type
  TClientDefinition = record
    Id: string;
    LabelText: string;
    FileName: string;
    MarkerDirectory: string;
    Format: string;
    Transport: string;
    Documentation: string;
    Note: string;
    BlockReason: string;
    Keys: TArray<string>;
    Supported: Boolean;
    LauncherSupported: Boolean;
    Detected: Boolean;
  end;

  TManagedClientEntry = record
    Name: string;
    Keys: TArray<string>;
    Text: string;
    Exists: Boolean;
    Owned: Boolean;
  end;

const
  COwner = 'DAI.ClientRegistration.v1';

var
  GRegistrationLock: TObject;

function Endpoint: string;
begin
  Result := 'http://' + CDAIDefaultBindAddress + ':' + IntToStr(TDAISettings.Instance.Port) + CDAIMcpPath;
end;

function OwnershipFile(const AConfigFile: string): string;
begin
  Result := AConfigFile + '.dai-registration.json';
end;

function HashEntry(const AEntry: string): string;
begin
  Result := THashSHA2.GetHashString(AEntry);
end;

function JsonString(const AValue: string): string;
var
  LString: TJSONString;
begin
  LString := TJSONString.Create(AValue);
  try
    Result := LString.ToJSON;
  finally
    LString.Free;
  end;
end;

function ReadJsonString(const AJson: TJSONObject; const AName: string): string;
begin
  if not AJson.TryGetValue<string>(AName, Result) then
    Result := '';
end;

function AbsolutePath(const APath, AName: string): string;
begin
  if (Length(APath) < 3) or not CharInSet(APath[1], ['a'..'z', 'A'..'Z']) or (APath[2] <> ':') or
    not CharInSet(APath[3], ['\', '/']) then
    raise EDAIClientConfigConflict.Create(AName + ' muss ein absoluter lokaler Windows-Pfad sein.');
  Result := TPath.GetFullPath(APath);
end;

function EnvDirectory(const AVariable, ADefault: string): string;
var
  LValue: string;
begin
  LValue := Trim(GetEnvironmentVariable(AVariable));
  if LValue = '' then
    LValue := ADefault;
  Result := ExcludeTrailingPathDelimiter(AbsolutePath(LValue, AVariable));
end;

function EnvFile(const AVariable, ADefault: string): string;
var
  LValue: string;
begin
  LValue := Trim(GetEnvironmentVariable(AVariable));
  if LValue = '' then
    LValue := ADefault;
  Result := AbsolutePath(LValue, AVariable);
end;

function BridgeFileName: string;
begin
  // HInstance belongs to the package; the helper is deployed beside the BPL.
  Result := TDAICodexRegistration.BridgeFileName;
end;

function BuildDefinition(AIndex: Integer): TClientDefinition;
var
  LHome: string;
  LAppData: string;
  LLocalAppData: string;
  LDirectory: string;
  LLegacy: string;
begin
  Result := Default(TClientDefinition);
  Result.Supported := True;
  Result.Format := 'json';
  Result.Transport := 'streamable-http';
  Result.Keys := ['mcpServers', CDAICodexServerName];
  // These local Windows client schemas explicitly support command/args/env STDIO entries.
  Result.LauncherSupported := AIndex in [0, 1, 2, 4, 6, 7, 8];
  case AIndex of
    0: begin Result.Id := 'codex'; Result.LabelText := 'Codex'; end;
    1: begin Result.Id := 'claude-code'; Result.LabelText := 'Claude Code (CLI / VS Code)'; end;
    2: begin Result.Id := 'claude-desktop'; Result.LabelText := 'Claude Desktop'; end;
    3: begin Result.Id := 'eigent'; Result.LabelText := 'Eigent'; end;
    4: begin Result.Id := 'gemini'; Result.LabelText := 'Gemini CLI / Code Assist (VS Code)'; end;
    5: begin Result.Id := 'gemini-desktop'; Result.LabelText := 'Gemini Desktop'; end;
    6: begin Result.Id := 'hermes'; Result.LabelText := 'Hermes'; end;
    7: begin Result.Id := 'lm-studio'; Result.LabelText := 'LM Studio'; end;
    8: begin Result.Id := 'openclaw'; Result.LabelText := 'OpenClaw'; end;
  end;
  try
    LHome := AbsolutePath(TDAICodexRegistration.UserProfileDirectory, 'USERPROFILE');
    LAppData := EnvDirectory('APPDATA', TPath.Combine(LHome, 'AppData\Roaming'));
    LLocalAppData := EnvDirectory('LOCALAPPDATA', TPath.Combine(LHome, 'AppData\Local'));
    case AIndex of
      0:
        begin
          Result.FileName := TDAICodexRegistration.CodexConfigFileName;
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Format := 'toml';
          Result.Documentation := 'https://developers.openai.com/codex/mcp/';
          Result.Note := 'Codex CLI, App und IDE-Erweiterung teilen die Benutzerkonfiguration; Client nach Änderungen neu starten.';
        end;
      1:
        begin
          LDirectory := EnvDirectory('CLAUDE_CONFIG_DIR', TPath.Combine(LHome, '.claude'));
          if Trim(GetEnvironmentVariable('CLAUDE_CONFIG_DIR')) <> '' then
            Result.FileName := TPath.Combine(LDirectory, '.claude.json')
          else
            Result.FileName := TPath.Combine(LHome, '.claude.json');
          Result.MarkerDirectory := LDirectory;
          Result.Documentation := 'https://code.claude.com/docs/en/mcp';
          Result.Note := 'Benutzerscope. Projekt- oder lokale MCP-Konfiguration und Unternehmensrichtlinien können Vorrang haben.';
        end;
      2:
        begin
          Result.FileName := EnvFile('DAI_CLAUDE_DESKTOP_CONFIG', TPath.Combine(LAppData, 'Claude\claude_desktop_config.json'));
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Transport := 'stdio-http-bridge';
          Result.Documentation := 'https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop';
          Result.Note := 'Die native Delphi-Bridge verbindet stdio mit dem lokalen HTTP-Server; Claude Desktop vollständig neu starten.';
        end;
      3:
        begin
          Result.MarkerDirectory := TPath.Combine(LHome, '.eigent');
          Result.Supported := False;
          Result.Documentation := 'https://github.com/eigent-ai/eigent/blob/main/server/README_EN.md';
          Result.Note := 'Eigent verwaltet MCPs über UI/API. Kein verifiziertes globales mcp.json-Dateischema; ' +
            'dai per URL/Bearer-Header und dai_start bei lokaler STDIO-Unterstützung manuell mit DAI.McpBridge.exe --launcher einrichten.';
        end;
      4:
        begin
          LDirectory := EnvDirectory('GEMINI_CLI_HOME', LHome);
          Result.FileName := TPath.Combine(LDirectory, '.gemini\settings.json');
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Documentation := 'https://geminicli.com/docs/tools/mcp-server/';
          Result.Note := 'Gemini CLI und Code Assist im VS-Code-Agentenmodus. IntelliJ hat eigene MCP-Einstellungen; dort manuell eintragen.';
        end;
      5:
        begin
          Result.Supported := False;
          Result.MarkerDirectory := TPath.Combine(LAppData, 'Gemini');
          Result.Documentation := 'https://geminicli.com/docs/tools/mcp-server/';
          Result.Note := 'Kein offizielles allgemeines MCP-Konfigurationsschema für eine Gemini-Desktop-App verifiziert. Gemini CLI verwenden.';
        end;
      6:
        begin
          LDirectory := EnvDirectory('HERMES_HOME', TPath.Combine(LLocalAppData, 'hermes'));
          LLegacy := TPath.Combine(LHome, '.hermes');
          if Trim(GetEnvironmentVariable('HERMES_HOME')) = '' then
          begin
            if TDirectory.Exists(LDirectory) and TDirectory.Exists(LLegacy) then
              Result.BlockReason := 'Mehrere Hermes-Konfigurationsordner; HERMES_HOME auf das gewünschte Profil setzen.'
            else if TDirectory.Exists(LLegacy) then
              LDirectory := LLegacy;
          end;
          Result.FileName := TPath.Combine(LDirectory, 'config.yaml');
          Result.MarkerDirectory := LDirectory;
          Result.Format := 'yaml';
          Result.Keys := ['mcp_servers', CDAICodexServerName];
          Result.Documentation := 'https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference';
          Result.Note := 'Native Windows-Konfiguration. Für ein benanntes Profil HERMES_HOME explizit auf dessen Ordner setzen.';
        end;
      7:
        begin
          Result.FileName := EnvFile('DAI_LM_STUDIO_CONFIG', TPath.Combine(LHome, '.lmstudio\mcp.json'));
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Documentation := 'https://lmstudio.ai/docs/app/mcp';
          Result.Note := 'LM Studio ab 0.3.17; nach Änderungen die MCP-Konfiguration neu laden.';
        end;
      8:
        begin
          LDirectory := EnvDirectory('OPENCLAW_STATE_DIR', TPath.Combine(LHome, '.openclaw'));
          Result.FileName := EnvFile('OPENCLAW_CONFIG_PATH', TPath.Combine(LDirectory, 'openclaw.json'));
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Format := 'json5';
          Result.Keys := ['mcp', 'servers', CDAICodexServerName];
          Result.Documentation := 'https://docs.openclaw.ai/tools/mcp';
          Result.Note := 'Native MCP-Unterstützung erforderlich; Gateway auf diesem Windows-Rechner. openclaw mcp doctor dai --probe prüft die Verbindung.';
          if (GetEnvironmentVariable('OPENCLAW_CONFIG_READONLY') = '1') or (GetEnvironmentVariable('OPENCLAW_NIX_MODE') = '1') then
            Result.BlockReason := 'OpenClaw ist als schreibgeschützt konfiguriert.'
          else if (Trim(GetEnvironmentVariable('OPENCLAW_CONFIG_PATH')) = '') and
            ((Trim(GetEnvironmentVariable('OPENCLAW_PROFILE')) <> '') or (Trim(GetEnvironmentVariable('OPENCLAW_HOME')) <> '')) then
            Result.BlockReason := 'Das OpenClaw-Profil ist mehrdeutig; OPENCLAW_CONFIG_PATH explizit setzen.';
        end;
    end;
    Result.Detected := TDirectory.Exists(Result.MarkerDirectory) or ((Result.FileName <> '') and
      (TFile.Exists(Result.FileName) or TFile.Exists(OwnershipFile(Result.FileName))));
  except
    on E: Exception do
      Result.BlockReason := 'Der Konfigurationspfad ist ungültig oder konnte nicht sicher ermittelt werden.';
  end;
end;

function BuildEntry(const AClient: TClientDefinition): string;
var
  LEntry: TJSONObject;
  LHeaders: TJSONObject;
  LEnvironment: TJSONObject;
  LCharacter: Char;
begin
  if (TDAISettings.Instance.Port < 1024) or (TDAISettings.Instance.Port > 65535) then
    raise EDAIClientConfigConflict.Create('Der MCP-Port muss zwischen 1024 und 65535 liegen.');
  if Trim(TDAISettings.Instance.Token) = '' then
    raise EDAIClientConfigConflict.Create('Ein leerer Bearer-Token kann nicht registriert werden.');
  for LCharacter in TDAISettings.Instance.Token do
    if (Ord(LCharacter) < 32) or (Ord(LCharacter) = 127) then
      raise EDAIClientConfigConflict.Create('Steuerzeichen im Bearer-Token werden nicht registriert.');
  if AClient.Format = 'yaml' then
    Exit(Format(
      {$IF CompilerVersion >= 36.0}  // Delphi 12+
      '''
      dai:
        url: %s
        headers:
          Authorization: %s
        timeout: 180
      ''',
      {$ELSE}
      'dai:' + sLineBreak +
      '  url: %s' + sLineBreak +
      '  headers:' + sLineBreak +
      '    Authorization: %s' + sLineBreak +
      '  timeout: 180'
      ,
      {$IFEND}
      [JsonString(Endpoint), JsonString('Bearer ' + TDAISettings.Instance.Token)]));
  LEntry := TJSONObject.Create;
  try
    if AClient.Id = 'claude-desktop' then
    begin
      LEntry.AddPair('command', BridgeFileName);
      LEntry.AddPair('args', TJSONArray.Create('--url', Endpoint));
      LEnvironment := TJSONObject.Create;
      LEnvironment.AddPair('DAI_MCP_TOKEN', TDAISettings.Instance.Token);
      LEntry.AddPair('env', LEnvironment);
    end
    else
    begin
      if AClient.Id = 'claude-code' then
        LEntry.AddPair('type', 'http');
      if AClient.Id = 'gemini' then
        LEntry.AddPair('httpUrl', Endpoint)
      else
        LEntry.AddPair('url', Endpoint);
      if AClient.Id = 'openclaw' then
      begin
        LEntry.AddPair('transport', 'streamable-http');
        LEntry.AddPair('enabled', TJSONBool.Create(True));
        LEntry.AddPair('requestTimeoutMs', TJSONNumber.Create(180000));
      end;
      if AClient.Id = 'gemini' then
        LEntry.AddPair('timeout', TJSONNumber.Create(180000));
      LHeaders := TJSONObject.Create;
      LHeaders.AddPair('Authorization', 'Bearer ' + TDAISettings.Instance.Token);
      LEntry.AddPair('headers', LHeaders);
    end;
    Result := LEntry.ToJSON;
  finally
    LEntry.Free;
  end;
end;

function BuildLauncherEntry(const AClient: TClientDefinition): string;
var
  LEntry: TJSONObject;
  LArguments: TJSONArray;
  LEnvironment: TJSONObject;
  LArgument: string;
begin
  LEntry := TJSONObject.Create;
  try
    LArguments := TJSONArray.Create;
    LEntry.AddPair('args', LArguments);
    for LArgument in TDAICodexRegistration.LauncherArguments do
      LArguments.Add(LArgument);
    LEnvironment := TJSONObject.Create;
    LEnvironment.AddPair('DAI_MCP_TOKEN', TDAISettings.Instance.Token);
    LEntry.AddPair('env', LEnvironment);
    if AClient.Format = 'yaml' then
      Exit('dai_start:' + sLineBreak +
        '  command: ' + JsonString(BridgeFileName) + sLineBreak +
        '  args: ' + LArguments.ToJSON + sLineBreak +
        '  env:' + sLineBreak +
        '    DAI_MCP_TOKEN: ' + JsonString(TDAISettings.Instance.Token) + sLineBreak +
        '  timeout: 180');
    LEntry.AddPair('command', BridgeFileName);
    if AClient.Id = 'claude-code' then
      LEntry.AddPair('type', 'stdio');
    if AClient.Id = 'openclaw' then
    begin
      LEntry.AddPair('transport', 'stdio');
      LEntry.AddPair('enabled', TJSONBool.Create(True));
      LEntry.AddPair('requestTimeoutMs', TJSONNumber.Create(180000));
    end;
    if AClient.Id = 'gemini' then
      LEntry.AddPair('timeout', TJSONNumber.Create(180000));
    Result := LEntry.ToJSON;
  finally
    LEntry.Free;
  end;
end;

function OwnershipText(const AClient: TClientDefinition; const AHash, APendingHash: TArray<string>; const AState: string): string;
var
  LJson: TJSONObject;
begin
  LJson := TJSONObject.Create;
  try
    LJson.AddPair('owner', COwner);
    LJson.AddPair('client', AClient.Id);
    LJson.AddPair('config_path', AClient.FileName);
    LJson.AddPair('entry_sha256', AHash[0]);
    LJson.AddPair('pending_sha256', APendingHash[0]);
    LJson.AddPair('launcher_entry_sha256', AHash[1]);
    LJson.AddPair('launcher_pending_sha256', APendingHash[1]);
    LJson.AddPair('state', AState);
    Result := LJson.ToJSON + sLineBreak;
  finally
    LJson.Free;
  end;
end;

function ValidOwnership(const AClient: TClientDefinition; const AOwnership: string; out AHash, APendingHash: TArray<string>): Boolean;
var
  LJsonValue: TJSONValue;
  LJson: TJSONObject;
  LIgnored: string;
  LIndex: Integer;
begin
  Result := False;
  AHash := ['', ''];
  APendingHash := ['', ''];
  if AOwnership = '' then
    Exit;
  TDAIClientConfigText.ExtractEntry(AOwnership, 'json', ['owner'], LIgnored);
  LJsonValue := TJSONObject.ParseJSONValue(AOwnership);
  try
    if not (LJsonValue is TJSONObject) then
      Exit;
    LJson := TJSONObject(LJsonValue);
    if (ReadJsonString(LJson, 'owner') <> COwner) or (ReadJsonString(LJson, 'client') <> AClient.Id) or
      not SameText(ReadJsonString(LJson, 'config_path'), AClient.FileName) then
      Exit;
    if not (LJson.GetValue('entry_sha256') is TJSONString) or
      not (LJson.GetValue('pending_sha256') is TJSONString) or
      ((LJson.GetValue('launcher_entry_sha256') <> nil) and not (LJson.GetValue('launcher_entry_sha256') is TJSONString)) or
      ((LJson.GetValue('launcher_pending_sha256') <> nil) and not (LJson.GetValue('launcher_pending_sha256') is TJSONString)) then
      Exit;
    AHash[0] := ReadJsonString(LJson, 'entry_sha256');
    APendingHash[0] := ReadJsonString(LJson, 'pending_sha256');
    // Older v1 sidecars own dai only. Missing launcher hashes never grant ownership of dai_start.
    AHash[1] := ReadJsonString(LJson, 'launcher_entry_sha256');
    APendingHash[1] := ReadJsonString(LJson, 'launcher_pending_sha256');
    for LIndex := 0 to 1 do
      if ((AHash[LIndex] <> '') and not TRegEx.IsMatch(AHash[LIndex], '^[a-fA-F0-9]{64}$')) or
        ((APendingHash[LIndex] <> '') and not TRegEx.IsMatch(APendingHash[LIndex], '^[a-fA-F0-9]{64}$')) then
        Exit;
    Result := (ReadJsonString(LJson, 'state') = 'registered') or
      (ReadJsonString(LJson, 'state') = 'pending') or (ReadJsonString(LJson, 'state') = 'removed');
  finally
    LJsonValue.Free;
  end;
end;

procedure SetStatus(const AResult: TJSONObject; const AStatus, AMessage: string; ARegistered: Boolean);
begin
  AResult.AddPair('status', AStatus);
  AResult.AddPair('message', AMessage);
  AResult.AddPair('registered', TJSONBool.Create(ARegistered));
end;

function ProcessClient(const AClient: TClientDefinition; const AAction: string; AExplicit: Boolean): TJSONObject;
var
  LText: string;
  LOwnership: string;
  LNext: string;
  LPending: string;
  LCommitted: string;
  LBackup: string;
  LEntries: array[0..1] of TManagedClientEntry;
  LIndex: Integer;
  LEntryCount: Integer;
  LOwned: Boolean;
  LAnyExists: Boolean;
  LAllOwned: Boolean;
  LRemove: Boolean;
  LCodex: TJSONObject;
  LCodexRegistered: Boolean;
  LCodexNeedsUpdate: Boolean;
  LSidecarExists: Boolean;
  LConfigExists: Boolean;
  LStoredHashes: TArray<string>;
  LPendingHashes: TArray<string>;
  LCurrentHashes: TArray<string>;
  LNextHashes: TArray<string>;
  LNextEntry: string;
  LDesiredEntry: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', AClient.Id);
  Result.AddPair('label', AClient.LabelText);
  Result.AddPair('path', AClient.FileName);
  Result.AddPair('detected', TJSONBool.Create(AClient.Detected));
  Result.AddPair('supported', TJSONBool.Create(AClient.Supported));
  Result.AddPair('transport', AClient.Transport);
  Result.AddPair('documentation', AClient.Documentation);
  Result.AddPair('launcher_supported', TJSONBool.Create(AClient.LauncherSupported));
  if AClient.LauncherSupported then
  begin
    Result.AddPair('launcher_server', 'dai_start');
    Result.AddPair('launcher_transport', 'stdio');
    Result.AddPair('bridge_path', BridgeFileName);
    Result.AddPair('bridge_exists', TJSONBool.Create(TFile.Exists(BridgeFileName)));
  end;
  if (AClient.FileName <> '') and (AClient.Id <> 'codex') then
    Result.AddPair('ownership_file', OwnershipFile(AClient.FileName));
  LOwned := False;
  try
    if AClient.BlockReason <> '' then
    begin
      SetStatus(Result, 'conflict', AClient.BlockReason, False);
      Exit;
    end;
    if not AClient.Supported then
    begin
      SetStatus(Result, 'manual_configuration', AClient.Note, False);
      Exit;
    end;
    if (AAction <> 'status') and not AClient.Detected and not AExplicit then
    begin
      SetStatus(Result, 'not_detected', 'Kein vorhandener Konfigurationsordner erkannt; zur Erstregistrierung den Client ausdrücklich auswählen.', False);
      Exit;
    end;
    if AClient.Id = 'codex' then
    begin
      if (AAction = 'register') and not TFile.Exists(BridgeFileName) then
      begin
        SetStatus(Result, 'missing_bridge', 'DAI.McpBridge.exe fehlt neben dem DAI-Package; den Launcher zuerst bauen bzw. installieren.', False);
        Exit;
      end;
      if AAction = 'register' then
        TDAICodexRegistration.RegisterFiles
      else if AAction = 'unregister' then
        TDAICodexRegistration.UnregisterFiles;
      LCodex := TDAICodexRegistration.Status;
      LCodexRegistered := False;
      LCodexNeedsUpdate := False;
      LCodex.TryGetValue<Boolean>('codex_entry_registered', LCodexRegistered);
      LCodex.TryGetValue<Boolean>('needs_update', LCodexNeedsUpdate);
      Result.AddPair('codex', LCodex);
      if LCodexRegistered and LCodexNeedsUpdate then
        SetStatus(Result, 'needs_update', 'Die verwaltete Codex-Registrierung passt nicht zu dai/dai_start, Port, Token oder IDE; erneut registrieren.', True)
      else if LCodexRegistered then
        SetStatus(Result, 'registered', AClient.Note, True)
      else if AAction = 'unregister' then
        SetStatus(Result, 'removed', 'Die verwaltete Codex-Registrierung wurde entfernt.', False)
      else if not AClient.Detected then
        SetStatus(Result, 'not_detected', AClient.Note, False)
      else
        SetStatus(Result, 'not_registered', AClient.Note, False);
      Exit;
    end;
    TDAIClientSafeFiles.ValidatePath(AClient.FileName, AAction <> 'status');
    TDAIClientSafeFiles.ValidatePath(OwnershipFile(AClient.FileName), AAction <> 'status');
    LConfigExists := TFile.Exists(AClient.FileName);
    LSidecarExists := TFile.Exists(OwnershipFile(AClient.FileName));
    LText := TDAIClientSafeFiles.ReadTextIfExists(AClient.FileName);
    LOwnership := TDAIClientSafeFiles.ReadTextIfExists(OwnershipFile(AClient.FileName));
    LStoredHashes := ['', ''];
    LPendingHashes := ['', ''];
    LCurrentHashes := ['', ''];
    LNextHashes := ['', ''];
    if LSidecarExists and not ValidOwnership(AClient, LOwnership, LStoredHashes, LPendingHashes) then
      raise EDAIClientConfigConflict.Create('Die vorhandene Ownership-Datei ist fremd oder ungültig; sie bleibt erhalten.');
    LEntryCount := 1;
    LEntries[0].Name := CDAICodexServerName;
    LEntries[0].Keys := AClient.Keys;
    if AClient.LauncherSupported then
    begin
      LEntryCount := 2;
      LEntries[1].Name := 'dai_start';
      LEntries[1].Keys := Copy(AClient.Keys);
      LEntries[1].Keys[High(LEntries[1].Keys)] := LEntries[1].Name;
    end;
    LAllOwned := True;
    LAnyExists := False;
    // Preflight both entries before changing the file or sidecar; a foreign launcher blocks partial registration.
    for LIndex := 0 to LEntryCount - 1 do
    begin
      LEntries[LIndex].Exists := TDAIClientConfigText.ExtractEntry(LText, AClient.Format,
        LEntries[LIndex].Keys, LEntries[LIndex].Text);
      if LEntries[LIndex].Exists then
        LCurrentHashes[LIndex] := HashEntry(LEntries[LIndex].Text);
      LEntries[LIndex].Owned := LEntries[LIndex].Exists and LSidecarExists and
        ((LCurrentHashes[LIndex] = LStoredHashes[LIndex]) or (LCurrentHashes[LIndex] = LPendingHashes[LIndex]));
      LAnyExists := LAnyExists or LEntries[LIndex].Exists;
      LOwned := LOwned or LEntries[LIndex].Owned;
      LAllOwned := LAllOwned and LEntries[LIndex].Owned;
      if LEntries[LIndex].Exists and not LEntries[LIndex].Owned then
      begin
        SetStatus(Result, 'conflict', 'Ein fremder oder nachträglich veränderter ' +
          LEntries[LIndex].Name + '-Eintrag existiert; beide Einträge bleiben erhalten.', False);
        Exit;
      end;
    end;
    Result.AddPair('launcher_registered', TJSONBool.Create((LEntryCount = 2) and LEntries[1].Owned));
    if AClient.LauncherSupported and not TFile.Exists(BridgeFileName) and (AAction <> 'unregister') then
    begin
      SetStatus(Result, 'missing_bridge', 'DAI.McpBridge.exe fehlt neben dem DAI-Package; native Delphi-Bridge zuerst bauen bzw. installieren.', LOwned);
      Exit;
    end;
    LRemove := AAction = 'unregister';
    if LRemove and not LAnyExists then
    begin
      if LSidecarExists then
        TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient.FileName),
          OwnershipText(AClient, ['', ''], ['', ''], 'removed'), LOwnership, True);
      SetStatus(Result, 'unchanged', 'Kein unveränderter eigener dai/dai_start-Eintrag zu entfernen.', False);
      Exit;
    end;
    LNext := LText;
    for LIndex := 0 to LEntryCount - 1 do
    begin
      LDesiredEntry := '';
      if not LRemove then
      begin
        if LIndex = 0 then
          LDesiredEntry := BuildEntry(AClient)
        else
          LDesiredEntry := BuildLauncherEntry(AClient);
      end;
      LNext := TDAIClientConfigText.Merge(LNext, AClient.Format, LEntries[LIndex].Keys, LDesiredEntry, LRemove);
    end;
    if AAction = 'status' then
    begin
      if LOwned then
      begin
        if LAllOwned and (LNext = LText) then
          SetStatus(Result, 'registered', AClient.Note, True)
        else
          SetStatus(Result, 'needs_update', 'Der verwaltete Eintrag passt nicht zu dai/dai_start, Port, Token, Bridge oder IDE; erneut registrieren.', True);
      end
      else if not AClient.Detected then
        SetStatus(Result, 'not_detected', AClient.Note, False)
      else
        SetStatus(Result, 'not_registered', AClient.Note, False);
      Exit;
    end;
    for LIndex := 0 to LEntryCount - 1 do
      if not LRemove then
      begin
        TDAIClientConfigText.ExtractEntry(LNext, AClient.Format, LEntries[LIndex].Keys, LNextEntry);
        LNextHashes[LIndex] := HashEntry(LNextEntry);
      end;
    LCommitted := OwnershipText(AClient, LNextHashes, ['', ''], 'registered');
    if LNext = LText then
    begin
      if LOwnership <> LCommitted then
        TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient.FileName), LCommitted, LOwnership, LSidecarExists);
      SetStatus(Result, 'unchanged', 'Bereits passend registriert.', LAllOwned);
      Exit;
    end;
    LPending := OwnershipText(AClient, LCurrentHashes, LNextHashes, 'pending');
    TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient.FileName), LPending, LOwnership, LSidecarExists);
    // One config write commits both entries. Pending hashes recover either side of that atomic write.
    LBackup := TDAIClientSafeFiles.WriteTextWithBackup(AClient.FileName, LNext, LText, LConfigExists);
    if LBackup <> '' then
      Result.AddPair('backup', LBackup);
    LOwned := not LRemove;
    Result.RemovePair('launcher_registered').Free;
    Result.AddPair('launcher_registered', TJSONBool.Create((LEntryCount = 2) and LOwned));
    if LRemove then
      LCommitted := OwnershipText(AClient, ['', ''], ['', ''], 'removed');
    try
      TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient.FileName), LCommitted, LPending, True);
    except
      on E: Exception do
      begin
        SetStatus(Result, 'configured_pending', 'Konfiguration geschrieben; der Ownership-Abschluss ist offen. Beim nächsten Registrieren erneut versuchen.', LOwned);
        Exit;
      end;
    end;
    if LRemove then
      SetStatus(Result, 'removed', 'Die unveränderten eigenen dai/dai_start-Einträge wurden entfernt; andere Inhalte bleiben erhalten.', False)
    else
      SetStatus(Result, 'configured', AClient.Note, True);
  except
    on E: EDAIClientConfigConflict do
      SetStatus(Result, 'conflict', E.Message, LOwned);
    on E: Exception do
      SetStatus(Result, 'error', 'Die Konfiguration konnte nicht sicher bearbeitet werden; Pfad und Schreibrechte prüfen.', LOwned);
  end;
end;

function NormalizeClient(const AClient: string): string;
begin
  Result := LowerCase(Trim(AClient));
  if Result = 'claude' then Result := 'claude-code';
  if Result = 'claude-cli' then Result := 'claude-code';
  if Result = 'claude-vscode' then Result := 'claude-code';
  if Result = 'gemini-cli' then Result := 'gemini';
  if Result = 'gemini-code-assist' then Result := 'gemini';
  if Result = 'lmstudio' then Result := 'lm-studio';
  if Result = 'all' then Result := '';
end;

function Execute(const AAction, AClient: string): TJSONObject;
var
  LClients: TJSONArray;
  LIndex: Integer;
  LDefinition: TClientDefinition;
  LFilter: string;
  LFound: Boolean;
begin
  System.TMonitor.Enter(GRegistrationLock);
  try
    LFilter := NormalizeClient(AClient);
    Result := TJSONObject.Create;
    try
      Result.AddPair('action', AAction);
      Result.AddPair('endpoint', Endpoint);
      LClients := TJSONArray.Create;
      Result.AddPair('clients', LClients);
      LFound := False;
      for LIndex := 0 to 8 do
      begin
        LDefinition := BuildDefinition(LIndex);
        if (LFilter = '') or (LDefinition.Id = LFilter) then
        begin
          LFound := True;
          LClients.AddElement(ProcessClient(LDefinition, AAction, LFilter <> ''));
        end;
      end;
      if not LFound then
        raise EArgumentException.Create('Unbekannter MCP-Client: ' + AClient);
    except
      Result.Free;
      raise;
    end;
  finally
    System.TMonitor.Exit(GRegistrationLock);
  end;
end;

class function TDAIClientRegistration.Status(const AClient: string): TJSONObject;
begin
  Result := Execute('status', AClient);
end;

class function TDAIClientRegistration.RegisterFiles(const AClient: string): TJSONObject;
begin
  Result := Execute('register', AClient);
end;

class function TDAIClientRegistration.UnregisterFiles(const AClient: string): TJSONObject;
begin
  Result := Execute('unregister', AClient);
end;

initialization
  GRegistrationLock := TObject.Create;

finalization
  GRegistrationLock.Free;

end.
