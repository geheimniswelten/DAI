unit h5u.DAI.Options.Navigation;

interface

type
  TDAIOptionsNavigationService = class
  public
    class var ShutdownCount: Integer;
    class procedure Shutdown; static;
  end;

implementation

uses
  DAI.Runtime.TestState;

class procedure TDAIOptionsNavigationService.Shutdown;
begin
  Inc(ShutdownCount);
  Events.Add('options-navigation-shutdown');
end;

end.
