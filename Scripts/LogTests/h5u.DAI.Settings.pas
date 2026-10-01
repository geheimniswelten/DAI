unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    LogAccessPoints: Boolean;
    class function Instance: TDAISettings; static;
  end;

implementation

class function TDAISettings.Instance: TDAISettings;
begin
  if not Assigned(FInstance) then
    FInstance := TDAISettings.Create;
  Result := FInstance;
end;

initialization

finalization
  TDAISettings.FInstance.Free;

end.
