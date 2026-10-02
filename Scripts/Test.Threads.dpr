program Test.Threads;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Threads;

type
  TBasicThread = class(TInterfacedObject, IOTAThread)
  public
    Id: Cardinal;
    State: TOTAThreadState;
    FileName: string;
    Line: Cardinal;
    FileReads: Integer;
    LineReads: Integer;
    SourceRaises: Boolean;
    destructor Destroy; override;
    function GetOSThreadID: LongWord;
    function GetState: TOTAThreadState;
    function GetCurrentFile: string;
    function GetCurrentLine: LongWord;
  end;

  TNamedThread = class(TBasicThread, IOTAThread90, IOTAThread140)
  public
    ThreadName: string;
    Display: string;
    NameRaises: Boolean;
    DisplayRaises: Boolean;
    function GetThreadName: string;
    procedure SetThreadName(const Name: string);
    function GetDisplayString: string;
  end;

  TProcess = class(TInterfacedObject, IOTAProcess)
  public
    Id: Cardinal;
    DebuggerId: Cardinal;
    State: TOTAProcessState;
    ThreadList: TList<IOTAThread>;
    Current: IOTAThread;
    CountOverride: Integer;
    ThreadReads: Integer;
    constructor Create;
    destructor Destroy; override;
    function GetCurrentThread: IOTAThread;
    procedure SetCurrentThread(Value: IOTAThread);
    function GetThreadCount: Integer;
    function GetThread(Index: Integer): IOTAThread;
    function GetProcessId: LongWord;
    function GetOSProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    procedure SetProcessState(const NewState: TOTAProcessState);
  end;

  TDebugger = class(TInterfacedObject, IOTADebuggerServices)
  public
    ProcessList: TList<IOTAProcess>;
    Current: IOTAProcess;
    CountOverride: Integer;
    constructor Create;
    destructor Destroy; override;
    function GetCurrentProcess: IOTAProcess;
    procedure SetCurrentProcess(const Process: IOTAProcess);
    function GetProcessCount: Integer;
    function GetProcess(Index: Integer): IOTAProcess;
  end;

const
  CProcessNames: array[TOTAProcessState] of string = ('nothing', 'running', 'stopping', 'stopped', 'fault',
    'resource_fault', 'terminated', 'exception', 'no_process');
  CThreadNames: array[TOTAThreadState] of string = ('stopped', 'runnable', 'blocked', 'none', 'other');

var
  GChecks: Integer;
  GGetterCount: Integer;
  GMutations: Integer;
  GDestroyed: Integer;
  GWrongDestructionThread: Integer;
  GDebugger: TDebugger;
  GParent: TProcess;
  GChild: TProcess;
  GEmpty: TProcess;
  GMain: TNamedThread;
  GBasic: TBasicThread;
  GChildThread: TNamedThread;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create(ADescription);
end;

procedure Getter;
begin
  Inc(GGetterCount);
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('An OTA getter ran outside the main thread.');
end;

procedure Destroyed;
begin
  Inc(GDestroyed);
  if GetCurrentThreadId <> MainThreadID then
    Inc(GWrongDestructionThread);
end;

procedure RejectMutation;
begin
  Inc(GMutations);
  raise EInvalidOperation.Create('Thread listing must never mutate debugger state.');
end;

destructor TBasicThread.Destroy;
begin
  Destroyed;
  inherited;
end;

function TBasicThread.GetOSThreadID: LongWord;
begin
  Getter;
  Result := Id;
end;

function TBasicThread.GetState: TOTAThreadState;
begin
  Getter;
  Result := State;
end;

function TBasicThread.GetCurrentFile: string;
begin
  Getter;
  Inc(FileReads);
  if SourceRaises then
    raise EInvalidOperation.Create('isolated source unavailable');
  Result := FileName;
end;

function TBasicThread.GetCurrentLine: LongWord;
begin
  Getter;
  Inc(LineReads);
  Result := Line;
end;

function TNamedThread.GetThreadName: string;
begin
  Getter;
  if NameRaises then
    raise EInvalidOperation.Create('isolated name unavailable');
  Result := ThreadName;
end;

procedure TNamedThread.SetThreadName(const Name: string);
begin
  RejectMutation;
end;

