program TestProjectGroups;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.Projects,
  h5u.DAI.Types;

type
  TTestEditor = class(TInterfacedObject, IOTAEditor)
    FileName: string;
    Modified: Boolean;
    function GetFileName: string;
    function GetModified: Boolean;
  end;
  TTestSourceEditor = class(TTestEditor, IOTASourceEditor)
  end;
  TTestModule = class(TInterfacedObject, IOTAModule)
  private
    FFileName: string;
  public
    SaveCount, ShowCount: Integer;
    LastShownFile: string;
    ShowCreatesSourceEditor, RaiseShowAbort: Boolean;
    Editors: TArray<IOTAEditor>;
    constructor Create(const AFileName: string);
    function GetFileName: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(AIndex: Integer): IOTAEditor;
    function Save(AForceSave, AForceSaveAs: Boolean): Boolean;
    function CloseModule(AForceClosed: Boolean): Boolean;
    procedure ShowFileName(const AFileName: string);
  end;
  TTestProject = class(TTestModule, IOTAProject)
    procedure RemoveFile(const AFileName: string);
  end;
  TTestGroup = class(TTestModule, IOTAProjectGroup)
    procedure RemoveProject(const AProject: IOTAProject);
    function GetProjectCount: Integer;
    function GetProject(AIndex: Integer): IOTAProject;
    function GetActiveProject: IOTAProject;
    procedure SetActiveProject(const AProject: IOTAProject);
  end;
  TTestHost = class(TInterfacedObject, IOTAModuleServices, IOTAActionServices)
  public
    Events: TList<string>;
    CloseCount, OpenCount, OpenFileCount, CreateCount: Integer;
    CloseResult, OpenResult, RegisterOpenedTarget, RaiseCloseAbort, LeaveOpenAfterClose: Boolean;
    EmptyGroupAfterClose, ChangeGroupOnAppend: Boolean;
    LastNewGroup, LastUnnamed: Boolean;
    LastFile: string;
    LastOwner: IOTAModule;
    LastCreated: TTestProject;
    LastCreatedInterface: IOTAProject;
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    function GetMainProjectGroup: IOTAProjectGroup;
    function GetActiveProject: IOTAProject;
    function CreateModule(const ACreator: IOTACreator): IOTAModule;
    function CloseAll: Boolean;
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    function OpenFile(const AFileName: string): Boolean;
    function OpenProject(const AFileName: string; ANewProjectGroup: Boolean): Boolean;
  end;

var
  CheckCount: Integer;
  FixtureRoot: string;
  Host: TTestHost;
  HostInterface: IInterface;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function JsonBoolean(const AObject: TJSONObject; const AName: string): Boolean;
var LValue: TJSONValue;
begin
  LValue := AObject.GetValue(AName);
  if not (LValue is TJSONBool) then
    raise Exception.Create('Missing Boolean result: ' + AName);
  Result := TJSONBool(LValue).AsBoolean;
end;

procedure AddProject(const AProject: IOTAProject);
begin
  TDAIOTA.TestProjects := TDAIOTA.TestProjects + [AProject];
  TDAIOTA.TestModules := TDAIOTA.TestModules + [AProject as IOTAModule];
  TDAIOTA.TestActiveProject := AProject;
end;

constructor TTestModule.Create(const AFileName: string);
begin inherited Create; FFileName := AFileName; end;
function TTestEditor.GetFileName: string;
begin Result := FileName; end;
function TTestEditor.GetModified: Boolean;
begin Result := Modified; end;
function TTestModule.GetFileName: string;
begin Result := FFileName; end;
function TTestModule.GetModuleFileCount: Integer;
begin Result := Length(Editors); end;
function TTestModule.GetModuleFileEditor(AIndex: Integer): IOTAEditor;
begin Result := Editors[AIndex]; end;
function TTestModule.Save(AForceSave, AForceSaveAs: Boolean): Boolean;
begin
  Check(TDAIOTA.DispatchDepth > 0, 'Save stays on IDE thread');
  Inc(SaveCount);
  Host.Events.Add('save');
  Result := True;
end;
function TTestModule.CloseModule(AForceClosed: Boolean): Boolean;
begin raise Exception.Create('Unexpected individual module close'); end;
procedure TTestModule.ShowFileName(const AFileName: string);
var
  LEditor: TTestSourceEditor;
