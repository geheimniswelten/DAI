unit h5u.DAI.OTA.Helpers;

interface

uses
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var Project: IOTAProject;
    class var AlwaysReadable, ReadOnlyReference: Boolean;
    class var Calls: Integer;
    class var LastProject: string;
    class function IsAlwaysReadableReference(const APath: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const APath: string): Boolean; static;
    class procedure Reset; static;
    class function ProjectByNameOrPath(const AProject: string): IOTAProject; static;
  end;

implementation

class function TDAIOTA.IsAlwaysReadableReference(const APath: string): Boolean;
begin Result := AlwaysReadable end;
class function TDAIOTA.IsReadOnlyReferenceFile(const APath: string): Boolean;
begin Result := ReadOnlyReference end;

class procedure TDAIOTA.Reset;
begin
  Project := nil;
  AlwaysReadable := False;
  ReadOnlyReference := False;
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
