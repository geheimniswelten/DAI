unit DAI.Lifecycle.TestRegistry;

interface

implementation

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows;

const
  CTestPrefix = 'Software\DelphiAI\DAI-Launcher-Tests\';

var
  GTestRoot: HKEY;

function OverridePredefinedKey(AKey, ANewKey: HKEY): Longint; stdcall;
  external 'advapi32.dll' name 'RegOverridePredefKey';

procedure OpenTestRegistry;
var
  LError: Longint;
  LPath: string;
  LGuid: TGUID;
begin
  // This unit is injected only into the generated blackbox-test program.
  // No environment-based registry redirection exists in the productive bridge.
  LPath := GetEnvironmentVariable('DAI_LAUNCHER_TEST_HKCU_ROOT');
  if not LPath.StartsWith(CTestPrefix) then
    raise EInvalidOperation.Create('The launcher test helper requires an isolated GUID registry root.');
  LGuid := StringToGUID(Copy(LPath, Length(CTestPrefix) + 1, MaxInt));
  if not SameText(LPath, CTestPrefix + GUIDToString(LGuid)) then
    raise EInvalidOperation.Create('The launcher test registry root must contain exactly one GUID.');
  LError := RegOpenKeyEx(HKEY_CURRENT_USER, PChar(LPath), 0, KEY_READ or KEY_WRITE or KEY_WOW64_64KEY, GTestRoot);
  if LError <> ERROR_SUCCESS then
    RaiseLastOSError(LError);
  LError := OverridePredefinedKey(HKEY_CURRENT_USER, GTestRoot);
  if LError <> ERROR_SUCCESS then
  begin
    RegCloseKey(GTestRoot);
    GTestRoot := 0;
    RaiseLastOSError(LError);
  end;
end;

initialization
  OpenTestRegistry;

finalization
  if GTestRoot <> 0 then
  begin
    OverridePredefinedKey(HKEY_CURRENT_USER, 0);
    RegCloseKey(GTestRoot);
  end;

end.
