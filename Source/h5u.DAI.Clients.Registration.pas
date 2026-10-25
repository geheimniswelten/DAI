unit h5u.DAI.Clients.Registration;

{$IF CompilerVersion >= 36.0}  // Delphi 12+
{$TEXTBLOCK CRLF}
{$IFEND}

interface

uses
  System.JSON;

type
  TDAIRegistrationHealth = (rhNotRegistered, rhCurrent, rhUpdateRecommended, rhCheckRecommended);

  TDAIClientRegistration = class sealed
  public
    class function Status(const AClient: string = ''): TJSONObject; static;
    class function ManualRegistrationInfo(const AClient: string; const APort: Integer; const AToken: string; const AShared: Boolean): string; static;
    class function Health(out ADetails: string): TDAIRegistrationHealth; static;
    class function ChangeVersion: Integer; static;
    class function RegisterFiles(const AClient: string = ''): TJSONObject; static;
    class function UnregisterFiles(const AClient: string = ''): TJSONObject; static;
    class function FindRegistrations(const AClient: string = ''): TJSONObject; static;
    class function RemoveFoundRegistration(const ACandidate: TJSONObject): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Hash,
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils,
  System.SyncObjs,
  h5u.DAI.Clients.ConfigText,
  h5u.DAI.Clients.SafeFiles,
  h5u.DAI.Codex.Registration,
  h5u.DAI.Consts,
  h5u.DAI.Localization,
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
    ServerName: string;
    LauncherServerName: string;
    ConnectionScope: string;
    RegistryRoot: string;
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
  GChangeVersion: Integer;

function Endpoint(const APort: Integer): string; overload;
begin
  Result := 'http://' + CDAIDefaultBindAddress + ':' + IntToStr(APort) + CDAIMcpPath;
end;

function Endpoint: string; overload;
begin
  Result := Endpoint(TDAISettings.Instance.Port);
end;

function OwnershipFile(const AClient: TClientDefinition): string;
begin
  // Keep the global v1 sidecar path so existing managed registrations remain owned.
  Result := AClient.FileName + '.' + AClient.ServerName + '-registration.json';
end;