function TNamedThread.GetDisplayString: string;
begin
  Getter;
  if DisplayRaises then
    raise EInvalidOperation.Create('isolated display unavailable');
  Result := Display;
end;

constructor TProcess.Create;
begin
  inherited;
  ThreadList := TList<IOTAThread>.Create;
  CountOverride := -1;
end;

destructor TProcess.Destroy;
begin
  Destroyed;
  Current := nil;
  ThreadList.Free;
  inherited;
end;

function TProcess.GetCurrentThread: IOTAThread;
begin
  Getter;
  Result := Current;
end;

procedure TProcess.SetCurrentThread(Value: IOTAThread);
begin
  RejectMutation;
end;

function TProcess.GetThreadCount: Integer;
begin
  Getter;
  if CountOverride = -1 then
    Result := ThreadList.Count
  else
    Result := CountOverride;
end;

function TProcess.GetThread(Index: Integer): IOTAThread;
begin
  Getter;
  Inc(ThreadReads);
  Result := ThreadList[Index];
end;

function TProcess.GetProcessId: LongWord;
begin
  Getter;
  Result := DebuggerId;
end;

function TProcess.GetOSProcessId: LongWord;
begin
  Getter;
  Result := Id;
end;

function TProcess.GetProcessState: TOTAProcessState;
begin
  Getter;
  Result := State;
end;

procedure TProcess.SetProcessState(const NewState: TOTAProcessState);
begin
  RejectMutation;
end;

constructor TDebugger.Create;
begin
  inherited;
  ProcessList := TList<IOTAProcess>.Create;
  CountOverride := -1;
end;

destructor TDebugger.Destroy;
begin
  Destroyed;
  Current := nil;
  ProcessList.Free;
  inherited;
end;

function TDebugger.GetCurrentProcess: IOTAProcess;
begin
  Getter;
  Result := Current;
end;

procedure TDebugger.SetCurrentProcess(const Process: IOTAProcess);
begin
  RejectMutation;
end;

function TDebugger.GetProcessCount: Integer;
begin
  Getter;
  if CountOverride = -1 then
    Result := ProcessList.Count
  else
    Result := CountOverride;
end;

function TDebugger.GetProcess(Index: Integer): IOTAProcess;
begin
  Getter;
  Result := ProcessList[Index];
end;

procedure Setup;
var
  LSecond: TBasicThread;
begin
  BorlandIDEServices := nil;
  GDebugger := TDebugger.Create;
  BorlandIDEServices := GDebugger;
  GParent := TProcess.Create;
  GParent.Id := 4000000001;
  GParent.DebuggerId := 41;
  GParent.State := psStopped;
  GDebugger.ProcessList.Add(GParent);
  GDebugger.ProcessList.Add(nil);
  GDebugger.Current := GParent;
  GMain := TNamedThread.Create;
  GMain.Id := 4000000002;
  GMain.State := tsStopped;
  GMain.ThreadName := 'Hauptthread Grüße';
  GMain.Display := 'Main thread label';
  GMain.FileName := 'C:\isolated\Grüße.pas';
  GMain.Line := 4294967295;
  GParent.ThreadList.Add(GMain);
  GParent.Current := GMain;
  GBasic := TBasicThread.Create;
  GBasic.Id := 17;
  GBasic.State := tsRunnable;
  GBasic.FileName := 'must-not-read.pas';
  GBasic.Line := 88;
  GParent.ThreadList.Add(GBasic);
  LSecond := TBasicThread.Create;
  LSecond.Id := 19;
  LSecond.State := tsBlocked;
  GParent.ThreadList.Add(LSecond);
  GChild := TProcess.Create;
  GChild.Id := 8002;
  GChild.DebuggerId := 42;
  GChild.State := psRunning;
  GDebugger.ProcessList.Add(GChild);
  GChildThread := TNamedThread.Create;
  GChildThread.Id := 21;
  GChildThread.State := tsStopped;
  GChildThread.ThreadName := 'child thread';
  GChildThread.FileName := 'running-process-must-not-read.pas';
  GChildThread.Line := 52;
  GChild.ThreadList.Add(GChildThread);
  GChild.ThreadList.Add(nil);
  GChild.Current := GChildThread;
  GEmpty := TProcess.Create;
  GEmpty.Id := 8003;
  GEmpty.DebuggerId := 43;
  GEmpty.State := psTerminated;
  GDebugger.ProcessList.Add(GEmpty);
  GGetterCount := 0;
  GMutations := 0;
