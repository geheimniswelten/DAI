unit h5u.DAI.MCP.Server;

interface

uses
  System.Classes,
  System.SysUtils;

type
  TDAIMCPServer = class
  private
    FActive: Boolean;
    FPort: Integer;
    FLastError: string;
    FDrainSucceeded: Boolean;
  public
    class var CreatedCount, DestroyedCount, UnsafeDestroyedCount, StopCount: Integer;
    class var FailureMode: Integer;
    class var OnStop, OnDestroy: TProc;
    constructor Create;
    destructor Destroy; override;
    class function ValidateConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean; static;
    function Start(const APort: Integer; const AToken: string): Boolean;
    function Stop: Boolean;
    function Active: Boolean;
    function ApplySettings: Boolean;
    property LastError: string read FLastError;
    property Port: Integer read FPort;
  end;

implementation

uses
  DAI.Runtime.TestState;

constructor TDAIMCPServer.Create;
begin
  inherited;
  Inc(CreatedCount);
end;

destructor TDAIMCPServer.Destroy;
begin
  if not FDrainSucceeded then
    Inc(UnsafeDestroyedCount);
  if Assigned(OnDestroy) then
    OnDestroy();
  Inc(DestroyedCount);
  Events.Add('server-destroy');
  inherited;
end;

class function TDAIMCPServer.ValidateConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean;
begin
  AError := '';
  Result := (APort >= 1024) and (APort <= 65535) and (AToken <> '');
end;

function TDAIMCPServer.Active: Boolean;
begin
  Result := FActive;
end;

function TDAIMCPServer.ApplySettings: Boolean;
begin
  Result := Start(7777, 'isolated-runtime-fixture');
end;

function TDAIMCPServer.Start(const APort: Integer; const AToken: string): Boolean;
begin
  FActive := True;
  FDrainSucceeded := False;
  FPort := APort;
  Result := True;
end;

function TDAIMCPServer.Stop: Boolean;
begin
  Inc(StopCount);
  Events.Add('server-stop');
  if Assigned(OnStop) then
    OnStop();
  case FailureMode of
    1: begin FLastError := 'isolated drain failure'; Exit(False); end;
    2: raise EInvalidOperation.Create('isolated drain exception');
    3: begin FLastError := ''; Exit(False); end;
  end;
  FDrainSucceeded := True;
  FActive := False;
  FPort := 0;
  FLastError := '';
  Result := True;
end;

end.