function NormalizeRegistryRoot(const ARegistryRoot: string): string;
begin
  Result := StringReplace(Trim(ARegistryRoot), '/', '\', [rfReplaceAll]);
  while Pos('\\', Result) <> 0 do
    Result := StringReplace(Result, '\\', '\', [rfReplaceAll]);
  Result := Result.Trim(['\']);
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

function BuildDefinition(AIndex: Integer; const AShared: Boolean): TClientDefinition; overload;
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
  Result.ServerName := DAIRegistrationServerName(AShared, TDAISettings.Instance.RegistryRoot);
  Result.LauncherServerName := Result.ServerName + '_start';
  if AShared then
    Result.ConnectionScope := 'shared'
  else
  begin
    Result.ConnectionScope := 'ide_profile';
    Result.RegistryRoot := NormalizeRegistryRoot(TDAISettings.Instance.RegistryRoot);
  end;
  Result.Keys := ['mcpServers', Result.ServerName];
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
          Result.Note := DAIText(
                  'Codex CLI, App und IDE-Erweiterung teilen die Benutzerkonfiguration; Client nach Änderungen neu starten.',
                  'Codex CLI, app and IDE extension share the user configuration; restart the client after changes.',
                  'Codex CLI, l’application et l’extension EDI partagent la configuration utilisateur ; redémarrer le client après modification.',
                  'Codex CLI、アプリ、IDE 拡張はユーザー設定を共有します。変更後にクライアントを再起動してください。');
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
          Result.Note := DAIText(
                  'Benutzerscope. Projekt- oder lokale MCP-Konfiguration und Unternehmensrichtlinien können Vorrang haben.',
                  'User scope. Project or local MCP settings and organization policies may take precedence.',
                  'Portée utilisateur. Les paramètres MCP du projet ou locaux et les règles de l’organisation peuvent être prioritaires.',
                  'ユーザー範囲の設定です。プロジェクトやローカルの MCP 設定、組織のポリシーが優先される場合があります。');
        end;
      2:
        begin
          Result.FileName := EnvFile('DAI_CLAUDE_DESKTOP_CONFIG', TPath.Combine(LAppData, 'Claude\claude_desktop_config.json'));
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Transport := 'stdio-http-bridge';
          Result.Documentation := 'https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop';
          Result.Note := DAIText(
                  'Die native Delphi-Bridge verbindet stdio mit dem lokalen HTTP-Server; Claude Desktop vollständig neu starten.',
                  'The native Delphi bridge connects stdio to the local HTTP server; fully restart Claude Desktop.',
                  'La passerelle Delphi native relie stdio au serveur HTTP local ; redémarrer complètement Claude Desktop.',
                  'ネイティブ Delphi ブリッジが stdio をローカル HTTP サーバーに接続します。Claude Desktop を完全に再起動してください。');
        end;
      3:
        begin
          Result.MarkerDirectory := TPath.Combine(LHome, '.eigent');
          Result.Supported := False;
          Result.Documentation := 'https://github.com/eigent-ai/eigent/blob/main/server/README_EN.md';
          Result.Note := DAIText(
                  'Eigent verwaltet MCPs über UI/API. Kein verifiziertes globales mcp.json-Dateischema; ',
                  'Eigent manages MCP through its UI/API. No verified global mcp.json schema; ',
                  'Eigent gère MCP via son interface/API. Aucun schéma mcp.json global vérifié ; ',
                  'Eigent は UI/API で MCP を管理します。確認済みのグローバル mcp.json スキーマはありません。') +
            Result.ServerName + DAIText(
                      ' per URL/Bearer-Header und ',
                      ' through URL/Bearer header and ',
                      ' via URL/en-tête Bearer et ',
                      ' を URL/Bearer ヘッダーで、') + Result.LauncherServerName +
            DAIText(
                      ' bei lokaler STDIO-Unterstützung manuell mit DAI.McpBridge.exe --launcher einrichten.',
                      ' manually using DAI.McpBridge.exe --launcher if local STDIO is supported.',
                      ' manuellement avec DAI.McpBridge.exe --launcher si STDIO local est pris en charge.',
                      ' をローカル STDIO 対応時に DAI.McpBridge.exe --launcher で手動設定してください。');
        end;
      4:
        begin
          LDirectory := EnvDirectory('GEMINI_CLI_HOME', LHome);
          Result.FileName := TPath.Combine(LDirectory, '.gemini\settings.json');
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Documentation := 'https://geminicli.com/docs/tools/mcp-server/';
          Result.Note := DAIText(
                  'Gemini CLI und Code Assist im VS-Code-Agentenmodus. IntelliJ hat eigene MCP-Einstellungen; dort manuell eintragen.',
                  'Gemini CLI and Code Assist in VS Code agent mode. IntelliJ has separate MCP settings; configure them manually.',
                  'Gemini CLI et Code Assist en mode agent VS Code. IntelliJ a ses propres paramètres MCP, à configurer manuellement.',
                  'Gemini CLI と VS Code エージェントモードの Code Assist に対応します。IntelliJ の MCP 設定は個別に手動で行ってください。');
        end;
      5:
        begin
          Result.Supported := False;
          Result.MarkerDirectory := TPath.Combine(LAppData, 'Gemini');
          Result.Documentation := 'https://geminicli.com/docs/tools/mcp-server/';
          Result.Note := DAIText(
                  'Kein offizielles allgemeines MCP-Konfigurationsschema für eine Gemini-Desktop-App verifiziert. Gemini CLI verwenden.',
                  'No official generic MCP configuration schema verified for a Gemini desktop app. Use Gemini CLI.',
                  'Aucun schéma MCP générique officiel vérifié pour une application Gemini de bureau. Utiliser Gemini CLI.',
                  'Gemini デスクトップアプリの公式汎用 MCP 設定スキーマは未確認です。Gemini CLI を使用してください。');
        end;
      6:
        begin
          LDirectory := EnvDirectory('HERMES_HOME', TPath.Combine(LLocalAppData, 'hermes'));
          LLegacy := TPath.Combine(LHome, '.hermes');
          if Trim(GetEnvironmentVariable('HERMES_HOME')) = '' then
          begin
            if TDirectory.Exists(LDirectory) and TDirectory.Exists(LLegacy) then
              Result.BlockReason := DAIText(
                          'Mehrere Hermes-Konfigurationsordner; HERMES_HOME auf das gewünschte Profil setzen.',
                          'Multiple Hermes configuration directories; set HERMES_HOME to the intended profile.',
                          'Plusieurs dossiers de configuration Hermes ; définir HERMES_HOME sur le profil souhaité.',
                          'Hermes 設定フォルダーが複数あります。HERMES_HOME を使用するプロファイルに設定してください。')
            else if TDirectory.Exists(LLegacy) then
              LDirectory := LLegacy;
          end;
          Result.FileName := TPath.Combine(LDirectory, 'config.yaml');
          Result.MarkerDirectory := LDirectory;
          Result.Format := 'yaml';
          Result.Keys := ['mcp_servers', Result.ServerName];
          Result.Documentation := 'https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference';
          Result.Note := DAIText(
                  'Native Windows-Konfiguration. Für ein benanntes Profil HERMES_HOME explizit auf dessen Ordner setzen.',
                  'Native Windows configuration. For a named profile, explicitly set HERMES_HOME to its directory.',
                  'Configuration Windows native. Pour un profil nommé, définir explicitement HERMES_HOME sur son dossier.',
                  'Windows のネイティブ設定です。名前付きプロファイルには HERMES_HOME でフォルダーを明示してください。');
        end;
      7:
        begin
          Result.FileName := EnvFile('DAI_LM_STUDIO_CONFIG', TPath.Combine(LHome, '.lmstudio\mcp.json'));
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Documentation := 'https://lmstudio.ai/docs/app/mcp';
          Result.Note := DAIText(
                  'LM Studio ab 0.3.17; nach Änderungen die MCP-Konfiguration neu laden.',
                  'LM Studio 0.3.17 or later; reload the MCP configuration after changes.',
                  'LM Studio 0.3.17 ou ultérieur ; recharger la configuration MCP après modification.',
                  'LM Studio 0.3.17 以降に対応します。変更後に MCP 設定を再読み込みしてください。');
        end;
      8:
        begin
          LDirectory := EnvDirectory('OPENCLAW_STATE_DIR', TPath.Combine(LHome, '.openclaw'));
          Result.FileName := EnvFile('OPENCLAW_CONFIG_PATH', TPath.Combine(LDirectory, 'openclaw.json'));
          Result.MarkerDirectory := TPath.GetDirectoryName(Result.FileName);
          Result.Format := 'json5';
          Result.Keys := ['mcp', 'servers', Result.ServerName];
          Result.Documentation := 'https://docs.openclaw.ai/tools/mcp';
          Result.Note := DAIText(
                  'Native MCP-Unterstützung erforderlich; Gateway auf diesem Windows-Rechner. openclaw mcp doctor ',
                  'Native MCP support required; gateway on this Windows computer. openclaw mcp doctor ',
                  'Prise en charge MCP native requise ; passerelle sur cet ordinateur Windows. openclaw mcp doctor ',
                  'ネイティブ MCP 対応とこの Windows コンピューター上のゲートウェイが必要です。openclaw mcp doctor ') +
            Result.ServerName + DAIText(
                      ' --probe prüft die Verbindung.',
                      ' --probe checks the connection.',
                      ' --probe vérifie la connexion.',
                      ' --probe で接続を確認できます。');
          if (GetEnvironmentVariable('OPENCLAW_CONFIG_READONLY') = '1') or (GetEnvironmentVariable('OPENCLAW_NIX_MODE') = '1') then
            Result.BlockReason := DAIText(
                      'OpenClaw ist als schreibgeschützt konfiguriert.',
                      'OpenClaw is configured as read-only.',
                      'OpenClaw est configuré en lecture seule.',
                      'OpenClaw は読み取り専用に設定されています。')
          else if (Trim(GetEnvironmentVariable('OPENCLAW_CONFIG_PATH')) = '') and
            ((Trim(GetEnvironmentVariable('OPENCLAW_PROFILE')) <> '') or (Trim(GetEnvironmentVariable('OPENCLAW_HOME')) <> '')) then
            Result.BlockReason := DAIText(
                      'Das OpenClaw-Profil ist mehrdeutig; OPENCLAW_CONFIG_PATH explizit setzen.',
                      'The OpenClaw profile is ambiguous; explicitly set OPENCLAW_CONFIG_PATH.',
                      'Le profil OpenClaw est ambigu ; définir explicitement OPENCLAW_CONFIG_PATH.',
                      'OpenClaw のプロファイルを特定できません。OPENCLAW_CONFIG_PATH を明示してください。');
        end;
    end;
    Result.Detected := TDirectory.Exists(Result.MarkerDirectory) or ((Result.FileName <> '') and
      (TFile.Exists(Result.FileName) or TFile.Exists(OwnershipFile(Result))));
  except
    on E: Exception do
      Result.BlockReason := DAIText(
          'Der Konfigurationspfad ist ungültig oder konnte nicht sicher ermittelt werden.',
          'The configuration path is invalid or could not be determined safely.',
          'Le chemin de configuration est invalide ou n’a pas pu être déterminé de façon sûre.',
          '設定パスが無効か、安全に特定できませんでした。');
  end;
end;

function BuildDefinition(AIndex: Integer): TClientDefinition; overload;
begin
  Result := BuildDefinition(AIndex, TDAISettings.Instance.UseSharedConnectionSettings);
end;

procedure ValidateConnection(const APort: Integer; const AToken: string);
var
  LCharacter: Char;
begin
  if (APort < 1024) or (APort > 65535) then
    raise EDAIClientConfigConflict.Create('Der MCP-Port muss zwischen 1024 und 65535 liegen.');
  if Trim(AToken) = '' then
    raise EDAIClientConfigConflict.Create('Ein leerer Bearer-Token kann nicht registriert werden.');
  for LCharacter in AToken do
    if (Ord(LCharacter) < 32) or (Ord(LCharacter) = 127) then
      raise EDAIClientConfigConflict.Create('Steuerzeichen im Bearer-Token werden nicht registriert.');
end;

function BuildEntry(const AClient: TClientDefinition; const APort: Integer; const AToken: string): string; overload;
var
  LEntry: TJSONObject;
  LHeaders: TJSONObject;
  LEnvironment: TJSONObject;
begin
  ValidateConnection(APort, AToken);
  if AClient.Format = 'yaml' then
    Exit(Format(
      {$IF CompilerVersion >= 36.0}  // Delphi 12+
      '''
      %s:
        url: %s
        headers:
          Authorization: %s
        timeout: 180
      ''',
      {$ELSE}
      '%s:' + sLineBreak +
      '  url: %s' + sLineBreak +
      '  headers:' + sLineBreak +
      '    Authorization: %s' + sLineBreak +
      '  timeout: 180'
      ,
      {$IFEND}
      [AClient.ServerName, JsonString(Endpoint(APort)), JsonString('Bearer ' + AToken)]));
  LEntry := TJSONObject.Create;
  try
    if AClient.Id = 'claude-desktop' then
    begin
      LEntry.AddPair('command', BridgeFileName);
      LEntry.AddPair('args', TJSONArray.Create('--url', Endpoint(APort)));
      LEnvironment := TJSONObject.Create;
      LEnvironment.AddPair('DAI_MCP_TOKEN', AToken);
      LEntry.AddPair('env', LEnvironment);
    end
    else
    begin
      if AClient.Id = 'claude-code' then
        LEntry.AddPair('type', 'http');
      if AClient.Id = 'gemini' then
        LEntry.AddPair('httpUrl', Endpoint(APort))
      else
        LEntry.AddPair('url', Endpoint(APort));
      if AClient.Id = 'openclaw' then
      begin
        LEntry.AddPair('transport', 'streamable-http');
        LEntry.AddPair('enabled', TJSONBool.Create(True));
        LEntry.AddPair('requestTimeoutMs', TJSONNumber.Create(180000));
      end;
      if AClient.Id = 'gemini' then
        LEntry.AddPair('timeout', TJSONNumber.Create(180000));
      LHeaders := TJSONObject.Create;
      LHeaders.AddPair('Authorization', 'Bearer ' + AToken);
      LEntry.AddPair('headers', LHeaders);
    end;
    Result := LEntry.ToJSON;
  finally
    LEntry.Free;
  end;
end;

function BuildEntry(const AClient: TClientDefinition): string; overload;
begin
  Result := BuildEntry(AClient, TDAISettings.Instance.Port, TDAISettings.Instance.Token);
end;

function LauncherArguments(const APort: Integer): TArray<string>;
var
  LIndex: Integer;
begin
  Result := TDAICodexRegistration.LauncherArguments;
  for LIndex := 0 to High(Result) - 1 do
    if Result[LIndex] = '--url' then
    begin
      Result[LIndex + 1] := Endpoint(APort);
      Exit;
    end;
  raise EDAIClientConfigConflict.Create('Der Starthelfer enthält keine HTTP-Verbindungsadresse.');
end;

function BuildLauncherEntry(const AClient: TClientDefinition; const APort: Integer; const AToken: string): string; overload;
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
    for LArgument in LauncherArguments(APort) do
      LArguments.Add(LArgument);
    LEnvironment := TJSONObject.Create;
    LEnvironment.AddPair('DAI_MCP_TOKEN', AToken);
    LEntry.AddPair('env', LEnvironment);
    if AClient.Format = 'yaml' then
      Exit(AClient.LauncherServerName + ':' + sLineBreak +
        '  command: ' + JsonString(BridgeFileName) + sLineBreak +
        '  args: ' + LArguments.ToJSON + sLineBreak +
        '  env:' + sLineBreak +
        '    DAI_MCP_TOKEN: ' + JsonString(AToken) + sLineBreak +
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

function BuildLauncherEntry(const AClient: TClientDefinition): string; overload;
begin
  Result := BuildLauncherEntry(AClient, TDAISettings.Instance.Port, TDAISettings.Instance.Token);
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
    LJson.AddPair('server_name', AClient.ServerName);
    LJson.AddPair('launcher_server', AClient.LauncherServerName);
    LJson.AddPair('connection_scope', AClient.ConnectionScope);
    LJson.AddPair('registry_root', AClient.RegistryRoot);
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
    if LJson.GetValue('connection_scope') = nil then
    begin
      // Only the unchanged global names may adopt an old v1 sidecar without scope metadata.
      if (AClient.ConnectionScope <> 'shared') or (LJson.GetValue('server_name') <> nil) or
        (LJson.GetValue('launcher_server') <> nil) or (LJson.GetValue('registry_root') <> nil) then
        Exit;
    end
    else if not (LJson.GetValue('server_name') is TJSONString) or
      not (LJson.GetValue('launcher_server') is TJSONString) or
      not (LJson.GetValue('connection_scope') is TJSONString) or
      not (LJson.GetValue('registry_root') is TJSONString) or
      (ReadJsonString(LJson, 'server_name') <> AClient.ServerName) or
      (ReadJsonString(LJson, 'launcher_server') <> AClient.LauncherServerName) or
      (ReadJsonString(LJson, 'connection_scope') <> AClient.ConnectionScope) or
      not SameText(NormalizeRegistryRoot(ReadJsonString(LJson, 'registry_root')), AClient.RegistryRoot) then
      Exit;
    if not (LJson.GetValue('entry_sha256') is TJSONString) or
      not (LJson.GetValue('pending_sha256') is TJSONString) or
      ((LJson.GetValue('launcher_entry_sha256') <> nil) and not (LJson.GetValue('launcher_entry_sha256') is TJSONString)) or
      ((LJson.GetValue('launcher_pending_sha256') <> nil) and not (LJson.GetValue('launcher_pending_sha256') is TJSONString)) then
      Exit;
    AHash[0] := ReadJsonString(LJson, 'entry_sha256');
    APendingHash[0] := ReadJsonString(LJson, 'pending_sha256');
    // Older global v1 sidecars own dai only. Missing launcher hashes never grant launcher ownership.
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

function ProcessClient(const AClient: TClientDefinition; const AAction: string; AExplicit: Boolean;
  const AExpectedConfigHash: string = ''; const AExpectedOwnershipHash: string = ''): TJSONObject;
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
  Result.AddPair('server_name', AClient.ServerName);
  Result.AddPair('launcher_server', AClient.LauncherServerName);
  Result.AddPair('connection_scope', AClient.ConnectionScope);
  Result.AddPair('launcher_supported', TJSONBool.Create(AClient.LauncherSupported));
  if AClient.LauncherSupported then
  begin
    Result.AddPair('launcher_transport', 'stdio');
    Result.AddPair('bridge_path', BridgeFileName);
    Result.AddPair('bridge_exists', TJSONBool.Create(TFile.Exists(BridgeFileName)));
  end;
  if (AClient.FileName <> '') and (AClient.Id <> 'codex') then
    Result.AddPair('ownership_file', OwnershipFile(AClient));
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
      SetStatus(Result, 'not_detected', DAIText(
        'Kein vorhandener Konfigurationsordner erkannt; zur Erstregistrierung den Client ausdrücklich auswählen.',
        'No existing configuration directory found; explicitly select the client for initial registration.',
        'Aucun dossier de configuration existant détecté ; sélectionner explicitement le client pour la première inscription.',
        '既存の設定フォルダーが見つかりません。初回登録ではクライアントを明示的に選択してください。'), False);
      Exit;
    end;
    if AClient.Id = 'codex' then
    begin
      if (AAction = 'register') and not TFile.Exists(BridgeFileName) then
      begin
        SetStatus(Result, 'missing_bridge', DAIText(
          'DAI.McpBridge.exe fehlt neben dem DAI-Package; den Launcher zuerst bauen bzw. installieren.',
          'DAI.McpBridge.exe is missing beside the DAI package; build or install the launcher first.',
          'DAI.McpBridge.exe est absent à côté du package DAI ; compiler ou installer d’abord le lanceur.',
          'DAI パッケージの隣に DAI.McpBridge.exe がありません。先にランチャーをビルドまたはインストールしてください。'), False);
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
        SetStatus(Result, 'needs_update', DAIText(
          'Die verwaltete Codex-Registrierung passt nicht zu ',
          'The managed Codex registration does not match ',
          'L’inscription Codex gérée ne correspond pas à ',
          '管理対象の Codex 登録が ') + AClient.ServerName + '/' +
          AClient.LauncherServerName + DAIText(
            ', Port, Token oder IDE; erneut registrieren.',
            ', port, token or IDE; register again.',
            ', au port, au jeton ou à l’EDI ; réinscrire.',
            '、ポート、トークン、IDE と一致しません。再登録してください。'), True)
      else if LCodexRegistered then
        SetStatus(Result, 'registered', AClient.Note, True)
      else if AAction = 'unregister' then
        SetStatus(Result, 'removed', DAIText(
          'Die verwaltete Codex-Registrierung wurde entfernt.',
          'The managed Codex registration was removed.',
          'L’inscription Codex gérée a été supprimée.',
          '管理対象の Codex 登録を削除しました。'), False)
      else if not AClient.Detected then
        SetStatus(Result, 'not_detected', AClient.Note, False)
      else
        SetStatus(Result, 'not_registered', AClient.Note, False);
      Exit;
    end;
    TDAIClientSafeFiles.ValidatePath(AClient.FileName, AAction <> 'status');
    TDAIClientSafeFiles.ValidatePath(OwnershipFile(AClient), AAction <> 'status');
    LConfigExists := TFile.Exists(AClient.FileName);
    LSidecarExists := TFile.Exists(OwnershipFile(AClient));
    LText := TDAIClientSafeFiles.ReadTextIfExists(AClient.FileName);
    LOwnership := TDAIClientSafeFiles.ReadTextIfExists(OwnershipFile(AClient));
    if ((AExpectedConfigHash <> '') and (HashEntry(LText) <> AExpectedConfigHash)) or
      ((AExpectedOwnershipHash <> '') and (HashEntry(LOwnership) <> AExpectedOwnershipHash)) then
      raise EDAIClientConfigConflict.Create(DAIText(
        'Die Registrierung wurde seit der Suche geändert; bitte erneut suchen.',
        'The registration has changed since the search; search again.',
        'L’inscription a changé depuis la recherche ; relancer la recherche.',
        '検索後に登録内容が変更されました。再検索してください。'));
    LStoredHashes := ['', ''];
    LPendingHashes := ['', ''];
    LCurrentHashes := ['', ''];
    LNextHashes := ['', ''];
    if LSidecarExists and not ValidOwnership(AClient, LOwnership, LStoredHashes, LPendingHashes) then
      raise EDAIClientConfigConflict.Create(DAIText(
        'Die vorhandene Ownership-Datei ist fremd oder ungültig; sie bleibt erhalten.',
        'The existing ownership file is foreign or invalid; it is retained.',
        'Le fichier de propriété existant est étranger ou invalide ; il est conservé.',
        '既存の所有情報ファイルは他の登録に属するか無効です。そのまま保持します。'));
    LEntryCount := 1;
    LEntries[0].Name := AClient.ServerName;
    LEntries[0].Keys := AClient.Keys;
    if AClient.LauncherSupported then
    begin
      LEntryCount := 2;
      LEntries[1].Name := AClient.LauncherServerName;
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
        SetStatus(Result, 'conflict', DAIText(
          'Ein fremder oder nachträglich veränderter ',
          'A foreign or subsequently edited ',
          'Une entrée étrangère ou modifiée ultérieurement ',
          '他の登録に属するか後から変更された ') +
          LEntries[LIndex].Name + DAIText(
            '-Eintrag existiert; beide Einträge bleiben erhalten.',
            ' entry exists; both entries are retained.',
            ' existe ; les deux entrées sont conservées.',
            ' エントリが存在します。両方のエントリを保持します。'), False);
        Exit;
      end;
    end;
    Result.AddPair('launcher_registered', TJSONBool.Create((LEntryCount = 2) and LEntries[1].Owned));
    if AClient.LauncherSupported and not TFile.Exists(BridgeFileName) and (AAction <> 'unregister') then
    begin
      SetStatus(Result, 'missing_bridge', DAIText(
        'DAI.McpBridge.exe fehlt neben dem DAI-Package; native Delphi-Bridge zuerst bauen bzw. installieren.',
        'DAI.McpBridge.exe is missing beside the DAI package; build or install the native Delphi bridge first.',
        'DAI.McpBridge.exe est absent à côté du package DAI ; compiler ou installer d’abord la passerelle Delphi native.',
        'DAI パッケージの隣に DAI.McpBridge.exe がありません。先にネイティブ Delphi ブリッジをビルドまたはインストールしてください。'), LOwned);
      Exit;
    end;
    LRemove := AAction = 'unregister';
    if LRemove and not LAnyExists then
    begin
      if LSidecarExists then
        TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient),
          OwnershipText(AClient, ['', ''], ['', ''], 'removed'), LOwnership, True);
      SetStatus(Result, 'unchanged', DAIText(
        'Kein unveränderter eigener ',
        'No unchanged owned ',
        'Aucune entrée propre non modifiée ',
        '削除できる未変更の自分の ') + AClient.ServerName + '/' +
        AClient.LauncherServerName + DAIText(
          '-Eintrag zu entfernen.',
          ' entry to remove.',
          ' à supprimer.',
          ' エントリはありません。'), False);
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
          SetStatus(Result, 'needs_update', DAIText(
            'Der verwaltete Eintrag passt nicht zu ',
            'The managed entry does not match ',
            'L’entrée gérée ne correspond pas à ',
            '管理対象のエントリが ') + AClient.ServerName + '/' +
            AClient.LauncherServerName + DAIText(
              ', Port, Token, Bridge oder IDE; erneut registrieren.',
              ', port, token, bridge or IDE; register again.',
              ', au port, au jeton, à la passerelle ou à l’EDI ; réinscrire.',
              '、ポート、トークン、ブリッジ、IDE と一致しません。再登録してください。'), True);
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
        TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient), LCommitted, LOwnership, LSidecarExists);
      SetStatus(Result, 'unchanged', DAIText(
        'Bereits passend registriert.',
        'Already registered with matching settings.',
        'Déjà inscrit avec les paramètres correspondants.',
        '適切な設定で登録済みです。'), LAllOwned);
      Exit;
    end;
    LPending := OwnershipText(AClient, LCurrentHashes, LNextHashes, 'pending');
    TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient), LPending, LOwnership, LSidecarExists);
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
      TDAIClientSafeFiles.WriteTextWithBackup(OwnershipFile(AClient), LCommitted, LPending, True);
    except
      on E: Exception do
      begin
        SetStatus(Result, 'configured_pending', DAIText(
          'Konfiguration geschrieben; der Ownership-Abschluss ist offen. Beim nächsten Registrieren erneut versuchen.',
          'Configuration written; ownership finalization is pending. Retry on the next registration.',
          'Configuration écrite ; la finalisation de la propriété est en attente. Réessayer à la prochaine inscription.',
          '設定を書き込みましたが、所有情報の確定が未完了です。次回の登録時に再試行してください。'), LOwned);
        Exit;
      end;
    end;
    if LRemove then
      SetStatus(Result, 'removed', DAIText(
        'Die unveränderten eigenen ',
        'The unchanged owned ',
        'Les entrées propres non modifiées ',
        '未変更の自分の ') + AClient.ServerName + '/' +
        AClient.LauncherServerName + DAIText(
          '-Einträge wurden entfernt; andere Inhalte bleiben erhalten.',
          ' entries were removed; other content is retained.',
          ' ont été supprimées ; les autres contenus sont conservés.',
          ' エントリを削除しました。他の内容は保持されます。'), False)
    else
      SetStatus(Result, 'configured', AClient.Note, True);
  except
    on E: EDAIClientConfigConflict do
      SetStatus(Result, 'conflict', E.Message, LOwned);
    on E: Exception do
      SetStatus(Result, 'error', DAIText(
        'Die Konfiguration konnte nicht sicher bearbeitet werden; Pfad und Schreibrechte prüfen.',
        'The configuration could not be edited safely; check the path and write permissions.',
        'La configuration n’a pas pu être modifiée de façon sûre ; vérifier le chemin et les droits d’écriture.',
        '設定を安全に編集できませんでした。パスと書き込み権限を確認してください。'), LOwned);
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

