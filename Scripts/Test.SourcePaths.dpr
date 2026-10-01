program TestSourcePaths;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.Consts,
  h5u.DAI.Settings;

type
  TTestIDEServices = class(TInterfacedObject, IOTAServices)
  private
    FBaseRegistryKey: string;
    FRootDirectory: string;
  public
    constructor Create(const ARootDirectory, ABaseRegistryKey: string);
    function GetBaseRegistryKey: string;
    function GetRootDirectory: string;
  end;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure CheckPath(const AActual, AExpected, ADescription: string);
begin
  Check(SameText(ExcludeTrailingPathDelimiter(TPath.GetFullPath(AActual)),
    ExcludeTrailingPathDelimiter(TPath.GetFullPath(AExpected))), ADescription + ': expected ' + AExpected + ', actual ' + AActual);
end;

procedure SetEnvironment(const AName, AValue: string);
begin
  if AValue = '' then
  begin
    if not Winapi.Windows.SetEnvironmentVariable(PChar(AName), nil) then
      RaiseLastOSError;
  end
  else if not Winapi.Windows.SetEnvironmentVariable(PChar(AName), PChar(AValue)) then
    RaiseLastOSError;
end;

procedure CheckRegistryAbsent(const ABaseRegistryKey: string);
var
  LRegistry: TRegistry;
begin
  LRegistry := TRegistry.Create(KEY_READ);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    Check(not LRegistry.OpenKeyReadOnly(ABaseRegistryKey), 'isolated registry key remains absent');
  finally
    LRegistry.Free;
  end;
end;

constructor TTestIDEServices.Create(const ARootDirectory, ABaseRegistryKey: string);
begin
  inherited Create;
  FRootDirectory := ARootDirectory;
  FBaseRegistryKey := ABaseRegistryKey;
end;

function TTestIDEServices.GetBaseRegistryKey: string;
begin
  Result := FBaseRegistryKey;
end;

function TTestIDEServices.GetRootDirectory: string;
begin
  Result := FRootDirectory;
end;

procedure TestPaths;
const
  CEnvironmentNames: array[0..4] of string = ('BDS', 'BDSCatalogRepository', 'BDSCatalogRepositoryAllUsers', 'USERPROFILE', 'PUBLIC');
var
  LBaseRegistryKey: string;
  LEnvironment: TDictionary<string, string>;
  LFixtureDirectory: string;
  LGuid: TGUID;
  LInstallationDirectory: string;
  LName: string;
  LProfileDirectory: string;
  LProjectsDirectory: string;
  LPublicDirectory: string;
  LRoots: TArray<string>;
  LSettings: TDAISettings;
  LStudioDirectory: string;