begin
  Check(TDAIOTA.DispatchDepth > 0, 'ShowFilename stays on IDE thread');
  Inc(ShowCount);
  LastShownFile := AFileName;
  Host.Events.Add('show');
  if RaiseShowAbort then
    raise EAbort.Create('Synthetic native source display cancellation');
  if ShowCreatesSourceEditor then
  begin
    LEditor := TTestSourceEditor.Create;
    LEditor.FileName := AFileName;
    Editors := Editors + [LEditor as IOTAEditor];
  end;
end;
procedure TTestProject.RemoveFile(const AFileName: string);
begin raise Exception.Create('Unexpected project file removal'); end;
procedure TTestGroup.RemoveProject(const AProject: IOTAProject);
begin raise Exception.Create('Unexpected project removal'); end;
function TTestGroup.GetProjectCount: Integer;
begin Result := Length(TDAIOTA.TestProjects); end;
function TTestGroup.GetProject(AIndex: Integer): IOTAProject;
begin Result := TDAIOTA.TestProjects[AIndex]; end;
function TTestGroup.GetActiveProject: IOTAProject;
begin Result := TDAIOTA.TestActiveProject; end;
procedure TTestGroup.SetActiveProject(const AProject: IOTAProject);
begin TDAIOTA.TestActiveProject := AProject; end;

constructor TTestHost.Create;
begin
  inherited Create;
  Events := TList<string>.Create;
  Reset;
end;
destructor TTestHost.Destroy;
begin Events.Free; inherited; end;
procedure TTestHost.Reset;
begin
  LastCreatedInterface := nil;
  LastCreated := nil;
  LastOwner := nil;
  TDAIOTA.TestActiveProject := nil;
  TDAIOTA.TestGroup := nil;
  TDAIOTA.TestProjects := nil;
  TDAIOTA.TestModules := nil;
  TDAIOTA.TestReadOnlyFile := '';
  CloseCount := 0;
  OpenCount := 0;
  OpenFileCount := 0;
  CreateCount := 0;
  LastFile := '';
  LastNewGroup := False;
  LastUnnamed := False;
  CloseResult := True;
  OpenResult := True;
  RegisterOpenedTarget := True;
  RaiseCloseAbort := False;
  LeaveOpenAfterClose := False;
  EmptyGroupAfterClose := False;
  ChangeGroupOnAppend := False;
  Events.Clear;
end;
function TTestHost.GetMainProjectGroup: IOTAProjectGroup;
begin Result := TDAIOTA.TestGroup; end;
function TTestHost.GetActiveProject: IOTAProject;
begin Result := TDAIOTA.TestActiveProject; end;
function TTestHost.GetModuleCount: Integer;
begin Result := Length(TDAIOTA.TestModules); end;
function TTestHost.GetModule(AIndex: Integer): IOTAModule;
begin Result := TDAIOTA.TestModules[AIndex]; end;
function TTestHost.CloseAll: Boolean;
begin
  Check(TDAIOTA.DispatchDepth > 0, 'CloseAll stays on IDE thread');
  Inc(CloseCount);
  Events.Add('close');
  if RaiseCloseAbort then
    raise EAbort.Create('Synthetic native save cancellation');
  Result := CloseResult;
  if Result and not LeaveOpenAfterClose then
  begin
    TDAIOTA.TestModules := nil;
    TDAIOTA.TestProjects := nil;
    TDAIOTA.TestGroup := nil;
    TDAIOTA.TestActiveProject := nil;
    if EmptyGroupAfterClose then
    begin
      TDAIOTA.TestGroup := TTestGroup.Create(TPath.Combine(FixtureRoot, 'FreshEmpty.groupproj'));
      TDAIOTA.TestModules := [TDAIOTA.TestGroup as IOTAModule];
    end;
  end;
end;
function TTestHost.OpenFile(const AFileName: string): Boolean;
begin
  Inc(OpenFileCount);
  raise Exception.Create('Project opening must never use OpenFile');
