program Test.ToolDispatch;

{$APPTYPE CONSOLE}
{$R 'dai-test-as-invoker.res'}

uses
  System.Classes,
  System.JSON,
  System.SysUtils,
  DAI.ToolDispatch.ProductionBranch,
  h5u.DAI.IDE.Control,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Types;

var
  GChecks: Integer;
  GContext: TDAIRequestContext;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create('Pruefung fehlgeschlagen: ' + ADescription);
end;

procedure CheckRequest(const AIndex: Integer; const ACategory: TDAIPermissionCategory; const AOperation: string);
var
  LRequest: TPermissionRequest;
begin
  Check(AIndex < Length(TDAIPermissionManager.Instance.Requests), 'Berechtigungsanfrage vorhanden');
  LRequest := TDAIPermissionManager.Instance.Requests[AIndex];
  Check(LRequest.Category = ACategory, 'Berechtigungsreihenfolge');
  Check(LRequest.Operation = AOperation, 'kanonischer Operationsname');
  Check(LRequest.Resource = '', 'Fensteraktion ohne fremde Ressource');
  Check(LRequest.Context.ThreadId = GContext.ThreadId, 'Thread-Kontext bleibt erhalten');
  Check(LRequest.Context.TransportSessionId = GContext.TransportSessionId, 'Transport-Kontext bleibt erhalten');
  Check(LRequest.Context.ProjectKey = GContext.ProjectKey, 'Projekt-Kontext bleibt erhalten');
  Check(LRequest.Context.ClientName = GContext.ClientName, 'Client-Kontext bleibt erhalten');
end;

procedure TestAction(const AInput: string; const ACanonical: string; const AEditAllowed: Boolean; const AExecuteAllowed: Boolean);
var
  LArguments: TJSONObject;
  LDenied: Boolean;
  LExpectedAllowed: Boolean;
  LResult: TJSONObject;
begin
  TDAIPermissionManager.Instance.Reset(AEditAllowed, AExecuteAllowed);
  TDAIIDEControl.Reset;
  LArguments := TJSONObject.Create;
  LResult := nil;
  LDenied := False;
  LExpectedAllowed := AEditAllowed and ((ACanonical <> 'close') or AExecuteAllowed);
  try
    LArguments.AddPair('action', AInput);
    try
      LResult := DispatchWindowControl('IDE_WINDOW_CONTROL', LArguments, GContext);
    except
      on E: EAbort do
        LDenied := True;
    end;
    Check(LDenied = not LExpectedAllowed, 'Freigabe entspricht den beiden Kategorien: ' + AInput);
    Check(Assigned(LResult) = LExpectedAllowed, 'kein Erfolgsobjekt bei Verweigerung');
    CheckRequest(0, pcEditInsideIDE, 'Delphi-IDE-Fenster steuern: ' + ACanonical);
    if AEditAllowed and (ACanonical = 'close') then
    begin
      Check(Length(TDAIPermissionManager.Instance.Requests) = 2, 'close fordert zusaetzlich execute an');
      CheckRequest(1, pcExecute, 'Delphi-IDE normal schließen');
    end
    else
      Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'kein unnoetiger Execute-Zugriff');
    if LExpectedAllowed then
    begin
      Check(TDAIIDEControl.ControlCalls = 1, 'genau ein Control-Aufruf nach Freigabe');
      Check(TDAIIDEControl.LastAction = ACanonical, 'Control erhaelt exakt die kanonische Aktion');
      Check(LResult.GetValue<string>('action') = ACanonical, 'Antwort der ausgefuehrten Aktion');
      Check(TDAIIDEControl.DeferredCloseCalls = Ord(ACanonical = 'close'), 'Close nur nach beiden Freigaben');
    end
    else
    begin
      Check(TDAIIDEControl.ControlCalls = 0, 'kein Control-Aufruf nach Verweigerung');
      Check(TDAIIDEControl.DeferredCloseCalls = 0, 'keine ausstehende Schliessaktion nach Verweigerung');
      Check(TDAIIDEControl.LastAction = '', 'keine uebergebene Aktion nach Verweigerung');
    end;
  finally
    LResult.Free;
    LArguments.Free;
  end;
end;

procedure TestInvalidArgument(const AArguments: TJSONObject);
var
  LRejected: Boolean;
  LResult: TJSONObject;
