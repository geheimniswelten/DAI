program TestLoadedFiles;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.LoadedFiles;

type
  TDAIOTA = class
    class var ReferenceFile: string;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function LoadedFileNames: TArray<string>; static;
    class function IsFileLoadedInIDE(const AFileName: string): Boolean; static;
    class function FindModuleByFileName(const AFileName: string): IOTAModule; static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
    class function Projects: TArray<IOTAProject>; static;
    class function ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean; static;
    class function WorkspaceRoots: TArray<string>; static;
    class function IsPathWithin(const AFileName, ARoot: string): Boolean; static;
  end;

// These environment adapters force the real IsWorkspaceFile method to exercise its loaded-file fallback.
class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin Result := (ReferenceFile <> '') and SameText(AFileName, ReferenceFile); end;
class function TDAIOTA.Projects: TArray<IOTAProject>;
begin Result := nil; end;
class function TDAIOTA.ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean;
begin raise EInvalidOperation.Create('The isolated fixture has no project members.'); end;
class function TDAIOTA.WorkspaceRoots: TArray<string>;
begin Result := nil; end;
class function TDAIOTA.IsPathWithin(const AFileName, ARoot: string): Boolean;
begin raise EInvalidOperation.Create('The isolated fixture has no workspace roots.'); end;

{$I DAI.LoadedFiles.Helpers.inc}

type
  TFakeModule = class(TInterfacedObject, IOTAModule, IOTAAdditionalModuleFiles)
    FileName: string;
    Editors, Additional: TArray<IOTAEditor>;
    Associated: TArray<string>;
    RaiseOnAssociations: Boolean;
    constructor Create(const AFileName: string);
    function GetFileName: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(AIndex: Integer): IOTAEditor;
    procedure GetAssociatedFilesFromModule(AFiles: TStrings);
    function GetAdditionalModuleFileCount: Integer;
    function GetAdditionalModuleFileEditor(AIndex: Integer): IOTAEditor;
  end;
  TFakeProject = class(TFakeModule, IOTAProject)
    Associations: TDictionary<string, TArray<string>>;
    RaiseOnProjectAssociations: Boolean;
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    procedure GetAssociatedFiles(const AFileName: string; AFiles: TStrings);
  end;
  TFakeGroup = class(TFakeModule, IOTAProjectGroup)
    Projects: TArray<IOTAProject>;
    function GetProjectCount: Integer;
    function GetProject(AIndex: Integer): IOTAProject;
  end;
  TFakeEditor = class(TInterfacedObject, IOTAEditor, IOTASourceEditor, IOTAEditBuffer)
    FileName: string;
    // Weak owner reference avoids fixture cycles; its lifetime is held by the host/snapshot.
    OwnerModule: TFakeModule;
    constructor Create(const AFileName: string; AOwner: TFakeModule = nil);
    function GetFileName: string;
    function GetModule: IOTAModule;
  end;
  TFakeHost = class(TInterfacedObject, IOTAModuleServices, IOTAEditorServices, IOTAEditBufferIterator)
    Modules: TArray<IOTAModule>;
    HiddenModules: TArray<IOTAModule>;
    Buffers: TArray<IOTAEditBuffer>;
    Group: IOTAProjectGroup;
    ActiveProject: IOTAProject;
    RaiseOnEnumeration, RaiseOnIterator: Boolean;
    NilIterator, NoIterator: Boolean;
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    function GetMainProjectGroup: IOTAProjectGroup;
    function GetActiveProject: IOTAProject;
    function FindModule(const AFileName: string): IOTAModule;
    function GetEditBufferIterator(out AIterator: IOTAEditBufferIterator): Boolean;
    function GetCount: Integer;
    function GetEditBuffer(AIndex: Integer): IOTAEditBuffer;
  end;
  TModulesOnly = class(TInterfacedObject, IOTAModuleServices)
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    function GetMainProjectGroup: IOTAProjectGroup;
    function GetActiveProject: IOTAProject;
    function FindModule(const AFileName: string): IOTAModule;
  end;

