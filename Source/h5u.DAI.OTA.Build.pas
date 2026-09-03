unit h5u.DAI.OTA.Build;

interface

uses
  System.JSON;

type
  TDAIBuildService = class sealed
  public
    class function CompileProject(const AProjectNameOrPath: string; const AFullBuild: Boolean; const AClearMessages: Boolean): TJSONObject; static;
    class function CompileProjectGroup(const AFullBuild: Boolean; const AClearMessages: Boolean): TJSONObject; static;
    class function RunProject(const AProjectNameOrPath: string; const AWithDebugger: Boolean): TJSONObject; static;
    class function StopProject(const AProjectNameOrPath: string; const AWithDebugger: Boolean): TJSONObject; static;
    class function ExecuteMSBuild(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDirectory: string; const ATimeoutMs: Cardinal): TJSONObject; static;
    class function ExecuteDCC32(const AArguments: TArray<string>; const AWorkingDirectory: string; const ATimeoutMs: Cardinal): TJSONObject; static;
    class procedure ClearProjectProcess(const AProjectFileName: string); static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Actions,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  Winapi.Windows,
  Vcl.ActnList,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Process,
  h5u.DAI.Types;

type
  TDAIRunningProcess = record
  public
    Handle: THandle;
    ProcessId: Cardinal;
    ProjectFileName: string;
  end;

var
  GProcessLock: TObject;
  GRunningProcesses: TDictionary<string, TDAIRunningProcess>;

function ProcessResultToJson(const AResult: TDAIProcessResult; const AExecutable: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('executable', AExecutable);
  Result.AddPair('started', TJSONBool.Create(AResult.Started));
  Result.AddPair('timed_out', TJSONBool.Create(AResult.TimedOut));
  Result.AddPair('exit_code', TJSONNumber.Create(Int64(AResult.ExitCode)));
  Result.AddPair('duration_ms', TJSONNumber.Create(AResult.DurationMs));
  Result.AddPair('output', AResult.Output);
  Result.AddPair('error', AResult.ErrorText);
  Result.AddPair('succeeded', TJSONBool.Create(AResult.Started and not AResult.TimedOut and (AResult.ExitCode = 0)));
end;

function FindIDEAction(const ANames: array of string): TBasicAction;
var
  LAction: TContainedAction;
  LActionIndex: Integer;
  LActionList: TCustomActionList;
  LName: string;
  LServices: INTAServices;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, LServices) then
    Exit;
  LActionList := LServices.ActionList;
  if not Assigned(LActionList) then
    Exit;

  for LName in ANames do
    for LActionIndex := 0 to LActionList.ActionCount - 1 do
    begin
      LAction := LActionList[LActionIndex];
      if Assigned(LAction) and SameText(LAction.Name, LName) then
        Exit(LAction);
    end;
end;

function ResolveTargetExecutable(const AProject: IOTAProject): string;
var
  LProjectFileName: string;
begin
  LProjectFileName := TDAIOTA.ProjectFileName(AProject);
  Result := Trim(TDAIOTA.ProjectTargetName(AProject));
  if Result = '' then
    Result := ChangeFileExt(LProjectFileName, '.exe');
  if not TPath.IsPathRooted(Result) then
    Result := TPath.Combine(TPath.GetDirectoryName(LProjectFileName), Result);
  Result := TPath.GetFullPath(Result);
end;

procedure SelectProject(const AProject: IOTAProject);
var
  LGroup: IOTAProjectGroup;
begin
  LGroup := TDAIOTA.MainProjectGroup;
  if Assigned(LGroup) then
    LGroup.ActiveProject := AProject;
end;

function CompileOneProject(const AProject: IOTAProject; const AFullBuild: Boolean; const AClearMessages: Boolean): Boolean;
var
  LMode: TOTACompileMode;
begin
  Result := False;
  if not Assigned(AProject) or not Assigned(AProject.ProjectBuilder) then
    Exit;

  if AFullBuild then
    LMode := cmOTABuild
  else
    LMode := cmOTAMake;
  Result := AProject.ProjectBuilder.BuildProject(LMode, True, AClearMessages);
end;

class procedure TDAIBuildService.ClearProjectProcess(const AProjectFileName: string);
var
  LKey: string;
  LProcess: TDAIRunningProcess;
begin
  LKey := LowerCase(TDAIOTA.NormalizeFileName(AProjectFileName));
  System.TMonitor.Enter(GProcessLock);
  try
    if GRunningProcesses.TryGetValue(LKey, LProcess) then
    begin
      if LProcess.Handle <> 0 then
        CloseHandle(LProcess.Handle);
      GRunningProcesses.Remove(LKey);
    end;
  finally
    System.TMonitor.Exit(GProcessLock);
  end;
