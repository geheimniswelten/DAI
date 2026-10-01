program TestLog;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.Log,
  h5u.DAI.Settings;

var
  CheckCount: Integer;
  ForeignCallCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function StartWorker(const AAction: TProc): TThread;
begin
  Result := TThread.CreateAnonymousThread(AAction);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

procedure JoinWithoutDispatch(const AWorker: TThread);
begin
  // TThread.WaitFor pumps CheckSynchronize on the main thread. This OS wait does not.
  Check(WaitForSingleObject(AWorker.Handle, 5000) = WAIT_OBJECT_0, 'worker terminates without dispatching IDE callbacks');
  Check(not Assigned(AWorker.FatalException), 'worker has no exception');
end;

procedure NormalChecks(const ASink: TLogMessageSink);
var
  LPrevious: Integer;
  LReplacement: TLogMessageSink;
  LReplacementLifetime: IInterface;
  LWorker: TThread;
begin
  TDAISettings.Instance.LogAccessPoints := False;
  TDAILog.Access('suppressed');
  Check(ASink.Messages.Count = 0, 'disabled access logging is silent');
  TDAILog.Error('main error');
  Check(ASink.Messages.Count = 1, 'error logging ignores access-log setting');
  Check(ASink.Messages[0] = '[DAI] Fehler: main error', 'main error prefix is preserved');
  Check(ASink.LastThreadId = MainThreadID, 'main logging executes on the owning thread');
  TDAISettings.Instance.LogAccessPoints := True;
  TDAILog.Access('main access');
  Check(ASink.Messages[1] = '[DAI] main access', 'access prefix is preserved');
  LPrevious := ASink.Messages.Count;
  LWorker := StartWorker(
    procedure
    begin
      TDAILog.Access('worker access Grüße 日本語');
      TDAILog.Error('worker error');
    end);
  try
    JoinWithoutDispatch(LWorker);
    Check(ASink.Messages.Count = LPrevious, 'worker logging cannot call IDE directly');
    Check(CheckSynchronize(0), 'normal worker messages have an owned queued callback');
    Check(ASink.Messages.Count = LPrevious + 2, 'queued messages reach the IDE sink');
    Check(ASink.Messages[LPrevious] = '[DAI] worker access Grüße 日本語', 'Unicode worker text and ordering preserved');
    Check(ASink.Messages[LPrevious + 1] = '[DAI] Fehler: worker error', 'queued error prefix preserved');
    Check(ASink.LastThreadId = MainThreadID, 'worker messages dispatch on the owning thread');
    Check(not CheckSynchronize(0), 'normal dispatch leaves no owned callback');
  finally
    LWorker.Free;
  end;

  LPrevious := ASink.Messages.Count;
  LReplacement := TLogMessageSink.Create;
  LReplacementLifetime := LReplacement;
  LWorker := StartWorker(procedure begin TDAILog.Error('current service'); end);
  try
    JoinWithoutDispatch(LWorker);
    BorlandIDEServices := LReplacementLifetime;
    Check(CheckSynchronize(0), 'service replacement message dispatches');
    Check(ASink.Messages.Count = LPrevious, 'queued message retains no old OTA service');
    Check(LReplacement.Messages.Count = 1, 'message resolves the current service at dispatch');
    LReplacement.RaiseOnMessage := True;
    TDAILog.Error('caught service error');
    Check(LReplacement.Messages.Count = 2, 'message-service exception is contained');
  finally
    BorlandIDEServices := ASink;
    LWorker.Free;
    LReplacementLifetime := nil;
  end;
end;

procedure ShutdownChecks(const ASink: TLogMessageSink);
var
  LForeignBefore: Integer;
  LPrevious: Integer;
  LReentrant: Boolean;
  LWorker: TThread;
begin
  LPrevious := ASink.Messages.Count;
  LReentrant := FindCmdLineSwitch('reentrant-shutdown');
  if LReentrant then
    TThread.ForceQueue(nil,
      procedure
      begin
        Inc(ForeignCallCount);
        TDAILog.Shutdown;
      end);
  LWorker := StartWorker(
    procedure
    begin
      for var LIndex := 1 to 128 do
        TDAILog.Error('discard at unload ' + IntToStr(LIndex));
    end);
  try
    JoinWithoutDispatch(LWorker);
    Check(ASink.Messages.Count = LPrevious, 'pending shutdown messages did not access IDE');
    if LReentrant then
    begin
      Check(CheckSynchronize(0), 'queued shutdown executes within an already extracted RTL batch');
      Check(ForeignCallCount = 1, 'foreign callback performs the reentrant shutdown');
      Check(not CheckSynchronize(0), 'late own callback from extracted batch leaves no future event');
    end
    else
    begin
      TDAILog.Shutdown;
      Check(not CheckSynchronize(0), 'shutdown removes own callback, not merely suppresses its IDE call');
    end;
    Check(ASink.Messages.Count = LPrevious, 'shutdown discards all pending log text');
  finally
    LWorker.Free;
  end;

  LForeignBefore := ForeignCallCount;
  TThread.ForceQueue(nil, procedure begin Inc(ForeignCallCount); end);
  TDAILog.Shutdown;
  Check(CheckSynchronize(0), 'unrelated nil-thread queued event remains scheduled');
  Check(ForeignCallCount = LForeignBefore + 1, 'unrelated queued event executes exactly once');
  Check(not CheckSynchronize(0), 'no owned log callback remains after foreign event');
  TDAILog.Error('late main error');
  TDAILog.Access('late main access');
  Check(ASink.Messages.Count = LPrevious, 'shutdown disables further main-thread IDE logging');

  LWorker := StartWorker(
    procedure
    begin
      for var LIndex := 1 to 128 do
      begin
        TDAILog.Error('late worker error');
        TDAILog.Access('late worker access');
        TDAILog.Shutdown;
      end;
    end);
  try
    JoinWithoutDispatch(LWorker);
    Check(not CheckSynchronize(0), 'retiring workers cannot enqueue log callbacks after shutdown');
    Check(ASink.Messages.Count = LPrevious, 'late workers never reach IDE message service');
  finally
    LWorker.Free;
  end;
end;

var
  LSink: TLogMessageSink;
  LSinkLifetime: IInterface;
begin
  try
    LSink := TLogMessageSink.Create;
    LSinkLifetime := LSink;
    BorlandIDEServices := LSinkLifetime;
    NormalChecks(LSink);
    ShutdownChecks(LSink);
    TDAILog.Shutdown;
    BorlandIDEServices := nil;
    LSinkLifetime := nil;
    Writeln(Format('PASS: %d log queue checks', [CheckCount]));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
