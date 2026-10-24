unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    CustomReadDirectoriesAlwaysAllowed: Boolean;
    class function Instance: TDAISettings; static;
    function ExpandPath(const APath: string): string;
  end;

implementation

uses System.IOUtils;

class function TDAISettings.Instance: TDAISettings;
begin
  Result := FInstance;
end;

function TDAISettings.ExpandPath(const APath: string): string;
begin
  Result := TPath.GetFullPath(APath);
end;

initialization
  TDAISettings.FInstance := TDAISettings.Create;
finalization
  TDAISettings.FInstance.Free;
end.