function FoundDefinition(const ABase: TClientDefinition; const AServerName, AOwnership: string): TClientDefinition;
var
  LValue: TJSONValue;
  LJson: TJSONObject;
begin
  if not TRegEx.IsMatch(AServerName, '^dai(?:_bds[0-9]+_[0-9]+(?:_p[a-f0-9]{16})?)?$') then
    raise EDAIClientConfigConflict.Create(DAIText(
      'Unbekannter DAI-Registrierungsname.',
      'Unknown DAI registration name.',
      'Nom d’inscription DAI inconnu.',
      '不明な DAI 登録名です。'));
  Result := ABase;
  Result.ServerName := AServerName;
  Result.LauncherServerName := AServerName + '_start';
  Result.Keys := Copy(ABase.Keys);
  Result.Keys[High(Result.Keys)] := AServerName;
  Result.RegistryRoot := '';
  Result.ConnectionScope := 'shared';
  if AServerName <> 'dai' then
    Result.ConnectionScope := 'ide_profile';
  // Reject duplicate JSON properties before reading scope metadata.
  TDAIClientConfigText.ExtractEntry(AOwnership, 'json', ['owner'], Result.Note);
  LValue := TJSONObject.ParseJSONValue(AOwnership);
  try
    if not (LValue is TJSONObject) then
      raise EDAIClientConfigConflict.Create('Die Ownership-Datei ist ungültig.');
    LJson := TJSONObject(LValue);
    Result.RegistryRoot := NormalizeRegistryRoot(ReadJsonString(LJson, 'registry_root'));
    if DAIRegistrationServerName(Result.ConnectionScope = 'shared', Result.RegistryRoot) <> AServerName then
      raise EDAIClientConfigConflict.Create('Name und IDE-Profil der Registrierung passen nicht zusammen.');
    if (Result.ConnectionScope = 'shared') and (Result.RegistryRoot <> '') then
      raise EDAIClientConfigConflict.Create('Der gemeinsame Eintrag enthält einen fremden IDE-Registrypfad.');
  finally
    LValue.Free;
  end;
