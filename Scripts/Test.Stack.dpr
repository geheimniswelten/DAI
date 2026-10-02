program TestStack;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI in 'StackTests\ToolsAPI.pas',
  h5u.DAI.OTA.Helpers in 'StackTests\h5u.DAI.OTA.Helpers.pas',
  h5u.DAI.OTA.Stack;

type
  TProcessDouble = class;
  TFrame = record
    Header, SimpleName, FileName: string;
    Line: Integer;
  end;

  TThreadDouble = class(TInterfacedObject, IOTAThread)
  private
    FAccessOpen, FCountRead: Boolean;
    procedure IndexedAccess(const AIndex: Integer; const AGetter: string);
  public
    Id: Cardinal;
    ThreadState: TOTAThreadState;
    Owner: TProcessDouble;
    AccessState: TOTACallStackState;
    Frames: TArray<TFrame>;
    Failure: string;
    CountOverride: Integer;
    Starts, Ends, Counts, Headers, Positions, SimpleHeaders, LastIndex: Integer;
    constructor Create(const AId: Cardinal);
    procedure ResetCounters;
    function GetOSThreadID: LongWord;
    function GetState: TOTAThreadState;
    function GetOwningProcess: IOTAProcess;
    function StartCallStackAccess: TOTACallStackState;
    procedure EndCallStackAccess;
    function GetCallCount: Integer;
    function GetCallHeader(Index: Integer): string;
    procedure GetCallPos(Index: Integer; out FileName: string; out LineNum: Integer);
    procedure Run;
    procedure Pause;
  end;

  TSimpleThreadDouble = class(TThreadDouble, IOTAThread110)
  public
    function GetSimpleCallHeader(Index: Integer): string;
  end;

  TProcessDouble = class(TInterfacedObject, IOTAProcess)
  public
    Id, DebuggerId: Cardinal;
    ProcessStateValue: TOTAProcessState;
    Current: IOTAThread;
    ThreadList: TArray<IOTAThread>;
    function GetOSProcessId: LongWord;
    function GetProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    function GetCurrentThread: IOTAThread;
    procedure SetCurrentThread(const Value: IOTAThread);
    function GetThreadCount: Integer;
    function GetThread(Index: Integer): IOTAThread;
    procedure Run;
    procedure Pause;
    procedure Terminate;
  end;

  TDebuggerDouble = class(TInterfacedObject, IOTADebuggerServices)
  public
    Current: IOTAProcess;
    ProcessList: TArray<IOTAProcess>;
    function GetCurrentProcess: IOTAProcess;
    procedure SetCurrentProcess(const Value: IOTAProcess);
    function GetProcessCount: Integer;
    function GetProcess(Index: Integer): IOTAProcess;
  end;

var
  CheckCount, MutationCount, GetterCount: Integer;
  Debugger: TDebuggerDouble;
  ParentProcess, ChildProcess: TProcessDouble;
  ParentThread, OtherThread: TThreadDouble;
  ChildThread: TSimpleThreadDouble;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure ReadGetter;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('OTA getter called outside the main thread');
  Inc(GetterCount);
end;

procedure ForbiddenMutation;
begin
  Inc(MutationCount);
  raise EInvalidOperation.Create('Stack reading must never mutate debugger state');
end;

constructor TThreadDouble.Create(const AId: Cardinal);
var
  LIndex: Integer;
begin
  inherited Create;
  Id := AId;
  ThreadState := tsStopped;
  AccessState := csAccessible;
  CountOverride := -1;
  SetLength(Frames, 3);
  for LIndex := 0 to High(Frames) do
  begin
    Frames[LIndex].Header := Format('Fixture.TForm.Handler%d(%d)', [LIndex + 1, LIndex]);
    Frames[LIndex].SimpleName := Format('Handler%d', [LIndex + 1]);
    Frames[LIndex].FileName := 'C:\Fixture\Unit' + IntToStr(LIndex + 1) + '.pas';
    Frames[LIndex].Line := 10 * (LIndex + 1);
  end;
