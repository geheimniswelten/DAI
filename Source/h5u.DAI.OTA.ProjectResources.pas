unit h5u.DAI.OTA.ProjectResources;

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.JSON;

type
  TDAIProjectResourceAction = (praAdd, praUpdate, praRemove);

  TDAIProjectResourceChange = record
    Action: TDAIProjectResourceAction;
    ResourceType, ResourceId: string;
    FileName, NewResourceType, NewResourceId: string;
  end;

  TDAIProjectResourcesService = class sealed
  public
    class function ListResources(const AProjectFile: string): TJSONObject; static;
    class function ChangeResource(const AProjectFile: string; const AChange: TDAIProjectResourceChange): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  ToolsAPI,
  Xml.XMLDoc,
  Xml.XMLIntf,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.OTA.ProjectResources.Live,
  h5u.DAI.Text.Encoding,
  h5u.DAI.Types;

const
  CMSBuildNamespace = 'http://schemas.microsoft.com/developer/msbuild/2003';
  CMaximumResources = 10000;

function IsMSBuildNode(const ANode: IXMLNode; const AName: string): Boolean;
begin
  Result := (ANode.NodeType = ntElement) and (ANode.LocalName = AName) and
    ((ANode.NamespaceURI = '') or (ANode.NamespaceURI = CMSBuildNamespace));
end;

function AttributeText(const ANode: IXMLNode; const AName: string): string;
begin
  if ANode.HasAttribute(AName) then
    Result := ANode.Attributes[AName]
  else
    Result := '';
end;

procedure AddMetadata(const AResult: TJSONObject; const AItem: IXMLNode; const AName, AKey: string);
var
  LIndex: Integer;
  LNode: IXMLNode;
  LValue: TJSONValue;
begin
  LValue := nil;
  for LIndex := 0 to AItem.ChildNodes.Count - 1 do
  begin
    LNode := AItem.ChildNodes[LIndex];
    if not IsMSBuildNode(LNode, AName) then
      Continue;
    if Assigned(LValue) or LNode.HasAttribute('Condition') then
    begin
      FreeAndNil(LValue);
      Break;
    end;
    LValue := TJSONString.Create(LNode.Text);
  end;
  if not Assigned(LValue) then
    LValue := TJSONNull.Create;
  AResult.AddPair(AKey, LValue);
end;

function DeclaredFile(const ADirectory, AInclude: string): TJSONValue;
begin
  if (AInclude = '') or AInclude.Contains('$(') or AInclude.Contains('@(') or AInclude.Contains('%(') or
    AInclude.Contains('*') or AInclude.Contains('?') or AInclude.Contains(';') or AInclude.Contains('%') then
    Exit(TJSONNull.Create);
  try
    Result := TJSONString.Create(TPath.GetFullPath(TPath.Combine(ADirectory, AInclude)));
  except
    on E: EArgumentException do
      Result := TJSONNull.Create;
  end;
end;

function ReadDeclaredResources(const AText, ADirectory: string): TJSONArray;
var
  LDocument: IXMLDocument;
  LRoot, LGroup, LItem: IXMLNode;
  LGroupIndex, LItemIndex: Integer;
  LInclude: string;
  LEntry: TJSONObject;
