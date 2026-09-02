unit h5u.DAI.Codex.Registration;

interface

uses
  System.JSON;

type
  TDAICodexRegistration = class sealed
  public
    class function CodexConfigFileName: string; static;
    class function SkillFileName: string; static;
    class function Status: TJSONObject; static;
    class procedure RegisterFiles; static;
    class procedure UnregisterFiles; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  h5u.DAI.Consts,
  h5u.DAI.Settings;

const
  CDAISkillMarker = '<!-- DAI managed skill -->';

function ReadTextIfExists(const AFileName: string): string;
begin
  if TFile.Exists(AFileName) then
    Result := TFile.ReadAllText(AFileName, TEncoding.UTF8)
  else
    Result := '';
end;

function RemoveManagedBlock(const AText: string): string;
var
  LEndPosition: Integer;
  LStartPosition: Integer;
begin
  Result := AText;
  LStartPosition := Pos(CDAIManagedBlockBegin, Result);
  while LStartPosition > 0 do
  begin
    LEndPosition := Pos(CDAIManagedBlockEnd, Result, LStartPosition);
    if LEndPosition = 0 then
      raise EInvalidOperation.Create('Der DAI-Block in der Codex-Konfiguration ist unvollständig.');
    Delete(Result, LStartPosition, LEndPosition - LStartPosition + Length(CDAIManagedBlockEnd));
    Result := Result.TrimRight + sLineBreak;
    LStartPosition := Pos(CDAIManagedBlockBegin, Result);
  end;
end;

function BuildCodexBlock: string;
begin
  Result :=
    CDAIManagedBlockBegin + sLineBreak +
    '[mcp_servers.' + CDAICodexServerName + ']' + sLineBreak +
    'url = "http://' + CDAIDefaultBindAddress + ':' + IntToStr(TDAISettings.Instance.Port) + CDAIMcpPath + '"' + sLineBreak +
    'enabled = true' + sLineBreak +
    'http_headers = { Authorization = "Bearer ' + TDAISettings.Instance.Token + '" }' + sLineBreak +
    CDAIManagedBlockEnd + sLineBreak;
end;

function BuildSkillContent: string;
begin
  Result :=
    CDAISkillMarker + sLineBreak +
    '# Delphi AI (DAI)' + sLineBreak + sLineBreak +
    'Nutze den MCP-Server `dai` für Zugriffe auf die aktuell geöffnete Delphi-IDE.' + sLineBreak + sLineBreak +
    '## Regeln' + sLineBreak + sLineBreak +
    '- Lese vor Änderungen stets den aktuellen Editorpuffer.' + sLineBreak +
    '- Verwende für geöffnete Dateien `file_write`; DAI aktualisiert dann den Undo-fähigen Editorpuffer.' + sLineBreak +
    '- Neue `.pas`-Dateien werden als UTF-8 mit BOM angelegt; vorhandene Codierung und Zeilenenden werden nach Möglichkeit erhalten.' + sLineBreak +
    '- Bearbeite DFM-Dateien nur im IDE-Textmodus; Delphi entscheidet beim Speichern selbst über ANSI oder UTF-8.' + sLineBreak +
    '- Delphi-Sourcen, Demos, GetIt-Repositories und zusätzliche Referenzverzeichnisse sind ausschließlich lesbar.' + sLineBreak +
    '- Projektwechsel, Kompilieren und Ausführen können Bestätigungen in der Delphi-IDE erfordern.' + sLineBreak +
    '- Verwende `msbuild_execute` und `dcc32_execute` nur für explizite Compileraufgaben.' + sLineBreak;
end;

class function TDAICodexRegistration.CodexConfigFileName: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, '.codex\config.toml');
end;

class procedure TDAICodexRegistration.RegisterFiles;
var
  LConfig: string;
  LConfigFileName: string;
  LSectionName: string;
begin
  TDAISettings.Instance.Save;
  LConfigFileName := CodexConfigFileName;
  LConfig := ReadTextIfExists(LConfigFileName);
  LSectionName := '[mcp_servers.' + CDAICodexServerName + ']';

  if (Pos(LSectionName, LConfig) > 0) and (Pos(CDAIManagedBlockBegin, LConfig) = 0) then
    raise EInvalidOperation.Create('Ein nicht von DAI verwalteter Codex-Eintrag namens "' + CDAICodexServerName + '" existiert bereits.');

  LConfig := RemoveManagedBlock(LConfig);
  if (LConfig <> '') and not LConfig.EndsWith(sLineBreak) then
    LConfig := LConfig + sLineBreak;
  LConfig := LConfig + BuildCodexBlock;

  ForceDirectories(TPath.GetDirectoryName(LConfigFileName));
  TFile.WriteAllText(LConfigFileName, LConfig, TEncoding.UTF8);

  ForceDirectories(TPath.GetDirectoryName(SkillFileName));
  TFile.WriteAllText(SkillFileName, BuildSkillContent, TEncoding.UTF8);
end;

class function TDAICodexRegistration.SkillFileName: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, '.agents\skills\' + CDAISkillDirectoryName + '\SKILL.md');
end;

class function TDAICodexRegistration.Status: TJSONObject;
var
  LConfig: string;
  LSkill: string;
begin
  LConfig := ReadTextIfExists(CodexConfigFileName);
  LSkill := ReadTextIfExists(SkillFileName);

  Result := TJSONObject.Create;
  Result.AddPair('codex_config', CodexConfigFileName);
  Result.AddPair('codex_config_exists', TJSONBool.Create(TFile.Exists(CodexConfigFileName)));
  Result.AddPair('codex_entry_registered', TJSONBool.Create(Pos(CDAIManagedBlockBegin, LConfig) > 0));
  Result.AddPair('skill_file', SkillFileName);
  Result.AddPair('skill_file_exists', TJSONBool.Create(TFile.Exists(SkillFileName)));
  Result.AddPair('skill_registered', TJSONBool.Create(Pos(CDAISkillMarker, LSkill) > 0));
end;

class procedure TDAICodexRegistration.UnregisterFiles;
var
  LConfig: string;
  LDirectory: string;
begin
  if TFile.Exists(CodexConfigFileName) then
  begin
    LConfig := RemoveManagedBlock(ReadTextIfExists(CodexConfigFileName));
    TFile.WriteAllText(CodexConfigFileName, LConfig.TrimRight + sLineBreak, TEncoding.UTF8);
  end;

  if TFile.Exists(SkillFileName) and (Pos(CDAISkillMarker, ReadTextIfExists(SkillFileName)) > 0) then
    TFile.Delete(SkillFileName);

  LDirectory := TPath.GetDirectoryName(SkillFileName);
  if TDirectory.Exists(LDirectory) and (Length(TDirectory.GetFileSystemEntries(LDirectory)) = 0) then
    TDirectory.Delete(LDirectory);
end;

end.
