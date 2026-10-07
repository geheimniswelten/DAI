program Test.ProjectSummary;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  Winapi.ActiveX,
  Xml.Win.msxmldom,
  ToolsAPI,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.PackageSummary,
  h5u.DAI.OTA.ProjectSummary;

type
  TTestConfiguration = class(TInterfacedObject, IOTABuildConfiguration)
  public
    NameValue, KeyValue, PlatformValue: string;
    PlatformChild: IOTABuildConfiguration;
    function GetName: string;
    function GetKey: string;
    function GetPlatform: string;
    function GetPlatformConfiguration(const APlatform: string): IOTABuildConfiguration;
  end;

  TTestOptions = class(TInterfacedObject, IOTAProjectOptions, IOTAProjectOptionsConfigurations)
  public
    TargetValue: string;
    ActiveValue: IOTABuildConfiguration;
    ConfigurationsValue: TArray<IOTABuildConfiguration>;
    function GetTargetName: string;
    function GetActiveConfiguration: IOTABuildConfiguration;
    function GetConfigurationCount: Integer;
    function GetConfiguration(AIndex: Integer): IOTABuildConfiguration;
  end;

  TTestProject = class(TInterfacedObject, IOTAProject)
  public
    FileValue, ConfigurationValue, PlatformValue, ProjectTypeValue, ApplicationTypeValue, FrameworkValue: string;
    OptionsValue: IOTAProjectOptions;
    FailMetadata: Boolean;
    function GetFileName: string;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetProjectType: string;
    function GetApplicationType: string;
    function GetFrameworkType: string;
    function GetProjectOptions: IOTAProjectOptions;
  end;

var
  CheckCount: Integer;
  FixtureRoot: string;
  ProjectObject: TTestProject;
  ProjectInterface: IOTAProject;
  OptionsObject: TTestOptions;
  OptionsInterface: IOTAProjectOptions;
  ConfigurationObject, PlatformObject, ForeignObject: TTestConfiguration;
  ConfigurationInterface, PlatformInterface, ForeignInterface: IOTABuildConfiguration;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise EInvalidOperation.Create(AMessage);
end;

function Value(const AObject: TJSONObject; const AName: string): string;
var
  LValue: TJSONValue;
begin
  LValue := AObject.GetValue(AName);
  Check(Assigned(LValue), 'Missing field ' + AName);
  Result := LValue.Value;
end;

procedure CheckNull(const AObject: TJSONObject; const AName: string);
begin
  Check(AObject.GetValue(AName) is TJSONNull, 'Expected null ' + AName);
end;

function Summary: TJSONObject;
var
  LArray: TJSONArray;
begin
  LArray := TDAIProjectSummaryService.Projects;
  try
    Check(LArray.Count = 1, 'Expected exactly one real project.');
    Result := TJSONObject(LArray.Items[0].Clone);
  finally
    LArray.Free;
  end;
end;

procedure SetBuffer(const AText: string; const AReadable: Boolean = True; const AFails: Boolean = False);
var
  LBuffer: TTestBuffer;
begin
  LBuffer.Text := AText;
  LBuffer.ReaderAvailable := AReadable;
  LBuffer.ReadFails := AFails;
  TDAIOTA.TestBuffers.AddOrSetValue(ChangeFileExt(ProjectObject.FileValue, '.dproj'), LBuffer);
end;

procedure CheckVersion(const AText, AExpected: string);
var
  LJson: TJSONObject;
begin
  SetBuffer(AText);
  LJson := Summary;
  try
    if AExpected = '' then
      CheckNull(LJson, 'project_version')
    else
      Check(Value(LJson, 'project_version') = AExpected, 'Unexpected project format version.');
  finally
    LJson.Free;
  end;
end;

function TTestConfiguration.GetName: string;
begin
  Result := NameValue;
end;

function TTestConfiguration.GetKey: string;
begin
  Result := KeyValue;
end;

function TTestConfiguration.GetPlatform: string;
begin
  Result := PlatformValue;
end;

function TTestConfiguration.GetPlatformConfiguration(const APlatform: string): IOTABuildConfiguration;
begin
  Result := nil;
  if Assigned(PlatformChild) then
    if SameText(PlatformChild.Platform, APlatform) then
      Result := PlatformChild;
end;

function TTestOptions.GetTargetName: string;
begin
  Result := TargetValue;
end;

function TTestOptions.GetActiveConfiguration: IOTABuildConfiguration;
begin
  Result := ActiveValue;
