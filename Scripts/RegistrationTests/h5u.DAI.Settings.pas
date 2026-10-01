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
    class function Instance: TDAISettings; static;
    procedure Save;
  end;

implementation

class function TDAISettings.Instance: TDAISettings;
begin
  if FInstance = nil then
  begin
    FInstance := TDAISettings.Create;
    FInstance.Port := 7331;
    FInstance.Token := 'test-token-never-use-in-production';
  end;
  Result := FInstance;
end;

procedure TDAISettings.Save;
begin
end;

end.
