program TestSessions;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  h5u.DAI.MCP.Sessions;

type
  TSessionWorker = class(TThread)
  private
    FStore: TDAIMCPSessions;
    FStart: TEvent;
    FAcquired: TEvent;
    FContinue: TEvent;
    FError: string;
    FCreateWon: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AStore: TDAIMCPSessions; const AStart, AContinue: TEvent);
    destructor Destroy; override;
    property Acquired: TEvent read FAcquired;
    property Error: string read FError;
    property CreateWon: Boolean read FCreateWon;
  end;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function NewSession: TDAIMCPSession;
begin
  Result.ClientName := 'Native session test';
  Result.ProtocolVersion := '2025-11-25';
end;

procedure TestExpiryAndTouch;
var
  LTick: UInt64;
  LStore: TDAIMCPSessions;
  LSession: TDAIMCPSession;
begin
  LTick := 1000;
  LStore := TDAIMCPSessions.Create(100, 2, function: UInt64 begin Result := LTick; end);
  try
    Check(LStore.Count = 0, 'initially empty');
    Check(not LStore.TryCreate('', NewSession), 'reject empty ID');
    Check(not LStore.TryCreate('  ', NewSession), 'reject whitespace ID');
    Check(LStore.TryCreate('a', NewSession), 'create a');
    Check(not LStore.TryCreate('a', NewSession), 'reject duplicate ID');
    LTick := 1050;
    Check(LStore.TryCreate('b', NewSession), 'create b');
    LTick := 1099;
    Check(LStore.TryAcquire('a', LSession), 'alive before timeout');
    Check((LSession.ClientName = NewSession.ClientName) and (LSession.ProtocolVersion = NewSession.ProtocolVersion), 'return complete snapshot');
    LStore.Release('a');
    LTick := 1150;
    Check(not LStore.TryAcquire('b', LSession), 'expires exactly at timeout');
    Check((LSession.ClientName = '') and (LSession.ProtocolVersion = ''), 'missing acquisition clears snapshot');
    Check(LStore.Count = 1, 'acquire sweeps expired sessions');
    LTick := 1198;
    Check(LStore.TryAcquire('a', LSession), 'release renews idle timeout');
    LStore.Release('a');
    LTick := 1298;
    Check(LStore.TryCreate('c', NewSession), 'creation sweeps expired sessions');
    Check(LStore.Count = 1, 'sweep preserves new session only');
    Check(not LStore.Remove('unknown'), 'remove unknown ID');
  finally
    LStore.Free;
  end;
end;

procedure TestActiveAndRemoval;
var
  LTick: UInt64;
  LStore: TDAIMCPSessions;
  LSession: TDAIMCPSession;
begin
  LTick := 0;
  LStore := TDAIMCPSessions.Create(100, 1, function: UInt64 begin Result := LTick; end);
  try
    Check(LStore.TryCreate('a', NewSession), 'create active test');
    Check(LStore.TryAcquire('a', LSession), 'first active request');
    Check(LStore.TryAcquire('a', LSession), 'second active request');
    LTick := 1000;
    Check(not LStore.TryCreate('b', NewSession), 'capacity rejection preserves active session');
    LStore.Release('a');
    Check(LStore.TryAcquire('a', LSession), 'one remaining request prevents expiry');
    LStore.Release('a');
    Check(LStore.Remove('a'), 'remove while one request is active');
    Check(LStore.Count = 0, 'removed session not counted');
    Check(not LStore.TryAcquire('a', LSession), 'removed session cannot be acquired');
    Check(not LStore.TryCreate('a', NewSession), 'no ID reuse until old request finishes');
    Check(not LStore.TryCreate('b', NewSession), 'retired request reserves capacity');
    LStore.Release('a');
    Check(LStore.TryCreate('a', NewSession), 'reuse allowed after release drains');
    LStore.Release('a');
    Check(LStore.Count = 1, 'unmatched release does not remove session');
    Check(LStore.TryAcquire('a', LSession), 'acquire before clear');
    LStore.Clear;
    Check(LStore.Count = 0, 'clear removes live sessions');
    LStore.Clear;
    Check(not LStore.TryCreate('a', NewSession), 'clear retains outstanding request protection');
    LStore.Release('a');
    Check(LStore.TryCreate('a', NewSession), 'clear drains without restoring old session');
    LStore.Clear;
    LStore.Release('a');
    Check(LStore.Count = 0, 'release never recreates missing session');
  finally
    LStore.Free;
  end;