end;

function Row(const AResult: TJSONObject; AIndex: Integer): TJSONObject;
begin
  Result := TJSONObject(AResult.GetValue<TJSONArray>('threads').Items[AIndex]);
end;

procedure TestSelectionAndMetadata;
var
  LResult: TJSONObject;
  LRow: TJSONObject;
  LParentRefs: Integer;
  LMainRefs: Integer;
begin
  Setup;
  LParentRefs := GParent.RefCount;
  LMainRefs := GMain.RefCount;
  LResult := TDAIThreadService.List;
  try
    Check(LResult.GetValue<Boolean>('available'), 'Current-process listing is available');
    Check(LResult.GetValue<Integer>('process_count') = 1, 'Default selection picks one current process');
    Check(LResult.GetValue<Integer>('debugger_process_count') = 4, 'Debugger process count preserves the provider count');
    Check(LResult.GetValue<Integer>('thread_total') = 3, 'Default thread total is the selected process total');
    Check(LResult.GetValue<Integer>('returned_count') = 3, 'All current-process threads are listed');
    Check(not LResult.GetValue<Boolean>('truncated'), 'Complete current-process result is not truncated');
    Check(LResult.GetValue<Integer>('maximum_threads') = 200, 'Default global thread limit is 200');
    LRow := Row(LResult, 0);
    Check(LRow.GetValue<Int64>('process_id') = 4000000001, 'OS process ID is returned unsigned and without narrowing');
    Check(LRow.GetValue<Integer>('debugger_process_id') = 41, 'Internal debugger PID is distinct from the OS PID');
    Check(LRow.GetValue<Int64>('thread_id') = 4000000002, 'OS thread ID is returned unsigned and without narrowing');
    Check(LRow.GetValue<string>('state') = 'stopped', 'Thread state uses the SDK state');
    Check(LRow.GetValue<Boolean>('current'), 'CurrentThread is marked within its own process');
    Check(LRow.GetValue<Boolean>('current_process'), 'CurrentProcess is marked independently');
    Check(LRow.GetValue<string>('name') = 'Hauptthread Grüße', 'Optional thread names preserve Unicode');
    Check(LRow.GetValue<Boolean>('name_available'), 'Supported name getter is reported available');
    Check(LRow.GetValue<string>('display_string') = 'Main thread label', 'Optional display getter is distinct from the thread name');
    Check(LRow.GetValue<Boolean>('source_available'), 'Stopped process plus stopped thread permits source info');
    Check(LRow.GetValue<string>('source_file') = 'C:\isolated\Grüße.pas', 'Source filename preserves Unicode');
    Check(LRow.GetValue<Int64>('source_line') = 4294967295, 'Source line preserves the SDK unsigned range');
    LRow := Row(LResult, 1);
    Check(not LRow.GetValue<Boolean>('name_available'), 'A provider without IOTAThread140 is handled');
    Check(LRow.GetValue('name') is TJSONNull, 'An unsupported name is explicitly unavailable');
    Check(LRow.GetValue<string>('display_string') = '17', 'Missing display interface falls back to the OS thread ID');
    Check(not LRow.GetValue<Boolean>('source_available'), 'A runnable thread has no source read');
    Check(GBasic.FileReads = 0, 'No source getter is used for a runnable thread');
  finally
    LResult.Free;
  end;
  Check(GParent.RefCount = LParentRefs, 'No process interface is retained after a result is returned');
  Check(GMain.RefCount = LMainRefs, 'No thread/name/display interface is retained after a result is returned');

  LResult := TDAIThreadService.List(8002);
  try
    Check(LResult.GetValue<Integer>('process_count') = 1, 'Explicit OS PID selects the child process');
    Check(LResult.GetValue<Integer>('thread_total') = 2, 'Explicit child total uses its provider count including an unavailable slot');
    Check(LResult.GetValue<Integer>('returned_count') = 1, 'Nil provider thread slots are skipped safely');
    Check(LResult.GetValue<Boolean>('truncated'), 'Missing provider slots are honestly reported as incomplete');
    LRow := Row(LResult, 0);
    Check(LRow.GetValue<Integer>('process_id') = 8002, 'Explicit selection uses OS PID rather than internal debugger PID');
    Check(LRow.GetValue<Boolean>('current'), 'Child CurrentThread marker belongs to the child process');
    Check(not LRow.GetValue<Boolean>('current_process'), 'Child selection does not fake IDE CurrentProcess');
    Check(not LRow.GetValue<Boolean>('source_available'), 'Running process prevents source reads even for tsStopped');
    Check(GChildThread.FileReads = 0, 'Running process source getter is never called');
    Check(GDebugger.Current = IOTAProcess(GParent), 'Explicit selection never switches the current process');
  finally
    LResult.Free;
  end;
  LResult := TDAIThreadService.List(0, True);
  try
    Check(LResult.GetValue<Integer>('process_count') = 3, 'All-processes selection includes parent, child and empty process');
    Check(LResult.GetValue<Integer>('thread_total') = 5, 'Thread total spans selected debugger processes');
    Check(LResult.GetValue<Integer>('returned_count') = 4, 'Available threads from both parent and child are returned');
    Check(Row(LResult, 3).GetValue<Integer>('process_id') = 8002, 'Child threads appear in all-processes results');
    Check(GChildThread.FileReads = 0, 'All-processes mode still obeys running-process source guards');
    Check(GMutations = 0, 'Listing never invokes state/selection/name mutation');
  finally
    LResult.Free;
  end;
