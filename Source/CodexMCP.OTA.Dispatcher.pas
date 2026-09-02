unit CodexMCP.OTA.Dispatcher;

interface

uses
  System.JSON;

type
  TCodexMCPToolDispatcher = class sealed
  strict private
    class function DoExecute(
      const AName: string;
      const AArguments: TJSONObject
    ): TJSONValue; static;
  public
    class function Execute(
      const AName: string;
      const AArguments: TJSONObject
    ): TJSONValue; static;
  end;

implementation

uses
  System.Actions,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  System.Types,
  ToolsAPI,
  CodexMCP.CodexRegistration,
  CodexMCP.Json,
  CodexMCP.Logger,
  CodexMCP.OTA.Common,
  CodexMCP.OTA.Creators,
  CodexMCP.OTA.Runtime,
  CodexMCP.OTA.UserInteraction,
  CodexMCP.Settings,
  CodexMCP.TextFiles,
  CodexMCP.Threading;

const
  CMaximumTextFileSize = 16 * 1024 * 1024;

function RequiredContent(const AArguments: TJSONObject): string;
var
  LValue: TJSONValue;
begin
  if not Assigned(AArguments) then
    raise EArgumentException.Create('Das Argumentobjekt fehlt.');
  LValue := AArguments.Values['content'];
  if not (LValue is TJSONString) then
    raise EArgumentException.Create(
      'Das erforderliche String-Argument "content" fehlt.'
    );
  Result := TJSONString(LValue).Value;
end;

function NewArrayResult(
  const AName: string;
  const AArray: TJSONArray
): TJSONObject;
begin
  Result := JsonSuccess;
  Result.AddPair(AName, AArray);
  Result.AddPair('count', TJSONNumber.Create(AArray.Count));
end;

procedure AddUniquePath(
  const APaths: TStrings;
  const APath: string
);
var
  LNormalized: string;
begin
  LNormalized := NormalizePath(APath);
  if (LNormalized <> '') and (APaths.IndexOf(LNormalized) < 0) then
    APaths.Add(LNormalized);
end;

function ProjectMemberPath(
  const AProject: IOTAProject;
  const AFileName: string
): string;
begin
  Result := AFileName;
  if not TPath.IsPathRooted(Result) then
    Result := TPath.Combine(ProjectDirectory(AProject), Result);
  Result := NormalizePath(Result);
end;

function CheckSearchPattern(const APattern: string): string;
begin
  Result := Trim(APattern);
  if Result = '' then
    Result := '*';
  if ContainsText(Result, '..') or
    Result.Contains(PathDelim) or
    Result.Contains('/') then
    raise EArgumentException.Create(
      'Das Suchmuster darf keinen Verzeichnispfad enthalten.'
    );
end;

function ListDirectoryFiles(
  const ADirectory,
  APattern: string;
  const ARecursive: Boolean;
  const AMaxResults: Integer
): TJSONObject;
var
  LArray: TJSONArray;
  LFiles: TStringDynArray;
  LIndex: Integer;
  LLimit: Integer;
  LList: TStringList;
  LOption: TSearchOption;
begin
  if not TDirectory.Exists(ADirectory) then
    raise EDirectoryNotFoundException.Create(ADirectory);
  if ARecursive then
    LOption := TSearchOption.soAllDirectories
  else
    LOption := TSearchOption.soTopDirectoryOnly;
  LFiles := TDirectory.GetFiles(ADirectory, APattern, LOption);
  LList := TStringList.Create;
  try
    LList.CaseSensitive := False;
    LList.Sorted := True;
    LList.Duplicates := dupIgnore;
    for LIndex := 0 to High(LFiles) do
      LList.Add(NormalizePath(LFiles[LIndex]));
    LLimit := Min(EnsureRange(AMaxResults, 1, 20000), LList.Count);
    LArray := TJSONArray.Create;
    for LIndex := 0 to LLimit - 1 do
      LArray.Add(LList[LIndex]);
    Result := NewArrayResult('files', LArray);
    Result.AddPair('directory', ADirectory);
    Result.AddPair('search_pattern', APattern);
    Result.AddPair('recursive', TJSONBool.Create(ARecursive));
    Result.AddPair('total_matches', TJSONNumber.Create(LList.Count));
    Result.AddPair('truncated', TJSONBool.Create(LLimit < LList.Count));
  finally
    LList.Free;
  end;
end;

function ListOpenFiles: TJSONObject;
var
  LFiles: TStringList;
  LResultArray: TJSONArray;
