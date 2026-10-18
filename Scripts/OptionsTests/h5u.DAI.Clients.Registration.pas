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
    class var FindCount: Integer;
    class var RemoveFoundCount: Integer;
    class var FindJSON: string;
    class var RemoveJSON: string;
    class var LastRemovedServer: string;
    class var LastFindClient: string;
    class function Status(const AClient: string): TJSONObject; static;
    class function RegisterFiles(const AClient: string): TJSONObject; static;
    class function UnregisterFiles(const AClient: string): TJSONObject; static;
    class function FindRegistrations(const AClient: string): TJSONObject; static;
    class function RemoveFoundRegistration(const ACandidate: TJSONObject): TJSONObject; static;
  end;

implementation

class function TDAIClientRegistration.FindRegistrations(const AClient: string): TJSONObject;
begin
  Inc(FindCount);
  LastFindClient := AClient;
  if FindJSON <> '' then
    Exit(TJSONObject.ParseJSONValue(FindJSON) as TJSONObject);
  Result := TJSONObject.Create;
  Result.AddPair('registrations', TJSONArray.Create);
end;

class function TDAIClientRegistration.RemoveFoundRegistration(const ACandidate: TJSONObject): TJSONObject;
begin
  Inc(RemoveFoundCount);
  LastRemovedServer := ACandidate.GetValue<string>('server_name', '');
  if RemoveJSON <> '' then
    Exit(TJSONObject.ParseJSONValue(RemoveJSON) as TJSONObject);
  Result := TJSONObject.Create;
  Result.AddPair('removed', TJSONBool.Create(True));
  Result.AddPair('message', 'Die ausgewählte Registrierung wurde entfernt.');
end;

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
