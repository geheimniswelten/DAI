unit h5u.DAI.OTA.Helpers;

interface

type
  TDAIOTA = class sealed
  public
    class function ActiveProjectFileName: string; static;
  end;

implementation

class function TDAIOTA.ActiveProjectFileName: string;
begin
  Result := 'C:\SyntheticDAITest\Project.dproj';
end;

end.