end;

function TTestOptions.GetConfigurationCount: Integer;
begin
  Result := Length(ConfigurationsValue);
end;

function TTestOptions.GetConfiguration(AIndex: Integer): IOTABuildConfiguration;
begin
  Result := ConfigurationsValue[AIndex];
end;

function TTestProject.GetFileName: string;
begin
  Result := FileValue;
end;

function TTestProject.GetConfiguration: string;
begin
  Result := ConfigurationValue;
end;

function TTestProject.GetPlatform: string;
begin
  Result := PlatformValue;
end;

function TTestProject.GetProjectType: string;
begin
  if FailMetadata then
    raise EInvalidOperation.Create('Metadata unavailable.');
  Result := ProjectTypeValue;
end;

function TTestProject.GetApplicationType: string;
begin
  if FailMetadata then
    raise EInvalidOperation.Create('Metadata unavailable.');
  Result := ApplicationTypeValue;
end;

function TTestProject.GetFrameworkType: string;
begin
  if FailMetadata then
    raise EInvalidOperation.Create('Metadata unavailable.');
  Result := FrameworkValue;
end;

function TTestProject.GetProjectOptions: IOTAProjectOptions;
begin
  Result := OptionsValue;
end;

procedure RunTests;
var
  LArray: TJSONArray;
  LJson, LPackage: TJSONObject;
  LSnapshotCount, LProjectsCount, LActiveCount: Integer;
  LXML: string;