end;

procedure TThreadDouble.ResetCounters;
begin
  Starts := 0;
  Ends := 0;
  Counts := 0;
  Headers := 0;
  Positions := 0;
  SimpleHeaders := 0;
  LastIndex := 0;
  FAccessOpen := False;
  FCountRead := False;
end;

function TThreadDouble.GetOSThreadID: LongWord;
begin ReadGetter; Result := Id; end;

function TThreadDouble.GetState: TOTAThreadState;
begin ReadGetter; Result := ThreadState; end;

function TThreadDouble.GetOwningProcess: IOTAProcess;
begin ReadGetter; Result := Owner; end;

function TThreadDouble.StartCallStackAccess: TOTACallStackState;
begin
  ReadGetter;
  Inc(Starts);
  if Failure = 'start' then
    raise EInvalidOperation.Create('Injected start failure');
  if FAccessOpen then
    raise EInvalidOperation.Create('Unbalanced stack access');
  FAccessOpen := True;
  FCountRead := False;
  Result := AccessState;
end;

procedure TThreadDouble.EndCallStackAccess;
begin
  ReadGetter;
  if not FAccessOpen then
    raise EInvalidOperation.Create('End without start');
  FAccessOpen := False;
  Inc(Ends);
end;

function TThreadDouble.GetCallCount: Integer;
begin
  ReadGetter;
  if not FAccessOpen or (AccessState <> csAccessible) then
    raise EInvalidOperation.Create('GetCallCount without accessible stack');
  Inc(Counts);
  FCountRead := True;
  if Failure = 'count' then
    raise EInvalidOperation.Create('Injected count failure');
  if CountOverride <> -1 then
    Exit(CountOverride);
  Result := Length(Frames);
end;

procedure TThreadDouble.IndexedAccess(const AIndex: Integer; const AGetter: string);
begin
  ReadGetter;
  if not FAccessOpen or not FCountRead or (AccessState <> csAccessible) then
    raise EInvalidOperation.Create('Indexed getter before GetCallCount/access');
  if (AIndex < 1) or (AIndex > Length(Frames)) then
    raise EInvalidOperation.Create('SDK call-stack indices are one-based');
  LastIndex := AIndex;
  if Failure = AGetter then
    raise EInvalidOperation.Create('Injected ' + AGetter + ' failure');
end;

function TThreadDouble.GetCallHeader(Index: Integer): string;
begin IndexedAccess(Index, 'header'); Inc(Headers); Result := Frames[Index - 1].Header; end;

procedure TThreadDouble.GetCallPos(Index: Integer; out FileName: string; out LineNum: Integer);
begin
  IndexedAccess(Index, 'position');
  Inc(Positions);
  FileName := Frames[Index - 1].FileName;
  LineNum := Frames[Index - 1].Line;
end;

function TSimpleThreadDouble.GetSimpleCallHeader(Index: Integer): string;
begin IndexedAccess(Index, 'simple'); Inc(SimpleHeaders); Result := Frames[Index - 1].SimpleName; end;

procedure TThreadDouble.Run;
begin ForbiddenMutation; end;
procedure TThreadDouble.Pause;
begin ForbiddenMutation; end;

function TProcessDouble.GetOSProcessId: LongWord;
begin ReadGetter; Result := Id; end;
function TProcessDouble.GetProcessId: LongWord;
begin ReadGetter; Result := DebuggerId; end;
function TProcessDouble.GetProcessState: TOTAProcessState;
begin ReadGetter; Result := ProcessStateValue; end;
function TProcessDouble.GetCurrentThread: IOTAThread;
begin ReadGetter; Result := Current; end;
procedure TProcessDouble.SetCurrentThread(const Value: IOTAThread);
begin ForbiddenMutation; end;
function TProcessDouble.GetThreadCount: Integer;
begin ReadGetter; Result := Length(ThreadList); end;
function TProcessDouble.GetThread(Index: Integer): IOTAThread;
begin ReadGetter; Result := ThreadList[Index]; end;
procedure TProcessDouble.Run;
begin ForbiddenMutation; end;
procedure TProcessDouble.Pause;
begin ForbiddenMutation; end;
procedure TProcessDouble.Terminate;
begin ForbiddenMutation; end;