end;

class function TDAIBuildService.CompileProject(const AProjectNameOrPath: string; const AFullBuild: Boolean; const AClearMessages: Boolean): TJSONObject;
var
  LProject: IOTAProject;
  LSucceeded: Boolean;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  LSucceeded := False;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      SelectProject(LProject);
      LSucceeded := CompileOneProject(LProject, AFullBuild, AClearMessages);
    end);

  Result := TJSONObject.Create;
  Result.AddPair('project', TDAIOTA.ProjectFileName(LProject));
  Result.AddPair('mode', IfThen(AFullBuild, 'build', 'make'));
  Result.AddPair('succeeded', TJSONBool.Create(LSucceeded));
end;

class function TDAIBuildService.CompileProjectGroup(const AFullBuild: Boolean; const AClearMessages: Boolean): TJSONObject;
var
  LAllSucceeded: Boolean;
  LClearMessages: Boolean;
  LItem: TJSONObject;
  LItems: TJSONArray;
  LProject: IOTAProject;
  LSucceeded: Boolean;
begin
  LItems := TJSONArray.Create;
  try
    LAllSucceeded := True;
    LClearMessages := AClearMessages;
    for LProject in TDAIOTA.Projects do
    begin
      LSucceeded := False;
      TDAIOTA.RunOnMainThread(
        procedure
        begin
          SelectProject(LProject);
          LSucceeded := CompileOneProject(LProject, AFullBuild, LClearMessages);
        end);

      LItem := TJSONObject.Create;
      LItem.AddPair('project', TDAIOTA.ProjectFileName(LProject));
      LItem.AddPair('succeeded', TJSONBool.Create(LSucceeded));
      LItems.AddElement(LItem);
      LAllSucceeded := LAllSucceeded and LSucceeded;
      LClearMessages := False;
      if not LSucceeded then
        Break;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('mode', IfThen(AFullBuild, 'build', 'make'));
    Result.AddPair('succeeded', TJSONBool.Create(LAllSucceeded));
    Result.AddPair('projects', LItems);
    LItems := nil;
  finally
    LItems.Free;
  end;
end;

class function TDAIBuildService.ExecuteDCC32(const AArguments: TArray<string>; const AWorkingDirectory: string; const ATimeoutMs: Cardinal): TJSONObject;
var
  LExecutable: string;
  LResult: TDAIProcessResult;
begin
  LExecutable := TDAIProcess.ResolveDCC32Executable;
  LResult := TDAIProcess.Execute(LExecutable, AArguments, AWorkingDirectory, ATimeoutMs);
  Result := ProcessResultToJson(LResult, LExecutable);
end;

class function TDAIBuildService.ExecuteMSBuild(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDirectory: string; const ATimeoutMs: Cardinal):
  TJSONObject;
var
  LResolvedExecutable: string;
  LResult: TDAIProcessResult;
begin
  LResolvedExecutable := TDAIProcess.ResolveMSBuildExecutable(AExecutable);
  LResult := TDAIProcess.Execute(LResolvedExecutable, AArguments, AWorkingDirectory, ATimeoutMs);
  Result := ProcessResultToJson(LResult, LResolvedExecutable);
end;

