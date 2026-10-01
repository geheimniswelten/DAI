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
  h5u.DAI.Settings,
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

procedure RequireWritableBuildFile(const AFileName: string);
var
  LExtension, LProjectSidecar: string;
begin
  TDAIOTA.RequireNoReparseWritePath(AFileName);
  if TDAIOTA.IsReadOnlyReferenceFile(AFileName) then
    raise EDAIAccessDenied.CreateFmt('Referenzverzeichnisse sind schreibgeschützt. Dieser IDE-Build darf die Datei nicht ändern: %s', [AFileName]);
  LExtension := TPath.GetExtension(AFileName);
  if SameText(LExtension, '.dpr') or SameText(LExtension, '.dpk') then
    LProjectSidecar := ChangeFileExt(AFileName, '.dproj')
  else if SameText(LExtension, '.dproj') then
    LProjectSidecar := AFileName
  else
    Exit;
  TDAIOTA.RequireNoReparseWritePath(LProjectSidecar);
  TDAIOTA.RequireNoReparseWritePath(LProjectSidecar + '.local');
end;

procedure RequireWritableBuildProject(const AProject: IOTAProject);
var
  LConfiguration: IOTABuildConfiguration;
  LConfigurations: IOTAProjectOptionsConfigurations;
  LEditor: IOTAEditor;
  LIndex: Integer;
  LCommonDirectory, LOption, LPath, LProjectDirectory, LUserDirectory: string;
