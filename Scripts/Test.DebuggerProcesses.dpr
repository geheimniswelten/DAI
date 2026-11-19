program Test.DebuggerProcesses;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Debugger;

type
  TMockProcess = class(TInterfacedObject, IOTAProcess)
  public
    Id: LongWord;
    State: TOTAProcessState;
    Executable: string;
    Detached: Boolean;
    function GetCurrentThread: IOTAThread;
    function GetThreadCount: Integer;
    function GetProcessId: LongWord;
    function GetOSProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    function GetExeName: string;
    function GetState: string;
    function GetStatus: string;
    procedure Detach;
    procedure Pause;
    procedure Run(Mode: TOTARunMode);
  end;

  TMockDebugger = class(TInterfacedObject, IOTADebuggerServices)
  public
    Processes: TList<IOTAProcess>;
    Current, PendingProcess: IOTAProcess;
    Calls, Enumerations: Integer;
    LastPid: Integer;
    LastExe, LastArgs, LastHost: string;
    LastPause, LastDetach: Boolean;
    Enumerates, TryConcurrentAttach, ConcurrentAttachRejected: Boolean;
    constructor Create;
    destructor Destroy; override;
    function GetCurrentProcess: IOTAProcess;
    function GetProcessCount: Integer;
    function GetProcess(Index: Integer): IOTAProcess;
    function GetSourceBkptCount: Integer;
    function GetAddressBkptCount: Integer;
    function GetSourceBkpt(Index: Integer): IOTASourceBreakpoint;
    function NewSourceBreakpoint(const FileName: string; LineNumber: Integer; const AProcess: IOTAProcess): IOTABreakpoint;
    procedure RemoveBreakpoint(const Breakpoint: IOTABreakpoint);
    procedure CreateProcess(const ExeName, Args: string; const RemoteHost: string = '');
    procedure AttachProcess(Pid: Integer; PauseAfterAttach: Boolean; DetachOnReset: Boolean; const RemoteHost: string = '');
    procedure EnumerateRunningProcesses(Callback: TEnumerateProcessesCallback; Param: Pointer; const HostName: string = '');
  end;

var
  GChecks: Integer;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
  Inc(GChecks);
end;

procedure ExpectError(const Action: TProc; ErrorClass: ExceptClass; const MessageText: string);
begin
  try
    Action();
  except
    on E: Exception do
    begin
      Check(E.InheritsFrom(ErrorClass), MessageText + ': ' + E.ClassName + ': ' + E.Message);
      Exit;
    end;
  end;
  raise Exception.Create(MessageText + ': no exception');
end;

function TMockProcess.GetCurrentThread: IOTAThread;
begin
  Result := nil;
end;

function TMockProcess.GetThreadCount: Integer;
begin
  Result := 0;
end;

function TMockProcess.GetProcessId: LongWord;
begin
  Result := 71;
end;

function TMockProcess.GetOSProcessId: LongWord;
begin
  Result := Id;
end;

function TMockProcess.GetProcessState: TOTAProcessState;
begin
  Result := State;
end;

function TMockProcess.GetExeName: string;
begin
  Result := Executable;
end;

function TMockProcess.GetState: string;
begin
  Result := '';
end;

function TMockProcess.GetStatus: string;
begin
  Result := '';
end;

procedure TMockProcess.Detach;
begin
  Detached := True;
end;

procedure TMockProcess.Pause;
begin
  raise EInvalidOperation.Create('Unexpected pause');
end;

procedure TMockProcess.Run(Mode: TOTARunMode);
begin
  raise EInvalidOperation.Create('Unexpected run');
end;

constructor TMockDebugger.Create;
begin
  inherited;
  Processes := TList<IOTAProcess>.Create;
end;

destructor TMockDebugger.Destroy;
begin
  Processes.Free;
  inherited;
end;

function TMockDebugger.GetCurrentProcess: IOTAProcess;
begin
  Result := Current;
end;

function TMockDebugger.GetProcessCount: Integer;
begin
  Result := Processes.Count;
end;

function TMockDebugger.GetProcess(Index: Integer): IOTAProcess;
begin
  Result := Processes[Index];
