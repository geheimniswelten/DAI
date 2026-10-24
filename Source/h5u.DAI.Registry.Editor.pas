unit h5u.DAI.Registry.Editor;

interface

uses
  Winapi.Windows;

function DAIOpenUsageLogInRegistryEditor(const AOwner: HWND; out AErrorMessage: string): Boolean;

implementation

uses
  System.SysUtils,
  System.Win.Registry,
  Winapi.ShellAPI,
  h5u.DAI.Usage;

function DAIOpenUsageLogInRegistryEditor(const AOwner: HWND; out AErrorMessage: string): Boolean;
const
  CRegeditSettingsKey = 'Software\Microsoft\Windows\CurrentVersion\Applets\Regedit';
var
  LWindowsDirectory: array[0..MAX_PATH] of Char;
  LDirectoryLength: UINT;
  LExecutable: string;
  LRegistry: TRegistry;
  LExecuteInfo: TShellExecuteInfo;
  LError: DWORD;
begin
  Result := False;
  AErrorMessage := '';
  try
    LDirectoryLength := GetWindowsDirectory(LWindowsDirectory, Length(LWindowsDirectory));
    if LDirectoryLength = 0 then
      RaiseLastOSError;
    if LDirectoryLength >= UINT(Length(LWindowsDirectory)) then
      RaiseLastOSError(ERROR_INSUFFICIENT_BUFFER);
    LExecutable := IncludeTrailingPathDelimiter(string(LWindowsDirectory)) + 'regedit.exe';
    LRegistry := TRegistry.Create(KEY_WRITE or KEY_WOW64_64KEY);
    try
      LRegistry.RootKey := HKEY_CURRENT_USER;
      // An empty root is useful before the first tool call has been counted.
      if not LRegistry.OpenKey(CDAIUsageRegistryRoot, True) then
        raise EOSError.Create('Der Registry-Pfad für die Nutzungszähler konnte nicht geöffnet werden.');
      LRegistry.CloseKey;
      if not LRegistry.OpenKey(CRegeditSettingsKey, True) then
        raise EOSError.Create('Der Startpfad des Registrierungs-Editors konnte nicht gesetzt werden.');
      // Regedit has no command-line switch for selecting a key. /m opens a new window,
      // whose initial selection is read from its own LastKey preference.
      LRegistry.WriteString('LastKey', 'Computer\HKEY_CURRENT_USER\' + CDAIUsageRegistryRoot);
    finally
      LRegistry.Free;
    end;
    LExecuteInfo := Default(TShellExecuteInfo);
    LExecuteInfo.cbSize := SizeOf(LExecuteInfo);
    LExecuteInfo.fMask := SEE_MASK_FLAG_NO_UI or SEE_MASK_NOASYNC;
    LExecuteInfo.Wnd := AOwner;
    LExecuteInfo.lpVerb := 'open';
    LExecuteInfo.lpFile := PChar(LExecutable);
    LExecuteInfo.lpParameters := '/m';
    LExecuteInfo.nShow := SW_SHOWNORMAL;
    if not ShellExecuteEx(@LExecuteInfo) then
    begin
      LError := GetLastError;
      // Cancelling the normal Windows UAC prompt is not an application error.
      if LError = ERROR_CANCELLED then
        Exit;
      RaiseLastOSError(LError);
    end;
    Result := True;
  except
    on E: Exception do
      AErrorMessage := 'Der Registrierungs-Editor konnte nicht geöffnet werden: ' + E.Message;
  end;
end;

end.
