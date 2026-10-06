unit h5u.DAI.OTA.Palette;
interface
uses System.JSON;
type
  TDAIPaletteService = class sealed
  public
    class var Calls, PermissionCount: Integer;
    class var LastArguments: string;
    class var LastResponse: TJSONObject;
    class procedure Reset; static;
    class function ListComponents(const AArguments: TJSONObject): TJSONObject; static;
  end;
implementation
uses h5u.DAI.Permissions.Manager;
class procedure TDAIPaletteService.Reset;
begin Calls := 0; PermissionCount := -1; LastArguments := ''; LastResponse := nil; end;
class function TDAIPaletteService.ListComponents(const AArguments: TJSONObject): TJSONObject;
begin
  Inc(Calls);
  if AArguments = nil then LastArguments := '' else LastArguments := AArguments.ToJSON;
  PermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := TJSONObject.Create;
  Result.AddPair('available', TJSONBool.Create(False));
  LastResponse := Result;
end;
end.