end;
function TTestHost.OpenProject(const AFileName: string; ANewProjectGroup: Boolean): Boolean;
var LExtension: string;
begin
  Check(TDAIOTA.DispatchDepth > 0, 'OpenProject stays on IDE thread');
  Inc(OpenCount);
  Events.Add('open');
  LastFile := AFileName;
  LastNewGroup := ANewProjectGroup;
  Result := OpenResult;
  if not Result or not RegisterOpenedTarget then Exit;
  LExtension := LowerCase(TPath.GetExtension(AFileName));
  if (LExtension = '.groupproj') or (LExtension = '.bdsgroup') or (LExtension = '.bpg') then
  begin
    TDAIOTA.TestGroup := TTestGroup.Create(AFileName);
    TDAIOTA.TestModules := [TDAIOTA.TestGroup as IOTAModule];
  end
  else
  begin
    if ChangeGroupOnAppend and not ANewProjectGroup then
      TDAIOTA.TestGroup := TTestGroup.Create(TPath.Combine(FixtureRoot, 'Unexpected.groupproj'));
    AddProject(TTestProject.Create(AFileName));
  end;
end;
function TTestHost.CreateModule(const ACreator: IOTACreator): IOTAModule;
begin
  Check(TDAIOTA.DispatchDepth > 0, 'CreateModule stays on IDE thread');
  Inc(CreateCount);
  Events.Add('create');
  LastOwner := ACreator.GetOwner;
  LastUnnamed := ACreator.GetUnnamed;
  LastFile := ACreator.GetFileName;
  LastCreated := TTestProject.Create(LastFile);
  LastCreatedInterface := LastCreated;
  AddProject(LastCreatedInterface);
  Result := LastCreatedInterface;
end;

procedure ExistingWorkspace(const AWithGroup: Boolean = True);
begin
  Host.Reset;
  if AWithGroup then
  begin
    TDAIOTA.TestGroup := TTestGroup.Create(TPath.Combine(FixtureRoot, 'Existing.groupproj'));
    TDAIOTA.TestModules := [TDAIOTA.TestGroup as IOTAModule];
  end;
  AddProject(TTestProject.Create(TPath.Combine(FixtureRoot, 'Existing.dpr')));
end;

procedure OpenProjects;
var
  LExtension: string;
  LResult: TJSONObject;
  LOriginalGroup: IOTAProjectGroup;
begin
  for LExtension in ['.dpr', '.dpk', '.dproj'] do
  begin
    ExistingWorkspace;
    LOriginalGroup := TDAIOTA.TestGroup;
    LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target' + LExtension));
    try
      Check(JsonBoolean(LResult, 'opened'), LExtension + ' is reported opened');
      Check(not JsonBoolean(LResult, 'already_open'), LExtension + ' target was new');
      Check((Host.OpenCount = 1) and (Host.OpenFileCount = 0), LExtension + ' uses native project action');
      Check(not Host.LastNewGroup, LExtension + ' defaults to append');
      Check(Host.CloseCount = 0, LExtension + ' does not close workspace by default');
      Check(TDAIOTA.TestGroup = LOriginalGroup, LExtension + ' retains original group');
      Check(Length(TDAIOTA.TestProjects) = 2, LExtension + ' retains existing project');
    finally LResult.Free; end;
  end;

  ExistingWorkspace;
  LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Existing.dpr'));
  try
    Check(JsonBoolean(LResult, 'already_open'), 'default already-open request is idempotent');
    Check((Host.OpenCount = 0) and (Host.CloseCount = 0), 'already-open default does not change workspace');
  finally LResult.Free; end;

  ExistingWorkspace;
  LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'), True);
  try
    Check(JsonBoolean(LResult, 'opened'), 'explicit replacement opens target');
    Check((Host.CloseCount = 1) and (Host.OpenCount = 1), 'replacement closes before opening');
    Check(Host.LastNewGroup, 'explicit replacement requests a new group');
    Check((Host.Events[0] = 'close') and (Host.Events[1] = 'open'), 'close precedes native open');
    Check(Length(TDAIOTA.TestProjects) = 1, 'replacement does not retain old project');
  finally LResult.Free; end;

  ExistingWorkspace;
  LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Existing.dpr'), True);
  try
    Check(JsonBoolean(LResult, 'opened'), 'already-open replacement reopens target');
    Check((Host.CloseCount = 1) and (Host.OpenCount = 1), 'close_others is honored for an already-open target');
    Check(Length(TDAIOTA.TestProjects) = 1, 'already-open replacement clears other projects');
  finally LResult.Free; end;

  for LExtension in ['.groupproj', '.bdsgroup', '.bpg'] do
  begin
    ExistingWorkspace;
    LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target' + LExtension));
    try
      Check(JsonBoolean(LResult, 'opened'), LExtension + ' group is reported opened');
      Check((Host.CloseCount = 1) and (Host.OpenCount = 1), LExtension + ' inherently replaces workspace');
      Check(Host.LastNewGroup, LExtension + ' uses new group flag');
      Check(TDAIOTA.SameFile(TDAIOTA.TestGroup.FileName, Host.LastFile), LExtension + ' verifies target group');
    finally LResult.Free; end;
  end;