begin
  LFiles := TStringList.Create;
  try
    LFiles.CaseSensitive := False;
    LFiles.Sorted := True;
    LFiles.Duplicates := dupIgnore;
    TCodexMCPThreading.RunInIDEThread(
      procedure
      var
        LEditorIndex: Integer;
        LModule: IOTAModule;
        LModuleIndex: Integer;
        LModuleServices: IOTAModuleServices;
      begin
        if not Supports(
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
          if Trim(LModule.FileName) <> '' then
            AddUniquePath(LFiles, LModule.FileName);
          for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
            if Assigned(LModule.ModuleFileEditors[LEditorIndex]) and
              (Trim(LModule.ModuleFileEditors[LEditorIndex].FileName) <> '') then
              AddUniquePath(
                LFiles,
                LModule.ModuleFileEditors[LEditorIndex].FileName
              );
        end;
      end
    );

    LResultArray := TJSONArray.Create;
    TCodexMCPThreading.RunInIDEThread(
      procedure
      var
        LFileName: string;
        LFormEditor: IOTAFormEditor;
        LItem: TJSONObject;
        LModule: IOTAModule;
        LSourceEditor: IOTASourceEditor;
      begin
        for LFileName in LFiles do
        begin
          LItem := TJSONObject.Create;
          LItem.AddPair('path', LFileName);
          LSourceEditor := FindSourceEditor(LFileName);
          LFormEditor := FindFormEditor(LFileName, LModule);
          LItem.AddPair(
            'source_editor',
            TJSONBool.Create(Assigned(LSourceEditor))
          );
          LItem.AddPair(
            'form_editor',
            TJSONBool.Create(Assigned(LFormEditor))
          );
          if Assigned(LSourceEditor) then
            LItem.AddPair('modified', TJSONBool.Create(LSourceEditor.Modified))
          else
            LItem.AddPair('modified', TJSONBool.Create(False));
          LItem.AddPair('access', PathAccessName(ClassifyPath(LFileName)));
          LResultArray.AddElement(LItem);
        end;
      end
    );
    Result := NewArrayResult('files', LResultArray);
  finally
    LFiles.Free;
  end;
end;

function ListProjects: TJSONObject;
var
  LArray: TJSONArray;
  LProjectGroupFile: string;
begin
  LArray := TJSONArray.Create;
  LProjectGroupFile := '';
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LActiveProject: IOTAProject;
      LItem: TJSONObject;
      LModuleServices: IOTAModuleServices;
      LProject: IOTAProject;
      LProjectGroup: IOTAProjectGroup;
      LTarget: string;
    begin
      LActiveProject := nil;
      LProjectGroup := nil;
      if Supports(
        BorlandIDEServices,
        IOTAModuleServices,
        LModuleServices
      ) then
      begin
        LActiveProject := LModuleServices.GetActiveProject;
        LProjectGroup := LModuleServices.MainProjectGroup;
      end;
      for LProject in CollectProjects do
      begin
        LItem := TJSONObject.Create;
        LItem.AddPair('name', TPath.GetFileNameWithoutExtension(LProject.FileName));
        LItem.AddPair('file', NormalizePath(LProject.FileName));
        LItem.AddPair('directory', ProjectDirectory(LProject));
        LItem.AddPair(
          'active',
          TJSONBool.Create(
            Assigned(LActiveProject) and
            SameFileName(LActiveProject.FileName, LProject.FileName)
          )
        );
        LItem.AddPair('module_count', TJSONNumber.Create(LProject.GetModuleCount));
        LItem.AddPair('configuration', LProject.CurrentConfiguration);
        LItem.AddPair('platform', LProject.CurrentPlatform);
        LTarget := '';
        if Assigned(LProject.ProjectOptions) then
          LTarget := LProject.ProjectOptions.TargetName;
        LItem.AddPair('target', LTarget);
        LArray.AddElement(LItem);
      end;
      if Assigned(LProjectGroup) then
        LProjectGroupFile := NormalizePath(LProjectGroup.FileName);
    end
  );
  Result := NewArrayResult('projects', LArray);
  if LProjectGroupFile <> '' then
    Result.AddPair('project_group', LProjectGroupFile)
  else
    Result.AddPair('project_group', TJSONNull.Create);
end;

function ListProjectFiles(const AProjectIdentifier: string): TJSONObject;
var
  LArray: TJSONArray;
  LItemPath: string;
  LPaths: TStringList;
  LProjectFile: string;
begin
  LArray := TJSONArray.Create;
  LPaths := TStringList.Create;
  try
    LPaths.CaseSensitive := False;
    LPaths.Sorted := True;
    LPaths.Duplicates := dupIgnore;
    LProjectFile := '';
    TCodexMCPThreading.RunInIDEThread(
      procedure
      var
        LCompanion: string;
        LExtension: string;
        LIndex: Integer;
        LInfo: IOTAModuleInfo;
        LMember: string;
        LProject: IOTAProject;
      begin
        LProject := FindProject(AProjectIdentifier);
        if not Assigned(LProject) then
          raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
        LProjectFile := NormalizePath(LProject.FileName);
        AddUniquePath(LPaths, LProjectFile);
        LExtension := LowerCase(TPath.GetExtension(LProjectFile));
        if SameText(LExtension, '.dproj') then
        begin
          LCompanion := ChangeFileExt(LProjectFile, '.dpr');
          if TFile.Exists(LCompanion) then
            AddUniquePath(LPaths, LCompanion);
        end
        else if SameText(LExtension, '.dpr') then
        begin
          LCompanion := ChangeFileExt(LProjectFile, '.dproj');
          if TFile.Exists(LCompanion) then
            AddUniquePath(LPaths, LCompanion);
        end;

        for LIndex := 0 to LProject.GetModuleCount - 1 do
        begin
          LInfo := LProject.GetModule(LIndex);
          if not Assigned(LInfo) then
            Continue;
          LMember := ProjectMemberPath(LProject, LInfo.FileName);
          AddUniquePath(LPaths, LMember);
          if SameText(TPath.GetExtension(LMember), '.pas') then
          begin
            LCompanion := ChangeFileExt(LMember, '.dfm');
            if TFile.Exists(LCompanion) or IsOpenEditorFile(LCompanion) then
              AddUniquePath(LPaths, LCompanion);
            LCompanion := ChangeFileExt(LMember, '.fmx');
            if TFile.Exists(LCompanion) or IsOpenEditorFile(LCompanion) then
              AddUniquePath(LPaths, LCompanion);
          end;
        end;
      end
    );
    for LItemPath in LPaths do
      LArray.Add(LItemPath);
    Result := NewArrayResult('files', LArray);
    Result.AddPair('project', LProjectFile);
  finally
    LPaths.Free;
  end;
end;

procedure ReadTextThroughPolicy(
  const APath: string;
  const ARequiredAccess: TCodexPathAccess;
  out AText,
  ASource,
  AEncoding: string;
  out AModified: Boolean
);
var
  LAccess: TCodexPathAccess;
  LDiskEncoding: TCodexTextEncoding;
  LEditorFound: Boolean;
