unit h5u.DAI.OTA.Helpers;
interface
type TDAIOTA = class
  class function IsAlwaysReadableReference(const APath: string): Boolean; static;
end;
implementation
class function TDAIOTA.IsAlwaysReadableReference(const APath: string): Boolean;
begin Result := False end;
end.
