unit h5u.DAI.Permissions.Manager;

interface

uses h5u.DAI.Types;

type
  TDAIPermissionManager = class sealed
  private
    class var FInstance: TDAIPermissionManager;
  public
    Requests: TArray<TDAIPermissionCategory>;
    class function Instance: TDAIPermissionManager; static;
    procedure Reset;
    function GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
    function Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string; const AContext: TDAIRequestContext): Boolean;
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
  Requests := nil;
end;

function TDAIPermissionManager.GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
begin
  if ACategory = pcReferenceRead then
    Result := plAlways
  else
    Result := plNever;
end;

function TDAIPermissionManager.Authorize(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
  const AContext: TDAIRequestContext): Boolean;
begin
  SetLength(Requests, Length(Requests) + 1);
  Requests[High(Requests)] := ACategory;
  Result := ACategory = pcReferenceRead;
end;

initialization

finalization
  TDAIPermissionManager.FInstance.Free;

end.
