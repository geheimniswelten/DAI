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
    FDeactivating: Boolean;
    FToken: string;
  public
    class var CreatedCount, DestroyedCount, UnsafeDestroyedCount, StopCount: Integer;
    class var FailureMode: Integer;
    class var DefaultStartCount, ExplicitStartCount: Integer;
    class var LastAppliedPort: Integer;
    class var LastAppliedToken: string;
    class var RaiseDefaultStart: Boolean;
    class var AccessTick: UInt64;
    class var OnStop, OnDestroy: TProc;
    constructor Create;
    destructor Destroy; override;
    class function ValidateConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean; static;
    function Start: Boolean; overload;
    function Start(const APort: Integer; const AToken: string): Boolean; overload;
    function Stop: Boolean;
    function Active: Boolean;
    function ApplySettings: Boolean;
    function LastMCPAccessTick: UInt64;
    property LastError: string read FLastError;
    property Port: Integer read FPort;
  end;

implementation

uses
  DAI.Runtime.TestState,
  h5u.DAI.Settings;

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

function TDAIMCPServer.LastMCPAccessTick: UInt64;
begin
  Result := AccessTick;
end;

function TDAIMCPServer.ApplySettings: Boolean;
begin
  Result := Start(7777, 'isolated-runtime-fixture');
end;

function TDAIMCPServer.Start: Boolean;
begin
  Inc(DefaultStartCount);
  if RaiseDefaultStart then
    raise EInvalidOperation.Create('isolated default start exception');
  if FDeactivating then
  begin
    FLastError := 'Der MCP-Server wird gerade gestoppt.';
    Exit(False);
  end;
  if FActive then
  begin
    FLastError := '';
    Exit(True);
  end;
  Result := Start(TDAISettings.Instance.Port, TDAISettings.Instance.Token);
end;

function TDAIMCPServer.Start(const APort: Integer; const AToken: string): Boolean;
begin
  Inc(ExplicitStartCount);
  if FDeactivating then
  begin
    FLastError := 'Der MCP-Server wird gerade gestoppt.';
    Exit(False);
  end;
  if FActive then
  begin
    Result := (FPort = APort) and (FToken = AToken);
    if Result then
      FLastError := ''
    else
      FLastError := 'Already active with a different configuration.';
    Exit;
  end;
  FActive := True;
  AccessTick := 0;
  FDrainSucceeded := False;
  FPort := APort;
  FToken := AToken;
  LastAppliedPort := APort;
  LastAppliedToken := AToken;
  FLastError := '';
  Result := True;
end;

function TDAIMCPServer.Stop: Boolean;
begin
  Inc(StopCount);
  Events.Add('server-stop');
  FDeactivating := True;
  try
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
    FToken := '';
    FLastError := '';
    Result := True;
  finally
    FDeactivating := False;
  end;
end;

end.
