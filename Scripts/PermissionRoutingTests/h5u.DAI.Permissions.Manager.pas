unit h5u.DAI.Permissions.Manager;

interface

uses h5u.DAI.Types;

type
  TPermissionRequest = record
    Category: TDAIPermissionCategory;
    Resource, Operation: string;
    Context: TDAIRequestContext;
  end;

  TDAIPermissionManager = class
  private
    class var FInstance: TDAIPermissionManager;
  public
    GlobalAllowed, ProjectAllowed: Boolean;
    Requests: TArray<TPermissionRequest>;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset(const AGlobalAllowed, AProjectAllowed: Boolean);
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string; const AContext: TDAIRequestContext): Boolean;
  end;

implementation

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  Result := FInstance;
end;

procedure TDAIPermissionManager.Reset(const AGlobalAllowed, AProjectAllowed: Boolean);
begin
  GlobalAllowed := AGlobalAllowed;
  ProjectAllowed := AProjectAllowed;
  Requests := [];
end;

function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string; const AContext: TDAIRequestContext): Boolean;
var
  LIndex: Integer;
begin
  LIndex := Length(Requests);
  SetLength(Requests, LIndex + 1);
  Requests[LIndex].Category := ACategory;
  Requests[LIndex].Operation := AOperation;
  Requests[LIndex].Resource := AResource;
  Requests[LIndex].Context := AContext;
  if ACategory = pcReferenceRead then
    Exit(True);
  if AContext.ProjectKey = '' then
    Result := GlobalAllowed
  else
    Result := ProjectAllowed;
end;

initialization
  TDAIPermissionManager.FInstance := TDAIPermissionManager.Create;
finalization
  TDAIPermissionManager.FInstance.Free;
end.
