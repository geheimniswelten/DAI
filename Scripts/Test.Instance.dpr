program TestInstance;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.MCP.Instance;

type
  TLeaseWorker = class(TThread)
  private
    FLease: TDAIMCPInstanceLease;
    FRelease: Boolean;
    FSuccess: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ALease: TDAIMCPInstanceLease; const ARelease: Boolean = False);
    property Success: Boolean read FSuccess;
  end;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function TestName: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := 'Local\DAI.tests.' + GUIDToString(LGuid);
end;

procedure ValidateTestName(const AName: string);
begin
  if not AName.StartsWith('Local\DAI.tests.') then
    raise EArgumentException.Create('Only isolated Local GUID names are permitted in tests.');
end;

constructor TLeaseWorker.Create(const ALease: TDAIMCPInstanceLease; const ARelease: Boolean);
begin
  inherited Create(True);
  FLease := ALease;
  FRelease := ARelease;
end;

procedure TLeaseWorker.Execute;
var
  I: Integer;
begin
  if FRelease then
  begin
    FLease.Release;
    FSuccess := True;
    Exit;
  end;
  FSuccess := True;
  for I := 1 to 1000 do
    if not FLease.TryAcquire then
    begin
      FSuccess := False;
      Exit;
    end;
end;

procedure WaitForWorker(const AWorker: TLeaseWorker);
begin
  if WaitForSingleObject(AWorker.Handle, 5000) <> WAIT_OBJECT_0 then
  begin
    // Exit this isolated process directly: TThread.Destroy would otherwise wait on a deadlock.
    Writeln('FAIL: worker exceeded five-second timeout');
    Halt(1);
  end;
  Check(True, 'worker finishes within timeout');
  AWorker.WaitFor;
end;

procedure TestLocalAndThreads;
var
  LName: string;
  LOwner, LOther: TDAIMCPInstanceLease;
  LWorkers: array[0..7] of TLeaseWorker;
  LReleaseWorker: TLeaseWorker;
  I: Integer;
begin
  LName := TestName;
  LOwner := TDAIMCPInstanceLease.Create(LName);
  LOther := TDAIMCPInstanceLease.Create(LName);
  FillChar(LWorkers, SizeOf(LWorkers), 0);
  try
    Check(LOwner.TryAcquire, 'first instance owns existence lease');
    Check(LOwner.TryAcquire, 'repeated acquire is idempotent');
    Check(not LOther.TryAcquire, 'same name rejects another instance regardless of HTTP port');
    Check(Pos('anderen Delphi-IDE', LOther.LastError) > 0, 'contention error explains IDE handoff');
    for I := Low(LWorkers) to High(LWorkers) do
    begin
      LWorkers[I] := TLeaseWorker.Create(LOwner);
      LWorkers[I].Start;
    end;
    for I := Low(LWorkers) to High(LWorkers) do
    begin
      WaitForWorker(LWorkers[I]);
      Check(LWorkers[I].Success, 'same object is idempotent across threads');
    end;
    Check(not LOther.TryAcquire, 'parallel calls retain single creator handle');
    LReleaseWorker := TLeaseWorker.Create(LOwner, True);
    try
      LReleaseWorker.Start;
      WaitForWorker(LReleaseWorker);
      Check(LReleaseWorker.Success, 'release works on another thread');
    finally
      LReleaseWorker.Free;
    end;
    LOwner.Release;
    Check(LOther.TryAcquire, 'release hands lease to the next IDE');
    Check(LOther.LastError = '', 'successful handoff clears old error');
    Check(not LOwner.TryAcquire, 'former owner cannot reclaim active lease');
    LOther.Free;
    LOther := nil;
    Check(LOwner.TryAcquire, 'destroying owner releases lease');
  finally
    for I := Low(LWorkers) to High(LWorkers) do
      LWorkers[I].Free;
    LOther.Free;
    LOwner.Free;
  end;
end;

procedure TestCreationError;
var
  LName: string;
  LEvent: THandle;
  LLease: TDAIMCPInstanceLease;
begin
  LName := TestName;
  LEvent := CreateEvent(nil, True, False, PChar(LName));
  if LEvent = 0 then
    RaiseLastOSError;
  try
    LLease := TDAIMCPInstanceLease.Create(LName);
    try
      Check(not LLease.TryAcquire, 'other kernel object type produces creation failure');
      Check(Pos('Windows-Fehler', LLease.LastError) > 0, 'creation failure distinguished from active IDE');
      LLease.Release;
    finally
      LLease.Free;
    end;
  finally
    CloseHandle(LEvent);
  end;
end;

function StartChild(const AExecutable, AMode, AName, AReadyEvent: string): TProcessInformation;
var
  LStartup: TStartupInfo;
  LCommand: string;
