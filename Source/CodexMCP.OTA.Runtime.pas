unit CodexMCP.OTA.Runtime;

interface

uses
  System.JSON,
  Winapi.Windows;

type
  TCodexMCPRuntime = class sealed
  strict private
    class var FLock: TObject;
    class var FProcessHandle: THandle;
    class var FProcessId: Cardinal;
    class constructor Create;
    class destructor Destroy;
    class function StartWithoutDebugger(
      const AExecutable,
      AWorkingDirectory: string
    ): TJSONObject; static;
    class function StopWithoutDebugger: Boolean; static;
  public
    class function RunProject(
      const AProjectIdentifier: string;
      const AUseDebugger,
      ABuildFirst: Boolean
    ): TJSONObject; static;
    class function StopProject: TJSONObject; static;
    class function Status: TJSONObject; static;
  end;

implementation

uses
  System.Actions,
  System.IOUtils,
  System.SysUtils,
  ToolsAPI,
  Vcl.Menus,
  CodexMCP.Json,
  CodexMCP.OTA.Common,
  CodexMCP.Threading;

function ProcessStateName(const AState: TOTAProcessState): string;
begin
  case AState of
    psNothing:
      Result := 'nothing';
    psRunning:
      Result := 'running';
    psStopping:
      Result := 'stopping';
    psStopped:
      Result := 'stopped';
    psFault:
      Result := 'fault';
    psResFault:
      Result := 'resource_fault';
    psTerminated:
      Result := 'terminated';
    psException:
      Result := 'exception';
    psNoProcess:
      Result := 'no_process';
  else
    Result := 'unknown';
  end;
end;

{ TCodexMCPRuntime }

class constructor TCodexMCPRuntime.Create;
begin
  FLock := TObject.Create;
  FProcessHandle := 0;
  FProcessId := 0;
end;

class destructor TCodexMCPRuntime.Destroy;
begin
  TMonitor.Enter(FLock);
  try
    if FProcessHandle <> 0 then
      CloseHandle(FProcessHandle);
    FProcessHandle := 0;
    FProcessId := 0;
  finally
    TMonitor.Exit(FLock);
  end;
  FLock.Free;
end;

class function TCodexMCPRuntime.StartWithoutDebugger(
  const AExecutable,
  AWorkingDirectory: string
): TJSONObject;
var
  LCommandLine: string;
  LExitCode: Cardinal;
  LProcessInfo: TProcessInformation;
  LStartupInfo: TStartupInfo;
begin
  TMonitor.Enter(FLock);
  try
    if FProcessHandle <> 0 then
    begin
      if GetExitCodeProcess(FProcessHandle, LExitCode) and
        (LExitCode = STILL_ACTIVE) then
        raise EInvalidOpException.Create(
          'Ein ohne Debugger gestarteter Prozess läuft bereits.'
        );
      CloseHandle(FProcessHandle);
      FProcessHandle := 0;
      FProcessId := 0;
    end;

    ZeroMemory(@LStartupInfo, SizeOf(LStartupInfo));
    LStartupInfo.cb := SizeOf(LStartupInfo);
    ZeroMemory(@LProcessInfo, SizeOf(LProcessInfo));
    LCommandLine := '"' + AExecutable + '"';
    if not CreateProcess(
      PChar(AExecutable),
      PChar(LCommandLine),
      nil,
      nil,
      False,
      CREATE_NEW_PROCESS_GROUP,
      nil,
      PChar(AWorkingDirectory),
      LStartupInfo,
      LProcessInfo
    ) then
      RaiseLastOSError;
    CloseHandle(LProcessInfo.hThread);
    FProcessHandle := LProcessInfo.hProcess;
    FProcessId := LProcessInfo.dwProcessId;

    Result := JsonSuccess;
    Result.AddPair('mode', 'without_debugger');
    Result.AddPair('executable', AExecutable);
    Result.AddPair('process_id', TJSONNumber.Create(FProcessId));
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TCodexMCPRuntime.StopWithoutDebugger: Boolean;
var
  LExitCode: Cardinal;
