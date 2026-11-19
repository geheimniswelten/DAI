unit h5u.DAI.OTA.Debugger;

interface

uses
  System.JSON;

type
  TDAIDebuggerService = class sealed
  public
    class function Status: TJSONObject; static;
    class function Processes(const ARemoteHost: string; const AMaximumProcesses: Integer): TJSONObject; static;
    class function LoadProcess(const AExecutable, AArguments, ARemoteHost: string): TJSONObject; static;
    class function AttachProcess(const AProcessId: Integer; const APauseAfterAttach, ADetachOnReset: Boolean; const ARemoteHost: string): TJSONObject; static;
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
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings,
  h5u.DAI.Types;

const
  CMaximumProcessResults = 1000;
  CMaximumProcessTextLength = 32767;
  CMaximumRemoteHostLength = 1024;
  CCurrentDebuggerSelection = 'current_ide_debugger';

type
  PProcessEnumeration = ^TProcessEnumeration;
  TProcessEnumeration = record
    Processes: TJSONArray;
    MaximumProcesses: Integer;
    EnumeratedCount: Int64;
  end;

var
  GExternalProcessRequestActive: Boolean;

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

procedure CheckProcessText(const AValue, AName: string; const AMaximumLength: Integer);
begin
  if Length(AValue) > AMaximumLength then
    raise EArgumentOutOfRangeException.CreateFmt('%s darf höchstens %d Zeichen enthalten.', [AName, AMaximumLength]);
  if Pos(#0, AValue) > 0 then
    raise EArgumentException.CreateFmt('%s darf kein Nullzeichen enthalten.', [AName]);
end;

procedure CheckRemoteHost(const ARemoteHost: string);
begin
  CheckProcessText(ARemoteHost, 'remote_host', CMaximumRemoteHostLength);
  if (ARemoteHost <> '') and (Trim(ARemoteHost) = '') then
    raise EArgumentException.Create('remote_host muss leer sein oder einen Host enthalten.');
end;

procedure AddProcessEndpoint(const AResult: TJSONObject; const ARemoteHost: string);
begin
  AResult.AddPair('remote_host', ARemoteHost);
  if ARemoteHost = '' then
    AResult.AddPair('scope', 'local')
  else
    AResult.AddPair('scope', 'remote');
  AResult.AddPair('debugger_selection', CCurrentDebuggerSelection);
end;

procedure CollectRunningProcess(Pid: LongWord; const ProcessName: string; Param: Pointer);
var
  LEnumeration: PProcessEnumeration;
  LProcess: TJSONObject;
begin
  LEnumeration := PProcessEnumeration(Param);
  Inc(LEnumeration.EnumeratedCount);
  if LEnumeration.Processes.Count >= LEnumeration.MaximumProcesses then
    Exit;

  LProcess := TJSONObject.Create;
  try
    LProcess.AddPair('process_id', TJSONNumber.Create(Int64(Pid)));
    LProcess.AddPair('name', ProcessName);
    LEnumeration.Processes.AddElement(LProcess);
  except
    LProcess.Free;
    raise;
  end;
end;

function LiveProcess(const AProcess: IOTAProcess): Boolean;
begin
  if not Assigned(AProcess) then
    Exit(False);
  Result := not (AProcess.ProcessState in [psNothing, psTerminated, psNoProcess]);
end;

procedure CheckNoLiveDebuggerProcess(const ADebugger: IOTADebuggerServices);
const
  CActiveProcess = 'Ein Debuggerprozess ist bereits aktiv. Verwenden Sie debugger_status oder debugger_control.';
var
  LIndex: Integer;
begin
  if LiveProcess(ADebugger.CurrentProcess) then
    raise EInvalidOperation.Create(CActiveProcess);
  for LIndex := 0 to ADebugger.ProcessCount - 1 do
    if LiveProcess(ADebugger.Processes[LIndex]) then
      raise EInvalidOperation.Create(CActiveProcess);
end;

function MatchesObservedProcess(const AProcess: IOTAProcess; const AProcessId: Integer; const AExecutable, ARemoteHost: string): Boolean;
begin
  if not LiveProcess(AProcess) then
    Exit(False);
  if AProcessId <> 0 then
    Exit(AProcess.OSProcessId = LongWord(AProcessId));
  if AProcess.OSProcessId = 0 then
    Exit(False);
  if ARemoteHost = '' then
    Result := SameText(AProcess.ExeName, AExecutable)
  else
    Result := AProcess.ExeName = AExecutable;
end;

procedure AddProcessObservation(const AResult: TJSONObject; const ADebugger: IOTADebuggerServices; const AProcessId: Integer; const AExecutable, ARemoteHost: string);
var
  LIndex: Integer;
  LProcess: IOTAProcess;
  LObserved: TJSONObject;
begin
  LObserved := nil;
  try
    LProcess := ADebugger.CurrentProcess;
    if not MatchesObservedProcess(LProcess, AProcessId, AExecutable, ARemoteHost) then
      for LIndex := 0 to ADebugger.ProcessCount - 1 do
      begin
        LProcess := ADebugger.Processes[LIndex];
        if MatchesObservedProcess(LProcess, AProcessId, AExecutable, ARemoteHost) then
          Break;
      end;
    if MatchesObservedProcess(LProcess, AProcessId, AExecutable, ARemoteHost) then
    begin
      LObserved := TJSONObject.Create;
      LObserved.AddPair('process_id', TJSONNumber.Create(Int64(LProcess.OSProcessId)));
      LObserved.AddPair('debugger_process_id', TJSONNumber.Create(Int64(LProcess.ProcessId)));
      LObserved.AddPair('executable', LProcess.ExeName);
      LObserved.AddPair('state', ProcessStateName(LProcess.ProcessState));
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(LObserved);
      AResult.AddPair('observation_error', E.Message);
    end;
  end;

  AResult.AddPair('process_observed', TJSONBool.Create(Assigned(LObserved)));
  if Assigned(LObserved) then
    AResult.AddPair('process', LObserved)
  else
    AResult.AddPair('process', TJSONNull.Create);
end;

function InvokeExternalProcess(const AExecutable, AArguments, ARemoteHost: string; const AProcessId: Integer; const APauseAfterAttach, ADetachOnReset: Boolean): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LDebugger: IOTADebuggerServices;
      begin
        if GExternalProcessRequestActive then
          raise EInvalidOperation.Create('Eine Prozessanforderung wird bereits von der IDE verarbeitet.');
        GExternalProcessRequestActive := True;
        try
          LDebugger := DebuggerServices;
          CheckNoLiveDebuggerProcess(LDebugger);
          AddProcessEndpoint(LResult, ARemoteHost);
          if AProcessId = 0 then
          begin
            LResult.AddPair('action', 'load');
            LResult.AddPair('executable', AExecutable);
            LDebugger.CreateProcess(AExecutable, AArguments, ARemoteHost);
          end
          else
          begin
            LResult.AddPair('action', 'attach');
            LResult.AddPair('process_id', TJSONNumber.Create(AProcessId));
            LResult.AddPair('pause_after_attach', TJSONBool.Create(APauseAfterAttach));
            LResult.AddPair('detach_on_reset', TJSONBool.Create(ADetachOnReset));
            LDebugger.AttachProcess(AProcessId, APauseAfterAttach, ADetachOnReset, ARemoteHost);
          end;
          LResult.AddPair('action_invoked', TJSONBool.Create(True));
          LResult.AddPair('completion_is_asynchronous', TJSONBool.Create(True));
          AddProcessObservation(LResult, LDebugger, AProcessId, AExecutable, ARemoteHost);
        finally
          GExternalProcessRequestActive := False;
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
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
        LProcessCapabilities: TJSONObject;
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
        LProcessCapabilities := TJSONObject.Create;
        LResult.AddPair('process_capabilities', LProcessCapabilities);
        LProcessCapabilities.AddPair('scope', 'public_toolsapi');
        LProcessCapabilities.AddPair('enumerate', TJSONBool.Create(True));
        LProcessCapabilities.AddPair('load', TJSONBool.Create(True));
        LProcessCapabilities.AddPair('attach', TJSONBool.Create(True));
        LProcessCapabilities.AddPair('detach', TJSONBool.Create(True));
        LProcessCapabilities.AddPair('debugger_selection', CCurrentDebuggerSelection);
        LProcessCapabilities.AddPair('current_debugger_support', TJSONNull.Create);
        LProcessCapabilities.AddPair('read_native_dialog_settings', TJSONBool.Create(False));
        LProcessCapabilities.AddPair('working_directory', TJSONBool.Create(False));
        LProcessCapabilities.AddPair('select_debugger', TJSONBool.Create(False));
        LProcessCapabilities.AddPair('select_paserver_profile', TJSONBool.Create(False));
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

class function TDAIDebuggerService.Processes(const ARemoteHost: string; const AMaximumProcesses: Integer): TJSONObject;
var
  LResult: TJSONObject;
begin
  CheckRemoteHost(ARemoteHost);
  if (AMaximumProcesses < 1) or (AMaximumProcesses > CMaximumProcessResults) then
    raise EArgumentOutOfRangeException.CreateFmt('maximum_processes muss zwischen 1 und %d liegen.', [CMaximumProcessResults]);

  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LDebugger: IOTADebuggerServices;
        LEnumeration: TProcessEnumeration;
      begin
        LDebugger := DebuggerServices;
        LEnumeration.Processes := TJSONArray.Create;
        LResult.AddPair('processes', LEnumeration.Processes);
        LEnumeration.MaximumProcesses := AMaximumProcesses;
        LEnumeration.EnumeratedCount := 0;
        LDebugger.EnumerateRunningProcesses(CollectRunningProcess, @LEnumeration, ARemoteHost);
        AddProcessEndpoint(LResult, ARemoteHost);
        LResult.AddPair('action_invoked', TJSONBool.Create(True));
        // An unsupported current debugger may return without invoking the callback.
        if LEnumeration.EnumeratedCount > 0 then
          LResult.AddPair('enumeration_confirmed', TJSONBool.Create(True))
        else
          LResult.AddPair('enumeration_confirmed', TJSONNull.Create);
        LResult.AddPair('maximum_processes', TJSONNumber.Create(AMaximumProcesses));
        LResult.AddPair('enumerated_count', TJSONNumber.Create(LEnumeration.EnumeratedCount));
        LResult.AddPair('returned_count', TJSONNumber.Create(LEnumeration.Processes.Count));
        LResult.AddPair('truncated', TJSONBool.Create(LEnumeration.EnumeratedCount > LEnumeration.Processes.Count));
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDebuggerService.LoadProcess(const AExecutable, AArguments, ARemoteHost: string): TJSONObject;
begin
  CheckProcessText(AExecutable, 'executable', CMaximumProcessTextLength);
  if Trim(AExecutable) = '' then
    raise EArgumentException.Create('executable muss den Namen der ausführbaren Datei enthalten.');
  CheckProcessText(AArguments, 'arguments', CMaximumProcessTextLength);
  CheckRemoteHost(ARemoteHost);
  Result := InvokeExternalProcess(AExecutable, AArguments, ARemoteHost, 0, False, False);
end;

class function TDAIDebuggerService.AttachProcess(const AProcessId: Integer; const APauseAfterAttach, ADetachOnReset: Boolean; const ARemoteHost: string): TJSONObject;
begin
  if AProcessId < 1 then
    raise EArgumentOutOfRangeException.Create('process_id muss zwischen 1 und 2147483647 liegen.');
  CheckRemoteHost(ARemoteHost);
  if (ARemoteHost = '') and (LongWord(AProcessId) = GetCurrentProcessId) then
    raise EInvalidOperation.Create('Die IDE kann den Debugger nicht mit ihrem eigenen Prozess verbinden.');
  Result := InvokeExternalProcess('', '', ARemoteHost, AProcessId, APauseAfterAttach, ADetachOnReset);
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
  else if (LAction = 'pause') or (LAction = 'detach') then
    LRunMode := ormUnused
  else
    raise EArgumentException.Create('action muss pause, continue, step_into, step_over, step_out oder detach sein.');

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
          raise EInvalidOperation.Create('Es gibt keinen aktuellen Debuggerprozess. Verwenden Sie project_run, debugger_process_load oder debugger_process_attach.');
        LState := LProcess.ProcessState;
        if LAction = 'pause' then
        begin
          if LState <> psRunning then
            raise EInvalidOperation.Create('Pause ist nur bei laufendem Debuggerprozess möglich.');
        end
        else if LAction = 'detach' then
        begin
          if (LState <> psRunning) and not StoppedProcess(LProcess) then
            raise EInvalidOperation.Create('Detach erfordert einen laufenden oder angehaltenen Debuggerprozess.');
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
        else if LAction = 'detach' then
          LProcess.Detach
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