end;

procedure CancelAndValidateOpen;
var
  LCancelled, LFailed: Boolean;
  LResult: TJSONObject;
  LExtension: string;
begin
  for LExtension in ['.dpr', '.groupproj'] do
  begin
    ExistingWorkspace;
    Host.CloseResult := False;
    LCancelled := False;
    try
      LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target' + LExtension), True);
      LResult.Free;
    except on E: EAbort do LCancelled := True; end;
    Check(LCancelled, LExtension + ' false CloseAll is cancellation');
    Check((Host.OpenCount = 0) and (Host.CreateCount = 0), LExtension + ' cancelled close never opens target');
    Check(Length(TDAIOTA.TestProjects) = 1, LExtension + ' cancellation preserves fixture workspace');
  end;

  ExistingWorkspace;
  Host.RaiseCloseAbort := True;
  LCancelled := False;
  try
    LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'), True);
    LResult.Free;
  except on E: EAbort do LCancelled := True; end;
  Check(LCancelled and (Host.OpenCount = 0), 'native EAbort propagates before opening');

  ExistingWorkspace;
  Host.LeaveOpenAfterClose := True;
  LFailed := False;
  try
    LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'), True);
    LResult.Free;
  except on E: EInvalidOperation do LFailed := True; end;
  Check(LFailed and (Host.OpenCount = 0), 'reported close success with remaining workspace stops replacement');

  for LExtension in ['.txt', '.pas', '.missing'] do
  begin
    ExistingWorkspace;
    LFailed := False;
    try
      LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target' + LExtension), True);
      LResult.Free;
    except on E: Exception do LFailed := (E is EArgumentException) or (E is EDAIFileNotFound); end;
    Check(LFailed, LExtension + ' rejects unsupported or missing target');
    Check((Host.CloseCount = 0) and (Host.OpenCount = 0), LExtension + ' validates before closing workspace');
  end;

  ExistingWorkspace(False);
  LFailed := False;
  try
    LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'));
    LResult.Free;
  except on E: EInvalidOperation do LFailed := True; end;
  Check(LFailed and (Host.CloseCount = 0) and (Host.OpenCount = 0), 'true unbound project is protected during append');

  ExistingWorkspace;
  Host.OpenResult := False;
  LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'));
  try Check(not JsonBoolean(LResult, 'opened'), 'native open false is not reported as success'); finally LResult.Free; end;

  ExistingWorkspace;
  Host.RegisterOpenedTarget := False;
  LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'));
  try Check(not JsonBoolean(LResult, 'opened'), 'native true without loaded target is not reported as success'); finally LResult.Free; end;

  ExistingWorkspace;
  Host.ChangeGroupOnAppend := True;
  LFailed := False;
  try
    LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'));
    LResult.Free;
  except on E: EInvalidOperation do LFailed := True; end;
  Check(LFailed, 'unexpected group switch during append is reported');
end;

procedure CreateProjects;
var
  LDirectory: string;
  LResult: TJSONObject;
  LOriginalGroup: IOTAProjectGroup;
  LFailed: Boolean;
  LModule: TTestModule;
  LEditor: TTestEditor;
