unit h5u.DAI.OTA.Stack;

interface

uses
  System.JSON;

type
  TDAIStackService = class sealed
  public
    class function Read(const AProcessId: Cardinal = 0; const AThreadId: Cardinal = 0; const AMaximumFrames: Integer = 50;
      const AMaximumCharacters: Integer = 20000): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.OTA.Helpers;

function ProcessStateName(const AState: TOTAProcessState): string;
begin
  case AState of
    psNothing: Result := 'nothing';
    psRunning: Result := 'running';
    psStopping: Result := 'stopping';
    psStopped: Result := 'stopped';
    psFault: Result := 'fault';
    psResFault: Result := 'resource_fault';
    psTerminated: Result := 'terminated';
    psException: Result := 'exception';
    psNoProcess: Result := 'no_process';
  else
    Result := 'unknown';
  end;
end;

function ThreadStateName(const AState: TOTAThreadState): string;
begin
  case AState of
    tsStopped: Result := 'stopped';
    tsRunnable: Result := 'runnable';
    tsBlocked: Result := 'blocked';
    tsNone: Result := 'none';
    tsOther: Result := 'other';
  else
    Result := 'unknown';
  end;
end;

procedure Unavailable(const AResult: TJSONObject; const ACode, AReason: string; const ARetryable: Boolean = False);
begin
  AResult.AddPair('available', TJSONBool.Create(False));
  AResult.AddPair('reason_code', ACode);
  AResult.AddPair('reason', AReason);
  AResult.AddPair('retryable', TJSONBool.Create(ARetryable));
end;

function BoundedText(const AText: string; var ABudget: Integer; var ATruncated: Boolean): string;
var
  LCount: Integer;
begin
  LCount := Length(AText);
  if LCount > ABudget then
  begin
    LCount := ABudget;
    // Do not return the first half of a UTF-16 surrogate pair at the budget boundary.
    if LCount > 0 then
      if (Ord(AText[LCount]) >= $D800) and (Ord(AText[LCount]) <= $DBFF) then
        Dec(LCount);
    ATruncated := True;
  end;
  Result := Copy(AText, 1, LCount);
  Dec(ABudget, LCount);
end;

function FrameJson(const AThread: IOTAThread; const ASimpleThread: IOTAThread110; const AIndex: Integer; var ABudget: Integer; var ATruncated: Boolean): TJSONObject;
var
  LFileName: string;
  LLine: Integer;
  LTruncated: Boolean;
begin
  Result := TJSONObject.Create;
  try
    LTruncated := False;
    // ToolsAPI requires GetCallCount first; the caller also acquired call-stack access.
    AThread.GetCallPos(AIndex, LFileName, LLine);
    Result.AddPair('index', TJSONNumber.Create(AIndex));
    Result.AddPair('filename', BoundedText(LFileName, ABudget, LTruncated));
    Result.AddPair('line', TJSONNumber.Create(LLine));
    Result.AddPair('source_info_available', TJSONBool.Create((LFileName <> '') and (LLine > 0)));
    if ABudget > 0 then
      Result.AddPair('header', BoundedText(AThread.GetCallHeader(AIndex), ABudget, LTruncated))
    else
    begin
      Result.AddPair('header', '');
      LTruncated := True;
    end;
    if Assigned(ASimpleThread) then
    begin
      if ABudget > 0 then
        Result.AddPair('function', BoundedText(ASimpleThread.GetSimpleCallHeader(AIndex), ABudget, LTruncated))
      else
      begin
        Result.AddPair('function', TJSONNull.Create);
        LTruncated := True;
      end;
    end
    else
      Result.AddPair('function', TJSONNull.Create);
    // The public per-frame getters expose neither a module nor an instruction address.
    Result.AddPair('module', TJSONNull.Create);
    Result.AddPair('address', TJSONNull.Create);
    Result.AddPair('fields_truncated', TJSONBool.Create(LTruncated));
    ATruncated := ATruncated or LTruncated;
  except
    Result.Free;
    raise;
  end;
end;

class function TDAIStackService.Read(const AProcessId: Cardinal; const AThreadId: Cardinal; const AMaximumFrames: Integer; const AMaximumCharacters: Integer): TJSONObject;
var
  LResult: TJSONObject;
