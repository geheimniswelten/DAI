unit h5u.DAI.Permissions.Store;

interface

uses
  h5u.DAI.Types;

type
  TDAIPermissionStore = class sealed
  public
    class function GetLevel(const ACategory: TDAIPermissionCategory; const AProjectFileName: string): TDAIPermissionLevel; static;
    class procedure SetLevel(const ACategory: TDAIPermissionCategory; const AProjectFileName: string; const ALevel: TDAIPermissionLevel); static;
    class function ProjectSettingsFileName(const AProjectFileName: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  h5u.DAI.Settings;

function ReadJsonObject(const AFileName: string): TJSONObject;
var
  LJson: TJSONValue;
begin
  Result := nil;
  if not TFile.Exists(AFileName) then
    Exit;

  try
    LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
    if LJson is TJSONObject then
      Result := TJSONObject(LJson)
    else
      LJson.Free;
  except
    Result := nil;
  end;
end;

function ReadProjectLevel(const ACategory: TDAIPermissionCategory; const AProjectFileName: string): TDAIPermissionLevel;
var
  LFileName: string;
  LJsonValue: TJSONValue;
  LPermissions: TJSONObject;
  LRoot: TJSONObject;
  LValue: string;
begin
  Result := plAsk;
  LFileName := TDAIPermissionStore.ProjectSettingsFileName(AProjectFileName);
  LRoot := ReadJsonObject(LFileName);
  try
    if not Assigned(LRoot) then
      Exit;
    LJsonValue := LRoot.GetValue('permissions');
    if not (LJsonValue is TJSONObject) then
      Exit;
    LPermissions := TJSONObject(LJsonValue);
    LValue := LPermissions.GetValue<string>(DAIPermissionCategoryKey(ACategory), 'ask');
    Result := DAIPermissionLevelFromKey(LValue);
    if not (Result in [plNever, plAsk, plAlways]) then
      Result := plAsk;
  finally
    LRoot.Free;
  end;
end;

function ReadGlobalLevel(const ACategory: TDAIPermissionCategory): TDAIPermissionLevel;
var
  LKey: string;
  LRegistry: TRegistry;
begin
  Result := plAsk;
  LKey := TDAISettings.Instance.RegistryRoot + '\Permissions';
  LRegistry := TRegistry.Create(KEY_READ);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKeyReadOnly(LKey) then
      Exit;
    if LRegistry.ValueExists(DAIPermissionCategoryKey(ACategory)) then
      Result := DAIPermissionLevelFromKey(LRegistry.ReadString(DAIPermissionCategoryKey(ACategory)));
    if not (Result in [plNever, plAsk, plAlways]) then
      Result := plAsk;
  finally
    LRegistry.Free;
  end;
end;

procedure WriteGlobalLevel(const ACategory: TDAIPermissionCategory; const ALevel: TDAIPermissionLevel);
var
  LKey: string;
  LRegistry: TRegistry;
begin
  LKey := TDAISettings.Instance.RegistryRoot + '\Permissions';
  LRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    if not LRegistry.OpenKey(LKey, True) then
      RaiseLastOSError;
    LRegistry.WriteString(DAIPermissionCategoryKey(ACategory), DAIPermissionLevelKey(ALevel));
  finally
    LRegistry.Free;
  end;
end;

procedure WriteProjectLevel(const ACategory: TDAIPermissionCategory; const AProjectFileName: string; const ALevel: TDAIPermissionLevel);
var
  LFileName: string;
  LJsonValue: TJSONValue;
  LPermissions: TJSONObject;
  LRoot: TJSONObject;
begin
  LFileName := TDAIPermissionStore.ProjectSettingsFileName(AProjectFileName);
  if LFileName = '' then
    Exit;

  LRoot := ReadJsonObject(LFileName);
  if not Assigned(LRoot) then
    LRoot := TJSONObject.Create;
  try
    LRoot.RemovePair('version').Free;
    LRoot.AddPair('version', TJSONNumber.Create(1));

    LJsonValue := LRoot.GetValue('permissions');
    if LJsonValue is TJSONObject then
      LPermissions := TJSONObject(LJsonValue)
    else
    begin
      LPermissions := TJSONObject.Create;
      LRoot.AddPair('permissions', LPermissions);
    end;

    LPermissions.RemovePair(DAIPermissionCategoryKey(ACategory)).Free;
    LPermissions.AddPair(DAIPermissionCategoryKey(ACategory), DAIPermissionLevelKey(ALevel));

    ForceDirectories(TPath.GetDirectoryName(LFileName));
    TFile.WriteAllText(LFileName, LRoot.Format(2), TEncoding.UTF8);
  finally
    LRoot.Free;
  end;
end;

class function TDAIPermissionStore.GetLevel(const ACategory: TDAIPermissionCategory; const AProjectFileName: string): TDAIPermissionLevel;
begin
  if Trim(AProjectFileName) <> '' then
  begin
    Result := ReadProjectLevel(ACategory, AProjectFileName);
    if Result <> plAsk then
      Exit;
  end;
  Result := ReadGlobalLevel(ACategory);
end;

class function TDAIPermissionStore.ProjectSettingsFileName(const AProjectFileName: string): string;
begin
  if Trim(AProjectFileName) = '' then
    Exit('');
  Result := ChangeFileExt(TPath.GetFullPath(AProjectFileName), '.dai.permissions.json');
end;

class procedure TDAIPermissionStore.SetLevel(const ACategory: TDAIPermissionCategory; const AProjectFileName: string; const ALevel: TDAIPermissionLevel);
var
  LPersistedLevel: TDAIPermissionLevel;
begin
  LPersistedLevel := ALevel;
  if not (LPersistedLevel in [plNever, plAsk, plAlways]) then
    LPersistedLevel := plAsk;

  if Trim(AProjectFileName) = '' then
    WriteGlobalLevel(ACategory, LPersistedLevel)
  else
    WriteProjectLevel(ACategory, AProjectFileName, LPersistedLevel);
end;

end.
