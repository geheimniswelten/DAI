program Test.CodeInsight;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  DAI.CodeInsight.Fixture,
  h5u.DAI.OTA.CodeInsight,
  h5u.DAI.OTA.Helpers;

const
  CInputFile = 'C:\SyntheticDAICodeInsight\Input.pas';

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + AMessage);
end;

procedure CheckDefinition(const AResult: TJSONObject; const AProvider: TTestCodeInsightProvider; const AExpectedCharacter: Integer;
  const ACase: string);
begin
  Check(AResult.GetValue<Boolean>('success'), ACase + ': successful');
  Check(AResult.GetValue<Boolean>('found'), ACase + ': definition found');
  Check(not AResult.GetValue<Boolean>('timed_out'), ACase + ': no false timeout');
  Check(AResult.GetValue<string>('provider_id') = AProvider.ProviderId, ACase + ': selected provider');
  Check(AResult.GetValue<Integer>('request_id') = AProvider.RequestId, ACase + ': current request ID');
  Check(SameText(AResult.GetValue<string>('definition_file'), AProvider.ReplyFile), ACase + ': current result instead of stale file');
  Check(AResult.GetValue<Integer>('definition_line') = AProvider.ReplyLine, ACase + ': current result line');
  Check(AResult.GetValue<Integer>('definition_character') = AExpectedCharacter, ACase + ': current result character');
end;

procedure CheckDefinitionCapability(const AExpected: Boolean);
var
  LResult: TJSONObject;
  LManagers: TJSONArray;
  LManager: TJSONObject;
begin
  LResult := TDAICodeInsightService.Status(CInputFile);
  try
    LManagers := LResult.GetValue<TJSONArray>('managers');
    Check(LManagers.Count = 1, 'status reports the active synthetic provider');
    LManager := LManagers.Items[0] as TJSONObject;
    Check(LManager.GetValue<Boolean>('definition_character_supported') = AExpected,
      'definition character support reflects the provider interface');
  finally
    LResult.Free;
  end;
end;

procedure CheckTimeout(const AProvider: TTestCodeInsightProvider; const AHover: Boolean);
var
  LResult: TJSONObject;
  LPreviousCancelCount: Integer;
begin
  AProvider.Mode := pmTimeout;
  LPreviousCancelCount := AProvider.CancelCount;
  if AHover then
    LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 100)
  else
    LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 100);
  try
    Check(not LResult.GetValue<Boolean>('success'), 'timeout is not successful');
    Check(not LResult.GetValue<Boolean>('found'), 'timeout does not claim a result');
    Check(LResult.GetValue<Boolean>('timed_out'), 'timeout reported');
    Check(AProvider.CancelCount = LPreviousCancelCount + 1, 'OTA cancellation called once');
    Check(AProvider.CancelledId = AProvider.RequestId, 'OTA cancellation uses current request ID');
  finally
    LResult.Free;
  end;
end;

procedure TestWorkerCaller(const AProvider: TTestCodeInsightProvider);
var
  LDone: TEvent;
  LError: string;
  LResult: TJSONObject;
  LStartedAt: UInt64;
  LWorker: TThread;
begin
  AProvider.Mode := pmDeferred;
  LDone := TEvent.Create(nil, True, False, '');
  LError := '';
  LResult := nil;
  LWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
      except
        on E: Exception do
          LError := E.ClassName + ': ' + E.Message;
      end;
      LDone.SetEvent;
    end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    LStartedAt := GetTickCount64;
    while (LDone.WaitFor(0) <> wrSignaled) and (GetTickCount64 - LStartedAt < 3000) do
      CheckSynchronize(10);
    Check(LDone.WaitFor(0) = wrSignaled, 'worker caller completes with main-thread OTA dispatch');
    LWorker.WaitFor;
    Check(LError = '', 'worker caller raises no exception: ' + LError);
    Check(Assigned(LResult), 'worker caller returns JSON');
    CheckDefinition(LResult, AProvider, AProvider.ReplyCharacter, 'worker callback');
    AProvider.JoinWorker;
  finally
    LResult.Free;
    LWorker.Free;
    LDone.Free;
  end;
end;

