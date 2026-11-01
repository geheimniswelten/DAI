unit h5u.DAI.OTA.ProjectOpen;
interface
type TDAIProjectOpenService = class
  class var ShutdownCount: Integer;
  class procedure Shutdown; static;
end;
implementation
uses DAI.Runtime.TestState;
class procedure TDAIProjectOpenService.Shutdown;
begin Inc(ShutdownCount); Events.Add('project-open-shutdown'); end;
end.
