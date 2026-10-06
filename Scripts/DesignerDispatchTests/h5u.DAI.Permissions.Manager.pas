unit h5u.DAI.Permissions.Manager;
interface
uses h5u.DAI.Types;
type
  TPermissionRequest = record
    Category: TDAIPermissionCategory;
    Operation, Resource: string;
    Context: TDAIRequestContext;
  end;
  TDAIPermissionManager = class sealed
  private
    class var FInstance: TDAIPermissionManager;
  public
    ReadAllowed, EditAllowed: Boolean;
    Requests: TArray<TPermissionRequest>;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset(const AReadAllowed: Boolean = True; const AEditAllowed: Boolean = True);
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
      const AContext: TDAIRequestContext): Boolean;
  end;
implementation
uses System.Classes, System.SysUtils;
class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin if FInstance = nil then FInstance := TDAIPermissionManager.Create; Result := FInstance; end;
procedure TDAIPermissionManager.Reset(const AReadAllowed, AEditAllowed: Boolean);
begin ReadAllowed := AReadAllowed; EditAllowed := AEditAllowed; Requests := nil; end;
function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
  const AContext: TDAIRequestContext): Boolean;
var I: Integer;
begin
  I := Length(Requests); SetLength(Requests, I + 1);
  Requests[I].Category := ACategory; Requests[I].Operation := AOperation;
  Requests[I].Resource := AResource; Requests[I].Context := AContext;
  case ACategory of
    pcReadAccess: Result := ReadAllowed;
    pcEditInsideIDE: Result := EditAllowed;
  else raise EInvalidOperation.Create('Unexpected designer permission category.');
  end;
end;
initialization
  TDAIPermissionManager.FInstance := nil;
finalization
  TDAIPermissionManager.FInstance.Free;
end.
