unit h5u.DAI.OTA.Debugger;

interface

uses
  System.JSON;

type
  TDAIDebuggerService = class sealed
  public
    class function Status: TJSONObject; static;
    class function Breakpoints: TJSONArray; static;
    class function SetBreakpoint(const AFileName: string; const ALine: Integer; const AEnabled: Boolean; const ACondition: string; const APassCount: Integer): TJSONObject; static;
    class function RemoveBreakpoint(const AFileName: string; const ALine: Integer): TJSONObject; static;
    class function Control(const AAction: string): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings,
  h5u.DAI.Types;

function DebuggerServices: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
    raise EInvalidOperation.Create('IOTADebuggerServices ist nicht verfügbar.');
end;

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

function StoppedProcess(const AProcess: IOTAProcess): Boolean;
begin
  Result := Assigned(AProcess) and (AProcess.ProcessState in [psStopped, psFault, psResFault, psException]);
end;

function BreakpointFileName(const AFileName: string; const ALine: Integer): string;
begin
  if ALine < 1 then
    raise EArgumentException.Create('Die Haltepunktzeile muss mindestens 1 sein.');
  if Trim(AFileName) = '' then
    raise EArgumentException.Create('Eine Quelldatei ist erforderlich.');
  Result := TDAISettings.Instance.ExpandPath(AFileName);
  if not TDAIOTA.IsWorkspaceFile(Result) then
    raise EDAIAccessDenied.Create('Quellhaltepunkte können nur für Workspace-Dateien geändert werden.');
end;

function FindBreakpoint(const ADebugger: IOTADebuggerServices; const AFileName: string; const ALine: Integer): IOTASourceBreakpoint;
var
  LIndex: Integer;
  LBreakpoint: IOTASourceBreakpoint;
begin
  Result := nil;
  for LIndex := 0 to ADebugger.SourceBkptCount - 1 do
  begin
    LBreakpoint := ADebugger.SourceBkpts[LIndex];
    if Assigned(LBreakpoint) and (LBreakpoint.LineNumber = ALine) and TDAIOTA.SameFile(LBreakpoint.FileName, AFileName) then
      Exit(LBreakpoint);
  end;
end;

function BreakpointJson(const ABreakpoint: IOTABreakpoint; const ADebugger: IOTADebuggerServices): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('file', ABreakpoint.FileName);
    Result.AddPair('line', TJSONNumber.Create(ABreakpoint.LineNumber));
    Result.AddPair('enabled', TJSONBool.Create(ABreakpoint.Enabled));
    Result.AddPair('condition', ABreakpoint.Expression);
    Result.AddPair('pass_count', TJSONNumber.Create(ABreakpoint.PassCount));
    Result.AddPair('current_pass_count', TJSONNumber.Create(ABreakpoint.CurPassCount));
    Result.AddPair('group', ABreakpoint.GroupName);
    if Assigned(ADebugger.CurrentProcess) then
      Result.AddPair('valid_in_current_process', TJSONBool.Create(ABreakpoint.ValidInCurrentProcess))
    else
      Result.AddPair('valid_in_current_process', TJSONNull.Create);
  except
    Result.Free;
    raise;
  end;
end;

