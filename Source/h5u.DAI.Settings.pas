unit h5u.DAI.Settings;

interface

uses
  System.Classes;

type
  TDAISettings = class sealed
  strict private
    class var FInstance: TDAISettings;
  private
    FEnabled: Boolean;
    FAllowIDEStartStop: Boolean;
    FLifecycleChangePending: Boolean;
    FManualClientRegistration: Boolean;
    FManualRegistrationChangePending: Boolean;
    FManualRegistrationChangeShared: Boolean;
    FLogAccessPoints: Boolean;
    FPort: Integer;
    FToken: string;
    FUseSharedConnectionSettings: Boolean;
    FConnectionBaselineKnown: array[Boolean] of Boolean;
    FConnectionBaselinePort: array[Boolean] of Integer;
    FConnectionBaselineToken: array[Boolean] of string;
    FLoadedConnectionShared: Boolean;
    FLoadedConnectionPort: Integer;
    FLoadedConnectionToken: string;
    FCustomReadDirectories: TStringList;
    FCustomReadDirectoriesAlwaysAllowed: Boolean;
    FRegistryRoot: string;
    function GetAllowIDEStartStop: Boolean;
    function GetManualClientRegistration: Boolean;
    procedure SetManualClientRegistration(const ARegistered: Boolean);
    procedure SetAllowIDEStartStop(const AAllowed: Boolean);
    function ReadRootDirectory: string;
    function StudioVersion: string;
  public
    constructor Create;
    destructor Destroy; override;
    class destructor Finalize;
    class function Instance: TDAISettings; static;
    function GenerateToken: string;
    procedure Load;
    procedure Save;
    function ReadConnectionSettings(const AShared: Boolean; out APort: Integer; out AToken: string): Boolean;
    procedure RefreshConnectionSettings;
    procedure DiscardLifecycleChange;
    procedure DiscardManualRegistrationChange;
    function ReadManualClientRegistration(const AShared: Boolean): Boolean;
    function ExpandPath(const APath: string): string;
    function LocalizedProjectsDirectoryHint: string;
    function DelphiSourceDirectory: string;
    function ToolsAPIDirectory: string;
    function CatalogRepositoryDirectory: string;
    function CatalogRepositoryAllUsersDirectory: string;
    function SamplesDirectory: string;
    function ReadOnlyRootDirectories: TArray<string>;
    property Enabled: Boolean read FEnabled write FEnabled;
    property AllowIDEStartStop: Boolean read GetAllowIDEStartStop write SetAllowIDEStartStop;
    property ManualClientRegistration: Boolean read GetManualClientRegistration write SetManualClientRegistration;
    property LogAccessPoints: Boolean read FLogAccessPoints write FLogAccessPoints;
    property Port: Integer read FPort write FPort;
    property Token: string read FToken write FToken;
    property UseSharedConnectionSettings: Boolean read FUseSharedConnectionSettings write FUseSharedConnectionSettings;
    property CustomReadDirectories: TStringList read FCustomReadDirectories;
    property CustomReadDirectoriesAlwaysAllowed: Boolean read FCustomReadDirectoriesAlwaysAllowed write FCustomReadDirectoriesAlwaysAllowed;
    property RegistryRoot: string read FRegistryRoot;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.Consts,
  h5u.DAI.Lifecycle.Policy;

const
  CSharedConnectionRegistryRoot = 'Software\DelphiAI\DAI\Connection';

function AcquireConnectionSettingsMutex: THandle;
var
  LToken: THandle;
  LTokenUser: TBytes;
  LRequired: DWORD;
  LStringSid: PChar;
  LName: string;
  LWaitResult: DWORD;
  LError: DWORD;
