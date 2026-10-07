unit h5u.DAI.Runtime;

interface

type
  TDAIRuntime = class sealed
  strict private
    class var FServer: TObject;
    class var FLastServerError: string;
    class var FStopping: Boolean;
  public
    class procedure Start; static;
    class function ApplySettings: Boolean; static;
    class procedure Stop; static;
    class function ValidateServerConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean; static;
    class function StartServer: Boolean; overload; static;
    class function StartServer(const APort: Integer; const AToken: string): Boolean; overload; static;
    class function ServerPort: Integer; static;
    class function StopServer: Boolean; static;
    class function ServerActive: Boolean; static;
    class function LastServerError: string; static;
    class function TryGetMCPAccessAgeMs(out AAgeMs: UInt64): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  h5u.DAI.Log,
  h5u.DAI.MCP.Server,
  h5u.DAI.OTA.Build,
  h5u.DAI.OTA.CodeInsight,
  h5u.DAI.OTA.Evaluation,
  h5u.DAI.OTA.ExpressionUI,
  h5u.DAI.Options.Navigation,
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

class function TDAIRuntime.ValidateServerConfiguration(const APort: Integer; const AToken: string; out AError: string): Boolean;
begin
  Result := TDAIMCPServer.ValidateConfiguration(APort, AToken, AError);
end;

class function TDAIRuntime.StartServer: Boolean;
begin
  FLastServerError := '';
  try
    if not Assigned(FServer) then
      FServer := TDAIMCPServer.Create;
    // The server checks shutdown before idempotence and preserves an active
    // temporary configuration instead of applying the persisted settings.
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

class function TDAIRuntime.StartServer(const APort: Integer; const AToken: string): Boolean;
begin
  FLastServerError := '';
  if not ValidateServerConfiguration(APort, AToken, FLastServerError) then
    Exit(False);
  try
    if not Assigned(FServer) then
      FServer := TDAIMCPServer.Create;
    Result := TDAIMCPServer(FServer).Start(APort, AToken);
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

class function TDAIRuntime.ServerPort: Integer;
begin
  if Assigned(FServer) then
    Result := TDAIMCPServer(FServer).Port
  else
    Result := 0;
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
  if Assigned(FServer) then
    Result := TDAIMCPServer(FServer).Active
  else
    Result := False;
end;

class function TDAIRuntime.TryGetMCPAccessAgeMs(out AAgeMs: UInt64): Boolean;
var
  LLastAccess: UInt64;
  LNow: UInt64;
begin
  AAgeMs := 0;
  if not Assigned(FServer) then
    Exit(False);
  LLastAccess := TDAIMCPServer(FServer).LastMCPAccessTick;
  if LLastAccess = 0 then
    Exit(False);
  LNow := TThread.GetTickCount64;
  if LNow >= LLastAccess then
    AAgeMs := LNow - LLastAccess;
  Result := True;
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
  if FStopping then
    Exit;
  FStopping := True;
  try
    // Close debugger and navigation callbacks before draining workers and modal UI loops.
    TDAILog.Shutdown;
    TDAIEvaluationService.Shutdown;
    TDAIExpressionUIService.Shutdown;
    TDAIOptionsNavigationService.Shutdown;
    TDAICodeInsightService.Shutdown;
    try
      if Assigned(FServer) then
      begin
        if not TDAIMCPServer(FServer).Stop then
        begin
          FLastServerError := TDAIMCPServer(FServer).LastError;
          if FLastServerError = '' then
            FLastServerError := 'Der MCP-Server konnte nicht vollständig beendet werden; die Laufzeit bleibt bis zum erfolgreichen Stop erhalten.';
          Exit;
        end;
        FLastServerError := TDAIMCPServer(FServer).LastError;
      end;
      FreeAndNil(FServer);
    except
      on E: Exception do
      begin
        FLastServerError := Format('Die DAI-Laufzeit konnte den MCP-Server nicht vollständig freigeben: %s: %s', [E.ClassName, E.Message]);
        TDAILog.Error(FLastServerError);
        Exit;
      end;
    end;

    TDAIPermissionManager.Instance.ClearAllSessions;
    TDAIBuildService.Shutdown;
    TDAIUIService.Shutdown;
  finally
    FStopping := False;
  end;
end;

initialization

finalization
  TDAIRuntime.Stop;

end.