procedure TestAdmissionLimit(const AProvider: TTestCodeInsightProvider; const AServices: TTestCodeInsightServices);
var
  LCallCount: Integer;
  LHintCount: Integer;
  LIndex: Integer;
  LResult: TJSONObject;
begin
  // No cancellation acknowledgement means the saved method pointer must stay alive.
  // Invocation errors after capture create the same retained state without 256 waits.
  AProvider.Mode := pmRaiseAfterCapture;
  for LIndex := 1 to 256 do
  begin
    LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
    try
      Check(not LResult.GetValue<Boolean>('success'), 'orphaned captured callback does not report success');
      Check(Pos('Synthetic provider keeps callback', LResult.GetValue<string>('message')) > 0,
        'each of the first 256 requests reaches the synthetic provider');
    finally
      LResult.Free;
    end;
  end;

  LCallCount := AProvider.DefinitionCount;
  LHintCount := AProvider.HintCount;
  AProvider.Mode := pmImmediate;
  LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
  try
    Check(not LResult.GetValue<Boolean>('success'), '257th pending request rejected');
    Check(not LResult.GetValue<Boolean>('found'), 'limit rejection has no result');
    Check(not LResult.GetValue<Boolean>('timed_out'), 'admission limit is not a provider timeout');
    Check(Pos('256', LResult.GetValue<string>('message')) > 0, 'limit rejection explains the bound');
    Check(AProvider.DefinitionCount = LCallCount, 'rejected definition never invokes provider');
  finally
    LResult.Free;
  end;

  LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 1000);
  try
    Check(not LResult.GetValue<Boolean>('success'), 'hover uses the same pending bound');
    Check(not LResult.GetValue<Boolean>('found'), 'rejected hover has no help');
    Check(Pos('256', LResult.GetValue<string>('message')) > 0, 'hover limit has explicit reason');
    Check(AProvider.HintCount = LHintCount, 'rejected hover never invokes provider');
    Check(AServices.ContextSetCount = AServices.ContextResetCount, 'admission rejection restores hover context');
  finally
    LResult.Free;
  end;

  AProvider.DeliverStoredDefinitions;
  LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
  try
    CheckDefinition(LResult, AProvider, AProvider.ReplyCharacter, 'late orphan completions reopen admission');
    Check(AProvider.DefinitionCount = LCallCount + 1, 'provider invocation resumes after late callbacks');
  finally
    LResult.Free;
  end;
end;

procedure CheckShutdownRejects(const AHover: Boolean);
var
  LRejected: Boolean;
  LResult: TJSONObject;
begin
  LRejected := False;
  LResult := nil;
  try
    try
      if AHover then
        LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 100)
      else
        LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 100);
    except
      on E: EInvalidOperation do
        LRejected := Pos('IDE-Neustart', E.Message) > 0;
    end;
    Check(LRejected, 'shutdown rejects a new request with an explicit reason');
    Check(not Assigned(LResult), 'shutdown does not fabricate a provider result');
  finally
    LResult.Free;
  end;
end;

procedure TestShutdown(const AProvider: TTestCodeInsightProvider; const AServices: TTestCodeInsightServices);
var
  LDefinitionCount: Integer;
  LHintCount: Integer;
  LSetCount: Integer;
  LResult: TJSONObject;
begin
  AProvider.Mode := pmImmediate;
  LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
  try
    CheckDefinition(LResult, AProvider, AProvider.ReplyCharacter, 'normal completion before shutdown');
    Check(AProvider.StoredDefinitionCount = 0, 'normal completion has no stored method pointer');
  finally
    LResult.Free;
  end;

  CheckTimeout(AProvider, False);
  CheckTimeout(AProvider, True);
  Check(AProvider.StoredDefinitionCount = 1, 'cancel does not revoke the retained definition callback');
  Check(AProvider.StoredHintCount = 1, 'cancel does not revoke the retained hover callback');
  LDefinitionCount := AProvider.DefinitionCount;
  LHintCount := AProvider.HintCount;
  LSetCount := AServices.ContextSetCount;
  TDAICodeInsightService.Shutdown;
  TDAICodeInsightService.Shutdown;
  CheckShutdownRejects(False);
  CheckShutdownRejects(True);
  Check(AProvider.DefinitionCount = LDefinitionCount, 'closed broker never invokes a new definition');
  Check(AProvider.HintCount = LHintCount, 'closed broker never invokes a new hint');
  Check(AServices.ContextSetCount = LSetCount, 'closed service does not set an editor query context');

  // The broker was detached by Shutdown. Both method pointers must still be safe.
  AProvider.DeliverStoredDefinitions;
  AProvider.DeliverStoredHints;
  Check(AProvider.StoredDefinitionCount = 0, 'late definition completed after shutdown');
  Check(AProvider.StoredHintCount = 0, 'late hover completed after shutdown');
  TDAICodeInsightService.Shutdown;
  CheckShutdownRejects(False);
