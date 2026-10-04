unit h5u.DAI.OTA.PackageSummary;

interface

uses
  System.JSON;

type
  TDAIPackageSummarySnapshot = class sealed
  public
    class var RegisteredState, EnabledState, LoadedState: string;
    class var CreateCount, ToJsonCount: Integer;
    constructor Create;
    function ToJson(const AConfiguration: IInterface; const ATargetFile, AProjectDirectory: string): TJSONObject;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  h5u.DAI.OTA.Helpers;

function Truth(const AValue: string): TJSONValue;
begin
  if AValue = 'true' then
    Result := TJSONBool.Create(True)
  else if AValue = 'false' then
    Result := TJSONBool.Create(False)
  else
    Result := TJSONNull.Create;
end;

constructor TDAIPackageSummarySnapshot.Create;
begin
  inherited;
  if TDAIOTA.DispatchDepth = 0 then
    raise EInvalidOperation.Create('Snapshot must be captured on the IDE thread.');
  Inc(CreateCount);
end;

function TDAIPackageSummarySnapshot.ToJson(const AConfiguration: IInterface; const ATargetFile, AProjectDirectory: string): TJSONObject;
begin
  if TDAIOTA.DispatchDepth = 0 then
    raise EInvalidOperation.Create('Snapshot lookup must run on the IDE thread.');
  if Assigned(AConfiguration) or (AProjectDirectory <> '') then
    raise EInvalidOperation.Create('Package actions require a direct target status snapshot.');
  Inc(ToJsonCount);
  Result := TJSONObject.Create;
  Result.AddPair('registered', Truth(RegisteredState));
  Result.AddPair('enabled', Truth(EnabledState));
  Result.AddPair('loaded', Truth(LoadedState));
end;

end.
