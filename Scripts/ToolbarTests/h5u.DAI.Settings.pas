unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  public
    Port: Integer;
    class function Instance: TDAISettings; static;
  end;

implementation

uses
  System.SysUtils;

class function TDAISettings.Instance: TDAISettings;
begin
  if not Assigned(FInstance) then
  begin
    FInstance := TDAISettings.Create;
    FInstance.Port := 7331;
  end;
  Result := FInstance;
end;

initialization

finalization
  FreeAndNil(TDAISettings.FInstance);

end.
