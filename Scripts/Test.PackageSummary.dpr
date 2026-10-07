program Test.PackageSummary;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.PackageSummary;

type
  TTestConfiguration = class(TInterfacedObject, IOTABuildConfiguration)
  public
    Description, RuntimeOnly, DesignOnly, NeverBuild: string;
    FailingOption: string;
    InheritedReads: Integer;
    function GetValue(const PropName: string; IncludeInheritedValues: Boolean): string;
  end;

  TTestPackage = class(TInterfacedObject, IOTAPackageInfo)
  public
    FileName: string;
    Loaded: Boolean;
    FailLoaded: Boolean;
    function GetFileName: string;
    function GetLoaded: Boolean;
  end;

  TTestServices = class(TInterfacedObject, IOTAServices, IOTAPackageServices)
  public
    RegistryKey, MacroDirectory: string;
    Packages: TArray<IOTAPackageInfo>;
    CountReads: Integer;
    FailCount: Boolean;
    function GetBaseRegistryKey: string;
    function ExpandRootMacro(const S: string): string;
    function GetPackageCount: Integer;
    function GetPackage(Index: Integer): IOTAPackageInfo;
  end;

var
  GChecks: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure CheckField(const AJson: TJSONObject; const AName, AValue: string);
var
  LValue: TJSONValue;
begin
  LValue := AJson.GetValue(AName);
  Check(Assigned(LValue), 'field present: ' + AName);
  if AValue = 'null' then
    Check(LValue is TJSONNull, AName + ' remains unknown, got ' + LValue.ToJSON + ' (check ' + IntToStr(GChecks) + ')' )
  else
    Check(LValue.Value = AValue, AName + ': expected ' + AValue + ', got ' + LValue.Value);
end;

function CompleteData: TDAIPackageSnapshotData;
begin
  Result := Default(TDAIPackageSnapshotData);
  Result.KnownComplete := True;
  Result.DisabledComplete := True;
  Result.LoadedComplete := True;
end;

function LoadedEntry(const AFileName: string; const AState: TDAIPackageTruth): TDAILoadedPackageSummary;
begin
  Result.FileName := AFileName;
  Result.Loaded := AState;
end;

procedure CheckStates(const AData: TDAIPackageSnapshotData; const ATarget, ADirectory, ARegistered, AEnabled, ALoaded: string);
var
  LSnapshot: TDAIPackageSummarySnapshot;
  LJson: TJSONObject;
begin
  LSnapshot := TDAIPackageSummarySnapshot.Create(AData);
  try
    LJson := LSnapshot.ToJson(nil, ATarget, ADirectory);
    try
      CheckField(LJson, 'registered', ARegistered);
      CheckField(LJson, 'enabled', AEnabled);
      CheckField(LJson, 'loaded', ALoaded);
      CheckField(LJson, 'description', 'null');
      CheckField(LJson, 'usage', 'null');
      CheckField(LJson, 'build_mode', 'null');
    finally
      LJson.Free;
    end;
  finally
    LSnapshot.Free;
  end;
end;

function TTestConfiguration.GetValue(const PropName: string; IncludeInheritedValues: Boolean): string;
begin
  if IncludeInheritedValues then
    Inc(InheritedReads);
  if PropName = FailingOption then
    raise Exception.Create('unavailable option');
  if PropName = 'DCC_Description' then
    Result := Description
  else if PropName = 'RuntimeOnlyPackage' then
    Result := RuntimeOnly
  else if PropName = 'DesignOnlyPackage' then
    Result := DesignOnly
  else if PropName = 'DCC_OutputNeverBuildDcps' then
    Result := NeverBuild
  else
    Result := '';
end;

function TTestPackage.GetFileName: string;
begin
  Result := FileName;
end;

function TTestPackage.GetLoaded: Boolean;
begin
  if FailLoaded then
    raise Exception.Create('unavailable loaded state');
  Result := Loaded;
end;

function TTestServices.GetBaseRegistryKey: string;
begin
  Result := RegistryKey;
end;

function TTestServices.ExpandRootMacro(const S: string): string;
begin
  Result := StringReplace(S, '$(BDSBIN)', MacroDirectory, [rfReplaceAll, rfIgnoreCase]);
end;

function TTestServices.GetPackageCount: Integer;
begin
  Inc(CountReads);
  if FailCount then
    raise Exception.Create('unavailable package service');
  Result := Length(Packages);
end;

function TTestServices.GetPackage(Index: Integer): IOTAPackageInfo;
begin
  Result := Packages[Index];
end;

