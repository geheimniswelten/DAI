program TestConnectionSettings;

{$APPTYPE CONSOLE}

uses
  DAI.Lifecycle.TestRegistry in 'LauncherTests\DAI.Lifecycle.TestRegistry.pas',
  System.Classes,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  ToolsAPI in 'ConnectionSettingsTests\ToolsAPI.pas',
  h5u.DAI.Consts,
  h5u.DAI.Lifecycle.Policy in '..\Source\h5u.DAI.Lifecycle.Policy.pas',
  h5u.DAI.Settings in '..\Source\h5u.DAI.Settings.pas';

const
  CSharedRoot = 'Software\DelphiAI\DAI\Connection';
  CIDE11Root = 'Software\Embarcadero\BDS\22.0\DAI';
  CIDE13Root = 'Software\Embarcadero\BDS\37.0\DAI';
  CScopeName = 'UseSharedConnectionSettings';

var
  CheckCount: Integer;
  TestStage: string;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function OpenRegistry(const APath: string; const AWrite: Boolean;
  const AView: LongWord = KEY_WOW64_64KEY): TRegistry;
var
  LOpened: Boolean;
begin
  if AWrite then
    Result := TRegistry.Create(KEY_READ or KEY_WRITE or AView)
  else
    Result := TRegistry.Create(KEY_READ or AView);
  try
    Result.RootKey := HKEY_CURRENT_USER;
    if AWrite then
      LOpened := Result.OpenKey(APath, True)
    else
      LOpened := Result.OpenKeyReadOnly(APath);
    if not LOpened then
      raise Exception.Create('Cannot open isolated test registry path: ' + APath);
  except
    Result.Free;
    raise;
  end;
end;

procedure SeedPair(const APath: string; const APort: Integer; const AToken: string);
var
  LRegistry: TRegistry;
begin
  LRegistry := OpenRegistry(APath, True);
  try
    LRegistry.WriteInteger('Port', APort);
    LRegistry.WriteString('Token', AToken);
  finally
    LRegistry.Free;
  end;
end;

procedure SeedScope(const APath: string; const AShared: Boolean);
var
  LRegistry: TRegistry;
begin
  LRegistry := OpenRegistry(APath, True);
  try
    LRegistry.WriteBool(CScopeName, AShared);
  finally
    LRegistry.Free;
  end;
end;

function RegistryKeyExists(const APath: string): Boolean;
var
  LRegistry: TRegistry;
begin
  LRegistry := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    Result := LRegistry.OpenKeyReadOnly(APath);
  finally
    LRegistry.Free;
  end;
end;

procedure CheckStoredPair(const APath: string; const APort: Integer;
  const AToken: string; const ADescription: string;
  const AView: LongWord = KEY_WOW64_64KEY);
var
  LRegistry: TRegistry;
begin
  LRegistry := OpenRegistry(APath, False, AView);
  try
    Check(LRegistry.ReadInteger('Port') = APort, ADescription + ': port');
    Check(LRegistry.ReadString('Token') = AToken, ADescription + ': token');
  finally
    LRegistry.Free;
  end;
end;

procedure CheckStoredScope(const APath: string; const AShared: Boolean);
var
  LRegistry: TRegistry;
begin
  LRegistry := OpenRegistry(APath, False);
  try
    Check(LRegistry.ReadBool(CScopeName) = AShared, 'Scope selection persists in its IDE root');
  finally
    LRegistry.Free;
  end;
end;

function RegistrySnapshot(const APath: string): string;
var
  LRegistry: TRegistry;
  LNames: TStringList;
  LKeys: TStringList;
  LName: string;
  LKey: string;
  LData: TBytes;
  LSize: DWORD;
  LType: DWORD;
  LError: Longint;
  LByte: Byte;
