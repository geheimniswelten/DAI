unit h5u.DAI.UI;

interface

type
  TDAIUIService = class
  public
    class var ShutdownCount: Integer;
    class procedure Shutdown; static;
  end;

implementation

uses
  DAI.Runtime.TestState;

class procedure TDAIUIService.Shutdown;
begin
  Inc(ShutdownCount);
  Events.Add('ui-shutdown');
end;

end.
