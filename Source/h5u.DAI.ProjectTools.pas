unit h5u.DAI.ProjectTools;

interface

uses
  System.JSON,
  System.SysUtils;

{$I '..\SDK\DAI.ProjectTools.Provider.inc'}

type
  TDAIProjectTools = class sealed
  public
    // The caller must first resolve a loaded project and authorize its read access.
    class function ListTools(const AProjectFile: string): TJSONObject; static;
    // The write authorizer must raise on denial. It is only called for V2 write tools.
    class function CallTool(const AProjectFile, AExtensionId, AToolName: string; const AArguments: TJSONObject; const AAuthorizeWrite: TProc = nil): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  Vcl.Forms,
  h5u.DAI.OTA.Helpers;

const
  CMaximumJSONBytes = 1024 * 1024;
  CMaximumArgumentBytes = 64 * 1024;
  CMaximumExtensions = 64;
  CMaximumTools = 64;
  CMaximumInfoCharacters = 16384;

procedure RequireProject(const AProjectFile: string);
begin
  if Trim(AProjectFile) = '' then
    raise EArgumentException.Create('Ein geladenes Projekt ist fuer Projektwerkzeuge erforderlich.');
end;

procedure RequireLoadedProject(const AProjectFile: string);
var
  LProject: IOTAProject;
  LActualFile: string;
begin
  // Recheck after authorization dialogs, which can pump IDE project changes.
  // This executes in the same main-thread block as discovery and invocation.
  LProject := TDAIOTA.ProjectByNameOrPath(AProjectFile);
  if not Assigned(LProject) then
    raise EArgumentException.Create('Das angeforderte Projekt ist nicht mehr in der IDE geladen.');
  LActualFile := TDAIOTA.ProjectFileName(LProject);
  if not SameText(ExpandFileName(LActualFile), ExpandFileName(AProjectFile)) then
    raise EArgumentException.Create('Die geladene Projektidentitaet hat sich geaendert.');
end;

function ValidIdentifier(const AValue: string; const AMaximumLength: Integer): Boolean;
var
  LCharacter: Char;
begin
  Result := False;
  if (AValue = '') or (Length(AValue) > AMaximumLength) then
    Exit;
  for LCharacter in AValue do
    if not CharInSet(LCharacter, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) then
      Exit;
  Result := True;
end;

procedure RequireJSONSize(const AText: string; const AMaximumBytes: Integer);
begin
  if Length(AText) > AMaximumBytes then
    raise EArgumentException.Create('Die JSON-Daten der Projekterweiterung sind zu gross.');
  if TEncoding.UTF8.GetByteCount(AText) > AMaximumBytes then
    raise EArgumentException.Create('Die JSON-Daten der Projekterweiterung sind zu gross.');
end;

function ParseObject(const AText: string): TJSONObject;
var
  LValue: TJSONValue;
begin
  RequireJSONSize(AText, CMaximumJSONBytes);
  LValue := TJSONObject.ParseJSONValue(AText);
  if not (LValue is TJSONObject) then
  begin
    LValue.Free;
    raise EArgumentException.Create('Die Projekterweiterung muss ein gueltiges JSON-Objekt liefern.');
  end;
  Result := TJSONObject(LValue);
end;

function OptionalString(const AObject: TJSONObject; const AName: string; const AMaximum: Integer): string;
var
  LValue: TJSONValue;
begin
  Result := '';
  LValue := AObject.GetValue(AName);
  if not Assigned(LValue) then
    Exit;
  if not (LValue is TJSONString) or (LValue is TJSONNumber) then
    raise EArgumentException.CreateFmt('Die Erweiterungseigenschaft %s muss ein String sein.', [AName]);
  Result := LValue.Value;
  if Length(Result) > AMaximum then
    raise EArgumentException.CreateFmt('Die Erweiterungseigenschaft %s ist zu lang.', [AName]);
end;

procedure RequireUniqueNames(const AObject: TJSONObject);
var
  LNames: TDictionary<string, Boolean>;
  LPair: TJSONPair;
