program Test.Packages;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.PackageSummary,
  h5u.DAI.OTA.Packages;

type
  TTestOptions = class(TInterfacedObject, IOTAProjectOptions)
  public
    TargetName: string;
    function GetTargetName: string;
  end;

  TTestProject = class(TInterfacedObject, IOTAProject)
  public
    FileName, ApplicationType, Configuration, Platform: string;
    Options: IOTAProjectOptions;
    function GetFileName: string;
    function GetApplicationType: string;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetOptions: IOTAProjectOptions;
  end;

  TTestPackageInfo = class(TInterfacedObject, IOTAPackageInfo)
  public
    FileName: string;
    IDEPackage: Boolean;
    RequiredBy: string;
    function GetFileName: string;
    function GetIDEPackage: Boolean;
    procedure GetRequiredByList(List: TStrings);
  end;

  TTestServices = class(TInterfacedObject, IOTAPackageServices210)
  public
    Infos: TArray<IOTAPackageInfo>;
    InstallCount, UninstallCount: Integer;
    LastFile: string;
    Succeeded, RaiseMutation: Boolean;
    function GetPackageCount: Integer;
    function GetPackage(Index: Integer): IOTAPackageInfo;
    function InstallPackage(const PackageName: string): Boolean;
    function UninstallPackage(const PackageName: string): Boolean;
  end;

var
  GChecks: Integer;
  GServices: TTestServices;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure RequireMainThread;
begin
  if TDAIOTA.DispatchDepth = 0 then
    raise EInvalidOperation.Create('IDE APIs must run on the main thread.');
end;

procedure ExpectError(const AAction: TProc; const AMessagePart: string);
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    AAction();
  except
    on E: Exception do
    begin
      LRaised := True;
      Check(E.Message.Contains(AMessagePart), 'Expected error ' + AMessagePart + ', got ' + E.Message);
    end;
  end;
  Check(LRaised, 'Expected rejection: ' + AMessagePart);
end;

procedure Field(const AJson: TJSONObject; const AName, AValue: string);
var
  LValue: TJSONValue;
begin
  LValue := AJson.GetValue(AName);
  Check(Assigned(LValue), 'Present field ' + AName);
  if AValue = 'null' then
    Check(LValue is TJSONNull, 'Unknown field ' + AName)
  else
    Check(LValue.Value = AValue, 'Value of ' + AName + ': ' + LValue.ToJSON);
end;

function TTestOptions.GetTargetName: string;
begin RequireMainThread; Result := TargetName; end;
function TTestProject.GetFileName: string;
begin RequireMainThread; Result := FileName; end;
function TTestProject.GetApplicationType: string;
begin RequireMainThread; Result := ApplicationType; end;
function TTestProject.GetConfiguration: string;
begin RequireMainThread; Result := Configuration; end;
function TTestProject.GetPlatform: string;
begin RequireMainThread; Result := Platform; end;
function TTestProject.GetOptions: IOTAProjectOptions;
begin RequireMainThread; Result := Options; end;
function TTestPackageInfo.GetFileName: string;
begin RequireMainThread; Result := FileName; end;
function TTestPackageInfo.GetIDEPackage: Boolean;
begin RequireMainThread; Result := IDEPackage; end;
procedure TTestPackageInfo.GetRequiredByList(List: TStrings);
begin RequireMainThread; if RequiredBy <> '' then List.Add(RequiredBy); end;
function TTestServices.GetPackageCount: Integer;
begin RequireMainThread; Result := Length(Infos); end;
function TTestServices.GetPackage(Index: Integer): IOTAPackageInfo;
begin RequireMainThread; Result := Infos[Index]; end;

function TTestServices.InstallPackage(const PackageName: string): Boolean;
begin
  RequireMainThread;
  Inc(InstallCount);
  LastFile := PackageName;
  if RaiseMutation then
    raise EInvalidOperation.Create('Synthetic SDK mutation failure');
  Result := Succeeded;
  if Result then
  begin
    TDAIPackageSummarySnapshot.RegisteredState := 'true';
    TDAIPackageSummarySnapshot.EnabledState := 'true';
    TDAIPackageSummarySnapshot.LoadedState := 'false';
  end;
end;