end;

procedure RunTests;
var
  LA: TTestCodeInsightProviderEx;
  LB: TTestCodeInsightProviderEx;
  LLegacy: TTestCodeInsightProvider;
  LHoldA: IOTACodeInsightManager;
  LHoldB: IOTACodeInsightManager;
  LHoldLegacy: IOTACodeInsightManager;
  LEditor: TTestSourceEditor;
  LView: TTestEditView;
  LResult: TJSONObject;
  LServices: TTestCodeInsightServices;
  LSetBefore: Integer;
  LResetBefore: Integer;
  LIndex: Integer;
begin
  Check(not Assigned(BorlandIDEServices), 'standalone fixture starts without IDE services');
  LServices := TTestCodeInsightServices.Create;
  BorlandIDEServices := LServices;
  LA := TTestCodeInsightProviderEx.Create('ProviderA');
  LHoldA := LA;
  LB := TTestCodeInsightProviderEx.Create('ProviderB');
  LHoldB := LB;
  LLegacy := TTestCodeInsightProvider.Create('Legacy');
  LHoldLegacy := LLegacy;
  LEditor := TTestSourceEditor.Create;
  TestSourceEditor := LEditor;
  LView := TTestEditView.Create;
  LEditor.View := LView;
  try
    LServices.Provider := LHoldA;
    CheckDefinitionCapability(True);
    LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
    try
      CheckDefinition(LResult, LA, LA.ReplyCharacter, 'synchronous callback before ID registration');
      Check(LA.InputLine = 11, 'definition line remains one-based');
      Check(LA.InputCharacter = 3, 'definition character remains zero-based');
    finally
      LResult.Free;
    end;

    LA.RequestId := 700;
    CheckTimeout(LA, False);
    LA.Mode := pmImmediate;
    LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
    try
      CheckDefinition(LResult, LA, LA.ReplyCharacter, 'same provider reuses cancelled ID');
    finally
      LResult.Free;
    end;
    LA.DeliverStoredDefinitions;

    CheckTimeout(LA, False);
    LB.RequestId := LA.RequestId;
    LB.LateProvider := LA;
    LServices.Provider := LHoldB;
    LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
    try
      CheckDefinition(LResult, LB, LB.ReplyCharacter, 'provider switch and late old callback before new registration');
    finally
      LResult.Free;
    end;

    // More cancellations than the previous finite ID filter could remember.
    // A very late callback still belongs to its original receiver.
    for LIndex := 1 to 130 do
    begin
      LB.RequestId := 1000 + LIndex;
      LB.Mode := pmTimeout;
      if LIndex = 1 then
        CheckTimeout(LB, False)
      else
      begin
        LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 100);
        try
          Check(LResult.GetValue<Boolean>('timed_out'), 'additional timeout remains isolated');
        finally
          LResult.Free;
        end;
      end;
    end;
    LB.RequestId := 5000;
    LB.Mode := pmImmediate;
    LB.LateProvider := LB;
    LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
    try
      CheckDefinition(LResult, LB, LB.ReplyCharacter, 'very late callbacks cannot overwrite new unregistered request');
    finally
      LResult.Free;
    end;

    TestWorkerCaller(LB);

    LServices.Provider := LHoldLegacy;
    CheckDefinitionCapability(False);
    LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 1000);
    try
      CheckDefinition(LResult, LLegacy, 0, 'legacy callback without character result');
    finally
      LResult.Free;
    end;

    LServices.Provider := LHoldA;
    LA.RequestId := 9000;
    LSetBefore := LServices.ContextSetCount;
    LResetBefore := LServices.ContextResetCount;
    CheckTimeout(LA, True);
    LA.Mode := pmImmediate;
    LA.LateProvider := LA;
    LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 1000);
    try
      Check(LResult.GetValue<Boolean>('success'), 'hover reuses cancelled ID successfully');
      Check(LResult.GetValue<Boolean>('found'), 'hover returns current text');
      Check(not LResult.GetValue<Boolean>('timed_out'), 'hover does not inherit timeout');
      Check(LResult.GetValue<string>('content') = LA.HintText, 'late hint cannot overwrite current request');
      Check(LA.HintLine = 11, 'hover line remains one-based');
      Check(LA.HintColumn = 4, 'hover column remains one-based');
      Check(LServices.ContextSetCount = LSetBefore + 2, 'each hover sets its query context');
      Check(LServices.ContextResetCount = LResetBefore + 2, 'successful and timed out hovers both reset context');
    finally
      LResult.Free;
    end;

    LA.HintText := 'HTML';
    LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 1000);
    try
      Check(not LResult.GetValue<Boolean>('success'), 'HTML marker is unavailable');
      Check(not LResult.GetValue<Boolean>('found'), 'HTML marker is not useful help text');
      Check(LResult.GetValue<string>('content') = '', 'HTML marker is not exposed as content');
      Check(Pos('HTML-Marker', LResult.GetValue<string>('message')) > 0, 'unavailable marker has explicit reason');
      Check(not LResult.GetValue<Boolean>('timed_out'), 'HTML marker does not fabricate a timeout');
      Check(LA.HtmlViewerCount = 0, 'unrelated selected viewer HTML is never used as position-specific help');
      Check(LA.SyncHintCount = 0, 'no speculative synchronous hint fallback');
    finally
      LResult.Free;
    end;

    LA.HintText := '<p>Actual <b>position-specific</b> HTML</p>';
    LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 1000);
    try
      Check(LResult.GetValue<Boolean>('success'), 'actual HTML remains available');
      Check(LResult.GetValue<Boolean>('found'), 'actual HTML is a help result');
      Check(LResult.GetValue<string>('content') = LA.HintText, 'actual HTML remains unchanged');
    finally
      LResult.Free;
    end;

    LA.HintText := '';
    LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 1000);
    try
      Check(not LResult.GetValue<Boolean>('found'), 'empty successful response does not claim help');
    finally
      LResult.Free;
    end;
    TestAdmissionLimit(LA, LServices);
    Check(LServices.ContextSetCount = LServices.ContextResetCount, 'all query contexts restored');

    LA.Mode := pmDeferred;
    LA.HintText := 'Delayed hover';
    LA.BeforeAsyncCallback :=
      procedure
      begin
        Check(GetCurrentThreadId = MainThreadID, 'query lifetime observer runs on the IDE thread');
        Check(LServices.ContextSetCount = LServices.ContextResetCount, 'query context is cleared before the callback/wait finishes');
        Check(LEditor.RefCount = 1, 'pending hover does not retain its editor');
        Check(LView.RefCount = 1, 'pending hover does not retain its view');
        Check(LServices.RefCount = 1, 'pending hover does not retain query services');
        Check(LA.RefCount = 3, 'pending hover retains only the required cancellation/provider references');
      end;
    LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 1000);
    try
      Check(LResult.GetValue<Boolean>('success'), 'hover still completes after early query-context release');
      Check(LResult.GetValue<string>('content') = LA.HintText, 'delayed hover returns its original result');
      LA.JoinWorker;
    finally
      LResult.Free;
      LA.BeforeAsyncCallback := nil;
    end;
    TestShutdown(LA, LServices);
  finally
    // Complete all retained synthetic pointers while the production unit is alive.
    LA.DeliverStoredDefinitions;
    LA.DeliverStoredHints;
    LB.DeliverStoredDefinitions;
    LB.DeliverStoredHints;
    TestSourceEditor := nil;
    LServices.Provider := nil;
    BorlandIDEServices := nil;
    LHoldLegacy := nil;
    LHoldB := nil;
    LHoldA := nil;
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS: ', CheckCount, ' Code Insight callback and hover checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
