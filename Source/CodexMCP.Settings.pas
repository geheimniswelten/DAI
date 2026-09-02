unit CodexMCP.Settings;

interface

uses
  System.SysUtils;

type
  TCodexMCPSettings = class
  strict private
    class var FInstance: TCodexMCPSettings;
  private
    FAdditionalReadOnlyRoots: string;
    FAuthToken: string;
    FEnabled: Boolean;
    FLoggingEnabled: Boolean;
    FPort: Integer;
    function GetRegistryKey: string;
    procedure EnsureAuthToken;
  public
    constructor Create;
    class destructor Destroy;
    class function Instance: TCodexMCPSettings; static;
    class function GenerateAuthToken: string; static;
    class function IsValidAuthToken(const AValue: string): Boolean; static;
    procedure Load;
    procedure Save;
    procedure RegenerateAuthToken;
    function AdditionalReadOnlyRootLines: TArray<string>;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Port: Integer read FPort write FPort;
    property LoggingEnabled: Boolean read FLoggingEnabled write FLoggingEnabled;
    property AdditionalReadOnlyRoots: string read FAdditionalReadOnlyRoots
      write FAdditionalReadOnlyRoots;
    property AuthToken: string read FAuthToken write FAuthToken;
    property RegistryKey: string read GetRegistryKey;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.StrUtils,
  System.Win.Registry,
  ToolsAPI,
  Winapi.Windows,
  CodexMCP.Constants;

const
  CValueEnabled = 'Enabled';
  CValuePort = 'Port';
  CValueLoggingEnabled = 'LoggingEnabled';
  CValueAdditionalReadOnlyRoots = 'AdditionalReadOnlyRoots';
  CValueAuthToken = 'AuthToken';

function CompactGuid(const AGuid: TGUID): string;
begin
  Result := GUIDToString(AGuid);
  Result := StringReplace(Result, '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
  Result := LowerCase(Result);
end;

{ TCodexMCPSettings }

constructor TCodexMCPSettings.Create;
begin
  inherited Create;
  FEnabled := False;
  FPort := CCodexMCPDefaultPort;
  FLoggingEnabled := False;
  FAdditionalReadOnlyRoots := '';
  FAuthToken := '';
  Load;
end;

class destructor TCodexMCPSettings.Destroy;
begin
  FreeAndNil(FInstance);
end;

function TCodexMCPSettings.AdditionalReadOnlyRootLines: TArray<string>;
var
  LIndex: Integer;
  LList: TStringList;
  LValue: string;
begin
  SetLength(Result, 0);
  LList := TStringList.Create;
  try
    LList.Text := FAdditionalReadOnlyRoots;
    for LIndex := 0 to LList.Count - 1 do
    begin
      LValue := Trim(LList[LIndex]);
      if (LValue = '') or StartsText('#', LValue) then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LValue;
    end;
  finally
    LList.Free;
  end;
end;

procedure TCodexMCPSettings.EnsureAuthToken;
begin
  FAuthToken := Trim(FAuthToken);
  if not IsValidAuthToken(FAuthToken) then
    FAuthToken := GenerateAuthToken;
end;

class function TCodexMCPSettings.GenerateAuthToken: string;
var
  LGuid1: TGUID;
  LGuid2: TGUID;
begin
  if CreateGUID(LGuid1) <> S_OK then
    RaiseLastOSError;
  if CreateGUID(LGuid2) <> S_OK then
    RaiseLastOSError;
  Result := CompactGuid(LGuid1) + CompactGuid(LGuid2);
end;

class function TCodexMCPSettings.IsValidAuthToken(
  const AValue: string
): Boolean;
var
  LChar: Char;
begin
  Result := Trim(AValue) <> '';
  if not Result then
    Exit;
  for LChar in AValue do
    if (Ord(LChar) <= 32) or (Ord(LChar) = 127) then
      Exit(False);
end;

function TCodexMCPSettings.GetRegistryKey: string;
var
  LOTAServices: IOTAServices;
begin
  Result := 'Software\Embarcadero\BDS\37.0' + CCodexMCPRegistrySuffix;
  if Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
    Result := LOTAServices.GetBaseRegistryKey + CCodexMCPRegistrySuffix;
end;

class function TCodexMCPSettings.Instance: TCodexMCPSettings;
begin
  if not Assigned(FInstance) then
    FInstance := TCodexMCPSettings.Create;
  Result := FInstance;
end;

procedure TCodexMCPSettings.Load;
var
  LRegistry: TRegistry;
begin
  LRegistry := TRegistry.Create(KEY_READ);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if LRegistry.OpenKeyReadOnly(GetRegistryKey) then
    begin
      if LRegistry.ValueExists(CValueEnabled) then
        FEnabled := LRegistry.ReadBool(CValueEnabled);
      if LRegistry.ValueExists(CValuePort) then
        FPort := LRegistry.ReadInteger(CValuePort);
      if LRegistry.ValueExists(CValueLoggingEnabled) then
        FLoggingEnabled := LRegistry.ReadBool(CValueLoggingEnabled);
      if LRegistry.ValueExists(CValueAdditionalReadOnlyRoots) then
        FAdditionalReadOnlyRoots :=
          LRegistry.ReadString(CValueAdditionalReadOnlyRoots);
      if LRegistry.ValueExists(CValueAuthToken) then
        FAuthToken := LRegistry.ReadString(CValueAuthToken);
    end;
  finally
    LRegistry.Free;
  end;

  if not InRange(FPort, 1024, 65535) then
    FPort := CCodexMCPDefaultPort;
  EnsureAuthToken;
end;

procedure TCodexMCPSettings.RegenerateAuthToken;
begin
  FAuthToken := GenerateAuthToken;
end;

procedure TCodexMCPSettings.Save;
var
  LRegistry: TRegistry;
begin
  if not InRange(FPort, 1024, 65535) then
    raise ERangeError.Create('Der Port muss zwischen 1024 und 65535 liegen.');
  FAuthToken := Trim(FAuthToken);
  if FAuthToken = '' then
    EnsureAuthToken
  else if not IsValidAuthToken(FAuthToken) then
    raise EArgumentException.Create(
      'Der Bearer-Token darf keine Leer- oder Steuerzeichen enthalten.'
    );
  LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKey(GetRegistryKey, True) then
      RaiseLastOSError;
    LRegistry.WriteBool(CValueEnabled, FEnabled);
    LRegistry.WriteInteger(CValuePort, FPort);
    LRegistry.WriteBool(CValueLoggingEnabled, FLoggingEnabled);
    LRegistry.WriteString(
      CValueAdditionalReadOnlyRoots,
      FAdditionalReadOnlyRoots
    );
    LRegistry.WriteString(CValueAuthToken, FAuthToken);
  finally
    LRegistry.Free;
  end;
end;

end.
