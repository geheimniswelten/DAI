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
    function GetAllowIDEStartStop: Boolean;
    procedure SetAllowIDEStartStop(const AAllowed: Boolean);
  public
    Enabled: Boolean;
    LogAccessPoints: Boolean;
    Port: Integer;
    Token: string;
    CustomReadDirectories: TStringList;
    SaveCount: Integer;
    PersistedAllowIDEStartStop: Boolean;
    PolicyWriteCount: Integer;
    DiscardCount: Integer;
    FailSave: Boolean;
    constructor Create;
    destructor Destroy; override;
    class function Instance: TDAISettings; static;
    class procedure Reset; static;
    function GenerateToken: string;
    function LocalizedProjectsDirectoryHint: string;
    procedure Save;
    procedure DiscardLifecycleChange;
    property AllowIDEStartStop: Boolean read GetAllowIDEStartStop write SetAllowIDEStartStop;
  end;

implementation

uses
  System.SysUtils;

constructor TDAISettings.Create;
begin
  inherited Create;
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
  FInstance.LogAccessPoints := False;
  FInstance.Port := 7101;
  FInstance.Token := 'synthetic-stored-options-token';
  FInstance.CustomReadDirectories.Clear;
  FInstance.SaveCount := 0;
  FInstance.FAllowIDEStartStop := True;
  FInstance.FLifecycleChangePending := False;
  FInstance.PersistedAllowIDEStartStop := True;
  FInstance.PolicyWriteCount := 0;
  FInstance.DiscardCount := 0;
  FInstance.FailSave := False;
end;

procedure TDAISettings.Save;
begin
  Inc(SaveCount);
  if FailSave then
    raise Exception.Create('Synthetic settings-save failure');
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
