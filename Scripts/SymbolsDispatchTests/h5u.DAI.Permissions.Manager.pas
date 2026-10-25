unit h5u.DAI.Permissions.Manager;

interface

uses
  System.SysUtils,
  h5u.DAI.Types;

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
    DeniedProject: string;
    DeniedCategory: TDAIPermissionCategory;
    Requests: TArray<TPermissionRequest>;
    OnAuthorize: TProc;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset;
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
      const AContext: TDAIRequestContext): Boolean;
  end;

implementation

uses System.Classes;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  if not Assigned(FInstance) then
    FInstance := TDAIPermissionManager.Create;
  Result := FInstance;
end;

procedure TDAIPermissionManager.Reset;
begin
  ReadAllowed := True;
  EditAllowed := True;
  DeniedProject := '';
  DeniedCategory := pcProjectRead;
  Requests := nil;
  OnAuthorize := nil;
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
    pcReferenceRead: Result := True;
    pcProjectRead: Result := ReadAllowed;
    pcIDEOptions, pcProjectWrite: Result := EditAllowed;
  else
    raise EInvalidOperation.Create('Unexpected permission category in index dispatch fixture.');
  end;
  if (DeniedProject <> '') and (DeniedProject = AContext.ProjectKey) and (DeniedCategory = ACategory) then
    Result := False;
  if Assigned(OnAuthorize) then
    OnAuthorize();
end;

initialization

finalization
  TDAIPermissionManager.FInstance.Free;

end.
