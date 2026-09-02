unit CodexMCP.OTA.Common;

interface

uses
  System.Actions,
  System.SysUtils,
  ToolsAPI,
  Vcl.Menus;

type
  TCodexPathAccess = (
    cpaForbidden,
    cpaWorkspaceReadWrite,
    cpaReadOnlyReference
  );

  TCodexReadOnlyRoot = record
    Name: string;
    Path: string;
    Source: string;
    Exists: Boolean;
  end;

function ExpandEnvironmentPath(const APath: string): string;
function NormalizePath(const APath: string): string;
function ResolveRequestedPath(const APath: string): string;
function IsPathWithin(const APath, ARoot: string): Boolean;
function ProjectDirectory(const AProject: IOTAProject): string;
function CollectProjects: TArray<IOTAProject>;
function FindProject(const AIdentifier: string): IOTAProject;
function FindModuleForFile(const AFileName: string): IOTAModule;
function FindSourceEditor(const AFileName: string): IOTASourceEditor;
function FindFormEditor(
  const AFileName: string;
  out AModule: IOTAModule
): IOTAFormEditor;
function ReadEditorText(const AEditor: IOTASourceEditor): string;
function ReplaceEditorText(
  const AEditor: IOTASourceEditor;
  const AText: string
): Boolean;
function SaveFileThroughIDE(const AFileName: string): Boolean;
function OpenOrActivateFile(const AFileName: string): Boolean;
function CloseFileThroughIDE(
  const AFileName: string;
  const AForce: Boolean
): Boolean;
function GetReadOnlyRoots: TArray<TCodexReadOnlyRoot>;
function ClassifyPath(const AFileName: string): TCodexPathAccess;
function IsInsideAnyProjectDirectory(const APath: string): Boolean;
function IsProjectMemberFile(const AFileName: string): Boolean;
function IsOpenEditorFile(const AFileName: string): Boolean;
function EnsureDfmTextMode(const AFileName: string): Boolean;
function PathAccessName(const AAccess: TCodexPathAccess): string;
function FindIDEAction(
  const ANames: array of string;
  const AShortCut: TShortCut = 0
): TBasicAction;
function ExecuteIDEAction(const AAction: TBasicAction): Boolean;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  Vcl.ActnList,
  Winapi.Windows,
  CodexMCP.Settings;

const
  CReaderChunkSize = 8192;

function AddUniqueProject(
  var AProjects: TArray<IOTAProject>;
  const AProject: IOTAProject
): Boolean;
var
  LExisting: IOTAProject;
begin
  Result := False;
  if not Assigned(AProject) then
    Exit;
  for LExisting in AProjects do
    if Assigned(LExisting) and SameFileName(
      LExisting.FileName,
      AProject.FileName
    ) then
      Exit;
  SetLength(AProjects, Length(AProjects) + 1);
  AProjects[High(AProjects)] := AProject;
  Result := True;
end;

function AddReadOnlyRoot(
  var ARoots: TArray<TCodexReadOnlyRoot>;
  const AName,
  APath,
  ASource: string
): Boolean;
var
  LNormalized: string;
  LRoot: TCodexReadOnlyRoot;
begin
  Result := False;
  LNormalized := NormalizePath(APath);
  if LNormalized = '' then
    Exit;
  for LRoot in ARoots do
    if SameFileName(LRoot.Path, LNormalized) then
      Exit;
  LRoot.Name := AName;
  LRoot.Path := LNormalized;
  LRoot.Source := ASource;
  LRoot.Exists := TDirectory.Exists(LNormalized);
  SetLength(ARoots, Length(ARoots) + 1);
  ARoots[High(ARoots)] := LRoot;
  Result := True;
end;

function FindMenuItemForAction(
  const ARoot: TMenuItem;
  const AAction: TBasicAction
): TMenuItem;
var
  LIndex: Integer;
begin
  Result := nil;
  if not Assigned(ARoot) or not Assigned(AAction) then
    Exit;
  if ARoot.Action = AAction then
    Exit(ARoot);
  for LIndex := 0 to ARoot.Count - 1 do
  begin
    Result := FindMenuItemForAction(ARoot[LIndex], AAction);
    if Assigned(Result) then
      Exit;
  end;
end;

function ActiveProjectDirectory: string;
var
  LRead: TThreadProcedure;
  LResult: string;