begin
  ExistingWorkspace;
  LOriginalGroup := TDAIOTA.TestGroup;
  LDirectory := TPath.Combine(FixtureRoot, 'Unsaved');
  LResult := TDAIProjectService.CreateProject('NewUnsaved', LDirectory, 'console', False);
  try
    Check(JsonBoolean(LResult, 'created') and not JsonBoolean(LResult, 'saved'), 'save=false creates an unsaved IDE project');
    Check((Host.LastOwner as IOTAProjectGroup) = LOriginalGroup, 'new project is owned by current group');
    Check(Host.LastUnnamed and (Host.LastCreated.SaveCount = 0), 'save=false retains unnamed creator and never saves');
    Check((Host.CloseCount = 0) and (Host.CreateCount = 1), 'create defaults to append');
    Check(Length(TDAIOTA.TestProjects) = 2, 'create preserves original project');
    Check(not TDirectory.Exists(LDirectory), 'save=false does not create target directory');
  finally LResult.Free; end;

  ExistingWorkspace;
  LDirectory := TPath.Combine(FixtureRoot, 'Saved');
  LResult := TDAIProjectService.CreateProject('NewSaved', LDirectory, 'console');
  try
    Check(JsonBoolean(LResult, 'saved'), 'default save remains true');
    Check(not Host.LastUnnamed and (Host.LastCreated.SaveCount = 1), 'saved creator keeps native save behavior');
    Check(TDirectory.Exists(LDirectory), 'save=true creates target directory');
    Check(Host.CloseCount = 0, 'default saved creation keeps current workspace');
  finally LResult.Free; end;

  ExistingWorkspace;
  LResult := TDAIProjectService.CreateProject('NewReplacement', TPath.Combine(FixtureRoot, 'Replacement'), 'console', False, True);
  try
    Check(JsonBoolean(LResult, 'created'), 'close_others creation succeeds');
    Check((Host.CloseCount = 1) and (Host.CreateCount = 1), 'close_others creation closes workspace first');
    Check(Host.LastOwner = nil, 'creator does not retain closed group as owner');
    Check((Host.Events[0] = 'close') and (Host.Events[1] = 'create'), 'close precedes module creation');
    Check(Length(TDAIOTA.TestProjects) = 1, 'replacement creation leaves only new project');
  finally LResult.Free; end;

  ExistingWorkspace;
  Host.CloseResult := False;
  LDirectory := TPath.Combine(FixtureRoot, 'Cancelled');
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('NewCancelled', LDirectory, 'console', True, True);
    LResult.Free;
  except on E: EAbort do LFailed := True; end;
  Check(LFailed and (Host.CreateCount = 0), 'cancelled close never creates project');
  Check(not TDirectory.Exists(LDirectory), 'cancelled close creates no target directory');

  ExistingWorkspace;
  Host.RaiseCloseAbort := True;
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('NativeAbort', FixtureRoot, 'console', False, True);
    LResult.Free;
  except on E: EAbort do LFailed := True; end;
  Check(LFailed and (Host.CreateCount = 0), 'native close EAbort prevents creation');

  ExistingWorkspace;
  Host.LeaveOpenAfterClose := True;
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('NotClosed', FixtureRoot, 'console', False, True);
    LResult.Free;
  except on E: EInvalidOperation do LFailed := True; end;
  Check(LFailed and (Host.CreateCount = 0), 'remaining projects after CloseAll prevent creation');

  ExistingWorkspace;
  Host.EmptyGroupAfterClose := True;
  LOriginalGroup := TDAIOTA.TestGroup;
  LResult := TDAIProjectService.CreateProject('FreshOwner', FixtureRoot, 'console', False, True);
  try
    Check(JsonBoolean(LResult, 'created'), 'empty implicit group after closing allows creation');
    Check((Host.LastOwner as IOTAProjectGroup) = TDAIOTA.TestGroup, 'creator uses newly fetched empty group');
    Check((Host.LastOwner as IOTAProjectGroup) <> LOriginalGroup, 'creator does not reuse old closed group');
  finally LResult.Free; end;

  ExistingWorkspace;
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('Existing', FixtureRoot, 'console', True, True);
    LResult.Free;
  except on E: EDAIFileAlreadyExists do LFailed := True; end;
  Check(LFailed and (Host.CloseCount = 0), 'existing project file is rejected before closing');

  ExistingWorkspace;
  AddProject(TTestProject.Create(TPath.Combine(FixtureRoot, 'LoadedOnly.dpr')));
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('LoadedOnly', FixtureRoot, 'console', True, True);
    LResult.Free;
  except on E: EDAIFileAlreadyExists do LFailed := True; end;
  Check(LFailed and (Host.CloseCount = 0), 'existing IDE-only project is rejected before closing');

  ExistingWorkspace;
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('InvalidKind', FixtureRoot, 'unknown', True, True);
    LResult.Free;
  except on E: EArgumentException do LFailed := True; end;
  Check(LFailed and (Host.CloseCount = 0), 'invalid project kind is rejected before closing');

  ExistingWorkspace;
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('Invalid name', FixtureRoot, 'console', True, True);
    LResult.Free;
  except on E: EArgumentException do LFailed := True; end;
  Check(LFailed and (Host.CloseCount = 0), 'invalid project name is rejected before closing');

  ExistingWorkspace(False);
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('UnboundAppend', FixtureRoot, 'console', False);
    LResult.Free;
  except on E: EInvalidOperation do LFailed := True; end;
  Check(LFailed and (Host.CloseCount = 0) and (Host.CreateCount = 0), 'true unbound project is protected during creation');

  ExistingWorkspace;
  TDAIOTA.TestReadOnlyFile := TPath.Combine(FixtureRoot, 'ReadOnlyReference.pas');
  LEditor := TTestEditor.Create;
  LEditor.FileName := TDAIOTA.TestReadOnlyFile;
  LEditor.Modified := True;
  LModule := TTestModule.Create(LEditor.FileName);
  LModule.Editors := [LEditor];
  TDAIOTA.TestModules := TDAIOTA.TestModules + [LModule as IOTAModule];
  LFailed := False;
  try
    LResult := TDAIProjectService.CreateProject('ReadOnlyGuard', FixtureRoot, 'console', False, True);
    LResult.Free;
  except on E: EDAIAccessDenied do LFailed := True; end;
  Check(LFailed and (Host.CloseCount = 0) and (Host.CreateCount = 0), 'modified reference editor blocks CloseAll before save could occur');

  LEditor.Modified := False;
  LResult := TDAIProjectService.CreateProject('UnmodifiedGuard', FixtureRoot, 'console', False, True);
  try
    Check(JsonBoolean(LResult, 'created') and (Host.CloseCount = 1), 'unmodified reference editor does not block workspace close');
  finally LResult.Free; end;
