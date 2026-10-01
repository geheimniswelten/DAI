unit h5u.DAI.OTA.Files;

interface

uses
  System.JSON;

type
  TDAIFileService = class sealed
  public
    class function OpenFiles: TJSONArray; static;
    class function Projects: TJSONArray; static;
    class function ProjectFiles(const AProjectNameOrPath: string): TJSONArray; static;
    class function DirectoryFiles(const ADirectory: string; const ASearchPattern: string; const ARecursive: Boolean; const AMaximumCount: Integer): TJSONArray; static;
    class function ReferenceRoots: TJSONArray; static;
    class function ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean = True): TJSONObject; static;
    class function WriteFile(const AFileName: string; const AContent: string; const AExpectedSha256: string; const ASave: Boolean; out AUsedEditorBuffer: Boolean):
      TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Hash,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings,
  h5u.DAI.Source.View,
  h5u.DAI.Text.Encoding,
  h5u.DAI.Types;

procedure AddUniqueFile(const AFiles: TDictionary<string, Boolean>; const AFileName: string);
var
  LFileName: string;
begin
  if Trim(AFileName) = '' then
    Exit;
  try
    LFileName := TDAIOTA.NormalizeFileName(AFileName);
  except
    Exit;
  end;
  AFiles.AddOrSetValue(LFileName, True);
end;

function FileAllowedForRead(const AFileName: string): Boolean;
begin
  Result := TDAIOTA.IsWorkspaceFile(AFileName) or TDAIOTA.IsReadOnlyReferenceFile(AFileName);
end;

function DirectoryAllowedForRead(const ADirectory: string): Boolean;
var
  LRoot: string;
begin
  Result := False;
  for LRoot in TDAIOTA.WorkspaceRoots do
    if TDAIOTA.IsPathWithin(ADirectory, LRoot) or TDAIOTA.SameFile(ADirectory, LRoot) then
      Exit(True);
  for LRoot in TDAISettings.Instance.ReadOnlyRootDirectories do
    if TDAIOTA.IsPathWithin(ADirectory, LRoot) or TDAIOTA.SameFile(ADirectory, LRoot) then
      Exit(True);
end;

function EnsureFormTextEditor(const AFileName: string): IOTASourceEditor;
var
  LActionServices: IOTAActionServices;
begin
  Result := TDAIOTA.FindSourceEditor(AFileName);
  if Assigned(Result) or not (SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx')) then
    Exit;

  if not TFile.Exists(AFileName) and not TDAIOTA.IsFormLoadedForFile(AFileName) then
    Exit;

  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
        LActionServices.OpenFile(AFileName);
    end);
  Result := TDAIOTA.FindSourceEditor(AFileName);
end;

function ReadCompleteText(const AFileName: string; out AFromEditor: Boolean; out AFormat: TDAITextFileFormat; out AFromDesigner: Boolean): string;
var
  LResult: string;
  LSourceEditor: IOTASourceEditor;