begin
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, LToken) then
    RaiseLastOSError;
  try
    LRequired := 0;
    GetTokenInformation(LToken, TokenUser, nil, 0, LRequired);
    if LRequired = 0 then
      RaiseLastOSError;
    SetLength(LTokenUser, LRequired);
    if not GetTokenInformation(LToken, TokenUser, @LTokenUser[0], LRequired,
      LRequired) then
      RaiseLastOSError;
    LStringSid := nil;
    if not ConvertSidToStringSid(PTokenUser(@LTokenUser[0])^.User.Sid,
      LStringSid) then
      RaiseLastOSError;
    try
      LName := 'Global\DelphiAI.DAI.Connection.' + string(LStringSid);
    finally
      LocalFree(HLOCAL(LStringSid));
    end;
  finally
    CloseHandle(LToken);
  end;

  Result := CreateMutex(nil, False, PChar(LName));
  if Result = 0 then
    RaiseLastOSError;
  LWaitResult := WaitForSingleObject(Result, 5000);
  if (LWaitResult = WAIT_OBJECT_0) or (LWaitResult = WAIT_ABANDONED) then
    Exit;
  LError := GetLastError;
  CloseHandle(Result);
  if LWaitResult = WAIT_TIMEOUT then
    raise EOSError.Create('Die DAI-Verbindungseinstellungen werden gerade von einer anderen IDE gespeichert.');
  RaiseLastOSError(LError);
end;

procedure ReleaseConnectionSettingsMutex(const AMutex: THandle);
begin
  ReleaseMutex(AMutex);
  CloseHandle(AMutex);
end;

function IsValidConnectionToken(const AToken: string): Boolean;
var
  LCharacter: Char;
begin
  Result := Trim(AToken) <> '';
  if not Result then
    Exit;
  for LCharacter in AToken do
    if (Ord(LCharacter) < 32) or (Ord(LCharacter) = 127) then
      Exit(False);
end;

function ReadStoredConnectionMode(const ARegistryRoot: string): Boolean;
var
  LRegistry: TRegistry;
begin
  Result := True;
  LRegistry := TRegistry.Create(KEY_READ);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if LRegistry.OpenKeyReadOnly(ARegistryRoot) and
      LRegistry.ValueExists('UseSharedConnectionSettings') then
      Result := LRegistry.ReadBool('UseSharedConnectionSettings');
  finally
    LRegistry.Free;
  end;
end;

function TryReadStoredConnectionSettings(const ARegistryRoot: string; const AShared: Boolean; out APort: Integer; out AToken: string): Boolean;
var
  LRegistry: TRegistry;
  LAccess: Cardinal;
begin
  Result := False;
  APort := 0;
  AToken := '';
  LAccess := KEY_READ;
  if AShared then
    LAccess := LAccess or KEY_WOW64_64KEY;
  LRegistry := TRegistry.Create(LAccess);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKeyReadOnly(ARegistryRoot) then
      Exit;
    if not LRegistry.ValueExists('Port') or not LRegistry.ValueExists('Token') then
      Exit;
    if LRegistry.GetDataType('Port') <> rdInteger then
      Exit;
    if not (LRegistry.GetDataType('Token') in [rdString, rdExpandString]) then
      Exit;
    APort := LRegistry.ReadInteger('Port');
    AToken := Trim(LRegistry.ReadString('Token'));
    Result := InRange(APort, 1024, 65535) and IsValidConnectionToken(AToken);
  finally
    LRegistry.Free;
  end;
end;

procedure WriteStoredConnectionSettings(const ARegistryRoot: string; const AShared: Boolean; const APort: Integer; const AToken: string);
var
  LRegistry: TRegistry;
  LAccess: Cardinal;
begin
  LAccess := KEY_READ or KEY_WRITE;
  if AShared then
    LAccess := LAccess or KEY_WOW64_64KEY;
  LRegistry := TRegistry.Create(LAccess);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKey(ARegistryRoot, True) then
      RaiseLastOSError;
    LRegistry.WriteInteger('Port', APort);
    LRegistry.WriteString('Token', AToken);
  finally
    LRegistry.Free;
  end;
end;

function ExpandEnvironmentStringsToString(const AValue: string): string;
var
  LRequired: Cardinal;
begin
  LRequired := ExpandEnvironmentStrings(PChar(AValue), nil, 0);
  if LRequired = 0 then
    Exit(AValue);
  SetLength(Result, LRequired);
  ExpandEnvironmentStrings(PChar(AValue), PChar(Result), LRequired);
  SetLength(Result, LRequired - 1);
end;