end;

procedure ImplicitGroupProjects;
var
  LResult: TJSONObject;
  LImplicitGroup: IOTAProjectGroup;
begin
  // A normal single project still belongs to the IDE's implicit, unsaved group.
  // This differs from a genuinely unbound package (nil MainProjectGroup).
  ExistingWorkspace;
  TDAIOTA.TestGroup := TTestGroup.Create('');
  TDAIOTA.TestModules[0] := TDAIOTA.TestGroup as IOTAModule;
  LImplicitGroup := TDAIOTA.TestGroup;
  LResult := TDAIProjectService.OpenProject(TPath.Combine(FixtureRoot, 'Target.dpr'));
  try
    Check(JsonBoolean(LResult, 'opened'), 'normal single project accepts another project in its implicit group');
    Check((Host.CloseCount = 0) and not Host.LastNewGroup, 'implicit group append avoids replacement');
    Check((TDAIOTA.TestGroup = LImplicitGroup) and (Length(TDAIOTA.TestProjects) = 2), 'implicit group and original project remain loaded');
  finally LResult.Free; end;
  LResult := TDAIProjectService.CreateProject('ImplicitOwner', FixtureRoot, 'console', False);
  try
    Check(JsonBoolean(LResult, 'created'), 'new project can be created in implicit group');
    Check((Host.LastOwner as IOTAProjectGroup) = LImplicitGroup, 'creator uses implicit group as owner');
    Check((Host.CloseCount = 0) and (Length(TDAIOTA.TestProjects) = 3), 'implicit creation retains all previous projects');
  finally LResult.Free; end;
end;

procedure OpenLoadedProjectSources;
var
  LEditor: TTestEditor;
  LExtension, LFileName: string;
  LFailed: Boolean;
  LOriginalGroup: IOTAProjectGroup;
  LModule: TTestModule;
  LProject: TTestProject;
  LResult: TJSONObject;