begin
  ValidateTestName(AName);
  LCommand := '"' + AExecutable + '" ' + AMode + ' "' + AName + '"';
  if AReadyEvent <> '' then
    LCommand := LCommand + ' "' + AReadyEvent + '"';
  UniqueString(LCommand);
  FillChar(LStartup, SizeOf(LStartup), 0);
  LStartup.cb := SizeOf(LStartup);
  FillChar(Result, SizeOf(Result), 0);
  if not CreateProcess(PChar(AExecutable), PChar(LCommand), nil, nil, False, CREATE_NO_WINDOW, nil, nil, LStartup, Result) then
    RaiseLastOSError;
end;

procedure CloseChild(var AProcess: TProcessInformation);
begin
  if AProcess.hProcess <> 0 then
  begin
    if WaitForSingleObject(AProcess.hProcess, 0) <> WAIT_OBJECT_0 then
    begin
      TerminateProcess(AProcess.hProcess, 99);
      WaitForSingleObject(AProcess.hProcess, 5000);
    end;
    CloseHandle(AProcess.hThread);
    CloseHandle(AProcess.hProcess);
    AProcess.hProcess := 0;
  end;
end;

procedure TestProcessProbe(const AExecutable: string);
var
  LName: string;
  LOwner: TDAIMCPInstanceLease;
  LProcess: TProcessInformation;
  LExitCode: DWORD;
begin
  LName := TestName;
  LOwner := TDAIMCPInstanceLease.Create(LName);
  try
    Check(LOwner.TryAcquire, 'parent acquires process test lease');
    LProcess := StartChild(AExecutable, '--probe', LName, '');
    try
      Check(WaitForSingleObject(LProcess.hProcess, 5000) = WAIT_OBJECT_0, 'child probe has bounded completion');
      if not GetExitCodeProcess(LProcess.hProcess, LExitCode) then
        RaiseLastOSError;
      Check(LExitCode = 10, 'another process cannot acquire parent lease');
    finally
      CloseChild(LProcess);
    end;
    LOwner.Release;
    LProcess := StartChild(AExecutable, '--probe', LName, '');
    try
      Check(WaitForSingleObject(LProcess.hProcess, 5000) = WAIT_OBJECT_0, 'handoff child has bounded completion');
      if not GetExitCodeProcess(LProcess.hProcess, LExitCode) then
        RaiseLastOSError;
      Check(LExitCode = 0, 'another process acquires after parent release');
    finally
      CloseChild(LProcess);
    end;
  finally
    LOwner.Free;
  end;
end;

procedure TestCrashRelease(const AExecutable: string);
var
  LName, LReadyName: string;
  LReady: THandle;
  LProcess: TProcessInformation;
  LLease: TDAIMCPInstanceLease;
begin
  LName := TestName;
  LReadyName := TestName;
  LReady := CreateEvent(nil, True, False, PChar(LReadyName));
  if LReady = 0 then
    RaiseLastOSError;
  try
    LProcess := StartChild(AExecutable, '--hold', LName, LReadyName);
    try
      Check(WaitForSingleObject(LReady, 5000) = WAIT_OBJECT_0, 'child signals ownership within timeout');
      LLease := TDAIMCPInstanceLease.Create(LName);
      try
        Check(not LLease.TryAcquire, 'live child owns lease');
        Check(TerminateProcess(LProcess.hProcess, 99), 'terminate isolated child without Delphi cleanup');
        Check(WaitForSingleObject(LProcess.hProcess, 5000) = WAIT_OBJECT_0, 'terminated child exits within timeout');
        Check(LLease.TryAcquire, 'kernel releases existence lease after process crash');
      finally
        LLease.Free;
      end;
    finally
      CloseChild(LProcess);
    end;
  finally
    CloseHandle(LReady);
  end;
end;

procedure RunChild;
var
  LLease: TDAIMCPInstanceLease;
  LReady: THandle;
begin
  ValidateTestName(ParamStr(2));
  LLease := TDAIMCPInstanceLease.Create(ParamStr(2));
  try
    if not LLease.TryAcquire then
      Halt(10);
    if ParamStr(1) = '--probe' then
      Exit;
    ValidateTestName(ParamStr(3));
    LReady := OpenEvent(EVENT_MODIFY_STATE, False, PChar(ParamStr(3)));
    if LReady = 0 then
      RaiseLastOSError;
    try
      if not SetEvent(LReady) then
        RaiseLastOSError;
    finally
      CloseHandle(LReady);
    end;
    // A hard timeout also bounds the child if the parent unexpectedly exits.
    Sleep(10000);
  finally
    LLease.Free;
  end;
end;

begin
  try
    if (ParamStr(1) = '--probe') or (ParamStr(1) = '--hold') then
    begin
      RunChild;
      Halt(0);
    end;
    TestLocalAndThreads;
    TestCreationError;
    TestProcessProbe(ParamStr(0));
    TestCrashRelease(ParamStr(0));
    if (ParamStr(1) = '--peer') and (ParamCount = 2) then
    begin
      TestProcessProbe(ParamStr(2));
      TestCrashRelease(ParamStr(2));
    end;
    Writeln('PASS: ', CheckCount, ' native instance checks; 8 workers, 8000 calls, same/cross-architecture process handoff and crash release.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
