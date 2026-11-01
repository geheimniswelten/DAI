unit h5u.DAI.OTA.Helpers;
interface
type TDAIOTA = class
  class var FailOnProjectQuery: Boolean;
  class var ProjectQueries: Integer;
  class function ActiveProjectFileName: string; static;
end;
implementation
uses System.Classes, System.SysUtils, Winapi.Windows;
class function TDAIOTA.ActiveProjectFileName: string;
begin
  InterlockedIncrement(ProjectQueries);
  if FailOnProjectQuery then raise EInvalidOperation.Create('Unexpected synchronous IDE project query');
  Result := '';
end;
end.