begin
  AText := '';
  ASource := '';
  AEncoding := '';
  AModified := False;
  LAccess := TCodexMCPThreading.CallInIDEThread<TCodexPathAccess>(
    function: TCodexPathAccess
    begin
      Result := ClassifyPath(APath);
    end
  );
  if LAccess <> ARequiredAccess then
    raise EAccessViolation.CreateFmt(
      'Der Pfad ist nicht für den angeforderten Zugriff freigegeben (%s).',
      [PathAccessName(LAccess)]
    );

  LEditorFound := False;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LEditor: IOTASourceEditor;
    begin
      if SameText(TPath.GetExtension(APath), '.dfm') then
        EnsureDfmTextMode(APath);
      LEditor := FindSourceEditor(APath);
      if Assigned(LEditor) then
      begin
        AText := ReadEditorText(LEditor);
        ASource := 'ide_buffer';
        AEncoding := 'ide_utf8_buffer';
        AModified := LEditor.Modified;
        LEditorFound := True;
      end;
    end
  );
  if LEditorFound then
    Exit;

  if TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    var
      LFormEditor: IOTAFormEditor;
      LModule: IOTAModule;
    begin
      LFormEditor := FindFormEditor(APath, LModule);
      Result := Assigned(LFormEditor);
    end
  ) then
    raise EInvalidOpException.Create(
      'Das Formular ist im Designer geöffnet, konnte aber nicht in den Textmodus umgeschaltet werden. Der Festplattenstand wird nicht als Ersatz verwendet.'
    );

  if not TFile.Exists(APath) then
    raise EFileNotFoundException.Create(APath);
  if TFile.GetSize(APath) > CMaximumTextFileSize then
    raise EIOException.CreateFmt(
      'Die Datei überschreitet die Textdatei-Grenze von %d MiB.',
      [CMaximumTextFileSize div 1024 div 1024]
    );
  if not ReadTextFilePreservingEncoding(APath, AText, LDiskEncoding) then
    raise EFileNotFoundException.Create(APath);
  ASource := 'disk';
  AEncoding := TextEncodingName(LDiskEncoding);
end;

function ReadFileResult(
  const AArguments: TJSONObject;
  const ARequiredAccess: TCodexPathAccess
): TJSONObject;
var
  LEncoding: string;
  LModified: Boolean;
  LPath: string;
  LSource: string;
  LText: string;
begin
  LPath := ResolveRequestedPath(RequireJsonString(AArguments, 'path'));
  ReadTextThroughPolicy(
    LPath,
    ARequiredAccess,
    LText,
    LSource,
    LEncoding,
    LModified
  );
  Result := JsonSuccess;
  Result.AddPair('path', LPath);
  Result.AddPair('content', LText);
  Result.AddPair('sha256', SHA256Text(LText));
  Result.AddPair('source', LSource);
  Result.AddPair('encoding', LEncoding);
  Result.AddPair('modified', TJSONBool.Create(LModified));
  Result.AddPair('access', PathAccessName(ARequiredAccess));
end;

function WriteWorkspaceFile(const AArguments: TJSONObject): TJSONObject;
var
  LAccess: TCodexPathAccess;
  LContent: string;
  LCreate: Boolean;
  LCurrent: string;
  LDiskEncoding: TCodexTextEncoding;
  LExpectedHash: string;
  LPath: string;
  LSave: Boolean;
  LUsedEditor: Boolean;
begin
  LPath := ResolveRequestedPath(RequireJsonString(AArguments, 'path'));
  LContent := RequiredContent(AArguments);
  if TEncoding.UTF8.GetByteCount(LContent) > CMaximumTextFileSize then
    raise ERangeError.CreateFmt(
      'Der neue Dateiinhalt überschreitet die Grenze von %d MiB.',
      [CMaximumTextFileSize div 1024 div 1024]
    );
  LSave := JsonBoolean(AArguments, 'save', False);
  LCreate := JsonBoolean(AArguments, 'create', False);
  LExpectedHash := Trim(JsonString(AArguments, 'expected_sha256'));
  LAccess := TCodexMCPThreading.CallInIDEThread<TCodexPathAccess>(
    function: TCodexPathAccess
    begin
      Result := ClassifyPath(LPath);
    end
  );
  if LAccess <> cpaWorkspaceReadWrite then
    raise EAccessViolation.CreateFmt(
      'Schreibzugriff verweigert (%s): %s',
      [PathAccessName(LAccess), LPath]
    );

  LUsedEditor := False;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LEditor: IOTASourceEditor;
    begin
      if SameText(TPath.GetExtension(LPath), '.dfm') then
        EnsureDfmTextMode(LPath);
      LEditor := FindSourceEditor(LPath);
      if not Assigned(LEditor) then
        Exit;
      LCurrent := ReadEditorText(LEditor);
      if (LExpectedHash <> '') and not SameText(
        LExpectedHash,
        SHA256Text(LCurrent)
      ) then
        raise EInvalidOpException.Create(
          'Die Datei wurde seit dem Lesen verändert (SHA-256 stimmt nicht überein).'
        );
      if not ReplaceEditorText(LEditor, LContent) then
        raise EInvalidOpException.Create(
          'Der Editor-Puffer konnte nicht vollständig ersetzt werden.'
        );
      if LSave and not SaveFileThroughIDE(LPath) then
        raise EInvalidOpException.Create(
          'Der geänderte Editor-Puffer konnte nicht gespeichert werden.'
        );
      LUsedEditor := True;
    end
  );

  if not LUsedEditor then
  begin
    if TCodexMCPThreading.CallInIDEThread<Boolean>(
      function: Boolean
      var
        LFormEditor: IOTAFormEditor;
        LModule: IOTAModule;
      begin
        LFormEditor := FindFormEditor(LPath, LModule);
        Result := Assigned(LFormEditor);
      end
    ) then
      raise EInvalidOpException.Create(
        'Das Formular ist im Designer geöffnet, konnte aber nicht in den Textmodus umgeschaltet werden. Ein direkter Festplatten-Schreibzugriff ist gesperrt.'
      );
    if TFile.Exists(LPath) then
    begin
      if TFile.GetSize(LPath) > CMaximumTextFileSize then
        raise EIOException.CreateFmt(
          'Die Datei überschreitet die Textdatei-Grenze von %d MiB.',
          [CMaximumTextFileSize div 1024 div 1024]
        );
      if not ReadTextFilePreservingEncoding(LPath, LCurrent, LDiskEncoding) then
        raise EFileNotFoundException.Create(LPath);
    end
    else
    begin
      if not LCreate then
        raise EFileNotFoundException.Create(
          'Die Datei existiert nicht; zum Anlegen ist create=true erforderlich.'
        );
      LCurrent := '';
      LDiskEncoding := cteUtf8;
    end;
    if (LExpectedHash <> '') and not SameText(
      LExpectedHash,
      SHA256Text(LCurrent)
    ) then
      raise EInvalidOpException.Create(
        'Die Datei wurde seit dem Lesen verändert (SHA-256 stimmt nicht überein).'
      );
    WriteTextFilePreservingEncoding(LPath, LContent, LDiskEncoding);
  end;

  Result := JsonSuccess;
  Result.AddPair('path', LPath);
  Result.AddPair('sha256', SHA256Text(LContent));
  Result.AddPair(
    'target',
    IfThen(LUsedEditor, 'ide_buffer', 'disk')
  );
  Result.AddPair('saved', TJSONBool.Create((not LUsedEditor) or LSave));