function TDebuggerDouble.GetCurrentProcess: IOTAProcess;
begin ReadGetter; Result := Current; end;
procedure TDebuggerDouble.SetCurrentProcess(const Value: IOTAProcess);
begin ForbiddenMutation; end;
function TDebuggerDouble.GetProcessCount: Integer;
begin ReadGetter; Result := Length(ProcessList); end;
function TDebuggerDouble.GetProcess(Index: Integer): IOTAProcess;
begin ReadGetter; Result := ProcessList[Index]; end;

function ReadOnWorker(const AProcessId: Cardinal = 0; const AThreadId: Cardinal = 0; const AFrames: Integer = 50;
  const ACharacters: Integer = 20000): TJSONObject;
var
  LWorker: TThread;
  LResult: TJSONObject;
begin
  LResult := nil;
  LWorker := TThread.CreateAnonymousThread(
    procedure begin LResult := TDAIStackService.Read(AProcessId, AThreadId, AFrames, ACharacters); end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    LWorker.WaitFor;
    if Assigned(LWorker.FatalException) then
      raise EInvalidOperation.Create(Exception(LWorker.FatalException).Message);
    Result := LResult;
  finally
    LWorker.Free;
  end;
end;

procedure InitializeFixtures;
begin
  ParentProcess := TProcessDouble.Create;
  ParentProcess.Id := 12345;
  ParentProcess.DebuggerId := 77;
  ParentProcess.ProcessStateValue := psStopped;
  ParentThread := TThreadDouble.Create(4321);
  ParentThread.Owner := ParentProcess;
  OtherThread := TThreadDouble.Create(7654);
  OtherThread.Owner := ParentProcess;
  ParentProcess.ThreadList := [nil, ParentThread, OtherThread];
  ParentProcess.Current := ParentThread;
  ChildProcess := TProcessDouble.Create;
  ChildProcess.Id := High(Cardinal);
  ChildProcess.DebuggerId := 88;
  ChildProcess.ProcessStateValue := psException;
  ChildThread := TSimpleThreadDouble.Create(High(Cardinal));
  ChildThread.Owner := ChildProcess;
  ChildProcess.ThreadList := [ChildThread];
  ChildProcess.Current := ChildThread;
  Debugger := TDebuggerDouble.Create;
  Debugger.ProcessList := [nil, ParentProcess, ChildProcess];
  Debugger.Current := ParentProcess;
  BorlandIDEServices := Debugger;
end;

procedure CheckUnavailable(const ACode: string; const AProcessId: Cardinal = 0; const AThreadId: Cardinal = 0;
  const ARetryable: Boolean = False);
var
  LResult: TJSONObject;
begin
  LResult := ReadOnWorker(AProcessId, AThreadId);
  try
    Check(not LResult.GetValue<Boolean>('available'), ACode + ': unavailable');
    Check(LResult.GetValue<string>('reason_code') = ACode, ACode + ': exact reason');
    Check(LResult.GetValue<string>('reason') <> '', ACode + ': useful reason');
    Check(LResult.GetValue<Boolean>('retryable') = ARetryable, ACode + ': retryability');
    Check(LResult.GetValue<TJSONArray>('frames').Count = 0, ACode + ': no fabricated frames');
  finally
    LResult.Free;
  end;
end;

procedure CheckSelectionAndStates;
var
  LResult: TJSONObject;
  LProcessState: TOTAProcessState;
  LThreadState: TOTAThreadState;
  LSavedDebugger: IInterface;
begin
  LSavedDebugger := BorlandIDEServices;
  BorlandIDEServices := nil;
  CheckUnavailable('debugger_unavailable');
  BorlandIDEServices := TInterfacedObject.Create;
  CheckUnavailable('debugger_unavailable');
  BorlandIDEServices := LSavedDebugger;
  Debugger.Current := nil;
  CheckUnavailable('no_current_process');
  LResult := ReadOnWorker(ChildProcess.Id);
  try
    Check(LResult.GetValue<Boolean>('available'), 'Explicit child process works without a CurrentProcess');
    Check(LResult.GetValue<Int64>('process_id') = Int64(High(Cardinal)), 'Full UInt32 OS process ID preserved');
    Check(LResult.GetValue<Int64>('thread_id') = Int64(High(Cardinal)), 'Full UInt32 OS thread ID preserved');
  finally LResult.Free; end;
  Debugger.Current := ParentProcess;
  CheckUnavailable('process_not_found', 999999);
  ParentProcess.Current := nil;
  CheckUnavailable('no_current_thread');
  LResult := ReadOnWorker(0, OtherThread.Id);
  try Check(LResult.GetValue<Boolean>('available'), 'Explicit thread works without CurrentThread'); finally LResult.Free; end;
  ParentProcess.Current := ParentThread;
  CheckUnavailable('thread_not_found', 0, ChildThread.Id);
  CheckUnavailable('thread_not_found', ChildProcess.Id, ParentThread.Id);
  CheckUnavailable('thread_not_found', 0, 999999);
  ParentThread.Owner := ChildProcess;
  CheckUnavailable('thread_process_mismatch');
  ParentThread.Owner := nil;
  CheckUnavailable('thread_owner_unavailable');
  ParentThread.Owner := ParentProcess;
  ParentThread.ResetCounters;
  for LProcessState := Low(TOTAProcessState) to High(TOTAProcessState) do
  begin
    ParentProcess.ProcessStateValue := LProcessState;
    if LProcessState in [psStopped, psFault, psResFault, psException] then
    begin
      LResult := ReadOnWorker;
      try
        Check(LResult.GetValue<Boolean>('available'), 'Stopped/fault/exception process supports stack access');
        Check(LResult.GetValue<Boolean>('suspended'), 'Stopped process and stopped thread report suspended');
      finally LResult.Free; end;
    end
    else
    begin
      ParentThread.ResetCounters;
      CheckUnavailable('process_not_stopped');
      Check(ParentThread.Starts = 0, 'Running/stopping/terminated process does not acquire stack access');
    end;
  end;
  ParentProcess.ProcessStateValue := psStopped;
  for LThreadState := tsRunnable to High(TOTAThreadState) do
  begin
    ParentThread.ResetCounters;
    ParentThread.ThreadState := LThreadState;
    CheckUnavailable('thread_not_stopped');
    Check(ParentThread.Starts = 0, 'Runnable/blocked/none/other thread does not acquire stack access');
  end;
  ParentThread.ThreadState := tsStopped;
  Check(Debugger.Current = IOTAProcess(ParentProcess), 'Process selection was never changed');
  Check(ParentProcess.Current = IOTAThread(ParentThread), 'Thread selection was never changed');
end;

procedure CheckFrames;
var
  LResult, LFrame: TJSONObject;
  LFrames: TJSONArray;
begin
  ParentThread.ResetCounters;
  LResult := ReadOnWorker;
  try
    Check(LResult.GetValue<Boolean>('available'), 'Current stopped thread returns a stack');
    Check(LResult.GetValue<Integer>('maximum_frames') = 50, 'Default frame limit is 50');
    Check(LResult.GetValue<Integer>('maximum_characters') = 20000, 'Default character limit is 20000');
    Check(LResult.GetValue<Integer>('total_frames') = 3, 'SDK total frame count preserved');
    Check(LResult.GetValue<Integer>('frame_count') = 3, 'All small-stack frames returned');
    Check(not LResult.GetValue<Boolean>('truncated'), 'Small stack is not truncated');
    LFrames := LResult.GetValue<TJSONArray>('frames');
    LFrame := TJSONObject(LFrames.Items[0]);
    Check(LFrame.GetValue<Integer>('index') = 1, 'First frame uses SDK index 1');
    Check(LFrame.GetValue<string>('header') = ParentThread.Frames[0].Header, 'Evaluator header is unparsed and exact');
    Check(LFrame.GetValue<string>('filename') = ParentThread.Frames[0].FileName, 'Actual SDK source filename returned');
    Check(LFrame.GetValue<Integer>('line') = 10, 'Actual SDK source line returned');
    Check(LFrame.GetValue<Boolean>('source_info_available'), 'Source availability is truthful');
    Check(LFrame.GetValue('function') is TJSONNull, 'Optional unavailable simple-header interface maps to null');
    Check(LFrame.GetValue('module') is TJSONNull, 'Unsupported frame module is null');
    Check(LFrame.GetValue('address') is TJSONNull, 'Unsupported frame address is null');
    Check(TJSONObject(LFrames.Items[2]).GetValue<Integer>('index') = 3, 'Final frame uses SDK index 3');
    Check(ParentThread.LastIndex = 3, 'One-based final index passed to SDK getters');
    Check(ParentThread.Counts = 1, 'GetCallCount queried exactly once before indexed getters');
    Check((ParentThread.Starts = 1) and (ParentThread.Ends = 1), 'Successful access is balanced');
  finally LResult.Free; end;
  ChildThread.Frames[1].FileName := '';
  ChildThread.Frames[1].Line := 0;
  ChildThread.Frames[1].Header := '';
  ChildThread.ResetCounters;
  LResult := ReadOnWorker(ChildProcess.Id, ChildThread.Id);
  try
    LFrame := TJSONObject(LResult.GetValue<TJSONArray>('frames').Items[0]);
    Check(LFrame.GetValue<string>('function') = ChildThread.Frames[0].SimpleName, 'Official simple function name returned');
    LFrame := TJSONObject(LResult.GetValue<TJSONArray>('frames').Items[1]);
    Check(LFrame.GetValue<string>('filename') = '', 'SDK unknown filename remains empty');
    Check(LFrame.GetValue<Integer>('line') = 0, 'SDK unknown source line remains zero');
    Check(not LFrame.GetValue<Boolean>('source_info_available'), 'Missing source location is explicit');
    Check(LFrame.GetValue<string>('header') = '', 'SDK empty header is not invented');
    Check(ChildThread.SimpleHeaders = 3, 'Optional SDK simple headers read for all frames');
    Check(LResult.GetValue<Integer>('debugger_process_id') = 88, 'Debugger internal ID distinguished from OS ID');
    Check(LResult.GetValue<string>('process_state') = 'exception', 'Actual process state preserved');
    Check(LResult.GetValue<string>('thread_state') = 'stopped', 'Actual thread state preserved');
  finally LResult.Free; end;
end;

procedure CheckAccessProtocol;
var
  LResult: TJSONObject;
  LAccess: TOTACallStackState;
  LFailure: string;
  LRejected: Boolean;
begin
  for LAccess := csInaccessible to csWait do
  begin
    ParentThread.ResetCounters;
    ParentThread.AccessState := LAccess;
    if LAccess = csWait then
      CheckUnavailable('call_stack_wait', 0, 0, True)
    else
      CheckUnavailable('call_stack_inaccessible');
    Check((ParentThread.Starts = 1) and (ParentThread.Ends = 1), 'Unavailable access also releases its access bracket');
    Check(ParentThread.Counts = 0, 'Unavailable stack does not query GetCallCount');
    Check((ParentThread.Headers = 0) and (ParentThread.Positions = 0), 'Unavailable stack has no indexed reads');
  end;
  ParentThread.AccessState := csAccessible;
  for LFailure in ['count', 'header', 'position'] do
  begin
    ParentThread.ResetCounters;
    ParentThread.Failure := LFailure;
    LRejected := False;
    try LResult := ReadOnWorker; LResult.Free; except on E: EInvalidOperation do LRejected := True; end;
    Check(LRejected, 'SDK ' + LFailure + ' failure propagates without fabricated success');
    Check((ParentThread.Starts = 1) and (ParentThread.Ends = 1), 'SDK ' + LFailure + ' failure releases stack access');
  end;
  ParentThread.Failure := '';
  ChildThread.Failure := 'simple';
  ChildThread.ResetCounters;
  LRejected := False;
  try LResult := ReadOnWorker(ChildProcess.Id); LResult.Free; except on E: EInvalidOperation do LRejected := True; end;
  Check(LRejected, 'Optional simple-header SDK failure propagates');
  Check(ChildThread.Ends = 1, 'Simple-header failure releases stack access');
  ChildThread.Failure := '';
  ParentThread.ResetCounters;
  ParentThread.Failure := 'start';
  LRejected := False;
  try LResult := ReadOnWorker; LResult.Free; except on E: EInvalidOperation do LRejected := True; end;
  Check(LRejected, 'Failed access acquisition propagates');
  Check((ParentThread.Starts = 1) and (ParentThread.Ends = 0), 'Failed start does not end an unacquired access bracket');
  ParentThread.Failure := '';
  ParentThread.CountOverride := -2;
  ParentThread.ResetCounters;
  LRejected := False;
  try LResult := ReadOnWorker; LResult.Free; except on E: EInvalidOperation do LRejected := True; end;
  Check(LRejected, 'Invalid negative SDK frame count is rejected');
  Check(ParentThread.Ends = 1, 'Invalid count releases stack access');
  ParentThread.CountOverride := 0;
  LResult := ReadOnWorker;
  try
    Check(LResult.GetValue<Boolean>('available'), 'Accessible empty stack is a valid result');
    Check(LResult.GetValue<Integer>('frame_count') = 0, 'Empty stack has zero frames');
    Check(not LResult.GetValue<Boolean>('truncated'), 'Empty stack is not truncated');
  finally LResult.Free; end;
  ParentThread.CountOverride := -1;
end;

function ReturnedCharacters(const AResult: TJSONObject): Integer;
var
  LFrames: TJSONArray;
  LFrame: TJSONValue;
  LKey: string;
  LValue: TJSONValue;
begin
  Result := 0;
  LFrames := AResult.GetValue<TJSONArray>('frames');
  for LFrame in LFrames do
    for LKey in ['filename', 'header', 'function'] do
    begin
      LValue := TJSONObject(LFrame).GetValue(LKey);
      if LValue is TJSONString then
        Inc(Result, Length(TJSONString(LValue).Value));
    end;
end;

procedure CheckLimits;
var
  LLimit, LIndex, LBefore: Integer;
  LResult, LFrame: TJSONObject;
  LRejected: Boolean;
  LSavedFrames: TArray<TFrame>;
begin
  for LLimit in [-1, 0, 501, High(Integer)] do
  begin
    LBefore := MarshalCount;
    LRejected := False;
    try LResult := TDAIStackService.Read(0, 0, LLimit); LResult.Free;
    except on E: EArgumentOutOfRangeException do LRejected := True; end;
    Check(LRejected, 'Invalid frame limit rejected');
    Check(MarshalCount = LBefore, 'Invalid frame limit rejected before accessing OTA');
  end;
  for LLimit in [-1, 0, 200001, High(Integer)] do
  begin
    LBefore := MarshalCount;
    LRejected := False;
    try LResult := TDAIStackService.Read(0, 0, 50, LLimit); LResult.Free;
    except on E: EArgumentOutOfRangeException do LRejected := True; end;
    Check(LRejected, 'Invalid character limit rejected');
    Check(MarshalCount = LBefore, 'Invalid character limit rejected before accessing OTA');
  end;
  LSavedFrames := Copy(ParentThread.Frames);
  SetLength(ParentThread.Frames, 600);
  for LIndex := 0 to High(ParentThread.Frames) do
  begin
    ParentThread.Frames[LIndex].Header := 'Frame' + IntToStr(LIndex + 1);
    ParentThread.Frames[LIndex].FileName := '';
    ParentThread.Frames[LIndex].Line := 0;
  end;
  LResult := ReadOnWorker;
  try
    Check(LResult.GetValue<Integer>('frame_count') = 50, 'Default limit truncates a large stack to 50');
    Check(LResult.GetValue<Integer>('total_frames') = 600, 'Truncation preserves actual total');
    Check(LResult.GetValue<Boolean>('truncated'), 'Frame-limit truncation explicit');
  finally LResult.Free; end;
  ParentThread.ResetCounters;
  LResult := ReadOnWorker(0, 0, 500, 200000);
  try
    Check(LResult.GetValue<Integer>('frame_count') = 500, 'Maximum 500 frames accepted');
    Check(ParentThread.LastIndex = 500, 'No getter reads frames beyond maximum');
  finally LResult.Free; end;
  ParentThread.ResetCounters;
  ParentThread.Frames[0].Header := StringOfChar('x', 100000);
  LResult := ReadOnWorker(0, 0, 500, 100);
  try
    Check(LResult.GetValue<Integer>('frame_count') = 1, 'Exhausted character budget stops reading further frames');
    Check(LResult.GetValue<Integer>('characters_returned') = 100, 'Character budget consumed exactly');
    Check(ReturnedCharacters(LResult) = 100, 'Reported character count equals actual returned strings');
    Check(Length(TJSONObject(LResult.GetValue<TJSONArray>('frames').Items[0]).GetValue<string>('header')) = 100,
      'Large evaluator header is bounded');
    Check(LResult.GetValue<Boolean>('truncated'), 'Character truncation explicit');
    Check(ParentThread.Positions = 1, 'No further source-location calls after exhausted budget');
  finally LResult.Free; end;
  ParentThread.Frames[0].Header := 'abc' + #$D83D#$DE00 + 'tail';
  LResult := ReadOnWorker(0, 0, 1, 4);
  try
    LFrame := TJSONObject(LResult.GetValue<TJSONArray>('frames').Items[0]);
    Check(LFrame.GetValue<string>('header') = 'abc', 'Truncation does not split a surrogate pair');
    Check(LResult.GetValue<Integer>('characters_returned') = 3, 'Surrogate guard counts returned characters accurately');
    Check(LFrame.GetValue<Boolean>('fields_truncated'), 'Per-frame text truncation explicit');
  finally LResult.Free; end;
  LResult := ReadOnWorker(0, 0, 1, 1);
  try
    Check(ReturnedCharacters(LResult) = 1, 'Minimum character budget accepted');
    Check(LResult.GetValue<Integer>('frame_count') = 1, 'Minimum frame budget accepted');
  finally LResult.Free; end;
  ParentThread.Frames := LSavedFrames;
  ParentThread.Frames[0].FileName := StringOfChar('f', 1000);
  ParentThread.ResetCounters;
  LResult := ReadOnWorker(0, 0, 50, 4);
  try
    LFrame := TJSONObject(LResult.GetValue<TJSONArray>('frames').Items[0]);
    Check(LFrame.GetValue<string>('filename') = 'ffff', 'Source filenames also obey character budget');
    Check(ParentThread.Headers = 0, 'No header getter after filename exhausts budget');
    Check(LResult.GetValue<Integer>('characters_returned') = ReturnedCharacters(LResult), 'Filename budget accounting exact');
  finally LResult.Free; end;
end;

begin
  try
    InitializeFixtures;
    CheckSelectionAndStates;
    CheckFrames;
    CheckAccessProtocol;
    CheckLimits;
    Check(MutationCount = 0, 'No continue/pause/terminate/process/thread-selection mutation occurred');
    Check(GetterCount > 0, 'Tests exercised genuine production getter calls');
    Check(MarshalCount > 0, 'Worker calls actually marshal to the main thread');
    BorlandIDEServices := nil;
    Writeln(Format('PASS: %d isolated stack checks (%s).', [CheckCount, {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF}]));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