begin
  TDAIPermissionManager.Instance.Reset(True, False);
  TDAIIDEControl.Reset;
  LRejected := False;
  LResult := nil;
  try
    try
      LResult := DispatchWindowControl('ide_window_control', AArguments, GContext);
    except
      on E: EArgumentException do
        LRejected := True;
    end;
    Check(LRejected, 'fehlender oder nicht als String angegebener Wert ist ungueltig');
    Check(not Assigned(LResult), 'kein Ergebnis fuer ungueltige Aktion');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 1, 'ungueltige Aktion fordert kein execute an');
    CheckRequest(0, pcEditInsideIDE, 'Delphi-IDE-Fenster steuern: ');
    Check(TDAIIDEControl.ControlCalls = 1, 'ungueltige Aktion wird vom Control-Vertrag abgewiesen');
    Check(TDAIIDEControl.LastAction = '', 'ArgumentString akzeptiert keine Zahl/Boolean/null');
    Check(TDAIIDEControl.DeferredCloseCalls = 0, 'ungueltige Aktion stellt kein Close bereit');
  finally
    LResult.Free;
  end;
end;

procedure RunTests;
const
  CCloseInputs: array[0..5] of string = ('close', 'CLOSE', 'Close', ' close ', #9' ClOsE '#9, #13#10'cLoSe'#13#10);
  CActions: array[0..3] of string = ('minimize', 'restore', 'foreground', 'background');
var
  LAction: string;
  LArguments: TJSONObject;
  LClose: string;
  LResult: TJSONObject;
  LUnknownRejected: Boolean;
begin
  GContext.ThreadId := 'dispatch-test-thread';
  GContext.TransportSessionId := 'dispatch-test-session';
  GContext.ProjectKey := 'C:\IsolatedDispatchTest\Project.dproj';
  GContext.ClientName := 'dispatch-test-client';
  for LClose in CCloseInputs do
  begin
    TestAction(LClose, 'close', True, False);
    TestAction(LClose, 'close', True, True);
    TestAction(LClose, 'close', False, True);
    TestAction(LClose, 'close', False, False);
  end;
  for LAction in CActions do
  begin
    TestAction(LAction, LAction, True, False);
    TestAction(' ' + UpperCase(LAction) + #9, LAction, True, False);
    TestAction(LAction, LAction, False, False);
  end;
  TestInvalidArgument(nil);
  LArguments := TJSONObject.Create;
  try
    TestInvalidArgument(LArguments);
    LArguments.AddPair('action', TJSONNull.Create);
    TestInvalidArgument(LArguments);
  finally
    LArguments.Free;
  end;
  LArguments := TJSONObject.Create;
  try
    LArguments.AddPair('action', TJSONNumber.Create(1));
    TestInvalidArgument(LArguments);
  finally
    LArguments.Free;
  end;
  LArguments := TJSONObject.Create;
  try
    LArguments.AddPair('action', TJSONBool.Create(True));
    TestInvalidArgument(LArguments);
  finally
    LArguments.Free;
  end;
  TDAIPermissionManager.Instance.Reset(True, True);
  TDAIIDEControl.Reset;
  LUnknownRejected := False;
  LResult := nil;
  try
    try
      LResult := DispatchWindowControl('other_tool', nil, GContext);
    except
      on E: EArgumentException do
        LUnknownRejected := True;
    end;
    Check(LUnknownRejected, 'Fixture ist auf den tatsaechlichen Fensterzweig begrenzt');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'kein Dispatch fuer fremde Tools');
    Check(TDAIIDEControl.ControlCalls = 0, 'kein Control fuer fremde Tools');
    Check(TDAIIDEControl.DeferredCloseCalls = 0, 'kein Close fuer fremde Tools');
  finally
    LResult.Free;
  end;
end;

procedure TestLifecycleDenial;
var
  LArguments, LResult: TJSONObject;
  LDenied: Boolean;
begin
  TDAIPermissionManager.Instance.Reset(True, True);
  TDAIIDEControl.Reset;
  TDAIIDEControl.LifecycleAllowed := False;
  LArguments := TJSONObject.Create;
  LResult := nil;
  LDenied := False;
  try
    LArguments.AddPair('action', ' CLOSE ');
    try
      LResult := DispatchWindowControl('ide_window_control', LArguments, GContext);
    except
      on E: EInvalidOperation do
        LDenied := True;
    end;
    Check(LDenied and not Assigned(LResult), 'Global lifecycle denial takes precedence over permission grants');
    Check(Length(TDAIPermissionManager.Instance.Requests) = 0, 'Disabled lifecycle does not display permission prompts');
    Check((TDAIIDEControl.ControlCalls = 0) and (TDAIIDEControl.DeferredCloseCalls = 0), 'Disabled lifecycle never dispatches close');
  finally
    LResult.Free;
    LArguments.Free;
    TDAIIDEControl.Reset;
  end;
end;

begin
  try
    RunTests;
    TestLifecycleDenial;
    Writeln('PASS ToolDispatch: ', GChecks, ' assertions');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