var
  Checks: Integer;
  Host: TFakeHost;
  FaultyModule: TFakeModule;
  FaultyProject: TFakeProject;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function Path(const ARelative: string): string;
begin Result := TPath.Combine('C:\DAILoadedFilesFixture', ARelative); end;

constructor TFakeModule.Create(const AFileName: string);
begin inherited Create; FileName := AFileName; end;
function TFakeModule.GetFileName: string;
begin Result := FileName; end;
function TFakeModule.GetModuleFileCount: Integer;
begin Result := Length(Editors); end;
function TFakeModule.GetModuleFileEditor(AIndex: Integer): IOTAEditor;
begin Result := Editors[AIndex]; end;
procedure TFakeModule.GetAssociatedFilesFromModule(AFiles: TStrings);
var LFile: string;
begin
  if RaiseOnAssociations then
    raise EInvalidOperation.Create('Synthetic native module association error.');
  for LFile in Associated do
    AFiles.Add(LFile);
end;
function TFakeModule.GetAdditionalModuleFileCount: Integer;
begin Result := Length(Additional); end;
function TFakeModule.GetAdditionalModuleFileEditor(AIndex: Integer): IOTAEditor;
begin Result := Additional[AIndex]; end;
constructor TFakeProject.Create(const AFileName: string);
begin
  inherited;
  RaiseOnAssociations := True; // Reading whole-project module associations would incorrectly mark closed units as loaded.
  Associations := TDictionary<string, TArray<string>>.Create(TIStringComparer.Ordinal);
end;
destructor TFakeProject.Destroy;
begin Associations.Free; inherited; end;
procedure TFakeProject.GetAssociatedFiles(const AFileName: string; AFiles: TStrings);
var LFile: string; LFiles: TArray<string>;
begin
  if RaiseOnProjectAssociations then
    raise EInvalidOperation.Create('Synthetic association enumeration error.');
  if Associations.TryGetValue(TPath.GetFullPath(AFileName), LFiles) then
    for LFile in LFiles do
      AFiles.Add(LFile);
end;
function TFakeGroup.GetProjectCount: Integer;
begin Result := Length(Projects); end;
function TFakeGroup.GetProject(AIndex: Integer): IOTAProject;
begin Result := Projects[AIndex]; end;
constructor TFakeEditor.Create(const AFileName: string; AOwner: TFakeModule);
begin inherited Create; FileName := AFileName; OwnerModule := AOwner; end;
function TFakeEditor.GetFileName: string;
begin Result := FileName; end;
function TFakeEditor.GetModule: IOTAModule;
begin Result := OwnerModule; end;
function TFakeHost.GetModuleCount: Integer;
begin
  if RaiseOnEnumeration then
    raise EInvalidOperation.Create('Synthetic module enumeration error.');
  Result := Length(Modules);
end;
function TFakeHost.GetModule(AIndex: Integer): IOTAModule;
begin Result := Modules[AIndex]; end;
function TFakeHost.GetMainProjectGroup: IOTAProjectGroup;
begin Result := Group; end;
function TFakeHost.GetActiveProject: IOTAProject;
begin Result := ActiveProject; end;
function TFakeHost.FindModule(const AFileName: string): IOTAModule;
begin Result := nil; end;
function TFakeHost.GetEditBufferIterator(out AIterator: IOTAEditBufferIterator): Boolean;
begin
  if RaiseOnIterator then
    raise EInvalidOperation.Create('Synthetic buffer iterator error.');
  if NilIterator or NoIterator then
    AIterator := nil
  else
    AIterator := Self;
  Result := not NoIterator;
end;
function TFakeHost.GetCount: Integer;
begin Result := Length(Buffers); end;
function TFakeHost.GetEditBuffer(AIndex: Integer): IOTAEditBuffer;
begin Result := Buffers[AIndex]; end;
function TModulesOnly.GetModuleCount: Integer;
begin Result := 0; end;
function TModulesOnly.GetModule(AIndex: Integer): IOTAModule;
begin Result := nil; end;
function TModulesOnly.GetMainProjectGroup: IOTAProjectGroup;
begin Result := nil; end;
function TModulesOnly.GetActiveProject: IOTAProject;
begin Result := nil; end;
function TModulesOnly.FindModule(const AFileName: string): IOTAModule;
begin Result := nil; end;

