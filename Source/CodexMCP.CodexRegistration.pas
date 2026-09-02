unit CodexMCP.CodexRegistration;

interface

type
  TCodexMCPRegistration = class sealed
  private
    class function RemoveManagedBlock(const AText: string): string; static;
  public
    class function CodexConfigDirectory: string; static;
    class function CodexConfigFile: string; static;
    class function SkillDirectory: string; static;
    class function SkillFile: string; static;
    class function CodexConfigExists: Boolean; static;
    class function SkillFileExists: Boolean; static;
    class function IsCodexRegistered: Boolean; static;
    class function IsSkillRegistered: Boolean; static;
    class procedure RegisterCodex; static;
    class procedure DeregisterCodex; static;
    class procedure RegisterSkill; static;
    class procedure DeregisterSkill; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  CodexMCP.Constants,
  CodexMCP.Settings,
  CodexMCP.TextFiles;

function UserProfile: string;
begin
  Result := GetEnvironmentVariable('USERPROFILE');
  if Result = '' then
    Result := TPath.GetHomePath;
end;

function ReadUtf8OrEmpty(const AFileName: string): string;
var
  LEncoding: TCodexTextEncoding;
begin
  Result := '';
  try
    ReadTextFilePreservingEncoding(AFileName, Result, LEncoding);
  except
    Result := '';
  end;
end;