end;

function TMockDebugger.GetSourceBkptCount: Integer;
begin
  Result := 0;
end;

function TMockDebugger.GetAddressBkptCount: Integer;
begin
  Result := 0;
end;

function TMockDebugger.GetSourceBkpt(Index: Integer): IOTASourceBreakpoint;
begin
  raise EInvalidOperation.Create('Unexpected breakpoint lookup');
end;

function TMockDebugger.NewSourceBreakpoint(const FileName: string; LineNumber: Integer; const AProcess: IOTAProcess): IOTABreakpoint;
begin
  raise EInvalidOperation.Create('Unexpected breakpoint creation');
end;

procedure TMockDebugger.RemoveBreakpoint(const Breakpoint: IOTABreakpoint);
begin
  raise EInvalidOperation.Create('Unexpected breakpoint removal');
end;

procedure TMockDebugger.CreateProcess(const ExeName, Args, RemoteHost: string);
begin
  Check(GetCurrentThreadId = MainThreadID, 'CreateProcess runs on the IDE thread');
  Inc(Calls);
  LastExe := ExeName;
  LastArgs := Args;
  LastHost := RemoteHost;
  if Assigned(PendingProcess) then
    Processes.Add(PendingProcess);
  if TryConcurrentAttach then
    try
      TDAIDebuggerService.AttachProcess(42, True, True, '').Free;
    except
      on E: EInvalidOperation do
        ConcurrentAttachRejected := True;
    end;
end;

procedure TMockDebugger.AttachProcess(Pid: Integer; PauseAfterAttach, DetachOnReset: Boolean; const RemoteHost: string);
begin
  Check(GetCurrentThreadId = MainThreadID, 'AttachProcess runs on the IDE thread');
  Inc(Calls);
  LastPid := Pid;
  LastPause := PauseAfterAttach;
  LastDetach := DetachOnReset;
  LastHost := RemoteHost;
  if Assigned(PendingProcess) then
    Current := PendingProcess;
end;

procedure TMockDebugger.EnumerateRunningProcesses(Callback: TEnumerateProcessesCallback; Param: Pointer; const HostName: string);
begin
  Check(GetCurrentThreadId = MainThreadID, 'Enumeration runs on the IDE thread');
  LastHost := HostName;
  Inc(Enumerations);
  if Enumerates then
  begin
    Callback(4000000001, 'Grüße.exe', Param);
    Callback(3030, 'C:\Target\Other.exe', Param);
    Callback(4040, 'NameOnly', Param);
  end;
end;

function Setup: TMockDebugger;
begin
  Result := TMockDebugger.Create;
  BorlandIDEServices := Result;
end;

procedure TestProcessList;
var
  Debugger: TMockDebugger;
  Response: TJSONObject;
  Row: TJSONObject;
  Rows: TJSONArray;
  Worker: TThread;
begin
  Debugger := Setup;
  Response := TDAIDebuggerService.Processes('', 200);
  try
    Check(Response.GetValue<string>('scope') = 'local', 'An empty host requests local enumeration');
    Check(Response.GetValue<Boolean>('action_invoked'), 'A callback-free invocation still reports the call');
    Check(Response.GetValue('enumeration_confirmed') is TJSONNull, 'No callbacks leave enumeration unconfirmed');
  finally
    Response.Free;
  end;

  Debugger.Enumerates := True;
  Response := nil;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      Response := TDAIDebuggerService.Processes('PRODAT-WORK:64447', 2);
    end);
  Worker.FreeOnTerminate := False;
  try
    Worker.Start;
    Worker.WaitFor;
    Check(not Assigned(Worker.FatalException) and Assigned(Response), 'Worker enumeration marshals successfully');
    Check(Debugger.LastHost = 'PRODAT-WORK:64447', 'Remote endpoint is passed unchanged');
    Check(Response.GetValue<string>('scope') = 'remote', 'Remote enumeration identifies its scope');
    Check(Response.GetValue<Boolean>('enumeration_confirmed'), 'Provider callbacks confirm enumeration');
    Check(Response.GetValue<Boolean>('truncated'), 'Extra processes are counted without exceeding the result limit');
    Check(Response.GetValue<Integer>('enumerated_count') = 3, 'All callback records are counted');
    Check(Response.GetValue<Integer>('returned_count') = 2, 'At most the requested records are included');
    Rows := Response.GetValue<TJSONArray>('processes');
    Row := TJSONObject(Rows.Items[0]);
    Check(Row.GetValue<Int64>('process_id') = 4000000001, 'SDK callback process IDs use the full unsigned range');
    Check(Row.GetValue<string>('name') = 'Grüße.exe', 'Callback text preserves Unicode');
  finally
    Worker.Free;
    Response.Free;
  end;
