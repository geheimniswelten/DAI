unit h5u.DAI.Permissions.Manager;

interface

uses
  h5u.DAI.Types;

type
  TPermissionRequest = record
    Category: TDAIPermissionCategory;
    Operation: string;
    Resource: string;
    Context: TDAIRequestContext;
  end;

  TDAIPermissionManager = class sealed
  private
    class var FInstance: TDAIPermissionManager;
  public
    EditAllowed: Boolean;
    ExecuteAllowed: Boolean;
    Requests: TArray<TPermissionRequest>;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset(const AEditAllowed: Boolean; const AExecuteAllowed: Boolean);
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string;
      const AContext: TDAIRequestContext): Boolean;
  end;

implementation

uses
  System.Classes,
  System.SysUtils;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  if not Assigned(FInstance) then
    FInstance := TDAIPermissionManager.Create;
  Result := FInstance;
end;

procedure TDAIPermissionManager.Reset(const AEditAllowed: Boolean; const AExecuteAllowed: Boolean);
begin
  EditAllowed := AEditAllowed;
  ExecuteAllowed := AExecuteAllowed;
  Requests := nil;
end;

function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string;
  const AContext: TDAIRequestContext): Boolean;
var
  LIndex: Integer;
begin
  LIndex := Length(Requests);
  SetLength(Requests, LIndex + 1);
  Requests[LIndex].Category := ACategory;
  Requests[LIndex].Operation := AOperation;
  Requests[LIndex].Resource := AResource;
  Requests[LIndex].Context := AContext;
  case ACategory of
    pcEditInsideIDE:
      Result := EditAllowed;
    pcExecute:
      Result := ExecuteAllowed;
  else
    raise EInvalidOperation.Create('Unerwartete Berechtigung im Fenster-Dispatch-Test.');
  end;
end;

initialization
  TDAIPermissionManager.FInstance := nil;

finalization
  TDAIPermissionManager.FInstance.Free;

end.