function EscapeTomlBasicString(const AValue: string): string;
begin
  Result := StringReplace(AValue, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
end;

function HasUnmanagedServerSection(const AText: string): Boolean;
var
  LIndex: Integer;
  LLine: string;
  LLines: TStringList;
begin
  Result := False;
  LLines := TStringList.Create;
  try
    LLines.Text := AText;
    for LIndex := 0 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[LIndex]);
      if SameText(LLine, '[mcp_servers.' + CCodexMCPServerId + ']') or
        SameText(LLine, '[mcp_servers."' + CCodexMCPServerId + '"]') or
        SameText(LLine, '[mcp_servers.''' + CCodexMCPServerId + ''']') then
        Exit(True);
    end;
  finally
    LLines.Free;
  end;
end;

{ TCodexMCPRegistration }

class function TCodexMCPRegistration.CodexConfigDirectory: string;
begin
  Result := TPath.Combine(UserProfile, '.codex');
end;

class function TCodexMCPRegistration.CodexConfigExists: Boolean;
begin
  Result := TFile.Exists(CodexConfigFile);
end;

class function TCodexMCPRegistration.CodexConfigFile: string;
begin
  Result := TPath.Combine(CodexConfigDirectory, 'config.toml');
end;

class procedure TCodexMCPRegistration.DeregisterCodex;
var
  LCurrent: string;
  LEncoding: TCodexTextEncoding;
  LNewText: string;
begin
  if not TFile.Exists(CodexConfigFile) then
    Exit;
  if not ReadTextFilePreservingEncoding(CodexConfigFile, LCurrent, LEncoding) then
    raise EIOException.CreateFmt(
      'Die Codex-Konfiguration konnte nicht gelesen werden: %s',
      [CodexConfigFile]
    );
  LNewText := RemoveManagedBlock(LCurrent);
  WriteTextFilePreservingEncoding(CodexConfigFile, LNewText, LEncoding);
end;

class procedure TCodexMCPRegistration.DeregisterSkill;
begin
  if TFile.Exists(SkillFile) then
    TFile.Delete(SkillFile);
  if TDirectory.Exists(SkillDirectory) and
    (Length(TDirectory.GetFileSystemEntries(SkillDirectory)) = 0) then
    TDirectory.Delete(SkillDirectory);
end;

class function TCodexMCPRegistration.IsCodexRegistered: Boolean;
var
  LText: string;
begin
  LText := ReadUtf8OrEmpty(CodexConfigFile);
  Result := ContainsText(LText, CCodexMCPManagedBegin) and
    ContainsText(LText, '[mcp_servers.' + CCodexMCPServerId + ']');
end;

class function TCodexMCPRegistration.IsSkillRegistered: Boolean;
var
  LText: string;
begin
  LText := ReadUtf8OrEmpty(SkillFile);
  Result := ContainsText(LText, 'name: ' + CCodexMCPSkillName) and
    ContainsText(LText, 'delphi_ide');
end;

class procedure TCodexMCPRegistration.RegisterCodex;
var
  LBlock: string;
  LCurrent: string;
  LEncoding: TCodexTextEncoding;
  LSettings: TCodexMCPSettings;
  LUrl: string;
begin
  LSettings := TCodexMCPSettings.Instance;
  LSettings.Save;
  ForceDirectories(CodexConfigDirectory);

  LCurrent := '';
  LEncoding := cteUtf8;
  if TFile.Exists(CodexConfigFile) and
    not ReadTextFilePreservingEncoding(CodexConfigFile, LCurrent, LEncoding) then
    raise EIOException.CreateFmt(
      'Die bestehende Codex-Konfiguration konnte nicht gelesen werden: %s',
      [CodexConfigFile]
    );
  LCurrent := TrimRight(RemoveManagedBlock(LCurrent));
  if HasUnmanagedServerSection(LCurrent) then
    raise EInvalidOpException.CreateFmt(
      'Die Codex-Konfiguration enthält bereits einen nicht von diesem Package verwalteten Abschnitt [mcp_servers.%s]. Benennen oder entfernen Sie diesen Abschnitt zuerst.',
      [CCodexMCPServerId]
    );
  if LCurrent <> '' then
    LCurrent := LCurrent + sLineBreak + sLineBreak;

  LUrl := Format(
    'http://127.0.0.1:%d%s',
    [LSettings.Port, CCodexMCPPath]
  );
  LBlock :=
    CCodexMCPManagedBegin + sLineBreak +
    '[mcp_servers.' + CCodexMCPServerId + ']' + sLineBreak +
    'url = "' + EscapeTomlBasicString(LUrl) + '"' + sLineBreak +
    'http_headers = { Authorization = "Bearer ' +
      EscapeTomlBasicString(LSettings.AuthToken) + '" }' + sLineBreak +
    'enabled = ' + LowerCase(BoolToStr(LSettings.Enabled, True)) + sLineBreak +
    CCodexMCPManagedEnd + sLineBreak;

  WriteTextFilePreservingEncoding(
    CodexConfigFile,
    LCurrent + LBlock,
    LEncoding
  );
end;

class procedure TCodexMCPRegistration.RegisterSkill;
const
  CSkillText =
    '---' + sLineBreak +
    'name: delphi-ide' + sLineBreak +
    'description: Work with the currently running Delphi 13 IDE through the delphi_ide MCP server.' + sLineBreak +
    '---' + sLineBreak + sLineBreak +
    '# Delphi IDE' + sLineBreak + sLineBreak +
    'Use the `delphi_ide` MCP tools for project, editor, build, run and user-interaction operations.' + sLineBreak + sLineBreak +
    '## Rules' + sLineBreak + sLineBreak +
    '- Read an open file through the MCP server before trusting its on-disk contents; the unsaved editor buffer is authoritative.' + sLineBreak +
    '- Only modify files accepted by `ide_write_file`. Delphi sources, demos, GetIt repositories and configured additional roots are read-only.' + sLineBreak +
    '- Use `expected_sha256` for non-trivial writes to avoid overwriting concurrent editor changes.' + sLineBreak +
    '- Use `ide_show_form_as_text` before editing a DFM when the visual designer is active.' + sLineBreak +
    '- Compile after multi-file changes and report compiler output to the user.' + sLineBreak;
begin
  ForceDirectories(SkillDirectory);
  WriteTextFilePreservingEncoding(SkillFile, CSkillText, cteUtf8);
end;

class function TCodexMCPRegistration.RemoveManagedBlock(
  const AText: string
): string;
var
  LBeginPos: Integer;
  LEndPos: Integer;
  LEndLength: Integer;
begin
  Result := AText;
  repeat
    LBeginPos := Pos(CCodexMCPManagedBegin, Result);
    if LBeginPos = 0 then
      Break;
    LEndPos := PosEx(CCodexMCPManagedEnd, Result, LBeginPos);
    if LEndPos = 0 then
    begin
      Delete(Result, LBeginPos, MaxInt);
      Break;
    end;
    LEndLength := Length(CCodexMCPManagedEnd);
    while (LEndPos + LEndLength <= Length(Result)) and
      CharInSet(Result[LEndPos + LEndLength], [#10, #13]) do
      Inc(LEndLength);
    Delete(Result, LBeginPos, LEndPos - LBeginPos + LEndLength);
  until False;
end;

class function TCodexMCPRegistration.SkillDirectory: string;
begin
  Result := TPath.Combine(
    TPath.Combine(
      TPath.Combine(UserProfile, '.agents'),
      'skills'
    ),
    CCodexMCPSkillName
  );
end;

class function TCodexMCPRegistration.SkillFile: string;
begin
  Result := TPath.Combine(SkillDirectory, 'SKILL.md');
end;

class function TCodexMCPRegistration.SkillFileExists: Boolean;
begin
  Result := TFile.Exists(SkillFile);
end;

end.