begin
  if (AMaximumFrames < 1) or (AMaximumFrames > 500) then
    raise EArgumentOutOfRangeException.Create('Der Parameter "maximum_frames" muss zwischen 1 und 500 liegen.');
  if (AMaximumCharacters < 1) or (AMaximumCharacters > 200000) then
    raise EArgumentOutOfRangeException.Create('Der Parameter "maximum_characters" muss zwischen 1 und 200000 liegen.');
  LResult := TJSONObject.Create;
  try
    LResult.AddPair('maximum_frames', TJSONNumber.Create(AMaximumFrames));
    LResult.AddPair('maximum_characters', TJSONNumber.Create(AMaximumCharacters));
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LAccess: TOTACallStackState;
        LBudget: Integer;
        LCount: Integer;
        LDebugger: IOTADebuggerServices;
        LFrames: TJSONArray;
        LIndex: Integer;
        LLimit: Integer;
        LOwner: IOTAProcess;
        LProcess: IOTAProcess;
        LProcessState: TOTAProcessState;
        LSimpleThread: IOTAThread110;
        LThread: IOTAThread;
        LThreadState: TOTAThreadState;
        LTruncated: Boolean;
      begin
        LFrames := TJSONArray.Create;
        LResult.AddPair('frames', LFrames);
        if not Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
        begin
          Unavailable(LResult, 'debugger_unavailable', 'IOTADebuggerServices ist nicht verfügbar.');
          Exit;
        end;
        LProcess := nil;
        if AProcessId = 0 then
          LProcess := LDebugger.CurrentProcess
        else
          for LIndex := 0 to LDebugger.ProcessCount - 1 do
          begin
            LProcess := LDebugger.Processes[LIndex];
            if Assigned(LProcess) then
              if LProcess.OSProcessId = AProcessId then
                Break;
            LProcess := nil;
          end;
        if not Assigned(LProcess) then
        begin
          if AProcessId = 0 then
            Unavailable(LResult, 'no_current_process', 'Es gibt keinen aktuellen Debug-Prozess.')
          else
            Unavailable(LResult, 'process_not_found', 'Die OS-Prozess-ID gehört nicht zu den gedebuggten Prozessen.');
          Exit;
        end;
        LProcessState := LProcess.ProcessState;
        LResult.AddPair('process_id', TJSONNumber.Create(Int64(LProcess.OSProcessId)));
        LResult.AddPair('debugger_process_id', TJSONNumber.Create(Int64(LProcess.ProcessId)));
        LResult.AddPair('process_state', ProcessStateName(LProcessState));
        LThread := nil;
        if AThreadId = 0 then
          LThread := LProcess.CurrentThread
        else
          for LIndex := 0 to LProcess.ThreadCount - 1 do
          begin
            LThread := LProcess.Threads[LIndex];
            if Assigned(LThread) then
              if LThread.GetOSThreadID = AThreadId then
                Break;
            LThread := nil;
          end;
        if not Assigned(LThread) then
        begin
          if AThreadId = 0 then
            Unavailable(LResult, 'no_current_thread', 'Es gibt keinen aktuellen Debug-Thread.')
          else
            Unavailable(LResult, 'thread_not_found', 'Die OS-Thread-ID gehört nicht zum ausgewählten Debug-Prozess.');
          Exit;
        end;
        LThreadState := LThread.State;
        LResult.AddPair('thread_id', TJSONNumber.Create(Int64(LThread.GetOSThreadID)));
        LResult.AddPair('thread_state', ThreadStateName(LThreadState));
        LResult.AddPair('suspended', TJSONBool.Create((LProcessState in [psStopped, psFault, psResFault, psException]) and
          (LThreadState = tsStopped)));
        LOwner := LThread.OwningProcess;
        if not Assigned(LOwner) then
        begin
          Unavailable(LResult, 'thread_owner_unavailable', 'Der Debug-Prozess des Threads ist nicht verfügbar.');
          Exit;
        end;
        if (LOwner.OSProcessId <> LProcess.OSProcessId) or (LOwner.ProcessId <> LProcess.ProcessId) then
        begin
          Unavailable(LResult, 'thread_process_mismatch', 'Der Thread gehört nicht zum ausgewählten Debug-Prozess.');
          Exit;
        end;
        if not (LProcessState in [psStopped, psFault, psResFault, psException]) then
        begin
          Unavailable(LResult, 'process_not_stopped', 'Der Debug-Prozess ist nicht angehalten.');
          Exit;
        end;
        if LThreadState <> tsStopped then
        begin
          Unavailable(LResult, 'thread_not_stopped', 'Der Debug-Thread ist nicht angehalten.');
          Exit;
        end;
        LAccess := LThread.StartCallStackAccess;
        try
          case LAccess of
            csInaccessible:
              begin
                Unavailable(LResult, 'call_stack_inaccessible', 'Der Callstack ist nicht zugänglich.');
                Exit;
              end;
            csWait:
              begin
                Unavailable(LResult, 'call_stack_wait', 'Der Callstack ist noch nicht bereit. Die Abfrage kann wiederholt werden.', True);
                Exit;
              end;
            csAccessible: ;
          else
            raise EInvalidOperation.Create('Die ToolsAPI lieferte einen unbekannten Callstack-Zustand.');
          end;
          // GetCallCount must precede every indexed call-stack getter (ToolsAPI.pas).
          LCount := LThread.GetCallCount;
          if LCount < 0 then
            raise EInvalidOperation.Create('Die ToolsAPI lieferte eine ungültige Callstack-Länge.');
          Supports(LThread, IOTAThread110, LSimpleThread);
          LLimit := LCount;
          if LLimit > AMaximumFrames then
            LLimit := AMaximumFrames;
          LBudget := AMaximumCharacters;
          LTruncated := False;
          for LIndex := 1 to LLimit do
          begin
            if LBudget <= 0 then
              Break;
            LFrames.AddElement(FrameJson(LThread, LSimpleThread, LIndex, LBudget, LTruncated));
          end;
          LResult.AddPair('available', TJSONBool.Create(True));
          LResult.AddPair('retryable', TJSONBool.Create(False));
          LResult.AddPair('total_frames', TJSONNumber.Create(LCount));
          LResult.AddPair('frame_count', TJSONNumber.Create(LFrames.Count));
          LResult.AddPair('characters_returned', TJSONNumber.Create(AMaximumCharacters - LBudget));
          LResult.AddPair('truncated', TJSONBool.Create(LTruncated or (LFrames.Count < LCount)));
        finally
          LThread.EndCallStackAccess;
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

end.
