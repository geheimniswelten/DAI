unit h5u.DAI.OTA.Helpers;
interface
type
  TDAIOTA = class sealed
  public
    class function IsAlwaysReadableReference(const AFileName: string): Boolean; static;
  end;
implementation
uses DAI.ExpressionDispatch.TestState;
class function TDAIOTA.IsAlwaysReadableReference(const AFileName: string): Boolean;
begin
  Result := ReferenceAlwaysReadable;
end;
end.
