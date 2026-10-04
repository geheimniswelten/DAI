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
    RejectGlobalRead, RejectGlobalExecute: Boolean;
    Requests: TArray<TPermissionRequest>;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset;
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
      const AContext: TDAIRequestContext): Boolean;
  end;
implementation
uses DAI.ExpressionDispatch.TestState;
class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin if FInstance = nil then FInstance := TDAIPermissionManager.Create; Result := FInstance; end;
procedure TDAIPermissionManager.Reset;
begin DeniedRequestIndex := -1; RejectGlobalRead := False; RejectGlobalExecute := False; Requests := nil; end;
function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
  const AContext: TDAIRequestContext): Boolean;
var LIndex: Integer;
begin
  LIndex := Length(Requests); SetLength(Requests, LIndex + 1);
  Requests[LIndex].Category := ACategory; Requests[LIndex].Operation := AOperation;
  Requests[LIndex].Resource := AResource; Requests[LIndex].Context := AContext;
  RecordEvent('permission:' + DAIPermissionCategoryKey(ACategory));
  if SwitchFileDuringPermission then CurrentFile := 'C:\Unauthorized\Other.pas';
  if SwitchDebugDuringPermission then begin CurrentProcessId := 9999; CurrentThreadId := 777; end;
  Result := LIndex <> DeniedRequestIndex;
  if AContext.ProjectKey = '' then
  begin
    if RejectGlobalRead and (ACategory = pcReadAccess) then Result := False;
    if RejectGlobalExecute and (ACategory = pcExecute) then Result := False;
  end;
end;
initialization
  TDAIPermissionManager.FInstance := nil;
finalization
  TDAIPermissionManager.FInstance.Free;
end.
