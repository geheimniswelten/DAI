unit h5u.DAI.OTA.Helpers;
interface
type TDAIOTA = class
  class function IsPathWithin(const APath, ARoot: string): Boolean; static;
end;
implementation
uses System.SysUtils;
class function TDAIOTA.IsPathWithin(const APath, ARoot: string): Boolean;
begin Result := SameText(Copy(APath, 1, Length(ARoot)), ARoot); end;
end.
