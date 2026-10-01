unit h5u.DAI.OTA.Designer;

interface

uses
  System.JSON;

type
  TDAIDesignerService = class sealed
  public
    class function InspectForm(const AFileName: string): TJSONObject; static;
    class function ShowDesigner(const AFileName: string): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  System.TypInfo,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings,
  h5u.DAI.Types;

const
  CMaximumComponents = 4096;
  CMaximumPropertyCharacters = 4096;

function DesignerFileName(const AFileName: string): string;
var
  LExtension: string;
begin
  if Trim(AFileName) = '' then
    raise EArgumentException.Create('Eine Form-Unit oder Formulardatei ist erforderlich.');
  Result := TDAISettings.Instance.ExpandPath(AFileName);
  LExtension := TPath.GetExtension(Result);
  if not SameText(LExtension, '.pas') and not SameText(LExtension, '.dfm') and not SameText(LExtension, '.fmx') then
    raise EArgumentException.Create('file muss auf eine .pas-, .dfm- oder .fmx-Datei zeigen.');
  if not TDAIOTA.IsWorkspaceFile(Result) and not TDAIOTA.IsReadOnlyReferenceFile(Result) then
    raise EDAIAccessDenied.Create('Designerzugriff ist nur für Workspace- und freigegebene Referenzdateien erlaubt.');
end;

function FindFormEditor(const AFileName: string): IOTAFormEditor;
begin
  Result := TDAIOTA.FindFormEditor(AFileName);
end;

function TryComponentString(const AComponent: IOTAComponent; const APropertyName: string; out AValue: string): Boolean;
var
  LAnsi: AnsiString;
  LShort: ShortString;
  LWide: WideString;
begin
  Result := False;
  AValue := '';
  if not Assigned(AComponent) then
    Exit;
  case AComponent.GetPropTypeByName(APropertyName) of
    tkString:
      begin
        LShort := '';
        Result := AComponent.GetPropValueByName(APropertyName, LShort);
        if Result then
          AValue := string(LShort);
      end;
    tkLString:
      begin
        Result := AComponent.GetPropValueByName(APropertyName, LAnsi);
        if Result then
          AValue := string(LAnsi);
      end;
    tkWString:
      begin
        Result := AComponent.GetPropValueByName(APropertyName, LWide);
        if Result then
          AValue := string(LWide);
      end;
    tkUString:
      Result := AComponent.GetPropValueByName(APropertyName, AValue);
  end;
  if not Result then
    AValue := '';
end;

function ComponentString(const AComponent: IOTAComponent; const APropertyName: string): string;
begin
  TryComponentString(AComponent, APropertyName, Result);
end;

function ScalarProperty(const AComponent: IOTAComponent; const AName: string; const AKind: TTypeKind): TJSONValue;
var
  LNative: INTAComponent;
  LNumber: Double;
  LPersistent: TPersistent;
  LPropInfo: PPropInfo;
  LText: string;
begin
  Result := nil;
  if AKind in [tkString, tkLString, tkWString, tkUString] then
  begin
    if not TryComponentString(AComponent, AName, LText) then
      Exit;
    if Length(LText) > CMaximumPropertyCharacters then
      SetLength(LText, CMaximumPropertyCharacters);
    Exit(TJSONString.Create(LText));
  end;

  // Native RTTI determines the exact ordinal/float storage type; an untyped
  // GetPropValue buffer cannot safely assume the size of every property.
  if not Supports(AComponent, INTAComponent, LNative) then
    Exit;
  LPersistent := LNative.GetPersistent;
  if not Assigned(LPersistent) then
    Exit;
  LPropInfo := GetPropInfo(LPersistent, AName);
  if not Assigned(LPropInfo) then
    Exit;
  case AKind of
    tkInteger:
      if GetTypeData(LPropInfo.PropType^).OrdType = otULong then
        Result := TJSONNumber.Create(Int64(Cardinal(GetOrdProp(LPersistent, LPropInfo))))
      else
        Result := TJSONNumber.Create(Int64(GetOrdProp(LPersistent, LPropInfo)));
    tkInt64:
      Result := TJSONNumber.Create(GetInt64Prop(LPersistent, LPropInfo));
    tkEnumeration:
      if SameText(string(LPropInfo.PropType^.Name), 'Boolean') then
        Result := TJSONBool.Create(GetOrdProp(LPersistent, LPropInfo) <> 0)
      else
        Result := TJSONString.Create(GetEnumProp(LPersistent, LPropInfo));
    tkFloat:
      begin
        LNumber := Double(GetFloatProp(LPersistent, LPropInfo));
        if not IsNan(LNumber) and not IsInfinite(LNumber) then
          Result := TJSONNumber.Create(LNumber);
      end;
    tkChar, tkWChar:
      Result := TJSONString.Create(string(Char(GetOrdProp(LPersistent, LPropInfo))));
  end;
end;

