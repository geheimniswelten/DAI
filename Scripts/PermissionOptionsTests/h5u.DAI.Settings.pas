unit h5u.DAI.Settings;

interface

type
  TDAISettings = class sealed
  private
    class var FInstance: TDAISettings;
  public
    RegistryRoot: string;
    class constructor Initialize;
    class destructor Finalize;
    class function Instance: TDAISettings; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils;

class constructor TDAISettings.Initialize;
var
  LGuid: TGUID;
begin
  FInstance := TDAISettings.Create;
  CreateGUID(LGuid);
  FInstance.RegistryRoot := 'Software\DAI\PermissionOptionsTests\' + GUIDToString(LGuid);
end;

class destructor TDAISettings.Finalize;
begin
  FInstance.Free;
end;

class function TDAISettings.Instance: TDAISettings;
begin
  if not FInstance.RegistryRoot.StartsWith('Software\DAI\PermissionOptionsTests\') then
    raise EInvalidOperation.Create('The isolated permission test registry root has not been initialized.');
  Result := FInstance;
end;

end.
