unit h5u.DAI.OTA.PackageSummary;

interface

uses
  System.JSON,
  ToolsAPI;

type
  TDAIPackageSummarySnapshot = class
  public
    class var CreateCount, FreeCount, ToJsonCount: Integer;
    constructor Create;
    destructor Destroy; override;
    function ToJson(const AConfiguration: IOTABuildConfiguration; const ATargetFile, AProjectDirectory: string): TJSONObject;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  h5u.DAI.OTA.Helpers;

constructor TDAIPackageSummarySnapshot.Create;
begin
  inherited Create;
  if TDAIOTA.DispatchDepth = 0 then
    raise EInvalidOperation.Create('Package state must be captured on the IDE thread.');
  Inc(CreateCount);
end;

destructor TDAIPackageSummarySnapshot.Destroy;
begin
  Inc(FreeCount);
  inherited;
end;

function TDAIPackageSummarySnapshot.ToJson(const AConfiguration: IOTABuildConfiguration; const ATargetFile, AProjectDirectory: string): TJSONObject;
begin
  Inc(ToJsonCount);
  Result := TJSONObject.Create;
  if Assigned(AConfiguration) then
  begin
    Result.AddPair('configuration_key', AConfiguration.Key);
    Result.AddPair('configuration_platform', AConfiguration.Platform);
  end
  else
  begin
    Result.AddPair('configuration_key', TJSONNull.Create);
    Result.AddPair('configuration_platform', TJSONNull.Create);
  end;
  Result.AddPair('target_file', ATargetFile);
  Result.AddPair('project_directory', AProjectDirectory);
end;

end.
