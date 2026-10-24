unit h5u.DAI.Settings;
interface
type
  TDAISettings = class
    class function Instance: TDAISettings; static;
    function ExpandPath(const APath: string): string;
  end;
implementation
var GSettings: TDAISettings;
class function TDAISettings.Instance: TDAISettings;
begin Result := GSettings end;
function TDAISettings.ExpandPath(const APath: string): string;
begin Result := APath end;
initialization
  GSettings := TDAISettings.Create;
finalization
  GSettings.Free;
end.