end;

function FoundCandidate(const ABase: TClientDefinition; const AServerName: string): TJSONObject;
var
  LClient: TClientDefinition;
  LOwnership, LText, LEntry, LStatus, LMessage, LEntryHash: string;
  LStored, LPending: TArray<string>;
  LKeys: TArray<string>;
  LIndex, LExisting: Integer;
  LRemovable, LValid, LExists: Boolean;
begin
  LClient := ABase;
  LClient.ServerName := AServerName;
  LClient.LauncherServerName := AServerName + '_start';
  LClient.ConnectionScope := 'shared';
  LClient.RegistryRoot := '';
  if AServerName <> 'dai' then
    LClient.ConnectionScope := 'ide_profile';
  LStatus := 'conflict';
  LMessage := DAIText(
    'Die Registrierung ist fremd, verändert oder nicht sicher lesbar; sie bleibt erhalten.',
    'The registration is foreign, modified or cannot be read safely; it is retained.',
    'L’inscription est étrangère, modifiée ou illisible de façon sûre ; elle est conservée.',
    'この登録は他のアプリに属するか、変更済みか、安全に読み取れません。そのまま保持します。');
  LText := '';
  LOwnership := '';
  LRemovable := False;
  LExisting := 0;
  try
    TDAIClientSafeFiles.ValidatePath(LClient.FileName);
    TDAIClientSafeFiles.ValidatePath(OwnershipFile(LClient));
    LText := TDAIClientSafeFiles.ReadTextIfExists(LClient.FileName);
    LOwnership := TDAIClientSafeFiles.ReadTextIfExists(OwnershipFile(LClient));
    LClient := FoundDefinition(ABase, AServerName, LOwnership);
    LValid := ValidOwnership(LClient, LOwnership, LStored, LPending);
    if LValid then
    begin
      LKeys := Copy(LClient.Keys);
      for LIndex := 0 to 1 do
      begin
        if LIndex = 0 then
          LKeys[High(LKeys)] := LClient.ServerName
        else
          LKeys[High(LKeys)] := LClient.LauncherServerName;
        LExists := TDAIClientConfigText.ExtractEntry(LText, LClient.Format, LKeys, LEntry);
        if LExists then
        begin
          Inc(LExisting);
          LEntryHash := HashEntry(LEntry);
          if (LEntryHash <> LStored[LIndex]) and (LEntryHash <> LPending[LIndex]) then
            LValid := False;
        end;
      end;
      if LValid and (LExisting > 0) then
      begin
        LRemovable := ABase.BlockReason = '';
        LStatus := 'managed';
        LMessage := DAIText(
          'Unveränderte DAI-Registrierung; kann gezielt entfernt werden.',
          'Unmodified DAI registration; it can be removed individually.',
          'Inscription DAI non modifiée ; elle peut être supprimée individuellement.',
          '未変更の DAI 登録です。個別に削除できます。');
        if not LRemovable then
        begin
          LStatus := 'conflict';
          LMessage := ABase.BlockReason;
        end;
      end
      else if LValid then
      begin
        // Successful unregister leaves an ownership tombstone for recovery, not an installed entry.
        LStatus := 'not_registered';
        LMessage := DAIText(
          'Die Ownership-Datei enthält keinen vorhandenen DAI-Eintrag.',
          'The ownership file contains no existing DAI entry.',
          'Le fichier de propriété ne contient aucune entrée DAI existante.',
          '所有情報ファイルに既存の DAI エントリがありません。');
      end;
    end;
  except
    on E: Exception do
    begin
      LStatus := 'conflict';
      LRemovable := False;
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('client', ABase.Id);
  Result.AddPair('label', ABase.LabelText);
  Result.AddPair('path', ABase.FileName);
  Result.AddPair('server_name', AServerName);
  Result.AddPair('launcher_server', AServerName + '_start');
  Result.AddPair('connection_scope', LClient.ConnectionScope);
  Result.AddPair('registry_root', LClient.RegistryRoot);
  Result.AddPair('current_scope', TJSONBool.Create(AServerName = ABase.ServerName));
  Result.AddPair('removable', TJSONBool.Create(LRemovable));
  Result.AddPair('status', LStatus);
  Result.AddPair('message', LMessage);
  Result.AddPair('config_sha256', HashEntry(LText));
  Result.AddPair('ownership_sha256', HashEntry(LOwnership));
