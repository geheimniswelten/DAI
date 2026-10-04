unit h5u.DAI.OTA.Helpers;

interface

uses
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var Project: IOTAProject;
    class var Calls: Integer;
    class var LastProject: string;
    class procedure Reset; static;
    class function ProjectByNameOrPath(const AProject: string): IOTAProject; static;
  end;

implementation

class procedure TDAIOTA.Reset;
begin
  Project := nil;
  Calls := 0;
  LastProject := '';
end;

class function TDAIOTA.ProjectByNameOrPath(const AProject: string): IOTAProject;
begin
  Inc(Calls);
  LastProject := AProject;
  Result := Project;
end;

end.