procedure CheckAbsentRegistry(const AKey: string);
var
  LRegistry: TRegistry;
begin
  LRegistry := TRegistry.Create(KEY_READ);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    Check(not LRegistry.OpenKeyReadOnly(AKey), 'isolated registry root remains absent');
    Check(LRegistry.LastError = ERROR_FILE_NOT_FOUND, 'registry was not modified');
  finally
    LRegistry.Free;
  end;
end;

procedure RunTests;
var
  LData: TDAIPackageSnapshotData;
  LDirectory, LTarget, LAlias, LOther: string;
  LGuid: TGUID;
  LConfiguration: TTestConfiguration;
  LConfigurationIntf: IOTABuildConfiguration;
  LSnapshot: TDAIPackageSummarySnapshot;
  LJson: TJSONObject;
  LServices: TTestServices;
  LPackage: TTestPackage;
  LLock: THandle;
  LPreviousEnvironment: string;
begin
  CreateGUID(LGuid);
  LDirectory := TPath.Combine(TPath.GetTempPath, 'DAI-PackageSummary-Fixture-' + GUIDToString(LGuid));
  TDirectory.CreateDirectory(LDirectory);
  LTarget := TPath.Combine(LDirectory, 'Package370.bpl');
  LAlias := TPath.Combine(LDirectory, 'DifferentAlias.bpl');
  LOther := TPath.Combine(LDirectory, 'OtherPackage370.bpl');
  TFile.WriteAllText(LTarget, 'test fixture, never executable');
  TFile.WriteAllText(LOther, 'different test fixture');
  Check(CreateHardLinkW(PWideChar(LAlias), PWideChar(LTarget), nil), 'hardlink fixture for path identity');
  try
    LServices := TTestServices.Create;
    LServices.RegistryKey := 'Software\DAI.PackageSummary.Tests\' + GUIDToString(LGuid);
    LServices.MacroDirectory := LDirectory;
    BorlandIDEServices := LServices;
    CheckAbsentRegistry(LServices.RegistryKey);

    LData := CompleteData;
    CheckStates(LData, LTarget, LDirectory, 'false', 'false', 'false');
    LData.KnownPackages := [LTarget];
    LData.LoadedPackages := [LoadedEntry(LTarget, ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'true');
    LData.LoadedPackages := [LoadedEntry(LTarget, ptFalse)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'false');
    LData.DisabledPackages := [LTarget];
    CheckStates(LData, LTarget, LDirectory, 'true', 'false', 'false');
    LData.LoadedPackages := [LoadedEntry(LTarget, ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'false', 'true');

    LData := CompleteData;
    LData.LoadedPackages := [LoadedEntry(LTarget, ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'false', 'false', 'true');
    LData.KnownPackages := [LOther];
    LData.LoadedPackages := [LoadedEntry(LOther, ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'false', 'false', 'false');
    LData.KnownPackages := [TPath.Combine(LDirectory, 'Release\Package370.bpl')];
    LData.LoadedPackages := [LoadedEntry(TPath.Combine(LDirectory, 'Release\Package370.bpl'), ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'false', 'false', 'false');

    LData := CompleteData;
    LData.KnownPackages := [LAlias];
    LData.DisabledPackages := [LAlias];
    LData.LoadedPackages := [LoadedEntry(LAlias, ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'false', 'true');
    LData.DisabledPackages := [];
    CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'true');
    CheckStates(LData, '\\?\' + LTarget, LDirectory, 'true', 'true', 'true');
    LLock := CreateFileW(PWideChar(LTarget), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
    Check(LLock <> INVALID_HANDLE_VALUE, 'exclusive sharing fixture');
    try
      CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'true');
      LData.KnownPackages := [LTarget];
      LData.LoadedPackages := [LoadedEntry(LTarget, ptTrue)];
      CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'true');
    finally
      CloseHandle(LLock);
    end;

    LData := CompleteData;
    LData.KnownPackages := ['$(BDSBIN)\Package370.bpl'];
    LData.LoadedPackages := [LoadedEntry('$(BDSBIN)\Package370.bpl', ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'true');
    CheckStates(LData, 'Package370.bpl', LDirectory, 'true', 'true', 'true');
    CheckStates(LData, UpperCase(LTarget), LDirectory, 'true', 'true', 'true');
    CheckStates(LData, TPath.Combine(LDirectory, '.\Package370.bpl'), LDirectory, 'true', 'true', 'true');
    LPreviousEnvironment := GetEnvironmentVariable('DAI_PACKAGE_TEST_DIRECTORY');
    SetEnvironmentVariableW('DAI_PACKAGE_TEST_DIRECTORY', PWideChar(LDirectory));
    try
      LData.KnownPackages := ['%DAI_PACKAGE_TEST_DIRECTORY%\Package370.bpl'];
      CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'true');
    finally
      if LPreviousEnvironment = '' then
        SetEnvironmentVariableW('DAI_PACKAGE_TEST_DIRECTORY', nil)
      else
        SetEnvironmentVariableW('DAI_PACKAGE_TEST_DIRECTORY', PWideChar(LPreviousEnvironment));
    end;
    CheckStates(LData, '', LDirectory, 'null', 'null', 'null');
    CheckStates(LData, '$(UNKNOWN)\Package370.bpl', LDirectory, 'null', 'null', 'null');
    CheckStates(LData, 'C:Package370.bpl', LDirectory, 'null', 'null', 'null');
    CheckStates(LData, LTarget + #0, LDirectory, 'null', 'null', 'null');
    CheckStates(LData, '%%\%DAI_PACKAGE_TEST_UNSET%\Package370.bpl', LDirectory, 'null', 'null', 'null');
    LData.KnownPackages := ['$(UNKNOWN)\Package370.bpl'];
    LData.LoadedPackages := [LoadedEntry('$(UNKNOWN)\Package370.bpl', ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'null', 'null', 'null');
    LData.KnownPackages := LData.KnownPackages + [LTarget];
    LData.LoadedPackages := LData.LoadedPackages + [LoadedEntry(LTarget, ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'true', 'true');
    LData.DisabledPackages := ['$(UNKNOWN)\Package370.bpl'];
    CheckStates(LData, LTarget, LDirectory, 'true', 'null', 'true');
    LData.DisabledPackages := LData.DisabledPackages + [LTarget];
    CheckStates(LData, LTarget, LDirectory, 'true', 'false', 'true');
    LData := Default(TDAIPackageSnapshotData);
    CheckStates(LData, LTarget, LDirectory, 'null', 'null', 'null');
    LData.KnownPackages := [LTarget];
    LData.LoadedPackages := [LoadedEntry(LTarget, ptFalse)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'null', 'null');
    LData.LoadedPackages := [LoadedEntry(LTarget, ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'true', 'null', 'true');
    LData.LoadedPackages := [LoadedEntry(LTarget, ptUnknown)];
    LData.LoadedComplete := True;
    CheckStates(LData, LTarget, LDirectory, 'true', 'null', 'null');

    LData := CompleteData;
    LData.KnownPackages := ['\\server.invalid\PackageSummary\Package370.bpl'];
    LData.LoadedPackages := [LoadedEntry('\\server.invalid\PackageSummary\Package370.bpl', ptTrue)];
    CheckStates(LData, LTarget, LDirectory, 'null', 'null', 'null');
    CheckStates(LData, '\\server.invalid\PackageSummary\Package370.bpl', LDirectory, 'true', 'true', 'true');
    LData.KnownPackages := [LAlias];
    LData.LoadedPackages := [LoadedEntry(LAlias, ptTrue)];
    LSnapshot := TDAIPackageSummarySnapshot.Create(LData);
    try
      LData.KnownPackages[0] := LOther;
      LData.LoadedPackages[0].FileName := LOther;
      LJson := LSnapshot.ToJson(nil, LTarget, LDirectory);
      try
        CheckField(LJson, 'registered', 'true');
        CheckField(LJson, 'loaded', 'true');
      finally
        LJson.Free;
      end;
      LJson := LSnapshot.ToJson(nil, LOther, LDirectory);
      try
        CheckField(LJson, 'registered', 'false');
        CheckField(LJson, 'loaded', 'false');
      finally
        LJson.Free;
      end;
    finally
      LSnapshot.Free;
    end;

    LConfiguration := TTestConfiguration.Create;
    LConfigurationIntf := LConfiguration;
    LConfiguration.Description := 'Current unsaved package description';
    LConfiguration.RuntimeOnly := 'TRUE';
    LConfiguration.DesignOnly := '0';
    LConfiguration.NeverBuild := 'true';
    LSnapshot := TDAIPackageSummarySnapshot.Create(CompleteData);
    try
      LJson := LSnapshot.ToJson(LConfigurationIntf, LTarget, LDirectory);
      try
        CheckField(LJson, 'description', LConfiguration.Description);
        CheckField(LJson, 'usage', 'runtime');
        CheckField(LJson, 'build_mode', 'manual');
        Check(LConfiguration.InheritedReads = 4, 'all values read from inherited current configuration');
      finally
        LJson.Free;
      end;
      LConfiguration.RuntimeOnly := 'false';
      LConfiguration.DesignOnly := '1';
      LConfiguration.NeverBuild := 'false';
      LJson := LSnapshot.ToJson(LConfigurationIntf, LTarget, LDirectory);
      try
        CheckField(LJson, 'usage', 'design_time');
        CheckField(LJson, 'build_mode', 'automatic');
      finally
        LJson.Free;
      end;
      LConfiguration.DesignOnly := 'false';
      LConfiguration.Description := '';
      LJson := LSnapshot.ToJson(LConfigurationIntf, LTarget, LDirectory);
      try
        CheckField(LJson, 'usage', 'runtime_and_design');
        CheckField(LJson, 'description', '');
      finally
        LJson.Free;
      end;
      LConfiguration.RuntimeOnly := 'true';
      LConfiguration.DesignOnly := 'true';
      LConfiguration.NeverBuild := '';
      LJson := LSnapshot.ToJson(LConfigurationIntf, LTarget, LDirectory);
      try
        CheckField(LJson, 'usage', 'null');
        CheckField(LJson, 'build_mode', 'null');
      finally
        LJson.Free;
      end;
      LConfiguration.RuntimeOnly := '';
      LConfiguration.DesignOnly := 'unexpected';
      LConfiguration.FailingOption := 'DCC_Description';
      LJson := LSnapshot.ToJson(LConfigurationIntf, LTarget, LDirectory);
      try
        CheckField(LJson, 'usage', 'null');
        CheckField(LJson, 'description', 'null');
      finally
        LJson.Free;
      end;
      LConfiguration.FailingOption := 'DCC_OutputNeverBuildDcps';
      LConfiguration.NeverBuild := 'true';
      LJson := LSnapshot.ToJson(LConfigurationIntf, LTarget, LDirectory);
      try
        CheckField(LJson, 'build_mode', 'null');
        CheckField(LJson, 'description', '');
      finally
        LJson.Free;
      end;
    finally
      LSnapshot.Free;
      LConfigurationIntf := nil;
    end;

    LPackage := TTestPackage.Create;
    LPackage.FileName := LTarget;
    LPackage.Loaded := True;
    LServices.Packages := [LPackage];
    LSnapshot := TDAIPackageSummarySnapshot.Create;
    try
      LJson := LSnapshot.ToJson(nil, LTarget, LDirectory);
      try
        CheckField(LJson, 'registered', 'false');
        CheckField(LJson, 'enabled', 'false');
        CheckField(LJson, 'loaded', 'true');
      finally
        LJson.Free;
      end;
      LPackage.Loaded := False;
      LJson := LSnapshot.ToJson(nil, LTarget, LDirectory);
      try
        CheckField(LJson, 'loaded', 'true');
        Check(LServices.CountReads = 1, 'package services captured once per list');
      finally
        LJson.Free;
      end;
    finally
      LSnapshot.Free;
    end;
    LPackage.FailLoaded := True;
    LSnapshot := TDAIPackageSummarySnapshot.Create;
    try
      LJson := LSnapshot.ToJson(nil, LTarget, LDirectory);
      try
        CheckField(LJson, 'loaded', 'null');
        CheckField(LJson, 'registered', 'false');
      finally
        LJson.Free;
      end;
    finally
      LSnapshot.Free;
    end;
    LServices.FailCount := True;
    LSnapshot := TDAIPackageSummarySnapshot.Create;
    try
      LJson := LSnapshot.ToJson(nil, LTarget, LDirectory);
      try
        CheckField(LJson, 'loaded', 'null');
        CheckField(LJson, 'registered', 'false');
      finally
        LJson.Free;
      end;
    finally
      LSnapshot.Free;
    end;
    CheckAbsentRegistry(LServices.RegistryKey);
    BorlandIDEServices := nil;
    LSnapshot := TDAIPackageSummarySnapshot.Create;
    try
      LJson := LSnapshot.ToJson(nil, LTarget, LDirectory);
      try
        CheckField(LJson, 'registered', 'null');
        CheckField(LJson, 'enabled', 'null');
        CheckField(LJson, 'loaded', 'null');
      finally
        LJson.Free;
      end;
    finally
      LSnapshot.Free;
    end;
  finally
    BorlandIDEServices := nil;
    TFile.Delete(LAlias);
    TFile.Delete(LTarget);
    TFile.Delete(LOther);
    TDirectory.Delete(LDirectory);
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS: ', GChecks, ' package summary checks');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
