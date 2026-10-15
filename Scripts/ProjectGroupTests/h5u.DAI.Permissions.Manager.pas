unit h5u.DAI.Permissions.Manager;

interface

type
  TDAIPermissionManager = class
  private
    class var FInstance: TDAIPermissionManager;
  public
    class function Instance: TDAIPermissionManager; static;
    class destructor Finalize;
    procedure ClearProjectSession(const AProject: string);
  end;

implementation

class destructor TDAIPermissionManager.Finalize;
begin
  FInstance.Free;
end;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  if FInstance = nil then
    FInstance := TDAIPermissionManager.Create;
  Result := FInstance;
end;

procedure TDAIPermissionManager.ClearProjectSession(const AProject: string);
begin
end;

end.