begin
  LNames := TDictionary<string, Boolean>.Create;
  try
    for LPair in AObject do
    begin
      if LNames.ContainsKey(LPair.JsonString.Value) then
        raise EArgumentException.CreateFmt('Doppelte JSON-Eigenschaft: %s', [LPair.JsonString.Value]);
      LNames.Add(LPair.JsonString.Value, True);
    end;
  finally
    LNames.Free;
  end;
end;

function ExtensionInfo(const AProvider: IDAIMCPReadOnlyExtensionV1): TJSONObject;
var
  LInfo: TJSONObject;
  LId: string;
  LPair: TJSONPair;
begin
  LInfo := ParseObject(AProvider.GetInfoJSON);
  try
    RequireUniqueNames(LInfo);
    for LPair in LInfo do
      if (LPair.JsonString.Value <> 'id') and (LPair.JsonString.Value <> 'title') and
        (LPair.JsonString.Value <> 'description') and (LPair.JsonString.Value <> 'instructions') then
        raise EArgumentException.CreateFmt('Unbekannte Erweiterungsmetadaten: %s', [LPair.JsonString.Value]);
    LId := OptionalString(LInfo, 'id', 64);
    if not ValidIdentifier(LId, 64) then
      raise EArgumentException.Create('Die Projekterweiterung besitzt keine gueltige Kennung.');
    OptionalString(LInfo, 'title', 256);
    OptionalString(LInfo, 'description', CMaximumInfoCharacters);
    OptionalString(LInfo, 'instructions', CMaximumInfoCharacters);
    Result := LInfo;
  except
    LInfo.Free;
    raise;
  end;
end;

procedure RequireObjectSchema(const ASchema: TJSONObject);
var
  LType, LProperties, LRequired, LAdditional: TJSONValue;
  LItem: TJSONValue;
begin
  RequireUniqueNames(ASchema);
  LType := ASchema.GetValue('type');
  if not (LType is TJSONString) then
    raise EArgumentException.Create('Das Projektschema muss type=object verwenden.');
  if LType.Value <> 'object' then
    raise EArgumentException.Create('Das Projektschema muss type=object verwenden.');
  LProperties := ASchema.GetValue('properties');
  if Assigned(LProperties) then
  begin
    if not (LProperties is TJSONObject) then
      raise EArgumentException.Create('Schema-properties muss ein Objekt sein.');
    RequireUniqueNames(TJSONObject(LProperties));
  end;
  LAdditional := ASchema.GetValue('additionalProperties');
  if not (LAdditional is TJSONBool) then
    raise EArgumentException.Create('Projektschemata muessen additionalProperties=false setzen.');
  if TJSONBool(LAdditional).AsBoolean then
    raise EArgumentException.Create('Projektschemata muessen additionalProperties=false setzen.');
  LRequired := ASchema.GetValue('required');
  if not Assigned(LRequired) then
    Exit;
  if not (LRequired is TJSONArray) then
    raise EArgumentException.Create('Schema-required muss ein Array sein.');
  for LItem in TJSONArray(LRequired) do
  begin
    if not (LItem is TJSONString) or (LItem is TJSONNumber) then
      raise EArgumentException.Create('Schema-required darf nur Eigenschaftsnamen enthalten.');
    if not Assigned(LProperties) then
      raise EArgumentException.Create('Schema-required verweist auf eine unbekannte Eigenschaft.');
    if not Assigned(TJSONObject(LProperties).GetValue(LItem.Value)) then
      raise EArgumentException.Create('Schema-required verweist auf eine unbekannte Eigenschaft.');
  end;
end;

procedure ToolAnnotations(const ATool: TJSONObject; const AAllowsWrites: Boolean; out AReadOnly, ADestructive: Boolean);
var
  LAnnotations, LValue: TJSONValue;
