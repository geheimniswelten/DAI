unit h5u.DAI.OTA.ProjectOpen;
interface
uses System.JSON, h5u.DAI.Types;
type TDAIProjectOpenService = class
  class function Open(const AFile: string; const AClose: Boolean; const AContext: TDAIRequestContext): TJSONObject; static;
  class function Status(const AId: string; const AContext: TDAIRequestContext): TJSONObject; static;
end;
implementation
uses h5u.DAI.OTA.Projects;
class function TDAIProjectOpenService.Open(const AFile: string; const AClose: Boolean; const AContext: TDAIRequestContext): TJSONObject;
begin Result := TDAIProjectService.OpenProject(AFile, AClose); end;
class function TDAIProjectOpenService.Status(const AId: string; const AContext: TDAIRequestContext): TJSONObject;
begin Result := TJSONObject.Create.AddPair('request_id', AId).AddPair('status', 'queued'); end;
end.
