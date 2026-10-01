program TestRuntime;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DAI.Runtime.TestState,
  h5u.DAI.Log,
  h5u.DAI.MCP.Server,
  h5u.DAI.OTA.Build,
  h5u.DAI.OTA.CodeInsight,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.UI;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure FalseAndReentrantChecks;
begin
  Check(TDAIRuntime.StartServer(7777, 'isolated-test-token'), 'isolated endpoint starts');
  Check(TDAIMCPServer.CreatedCount = 1, 'one runtime owner created');
  TDAIMCPServer.FailureMode := 1;
  TDAIMCPServer.OnStop := procedure begin TDAIRuntime.Stop; end;
  TDAIMCPServer.OnDestroy := procedure begin TDAIRuntime.Stop; end;
  Events.Clear;
  TDAIRuntime.Stop;
  Check(Events.Count = 3, 'failed drain preserves dependent services');
  Check(Events[0] = 'log-shutdown', 'logging admission closes first');
  Check(Events[1] = 'insight-shutdown', 'insight admission closes before HTTP drain');
  Check(Events[2] = 'server-stop', 'server drain follows admission closure');
  Check(LoggerStopped and InsightStopped, 'both admissions remain closed after failed drain');
  Check(TDAIMCPServer.StopCount = 1, 'nested permanent Stop does not reenter server drain');
  Check(TDAILog.ShutdownCount = 1, 'nested Stop does not reenter logging shutdown');
  Check(TDAICodeInsightService.ShutdownCount = 1, 'nested Stop does not reenter insight shutdown');
  Check(TDAIMCPServer.DestroyedCount = 0, 'failed drain never destroys server');
  Check(TDAIRuntime.ServerActive and (TDAIRuntime.ServerPort = 7777), 'failed server object remains valid');
  Check(TDAIRuntime.LastServerError = 'isolated drain failure', 'failed drain error preserved');
  Check(TDAIPermissionManager.ClearCount = 0, 'permissions remain alive on failed drain');
  Check(TDAIBuildService.ShutdownCount = 0, 'build state remains alive on failed drain');
  Check(TDAIUIService.ShutdownCount = 0, 'UI state remains alive on failed drain');

  TDAIMCPServer.FailureMode := 0;
  Events.Clear;
  TDAIRuntime.Stop;
  Check(TDAIMCPServer.StopCount = 2, 'successful retry drains the same retained server');
  Check(TDAIMCPServer.DestroyedCount = 1, 'successful retry destroys server once');
  Check(TDAIMCPServer.UnsafeDestroyedCount = 0, 'no server is destroyed before a successful drain');
  Check(not TDAIRuntime.ServerActive and (TDAIRuntime.ServerPort = 0), 'successful retry clears runtime owner');
  Check(TDAIRuntime.LastServerError = '', 'successful retry clears previous error');
  Check(TDAIPermissionManager.ClearCount = 1, 'successful retry clears permissions once');
  Check(TDAIBuildService.ShutdownCount = 1, 'successful retry closes build state once');
  Check(TDAIUIService.ShutdownCount = 1, 'successful retry closes UI state once');
  Check(Events.IndexOf('server-destroy') < Events.IndexOf('permissions-clear'), 'dependent state closes after destruction');
  TDAIRuntime.Stop;
  Check(TDAIMCPServer.DestroyedCount = 1, 'repeated permanent Stop is idempotent for ownership');
  Check(TDAIMCPServer.StopCount = 2, 'repeated Stop does not call a freed server');
end;

procedure ExceptionAndFallbackChecks;
begin
  TDAIMCPServer.OnStop := nil;
  TDAIMCPServer.OnDestroy := nil;
  Check(TDAIRuntime.StartServer(7778, 'isolated-test-token'), 'second disposable endpoint starts');
  TDAIMCPServer.FailureMode := 2;
  TDAIRuntime.Stop;
  Check(TDAIMCPServer.DestroyedCount = 1, 'drain exception preserves the second server');
  Check(TDAIRuntime.LastServerError.Contains('isolated drain exception'), 'drain exception is retained as status');
  TDAIMCPServer.FailureMode := 3;
  TDAIRuntime.Stop;
  Check(TDAIMCPServer.DestroyedCount = 1, 'empty-error failure also preserves server');
  Check(TDAIRuntime.LastServerError <> '', 'empty failure gets an actionable status');
  TDAIMCPServer.FailureMode := 0;
  TDAIRuntime.Stop;
  Check(TDAIMCPServer.DestroyedCount = 2, 'second endpoint released after final retry');
  Check(TDAIMCPServer.UnsafeDestroyedCount = 0, 'all destructors follow successful drain');
end;

begin
  try
    FalseAndReentrantChecks;
    ExceptionAndFallbackChecks;
    Writeln(Format('PASS: %d runtime shutdown checks', [CheckCount]));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
