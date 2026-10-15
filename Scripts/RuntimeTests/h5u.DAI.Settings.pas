unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    Enabled: Boolean;
    Port: Integer;
    Token: string;
    class function Instance: TDAISettings; static;
    procedure Load;
    procedure RefreshConnectionSettings;
    class var RefreshCount: Integer;
    class var RefreshPending: Boolean;
    class var RefreshedPort: Integer;
    class var RefreshedToken: string;
  end;

implementation

class function TDAISettings.Instance: TDAISettings;
begin
  if not Assigned(FInstance) then
  begin
    FInstance := TDAISettings.Create;
    FInstance.Enabled := True;
    FInstance.Port := 7777;
    FInstance.Token := 'isolated-runtime-fixture';
  end;
  Result := FInstance;
end;

procedure TDAISettings.Load;
begin
end;

procedure TDAISettings.RefreshConnectionSettings;
begin
  Inc(RefreshCount);
  if RefreshPending then
  begin
    Port := RefreshedPort;
    Token := RefreshedToken;
    RefreshPending := False;
  end;
end;

initialization

finalization
  TDAISettings.FInstance.Free;

end.