class function TDAIBuildService.RunProject(const AProjectNameOrPath: string; const AWithDebugger: Boolean): TJSONObject;
var
  LAction: TBasicAction;
  LExecutable: string;
  LKey: string;
  LProcess: TDAIRunningProcess;
  LProject: IOTAProject;
  LStarted: Boolean;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

  if AWithDebugger then
  begin
    LStarted := False;
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        SelectProject(LProject);
        LAction := FindIDEAction([
          'RunRunCommand',
          'ProjectRunCommand',
          'DebuggerRunCommand',
          'RunCommand',
          'RunProjectCommand'
        ]);
        if not Assigned(LAction) then
          raise EInvalidOperation.Create('Die IDE-Aktion zum Starten mit Debugger wurde nicht gefunden.');
        LStarted := LAction.Execute;
      end);

    Result := TJSONObject.Create;
    Result.AddPair('project', TDAIOTA.ProjectFileName(LProject));
    Result.AddPair('debugger', TJSONBool.Create(True));
    Result.AddPair('started', TJSONBool.Create(LStarted));
    Exit;
  end;

  LExecutable := ResolveTargetExecutable(LProject);
  if not TFile.Exists(LExecutable) then
    raise EDAIFileNotFound.CreateFmt('Die Projekt-Ausgabedatei wurde nicht gefunden: %s', [LExecutable]);

  LKey := LowerCase(TDAIOTA.NormalizeFileName(TDAIOTA.ProjectFileName(LProject)));
  System.TMonitor.Enter(GProcessLock);
  try
    if GRunningProcesses.TryGetValue(LKey, LProcess) then
    begin
      if (LProcess.Handle <> 0) and (WaitForSingleObject(LProcess.Handle, 0) = WAIT_TIMEOUT) then
        raise EInvalidOperation.Create('Das Projekt läuft bereits ohne Debugger.');
      if LProcess.Handle <> 0 then
        CloseHandle(LProcess.Handle);
      GRunningProcesses.Remove(LKey);
    end;

    LProcess := Default(TDAIRunningProcess);
    LProcess.ProjectFileName := TDAIOTA.ProjectFileName(LProject);
    LStarted := TDAIProcess.StartDetached(
      LExecutable,
      [],
      TPath.GetDirectoryName(LExecutable),
      LProcess.Handle,
      LProcess.ProcessId
    );
    if LStarted then
      GRunningProcesses.AddOrSetValue(LKey, LProcess);
  finally
    System.TMonitor.Exit(GProcessLock);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('project', TDAIOTA.ProjectFileName(LProject));
  Result.AddPair('executable', LExecutable);
  Result.AddPair('debugger', TJSONBool.Create(False));
  Result.AddPair('started', TJSONBool.Create(LStarted));
  Result.AddPair('process_id', TJSONNumber.Create(LProcess.ProcessId));
end;

class procedure TDAIBuildService.Shutdown;
var
  LProcess: TDAIRunningProcess;
begin
  System.TMonitor.Enter(GProcessLock);
  try
    for LProcess in GRunningProcesses.Values do
      if LProcess.Handle <> 0 then
        CloseHandle(LProcess.Handle);
    GRunningProcesses.Clear;
  finally
    System.TMonitor.Exit(GProcessLock);
  end;
end;

class function TDAIBuildService.StopProject(const AProjectNameOrPath: string; const AWithDebugger: Boolean): TJSONObject;
var
  LDebugger: IOTADebuggerServices;
  LPair: TPair<string, TDAIRunningProcess>;
  LProcess: IOTAProcess;
  LRemoveKey: string;
  LRunningProcess: TDAIRunningProcess;
  LStopped: Boolean;
  LTargetKey: string;
  LTargetProject: IOTAProject;
begin
  LStopped := False;
  if AWithDebugger then
  begin
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        if not Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
          raise EInvalidOperation.Create('IOTADebuggerServices ist nicht verfügbar.');
        LProcess := LDebugger.CurrentProcess;
        if not Assigned(LProcess) then
          Exit;
        if LProcess.ProcessState in [psNothing, psTerminated, psNoProcess] then
          Exit;
        LProcess.Terminate;
        LStopped := True;
      end);

    Result := TJSONObject.Create;
    Result.AddPair('debugger', TJSONBool.Create(True));
    Result.AddPair('stopped', TJSONBool.Create(LStopped));
    Exit;
  end;

  LTargetKey := '';
  if Trim(AProjectNameOrPath) <> '' then
  begin
    LTargetProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
    if Assigned(LTargetProject) then
      LTargetKey := LowerCase(TDAIOTA.ProjectFileName(LTargetProject))
    else
      LTargetKey := LowerCase(TDAIOTA.NormalizeFileName(AProjectNameOrPath));
  end;

  LRemoveKey := '';
  System.TMonitor.Enter(GProcessLock);
  try
    for LPair in GRunningProcesses do
    begin
      if (LTargetKey <> '') and not SameText(LPair.Key, LTargetKey) then
        Continue;
      LRunningProcess := LPair.Value;
      if (LRunningProcess.Handle <> 0) and (WaitForSingleObject(LRunningProcess.Handle, 0) = WAIT_TIMEOUT) then
      begin
        LStopped := TerminateProcess(LRunningProcess.Handle, 4);
        WaitForSingleObject(LRunningProcess.Handle, 5000);
        CloseHandle(LRunningProcess.Handle);
        LRemoveKey := LPair.Key;
        Break;
      end;
    end;
    if LRemoveKey <> '' then
      GRunningProcesses.Remove(LRemoveKey);
  finally
    System.TMonitor.Exit(GProcessLock);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('debugger', TJSONBool.Create(False));
  Result.AddPair('stopped', TJSONBool.Create(LStopped));
end;

initialization
  GProcessLock := TObject.Create;
  GRunningProcesses := TDictionary<string, TDAIRunningProcess>.Create;

finalization
  TDAIBuildService.Shutdown;
  GRunningProcesses.Free;
  GProcessLock.Free;

end.
