unit h5u.DAI.Clients.Registration;

interface

type
  TDAIRegistrationHealth = (rhNotRegistered, rhCurrent, rhUpdateRecommended, rhCheckRecommended);

  TDAIClientRegistration = class sealed
  public
    class var HealthState: TDAIRegistrationHealth;
    class var HealthDetails: string;
    class var HealthCount: Integer;
    class var Version: Integer;
    class var RaiseHealth: Boolean;
    class function Health(out ADetails: string): TDAIRegistrationHealth; static;
    class function ChangeVersion: Integer; static;
    class procedure Reset; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils;

class function TDAIClientRegistration.Health(out ADetails: string): TDAIRegistrationHealth;
begin
  Inc(HealthCount);
  if RaiseHealth then
    raise EInvalidOperation.Create('isolated registration read failure');
  ADetails := HealthDetails;
  Result := HealthState;
end;

class function TDAIClientRegistration.ChangeVersion: Integer;
begin
  Result := Version;
end;

class procedure TDAIClientRegistration.Reset;
begin
  HealthState := rhCurrent;
  HealthDetails := '';
  HealthCount := 0;
  Version := 0;
  RaiseHealth := False;
end;

initialization
  TDAIClientRegistration.Reset;

end.