function TTestServices.UninstallPackage(const PackageName: string): Boolean;
begin
  RequireMainThread;
  Inc(UninstallCount);
  LastFile := PackageName;
  if RaiseMutation then
    raise EInvalidOperation.Create('Synthetic SDK mutation failure');
  Result := Succeeded;
  if Result then
  begin
    TDAIPackageSummarySnapshot.RegisteredState := 'false';
    TDAIPackageSummarySnapshot.EnabledState := 'false';
    TDAIPackageSummarySnapshot.LoadedState := 'false';
  end;
end;

procedure InstallFile(const AFileName: string);
var
  LJson: TJSONObject;
begin
  LJson := TDAIPackageService.Install(TDAIPackageService.Prepare('', AFileName));
  LJson.Free;
end;

procedure ReplaceHeaderWord(const AFileName: string; const AHeaderOffset: Integer; const AValue: Word);
var
  LFile: TFileStream;
  LDos: TImageDosHeader;
begin
  LFile := TFileStream.Create(AFileName, fmOpenReadWrite);
  try
    LFile.ReadBuffer(LDos, SizeOf(LDos));
    LFile.Position := LDos._lfanew + SizeOf(DWORD) + AHeaderOffset;
    LFile.WriteBuffer(AValue, SizeOf(AValue));
  finally
    LFile.Free;
  end;
end;

procedure ReplacePackageResource(const AFileName: string; const AFlags: DWORD; const ASize: DWORD);
var
  LUpdate: THandle;
  LHeader: array[0..1] of DWORD;
begin
  LHeader[0] := AFlags;
  LHeader[1] := 0;
  LUpdate := BeginUpdateResourceW(PWideChar(AFileName), False);
  Check(LUpdate <> 0, 'Fixture resource update opened');
  Check(UpdateResourceW(LUpdate, RT_RCDATA, 'PACKAGEINFO', 0, @LHeader[0], ASize), 'Fixture resource updated');
  Check(EndUpdateResourceW(LUpdate, False), 'Fixture resource update closed');
end;

procedure RunTests;
var
  LRoot, LFile, LRuntime, LPlain, LBroken, LSelfAlias, LAlias: string;
  LProject: TTestProject;
  LOptions: TTestOptions;
  LProjectInterface: IOTAProject;
  LInfo: TTestPackageInfo;
  LTarget: TDAIPackageTarget;
  LJson: TJSONObject;
  LFileStream: TFileStream;
  LBefore: Integer;
  LServicesInterface: IOTAPackageServices210;
