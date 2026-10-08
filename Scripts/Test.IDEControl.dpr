program TestIDEControl;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.SysUtils,
  Vcl.Forms,
  Winapi.Messages,
  Winapi.Windows,
  h5u.DAI.IDE.Control,
  h5u.DAI.Lifecycle.Policy in 'IDEControlTests\h5u.DAI.Lifecycle.Policy.pas',
  h5u.DAI.OTA.Helpers in 'IDEControlTests\h5u.DAI.OTA.Helpers.pas';

type
  TControlFixture = class(TForm)
  private
    procedure QueryClose(Sender: TObject; var CanClose: Boolean);
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    AllowClose, ResponseWritten, SawResponseBeforeClose: Boolean;
    CloseMessageCount, CloseQueryCount: Integer;
    constructor Create(AOwner: TComponent); override;
    procedure DropHandle;
  end;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

constructor TControlFixture.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Name := 'DAIIDEControlFixture';
  Caption := 'DAI – isolierter IDE-Control-Test';
  Position := poScreenCenter;
  Width := 480;
  Height := 160;
  OnCloseQuery := QueryClose;
end;

procedure TControlFixture.QueryClose(Sender: TObject; var CanClose: Boolean);
begin
  Inc(CloseQueryCount);
  CanClose := AllowClose;
end;

procedure TControlFixture.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_CLOSE then
  begin
    Inc(CloseMessageCount);
    SawResponseBeforeClose := ResponseWritten;
  end;
  inherited;
end;

procedure TControlFixture.DropHandle;
begin
  if HandleAllocated then
    DestroyHandle;
end;

procedure RunWorker(const AAction: TThreadProcedure);
var
  LWorker: TThread;
begin
  LWorker := TThread.CreateAnonymousThread(AAction);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    LWorker.WaitFor;
    if Assigned(LWorker.FatalException) then
      raise Exception.Create(Exception(LWorker.FatalException).Message);
  finally
    LWorker.Free;
  end;
end;