function ProcessJson(const AProcess: IOTAProcess; const ACurrent: Boolean): TJSONObject;
var
  LThread: IOTAThread;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('process_id', TJSONNumber.Create(Int64(AProcess.OSProcessId)));
    Result.AddPair('debugger_process_id', TJSONNumber.Create(Int64(AProcess.ProcessId)));
    Result.AddPair('executable', AProcess.ExeName);
    Result.AddPair('state', ProcessStateName(AProcess.ProcessState));
    Result.AddPair('state_text', AProcess.State);
    Result.AddPair('status_text', AProcess.Status);
    Result.AddPair('current', TJSONBool.Create(ACurrent));
    Result.AddPair('thread_count', TJSONNumber.Create(AProcess.ThreadCount));
    LThread := AProcess.CurrentThread;
    if Assigned(LThread) then
    begin
      Result.AddPair('current_thread_id', TJSONNumber.Create(Int64(LThread.GetOSThreadID)));
      if StoppedProcess(AProcess) and (LThread.State = tsStopped) then
      begin
        Result.AddPair('current_file', LThread.CurrentFile);
        Result.AddPair('current_line', TJSONNumber.Create(Int64(LThread.CurrentLine)));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TDAIDebuggerService.Status: TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LCurrent: IOTAProcess;
        LDebugger: IOTADebuggerServices;
        LExpressions: TJSONObject;
        LIndex: Integer;
        LProcess: IOTAProcess;
        LProcesses: TJSONArray;
      begin
        if not Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
        begin
          LResult.AddPair('available', TJSONBool.Create(False));
          Exit;
        end;
        LResult.AddPair('available', TJSONBool.Create(True));
        LExpressions := TJSONObject.Create;
        LResult.AddPair('expression_capabilities', LExpressions);
        LExpressions.AddPair('evaluate', TJSONBool.Create(True));
        LExpressions.AddPair('modify', TJSONBool.Create(True));
        LExpressions.AddPair('cursor_expression', TJSONBool.Create(True));
        LExpressions.AddPair('native_add_watch', TJSONBool.Create(True));
        LExpressions.AddPair('native_watch_at_cursor', TJSONBool.Create(True));
        LExpressions.AddPair('native_evaluate_modify', TJSONBool.Create(True));
        LExpressions.AddPair('native_inspect_at_cursor', TJSONBool.Create(True));
        LExpressions.AddPair('watch_list_read', TJSONBool.Create(False));
        LExpressions.AddPair('watch_edit', TJSONBool.Create(False));
        LExpressions.AddPair('watch_delete', TJSONBool.Create(False));
        LExpressions.AddPair('scope', 'public_toolsapi');
        LCurrent := LDebugger.CurrentProcess;
        LResult.AddPair('has_current_process', TJSONBool.Create(Assigned(LCurrent)));
        LResult.AddPair('source_breakpoint_count', TJSONNumber.Create(LDebugger.SourceBkptCount));
        LResult.AddPair('address_breakpoint_count', TJSONNumber.Create(LDebugger.AddressBkptCount));
        LProcesses := TJSONArray.Create;
        LResult.AddPair('processes', LProcesses);
        for LIndex := 0 to LDebugger.ProcessCount - 1 do
        begin
          LProcess := LDebugger.Processes[LIndex];
          if Assigned(LProcess) then
            LProcesses.AddElement(ProcessJson(LProcess, LProcess = LCurrent));
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDebuggerService.Breakpoints: TJSONArray;
var
  LResult: TJSONArray;
begin
  LResult := TJSONArray.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LBreakpoint: IOTASourceBreakpoint;
        LDebugger: IOTADebuggerServices;
        LIndex: Integer;
      begin
        LDebugger := DebuggerServices;
        for LIndex := 0 to LDebugger.SourceBkptCount - 1 do
        begin
          LBreakpoint := LDebugger.SourceBkpts[LIndex];
          if Assigned(LBreakpoint) then
            LResult.AddElement(BreakpointJson(LBreakpoint, LDebugger));
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDebuggerService.SetBreakpoint(const AFileName: string; const ALine: Integer; const AEnabled: Boolean;
  const ACondition: string; const APassCount: Integer): TJSONObject;
var
  LFileName: string;
  LResult: TJSONObject;
