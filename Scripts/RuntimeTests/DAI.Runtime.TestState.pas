unit DAI.Runtime.TestState;

interface

uses
  System.Classes;

var
  Events: TStringList;
  LoggerStopped: Boolean;
  InsightStopped: Boolean;

implementation

initialization
  Events := TStringList.Create;

finalization
  Events.Free;

end.
