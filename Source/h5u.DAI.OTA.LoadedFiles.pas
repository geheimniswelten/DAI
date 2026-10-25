unit h5u.DAI.OTA.LoadedFiles;

interface

uses
  System.Generics.Collections,
  ToolsAPI;

type
  // Capture on the IDE thread. Module ownership is retained without opening or showing anything.
  TDAILoadedFiles = class sealed
  private
    FFiles: TDictionary<string, IOTAModule>;
    FModules: TList<IOTAModule>;
    FProjects: TList<IOTAProject>;
    class function NormalizeFileName(const AFileName: string): string; static;
    procedure AddFile(const AFileName: string; const AModule: IOTAModule);
    procedure AddEditor(const AEditor: IOTAEditor; const AModule: IOTAModule);
    procedure AddModule(const AModule: IOTAModule);
    procedure AddAssociatedForms;
  public
    constructor Create(const AServices: IInterface);
    destructor Destroy; override;
    function FileNames: TArray<string>;
    function Contains(const AFileName: string): Boolean;
    function FindModule(const AFileName: string): IOTAModule;
  end;

implementation

uses
  System.Classes,
  System.Generics.Defaults,
  System.IOUtils,
  System.SysUtils;

class function TDAILoadedFiles.NormalizeFileName(const AFileName: string): string;
begin
  if Trim(AFileName) = '' then
    Exit('');
  Result := TPath.GetFullPath(AFileName);
  if not SameText(Result, TPath.GetPathRoot(Result)) then
    Result := ExcludeTrailingPathDelimiter(Result);
end;

procedure TDAILoadedFiles.AddFile(const AFileName: string; const AModule: IOTAModule);
var
  LExisting: IOTAModule;
  LFileName: string;
begin
  LFileName := NormalizeFileName(AFileName);
  if LFileName = '' then
    Exit;
  if not FFiles.TryGetValue(LFileName, LExisting) then
    FFiles.Add(LFileName, AModule)
  else if not Assigned(LExisting) and Assigned(AModule) then
    FFiles.AddOrSetValue(LFileName, AModule);
end;

procedure TDAILoadedFiles.AddEditor(const AEditor: IOTAEditor; const AModule: IOTAModule);
var
  LModule: IOTAModule;
begin
  if not Assigned(AEditor) then
    Exit;
  LModule := AEditor.Module;
  if not Assigned(LModule) then
    LModule := AModule;
  AddModule(LModule);
  AddFile(AEditor.FileName, LModule);
end;

procedure TDAILoadedFiles.AddModule(const AModule: IOTAModule);
var
  LAdditional: IOTAAdditionalModuleFiles;
  LExtension: string;
  LGroup: IOTAProjectGroup;
  LIndex: Integer;
  LModule: IOTAModule;
  LProject: IOTAProject;
begin
  if not Assigned(AModule) then
    Exit;
  // A project/group interface can have a different interface pointer from its IOTAModule view.
  Supports(AModule, IOTAModule, LModule);
  if not Assigned(LModule) then
    raise EInvalidOperation.Create('Ein geladenes IDE-Modul stellt seine Modulansicht nicht bereit.');
  if FModules.Contains(LModule) then
    Exit;
  FModules.Add(LModule);
  AddFile(LModule.FileName, LModule);
  for LIndex := 0 to LModule.ModuleFileCount - 1 do
    AddEditor(LModule.ModuleFileEditors[LIndex], LModule);
  if Supports(LModule, IOTAAdditionalModuleFiles, LAdditional) then
    for LIndex := 0 to LAdditional.AdditionalModuleFileCount - 1 do
      AddEditor(LAdditional.AdditionalModuleFileEditors[LIndex], LModule);
  if Supports(LModule, IOTAProject, LProject) then
  begin
    if not FProjects.Contains(LProject) then
      FProjects.Add(LProject);
    // Delphi project options are loaded with their actual DPR/DPK, even before the first save.
    // The reverse mapping would invent a DPR for package or other project types.
    LExtension := TPath.GetExtension(LModule.FileName);
    if SameText(LExtension, '.dpr') or SameText(LExtension, '.dpk') then
      AddFile(ChangeFileExt(LModule.FileName, '.dproj'), LModule);
  end;
  if Supports(LModule, IOTAProjectGroup, LGroup) then
    for LIndex := 0 to LGroup.ProjectCount - 1 do
      AddModule(LGroup.Projects[LIndex]);