end;

function CreateProjectTool(const AArguments: TJSONObject): TJSONObject;
var
  LCreatedDirectory: string;
  LCreatedProject: string;
  LDirectory: string;
  LKind: TCodexProjectKind;
  LKindText: string;
  LProjectName: string;
begin
  LDirectory := ResolveRequestedPath(
    RequireJsonString(AArguments, 'directory')
  );
  LProjectName := RequireJsonString(AArguments, 'name');
  LKindText := JsonString(AArguments, 'kind', 'console');
  if SameText(LKindText, 'vcl') then
    LKind := cpkVcl
  else if SameText(LKindText, 'console') then
    LKind := cpkConsole
  else
    raise EArgumentException.Create('kind muss "console" oder "vcl" sein.');

  if TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    var
      LRoot: TCodexReadOnlyRoot;
    begin
      Result := False;
      for LRoot in GetReadOnlyRoots do
        if IsPathWithin(LDirectory, LRoot.Path) then
          Exit(True);
    end
  ) then
    raise EAccessViolation.Create(
      'In einem schreibgeschützten Referenzverzeichnis darf kein Projekt angelegt werden.'
    );

  LCreatedProject := '';
  LCreatedDirectory := '';
  if not TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    var
      LProject: IOTAProject;
    begin
      LProject := nil;
      Result := CreateDelphiProject(
        LDirectory,
        LProjectName,
        LKind,
        LProject
      );
      if Result and Assigned(LProject) then
      begin
        LCreatedProject := NormalizePath(LProject.FileName);
        LCreatedDirectory := ProjectDirectory(LProject);
      end;
    end
  ) then
    raise EInvalidOpException.Create('Das Delphi-Projekt konnte nicht erstellt werden.');
  Result := JsonSuccess;
  Result.AddPair('project', LCreatedProject);
  Result.AddPair('directory', LCreatedDirectory);
  Result.AddPair('kind', LKindText);
end;

function OpenProjectTool(const AArguments: TJSONObject): TJSONObject;
var
  LExtension: string;
  LPath: string;
  LSuccess: Boolean;
begin
  LPath := ResolveRequestedPath(RequireJsonString(AArguments, 'path'));
  if not TFile.Exists(LPath) then
    raise EFileNotFoundException.Create(LPath);
  LExtension := LowerCase(TPath.GetExtension(LPath));
  if not MatchText(
    LExtension,
    ['.dproj', '.dpr', '.dpk', '.groupproj', '.bpg']
  ) then
    raise EArgumentException.Create(
      'Der Pfad bezeichnet keine unterstützte Delphi-Projekt- oder Projektgruppendatei.'
    );
  LSuccess := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    var
      LActionServices: IOTAActionServices;
    begin
      Result := Supports(
        BorlandIDEServices,
        IOTAActionServices,
        LActionServices
      ) and LActionServices.OpenFile(LPath);
    end
  );
  if not LSuccess then
    raise EInvalidOpException.Create('Das Projekt konnte nicht geöffnet werden.');
  Result := JsonSuccessPair('path', LPath);
end;

function SaveProjectTool(const AArguments: TJSONObject): TJSONObject;
var
  LIdentifier: string;
  LProjectFile: string;
  LReadOnlyModulesSkipped: Integer;
  LSaveModules: Boolean;
  LSaved: Boolean;
begin
  LIdentifier := JsonString(AArguments, 'project');
  LSaveModules := JsonBoolean(AArguments, 'save_modules', True);
  LProjectFile := '';
  LReadOnlyModulesSkipped := 0;
  LSaved := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    var
      LIndex: Integer;
      LInfo: IOTAModuleInfo;
      LModule: IOTAModule;
      LModulePath: string;
      LProject: IOTAProject;
    begin
      LProject := FindProject(LIdentifier);
      if not Assigned(LProject) then
        raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
      LProjectFile := NormalizePath(LProject.FileName);
      if ClassifyPath(LProjectFile) <> cpaWorkspaceReadWrite then
        raise EAccessViolation.Create(
          'Das ausgewählte Projekt liegt in einem schreibgeschützten Referenzpfad.'
        );
      if LSaveModules then
        for LIndex := 0 to LProject.GetModuleCount - 1 do
        begin
          LInfo := LProject.GetModule(LIndex);
          if not Assigned(LInfo) then
            Continue;
          LModulePath := LInfo.FileName;
          if not TPath.IsPathRooted(LModulePath) then
            LModulePath := TPath.Combine(ProjectDirectory(LProject), LModulePath);
          LModulePath := NormalizePath(LModulePath);
          if ClassifyPath(LModulePath) = cpaReadOnlyReference then
          begin
            Inc(LReadOnlyModulesSkipped);
            Continue;
          end;
          LModule := FindModuleForFile(LModulePath);
          if Assigned(LModule) and not LModule.Save(False, True) then
            Exit(False);
        end;
      Result := LProject.Save(False, True);
    end
  );
  if not LSaved then
    raise EInvalidOpException.Create('Das Projekt konnte nicht gespeichert werden.');
  Result := JsonSuccessPair('project', LProjectFile);
  Result.AddPair('modules_saved', TJSONBool.Create(LSaveModules));
  Result.AddPair(
    'read_only_modules_skipped',
    TJSONNumber.Create(LReadOnlyModulesSkipped)
  );