begin
  AFromEditor := False;
  AFromDesigner := False;
  LSourceEditor := TDAIOTA.FindSourceEditor(AFileName);
  if Assigned(LSourceEditor) then
  begin
    AFromEditor := True;
    LResult := '';
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        LResult := TDAIOTA.ReadEditorText(LSourceEditor);
      end);
    AFormat.EncodingKind := tekIDEBuffer;
    AFormat.LineEndingKind := TDAITextEncoding.DetectLineEnding(LResult);
    Exit(LResult);
  end;

  if (SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx')) and
    TDAIOTA.ReadFormText(AFileName, CDAIMaxTextFileBytes, LResult) then
  begin
    AFromEditor := True;
    AFromDesigner := True;
    AFormat.EncodingKind := tekIDEBuffer;
    AFormat.LineEndingKind := TDAITextEncoding.DetectLineEnding(LResult);
    Exit(LResult);
  end;

  if not TFile.Exists(AFileName) then
    raise EDAIFileNotFound.CreateFmt('Datei nicht gefunden: %s', [AFileName]);
  if TFile.GetSize(AFileName) > CDAIMaxTextFileBytes then
    raise EInvalidOperation.CreateFmt('Die Datei überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);
  Result := TDAITextEncoding.ReadFile(AFileName, AFormat);
end;

class function TDAIFileService.DirectoryFiles(const ADirectory: string; const ASearchPattern: string; const ARecursive: Boolean; const AMaximumCount: Integer): TJSONArray;
var
  LCount: Integer;
  LDirectory: string;
  LFileName: string;
  LFiles: TArray<string>;
  LLimit: Integer;
  LPattern: string;
  LSearchOption: TSearchOption;
begin
  LDirectory := TDAISettings.Instance.ExpandPath(ADirectory);
  if not TDirectory.Exists(LDirectory) then
    raise EDirectoryNotFoundException.CreateFmt('Verzeichnis nicht gefunden: %s', [LDirectory]);
  if not DirectoryAllowedForRead(LDirectory) then
    raise EDAIAccessDenied.Create('Das Verzeichnis gehört weder zum Workspace noch zu einem freigegebenen Referenzpfad.');

  LPattern := Trim(ASearchPattern);
  if LPattern = '' then
    LPattern := '*';
  if LPattern.Contains('\') or LPattern.Contains('/') or LPattern.Contains('..') then
    raise EArgumentException.Create('Das Suchmuster darf keinen Verzeichnispfad enthalten.');

  if ARecursive then
    LSearchOption := TSearchOption.soAllDirectories
  else
    LSearchOption := TSearchOption.soTopDirectoryOnly;

  LLimit := AMaximumCount;
  if LLimit <= 0 then
    LLimit := 5000;
  LLimit := EnsureRange(LLimit, 1, 50000);

  LFiles := TDirectory.GetFiles(LDirectory, LPattern, LSearchOption);
  TArray.Sort<string>(LFiles);
  Result := TJSONArray.Create;
  LCount := 0;
  for LFileName in LFiles do
  begin
    Result.Add(TDAIOTA.NormalizeFileName(LFileName));
    Inc(LCount);
    if LCount >= LLimit then
      Break;
  end;
end;

class function TDAIFileService.OpenFiles: TJSONArray;
var
  LFileName: string;
  LFiles: TDictionary<string, Boolean>;
begin
  Result := TJSONArray.Create;
  LFiles := TDictionary<string, Boolean>.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure var LEditorIndex: Integer;
        LModuleIndex: Integer;
        LModuleServices: IOTAModuleServices;
        LModule: IOTAModule;
      begin
        if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
          Exit;

        for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
        begin
          LModule := LModuleServices.Modules[LModuleIndex];
          if not Assigned(LModule) then
            Continue;
          AddUniqueFile(LFiles, LModule.FileName);
          for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
            if Assigned(LModule.ModuleFileEditors[LEditorIndex]) then
              AddUniqueFile(LFiles, LModule.ModuleFileEditors[LEditorIndex].FileName);
        end;
      end);

    for LFileName in LFiles.Keys do
      Result.Add(LFileName);
  finally
    LFiles.Free;
  end;
end;

class function TDAIFileService.ProjectFiles(const AProjectNameOrPath: string): TJSONArray;
var
  LFiles: TDictionary<string, Boolean>;
  LFileName: string;
  LProject: IOTAProject;
begin
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');
  Result := TJSONArray.Create;
  LFiles := TDictionary<string, Boolean>.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LAdditionalFiles: TStringList;
        LFileName: string;
        LIndex: Integer;
        LModuleInfo: IOTAModuleInfo;
      begin
        AddUniqueFile(LFiles, TDAIOTA.ProjectFileName(LProject));
        for LIndex := 0 to LProject.GetModuleCount - 1 do
        begin
          LModuleInfo := LProject.GetModule(LIndex);
          if not Assigned(LModuleInfo) then
            Continue;
          AddUniqueFile(LFiles, LModuleInfo.FileName);

          LAdditionalFiles := TStringList.Create;
          try
            LModuleInfo.GetAdditionalFiles(LAdditionalFiles);
            for LFileName in LAdditionalFiles do
              AddUniqueFile(LFiles, LFileName);
          finally
            LAdditionalFiles.Free;
          end;
        end;
      end);

    for LFileName in LFiles.Keys do
      Result.Add(LFileName);
  finally
    LFiles.Free;
  end;
end;

class function TDAIFileService.Projects: TJSONArray;
var
  LItem: TJSONObject;
  LProject: IOTAProject;
  LProjectFileName: string;
begin
  Result := TJSONArray.Create;
  for LProject in TDAIOTA.Projects do
  begin
    LProjectFileName := TDAIOTA.ProjectFileName(LProject);
    LItem := TJSONObject.Create;
    LItem.AddPair('name', TPath.GetFileNameWithoutExtension(LProjectFileName));
    LItem.AddPair('file', LProjectFileName);
    LItem.AddPair('directory', TDAIOTA.NormalizeFileName(TPath.GetDirectoryName(LProjectFileName)));
    LItem.AddPair('configuration', TDAIOTA.ProjectConfiguration(LProject));
    LItem.AddPair('platform', TDAIOTA.ProjectPlatform(LProject));
    Result.AddElement(LItem);
  end;
end;

class function TDAIFileService.ReadFile(const AFileName: string; const AMaximumCharacters: Integer; const AInterfacesOnly: Boolean): TJSONObject;
var
  LContent: string;
  LFileName: string;
  LFormat: TDAITextFileFormat;
  LFromDesigner: Boolean;
  LFromEditor: Boolean;
  LHash: string;
  LOriginalLength: Integer;
  LImplementationOmitted: Boolean;
  LTruncated: Boolean;
  LViewLength: Integer;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if not FileAllowedForRead(LFileName) then
    raise EDAIAccessDenied.Create('Lesezugriff ist nur auf Workspace- und freigegebene Referenzdateien erlaubt.');

  LContent := ReadCompleteText(LFileName, LFromEditor, LFormat, LFromDesigner);
  LOriginalLength := Length(LContent);
  LHash := THashSHA2.GetHashString(LContent);
  LImplementationOmitted := False;
  if AInterfacesOnly then
    LContent := TDAISourceView.InterfaceText(LFileName, LContent, LImplementationOmitted);
  LViewLength := Length(LContent);
  LTruncated := (AMaximumCharacters > 0) and (Length(LContent) > AMaximumCharacters);
  if LTruncated then
    SetLength(LContent, AMaximumCharacters);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('content', LContent);
  if LFromDesigner then
    Result.AddPair('source', 'designer_buffer')
  else
    Result.AddPair('source', IfThen(LFromEditor, 'editor_buffer', 'disk'));
  Result.AddPair('encoding', TDAITextEncoding.EncodingName(LFormat.EncodingKind));
  Result.AddPair('line_ending', TDAITextEncoding.LineEndingName(LFormat.LineEndingKind));
  Result.AddPair('sha256', LHash);
  Result.AddPair('sha256_scope', 'complete_content');
  Result.AddPair('interfaces_only', TJSONBool.Create(AInterfacesOnly));
  Result.AddPair('implementation_omitted', TJSONBool.Create(LImplementationOmitted));
  Result.AddPair('view_characters', TJSONNumber.Create(LViewLength));
  Result.AddPair('content_complete', TJSONBool.Create(not LImplementationOmitted and not LTruncated));
  Result.AddPair('original_characters', TJSONNumber.Create(LOriginalLength));
  Result.AddPair('truncated', TJSONBool.Create(LTruncated));
  Result.AddPair('read_only_reference', TJSONBool.Create(TDAIOTA.IsReadOnlyReferenceFile(LFileName)));
end;

class function TDAIFileService.ReferenceRoots: TJSONArray;
var
  LAlias: string;
  LDirectory: string;
begin
  Result := TJSONArray.Create;
  for LDirectory in TDAISettings.Instance.ReadOnlyRootDirectories do
  begin
    LAlias := '';
    if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.DelphiSourceDirectory) then
      LAlias := '%BDS%\source'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.ToolsAPIDirectory) then
      LAlias := '%BDS%\source\ToolsAPI'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.SamplesDirectory) then
      LAlias := '%BDS%\Samples'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.CatalogRepositoryAllUsersDirectory) then
      LAlias := '%BDSCatalogRepositoryAllUsers%'
    else if TDAIOTA.SameFile(LDirectory, TDAISettings.Instance.CatalogRepositoryDirectory) then
      LAlias := '%BDSCatalogRepository%';
    Result.AddElement(
      TJSONObject.Create
        .AddPair('directory', LDirectory)
        .AddPair('alias', LAlias)
        .AddPair('exists', TJSONBool.Create(TDirectory.Exists(LDirectory)))
        .AddPair('read_only', TJSONBool.Create(True))
    );
  end;
