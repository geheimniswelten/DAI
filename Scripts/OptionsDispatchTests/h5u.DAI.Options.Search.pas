unit h5u.DAI.Options.Search;

interface

uses System.JSON;

type
  TDAIOptionsSearchService = class sealed
  public
    class var Calls, MaximumResults, PermissionCount: Integer;
    class var Query, Scope, Project: string;
    class var LastResponse: TJSONObject;
    class procedure Reset; static;
    class function Search(const AQuery, AScope, AProject: string; const AMaximumResults: Integer): TJSONObject; static;
  end;

implementation

uses h5u.DAI.Permissions.Manager;

class procedure TDAIOptionsSearchService.Reset;
begin
  Calls := 0;
  MaximumResults := -1;
  PermissionCount := -1;
  Query := '';
  Scope := '';
  Project := '';
  LastResponse := nil;
end;

class function TDAIOptionsSearchService.Search(const AQuery, AScope, AProject: string; const AMaximumResults: Integer): TJSONObject;
begin
  Inc(Calls);
  Query := AQuery;
  Scope := AScope;
  Project := AProject;
  MaximumResults := AMaximumResults;
  PermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := TJSONObject.Create;
  Result.AddPair('service_response', 'final-options-search-response');
  Result.AddPair('catalog_complete', TJSONNull.Create);
  LastResponse := Result;
end;

end.