begin
  for LExtension in ['.dpr', '.dpk'] do
  begin
    ExistingWorkspace;
    LOriginalGroup := TDAIOTA.TestGroup;
    LFileName := TPath.Combine(FixtureRoot, 'Target' + LExtension);
    LProject := TTestProject.Create(LFileName);
    AddProject(LProject);
    LProject.ShowCreatesSourceEditor := True;
    LResult := TDAIProjectService.OpenFile(LFileName);
    try
      Check(JsonBoolean(LResult, 'opened'), LExtension + ' loaded source uses native module display');
      Check(JsonBoolean(LResult, 'source_editor_available'), LExtension + ' verifies editor availability after native display');
      Check((LProject.ShowCount = 1) and (LProject.LastShownFile = LFileName), LExtension + ' displays the exact loaded source');
      Check((Host.OpenCount = 0) and (Host.OpenFileCount = 0) and (Host.CloseCount = 0) and (Host.CreateCount = 0),
        LExtension + ' source display never opens or replaces a project');
      Check((TDAIOTA.TestGroup = LOriginalGroup) and (Length(TDAIOTA.TestProjects) = 2), LExtension + ' source display preserves the workspace');
      Check(LProject.SaveCount = 0, LExtension + ' source display never saves the project');
    finally LResult.Free; end;
  end;

  ExistingWorkspace;
  LFileName := TPath.Combine(FixtureRoot, 'NotSavedYet.dpr');
  LProject := TTestProject.Create(LFileName);
  AddProject(LProject);
  Check(not TFile.Exists(LFileName), 'unsaved source fixture has no disk file');
  LResult := TDAIProjectService.OpenFile(LFileName);
  try
    Check(JsonBoolean(LResult, 'opened'), 'unsaved loaded source can request native display without disk existence');
    Check(not JsonBoolean(LResult, 'source_editor_available'), 'native show request does not invent a verified text editor');
    Check((LProject.ShowCount = 1) and (LProject.SaveCount = 0), 'unsaved source uses native display without saving');
    Check(not TFile.Exists(LFileName), 'unsaved source display creates no disk file');
  finally LResult.Free; end;

  ExistingWorkspace;
  LFileName := TPath.Combine(FixtureRoot, 'Target.dpk');
  LProject := TTestProject.Create(TPath.Combine(FixtureRoot, 'Target.dproj'));
  LEditor := TTestSourceEditor.Create;
  LEditor.FileName := LFileName;
  LEditor.Modified := True;
  LProject.Editors := [LEditor as IOTAEditor];
  AddProject(LProject);
  LResult := TDAIProjectService.OpenFile(LFileName);
  try
    Check(JsonBoolean(LResult, 'opened') and JsonBoolean(LResult, 'source_editor_available'), 'actual source editor of metadata-named project is accepted');
    Check((LProject.ShowCount = 1) and (LProject.SaveCount = 0) and LEditor.Modified, 'existing modified source editor remains unsaved');
    Check(LProject.Editors[0] = (LEditor as IOTAEditor), 'existing source editor is retained');
  finally LResult.Free; end;

  ExistingWorkspace;
  LProject := TTestProject.Create(TPath.Combine(FixtureRoot, 'Target.dproj'));
  LEditor := TTestEditor.Create;
  LEditor.FileName := TPath.Combine(FixtureRoot, 'Target.dpr');
  LProject.Editors := [LEditor as IOTAEditor];
  AddProject(LProject);
  LFailed := False;
  try
    LResult := TDAIProjectService.OpenFile(LEditor.FileName);
    LResult.Free;
  except on E: EArgumentException do LFailed := True; end;
  Check(LFailed and (LProject.ShowCount = 0), 'matching project metadata and a non-source editor do not invent a DPR');

  ExistingWorkspace;
  LFileName := TPath.Combine(FixtureRoot, 'Target.dpr');
  TDAIOTA.TestModules := TDAIOTA.TestModules + [TTestModule.Create(LFileName) as IOTAModule];
  LFailed := False;
  try
    LResult := TDAIProjectService.OpenFile(LFileName);
    LResult.Free;
  except on E: EArgumentException do LFailed := True; end;
  Check(LFailed and (Host.OpenCount = 0), 'ordinary text module is not treated as a loaded project');

  for LExtension in ['.dpr', '.dpk', '.dproj', '.groupproj', '.bdsgroup', '.bpg'] do
  begin
    ExistingWorkspace;
    LFailed := False;
    try
      LResult := TDAIProjectService.OpenFile(TPath.Combine(FixtureRoot, 'Target' + LExtension));
      LResult.Free;
    except on E: EArgumentException do LFailed := True; end;
    Check(LFailed, LExtension + ' unloaded project or metadata requires project_open');
    Check((Host.OpenCount = 0) and (Host.OpenFileCount = 0) and (Host.CloseCount = 0), LExtension + ' refusal preserves workspace');
  end;

  for LExtension in ['.dproj', '.groupproj', '.bdsgroup', '.bpg'] do
  begin
    ExistingWorkspace;
    LFileName := TPath.Combine(FixtureRoot, 'Target' + LExtension);
    if LExtension = '.dproj' then
    begin
      LProject := TTestProject.Create(LFileName);
      LModule := LProject;
      AddProject(LProject);
    end
    else
    begin
      LModule := TTestGroup.Create(LFileName);
      TDAIOTA.TestModules := TDAIOTA.TestModules + [LModule as IOTAModule];
    end;
    LFailed := False;
    try
      LResult := TDAIProjectService.OpenFile(LFileName);
      LResult.Free;
    except on E: EArgumentException do LFailed := True; end;
    Check(LFailed and (LModule.ShowCount = 0), LExtension + ' loaded metadata cannot be shown as project source');
    Check((Host.OpenCount = 0) and (Host.OpenFileCount = 0) and (LModule.SaveCount = 0), LExtension + ' metadata refusal has no fallback or save');
  end;

  ExistingWorkspace;
  LProject := TTestProject.Create(TPath.Combine(FixtureRoot, 'Target.dpk'));
  LProject.RaiseShowAbort := True;
  AddProject(LProject);
  LFailed := False;
  try
    LResult := TDAIProjectService.OpenFile(LProject.GetFileName);
    LResult.Free;
  except on E: EAbort do LFailed := True; end;
  Check(LFailed and (LProject.ShowCount = 1), 'native source display cancellation propagates');
  Check((Host.OpenCount = 0) and (Host.OpenFileCount = 0) and (LProject.SaveCount = 0), 'native display failure never falls back to project open or save');
