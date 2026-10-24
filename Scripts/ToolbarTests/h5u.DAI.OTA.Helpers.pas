unit h5u.DAI.OTA.Helpers;

interface

type
  TDAIOTA = class sealed
  public
    class var ActiveProjectName: string;
    class function ActiveProjectFileName: string; static;
  end;

implementation

class function TDAIOTA.ActiveProjectFileName: string;
begin
  Result := ActiveProjectName;
end;

end.