end;

function RemoveProjectTool(const AArguments: TJSONObject): TJSONObject;
var
  LClose: Boolean;
  LClosed: Boolean;
  LForce: Boolean;
  LIdentifier: string;
  LProjectFile: string;
  LRemovedFromGroup: Boolean;
begin
  LIdentifier := JsonString(AArguments, 'project');
  LClose := JsonBoolean(AArguments, 'close', True);
  LForce := JsonBoolean(AArguments, 'force', False);
  LProjectFile := '';
  LClosed := False;
  LRemovedFromGroup := False;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LIndex: Integer;
      LModule: IOTAModule;
      LModuleServices: IOTAModuleServices;
      LProject: IOTAProject;
      LProjectGroup: IOTAProjectGroup;
    begin
      LProject := FindProject(LIdentifier);
      if not Assigned(LProject) then
        raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
      LProjectFile := NormalizePath(LProject.FileName);
      LProjectGroup := nil;
      if Supports(
        BorlandIDEServices,
        IOTAModuleServices,
        LModuleServices
      ) then
        LProjectGroup := LModuleServices.MainProjectGroup;
      if Assigned(LProjectGroup) then
        for LIndex := 0 to LProjectGroup.ProjectCount - 1 do
          if Assigned(LProjectGroup.Projects[LIndex]) and SameFileName(
            LProjectGroup.Projects[LIndex].FileName,
            LProject.FileName
          ) then
          begin
            LProjectGroup.RemoveProject(LProject);
            LRemovedFromGroup := True;
            Break;
          end;
      if LClose then
      begin
        LModule := FindModuleForFile(LProjectFile);
        if Assigned(LModule) then
        begin
          LClosed := LModule.CloseModule(LForce);
          if not LClosed then
            raise EInvalidOpException.Create(
              'Das Projekt wurde nicht geschlossen; möglicherweise wurde der Vorgang vom Benutzer abgebrochen.'
            );
        end
        else
          LClosed := True;
      end;
      if not LRemovedFromGroup and not LClose then
        raise EInvalidOpException.Create(
          'Ohne Projektgruppe ist weder Entfernen noch Schließen angefordert.'
        );
    end
  );
  Result := JsonSuccessPair('project', LProjectFile);
  Result.AddPair(
    'removed_from_group',
    TJSONBool.Create(LRemovedFromGroup)
  );
  Result.AddPair('closed', TJSONBool.Create(LClosed));
end;

function CreateUnitTool(
  const AArguments: TJSONObject;
  const AFormUnit: Boolean
): TJSONObject;
var
  LAncestor: string;
  LDfmSource: string;
  LFileName: string;
  LFormName: string;
  LMainForm: Boolean;
  LProjectFile: string;
  LProjectIdentifier: string;
  LSource: string;
  LUnitName: string;
begin
  LProjectIdentifier := JsonString(AArguments, 'project');
  LUnitName := RequireJsonString(AArguments, 'unit_name');
  LFileName := JsonString(AArguments, 'file_name');
  if Trim(LFileName) = '' then
    LFileName := JsonString(AArguments, 'path');
  LSource := JsonString(AArguments, 'source');
  LFormName := JsonString(AArguments, 'form_name', 'Form1');
  LAncestor := JsonString(AArguments, 'ancestor', 'TForm');
  LDfmSource := JsonString(AArguments, 'dfm_source');
  LMainForm := JsonBoolean(AArguments, 'main_form', False);
  LProjectFile := '';

  if not TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    var
      LModule: IOTAModule;
      LProject: IOTAProject;
      LResolved: string;
    begin
      LModule := nil;
      LProject := FindProject(LProjectIdentifier);
      if not Assigned(LProject) then
        raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
      LProjectFile := NormalizePath(LProject.FileName);
      if Trim(LFileName) = '' then
        LResolved := TPath.Combine(
          ProjectDirectory(LProject),
          LUnitName + '.pas'
        )
      else if TPath.IsPathRooted(ExpandEnvironmentPath(LFileName)) then
        LResolved := ResolveRequestedPath(LFileName)
      else
        LResolved := NormalizePath(
          TPath.Combine(ProjectDirectory(LProject), LFileName)
        );
      if not IsPathWithin(LResolved, ProjectDirectory(LProject)) then
        raise EAccessViolation.Create(
          'Neue Units müssen innerhalb des ausgewählten Projektverzeichnisses liegen.'
        );
      if ClassifyPath(LResolved) <> cpaWorkspaceReadWrite then
        raise EAccessViolation.Create(
          'Im ausgewählten Projektpfad ist kein Schreibzugriff zulässig.'
        );
      LFileName := LResolved;
      if AFormUnit then
        Result := CreateDelphiFormUnit(
          LProject,
          LFileName,
          LUnitName,
          LFormName,
          LAncestor,
          LSource,
          LDfmSource,
          LMainForm,
          LModule
        )
      else
        Result := CreateDelphiUnit(
          LProject,
          LFileName,
          LUnitName,
          LSource,
          LModule
        );
    end
  ) then
    raise EInvalidOpException.Create('Die Unit konnte nicht erstellt werden.');

  Result := JsonSuccess;
  Result.AddPair('project', LProjectFile);
  Result.AddPair('unit', LFileName);
  if AFormUnit then
    Result.AddPair('form', ChangeFileExt(LFileName, '.dfm'));
end;

function OpenFileTool(const AArguments: TJSONObject): TJSONObject;
var
  LPath: string;
  LSuccess: Boolean;
begin
  LPath := ResolveRequestedPath(RequireJsonString(AArguments, 'path'));
  if not TFile.Exists(LPath) and not TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    begin
      Result := IsOpenEditorFile(LPath);
    end
  ) then
    raise EFileNotFoundException.Create(LPath);
  if TCodexMCPThreading.CallInIDEThread<TCodexPathAccess>(
    function: TCodexPathAccess
    begin
      Result := ClassifyPath(LPath);
    end
  ) = cpaForbidden then
    raise EAccessViolation.Create(
      'Die Datei liegt weder in einem offenen Projekt noch in einem freigegebenen Referenzpfad.'
    );
  LSuccess := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    begin
      Result := OpenOrActivateFile(LPath);
    end
  );
  if not LSuccess then
    raise EInvalidOpException.Create('Die Datei konnte nicht geöffnet/aktiviert werden.');
  Result := JsonSuccessPair('path', LPath);
