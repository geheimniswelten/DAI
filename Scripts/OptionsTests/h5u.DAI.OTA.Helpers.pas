unit h5u.DAI.OTA.Helpers;

interface

type
  TDAIOTA = class sealed
  public
    class function ActiveProjectFileName: string; static;
  end;

var
  SyntheticProjectFileName: string = 'C:\SyntheticDAITest\Project.dproj';

implementation

class function TDAIOTA.ActiveProjectFileName: string;
begin
  Result := SyntheticProjectFileName;
end;

end.
