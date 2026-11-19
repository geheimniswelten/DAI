unit h5u.DAI.OTA.ProjectResources.Live;

interface

uses
  System.Classes,
  ToolsAPI;

type
  EDAIRcItemBackendUnavailable = class(EInvalidOperation);

  TDAIProjectResource = record
    FileName: string;
    ResourceType: string;
    ResourceId: string;
  end;

  TDAIProjectResourceBackend = class sealed
  public
    class function List(const AProject: IOTAProject): TArray<TDAIProjectResource>; static;
    class function Add(const AProject: IOTAProject; const AFileName, AResourceType, AResourceId: string): TDAIProjectResource; static;
    class function Update(const AProject: IOTAProject; const AResourceType, AResourceId, ANewFileName, ANewResourceType, ANewResourceId: string): TDAIProjectResource; static;
    class function Remove(const AProject: IOTAProject; const AResourceType, AResourceId: string): TDAIProjectResource; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  h5u.DAI.OTA.Helpers;

const
  CModuleInfoClass = 'BaseDelphiProject.TOTAModuleInfo';
  CFileEntryClass = 'CodeMgr.TCustomFileEntry';
  CResourceEntryClass = 'ResourceItemContainer.TResourceItemFileEntry';

type
  TResourceEntry = record
    Native: TObject;
    Resource: TDAIProjectResource;
  end;

  // Module enumeration and AddFile/RemoveFile are public OTA.
  // RcItem properties have no public OTA accessor. Validate the existing IDE
  // model's RTTI contract before reading or writing it. No VMT offsets or
  // decorated exports are used, and properties are invoked via their setters.
  TResourceModel = record
    Context: TRttiContext;
    function Entries(const AProject: IOTAProject): TArray<TResourceEntry>;
    function NativeEntry(const AModuleInfo: IOTAModuleInfo): TObject;
    procedure SetValues(const AEntry: TResourceEntry; const AValue: TDAIProjectResource);
  end;

procedure BackendUnavailable(const AReason: string);
begin
  raise EDAIRcItemBackendUnavailable.CreateFmt('Das native Delphi-Ressourcenmodell ist nicht verfügbar: %s.', [AReason]);
end;

function RequireStringProperty(const AType: TRttiType; const AName: string): TRttiProperty;
begin
  Result := AType.GetProperty(AName);
  if not Assigned(Result) then
    BackendUnavailable(AType.QualifiedName + '.' + AName);
  if not Result.IsReadable or not Result.IsWritable or not Assigned(Result.PropertyType) then
    BackendUnavailable(AType.QualifiedName + '.' + AName);
  if Result.PropertyType.TypeKind <> tkUString then
    BackendUnavailable(AType.QualifiedName + '.' + AName);
end;

function TResourceModel.NativeEntry(const AModuleInfo: IOTAModuleInfo): TObject;
var
  LModuleObject: TObject;
  LEntryField: TRttiField;
begin
  if not Assigned(AModuleInfo) then
    BackendUnavailable('ein Projektmodul ist nicht verfügbar');
  LModuleObject := nil;
  try
    LModuleObject := AModuleInfo as TObject;
  except
    on E: EInvalidCast do
      BackendUnavailable('unbekannter IDE-Projektmoduleintrag');
  end;
  if not Assigned(LModuleObject) then
    BackendUnavailable('unbekannter IDE-Projektmoduleintrag');
  if not SameText(LModuleObject.QualifiedClassName, CModuleInfoClass) then
    BackendUnavailable('unbekannter IDE-Projektmoduleintrag');

  LEntryField := Context.GetType(LModuleObject.ClassType).GetField('FUsesEntry');
  if not Assigned(LEntryField) then
    BackendUnavailable(CModuleInfoClass + '.FUsesEntry');
  if not Assigned(LEntryField.FieldType) then
    BackendUnavailable(CModuleInfoClass + '.FUsesEntry');
  if (LEntryField.FieldType.TypeKind <> tkClass) or not SameText(LEntryField.FieldType.QualifiedName, CFileEntryClass) then
    BackendUnavailable(CModuleInfoClass + '.FUsesEntry');

  Result := LEntryField.GetValue(LModuleObject).AsObject;
  if not Assigned(Result) then
    BackendUnavailable('ein Projektdateieintrag ist nicht verfügbar');
