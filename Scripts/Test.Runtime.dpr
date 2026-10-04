program TestRuntime;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DAI.Runtime.TestState,
  h5u.DAI.Log,
  h5u.DAI.MCP.Server,
  h5u.DAI.OTA.Build,
  h5u.DAI.OTA.CodeInsight,
  h5u.DAI.OTA.Evaluation,
  h5u.DAI.OTA.ExpressionUI,
  h5u.DAI.Options.Navigation,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Settings,
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
var
  LDefaultCalls: Integer;
  LExplicitCalls: Integer;
begin
  Check(TDAIRuntime.StartServer(7777, 'isolated-test-token'), 'isolated endpoint starts');
  Check(TDAIMCPServer.CreatedCount = 1, 'one runtime owner created');
  TDAISettings.Instance.Port := 7999;
  TDAISettings.Instance.Token := 'different-persisted-test-token';
  LDefaultCalls := TDAIMCPServer.DefaultStartCount;
  LExplicitCalls := TDAIMCPServer.ExplicitStartCount;
  Check(TDAIRuntime.StartServer, 'parameterless start is idempotent for active temporary endpoint');
  Check(TDAIMCPServer.DefaultStartCount = LDefaultCalls + 1, 'active start reaches the server state guard');
  Check(TDAIMCPServer.ExplicitStartCount = LExplicitCalls, 'active start never reapplies explicit persisted values');
  Check(TDAIRuntime.ServerPort = 7777, 'active temporary port remains unchanged');
  Check(TDAIMCPServer.LastAppliedToken = 'isolated-test-token', 'active temporary token remains unchanged');
  Check(TDAISettings.Instance.Port = 7999, 'persisted port remains distinct from runtime');
  Check(TDAISettings.Instance.Token = 'different-persisted-test-token', 'persisted token is not overwritten');
  TDAIMCPServer.FailureMode := 1;
  TDAIMCPServer.OnStop :=
    procedure
    begin
      Check(TDAIRuntime.ServerActive, 'server still reports active while its stop callback drains');
      Check(not TDAIRuntime.StartServer, 'parameterless start during drain is rejected');
      Check(TDAIRuntime.LastServerError.Contains('gestoppt'), 'drain refusal exposes the server reason');
      Check(TDAIRuntime.ServerPort = 7777, 'rejected drain start preserves active port until stop finishes');
      TDAIRuntime.Stop;
    end;
  TDAIMCPServer.OnDestroy := procedure begin TDAIRuntime.Stop; end;
  Events.Clear;
  TDAIRuntime.Stop;
  Check(Events.Count = 6, 'failed drain preserves dependent services');
  Check(Events[0] = 'log-shutdown', 'logging admission closes first');
  Check(Events[1] = 'evaluation-shutdown', 'debugger receivers close before HTTP drain');
  Check(Events[2] = 'expression-ui-shutdown', 'debugger editor callbacks close before modal HTTP drain');
  Check(Events[3] = 'options-navigation-shutdown', 'navigation callbacks close before modal HTTP drain');
  Check(Events[4] = 'insight-shutdown', 'insight admission closes before HTTP drain');
  Check(Events[5] = 'server-stop', 'server drain follows admission closure');
  Check(LoggerStopped and InsightStopped, 'both admissions remain closed after failed drain');
  Check(TDAIMCPServer.StopCount = 1, 'nested permanent Stop does not reenter server drain');
  Check(TDAILog.ShutdownCount = 1, 'nested Stop does not reenter logging shutdown');
  Check(TDAIEvaluationService.ShutdownCount = 1, 'nested Stop does not reenter debugger receiver shutdown');
  Check(TDAIExpressionUIService.ShutdownCount = 1, 'nested Stop does not reenter debugger editor shutdown');
  Check(TDAIOptionsNavigationService.ShutdownCount = 1, 'nested Stop does not reenter navigation shutdown');
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
  Check(Events.IndexOf('options-navigation-shutdown') < Events.IndexOf('server-stop'), 'retry cancels navigation before draining');
  Check(Events.IndexOf('evaluation-shutdown') < Events.IndexOf('server-stop'), 'retry cancels debugger receivers before draining');
  Check(Events.IndexOf('expression-ui-shutdown') < Events.IndexOf('server-stop'), 'retry cancels debugger editor callbacks before draining');
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

procedure DefaultStartExceptionChecks;
begin
  Check(TDAIRuntime.StartServer, 'inactive parameterless start uses current stored configuration');
  Check(TDAIRuntime.ServerPort = 7999, 'cold parameterless start applies persisted port');
  Check(TDAIMCPServer.LastAppliedToken = 'different-persisted-test-token', 'cold parameterless start applies persisted token');
  TDAIMCPServer.RaiseDefaultStart := True;
  try
    Check(not TDAIRuntime.StartServer, 'default-start producer exception is contained');
    Check(TDAIRuntime.LastServerError.Contains('isolated default start exception'), 'default-start exception appears in status');
    Check(Events[Events.Count - 1].Contains('isolated default start exception'), 'default-start exception is logged');
    Check(TDAIRuntime.ServerActive and (TDAIRuntime.ServerPort = 7999), 'contained exception does not overwrite active configuration');
  finally
    TDAIMCPServer.RaiseDefaultStart := False;
  end;
  Check(TDAIRuntime.StartServer, 'idempotent start recovers after producer exception');
  Check(TDAIRuntime.LastServerError = '', 'successful start clears the prior error');
  TDAIRuntime.Stop;
  Check(not TDAIRuntime.ServerActive, 'additional default-start endpoint is cleaned up');
  Check(TDAIMCPServer.UnsafeDestroyedCount = 0, 'default-start tests never destroy an undrained server');
end;

begin
  try
    FalseAndReentrantChecks;
    ExceptionAndFallbackChecks;
    DefaultStartExceptionChecks;
    Writeln(Format('PASS: %d runtime start/shutdown checks', [CheckCount]));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
