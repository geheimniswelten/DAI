unit h5u.DAI.OTA.AI;

interface

uses
  System.JSON;

type
  TDAIAIService = class sealed
  public
    class function Status: TJSONObject; static;
  end;

implementation

class function TDAIAIService.Status: TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('available', TJSONBool.Create(True)).AddPair('fixture', 'no_model_request');
end;

end.