end;

procedure TestGlobalLimitsAndUnavailable;
var
  LResult: TJSONObject;
  LBefore: Integer;
  LRejected: Boolean;
  LDuplicate: TProcess;
begin
  Setup;
  LResult := TDAIThreadService.List(0, True, 1);
  try
    Check(LResult.GetValue<Integer>('returned_count') = 1, 'A single global limit covers all processes');
    Check(LResult.GetValue<Integer>('thread_total') = 5, 'The global limit preserves the full thread count');
    Check(LResult.GetValue<Integer>('process_count') = 3, 'Process metadata remains complete after reaching the thread limit');
    Check(LResult.GetValue<Boolean>('truncated'), 'A limited result is marked truncated');
    Check(GParent.ThreadReads = 1, 'No extra current-process thread is fetched after the limit');
    Check(GChild.ThreadReads = 0, 'No child thread getter is fetched after the global limit');
    Check(GChildThread.FileReads = 0, 'No child source read occurs after the global limit');
  finally
    LResult.Free;
  end;
  GParent.CountOverride := MaxInt;
  GChild.CountOverride := MaxInt;
  LResult := TDAIThreadService.List(0, True, 1);
  try
    Check(LResult.GetValue<Int64>('thread_total') = Int64(MaxInt) * 2, 'Global totals avoid 32-bit integer overflow');
  finally
    LResult.Free;
  end;
  GParent.CountOverride := -1;
  GChild.CountOverride := -1;
  LBefore := GGetterCount;
  LRejected := False;
  try
    LResult := TDAIThreadService.List(8002, True);
    LResult.Free;
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'Explicit PID combined with all_processes is rejected');
  Check(GGetterCount = LBefore, 'Conflicting filters do not enter any OTA getter');
  for LBefore in [0, 5001] do
  begin
    LRejected := False;
    try
      LResult := TDAIThreadService.List(0, False, LBefore);
      LResult.Free;
    except
      on E: EArgumentOutOfRangeException do
        LRejected := True;
    end;
    Check(LRejected, 'Thread limit outside 1..5000 is rejected');
  end;
  LResult := TDAIThreadService.List(0, True, 5000);
  try
    Check(LResult.GetValue<Integer>('maximum_threads') = 5000, 'Maximum allowed thread limit is accepted');
  finally
    LResult.Free;
  end;
  LResult := TDAIThreadService.List(41);
  try
    Check(not LResult.GetValue<Boolean>('available'), 'Internal debugger PID is not mistaken for an OS PID');
    Check(Pos('41', LResult.GetValue<string>('reason')) > 0, 'An unknown OS PID has an explicit reason');
    Check(LResult.GetValue<Integer>('returned_count') = 0, 'An unknown OS PID returns no unrelated threads');
  finally
    LResult.Free;
  end;
  LResult := TDAIThreadService.List(8003);
  try
    Check(LResult.GetValue<Boolean>('available'), 'An existing empty process is available');
    Check(LResult.GetValue<Integer>('thread_total') = 0, 'An empty process has a genuine zero thread total');
    Check(not LResult.GetValue<Boolean>('truncated'), 'An empty process is not incomplete');
  finally
    LResult.Free;
  end;
  GDebugger.Current := nil;
  LResult := TDAIThreadService.List;
  try
    Check(not LResult.GetValue<Boolean>('available'), 'Absent CurrentProcess is handled without nil dereference');
    Check(LResult.GetValue<Boolean>('debugger_available'), 'Absent CurrentProcess does not hide available services');
    Check(LResult.GetValue<string>('reason') <> '', 'Absent CurrentProcess has a reason');
  finally
    LResult.Free;
  end;
  LResult := TDAIThreadService.List(0, True);
  try
    Check(LResult.GetValue<Integer>('process_count') = 3, 'All-processes mode remains usable without CurrentProcess');
    Check(not Row(LResult, 0).GetValue<Boolean>('current_process'), 'No thread is marked as a missing CurrentProcess');
  finally
    LResult.Free;
  end;
  LDuplicate := TProcess.Create;
  LDuplicate.Id := GChild.Id;
  GDebugger.ProcessList.Add(LDuplicate);
  LRejected := False;
  try
    LResult := TDAIThreadService.List(8002);
    LResult.Free;
  except
    on E: EInvalidOperation do
      LRejected := True;
  end;
  Check(LRejected, 'Ambiguous duplicate OS process IDs are rejected');
  BorlandIDEServices := nil;
  LResult := TDAIThreadService.List;
  try
    Check(not LResult.GetValue<Boolean>('available'), 'Unavailable debugger services return clear availability');
    Check(not LResult.GetValue<Boolean>('debugger_available'), 'Service availability is distinct from empty selection');
    Check(LResult.GetValue<Integer>('thread_total') = 0, 'Unavailable services do not claim live threads');
    Check(LResult.GetValue<string>('reason') <> '', 'Unavailable services have a reason');
  finally
    LResult.Free;
  end;
