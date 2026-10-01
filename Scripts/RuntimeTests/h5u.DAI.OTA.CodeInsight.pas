unit h5u.DAI.OTA.CodeInsight;

interface

type
  TDAICodeInsightService = class
  public
    class var ShutdownCount: Integer;
    class procedure Shutdown; static;
  end;

implementation

uses
  DAI.Runtime.TestState;

class procedure TDAICodeInsightService.Shutdown;
begin
  Inc(ShutdownCount);
  InsightStopped := True;
  Events.Add('insight-shutdown');
end;

end.
