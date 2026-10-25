unit h5u.DAI.OTA.Files;

interface

uses System.JSON;

type
  TDAIFileService = class sealed
  public
    class var Rows: TJSONArray;
    class var Calls: Integer;
    class function Projects: TJSONArray; static;
  end;

implementation

class function TDAIFileService.Projects: TJSONArray;
begin
  Inc(Calls);
  Result := Rows.Clone as TJSONArray;
end;

initialization

finalization
  TDAIFileService.Rows.Free;

end.
