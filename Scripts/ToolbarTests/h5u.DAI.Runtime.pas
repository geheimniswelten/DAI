unit h5u.DAI.Runtime;

interface

uses
  System.Classes,
  System.SysUtils;

type
  TDAIRuntime = class sealed
  public
    class var Active: Boolean;
    class var HasMCPAccess: Boolean;
    class var MCPAccessAgeMs: UInt64;
    class var Port: Integer;
    class var ErrorText: string;
    class var FailStart: Boolean;
    class var FailStop: Boolean;
    class var RaiseStart: Boolean;
    class var RaiseStop: Boolean;
    class var StartCount: Integer;
    class var StopCount: Integer;
    class var OnStart: TProc;
    class var OnStop: TProc;
    class function StartServer: Boolean; static;
    class function StopServer: Boolean; static;
    class function ServerActive: Boolean; static;
    class function ServerPort: Integer; static;
    class function LastServerError: string; static;
    class function TryGetMCPAccessAgeMs(out AAgeMs: UInt64): Boolean; static;
    class procedure Reset; static;
  end;

implementation

uses
  h5u.DAI.Settings;

class function TDAIRuntime.StartServer: Boolean;
begin
  Inc(StartCount);
  ErrorText := '';
  if Assigned(OnStart) then
    OnStart;
  if RaiseStart then
    raise EInvalidOperation.Create('isolated start exception');
  Result := not FailStart;
  if Result then
  begin
    Active := True;
    Port := TDAISettings.Instance.Port;
  end
  else
    ErrorText := 'isolated bind failed';
end;

class function TDAIRuntime.StopServer: Boolean;
begin
  Inc(StopCount);
  ErrorText := '';
  if Assigned(OnStop) then
    OnStop;
  if RaiseStop then
    raise EInvalidOperation.Create('isolated stop exception');
  Result := not FailStop;
  if Result then
    Active := False
  else
    ErrorText := 'isolated drain failed';
end;

class function TDAIRuntime.ServerActive: Boolean;
begin
  Result := Active;
end;

class function TDAIRuntime.ServerPort: Integer;
begin
  Result := Port;
end;

class function TDAIRuntime.LastServerError: string;
begin
  Result := ErrorText;
end;

class function TDAIRuntime.TryGetMCPAccessAgeMs(out AAgeMs: UInt64): Boolean;
begin
  AAgeMs := MCPAccessAgeMs;
  Result := HasMCPAccess;
end;

class procedure TDAIRuntime.Reset;
begin
  Active := False;
  HasMCPAccess := False;
  MCPAccessAgeMs := 0;
  Port := 0;
  ErrorText := '';
  FailStart := False;
  FailStop := False;
  RaiseStart := False;
  RaiseStop := False;
  StartCount := 0;
  StopCount := 0;
  OnStart := nil;
  OnStop := nil;
end;

end.