begin
  LResult := '';
  LRead :=
    procedure
    var
      LModuleServices: IOTAModuleServices;
      LProject: IOTAProject;
    begin
      if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
      begin
        LProject := LModuleServices.GetActiveProject;
        if Assigned(LProject) then
          LResult := ProjectDirectory(LProject);
      end;
    end;
  if GetCurrentThreadId = MainThreadID then
    LRead()
  else
    TThread.Synchronize(nil, LRead);
  Result := LResult;
end;

function ExpandEnvironmentPath(const APath: string): string;
var
  LBuffer: TArray<Char>;
  LRequired: DWORD;
begin
  Result := Trim(APath);
  if Result = '' then
    Exit;
  LRequired := ExpandEnvironmentStrings(PChar(Result), nil, 0);
  if LRequired = 0 then
    Exit;
  SetLength(LBuffer, LRequired);
  if ExpandEnvironmentStrings(
    PChar(Result),
    PChar(LBuffer),
    Length(LBuffer)
  ) = 0 then
    Exit;
  Result := PChar(LBuffer);
end;

function NormalizePath(const APath: string): string;
begin
  Result := Trim(ExpandEnvironmentPath(APath));
  if Result = '' then
    Exit;
  try
    Result := TPath.GetFullPath(Result);
    if (Length(Result) > 3) and Result.EndsWith(PathDelim) then
      Result := ExcludeTrailingPathDelimiter(Result);
  except
    Result := '';
  end;
end;

function ResolveRequestedPath(const APath: string): string;
var
  LBase: string;
  LPath: string;
begin
  LPath := ExpandEnvironmentPath(APath);
  if LPath = '' then
    Exit('');
  if not TPath.IsPathRooted(LPath) then
  begin
    LBase := ActiveProjectDirectory;
    if LBase = '' then
      LBase := GetCurrentDir;
    LPath := TPath.Combine(LBase, LPath);
  end;
  Result := NormalizePath(LPath);
end;

function IsPathWithin(const APath, ARoot: string): Boolean;
var
  LPath: string;
  LRoot: string;
begin
  LPath := NormalizePath(APath);
  LRoot := NormalizePath(ARoot);
  Result := (LPath <> '') and (LRoot <> '') and
    (
      SameFileName(LPath, LRoot) or
      StartsText(IncludeTrailingPathDelimiter(LRoot), LPath)
    );
end;

function ProjectDirectory(const AProject: IOTAProject): string;
begin
  Result := '';
  if Assigned(AProject) and (Trim(AProject.FileName) <> '') then
    Result := NormalizePath(TPath.GetDirectoryName(AProject.FileName));
end;

function CollectProjects: TArray<IOTAProject>;
var
  LIndex: Integer;
  LModuleServices: IOTAModuleServices;
  LProjectGroup: IOTAProjectGroup;
begin
  SetLength(Result, 0);
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
    Exit;

  LProjectGroup := LModuleServices.MainProjectGroup;
  if Assigned(LProjectGroup) then
    for LIndex := 0 to LProjectGroup.ProjectCount - 1 do
      AddUniqueProject(Result, LProjectGroup.Projects[LIndex]);
  AddUniqueProject(Result, LModuleServices.GetActiveProject);
end;

function FindProject(const AIdentifier: string): IOTAProject;
var
  LCandidate: IOTAProject;
  LIdentifier: string;
  LModuleServices: IOTAModuleServices;
begin
  Result := nil;
  LIdentifier := Trim(AIdentifier);
  if LIdentifier = '' then
  begin
    if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
      Result := LModuleServices.GetActiveProject;
    Exit;
  end;

  for LCandidate in CollectProjects do
    if Assigned(LCandidate) and
      (
        SameFileName(LCandidate.FileName, ResolveRequestedPath(LIdentifier)) or
        SameText(
          TPath.GetFileNameWithoutExtension(LCandidate.FileName),
          LIdentifier
        ) or
        SameText(TPath.GetFileName(LCandidate.FileName), LIdentifier)
      ) then
      Exit(LCandidate);
end;

function FindModuleForFile(const AFileName: string): IOTAModule;
var
  LEditor: IOTAEditor;
  LEditorIndex: Integer;
  LModule: IOTAModule;
  LModuleIndex: Integer;
  LModuleServices: IOTAModuleServices;
  LPath: string;
begin
  Result := nil;
  LPath := ResolveRequestedPath(AFileName);
  if (LPath = '') or not Supports(
    BorlandIDEServices,
    IOTAModuleServices,
    LModuleServices
  ) then
    Exit;

  for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
  begin
    LModule := LModuleServices.Modules[LModuleIndex];
    if not Assigned(LModule) then
      Continue;
    if SameFileName(LModule.FileName, LPath) then
      Exit(LModule);
    for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
    begin
      LEditor := LModule.ModuleFileEditors[LEditorIndex];
      if Assigned(LEditor) and SameFileName(LEditor.FileName, LPath) then
        Exit(LModule);
    end;
  end;
