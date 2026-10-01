unit h5u.DAI.Runtime;

interface

type
  TDAIRuntime = class sealed
  private
    class var FActive: Boolean;
    class var FStartedPort: Integer;
  public
    class var CapturedPort: Integer;
    class var CapturedToken: string;
    class var StartCount: Integer;
    class var LegacyStartCount: Integer;
    class var StopCount: Integer;
    class var ApplyCount: Integer;
    class procedure Reset; static;
    class function StartServer: Boolean; overload; static;
    class function StartServer(const APort: Integer; const AToken: string): Boolean; overload; static;
    class function StopServer: Boolean; static;
    class function ApplySettings: Boolean; static;
    class function ServerActive: Boolean; static;
    class function ServerPort: Integer; static;
    class function LastServerError: string; static;
    class function ValidateServerConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  h5u.DAI.Settings;

class function TDAIRuntime.ApplySettings: Boolean;
begin
  Inc(ApplyCount);
  Result := True;
end;

class function TDAIRuntime.LastServerError: string;
begin
  Result := '';
end;

class procedure TDAIRuntime.Reset;
begin
  FActive := False;
  FStartedPort := 0;
  CapturedPort := 0;
  CapturedToken := '';
  StartCount := 0;
  LegacyStartCount := 0;
  StopCount := 0;
  ApplyCount := 0;
end;

class function TDAIRuntime.ServerActive: Boolean;
begin
  Result := FActive;
end;

class function TDAIRuntime.ServerPort: Integer;
begin
  Result := FStartedPort;
end;

class function TDAIRuntime.StartServer: Boolean;
begin
  // Keep the old API functional so the original UI handler fails the value assertion.
  Inc(LegacyStartCount);
  Result := StartServer(TDAISettings.Instance.Port, TDAISettings.Instance.Token);
end;

class function TDAIRuntime.StartServer(const APort: Integer; const AToken: string): Boolean;
var
  LError: string;
begin
  if not ValidateServerConfiguration(APort, AToken, LError) then
    raise EArgumentException.Create(LError);
  Inc(StartCount);
  CapturedPort := APort;
  CapturedToken := AToken;
  FStartedPort := APort;
  FActive := True;
  Result := True;
end;

class function TDAIRuntime.StopServer: Boolean;
begin
  Inc(StopCount);
  FActive := False;
  FStartedPort := 0;
  Result := True;
end;

class function TDAIRuntime.ValidateServerConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean;
begin
  Result := (APort >= 1) and (APort <= 65535) and (Trim(AToken) <> '');
  if Result then
    AError := ''
  else
    AError := 'Invalid synthetic server configuration.';
end;

end.
