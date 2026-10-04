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
    ReadAllowed: Boolean;
    EditAllowed: Boolean;
    DeniedProjectKey: string;
    Requests: TArray<TPermissionRequest>;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset(const AReadAllowed, AEditAllowed: Boolean);
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
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

procedure TDAIPermissionManager.Reset(const AReadAllowed, AEditAllowed: Boolean);
begin
  ReadAllowed := AReadAllowed;
  EditAllowed := AEditAllowed;
  DeniedProjectKey := '';
  Requests := nil;
end;

function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
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
    pcReadAccess:
      Result := ReadAllowed and ((DeniedProjectKey = '') or not SameText(AContext.ProjectKey, DeniedProjectKey));
    pcEditInsideIDE:
      Result := EditAllowed;
  else
    raise EInvalidOperation.Create('Unexpected permission category in project-options dispatch fixture.');
  end;
end;

initialization
  TDAIPermissionManager.FInstance := nil;

finalization
  TDAIPermissionManager.FInstance.Free;

end.
