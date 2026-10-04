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
    DeniedRequestIndex: Integer;
    Requests: TArray<TPermissionRequest>;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset;
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
      const AContext: TDAIRequestContext): Boolean;
  end;

implementation

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  if not Assigned(FInstance) then
    FInstance := TDAIPermissionManager.Create;
  Result := FInstance;
end;

procedure TDAIPermissionManager.Reset;
begin
  DeniedRequestIndex := -1;
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
  Result := LIndex <> DeniedRequestIndex;
end;

initialization
  TDAIPermissionManager.FInstance := nil;

finalization
  TDAIPermissionManager.FInstance.Free;

end.