begin
  Result := False;
  TMonitor.Enter(FLock);
  try
    if FProcessHandle = 0 then
      Exit;
    if GetExitCodeProcess(FProcessHandle, LExitCode) and
      (LExitCode = STILL_ACTIVE) then
    begin
      Result := TerminateProcess(FProcessHandle, 0);
      if Result then
        WaitForSingleObject(FProcessHandle, 5000);
    end;
    CloseHandle(FProcessHandle);
    FProcessHandle := 0;
    FProcessId := 0;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TCodexMCPRuntime.RunProject(
  const AProjectIdentifier: string;
  const AUseDebugger,
  ABuildFirst: Boolean
): TJSONObject;
var
  LExecutable: string;
  LProjectFile: string;
  LWorkingDirectory: string;
begin
  LExecutable := '';
  LProjectFile := '';
  LWorkingDirectory := '';

  if AUseDebugger then
  begin
    Result := TCodexMCPThreading.CallInIDEThread<TJSONObject>(
      function: TJSONObject
      var
        LAction: TBasicAction;
        LBuildSucceeded: Boolean;
        LModuleServices: IOTAModuleServices;
        LProject: IOTAProject;
        LProjectGroup: IOTAProjectGroup;
      begin
        LProject := FindProject(AProjectIdentifier);
        if not Assigned(LProject) then
          raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
        if ClassifyPath(LProject.FileName) <> cpaWorkspaceReadWrite then
          raise EAccessViolation.Create(
            'Das ausgewählte Projekt liegt in einem schreibgeschützten Referenzpfad.'
          );
        if not Assigned(LProject.ProjectBuilder) then
          raise EInvalidOpException.Create('Das Projekt besitzt keinen ProjectBuilder.');
        LProjectGroup := nil;
        if Supports(
          BorlandIDEServices,
          IOTAModuleServices,
          LModuleServices
        ) then
          LProjectGroup := LModuleServices.MainProjectGroup;
        if Assigned(LProjectGroup) then
          LProjectGroup.ActiveProject := LProject;

        if ABuildFirst then
        begin
          LBuildSucceeded := LProject.ProjectBuilder.BuildProject(
            cmOTAMake,
            True,
            True
          );
          if not LBuildSucceeded then
            raise EInvalidOpException.Create(
              'Das Projekt konnte vor dem Start nicht kompiliert werden.'
            );
        end;

        LAction := FindIDEAction(
          [
            'RunRunCommand',
            'ProjectRunCommand',
            'DebuggerRunCommand',
            'RunCommand',
            'RunProjectCommand'
          ],
          Vcl.Menus.ShortCut(VK_F9, [])
        );
        if not ExecuteIDEAction(LAction) then
          raise EInvalidOpException.Create(
            'Der Startbefehl der Delphi-IDE ist nicht verfügbar.'
          );
        Result := JsonSuccess;
        Result.AddPair('mode', 'debugger');
        Result.AddPair('project', LProject.FileName);
        Result.AddPair('state', 'starting');
      end
    );
    Exit;
  end;

  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LBuildSucceeded: Boolean;
      LProject: IOTAProject;
    begin
      LProject := FindProject(AProjectIdentifier);
      if not Assigned(LProject) then
        raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
      if ClassifyPath(LProject.FileName) <> cpaWorkspaceReadWrite then
        raise EAccessViolation.Create(
          'Das ausgewählte Projekt liegt in einem schreibgeschützten Referenzpfad.'
        );
      if not Assigned(LProject.ProjectOptions) then
        raise EInvalidOpException.Create('Projektoptionen sind nicht verfügbar.');
      if ABuildFirst then
      begin
        if not Assigned(LProject.ProjectBuilder) then
          raise EInvalidOpException.Create('Das Projekt besitzt keinen ProjectBuilder.');
        LBuildSucceeded := LProject.ProjectBuilder.BuildProject(
          cmOTAMake,
          True,
          True
        );
        if not LBuildSucceeded then
          raise EInvalidOpException.Create(
            'Das Projekt konnte vor dem Start nicht kompiliert werden.'
          );
      end;
      LProjectFile := LProject.FileName;
      LWorkingDirectory := ProjectDirectory(LProject);
      LExecutable := Trim(LProject.ProjectOptions.TargetName);
    end
  );

  if LExecutable = '' then
    raise EInvalidOpException.Create('Das Projekt hat kein ausführbares Ziel.');
  if not TPath.IsPathRooted(LExecutable) then
    LExecutable := TPath.Combine(LWorkingDirectory, LExecutable);
  LExecutable := NormalizePath(LExecutable);
  if not TFile.Exists(LExecutable) then
    raise EFileNotFoundException.Create(
      'Die Ausgabedatei wurde nicht gefunden: ' + LExecutable
    );
  Result := StartWithoutDebugger(LExecutable, LWorkingDirectory);
  Result.AddPair('project', LProjectFile);
