unit h5u.DAI.Settings;

interface

type
  TDAISettings = class sealed
  private
    class var FInstance: TDAISettings;
  public
    CatalogRepositoryAllUsersDirectory: string;
    CatalogRepositoryDirectory: string;
    class function Instance: TDAISettings; static;
    function ExpandPath(const AFileName: string): string;
  end;

implementation

uses
  System.IOUtils;

class function TDAISettings.Instance: TDAISettings;
begin
  Result := FInstance;
end;

function TDAISettings.ExpandPath(const AFileName: string): string;
begin
  Result := TPath.GetFullPath(AFileName);
end;

initialization
  TDAISettings.FInstance := TDAISettings.Create;

finalization
  TDAISettings.FInstance.Free;

end.
