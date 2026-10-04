unit h5u.DAI.OTA.ExpressionUI;

interface

type
  TDAIExpressionUIService = class
  public
    class var ShutdownCount: Integer;
    class procedure Shutdown; static;
  end;

implementation

uses
  DAI.Runtime.TestState;

class procedure TDAIExpressionUIService.Shutdown;
begin
  Inc(ShutdownCount);
  Events.Add('expression-ui-shutdown');
end;

end.