end;

procedure TestLoadRequest;
const
  RemoteExecutable = './Grüße/Prodat';
  RemoteHost = 'PRODAT-WORK:64447';
  Arguments = '/Cfg "Test DB" ';
var
  Debugger: TMockDebugger;
  Observed: TMockProcess;
  Response: TJSONObject;
begin
  Debugger := Setup;
  Debugger.TryConcurrentAttach := True;
  Response := TDAIDebuggerService.LoadProcess(RemoteExecutable, Arguments, RemoteHost);
  try
    Check(Debugger.Calls = 1, 'The native launch call runs once');
    Check(Debugger.ConcurrentAttachRejected, 'A reentrant attach is rejected during the native call');
    Check(Debugger.LastExe = RemoteExecutable, 'The remote path is passed verbatim');
    Check(Debugger.LastArgs = Arguments, 'The argument string is passed verbatim');
    Check(Debugger.LastHost = RemoteHost, 'Launch forwards the remote host');
    Check(Response.GetValue<Boolean>('action_invoked'), 'A completed SDK call is reported separately');
    Check(Response.GetValue<Boolean>('completion_is_asynchronous'), 'The response reports asynchronous completion');
    Check(not Response.GetValue<Boolean>('process_observed'), 'A silent no-op is unconfirmed');
    Check(Response.GetValue('process') is TJSONNull, 'A silent no-op has no process');
  finally
    Response.Free;
  end;

  Debugger.TryConcurrentAttach := False;
  Observed := TMockProcess.Create;
  Observed.Id := 4280;
  Observed.State := psRunning;
  Observed.Executable := './grüße/PRODAT';
  Debugger.PendingProcess := Observed;
  Response := TDAIDebuggerService.LoadProcess(RemoteExecutable, Arguments, RemoteHost);
  try
    Check(not Response.GetValue<Boolean>('process_observed'), 'A differently cased remote path is not an exact observation');
  finally
    Response.Free;
  end;
  Debugger.Processes.Clear;
  Observed.Executable := RemoteExecutable;
  Response := TDAIDebuggerService.LoadProcess(RemoteExecutable, Arguments, RemoteHost);
  try
    Check(Response.GetValue<Boolean>('process_observed'), 'An exact new remote executable is observed in the process list');
    Check(Response.GetValue<TJSONObject>('process').GetValue<Int64>('process_id') = 4280, 'Observation reports the OS process ID');
    Check(Response.GetValue<TJSONObject>('process').GetValue<Int64>('debugger_process_id') = 71, 'Observation reports the internal debugger ID separately');
  finally
    Response.Free;
  end;
end;

procedure TestAttachAndDetach;
var
  Debugger: TMockDebugger;
  Attached, Terminated: TMockProcess;
  Response: TJSONObject;
