unit h5u.DAI.OTA.Threads;

interface

uses
  System.JSON;

type
  TDAIThreadService = class sealed
  public
    class function List(const AProcessId: Cardinal = 0; const AAllProcesses: Boolean = False; const AMaximumThreads: Integer = 200): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.OTA.Helpers;

const
  CMaximumThreads = 5000;

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

function ThreadJson(const AThread: IOTAThread; const ACurrentThread: IOTAThread; const AProcessId, ADebuggerProcessId: Cardinal;
  const ACurrentProcess: Boolean; const AProcessState: TOTAProcessState): TJSONObject;
var
  LDisplay: string;
  LDisplayAvailable: Boolean;
  LDisplayReason: string;
  LFile: string;
  LLine: Cardinal;
  LName: string;
  LNameAvailable: Boolean;
  LNameReason: string;
  LSourceAvailable: Boolean;
  LSourceReason: string;
  LState: TOTAThreadState;
  LThread90: IOTAThread90;
  LThread140: IOTAThread140;
  LThreadId: Cardinal;
begin
  LThreadId := AThread.GetOSThreadID;
  LState := AThread.State;
  LName := '';
  LNameAvailable := False;
  LNameReason := 'Der Debuggeranbieter unterstützt IOTAThread140 für Threadnamen nicht.';
  if Supports(AThread, IOTAThread140, LThread140) then
    try
      LName := LThread140.GetThreadName;
      LNameAvailable := True;
      LNameReason := '';
    except
      on E: Exception do
        LNameReason := E.ClassName + ': ' + E.Message;
    end;
  LDisplay := UIntToStr(LThreadId);
  LDisplayAvailable := False;
  LDisplayReason := 'Der Debuggeranbieter unterstützt IOTAThread90 für die Threadanzeige nicht.';
  if Supports(AThread, IOTAThread90, LThread90) then
    try
      LDisplay := LThread90.GetDisplayString;
      if LDisplay = '' then
        LDisplay := UIntToStr(LThreadId);
      LDisplayAvailable := True;
      LDisplayReason := '';
    except
      on E: Exception do
        LDisplayReason := E.ClassName + ': ' + E.Message;
    end;
  LFile := '';
  LLine := 0;
  LSourceAvailable := False;
  LSourceReason := 'Quellpositionen werden nur für gestoppte Prozesse und gestoppte Threads gelesen.';
  if AProcessState in [psStopped, psFault, psResFault, psException] then
    if LState = tsStopped then
      try
        LFile := AThread.CurrentFile;
        LLine := AThread.CurrentLine;
        LSourceAvailable := (LFile <> '') and (LLine > 0);
        if LSourceAvailable then
          LSourceReason := ''
        else
          LSourceReason := 'Für diese Threadposition ist keine Quellposition mit Debuginformationen verfügbar.';
      except
        on E: Exception do
        begin
          LFile := '';
          LLine := 0;
          LSourceReason := E.ClassName + ': ' + E.Message;
        end;
      end;
  Result := TJSONObject.Create;
  try
    Result.AddPair('process_id', TJSONNumber.Create(Int64(AProcessId)));
    Result.AddPair('debugger_process_id', TJSONNumber.Create(Int64(ADebuggerProcessId)));
    Result.AddPair('thread_id', TJSONNumber.Create(Int64(LThreadId)));
    Result.AddPair('state', ThreadStateName(LState));
    Result.AddPair('current', TJSONBool.Create(AThread = ACurrentThread));
    Result.AddPair('current_process', TJSONBool.Create(ACurrentProcess));
    Result.AddPair('name_available', TJSONBool.Create(LNameAvailable));
    if LNameAvailable then
      Result.AddPair('name', LName)
    else
      Result.AddPair('name', TJSONNull.Create);
    Result.AddPair('name_reason', LNameReason);
    Result.AddPair('display_string', LDisplay);
    Result.AddPair('display_string_available', TJSONBool.Create(LDisplayAvailable));
    Result.AddPair('display_string_reason', LDisplayReason);
    Result.AddPair('source_available', TJSONBool.Create(LSourceAvailable));
    if LSourceAvailable then
    begin
      Result.AddPair('source_file', LFile);
      Result.AddPair('source_line', TJSONNumber.Create(Int64(LLine)));
    end
    else
    begin
      Result.AddPair('source_file', TJSONNull.Create);
      Result.AddPair('source_line', TJSONNull.Create);
    end;
    Result.AddPair('source_reason', LSourceReason);
  except
    Result.Free;
    raise;
  end;
end;

class function TDAIThreadService.List(const AProcessId: Cardinal; const AAllProcesses: Boolean; const AMaximumThreads: Integer): TJSONObject;
var
  LResult: TJSONObject;
