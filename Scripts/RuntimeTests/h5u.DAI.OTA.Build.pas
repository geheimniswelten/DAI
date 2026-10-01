unit h5u.DAI.OTA.Build;

interface

type
  TDAIBuildService = class
  public
    class var ShutdownCount: Integer;
    class procedure Shutdown; static;
  end;

implementation

uses
  DAI.Runtime.TestState;

class procedure TDAIBuildService.Shutdown;
begin
  Inc(ShutdownCount);
  Events.Add('build-shutdown');
end;

end.