begin
  CreateGUID(LGuid);
  LBaseRegistryKey := 'Software\DAI.SourcePaths.Tests\' + GUIDToString(LGuid) + '\99.7';
  LFixtureDirectory := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'Fixture-' + GUIDToString(LGuid));
  LInstallationDirectory := TPath.Combine(LFixtureDirectory, 'Installed Studio');
  LProfileDirectory := TPath.Combine(LFixtureDirectory, 'Profile');
  LPublicDirectory := TPath.Combine(LFixtureDirectory, 'Public');
  LStudioDirectory := TPath.Combine(LProfileDirectory, 'Documents\Embarcadero\Studio\99.7');
  LProjectsDirectory := TPath.Combine(LStudioDirectory, 'Projects');
  LEnvironment := TDictionary<string, string>.Create;
  LSettings := nil;
  try
    for LName in CEnvironmentNames do
      LEnvironment.Add(LName, GetEnvironmentVariable(LName));
    SetEnvironment('BDS', TPath.Combine(LFixtureDirectory, 'Environment Studio'));
    SetEnvironment('USERPROFILE', LProfileDirectory);
    SetEnvironment('PUBLIC', LPublicDirectory);
    SetEnvironment('BDSCatalogRepository', '');
    SetEnvironment('BDSCatalogRepositoryAllUsers', '');
    CheckRegistryAbsent(LBaseRegistryKey);
    BorlandIDEServices := TTestIDEServices.Create(LInstallationDirectory + '\', LBaseRegistryKey + '\');
    LSettings := TDAISettings.Create;
    Check(LSettings.RegistryRoot = LBaseRegistryKey + '\\' + CDAIRegistrySubKey, 'registry root uses IDE service, without writes');
    CheckPath(LSettings.DelphiSourceDirectory, TPath.Combine(LInstallationDirectory, 'source'), 'IDE root overrides environment');
    CheckPath(LSettings.ToolsAPIDirectory, TPath.Combine(LInstallationDirectory, 'source\ToolsAPI'), 'ToolsAPI reference root');
    Check(LSettings.ExpandPath(' ') = '', 'empty input stays empty');
    Check(LSettings.ExpandPath('C:\') = 'C:\', 'drive root stays absolute instead of drive-relative');
    CheckPath(LSettings.ExpandPath('  %bds%\source\..\source\ToolsAPI\  '), LSettings.ToolsAPIDirectory, 'case, trim and full path');
    CheckPath(LSettings.SamplesDirectory, TPath.Combine(LPublicDirectory, 'Documents\Embarcadero\Studio\99.7\Samples'), 'public samples use IDE version');
    CheckPath(LSettings.ExpandPath('%BDS%\Samples'), LSettings.SamplesDirectory, 'legacy sample alias resolves public samples');
    CheckPath(LSettings.ExpandPath('%bDs%\sAmPlEs\Delphi\VCL'), TPath.Combine(LSettings.SamplesDirectory, 'Delphi\VCL'), 'sample alias keeps suffix');
    CheckPath(LSettings.ExpandPath('%BDS%\SamplesBackup'), TPath.Combine(LInstallationDirectory, 'SamplesBackup'), 'sample alias preserves sibling names');
    CheckPath(LSettings.CatalogRepositoryDirectory, TPath.Combine(LStudioDirectory, 'CatalogRepository'), 'per-user catalog fallback');
    CheckPath(LSettings.CatalogRepositoryAllUsersDirectory,
      TPath.Combine(LPublicDirectory, 'Documents\Embarcadero\Studio\99.7\CatalogRepository'), 'all-users catalog fallback');
    CheckPath(LSettings.ExpandPath('%bDsCaTaLoGrEpOsItOrY%\Packages'),
      TPath.Combine(LSettings.CatalogRepositoryDirectory, 'Packages'), 'user catalog alias fallback');
    CheckPath(LSettings.ExpandPath('%BDSCatalogRepositoryAllUsers%\Packages'),
      TPath.Combine(LSettings.CatalogRepositoryAllUsersDirectory, 'Packages'), 'all-users catalog alias fallback');

    SetEnvironment('BDSCatalogRepository', TPath.Combine(LFixtureDirectory, 'Custom User Catalog'));
    SetEnvironment('BDSCatalogRepositoryAllUsers', '%PUBLIC%\Custom All Users Catalog');
    CheckPath(LSettings.CatalogRepositoryDirectory, TPath.Combine(LFixtureDirectory, 'Custom User Catalog'), 'user catalog environment');
    CheckPath(LSettings.CatalogRepositoryAllUsersDirectory, TPath.Combine(LPublicDirectory, 'Custom All Users Catalog'), 'all-users nested environment');
    CheckPath(LSettings.ExpandPath('%BDSCatalogRepository%\One'),
      TPath.Combine(LFixtureDirectory, 'Custom User Catalog\One'), 'user catalog environment alias suffix');
    CheckPath(LSettings.ExpandPath('%BDSCatalogRepositoryAllUsers%\Two'),
      TPath.Combine(LPublicDirectory, 'Custom All Users Catalog\Two'), 'all-users environment alias suffix');
    SetEnvironment('BDSCatalogRepository', '%BDS%\Catalog');
    CheckPath(LSettings.CatalogRepositoryDirectory, TPath.Combine(LInstallationDirectory, 'Catalog'), 'catalog environment may use BDS alias');

    LSettings.CustomReadDirectories.Add('%BDS%\Samples\Delphi');
    LSettings.CustomReadDirectories.Add(' ');
    LSettings.CustomReadDirectories.Add('%BDSCatalogRepositoryAllUsers%\Packages');
    LRoots := LSettings.ReadOnlyRootDirectories;
    Check(Length(LRoots) = 7, 'five default roots and two non-empty custom roots');
    CheckPath(LRoots[0], LSettings.DelphiSourceDirectory, 'source root retained');
    CheckPath(LRoots[1], LSettings.ToolsAPIDirectory, 'ToolsAPI root retained');
    CheckPath(LRoots[2], LSettings.CatalogRepositoryDirectory, 'user catalog root retained');
    CheckPath(LRoots[3], LSettings.CatalogRepositoryAllUsersDirectory, 'all-users catalog root retained');
    CheckPath(LRoots[4], LSettings.SamplesDirectory, 'samples root retained');
    CheckPath(LRoots[5], TPath.Combine(LSettings.SamplesDirectory, 'Delphi'), 'custom sample alias is expanded');
    CheckPath(LRoots[6], TPath.Combine(LSettings.CatalogRepositoryAllUsersDirectory, 'Packages'), 'custom catalog alias is expanded');
    Check(not TDirectory.Exists(LInstallationDirectory), 'resolving reference aliases creates no installation directory');
    Check(not TDirectory.Exists(LPublicDirectory), 'resolving reference aliases creates no public directory');

    TDirectory.CreateDirectory(LProjectsDirectory);
    CheckPath(LSettings.LocalizedProjectsDirectoryHint, LProjectsDirectory, 'existing English project folder is detected on any UI language');
    TDirectory.Delete(LProjectsDirectory, False);
    Check(not TDirectory.Exists(LProjectsDirectory), 'empty test fixture cleaned without recursive deletion');
    BorlandIDEServices := nil;
    CheckPath(LSettings.DelphiSourceDirectory, TPath.Combine(GetEnvironmentVariable('BDS'), 'source'), 'environment root outside IDE');
    CheckPath(LSettings.SamplesDirectory, TPath.Combine(LPublicDirectory, 'Documents\Embarcadero\Studio\37.0\Samples'), 'default version outside IDE');
    if FindCmdLineSwitch('strict-separators') then
    begin
      CheckPath(LSettings.ExpandPath('%BDS%/Samples'), LSettings.SamplesDirectory, 'forward slash sample alias');
      CheckPath(LSettings.ExpandPath('%bds%/samples/Delphi'), TPath.Combine(LSettings.SamplesDirectory, 'Delphi'), 'forward slash alias suffix');
    end;
    CheckRegistryAbsent(LBaseRegistryKey);
  finally
    LSettings.Free;
    BorlandIDEServices := nil;
    for LName in CEnvironmentNames do
      if LEnvironment.ContainsKey(LName) then
        SetEnvironment(LName, LEnvironment[LName]);
    LEnvironment.Free;
  end;
end;

begin
  try
    TestPaths;
    Writeln('PASS: ', CheckCount, ' source path and alias checks; real Settings, isolated OTA service, no registry writes.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
