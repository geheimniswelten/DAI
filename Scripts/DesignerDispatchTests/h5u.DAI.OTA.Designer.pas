unit h5u.DAI.OTA.Designer;
interface
uses System.JSON;
type
  TDAIDesignerService = class sealed
  public
    class var Calls: Integer;
    class var LastMethod, LastFile, LastArguments: string;
    class var LastResponse: TJSONObject;
    class var PermissionCount: Integer;
    class procedure Reset; static;
    class function SearchComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function SelectComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function ReadProperties(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function SetProperty(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function MoveComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function CreateComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
  end;
implementation
uses h5u.DAI.Permissions.Manager;
function Response(const AMethod, AFileName: string; const AArguments: TJSONObject): TJSONObject;
begin
  Inc(TDAIDesignerService.Calls);
  TDAIDesignerService.LastMethod := AMethod;
  TDAIDesignerService.LastFile := AFileName;
  if AArguments = nil then TDAIDesignerService.LastArguments := ''
  else TDAIDesignerService.LastArguments := AArguments.ToJSON;
  TDAIDesignerService.PermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := TJSONObject.Create;
  Result.AddPair('modified', TJSONBool.Create(False));
  Result.AddPair('actual_value', TJSONNull.Create);
  TDAIDesignerService.LastResponse := Result;
end;
class procedure TDAIDesignerService.Reset;
begin Calls := 0; LastMethod := ''; LastFile := ''; LastArguments := ''; PermissionCount := -1; LastResponse := nil; end;
class function TDAIDesignerService.SearchComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
begin Result := Response('search', AFileName, AArguments); end;
class function TDAIDesignerService.SelectComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
begin Result := Response('select', AFileName, AArguments); end;
class function TDAIDesignerService.ReadProperties(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
begin Result := Response('properties', AFileName, AArguments); end;
class function TDAIDesignerService.SetProperty(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
begin Result := Response('set_property', AFileName, AArguments); end;
class function TDAIDesignerService.MoveComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
begin Result := Response('move', AFileName, AArguments); end;
class function TDAIDesignerService.CreateComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
begin Result := Response('create', AFileName, AArguments); end;
end.
