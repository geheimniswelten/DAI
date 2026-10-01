unit h5u.DAI.Settings;
interface
type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    Port: Integer;
    Enabled: Boolean;
    Token: string;
    RegistryRoot: string;
    class function Instance: TDAISettings; static;
    procedure Save;
  end;
implementation
class function TDAISettings.Instance: TDAISettings;
begin
  if FInstance = nil then
  begin
    FInstance := TDAISettings.Create;
    FInstance.Token := 'isolated-test-token';
    FInstance.Enabled := True;
  end;
  Result := FInstance;
end;
procedure TDAISettings.Save;
begin end;
end.