unit h5u.DAI.Permissions.Manager;

interface

type
  TDAIPermissionManager = class
  private
    class var FInstance: TDAIPermissionManager;
  public
    class var ClearCount: Integer;
    class var Version: Integer;
    class var SummaryCount: Integer;
    class var IDESummary: string;
    class var ProjectSummary: string;
    class var LastProjectKey: string;
    class function Instance: TDAIPermissionManager; static;
    class function ChangeVersion: Integer; static;
    class procedure Reset; static;
    function GetAccessSummary(const AProjectKey: string; const AForIDE: Boolean): string;
    procedure ClearAllSessions;
  end;

implementation

uses
  System.SysUtils;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  if not Assigned(FInstance) then
    FInstance := TDAIPermissionManager.Create;
  Result := FInstance;
end;

procedure TDAIPermissionManager.ClearAllSessions;
begin
  Inc(ClearCount);
  Inc(Version);
  IDESummary := 'lesen';
  ProjectSummary := 'nachfragen';
end;

class function TDAIPermissionManager.ChangeVersion: Integer;
begin
  Result := Version;
end;

class procedure TDAIPermissionManager.Reset;
begin
  ClearCount := 0;
  Version := 0;
  SummaryCount := 0;
  IDESummary := 'lesen';
  ProjectSummary := 'lesen';
  LastProjectKey := '';
end;

function TDAIPermissionManager.GetAccessSummary(const AProjectKey: string; const AForIDE: Boolean): string;
begin
  Inc(SummaryCount);
  if AForIDE then
    Exit(IDESummary);
  LastProjectKey := AProjectKey;
  if AProjectKey = '' then
    Exit('kein Projekt');
  Result := ProjectSummary;
end;

initialization

finalization
  FreeAndNil(TDAIPermissionManager.FInstance);

end.