end;

procedure TDAILoadedFiles.AddAssociatedForms;
var
  LAssociated: TStringList;
  LExtension: string;
  LFileName: string;
  LInitialFiles: TArray<string>;
  LModule: IOTAModule;
  LProjectModule: IOTAProject;
  LGroupModule: IOTAProjectGroup;
  LProject: IOTAProject;
  procedure AddForms(const AOwner: IOTAModule);
  var
    LFile: string;
    LFileExtension: string;
  begin
    for LFile in LAssociated do
    begin
      LFileExtension := TPath.GetExtension(LFile);
      if SameText(LFileExtension, '.pas') or SameText(LFileExtension, '.dfm') or SameText(LFileExtension, '.fmx') then
        AddFile(LFile, AOwner);
    end;
  end;
begin
  LAssociated := TStringList.Create;
  try
    // A loaded unit owns its associated form even without a project or visible editor.
    // Project/group association lists must not turn all their members into loaded files.
    for LModule in FModules do
      if not Supports(LModule, IOTAProject, LProjectModule) and not Supports(LModule, IOTAProjectGroup, LGroupModule) then
      begin
        LAssociated.Clear;
        LModule.GetAssociatedFilesFromModule(LAssociated);
        AddForms(LModule);
      end;
    LInitialFiles := FFiles.Keys.ToArray;
    for LFileName in LInitialFiles do
    begin
      LModule := FFiles[LFileName];
      if Assigned(LModule) then
        Continue;
      LExtension := TPath.GetExtension(LFileName);
      if not SameText(LExtension, '.pas') and not SameText(LExtension, '.dfm') and not SameText(LExtension, '.fmx') then
        Continue;
      // Only orphan text buffers need the slower project association fallback.
      for LProject in FProjects do
      begin
        LAssociated.Clear;
        LProject.GetAssociatedFiles(LFileName, LAssociated);
        AddForms(nil);
      end;
    end;
  finally
    LAssociated.Free;
  end;
end;

constructor TDAILoadedFiles.Create(const AServices: IInterface);
var
  LEditorServices: IOTAEditorServices;
  LIndex: Integer;
  LIterator: IOTAEditBufferIterator;
  LModuleServices: IOTAModuleServices;
begin
  inherited Create;
  FFiles := TDictionary<string, IOTAModule>.Create(TIStringComparer.Ordinal);
  FModules := TList<IOTAModule>.Create;
  FProjects := TList<IOTAProject>.Create;
  if not Supports(AServices, IOTAModuleServices, LModuleServices) then
    raise EInvalidOperation.Create('Der geladene IDE-Dateizustand ist nicht verfügbar: IOTAModuleServices fehlt.');
  for LIndex := 0 to LModuleServices.ModuleCount - 1 do
    AddModule(LModuleServices.Modules[LIndex]);
  AddModule(LModuleServices.MainProjectGroup);
  AddModule(LModuleServices.GetActiveProject);
  if not Supports(AServices, IOTAEditorServices, LEditorServices) then
    raise EInvalidOperation.Create('Der geladene IDE-Dateizustand ist nicht vollständig verfügbar: IOTAEditorServices fehlt.');
  if LEditorServices.GetEditBufferIterator(LIterator) then
  begin
    if not Assigned(LIterator) then
      raise EInvalidOperation.Create('Der Editorpuffer-Iterator wurde als verfügbar gemeldet, ist aber nicht lesbar.');
    for LIndex := 0 to LIterator.Count - 1 do
      AddEditor(LIterator.EditBuffers[LIndex], nil);
  end;
  AddAssociatedForms;
end;

destructor TDAILoadedFiles.Destroy;
begin
  FProjects.Free;
  FModules.Free;
  FFiles.Free;
  inherited;
end;

function TDAILoadedFiles.FileNames: TArray<string>;
begin
  Result := FFiles.Keys.ToArray;
  TArray.Sort<string>(Result, TIStringComparer.Ordinal);
end;

function TDAILoadedFiles.Contains(const AFileName: string): Boolean;
begin
  Result := FFiles.ContainsKey(NormalizeFileName(AFileName));
end;

function TDAILoadedFiles.FindModule(const AFileName: string): IOTAModule;
begin
  if not FFiles.TryGetValue(NormalizeFileName(AFileName), Result) then
    Result := nil;
end;

end.