begin
  if AAllProcesses and (AProcessId <> 0) then
    raise EArgumentException.Create('process_id und all_processes=true können nicht gemeinsam verwendet werden.');
  if (AMaximumThreads < 1) or (AMaximumThreads > CMaximumThreads) then
    raise EArgumentOutOfRangeException.CreateFmt('maximum_threads muss zwischen 1 und %d liegen.', [CMaximumThreads]);
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LCurrentProcess: IOTAProcess;
        LCurrentThread: IOTAThread;
        LDebugger: IOTADebuggerServices;
        LDebuggerCount: Integer;
        LDebuggerProcessId: Cardinal;
        LFound: Boolean;
        LIndex: Integer;
        LOSProcessId: Cardinal;
        LProcess: IOTAProcess;
        LProcessCount: Integer;
        LProcessItem: TJSONObject;
        LProcesses: TJSONArray;
        LProcessState: TOTAProcessState;
        LReason: string;
        LSelected: TList<IOTAProcess>;
        LThread: IOTAThread;
        LThreadCount: Integer;
        LThreadIndex: Integer;
        LThreads: TJSONArray;
        LThreadTotal: Int64;
      begin
        LThreads := TJSONArray.Create;
        LResult.AddPair('threads', LThreads);
        LProcesses := TJSONArray.Create;
        LResult.AddPair('processes', LProcesses);
        LResult.AddPair('requested_process_id', TJSONNumber.Create(Int64(AProcessId)));
        LResult.AddPair('all_processes', TJSONBool.Create(AAllProcesses));
        LResult.AddPair('maximum_threads', TJSONNumber.Create(AMaximumThreads));
        LDebuggerCount := 0;
        LThreadTotal := 0;
        LProcessCount := 0;
        LReason := '';
        LFound := Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger);
        if not LFound then
          LReason := 'IOTADebuggerServices ist nicht verfügbar.'
        else
        begin
          LDebuggerCount := LDebugger.ProcessCount;
          if LDebuggerCount < 0 then
            raise EInvalidOperation.Create('Der Debuggeranbieter liefert eine ungültige Prozessanzahl.');
          LCurrentProcess := LDebugger.CurrentProcess;
          LSelected := TList<IOTAProcess>.Create;
          try
            if not AAllProcesses and (AProcessId = 0) then
            begin
              if Assigned(LCurrentProcess) then
                LSelected.Add(LCurrentProcess)
              else
                LReason := 'Es ist kein aktueller Debuggerprozess ausgewählt.';
            end
            else
              for LIndex := 0 to LDebuggerCount - 1 do
              begin
                LProcess := LDebugger.Processes[LIndex];
                if Assigned(LProcess) then
                  if AAllProcesses or (LProcess.OSProcessId = AProcessId) then
                    LSelected.Add(LProcess);
              end;
            if (AProcessId <> 0) and (LSelected.Count > 1) then
              raise EInvalidOperation.Create('Die angeforderte OS-Prozess-ID ist in der Debuggerliste nicht eindeutig.');
            if (LSelected.Count = 0) and (LReason = '') then
              if AProcessId <> 0 then
                LReason := Format('Der Debugger verwaltet keinen Prozess mit der OS-Prozess-ID %s.', [UIntToStr(AProcessId)])
              else
                LReason := 'Der Debugger verwaltet derzeit keine Prozesse.';
            for LProcess in LSelected do
            begin
              LOSProcessId := LProcess.OSProcessId;
              LDebuggerProcessId := LProcess.ProcessId;
              LProcessState := LProcess.ProcessState;
              LThreadCount := LProcess.ThreadCount;
              if LThreadCount < 0 then
                raise EInvalidOperation.Create('Der Debuggeranbieter liefert eine ungültige Threadanzahl.');
              Inc(LThreadTotal, LThreadCount);
              Inc(LProcessCount);
              LProcessItem := TJSONObject.Create;
              LProcesses.AddElement(LProcessItem);
              LProcessItem.AddPair('process_id', TJSONNumber.Create(Int64(LOSProcessId)));
              LProcessItem.AddPair('debugger_process_id', TJSONNumber.Create(Int64(LDebuggerProcessId)));
              LProcessItem.AddPair('state', ProcessStateName(LProcessState));
              LProcessItem.AddPair('current', TJSONBool.Create(LProcess = LCurrentProcess));
              LProcessItem.AddPair('thread_count', TJSONNumber.Create(LThreadCount));
              if LThreads.Count >= AMaximumThreads then
                Continue;
              LCurrentThread := LProcess.CurrentThread;
              for LThreadIndex := 0 to LThreadCount - 1 do
              begin
                if LThreads.Count >= AMaximumThreads then
                  Break;
                LThread := LProcess.Threads[LThreadIndex];
                if Assigned(LThread) then
                  LThreads.AddElement(ThreadJson(LThread, LCurrentThread, LOSProcessId, LDebuggerProcessId,
                    LProcess = LCurrentProcess, LProcessState));
              end;
              LThread := nil;
              LCurrentThread := nil;
            end;
          finally
            // All OTA interfaces, including the selected process collection,
            // are released here on the IDE thread before returning JSON only.
            LSelected.Free;
            LProcess := nil;
            LThread := nil;
            LCurrentThread := nil;
            LCurrentProcess := nil;
            LDebugger := nil;
          end;
        end;
        LResult.AddPair('available', TJSONBool.Create(LFound and (LProcessCount > 0)));
        LResult.AddPair('debugger_available', TJSONBool.Create(LFound));
        LResult.AddPair('debugger_process_count', TJSONNumber.Create(LDebuggerCount));
        LResult.AddPair('process_count', TJSONNumber.Create(LProcessCount));
        LResult.AddPair('thread_total', TJSONNumber.Create(LThreadTotal));
        LResult.AddPair('returned_count', TJSONNumber.Create(LThreads.Count));
        LResult.AddPair('truncated', TJSONBool.Create(Int64(LThreads.Count) < LThreadTotal));
        LResult.AddPair('reason', LReason);
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

end.