end;

procedure FindClientRegistrations(const ABase: TClientDefinition; const AResults: TJSONArray);
var
  LDirectory, LFile, LName, LPrefix, LServer, LOwnership: string;
  LFiles: TArray<string>;
  LCandidate, LJson: TJSONObject;
  LValue: TJSONValue;
begin
  if not ABase.Supported or (ABase.FileName = '') then
    Exit;
  LDirectory := TPath.GetDirectoryName(ABase.FileName);
  if not TDirectory.Exists(LDirectory) then
    Exit;
  try
    TDAIClientSafeFiles.ValidatePath(ABase.FileName);
    LPrefix := TPath.GetFileName(ABase.FileName) + '.';
    LFiles := TDirectory.GetFiles(LDirectory, LPrefix + 'dai*-registration.json', TSearchOption.soTopDirectoryOnly);
  except
    on E: Exception do
      Exit;
  end;
  for LFile in LFiles do
  begin
    LName := TPath.GetFileName(LFile);
    LServer := Copy(LName, Length(LPrefix) + 1, Length(LName) - Length(LPrefix) - Length('-registration.json'));
    if not TRegEx.IsMatch(LServer, '^dai(?:_bds[0-9]+_[0-9]+(?:_p[a-f0-9]{16})?)?$') then
      Continue;
    LCandidate := FoundCandidate(ABase, LServer);
    if ReadJsonString(LCandidate, 'status') = 'not_registered' then
    begin
      // Removed sidecars are normal transaction history and should not fill the search list.
      LValue := nil;
      try
        LOwnership := TDAIClientSafeFiles.ReadTextIfExists(LFile);
        LValue := TJSONObject.ParseJSONValue(LOwnership);
        if LValue is TJSONObject then
        begin
          LJson := TJSONObject(LValue);
          if ReadJsonString(LJson, 'state') = 'removed' then
          begin
            LCandidate.Free;
            LCandidate := nil;
          end;
        end;
      except
        on E: Exception do
          ;
      end;
      LValue.Free;
    end;
    if LCandidate <> nil then
      AResults.AddElement(LCandidate);
  end;