begin
  Debugger := Setup;
  Terminated := TMockProcess.Create;
  Terminated.State := psTerminated;
  Debugger.Processes.Add(Terminated);
  Debugger.Processes.Add(nil);
  Attached := TMockProcess.Create;
  Attached.Id := MaxInt;
  Attached.State := psStopped;
  Debugger.PendingProcess := Attached;
  Response := TDAIDebuggerService.AttachProcess(MaxInt, False, True, 'PRODAT-WORK');
  try
    Check(Debugger.LastPid = MaxInt, 'Attach accepts the full positive signed SDK PID range');
    Check(not Debugger.LastPause and Debugger.LastDetach, 'Attach forwards both lifecycle flags');
    Check(Debugger.LastHost = 'PRODAT-WORK', 'Attach forwards the remote host');
    Check(Response.GetValue<Boolean>('process_observed'), 'Attach observes the exact OS process ID');
  finally
    Response.Free;
  end;

  Response := TDAIDebuggerService.Control('detach');
  try
    Check(Attached.Detached, 'Detach is available for a stopped debuggee without a stopped thread');
    Check(Response.GetValue<Boolean>('requested'), 'Detach reports the request');
  finally
    Response.Free;
  end;
  Attached.Detached := False;
  Attached.State := psRunning;
  TDAIDebuggerService.Control('detach').Free;
  Check(Attached.Detached, 'Detach is available for a running debuggee');

  Attached.Detached := False;
  Attached.State := psStopping;
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.Control('detach').Free;
    end, EInvalidOperation, 'A stopping debuggee cannot be detached again');
  Check(not Attached.Detached, 'Rejected detach does not call OTA');
end;

procedure TestRejectedRequestsAndCapabilities;
var
  Debugger: TMockDebugger;
  Active: TMockProcess;
  Response: TJSONObject;
  Capabilities: TJSONObject;
begin
  Debugger := Setup;
  Active := TMockProcess.Create;
  Active.State := psRunning;
  Debugger.Processes.Add(Active);
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.LoadProcess('thing.exe', '', '').Free;
    end, EInvalidOperation, 'An active noncurrent process blocks launch');
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.AttachProcess(123, True, True, '').Free;
    end, EInvalidOperation, 'An active noncurrent process blocks attach');
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.AttachProcess(0, True, True, '').Free;
    end, EArgumentOutOfRangeException, 'Invalid process ID is rejected');
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.AttachProcess(Integer(GetCurrentProcessId), True, True, '').Free;
    end, EInvalidOperation, 'Local self-attachment is rejected');
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.LoadProcess('file' + #0 + '.exe', '', '').Free;
    end, EArgumentException, 'Embedded null in executable is rejected');
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.LoadProcess('file.exe', StringOfChar('a', 32768), '').Free;
    end, EArgumentOutOfRangeException, 'Overlong arguments are rejected');
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.Processes(StringOfChar('h', 1025), 200).Free;
    end, EArgumentOutOfRangeException, 'An overlong remote host is rejected');
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.Processes('', 1001).Free;
    end, EArgumentOutOfRangeException, 'An excessive process list limit is rejected');
  Check(Debugger.Calls = 0, 'Validation and active session checks prevent all execution calls');
  Check(Debugger.Enumerations = 0, 'Validation precedes OTA enumeration');

  Response := TDAIDebuggerService.Status;
  try
    Capabilities := Response.GetValue<TJSONObject>('process_capabilities');
    Check(Capabilities.GetValue<Boolean>('load'), 'Status advertises the public launch call');
    Check(not Capabilities.GetValue<Boolean>('select_debugger'), 'Status does not claim engine selection');
    Check(not Capabilities.GetValue<Boolean>('working_directory'), 'Status does not claim working-directory support');
    Check(not Capabilities.GetValue<Boolean>('read_native_dialog_settings'), 'Status does not claim native settings reads');
    Check(Capabilities.GetValue('current_debugger_support') is TJSONNull, 'SDK support and active engine support are distinct');
  finally
    Response.Free;
  end;

  BorlandIDEServices := nil;
  ExpectError(
    procedure
    begin
      TDAIDebuggerService.Processes('', 200).Free;
    end, EInvalidOperation, 'Missing debugger service produces an explicit error');
  Response := TDAIDebuggerService.Status;
  try
    Check(not Response.GetValue<Boolean>('available'), 'Status reports an unavailable service');
  finally
    Response.Free;
  end;
end;

begin
  try
    TestProcessList;
    TestLoadRequest;
    TestAttachAndDetach;
    TestRejectedRequestsAndCapabilities;
    BorlandIDEServices := nil;
    Writeln('DAI debugger processes: ', GChecks, ' checks passed.');
  except
    on E: Exception do
    begin
      BorlandIDEServices := nil;
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