procedure CheckFile(const AFileName: string; const AOwner: IOTAModule);
var LExpected: IOTAModule;
begin
  Supports(AOwner, IOTAModule, LExpected);
  Check(TDAIOTA.IsFileLoadedInIDE(LowerCase(AFileName)), AFileName + ' is loaded, independently of path case.');
  Check(TDAIOTA.FindModuleByFileName(UpperCase(AFileName)) = LExpected, AFileName + ' has the actual owning module.');
end;

procedure CheckProjects;
var
  LGroup: TFakeGroup;
  LApp, LPackage, LMetadata, LForeign, LStandalone: IOTAProject;
begin
  LApp := TFakeProject.Create(Path('App.dpr'));
  LPackage := TFakeProject.Create(Path('Package.dpk'));
  LMetadata := TFakeProject.Create(Path('OnlyMetadata.dproj'));
  LForeign := TFakeProject.Create(Path('Other.cbproj'));
  LStandalone := TFakeProject.Create(Path('Standalone.dpk'));
  LGroup := TFakeGroup.Create(Path('Projects.groupproj'));
  LGroup.Projects := [LApp, nil, LPackage, LMetadata, LForeign];
  Host.Group := LGroup;
  Host.ActiveProject := LStandalone;
  Host.Modules := [nil];
  CheckFile(Path('Projects.groupproj'), LGroup);
  CheckFile(Path('App.dpr'), LApp);
  CheckFile(Path('App.dproj'), LApp);
  CheckFile(Path('Package.dpk'), LPackage);
  CheckFile(Path('Package.dproj'), LPackage);
  CheckFile(Path('OnlyMetadata.dproj'), LMetadata);
  CheckFile(Path('Other.cbproj'), LForeign);
  CheckFile(Path('Standalone.dpk'), LStandalone);
  CheckFile(Path('Standalone.dproj'), LStandalone);
  Check(Length(TDAIOTA.LoadedFileNames) = 9, 'Projects without tabs are collected once.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('OnlyMetadata.dpr')), 'A DPROJ does not invent a DPR.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('OnlyMetadata.dpk')), 'A DPROJ does not invent a DPK.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('Other.dproj')), 'A foreign project does not invent a Delphi sidecar.');
  Check(not TFile.Exists(Path('App.dproj')), 'No physical sidecar is needed and no file was created.');
  Host.Modules := [LApp, LPackage, LGroup];
  Check(Length(TDAIOTA.LoadedFileNames) = 9, 'Explicit and enumerated projects are deduplicated.');
  Host.Group := nil;
  Host.Modules := nil;
  CheckFile(Path('Standalone.dproj'), LStandalone);
  Check(Length(TDAIOTA.LoadedFileNames) = 2, 'Standalone active package works without a group.');
end;

procedure CheckStandaloneForms;
var
  LVCL, LFMX: TFakeModule;
  LVCLRef, LFMXRef: IOTAModule;
