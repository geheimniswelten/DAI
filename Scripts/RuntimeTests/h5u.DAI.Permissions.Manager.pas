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
  DAI.Runtime.TestState;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  if not Assigned(FInstance) then
    FInstance := TDAIPermissionManager.Create;
  Result := FInstance;
end;

procedure TDAIPermissionManager.ClearAllSessions;
begin
  Inc(ClearCount);
  Events.Add('permissions-clear');
end;

initialization

finalization
  TDAIPermissionManager.FInstance.Free;

end.
