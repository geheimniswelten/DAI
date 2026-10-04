unit h5u.DAI.OTA.PackageSummary;

interface

uses
  System.Generics.Collections,
  System.JSON,
  ToolsAPI,
  Winapi.Windows;

type
  TDAIPackageTruth = (ptUnknown, ptFalse, ptTrue);

  TDAILoadedPackageSummary = record
    FileName: string;
    Loaded: TDAIPackageTruth;
  end;

  TDAIPackageSnapshotData = record
    KnownPackages: TArray<string>;
    DisabledPackages: TArray<string>;
    LoadedPackages: TArray<TDAILoadedPackageSummary>;
    KnownComplete: Boolean;
    DisabledComplete: Boolean;
    LoadedComplete: Boolean;
  end;

  TDAIPackageFileIdentity = record
    Error: DWORD;
    Information: TByHandleFileInformation;
  end;

  TDAIPackageSummarySnapshot = class sealed
  private
    FData: TDAIPackageSnapshotData;
    FServices: IOTAServices;
    FIdentityCache: TDictionary<string, TDAIPackageFileIdentity>;
    FExpansionCache: TDictionary<string, string>;
    function ExpandedFileName(const AFileName, ABaseDirectory: string; out AExpanded: string): Boolean;
    function Identity(const AFileName: string): TDAIPackageFileIdentity;
    function MatchFile(const ATargetFile, ACandidate: string): TDAIPackageTruth;
    function MatchNames(const ATargetFile: string; const ANames: TArray<string>; const AComplete: Boolean): TDAIPackageTruth;
    function LoadedState(const ATargetFile: string): TDAIPackageTruth;
    procedure CaptureRegistry;
    procedure CaptureLoadedPackages;
  public
    // Capture once on the IDE main thread; the snapshot never installs or loads a package.
    constructor Create; overload;
    // The same resolver can also consume an already collected, read-only snapshot.
    constructor Create(const AData: TDAIPackageSnapshotData); overload;
    destructor Destroy; override;
    function ToJson(const AConfiguration: IOTABuildConfiguration; const ATargetFile, AProjectDirectory: string): TJSONObject;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  System.Win.Registry;

const
  CMaximumPackages = 10000;

function JsonTruth(const AValue: TDAIPackageTruth): TJSONValue;
begin
  case AValue of
    ptFalse: Result := TJSONBool.Create(False);
    ptTrue: Result := TJSONBool.Create(True);
  else
    Result := TJSONNull.Create;
  end;
end;

function OptionBoolean(const AConfiguration: IOTABuildConfiguration; const AName: string): TDAIPackageTruth;
var
  LValue: string;
begin
  Result := ptUnknown;
  if not Assigned(AConfiguration) then
    Exit;
  try
    LValue := Trim(AConfiguration.GetValue(AName, True));
    if SameText(LValue, 'true') or (LValue = '1') then
      Result := ptTrue
    else if SameText(LValue, 'false') or (LValue = '0') then
      Result := ptFalse;
  except
    // An unavailable option is different from an explicit false value.
    Result := ptUnknown;
  end;
end;

procedure AddPackageOptions(const AJson: TJSONObject; const AConfiguration: IOTABuildConfiguration);
var
  LDescription: TJSONValue;
  LRuntime, LDesign, LNeverBuild: TDAIPackageTruth;
  LUsage, LBuildMode: TJSONValue;
begin
  LDescription := nil;
  if Assigned(AConfiguration) then
    try
      LDescription := TJSONString.Create(AConfiguration.GetValue('DCC_Description', True));
    except
      LDescription := TJSONNull.Create;
    end;
  if not Assigned(LDescription) then
    LDescription := TJSONNull.Create;
  AJson.AddPair('description', LDescription);

  LRuntime := OptionBoolean(AConfiguration, 'RuntimeOnlyPackage');
  LDesign := OptionBoolean(AConfiguration, 'DesignOnlyPackage');
  LUsage := TJSONNull.Create;
  if (LRuntime <> ptUnknown) and (LDesign <> ptUnknown) then
  begin
    if (LRuntime = ptTrue) and (LDesign = ptFalse) then
    begin
      LUsage.Free;
      LUsage := TJSONString.Create('runtime');
    end
    else if (LDesign = ptTrue) and (LRuntime = ptFalse) then
    begin
      LUsage.Free;
      LUsage := TJSONString.Create('design_time');
    end
    else if (LRuntime = ptFalse) and (LDesign = ptFalse) then
    begin
      LUsage.Free;
      LUsage := TJSONString.Create('runtime_and_design');
    end;
  end;
  AJson.AddPair('usage', LUsage);

  LNeverBuild := OptionBoolean(AConfiguration, 'DCC_OutputNeverBuildDcps');
  LBuildMode := TJSONNull.Create;
  if LNeverBuild <> ptUnknown then
  begin
    LBuildMode.Free;
    if LNeverBuild = ptTrue then
      LBuildMode := TJSONString.Create('manual')
    else
      LBuildMode := TJSONString.Create('automatic');
  end;
  AJson.AddPair('build_mode', LBuildMode);