begin
  Host.ActiveProject := nil;
  Host.Group := nil;
  Host.Buffers := nil;
  LVCL := TFakeModule.Create(Path('StandaloneForm.pas'));
  LVCLRef := LVCL;
  LVCL.Associated := [Path('StandaloneForm.dfm'), Path('StandaloneForm.res')];
  LFMX := TFakeModule.Create(Path('StandaloneMobile.fmx'));
  LFMXRef := LFMX;
  LFMX.Associated := [Path('StandaloneMobile.pas')];
  Host.Modules := [LVCLRef, LFMXRef];
  CheckFile(Path('StandaloneForm.dfm'), LVCLRef);
  CheckFile(Path('StandaloneMobile.pas'), LFMXRef);
  Check(Length(TDAIOTA.LoadedFileNames) = 4, 'Standalone form modules retain both files without project or editor tabs.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('StandaloneForm.res')), 'A standalone form does not load its resource file.');
end;

procedure CheckBuffersAndForms;
var
  LProject: TFakeProject;
  LModule, LFMXModule, LExtraModule, LLooseDPR: TFakeModule;
  LModuleRef, LFMXRef, LExtraRef: IOTAModule;
  LNames: TArray<string>;
  LIndex: Integer;
begin
  LProject := TFakeProject.Create(Path('Forms.dpr'));
  FaultyProject := LProject;
  Host.ActiveProject := LProject;
  LProject.Associations.Add(Path('Unit.pas'), [Path('Unit.dfm'), Path('Unit.res')]);
  LProject.Associations.Add(Path('Mobile.fmx'), [Path('Mobile.pas')]);
  LProject.Associations.Add(Path('ClosedUnit.pas'), [Path('ClosedUnit.dfm')]);
  LProject.Associations.Add(Path('Orphan.pas'), [Path('Orphan.dfm')]);
  LModule := TFakeModule.Create(Path('Unit.pas'));
  FaultyModule := LModule;
  LModuleRef := LModule;
  LModule.Associated := [Path('Unit.dfm'), Path('Unit.res')];
  LModule.Editors := [TFakeEditor.Create(Path('Sub\..\UNIT.PAS'), LModule), nil];
  LModule.Additional := [TFakeEditor.Create(Path('Extra.inc'), LModule)];
  LFMXModule := TFakeModule.Create(Path('Mobile.fmx'));
  LFMXModule.Associated := [Path('Mobile.pas')];
  LFMXRef := LFMXModule;
  LExtraModule := TFakeModule.Create(Path('BufferOwner.pas'));
  LExtraRef := LExtraModule;
  Host.HiddenModules := [LExtraRef];
  LLooseDPR := TFakeModule.Create(Path('NotAProject.dpr'));
  Host.Modules := [LModuleRef, LFMXRef, LLooseDPR];
  Host.Buffers := [TFakeEditor.Create(Path('Iterator.txt')), TFakeEditor.Create(Path('BUFFEROWNER.PAS')),
    TFakeEditor.Create(Path('BufferOwner.pas'), LExtraModule), TFakeEditor.Create(Path('Orphan.pas')), nil];
  CheckFile(Path('Unit.pas'), LModuleRef);
  CheckFile(Path('Unit.dfm'), LModuleRef);
  CheckFile(Path('Extra.inc'), LModuleRef);
  CheckFile(Path('Mobile.fmx'), LFMXRef);
  CheckFile(Path('Mobile.pas'), LFMXRef);
  CheckFile(Path('BufferOwner.pas'), LExtraRef);
  Check(TDAIOTA.IsFileLoadedInIDE(Path('Iterator.txt')), 'An iterator-only buffer is loaded even without a module.');
  Check(not Assigned(TDAIOTA.FindModuleByFileName(Path('Iterator.txt'))), 'An orphan buffer does not invent an owner.');
  Check(TDAIOTA.IsFileLoadedInIDE(Path('Orphan.dfm')), 'An orphan Pascal buffer retains its real project-associated form.');
  Check(not Assigned(TDAIOTA.FindModuleByFileName(Path('Orphan.dfm'))), 'An association does not invent a module owner for an orphan buffer.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('NotAProject.dproj')), 'Only a real IOTAProject gains its DPROJ sidecar.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('Unit.res')), 'A project resource is not treated as a loaded form.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('ClosedUnit.pas')), 'An unloaded project unit remains unloaded.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('ClosedUnit.dfm')), 'Its paired form remains unloaded too.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('Unit.fmx')), 'A VCL form does not invent an FMX file.');
  Check(not TDAIOTA.IsFileLoadedInIDE(Path('Mobile.dfm')), 'An FMX form does not invent a DFM file.');
  LNames := TDAIOTA.LoadedFileNames;
  Check(Length(LNames) = 12, 'Normalized duplicate buffer/module paths appear once.');
  for LIndex := 1 to High(LNames) do
    Check((TIStringComparer.Ordinal as IComparer<string>).Compare(LNames[LIndex - 1], LNames[LIndex]) < 0, 'Names are sorted and case-insensitively unique.');
  Check(TDAIOTA.IsWorkspaceFile(Path('Iterator.txt')), 'An out-of-root loaded buffer uses project permissions.');
  TDAIOTA.ReferenceFile := Path('Unit.dfm');
  Check(not TDAIOTA.IsWorkspaceFile(TDAIOTA.ReferenceFile), 'Loaded state never grants writes to a reference file.');
  TDAIOTA.ReferenceFile := '';
