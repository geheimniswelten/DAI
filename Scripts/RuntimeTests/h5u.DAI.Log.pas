unit h5u.DAI.Log;

interface

type
  TDAILog = class
  public
    class var ShutdownCount: Integer;
    class procedure Error(const AText: string); static;
    class procedure Shutdown; static;
  end;

implementation

uses
  DAI.Runtime.TestState;

class procedure TDAILog.Error(const AText: string);
begin
  Events.Add('error: ' + AText);
end;

class procedure TDAILog.Shutdown;
begin
  Inc(ShutdownCount);
  LoggerStopped := True;
  Events.Add('log-shutdown');
end;

end.
