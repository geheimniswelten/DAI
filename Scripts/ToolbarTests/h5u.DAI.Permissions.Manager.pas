unit h5u.DAI.Permissions.Manager;

interface

type
  TDAIPermissionManager = class
  private
    class var FInstance: TDAIPermissionManager;
  public
    class var ClearCount: Integer;
    class function Instance: TDAIPermissionManager; static;
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
end;

initialization

finalization
  FreeAndNil(TDAIPermissionManager.FInstance);

end.
