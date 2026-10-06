unit h5u.DAI.OTA.Designer;

interface

uses
  System.JSON;

type
  TDAIDesignerService = class sealed
  public
    class function InspectForm(const AFileName: string): TJSONObject; static;
    class function ShowDesigner(const AFileName: string): TJSONObject; static;
    class function SearchComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function SelectComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function ReadProperties(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function SetProperty(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function MoveComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
    class function CreateComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  System.TypInfo,
  DesignIntf,
  DesignEditors,
  Vcl.Controls,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Source.Regex,
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

type
  TDesignerComponentAccess = class(TComponent);

  TDesignerPropertyList = class
  public
    Items: TList<IProperty>;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AProperty: IProperty);
    function Find(const AName: string): IProperty;
  end;

  TDesignerValueList = class
  public
    Items: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AValue: string);
  end;

  TDesignerPropertyChange = record
    PropertyName: string;
    Editor: IProperty;
    Text: string;
  end;

  // Some registered nested editors (notably set elements) share a property
  // table owned by their parent editor. Keep the entire path alive until the
  // returned editor is released, rather than retaining only its last element.
  TDesignerPropertyHandle = class(TInterfacedObject, IProperty)
  private
    FProperty: IProperty;
    FParents: TArray<IProperty>;
  public
    constructor Create(const AProperty: IProperty; const AParents: TArray<IProperty>);
    procedure Activate;
    function AllEqual: Boolean;
    function AutoFill: Boolean;
    procedure Edit;
    function HasInstance(Instance: TPersistent): Boolean;
    function GetAttributes: TPropertyAttributes;
    function GetEditLimit: Integer;
    function GetEditValue(out Value: string): Boolean;
    function GetName: string;
    procedure GetProperties(Proc: TGetPropProc);
    function GetPropInfo: PPropInfo;
    function GetPropType: PTypeInfo;
    function GetValue: string;
    procedure GetValues(Proc: TGetStrProc);
    procedure Revert;
    procedure SetValue(const Value: string);
    function ValueAvailable: Boolean;
  end;

constructor TDesignerPropertyHandle.Create(const AProperty: IProperty; const AParents: TArray<IProperty>);
begin
  inherited Create;
  FProperty := AProperty;
  FParents := Copy(AParents);
end;

procedure TDesignerPropertyHandle.Activate;
begin
  FProperty.Activate;
end;

function TDesignerPropertyHandle.AllEqual: Boolean;
begin
  Result := FProperty.AllEqual;
end;

function TDesignerPropertyHandle.AutoFill: Boolean;
begin
  Result := FProperty.AutoFill;
end;

procedure TDesignerPropertyHandle.Edit;
begin
  FProperty.Edit;
end;

function TDesignerPropertyHandle.HasInstance(Instance: TPersistent): Boolean;
begin
  Result := FProperty.HasInstance(Instance);
end;

function TDesignerPropertyHandle.GetAttributes: TPropertyAttributes;
begin
  Result := FProperty.GetAttributes;
end;

function TDesignerPropertyHandle.GetEditLimit: Integer;
begin
  Result := FProperty.GetEditLimit;
end;

function TDesignerPropertyHandle.GetEditValue(out Value: string): Boolean;
begin
  Result := FProperty.GetEditValue(Value);
end;

function TDesignerPropertyHandle.GetName: string;
begin
  Result := FProperty.GetName;
end;

procedure TDesignerPropertyHandle.GetProperties(Proc: TGetPropProc);
begin
  FProperty.GetProperties(Proc);
end;

function TDesignerPropertyHandle.GetPropInfo: PPropInfo;
begin
  Result := FProperty.GetPropInfo;
end;

function TDesignerPropertyHandle.GetPropType: PTypeInfo;
begin
  Result := FProperty.GetPropType;
end;

function TDesignerPropertyHandle.GetValue: string;
begin
  Result := FProperty.GetValue;
end;

procedure TDesignerPropertyHandle.GetValues(Proc: TGetStrProc);
begin
  FProperty.GetValues(Proc);
end;

procedure TDesignerPropertyHandle.Revert;
begin
  FProperty.Revert;
end;

procedure TDesignerPropertyHandle.SetValue(const Value: string);
begin
  FProperty.SetValue(Value);
end;

function TDesignerPropertyHandle.ValueAvailable: Boolean;
begin
  Result := FProperty.ValueAvailable;
end;

constructor TDesignerPropertyList.Create;
begin
  inherited Create;
  Items := TList<IProperty>.Create;
end;

destructor TDesignerPropertyList.Destroy;
begin
  Items.Free;
  inherited;
end;

procedure TDesignerPropertyList.Add(const AProperty: IProperty);
begin
  if Assigned(AProperty) then
    Items.Add(AProperty);
end;

function TDesignerPropertyList.Find(const AName: string): IProperty;
var
  LProperty: IProperty;
begin
  Result := nil;
  for LProperty in Items do
    if SameText(LProperty.GetName, AName) then
      Exit(LProperty);
end;

constructor TDesignerValueList.Create;
begin
  inherited Create;
  Items := TStringList.Create;
  Items.CaseSensitive := False;
end;

destructor TDesignerValueList.Destroy;
begin
  Items.Free;
  inherited;
end;

procedure TDesignerValueList.Add(const AValue: string);
begin
  if Items.Count < CMaximumComponents then
    Items.Add(AValue);
end;

function DesignerArgument(const AArguments: TJSONObject; const AName: string): TJSONValue;
begin
  if not Assigned(AArguments) then
    raise EArgumentException.Create('Designerargumente fehlen.');
  Result := AArguments.GetValue(AName);
end;

function DesignerString(const AArguments: TJSONObject; const AName: string; const ADefault: string = ''): string;
var
  LValue: TJSONValue;