end;

procedure TestProviderFailuresAndSourceGuards;
var
  LResult: TJSONObject;
  LProcessState: TOTAProcessState;
  LThreadState: TOTAThreadState;
  LAllowed: Boolean;
  LBefore: Integer;
  LRejected: Boolean;
begin
  Setup;
  GMain.NameRaises := True;
  GMain.DisplayRaises := True;
  LResult := TDAIThreadService.List;
  try
    Check(not Row(LResult, 0).GetValue<Boolean>('name_available'), 'Provider name exception is optional, not a failed thread list');
    Check(Row(LResult, 0).GetValue('name') is TJSONNull, 'A failed name getter returns unavailable rather than a fabricated name');
    Check(Pos('isolated name unavailable', Row(LResult, 0).GetValue<string>('name_reason')) > 0, 'Name failure reason is retained');
    Check(not Row(LResult, 0).GetValue<Boolean>('display_string_available'), 'Provider display exception is optional');
    Check(Row(LResult, 0).GetValue<string>('display_string') = '4000000002', 'Display failure retains the OS ID fallback');
    Check(LResult.GetValue<Integer>('returned_count') = 3, 'Provider optional-metadata failures do not hide other threads');
  finally
    LResult.Free;
  end;
  GMain.NameRaises := False;
  GMain.DisplayRaises := False;
  GMain.ThreadName := '';
  GMain.Display := '';
  LResult := TDAIThreadService.List;
  try
    Check(Row(LResult, 0).GetValue<Boolean>('name_available'), 'A supported unnamed thread remains a successful name query');
    Check(Row(LResult, 0).GetValue<string>('name') = '', 'A supported unnamed thread returns the SDK empty string');
    Check(Row(LResult, 0).GetValue<string>('display_string') = '4000000002', 'SDK empty display falls back to the OS ID');
  finally
    LResult.Free;
  end;
  for LProcessState := Low(TOTAProcessState) to High(TOTAProcessState) do
    for LThreadState := Low(TOTAThreadState) to High(TOTAThreadState) do
    begin
      GParent.State := LProcessState;
      GMain.State := LThreadState;
      LBefore := GMain.FileReads;
      LAllowed := (LProcessState in [psStopped, psFault, psResFault, psException]) and (LThreadState = tsStopped);
      LResult := TDAIThreadService.List(0, False, 1);
      try
        Check(Row(LResult, 0).GetValue<string>('state') = CThreadNames[LThreadState], 'All SDK thread states map consistently');
        Check(TJSONObject(LResult.GetValue<TJSONArray>('processes').Items[0]).GetValue<string>('state') =
          CProcessNames[LProcessState], 'All SDK process states map consistently');
        Check(Row(LResult, 0).GetValue<Boolean>('source_available') = LAllowed, 'Source info obeys both process and thread state');
        Check((GMain.FileReads > LBefore) = LAllowed, 'Source getter is called exactly for safe stopped-state combinations');
      finally
        LResult.Free;
      end;
    end;
  GParent.State := psStopped;
  GMain.State := tsStopped;
  GMain.SourceRaises := True;
  LResult := TDAIThreadService.List;
  try
    Check(not Row(LResult, 0).GetValue<Boolean>('source_available'), 'A provider source exception leaves thread metadata available');
    Check(Row(LResult, 0).GetValue('source_file') is TJSONNull, 'A failed source getter returns explicit null');
    Check(Pos('isolated source unavailable', Row(LResult, 0).GetValue<string>('source_reason')) > 0, 'Source provider reason is retained');
  finally
    LResult.Free;
  end;
  GMain.SourceRaises := False;
  GMain.FileName := '';
  GMain.Line := 0;
  LResult := TDAIThreadService.List;
  try
    Check(not Row(LResult, 0).GetValue<Boolean>('source_available'), 'Missing debug info is distinct from a valid source position');
    Check(Row(LResult, 0).GetValue<string>('source_reason') <> '', 'Missing debug info has a reason');
  finally
    LResult.Free;
  end;
  GParent.CountOverride := -2;
  LRejected := False;
  try
    LResult := TDAIThreadService.List;
    LResult.Free;
  except
    on E: EInvalidOperation do
      LRejected := True;
  end;
  Check(LRejected, 'A negative provider thread count is rejected');
  GParent.CountOverride := -1;
  GDebugger.CountOverride := -2;
  LRejected := False;
  try
    LResult := TDAIThreadService.List;
    LResult.Free;
  except
    on E: EInvalidOperation do
      LRejected := True;
  end;
  Check(LRejected, 'A negative provider process count is rejected');