end;

function RemovalResult(const ACandidate: TJSONObject; const AStatus, AMessage: string; ARemoved: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('removed', TJSONBool.Create(ARemoved));
  Result.AddPair('status', AStatus);
  Result.AddPair('message', AMessage);
  if ACandidate <> nil then
  begin
    Result.AddPair('server_name', ReadJsonString(ACandidate, 'server_name'));
    Result.AddPair('path', ReadJsonString(ACandidate, 'path'));
  end;
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
    TDAISettings.Instance.RefreshConnectionSettings;
    LFilter := NormalizeClient(AClient);
    Result := TJSONObject.Create;
    try
      Result.AddPair('action', AAction);
      Result.AddPair('endpoint', Endpoint);
      Result.AddPair('server_name', TDAICodexRegistration.ServerName);
      Result.AddPair('launcher_server', TDAICodexRegistration.LauncherServerName);
      if TDAISettings.Instance.UseSharedConnectionSettings then
        Result.AddPair('connection_scope', 'shared')
      else
        Result.AddPair('connection_scope', 'ide_profile');
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

function ManualCodexConfig(const AClient: TClientDefinition; const APort: Integer; const AToken: string): string;
var
  LArguments: TJSONArray;
  LArgument: string;
begin
  LArguments := TJSONArray.Create;
  try
    for LArgument in LauncherArguments(APort) do
      LArguments.Add(LArgument);
    Result := '[mcp_servers.' + AClient.ServerName + ']' + sLineBreak +
      'url = ' + JsonString(Endpoint(APort)) + sLineBreak +
      'enabled = true' + sLineBreak +
      'http_headers = { Authorization = ' + JsonString('Bearer ' + AToken) + ' }' + sLineBreak +
      '[mcp_servers.' + AClient.LauncherServerName + ']' + sLineBreak +
      'command = ' + JsonString(BridgeFileName) + sLineBreak +
      'args = ' + LArguments.ToJSON + sLineBreak +
      'env = { DAI_MCP_TOKEN = ' + JsonString(AToken) + ' }' + sLineBreak +
      'enabled = true';
  finally
    LArguments.Free;
  end;
end;

function ManualClientConfig(const AClient: TClientDefinition; const APort: Integer; const AToken: string): string;
var
  LKeys: TArray<string>;
begin
  if AClient.Id = 'codex' then
    Exit(ManualCodexConfig(AClient, APort, AToken));
  Result := TDAIClientConfigText.Merge('', AClient.Format, AClient.Keys, BuildEntry(AClient, APort, AToken), False);
  if AClient.LauncherSupported then
  begin
    LKeys := Copy(AClient.Keys);
    LKeys[High(LKeys)] := AClient.LauncherServerName;
    Result := TDAIClientConfigText.Merge(Result, AClient.Format, LKeys, BuildLauncherEntry(AClient, APort, AToken), False);
  end;
end;

class function TDAIClientRegistration.ManualRegistrationInfo(const AClient: string; const APort: Integer; const AToken: string; const AShared: Boolean): string;
var
  LClient, LGeneric: TClientDefinition;
  LIndex: Integer;
  LFilter, LArguments, LConfig: string;
  LArgument: string;
  LText: TStringList;
begin
  ValidateConnection(APort, AToken);
  LFilter := NormalizeClient(AClient);
  LClient := Default(TClientDefinition);
  for LIndex := 0 to 8 do
  begin
    LGeneric := BuildDefinition(LIndex, AShared);
    if LGeneric.Id = LFilter then
    begin
      LClient := LGeneric;
      Break;
    end;
  end;
  LGeneric := BuildDefinition(2, AShared);
  LArguments := '';
  for LArgument in LauncherArguments(APort) do
  begin
    if LArguments <> '' then
      LArguments := LArguments + ', ';
    LArguments := LArguments + JsonString(LArgument);
  end;
  LText := TStringList.Create;
  try
    LText.Add(DAIText(
      'Manuelle MCP-Registrierung',
      'Manual MCP registration',
      'Inscription MCP manuelle',
      'MCP の手動登録'));
    if LClient.Id <> '' then
      LText.Add(DAIText(
          'Client: ',
          'Client: ',
          'Client : ',
          'クライアント: ') + LClient.LabelText);
    if AShared then
      LText.Add(DAIText(
          'Verbindung: gemeinsam für alle Delphi-Versionen',
          'Connection: shared by all Delphi versions',
          'Connexion : partagée par toutes les versions de Delphi',
          '接続: すべての Delphi バージョンで共有'))
    else
      LText.Add(DAIText(
          'Verbindung: dieses IDE-Profil (',
          'Connection: this IDE profile (',
          'Connexion : ce profil de l’EDI (',
          '接続: この IDE プロファイル (') + TDAISettings.Instance.RegistryRoot + ')');
    LText.Add(DAIText(
      'Servername: ',
      'Server name: ',
      'Nom du serveur : ',
      'サーバー名: ') + LGeneric.ServerName);
    LText.Add(DAIText(
      'Transport: Streamable HTTP, nur lokaler Rechner',
      'Transport: Streamable HTTP, local computer only',
      'Transport : Streamable HTTP, ordinateur local uniquement',
      'トランスポート: Streamable HTTP、ローカルコンピューターのみ'));
    LText.Add('URL: ' + Endpoint(APort));
    LText.Add(DAIText(
      'HTTP-Header: Authorization: Bearer ',
      'HTTP header: Authorization: Bearer ',
      'En-tête HTTP : Authorization: Bearer ',
      'HTTP ヘッダー: Authorization: Bearer ') + AToken);
    LText.Add('');
    LText.Add(DAIText(
      'Alternativ MCP über STDIO:',
      'Alternatively, MCP over STDIO:',
      'Autre possibilité : MCP via STDIO :',
      '代替接続: STDIO 経由の MCP:'));
    LText.Add(DAIText(
      'Programm: ',
      'Program: ',
      'Programme : ',
      'プログラム: ') + BridgeFileName);
    LText.Add(DAIText(
      'Argumente (JSON-Liste): ["--url", ',
      'Arguments (JSON array): ["--url", ',
      'Arguments (tableau JSON) : ["--url", ',
      '引数 (JSON 配列): ["--url", ') + JsonString(Endpoint(APort)) + ']');
    LText.Add(DAIText(
      'Umgebungsvariable: DAI_MCP_TOKEN=',
      'Environment variable: DAI_MCP_TOKEN=',
      'Variable d’environnement : DAI_MCP_TOKEN=',
      '環境変数: DAI_MCP_TOKEN=') + AToken);
    LText.Add('');
    LText.Add(DAIText(
      'Zusätzlicher Starthelfer (MCP über STDIO): ',
      'Additional launcher (MCP over STDIO): ',
      'Lanceur supplémentaire (MCP via STDIO) : ',
      '追加ランチャー (STDIO 経由の MCP): ') + LGeneric.LauncherServerName);
    LText.Add(DAIText(
      'Programm: ',
      'Program: ',
      'Programme : ',
      'プログラム: ') + BridgeFileName);
    LText.Add(DAIText(
      'Delphi-IDE: ',
      'Delphi IDE: ',
      'EDI Delphi : ',
      'Delphi IDE: ') + TDAICodexRegistration.HostIDEExecutable);
    LText.Add(DAIText(
      'Argumente (JSON-Liste): [',
      'Arguments (JSON array): [',
      'Arguments (tableau JSON) : [',
      '引数 (JSON 配列): [') + LArguments + ']');
    LText.Add(DAIText(
      'Umgebungsvariable: DAI_MCP_TOKEN=',
      'Environment variable: DAI_MCP_TOKEN=',
      'Variable d’environnement : DAI_MCP_TOKEN=',
      '環境変数: DAI_MCP_TOKEN=') + AToken);
    LText.Add(DAIText(
      'Der Starthelfer startet oder beendet Delphi nur auf ausdrücklichen Auftrag und entsprechend der DAI-Option.',
      'The launcher starts or closes Delphi only on explicit request and according to the DAI option.',
      'Le lanceur démarre ou ferme Delphi uniquement sur demande explicite et selon l’option DAI.',
      'ランチャーは明示的な要求があり、DAI の設定で許可されている場合にのみ Delphi を起動または終了します。'));
    LText.Add('');
    if (LClient.Id <> '') and LClient.Supported then
    begin
      LText.Add(DAIText(
          'Konfigurationsdatei: ',
          'Configuration file: ',
          'Fichier de configuration : ',
          '設定ファイル: ') + LClient.FileName);
      LText.Add(DAIText(
          'Format: ',
          'Format: ',
          'Format : ',
          '形式: ') + LClient.Format);
      LConfig := ManualClientConfig(LClient, APort, AToken);
    end
    else
    begin
      LText.Add(DAIText(
          'In den MCP-Einstellungen des Clients URL und HTTP-Header oder Programm, Argumente und Umgebung eintragen.',
          'In the client’s MCP settings, enter the URL and HTTP header or the program, arguments and environment.',
          'Dans les paramètres MCP du client, saisir l’URL et l’en-tête HTTP ou le programme, les arguments et l’environnement.',
          'クライアントの MCP 設定に、URL と HTTP ヘッダー、またはプログラム、引数、環境変数を入力します。'));
      LText.Add(DAIText(
          'Allgemeines STDIO-Beispiel im mcpServers-Schema; Unterstützung im Client prüfen.',
          'Generic STDIO example using the mcpServers schema; check client support.',
          'Exemple STDIO générique au format mcpServers ; vérifier sa prise en charge par le client.',
          'mcpServers スキーマの汎用 STDIO 設定例です。クライアントが対応しているか確認してください。'));
      LConfig := ManualClientConfig(LGeneric, APort, AToken);
    end;
    if LClient.BlockReason <> '' then
      LText.Add(DAIText(
          'Pfadhinweis: ',
          'Path note: ',
          'Remarque sur le chemin : ',
          'パスに関する注意: ') + LClient.BlockReason);
    if LClient.Note <> '' then
      LText.Add(LClient.Note);
    if LClient.Documentation <> '' then
      LText.Add(DAIText(
          'Dokumentation: ',
          'Documentation: ',
          'Documentation : ',
          'ドキュメント: ') + LClient.Documentation);
    LText.Add('');
    LText.Add(DAIText(
      'Die Werte entsprechen der aktuellen Auswahl im Einstellungsfenster. Geänderte Werte zuerst in DAI speichern.',
      'The values reflect the current selection in the settings window. Save changed values in DAI first.',
      'Les valeurs correspondent au choix actuel dans les paramètres. Enregistrer d’abord les modifications dans DAI.',
      '設定画面で現在選択されている値です。変更した値は先に DAI で保存してください。'));
    LText.Add(DAIText(
      'Vorhandene andere MCP-Einträge erhalten; Client danach neu laden oder neu starten.',
      'Keep other existing MCP entries; reload or restart the client afterwards.',
      'Conserver les autres entrées MCP existantes, puis recharger ou redémarrer le client.',
      '既存の他の MCP エントリは保持し、その後クライアントを再読み込みまたは再起動してください。'));
    LText.Add(DAIText(
      'Es werden keine Konfigurationsdateien geschrieben und keine Registrierungen verändert.',
      'No configuration files are written and no registrations are changed.',
      'Aucun fichier de configuration n’est écrit et aucune inscription n’est modifiée.',
      '設定ファイルの書き込みや登録内容の変更は行いません。'));
    LText.Add('');
    LText.Add(DAIText(
      'Konfiguration zum Übernehmen:',
      'Configuration to copy:',
      'Configuration à copier :',
      'コピーする設定:'));
    LText.Add(LConfig);
    Result := LText.Text;
  finally
    LText.Free;
  end;
end;

class function TDAIClientRegistration.Status(const AClient: string): TJSONObject;
begin
  Result := Execute('status', AClient);
end;

class function TDAIClientRegistration.RegisterFiles(const AClient: string): TJSONObject;
begin
  try
    Result := Execute('register', AClient);
  finally
    TInterlocked.Increment(GChangeVersion);
  end;
end;

class function TDAIClientRegistration.UnregisterFiles(const AClient: string): TJSONObject;
begin
  try
    Result := Execute('unregister', AClient);
  finally
    TInterlocked.Increment(GChangeVersion);
  end;
end;

class function TDAIClientRegistration.FindRegistrations(const AClient: string): TJSONObject;
var
  LFilter: string;
  LIndex: Integer;
  LFound: Boolean;
  LDefinition: TClientDefinition;
  LResults, LCodex: TJSONArray;
  LValue: TJSONValue;
begin
  System.TMonitor.Enter(GRegistrationLock);
  try
    LFilter := NormalizeClient(AClient);
    Result := TJSONObject.Create;
    try
      LResults := TJSONArray.Create;
      Result.AddPair('registrations', LResults);
      LFound := False;
      for LIndex := 0 to 8 do
      begin
        LDefinition := BuildDefinition(LIndex);
        if (LFilter <> '') and (LDefinition.Id <> LFilter) then
          Continue;
        LFound := True;
        if LDefinition.Id = 'codex' then
        begin
          LCodex := TDAICodexRegistration.FindRegistrations;
          try
            for LValue in LCodex do
              LResults.AddElement(TJSONValue(LValue.Clone));
          finally
            LCodex.Free;
          end;
        end
        else
          FindClientRegistrations(LDefinition, LResults);
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

function RemoveFoundRegistrationImpl(const ACandidate: TJSONObject): TJSONObject;
var
  LIndex: Integer;
  LBase, LDefinition: TClientDefinition;
  LClient, LServer, LConfigHash, LOwnershipHash, LOwnership, LStatus: string;
  LCurrent, LAction: TJSONObject;
  LRemovable, LRemoved: Boolean;
begin
  if ACandidate = nil then
    Exit(RemovalResult(nil, 'conflict', DAIText(
      'Kein Suchtreffer ausgewählt.',
      'No search result selected.',
      'Aucun résultat sélectionné.',
      '検索結果が選択されていません。'), False));
  System.TMonitor.Enter(GRegistrationLock);
  try
    try
      LClient := ReadJsonString(ACandidate, 'client');
      if LClient = 'codex' then
        Exit(TDAICodexRegistration.RemoveFoundRegistration(ACandidate));
      LBase := Default(TClientDefinition);
      for LIndex := 1 to 8 do
      begin
        LDefinition := BuildDefinition(LIndex);
        if LDefinition.Id = LClient then
        begin
          LBase := LDefinition;
          Break;
        end;
      end;
      if not LBase.Supported or (LBase.FileName = '') or
        not SameText(LBase.FileName, ReadJsonString(ACandidate, 'path')) then
        Exit(RemovalResult(ACandidate, 'conflict', DAIText(
          'Der Suchtreffer gehört zu keinem bekannten Clientpfad.',
          'The search result does not belong to a known client path.',
          'Le résultat ne correspond à aucun chemin de client connu.',
          '検索結果が既知のクライアントパスに属していません。'), False));
      LServer := ReadJsonString(ACandidate, 'server_name');
      if not TRegEx.IsMatch(LServer, '^dai(?:_bds[0-9]+_[0-9]+(?:_p[a-f0-9]{16})?)?$') then
        Exit(RemovalResult(ACandidate, 'conflict', DAIText(
          'Unbekannter DAI-Registrierungsname.',
          'Unknown DAI registration name.',
          'Nom d’inscription DAI inconnu.',
          '不明な DAI 登録名です。'), False));
      LCurrent := FoundCandidate(LBase, LServer);
      try
        LRemovable := False;
        LCurrent.TryGetValue<Boolean>('removable', LRemovable);
        if not LRemovable then
          Exit(RemovalResult(LCurrent, 'conflict', ReadJsonString(LCurrent, 'message'), False));
        LConfigHash := ReadJsonString(ACandidate, 'config_sha256');
        LOwnershipHash := ReadJsonString(ACandidate, 'ownership_sha256');
        if (LConfigHash = '') or (LOwnershipHash = '') or
          (LConfigHash <> ReadJsonString(LCurrent, 'config_sha256')) or
          (LOwnershipHash <> ReadJsonString(LCurrent, 'ownership_sha256')) or
          (ReadJsonString(ACandidate, 'launcher_server') <> ReadJsonString(LCurrent, 'launcher_server')) or
          (ReadJsonString(ACandidate, 'connection_scope') <> ReadJsonString(LCurrent, 'connection_scope')) or
          not SameText(ReadJsonString(ACandidate, 'registry_root'), ReadJsonString(LCurrent, 'registry_root')) then
          Exit(RemovalResult(LCurrent, 'conflict', DAIText(
            'Die Registrierung wurde seit der Suche geändert; bitte erneut suchen.',
            'The registration has changed since the search; search again.',
            'L’inscription a changé depuis la recherche ; relancer la recherche.',
            '検索後に登録内容が変更されました。再検索してください。'), False));
        LDefinition := LBase;
        LDefinition.ServerName := LServer;
        LOwnership := TDAIClientSafeFiles.ReadTextIfExists(OwnershipFile(LDefinition));
        LDefinition := FoundDefinition(LBase, LServer, LOwnership);
        LAction := ProcessClient(LDefinition, 'unregister', True, LConfigHash, LOwnershipHash);
        try
          LStatus := ReadJsonString(LAction, 'status');
          LRemoved := (LStatus = 'removed') or (LStatus = 'configured_pending');
          Result := RemovalResult(LCurrent, LStatus, ReadJsonString(LAction, 'message'), LRemoved);
          if LAction.GetValue('backup') is TJSONString then
            Result.AddPair('backup', ReadJsonString(LAction, 'backup'));
        finally
          LAction.Free;
        end;
      finally
        LCurrent.Free;
      end;
    except
      on E: Exception do
        Result := RemovalResult(nil, 'conflict', DAIText(
          'Die Registrierung konnte nicht sicher entfernt werden; bitte erneut suchen.',
          'The registration could not be removed safely; search again.',
          'L’inscription n’a pas pu être supprimée de façon sûre ; relancer la recherche.',
          '登録を安全に削除できませんでした。再検索してください。'), False);
    end;
  finally
    System.TMonitor.Exit(GRegistrationLock);
  end;
end;

class function TDAIClientRegistration.RemoveFoundRegistration(const ACandidate: TJSONObject): TJSONObject;
begin
  try
    Result := RemoveFoundRegistrationImpl(ACandidate);
  finally
    TInterlocked.Increment(GChangeVersion);
  end;
end;

class function TDAIClientRegistration.ChangeVersion: Integer;
begin
  // The toolbar reads only these counters on its timer; configuration files are checked on demand.
  Result := TInterlocked.CompareExchange(GChangeVersion, 0, 0) + TDAICodexRegistration.ChangeVersion;
end;

class function TDAIClientRegistration.Health(out ADetails: string): TDAIRegistrationHealth;
var
  LStatus, LClient, LCodex: TJSONObject;
  LValue: TJSONValue;
  LClients: TJSONArray;
  LState, LLabel, LReason: string;
  LHealth: TDAIRegistrationHealth;
  LRegistered, LDetected, LLegacy: Boolean;
begin
  Result := rhNotRegistered;
  ADetails := 'Keine Registrierung für die aktuellen Verbindungseinstellungen gefunden.';
  try
    LStatus := Status;
    try
      LClients := LStatus.GetValue<TJSONArray>('clients');
      for LValue in LClients do
      begin
        LClient := LValue as TJSONObject;
        LState := ReadJsonString(LClient, 'status');
        LLabel := ReadJsonString(LClient, 'label');
        LRegistered := LClient.GetValue<Boolean>('registered', False);
        LDetected := LClient.GetValue<Boolean>('detected', False);
        LHealth := rhNotRegistered;
        LReason := '';
        if LRegistered then
        begin
          LHealth := rhCurrent;
          if (LState = 'needs_update') or (LState = 'missing_bridge') then
          begin
            LHealth := rhUpdateRecommended;
            LReason := 'Registrierung oder Starthelfer aktualisieren.';
          end;
        end;
        if ((LState = 'conflict') or (LState = 'error')) and
          (LRegistered or (LDetected and (TFile.Exists(ReadJsonString(LClient, 'path')) or
          TFile.Exists(ReadJsonString(LClient, 'ownership_file'))))) then
        begin
          LHealth := rhCheckRecommended;
          LReason := 'Registrierung konnte nicht eindeutig geprüft werden; DAI-Optionen öffnen.';
        end;
        if LClient.TryGetValue<TJSONObject>('codex', LCodex) then
        begin
          LLegacy := LCodex.GetValue<Boolean>('legacy_codex_entry_registered', False);
          if LRegistered or LLegacy then
          begin
            if not LCodex.GetValue<Boolean>('bridge_exists', False) or
              not LCodex.GetValue<Boolean>('skill_current', False) or LLegacy or
              LCodex.GetValue<Boolean>('legacy_skill_registered', False) then
            begin
              LHealth := rhUpdateRecommended;
              LReason := 'Registrierung, Delphi-Skill oder Starthelfer aktualisieren.';
            end;
            if LCodex.GetValue<Boolean>('skill_file_exists', False) and
              not LCodex.GetValue<Boolean>('skill_managed', False) then
            begin
              LHealth := rhCheckRecommended;
              LReason := 'Vorhandenen Delphi-Skill in den DAI-Optionen prüfen.';
            end;
          end;
          if (ReadJsonString(LCodex, 'codex_registration_error') <> '') or
            LCodex.GetValue<Boolean>('unmanaged_entry_present', False) then
          begin
            LHealth := rhCheckRecommended;
            LReason := 'Vorhandene Codex-Registrierung in den DAI-Optionen prüfen.';
          end;
        end;
        if Ord(LHealth) > Ord(Result) then
        begin
          Result := LHealth;
          if Result = rhCurrent then
            ADetails := 'Passend registriert.'
          else
            // Never surface parser messages or configuration text in the toolbar hint.
            ADetails := LLabel + ': ' + LReason;
        end;
      end;
    finally
      LStatus.Free;
    end;
  except
    on E: Exception do
    begin
      Result := rhCheckRecommended;
      ADetails := 'Registrierungen konnten nicht geprüft werden; DAI-Optionen öffnen.';
    end;
  end;
end;

initialization
  GRegistrationLock := TObject.Create;

finalization
  GRegistrationLock.Free;

end.