end;

function CloseFileTool(const AArguments: TJSONObject): TJSONObject;
var
  LForce: Boolean;
  LPath: string;
  LSuccess: Boolean;
begin
  LPath := ResolveRequestedPath(RequireJsonString(AArguments, 'path'));
  LForce := JsonBoolean(AArguments, 'force', False);
  LSuccess := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    begin
      Result := CloseFileThroughIDE(LPath, LForce);
    end
  );
  if not LSuccess then
    raise EInvalidOpException.Create('Die Datei konnte nicht geschlossen werden.');
  Result := JsonSuccessPair('path', LPath);
end;

function RemoveFileFromProjectTool(
  const AArguments: TJSONObject
): TJSONObject;
var
  LPath: string;
  LProjectFile: string;
  LProjectIdentifier: string;
  LRequestedPath: string;
begin
  LRequestedPath := ExpandEnvironmentPath(
    RequireJsonString(AArguments, 'path')
  );
  LProjectIdentifier := JsonString(AArguments, 'project');
  LPath := '';
  LProjectFile := '';
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LIndex: Integer;
      LInfo: IOTAModuleInfo;
      LMemberPath: string;
      LProject: IOTAProject;
      LResolvedPath: string;
    begin
      LProject := FindProject(LProjectIdentifier);
      if not Assigned(LProject) then
        raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
      LProjectFile := NormalizePath(LProject.FileName);
      if ClassifyPath(LProjectFile) <> cpaWorkspaceReadWrite then
        raise EAccessViolation.Create(
          'Das ausgewählte Projekt liegt in einem schreibgeschützten Referenzpfad.'
        );
      if TPath.IsPathRooted(LRequestedPath) then
        LResolvedPath := NormalizePath(LRequestedPath)
      else
        LResolvedPath := NormalizePath(
          TPath.Combine(ProjectDirectory(LProject), LRequestedPath)
        );

      for LIndex := 0 to LProject.GetModuleCount - 1 do
      begin
        LInfo := LProject.GetModule(LIndex);
        if not Assigned(LInfo) then
          Continue;
        LMemberPath := ProjectMemberPath(LProject, LInfo.FileName);
        if SameFileName(LMemberPath, LResolvedPath) then
        begin
          LPath := LMemberPath;
          Break;
        end;
      end;
      if LPath = '' then
        raise EArgumentException.Create(
          'Die Datei ist kein Mitglied des ausgewählten Projekts.'
        );
      if ClassifyPath(LPath) <> cpaWorkspaceReadWrite then
        raise EAccessViolation.Create(
          'Die Datei liegt in einem schreibgeschützten Referenzpfad.'
        );
      LProject.RemoveFile(LPath);
    end
  );
  Result := JsonSuccess;
  Result.AddPair('project', LProjectFile);
  Result.AddPair('file', LPath);
end;

function ShowFormAsTextTool(const AArguments: TJSONObject): TJSONObject;
var
  LPath: string;
  LSuccess: Boolean;
begin
  LPath := ResolveRequestedPath(RequireJsonString(AArguments, 'path'));
  if SameText(TPath.GetExtension(LPath), '.pas') then
    LPath := ChangeFileExt(LPath, '.dfm');
  if TCodexMCPThreading.CallInIDEThread<TCodexPathAccess>(
    function: TCodexPathAccess
    begin
      Result := ClassifyPath(LPath);
    end
  ) = cpaForbidden then
    raise EAccessViolation.Create(
      'Das Formular liegt weder in einem offenen Projekt noch in einem freigegebenen Referenzpfad.'
    );
  LSuccess := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    begin
      Result := EnsureDfmTextMode(LPath);
    end
  );
  if not LSuccess then
    raise EInvalidOpException.Create(
      'Das Formular konnte nicht in den Textmodus umgeschaltet werden.'
    );
  Result := JsonSuccessPair('path', LPath);
end;

function CompileProjectTool(const AArguments: TJSONObject): TJSONObject;
var
  LClearMessages: Boolean;
  LMode: string;
  LProjectIdentifier: string;
begin
  LProjectIdentifier := JsonString(AArguments, 'project');
  LMode := JsonString(AArguments, 'mode', 'make');
  LClearMessages := JsonBoolean(AArguments, 'clear_messages', True);
  Result := TCodexMCPThreading.CallInIDEThread<TJSONObject>(
    function: TJSONObject
    var
      LCompileMode: TOTACompileMode;
      LProject: IOTAProject;
      LSucceeded: Boolean;
    begin
      LProject := FindProject(LProjectIdentifier);
      if not Assigned(LProject) then
        raise EInvalidOpException.Create('Kein passendes Delphi-Projekt gefunden.');
      if ClassifyPath(LProject.FileName) <> cpaWorkspaceReadWrite then
        raise EAccessViolation.Create(
          'Das ausgewählte Projekt liegt in einem schreibgeschützten Referenzpfad.'
        );
      if not Assigned(LProject.ProjectBuilder) then
        raise EInvalidOpException.Create('Das Projekt besitzt keinen ProjectBuilder.');
      if SameText(LMode, 'build') then
        LCompileMode := cmOTABuild
      else if SameText(LMode, 'make') then
        LCompileMode := cmOTAMake
      else
        raise EArgumentException.Create('mode muss "make" oder "build" sein.');
      LSucceeded := LProject.ProjectBuilder.BuildProject(
        LCompileMode,
        True,
        LClearMessages
      );
      Result := JsonSuccess;
      Result.AddPair('project', NormalizePath(LProject.FileName));
      Result.AddPair('mode', LMode);
      Result.AddPair('succeeded', TJSONBool.Create(LSucceeded));
    end
  );
end;

function CompileProjectGroupTool(const AArguments: TJSONObject): TJSONObject;
var
  LClearMessages: Boolean;
  LMode: string;
