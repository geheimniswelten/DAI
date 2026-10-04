unit h5u.DAI.OTA.Packages;

interface

uses System.JSON;

type
{$I DAI.PackageDispatch.Target.inc}

  // Only the final OTA boundary is replaced. No registry or BPL operation is performed.
  TDAIPackageService = class sealed
  public
    class var PrepareCalls, StatusCalls, InstallCalls, UninstallCalls, PreparePermissionCount: Integer;
    class var LastProject, LastFile: string;
    class var Target, LastTarget: TDAIPackageTarget;
    class var SdkSucceeded, RejectPrepare: Boolean;
    class procedure Reset; static;
    class function Prepare(const AProject, AFileName: string): TDAIPackageTarget; static;
    class function Status(const ATarget: TDAIPackageTarget): TJSONObject; static;
    class function Install(const ATarget: TDAIPackageTarget): TJSONObject; static;
    class function Uninstall(const ATarget: TDAIPackageTarget): TJSONObject; static;
  end;

implementation

uses System.SysUtils, h5u.DAI.Permissions.Manager;

function Response(const AAction: string; const ATarget: TDAIPackageTarget): TJSONObject;
begin
  TDAIPackageService.LastTarget := ATarget;
  Result := TJSONObject.Create;
  Result.AddPair('service_response', 'final-package-service-response');
  Result.AddPair('action', AAction);
  Result.AddPair('sdk_succeeded', TJSONBool.Create(TDAIPackageService.SdkSucceeded));
  Result.AddPair('package_file', ATarget.FileName);
  Result.AddPair('registered', TJSONNull.Create);
end;

class procedure TDAIPackageService.Reset;
begin
  PrepareCalls := 0;
  StatusCalls := 0;
  InstallCalls := 0;
  UninstallCalls := 0;
  PreparePermissionCount := -1;
  LastProject := '';
  LastFile := '';
  Target := Default(TDAIPackageTarget);
  LastTarget := Default(TDAIPackageTarget);
  SdkSucceeded := True;
  RejectPrepare := False;
end;

class function TDAIPackageService.Prepare(const AProject, AFileName: string): TDAIPackageTarget;
begin
  Inc(PrepareCalls);
  PreparePermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  LastProject := AProject;
  LastFile := AFileName;
  if RejectPrepare then
    raise EArgumentException.Create('No package target is available.');
  Result := Target;
end;

class function TDAIPackageService.Status(const ATarget: TDAIPackageTarget): TJSONObject;
begin
  Inc(StatusCalls);
  Result := Response('status', ATarget);
end;

class function TDAIPackageService.Install(const ATarget: TDAIPackageTarget): TJSONObject;
begin
  Inc(InstallCalls);
  Result := Response('install', ATarget);
end;

class function TDAIPackageService.Uninstall(const ATarget: TDAIPackageTarget): TJSONObject;
begin
  Inc(UninstallCalls);
  Result := Response('uninstall', ATarget);
end;

end.
