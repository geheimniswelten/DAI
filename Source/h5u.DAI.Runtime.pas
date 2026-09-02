unit h5u.DAI.Runtime;

interface

type
  TDAIRuntime = class sealed
  strict private
    class var FServer: TObject;
  public
    class procedure Start; static;
    class procedure ApplySettings; static;
    class procedure Stop; static;
    class function ServerActive: Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  h5u.DAI.MCP.Server,
  h5u.DAI.OTA.Build,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Settings,
  h5u.DAI.UI;

class procedure TDAIRuntime.ApplySettings;
begin
  if not Assigned(FServer) then
    FServer := TDAIMCPServer.Create;
  TDAIMCPServer(FServer).ApplySettings;
end;

class function TDAIRuntime.ServerActive: Boolean;
begin
  Result := Assigned(FServer) and TDAIMCPServer(FServer).Active;
end;

class procedure TDAIRuntime.Start;
begin
  TDAISettings.Instance.Load;
  ApplySettings;
end;

class procedure TDAIRuntime.Stop;
begin
  if Assigned(FServer) then
    TDAIMCPServer(FServer).Stop;
  FreeAndNil(FServer);
  TDAIPermissionManager.Instance.ClearAllSessions;
  TDAIBuildService.Shutdown;
  TDAIUIService.Shutdown;
end;

initialization

finalization
  TDAIRuntime.Stop;

end.