begin
  LMode := JsonString(AArguments, 'mode', 'make');
  LClearMessages := JsonBoolean(AArguments, 'clear_messages', True);
  Result := TCodexMCPThreading.CallInIDEThread<TJSONObject>(
    function: TJSONObject
    var
      LAllSucceeded: Boolean;
      LArray: TJSONArray;
      LCompileMode: TOTACompileMode;
      LCount: Integer;
      LFirst: Boolean;
      LItem: TJSONObject;
      LProject: IOTAProject;
      LSucceeded: Boolean;
    begin
      if SameText(LMode, 'build') then
        LCompileMode := cmOTABuild
      else if SameText(LMode, 'make') then
        LCompileMode := cmOTAMake
      else
        raise EArgumentException.Create('mode muss "make" oder "build" sein.');
      LArray := TJSONArray.Create;
      LAllSucceeded := True;
      LCount := 0;
      LFirst := True;
      for LProject in CollectProjects do
      begin
        if ClassifyPath(LProject.FileName) <> cpaWorkspaceReadWrite then
        begin
          LArray.Free;
          raise EAccessViolation.CreateFmt(
            'Das Projekt liegt in einem schreibgeschützten Referenzpfad: %s',
            [LProject.FileName]
          );
        end;
      end;
      for LProject in CollectProjects do
      begin
        Inc(LCount);
        if not Assigned(LProject.ProjectBuilder) then
          LSucceeded := False
        else
          LSucceeded := LProject.ProjectBuilder.BuildProject(
            LCompileMode,
            True,
            LClearMessages and LFirst
          );
        LFirst := False;
        LAllSucceeded := LAllSucceeded and LSucceeded;
        LItem := TJSONObject.Create;
        LItem.AddPair('project', NormalizePath(LProject.FileName));
        LItem.AddPair('succeeded', TJSONBool.Create(LSucceeded));
        LArray.AddElement(LItem);
      end;
      if LCount = 0 then
      begin
        LArray.Free;
        raise EInvalidOpException.Create('Die aktuelle Projektgruppe enthält kein Projekt.');
      end;
      Result := JsonSuccess;
      Result.AddPair('mode', LMode);
      Result.AddPair('count', TJSONNumber.Create(LCount));
      Result.AddPair('projects', LArray);
      Result.AddPair('succeeded', TJSONBool.Create(LAllSucceeded));
    end
  );
end;

function ReadOnlyRootsTool: TJSONObject;
var
  LArray: TJSONArray;
begin
  LArray := TJSONArray.Create;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LItem: TJSONObject;
      LRoot: TCodexReadOnlyRoot;
    begin
      for LRoot in GetReadOnlyRoots do
      begin
        LItem := TJSONObject.Create;
        LItem.AddPair('name', LRoot.Name);
        LItem.AddPair('path', LRoot.Path);
        LItem.AddPair('source', LRoot.Source);
        LItem.AddPair('exists', TJSONBool.Create(LRoot.Exists));
        LArray.AddElement(LItem);
      end;
    end
  );
  Result := NewArrayResult('roots', LArray);
end;

function ListWorkspaceDirectoryTool(
  const AArguments: TJSONObject
): TJSONObject;
var
  LDirectory: string;
  LMax: Integer;
  LPattern: string;
  LRecursive: Boolean;
  LValid: Boolean;
begin
  LDirectory := JsonString(AArguments, 'path');
  if Trim(LDirectory) = '' then
    LDirectory := TCodexMCPThreading.CallInIDEThread<string>(
      function: string
      var
        LProject: IOTAProject;
      begin
        LProject := FindProject('');
        if Assigned(LProject) then
          Result := ProjectDirectory(LProject)
        else
          Result := '';
      end
    )
  else
    LDirectory := ResolveRequestedPath(LDirectory);
  if LDirectory = '' then
    raise EInvalidOpException.Create('Kein Projektverzeichnis verfügbar.');
  LValid := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    begin
      Result := IsInsideAnyProjectDirectory(LDirectory);
    end
  );
  if not LValid then
    raise EAccessViolation.Create(
      'Das Verzeichnis liegt nicht in einem aktuell geöffneten Projekt.'
    );
  LPattern := CheckSearchPattern(
    JsonString(AArguments, 'search_pattern', '*')
  );
  LRecursive := JsonBoolean(AArguments, 'recursive', False);
  LMax := JsonInteger(AArguments, 'max_results', 5000);
  Result := ListDirectoryFiles(
    LDirectory,
    LPattern,
    LRecursive,
    LMax
  );
end;

function ListReadOnlyDirectoryTool(
  const AArguments: TJSONObject
): TJSONObject;
var
  LDirectory: string;
  LMax: Integer;
  LPattern: string;
  LRecursive: Boolean;
  LValid: Boolean;
begin
  LDirectory := ResolveRequestedPath(RequireJsonString(AArguments, 'path'));
  LValid := TCodexMCPThreading.CallInIDEThread<Boolean>(
    function: Boolean
    begin
      Result := ClassifyPath(LDirectory) = cpaReadOnlyReference;
    end
  );
  if not LValid then
    raise EAccessViolation.Create(
      'Das Verzeichnis liegt nicht in einem schreibgeschützten Referenzpfad.'
    );
  LPattern := CheckSearchPattern(
    JsonString(AArguments, 'search_pattern', '*')
  );
  LRecursive := JsonBoolean(AArguments, 'recursive', False);
  LMax := JsonInteger(AArguments, 'max_results', 5000);
  Result := ListDirectoryFiles(
    LDirectory,
    LPattern,
    LRecursive,
    LMax
  );
end;

function StatusTool: TJSONObject;
var
  LRootArray: TJSONArray;
  LRuntime: TJSONObject;
