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
    FLogAccessPoints: Boolean;
    FPort: Integer;
    FToken: string;
    FCustomReadDirectories: TStringList;
    FRegistryRoot: string;
    function GetAllowIDEStartStop: Boolean;
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
    procedure DiscardLifecycleChange;
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
    property LogAccessPoints: Boolean read FLogAccessPoints write FLogAccessPoints;
    property Port: Integer read FPort write FPort;
    property Token: string read FToken write FToken;
    property CustomReadDirectories: TStringList read FCustomReadDirectories;
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
  FEnabled := True;
  FAllowIDEStartStop := True;
  FLifecycleChangePending := False;
  FLogAccessPoints := False;
  FPort := CDAIDefaultPort;
  FToken := GenerateToken;
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
begin
  DiscardLifecycleChange;
  LRegistry := TRegistry.Create(KEY_READ);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKeyReadOnly(FRegistryRoot) then
      Exit;
    if LRegistry.ValueExists('Enabled') then
      FEnabled := LRegistry.ReadBool('Enabled');
    if LRegistry.ValueExists('LogAccessPoints') then
      FLogAccessPoints := LRegistry.ReadBool('LogAccessPoints');
    if LRegistry.ValueExists('Port') then
      FPort := LRegistry.ReadInteger('Port');
    if LRegistry.ValueExists('Token') then
      FToken := Trim(LRegistry.ReadString('Token'));
    if LRegistry.ValueExists('CustomReadDirectories') then
      FCustomReadDirectories.Text := LRegistry.ReadString('CustomReadDirectories');
  finally
    LRegistry.Free;
  end;

  if not InRange(FPort, 1024, 65535) then
    FPort := CDAIDefaultPort;
  if FToken = '' then
    FToken := GenerateToken;
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
begin
  if not InRange(FPort, 1024, 65535) then
    raise EArgumentOutOfRangeException.Create('Der Port muss zwischen 1024 und 65535 liegen.');
  if Trim(FToken) = '' then
    FToken := GenerateToken;

  LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKey(FRegistryRoot, True) then
      RaiseLastOSError;
    LRegistry.WriteBool('Enabled', FEnabled);
    LRegistry.WriteBool('LogAccessPoints', FLogAccessPoints);
    LRegistry.WriteInteger('Port', FPort);
    LRegistry.WriteString('Token', FToken);
    LRegistry.WriteString('CustomReadDirectories', FCustomReadDirectories.Text);
  finally
    LRegistry.Free;
  end;
  if FLifecycleChangePending then
  begin
    TDAILifecyclePolicy.WriteAllowed(FAllowIDEStartStop);
    FLifecycleChangePending := False;
  end;
end;

end.
