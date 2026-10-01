unit h5u.DAI.Runtime;

interface

type
  TDAIRuntime = class sealed
  strict private
    class var FServer: TObject;
    class var FLastServerError: string;
  public
    class procedure Start; static;
    class function ApplySettings: Boolean; static;
    class procedure Stop; static;
    class function StartServer: Boolean; static;
    class function StopServer: Boolean; static;
    class function ServerActive: Boolean; static;
    class function LastServerError: string; static;
  end;

implementation

uses
  System.SysUtils,
  h5u.DAI.Log,
  h5u.DAI.MCP.Server,
  h5u.DAI.OTA.Build,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Settings,
  h5u.DAI.UI;

class function TDAIRuntime.ApplySettings: Boolean;
begin
  FLastServerError := '';
  try
    if not Assigned(FServer) then
      FServer := TDAIMCPServer.Create;

    Result := TDAIMCPServer(FServer).ApplySettings;
    FLastServerError := TDAIMCPServer(FServer).LastError;
    if not Result and (FLastServerError = '') then
      FLastServerError := 'Der MCP-Server konnte nicht gestartet beziehungsweise gestoppt werden.';
  except
    on E: Exception do
    begin
      FLastServerError := Format('Die MCP-Servereinstellungen konnten nicht angewendet werden: %s: %s', [E.ClassName, E.Message]);
      TDAILog.Error(FLastServerError);
      Result := False;
    end;
  end;
end;

class function TDAIRuntime.StartServer: Boolean;
begin
  FLastServerError := '';
  try
    if not Assigned(FServer) then
      FServer := TDAIMCPServer.Create;
    Result := TDAIMCPServer(FServer).Start;
    FLastServerError := TDAIMCPServer(FServer).LastError;
  except
    on E: Exception do
    begin
      FLastServerError := 'Der MCP-Server konnte nicht gestartet werden: ' + E.Message;
      TDAILog.Error(FLastServerError);
      Result := False;
    end;
  end;
end;

class function TDAIRuntime.StopServer: Boolean;
begin
  FLastServerError := '';
  try
    if Assigned(FServer) then
      Result := TDAIMCPServer(FServer).Stop
    else
      Result := True;
    if Assigned(FServer) then
      FLastServerError := TDAIMCPServer(FServer).LastError;
    if Result then
      TDAIPermissionManager.Instance.ClearAllSessions;
  except
    on E: Exception do
    begin
      FLastServerError := 'Der MCP-Server konnte nicht gestoppt werden: ' + E.Message;
      TDAILog.Error(FLastServerError);
      Result := False;
    end;
  end;
end;

class function TDAIRuntime.LastServerError: string;
begin
  Result := FLastServerError;
end;

class function TDAIRuntime.ServerActive: Boolean;
begin
  Result := Assigned(FServer) and TDAIMCPServer(FServer).Active;
end;

class procedure TDAIRuntime.Start;
begin
  FLastServerError := '';
  try
    TDAISettings.Instance.Load;
    if TDAISettings.Instance.Enabled then
      StartServer;
  except
    on E: Exception do
    begin
      FLastServerError := Format('Die DAI-Laufzeit konnte nicht vollständig gestartet werden: %s: %s', [E.ClassName, E.Message]);
      TDAILog.Error(FLastServerError);
    end;
  end;
end;

class procedure TDAIRuntime.Stop;
begin
  try
    if Assigned(FServer) then
    begin
      TDAIMCPServer(FServer).Stop;
      FLastServerError := TDAIMCPServer(FServer).LastError;
    end;
    FreeAndNil(FServer);
  except
    on E: Exception do
    begin
      FLastServerError := Format('Die DAI-Laufzeit konnte den MCP-Server nicht vollständig freigeben: %s: %s', [E.ClassName, E.Message]);
      TDAILog.Error(FLastServerError);
    end;
  end;

  TDAIPermissionManager.Instance.ClearAllSessions;
  TDAIBuildService.Shutdown;
  TDAIUIService.Shutdown;
end;

initialization

finalization
  TDAIRuntime.Stop;

end.