begin
  AReadOnly := True;
  ADestructive := False;
  LAnnotations := ATool.GetValue('annotations');
  if Assigned(LAnnotations) then
  begin
    if not (LAnnotations is TJSONObject) then
      raise EArgumentException.Create('Werkzeug-annotations muss ein Objekt sein.');
    RequireUniqueNames(TJSONObject(LAnnotations));
    LValue := TJSONObject(LAnnotations).GetValue('readOnlyHint');
    if Assigned(LValue) then
    begin
      if not (LValue is TJSONBool) then
        raise EArgumentException.Create('readOnlyHint muss ein Boolean sein.');
      AReadOnly := TJSONBool(LValue).AsBoolean;
      if not AAllowsWrites and not AReadOnly then
        raise EArgumentException.Create('V1-Projektwerkzeuge muessen als lesend deklariert sein.');
    end
    else if AAllowsWrites then
      raise EArgumentException.Create('V2-Projektwerkzeuge benoetigen readOnlyHint.');

    ADestructive := not AReadOnly;
    LValue := TJSONObject(LAnnotations).GetValue('destructiveHint');
    if Assigned(LValue) then
    begin
      if not (LValue is TJSONBool) then
        raise EArgumentException.Create('destructiveHint muss ein Boolean sein.');
      ADestructive := TJSONBool(LValue).AsBoolean;
      if AReadOnly and ADestructive then
        raise EArgumentException.Create('Lesende Projektwerkzeuge duerfen nicht destruktiv sein.');
    end;
  end
  else if AAllowsWrites then
    raise EArgumentException.Create('V2-Projektwerkzeuge benoetigen annotations mit readOnlyHint.');
end;

function ToolIsReadOnly(const ATool: TJSONObject): Boolean;
begin
  Result := ATool.GetValue<TJSONObject>('annotations').GetValue<Boolean>('readOnlyHint');
end;

function ExtensionTools(const AProvider: IDAIMCPReadOnlyExtensionV1; const AProjectFile: string; const AAllowsWrites: Boolean): TJSONArray;
var
  LValue, LItem, LSchema: TJSONValue;
  LTool, LCopy, LAnnotations: TJSONObject;
  LNames: TDictionary<string, Boolean>;
  LName, LText: string;
  LReadOnly, LDestructive: Boolean;
begin
  Result := nil;
  LText := AProvider.GetToolsJSON(AProjectFile);
  RequireJSONSize(LText, CMaximumJSONBytes);
  LValue := TJSONObject.ParseJSONValue(LText);
  if not (LValue is TJSONArray) then
  begin
    LValue.Free;
    raise EArgumentException.Create('Die Projekterweiterung muss ein JSON-Array mit Werkzeugen liefern.');
  end;
  LNames := TDictionary<string, Boolean>.Create;
  try
    if TJSONArray(LValue).Count > CMaximumTools then
      raise EArgumentException.Create('Die Projekterweiterung liefert zu viele Werkzeuge.');
    Result := TJSONArray.Create;
    try
      for LItem in TJSONArray(LValue) do
      begin
        if not (LItem is TJSONObject) then
          raise EArgumentException.Create('Ein Projektwerkzeug muss ein JSON-Objekt sein.');
        LTool := TJSONObject(LItem);
        RequireUniqueNames(LTool);
        LName := OptionalString(LTool, 'name', 128);
        if not ValidIdentifier(LName, 128) then
          raise EArgumentException.Create('Ein Projektwerkzeug besitzt keinen gueltigen Namen.');
        if LNames.ContainsKey(LowerCase(LName)) then
          raise EArgumentException.CreateFmt('Doppelter Projektwerkzeugname: %s', [LName]);
        LNames.Add(LowerCase(LName), True);
        LSchema := LTool.GetValue('inputSchema');
        if not (LSchema is TJSONObject) then
          raise EArgumentException.Create('Ein Projektwerkzeug benoetigt ein Eingabeschema.');
        RequireObjectSchema(TJSONObject(LSchema));
        ToolAnnotations(LTool, AAllowsWrites, LReadOnly, LDestructive);
        LCopy := TJSONObject.Create;
        Result.AddElement(LCopy);
        LCopy.AddPair('name', LName);
        LCopy.AddPair('title', OptionalString(LTool, 'title', 256));
        LCopy.AddPair('description', OptionalString(LTool, 'description', CMaximumInfoCharacters));
        LCopy.AddPair('inputSchema', LSchema.Clone as TJSONObject);
        LAnnotations := TJSONObject.Create;
        LCopy.AddPair('annotations', LAnnotations);
        LAnnotations.AddPair('readOnlyHint', TJSONBool.Create(LReadOnly));
        LAnnotations.AddPair('destructiveHint', TJSONBool.Create(LDestructive));
      end;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    LNames.Free;
    LValue.Free;
  end;
