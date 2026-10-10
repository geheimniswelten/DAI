unit h5u.DAI.Permissions.Manager;

interface

uses
  System.SysUtils,
  h5u.DAI.Types;

type
  TPermissionWrite = record
    Category: TDAIPermissionCategory;
    Level: TDAIPermissionLevel;
    ProjectKey: string;
    UseGlobal: Boolean;
  end;

  TDAIPermissionManager = class
  private
    class var FInstance: TDAIPermissionManager;
  public
    ReadCount: Integer;
    WriteCount: Integer;
    GlobalReadCount: Integer;
    ProjectReadCount: Integer;
    GlobalWriteCount: Integer;
    ProjectWriteCount: Integer;
    ResetCount: Integer;
    LastProjectKey: string;
    GlobalLevels: array[TDAIPermissionCategory] of TDAIPermissionLevel;
    ProjectLevels: array[TDAIPermissionCategory] of TDAIPermissionLevel;
    ProjectInherits: array[TDAIPermissionCategory] of Boolean;
    Writes: TArray<TPermissionWrite>;
    class function Instance: TDAIPermissionManager; static;
    class procedure Reset; static;
    function GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
    function GetLevelForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext;
      out AInheritsGlobal: Boolean): TDAIPermissionLevel;
    procedure SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
    procedure UseGlobalLevelFromOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext);
  end;

implementation

function TDAIPermissionManager.GetEffectiveLevel(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): TDAIPermissionLevel;
begin
  Inc(ReadCount);
  LastProjectKey := AContext.ProjectKey;
  if AContext.ProjectKey = '' then
  begin
    Inc(GlobalReadCount);
    Result := GlobalLevels[ACategory];
  end
  else
  begin
    Inc(ProjectReadCount);
    if ProjectInherits[ACategory] then
      Result := GlobalLevels[ACategory]
    else
      Result := ProjectLevels[ACategory];
  end;
end;

function TDAIPermissionManager.GetLevelForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext;
  out AInheritsGlobal: Boolean): TDAIPermissionLevel;
begin
  Result := GetEffectiveLevel(ACategory, AContext);
  AInheritsGlobal := (AContext.ProjectKey <> '') and ProjectInherits[ACategory];
end;

class function TDAIPermissionManager.Instance: TDAIPermissionManager;
begin
  Result := FInstance;
end;

class procedure TDAIPermissionManager.Reset;
var
  LCategory: TDAIPermissionCategory;
begin
  FInstance.ReadCount := 0;
  FInstance.WriteCount := 0;
  FInstance.GlobalReadCount := 0;
  FInstance.ProjectReadCount := 0;
  FInstance.GlobalWriteCount := 0;
  FInstance.ProjectWriteCount := 0;
  FInstance.ResetCount := 0;
  FInstance.LastProjectKey := '';
  SetLength(FInstance.Writes, 0);
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
  begin
    FInstance.GlobalLevels[LCategory] := plAsk;
    FInstance.ProjectLevels[LCategory] := plAsk;
    FInstance.ProjectInherits[LCategory] := True;
  end;
end;

procedure TDAIPermissionManager.SetLevelFromOptions(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel; const AContext: TDAIRequestContext);
begin
  Inc(WriteCount);
  SetLength(Writes, WriteCount);
  Writes[WriteCount - 1].Category := ACategory;
  Writes[WriteCount - 1].Level := ALevel;
  Writes[WriteCount - 1].ProjectKey := AContext.ProjectKey;
  Writes[WriteCount - 1].UseGlobal := False;
  if AContext.ProjectKey = '' then
  begin
    Inc(GlobalWriteCount);
    GlobalLevels[ACategory] := ALevel;
  end
  else
  begin
    Inc(ProjectWriteCount);
    ProjectLevels[ACategory] := ALevel;
    ProjectInherits[ACategory] := False;
  end;
end;

procedure TDAIPermissionManager.UseGlobalLevelFromOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext);
begin
  if AContext.ProjectKey = '' then
    raise Exception.Create('Synthetic reset requires a project key');
  Inc(WriteCount);
  Inc(ProjectWriteCount);
  Inc(ResetCount);
  SetLength(Writes, WriteCount);
  Writes[WriteCount - 1].Category := ACategory;
  Writes[WriteCount - 1].Level := GlobalLevels[ACategory];
  Writes[WriteCount - 1].ProjectKey := AContext.ProjectKey;
  Writes[WriteCount - 1].UseGlobal := True;
  ProjectInherits[ACategory] := True;
end;

initialization
  TDAIPermissionManager.FInstance := TDAIPermissionManager.Create;

finalization
  TDAIPermissionManager.FInstance.Free;

end.