function ComponentJson(const AComponent: IOTAComponent): TJSONObject;
var
  LIndex: Integer;
  LKind: TTypeKind;
  LName: string;
  LParent: IOTAComponent;
  LProperties: TJSONArray;
  LProperty: TJSONObject;
  LValue: TJSONValue;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('name', ComponentString(AComponent, 'Name'));
    Result.AddPair('type', AComponent.GetComponentType);
    Result.AddPair('is_control', TJSONBool.Create(AComponent.IsTControl));
    LParent := AComponent.GetParent;
    if Assigned(LParent) then
      Result.AddPair('parent', ComponentString(LParent, 'Name'))
    else
      Result.AddPair('parent', TJSONNull.Create);
    LProperties := TJSONArray.Create;
    Result.AddPair('properties', LProperties);
    for LIndex := 0 to AComponent.GetPropCount - 1 do
    begin
      LName := AComponent.GetPropName(LIndex);
      LKind := AComponent.GetPropType(LIndex);
      LProperty := TJSONObject.Create;
      LProperties.AddElement(LProperty);
      LProperty.AddPair('name', LName);
      LProperty.AddPair('kind', GetEnumName(TypeInfo(TTypeKind), Ord(LKind)));
      try
        LValue := ScalarProperty(AComponent, LName, LKind);
        LProperty.AddPair('value_available', TJSONBool.Create(Assigned(LValue)));
        if Assigned(LValue) then
          LProperty.AddPair('value', LValue);
      except
        on E: Exception do
        begin
          LProperty.AddPair('value_available', TJSONBool.Create(False));
          LProperty.AddPair('read_error', E.Message);
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure CollectComponents(const AComponent: IOTAComponent; const AItems: TJSONArray; const ASeen: TDictionary<Pointer, Boolean>; var ATruncated: Boolean);
var
  LHandle: Pointer;
  LIndex: Integer;
begin
  if not Assigned(AComponent) then
    Exit;
  LHandle := AComponent.GetComponentHandle;
  if ASeen.ContainsKey(LHandle) then
    Exit;
  if AItems.Count >= CMaximumComponents then
  begin
    ATruncated := True;
    Exit;
  end;
  ASeen.Add(LHandle, True);
  AItems.AddElement(ComponentJson(AComponent));
  for LIndex := 0 to AComponent.GetComponentCount - 1 do
    CollectComponents(AComponent.GetComponent(LIndex), AItems, ASeen, ATruncated);
  for LIndex := 0 to AComponent.GetControlCount - 1 do
    CollectComponents(AComponent.GetControl(LIndex), AItems, ASeen, ATruncated);
end;

class function TDAIDesignerService.InspectForm(const AFileName: string): TJSONObject;
var
  LFileName: string;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LComponents: TJSONArray;
        LFormEditor: IOTAFormEditor;
        LIndex: Integer;
        LRoot: IOTAComponent;
        LSeen: TDictionary<Pointer, Boolean>;
        LSelected: IOTAComponent;
        LSelection: TJSONArray;
        LTruncated: Boolean;
      begin
        LFormEditor := FindFormEditor(LFileName);
        if not Assigned(LFormEditor) then
          raise EInvalidOperation.Create('Kein geladener Formdesigner gefunden. Öffnen Sie zuerst die Form-Unit mit file_open.');
        LRoot := LFormEditor.GetRootComponent;
        if not Assigned(LRoot) then
          raise EInvalidOperation.Create('Der Formdesigner enthält keine Root-Komponente.');
        LResult.AddPair('file', LFormEditor.FileName);
        LResult.AddPair('module_file', LFormEditor.Module.FileName);
        LResult.AddPair('root_name', ComponentString(LRoot, 'Name'));
        LResult.AddPair('root_type', LRoot.GetComponentType);
        LResult.AddPair('modified', TJSONBool.Create(LFormEditor.Modified));
        LResult.AddPair('string_values_maximum_characters', TJSONNumber.Create(CMaximumPropertyCharacters));
        LComponents := TJSONArray.Create;
        LResult.AddPair('components', LComponents);
        LSeen := TDictionary<Pointer, Boolean>.Create;
        try
          LTruncated := False;
          CollectComponents(LRoot, LComponents, LSeen, LTruncated);
          LResult.AddPair('components_truncated', TJSONBool.Create(LTruncated));
        finally
          LSeen.Free;
        end;
        LSelection := TJSONArray.Create;
        LResult.AddPair('selection', LSelection);
        for LIndex := 0 to LFormEditor.GetSelCount - 1 do
        begin
          LSelected := LFormEditor.GetSelComponent(LIndex);
          if Assigned(LSelected) then
            LSelection.Add(ComponentString(LSelected, 'Name'));
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDesignerService.ShowDesigner(const AFileName: string): TJSONObject;
var
  LFileName: string;
  LFormEditor: IOTAFormEditor;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LFormEditor := TDAIOTA.EnsureFormDesigner(LFileName);
  if not Assigned(LFormEditor) then
    raise EInvalidOperation.CreateFmt('Die angegebene Datei hat keinen verfügbaren Formdesigner: %s', [LFileName]);
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      begin
        LResult.AddPair('file', LFormEditor.FileName);
        LResult.AddPair('shown', TJSONBool.Create(True));
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

end.