end;


function TResourceModel.Entries(const AProject: IOTAProject): TArray<TResourceEntry>;
var
  LIndex: Integer;
  LModuleInfo: IOTAModuleInfo;
  LNativeType: TRttiType;
  LEntry: TResourceEntry;
  LEntries: TList<TResourceEntry>;
begin
  LEntries := TList<TResourceEntry>.Create;
  try
    for LIndex := 0 to AProject.GetModuleCount - 1 do
    begin
      LModuleInfo := AProject.GetModule(LIndex);
      LEntry.Native := NativeEntry(LModuleInfo);
      if not SameText(LEntry.Native.QualifiedClassName, CResourceEntryClass) then
        Continue;

      LNativeType := Context.GetType(LEntry.Native.ClassType);
      LEntry.Resource.FileName := RequireStringProperty(LNativeType, 'FileName').GetValue(LEntry.Native).AsString;
      LEntry.Resource.ResourceType := RequireStringProperty(LNativeType, 'ResourceType').GetValue(LEntry.Native).AsString;
      LEntry.Resource.ResourceId := RequireStringProperty(LNativeType, 'ResourceId').GetValue(LEntry.Native).AsString;
      if not TDAIOTA.SameFile(LEntry.Resource.FileName, LModuleInfo.FileName) then
        BackendUnavailable('abweichender Ressourcenpfad im IDE-Modell');
      LEntries.Add(LEntry);
    end;
    Result := LEntries.ToArray;
  finally
    LEntries.Free;
  end;
end;

procedure TResourceModel.SetValues(const AEntry: TResourceEntry; const AValue: TDAIProjectResource);
var
  LType: TRttiType;
  LFileName, LResourceType, LResourceId: TRttiProperty;
begin
  LType := Context.GetType(AEntry.Native.ClassType);
  LFileName := RequireStringProperty(LType, 'FileName');
  LResourceType := RequireStringProperty(LType, 'ResourceType');
  LResourceId := RequireStringProperty(LType, 'ResourceId');
  if LFileName.GetValue(AEntry.Native).AsString <> AValue.FileName then
    LFileName.SetValue(AEntry.Native, TValue.From<string>(AValue.FileName));
  if LResourceType.GetValue(AEntry.Native).AsString <> AValue.ResourceType then
    LResourceType.SetValue(AEntry.Native, TValue.From<string>(AValue.ResourceType));
  if LResourceId.GetValue(AEntry.Native).AsString <> AValue.ResourceId then
    LResourceId.SetValue(AEntry.Native, TValue.From<string>(AValue.ResourceId));
end;


function MatchingProjectFiles(const AProject: IOTAProject; const AFileName: string): Integer;
var
  LIndex: Integer;
  LModule: IOTAModuleInfo;
begin
  Result := 0;
  for LIndex := 0 to AProject.GetModuleCount - 1 do
  begin
    LModule := AProject.GetModule(LIndex);
    if Assigned(LModule) then
      if TDAIOTA.SameFile(LModule.FileName, AFileName) then
        Inc(Result);
  end;
end;

function FindEntry(const AEntries: TArray<TResourceEntry>; const AResourceType, AResourceId: string): TResourceEntry;
var
  LEntry: TResourceEntry;
begin
  Result := Default(TResourceEntry);
  for LEntry in AEntries do
    if SameText(LEntry.Resource.ResourceType, AResourceType) and SameText(LEntry.Resource.ResourceId, AResourceId) then
    begin
      if Assigned(Result.Native) then
        raise EInvalidOperation.CreateFmt('Mehrere Ressourceneinträge passen zu %s %s.', [AResourceType, AResourceId]);
      Result := LEntry;
    end;
end;

function RequireEntry(const AEntries: TArray<TResourceEntry>; const AResourceType, AResourceId: string): TResourceEntry;
begin
  Result := FindEntry(AEntries, AResourceType, AResourceId);
  if not Assigned(Result.Native) then
    raise EArgumentException.CreateFmt('Ressource %s %s wurde im Projekt nicht gefunden.', [AResourceType, AResourceId]);