end;

procedure TestWorkerLifetime;
var
  LWorker: TThread;
  LResult: TJSONObject;
  LParentRefs: Integer;
  LMainRefs: Integer;
begin
  Setup;
  LParentRefs := GParent.RefCount;
  LMainRefs := GMain.RefCount;
  LResult := nil;
  LWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      LResult := TDAIThreadService.List(0, True, 2);
    end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    LWorker.WaitFor;
    Check(not Assigned(LWorker.FatalException), 'A worker request marshals every SDK getter to the main thread');
    Check(Assigned(LResult), 'Worker receives JSON after the main-thread snapshot');
    Check(LResult.GetValue<Integer>('returned_count') = 2, 'Worker request respects the global limit');
    Check(GParent.RefCount = LParentRefs, 'Worker request retains no process interfaces beyond the callback');
    Check(GMain.RefCount = LMainRefs, 'Worker request retains no optional thread interfaces beyond the callback');
    Check(GMutations = 0, 'Worker request makes no mutation');
  finally
    LWorker.Free;
    LResult.Free;
  end;
  BorlandIDEServices := nil;
  Check(GWrongDestructionThread = 0, 'Every fixture SDK object is released on the main thread');
end;

begin
  try
    TestSelectionAndMetadata;
    TestGlobalLimitsAndUnavailable;
    TestProviderFailuresAndSourceGuards;
    TestWorkerLifetime;
    Check(GDestroyed > 0, 'Fixture reference-counted objects are actually destroyed');
    Check(GWrongDestructionThread = 0, 'No SDK object is destroyed on the worker');
    Writeln('DAI threads: ', GChecks, ' checks passed.');
  except
    on E: Exception do
    begin
      BorlandIDEServices := nil;
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