end;

function FindSourceEditor(const AFileName: string): IOTASourceEditor;
var
  LEditorIndex: Integer;
  LModule: IOTAModule;
  LModuleIndex: Integer;
  LModuleServices: IOTAModuleServices;
  LPath: string;
  LSourceEditor: IOTASourceEditor;
begin
  Result := nil;
  LPath := ResolveRequestedPath(AFileName);
  if (LPath = '') or not Supports(
    BorlandIDEServices,
    IOTAModuleServices,
    LModuleServices
  ) then
    Exit;

  for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
  begin
    LModule := LModuleServices.Modules[LModuleIndex];
    if not Assigned(LModule) then
      Continue;
    for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
      if Supports(
        LModule.ModuleFileEditors[LEditorIndex],
        IOTASourceEditor,
        LSourceEditor
      ) and SameFileName(LSourceEditor.FileName, LPath) then
        Exit(LSourceEditor);
  end;
end;

function FindFormEditor(
  const AFileName: string;
  out AModule: IOTAModule
): IOTAFormEditor;
var
  LEditorIndex: Integer;
  LFormEditor: IOTAFormEditor;
  LModuleIndex: Integer;
  LModuleServices: IOTAModuleServices;
  LPath: string;
begin
  Result := nil;
  AModule := nil;
  LPath := ResolveRequestedPath(AFileName);
  if (LPath = '') or not Supports(
    BorlandIDEServices,
    IOTAModuleServices,
    LModuleServices
  ) then
    Exit;

  for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
  begin
    AModule := LModuleServices.Modules[LModuleIndex];
    if not Assigned(AModule) then
      Continue;
    for LEditorIndex := 0 to AModule.ModuleFileCount - 1 do
      if Supports(
        AModule.ModuleFileEditors[LEditorIndex],
        IOTAFormEditor,
        LFormEditor
      ) and SameFileName(LFormEditor.FileName, LPath) then
        Exit(LFormEditor);
  end;
  AModule := nil;
end;

function ReadEditorText(const AEditor: IOTASourceEditor): string;
var
  LBuffer: TBytes;
  LBytesRead: Integer;
  LOffset: Integer;
  LTextBytes: TBytes;
  LReader: IOTAEditReader;