begin
  Result := JsonSuccess;
  Result.AddPair('enabled', TJSONBool.Create(TCodexMCPSettings.Instance.Enabled));
  Result.AddPair('port', TJSONNumber.Create(TCodexMCPSettings.Instance.Port));
  Result.AddPair(
    'logging_enabled',
    TJSONBool.Create(TCodexMCPSettings.Instance.LoggingEnabled)
  );
  Result.AddPair(
    'codex_config_file',
    TCodexMCPRegistration.CodexConfigFile
  );
  Result.AddPair(
    'codex_config_exists',
    TJSONBool.Create(TCodexMCPRegistration.CodexConfigExists)
  );
  Result.AddPair(
    'codex_registered',
    TJSONBool.Create(TCodexMCPRegistration.IsCodexRegistered)
  );
  Result.AddPair('skill_file', TCodexMCPRegistration.SkillFile);
  Result.AddPair(
    'skill_file_exists',
    TJSONBool.Create(TCodexMCPRegistration.SkillFileExists)
  );
  Result.AddPair(
    'skill_registered',
    TJSONBool.Create(TCodexMCPRegistration.IsSkillRegistered)
  );
  LRuntime := TCodexMCPRuntime.Status;
  Result.AddPair('runtime', LRuntime);
  LRootArray := TJSONArray.Create;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LRoot: TCodexReadOnlyRoot;
      LRootItem: TJSONObject;
    begin
      for LRoot in GetReadOnlyRoots do
      begin
        LRootItem := TJSONObject.Create;
        LRootItem.AddPair('name', LRoot.Name);
        LRootItem.AddPair('path', LRoot.Path);
        LRootItem.AddPair('exists', TJSONBool.Create(LRoot.Exists));
        LRootArray.AddElement(LRootItem);
      end;
    end
  );
  Result.AddPair('read_only_roots', LRootArray);
end;

class function TCodexMCPToolDispatcher.DoExecute(
  const AName: string;
  const AArguments: TJSONObject
): TJSONValue;
begin
  if SameText(AName, 'ide_status') then
    Exit(StatusTool);
  if SameText(AName, 'ide_list_open_files') then
    Exit(ListOpenFiles);
  if SameText(AName, 'ide_list_projects') then
    Exit(ListProjects);
  if SameText(AName, 'ide_list_project_files') then
    Exit(ListProjectFiles(JsonString(AArguments, 'project')));
  if SameText(AName, 'ide_list_directory_files') then
    Exit(ListWorkspaceDirectoryTool(AArguments));
  if SameText(AName, 'ide_read_file') then
    Exit(ReadFileResult(AArguments, cpaWorkspaceReadWrite));
  if SameText(AName, 'ide_write_file') then
    Exit(WriteWorkspaceFile(AArguments));
  if SameText(AName, 'ide_list_readonly_roots') then
    Exit(ReadOnlyRootsTool);
  if SameText(AName, 'ide_list_readonly_files') then
    Exit(ListReadOnlyDirectoryTool(AArguments));
  if SameText(AName, 'ide_read_readonly_file') then
    Exit(ReadFileResult(AArguments, cpaReadOnlyReference));
  if SameText(AName, 'ide_create_project') then
    Exit(CreateProjectTool(AArguments));
  if SameText(AName, 'ide_open_project') then
    Exit(OpenProjectTool(AArguments));
  if SameText(AName, 'ide_save_project') then
    Exit(SaveProjectTool(AArguments));
  if SameText(AName, 'ide_remove_project') then
    Exit(RemoveProjectTool(AArguments));
  if SameText(AName, 'ide_create_unit') then
    Exit(CreateUnitTool(AArguments, False));
  if SameText(AName, 'ide_create_form_unit') then
    Exit(CreateUnitTool(AArguments, True));
  if SameText(AName, 'ide_open_file') or
    SameText(AName, 'ide_activate_file') then
    Exit(OpenFileTool(AArguments));
  if SameText(AName, 'ide_close_file') then
    Exit(CloseFileTool(AArguments));
  if SameText(AName, 'ide_remove_file_from_project') then
    Exit(RemoveFileFromProjectTool(AArguments));
  if SameText(AName, 'ide_show_form_as_text') then
    Exit(ShowFormAsTextTool(AArguments));
  if SameText(AName, 'ide_compile_project') then
    Exit(CompileProjectTool(AArguments));
  if SameText(AName, 'ide_compile_project_group') then
    Exit(CompileProjectGroupTool(AArguments));
  if SameText(AName, 'ide_run_project') then
    Exit(
      TCodexMCPRuntime.RunProject(
        JsonString(AArguments, 'project'),
        JsonBoolean(AArguments, 'debugger', True),
        JsonBoolean(AArguments, 'build_first', True)
      )
    );
  if SameText(AName, 'ide_stop_project') then
    Exit(TCodexMCPRuntime.StopProject);
  if SameText(AName, 'ide_message_box') then
    Exit(
      TCodexMCPUserInteraction.ShowMessageBox(
        JsonString(AArguments, 'title', 'Codex'),
        RequireJsonString(AArguments, 'text'),
        JsonString(AArguments, 'kind', 'information'),
        JsonString(AArguments, 'buttons', 'ok')
      )
    );
  if SameText(AName, 'ide_input_box') then
    Exit(
      TCodexMCPUserInteraction.ShowInputBox(
        JsonString(AArguments, 'title', 'Codex'),
        RequireJsonString(AArguments, 'prompt'),
        JsonString(AArguments, 'default')
      )
    );
  if SameText(AName, 'ide_balloon_hint') then
    Exit(
      TCodexMCPUserInteraction.ShowBalloonHint(
        JsonString(AArguments, 'title', 'Codex'),
        RequireJsonString(AArguments, 'text'),
        JsonInteger(AArguments, 'timeout_ms', 5000)
      )
    );
  raise EArgumentException.CreateFmt('Unbekanntes MCP-Tool: %s', [AName]);
end;

class function TCodexMCPToolDispatcher.Execute(
  const AName: string;
  const AArguments: TJSONObject
): TJSONValue;
begin
  TCodexMCPLogger.Log(AName, 'Aufruf');
  try
    Result := DoExecute(AName, AArguments);
    TCodexMCPLogger.Log(AName, 'Erfolgreich');
  except
    on E: Exception do
    begin
      TCodexMCPLogger.Log(AName, 'Fehler: ' + E.Message);
      raise;
    end;
  end;
end;

end.