begin
  LFileName := BreakpointFileName(AFileName, ALine);
  if APassCount < 0 then
    raise EArgumentException.Create('pass_count darf nicht negativ sein.');
  if not TFile.Exists(LFileName) and not TDAIOTA.IsFileOpenInEditor(LFileName) then
    raise EDAIFileNotFound.CreateFmt('Quelldatei nicht gefunden: %s', [LFileName]);
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LBreakpoint: IOTABreakpoint;
      LCreated: Boolean;
      LDebugger: IOTADebuggerServices;
    begin
      LDebugger := DebuggerServices;
      LBreakpoint := FindBreakpoint(LDebugger, LFileName, ALine);
      LCreated := not Assigned(LBreakpoint);
      if LCreated then
        LBreakpoint := LDebugger.NewSourceBreakpoint(LFileName, ALine, nil);
      if not Assigned(LBreakpoint) then
        raise EInvalidOperation.Create('Der Quellhaltepunkt konnte nicht erstellt werden.');
      try
        LBreakpoint.Enabled := AEnabled;
        LBreakpoint.Expression := ACondition;
        LBreakpoint.PassCount := APassCount;
        LResult := BreakpointJson(LBreakpoint, LDebugger);
        LResult.AddPair('created', TJSONBool.Create(LCreated));
      except
        if LCreated then
          LDebugger.RemoveBreakpoint(LBreakpoint);
        LResult.Free;
        LResult := nil;
        raise;
      end;
    end);
  Result := LResult;
end;

class function TDAIDebuggerService.RemoveBreakpoint(const AFileName: string; const ALine: Integer): TJSONObject;
var
  LFileName: string;
  LRemoved: Boolean;
begin
  LFileName := BreakpointFileName(AFileName, ALine);
  LRemoved := False;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LBreakpoint: IOTASourceBreakpoint;
      LDebugger: IOTADebuggerServices;
    begin
      LDebugger := DebuggerServices;
      LBreakpoint := FindBreakpoint(LDebugger, LFileName, ALine);
      if Assigned(LBreakpoint) then
      begin
        LDebugger.RemoveBreakpoint(LBreakpoint);
        LBreakpoint := nil;
        LRemoved := True;
      end;
    end);
  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('line', TJSONNumber.Create(ALine));
  Result.AddPair('removed', TJSONBool.Create(LRemoved));
end;

class function TDAIDebuggerService.Control(const AAction: string): TJSONObject;
var
  LAction: string;
  LResult: TJSONObject;
  LRunMode: TOTARunMode;
begin
  LAction := LowerCase(Trim(AAction));
  if LAction = 'continue' then
    LRunMode := ormRun
  else if LAction = 'step_into' then
    LRunMode := ormStmtStepInto
  else if LAction = 'step_over' then
    LRunMode := ormStmtStepOver
  else if LAction = 'step_out' then
    LRunMode := ormRunUntilReturn
  else if LAction = 'pause' then
    LRunMode := ormUnused
  else
    raise EArgumentException.Create('action muss pause, continue, step_into, step_over oder step_out sein.');

  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LDebugger: IOTADebuggerServices;
        LProcess: IOTAProcess;
        LState: TOTAProcessState;
        LThread: IOTAThread;
      begin
        LDebugger := DebuggerServices;
        LProcess := LDebugger.CurrentProcess;
        if not Assigned(LProcess) then
          raise EInvalidOperation.Create('Es gibt keinen aktuellen Debuggerprozess. Starten Sie zuerst project_run mit debugger=true.');
        LState := LProcess.ProcessState;
        if LAction = 'pause' then
        begin
          if LState <> psRunning then
            raise EInvalidOperation.Create('Pause ist nur bei laufendem Debuggerprozess möglich.');
        end
        else
        begin
          if not StoppedProcess(LProcess) then
            raise EInvalidOperation.Create('Fortsetzen und Schrittbefehle erfordern einen angehaltenen Debuggerprozess.');
          LThread := LProcess.CurrentThread;
          if not Assigned(LThread) or (LThread.State <> tsStopped) then
            raise EInvalidOperation.Create('Der aktuelle Debuggerthread ist nicht angehalten.');
        end;
        LResult.AddPair('action', LAction);
        LResult.AddPair('process_id', TJSONNumber.Create(Int64(LProcess.OSProcessId)));
        LResult.AddPair('state_before', ProcessStateName(LState));
        if LAction = 'pause' then
          LProcess.Pause
        else
          LProcess.Run(LRunMode);
        LResult.AddPair('requested', TJSONBool.Create(True));
        LResult.AddPair('completion_is_asynchronous', TJSONBool.Create(True));
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

end.
