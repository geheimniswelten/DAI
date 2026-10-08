program TestLifecycleSettings;

{$APPTYPE CONSOLE}

uses
  DAI.Lifecycle.TestRegistry in 'LauncherTests\DAI.Lifecycle.TestRegistry.pas',
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI in 'LifecycleSettingsTests\ToolsAPI.pas',
  h5u.DAI.Consts,
  h5u.DAI.Lifecycle.Policy in '..\Source\h5u.DAI.Lifecycle.Policy.pas',
  h5u.DAI.Settings in '..\Source\h5u.DAI.Settings.pas';

var
  CheckCount: Integer;
  TestStage: string;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function OpenPolicyKey: HKEY;
var
  LError: Longint;
begin
  LError := RegCreateKeyEx(HKEY_CURRENT_USER, PChar(TDAILifecyclePolicy.CRegistryKey), 0, nil, REG_OPTION_NON_VOLATILE,
    KEY_QUERY_VALUE or KEY_SET_VALUE or KEY_WOW64_64KEY, nil, Result, nil);
  if LError <> ERROR_SUCCESS then
    RaiseLastOSError(LError);
end;

function PolicyKeyExists: Boolean;
var
  LKey: HKEY;
  LError: Longint;
begin
  LError := RegOpenKeyEx(HKEY_CURRENT_USER, PChar(TDAILifecyclePolicy.CRegistryKey), 0, KEY_QUERY_VALUE or KEY_WOW64_64KEY, LKey);
  if LError = ERROR_SUCCESS then
  begin
    RegCloseKey(LKey);
    Exit(True);
  end;
  if (LError <> ERROR_FILE_NOT_FOUND) and (LError <> ERROR_PATH_NOT_FOUND) then
    RaiseLastOSError(LError);
  Result := False;
end;

procedure CheckPolicy(const AExpected: Boolean; const AExpectedReason: string; const ADescription: string);
var
  LReason: string;
  LAllowed: Boolean;
begin
  LAllowed := TDAILifecyclePolicy.ReadAllowed(LReason);
  Check(LAllowed = AExpected, ADescription + ': effective permission');
  Check(LReason = AExpectedReason, ADescription + ': reason');
end;

procedure SetRawPolicy(const AType: DWORD; const AData: TBytes);
var
  LKey: HKEY;
  LError: Longint;
  LData: PByte;
begin
  LKey := OpenPolicyKey;
  try
    LData := nil;
    if Length(AData) <> 0 then
      LData := @AData[0];
    LError := RegSetValueEx(LKey, PChar(TDAILifecyclePolicy.CValueName), 0, AType, LData, Length(AData));
    if LError <> ERROR_SUCCESS then
      RaiseLastOSError(LError);
  finally
    RegCloseKey(LKey);
  end;
end;

procedure CheckStoredDword(const AExpected: DWORD);
var
  LKey: HKEY;
  LType: DWORD;
  LSize: DWORD;
  LValue: DWORD;
  LError: Longint;
begin
  LKey := OpenPolicyKey;
  try
    LType := REG_NONE;
    LSize := SizeOf(LValue);
    LValue := High(DWORD);
    LError := RegQueryValueEx(LKey, PChar(TDAILifecyclePolicy.CValueName), nil, @LType, PByte(@LValue), @LSize);
    Check(LError = ERROR_SUCCESS, 'Native policy value can be read');
    Check(LType = REG_DWORD, 'Native policy uses REG_DWORD');
    Check(LSize = SizeOf(DWORD), 'Native policy uses exactly four bytes');
    Check(LValue = AExpected, 'Native policy stores the exact 0/1 value');
  finally
    RegCloseKey(LKey);
  end;
end;

procedure RunChecks;
var
  LFirst: TDAISettings;
  LSecond: TDAISettings;
  LKey: HKEY;
  LError: Longint;
  LFailed: Boolean;
