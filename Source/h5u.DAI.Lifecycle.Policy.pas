unit h5u.DAI.Lifecycle.Policy;

interface

type
  TDAILifecyclePolicy = class sealed
  public const
    CRegistryKey = 'Software\DelphiAI\DAI';
    CValueName = 'AllowIDEStartStop';
  public
    class function ReadAllowed(out AReason: string): Boolean; static;
    class procedure WriteAllowed(const AAllowed: Boolean); static;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows;

class function TDAILifecyclePolicy.ReadAllowed(out AReason: string): Boolean;
var
  LKey: HKEY;
  LStatus: Longint;
  LType: DWORD;
  LSize: DWORD;
  LValue: DWORD;
begin
  Result := False;
  AReason := 'settings_unreadable';
  LKey := 0;
  LStatus := RegOpenKeyEx(HKEY_CURRENT_USER, PChar(CRegistryKey), 0, KEY_QUERY_VALUE or KEY_WOW64_64KEY, LKey);
  if (LStatus = ERROR_FILE_NOT_FOUND) or (LStatus = ERROR_PATH_NOT_FOUND) then
  begin
    AReason := 'allowed_by_default';
    Exit(True);
  end;
  if LStatus <> ERROR_SUCCESS then
    Exit;
  try
    LType := REG_NONE;
    LSize := SizeOf(LValue);
    LValue := 0;
    LStatus := RegQueryValueEx(LKey, PChar(CValueName), nil, @LType, PByte(@LValue), @LSize);
    if LStatus = ERROR_FILE_NOT_FOUND then
    begin
      AReason := 'allowed_by_default';
      Exit(True);
    end;
    if LStatus <> ERROR_SUCCESS then
      Exit;
    if (LType <> REG_DWORD) or (LSize <> SizeOf(LValue)) then
      Exit;
    case LValue of
      0: AReason := 'disabled_in_dai_options';
      1:
      begin
        Result := True;
        AReason := 'allowed';
      end;
    end;
  finally
    RegCloseKey(LKey);
  end;
end;

class procedure TDAILifecyclePolicy.WriteAllowed(const AAllowed: Boolean);
var
  LKey: HKEY;
  LStatus: Longint;
  LValue: DWORD;
begin
  LKey := 0;
  LStatus := RegCreateKeyEx(HKEY_CURRENT_USER, PChar(CRegistryKey), 0, nil, REG_OPTION_NON_VOLATILE,
    KEY_SET_VALUE or KEY_WOW64_64KEY, nil, LKey, nil);
  if LStatus <> ERROR_SUCCESS then
    RaiseLastOSError(LStatus);
  try
    if AAllowed then
      LValue := 1
    else
      LValue := 0;
    LStatus := RegSetValueEx(LKey, PChar(CValueName), 0, REG_DWORD, PByte(@LValue), SizeOf(LValue));
    if LStatus <> ERROR_SUCCESS then
      RaiseLastOSError(LStatus);
  finally
    RegCloseKey(LKey);
  end;
end;

end.