begin
  Result := APath + ':missing;';
  LRegistry := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKeyReadOnly(APath) then
      Exit;
    Result := APath + ':exists;';
    LNames := TStringList.Create;
    LKeys := TStringList.Create;
    try
      LRegistry.GetValueNames(LNames);
      LNames.Sort;
      for LName in LNames do
      begin
        LSize := 0;
        LType := REG_NONE;
        LError := RegQueryValueEx(LRegistry.CurrentKey, PChar(LName), nil, @LType, nil, @LSize);
        if LError <> ERROR_SUCCESS then
          RaiseLastOSError(LError);
        SetLength(LData, LSize);
        if LSize <> 0 then
        begin
          LError := RegQueryValueEx(LRegistry.CurrentKey, PChar(LName), nil, @LType, @LData[0], @LSize);
          if LError <> ERROR_SUCCESS then
            RaiseLastOSError(LError);
        end;
        Result := Result + LName + ':' + IntToStr(LType) + ':';
        for LByte in LData do
          Result := Result + IntToHex(LByte, 2);
        Result := Result + ';';
      end;
      LRegistry.GetKeyNames(LKeys);
      LKeys.Sort;
      for LKey in LKeys do
        Result := Result + RegistrySnapshot(APath + '\' + LKey);
    finally
      LKeys.Free;
      LNames.Free;
    end;
  finally
    LRegistry.Free;
  end;
end;

function SettingsForIDE(const AVersion: string): TDAISettings;
begin
  SetTestIDERegistryRoot('Software\Embarcadero\BDS\' + AVersion);
  Result := TDAISettings.Create;
end;

procedure SelectScope(const ASettings: TDAISettings; const AShared: Boolean);
var
  LPort: Integer;
  LToken: string;
begin
  ASettings.ReadConnectionSettings(AShared, LPort, LToken);
  ASettings.UseSharedConnectionSettings := AShared;
  ASettings.Port := LPort;
  ASettings.Token := LToken;
end;

procedure CheckPair(const ASettings: TDAISettings; const APort: Integer;
  const AToken: string; const ADescription: string);
begin
  Check(ASettings.Port = APort, ADescription + ': port');
  Check(ASettings.Token = AToken, ADescription + ': token');
end;

procedure CheckFreshDefaults;
var
  LFirst: TDAISettings;
  LSecond: TDAISettings;
  LToken: string;
begin
  LFirst := SettingsForIDE('22.0');
  try
    Check(LFirst.RegistryRoot = CIDE11Root, 'Fake Delphi 11 has an independent IDE root');
    Check(LFirst.UseSharedConnectionSettings, 'Fresh Delphi 11 uses shared credentials by default');
    Check(LFirst.Port = CDAIDefaultPort, 'Fresh shared port uses the product default');
    LToken := LFirst.Token;
    Check(Trim(LToken) <> '', 'Fresh shared token is generated');
    CheckStoredPair(CSharedRoot, CDAIDefaultPort, LToken, 'First Load publishes a complete shared pair');
    LFirst.Enabled := False;
    LFirst.Save;
    LSecond := SettingsForIDE('37.0');
    try
      Check(LSecond.RegistryRoot = CIDE13Root, 'Fake Delphi 13 has an independent IDE root');
      Check(LSecond.UseSharedConnectionSettings, 'Fresh Delphi 13 also defaults to shared credentials');
      CheckPair(LSecond, CDAIDefaultPort, LToken, 'Another IDE reuses the generated common pair');
      Check(LSecond.Enabled, 'Enabled remains local to its IDE');
      CheckStoredPair(CSharedRoot, CDAIDefaultPort, LToken, '64-bit view sees the shared pair', KEY_WOW64_64KEY);
      CheckStoredPair(CSharedRoot, CDAIDefaultPort, LToken, '32-bit view sees the same pair', KEY_WOW64_32KEY);
    finally
      LSecond.Free;
    end;
  finally
    LFirst.Free;
  end;
end;

procedure CheckLegacyMigration;
var
  LFirst: TDAISettings;
  LSecond: TDAISettings;
begin
  SeedPair(CIDE11Root, 8111, 'synthetic-legacy-first');
  SeedPair(CIDE13Root, 8222, 'synthetic-legacy-second');
  LFirst := SettingsForIDE('22.0');
  try
    Check(LFirst.UseSharedConnectionSettings, 'Existing installations adopt shared mode by default');
    CheckPair(LFirst, 8111, 'synthetic-legacy-first', 'First valid legacy pair migrates together');
    LSecond := SettingsForIDE('37.0');
    try
      CheckPair(LSecond, 8111, 'synthetic-legacy-first', 'Later IDE cannot overwrite an existing common pair');
      LSecond.Save;
      CheckStoredPair(CSharedRoot, 8111, 'synthetic-legacy-first', 'Saving the later IDE preserves the migrated pair');
      CheckStoredPair(CIDE11Root, 8111, 'synthetic-legacy-first', 'Migration preserves first legacy credentials');
      CheckStoredPair(CIDE13Root, 8222, 'synthetic-legacy-second', 'Migration preserves later legacy credentials');
    finally
      LSecond.Free;
    end;
  finally
    LFirst.Free;
  end;
end;

procedure CheckSeparateRoundTrip;
var
  LFirst: TDAISettings;
  LSecond: TDAISettings;
  LReloaded: TDAISettings;
begin
  SeedPair(CIDE11Root, 8311, 'synthetic-separate-11');
  SeedScope(CIDE11Root, False);
  SeedPair(CIDE13Root, 8313, 'synthetic-separate-13');
  SeedScope(CIDE13Root, False);
  LFirst := SettingsForIDE('22.0');
  try
    LSecond := SettingsForIDE('37.0');
    try
      Check(not LFirst.UseSharedConnectionSettings and not LSecond.UseSharedConnectionSettings,
        'Each IDE remembers an explicit separate mode');
      CheckPair(LFirst, 8311, 'synthetic-separate-11', 'Delphi 11 loads its separate pair');
      CheckPair(LSecond, 8313, 'synthetic-separate-13', 'Delphi 13 loads its separate pair');
      Check(not RegistryKeyExists(CSharedRoot), 'Loading separate mode does not initialize common settings');
      LFirst.Port := 8322;
      LFirst.Token := 'synthetic-separate-11-edited';
      LFirst.Save;
      CheckStoredPair(CIDE13Root, 8313, 'synthetic-separate-13', 'Separate save leaves another IDE untouched');
      Check(not RegistryKeyExists(CSharedRoot), 'Saving separate mode leaves common settings absent');
      SelectScope(LFirst, True);
      CheckPair(LFirst, 8322, 'synthetic-separate-11-edited', 'Absent destination starts with the current pair');
      LFirst.Save;
      CheckStoredScope(CIDE11Root, True);
      CheckStoredPair(CSharedRoot, 8322, 'synthetic-separate-11-edited', 'Switching initializes the common pair');
      SelectScope(LSecond, True);
      CheckPair(LSecond, 8322, 'synthetic-separate-11-edited', 'Switch to common previews existing common values');
      LSecond.Save;
      CheckStoredScope(CIDE13Root, True);
      CheckStoredPair(CIDE13Root, 8313, 'synthetic-separate-13', 'Shared mode preserves former separate values');
      SelectScope(LSecond, False);
      CheckPair(LSecond, 8313, 'synthetic-separate-13', 'Switch back restores the former separate pair');
      LSecond.Save;
      CheckStoredScope(CIDE13Root, False);
      LReloaded := SettingsForIDE('37.0');
      try
        Check(not LReloaded.UseSharedConnectionSettings, 'Recreated object remembers separate scope');
        CheckPair(LReloaded, 8313, 'synthetic-separate-13', 'Recreated object restores the separate pair');
      finally
        LReloaded.Free;
      end;
      LReloaded := SettingsForIDE('22.0');
      try
        Check(LReloaded.UseSharedConnectionSettings, 'Other IDE retains common scope');
        CheckPair(LReloaded, 8322, 'synthetic-separate-11-edited', 'Other IDE retains common credentials');
      finally
        LReloaded.Free;
      end;
    finally
      LSecond.Free;
    end;
  finally
    LFirst.Free;
  end;
end;

procedure CheckPreview;
var
  LSettings: TDAISettings;
  LRegistry: TRegistry;
  LBefore: string;
  LPort: Integer;
  LToken: string;
begin
  SeedPair(CIDE11Root, 8411, 'synthetic-preview-local');
  SeedScope(CIDE11Root, False);
  SeedPair(CSharedRoot, 8412, 'synthetic-preview-common');
  LSettings := SettingsForIDE('22.0');
  try
    LBefore := RegistrySnapshot('Software');
    Check(LSettings.ReadConnectionSettings(True, LPort, LToken), 'Complete common preview reports stored values');
    Check((LPort = 8412) and (LToken = 'synthetic-preview-common'), 'Common preview returns the complete destination pair');
    CheckPair(LSettings, 8411, 'synthetic-preview-local', 'Preview leaves current in-memory pair untouched');
    Check(not LSettings.UseSharedConnectionSettings, 'Preview does not change the selected scope');
    Check(RegistrySnapshot('Software') = LBefore, 'Preview does not mutate any registry key or value');
    Check(LSettings.ReadConnectionSettings(False, LPort, LToken), 'Separate preview reports stored local pair');
    Check((LPort = 8411) and (LToken = 'synthetic-preview-local'), 'Separate preview returns its own pair');
    LSettings.Port := 8413;
    LSettings.Token := 'synthetic-preview-pending';
    LSettings.ReadConnectionSettings(True, LPort, LToken);
    CheckPair(LSettings, 8413, 'synthetic-preview-pending', 'Preview does not discard edited credentials');
    LRegistry := OpenRegistry(CSharedRoot, True);
    try
      Check(LRegistry.DeleteValue('Token'), 'Test removes only a synthetic destination token');
    finally
      LRegistry.Free;
    end;
    LBefore := RegistrySnapshot('Software');
    Check(not LSettings.ReadConnectionSettings(True, LPort, LToken), 'Partial destination reports fallback');
    Check((LPort = 8413) and (LToken = 'synthetic-preview-pending'), 'Partial preview falls back to the current complete pair');
    Check(RegistrySnapshot('Software') = LBefore, 'Fallback preview does not repair or persist partial values');
    CheckPair(LSettings, 8413, 'synthetic-preview-pending', 'Fallback preview leaves edited credentials intact');
    LRegistry := OpenRegistry(CSharedRoot, True);
    try
      LRegistry.WriteString('Token', 'synthetic' + #127 + 'invalid-preview');
    finally
      LRegistry.Free;
    end;
    LBefore := RegistrySnapshot('Software');
    Check(not LSettings.ReadConnectionSettings(True, LPort, LToken), 'Malformed destination token reports fallback');
    Check((LPort = 8413) and (LToken = 'synthetic-preview-pending'), 'Malformed preview cannot expose unusable credentials');
    Check(RegistrySnapshot('Software') = LBefore, 'Malformed preview also leaves stored values intact');
  finally
    LSettings.Free;
  end;
end;

procedure CheckPartialSharedPort;
var
  LSettings: TDAISettings;
  LRegistry: TRegistry;
begin
  LRegistry := OpenRegistry(CSharedRoot, True);
  try
    LRegistry.WriteInteger('Port', 8511);
  finally
    LRegistry.Free;
  end;
  SeedPair(CIDE11Root, 8512, 'synthetic-complete-legacy');
  LSettings := SettingsForIDE('22.0');
  try
    CheckPair(LSettings, 8512, 'synthetic-complete-legacy', 'Shared port without token cannot be combined with a legacy token');
    CheckStoredPair(CSharedRoot, 8512, 'synthetic-complete-legacy', 'Partial common store becomes one complete legacy pair');
  finally
    LSettings.Free;
  end;
end;

procedure CheckPartialSharedToken;
var
  LSettings: TDAISettings;
  LRegistry: TRegistry;
begin
  LRegistry := OpenRegistry(CSharedRoot, True);
  try
    LRegistry.WriteString('Token', 'synthetic-orphan-token');
  finally
    LRegistry.Free;
  end;
  LRegistry := OpenRegistry(CIDE11Root, True);
  try
    LRegistry.WriteInteger('Port', 8513);
  finally
    LRegistry.Free;
  end;
  LSettings := SettingsForIDE('22.0');
  try
    Check(LSettings.Port = CDAIDefaultPort, 'Two partial stores cannot supply a combined nondefault port');
    Check((LSettings.Token <> '') and (LSettings.Token <> 'synthetic-orphan-token'),
      'Two partial stores cannot reuse an orphan token');
    CheckStoredPair(CSharedRoot, LSettings.Port, LSettings.Token, 'Partial stores produce a complete fresh common pair');
  finally
    LSettings.Free;
  end;
end;

procedure CheckMalformedTokens;
var
  LSettings: TDAISettings;
begin
  SeedPair(CSharedRoot, 8521, 'synthetic' + #13#10 + 'invalid-common');
  SeedPair(CIDE11Root, 8522, 'synthetic' + #9 + 'invalid-legacy');
  LSettings := SettingsForIDE('22.0');
  try
    Check(LSettings.Port = CDAIDefaultPort, 'Malformed stored tokens cannot publish either stored port');
    Check((Trim(LSettings.Token) <> '') and (Pos(#13, LSettings.Token) = 0) and
      (Pos(#10, LSettings.Token) = 0) and (Pos(#9, LSettings.Token) = 0),
      'Shared Load replaces malformed stored tokens with a usable token');
    CheckStoredPair(CSharedRoot, LSettings.Port, LSettings.Token, 'Malformed legacy token is never migrated globally');
    CheckStoredPair(CIDE11Root, 8522, 'synthetic' + #9 + 'invalid-legacy', 'Rejected legacy credentials remain untouched');
  finally
    LSettings.Free;
  end;
end;

procedure CheckInvalidSave;
var
  LSettings: TDAISettings;
  LBefore: string;
  LFailed: Boolean;
begin
  LSettings := SettingsForIDE('22.0');
  try
    LBefore := RegistrySnapshot('Software');
    LSettings.Port := 1023;
    LSettings.Token := 'synthetic-invalid-pending';
    LSettings.Enabled := False;
    LSettings.AllowIDEStartStop := False;
    LFailed := False;
    try
      LSettings.Save;
    except
      on E: EArgumentOutOfRangeException do
        LFailed := True;
    end;
    Check(LFailed, 'Invalid shared port is rejected');
    Check(RegistrySnapshot('Software') = LBefore, 'Invalid Save cannot write scope, credentials, local options or lifecycle');
    LSettings.Port := 1024;
    LSettings.Token := 'synthetic' + #10 + 'invalid-save';
    LFailed := False;
    try
      LSettings.Save;
    except
      on E: EArgumentException do
        LFailed := True;
    end;
    Check(LFailed, 'Embedded token control character is rejected');
    Check(RegistrySnapshot('Software') = LBefore, 'Invalid token Save cannot persist any pending values');
    LSettings.DiscardLifecycleChange;
    LSettings.Port := 1024;
    LSettings.Token := ' ';
    LSettings.Save;
    Check(Trim(LSettings.Token) <> '', 'Saving an empty token generates a usable token');
    CheckStoredPair(CSharedRoot, 1024, LSettings.Token, 'Lower valid port boundary persists');
    LSettings.Port := 65535;
    LSettings.Save;
    CheckStoredPair(CSharedRoot, 65535, LSettings.Token, 'Upper valid port boundary persists');
    LBefore := RegistrySnapshot('Software');
    LSettings.Port := 65536;
    LFailed := False;
    try
      LSettings.Save;
    except
      on E: EArgumentOutOfRangeException do
        LFailed := True;
    end;
    Check(LFailed, 'Port beyond the upper boundary is rejected');
    Check(RegistrySnapshot('Software') = LBefore, 'Rejected upper port leaves persisted settings unchanged');
  finally
    LSettings.Free;
  end;
end;

procedure CheckStaleSave;
var
  LFirst: TDAISettings;
  LSecond: TDAISettings;
begin
  LFirst := SettingsForIDE('22.0');
  try
    LSecond := SettingsForIDE('37.0');
    try
      LFirst.Port := 8611;
      LFirst.Token := 'synthetic-another-writer';
      LFirst.Save;
      LSecond.LogAccessPoints := True;
      LSecond.Save;
      CheckStoredPair(CSharedRoot, 8611, 'synthetic-another-writer', 'Unrelated stale-object save preserves newer common credentials');
      SeedPair(CSharedRoot, 8612, 'synthetic-external-writer');
      LFirst.Enabled := False;
      LFirst.Save;
      CheckStoredPair(CSharedRoot, 8612, 'synthetic-external-writer', 'Repeated unrelated save also preserves external credentials');
      LFirst.Port := 8613;
      LFirst.Token := 'synthetic-explicit-edit';
      LFirst.Save;
      CheckStoredPair(CSharedRoot, 8613, 'synthetic-explicit-edit', 'An intentional credential edit still persists');
      LSecond.Load;
      CheckPair(LSecond, 8613, 'synthetic-explicit-edit', 'Load reads the latest common pair');
    finally
      LSecond.Free;
    end;
  finally
    LFirst.Free;
  end;
end;

procedure CheckStalePreviewSave;
var
  LSettings: TDAISettings;
begin
  SeedPair(CIDE11Root, 8711, 'synthetic-preview-separate');
  SeedScope(CIDE11Root, False);
  SeedPair(CSharedRoot, 8712, 'synthetic-preview-original');
  LSettings := SettingsForIDE('22.0');
  try
    SelectScope(LSettings, True);
    SeedPair(CSharedRoot, 8713, 'synthetic-preview-newer-writer');
    LSettings.Enabled := False;
    LSettings.Save;
    CheckStoredScope(CIDE11Root, True);
    CheckStoredPair(CSharedRoot, 8713, 'synthetic-preview-newer-writer',
      'Unedited destination preview cannot overwrite a later common writer on scope change');
    CheckStoredPair(CIDE11Root, 8711, 'synthetic-preview-separate', 'Scope change preserves separate credentials');
    LSettings.Load;
    CheckPair(LSettings, 8713, 'synthetic-preview-newer-writer', 'Reload after scope change observes the preserved latest pair');
  finally
    LSettings.Free;
  end;
end;

procedure CheckRefresh;
var
  LSettings: TDAISettings;
  LBefore: string;
begin
  LSettings := SettingsForIDE('22.0');
  try
    LSettings.Enabled := False;
    LSettings.LogAccessPoints := True;
    LSettings.CustomReadDirectories.Add('C:\Synthetic-Pending-Directory');
    LSettings.AllowIDEStartStop := False;
    SeedPair(CSharedRoot, 8811, 'synthetic-refreshed-common');
    LBefore := RegistrySnapshot('Software');
    LSettings.RefreshConnectionSettings;
    CheckPair(LSettings, 8811, 'synthetic-refreshed-common', 'Refresh observes a newer common writer');
    Check(not LSettings.Enabled and LSettings.LogAccessPoints, 'Refresh preserves unrelated local drafts');
    Check(LSettings.CustomReadDirectories.IndexOf('C:\Synthetic-Pending-Directory') >= 0,
      'Refresh preserves pending directory changes');
    Check(not LSettings.AllowIDEStartStop, 'Refresh preserves the pending lifecycle draft');
    Check(RegistrySnapshot('Software') = LBefore, 'Refresh is read-only');
    LSettings.Port := 8812;
    LSettings.Token := 'synthetic-refreshed-edited-draft';
    SeedPair(CSharedRoot, 8813, 'synthetic-external-after-draft');
    LSettings.RefreshConnectionSettings;
    CheckPair(LSettings, 8812, 'synthetic-refreshed-edited-draft', 'Refresh preserves explicitly edited credentials');
    LSettings.Load;
    CheckPair(LSettings, 8813, 'synthetic-external-after-draft', 'Explicit Load may discard an edited credential draft');
    LSettings.UseSharedConnectionSettings := False;
    LSettings.RefreshConnectionSettings;
    Check(not LSettings.UseSharedConnectionSettings, 'Refresh preserves a pending scope change');
    CheckPair(LSettings, 8813, 'synthetic-external-after-draft', 'Refresh does not replace credentials after a scope draft');
  finally
    LSettings.Free;
  end;
end;

procedure CheckSameIDEConcurrentScope;
var
  LFirst: TDAISettings;
  LSecond: TDAISettings;
  LBefore: string;
begin
  SeedPair(CSharedRoot, 8921, 'synthetic-same-ide-common');
  SeedPair(CIDE11Root, 8922, 'synthetic-same-ide-separate');
  LFirst := SettingsForIDE('22.0');
  try
    LSecond := SettingsForIDE('22.0');
    try
      SelectScope(LFirst, False);
      LFirst.Save;
      LSecond.Enabled := False;
      LSecond.Save;
      Check(not LSecond.UseSharedConnectionSettings, 'Unedited stale Save adopts a concurrent same-IDE scope selection');
      CheckPair(LSecond, 8922, 'synthetic-same-ide-separate', 'Unedited stale Save adopts the selected separate pair');
      CheckStoredScope(CIDE11Root, False);
      CheckStoredPair(CSharedRoot, 8921, 'synthetic-same-ide-common', 'Stale same-IDE Save preserves common credentials');
      SelectScope(LFirst, True);
      LFirst.Save;
      LSecond.LogAccessPoints := True;
      LBefore := RegistrySnapshot('Software');
      LSecond.RefreshConnectionSettings;
      Check(LSecond.UseSharedConnectionSettings, 'Unedited stale Refresh adopts a concurrent same-IDE scope selection');
      CheckPair(LSecond, 8921, 'synthetic-same-ide-common', 'Unedited stale Refresh adopts the selected common pair');
      Check(not LSecond.Enabled and LSecond.LogAccessPoints, 'Scope Refresh preserves unrelated drafts');
      Check(RegistrySnapshot('Software') = LBefore, 'Concurrent scope Refresh does not persist anything');
      SelectScope(LFirst, False);
      LFirst.Save;
      LSecond.Port := 8923;
      LSecond.Token := 'synthetic-same-ide-explicit-draft';
      LSecond.RefreshConnectionSettings;
      Check(LSecond.UseSharedConnectionSettings, 'Refresh preserves the scope of an explicitly edited credential draft');
      CheckPair(LSecond, 8923, 'synthetic-same-ide-explicit-draft', 'Refresh preserves an explicit draft across another scope change');
    finally
      LSecond.Free;
    end;
  finally
    LFirst.Free;
  end;
end;

procedure CheckCrossWrite;
var
  LSettings: TDAISettings;
begin
  LSettings := SettingsForIDE('22.0');
  try
    LSettings.Port := 8911;
    LSettings.Token := 'synthetic-cross-architecture';
    LSettings.Save;
    CheckStoredPair(CSharedRoot, 8911, 'synthetic-cross-architecture', 'Cross-architecture writer publishes common values');
  finally
    LSettings.Free;
  end;
end;

procedure CheckCrossRead;
var
  LSettings: TDAISettings;
begin
  LSettings := SettingsForIDE('37.0');
  try
    Check(LSettings.UseSharedConnectionSettings, 'Other architecture defaults to shared mode');
    CheckPair(LSettings, 8911, 'synthetic-cross-architecture', 'Other IDE architecture reads the same common registry store');
  finally
    LSettings.Free;
  end;
end;

begin
  try
    TestStage := ParamStr(1);
    if TestStage = 'fresh' then
      CheckFreshDefaults
    else if TestStage = 'legacy' then
      CheckLegacyMigration
    else if TestStage = 'separate' then
      CheckSeparateRoundTrip
    else if TestStage = 'preview' then
      CheckPreview
    else if TestStage = 'partial-port' then
      CheckPartialSharedPort
    else if TestStage = 'partial-token' then
      CheckPartialSharedToken
    else if TestStage = 'malformed-token' then
      CheckMalformedTokens
    else if TestStage = 'invalid-save' then
      CheckInvalidSave
    else if TestStage = 'stale-save' then
      CheckStaleSave
    else if TestStage = 'stale-preview' then
      CheckStalePreviewSave
    else if TestStage = 'refresh' then
      CheckRefresh
    else if TestStage = 'concurrent-scope' then
      CheckSameIDEConcurrentScope
    else if TestStage = 'cross-write' then
      CheckCrossWrite
    else if TestStage = 'cross-read' then
      CheckCrossRead
    else
      raise EArgumentException.Create('Unknown test scenario: ' + TestStage);
    Writeln('PASS: ', CheckCount, ' isolated native connection/settings checks (', TestStage, ')');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Writeln('Stage: ', TestStage);
      ExitCode := 1;
    end;
  end;
end.