begin
  Result := '';
  if not Assigned(AEditor) then
    Exit;
  LReader := AEditor.CreateReader;
  if not Assigned(LReader) then
    Exit;
  SetLength(LBuffer, CReaderChunkSize);
  SetLength(LTextBytes, 0);
  LOffset := 0;
  repeat
    LBytesRead := LReader.GetText(
      LOffset,
      PAnsiChar(@LBuffer[0]),
      CReaderChunkSize
    );
    if LBytesRead > 0 then
    begin
      SetLength(LTextBytes, Length(LTextBytes) + LBytesRead);
      Move(
        LBuffer[0],
        LTextBytes[Length(LTextBytes) - LBytesRead],
        LBytesRead
      );
      Inc(LOffset, LBytesRead);
    end;
  until LBytesRead < CReaderChunkSize;
  if Length(LTextBytes) > 0 then
    Result := TEncoding.UTF8.GetString(LTextBytes);
  if Result.EndsWith(#0) then
    SetLength(Result, Length(Result) - 1);
end;

function ReplaceEditorText(
  const AEditor: IOTASourceEditor;
  const AText: string
): Boolean;
var
  LNewText: UTF8String;
  LWriter: IOTAEditWriter;
begin
  Result := False;
  if not Assigned(AEditor) then
    Exit;
  LWriter := AEditor.CreateUndoableWriter;
  if not Assigned(LWriter) then
    Exit;
  LWriter.CopyTo(0);
  LWriter.DeleteTo(MaxInt);
  LNewText := UTF8Encode(AText);
  if Length(LNewText) > 0 then
    LWriter.Insert(PAnsiChar(LNewText));
  LWriter := nil;
  Result := ReadEditorText(AEditor) = AText;
end;

function SaveFileThroughIDE(const AFileName: string): Boolean;
var
  LActionServices: IOTAActionServices;
  LModule: IOTAModule;
  LPath: string;
begin
  LPath := ResolveRequestedPath(AFileName);
  if LPath = '' then
    Exit(False);

  LModule := FindModuleForFile(LPath);
  if Assigned(LModule) then
    Exit(LModule.Save(False, True));

  Result := Supports(
    BorlandIDEServices,
    IOTAActionServices,
    LActionServices
  ) and LActionServices.SaveFile(LPath);
end;

function OpenOrActivateFile(const AFileName: string): Boolean;
var
  LActionServices: IOTAActionServices;
  LModule: IOTAModule;
  LPath: string;
begin
  Result := False;
  LPath := ResolveRequestedPath(AFileName);
  if LPath = '' then
    Exit;
  LModule := FindModuleForFile(LPath);
  if Assigned(LModule) then
  begin
    try
      LModule.ShowFileName(LPath);
    except
      LModule.Show;
    end;
    Exit(True);
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
    Result := LActionServices.OpenFile(LPath);
end;

function CloseFileThroughIDE(
  const AFileName: string;
  const AForce: Boolean
): Boolean;
var
  LModule: IOTAModule;
begin
  LModule := FindModuleForFile(AFileName);
  Result := Assigned(LModule) and LModule.CloseModule(AForce);
end;

function GetReadOnlyRoots: TArray<TCodexReadOnlyRoot>;
var
  LAdditional: TArray<string>;
  LBDSRoot: string;
  LCatalogAllUsers: string;
  LCatalogUser: string;
  LIndex: Integer;
  LOTAServices: IOTAServices;
  LPublic: string;
  LUserProfile: string;
begin
  SetLength(Result, 0);
  LBDSRoot := GetEnvironmentVariable('BDS');
  if Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
    LBDSRoot := LOTAServices.GetRootDirectory;
  if LBDSRoot <> '' then
    AddReadOnlyRoot(
      Result,
      'Delphi-Sourcen',
      TPath.Combine(LBDSRoot, 'source'),
      '%BDS%\source'
    );

  LUserProfile := GetEnvironmentVariable('USERPROFILE');
  if LUserProfile = '' then
    LUserProfile := TPath.GetHomePath;
  LPublic := GetEnvironmentVariable('PUBLIC');
  if (LPublic = '') and (LUserProfile <> '') then
    LPublic := TPath.Combine(TPath.GetDirectoryName(LUserProfile), 'Public');

  LCatalogUser := GetEnvironmentVariable('BDSCatalogRepository');
  if LCatalogUser = '' then
    LCatalogUser := TPath.Combine(
      LUserProfile,
      'Documents\Embarcadero\Studio\37.0\CatalogRepository'
    );
  AddReadOnlyRoot(
    Result,
    'GetIt (Benutzer)',
    LCatalogUser,
    '%BDSCatalogRepository%'
  );

  LCatalogAllUsers := GetEnvironmentVariable('BDSCatalogRepositoryAllUsers');
  if LCatalogAllUsers = '' then
    LCatalogAllUsers := TPath.Combine(
      LPublic,
      'Documents\Embarcadero\Studio\37.0\CatalogRepository'
    );
  AddReadOnlyRoot(
    Result,
    'GetIt (Alle Benutzer)',
    LCatalogAllUsers,
    '%BDSCatalogRepositoryAllUsers%'
  );

  AddReadOnlyRoot(
    Result,
    'Delphi-Demos',
    TPath.Combine(
      LPublic,
      'Documents\Embarcadero\Studio\37.0\Samples'
    ),
    '%PUBLIC%\Documents\Embarcadero\Studio\37.0\Samples'
  );

  LAdditional := TCodexMCPSettings.Instance.AdditionalReadOnlyRootLines;
  for LIndex := 0 to High(LAdditional) do
    AddReadOnlyRoot(
      Result,
      Format('Zusätzliches Verzeichnis %d', [LIndex + 1]),
      LAdditional[LIndex],
      'IDE-Optionen'
    );
end;

function IsInsideAnyProjectDirectory(const APath: string): Boolean;
var
  LProject: IOTAProject;
begin
  Result := False;
  for LProject in CollectProjects do
    if IsPathWithin(APath, ProjectDirectory(LProject)) then
      Exit(True);
end;

function IsProjectMemberFile(const AFileName: string): Boolean;
var
  LIndex: Integer;
  LInfo: IOTAModuleInfo;
  LMemberPath: string;
  LPath: string;
  LProject: IOTAProject;
begin
  Result := False;
  LPath := ResolveRequestedPath(AFileName);
  for LProject in CollectProjects do
  begin
    if SameFileName(LProject.FileName, LPath) then
      Exit(True);
    for LIndex := 0 to LProject.GetModuleCount - 1 do
    begin
      LInfo := LProject.GetModule(LIndex);
      if not Assigned(LInfo) then
        Continue;
      if TPath.IsPathRooted(LInfo.FileName) then
        LMemberPath := NormalizePath(LInfo.FileName)
      else
        LMemberPath := NormalizePath(
          TPath.Combine(ProjectDirectory(LProject), LInfo.FileName)
        );
      if SameFileName(LMemberPath, LPath) then
        Exit(True);
    end;
  end;
end;

function IsOpenEditorFile(const AFileName: string): Boolean;
var
  LEditorIndex: Integer;
  LModule: IOTAModule;
  LModuleIndex: Integer;
  LModuleServices: IOTAModuleServices;
  LPath: string;
begin
  Result := False;
  LPath := ResolveRequestedPath(AFileName);
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
    Exit;
  for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
  begin
    LModule := LModuleServices.Modules[LModuleIndex];
    if not Assigned(LModule) then
      Continue;
    if SameFileName(LModule.FileName, LPath) then
      Exit(True);
    for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
      if Assigned(LModule.ModuleFileEditors[LEditorIndex]) and SameFileName(
        LModule.ModuleFileEditors[LEditorIndex].FileName,
        LPath
      ) then
        Exit(True);
  end;
end;

function ClassifyPath(const AFileName: string): TCodexPathAccess;
var
  LPath: string;
  LRoot: TCodexReadOnlyRoot;
begin
  Result := cpaForbidden;
  LPath := ResolveRequestedPath(AFileName);
  if LPath = '' then
    Exit;

  for LRoot in GetReadOnlyRoots do
    if IsPathWithin(LPath, LRoot.Path) then
      Exit(cpaReadOnlyReference);

  if IsOpenEditorFile(LPath) or IsProjectMemberFile(LPath) or
    IsInsideAnyProjectDirectory(LPath) then
    Result := cpaWorkspaceReadWrite;
end;

function PathAccessName(const AAccess: TCodexPathAccess): string;
begin
  case AAccess of
    cpaWorkspaceReadWrite:
      Result := 'workspace_read_write';
    cpaReadOnlyReference:
      Result := 'read_only_reference';
  else
    Result := 'forbidden';
  end;
end;

function FindIDEAction(
  const ANames: array of string;
  const AShortCut: TShortCut
): TBasicAction;
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

  if AShortCut <> 0 then
    for LActionIndex := 0 to LActionList.ActionCount - 1 do
    begin
      LAction := LActionList[LActionIndex];
      if (LAction is TCustomAction) and
        (TCustomAction(LAction).ShortCut = AShortCut) then
        Exit(LAction);
    end;
end;

function ExecuteIDEAction(const AAction: TBasicAction): Boolean;
var
  LMenuItem: TMenuItem;
  LServices: INTAServices;
begin
  Result := False;
  if not Assigned(AAction) then
    Exit;
  if Supports(BorlandIDEServices, INTAServices, LServices) and
    Assigned(LServices.MainMenu) then
  begin
    LMenuItem := FindMenuItemForAction(LServices.MainMenu.Items, AAction);
    if Assigned(LMenuItem) then
    begin
      LMenuItem.Click;
      Exit(True);
    end;
  end;
  Result := AAction.Execute;
end;

function EnsureDfmTextMode(const AFileName: string): Boolean;
var
  LAction: TBasicAction;
  LFormEditor: IOTAFormEditor;
  LModule: IOTAModule;
  LPath: string;
begin
  LPath := ResolveRequestedPath(AFileName);
  if SameText(TPath.GetExtension(LPath), '.pas') then
    LPath := ChangeFileExt(LPath, '.dfm');
  Result := Assigned(FindSourceEditor(LPath));
  if Result then
    Exit;
  if not SameText(TPath.GetExtension(LPath), '.dfm') then
    Exit(False);

  LFormEditor := FindFormEditor(LPath, LModule);
  if not Assigned(LFormEditor) or not Assigned(LModule) then
    Exit(False);
  try
    LModule.ShowFileName(LPath);
  except
    LModule.Show;
  end;

  LAction := FindIDEAction(
    [
      'ViewFormAsTextCommand',
      'ViewAsTextCommand',
      'FormViewAsTextCommand',
      'ViewToggleFormUnitCommand',
      'ToggleFormUnitCommand'
    ],
    Vcl.Menus.ShortCut(VK_F12, [ssAlt])
  );
  Result := ExecuteIDEAction(LAction) and Assigned(FindSourceEditor(LPath));
end;

end.
