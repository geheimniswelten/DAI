program TestUsage;

{$APPTYPE CONSOLE}

uses
  DAI.Lifecycle.TestRegistry in 'LauncherTests\DAI.Lifecycle.TestRegistry.pas',
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  h5u.DAI.Usage in '..\Source\h5u.DAI.Usage.pas';

type
  TCounterThread = class(TThread)
  private
    FName: string;
    FCount: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const AName: string; const ACount: Integer);
  end;

  TMutexThread = class(TThread)
  private
    FReady: TEvent;
    FRelease: TEvent;
    FAcquired: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

const
  CThreadCount = 8;
  CCallsPerThread = 150;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function UsagePath(const AMonth: string): string;
begin
  Result := CDAIUsageRegistryRoot + '\' + AMonth;
end;

function OpenMonth(const AMonth: string): TRegistry;
begin
  Result := TRegistry.Create(KEY_READ or KEY_WRITE or KEY_WOW64_64KEY);
  try
    Result.RootKey := HKEY_CURRENT_USER;
    if not Result.OpenKey(UsagePath(AMonth), True) then
      raise Exception.Create('Cannot open isolated monthly test key.');
  except
    Result.Free;
    raise;
  end;
end;

function ReadCount(const AMonth, AName: string): UInt64;
var
  LRegistry: TRegistry;
  LType: DWORD;
  LSize: DWORD;
  LError: Longint;
begin
  LRegistry := OpenMonth(AMonth);
  try
    LSize := SizeOf(Result);
    LType := REG_NONE;
    Result := 0;
    LError := RegQueryValueEx(LRegistry.CurrentKey, PChar(AName), nil, @LType, PByte(@Result), @LSize);
    if LError <> ERROR_SUCCESS then
      RaiseLastOSError(LError);
    Check((LType = REG_QWORD) and (LSize = SizeOf(Result)), 'Counter is stored as REG_QWORD');
  finally
    LRegistry.Free;
  end;
end;

procedure SeedQWord(const AName: string; const AValue: UInt64);
var
  LRegistry: TRegistry;
  LError: Longint;
begin
  LRegistry := OpenMonth('2026_10');
  try
    LError := RegSetValueEx(LRegistry.CurrentKey, PChar(AName), 0, REG_QWORD, PByte(@AValue), SizeOf(AValue));
    if LError <> ERROR_SUCCESS then
      RaiseLastOSError(LError);
  finally
    LRegistry.Free;
  end;
end;

constructor TCounterThread.Create(const AName: string; const ACount: Integer);
begin
  inherited Create(True);
  FName := AName;
  FCount := ACount;
end;

procedure TCounterThread.Execute;
var
  LIndex: Integer;
begin
  for LIndex := 1 to FCount do
    TDAIUsage.TestRecordToolCallAt(FName, True, EncodeDate(2026, 10, 24));
end;

constructor TMutexThread.Create;
begin
  inherited Create(True);
  FReady := TEvent.Create(nil, True, False, '');
  FRelease := TEvent.Create(nil, True, False, '');
end;

destructor TMutexThread.Destroy;
begin
  FRelease.SetEvent;
  WaitFor;
  FRelease.Free;
  FReady.Free;
  inherited;
end;

procedure TMutexThread.Execute;
var
  LMutex: THandle;
begin
  LMutex := CreateMutex(nil, False, PChar(TDAIUsage.TestMutexName));
  try
    FAcquired := (LMutex <> 0) and (WaitForSingleObject(LMutex, 5000) = WAIT_OBJECT_0);
    FReady.SetEvent;
    if FAcquired then
    begin
      FRelease.WaitFor(5000);
      ReleaseMutex(LMutex);
    end;
  finally
    if LMutex <> 0 then
      CloseHandle(LMutex);
  end;
end;

procedure CheckMonthsAndActivity;
var
  LBefore: UInt64;
  LRegistry: TRegistry;