end;

procedure CreateFixtures;
var
  LGuid: TGUID;
  LFile: string;
begin
  CreateGUID(LGuid);
  FixtureRoot := TPath.Combine(TPath.GetTempPath, 'DAI-ProjectGroupTests-' + GUIDToString(LGuid));
  TDirectory.CreateDirectory(FixtureRoot);
  for LFile in ['Existing.dpr', 'Existing.groupproj', 'Target.dpr', 'Target.dpk', 'Target.dproj',
    'Target.groupproj', 'Target.bdsgroup', 'Target.bpg', 'Target.txt', 'Target.pas'] do
    TFile.WriteAllText(TPath.Combine(FixtureRoot, LFile), 'isolated fixture');
end;

begin
  try
    Check(BorlandIDEServices = nil, 'test starts without any IDE host');
    Host := TTestHost.Create;
    HostInterface := Host;
    BorlandIDEServices := HostInterface;
    CreateFixtures;
    try
      OpenProjects;
      CancelAndValidateOpen;
      CreateProjects;
      ImplicitGroupProjects;
      OpenLoadedProjectSources;
      Check(Host.OpenFileCount = 0, 'project suite never uses OpenFile');
      Writeln('OK: ', CheckCount, ' isolated native project-group checks (', SizeOf(Pointer) * 8, '-bit)');
    finally
      Host.Reset;
      BorlandIDEServices := nil;
      HostInterface := nil;
      Host := nil;
      if (FixtureRoot <> '') and TDAIOTA.IsPathWithin(FixtureRoot, TPath.GetTempPath) and
        TPath.GetFileName(FixtureRoot).StartsWith('DAI-ProjectGroupTests-') then
        TDirectory.Delete(FixtureRoot, True);
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