end;

function ApplicationProvider(const AIndex: Integer; out AProvider: IDAIMCPReadOnlyExtensionV1; out AAllowsWrites: Boolean): Boolean;
var
  LComponent: TComponent;
  LProviderV2: IDAIMCPProjectExtensionV2;
begin
  AProvider := nil;
  AAllowsWrites := False;
  LComponent := Application.Components[AIndex];
  if LComponent.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit(False);
  if Supports(LComponent, IDAIMCPProjectExtensionV2, LProviderV2) then
  begin
    AProvider := LProviderV2;
    AAllowsWrites := True;
    Exit(True);
  end;
  Result := Supports(LComponent, IDAIMCPReadOnlyExtensionV1, AProvider);
end;

procedure RegisterExtensionId(const AIds: TDictionary<string, Boolean>; const AInfo: TJSONObject);
var
  LId: string;
begin
  LId := LowerCase(AInfo.GetValue<string>('id'));
  if AIds.ContainsKey(LId) then
    raise EArgumentException.CreateFmt('Mehrere geladene Projekterweiterungen verwenden die Kennung %s.', [LId]);
  if AIds.Count >= CMaximumExtensions then
    raise EArgumentException.Create('Es sind zu viele Projekterweiterungen geladen.');
  AIds.Add(LId, True);
end;

procedure ValidateArguments(const ATool, AArguments: TJSONObject);
var
  LSchema, LProperties: TJSONObject;
  LRequired: TJSONArray;
  LPair: TJSONPair;
  LItem: TJSONValue;
begin
  RequireUniqueNames(AArguments);
  LSchema := ATool.GetValue<TJSONObject>('inputSchema');
  LProperties := LSchema.GetValue<TJSONObject>('properties', nil);
  for LPair in AArguments do
  begin
    if Assigned(LProperties) then
      if Assigned(LProperties.GetValue(LPair.JsonString.Value)) then
        Continue;
    raise EArgumentException.CreateFmt('Unbekanntes Projektwerkzeug-Argument: %s', [LPair.JsonString.Value]);
  end;
  LRequired := LSchema.GetValue<TJSONArray>('required', nil);
  if Assigned(LRequired) then
    for LItem in LRequired do
      if not Assigned(AArguments.GetValue(LItem.Value)) then
        raise EArgumentException.CreateFmt('Erforderliches Projektwerkzeug-Argument fehlt: %s', [LItem.Value]);
  // Providers validate property types, ranges and domain semantics themselves.
end;