end;

function RequireFileEntry(const AEntries: TArray<TResourceEntry>; const AFileName: string): TResourceEntry;
var
  LEntry: TResourceEntry;
begin
  Result := Default(TResourceEntry);
  for LEntry in AEntries do
    if TDAIOTA.SameFile(LEntry.Resource.FileName, AFileName) then
    begin
      if Assigned(Result.Native) then
        raise EInvalidOperation.CreateFmt('Mehrere Ressourceneinträge verwenden dieselbe Quelldatei: %s.', [AFileName]);
      Result := LEntry;
    end;
  if not Assigned(Result.Native) then
    BackendUnavailable('der angelegte RcItem-Eintrag konnte nicht gelesen werden');
end;

procedure RequireUnusedSource(const AProject: IOTAProject; const AFileName: string);
begin
  if MatchingProjectFiles(AProject, AFileName) <> 0 then
    raise EArgumentException.CreateFmt('Die Quelldatei ist bereits im Projekt eingetragen: %s.', [AFileName]);
end;

procedure RequireAvailableKey(const AEntries: TArray<TResourceEntry>; const AResource: TDAIProjectResource; const AExcept: TObject);
var
  LExisting: TResourceEntry;
begin
  if SameText(AResource.ResourceType, 'ICON') and SameText(AResource.ResourceId, 'MAINICON') then
    raise EArgumentException.Create('MAINICON ist für das Hauptsymbol des Projekts reserviert.');
  LExisting := FindEntry(AEntries, AResource.ResourceType, AResource.ResourceId);
  if Assigned(LExisting.Native) and (LExisting.Native <> AExcept) then
    raise EArgumentException.CreateFmt('Ressource %s %s ist bereits vorhanden.', [AResource.ResourceType, AResource.ResourceId]);
end;

function VerifyEntry(const AModel: TResourceModel; const AProject: IOTAProject; const AExpected: TDAIProjectResource; const AObject: TObject): TDAIProjectResource;
var
  LEntry: TResourceEntry;
begin
  LEntry := RequireEntry(AModel.Entries(AProject), AExpected.ResourceType, AExpected.ResourceId);
  if (LEntry.Native <> AObject) or not TDAIOTA.SameFile(LEntry.Resource.FileName, AExpected.FileName) then
    raise EInvalidOperation.Create('Die IDE hat den Ressourceneintrag nicht wie angefordert übernommen.');
  Result := LEntry.Resource;
end;

procedure MarkProjectModified(const AProject: IOTAProject);
begin
  AProject.ProjectOptions.ModifiedState := True;
  AProject.MarkModified;
end;


class function TDAIProjectResourceBackend.List(const AProject: IOTAProject): TArray<TDAIProjectResource>;
var
  LModel: TResourceModel;
  LEntries: TArray<TResourceEntry>;
  LIndex: Integer;
begin
  LModel.Context := TRttiContext.Create;
  try
    LEntries := LModel.Entries(AProject);
    SetLength(Result, Length(LEntries));
    for LIndex := 0 to High(LEntries) do
      Result[LIndex] := LEntries[LIndex].Resource;
  finally
    LModel.Context.Free;
  end;
end;

class function TDAIProjectResourceBackend.Add(const AProject: IOTAProject; const AFileName, AResourceType, AResourceId: string): TDAIProjectResource;
var
  LModel: TResourceModel;
  LEntry: TResourceEntry;
  LValue: TDAIProjectResource;
  LSourceForAdd: string;
