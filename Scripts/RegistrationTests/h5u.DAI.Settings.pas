unit h5u.DAI.Settings;

interface

type
  // This test adapter prevents isolated registration tests from touching the IDE registry.
  TDAISettings = class sealed
  private
    class var FInstance: TDAISettings;
  public
    Port: Integer;
    Token: string;
    UseSharedConnectionSettings: Boolean;
    RegistryRoot: string;
    SaveCount: Integer;
    class function Instance: TDAISettings; static;
    procedure Save;
    procedure RefreshConnectionSettings;
  end;

implementation

class function TDAISettings.Instance: TDAISettings;
begin
  if FInstance = nil then
  begin
    FInstance := TDAISettings.Create;
    FInstance.Port := 7331;
    FInstance.Token := 'test-token-never-use-in-production';
    FInstance.UseSharedConnectionSettings := True;
    FInstance.RegistryRoot := 'Software\Embarcadero\BDS\37.0\DAI';
  end;
  Result := FInstance;
end;

procedure TDAISettings.Save;
begin
  Inc(SaveCount);
end;

procedure TDAISettings.RefreshConnectionSettings;
begin
end;

end.
