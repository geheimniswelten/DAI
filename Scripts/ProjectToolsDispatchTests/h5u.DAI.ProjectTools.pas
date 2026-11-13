unit h5u.DAI.ProjectTools;
interface
uses System.JSON, System.SysUtils;
type
  TDAIProjectTools = class sealed
  public
    class var Calls: Integer;
    class var LastProject, LastExtension, LastTool, LastArguments: string;
    class procedure Reset; static;
    class function ListTools(const AProjectFile: string): TJSONObject; static;
    class function CallTool(const AProjectFile, AExtensionId, AToolName: string; const AArguments: TJSONObject;
      const AAuthorizeWrite: TProc = nil): TJSONObject; static;
  end;
implementation
uses System.Classes, h5u.DAI.Permissions.Manager, h5u.DAI.Types;
procedure RequirePermission;
var Requests: TArray<TPermissionRequest>;
begin
  Requests := TDAIPermissionManager.Instance.Requests;
  if Length(Requests) <> 1 then raise EInvalidOperation.Create('Provider reached without exactly one permission check.');
  if Requests[0].Category <> pcProjectRead then raise EInvalidOperation.Create('Provider reached under wrong permission category.');
  if not TDAIPermissionManager.Instance.ProjectAllowed then raise EInvalidOperation.Create('Provider reached after permission denial.');
end;
class procedure TDAIProjectTools.Reset;
begin Calls := 0; LastProject := ''; LastExtension := ''; LastTool := ''; LastArguments := ''; end;
class function TDAIProjectTools.ListTools(const AProjectFile: string): TJSONObject;
begin
  RequirePermission; Inc(Calls); LastProject := AProjectFile;
  Result := TJSONObject.Create.AddPair('kind', 'list');
end;
class function TDAIProjectTools.CallTool(const AProjectFile, AExtensionId, AToolName: string; const AArguments: TJSONObject;
  const AAuthorizeWrite: TProc): TJSONObject;
begin
  RequirePermission;
  if AToolName = 'change' then
    AAuthorizeWrite();
  Inc(Calls); LastProject := AProjectFile; LastExtension := AExtensionId; LastTool := AToolName;
  LastArguments := AArguments.ToJSON;
  Result := TJSONObject.Create.AddPair('kind', 'call');
end;
end.