function ControlOnWorker(const AAction: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  RunWorker(procedure begin LResult := TDAIIDEControl.Control(AAction); end);
  Result := LResult;
end;

function CloseQueued(const AWindow: HWND): Boolean;
var
  LMessage: TMsg;
begin
  Result := PeekMessage(LMessage, AWindow, WM_CLOSE, WM_CLOSE, PM_NOREMOVE);
end;

procedure DispatchClose(const AWindow: HWND);
var
  LMessage: TMsg;
begin
  while PeekMessage(LMessage, AWindow, WM_CLOSE, WM_CLOSE, PM_REMOVE) do
    DispatchMessage(LMessage);
end;

procedure CheckState(const AResult: TJSONObject; const AWindow: HWND);
begin
  Check(AResult.GetValue<Boolean>('minimized') = IsIconic(AWindow), 'Result reports actual minimized state');
  Check(AResult.GetValue<Boolean>('visible') = IsWindowVisible(AWindow), 'Result reports actual window visibility');
  Check(AResult.GetValue<Boolean>('foreground') = (GetForegroundWindow = AWindow), 'Result reports actual OS foreground state');
end;

procedure CheckUnavailable;
var
  LDenied: Boolean;
  LResult: TJSONObject;
begin
  Check(not Assigned(Application.MainForm), 'Test starts without an application main form');
  Check(not TDAIIDEControl.HasDeferredClose, 'New thread has no deferred close');
  Check(not TDAIIDEControl.CompleteDeferredClose, 'Completing an empty request is harmless');
  LDenied := False;
  try
    LResult := ControlOnWorker('restore');
    LResult.Free;
  except
    on E: EInvalidOperation do LDenied := True;
    on E: Exception do
      LDenied := Pos('Hauptfenster', E.Message) > 0;
  end;
  Check(LDenied, 'Control rejects missing main form');
  Check(not Assigned(Application.MainForm), 'Control never creates a main form');
end;

procedure CheckActions(const AForm: TControlFixture);
const
  CInvalid: array[0..3] of string = ('', 'terminate', 'force_close', 'other-window');
var
  LAction: string;
  LResult: TJSONObject;
  LDenied: Boolean;
  LBefore, LAfter: TRect;
  LWindow: HWND;
  LProcessId: Cardinal;
  LThreadId: Cardinal;
begin
  AForm.DropHandle;
  LDenied := False;
  try
    LResult := TDAIIDEControl.Control('restore');
    LResult.Free;
  except on E: EInvalidOperation do LDenied := True; end;
  Check(LDenied, 'Main form without allocated HWND is unavailable');
  Check(not AForm.HandleAllocated, 'Control does not allocate a missing HWND');
  AForm.Show;
  LWindow := AForm.Handle;
  LThreadId := GetWindowThreadProcessId(LWindow, LProcessId);
  Check(Application.MainForm = AForm, 'Fixture is the actual application main form');
  Check((LThreadId = MainThreadID) and (LProcessId = GetCurrentProcessId), 'Fixture HWND belongs to this process and main thread');
  for LAction in CInvalid do
  begin
    GetWindowRect(LWindow, LBefore);
    LDenied := False;
    try
      LResult := TDAIIDEControl.Control(LAction);
      LResult.Free;
    except on E: EArgumentException do LDenied := True; end;
    GetWindowRect(LWindow, LAfter);
    Check(LDenied, 'Invalid action is rejected');
    Check(EqualRect(LBefore, LAfter) and not IsIconic(LWindow), 'Invalid action does not mutate the main window');
    Check(not CloseQueued(LWindow) and not TDAIIDEControl.HasDeferredClose, 'Invalid action never queues or prepares close');
  end;
  LResult := ControlOnWorker('minimize');
  try
    Check(LResult.GetValue<Boolean>('accepted') and IsIconic(LWindow), 'Worker action minimizes actual main HWND');
    CheckState(LResult, LWindow);
    Check(not LResult.GetValue<Boolean>('close_pending'), 'Minimize is not a pending close');
  finally LResult.Free; end;
  LResult := ControlOnWorker(' ReStOrE ');
  try
    Check(LResult.GetValue<string>('action') = 'restore', 'Action normalization is explicit in result');
    Check(LResult.GetValue<Boolean>('accepted') and not IsIconic(LWindow), 'Worker action restores actual main HWND');
    CheckState(LResult, LWindow);
  finally LResult.Free; end;
  GetWindowRect(LWindow, LBefore);
  LResult := ControlOnWorker('background');
  try
    GetWindowRect(LWindow, LAfter);
    Check(LResult.GetValue<Boolean>('accepted'), 'Background native SetWindowPos succeeds for own main HWND');
    Check(EqualRect(LBefore, LAfter), 'Background preserves main window position and size');
    CheckState(LResult, LWindow);
  finally LResult.Free; end;
  LResult := ControlOnWorker('minimize');
  LResult.Free;
  LResult := ControlOnWorker('foreground');
  try
    Check(not IsIconic(LWindow), 'Foreground request restores a minimized main window');
    Check(LResult.GetValue<Boolean>('accepted') = (GetForegroundWindow = LWindow), 'Foreground acceptance reports OS decision without assuming focus');
    CheckState(LResult, LWindow);
  finally LResult.Free; end;
end;

procedure CheckThreadIsolation(const AForm: TControlFixture);
var
  LReady, LContinue: TEvent;
  LWorker: TThread;
  LReadyDeadline: UInt64;
  LWorkerHadPending, LWorkerStillPending, LOtherHadPending, LOtherPosted: Boolean;
  LWorkerPosted: Boolean;
begin
  LReady := TEvent.Create(nil, True, False, '');
  LContinue := TEvent.Create(nil, True, False, '');
  LWorkerHadPending := False;
  LWorkerStillPending := False;
  LOtherHadPending := False;
  LOtherPosted := False;
  LWorkerPosted := False;
  LWorker := TThread.CreateAnonymousThread(
    procedure
    var LResult: TJSONObject;
    begin
      LResult := TDAIIDEControl.Control('close');
      LResult.Free;
      LWorkerHadPending := TDAIIDEControl.HasDeferredClose;
      LReady.SetEvent;
      if LContinue.WaitFor(5000) <> wrSignaled then
        raise Exception.Create('Thread isolation fixture timed out.');
      LWorkerStillPending := TDAIIDEControl.HasDeferredClose;
      TDAIIDEControl.ResetDeferredClose;
      LWorkerPosted := TDAIIDEControl.CompleteDeferredClose;
    end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    LReadyDeadline := GetTickCount64 + 3000;
    while (LReady.WaitFor(0) <> wrSignaled) and (GetTickCount64 < LReadyDeadline) do
      CheckSynchronize(1);
    Check(LReady.WaitFor(0) = wrSignaled, 'Worker prepared close after main-thread lookup');
    Check(LWorkerHadPending, 'Deferred close belongs to original worker');
    Check(not TDAIIDEControl.HasDeferredClose, 'IDE main thread does not inherit worker close state');
    TDAIIDEControl.ResetDeferredClose;
    RunWorker(procedure
      begin
        LOtherHadPending := TDAIIDEControl.HasDeferredClose;
        LOtherPosted := TDAIIDEControl.CompleteDeferredClose;
        TDAIIDEControl.ResetDeferredClose;
      end);
    Check(not LOtherHadPending and not LOtherPosted, 'Other worker cannot see or complete pending close');
    Check(not CloseQueued(AForm.Handle), 'Prepared close has not posted WM_CLOSE');
    LContinue.SetEvent;
    LWorker.WaitFor;
    Check(not Assigned(LWorker.FatalException), 'Close preparation worker finishes normally');
    Check(LWorkerStillPending, 'Main/other thread resets do not erase original worker pending state');
    Check(not LWorkerPosted and not CloseQueued(AForm.Handle), 'Reset after response failure prevents any close message');
    Check(AForm.CloseMessageCount = 0, 'Preparing/cancelling never invokes native close handling');
  finally
    LContinue.SetEvent;
    LWorker.WaitFor;
    LWorker.Free;
    LContinue.Free;
    LReady.Free;
  end;
end;

procedure CheckStaleHandle(const AForm: TControlFixture);
var
  LPosted, LHadPending, LStillPending: Boolean;
begin
  LPosted := True;
  LHadPending := False;
  LStillPending := True;
  RunWorker(procedure
    var LResult: TJSONObject;
    begin
      LResult := TDAIIDEControl.Control('close');
      LResult.Free;
      LHadPending := TDAIIDEControl.HasDeferredClose;
      TDAIOTA.RunOnMainThread(procedure begin AForm.DropHandle; end);
      LPosted := TDAIIDEControl.CompleteDeferredClose;
      LStillPending := TDAIIDEControl.HasDeferredClose;
    end);
  Check(LHadPending, 'Stale test starts with a valid prepared main HWND');
  Check(not LPosted and not LStillPending, 'Destroyed main HWND is not posted and pending state is consumed');
  Check(not AForm.HandleAllocated, 'Stale completion does not recreate main HWND');
  Check(AForm.CloseMessageCount = 0, 'Stale completion never invokes close handling');
  AForm.Visible := False;
  AForm.Show;
  Check(IsWindow(AForm.Handle), 'Only fixture explicitly creates its replacement window');
  Check(not CloseQueued(AForm.Handle), 'Replacement main HWND receives no stale close');
end;

procedure CheckDeferredClose(const AForm: TControlFixture; const AAllowClose: Boolean);
var
  LBeforeQueryCount, LBeforeCloseCount: Integer;
  LPosted, LStillPending, LSecondPosted, LTerminatedBeforePost: Boolean;
  LResult: TJSONObject;
begin
  AForm.AllowClose := AAllowClose;
  AForm.ResponseWritten := False;
  AForm.SawResponseBeforeClose := False;
  LBeforeQueryCount := AForm.CloseQueryCount;
  LBeforeCloseCount := AForm.CloseMessageCount;
  LResult := nil;
  LPosted := False;
  LStillPending := True;
  LSecondPosted := True;
  LTerminatedBeforePost := True;
  RunWorker(procedure
    begin
      LResult := TDAIIDEControl.Control('close');
      LTerminatedBeforePost := Application.Terminated;
      // This synthetic completed-response marker checks native ordering only.
      // The real HTTP WriteContent-before-Complete boundary is tested by Test.Protocol.
      AForm.ResponseWritten := True;
      LPosted := TDAIIDEControl.CompleteDeferredClose;
      LStillPending := TDAIIDEControl.HasDeferredClose;
      LSecondPosted := TDAIIDEControl.CompleteDeferredClose;
    end);
  try
    Check(LResult.GetValue<Boolean>('accepted'), 'Close preparation is accepted');
    Check(LResult.GetValue<Boolean>('close_pending'), 'Close response explicitly reports deferred state');
    Check(LResult.GetValue<Boolean>('save_prompts_possible'), 'Close response preserves possible save prompts/cancellation');
    Check(not LTerminatedBeforePost, 'Control close does not terminate the application');
    Check(LPosted, 'Completing the same worker close posts WM_CLOSE');
    Check(not LStillPending and not LSecondPosted, 'Close completion consumes state exactly once');
    Check(CloseQueued(AForm.Handle), 'WM_CLOSE is queued after completed-response marker');
    Check(AForm.CloseMessageCount = LBeforeCloseCount, 'Posting does not call close handling synchronously');
    DispatchClose(AForm.Handle);
    Check(AForm.CloseMessageCount = LBeforeCloseCount + 1, 'Exactly one native WM_CLOSE reaches fixture');
    Check(AForm.CloseQueryCount = LBeforeQueryCount + 1, 'Normal native CloseQuery is invoked');
    Check(AForm.SawResponseBeforeClose, 'Native close runs after response completion marker');
    if AAllowClose then
    begin
      // VCL Terminate posts WM_QUIT; its application loop observes it afterwards.
      Application.ProcessMessages;
      Check(Application.Terminated, 'Positive CloseQuery follows normal main-form shutdown')
    end
    else
    begin
      Check(not Application.Terminated, 'CloseQuery veto prevents application shutdown');
      Check(IsWindow(AForm.Handle) and AForm.Visible, 'Veto leaves existing main window available');
    end;
  finally
    LResult.Free;
  end;
end;

procedure CheckLifecycleGate(const AForm: TControlFixture);
var
  LDenied, LPosted, LStillPending: Boolean;
  LResult: TJSONObject;
begin
  TDAILifecyclePolicy.Allowed := False;
  LDenied := False;
  try
    LResult := ControlOnWorker('close');
    LResult.Free;
  except
    on E: Exception do
      LDenied := Pos('disabled_in_dai_options', E.Message) > 0;
  end;
  Check(LDenied, 'Lifecycle gate rejects close with an actionable reason');
  Check(not CloseQueued(AForm.Handle) and (AForm.CloseMessageCount = 0), 'Denied close never posts native WM_CLOSE');
  LResult := ControlOnWorker('minimize');
  try
    Check(LResult.GetValue<Boolean>('accepted') and IsIconic(AForm.Handle), 'Lifecycle gate preserves other window controls');
  finally
    LResult.Free;
  end;
  LResult := ControlOnWorker('restore');
  LResult.Free;
  TDAILifecyclePolicy.Allowed := True;
  LPosted := True;
  LStillPending := True;
  RunWorker(procedure
    var LPrepared: TJSONObject;
    begin
      LPrepared := TDAIIDEControl.Control('close');
      LPrepared.Free;
      TDAILifecyclePolicy.Allowed := False;
      LPosted := TDAIIDEControl.CompleteDeferredClose;
      LStillPending := TDAIIDEControl.HasDeferredClose;
    end);
  Check(not LPosted and not LStillPending, 'Disabling after preparation cancels and consumes deferred close');
  Check(not CloseQueued(AForm.Handle) and (AForm.CloseMessageCount = 0), 'Fresh policy is checked before native message posting');
  TDAILifecyclePolicy.Allowed := True;
end;

var
  Fixture: TControlFixture;
begin
  try
    TDAILifecyclePolicy.Allowed := True;
    Application.Initialize;
    Application.ShowMainForm := False;
    CheckUnavailable;
    Fixture := nil;
    Application.CreateForm(TControlFixture, Fixture);
    try
      CheckActions(Fixture);
      CheckThreadIsolation(Fixture);
      CheckStaleHandle(Fixture);
      CheckLifecycleGate(Fixture);
      CheckDeferredClose(Fixture, False);
      CheckDeferredClose(Fixture, True);
      Writeln('PASS: ', CheckCount, ' native IDE control/deferred close checks');
    finally
      Fixture.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
