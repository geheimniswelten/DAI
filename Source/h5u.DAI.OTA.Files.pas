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
    class function DirectoryFiles( const ADirectory: string;
      const ASearchPattern: string;
      const ARecursive: Boolean;
      const AMaximumCount: Integer
    ): TJSONArray; static;
    class function ReferenceRoots: TJSONArray; static;
    class function ReadFile( const AFileName: string;
      const AMaximumCharacters: Integer
    ): TJSONObject; static;
    class function WriteFile( const AFileName: string;
      const AContent: string;
      const AExpectedSha256: string;
      const ASave: Boolean;
      out AUsedEditorBuffer: Boolean
    ): TJSONObject; static;
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

function EnsureDFMTextEditor(const AFileName: string): IOTASourceEditor;
var
  LActionServices: IOTAActionServices;
begin
  Result := TDAIOTA.FindSourceEditor(AFileName);
  if Assigned(Result) or not SameText(TPath.GetExtension(AFileName), '.dfm') then
    Exit;

  if not TDAIOTA.IsFormLoadedForFile(AFileName) then
    Exit;

  TDAIOTA.RunOnMainThread(
    procedure
    begin
      if Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
        LActionServices.OpenFile(AFileName);
    end);
  Result := TDAIOTA.FindSourceEditor(AFileName);
end;

function ReadCompleteText(const AFileName: string; out AFromEditor: Boolean): string;
var
  LResult: string;
  LSourceEditor: IOTASourceEditor;
begin
  AFromEditor := False;
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
    Exit(LResult);
  end;

  if not TFile.Exists(AFileName) then
    raise EFOpenError.CreateFmt('Datei nicht gefunden: %s', [AFileName]);
  if TFile.GetSize(AFileName) > CDAIMaxTextFileBytes then
    raise EInvalidOperation.CreateFmt('Die Datei überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);
  Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
end;

class function TDAIFileService.DirectoryFiles( const ADirectory: string;
  const ASearchPattern: string;
  const ARecursive: Boolean;
  const AMaximumCount: Integer
): TJSONArray;
var
  LCount: Integer;
  LDirectory: string;
  LFileName: string;
  LFiles: TArray<string>;
  LLimit: Integer;
  LPattern: string;
  LSearchOption: TSearchOption;
begin
  Result := TJSONArray.Create;
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
  Result := TJSONArray.Create;
  LFiles := TDictionary<string, Boolean>.Create;
  try
    LProject := TDAIOTA.ProjectByNameOrPath(AProjectNameOrPath);
    if not Assigned(LProject) then
      raise EArgumentException.Create('Das angegebene Projekt ist nicht geöffnet.');

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

class function TDAIFileService.ReadFile(const AFileName: string; const AMaximumCharacters: Integer): TJSONObject;
var
  LContent: string;
  LFileName: string;
  LFromEditor: Boolean;
  LHash: string;
  LOriginalLength: Integer;
  LTruncated: Boolean;
begin
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);
  if not FileAllowedForRead(LFileName) then
    raise EDAIAccessDenied.Create('Lesezugriff ist nur auf Workspace- und freigegebene Referenzdateien erlaubt.');

  LContent := ReadCompleteText(LFileName, LFromEditor);
  LOriginalLength := Length(LContent);
  LHash := THashSHA2.GetHashString(LContent);
  LTruncated := (AMaximumCharacters > 0) and (Length(LContent) > AMaximumCharacters);
  if LTruncated then
    SetLength(LContent, AMaximumCharacters);

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('content', LContent);
  Result.AddPair('source', IfThen(LFromEditor, 'editor_buffer', 'disk'));
  Result.AddPair('sha256', LHash);
  Result.AddPair('original_characters', TJSONNumber.Create(LOriginalLength));
  Result.AddPair('truncated', TJSONBool.Create(LTruncated));
  Result.AddPair('read_only_reference', TJSONBool.Create(TDAIOTA.IsReadOnlyReferenceFile(LFileName)));
end;

class function TDAIFileService.ReferenceRoots: TJSONArray;
var
  LDirectory: string;
begin
  Result := TJSONArray.Create;
  for LDirectory in TDAISettings.Instance.ReadOnlyRootDirectories do
    Result.AddElement(
      TJSONObject.Create
        .AddPair('directory', LDirectory)
        .AddPair('exists', TJSONBool.Create(TDirectory.Exists(LDirectory)))
        .AddPair('read_only', TJSONBool.Create(True))
    );
end;

class function TDAIFileService.WriteFile( const AFileName: string;
  const AContent: string;
  const AExpectedSha256: string;
  const ASave: Boolean;
  out AUsedEditorBuffer: Boolean
): TJSONObject;
var
  LActionServices: IOTAActionServices;
  LCurrentContent: string;
  LCurrentHash: string;
  LFileName: string;
  LSourceEditor: IOTASourceEditor;
begin
  AUsedEditorBuffer := False;
  LFileName := TDAISettings.Instance.ExpandPath(AFileName);

  if TDAIOTA.IsReadOnlyReferenceFile(LFileName) then
    raise EDAIAccessDenied.Create('Delphi-Sourcen, Demos, GetIt-Pakete und zusätzliche Referenzverzeichnisse sind schreibgeschützt.');
  if not TDAIOTA.IsWorkspaceFile(LFileName) then
    raise EDAIAccessDenied.Create('Schreibzugriff ist nur innerhalb geöffneter Workspaces erlaubt.');
  if TEncoding.UTF8.GetByteCount(AContent) > CDAIMaxTextFileBytes then
    raise EInvalidOperation.CreateFmt('Der neue Inhalt überschreitet das Limit von %d MiB.', [CDAIMaxTextFileBytes div 1024 div 1024]);

  if TFile.Exists(LFileName) or TDAIOTA.IsFileOpenInEditor(LFileName) then
  begin
    LCurrentContent := ReadCompleteText(LFileName, AUsedEditorBuffer);
    LCurrentHash := THashSHA2.GetHashString(LCurrentContent);
    if (Trim(AExpectedSha256) <> '') and not SameText(LCurrentHash, Trim(AExpectedSha256)) then
      raise EInvalidOperation.CreateFmt('Die Datei wurde zwischenzeitlich geändert. Erwartet: %s; aktuell: %s.', [AExpectedSha256, LCurrentHash]);
  end;

  LSourceEditor := EnsureDFMTextEditor(LFileName);
  if Assigned(LSourceEditor) then
  begin
    AUsedEditorBuffer := True;
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        if not TDAIOTA.ReplaceEditorText(LSourceEditor, AContent) then
          raise EInvalidOperation.Create('Der Editorpuffer konnte nicht ersetzt werden.');
        if ASave and Supports(BorlandIDEServices, IOTAActionServices, LActionServices) and not LActionServices.SaveFile(LFileName) then
          raise EInvalidOperation.Create('Der Editorpuffer wurde geändert, konnte aber nicht gespeichert werden.');
      end);
  end
  else
  begin
    if TDAIOTA.IsFormLoadedForFile(LFileName) then
      raise EInvalidOperation.Create('Das Formular ist im Designer geladen. Wechseln Sie zuerst mit form_show_as_text in den Textmodus.');
    ForceDirectories(TPath.GetDirectoryName(LFileName));
    TFile.WriteAllText(LFileName, AContent, TEncoding.UTF8);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file', LFileName);
  Result.AddPair('target', IfThen(AUsedEditorBuffer, 'editor_buffer', 'disk'));
  Result.AddPair('saved', TJSONBool.Create((not AUsedEditorBuffer) or ASave));
  Result.AddPair('sha256', THashSHA2.GetHashString(AContent));
end;

end.
