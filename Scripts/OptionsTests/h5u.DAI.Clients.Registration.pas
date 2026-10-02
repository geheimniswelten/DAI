unit h5u.DAI.Clients.Registration;

interface

uses
  System.JSON;

type
  TDAIClientRegistration = class sealed
  public
    class var RegisterCount: Integer;
    class var UnregisterCount: Integer;
    class var StatusCount: Integer;
    class var StatusJSON: string;
    class function Status(const AClient: string): TJSONObject; static;
    class function RegisterFiles(const AClient: string): TJSONObject; static;
    class function UnregisterFiles(const AClient: string): TJSONObject; static;
  end;

implementation

class function TDAIClientRegistration.RegisterFiles(const AClient: string): TJSONObject;
begin
  Inc(RegisterCount);
  Result := Status(AClient);
end;

class function TDAIClientRegistration.Status(const AClient: string): TJSONObject;
begin
  Inc(StatusCount);
  if StatusJSON <> '' then
    Exit(TJSONObject.ParseJSONValue(StatusJSON) as TJSONObject);
  Result := TJSONObject.Create;
  Result.AddPair('clients', TJSONArray.Create);
end;

class function TDAIClientRegistration.UnregisterFiles(const AClient: string): TJSONObject;
begin
  Inc(UnregisterCount);
  Result := Status(AClient);
end;

end.
