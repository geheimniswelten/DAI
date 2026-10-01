unit h5u.DAI.Permissions.Manager;

interface

uses
  h5u.DAI.Types;

type
  TDAIPermissionManager = class
  private
    class var FInstance: TDAIPermissionManager;
  public
    ReadCount: Integer;
    WriteCount: Integer;
    LastProjectKey: string;
    class function Instance: TDAIPermissionManager; static;
    class procedure Reset; static;
    function GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
    procedure SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
  end;

implementation

function TDAIPermissionManager.GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
begin
  Inc(ReadCount);
  LastProjectKey := AContext.ProjectKey;
  Result := plAsk;
end;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  Result := FInstance;
end;

class procedure TDAIPermissionManager.Reset;
begin
  FInstance.ReadCount := 0;
  FInstance.WriteCount := 0;
  FInstance.LastProjectKey := '';
end;

procedure TDAIPermissionManager.SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
begin
  Inc(WriteCount);
end;

initialization
  TDAIPermissionManager.FInstance := TDAIPermissionManager.Create;

finalization
  TDAIPermissionManager.FInstance.Free;

end.