end;

procedure TestCapacityAndClock;
var
  LTick: UInt64;
  LStore: TDAIMCPSessions;
  LSession: TDAIMCPSession;
begin
  LTick := 1000;
  LStore := TDAIMCPSessions.Create(100, 2, function: UInt64 begin Result := LTick; end);
  try
    Check(LStore.TryCreate('a', NewSession) and LStore.TryCreate('b', NewSession), 'fill capacity');
    Check(not LStore.TryCreate('c', NewSession), 'reject third session without clearing existing ones');
    Check(LStore.Count = 2, 'capacity preserves count');
    LTick := 900;
    Check(LStore.TryAcquire('a', LSession), 'backward test clock does not underflow');
    LStore.Release('a');
    LTick := 1050;
    Check(LStore.TryAcquire('a', LSession), 'backward clock never moves activity backward');
    LStore.Release('a');
    LTick := 1090;
    LStore.Release('a');
    LTick := 1150;
    Check(not LStore.TryAcquire('a', LSession), 'unmatched release does not extend idle timeout');
    Check(LStore.Count = 0, 'global sweep removes unrelated expired session');
    Check(LStore.TryCreate('c', NewSession), 'expired slots become available');
    Check(LStore.TryAcquire('c', LSession), 'acquire long-running request');
    LTick := 10000;
    LStore.Release('c');
    LTick := 10099;
    Check(LStore.TryAcquire('c', LSession), 'late release alone starts a new idle interval');
    LStore.Release('c');
  finally
    LStore.Free;
  end;
end;

constructor TSessionWorker.Create(const AStore: TDAIMCPSessions; const AStart, AContinue: TEvent);
begin
  inherited Create(True);
  FStore := AStore;
  FStart := AStart;
  FContinue := AContinue;
  FAcquired := TEvent.Create(nil, True, False, '');
end;

destructor TSessionWorker.Destroy;
begin
  inherited;
  FAcquired.Free;
end;

procedure TSessionWorker.Execute;
var
  LSession: TDAIMCPSession;
  I: Integer;
begin
  try
    if FStart.WaitFor(10000) <> wrSignaled then
      raise Exception.Create('start gate timeout');
    FCreateWon := FStore.TryCreate('parallel', NewSession);
    if not FStore.TryAcquire('parallel', LSession) then
      raise Exception.Create('parallel acquire failed');
    FAcquired.SetEvent;
    try
      if FContinue.WaitFor(10000) <> wrSignaled then
        raise Exception.Create('continue gate timeout');
    finally
      FStore.Release('parallel');
    end;
    for I := 1 to 1000 do
    begin
      if not FStore.TryAcquire('parallel', LSession) then
        raise Exception.Create('repeated parallel acquire failed');
      try
        if LSession.ClientName <> NewSession.ClientName then
          raise Exception.Create('parallel snapshot mismatch');
      finally
        FStore.Release('parallel');
      end;
    end;
  except
    on E: Exception do
    begin
      FError := E.Message;
      FAcquired.SetEvent;
    end;
  end;
end;

procedure TestParallel;
const
  CWorkerCount = 8;
var
  LTick: UInt64;
  LStore: TDAIMCPSessions;
  LStart, LContinue: TEvent;
  LWorkers: array[0..CWorkerCount - 1] of TSessionWorker;
  LSession: TDAIMCPSession;
  I, LWinners: Integer;
