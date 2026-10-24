unit h5u.DAI.Settings;

interface

type
  TDAISettings = class
  private
    class var FInstance: TDAISettings;
  private
    FManualClientRegistration: Boolean;
    function GetManualClientRegistration: Boolean;
  public
    Port: Integer;
    RaiseManualRead: Boolean;
    property ManualClientRegistration: Boolean read GetManualClientRegistration write FManualClientRegistration;
    class function Instance: TDAISettings; static;
  end;

implementation

uses
  System.SysUtils;

function TDAISettings.GetManualClientRegistration: Boolean;
begin
  if RaiseManualRead then
    raise Exception.Create('synthetic manual confirmation read failure');
  Result := FManualClientRegistration;
end;

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