begin
  TestStage := 'Fresh isolated HKCU';
  Check(not Assigned(BorlandIDEServices), 'Settings has no live IDE services');
  Check(not PolicyKeyExists, 'Fresh isolated HKCU has no global policy key');
  CheckPolicy(True, 'allowed_by_default', 'Missing key');
  LFirst := TDAISettings.Create;
  try
    LSecond := TDAISettings.Create;
    try
      Check(LFirst.RegistryRoot = 'Software\Embarcadero\BDS\37.0\DAI', 'Real Settings fallback registry root stays inside isolated HKCU');
      Check(LFirst.AllowIDEStartStop and LSecond.AllowIDEStartStop, 'Both actual Settings objects default to enabled');
      Check(not PolicyKeyExists, 'Constructing settings never creates the policy key');
      LFirst.AllowIDEStartStop := False;
      Check(not LFirst.AllowIDEStartStop, 'Explicit setter exposes the pending draft on its own object');
      Check(LSecond.AllowIDEStartStop, 'Pending draft does not affect another Settings object');
      CheckPolicy(True, 'allowed_by_default', 'Setter has not persisted the pending draft');
      Check(not PolicyKeyExists, 'Setter never creates the policy key');
      LFirst.Save;
      CheckPolicy(False, 'disabled_in_dai_options', 'Save persists explicit disable');
      CheckStoredDword(0);
      Check(not LSecond.AllowIDEStartStop, 'Existing second object reads saved disable without Load');

      TestStage := 'Unrelated saves preserve external policy';
      LSecond.Port := 7201;
      LSecond.Save;
      CheckPolicy(False, 'disabled_in_dai_options', 'Port-only save does not replay its enabled constructor value');
      TDAILifecyclePolicy.WriteAllowed(True);
      Check(LFirst.AllowIDEStartStop, 'First object observes another writer enabling shared policy');
      LFirst.Port := 7202;
      LFirst.Save;
      CheckPolicy(True, 'allowed', 'First-object unrelated save preserves external enable');
      TDAILifecyclePolicy.WriteAllowed(False);
      LSecond.Save;
      CheckPolicy(False, 'disabled_in_dai_options', 'Second-object repeated save preserves external disable');
      LFirst.Save;
      CheckPolicy(False, 'disabled_in_dai_options', 'First-object repeated save also preserves external disable');

      TestStage := 'Load and discard pending changes';
      LFirst.AllowIDEStartStop := True;
      Check(LFirst.AllowIDEStartStop, 'New explicit enable remains pending');
      CheckPolicy(False, 'disabled_in_dai_options', 'Pending enable leaves persisted policy disabled');
      LFirst.Load;
      Check(not LFirst.AllowIDEStartStop, 'Load discards pending lifecycle change and reads current policy');
      LFirst.Save;
      CheckPolicy(False, 'disabled_in_dai_options', 'Save after Load never replays discarded pending enable');
      LSecond.AllowIDEStartStop := True;
      LSecond.DiscardLifecycleChange;
      Check(not LSecond.AllowIDEStartStop, 'Explicit Discard exposes the current persisted policy again');
      LSecond.Save;
      CheckPolicy(False, 'disabled_in_dai_options', 'Save after Discard does not persist discarded draft');

      TestStage := 'Failed save and retry';
      LFirst.AllowIDEStartStop := True;
      LFirst.Port := 1023;
      LFailed := False;
      try
        LFirst.Save;
      except
        on E: EArgumentOutOfRangeException do
          LFailed := True;
      end;
      Check(LFailed, 'Real settings rejects an invalid port before any policy write');
      CheckPolicy(False, 'disabled_in_dai_options', 'Failed Save preserves the disabled policy');
      LFirst.DiscardLifecycleChange;
      LFirst.Port := 7203;
      LFirst.Save;
      CheckPolicy(False, 'disabled_in_dai_options', 'Unrelated valid save after Discard cannot replay failed enable');
      LFirst.AllowIDEStartStop := True;
      LFirst.Save;
      CheckPolicy(True, 'allowed', 'Explicit retry persists enable');
      CheckStoredDword(1);
      Check(LSecond.AllowIDEStartStop, 'Existing second object observes the successful retry');

      TestStage := 'Native malformed registry values';
      SetRawPolicy(REG_SZ, TEncoding.Unicode.GetBytes('1' + #0));
      CheckPolicy(False, 'settings_unreadable', 'REG_SZ cannot grant permission');
      Check(not LFirst.AllowIDEStartStop, 'Real Settings getter fails closed on wrong registry type');
      LFirst.Save;
      CheckPolicy(False, 'settings_unreadable', 'Unrelated settings save does not overwrite malformed policy');
      SetRawPolicy(REG_DWORD, TBytes.Create(2, 0, 0, 0));
      CheckPolicy(False, 'settings_unreadable', 'DWORD 2 cannot grant permission');
      SetRawPolicy(REG_DWORD, TBytes.Create(255, 255, 255, 255));
      CheckPolicy(False, 'settings_unreadable', 'DWORD minus-one bit pattern cannot grant permission');
      SetRawPolicy(REG_BINARY, TBytes.Create(1));
      CheckPolicy(False, 'settings_unreadable', 'Truncated binary cannot grant permission');
      SetRawPolicy(REG_DWORD, TBytes.Create(1));
      CheckPolicy(False, 'settings_unreadable', 'Truncated DWORD cannot grant permission');
      SetRawPolicy(REG_DWORD, TBytes.Create(1, 0, 0, 0, 0, 0, 0, 0));
      CheckPolicy(False, 'settings_unreadable', 'Oversized DWORD cannot grant permission');
      SetRawPolicy(REG_DWORD, nil);
      CheckPolicy(False, 'settings_unreadable', 'Empty DWORD cannot grant permission');
      LKey := OpenPolicyKey;
      try
        LError := RegDeleteValue(LKey, PChar(TDAILifecyclePolicy.CValueName));
        if LError <> ERROR_SUCCESS then
          RaiseLastOSError(LError);
      finally
        RegCloseKey(LKey);
      end;
      CheckPolicy(True, 'allowed_by_default', 'Existing key without policy value');
      Check(LFirst.AllowIDEStartStop and LSecond.AllowIDEStartStop, 'Both Settings objects use default after value deletion');
    finally
      LSecond.Free;
    end;
  finally
    LFirst.Free;
  end;
end;

begin
  try
    RunChecks;
    Writeln('PASS: ', CheckCount, ' isolated native lifecycle/settings checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Writeln('Stage: ', TestStage);
      ExitCode := 1;
    end;
  end;
end.