end;

class function TCodexMCPRuntime.Status: TJSONObject;
var
  LDebuggerState: string;
  LExitCode: Cardinal;
  LNoDebugActive: Boolean;
  LNoDebugPid: Cardinal;
begin
  LDebuggerState := TCodexMCPThreading.CallInIDEThread<string>(
    function: string
    var
      LDebugger: IOTADebuggerServices;
      LProcess: IOTAProcess;
    begin
      Result := 'unavailable';
      if not Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
        Exit;
      LProcess := LDebugger.CurrentProcess;
      if not Assigned(LProcess) then
        Exit('no_process');
      Result := ProcessStateName(LProcess.ProcessState);
    end
  );

  LNoDebugActive := False;
  LNoDebugPid := 0;
  TMonitor.Enter(FLock);
  try
    if FProcessHandle <> 0 then
    begin
      LNoDebugActive := GetExitCodeProcess(FProcessHandle, LExitCode) and
        (LExitCode = STILL_ACTIVE);
      if LNoDebugActive then
        LNoDebugPid := FProcessId
      else
      begin
        CloseHandle(FProcessHandle);
        FProcessHandle := 0;
        FProcessId := 0;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;

  Result := JsonSuccess;
  Result.AddPair('debugger_state', LDebuggerState);
  Result.AddPair('without_debugger_active', TJSONBool.Create(LNoDebugActive));
  if LNoDebugActive then
    Result.AddPair('without_debugger_process_id', TJSONNumber.Create(LNoDebugPid))
  else
    Result.AddPair('without_debugger_process_id', TJSONNull.Create);
end;

class function TCodexMCPRuntime.StopProject: TJSONObject;
var
  LDebuggerStopped: Boolean;
  LNoDebuggerStopped: Boolean;
begin
  LDebuggerStopped := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    var
      LAction: TBasicAction;
      LDebugger: IOTADebuggerServices;
      LProcess: IOTAProcess;
    begin
      Result := False;
      if Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) then
      begin
        LProcess := LDebugger.CurrentProcess;
        if Assigned(LProcess) and not (
          LProcess.ProcessState in [psNothing, psTerminated, psNoProcess]
        ) then
        begin
          LProcess.Terminate;
          Exit(True);
        end;
      end;
      LAction := FindIDEAction(
        ['RunProgramResetCommand', 'ProgramResetCommand', 'DebugStopCommand'],
        Vcl.Menus.ShortCut(VK_F2, [ssCtrl])
      );
      if Assigned(LAction) then
        Result := ExecuteIDEAction(LAction);
    end
  );

  LNoDebuggerStopped := StopWithoutDebugger;
  Result := JsonSuccess;
  Result.AddPair('debugger_stopped', TJSONBool.Create(LDebuggerStopped));
  Result.AddPair(
    'without_debugger_stopped',
    TJSONBool.Create(LNoDebuggerStopped)
  );
  Result.AddPair(
    'anything_stopped',
    TJSONBool.Create(LDebuggerStopped or LNoDebuggerStopped)
  );
end;

end.
