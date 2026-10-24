unit h5u.DAI.Consts;

interface

const
  {$IFDEF WIN64}
  CDAIIDEArchitecture = 'Win64';
  CDAIKnownPackagesKey = 'Known Packages x64';
  {$ELSE}
  CDAIIDEArchitecture = 'Win32';
  CDAIKnownPackagesKey = 'Known Packages';
  {$ENDIF}
  CDAIName = 'DAI';
  CDAIDisplayName = 'Delphi AI';
  CDAIVersion = '1.2.35';
  CDAIDefaultPort = 7331;
  CDAIDefaultBindAddress = '127.0.0.1';
  CDAIMcpPath = '/mcp';
  CDAIRegistrySubKey = 'DAI';
  CDAICodexServerName = 'dai';
  CDAIManagedBlockBegin = '# >>> DAI managed >>>';
  CDAIManagedBlockEnd = '# <<< DAI managed <<<';
  CDAISkillDirectoryName = 'dai-delphi-ide';
  CDAILegacySkillDirectoryName = 'delphi-ide';
  CDAIMaxRequestBytes = 32 * 1024 * 1024;
  CDAIMaxTextFileBytes = 16 * 1024 * 1024;
  CDAIDefaultProcessTimeoutMs = 300000;
  CDAIMaxProcessOutputBytes = 8 * 1024 * 1024;

function DAIRegistrationServerName(const AShared: Boolean; const ARegistryRoot: string): string;
function DAIRegistrationLauncherName(const AShared: Boolean; const ARegistryRoot: string): string;

implementation

uses
  System.Hash,
  System.SysUtils;

function DAIRegistrationServerName(const AShared: Boolean; const ARegistryRoot: string): string;
var
  LKey, LVersion, LLeaf, LDefaultRoot: string;
  LParts: TArray<string>;
  LIndex, LMajorEnd, LMinorStart: Integer;
  LCharacter: Char;
begin
  if AShared then
    Exit(CDAICodexServerName);
  for LCharacter in ARegistryRoot do
    if (Ord(LCharacter) < 32) or (Ord(LCharacter) = 127) then
      raise EArgumentException.Create('Der IDE-Registrypfad enthält ungültige Steuerzeichen.');
  LKey := StringReplace(Trim(ARegistryRoot), '/', '\', [rfReplaceAll]);
  while Pos('\\', LKey) <> 0 do
    LKey := StringReplace(LKey, '\\', '\', [rfReplaceAll]);
  LKey := LKey.Trim(['\']);
  LParts := LKey.Split(['\']);
  if Length(LParts) < 3 then
    raise EArgumentException.Create('Der IDE-Registrypfad enthält keine BDS-Version.');
  if not SameText(LParts[0], 'Software') or not SameText(LParts[High(LParts)], CDAIRegistrySubKey) then
    raise EArgumentException.Create('Der IDE-Registrypfad ist kein DAI-Einstellungsbereich.');
  LLeaf := LParts[High(LParts) - 1];
  LIndex := 1;
  while LIndex <= Length(LLeaf) do
  begin
    if not CharInSet(LLeaf[LIndex], ['0'..'9']) then
      Break;
    Inc(LIndex);
  end;
  LMajorEnd := LIndex;
  if (LIndex = 1) or (LIndex > Length(LLeaf)) then
    raise EArgumentException.Create('Der IDE-Registrypfad enthält keine gültige BDS-Version.');
  if LLeaf[LIndex] <> '.' then
    raise EArgumentException.Create('Der IDE-Registrypfad enthält keine gültige BDS-Version.');
  Inc(LIndex);
  LMinorStart := LIndex;
  while LIndex <= Length(LLeaf) do
  begin
    if not CharInSet(LLeaf[LIndex], ['0'..'9']) then
      Break;
    Inc(LIndex);
  end;
  if LIndex = LMinorStart then
    raise EArgumentException.Create('Der IDE-Registrypfad enthält keine gültige BDS-Version.');
  LVersion := Copy(LLeaf, 1, LMajorEnd - 1) + '_' + Copy(LLeaf, LMinorStart, LIndex - LMinorStart);
  Result := CDAICodexServerName + '_bds' + LVersion;
  LDefaultRoot := 'Software\Embarcadero\BDS\' + Copy(LLeaf, 1, LIndex - 1) + '\' + CDAIRegistrySubKey;
  if not SameText(LKey, LDefaultRoot) then
    Result := Result + '_p' + Copy(THashSHA2.GetHashString(LowerCase(LKey)), 1, 16);
end;

function DAIRegistrationLauncherName(const AShared: Boolean; const ARegistryRoot: string): string;
begin
  Result := DAIRegistrationServerName(AShared, ARegistryRoot) + '_start';
end;

end.