begin
  TDAIUsage.ResetActivity;
  Check(TDAIUsage.LastActivityTick = 0, 'Activity starts unset');
  TDAIUsage.TestRecordToolCallAt('ide_status', False, EncodeDate(2025, 12, 31) + EncodeTime(23, 59, 59, 999));
  Check(TDAIUsage.LastActivityTick = 0, 'Orientation call does not activate icon');
  TDAIUsage.TestRecordToolCallAt('ide_status', False, EncodeDate(2026, 1, 1));
  Check(ReadCount('2025_12', 'ide_status') = 1, 'Last month receives its own counter');
  Check(ReadCount('2026_01', 'ide_status') = 1, 'New year and month start a separate counter');
  TDAIUsage.TestRecordToolCallAt('file_read', True, EncodeDate(2026, 1, 1));
  LBefore := TDAIUsage.LastActivityTick;
  Check(LBefore > 0, 'Content access sets monotonic activity tick');
  TDAIUsage.TestRecordToolCallAt('file_read', True, EncodeDate(2026, 1, 2));
  Check(TDAIUsage.LastActivityTick >= LBefore, 'Consecutive activity ticks never decrease');
  Check(ReadCount('2026_01', 'file_read') = 2, 'Each call counts exactly once');
  TDAIUsage.ResetActivity;
  Check(TDAIUsage.LastActivityTick = 0, 'Reset clears activity');
  Check(ReadCount('2026_01', 'file_read') = 2, 'Reset preserves persistent counters');
  TDAIUsage.TestRecordToolCallAt('', True, EncodeDate(2026, 1, 1));
  TDAIUsage.TestRecordToolCallAt('FILE_READ', True, EncodeDate(2026, 1, 1));
  TDAIUsage.TestRecordToolCallAt('file\read', True, EncodeDate(2026, 1, 1));
  TDAIUsage.TestRecordToolCallAt('file/read', True, EncodeDate(2026, 1, 1));
  TDAIUsage.TestRecordToolCallAt('file read', True, EncodeDate(2026, 1, 1));
  TDAIUsage.TestRecordToolCallAt('1tool', True, EncodeDate(2026, 1, 1));
  TDAIUsage.TestRecordToolCallAt(StringOfChar('a', 97), True, EncodeDate(2026, 1, 1));
  Check(TDAIUsage.LastActivityTick = 0, 'Rejected names cannot activate icon');
  LRegistry := OpenMonth('2026_01');
  try
    Check(not LRegistry.ValueExists('file\read'), 'Invalid path-like tool name is not stored');
    Check(not LRegistry.ValueExists(StringOfChar('a', 97)), 'Oversized tool name is not stored');
  finally
    LRegistry.Free;
  end;
  TDAIUsage.RecordToolCall('current_month', False);
  Check(ReadCount(FormatDateTime('yyyy_mm', Date), 'current_month') = 1, 'Production entry point uses the local calendar month');
end;

procedure CheckMalformedCounters;
var
  LRegistry: TRegistry;
  LBinary: Word;
