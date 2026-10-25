unit h5u.DAI.Settings;

interface

type
  TDAISettings = class sealed
  private
    class var FInstance: TDAISettings;
  public
    Enabled, UseSharedConnectionSettings: Boolean;
    Port: Integer;
    RegistryRoot: string;
    class function Instance: TDAISettings; static;
  end;

implementation

class function TDAISettings.Instance: TDAISettings;
begin
  if not Assigned(FInstance) then
  begin
    FInstance := TDAISettings.Create;
    FInstance.Enabled := True;
    FInstance.UseSharedConnectionSettings := True;
    FInstance.Port := 7333;
    FInstance.RegistryRoot := 'Software\Embarcadero\BDS\37.0\DAI';
  end;
  Result := FInstance;
end;

initialization

finalization
  TDAISettings.FInstance.Free;

end.