begin
  ProjectObject := TTestProject.Create;
  ProjectInterface := ProjectObject;
  OptionsObject := TTestOptions.Create;
  OptionsInterface := OptionsObject;
  ProjectObject.OptionsValue := OptionsInterface;
  ProjectObject.FileValue := TPath.Combine(FixtureRoot, 'App.dpr');
  ProjectObject.ConfigurationValue := 'Debug';
  ProjectObject.PlatformValue := 'Win64';
  ProjectObject.ProjectTypeValue := 'DelphiConsoleApplication';
  ProjectObject.ApplicationTypeValue := 'Console';
  ProjectObject.FrameworkValue := 'None';
  OptionsObject.TargetValue := 'out\App.exe';
  TDAIOTA.TestProjects := [nil, ProjectInterface];
  TDAIOTA.TestActiveProject := ProjectInterface;
  LSnapshotCount := TDAIPackageSummarySnapshot.CreateCount;
  LProjectsCount := TDAIOTA.ProjectsCount;
  LActiveCount := TDAIOTA.ActiveProjectCount;
  LJson := Summary;
  try
    Check(Value(LJson, 'name') = 'App', 'Preserve project name.');
    Check(Value(LJson, 'file') = ProjectObject.FileValue, 'Preserve full project path.');
    Check(Value(LJson, 'directory') = FixtureRoot, 'Preserve project directory.');
    Check(Value(LJson, 'configuration') = 'Debug', 'Current config.');
    Check(Value(LJson, 'platform') = 'Win64', 'Current platform.');
    Check(Value(LJson, 'active') = 'true', 'Active flag.');
    Check(Value(LJson, 'application_type') = 'Console', 'Console is separate from None framework.');
    Check(Value(LJson, 'framework_type') = 'None', 'Raw framework.');
    Check(Value(LJson, 'project_type') = 'DelphiConsoleApplication', 'Raw project type.');
    Check(Value(LJson, 'output_type') = 'EXE', 'Console EXE class.');
    Check(Value(LJson, 'target_name') = OptionsObject.TargetValue, 'Raw SDK target preserved.');
    Check(Value(LJson, 'target_file') = TPath.Combine(FixtureRoot, 'out\App.exe'), 'Relative target uses project directory.');
    CheckNull(LJson, 'project_version');
    CheckNull(LJson, 'package');
  finally
    LJson.Free;
  end;
  Check(TDAIPackageSummarySnapshot.CreateCount = LSnapshotCount, 'No package snapshot for EXE-only list.');
  Check(TDAIOTA.ProjectsCount = LProjectsCount + 1, 'Read projects once.');
  Check(TDAIOTA.ActiveProjectCount = LActiveCount + 1, 'Read active project once.');

  TDAIOTA.TestProjects := [];
  LArray := TDAIProjectSummaryService.Projects;
  try
    Check(LArray.Count = 0, 'Empty workspace.');
    Check(TDAIPackageSummarySnapshot.CreateCount = LSnapshotCount, 'No package snapshot for empty workspace.');
  finally
    LArray.Free;
  end;
  TDAIOTA.TestProjects := [ProjectInterface];
  TDAIOTA.TestActiveProject := nil;
  ProjectObject.ApplicationTypeValue := 'Library';
  LJson := Summary;
  try
    Check(Value(LJson, 'output_type') = 'DLL', 'Library class.');
    Check(Value(LJson, 'active') = 'false', 'No active project.');
  finally
    LJson.Free;
  end;
  ProjectObject.ApplicationTypeValue := 'StaticLibrary';
  LJson := Summary;
  try CheckNull(LJson, 'output_type'); finally LJson.Free; end;
  ProjectObject.ApplicationTypeValue := 'Application';
  ProjectObject.FrameworkValue := 'FMX';
  LJson := Summary;
  try
    Check(Value(LJson, 'output_type') = 'EXE', 'Application class.');
    Check(Value(LJson, 'framework_type') = 'FMX', 'FMX metadata.');
  finally LJson.Free; end;
  ProjectObject.FailMetadata := True;
  LJson := Summary;
  try
    CheckNull(LJson, 'application_type');
    CheckNull(LJson, 'framework_type');
    CheckNull(LJson, 'output_type');
  finally LJson.Free; end;
  ProjectObject.FailMetadata := False;
  for LXML in ['$(Config)\App.exe', 'C:out.exe', '\out.exe', '%BDS%\out.exe', '@(Targets)'] do
  begin
    OptionsObject.TargetValue := LXML;
    LJson := Summary;
    try CheckNull(LJson, 'target_file'); finally LJson.Free; end;
  end;
  OptionsObject.TargetValue := TPath.Combine(FixtureRoot, 'Complete370.bpl');
  LJson := Summary;
  try
    Check(Value(LJson, 'target_file') = OptionsObject.TargetValue, 'Absolute SDK filename and suffix preserved.');
  finally LJson.Free; end;

  CheckVersion('<Project><PropertyGroup><ProjectVersion>20.5</ProjectVersion></PropertyGroup></Project>', '20.5');
  CheckVersion('<p:Project xmlns:p="http://schemas.microsoft.com/developer/msbuild/2003"><p:PropertyGroup>' +
    '<p:ProjectVersion> 20.4 </p:ProjectVersion></p:PropertyGroup></p:Project>', '20.4');
  CheckVersion('<Project><!-- <ProjectVersion>99</ProjectVersion> --><Target><ProjectVersion>99</ProjectVersion></Target>' +
    '<PropertyGroup><ProjectVersion>20.3</ProjectVersion></PropertyGroup><Import Project="never-loaded.props"/></Project>', '20.3');
  CheckVersion('<Project><PropertyGroup Condition="false"><ProjectVersion>99</ProjectVersion></PropertyGroup>' +
    '<PropertyGroup><ProjectVersion>20.2</ProjectVersion></PropertyGroup></Project>', '20.2');
  CheckVersion('<Project><PropertyGroup><ProjectVersion Condition="false">99</ProjectVersion></PropertyGroup></Project>', '');
  CheckVersion('<Project><PropertyGroup><ProjectVersion>20.5</ProjectVersion><ProjectVersion>20.4</ProjectVersion></PropertyGroup></Project>', '');
  CheckVersion('<Project xmlns="urn:foreign"><PropertyGroup><ProjectVersion>99</ProjectVersion></PropertyGroup></Project>', '');
  CheckVersion('<Project><PropertyGroup><ProjectVersion>$(Custom)</ProjectVersion></PropertyGroup></Project>', '');
  CheckVersion('<!DOCTYPE Project [<!ENTITY version SYSTEM "file:///never-read.txt">]><Project><PropertyGroup>' +
    '<ProjectVersion>&version;</ProjectVersion></PropertyGroup></Project>', '');
  CheckVersion('<Project><PropertyGroup>', '');
  CheckVersion(StringOfChar('x', CDAIMaxTextFileBytes div SizeOf(Char) + 1), '');
  TDAIOTA.TestBuffers.Clear;
  LXML := '<Project><PropertyGroup><ProjectVersion>20.1</ProjectVersion></PropertyGroup></Project>';
  TFile.WriteAllText(ChangeFileExt(ProjectObject.FileValue, '.dproj'), LXML, TEncoding.Unicode);
  LJson := Summary;
  try Check(Value(LJson, 'project_version') = '20.1', 'UTF16 disk format version.'); finally LJson.Free; end;
  CheckVersion('<Project><PropertyGroup><ProjectVersion>20.6</ProjectVersion></PropertyGroup></Project>', '20.6');
  SetBuffer('<Project/>', False);
  LJson := Summary;
  try CheckNull(LJson, 'project_version'); finally LJson.Free; end;
  SetBuffer('<Project/>', True, True);
  LJson := Summary;
  try CheckNull(LJson, 'project_version'); finally LJson.Free; end;
  Check(TDAIOTA.BufferReadCount > 0, 'Current buffer read.');
  TDAIOTA.TestBuffers.Clear;

  ConfigurationObject := TTestConfiguration.Create;
  ConfigurationInterface := ConfigurationObject;
  ConfigurationObject.NameValue := 'Debug';
  ConfigurationObject.KeyValue := 'Cfg_1';
  PlatformObject := TTestConfiguration.Create;
  PlatformInterface := PlatformObject;
  PlatformObject.NameValue := 'Debug';
  PlatformObject.KeyValue := 'Cfg_1_Win64';
  PlatformObject.PlatformValue := 'Win64';
  ConfigurationObject.PlatformChild := PlatformInterface;
  ForeignObject := TTestConfiguration.Create;
  ForeignInterface := ForeignObject;
  ForeignObject.NameValue := 'Debug';
  ForeignObject.KeyValue := 'Cfg_1_Win32';
  ForeignObject.PlatformValue := 'Win32';
  OptionsObject.ActiveValue := ForeignInterface;
  OptionsObject.ConfigurationsValue := [nil, ConfigurationInterface];
  ProjectObject.ApplicationTypeValue := 'Package';
  LSnapshotCount := TDAIPackageSummarySnapshot.CreateCount;
  TDAIOTA.TestProjects := [ProjectInterface, ProjectInterface];
  LArray := TDAIProjectSummaryService.Projects;
  try
    Check(LArray.Count = 2, 'Multiple package entries.');
    LJson := TJSONObject(LArray.Items[0]);
    Check(Value(LJson, 'output_type') = 'Package', 'Package class.');
    LPackage := LJson.GetValue<TJSONObject>('package');
    Check(Value(LPackage, 'configuration_key') = 'Cfg_1_Win64', 'Choose own selected platform instead of foreign active node.');
    Check(Value(LPackage, 'configuration_platform') = 'Win64', 'Correct package platform.');
    Check(Value(LPackage, 'target_file') = OptionsObject.TargetValue, 'Package actual target forwarded.');
    Check(TDAIPackageSummarySnapshot.CreateCount = LSnapshotCount + 1, 'One shared package snapshot.');
    Check(TDAIPackageSummarySnapshot.FreeCount = TDAIPackageSummarySnapshot.CreateCount, 'Snapshot ownership released.');
  finally LArray.Free; end;
  TDAIOTA.TestProjects := [ProjectInterface];
  OptionsObject.ActiveValue := ConfigurationInterface;
  ConfigurationObject.PlatformChild := nil;
  LJson := Summary;
  try
    LPackage := LJson.GetValue<TJSONObject>('package');
    CheckNull(LPackage, 'configuration_key');
  finally LJson.Free; end;
  OptionsObject.ActiveValue := nil;
  OptionsObject.ConfigurationsValue := [nil];
  LJson := Summary;
  try
    LPackage := LJson.GetValue<TJSONObject>('package');
    CheckNull(LPackage, 'configuration_key');
  finally LJson.Free; end;
  Check(TDAIOTA.DispatchDepth = 0, 'Dispatch returned normally.');
end;

begin
  try
    CoInitialize(nil);
    try
      FixtureRoot := TPath.Combine(TPath.GetTempPath, 'DAI-ProjectSummary-Fixture-' + TGUID.NewGuid.ToString);
      ForceDirectories(FixtureRoot);
      try
        RunTests;
      finally
        if not SameText(TPath.GetDirectoryName(TPath.GetFullPath(FixtureRoot)),
          ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.GetTempPath))) or
          not TPath.GetFileName(FixtureRoot).StartsWith('DAI-ProjectSummary-Fixture-{') then
          raise EInvalidOperation.Create('Fixture cleanup path is outside the temporary directory.');
        TDirectory.Delete(FixtureRoot, True);
      end;
    finally
      CoUninitialize;
    end;
    Writeln('Project summary tests passed: ', CheckCount, ' checks.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
