unit h5u.DAI.MCP.Instance;

interface

uses
  System.SysUtils,
  Winapi.Windows;

type
  TDAIMCPInstanceLease = class sealed
  private
    FLock: TObject;
    FHandle: THandle;
    FName: string;
    FLastError: string;
    function GetLastErrorText: string;
  public
    constructor Create(const AName: string = '');
    destructor Destroy; override;
    function TryAcquire: Boolean;
    procedure Release;
    property LastError: string read GetLastErrorText;
  end;

implementation

function DefaultInstanceName: string;
var
  LToken: THandle;
  LRequired: DWORD;
  LUser: TBytes;
  LSid: LPWSTR;
begin
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, LToken) then
    RaiseLastOSError;
  try
    LRequired := 0;
    GetTokenInformation(LToken, TokenUser, nil, 0, LRequired);
    if LRequired = 0 then
      RaiseLastOSError;
    SetLength(LUser, LRequired);
    if not GetTokenInformation(LToken, TokenUser, @LUser[0], LRequired, LRequired) then
      RaiseLastOSError;
    LSid := nil;
    if not ConvertSidToStringSidW(PTokenUser(@LUser[0])^.User.Sid, LSid) then
      RaiseLastOSError;
    try
      Result := 'Global\DAI.MCP.Server.' + string(LSid);
    finally
      LocalFree(HLOCAL(LSid));
    end;
  finally
    CloseHandle(LToken);
  end;
end;

constructor TDAIMCPInstanceLease.Create(const AName: string);
begin
  inherited Create;
  FLock := TObject.Create;
  FName := AName;
  if FName = '' then
    try
      FName := DefaultInstanceName;
    except
      on E: Exception do
        FLastError := 'Die Windows-Benutzerkennung fuer die DAI-Serversperre konnte nicht ermittelt werden: ' + E.Message;
    end;
end;

destructor TDAIMCPInstanceLease.Destroy;
begin
  if Assigned(FLock) then
    Release;
  FLock.Free;
  inherited;
end;

function TDAIMCPInstanceLease.TryAcquire: Boolean;
var
  LHandle: THandle;
  LError: DWORD;
begin
  System.TMonitor.Enter(FLock);
  try
    if FHandle <> 0 then
    begin
      FLastError := '';
      Exit(True);
    end;
    if FName = '' then
      Exit(False);
    Winapi.Windows.SetLastError(ERROR_SUCCESS);
    LHandle := CreateMutex(nil, False, PChar(FName));
    LError := Winapi.Windows.GetLastError;
    if LHandle = 0 then
    begin
      FLastError := Format('Die DAI-Serversperre konnte nicht erstellt werden. Windows-Fehler %d: %s', [LError, SysErrorMessage(LError)]);
      Exit(False);
    end;
    if LError = ERROR_ALREADY_EXISTS then
    begin
      CloseHandle(LHandle);
      FLastError := 'DAI ist bereits in einer anderen Delphi-IDE aktiv. Stoppen Sie DAI dort und starten Sie den Server hier erneut.';
      Exit(False);
    end;
    // This is an existence lease, not thread ownership. Keep only the creator handle.
    FHandle := LHandle;
    FLastError := '';
    Result := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TDAIMCPInstanceLease.Release;
begin
  System.TMonitor.Enter(FLock);
  try
    if FHandle <> 0 then
    begin
      CloseHandle(FHandle);
      FHandle := 0;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TDAIMCPInstanceLease.GetLastErrorText: string;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FLastError;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