class function TDAIProjectTools.ListTools(const AProjectFile: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  RequireProject(AProjectFile);
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LProvider: IDAIMCPReadOnlyExtensionV1;
        LExtensions, LTools: TJSONArray;
        LTool: TJSONValue;
        LInfo: TJSONObject;
        LAllowsWrites, LReadOnly: Boolean;
        LIds: TDictionary<string, Boolean>;
        LIndex: Integer;
      begin
        RequireLoadedProject(AProjectFile);
        LResult.AddPair('project', AProjectFile);
        LReadOnly := True;
        LExtensions := TJSONArray.Create;
        LResult.AddPair('extensions', LExtensions);
        if Assigned(Application) then
        begin
          LIds := TDictionary<string, Boolean>.Create;
          try
            for LIndex := 0 to Application.ComponentCount - 1 do
            begin
              if not ApplicationProvider(LIndex, LProvider, LAllowsWrites) then
                Continue;
              if not LProvider.SupportsProject(AProjectFile) then
                Continue;
              LInfo := ExtensionInfo(LProvider);
              LExtensions.AddElement(LInfo);
              RegisterExtensionId(LIds, LInfo);
              LTools := ExtensionTools(LProvider, AProjectFile, LAllowsWrites);
              LInfo.AddPair('tools', LTools);
              for LTool in LTools do
                LReadOnly := LReadOnly and ToolIsReadOnly(TJSONObject(LTool));
              RequireJSONSize(LResult.ToJSON, CMaximumJSONBytes);
              LProvider := nil;
            end;
          finally
            LIds.Free;
            // All package interfaces are released on the IDE thread, even on error.
            LProvider := nil;
          end;
        end;
        LResult.AddPair('read_only', TJSONBool.Create(LReadOnly));
        RequireJSONSize(LResult.ToJSON, CMaximumJSONBytes);
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIProjectTools.CallTool(const AProjectFile, AExtensionId, AToolName: string; const AArguments: TJSONObject; const AAuthorizeWrite: TProc): TJSONObject;
var
  LArgumentsJSON, LWriteDescriptor: string;
  LResult: TJSONObject;

  procedure Dispatch(const AWriteAuthorized: Boolean);
  begin
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LProvider, LSelected: IDAIMCPReadOnlyExtensionV1;
        LInfo, LArguments, LTool: TJSONObject;
        LIds: TDictionary<string, Boolean>;
        LTools: TJSONArray;
        LItem: TJSONValue;
        LIndex: Integer;
        LAllowsWrites, LSelectedAllowsWrites: Boolean;
      begin
        RequireLoadedProject(AProjectFile);
        if not Assigned(Application) then
          raise EArgumentException.Create('Keine Projekterweiterung ist verfuegbar.');
        LSelectedAllowsWrites := False;
        LIds := TDictionary<string, Boolean>.Create;
        try
          for LIndex := 0 to Application.ComponentCount - 1 do
          begin
            if not ApplicationProvider(LIndex, LProvider, LAllowsWrites) then
              Continue;
            if not LProvider.SupportsProject(AProjectFile) then
              Continue;
            LInfo := ExtensionInfo(LProvider);
            try
              RegisterExtensionId(LIds, LInfo);
              if SameText(LInfo.GetValue<string>('id'), AExtensionId) then
              begin
                LSelected := LProvider;
                LSelectedAllowsWrites := LAllowsWrites;
              end;
            finally
              LInfo.Free;
              LProvider := nil;
            end;
          end;
          if not Assigned(LSelected) then
            raise EArgumentException.Create('Die angeforderte Projekterweiterung ist fuer dieses Projekt nicht verfuegbar.');
          LTools := ExtensionTools(LSelected, AProjectFile, LSelectedAllowsWrites);
          try
            for LItem in LTools do
            begin
              LTool := TJSONObject(LItem);
              if not SameText(LTool.GetValue<string>('name'), AToolName) then
                Continue;
              LArguments := ParseObject(LArgumentsJSON);
              try
                ValidateArguments(LTool, LArguments);
              finally
                LArguments.Free;
              end;
              if AWriteAuthorized and (LTool.ToJSON <> LWriteDescriptor) then
                raise EArgumentException.Create('Die Werkzeugdeklaration hat sich seit der Schreibfreigabe geaendert.');
              if not AWriteAuthorized and not ToolIsReadOnly(LTool) then
              begin
                LWriteDescriptor := LTool.ToJSON;
                Exit;
              end;
              LResult := ParseObject(LSelected.CallToolJSON(AProjectFile, LTool.GetValue<string>('name'), LArgumentsJSON));
              Exit;
            end;
            raise EArgumentException.Create('Das angeforderte Werkzeug ist in der Projekterweiterung nicht verfuegbar.');
          finally
            LTools.Free;
          end;
        finally
          LIds.Free;
          LProvider := nil;
          LSelected := nil;
        end;
      end);
  end;

begin
  RequireProject(AProjectFile);
  if not ValidIdentifier(AExtensionId, 64) or not ValidIdentifier(AToolName, 128) then
    raise EArgumentException.Create('extension und tool muessen gueltige Kennungen sein.');
  if Assigned(AArguments) then
    LArgumentsJSON := AArguments.ToJSON
  else
    LArgumentsJSON := '{}';
  RequireJSONSize(LArgumentsJSON, CMaximumArgumentBytes);
  LResult := nil;
  try
    Dispatch(False);
    if LWriteDescriptor <> '' then
    begin
      if not Assigned(AAuthorizeWrite) then
        raise EAbort.Create('Eine Schreibfreigabe fuer dieses Projektwerkzeug ist erforderlich.');
      // A permission dialog can pump messages and close the project or unload
      // its provider. Resolve and validate again with no retained references.
      AAuthorizeWrite();
      Dispatch(True);
    end;
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

end.