end;

class function TDAIFileService.WriteFile(const AFileName: string; const AContent: string; const AExpectedSha256: string; const ASave: Boolean; out AUsedEditorBuffer: Boolean):
  TJSONObject;
var
  LActionServices: IOTAActionServices;
  LActualContent: string;
  LBytes: TBytes;
  LCurrentContent: string;
  LCurrentFormat: TDAITextFileFormat;
  LCurrentHash: string;
  LFileName: string;
  LFromDesigner: Boolean;
  LHasCurrentContent: Boolean;
  LOriginalEncoding: string;
  LOriginalLineEnding: string;
  LProjectSidecar: string;
  LFormat: TDAITextFileFormat;
  LSourceEditor: IOTASourceEditor;
  LWrittenContent: string;
begin
  AUsedEditorBuffer := False;
  LFromDesigner := False;
  LHasCurrentContent := False;
  LOriginalEncoding := '';
  LOriginalLineEnding := '';
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  TDAIOTA.RequireNoReparseWritePath(LFileName);
  if SameText(TPath.GetExtension(LFileName), '.dpr') or SameText(TPath.GetExtension(LFileName), '.dpk') then
    LProjectSidecar := ChangeFileExt(LFileName, '.dproj')
  else if SameText(TPath.GetExtension(LFileName), '.dproj') then
    LProjectSidecar := LFileName
  else
    LProjectSidecar := '';
  if LProjectSidecar <> '' then
  begin
    TDAIOTA.RequireNoReparseWritePath(LProjectSidecar);
    TDAIOTA.RequireNoReparseWritePath(LProjectSidecar + '.local');
  end;

  if TDAIOTA.IsReadOnlyReferenceFile(LFileName) then
    raise EDAIAccessDenied.Create('Delphi-Sourcen, Demos, GetIt-Pakete und zusätzliche Referenzverzeichnisse sind schreibgeschützt.');
  if not TDAIOTA.IsWorkspaceFile(LFileName) then
    raise EDAIAccessDenied.Create('Schreibzugriff ist nur innerhalb geöffneter Workspaces erlaubt.');

  if TFile.Exists(LFileName) or TDAIOTA.IsFileOpenInEditor(LFileName) or TDAIOTA.IsFormLoadedForFile(LFileName) then
  begin
    LCurrentContent := ReadCompleteText(LFileName, AUsedEditorBuffer, LCurrentFormat, LFromDesigner);
    LHasCurrentContent := True;
    LCurrentHash := THashSHA2.GetHashString(LCurrentContent);
    LOriginalEncoding := TDAITextEncoding.EncodingName(LCurrentFormat.EncodingKind);
    LOriginalLineEnding := TDAITextEncoding.LineEndingName(LCurrentFormat.LineEndingKind);
    if (Trim(AExpectedSha256) <> '') and not SameText(LCurrentHash, Trim(AExpectedSha256)) then
      raise EInvalidOperation.CreateFmt('Die Datei wurde zwischenzeitlich geändert. Erwartet: %s; aktuell: %s.', [AExpectedSha256, LCurrentHash]);
  end
  else if Trim(AExpectedSha256) <> '' then
    raise EInvalidOperation.Create('Die Datei existiert nicht mehr; expected_sha256 kann nicht erfüllt werden.');

  TDAISourceView.RequireCompleteUnit(LFileName, AContent);
  LSourceEditor := EnsureFormTextEditor(LFileName);
  if Assigned(LSourceEditor) then
  begin
    if LHasCurrentContent then
      LWrittenContent := TDAITextEncoding.PrepareText(LFileName, AContent, LCurrentFormat.LineEndingKind)
    else
      LWrittenContent := TDAITextEncoding.PrepareText(LFileName, AContent, lekNone);
    if TEncoding.UTF8.GetByteCount(LWrittenContent) > CDAIMaxTextFileBytes then
      raise EInvalidOperation.CreateFmt('Der neue Inhalt überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);

    AUsedEditorBuffer := True;
    LFormat.EncodingKind := tekIDEBuffer;
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        if LHasCurrentContent and (TDAIOTA.ReadEditorText(LSourceEditor) <> LCurrentContent) then
        begin
          if LFromDesigner then
            raise EInvalidOperation.Create('Der Formulartext wurde in einen Textpuffer übertragen. Lesen Sie den aktuellen IDE-Textpuffer erneut.');
          raise EInvalidOperation.Create('Der Editorpuffer wurde während der Schreibanforderung geändert. Lesen Sie die Datei erneut.');
        end;
        if not TDAIOTA.ReplaceEditorText(LSourceEditor, LWrittenContent, LActualContent) then
          raise EInvalidOperation.Create('Der Editorpuffer konnte nicht ersetzt werden.');
        LWrittenContent := LActualContent;
        if ASave then
        begin
          if not Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
            raise EInvalidOperation.Create('Der Editorpuffer wurde geändert; IOTAActionServices zum Speichern ist nicht verfügbar.');
          if not LActionServices.SaveFile(LFileName) then
            raise EInvalidOperation.Create('Der Editorpuffer wurde geändert, konnte aber nicht gespeichert werden.');
          LWrittenContent := TDAIOTA.ReadEditorText(LSourceEditor);
        end;
        LFormat.LineEndingKind := TDAITextEncoding.DetectLineEnding(LWrittenContent);
      end);
  end
  else
  begin
    if not ASave then
      raise EInvalidOperation.Create('save=false erfordert einen geöffneten IDE-Textpuffer. Öffnen Sie die Datei zuerst mit file_open.');
    if SameText(TPath.GetExtension(LFileName), '.dfm') or SameText(TPath.GetExtension(LFileName), '.fmx') then
      raise EInvalidOperation.Create('Formulardateien werden ausschließlich über einen verfügbaren IDE-Textpuffer geändert.');
    if TDAIOTA.IsFormLoadedForFile(LFileName) then
      raise EInvalidOperation.Create('Das Formular ist im Designer geladen. Wechseln Sie zuerst mit form_show_as_text in den Textmodus.');

    LBytes := TDAITextEncoding.PrepareWrite(LFileName, AContent, LWrittenContent, LFormat);
    if Length(LBytes) > CDAIMaxTextFileBytes then
      raise EInvalidOperation.CreateFmt('Der neue Inhalt überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);
    ForceDirectories(TPath.GetDirectoryName(LFileName));
    TFile.WriteAllBytes(LFileName, LBytes);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('target', IfThen(AUsedEditorBuffer, 'editor_buffer', 'disk'));
  Result.AddPair('saved', TJSONBool.Create((not AUsedEditorBuffer) or ASave));
  Result.AddPair('encoding', TDAITextEncoding.EncodingName(LFormat.EncodingKind));
  Result.AddPair('original_encoding', LOriginalEncoding);
  Result.AddPair('line_ending', TDAITextEncoding.LineEndingName(LFormat.LineEndingKind));
  Result.AddPair('original_line_ending', LOriginalLineEnding);
  Result.AddPair('sha256', THashSHA2.GetHashString(LWrittenContent));
end;

end.
