unit h5u.DAI.OTA.Evaluation;

interface

type
  TDAIEvaluationService = class
  public
    class var ShutdownCount: Integer;
    class procedure Shutdown; static;
  end;

implementation

uses
  DAI.Runtime.TestState;

class procedure TDAIEvaluationService.Shutdown;
begin
  Inc(ShutdownCount);
  Events.Add('evaluation-shutdown');
end;

end.
