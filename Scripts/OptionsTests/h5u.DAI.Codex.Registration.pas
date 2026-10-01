unit h5u.DAI.Codex.Registration;

interface

uses
  System.JSON;

type
  TDAICodexRegistration = class sealed
  public
    class function Status: TJSONObject; static;
  end;

implementation

class function TDAICodexRegistration.Status: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('codex_config', 'synthetic-options-config');
  Result.AddPair('codex_entry_registered', TJSONBool.Create(False));
  Result.AddPair('skill_file', 'synthetic-options-skill');
  Result.AddPair('skill_registered', TJSONBool.Create(False));
end;

end.