begin
  if (Length(AText) > CDAIMaxTextFileBytes div SizeOf(Char)) or AText.ToUpper.Contains('<!DOCTYPE') then
    raise EArgumentException.Create('Die DPROJ ist zu groß oder enthält einen nicht unterstützten Dokumenttyp.');
  LDocument := NewXMLDocument;
  LDocument.ParseOptions := [];
  LDocument.Options := [];
  LDocument.LoadFromXML(AText);
  LRoot := LDocument.DocumentElement;
  if not Assigned(LRoot) or not IsMSBuildNode(LRoot, 'Project') then
    raise EArgumentException.Create('Die Datei enthält kein unterstütztes MSBuild-Projekt.');
  Result := TJSONArray.Create;
  try
    for LGroupIndex := 0 to LRoot.ChildNodes.Count - 1 do
    begin
      LGroup := LRoot.ChildNodes[LGroupIndex];
      if not IsMSBuildNode(LGroup, 'ItemGroup') then
        Continue;
      for LItemIndex := 0 to LGroup.ChildNodes.Count - 1 do
      begin
        LItem := LGroup.ChildNodes[LItemIndex];
        if not IsMSBuildNode(LItem, 'RcItem') or not LItem.HasAttribute('Include') then
          Continue;
        if Result.Count >= CMaximumResources then
          raise EInvalidOperation.Create('Die Zahl der Ressourceneinträge überschreitet das Prüflimit.');
        LEntry := TJSONObject.Create;
        Result.AddElement(LEntry);
        LInclude := AttributeText(LItem, 'Include');
        LEntry.AddPair('include', LInclude);
        LEntry.AddPair('file', DeclaredFile(ADirectory, LInclude));
        AddMetadata(LEntry, LItem, 'ResourceType', 'resource_type');
        AddMetadata(LEntry, LItem, 'ResourceId', 'resource_id');
        if LGroup.HasAttribute('Condition') then
          LEntry.AddPair('group_condition', AttributeText(LGroup, 'Condition'));
        if LItem.HasAttribute('Condition') then
          LEntry.AddPair('item_condition', AttributeText(LItem, 'Condition'));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function ResolveLoadedProject(const AProjectFile: string): IOTAProject;
begin
  Result := TDAIOTA.ProjectByNameOrPath(AProjectFile);
  if not Assigned(Result) or not TDAIOTA.SameFile(Result.FileName, AProjectFile) then
    raise EArgumentException.Create('Das gewählte Projekt ist in dieser IDE nicht geladen.');
  if not MatchText(TPath.GetExtension(AProjectFile), ['.dproj', '.dpr', '.dpk']) then
    raise EArgumentException.Create('Projektressourcen erfordern ein geladenes Delphi-Projekt.');
end;

function ResourceJson(const AResource: TDAIProjectResource): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AResource.FileName);
  Result.AddPair('resource_type', AResource.ResourceType);
  Result.AddPair('resource_id', AResource.ResourceId);
end;

function LiveResourceList(const AProject: IOTAProject): TJSONArray;
var
  LResource: TDAIProjectResource;
begin
  Result := TJSONArray.Create;
  try
    for LResource in TDAIProjectResourceBackend.List(AProject) do
      Result.AddElement(ResourceJson(LResource));
  except
    Result.Free;
    raise;
  end;
end;

procedure RequireResourceToken(const AName, AValue: string);
var
  LCharacter: Char;
  LValue: UInt64;
begin
  if (AValue = '') or (Length(AValue) > 255) then
    raise EArgumentException.CreateFmt('%s muss ein Ressourcenname oder eine ID zwischen 1 und 65535 sein.', [AName]);
  if CharInSet(AValue[1], ['0'..'9']) then
  begin
    if not TryStrToUInt64(AValue, LValue) or (LValue = 0) or (LValue > High(Word)) then
      raise EArgumentException.CreateFmt('%s muss eine ID zwischen 1 und 65535 sein.', [AName]);
    if AValue <> UIntToStr(LValue) then
      raise EArgumentException.CreateFmt('%s muss eine dezimale Ressourcen-ID ohne führende Nullen sein.', [AName]);
    Exit;
  end;
  for LCharacter in AValue do
    if not CharInSet(LCharacter, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      raise EArgumentException.CreateFmt('%s muss ein gültiger RC-Bezeichner sein.', [AName]);
end;

function ResolveAssetFile(const AProjectFile, AFileName: string): string;
begin
  if AFileName.Contains('$(') or AFileName.Contains('@(') or AFileName.Contains('%(') or AFileName.Contains(';') then
    raise EArgumentException.Create('Die Ressourcendatei muss ein einzelner Dateipfad sein.');
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(AProjectFile), AFileName));
  if not TFile.Exists(Result) then
    raise EDAIFileNotFound.CreateFmt('Ressourcendatei nicht gefunden: %s', [Result]);
end;

procedure RequireWritableProjectFile(const AProjectFile: string);
var
  LConfigFile: string;