end;

function HasUnresolvedMacro(const AValue: string): Boolean;
var
  LStart, LEnd: Integer;
begin
  Result := (Pos('$(', AValue) <> 0) or (Pos('@(', AValue) <> 0);
  if Result then
    Exit;
  LStart := Pos('%', AValue);
  while LStart > 0 do
  begin
    LEnd := PosEx('%', AValue, LStart + 1);
    if LEnd = 0 then
      Exit;
    if LEnd > LStart + 1 then
      Exit(True);
    LStart := PosEx('%', AValue, LEnd + 1);
  end;
end;

function EnvironmentExpanded(const AValue: string): string;
var
  LLength: DWORD;
begin
  LLength := ExpandEnvironmentStringsW(PWideChar(AValue), nil, 0);
  if LLength = 0 then
    RaiseLastOSError;
  SetLength(Result, LLength);
  if ExpandEnvironmentStringsW(PWideChar(AValue), PWideChar(Result), LLength) = 0 then
    RaiseLastOSError;
  SetLength(Result, LLength - 1);
end;

function AbsolutePath(const AValue: string): Boolean;
begin
  Result := AValue.StartsWith('\\');
  if Length(AValue) >= 3 then
    Result := Result or ((AValue[2] = ':') and (AValue[3] = '\'));
end;

function FileIdentity(const AFileName: string; out AInfo: TByHandleFileInformation): DWORD;
var
  LHandle: THandle;
begin
  LHandle := CreateFileW(PWideChar(AFileName), FILE_READ_ATTRIBUTES, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if LHandle = INVALID_HANDLE_VALUE then
    Exit(GetLastError);
  try
    if GetFileInformationByHandle(LHandle, AInfo) then
      Result := ERROR_SUCCESS
    else
      Result := GetLastError;
  finally
    CloseHandle(LHandle);
  end;
end;

constructor TDAIPackageSummarySnapshot.Create;
begin
  inherited Create;
  FIdentityCache := TDictionary<string, TDAIPackageFileIdentity>.Create;
  FExpansionCache := TDictionary<string, string>.Create;
  Supports(BorlandIDEServices, IOTAServices, FServices);
  CaptureRegistry;
  CaptureLoadedPackages;
end;

constructor TDAIPackageSummarySnapshot.Create(const AData: TDAIPackageSnapshotData);
begin
  inherited Create;
  FIdentityCache := TDictionary<string, TDAIPackageFileIdentity>.Create;
  FExpansionCache := TDictionary<string, string>.Create;
  FData := AData;
  FData.KnownPackages := Copy(AData.KnownPackages);
  FData.DisabledPackages := Copy(AData.DisabledPackages);
  FData.LoadedPackages := Copy(AData.LoadedPackages);
  Supports(BorlandIDEServices, IOTAServices, FServices);
end;

destructor TDAIPackageSummarySnapshot.Destroy;
begin
  FExpansionCache.Free;
  FIdentityCache.Free;
  inherited;
end;

procedure TDAIPackageSummarySnapshot.CaptureRegistry;
var
  LBaseKey, LSuffix: string;

  procedure ReadNames(const ASubKey: string; var ANames: TArray<string>; var AComplete: Boolean);
  var
    LRegistry: TRegistry;
    LNames: TStringList;
    LName: string;
  begin
    LRegistry := TRegistry.Create(KEY_READ);
    LNames := TStringList.Create;
    try
      try
        LRegistry.RootKey := HKEY_CURRENT_USER;
        if not LRegistry.OpenKeyReadOnly(LBaseKey + '\' + ASubKey + LSuffix) then
        begin
          if (LRegistry.LastError <> ERROR_FILE_NOT_FOUND) and (LRegistry.LastError <> ERROR_PATH_NOT_FOUND) then
            AComplete := False;
          Exit;
        end;
        LRegistry.GetValueNames(LNames);
        if Length(ANames) + LNames.Count > CMaximumPackages then
        begin
          AComplete := False;
          Exit;
        end;
        for LName in LNames do
          ANames := ANames + [LName];
      except
        AComplete := False;
      end;
    finally
      LNames.Free;
      LRegistry.Free;
    end;
  end;

begin
  FData.KnownComplete := False;
  FData.DisabledComplete := False;
  if not Assigned(FServices) then
    Exit;
  try
    LBaseKey := ExcludeTrailingPathDelimiter(FServices.GetBaseRegistryKey).TrimLeft(['\']);
    if Trim(LBaseKey) = '' then
      Exit;
    {$IFDEF WIN64}
    LSuffix := ' x64';
    {$ELSE}
    LSuffix := '';
    {$ENDIF}
    FData.KnownComplete := True;
    FData.DisabledComplete := True;
    ReadNames('Known Packages', FData.KnownPackages, FData.KnownComplete);
    ReadNames('Known IDE Packages', FData.KnownPackages, FData.KnownComplete);
    ReadNames('Disabled Packages', FData.DisabledPackages, FData.DisabledComplete);
    ReadNames('Disabled IDE Packages', FData.DisabledPackages, FData.DisabledComplete);
  except
    FData.KnownComplete := False;
    FData.DisabledComplete := False;
  end;
end;

procedure TDAIPackageSummarySnapshot.CaptureLoadedPackages;
var
  LServices: IOTAPackageServices;
  LPackage: IOTAPackageInfo;
  LEntry: TDAILoadedPackageSummary;
  LCount, LIndex: Integer;
begin
  FData.LoadedComplete := False;
  if not Supports(BorlandIDEServices, IOTAPackageServices, LServices) then
    Exit;
  try
    LCount := LServices.PackageCount;
    if (LCount < 0) or (LCount > CMaximumPackages) then
      Exit;
    FData.LoadedComplete := True;
    for LIndex := 0 to LCount - 1 do
    begin
      try
        LPackage := LServices.Package[LIndex];
        if not Assigned(LPackage) then
        begin
          FData.LoadedComplete := False;
          Continue;
        end;
        LEntry.FileName := LPackage.FileName;
        LEntry.Loaded := ptUnknown;
        try
          if LPackage.Loaded then
            LEntry.Loaded := ptTrue
          else
            LEntry.Loaded := ptFalse;
        except
          LEntry.Loaded := ptUnknown;
        end;
        FData.LoadedPackages := FData.LoadedPackages + [LEntry];
      except
        FData.LoadedComplete := False;
      end;
    end;
  except
    FData.LoadedComplete := False;
  end;
end;

function TDAIPackageSummarySnapshot.ExpandedFileName(const AFileName, ABaseDirectory: string; out AExpanded: string): Boolean;
var
  LValue, LPrevious, LCacheKey: string;
  LIteration: Integer;
begin
  Result := False;
  AExpanded := '';
  LCacheKey := AFileName + #0 + ABaseDirectory;
  if FExpansionCache.TryGetValue(LCacheKey, AExpanded) then
    Exit(AExpanded <> '');
  try
    try
      LValue := Trim(AFileName);
      if (LValue = '') or (Pos(#0, AFileName) > 0) or (Pos(#0, ABaseDirectory) > 0) then
        Exit;
      if Length(LValue) >= 2 then
        if (LValue[1] = '"') and (LValue[Length(LValue)] = '"') then
          LValue := Copy(LValue, 2, Length(LValue) - 2);
      LValue := StringReplace(LValue, '/', '\', [rfReplaceAll]);
      for LIteration := 1 to 8 do
      begin
        LPrevious := LValue;
        if Assigned(FServices) then
          LValue := FServices.ExpandRootMacro(LValue);
        LValue := EnvironmentExpanded(LValue);
        if LPrevious = LValue then
          Break;
      end;
      if (Trim(LValue) = '') or HasUnresolvedMacro(LValue) then
        Exit;
      if not AbsolutePath(LValue) then
      begin
        // Registry paths have no project-relative base; do not guess using the IDE working directory.
        if (Trim(ABaseDirectory) = '') or (Pos(':', LValue) > 0) then
          Exit;
        LValue := TPath.Combine(ABaseDirectory, LValue);
      end;
      if not AbsolutePath(LValue) then
        Exit;
      AExpanded := TPath.GetFullPath(LValue);
      Result := True;
    except
      AExpanded := '';
    end;
  finally
    FExpansionCache.AddOrSetValue(LCacheKey, AExpanded);
  end;
end;

function TDAIPackageSummarySnapshot.Identity(const AFileName: string): TDAIPackageFileIdentity;
var
  LKey, LDriveRoot: string;
begin
  LKey := UpperCase(AFileName);
  if FIdentityCache.TryGetValue(LKey, Result) then
    Exit;
  Result := Default(TDAIPackageFileIdentity);
  Result.Error := ERROR_NOT_SUPPORTED;
  // Do not perform remote filesystem probes while reading a project list on the IDE main thread.
  LDriveRoot := '';
  if not AFileName.StartsWith('\\') then
    LDriveRoot := TPath.GetPathRoot(AFileName)
  else if AFileName.StartsWith('\\?\') then
    if Length(AFileName) >= 7 then
      if (AFileName[6] = ':') and (AFileName[7] = '\') then
        LDriveRoot := Copy(AFileName, 5, 3);
  if LDriveRoot <> '' then
    if GetDriveTypeW(PWideChar(LDriveRoot)) <> DRIVE_REMOTE then
      Result.Error := FileIdentity(AFileName, Result.Information);
  FIdentityCache.AddOrSetValue(LKey, Result);
end;

function TDAIPackageSummarySnapshot.MatchFile(const ATargetFile, ACandidate: string): TDAIPackageTruth;
var
  LCandidate: string;
  LTargetIdentity, LCandidateIdentity: TDAIPackageFileIdentity;
begin
  Result := ptUnknown;
  if not ExpandedFileName(ACandidate, '', LCandidate) then
    Exit;
  if SameText(ATargetFile, LCandidate) then
    Exit(ptTrue);
  LTargetIdentity := Identity(ATargetFile);
  LCandidateIdentity := Identity(LCandidate);
  if (LTargetIdentity.Error = ERROR_SUCCESS) and (LCandidateIdentity.Error = ERROR_SUCCESS) then
  begin
    if (LTargetIdentity.Information.nFileIndexHigh = 0) and (LTargetIdentity.Information.nFileIndexLow = 0) then
      Exit;
    if (LCandidateIdentity.Information.nFileIndexHigh = 0) and (LCandidateIdentity.Information.nFileIndexLow = 0) then
      Exit;
    if (LTargetIdentity.Information.dwVolumeSerialNumber = LCandidateIdentity.Information.dwVolumeSerialNumber) and
      (LTargetIdentity.Information.nFileIndexHigh = LCandidateIdentity.Information.nFileIndexHigh) and
      (LTargetIdentity.Information.nFileIndexLow = LCandidateIdentity.Information.nFileIndexLow) then
      Result := ptTrue
    else
      Result := ptFalse;
  end
  else if (LTargetIdentity.Error = ERROR_FILE_NOT_FOUND) or (LTargetIdentity.Error = ERROR_PATH_NOT_FOUND) or
    (LCandidateIdentity.Error = ERROR_FILE_NOT_FOUND) or (LCandidateIdentity.Error = ERROR_PATH_NOT_FOUND) then
    Result := ptFalse;
end;

function TDAIPackageSummarySnapshot.MatchNames(const ATargetFile: string; const ANames: TArray<string>; const AComplete: Boolean): TDAIPackageTruth;
var
  LName: string;
  LMatch: TDAIPackageTruth;
begin
  if AComplete then
    Result := ptFalse
  else
    Result := ptUnknown;
  for LName in ANames do
  begin
    LMatch := MatchFile(ATargetFile, LName);
    if LMatch = ptTrue then
      Exit(ptTrue);
    if LMatch = ptUnknown then
      Result := ptUnknown;
  end;
end;

function TDAIPackageSummarySnapshot.LoadedState(const ATargetFile: string): TDAIPackageTruth;
var
  LEntry: TDAILoadedPackageSummary;
  LMatch: TDAIPackageTruth;
begin
  if FData.LoadedComplete then
    Result := ptFalse
  else
    Result := ptUnknown;
  for LEntry in FData.LoadedPackages do
  begin
    LMatch := MatchFile(ATargetFile, LEntry.FileName);
    if LMatch = ptUnknown then
      Result := ptUnknown
    else if LMatch = ptTrue then
    begin
      if LEntry.Loaded = ptTrue then
        Exit(ptTrue);
      if LEntry.Loaded = ptUnknown then
        Result := ptUnknown;
    end;
  end;
end;

function TDAIPackageSummarySnapshot.ToJson(const AConfiguration: IOTABuildConfiguration; const ATargetFile, AProjectDirectory: string): TJSONObject;
var
  LRegistered, LDisabled, LEnabled, LLoaded: TDAIPackageTruth;
  LTargetFile: string;
begin
  LRegistered := ptUnknown;
  LEnabled := ptUnknown;
  LLoaded := ptUnknown;
  if ExpandedFileName(ATargetFile, AProjectDirectory, LTargetFile) then
  begin
    LRegistered := MatchNames(LTargetFile, FData.KnownPackages, FData.KnownComplete);
    LDisabled := MatchNames(LTargetFile, FData.DisabledPackages, FData.DisabledComplete);
    LLoaded := LoadedState(LTargetFile);
    if (LRegistered = ptFalse) or (LDisabled = ptTrue) then
      LEnabled := ptFalse
    else if (LRegistered = ptTrue) and (LDisabled = ptFalse) then
      LEnabled := ptTrue;
  end;
  Result := TJSONObject.Create;
  try
    AddPackageOptions(Result, AConfiguration);
    Result.AddPair('registered', JsonTruth(LRegistered));
    Result.AddPair('enabled', JsonTruth(LEnabled));
    Result.AddPair('loaded', JsonTruth(LLoaded));
  except
    Result.Free;
    raise;
  end;
end;

end.
