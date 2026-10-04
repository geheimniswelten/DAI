unit h5u.DAI.Windows.Inspection;
interface
uses Winapi.Windows;
type TDAIWindowService = class sealed
  public
    class var ProtectedHandle: HWND;
    class function IsProtectedPermissionWindow(const AHandle: HWND): Boolean; static;
end;
implementation
class function TDAIWindowService.IsProtectedPermissionWindow(const AHandle: HWND): Boolean;
begin Result := (AHandle <> 0) and (AHandle = ProtectedHandle); end;
end.
