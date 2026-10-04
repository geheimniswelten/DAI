unit h5u.DAI.OTA.ProjectSummary;

interface

uses
  System.JSON;

type
  TDAIProjectSummaryService = class sealed
  public
    class function Projects: TJSONArray; static;
  end;

implementation

class function TDAIProjectSummaryService.Projects: TJSONArray;
begin
  // The project summary has its own production-unit tests. This fixture
  // isolates directory searches from unrelated project and package services.
  Result := TJSONArray.Create;
end;

end.