begin
  LValue := DesignerArgument(AArguments, AName);
  if not Assigned(LValue) then
    Exit(ADefault);
  if not (LValue is TJSONString) then
    raise EArgumentException.CreateFmt('%s muss eine Zeichenfolge sein.', [AName]);
  Result := LValue.Value;
  if (Length(Result) > CMaximumPropertyCharacters) or (Pos(#0, Result) <> 0) then
    raise EArgumentException.CreateFmt('%s ist zu lang oder enthält NUL.', [AName]);
end;

function DesignerRequiredString(const AArguments: TJSONObject; const AName: string): string;
begin
  Result := Trim(DesignerString(AArguments, AName));
  if Result = '' then
    raise EArgumentException.CreateFmt('%s ist erforderlich.', [AName]);
end;

function DesignerBoolean(const AArguments: TJSONObject; const AName: string; const ADefault: Boolean): Boolean;
var
  LValue: TJSONValue;
begin
  LValue := DesignerArgument(AArguments, AName);
  if not Assigned(LValue) then
    Exit(ADefault);
  if not (LValue is TJSONBool) then
    raise EArgumentException.CreateFmt('%s muss ein Boolean sein.', [AName]);
  Result := TJSONBool(LValue).AsBoolean;
end;

function JsonInteger(const AValue: TJSONValue; out AResult: Int64): Boolean;
var
  LNumber: Double;
begin
  LNumber := 0;
  Result := (AValue is TJSONNumber) and TryStrToInt64(AValue.Value, AResult);
  if Result or not (AValue is TJSONNumber) then
    Exit;
  // Exponential/decimal integer JSON is accepted only where Double is exact.
  Result := TryStrToFloat(AValue.Value, LNumber, TFormatSettings.Invariant) and
    not IsNan(LNumber) and not IsInfinite(LNumber) and
    (Abs(LNumber) <= 9007199254740991.0) and (Frac(LNumber) = 0);
  if Result then
    AResult := Trunc(LNumber);
end;

function DesignerInteger(const AArguments: TJSONObject; const AName: string; const ADefault: Integer): Integer;
var
  LValue: TJSONValue;
  LInteger: Int64;
begin
  LValue := DesignerArgument(AArguments, AName);
  if not Assigned(LValue) then
    Exit(ADefault);
  if not JsonInteger(LValue, LInteger) or (LInteger < Low(Integer)) or (LInteger > High(Integer)) then
    raise EArgumentOutOfRangeException.CreateFmt('%s muss eine 32-Bit-Ganzzahl sein.', [AName]);
  Result := Integer(LInteger);
end;

function DesignerNumber(const AArguments: TJSONObject; const AName: string; const ADefault: Double): Double;
var
  LValue: TJSONValue;
begin
  LValue := DesignerArgument(AArguments, AName);
  if not Assigned(LValue) then
    Exit(ADefault);
  Result := 0;
  if not (LValue is TJSONNumber) or not TryStrToFloat(LValue.Value, Result, TFormatSettings.Invariant) or
    IsNan(Result) or IsInfinite(Result) then
    raise EArgumentException.CreateFmt('%s muss eine endliche JSON-Zahl sein.', [AName]);
end;

function NativeComponent(const AComponent: IOTAComponent): TComponent;
var
  LNative: INTAComponent;
begin
  Result := nil;
  if Assigned(AComponent) and Supports(AComponent, INTAComponent, LNative) then
    Result := LNative.GetComponent;
  if not Assigned(Result) then
    raise EInvalidOperation.Create('Die Komponente bietet keinen nativen Designerzugriff.');
end;

function NativePersistent(const AComponent: IOTAComponent): TPersistent;
var
  LNative: INTAComponent;
begin
  Result := nil;
  if Assigned(AComponent) and Supports(AComponent, INTAComponent, LNative) then
    Result := LNative.GetPersistent;
  if not Assigned(Result) then
    raise EInvalidOperation.Create('Die Komponente bietet keinen nativen Propertyzugriff.');
end;

function LoadedDesigner(const AFileName: string): IOTAFormEditor;
begin
  Result := FindFormEditor(AFileName);
  if not Assigned(Result) then
    raise EInvalidOperation.Create('Kein geladener Formdesigner gefunden. Öffnen Sie zuerst die Form-Unit mit file_open.');
  if not Assigned(Result.GetRootComponent) then
    raise EInvalidOperation.Create('Der Formdesigner enthält keine Root-Komponente.');
end;

function NativeDesigner(const AFormEditor: IOTAFormEditor): IDesigner;
var
  LNative: INTAFormEditor;
begin
  Result := nil;
  if Supports(AFormEditor, INTAFormEditor, LNative) then
    Result := LNative.GetFormDesigner;
  if not Assigned(Result) then
    raise EInvalidOperation.Create('Der Formdesigner bietet keine registrierten Propertyeditoren.');
end;

procedure RequireWritableDesignerPath(const AFileName: string);
var
  LAttributes: DWORD;
begin
  if (Trim(AFileName) = '') or TDAIOTA.IsReadOnlyReferenceFile(AFileName) or
    not TDAIOTA.IsWorkspaceFile(AFileName) then
    raise EDAIAccessDenied.Create('Designeränderungen sind nur in geladenen Workspace-Dateien erlaubt.');
  TDAIOTA.RequireNoReparseWritePath(AFileName);
  LAttributes := GetFileAttributesW(PWideChar(AFileName));
  if (LAttributes <> INVALID_FILE_ATTRIBUTES) and ((LAttributes and FILE_ATTRIBUTE_READONLY) <> 0) then
    raise EDAIAccessDenied.CreateFmt('Die Designerdatei ist schreibgeschützt: %s', [AFileName]);
end;

procedure RequireWritableDesigner(const AFormEditor: IOTAFormEditor; const ADesigner: IDesigner);
var
  LModule: IOTAModule;
  LEditor: IOTAEditor;
  LBuffer: IOTAEditBuffer;
  LIndex: Integer;
begin
  RequireWritableDesignerPath(AFormEditor.FileName);
  if ADesigner.IsSourceReadOnly then
    raise EDAIAccessDenied.Create('Der Quelltext des Designers ist in der IDE schreibgeschützt.');
  LModule := AFormEditor.Module;
  if not Assigned(LModule) then
    raise EInvalidOperation.Create('Der Designer hat kein zugehöriges Quelltextmodul.');
  RequireWritableDesignerPath(LModule.FileName);
  for LIndex := 0 to LModule.ModuleFileCount - 1 do
  begin
    LEditor := LModule.ModuleFileEditors[LIndex];
    if not Assigned(LEditor) then
      Continue;
    RequireWritableDesignerPath(LEditor.FileName);
    if Supports(LEditor, IOTAEditBuffer, LBuffer) then
      if LBuffer.IsReadOnly then
        raise EDAIAccessDenied.CreateFmt('Der Editorpuffer ist schreibgeschützt: %s', [LEditor.FileName]);
  end;
end;

function RequiredComponent(const AFormEditor: IOTAFormEditor; const AName: string): IOTAComponent;
var
  LRoot: IOTAComponent;
begin
  Result := AFormEditor.FindComponent(AName);
  LRoot := AFormEditor.GetRootComponent;
  if not Assigned(Result) and SameText(ComponentString(LRoot, 'Name'), AName) then
    Result := LRoot;
  if not Assigned(Result) then
    raise EArgumentException.CreateFmt('Komponente nicht gefunden: %s', [AName]);
end;

function BelongsToRoot(const AComponent, ARoot: TComponent): Boolean;
var
  LCurrent: TComponent;
  LDepth: Integer;
begin
  LCurrent := AComponent;
  for LDepth := 0 to CMaximumComponents do
  begin
    if LCurrent = ARoot then
      Exit(True);
    if not Assigned(LCurrent) then
      Break;
    LCurrent := LCurrent.Owner;
  end;
  Result := False;
end;

function ClassHasName(AClass: TClass; const AName: string): Boolean;
begin
  while Assigned(AClass) do
  begin
    if AClass.ClassNameIs(AName) then
      Exit(True);
    AClass := AClass.ClassParent;
  end;
  Result := False;
end;

function ComponentSummary(const AComponent: IOTAComponent): TJSONObject;
var
  LNative: INTAComponent;
  LParent: IOTAComponent;
  LComponent, LNativeParent: TComponent;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('name', ComponentString(AComponent, 'Name'));
    Result.AddPair('type', AComponent.GetComponentType);
    LParent := AComponent.GetParent;
    LNativeParent := nil;
    LComponent := nil;
    if Supports(AComponent, INTAComponent, LNative) then
      LComponent := LNative.GetComponent;
    if Assigned(LComponent) then
      LNativeParent := LComponent.GetParentComponent;
    if Assigned(LComponent) then
    begin
      if Assigned(LComponent.Owner) then
        Result.AddPair('owner', LComponent.Owner.Name)
      else
        Result.AddPair('owner', TJSONNull.Create);
    end;
    if Assigned(LNativeParent) then
      Result.AddPair('parent', LNativeParent.Name)
    else
    begin
      if not Assigned(LComponent) and Assigned(LParent) then
        Result.AddPair('parent', ComponentString(LParent, 'Name'))
      else
        Result.AddPair('parent', TJSONNull.Create);
    end;
    Result.AddPair('is_control', TJSONBool.Create(AComponent.IsTControl));
  except
    Result.Free;
    raise;
  end;
end;

procedure CollectDesignerComponents(const AComponent: IOTAComponent; const AItems: TList<IOTAComponent>; const ASeen: TDictionary<Pointer, Boolean>; var ATruncated: Boolean);
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
  AItems.Add(AComponent);
  for LIndex := 0 to AComponent.GetComponentCount - 1 do
    CollectDesignerComponents(AComponent.GetComponent(LIndex), AItems, ASeen, ATruncated);
  for LIndex := 0 to AComponent.GetControlCount - 1 do
    CollectDesignerComponents(AComponent.GetControl(LIndex), AItems, ASeen, ATruncated);
end;

function ComponentSelection(const AFormEditor: IOTAFormEditor): TJSONArray;
var
  LIndex: Integer;
  LComponent: IOTAComponent;
begin
  Result := TJSONArray.Create;
  try
    for LIndex := 0 to AFormEditor.GetSelCount - 1 do
    begin
      LComponent := AFormEditor.GetSelComponent(LIndex);
      if Assigned(LComponent) then
        Result.Add(ComponentString(LComponent, 'Name'));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function DesignerProperties(const AComponent: IOTAComponent; const ADesigner: IDesigner): TDesignerPropertyList;
var
  LSelection: IDesignerSelections;
begin
  Result := TDesignerPropertyList.Create;
  try
    LSelection := TDesignerSelections.Create;
    LSelection.Add(NativePersistent(AComponent));
    GetComponentProperties(LSelection, tkAny, ADesigner, Result.Add);
  except
    Result.Free;
    raise;
  end;
end;

function FindDesignerProperty(const AComponent: IOTAComponent; const ADesigner: IDesigner; const APath: string): IProperty;
var
  LNames: TArray<string>;
  LIndex: Integer;
  LProperties, LNested: TDesignerPropertyList;
  LParents: TList<IProperty>;
begin
  if (APath = '') or (Length(APath) > 512) then
    raise EArgumentException.Create('property muss einen Propertynamen oder Pfad enthalten.');
  LNames := APath.Split(['.']);
  if Length(LNames) > 16 then
    raise EArgumentException.Create('Der Propertypfad darf höchstens 16 Ebenen enthalten.');
  LProperties := DesignerProperties(AComponent, ADesigner);
  LParents := TList<IProperty>.Create;
  try
    Result := nil;
    for LIndex := 0 to High(LNames) do
    begin
      if Trim(LNames[LIndex]) = '' then
        raise EArgumentException.CreateFmt('Ungültiger Propertypfad: %s', [APath]);
      Result := LProperties.Find(LNames[LIndex]);
      if not Assigned(Result) then
        raise EArgumentException.CreateFmt('Designerproperty nicht gefunden: %s', [APath]);
      if not Assigned(Result.GetPropType) then
        raise EInvalidOperation.CreateFmt('Die Designerproperty bietet keine Typinformationen: %s', [APath]);
      LParents.Add(Result);
      if LIndex < High(LNames) then
      begin
        if not (paSubProperties in Result.GetAttributes) then
          raise EArgumentException.CreateFmt('Die Property bietet keine Unterproperties: %s', [LNames[LIndex]]);
        LNested := TDesignerPropertyList.Create;
        try
          Result.GetProperties(LNested.Add);
        except
          LNested.Free;
          raise;
        end;
        LProperties.Free;
        LProperties := LNested;
      end;
    end;
    Result := TDesignerPropertyHandle.Create(Result, LParents.ToArray);
  finally
    LParents.Free;
    LProperties.Free;
  end;
end;

function NativePropertyOwner(const AComponent: IOTAComponent; const APath: string; const ARoot: TComponent; const AForWrite: Boolean; out APropInfo: PPropInfo): TPersistent;
var
  LNames: TArray<string>;
  LIndex: Integer;
  LObject: TObject;
begin
  Result := NativePersistent(AComponent);
  APropInfo := nil;
  LNames := APath.Split(['.']);
  for LIndex := 0 to High(LNames) do
  begin
    if AForWrite then
      if Result is TComponent then
        if not BelongsToRoot(TComponent(Result), ARoot) then
          raise EDAIAccessDenied.Create('Properties von Komponenten anderer Designer können hier nicht verändert werden.');
    APropInfo := GetPropInfo(Result, LNames[LIndex]);
    if not Assigned(APropInfo) then
      Exit(nil);
    if LIndex < High(LNames) then
    begin
      if APropInfo.PropType^.Kind <> tkClass then
        Exit(nil);
      LObject := GetObjectProp(Result, APropInfo);
      if not (LObject is TPersistent) then
        Exit(nil);
      Result := TPersistent(LObject);
    end;
  end;
end;

function NativePropertyValue(const AComponent: IOTAComponent; const APath: string): TJSONValue;
var
  LOwner: TPersistent;
  LInfo: PPropInfo;
  LObject: TObject;
  LText: string;
  LNumber: Double;
begin
  Result := nil;
  LOwner := NativePropertyOwner(AComponent, APath, nil, False, LInfo);
  if not Assigned(LOwner) or not Assigned(LInfo) then
    Exit;
  case LInfo.PropType^.Kind of
    tkInteger:
      if GetTypeData(LInfo.PropType^).OrdType = otULong then
        Result := TJSONNumber.Create(Int64(Cardinal(GetOrdProp(LOwner, LInfo))))
      else
        Result := TJSONNumber.Create(Int64(GetOrdProp(LOwner, LInfo)));
    tkInt64:
      Result := TJSONNumber.Create(GetInt64Prop(LOwner, LInfo));
    tkEnumeration:
      if SameText(string(LInfo.PropType^.Name), 'Boolean') then
        Result := TJSONBool.Create(GetOrdProp(LOwner, LInfo) <> 0)
      else
        Result := TJSONString.Create(GetEnumProp(LOwner, LInfo));
    tkFloat:
      begin
        LNumber := Double(GetFloatProp(LOwner, LInfo));
        if not IsNan(LNumber) and not IsInfinite(LNumber) then
          Result := TJSONNumber.Create(LNumber);
      end;
    tkChar, tkWChar:
      Result := TJSONString.Create(string(Char(GetOrdProp(LOwner, LInfo))));
    tkString, tkLString, tkWString, tkUString:
      begin
        LText := GetStrProp(LOwner, LInfo);
        if Length(LText) > CMaximumPropertyCharacters then
          SetLength(LText, CMaximumPropertyCharacters);
        Result := TJSONString.Create(LText);
      end;
    tkSet:
      Result := TJSONString.Create(GetSetProp(LOwner, LInfo, True));
    tkClass:
      begin
        LObject := GetObjectProp(LOwner, LInfo);
        if not Assigned(LObject) then
          Result := TJSONNull.Create
        else if LObject is TComponent then
          Result := TJSONString.Create(TComponent(LObject).Name);
      end;
  end;
end;

function DesignerPropertyJson(const AComponent: IOTAComponent; const APath: string; const AProperty: IProperty): TJSONObject;
var
  LValue: TJSONValue;
  LText: string;
  LType: PTypeInfo;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('name', APath);
    LType := AProperty.GetPropType;
    if not Assigned(LType) then
      raise EInvalidOperation.CreateFmt('Die Designerproperty bietet keine Typinformationen: %s', [APath]);
    Result.AddPair('kind', GetEnumName(TypeInfo(TTypeKind), Ord(LType^.Kind)));
    Result.AddPair('read_only', TJSONBool.Create(paReadOnly in AProperty.GetAttributes));
    Result.AddPair('has_subproperties', TJSONBool.Create(paSubProperties in AProperty.GetAttributes));
    try
      LText := AProperty.GetValue;
      if Length(LText) > CMaximumPropertyCharacters then
        SetLength(LText, CMaximumPropertyCharacters);
      Result.AddPair('display_value', LText);
      LValue := NativePropertyValue(AComponent, APath);
      if not Assigned(LValue) and (AProperty.GetPropType^.Kind = tkSet) and
        (SameText(LText, 'True') or SameText(LText, 'False')) then
        LValue := TJSONBool.Create(SameText(LText, 'True'));
      Result.AddPair('value_available', TJSONBool.Create(Assigned(LValue)));
      if Assigned(LValue) then
        Result.AddPair('value', LValue);
    except
      on E: Exception do
      begin
        Result.AddPair('value_available', TJSONBool.Create(False));
        Result.AddPair('read_error', E.Message);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function CheckedPropertyText(const AFormEditor: IOTAFormEditor; const AComponent: IOTAComponent; const APath: string; const AProperty: IProperty; const AValue: TJSONValue): string;
var
  LKind: TTypeKind;
  LData: PTypeData;
  LInteger, LMinimum, LMaximum: Int64;
  LNumber: Extended;
  LInfo: PPropInfo;
  LOwner: TPersistent;
  LRoot, LReference: TComponent;
  LValues: TDesignerValueList;
  LExisting: IOTAComponent;
  LIsBoolean: Boolean;
  LParentInfo: PPropInfo;
  LParentPath: string;
begin
  if not Assigned(AValue) then
    raise EArgumentException.Create('value ist erforderlich.');
  if (AValue is TJSONArray) or (AValue is TJSONObject) then
    raise EArgumentException.Create('value muss ein JSON-Skalar sein.');
  if AValue is TJSONString then
    if (Length(AValue.Value) > CMaximumPropertyCharacters) or (Pos(#0, AValue.Value) <> 0) then
      raise EArgumentException.Create('Der Propertywert ist zu lang oder enthält NUL.');
  if (paReadOnly in AProperty.GetAttributes) or not AProperty.ValueAvailable then
    raise EDAIAccessDenied.CreateFmt('Die Designerproperty ist schreibgeschützt oder nicht verfügbar: %s', [APath]);
  LRoot := NativeComponent(AFormEditor.GetRootComponent);
  LOwner := NativePropertyOwner(AComponent, APath, LRoot, True, LInfo);
  if not Assigned(LOwner) then
  begin
    // Registered set-element editors are synthetic Boolean subproperties.
    // Other unresolved paths cannot establish which object would be changed.
    LParentPath := Copy(APath, 1, LastDelimiter('.', APath) - 1);
    if LParentPath = '' then
      raise EArgumentException.Create('Der native Zielpfad der Property ist nicht prüfbar.');
    LOwner := NativePropertyOwner(AComponent, LParentPath, LRoot, True, LParentInfo);
    if not Assigned(LOwner) or not Assigned(LParentInfo) then
      raise EArgumentException.Create('Nur sicher auflösbare Designerpropertypfade können verändert werden.');
    if LParentInfo.PropType^.Kind <> tkSet then
      raise EArgumentException.Create('Nur sicher auflösbare Designerpropertypfade können verändert werden.');
    LInfo := LParentInfo;
  end;
  if Assigned(LOwner) and Assigned(LInfo) then
    if not Assigned(LInfo.SetProc) then
      raise EDAIAccessDenied.CreateFmt('Die Property hat keinen Setter: %s', [APath]);
  LKind := AProperty.GetPropType^.Kind;
  LData := GetTypeData(AProperty.GetPropType);
  LValues := TDesignerValueList.Create;
  try
    if paValueList in AProperty.GetAttributes then
      AProperty.GetValues(LValues.Add);
    LIsBoolean := (LValues.Items.Count = 2) and
      (LValues.Items.IndexOf('True') >= 0) and (LValues.Items.IndexOf('False') >= 0);
    if LIsBoolean then
    begin
      if AValue is TJSONBool then
      begin
        if TJSONBool(AValue).AsBoolean then
          Exit('True')
        else
          Exit('False');
      end;
      if (AValue is TJSONString) and (LValues.Items.IndexOf(AValue.Value) >= 0) then
        Exit(LValues.Items[LValues.Items.IndexOf(AValue.Value)]);
      raise EArgumentException.CreateFmt('%s benötigt einen Boolean.', [APath]);
    end;
    case LKind of
      tkString, tkLString, tkWString, tkUString, tkChar, tkWChar, tkMethod:
        begin
          if not (AValue is TJSONString) then
            raise EArgumentException.CreateFmt('%s benötigt eine Zeichenfolge.', [APath]);
          Result := AValue.Value;
          if (Length(Result) > CMaximumPropertyCharacters) or (Pos(#0, Result) <> 0) then
            raise EArgumentException.Create('Der Propertywert ist zu lang oder enthält NUL.');
          if (LKind in [tkChar, tkWChar]) and (Length(Result) <> 1) then
            raise EArgumentException.Create('Eine Zeichenproperty benötigt genau ein UTF-16-Zeichen.');
          if LKind = tkChar then
            if Ord(Result[1]) > 255 then
              raise EArgumentOutOfRangeException.Create('Eine AnsiChar-Property benötigt ein Zeichen im Bereich 0 bis 255.');
          if (LKind = tkString) and (Length(Result) > LData.MaxLength) then
            raise EArgumentOutOfRangeException.Create('Der Wert überschreitet die ShortString-Länge.');
          if SameText(APath, 'Name') or
            ((LastDelimiter('.', APath) > 0) and SameText(Copy(APath, LastDelimiter('.', APath) + 1, MaxInt), 'Name')) then
          begin
            if LOwner is TComponent then
            begin
              if not IsValidIdent(Result) or (Result = '') then
                raise EArgumentException.Create('Name muss ein gültiger Delphi-Bezeichner sein.');
              if AProperty.GetEditLimit > 0 then
                if Length(Result) > AProperty.GetEditLimit then
                  raise EArgumentOutOfRangeException.Create('Name überschreitet die Länge des registrierten Propertyeditors.');
              LExisting := AFormEditor.FindComponent(Result);
              if Assigned(LExisting) then
                if NativeComponent(LExisting) <> LOwner then
                  raise EArgumentException.CreateFmt('Der Komponentenname ist bereits vergeben: %s', [Result]);
            end;
          end;
        end;
      tkInteger, tkInt64:
        begin
          if (AValue is TJSONString) and (LValues.Items.IndexOf(AValue.Value) >= 0) then
            Exit(LValues.Items[LValues.Items.IndexOf(AValue.Value)]);
          if not JsonInteger(AValue, LInteger) then
            raise EArgumentException.CreateFmt('%s benötigt eine Ganzzahl oder einen bekannten Designerwert.', [APath]);
          if LKind = tkInt64 then
          begin
            LMinimum := LData.MinInt64Value;
            LMaximum := LData.MaxInt64Value;
          end
          else if LData.OrdType = otULong then
          begin
            LMinimum := Cardinal(LData.MinValue);
            LMaximum := Cardinal(LData.MaxValue);
          end
          else
          begin
            LMinimum := LData.MinValue;
            LMaximum := LData.MaxValue;
          end;
          if (LInteger < LMinimum) or ((LMaximum >= LMinimum) and (LInteger > LMaximum)) then
            raise EArgumentOutOfRangeException.CreateFmt('Die Ganzzahl liegt außerhalb des Bereichs von %s.', [APath]);
          Result := IntToStr(LInteger);
        end;
      tkEnumeration:
        begin
          if not (AValue is TJSONString) then
            raise EArgumentException.CreateFmt('%s benötigt einen gültigen Enum-Namen.', [APath]);
          LInteger := GetEnumValue(AProperty.GetPropType, AValue.Value);
          if (LInteger < LData.MinValue) or (LInteger > LData.MaxValue) or
            not SameText(GetEnumName(AProperty.GetPropType, Integer(LInteger)), AValue.Value) then
            raise EArgumentException.CreateFmt('%s benötigt einen gültigen Enum-Namen.', [APath]);
          Result := AValue.Value;
        end;
      tkFloat:
        begin
          if not (AValue is TJSONNumber) or not TryStrToFloat(AValue.Value, LNumber, TFormatSettings.Invariant) or
            IsNan(LNumber) or IsInfinite(LNumber) then
            raise EArgumentException.CreateFmt('%s benötigt eine endliche JSON-Zahl.', [APath]);
          if ((LData.FloatType = ftSingle) and (Abs(LNumber) > MaxSingle)) or
            ((LData.FloatType = ftDouble) and (Abs(LNumber) > MaxDouble)) or
            ((LData.FloatType = ftComp) and ((LNumber < Low(Int64)) or (LNumber > High(Int64)) or (Frac(LNumber) <> 0))) or
            ((LData.FloatType = ftCurr) and ((LNumber < -922337203685477.5808) or (LNumber > 922337203685477.5807))) then
            raise EArgumentOutOfRangeException.CreateFmt('Die Zahl liegt außerhalb des Bereichs von %s.', [APath]);
          // Registered Delphi float editors parse using the IDE's locale.
          Result := FloatToStr(LNumber);
        end;
      tkSet:
        begin
          if not (AValue is TJSONString) then
            raise EArgumentException.CreateFmt('%s benötigt eine Set-Zeichenfolge.', [APath]);
          Result := AValue.Value;
          StringToSet(AProperty.GetPropType, Result);
        end;
      tkClass:
        begin
          if not LData.ClassType.InheritsFrom(TComponent) then
            raise EArgumentException.Create('Objektproperties werden über ihre Unterproperties bearbeitet.');
          if AValue is TJSONNull then
            Exit('');
          if not (AValue is TJSONString) then
            raise EArgumentException.Create('Eine Komponentenreferenz benötigt einen Namen oder null.');
          Result := AValue.Value;
          if Result = '' then
            Exit;
          LReference := NativeComponent(RequiredComponent(AFormEditor, Result));
          if not LReference.InheritsFrom(LData.ClassType) then
            raise EArgumentException.Create('Die referenzierte Komponente hat einen inkompatiblen Typ.');
        end;
    else
      raise EArgumentException.CreateFmt('Dieser Propertytyp wird nicht als Skalar verändert: %s', [APath]);
    end;
  finally
    LValues.Free;
  end;
end;

function ValidContainer(const AContainer: TComponent; const AChildClass: TClass): Boolean;
begin
  if not Assigned(AContainer) or not Assigned(AChildClass) then
    Exit(False);
  if csInline in AContainer.ComponentState then
    Exit(False);
  if AChildClass.InheritsFrom(TControl) then
  begin
    Result := False;
    if AContainer is TWinControl then
      Result := csAcceptsControls in TControl(AContainer).ControlStyle;
  end
  else if ClassHasName(AChildClass, 'TFmxObject') then
    Result := ClassHasName(AContainer.ClassType, 'TFmxObject')
  else
    Result := False;
end;

function ParentForComponent(const AFormEditor: IOTAFormEditor; const AArguments: TJSONObject;
  const AChildClass: TClass; const ADefaultMode: string; const AExisting: IOTAComponent): IOTAComponent;
var
  LMode, LName: string;
  LRoot, LSelected: IOTAComponent;
  LSelectedNative, LRootNative, LParent: TComponent;
begin
  Result := nil;
  LMode := DesignerString(AArguments, 'parent_mode', ADefaultMode);
  LName := DesignerString(AArguments, 'parent');
  if (LMode <> 'explicit') and (LMode <> 'selected') and (LMode <> 'selected_parent') and (LMode <> 'root') then
    raise EArgumentException.Create('parent_mode muss explicit, selected, selected_parent oder root sein.');
  if (LName <> '') and (LMode <> 'explicit') and (Assigned(DesignerArgument(AArguments, 'parent_mode'))) then
    raise EArgumentException.Create('parent kann nur mit parent_mode=explicit kombiniert werden.');
  if LName <> '' then
    LMode := 'explicit';
  LRoot := AFormEditor.GetRootComponent;
  LRootNative := NativeComponent(LRoot);
  if (LMode = 'explicit') and (LName = '') then
  begin
    if Assigned(AExisting) then
      Exit;
    Result := LRoot;
  end;
  if (LMode = 'explicit') and (LName <> '') then
    Result := RequiredComponent(AFormEditor, LName)
  else if LMode = 'root' then
    Result := LRoot
  else if LMode <> 'explicit' then
  begin
    LSelected := nil;
    if AFormEditor.GetSelCount > 0 then
      LSelected := AFormEditor.GetSelComponent(0);
    if Assigned(LSelected) then
    begin
      LSelectedNative := NativeComponent(LSelected);
      if (LMode = 'selected') and ValidContainer(LSelectedNative, AChildClass) then
      begin
        if Assigned(AExisting) then
        begin
          if LSelected.GetComponentHandle <> AExisting.GetComponentHandle then
            Result := LSelected;
        end
        else
          Result := LSelected;
      end;
      if not Assigned(Result) then
      begin
        LParent := LSelectedNative.GetParentComponent;
        if Assigned(LParent) and ValidContainer(LParent, AChildClass) then
          Result := RequiredComponent(AFormEditor, LParent.Name);
      end;
    end;
    if not Assigned(Result) then
      Result := LRoot;
  end;
  if not AChildClass.InheritsFrom(TControl) and not ClassHasName(AChildClass, 'TFmxObject') then
  begin
    // Nonvisual components have an owner, not a visual parent.
    if (LMode = 'explicit') and (NativeComponent(Result) <> LRootNative) then
      raise EArgumentException.Create('Nichtvisuelle Komponenten werden dem Formular als Owner zugeordnet.');
    Exit(LRoot);
  end;
  if not ValidContainer(NativeComponent(Result), AChildClass) or
    not BelongsToRoot(NativeComponent(Result), LRootNative) then
    raise EArgumentException.Create('Der gewählte Parent ist kein kompatibler Container dieses Designers.');
end;

procedure RequireNoParentCycle(const AComponent, AParent: TComponent);
var
  LCurrent: TComponent;
  LSeen: TDictionary<TComponent, Boolean>;
begin
  LSeen := TDictionary<TComponent, Boolean>.Create;
  try
    LCurrent := AParent;
    while Assigned(LCurrent) do
    begin
      if (LCurrent = AComponent) or LSeen.ContainsKey(LCurrent) or (LSeen.Count >= CMaximumComponents) then
        raise EArgumentException.Create('Der Parentwechsel würde einen Zyklus erzeugen.');
      LSeen.Add(LCurrent, True);
      LCurrent := LCurrent.GetParentComponent;
    end;
  finally
    LSeen.Free;
  end;
end;

procedure AddMutationStatus(const AResult: TJSONObject; const AFormEditor: IOTAFormEditor);
begin
  AResult.AddPair('file', AFormEditor.FileName);
  AResult.AddPair('modified', TJSONBool.Create(AFormEditor.Modified));
  AResult.AddPair('saved', TJSONBool.Create(False));
end;

procedure AddNameSyncStatus(const AResult: TJSONObject);
begin
  AResult.AddPair('source_declaration_verified', TJSONBool.Create(False));
  AResult.AddPair('source_sync_note', 'Der tatsächliche Komponentenname wurde gelesen; die Pascal-Deklaration wurde nicht gesondert geprüft.');
end;

procedure RaiseDesignerMutationFailure(const ADesigner: IDesigner; const AError: Exception);
begin
  // A third-party setter may change state before raising. Mark the designer
  // dirty even on failure; do not try to undo arbitrary component-side effects.
  try
    ADesigner.Modified;
  except
    // Preserve the original setter/reparent error if dirty marking also fails.
  end;
  raise EInvalidOperation.CreateFmt('%s: %s. Änderungen können teilweise übernommen sein; es wurde nicht gespeichert.',
    [AError.ClassName, AError.Message]);
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

class function TDAIDesignerService.SearchComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
var
  LFileName, LQuery, LClassName, LParentName: string;
  LCaseSensitive, LUseRegex: Boolean;
  LMaximum: Integer;
  LRegex: TDAIRegex;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LQuery := DesignerString(AArguments, 'query');
  LClassName := DesignerString(AArguments, 'class_name');
  LParentName := DesignerString(AArguments, 'parent');
  LCaseSensitive := DesignerBoolean(AArguments, 'case_sensitive', False);
  LUseRegex := DesignerBoolean(AArguments, 'use_regex', False);
  LMaximum := DesignerInteger(AArguments, 'maximum_results', 100);
  if (LMaximum < 1) or (LMaximum > CMaximumComponents) then
    raise EArgumentOutOfRangeException.Create('maximum_results muss zwischen 1 und 4096 liegen.');
  LRegex := nil;
  if LUseRegex then
    LRegex := TDAIRegex.Create(LQuery, LCaseSensitive);
  try
    LResult := TJSONObject.Create;
    try
      TDAIOTA.RunOnMainThread(
        procedure
        var
          LFormEditor: IOTAFormEditor;
          LComponents: TList<IOTAComponent>;
          LSeen: TDictionary<Pointer, Boolean>;
          LComponent: IOTAComponent;
          LSummary: TJSONObject;
          LItems: TJSONArray;
          LName: string;
          LMatch, LTruncated: Boolean;
          LMatches: Integer;
        begin
          LFormEditor := LoadedDesigner(LFileName);
          LComponents := TList<IOTAComponent>.Create;
          LSeen := TDictionary<Pointer, Boolean>.Create;
          try
            LTruncated := False;
            CollectDesignerComponents(LFormEditor.GetRootComponent, LComponents, LSeen, LTruncated);
            LItems := TJSONArray.Create;
            LResult.AddPair('components', LItems);
            LMatches := 0;
            for LComponent in LComponents do
            begin
              LName := ComponentString(LComponent, 'Name');
              if LUseRegex then
                LMatch := LRegex.IsMatch(LName)
              else if LCaseSensitive then
                LMatch := (LQuery = '') or (Pos(LQuery, LName) > 0)
              else
                LMatch := (LQuery = '') or (Pos(UpperCase(LQuery), UpperCase(LName)) > 0);
              if not LMatch or ((LClassName <> '') and not SameText(LClassName, LComponent.GetComponentType)) then
                Continue;
              LSummary := ComponentSummary(LComponent);
              try
                if (LParentName <> '') and not SameText(LParentName, LSummary.GetValue('parent').Value) then
                  Continue;
                Inc(LMatches);
                if LItems.Count < LMaximum then
                begin
                  LItems.AddElement(LSummary);
                  LSummary := nil;
                end;
              finally
                LSummary.Free;
              end;
            end;
            LResult.AddPair('file', LFormEditor.FileName);
            LResult.AddPair('matched_components', TJSONNumber.Create(LMatches));
            LResult.AddPair('components_truncated', TJSONBool.Create(LTruncated or (LMatches > LMaximum)));
          finally
            LSeen.Free;
            LComponents.Free;
          end;
        end);
      Result := LResult;
    except
      LResult.Free;
      raise;
    end;
  finally
    LRegex.Free;
  end;
end;

class function TDAIDesignerService.SelectComponents(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
var
  LFileName: string;
  LNames: TJSONValue;
  LAdd, LFocus: Boolean;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LNames := DesignerArgument(AArguments, 'components');
  if not (LNames is TJSONArray) then
    raise EArgumentException.Create('components muss eine Liste mit 1 bis 4096 Komponentennamen sein.');
  if (TJSONArray(LNames).Count < 1) or (TJSONArray(LNames).Count > CMaximumComponents) then
    raise EArgumentException.Create('components muss eine Liste mit 1 bis 4096 Komponentennamen sein.');
  LAdd := DesignerBoolean(AArguments, 'add_to_selection', False);
  LFocus := DesignerBoolean(AArguments, 'focus', True);
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LFormEditor: IOTAFormEditor;
        LDesigner: IDesigner;
        LComponents: TList<IOTAComponent>;
        LValue: TJSONValue;
        LIndex: Integer;
        LSuccess: Boolean;
      begin
        LFormEditor := LoadedDesigner(LFileName);
        LDesigner := NativeDesigner(LFormEditor);
        RequireWritableDesigner(LFormEditor, LDesigner);
        LComponents := TList<IOTAComponent>.Create;
        try
          for LValue in TJSONArray(LNames) do
          begin
            if not (LValue is TJSONString) or (Trim(LValue.Value) = '') then
              raise EArgumentException.Create('components darf nur nichtleere Zeichenfolgen enthalten.');
            LComponents.Add(RequiredComponent(LFormEditor, LValue.Value));
          end;
          for LIndex := 0 to LComponents.Count - 1 do
          begin
            LSuccess := LComponents[LIndex].Select(LAdd or (LIndex > 0));
            if not LSuccess then
              raise EInvalidOperation.CreateFmt('Komponente konnte nicht ausgewählt werden: %s', [ComponentString(LComponents[LIndex], 'Name')]);
            // Focus only shows a form/data module; it does not select its root.
            if (LIndex = 0) and LFocus then
              if not LComponents[LIndex].Focus(True) then
                raise EInvalidOperation.Create('Der Designer konnte nicht in den Vordergrund gebracht werden.');
          end;
          LResult.AddPair('file', LFormEditor.FileName);
          LResult.AddPair('selection', ComponentSelection(LFormEditor));
        finally
          LComponents.Free;
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDesignerService.ReadProperties(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
var
  LFileName, LComponentName: string;
  LNames: TJSONValue;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LComponentName := DesignerRequiredString(AArguments, 'component');
  LNames := DesignerArgument(AArguments, 'properties');
  if Assigned(LNames) and not (LNames is TJSONArray) then
    raise EArgumentException.Create('properties muss eine Liste von Propertypfaden sein.');
  if Assigned(LNames) then
    if TJSONArray(LNames).Count > CMaximumComponents then
      raise EArgumentException.Create('Zu viele Propertypfade.');
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LFormEditor: IOTAFormEditor;
        LDesigner: IDesigner;
        LComponent: IOTAComponent;
        LProperties: TDesignerPropertyList;
        LItems: TJSONArray;
        LValue: TJSONValue;
        LProperty: IProperty;
        LReadAll: Boolean;
      begin
        LFormEditor := LoadedDesigner(LFileName);
        LDesigner := NativeDesigner(LFormEditor);
        LComponent := RequiredComponent(LFormEditor, LComponentName);
        LResult.AddPair('file', LFormEditor.FileName);
        LResult.AddPair('component', ComponentString(LComponent, 'Name'));
        LItems := TJSONArray.Create;
        LResult.AddPair('properties', LItems);
        LReadAll := not Assigned(LNames);
        if Assigned(LNames) then
          LReadAll := TJSONArray(LNames).Count = 0;
        if not LReadAll then
          for LValue in TJSONArray(LNames) do
          begin
            if not (LValue is TJSONString) then
              raise EArgumentException.Create('properties darf nur Zeichenfolgen enthalten.');
            LProperty := FindDesignerProperty(LComponent, LDesigner, LValue.Value);
            LItems.AddElement(DesignerPropertyJson(LComponent, LValue.Value, LProperty));
          end
        else
        begin
          LProperties := DesignerProperties(LComponent, LDesigner);
          try
            for LProperty in LProperties.Items do
              LItems.AddElement(DesignerPropertyJson(LComponent, LProperty.GetName, LProperty));
          finally
            LProperties.Free;
          end;
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDesignerService.SetProperty(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
var
  LFileName, LComponentName, LPath: string;
  LValue: TJSONValue;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LComponentName := DesignerRequiredString(AArguments, 'component');
  LPath := DesignerRequiredString(AArguments, 'property');
  LValue := DesignerArgument(AArguments, 'value');
  if not Assigned(LValue) then
    raise EArgumentException.Create('value ist erforderlich.');
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LFormEditor: IOTAFormEditor;
        LDesigner: IDesigner;
        LComponent: IOTAComponent;
        LProperty: IProperty;
        LText: string;
        LHandle: TOTAHandle;
      begin
        LFormEditor := LoadedDesigner(LFileName);
        LDesigner := NativeDesigner(LFormEditor);
        RequireWritableDesigner(LFormEditor, LDesigner);
        LComponent := RequiredComponent(LFormEditor, LComponentName);
        LProperty := FindDesignerProperty(LComponent, LDesigner, LPath);
        LText := CheckedPropertyText(LFormEditor, LComponent, LPath, LProperty, LValue);
        LHandle := LComponent.GetComponentHandle;
        try
          LProperty.SetValue(LText);
          LDesigner.Modified;
        except
          on E: Exception do
            RaiseDesignerMutationFailure(LDesigner, E);
        end;
        // Custom setters can rename components. Read the actual object back.
        LComponent := LFormEditor.GetComponentFromHandle(LHandle);
        if not Assigned(LComponent) then
          raise EInvalidOperation.Create('Die Komponente ist nach dem Propertysetter nicht mehr im Designer vorhanden.');
        LProperty := FindDesignerProperty(LComponent, LDesigner, LPath);
        LResult.AddPair('component', ComponentSummary(LComponent));
        LResult.AddPair('property', DesignerPropertyJson(LComponent, LPath, LProperty));
        AddMutationStatus(LResult, LFormEditor);
        if SameText(LPath, 'Name') or not SameText(LComponentName, ComponentString(LComponent, 'Name')) then
          AddNameSyncStatus(LResult);
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDesignerService.MoveComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
var
  LFileName, LComponentName: string;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LComponentName := DesignerRequiredString(AArguments, 'component');
  // All dimensions are validated before the designer or parent is modified.
  DesignerNumber(AArguments, 'x', 0);
  DesignerNumber(AArguments, 'y', 0);
  if DesignerNumber(AArguments, 'width', 0) < 0 then
    raise EArgumentOutOfRangeException.Create('width darf nicht negativ sein.');
  if DesignerNumber(AArguments, 'height', 0) < 0 then
    raise EArgumentOutOfRangeException.Create('height darf nicht negativ sein.');
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LFormEditor: IOTAFormEditor;
        LDesigner: IDesigner;
        LComponent, LParent: IOTAComponent;
        LNative, LNativeParent, LOwner, LRoot: TComponent;
        LChanges: TArray<TDesignerPropertyChange>;
        LArguments, LPaths: TArray<string>;
        LIndex, LCount, LX, LY: Integer;
        LIsVisual, LChangedParent, LChanged: Boolean;
        LValues: TJSONArray;
        LHandle: TOTAHandle;
      begin
        LFormEditor := LoadedDesigner(LFileName);
        LDesigner := NativeDesigner(LFormEditor);
        RequireWritableDesigner(LFormEditor, LDesigner);
        LComponent := RequiredComponent(LFormEditor, LComponentName);
        LNative := NativeComponent(LComponent);
        LRoot := NativeComponent(LFormEditor.GetRootComponent);
        if LNative = LRoot then
          raise EArgumentException.Create('Die Root-Komponente kann nicht mit designer_component_move verschoben werden.');
        if not BelongsToRoot(LNative, LRoot) then
          raise EDAIAccessDenied.Create('Die Komponente gehört nicht zu diesem Designer.');
        LOwner := LNative.Owner;
        LParent := ParentForComponent(LFormEditor, AArguments, LNative.ClassType, 'explicit', LComponent);
        LNativeParent := nil;
        LChangedParent := False;
        if Assigned(LParent) then
        begin
          LNativeParent := NativeComponent(LParent);
          LChangedParent := LNative.GetParentComponent <> LNativeParent;
          if LChangedParent then
          begin
            if not ValidContainer(LNativeParent, LNative.ClassType) then
              raise EArgumentException.Create('Diese Komponente besitzt keinen veränderbaren visuellen Parent.');
            if csAncestor in LNative.ComponentState then
              raise EArgumentException.Create('Der Parent einer geerbten Komponente kann hier nicht verändert werden.');
            RequireNoParentCycle(LNative, LNativeParent);
          end;
        end;
        LIsVisual := (LNative is TControl) or ClassHasName(LNative.ClassType, 'TFmxObject');
        LArguments := TArray<string>.Create('x', 'y', 'width', 'height');
        if LNative is TControl then
          LPaths := TArray<string>.Create('Left', 'Top', 'Width', 'Height')
        else
          LPaths := TArray<string>.Create('Position.X', 'Position.Y', 'Width', 'Height');
        SetLength(LChanges, 4);
        LCount := 0;
        LX := SmallInt(Word(Cardinal(LNative.DesignInfo) and $FFFF));
        LY := SmallInt(Word(Cardinal(LNative.DesignInfo) shr 16));
        for LIndex := 0 to High(LArguments) do
          if Assigned(DesignerArgument(AArguments, LArguments[LIndex])) then
          begin
            if not LIsVisual then
            begin
              if LIndex >= 2 then
                raise EArgumentException.Create('Nichtvisuelle Designerkomponenten haben keine Breite oder Höhe.');
              if (DesignerInteger(AArguments, LArguments[LIndex], 0) < Low(SmallInt)) or
                (DesignerInteger(AArguments, LArguments[LIndex], 0) > High(SmallInt)) then
                raise EArgumentOutOfRangeException.Create('Die Position einer nichtvisuellen Komponente muss in einen SmallInt passen.');
              if LIndex = 0 then
                LX := DesignerInteger(AArguments, 'x', 0)
              else
                LY := DesignerInteger(AArguments, 'y', 0);
            end
            else
            begin
              LChanges[LCount].PropertyName := LPaths[LIndex];
              LChanges[LCount].Editor := FindDesignerProperty(LComponent, LDesigner, LPaths[LIndex]);
              LChanges[LCount].Text := CheckedPropertyText(LFormEditor, LComponent, LPaths[LIndex],
                LChanges[LCount].Editor, DesignerArgument(AArguments, LArguments[LIndex]));
              Inc(LCount);
            end;
          end;
        LChanged := LChangedParent or (LCount > 0) or (not LIsVisual and
          (Assigned(DesignerArgument(AArguments, 'x')) or Assigned(DesignerArgument(AArguments, 'y'))));
        LHandle := LComponent.GetComponentHandle;
        if LChanged then
        begin
          try
            if LChangedParent then
            begin
              // No public OTA reparent operation exists. This is the same
              // virtual operation used by streaming; Owner is kept unchanged.
              TDesignerComponentAccess(LNative).SetParentComponent(LNativeParent);
              if (LNative.Owner <> LOwner) or (LNative.GetParentComponent <> LNativeParent) then
                raise EInvalidOperation.Create('Der Parentwechsel wurde vom nativen Designerobjekt nicht wie angefordert übernommen.');
            end;
            if not LIsVisual then
              LNative.DesignInfo := Integer(Cardinal(Word(LX)) or (Cardinal(Word(LY)) shl 16));
            for LIndex := 0 to LCount - 1 do
              LChanges[LIndex].Editor.SetValue(LChanges[LIndex].Text);
            LDesigner.Modified;
          except
            on E: Exception do
              RaiseDesignerMutationFailure(LDesigner, E);
          end;
        end;
        LComponent := LFormEditor.GetComponentFromHandle(LHandle);
        if not Assigned(LComponent) then
          raise EInvalidOperation.Create('Die verschobene Komponente ist nicht mehr im Designer vorhanden.');
        LResult.AddPair('component', ComponentSummary(LComponent));
        LResult.AddPair('parent_changed', TJSONBool.Create(LChangedParent));
        LResult.AddPair('changed', TJSONBool.Create(LChanged));
        LValues := TJSONArray.Create;
        LResult.AddPair('properties', LValues);
        for LIndex := 0 to LCount - 1 do
          LValues.AddElement(DesignerPropertyJson(LComponent, LChanges[LIndex].PropertyName,
            FindDesignerProperty(LComponent, LDesigner, LChanges[LIndex].PropertyName)));
        if not LIsVisual then
        begin
          LResult.AddPair('x', TJSONNumber.Create(SmallInt(Word(Cardinal(NativeComponent(LComponent).DesignInfo) and $FFFF))));
          LResult.AddPair('y', TJSONNumber.Create(SmallInt(Word(Cardinal(NativeComponent(LComponent).DesignInfo) shr 16))));
        end;
        AddMutationStatus(LResult, LFormEditor);
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIDesignerService.CreateComponent(const AFileName: string; const AArguments: TJSONObject): TJSONObject;
var
  LFileName, LClassName, LName: string;
  LX, LY, LWidth, LHeight: Integer;
  LSelect: Boolean;
  LResult: TJSONObject;
begin
  LFileName := DesignerFileName(AFileName);
  LClassName := DesignerRequiredString(AArguments, 'class_name');
  LName := DesignerString(AArguments, 'name');
  if not IsValidIdent(LClassName, True) then
    raise EArgumentException.Create('class_name muss ein gültiger Klassenname sein.');
  if (LName <> '') and not IsValidIdent(LName) then
    raise EArgumentException.Create('name muss ein gültiger Delphi-Bezeichner sein.');
  LX := DesignerInteger(AArguments, 'x', -1);
  LY := DesignerInteger(AArguments, 'y', -1);
  LWidth := DesignerInteger(AArguments, 'width', -1);
  LHeight := DesignerInteger(AArguments, 'height', -1);
  if (LWidth < -1) or (LHeight < -1) then
    raise EArgumentOutOfRangeException.Create('width und height müssen -1 oder nichtnegativ sein.');
  LSelect := DesignerBoolean(AArguments, 'select', True);
  LResult := TJSONObject.Create;
  try
    TDAIOTA.RunOnMainThread(
      procedure
      var
        LFormEditor: IOTAFormEditor;
        LDesigner: IDesigner;
        LComponent, LParent: IOTAComponent;
        LClass, LParentClass, LGroupClass: TPersistentClass;
        LFinder: TClassFinder;
        LRoot: TComponent;
        LProperty: IProperty;
        LNameValue: TJSONString;
        LText: string;
        LOriginalError: string;
        LHandle: TOTAHandle;
      begin
        LFormEditor := LoadedDesigner(LFileName);
        LDesigner := NativeDesigner(LFormEditor);
        RequireWritableDesigner(LFormEditor, LDesigner);
        if (LName <> '') and Assigned(LFormEditor.FindComponent(LName)) then
          raise EArgumentException.CreateFmt('Der Komponentenname ist bereits vergeben: %s', [LName]);
        LRoot := NativeComponent(LFormEditor.GetRootComponent);
        LGroupClass := LDesigner.ActiveClassGroup;
        if not Assigned(LGroupClass) then
          LGroupClass := TPersistentClass(LRoot.ClassType);
        LFinder := TClassFinder.Create(LGroupClass, False);
        try
          LClass := LFinder.GetClass(LClassName);
        finally
          LFinder.Free;
        end;
        if Assigned(LClass) then
          if not LClass.InheritsFrom(TComponent) then
            raise EArgumentException.Create('class_name bezeichnet keine Komponentenklasse.');
        // Palette registration need not register the class with RTL GetClass.
        // Unknown classes are resolved by OTA CreateComponent, never by native
        // construction. Use the form's framework to validate its target first.
        if Assigned(LClass) then
          LParentClass := LClass
        else
          LParentClass := TPersistentClass(LRoot.ClassType);
        LParent := ParentForComponent(LFormEditor, AArguments, LParentClass, 'selected', nil);
        LComponent := LFormEditor.CreateComponent(LParent, LClassName, LX, LY, LWidth, LHeight);
        if not Assigned(LComponent) then
          raise EInvalidOperation.CreateFmt('Die IDE konnte die Komponentenklasse nicht erzeugen: %s', [LClassName]);
        try
          LHandle := LComponent.GetComponentHandle;
          if not BelongsToRoot(NativeComponent(LComponent), LRoot) then
            raise EInvalidOperation.Create('Die neue Komponente wurde keinem gültigen Owner dieses Designers zugeordnet.');
          if (NativeComponent(LComponent) is TControl) or ClassHasName(NativeComponent(LComponent).ClassType, 'TFmxObject') then
          begin
            if not ValidContainer(NativeComponent(LParent), NativeComponent(LComponent).ClassType) or
              (NativeComponent(LComponent).GetParentComponent <> NativeComponent(LParent)) then
              raise EInvalidOperation.Create('Die neue Komponente wurde keinem kompatiblen angeforderten Parent zugeordnet.');
          end;
          if LName <> '' then
          begin
            LProperty := FindDesignerProperty(LComponent, LDesigner, 'Name');
            LNameValue := TJSONString.Create(LName);
            try
              LText := CheckedPropertyText(LFormEditor, LComponent, 'Name', LProperty, LNameValue);
            finally
              LNameValue.Free;
            end;
            LProperty.SetValue(LText);
          end;
          LDesigner.Modified;
          LComponent := LFormEditor.GetComponentFromHandle(LHandle);
          if not Assigned(LComponent) then
            raise EInvalidOperation.Create('Die neue Komponente ist nach ihrem Propertysetter nicht mehr im Designer vorhanden.');
          if LSelect then
            if not LComponent.Select(False) then
              raise EInvalidOperation.Create('Die neue Komponente konnte nicht ausgewählt werden.');
          LResult.AddPair('component', ComponentSummary(LComponent));
          LResult.AddPair('selection', ComponentSelection(LFormEditor));
          AddMutationStatus(LResult, LFormEditor);
          AddNameSyncStatus(LResult);
        except
          on E: Exception do
          begin
            // Roll back through OTA so the IDE owns resource/declaration
            // removal. A failed rollback must disclose the remaining object.
            LOriginalError := E.ClassName + ': ' + E.Message;
            if Assigned(LComponent) then
              try
                if not LComponent.Delete then
                  raise EInvalidOperation.Create('Die IDE hat das Löschen der neuen Komponente abgelehnt.');
              except
                on ECleanup: Exception do
                  raise EInvalidOperation.CreateFmt('Erzeugen fehlgeschlagen (%s); Rücknahme fehlgeschlagen (%s). Die neue Komponente kann im Designer verbleiben.',
                    [LOriginalError, ECleanup.Message]);
              end;
            raise;
          end;
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

end.
