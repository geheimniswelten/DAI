unit h5u.DAI.OTA.Helpers;
interface
type TDAIOTA = class
  class function ActiveProjectFileName: string; static;
end;
implementation
class function TDAIOTA.ActiveProjectFileName: string;
begin Result := ''; end;
end.