begin
  LTick := 0;
  LStore := TDAIMCPSessions.Create(100, 1, function: UInt64 begin Result := LTick; end);
  LStart := TEvent.Create(nil, True, False, '');
  LContinue := TEvent.Create(nil, True, False, '');
  FillChar(LWorkers, SizeOf(LWorkers), 0);
  try
    for I := Low(LWorkers) to High(LWorkers) do
    begin
      LWorkers[I] := TSessionWorker.Create(LStore, LStart, LContinue);
      LWorkers[I].Start;
    end;
    LStart.SetEvent;
    for I := Low(LWorkers) to High(LWorkers) do
      Check(LWorkers[I].Acquired.WaitFor(10000) = wrSignaled, 'parallel acquisition gate');
    // Every worker is paused with an acquired lease; this tick write is synchronized by the gates.
    LTick := 1000;
    Check(not LStore.TryCreate('overflow', NewSession), 'parallel active requests survive timeout and capacity rejection');
    Check(LStore.TryAcquire('parallel', LSession), 'parallel session remains present');
    LStore.Release('parallel');
    LContinue.SetEvent;
    LWinners := 0;
    for I := Low(LWorkers) to High(LWorkers) do
    begin
      LWorkers[I].WaitFor;
      Check(LWorkers[I].Error = '', 'parallel worker completed: ' + LWorkers[I].Error);
      if LWorkers[I].CreateWon then
        Inc(LWinners);
    end;
    Check(LWinners = 1, 'exactly one concurrent create wins');
    Check(LStore.Count = 1, '8000 parallel request cycles preserve session');
    LTick := 1100;
    Check(not LStore.TryAcquire('parallel', LSession), 'all parallel leases released, allowing expiry');
  finally
    LStart.SetEvent;
    LContinue.SetEvent;
    for I := Low(LWorkers) to High(LWorkers) do
      LWorkers[I].Free;
    LContinue.Free;
    LStart.Free;
    LStore.Free;
  end;
end;

procedure TestDefaultsAndValidation;
var
  LStore: TDAIMCPSessions;
  LTick: UInt64;
  LSession: TDAIMCPSession;
  I: Integer;
begin
  LStore := TDAIMCPSessions.Create;
  try
    Check(LStore.TryCreate('real-clock', NewSession), 'default monotonic clock works');
    Check(LStore.TryAcquire('real-clock', LSession), 'default timeout permits immediate acquire');
    LStore.Release('real-clock');
  finally
    LStore.Free;
  end;
  LTick := 0;
  LStore := TDAIMCPSessions.Create(CDAIMCPSessionIdleTimeoutMs, CDAIMCPMaximumSessions, function: UInt64 begin Result := LTick; end);
  try
    for I := 1 to CDAIMCPMaximumSessions do
      if not LStore.TryCreate(IntToStr(I), NewSession) then
        raise Exception.Create('default capacity lower than 1024');
    Check(not LStore.TryCreate('overflow', NewSession), 'default capacity is exactly 1024');
    LTick := 1800000;
    Check(not LStore.TryAcquire('1', LSession) and (LStore.Count = 0), 'default idle timeout is exactly 30 minutes');
  finally
    LStore.Free;
  end;
  try
    LStore := TDAIMCPSessions.Create(0);
    LStore.Free;
    Check(False, 'zero timeout rejected');
  except
    on E: EArgumentOutOfRangeException do Check(True, 'zero timeout rejected');
  end;
  try
    LStore := TDAIMCPSessions.Create(100, 0);
    LStore.Free;
    Check(False, 'zero capacity rejected');
  except
    on E: EArgumentOutOfRangeException do Check(True, 'zero capacity rejected');
  end;
end;

begin
  try
    TestExpiryAndTouch;
    TestActiveAndRemoval;
    TestCapacityAndClock;
    TestParallel;
    TestDefaultsAndValidation;
    Writeln('PASS: ', CheckCount, ' native session checks; 8 workers, 8000 parallel request cycles.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
