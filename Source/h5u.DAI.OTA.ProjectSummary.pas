unit h5u.DAI.OTA.ProjectSummary;

interface

uses
  System.JSON;

type
  TDAIProjectSummaryService = class sealed
  public
    class function Projects: TJSONArray; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  Xml.XMLDoc,
  Xml.XMLIntf,
  ToolsAPI,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.PackageSummary,
  h5u.DAI.Text.Encoding;

const
  CMaximumConfigurations = 1000;
  CMSBuildNamespace = 'http://schemas.microsoft.com/developer/msbuild/2003';

procedure AddNullableString(const AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue = '' then
    AObject.AddPair(AName, TJSONNull.Create)
  else
    AObject.AddPair(AName, AValue);
end;

function OutputType(const AApplicationType: string): string;
begin
  if SameText(AApplicationType, sApplication) or SameText(AApplicationType, sConsole) then
    Exit('EXE');
  if SameText(AApplicationType, sLibrary) then
    Exit('DLL');
  if SameText(AApplicationType, sPackage) then
    Exit('Package');
  Result := '';
end;

function TargetFile(const ATargetName, AProjectDirectory: string): string;
begin
  Result := Trim(ATargetName);
  // TargetName includes the actual platform extension and package suffix.
  if (Result = '') or Result.Contains('$(') or Result.Contains('@(') or Result.Contains('%') then
    Exit('');
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  try
    if TPath.IsPathRooted(Result) then
    begin
      if not Result.StartsWith('\\') then
      begin
        if Length(Result) < 3 then
          Exit('');
        if (Result[2] <> ':') or (Result[3] <> '\') then
          Exit('');
      end;
    end
    else
    begin
      if Result.Contains(':') then
        Exit('');
      Result := TPath.Combine(AProjectDirectory, Result);
    end;
    Result := TDAIOTA.NormalizeFileName(Result);
  except
    Result := '';
  end;
end;

function ConfigurationMatches(const AConfiguration: IOTABuildConfiguration; const AName: string): Boolean;
begin
  Result := False;
  if Assigned(AConfiguration) and (AName <> '') then
    Result := SameText(AConfiguration.Name, AName) or SameText(AConfiguration.Key, AName);
end;

function MatchingPlatformConfiguration(const AConfiguration: IOTABuildConfiguration; const AName, APlatform: string): IOTABuildConfiguration;
begin
  Result := nil;
  if not Assigned(AConfiguration) then
    Exit;
  if not ConfigurationMatches(AConfiguration, AName) then
    Exit;
  if SameText(AConfiguration.Platform, APlatform) then
    Exit(AConfiguration);
  if (AConfiguration.Platform <> '') or (APlatform = '') then
    Exit;
  Result := AConfiguration.PlatformConfiguration[APlatform];
  if Assigned(Result) then
    if not SameText(Result.Platform, APlatform) then
      Result := nil;
end;

function CurrentBuildConfiguration(const AProject: IOTAProject; const AConfiguration, APlatform: string): IOTABuildConfiguration;
var
  LCandidate: IOTABuildConfiguration;
  LConfigurations: IOTAProjectOptionsConfigurations;
  LCount, LIndex: Integer;
begin
  Result := nil;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, LConfigurations) then
    Exit;
  // Match the project's own selection; never activate a project or switch scopes.
  try
    Result := MatchingPlatformConfiguration(LConfigurations.ActiveConfiguration, AConfiguration, APlatform);
  except
    Result := nil;
  end;
  if Assigned(Result) then
    Exit;
  LCount := LConfigurations.ConfigurationCount;
  if (LCount < 0) or (LCount > CMaximumConfigurations) then
    Exit;
  for LIndex := 0 to LCount - 1 do
  begin
    LCandidate := MatchingPlatformConfiguration(LConfigurations.Configurations[LIndex], AConfiguration, APlatform);
    if not Assigned(LCandidate) then
      Continue;
    if Assigned(Result) then
    begin
      if not SameText(Result.Key, LCandidate.Key) then
        Exit(nil);
    end
    else
      Result := LCandidate;
  end;
end;

function IsMSBuildNode(const ANode: IXMLNode; const ALocalName: string): Boolean;
begin
  Result := False;
  if not Assigned(ANode) then
    Exit;
  if ANode.NodeType <> ntElement then
    Exit;
  Result := (ANode.LocalName = ALocalName) and ((ANode.NamespaceURI = '') or (ANode.NamespaceURI = CMSBuildNamespace));
end;

function ProjectVersionFromText(const AText: string): string;
var
  LDocument: IXMLDocument;
  LGroup, LNode, LRoot: IXMLNode;
  LGroupIndex, LNodeIndex, LVersionCount: Integer;
begin
  Result := '';
  if (Length(AText) > CDAIMaxTextFileBytes div SizeOf(Char)) or AText.ToUpper.Contains('<!DOCTYPE') then
    Exit;
  LDocument := NewXMLDocument;
  LDocument.ParseOptions := [];
  LDocument.Options := [];
  LDocument.LoadFromXML(AText);
  LRoot := LDocument.DocumentElement;
  if not IsMSBuildNode(LRoot, 'Project') then
    Exit;
  LVersionCount := 0;
  for LGroupIndex := 0 to LRoot.ChildNodes.Count - 1 do
  begin
    LGroup := LRoot.ChildNodes[LGroupIndex];
    if not IsMSBuildNode(LGroup, 'PropertyGroup') then
      Continue;
    if LGroup.HasAttribute('Condition') then
      Continue;
    for LNodeIndex := 0 to LGroup.ChildNodes.Count - 1 do
    begin
      LNode := LGroup.ChildNodes[LNodeIndex];
      if not IsMSBuildNode(LNode, 'ProjectVersion') then
        Continue;
      if LNode.HasAttribute('Condition') then
        Continue;
      Inc(LVersionCount);
      if LVersionCount > 1 then
        Exit('');
      Result := Trim(LNode.Text);
      if (Length(Result) > 128) or Result.Contains('$(') or Result.Contains('@(') then
        Exit('');
    end;
  end;
end;

function ReadProjectVersion(const AProjectFile: string): string;
var
  LExtension, LFileName, LText: string;
  LFormat: TDAITextFileFormat;
  LSourceEditor: IOTASourceEditor;
begin
  Result := '';
  LExtension := TPath.GetExtension(AProjectFile);
  if not (SameText(LExtension, '.dpr') or SameText(LExtension, '.dpk') or SameText(LExtension, '.dproj')) then
    Exit;
  LFileName := ChangeFileExt(AProjectFile, '.dproj');
  try
    LSourceEditor := TDAIOTA.FindSourceEditor(LFileName);
    if Assigned(LSourceEditor) then
    begin
      // An unavailable or malformed current buffer must not be replaced by stale disk metadata.
      if not Assigned(LSourceEditor.CreateReader) then
        Exit;
      LText := TDAIOTA.ReadEditorText(LSourceEditor);
    end
    else
    begin
      if not TFile.Exists(LFileName) then
        Exit;
      if TFile.GetSize(LFileName) > CDAIMaxTextFileBytes then
        Exit;
      LText := TDAITextEncoding.ReadFile(LFileName, LFormat);
    end;
    Result := ProjectVersionFromText(LText);
  except
    Result := '';
  end;
end;

function ProjectSummary(const AProject, AActiveProject: IOTAProject; var APackages: TDAIPackageSummarySnapshot): TJSONObject;
var
  LApplicationType, LConfiguration, LDirectory, LFileName, LFrameworkType, LPlatform, LProjectType, LTargetFile, LTargetName: string;
  LBuildConfiguration: IOTABuildConfiguration;
  LIsActive: Boolean;
begin
  LFileName := TDAIOTA.NormalizeFileName(AProject.FileName);
  LDirectory := TDAIOTA.NormalizeFileName(TPath.GetDirectoryName(LFileName));
  LConfiguration := '';
  LPlatform := '';
  LProjectType := '';
  LApplicationType := '';
  LFrameworkType := '';
  LTargetName := '';
  try LConfiguration := AProject.CurrentConfiguration; except end;
  try LPlatform := AProject.CurrentPlatform; except end;
  try LProjectType := AProject.ProjectType; except end;
  try LApplicationType := AProject.ApplicationType; except end;
  try LFrameworkType := AProject.FrameworkType; except end;
  try
    if Assigned(AProject.ProjectOptions) then
      LTargetName := AProject.ProjectOptions.TargetName;
  except
    LTargetName := '';
  end;
  LTargetFile := TargetFile(LTargetName, LDirectory);
  LBuildConfiguration := nil;
  if SameText(LApplicationType, sPackage) then
    try
      LBuildConfiguration := CurrentBuildConfiguration(AProject, LConfiguration, LPlatform);
    except
      LBuildConfiguration := nil;
    end;
  LIsActive := AProject = AActiveProject;
  if not LIsActive and Assigned(AActiveProject) then
    LIsActive := TDAIOTA.SameFile(LFileName, AActiveProject.FileName);
  Result := TJSONObject.Create;
  try
    Result.AddPair('name', TPath.GetFileNameWithoutExtension(LFileName));
    Result.AddPair('file', LFileName);
    Result.AddPair('directory', LDirectory);
    Result.AddPair('configuration', LConfiguration);
    Result.AddPair('platform', LPlatform);
    Result.AddPair('active', TJSONBool.Create(LIsActive));
    AddNullableString(Result, 'project_type', LProjectType);
    AddNullableString(Result, 'application_type', LApplicationType);
    AddNullableString(Result, 'framework_type', LFrameworkType);
    AddNullableString(Result, 'output_type', OutputType(LApplicationType));
    AddNullableString(Result, 'target_name', LTargetName);
    AddNullableString(Result, 'target_file', LTargetFile);
    AddNullableString(Result, 'project_version', ReadProjectVersion(LFileName));
    if SameText(LApplicationType, sPackage) then
    begin
      if not Assigned(APackages) then
        APackages := TDAIPackageSummarySnapshot.Create;
      Result.AddPair('package', APackages.ToJson(LBuildConfiguration, LTargetFile, LDirectory));
    end
    else
      Result.AddPair('package', TJSONNull.Create);
  except
    Result.Free;
    raise;
  end;
end;

class function TDAIProjectSummaryService.Projects: TJSONArray;
var
  LResult: TJSONArray;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LActiveProject, LProject: IOTAProject;
      LPackages: TDAIPackageSummarySnapshot;
      LProjects: TArray<IOTAProject>;
    begin
      LProjects := TDAIOTA.Projects;
      LActiveProject := TDAIOTA.ActiveProject;
      LPackages := nil;
      try
        LResult := TJSONArray.Create;
        try
          for LProject in LProjects do
            if Assigned(LProject) then
              LResult.AddElement(ProjectSummary(LProject, LActiveProject, LPackages));
        except
          FreeAndNil(LResult);
          raise;
        end;
      finally
        LPackages.Free;
      end;
    end);
  Result := LResult;
end;

end.
