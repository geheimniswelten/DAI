unit CodexMCP.Host;

interface

type
  TCodexMCPHost = class sealed
  strict private
    class var FInstance: TCodexMCPHost;
    FLastError: string;
    FServer: TObject;
    function GetRunning: Boolean;
    function GetPort: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    class destructor DestroyClass;
    class function Instance: TCodexMCPHost; static;
    class procedure ShutdownInstance; static;
    procedure ApplySettings;
    procedure Shutdown;
    function StatusText: string;
    property Running: Boolean read GetRunning;
    property Port: Integer read GetPort;
    property LastError: string read FLastError;
  end;

implementation

uses
  System.SysUtils,
  CodexMCP.Logger,
  CodexMCP.Server,
  CodexMCP.Settings;

{ TCodexMCPHost }

constructor TCodexMCPHost.Create;
begin
  inherited Create;
  FServer := TCodexMCPServer.Create;
  FLastError := '';
end;

destructor TCodexMCPHost.Destroy;
begin
  Shutdown;
  FServer.Free;
  inherited;
end;

procedure TCodexMCPHost.ApplySettings;
var
  LSettings: TCodexMCPSettings;
begin
  LSettings := TCodexMCPSettings.Instance;
  FLastError := '';
  try
    TCodexMCPServer(FServer).Stop;
    if LSettings.Enabled then
    begin
      TCodexMCPServer(FServer).Start(LSettings.Port, LSettings.AuthToken);
      TCodexMCPLogger.Log(
        'server',
        Format('Gestartet auf 127.0.0.1:%d', [LSettings.Port])
      );
    end
    else
      TCodexMCPLogger.Log('server', 'Deaktiviert');
  except
    on E: Exception do
    begin
      FLastError := E.ClassName + ': ' + E.Message;
      TCodexMCPLogger.Log('server', 'Startfehler: ' + E.Message);
    end;
  end;
end;

class destructor TCodexMCPHost.DestroyClass;
begin
  ShutdownInstance;
end;

function TCodexMCPHost.GetPort: Integer;
begin
  Result := TCodexMCPServer(FServer).Port;
end;

function TCodexMCPHost.GetRunning: Boolean;
begin
  Result := TCodexMCPServer(FServer).Active;
end;

class function TCodexMCPHost.Instance: TCodexMCPHost;
begin
  if not Assigned(FInstance) then
    FInstance := TCodexMCPHost.Create;
  Result := FInstance;
end;

class procedure TCodexMCPHost.ShutdownInstance;
begin
  FreeAndNil(FInstance);
end;

procedure TCodexMCPHost.Shutdown;
begin
  if Assigned(FServer) then
    TCodexMCPServer(FServer).Stop;
end;

function TCodexMCPHost.StatusText: string;
begin
  if Running then
    Result := Format('Aktiv auf http://127.0.0.1:%d/mcp', [Port])
  else if FLastError <> '' then
    Result := 'Fehler: ' + FLastError
  else
    Result := 'Nicht aktiv';
end;

end.
