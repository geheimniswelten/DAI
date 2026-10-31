unit h5u.DAI.Settings;

interface

uses
  System.Classes;

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
    FAllowIDEStartStop: Boolean;
    FLifecycleChangePending: Boolean;
    FManualClientRegistration: Boolean;
    FManualRegistrationPending: Boolean;
    FManualRegistrationShared: Boolean;
    function GetManualClientRegistration: Boolean;
    procedure SetManualClientRegistration(const ARegistered: Boolean);
    function GetAllowIDEStartStop: Boolean;
    procedure SetAllowIDEStartStop(const AAllowed: Boolean);
  public
    Enabled: Boolean;
    RegistryRoot: string;
    UseSharedConnectionSettings: Boolean;
    SavedConnectionAvailable: array[Boolean] of Boolean;
    SavedConnectionPort: array[Boolean] of Integer;
    SavedConnectionToken: array[Boolean] of string;
    ConnectionReadCount: Integer;
    ConnectionRefreshCount: Integer;
    FailConnectionRead: Boolean;
    LogAccessPoints: Boolean;
    Port: Integer;
    Token: string;
    CustomReadDirectories: TStringList;
    CustomReadDirectoriesAlwaysAllowed: Boolean;
    SaveCount: Integer;
    PersistedAllowIDEStartStop: Boolean;
    PolicyWriteCount: Integer;
    DiscardCount: Integer;
    FailSave: Boolean;
    SavedManualClientRegistration: array[Boolean] of Boolean;
    ManualRegistrationReadCount: Integer;
    ManualRegistrationWriteCount: Integer;
    ManualRegistrationDiscardCount: Integer;
    FailManualRegistrationRead: Boolean;
    constructor Create;
    destructor Destroy; override;
    class function Instance: TDAISettings; static;
    class procedure Reset; static;
    function GenerateToken: string;
    function LocalizedProjectsDirectoryHint: string;
    procedure RefreshConnectionSettings;
    function ReadConnectionSettings(const AShared: Boolean; out APort: Integer; out AToken: string): Boolean;
    procedure Save;
    procedure DiscardLifecycleChange;
    procedure DiscardManualRegistrationChange;
    function ReadManualClientRegistration(const AShared: Boolean): Boolean;
    property ManualClientRegistration: Boolean read GetManualClientRegistration write SetManualClientRegistration;
    property AllowIDEStartStop: Boolean read GetAllowIDEStartStop write SetAllowIDEStartStop;
  end;

implementation

uses
  System.SysUtils;

constructor TDAISettings.Create;
begin
  inherited Create;
  RegistryRoot := 'Software\Embarcadero\BDS\37.0\DAI';
  CustomReadDirectories := TStringList.Create;
end;

destructor TDAISettings.Destroy;
begin
  CustomReadDirectories.Free;
  inherited Destroy;
end;

function TDAISettings.GenerateToken: string;
begin
  Result := 'synthetic-generated-options-token';
end;

class function TDAISettings.Instance: TDAISettings;
begin
  Result := FInstance;
end;

procedure TDAISettings.DiscardLifecycleChange;
begin
  Inc(DiscardCount);
  FLifecycleChangePending := False;
end;

procedure TDAISettings.DiscardManualRegistrationChange;
begin
  Inc(ManualRegistrationDiscardCount);
  FManualRegistrationPending := False;
end;

function TDAISettings.ReadManualClientRegistration(const AShared: Boolean): Boolean;
begin
  Inc(ManualRegistrationReadCount);
  if FailManualRegistrationRead then
    raise Exception.Create('Synthetic manual-registration-preview failure');
  Result := SavedManualClientRegistration[AShared];
end;

function TDAISettings.GetManualClientRegistration: Boolean;
begin
  if FManualRegistrationPending and (FManualRegistrationShared = UseSharedConnectionSettings) then
    Exit(FManualClientRegistration);
  Result := SavedManualClientRegistration[UseSharedConnectionSettings];
end;

