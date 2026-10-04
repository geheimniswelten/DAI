unit h5u.DAI.OTA.Search;

interface

uses
  System.JSON,
  ToolsAPI,
  h5u.DAI.Source.Search;

type
{$I 'DAI.SearchDispatch.Plan.inc'}

  TDAISourceSearchService = class sealed
  public
    class var PrepareCalls, SearchCalls: Integer;
    class var LastScope, LastProject, LastDirectory, LastQuery: string;
    class var LastTimeoutMs: Integer;
    class var LastOptions: TDAISourceSearchOptions;
    class var LastPlan: TDAISourceSearchPlan;
    class var PreparedProjectKeys: TArray<string>;
    class procedure Reset; static;
    class function Prepare(const AScope, AProject, ADirectory: string; const ATimeoutMs: Integer): TDAISourceSearchPlan; static;
    class function SearchPrepared(const AQuery: string; const APlan: TDAISourceSearchPlan; const AOptions: TDAISourceSearchOptions): TJSONObject; static;
  end;

implementation

class procedure TDAISourceSearchService.Reset;
begin
  PrepareCalls := 0;
  SearchCalls := 0;
  LastScope := '';
  LastProject := '';
  LastDirectory := '';
  LastQuery := '';
  LastTimeoutMs := 0;
  LastOptions := Default(TDAISourceSearchOptions);
  LastPlan := Default(TDAISourceSearchPlan);
  PreparedProjectKeys := nil;
end;

class function TDAISourceSearchService.Prepare(const AScope, AProject, ADirectory: string; const ATimeoutMs: Integer): TDAISourceSearchPlan;
begin
  Inc(PrepareCalls);
  LastScope := AScope;
  LastProject := AProject;
  LastDirectory := ADirectory;
  LastTimeoutMs := ATimeoutMs;
  Result := Default(TDAISourceSearchPlan);
  Result.Scope := AScope;
  Result.Directory := ADirectory;
  Result.ProjectKeys := PreparedProjectKeys;
  Result.PreparationMs := 7;
end;

class function TDAISourceSearchService.SearchPrepared(const AQuery: string; const APlan: TDAISourceSearchPlan;
  const AOptions: TDAISourceSearchOptions): TJSONObject;
begin
  Inc(SearchCalls);
  LastQuery := AQuery;
  LastPlan := APlan;
  LastOptions := AOptions;
  Result := TJSONObject.Create;
  Result.AddPair('service_response', 'final-source-service-response');
end;

end.