begin
  LRoot := TPath.GetDirectoryName(ParamStr(0));
  LFile := TPath.Combine(LRoot, 'PackageFixture.bpl');
  LRuntime := TPath.Combine(LRoot, 'RuntimeFixture.bpl');
  LPlain := TPath.Combine(LRoot, 'PlainFixture.bpl');
  LBroken := TPath.Combine(LRoot, 'BrokenFixture.bpl');
  LSelfAlias := TPath.Combine(LRoot, 'SelfAlias.bpl');
  LAlias := TPath.Combine(LRoot, 'PackageAlias.bpl');
  TFile.Copy(TPath.Combine(LRoot, 'PlainFixture.dll'), LPlain, True);
  GServices := TTestServices.Create;
  GServices.Succeeded := True;
  LServicesInterface := GServices;
  BorlandIDEServices := GServices;
  LOptions := TTestOptions.Create;
  LOptions.TargetName := 'PackageFixture.bpl';
  LProject := TTestProject.Create;
  LProject.FileName := TPath.Combine(LRoot, 'PackageFixture.dproj');
  LProject.ApplicationType := 'Package';
  LProject.Configuration := 'Debug';
  {$IFDEF WIN64}
  LProject.Platform := 'Win64';
  {$ELSE}
  LProject.Platform := 'Win32';
  {$ENDIF}
  LProject.Options := LOptions;
  LProjectInterface := LProject;
  TDAIOTA.TestProjects := [LProjectInterface];
  TDAIOTA.TestActiveProject := LProjectInterface;
  try
    LTarget := TDAIPackageService.Prepare('', '');
    Check(LTarget.FileName = LFile, 'Current project target uses SDK suffix and project-relative output');
    Check(LTarget.ProjectFile = LProject.FileName, 'Current project identity retained');
    Check(LTarget.Configuration = 'Debug', 'Current configuration retained');
    Check(LTarget.Platform = LProject.Platform, 'Current platform retained');
    Check(TDAIPackageService.Prepare('PackageFixture', '').FileName = LFile, 'Named project resolved without activation');
    ExpectError(procedure begin TDAIPackageService.Prepare('PackageFixture', LFile); end, 'gleichzeitig');
    ExpectError(procedure begin TDAIPackageService.Prepare('', 'PackageFixture.bpl'); end, 'qualifizierten');
    ExpectError(procedure begin TDAIPackageService.Prepare('', 'C:PackageFixture.bpl'); end, 'qualifizierten');
    ExpectError(procedure begin TDAIPackageService.Prepare('', '\PackageFixture.bpl'); end, 'qualifizierten');
    ExpectError(procedure begin TDAIPackageService.Prepare('', LFile + #0); end, 'NUL-Zeichen');
    ExpectError(procedure begin TDAIPackageService.Prepare('', 'C:\$(Platform)\PackageFixture.bpl'); end, 'Makros');
    ExpectError(procedure begin TDAIPackageService.Prepare('', TPath.ChangeExtension(LFile, '.dll')); end, '.bpl');
    LProject.ApplicationType := 'Application';
    ExpectError(procedure begin TDAIPackageService.Prepare('', ''); end, 'kein Package');
    LProject.ApplicationType := 'Package';
    ExpectError(procedure begin TDAIPackageService.Prepare('missing', ''); end, 'nicht geöffnet');

    LJson := TDAIPackageService.Status(LTarget);
    try
      Field(LJson, 'project', LProject.FileName);
      Field(LJson, 'installed', 'null');
      Field(LJson, 'registered', 'null');
      Field(LJson, 'loaded', 'null');
    finally LJson.Free; end;
    LJson := TDAIPackageService.Status(TDAIPackageService.Prepare('', LFile));
    try
      Field(LJson, 'project', 'null');
      Field(LJson, 'configuration', 'null');
      Field(LJson, 'platform', 'null');
    finally LJson.Free; end;

    LBefore := GServices.InstallCount + GServices.UninstallCount;
    LProject.Configuration := 'Release';
    ExpectError(procedure begin TDAIPackageService.Install(LTarget).Free; end, 'geändert');
    LProject.Configuration := 'Debug';
    LProject.Platform := 'Android';
    ExpectError(procedure begin TDAIPackageService.Uninstall(LTarget).Free; end, 'geändert');
    LProject.Platform := LTarget.Platform;
    LOptions.TargetName := 'OtherFixture.bpl';
    ExpectError(procedure begin TDAIPackageService.Install(LTarget).Free; end, 'geändert');
    LOptions.TargetName := 'PackageFixture.bpl';
    TDAIOTA.TestProjects := [];
    ExpectError(procedure begin TDAIPackageService.Uninstall(LTarget).Free; end, 'nicht geöffnet');
    TDAIOTA.TestProjects := [LProjectInterface];
    Check(GServices.InstallCount + GServices.UninstallCount = LBefore, 'Stale target guards perform no SDK mutation');

    LJson := TDAIPackageService.Install(LTarget);
    try
      Field(LJson, 'operation', 'install');
      Field(LJson, 'succeeded', 'true');
      Field(LJson, 'installed', 'true');
      Field(LJson, 'loaded', 'false');
      Check(GServices.LastFile = LFile, 'SDK install receives exact full target');
    finally LJson.Free; end;
    Check(GetModuleHandleW('PackageFixture.bpl') = 0, 'Preflight never initializes or loads the fixture as executable code');
    GServices.Succeeded := False;
    LJson := TDAIPackageService.Install(LTarget);
    try
      Field(LJson, 'succeeded', 'false');
      Field(LJson, 'installed', 'true');
    finally LJson.Free; end;
    LJson := TDAIPackageService.Uninstall(LTarget);
    try
      Field(LJson, 'succeeded', 'false');
      Field(LJson, 'installed', 'true');
    finally LJson.Free; end;
    GServices.Succeeded := True;
    LJson := TDAIPackageService.Uninstall(LTarget);
    try
      Field(LJson, 'operation', 'uninstall');
      Field(LJson, 'succeeded', 'true');
      Field(LJson, 'installed', 'false');
      Check(GServices.LastFile = LFile, 'SDK uninstall receives exact full target');
    finally LJson.Free; end;
    GServices.RaiseMutation := True;
    ExpectError(procedure begin TDAIPackageService.Install(LTarget).Free; end, 'Synthetic SDK');
    ExpectError(procedure begin TDAIPackageService.Uninstall(LTarget).Free; end, 'Synthetic SDK');
    GServices.RaiseMutation := False;
    LFileStream := TFileStream.Create(LFile, fmOpenReadWrite or fmShareDenyWrite);
    LFileStream.Free;
    Check(True, 'Validation file handles released after SDK exceptions');

    LBefore := GServices.InstallCount;
    ExpectError(procedure begin InstallFile(LRuntime); end, 'Runtime-only');
    ExpectError(procedure begin InstallFile(LPlain); end, 'kein Delphi-Package');
    TFile.Copy(LFile, LBroken, True);
    {$IFDEF WIN64}
    ReplaceHeaderWord(LBroken, 0, IMAGE_FILE_MACHINE_I386);
    {$ELSE}
    ReplaceHeaderWord(LBroken, 0, IMAGE_FILE_MACHINE_AMD64);
    {$ENDIF}
    ExpectError(procedure begin InstallFile(LBroken); end, 'Package benötigt');
    TFile.Copy(LFile, LBroken, True);
    ReplaceHeaderWord(LBroken, 18, IMAGE_FILE_EXECUTABLE_IMAGE);
    ExpectError(procedure begin InstallFile(LBroken); end, 'keine DLL');
    TFile.Copy(LPlain, LBroken, True);
    ReplacePackageResource(LBroken, $40000000, 4);
    ExpectError(procedure begin InstallFile(LBroken); end, 'unvollständig');
    ReplacePackageResource(LBroken, $80000000, 8);
    ExpectError(procedure begin InstallFile(LBroken); end, 'kein Delphi-Package');
    ReplacePackageResource(LBroken, $40000006, 8);
    ExpectError(procedure begin InstallFile(LBroken); end, 'widersprüchliche');
    TFile.WriteAllText(LBroken, 'not PE');
    ExpectError(procedure begin InstallFile(LBroken); end, 'PE-Dateikopf');
    ExpectError(procedure begin InstallFile(TPath.Combine(LRoot, 'MissingFixture.bpl')); end, 'existiert nicht');
    Check(GServices.InstallCount = LBefore, 'Invalid package fixtures never reach SDK InstallPackage');

    Check(CreateHardLinkW(PWideChar(LSelfAlias), PWideChar(ParamStr(0)), nil), 'Self hardlink fixture created');
    ExpectError(procedure begin InstallFile(LSelfAlias); end, 'selbst');
    ExpectError(procedure begin TDAIPackageService.Uninstall(TDAIPackageService.Prepare('', LSelfAlias)).Free; end, 'selbst');
    Check(CreateHardLinkW(PWideChar(LAlias), PWideChar(LFile), nil), 'Package alias fixture created');
    LInfo := TTestPackageInfo.Create;
    LInfo.FileName := LAlias;
    LInfo.IDEPackage := True;
    GServices.Infos := [LInfo];
    ExpectError(procedure begin TDAIPackageService.Install(LTarget).Free; end, 'geschütztes IDE');
    ExpectError(procedure begin TDAIPackageService.Uninstall(LTarget).Free; end, 'geschütztes IDE');
    LInfo.IDEPackage := False;
    LInfo.RequiredBy := 'DAI370.bpl';
    ExpectError(procedure begin TDAIPackageService.Uninstall(LTarget).Free; end, 'DAI370.bpl');
    GServices.Infos := [];
    BorlandIDEServices := nil;
    ExpectError(procedure begin TDAIPackageService.Uninstall(LTarget).Free; end, 'keine Dienste');
    BorlandIDEServices := GServices;
    LTarget := TDAIPackageService.Prepare('', TPath.Combine(LRoot, 'MissingFixture.bpl'));
    LJson := TDAIPackageService.Uninstall(LTarget);
    try
      Field(LJson, 'succeeded', 'true');
      Field(LJson, 'installed', 'false');
      Check(GServices.LastFile = LTarget.FileName, 'Missing stale registration can be removed with exact path');
    finally LJson.Free; end;
    Check(TDAIOTA.TestActiveProject = LProjectInterface, 'No project activation');
    Check(TDAIOTA.DispatchDepth = 0, 'All main-thread scopes balanced');
  finally
    TDAIOTA.TestActiveProject := nil;
    TDAIOTA.TestProjects := [];
    BorlandIDEServices := nil;
    if TFile.Exists(LSelfAlias) then TFile.Delete(LSelfAlias);
    if TFile.Exists(LAlias) then TFile.Delete(LAlias);
    if TFile.Exists(LBroken) then TFile.Delete(LBroken);
    if TFile.Exists(LPlain) then TFile.Delete(LPlain);
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS: ', GChecks, ' package action checks');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
