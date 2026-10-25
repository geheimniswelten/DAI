unit h5u.DAI.Settings;

interface

type
  TDAISettings = class sealed
  private
    class var FInstance: TDAISettings;
  public
    DelphiSourceDirectory: string;
    ToolsAPIDirectory: string;
    CatalogRepositoryDirectory: string;
    CatalogRepositoryAllUsersDirectory: string;
    class constructor Create;
    class destructor Destroy;
    class function Instance: TDAISettings; static;
  end;

implementation

class constructor TDAISettings.Create;
begin
  FInstance := TDAISettings.Create;
end;

class destructor TDAISettings.Destroy;
begin
  FInstance.Free;
end;

class function TDAISettings.Instance: TDAISettings;
begin
  Result := FInstance;
end;

end.
