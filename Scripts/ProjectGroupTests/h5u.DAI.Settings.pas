unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    class function Instance: TDAISettings; static;
    class destructor Finalize;
    function ExpandPath(const APath: string): string;
  end;

implementation

uses System.IOUtils, System.SysUtils;

class destructor TDAISettings.Finalize;
begin
  FInstance.Free;
end;

class function TDAISettings.Instance: TDAISettings;
begin
  if FInstance = nil then
    FInstance := TDAISettings.Create;
  Result := FInstance;
end;

function TDAISettings.ExpandPath(const APath: string): string;
begin
  if Trim(APath) = '' then
    Exit('');
  Result := TPath.GetFullPath(APath);
end;

end.