begin
  LConfigFile := ChangeFileExt(AProjectFile, '.dproj');
  TDAIOTA.RequireNoReparseWritePath(LConfigFile);
  if TDAIOTA.IsReadOnlyReferenceFile(LConfigFile) or
    (TFile.Exists(LConfigFile) and (TFileAttribute.faReadOnly in TFile.GetAttributes(LConfigFile))) then
    raise EDAIAccessDenied.CreateFmt('Die Projektdatei ist schreibgeschützt: %s', [LConfigFile]);
end;

class function TDAIProjectResourcesService.ListResources(const AProjectFile: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LProject: IOTAProject;
      LEditor: IOTASourceEditor;
      LFileName, LSource, LText: string;
      LFormat: TDAITextFileFormat;
      LResources: TJSONArray;
    begin
      LProject := ResolveLoadedProject(AProjectFile);
      try
        LResources := LiveResourceList(LProject);
        LSource := 'ide_project';
      except
        on E: EDAIRcItemBackendUnavailable do
        begin
          LFileName := ChangeFileExt(AProjectFile, '.dproj');
          LEditor := TDAIOTA.FindSourceEditor(LFileName);
          if Assigned(LEditor) then
          begin
            if not Assigned(LEditor.CreateReader) then
              raise EInvalidOperation.Create('Der geöffnete Projekttext kann nicht gelesen werden.');
            LText := TDAIOTA.ReadEditorText(LEditor);
            LSource := 'editor_buffer';
          end
          else
          begin
            if not TFile.Exists(LFileName) then
              raise EDAIFileNotFound.CreateFmt('Gespeicherte Projektdatei nicht gefunden: %s', [LFileName]);
            LText := TDAITextEncoding.ReadFile(LFileName, LFormat, CDAIMaxTextFileBytes);
            LSource := 'saved_dproj';
          end;
          LResources := ReadDeclaredResources(LText, TPath.GetDirectoryName(LFileName));
        end;
      end;
      try
        LResult := TJSONObject.Create;
      except
        LResources.Free;
        raise;
      end;
      LResult.AddPair('resources', LResources);
      LResult.AddPair('project', AProjectFile);
      LResult.AddPair('source', LSource);
    end);
  Result := LResult;
end;

class function TDAIProjectResourcesService.ChangeResource(const AProjectFile: string; const AChange: TDAIProjectResourceChange): TJSONObject;
var
  LResult: TJSONObject;
  LFileName: string;
begin
  if AChange.Action = praAdd then
  begin
    RequireResourceToken('resource_type', AChange.ResourceType);
    RequireResourceToken('resource_id', AChange.ResourceId);
  end;
  if AChange.NewResourceType <> '' then
    RequireResourceToken('new_resource_type', AChange.NewResourceType);
  if AChange.NewResourceId <> '' then
    RequireResourceToken('new_resource_id', AChange.NewResourceId);
  if AChange.FileName <> '' then
    LFileName := ResolveAssetFile(AProjectFile, AChange.FileName);
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    var
      LProject: IOTAProject;
      LEditor: IOTASourceEditor;
      LResource: TDAIProjectResource;
    begin
      LProject := ResolveLoadedProject(AProjectFile);
      RequireWritableProjectFile(AProjectFile);
      LEditor := TDAIOTA.FindSourceEditor(ChangeFileExt(AProjectFile, '.dproj'));
      if Assigned(LEditor) and LEditor.Modified then
        raise EInvalidOperation.Create('Die Projektdatei enthält ungespeicherte Änderungen im Texteditor.');
      case AChange.Action of
        praAdd:
          LResource := TDAIProjectResourceBackend.Add(LProject, LFileName, AChange.ResourceType, AChange.ResourceId);
        praUpdate:
          LResource := TDAIProjectResourceBackend.Update(LProject, AChange.ResourceType, AChange.ResourceId,
            LFileName, AChange.NewResourceType, AChange.NewResourceId);
        praRemove:
          LResource := TDAIProjectResourceBackend.Remove(LProject, AChange.ResourceType, AChange.ResourceId);
      end;
      LResult := TJSONObject.Create;
      LResult.AddPair('project', AProjectFile);
      LResult.AddPair('resource', ResourceJson(LResource));
      LResult.AddPair('saved', TJSONBool.Create(False));
      LResult.AddPair('modified', TJSONBool.Create(LProject.ProjectOptions.ModifiedState));
    end);
  Result := LResult;
end;

end.