procedure TDAISettings.SetManualClientRegistration(const ARegistered: Boolean);
begin
  FManualClientRegistration := ARegistered;
  FManualRegistrationShared := UseSharedConnectionSettings;
  FManualRegistrationPending := True;
end;

function TDAISettings.GetAllowIDEStartStop: Boolean;
begin
  if FLifecycleChangePending then
    Exit(FAllowIDEStartStop);
  Result := PersistedAllowIDEStartStop;
end;

procedure TDAISettings.SetAllowIDEStartStop(const AAllowed: Boolean);
begin
  FAllowIDEStartStop := AAllowed;
  FLifecycleChangePending := True;
end;

function TDAISettings.LocalizedProjectsDirectoryHint: string;
begin
  Result := 'C:\SyntheticDAITest\Projects';
end;

class procedure TDAISettings.Reset;
begin
  FInstance.Enabled := False;
  FInstance.UseSharedConnectionSettings := True;
  FInstance.SavedConnectionAvailable[False] := False;
  FInstance.SavedConnectionAvailable[True] := False;
  FInstance.SavedConnectionPort[False] := 0;
  FInstance.SavedConnectionPort[True] := 0;
  FInstance.SavedConnectionToken[False] := '';
  FInstance.SavedConnectionToken[True] := '';
  FInstance.ConnectionReadCount := 0;
  FInstance.ConnectionRefreshCount := 0;
  FInstance.FailConnectionRead := False;
  FInstance.LogAccessPoints := False;
  FInstance.Port := 7101;
  FInstance.Token := 'synthetic-stored-options-token';
  FInstance.CustomReadDirectories.Clear;
  FInstance.CustomReadDirectoriesAlwaysAllowed := False;
  FInstance.SaveCount := 0;
  FInstance.FAllowIDEStartStop := True;
  FInstance.FLifecycleChangePending := False;
  FInstance.PersistedAllowIDEStartStop := True;
  FInstance.PolicyWriteCount := 0;
  FInstance.DiscardCount := 0;
  FInstance.FailSave := False;
  FInstance.FManualClientRegistration := False;
  FInstance.FManualRegistrationPending := False;
  FInstance.FManualRegistrationShared := True;
  FInstance.SavedManualClientRegistration[False] := False;
  FInstance.SavedManualClientRegistration[True] := False;
  FInstance.ManualRegistrationReadCount := 0;
  FInstance.ManualRegistrationWriteCount := 0;
  FInstance.ManualRegistrationDiscardCount := 0;
  FInstance.FailManualRegistrationRead := False;
end;

procedure TDAISettings.RefreshConnectionSettings;
begin
  Inc(ConnectionRefreshCount);
end;

function TDAISettings.ReadConnectionSettings(const AShared: Boolean; out APort: Integer; out AToken: string): Boolean;
begin
  Inc(ConnectionReadCount);
  if FailConnectionRead then
    raise Exception.Create('Synthetic connection-preview failure');
  Result := SavedConnectionAvailable[AShared];
  if Result then
  begin
    APort := SavedConnectionPort[AShared];
    AToken := SavedConnectionToken[AShared];
  end
  else
  begin
    APort := Port;
    AToken := Token;
  end;
end;

procedure TDAISettings.Save;
begin
  Inc(SaveCount);
  if FailSave then
    raise Exception.Create('Synthetic settings-save failure');
  if FManualRegistrationPending then
  begin
    SavedManualClientRegistration[FManualRegistrationShared] := FManualClientRegistration;
    Inc(ManualRegistrationWriteCount);
    FManualRegistrationPending := False;
  end;
  SavedConnectionAvailable[UseSharedConnectionSettings] := True;
  SavedConnectionPort[UseSharedConnectionSettings] := Port;
  SavedConnectionToken[UseSharedConnectionSettings] := Token;
  if FLifecycleChangePending then
  begin
    PersistedAllowIDEStartStop := FAllowIDEStartStop;
    Inc(PolicyWriteCount);
    FLifecycleChangePending := False;
  end;
end;

initialization
  TDAISettings.FInstance := TDAISettings.Create;
  TDAISettings.Reset;

finalization
  TDAISettings.FInstance.Free;

end.
