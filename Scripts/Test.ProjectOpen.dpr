program TestProjectOpen;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.JSON, System.SysUtils, System.SyncObjs, System.UITypes,
  Vcl.Forms, Vcl.ExtCtrls, Winapi.Windows,
  h5u.DAI.OTA.ProjectOpen, h5u.DAI.OTA.Projects, h5u.DAI.Types;
type
  TDialogProbe = class
    Timer: TTimer;
    Reply: Integer;
    Seen: Boolean;
    ShutDown: Boolean;
    procedure Tick(Sender: TObject);
  end;
var
  Checks: Integer;
  Context: TDAIRequestContext;
  Id: string;
  Probe: TDialogProbe;
procedure Check(const AValue: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not AValue then raise Exception.Create('FAIL: ' + AMessage);
end;
procedure TDialogProbe.Tick(Sender: TObject);
var I: Integer;
begin
  for I := 0 to Screen.CustomFormCount - 1 do
    if (Screen.CustomForms[I].ClassName = 'TMessageForm') and Screen.CustomForms[I].Visible then
    begin
      Seen := True;
      SetWindowPos(Screen.CustomForms[I].Handle, 0, -20000, -20000, 0, 0, SWP_NOSIZE or SWP_NOACTIVATE or SWP_NOZORDER);
      if ShutDown then TDAIProjectOpenService.Shutdown;
      Screen.CustomForms[I].ModalResult := Reply;
      Timer.Enabled := False;
      Exit;
    end;
end;
function AwaitDone: TJSONObject;
var LStarted: UInt64;
begin
  LStarted := GetTickCount64;
  repeat
    CheckSynchronize(1);
    Result := TDAIProjectOpenService.Status(Id, Context);
    if Result.GetValue<Boolean>('finished') then Exit;
    Result.Free;
    if GetTickCount64 - LStarted > 5000 then raise Exception.Create('Project job did not complete');
    Sleep(1);
  until False;
end;
procedure OpenOne;
var LValue: TJSONObject;
begin
  LValue := TDAIProjectOpenService.Open('C:\SyntheticDAI\Project.dproj', True, Context);
  try
    Id := LValue.GetValue<string>('request_id');
    Check((Id <> '') and (LValue.GetValue<string>('status') = 'queued'), 'start returns an immediate queued job');
    Check(LValue.GetValue('opened') is TJSONNull, 'queued does not claim the project is already open');
  finally LValue.Free; end;
end;
procedure PollWithoutUI;
var LWorker: TThread; LDone: TEvent; LError: string;
begin
  LDone := TEvent.Create(nil, True, False, '');
  LError := '';
  LWorker := TThread.CreateAnonymousThread(
    procedure
    var LValue: TJSONObject; I: Integer;
    begin
      try
        for I := 1 to 50 do
        begin
          LValue := TDAIProjectOpenService.Status(Id, Context);
          try
            if LValue.GetValue<Boolean>('finished') then raise Exception.Create('status falsely completed without a UI pump');
          finally LValue.Free; end;
        end;
      except on E: Exception do LError := E.Message; end;
      LDone.SetEvent;
    end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    Check(LDone.WaitFor(1000) = wrSignaled, 'status stays reachable while the IDE thread does not pump messages');
    Check(WaitForSingleObject(LWorker.Handle, 1000) = WAIT_OBJECT_0, 'polling worker exits without pumping the IDE queue');
    Check(LError = '', 'pending status remains accurate');
  finally LWorker.Free; LDone.Free; end;
end;
procedure DialogCase(const AReply: Integer; const AExpected: string);
var LValue: TJSONObject; LBefore: Integer;
begin
  Probe.Reply := AReply;
  Probe.Seen := False;
  Probe.Timer.Enabled := True;
  TDAIProjectService.ShowSaveDialog := True;
  LBefore := TDAIProjectService.Opens;
  OpenOne;
  LValue := AwaitDone;
  try
    Check(Probe.Seen, 'a real VCL save-dialog fixture was handled');
    Check(LValue.GetValue<string>('status') = AExpected, 'native choice becomes the terminal job status');
    Check(not LValue.GetValue<Boolean>('sdk_pending'), 'a finished job is not pending');
    if (AReply = mrCancel) or Probe.ShutDown then
      Check(TDAIProjectService.Opens = LBefore, 'Cancel prevents opening the target project')
    else
      Check(TDAIProjectService.Opens = LBefore + 1, 'Save and Discard both allow the target to open');
  finally LValue.Free; Probe.Timer.Enabled := False; end;
end;
var LValue: TJSONObject; LOther: TDAIRequestContext; LDenied: Boolean;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    Context.ThreadId := 'project-open-test';
    Context.TransportSessionId := 'test-transport';
    Probe := TDialogProbe.Create;
    Probe.Timer := TTimer.Create(nil);
    Probe.Timer.Enabled := False;
    Probe.Timer.Interval := 50;
    Probe.Timer.OnTimer := Probe.Tick;
    try
      OpenOne;
      PollWithoutUI;
      LValue := TDAIProjectOpenService.Open('C:\SyntheticDAI\Project.dproj', True, Context);
      try Check(LValue.GetValue<string>('request_id') = Id, 'repeating a pending request reuses its job'); finally LValue.Free; end;
      LOther := Context;
      LOther.ThreadId := 'other-chat';
      LDenied := False;
      try TDAIProjectOpenService.Status(Id, LOther).Free; except on E: EArgumentException do LDenied := True; end;
      Check(LDenied, 'another chat cannot read this job');
      LDenied := False;
      try TDAIProjectOpenService.Open('C:\SyntheticDAI\Other.dproj', False, Context).Free;
      except on E: EInvalidOperation do LDenied := True; end;
      Check(LDenied, 'overlapping project changes are rejected');
      LValue := AwaitDone;
      try Check(LValue.GetValue<Boolean>('opened'), 'completed job retains the original OTA result'); finally LValue.Free; end;
      DialogCase(mrYes, 'completed');
      DialogCase(mrNo, 'completed');
      DialogCase(mrCancel, 'cancelled');
      TDAIProjectService.ShowSaveDialog := False;
      TDAIProjectService.Fail := True;
      OpenOne;
      LValue := AwaitDone;
      try
        Check(LValue.GetValue<string>('status') = 'error', 'load exceptions are retained in status');
        Check(Pos('Synthetic project load failure', LValue.GetValue<string>('error')) > 0, 'load error text stays available');
      finally LValue.Free; end;
      TDAIProjectService.Fail := False;
      Probe.ShutDown := True;
      DialogCase(mrNo, 'cancelled');
      LDenied := False;
      try TDAIProjectOpenService.Open('C:\SyntheticDAI\Other.dproj', False, Context).Free;
      except on E: EInvalidOperation do LDenied := True; end;
      Check(LDenied, 'shutdown does not accept later jobs');
      Writeln('PASS: ', Checks, ' asynchronous project-open checks');
    finally Probe.Timer.Free; Probe.Free; end;
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