begin
  if not Assigned(AProject) then
    Exit;
  RequireWritableBuildFile(AProject.FileName);
  for LIndex := 0 to AProject.ModuleFileCount - 1 do
  begin
    LEditor := AProject.ModuleFileEditors[LIndex];
    if Assigned(LEditor) then
      RequireWritableBuildFile(LEditor.FileName);
  end;
  RequireWritableBuildFile(ResolveTargetExecutable(AProject));
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, LConfigurations) then
    Exit;
  LConfiguration := LConfigurations.ActiveConfiguration;
  if not Assigned(LConfiguration) then
    Exit;
  if Trim(AProject.CurrentPlatform) <> '' then
    if Assigned(LConfiguration.PlatformConfiguration[AProject.CurrentPlatform]) then
      LConfiguration := LConfiguration.PlatformConfiguration[AProject.CurrentPlatform];
  LProjectDirectory := TPath.GetDirectoryName(TDAIOTA.ProjectFileName(AProject));
  LCommonDirectory := GetEnvironmentVariable('BDSCOMMONDIR');
  if LCommonDirectory = '' then
    LCommonDirectory := TPath.GetDirectoryName(TDAISettings.Instance.CatalogRepositoryAllUsersDirectory);
  LUserDirectory := GetEnvironmentVariable('BDSUSERDIR');
  if LUserDirectory = '' then
    LUserDirectory := TPath.GetDirectoryName(TDAISettings.Instance.CatalogRepositoryDirectory);
  for LOption in ['DCC_ExeOutput', 'DCC_DcuOutput', 'DCC_BplOutput', 'DCC_DcpOutput'] do
  begin
    LPath := Trim(LConfiguration.GetValue(LOption));
    if LPath = '' then
      Continue;
    LPath := StringReplace(LPath, '$(PROJECTDIR)', LProjectDirectory, [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(MSBuildProjectDirectory)', LProjectDirectory, [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(Platform)', AProject.CurrentPlatform, [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(Config)', AProject.CurrentConfiguration, [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(Configuration)', AProject.CurrentConfiguration, [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(MSBuildProjectName)', TPath.GetFileNameWithoutExtension(AProject.FileName), [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(BDS)', '%BDS%', [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(BDSCOMMONDIR)', LCommonDirectory, [rfReplaceAll, rfIgnoreCase]);
    LPath := StringReplace(LPath, '$(BDSUSERDIR)', LUserDirectory, [rfReplaceAll, rfIgnoreCase]);
    // Unresolved custom MSBuild expressions cannot be classified safely as an output directory.
    if LPath.Contains('$(') or LPath.Contains('@(') then
      raise EInvalidOperation.CreateFmt('Der IDE-Build-Ausgabepfad für %s enthält nicht auflösbare Makros: %s', [LOption, LPath]);
    if not TPath.IsPathRooted(LPath) and not LPath.Contains('%') then
      LPath := TPath.Combine(LProjectDirectory, LPath);
    LPath := TDAISettings.Instance.ExpandPath(LPath);
    RequireWritableBuildFile(TPath.Combine(LPath, 'dai-output-policy-check.tmp'));
  end;
end;

procedure RequireWritableBuildClosure(const AProject: IOTAProject);
var
  LDependencies: IOTAProjectDependenciesList;
  LDependency: IOTAProject;
  LGroup: IOTAProjectGroup;
  LIndex, LProjectIndex: Integer;
  LProjects: TList<IOTAProject>;
  LServices: IOTAProjectGroupProjectDependencies;
begin
  if not Assigned(AProject) then
    Exit;
  LGroup := TDAIOTA.MainProjectGroup;
  LProjects := TList<IOTAProject>.Create;
  try
    LProjects.Add(AProject);
    Supports(LGroup, IOTAProjectGroupProjectDependencies, LServices);
    LProjectIndex := 0;
    while LProjectIndex < LProjects.Count do
    begin
      RequireWritableBuildProject(LProjects[LProjectIndex]);
      if Assigned(LServices) then
      begin
        LDependencies := LServices.GetProjectDependencies(LProjects[LProjectIndex]);
        if Assigned(LDependencies) then
          for LIndex := 0 to LDependencies.ProjectCount - 1 do
          begin
            LDependency := LDependencies.Projects[LIndex];
            if Assigned(LDependency) and (LProjects.IndexOf(LDependency) < 0) then
            begin
              if LProjects.Count >= 1000 then
                raise EInvalidOperation.Create('Die Projektabhängigkeiten überschreiten das Prüflimit von 1000 Projekten.');
              LProjects.Add(LDependency);
            end;
          end;
      end;
      Inc(LProjectIndex);
    end;
  finally
    LProjects.Free;
  end;
end;

procedure RequireWritableModifiedEditors;
var
  LEditor: IOTAEditor;
  LEditorIndex, LModuleIndex: Integer;
  LModule: IOTAModule;
  LServices: IOTAModuleServices;
begin
  // The IDE can save dirty buffers and stream forms while compiling, including editors outside the target project.
  if not Supports(BorlandIDEServices, IOTAModuleServices, LServices) then
    Exit;
  for LModuleIndex := 0 to LServices.ModuleCount - 1 do
  begin
    LModule := LServices.Modules[LModuleIndex];
    if not Assigned(LModule) then
      Continue;
    for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
    begin
      LEditor := LModule.ModuleFileEditors[LEditorIndex];
      if Assigned(LEditor) then
        if LEditor.Modified then
          RequireWritableBuildFile(LEditor.FileName);
    end;
  end;
end;

procedure SelectProject(const AProject: IOTAProject);
var
  LGroup: IOTAProjectGroup;
begin
  LGroup := TDAIOTA.MainProjectGroup;
  if Assigned(LGroup) then
  begin
    RequireWritableBuildFile(LGroup.FileName);
    LGroup.ActiveProject := AProject;
  end;
end;

function CompileOneProject(const AProject: IOTAProject; const AFullBuild: Boolean; const AClearMessages: Boolean): Boolean;
var
  LMode: TOTACompileMode;
begin
  Result := False;
  if not Assigned(AProject) or not Assigned(AProject.ProjectBuilder) then
    Exit;

  RequireWritableBuildClosure(AProject);
  RequireWritableModifiedEditors;

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
      RequireWritableBuildClosure(LProject);
      RequireWritableModifiedEditors;
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
  LProjects: TArray<IOTAProject>;
  LSucceeded: Boolean;
begin
  LProjects := TDAIOTA.Projects;
  // Reject the whole group before the first project selection or build creates any outputs.
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LPreflightProject: IOTAProject;
    begin
      for LPreflightProject in LProjects do
        RequireWritableBuildClosure(LPreflightProject);
      RequireWritableModifiedEditors;
    end);
  LItems := TJSONArray.Create;
  try
    LAllSucceeded := True;
    LClearMessages := AClearMessages;
    for LProject in LProjects do
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
  LDebugger: IOTADebuggerServices;
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
        // The IDE Run action may save modified files and automatically rebuild an out-of-date project.
        RequireWritableBuildClosure(LProject);
        RequireWritableModifiedEditors;
        if Supports(BorlandIDEServices, IOTADebuggerServices, LDebugger) and Assigned(LDebugger.CurrentProcess) and
          not (LDebugger.CurrentProcess.ProcessState in [psNothing, psTerminated, psNoProcess]) then
          raise EInvalidOperation.Create('Ein Debuggerprozess ist bereits aktiv. Verwenden Sie debugger_control zum Fortsetzen oder project_stop.');
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
    LTargetProject := nil;
    if Trim(AProjectNameOrPath) <> '' then
    begin
      LTargetProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
      if not Assigned(LTargetProject) then
        raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');
    end;
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
        if Assigned(LTargetProject) and not TDAIOTA.SameFile(LProcess.ExeName, ResolveTargetExecutable(LTargetProject)) then
          raise EInvalidOperation.Create('Der aktuelle Debuggerprozess gehört nicht zur Ausgabedatei des angegebenen Projekts.');
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