constructor TDAISettings.Create;
begin
  inherited Create;
  FCustomReadDirectories := TStringList.Create;
  FCustomReadDirectories.LineBreak := sLineBreak;
  FCustomReadDirectoriesAlwaysAllowed := False;
  FEnabled := True;
  FAllowIDEStartStop := True;
  FLifecycleChangePending := False;
  FManualRegistrationChangePending := False;
  FLogAccessPoints := False;
  FPort := CDAIDefaultPort;
  FToken := GenerateToken;
  FUseSharedConnectionSettings := True;
  FRegistryRoot := 'Software\Embarcadero\BDS\37.0\' + CDAIRegistrySubKey;

  if Supports(BorlandIDEServices, IOTAServices) then
    FRegistryRoot := (BorlandIDEServices as IOTAServices).GetBaseRegistryKey + '\' + CDAIRegistrySubKey;

  Load;
end;

destructor TDAISettings.Destroy;
begin
  FCustomReadDirectories.Free;
  inherited Destroy;
end;

class destructor TDAISettings.Finalize;
begin
  FInstance.Free;
  FInstance := nil;
end;

function TDAISettings.CatalogRepositoryAllUsersDirectory: string;
begin
  Result := ExpandPath(GetEnvironmentVariable('BDSCatalogRepositoryAllUsers'));
  if Result = '' then
    Result := ExpandPath('%PUBLIC%\Documents\Embarcadero\Studio\' + StudioVersion + '\CatalogRepository');
end;

function TDAISettings.CatalogRepositoryDirectory: string;
begin
  Result := ExpandPath(GetEnvironmentVariable('BDSCatalogRepository'));
  if Result = '' then
    Result := ExpandPath('%USERPROFILE%\Documents\Embarcadero\Studio\' + StudioVersion + '\CatalogRepository');
end;

function TDAISettings.DelphiSourceDirectory: string;
begin
  Result := TPath.Combine(ReadRootDirectory, 'source');
end;

function TDAISettings.ExpandPath(const APath: string): string;
var
  LCatalog: string;
  LCatalogAllUsers: string;
  LSamples: string;
  LValue: string;
begin
  LValue := Trim(APath);
  if LValue = '' then
    Exit('');

  LValue := StringReplace(LValue, '/', '\', [rfReplaceAll]);
  LSamples := '%PUBLIC%\Documents\Embarcadero\Studio\' + StudioVersion + '\Samples';
  if SameText(LValue, '%BDS%\Samples') or StartsText('%BDS%\Samples\', LValue) then
    LValue := LSamples + Copy(LValue, Length('%BDS%\Samples') + 1, MaxInt);
  LCatalog := GetEnvironmentVariable('BDSCatalogRepository');
  if LCatalog = '' then
    LCatalog := '%USERPROFILE%\Documents\Embarcadero\Studio\' + StudioVersion + '\CatalogRepository';
  LCatalogAllUsers := GetEnvironmentVariable('BDSCatalogRepositoryAllUsers');
  if LCatalogAllUsers = '' then
    LCatalogAllUsers := '%PUBLIC%\Documents\Embarcadero\Studio\' + StudioVersion + '\CatalogRepository';
  LValue := StringReplace(LValue, '%BDSCatalogRepositoryAllUsers%', LCatalogAllUsers, [rfReplaceAll, rfIgnoreCase]);
  LValue := StringReplace(LValue, '%BDSCatalogRepository%', LCatalog, [rfReplaceAll, rfIgnoreCase]);
  LValue := StringReplace(LValue, '%BDS%', ReadRootDirectory, [rfReplaceAll, rfIgnoreCase]);
  Result := TPath.GetFullPath(ExpandEnvironmentStringsToString(LValue));
  if not SameText(Result, TPath.GetPathRoot(Result)) then
    Result := ExcludeTrailingPathDelimiter(Result);
end;

function TDAISettings.GenerateToken: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := LowerCase(StringReplace(StringReplace(GUIDToString(LGuid), '{', '', []), '}', '', []));
end;

class function TDAISettings.Instance: TDAISettings;
begin
  if FInstance = nil then
    FInstance := TDAISettings.Create;
  Result := FInstance;
end;

procedure TDAISettings.DiscardLifecycleChange;
begin
  FLifecycleChangePending := False;
end;

procedure TDAISettings.DiscardManualRegistrationChange;
begin
  FManualRegistrationChangePending := False;
end;

function TDAISettings.ReadManualClientRegistration(const AShared: Boolean): Boolean;
var
  LRegistry: TRegistry;
  LRegistryRoot: string;
  LAccess: Cardinal;
begin
  Result := False;
  LAccess := KEY_READ;
  if AShared then
  begin
    LRegistryRoot := CSharedConnectionRegistryRoot;
    LAccess := LAccess or KEY_WOW64_64KEY;
  end
  else
    LRegistryRoot := FRegistryRoot;
  LRegistry := TRegistry.Create(LAccess);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if LRegistry.OpenKeyReadOnly(LRegistryRoot) and LRegistry.ValueExists('ManualClientRegistration') and
      (LRegistry.GetDataType('ManualClientRegistration') = rdInteger) then
      Result := LRegistry.ReadBool('ManualClientRegistration');
  finally
    LRegistry.Free;
  end;
end;

function TDAISettings.GetManualClientRegistration: Boolean;
begin
  if FManualRegistrationChangePending and (FManualRegistrationChangeShared = FUseSharedConnectionSettings) then
    Exit(FManualClientRegistration);
  // Read the current destination so another IDE's confirmation is observed.
  Result := ReadManualClientRegistration(FUseSharedConnectionSettings);
end;

procedure TDAISettings.SetManualClientRegistration(const ARegistered: Boolean);
begin
  FManualClientRegistration := ARegistered;
  FManualRegistrationChangeShared := FUseSharedConnectionSettings;
  FManualRegistrationChangePending := True;
end;

function TDAISettings.GetAllowIDEStartStop: Boolean;
var
  LReason: string;
begin
  if FLifecycleChangePending then
    Exit(FAllowIDEStartStop);
  Result := TDAILifecyclePolicy.ReadAllowed(LReason);
end;

procedure TDAISettings.SetAllowIDEStartStop(const AAllowed: Boolean);
begin
  FAllowIDEStartStop := AAllowed;
  FLifecycleChangePending := True;
end;

procedure TDAISettings.Load;
var
  LRegistry: TRegistry;
  LMutex: THandle;
  LFallbackPort: Integer;
  LFallbackToken: string;
  LLegacyPort: Integer;
  LLegacyToken: string;
  LHasLegacyPair: Boolean;
begin
  DiscardLifecycleChange;
  DiscardManualRegistrationChange;
  FCustomReadDirectoriesAlwaysAllowed := False;
  FUseSharedConnectionSettings := True;
  FConnectionBaselineKnown[False] := False;
  FConnectionBaselineKnown[True] := False;
  LFallbackPort := FPort;
  if not InRange(LFallbackPort, 1024, 65535) then
    LFallbackPort := CDAIDefaultPort;
  LFallbackToken := Trim(FToken);
  if not IsValidConnectionToken(LFallbackToken) then
    LFallbackToken := GenerateToken;
  LLegacyPort := LFallbackPort;
  LLegacyToken := LFallbackToken;
  LMutex := AcquireConnectionSettingsMutex;
  try
    FUseSharedConnectionSettings := ReadStoredConnectionMode(FRegistryRoot);
    LHasLegacyPair := TryReadStoredConnectionSettings(FRegistryRoot, False,
      LLegacyPort, LLegacyToken);
    if not LHasLegacyPair then
    begin
      LLegacyPort := LFallbackPort;
      LLegacyToken := LFallbackToken;
    end;
    LRegistry := TRegistry.Create(KEY_READ);
    try
      LRegistry.RootKey := HKEY_CURRENT_USER;
      if LRegistry.OpenKeyReadOnly(FRegistryRoot) then
      begin
        if LRegistry.ValueExists('Enabled') then
          FEnabled := LRegistry.ReadBool('Enabled');
        if LRegistry.ValueExists('LogAccessPoints') then
          FLogAccessPoints := LRegistry.ReadBool('LogAccessPoints');
        if LRegistry.ValueExists('CustomReadDirectories') then
          FCustomReadDirectories.Text := LRegistry.ReadString('CustomReadDirectories');
        if LRegistry.ValueExists('CustomReadDirectoriesAlwaysAllowed') then
          FCustomReadDirectoriesAlwaysAllowed := LRegistry.ReadBool('CustomReadDirectoriesAlwaysAllowed');
        if not FUseSharedConnectionSettings then
        begin
          if LRegistry.ValueExists('Port') then
            LLegacyPort := LRegistry.ReadInteger('Port');
          if LRegistry.ValueExists('Token') then
            LLegacyToken := Trim(LRegistry.ReadString('Token'));
        end;
      end;
    finally
      LRegistry.Free;
    end;

    if FUseSharedConnectionSettings then
    begin
      // First load publishes the pair immediately, so another IDE uses it even
      // when this IDE has never opened or saved its options.
      if not TryReadStoredConnectionSettings(CSharedConnectionRegistryRoot, True,
        FPort, FToken) then
      begin
        if LHasLegacyPair then
        begin
          FPort := LLegacyPort;
          FToken := LLegacyToken;
        end
        else
        begin
          FPort := LFallbackPort;
          FToken := LFallbackToken;
        end;
        WriteStoredConnectionSettings(CSharedConnectionRegistryRoot, True,
          FPort, FToken);
      end;
    end
    else
    begin
      FPort := LLegacyPort;
      FToken := LLegacyToken;
      if not InRange(FPort, 1024, 65535) then
        FPort := CDAIDefaultPort;
      if FToken = '' then
        FToken := GenerateToken;
    end;
    FConnectionBaselineKnown[FUseSharedConnectionSettings] := True;
    FConnectionBaselinePort[FUseSharedConnectionSettings] := FPort;
    FConnectionBaselineToken[FUseSharedConnectionSettings] := FToken;
    FLoadedConnectionShared := FUseSharedConnectionSettings;
    FLoadedConnectionPort := FPort;
    FLoadedConnectionToken := FToken;
  finally
    ReleaseConnectionSettingsMutex(LMutex);
  end;
end;

function TDAISettings.ReadConnectionSettings(const AShared: Boolean; out APort: Integer; out AToken: string): Boolean;
var
  LRegistryRoot: string;
  LMutex: THandle;
begin
  if AShared then
    LRegistryRoot := CSharedConnectionRegistryRoot
  else
    LRegistryRoot := FRegistryRoot;
  LMutex := AcquireConnectionSettingsMutex;
  try
    Result := TryReadStoredConnectionSettings(LRegistryRoot, AShared, APort, AToken);
    if not Result then
    begin
      APort := FPort;
      AToken := FToken;
    end;
    // A preview is also the edit baseline for that destination. Active values
    // and the registry remain unchanged until the options are applied.
    FConnectionBaselineKnown[AShared] := True;
    FConnectionBaselinePort[AShared] := APort;
    FConnectionBaselineToken[AShared] := AToken;
  finally
    ReleaseConnectionSettingsMutex(LMutex);
  end;
end;

procedure TDAISettings.RefreshConnectionSettings;
var
  LRegistryRoot: string;
  LPort: Integer;
  LToken: string;
  LMutex: THandle;
  LShared: Boolean;
begin
  if (FUseSharedConnectionSettings <> FLoadedConnectionShared) or
    (FPort <> FLoadedConnectionPort) or (FToken <> FLoadedConnectionToken) then
    Exit;
  LMutex := AcquireConnectionSettingsMutex;
  try
    LShared := ReadStoredConnectionMode(FRegistryRoot);
    if LShared then
      LRegistryRoot := CSharedConnectionRegistryRoot
    else
      LRegistryRoot := FRegistryRoot;
    if TryReadStoredConnectionSettings(LRegistryRoot, LShared, LPort, LToken) then
    begin
      FPort := LPort;
      FToken := LToken;
    end;
    FUseSharedConnectionSettings := LShared;
    FConnectionBaselineKnown[FUseSharedConnectionSettings] := True;
    FConnectionBaselinePort[FUseSharedConnectionSettings] := FPort;
    FConnectionBaselineToken[FUseSharedConnectionSettings] := FToken;
    FLoadedConnectionShared := FUseSharedConnectionSettings;
    FLoadedConnectionPort := FPort;
    FLoadedConnectionToken := FToken;
  finally
    ReleaseConnectionSettingsMutex(LMutex);
  end;
end;

function TDAISettings.LocalizedProjectsDirectoryHint: string;
const
  CEnglish = 'Projects';
  CGerman = 'Projekte';
  CItalian = 'Progetti';
  CJapanese = 'プロジェクト';
var
  LCandidates: TArray<string>;
  LCandidate: string;
  LDocumentsRoot: string;
  LLanguage: Word;
  LPreferredName: string;
begin
  LLanguage := PrimaryLangID(GetUserDefaultUILanguage);
  case LLanguage of
    LANG_GERMAN:
      LPreferredName := CGerman;
    LANG_ITALIAN:
      LPreferredName := CItalian;
    LANG_JAPANESE:
      LPreferredName := CJapanese;
  else
    LPreferredName := CEnglish;
  end;

  LDocumentsRoot := ExpandPath('%USERPROFILE%\Documents\Embarcadero\Studio\' + StudioVersion);
  LCandidates := [
    TPath.Combine(LDocumentsRoot, LPreferredName),
    TPath.Combine(LDocumentsRoot, CEnglish),
    TPath.Combine(LDocumentsRoot, CGerman),
    TPath.Combine(LDocumentsRoot, CItalian),
    TPath.Combine(LDocumentsRoot, CJapanese)
  ];

  for LCandidate in LCandidates do
    if TDirectory.Exists(LCandidate) then
      Exit(LCandidate);

  Result := TPath.Combine(LDocumentsRoot, LPreferredName);
end;

function TDAISettings.ReadOnlyRootDirectories: TArray<string>;
var
  LDirectory: string;
  LItems: TArray<string>;
begin
  LItems := [
    DelphiSourceDirectory,
    ToolsAPIDirectory,
    CatalogRepositoryDirectory,
    CatalogRepositoryAllUsersDirectory,
    SamplesDirectory
  ];

  for LDirectory in FCustomReadDirectories do
    if Trim(LDirectory) <> '' then
      LItems := LItems + [ExpandPath(LDirectory)];

  Result := LItems;
end;

function TDAISettings.ReadRootDirectory: string;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices) then
    Result := ExcludeTrailingPathDelimiter((BorlandIDEServices as IOTAServices).GetRootDirectory);
  if Result = '' then
    Result := ExcludeTrailingPathDelimiter(GetEnvironmentVariable('BDS'));
end;

function TDAISettings.SamplesDirectory: string;
begin
  Result := ExpandPath('%PUBLIC%\Documents\Embarcadero\Studio\' + StudioVersion + '\Samples');
end;

function TDAISettings.ToolsAPIDirectory: string;
begin
  Result := TPath.Combine(DelphiSourceDirectory, 'ToolsAPI');
end;


function TDAISettings.StudioVersion: string;
var
  LBaseRegistryKey: string;
begin
  Result := '37.0';
  if not Supports(BorlandIDEServices, IOTAServices) then
    Exit;

  LBaseRegistryKey := ExcludeTrailingPathDelimiter((BorlandIDEServices as IOTAServices).GetBaseRegistryKey);
  if LastDelimiter('\/', LBaseRegistryKey) > 0 then
    LBaseRegistryKey := Copy(LBaseRegistryKey, LastDelimiter('\/', LBaseRegistryKey) + 1, MaxInt);
  if Trim(LBaseRegistryKey) <> '' then
    Result := LBaseRegistryKey;
end;

procedure TDAISettings.Save;
var
  LRegistry: TRegistry;
  LRegistryRoot: string;
  LMutex: THandle;
  LStoredPort: Integer;
  LStoredToken: string;
  LConnectionChanged: Boolean;
  LConnectionClean: Boolean;
  LManualAccess: Cardinal;
begin
  if not InRange(FPort, 1024, 65535) then
    raise EArgumentOutOfRangeException.Create('Der Port muss zwischen 1024 und 65535 liegen.');
  if Trim(FToken) = '' then
    FToken := GenerateToken;
  if not IsValidConnectionToken(FToken) then
    raise EArgumentException.Create('Der Bearer-Token darf keine Steuerzeichen enthalten.');

  LMutex := AcquireConnectionSettingsMutex;
  try
    LConnectionClean := (FUseSharedConnectionSettings = FLoadedConnectionShared) and
      (FPort = FLoadedConnectionPort) and (FToken = FLoadedConnectionToken);
    if LConnectionClean then
      FUseSharedConnectionSettings := ReadStoredConnectionMode(FRegistryRoot);
    LConnectionChanged := not FConnectionBaselineKnown[FUseSharedConnectionSettings] or
      (FPort <> FConnectionBaselinePort[FUseSharedConnectionSettings]) or
      (FToken <> FConnectionBaselineToken[FUseSharedConnectionSettings]);
    if LConnectionClean then
      LConnectionChanged := False;
    if not FConnectionBaselineKnown[FUseSharedConnectionSettings] and
      (FPort = FLoadedConnectionPort) and (FToken = FLoadedConnectionToken) then
      LConnectionChanged := False;

    if FUseSharedConnectionSettings then
      LRegistryRoot := CSharedConnectionRegistryRoot
    else
      LRegistryRoot := FRegistryRoot;
    // An unrelated options save must not replay credentials that another IDE
    // changed after this settings object or destination preview was loaded.
    if not LConnectionChanged and TryReadStoredConnectionSettings(LRegistryRoot,
      FUseSharedConnectionSettings, LStoredPort, LStoredToken) then
    begin
      FPort := LStoredPort;
      FToken := LStoredToken;
    end
    else
      WriteStoredConnectionSettings(LRegistryRoot, FUseSharedConnectionSettings,
        FPort, FToken);

    LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
    try
      LRegistry.RootKey := HKEY_CURRENT_USER;
      if not LRegistry.OpenKey(FRegistryRoot, True) then
        RaiseLastOSError;
      LRegistry.WriteBool('UseSharedConnectionSettings', FUseSharedConnectionSettings);
      LRegistry.WriteBool('Enabled', FEnabled);
      LRegistry.WriteBool('LogAccessPoints', FLogAccessPoints);
      LRegistry.WriteString('CustomReadDirectories', FCustomReadDirectories.Text);
      LRegistry.WriteBool('CustomReadDirectoriesAlwaysAllowed', FCustomReadDirectoriesAlwaysAllowed);
    finally
      LRegistry.Free;
    end;
    if FManualRegistrationChangePending then
    begin
      LManualAccess := KEY_READ or KEY_WRITE;
      if FManualRegistrationChangeShared then
      begin
        LRegistryRoot := CSharedConnectionRegistryRoot;
        LManualAccess := LManualAccess or KEY_WOW64_64KEY;
      end
      else
        LRegistryRoot := FRegistryRoot;
      LRegistry := TRegistry.Create(LManualAccess);
      try
        LRegistry.RootKey := HKEY_CURRENT_USER;
        if not LRegistry.OpenKey(LRegistryRoot, True) then
          RaiseLastOSError;
        LRegistry.WriteBool('ManualClientRegistration', FManualClientRegistration);
        FManualRegistrationChangePending := False;
      finally
        LRegistry.Free;
      end;
    end;
    FConnectionBaselineKnown[FUseSharedConnectionSettings] := True;
    FConnectionBaselinePort[FUseSharedConnectionSettings] := FPort;
    FConnectionBaselineToken[FUseSharedConnectionSettings] := FToken;
    FLoadedConnectionShared := FUseSharedConnectionSettings;
    FLoadedConnectionPort := FPort;
    FLoadedConnectionToken := FToken;
  finally
    ReleaseConnectionSettingsMutex(LMutex);
  end;
  if FLifecycleChangePending then
  begin
    TDAILifecyclePolicy.WriteAllowed(FAllowIDEStartStop);
    FLifecycleChangePending := False;
  end;
end;

end.
