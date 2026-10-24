unit h5u.DAI.Settings;
interface
type
  TDAISettings = class sealed
  private
    class var FInstance: TDAISettings;
  public
    class function Instance: TDAISettings; static;
    function ExpandPath(const APath: string): string;
  end;
implementation
class function TDAISettings.Instance: TDAISettings;
begin
  if FInstance = nil then FInstance := TDAISettings.Create;
  Result := FInstance;
end;
function TDAISettings.ExpandPath(const APath: string): string;
begin
  Result := APath;
end;
initialization
finalization
  TDAISettings.FInstance.Free;
end.
