unit h5u.DAI.OTA.Helpers;

interface

type
  TDAIOTA = class sealed
  public
    class var ActiveFileName: string;
    class function ActiveProjectFileName: string; static;
  end;

implementation

class function TDAIOTA.ActiveProjectFileName: string;
begin
  Result := ActiveFileName;
end;

end.