begin
  LModel.Context := TRttiContext.Create;
  try
    LValue.FileName := AFileName;
    LValue.ResourceType := AResourceType;
    LValue.ResourceId := AResourceId;
    RequireAvailableKey(LModel.Entries(AProject), LValue, nil);
    RequireUnusedSource(AProject, AFileName);

    LSourceForAdd := AFileName;
    // Delphi adds existing ICO files as RcItem entries directly. The resource-model
    // path is also used to insert arbitrary file types into the same container.
    if not SameText(TPath.GetExtension(AFileName), '.ico') then
    begin
      LSourceForAdd := TPath.Combine(TPath.GetDirectoryName(AProject.FileName), 'DAIResource-' + TGUID.NewGuid.ToString + '.png');
      RequireUnusedSource(AProject, LSourceForAdd);
      if TFile.Exists(LSourceForAdd) then
        raise EInvalidOperation.Create('Der interne temporäre Ressourcenpfad ist bereits belegt.');
    end;
    LEntry := Default(TResourceEntry);
    try
      AProject.AddFile(LSourceForAdd, False);
      LEntry := RequireFileEntry(LModel.Entries(AProject), LSourceForAdd);
      if TDAIOTA.SameFile(LEntry.Resource.FileName, AFileName) then
        LValue.FileName := LEntry.Resource.FileName;
      LModel.SetValues(LEntry, LValue);
      Result := VerifyEntry(LModel, AProject, LValue, LEntry.Native);
      MarkProjectModified(AProject);
    except
      if Assigned(LEntry.Native) and (MatchingProjectFiles(AProject, AFileName) = 1) then
        AProject.RemoveFile(AFileName)
      else if MatchingProjectFiles(AProject, LSourceForAdd) = 1 then
        AProject.RemoveFile(LSourceForAdd);
      raise;
    end;
  finally
    LModel.Context.Free;
  end;
end;

class function TDAIProjectResourceBackend.Update(const AProject: IOTAProject; const AResourceType, AResourceId,
  ANewFileName, ANewResourceType, ANewResourceId: string): TDAIProjectResource;
var
  LModel: TResourceModel;
  LEntries: TArray<TResourceEntry>;
  LEntry: TResourceEntry;
  LValue: TDAIProjectResource;
begin
  LModel.Context := TRttiContext.Create;
  try
    LEntries := LModel.Entries(AProject);
    LEntry := RequireEntry(LEntries, AResourceType, AResourceId);
    LValue := LEntry.Resource;
    if ANewFileName <> '' then
      LValue.FileName := ANewFileName;
    if ANewResourceType <> '' then
      LValue.ResourceType := ANewResourceType;
    if ANewResourceId <> '' then
      LValue.ResourceId := ANewResourceId;
    if (LValue.FileName = LEntry.Resource.FileName) and (LValue.ResourceType = LEntry.Resource.ResourceType) and
      (LValue.ResourceId = LEntry.Resource.ResourceId) then
      Exit(LEntry.Resource);
    RequireAvailableKey(LEntries, LValue, LEntry.Native);
    if not TDAIOTA.SameFile(LValue.FileName, LEntry.Resource.FileName) then
      RequireUnusedSource(AProject, LValue.FileName);

    try
      LModel.SetValues(LEntry, LValue);
      Result := VerifyEntry(LModel, AProject, LValue, LEntry.Native);
      MarkProjectModified(AProject);
    except
      LModel.SetValues(LEntry, LEntry.Resource);
      raise;
    end;
  finally
    LModel.Context.Free;
  end;
end;

class function TDAIProjectResourceBackend.Remove(const AProject: IOTAProject; const AResourceType, AResourceId: string): TDAIProjectResource;
var
  LModel: TResourceModel;
  LEntry: TResourceEntry;
begin
  LModel.Context := TRttiContext.Create;
  try
    LEntry := RequireEntry(LModel.Entries(AProject), AResourceType, AResourceId);
    Result := LEntry.Resource;
    if MatchingProjectFiles(AProject, Result.FileName) <> 1 then
      raise EInvalidOperation.CreateFmt('Die Ressource kann nicht eindeutig anhand ihrer Datei entfernt werden: %s.', [Result.FileName]);
    AProject.RemoveFile(Result.FileName);
    if MatchingProjectFiles(AProject, Result.FileName) <> 0 then
      raise EInvalidOperation.Create('Die IDE hat den Ressourceneintrag nicht entfernt.');
    MarkProjectModified(AProject);
  finally
    LModel.Context.Free;
  end;
end;

end.