begin
  LRegistry := OpenMonth('2026_10');
  try
    LRegistry.WriteString('wrong_type', 'keep me');
    LBinary := 7;
    Check(RegSetValueEx(LRegistry.CurrentKey, 'wrong_size', 0, REG_QWORD, @LBinary, SizeOf(LBinary)) = ERROR_SUCCESS,
      'Seed malformed REG_QWORD size');
  finally
    LRegistry.Free;
  end;
  SeedQWord('negative_count', High(UInt64));
  SeedQWord('saturated_count', UInt64(High(Int64)));
  SeedQWord('last_increment', UInt64(High(Int64)) - 1);
  TDAIUsage.TestRecordToolCallAt('wrong_type', True, EncodeDate(2026, 10, 1));
  TDAIUsage.TestRecordToolCallAt('wrong_size', True, EncodeDate(2026, 10, 1));
  TDAIUsage.TestRecordToolCallAt('negative_count', True, EncodeDate(2026, 10, 1));
  TDAIUsage.TestRecordToolCallAt('saturated_count', True, EncodeDate(2026, 10, 1));
  TDAIUsage.TestRecordToolCallAt('last_increment', True, EncodeDate(2026, 10, 1));
  TDAIUsage.TestRecordToolCallAt('last_increment', True, EncodeDate(2026, 10, 1));
  LRegistry := OpenMonth('2026_10');
  try
    Check(LRegistry.ReadString('wrong_type') = 'keep me', 'Unknown registry type remains intact');
    Check(LRegistry.GetDataSize('wrong_size') = SizeOf(LBinary), 'Malformed size remains intact');
  finally
    LRegistry.Free;
  end;
  Check(ReadCount('2026_10', 'negative_count') = High(UInt64), 'Out-of-range count remains intact without raising');
  Check(ReadCount('2026_10', 'saturated_count') = UInt64(High(Int64)), 'Maximum counter saturates');
  Check(ReadCount('2026_10', 'last_increment') = UInt64(High(Int64)), 'Last valid increment cannot overflow');
end;

procedure CheckConcurrency;
var
  LThreads: array[0..CThreadCount - 1] of TCounterThread;
  LIndex: Integer;
begin
  for LIndex := Low(LThreads) to High(LThreads) do
    LThreads[LIndex] := TCounterThread.Create('parallel_calls', CCallsPerThread);
  try
    for LIndex := Low(LThreads) to High(LThreads) do
      LThreads[LIndex].Start;
    for LIndex := Low(LThreads) to High(LThreads) do
    begin
      LThreads[LIndex].WaitFor;
      Check(not Assigned(LThreads[LIndex].FatalException), 'Parallel thread completes without error');
    end;
    Check(ReadCount('2026_10', 'parallel_calls') = CThreadCount * CCallsPerThread, 'Parallel calls do not lose increments');
  finally
    for LIndex := Low(LThreads) to High(LThreads) do
      LThreads[LIndex].Free;
  end;
end;

procedure CheckMutexTimeout;
var
  LThread: TMutexThread;
  LStarted: UInt64;
  LRegistry: TRegistry;
begin
  LThread := TMutexThread.Create;
  try
    LThread.Start;
    Check(LThread.FReady.WaitFor(5000) = wrSignaled, 'Mutex holder starts');
    Check(LThread.FAcquired, 'Other thread owns the shared mutex');
    TDAIUsage.ResetActivity;
    LStarted := GetTickCount64;
    TDAIUsage.TestRecordToolCallAt('blocked_counter', True, EncodeDate(2026, 10, 1));
    Check(GetTickCount64 - LStarted < 1000, 'Statistics mutex wait is bounded');
    Check(TDAIUsage.LastActivityTick > 0, 'Counter failure does not suppress activity');
    LRegistry := OpenMonth('2026_10');
    try
      Check(not LRegistry.ValueExists('blocked_counter'), 'Contended counter is skipped safely');
    finally
      LRegistry.Free;
    end;
  finally
    LThread.Free;
  end;
end;

procedure Run;
var
  LIndex: Integer;
begin
  if ParamStr(1) = 'increment' then
  begin
    for LIndex := 1 to 300 do
      TDAIUsage.TestRecordToolCallAt('cross_process', False, EncodeDate(2026, 10, 1));
    Exit;
  end;
  if ParamStr(1) = 'check' then
  begin
    Check(ReadCount('2026_10', 'cross_process') = StrToInt(ParamStr(2)), 'Processes and architectures share exact counter');
    Exit;
  end;
  Check(ParamCount = 0, 'Only known test scenarios are accepted');
  CheckMonthsAndActivity;
  CheckMalformedCounters;
  CheckConcurrency;
  CheckMutexTimeout;
end;

begin
  try
    Run;
    Writeln('Usage tests passed: ', CheckCount, ' checks.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