end;

procedure CheckFailures;
var
  LRaised: Boolean;
  LSavedServices: IInterface;
begin
  Host.RaiseOnEnumeration := True;
  LRaised := False;
  try TDAIOTA.IsFileLoadedInIDE(Path('Anything.pas')); except on E: EInvalidOperation do LRaised := True; end;
  Check(LRaised, 'Module enumeration failure does not become closed.');
  Host.RaiseOnEnumeration := False;
  Host.RaiseOnIterator := True;
  LRaised := False;
  try TDAIOTA.LoadedFileNames; except on E: EInvalidOperation do LRaised := True; end;
  Check(LRaised, 'Iterator failure does not return an incomplete success.');
  Host.RaiseOnIterator := False;
  FaultyModule.RaiseOnAssociations := True;
  LRaised := False;
  try TDAIOTA.IsFileLoadedInIDE(Path('Anything.pas')); except on E: EInvalidOperation do LRaised := True; end;
  Check(LRaised, 'Association failure does not become closed.');
  FaultyModule.RaiseOnAssociations := False;
  FaultyProject.RaiseOnProjectAssociations := True;
  LRaised := False;
  try TDAIOTA.IsFileLoadedInIDE(Path('Anything.pas')); except on E: EInvalidOperation do LRaised := True; end;
  Check(LRaised, 'Project fallback association failure does not become closed.');
  FaultyProject.RaiseOnProjectAssociations := False;
  Host.NilIterator := True;
  LRaised := False;
  try TDAIOTA.IsFileLoadedInIDE(Path('Anything.pas')); except on E: EInvalidOperation do LRaised := True; end;
  Check(LRaised, 'A successful iterator query with no iterator reports an unavailable status.');
  Host.NilIterator := False;
  Host.Buffers := nil;
  Host.NoIterator := True;
  Check(TDAIOTA.IsFileLoadedInIDE(Path('Unit.pas')), 'A false iterator result permits an empty iterator and retains loaded modules.');
  Host.NoIterator := False;
  LSavedServices := BorlandIDEServices;
  BorlandIDEServices := TModulesOnly.Create;
  LRaised := False;
  try TDAIOTA.IsFileLoadedInIDE(Path('Anything.pas')); except on E: EInvalidOperation do LRaised := True; end;
  Check(LRaised, 'Missing editor services do not report iterator-only buffers as closed.');
  BorlandIDEServices := LSavedServices;
  BorlandIDEServices := nil;
  LRaised := False;
  try TDAIOTA.IsFileLoadedInIDE(Path('Anything.pas')); except on E: EInvalidOperation do LRaised := True; end;
  Check(LRaised, 'Missing IDE services report an unavailable status.');
end;

begin
  try
    Host := TFakeHost.Create;
    BorlandIDEServices := Host;
    Check(Length(TDAIOTA.LoadedFileNames) = 0, 'An empty IDE has no loaded files.');
    Check(not TDAIOTA.IsFileLoadedInIDE(Path('Closed.pas')), 'An empty IDE reports an existing query path as closed.');
    CheckProjects;
    CheckStandaloneForms;
    CheckBuffersAndForms;
    CheckFailures;
    Writeln('LoadedFiles checks passed: ', Checks);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
  BorlandIDEServices := nil;
end.
