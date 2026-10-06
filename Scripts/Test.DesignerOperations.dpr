program TestDesignerOperations;
{$APPTYPE CONSOLE}

// Real VCL components and the original SDK property editors are operated through SDK doubles.
// This checks the requested OTA call paths, validation and state; it does not claim to reproduce
// the IDE's Pascal field synchronization or undo stack. No running IDE or source files are used.
uses
  System.Classes, System.JSON, System.SysUtils, System.Types,
  ToolsAPI, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.StdCtrls,
  DAI.Designer.Fixture, h5u.DAI.OTA.Helpers, h5u.DAI.OTA.Designer;

const
  CFormFile = 'C:\Workspace\FormUnit.dfm';
type
  TOperation = (opSearch, opSelect, opRead, opSet, opMove, opCreate);
var
  GChecks: Integer;
  GEditor: TTestFormEditor;
  GEditorInterface: IOTAFormEditor;

procedure Check(const ACondition: Boolean; const AName: string);
begin
  if not ACondition then raise Exception.Create('FAIL: ' + AName);
  Inc(GChecks);
end;

procedure NewFixture;
begin
  TDAIOTA.TestEditor := nil;
  GEditorInterface := nil;
  GEditor := TTestFormEditor.Create;
  GEditorInterface := GEditor;
  TDAIOTA.TestEditor := GEditorInterface;
  TDAIOTA.WorkspaceAllowed := True;
  TDAIOTA.ReferenceFile := False;
  TDAIOTA.DeniedPath := '';
  TDAIOTA.ReferencePath := '';
  TDAIOTA.RejectReparsePath := False;
  TDAIOTA.ReparseChecks := 0;
  NamePropertyCalls := 0;
  WidthPropertyCalls := 0;
  WidthPropertyRaises := False;
end;

function Invoke(const AOperation: TOperation; const AJson: string): TJSONObject;
var
  LArguments: TJSONObject;
begin
  LArguments := TJSONObject(TJSONObject.ParseJSONValue(AJson));
  try
    case AOperation of
      opSearch: Result := TDAIDesignerService.SearchComponents(CFormFile, LArguments);
      opSelect: Result := TDAIDesignerService.SelectComponents(CFormFile, LArguments);
      opRead: Result := TDAIDesignerService.ReadProperties(CFormFile, LArguments);
      opSet: Result := TDAIDesignerService.SetProperty(CFormFile, LArguments);
      opMove: Result := TDAIDesignerService.MoveComponent(CFormFile, LArguments);
      opCreate: Result := TDAIDesignerService.CreateComponent(CFormFile, LArguments);
    else raise Exception.Create('Unknown test operation');
    end;
  finally
    LArguments.Free;
  end;
end;

procedure Reject(const AOperation: TOperation; const AJson, AName: string);
var
  LBeforeCreate, LBeforeSelect, LBeforeModified: Integer;
  LBeforeParent: TWinControl;
  LBeforeBounds: TRect;
  LBeforeName, LBeforeCaption: string;
  LLabel: TLabel;
  LResult: TJSONObject;
  LRejected: Boolean;
begin
  LBeforeCreate := GEditor.CreateCount;
  LBeforeSelect := GEditor.SelectCount;
  LBeforeModified := GEditor.DesignerObject.ModifiedCount;
  LLabel := TLabel(GEditor.Root.FindComponent('Label1'));
  LBeforeParent := LLabel.Parent;
  LBeforeBounds := LLabel.BoundsRect;
  LBeforeName := LLabel.Name;
  LBeforeCaption := LLabel.Caption;
  LRejected := False;
  try
    LResult := Invoke(AOperation, AJson);
    LResult.Free;
  except
    on E: EArgumentException do LRejected := True;
    on E: EInvalidOperation do LRejected := True;
    on E: Exception do
      if E.ClassName = 'EDAIAccessDenied' then LRejected := True else raise;
  end;
  Check(LRejected, AName + ' rejected');
  Check((GEditor.CreateCount = LBeforeCreate) and (GEditor.SelectCount = LBeforeSelect) and
    (GEditor.DesignerObject.ModifiedCount = LBeforeModified) and (LLabel.Name = LBeforeName) and
    (LLabel.Caption = LBeforeCaption) and (LLabel.Parent = LBeforeParent) and
    EqualRect(LLabel.BoundsRect, LBeforeBounds), AName + ' leaves state untouched');
end;

procedure TestSearch;
var
  LResult: TJSONObject;
  LItems: TJSONArray;
begin
  NewFixture;
  LResult := Invoke(opSearch, '{"query":"label"}');
  try
    LItems := LResult.GetValue<TJSONArray>('components');
    Check(LItems.Count = 1, 'literal component name search');
    Check(TJSONObject(LItems.Items[0]).GetValue<string>('name') = 'Label1', 'search returns component metadata');
  finally LResult.Free; end;
  LResult := Invoke(opSearch, '{"query":"LABEL","case_sensitive":true}');
  try Check(LResult.GetValue<TJSONArray>('components').Count = 0, 'case-sensitive name search'); finally LResult.Free; end;
  LResult := Invoke(opSearch, '{"query":"^(Label|Button)1$","use_regex":true,"parent":"Panel1"}');
  try Check(LResult.GetValue<TJSONArray>('components').Count = 2, 'regex and parent filter'); finally LResult.Free; end;
  LResult := Invoke(opSearch, '{"class_name":"TPanel"}');
  try Check(LResult.GetValue<TJSONArray>('components').Count = 2, 'exact class filter'); finally LResult.Free; end;
  LResult := Invoke(opSearch, '{"maximum_results":1}');
  try
    Check(LResult.GetValue<TJSONArray>('components').Count = 1, 'search result limit');
    Check(LResult.GetValue<Boolean>('components_truncated'), 'search truncation reported');
  finally LResult.Free; end;
  Reject(opSearch, '{"use_regex":true,"query":"["}', 'invalid regex');
  Reject(opSearch, '{"maximum_results":0}', 'invalid result count');
  Reject(opSearch, '{"case_sensitive":"false"}', 'invalid search boolean');
  Check(not GEditor.ModifiedFlag, 'search never modifies designer');
end;

procedure TestSelection;
var LResult: TJSONObject;
begin
  NewFixture;
  LResult := Invoke(opSelect, '{"components":["Label1","Button1"]}');
  try
    Check(GEditor.Selection.Count = 2, 'select multiple components');
    Check(GEditor.FocusCount = 1, 'focus defaults to first requested component');
    Check(LResult.GetValue<TJSONArray>('selection').Count = 2, 'selection result from OTA');
  finally LResult.Free; end;
  LResult := Invoke(opSelect, '{"components":["Panel2"],"add_to_selection":true,"focus":false}');
  try
    Check(GEditor.Selection.Count = 3, 'append selection');
    Check(GEditor.FocusCount = 1, 'focus false uses Select');
  finally LResult.Free; end;
  Reject(opSelect, '{"components":["Panel1","Missing"]}', 'validate all selections before changing selection');
  Reject(opSelect, '{"components":["Panel1",true]}', 'mixed selection array');
  Reject(opSelect, '{"components":[]}', 'empty selection array');
  Reject(opSelect, '{"components":["Panel1"],"focus":0}', 'invalid focus');
  LResult := Invoke(opSelect, '{"components":["Form1"]}');
  try
    Check((GEditor.Selection.Count = 1) and (GEditor.Native(GEditor.Selection[0]) = GEditor.Root),
      'root selection selected explicitly even when root Focus only brings designer forward');
  finally LResult.Free; end;
  LResult := Invoke(opSelect, '{"components":["Form1","Button1"]}');
  try Check(GEditor.Selection.Count = 2, 'root and ordinary component multi-selection'); finally LResult.Free; end;
  Check(not GEditor.ModifiedFlag, 'selection never changes form contents');
end;

procedure TestProperties;
var
  LResult: TJSONObject;
  LProperty: TJSONObject;
  LLabel: TLabel;
begin
  NewFixture;
  LLabel := TLabel(GEditor.Root.FindComponent('Label1'));
  LResult := Invoke(opRead, '{"component":"Label1","properties":["Name","Caption","Font.Size"]}');
  try
    Check(LResult.GetValue<TJSONArray>('properties').Count = 3, 'property names and nested path read');
    LProperty := TJSONObject(LResult.GetValue<TJSONArray>('properties').Items[1]);
    Check(LProperty.GetValue<string>('value') = 'Original caption', 'property editor displays real caption');
  finally LResult.Free; end;
  LResult := Invoke(opSet, '{"component":"Label1","property":"Caption","value":"Grüße aus DAI"}');
  try
    Check(LLabel.Caption = 'Grüße aus DAI', 'Unicode caption through registered property editor');
    Check(GEditor.NativeSetCount = 0, 'no raw OTA/native property setters used');
    Check(GEditor.ModifiedFlag, 'property change marks designer modified');
  finally LResult.Free; end;
  LResult := Invoke(opSet, '{"component":"Label1","property":"Font.Size","value":18}');
  try Check(LLabel.Font.Size = 18, 'nested integer property via editor'); finally LResult.Free; end;
  LResult := Invoke(opSet, '{"component":"Label1","property":"Visible","value":false}');
  try Check(not LLabel.Visible, 'Boolean property via editor'); finally LResult.Free; end;
  LResult := Invoke(opSet, '{"component":"Label1","property":"Flags.flFirst","value":true}');
  try Check(flFirst in TTestLabel(LLabel).Flags, 'synthetic set element retains parent editor during setter'); finally LResult.Free; end;
  LResult := Invoke(opSet, '{"component":"Label1","property":"Flags.flFirst","value":false}');
  try Check(not (flFirst in TTestLabel(LLabel).Flags), 'synthetic set element Boolean false'); finally LResult.Free; end;
  LResult := Invoke(opSet, '{"component":"Label1","property":"BigInteger","value":9007199254740993}');
  try Check(TTestLabel(LLabel).BigInteger = 9007199254740993, 'exact Int64 above Double integer precision'); finally LResult.Free; end;
  Reject(opSet, '{"component":"Label1","property":"Left","value":2147483648}', 'integer overflow');
  Reject(opSet, '{"component":"Label1","property":"Left","value":1.5}', 'fractional integer');
  Reject(opSet, '{"component":"Label1","property":"Visible","value":"notabool"}', 'invalid Boolean value');
  Reject(opSet, '{"component":"Label1","property":"Caption","value":{}}', 'object not scalar');
  Reject(opSet, '{"component":"Label1","property":"Name","value":"Panel1"}', 'duplicate component name');
  Reject(opSet, '{"component":"Label1","property":"Name","value":"bad name"}', 'invalid component identifier');
  Reject(opRead, '{"component":"Label1","properties":["Missing"]}', 'unknown property');
  LResult := Invoke(opSet, '{"component":"Label1","property":"Name","value":"CaptionLabel"}');
  try
    Check(LLabel.Name = 'CaptionLabel', 'Name changed');
    Check(NamePropertyCalls = 1, 'Name change invokes registered Name property editor');
    Check(GEditor.NativeSetCount = 0, 'Name change bypasses raw setters');
    Check(GEditor.Root.FindComponent('CaptionLabel') = LLabel, 'updated component remains accessible by actual name');
  finally LResult.Free; end;
  Check(GEditor.ModuleObject.SaveCount = 0, 'property operations never save');
end;

procedure TestMovement;
var LResult: TJSONObject; LLabel: TLabel; LPanel1, LPanel2: TPanel; LTimer: TTimer;
begin
  NewFixture;
  LLabel := TLabel(GEditor.Root.FindComponent('Label1'));
  LPanel1 := TPanel(GEditor.Root.FindComponent('Panel1'));
  LPanel2 := TPanel(GEditor.Root.FindComponent('Panel2'));
  LResult := Invoke(opMove, '{"component":"Label1","x":-5,"y":35,"width":120,"height":40,"parent":"Panel2"}');
  try
    Check((LLabel.Left = -5) and (LLabel.Top = 35) and (LLabel.Width = 120) and (LLabel.Height = 40), 'position and dimensions changed');
    Check(LLabel.Parent = LPanel2, 'native fallback reparent');
    Check(LLabel.Owner = GEditor.Root, 'reparent preserves Owner');
    Check(LResult.GetValue<Boolean>('parent_changed'), 'parent change reported');
    Check(GEditor.NativeSetCount = 0, 'position through registered editors');
  finally LResult.Free; end;
  Reject(opMove, '{"component":"Label1","parent":"Panel1","height":-1}', 'dimensions checked before reparent');
  Reject(opMove, '{"component":"Label1","parent":"Button1"}', 'noncontainer parent');
  Reject(opMove, '{"component":"Label1","width":1.25}', 'fractional dimension');
  Reject(opMove, '{"component":"Form1","x":1}', 'root movement');
  Reject(opMove, '{"component":"Panel1","parent":"Panel1"}', 'self parent cycle');
  LPanel2.Parent := LPanel1;
  Reject(opMove, '{"component":"Panel1","parent":"Panel2"}', 'descendant parent cycle');
  LPanel2.Parent := GEditor.Root;
  LResult := Invoke(opMove, '{"component":"Label1"}');
  try Check(not LResult.GetValue<Boolean>('changed'), 'empty move is no-op'); finally LResult.Free; end;
  LTimer := TTimer(GEditor.Root.FindComponent('Timer1'));
  LResult := Invoke(opMove, '{"component":"Timer1","x":-12,"y":123}');
  try
    Check(SmallInt(Word(Cardinal(LTimer.DesignInfo) and $FFFF)) = -12, 'nonvisual design icon X');
    Check(SmallInt(Word(Cardinal(LTimer.DesignInfo) shr 16)) = 123, 'nonvisual design icon Y');
  finally LResult.Free; end;
  Reject(opMove, '{"component":"Timer1","width":1}', 'nonvisual width unsupported');
  Reject(opMove, '{"component":"Timer1","x":32768}', 'nonvisual icon range');
  Check(GEditor.ModuleObject.SaveCount = 0, 'movement never saves');
end;

procedure TestCreation;
var LResult: TJSONObject; LNew: TComponent; LBeforeSelect: Integer;
begin
  NewFixture;
  LResult := Invoke(opCreate, '{"class_name":"TButton","name":"NewButton","parent":"Panel2","x":30,"y":40,"width":110,"height":32}');
  try
    Check(GEditor.CreateCount = 1, 'creation calls OTA CreateComponent');
    Check(GEditor.LastContainer = 'Panel2', 'explicit parent passed to OTA');
    Check((GEditor.LastX = 30) and (GEditor.LastY = 40) and (GEditor.LastW = 110) and (GEditor.LastH = 32), 'geometry passed to OTA');
    LNew := GEditor.Root.FindComponent('NewButton');
    Check(Assigned(LNew) and (LNew.Owner = GEditor.Root), 'OTA-created component owner and name');
    Check(GEditor.Selection.Count = 1, 'new component selected by default');
    Check(GEditor.NativeSetCount = 0, 'create-name does not use raw setters');
  finally LResult.Free; end;
  LResult := Invoke(opSelect, '{"components":["Panel1"],"focus":false}'); LResult.Free;
  LBeforeSelect := GEditor.SelectCount;
  LResult := Invoke(opCreate, '{"class_name":"TButton","select":false}');
  try
    Check(GEditor.LastContainer = 'Panel1', 'selected container is default creation parent');
    Check((GEditor.LastX = -1) and (GEditor.LastY = -1) and (GEditor.LastW = -1) and (GEditor.LastH = -1), 'default bounds delegated to OTA');
    Check(GEditor.Native(GEditor.Selection[0]).Name = 'Panel1', 'select false preserves selection');
    Check(GEditor.SelectCount = LBeforeSelect, 'select false never calls OTA Select, even with complete Boolean evaluation');
  finally LResult.Free; end;
  LResult := Invoke(opSelect, '{"components":["Label1"],"focus":false}'); LResult.Free;
  LResult := Invoke(opCreate, '{"class_name":"TButton","select":false}');
  try Check(GEditor.LastContainer = 'Panel1', 'selected noncontainer falls back to its parent'); finally LResult.Free; end;
  LResult := Invoke(opSelect, '{"components":["Panel2"],"focus":false}'); LResult.Free;
  LResult := Invoke(opCreate, '{"class_name":"TButton","parent_mode":"selected_parent","select":false}');
  try Check(GEditor.LastContainer = 'Form1', 'selected_parent uses surrounding parent'); finally LResult.Free; end;
  LResult := Invoke(opCreate, '{"class_name":"TTimer","select":false}');
  try Check(GEditor.LastContainer = 'Form1', 'nonvisual creation uses root Owner'); finally LResult.Free; end;
  Check(GetClass('TUnregisteredPaletteButton') = nil, 'custom palette class is not in RTL class registry');
  LResult := Invoke(opCreate, '{"class_name":"TUnregisteredPaletteButton","name":"PaletteButton","parent":"Panel1","select":false}');
  try
    Check(GEditor.Root.FindComponent('PaletteButton') is TUnregisteredPaletteButton,
      'class absent from RTL registry resolved through OTA creation');
  finally LResult.Free; end;
  Reject(opCreate, '{"class_name":"TButton","name":"Panel1"}', 'duplicate requested new name');
  Reject(opCreate, '{"class_name":"TButton","parent":"Button1"}', 'invalid creation container');
  Reject(opCreate, '{"class_name":"TButton","width":-2}', 'invalid creation size');
  Reject(opCreate, '{"class_name":"TButton","select":"yes"}', 'invalid create Boolean');
  Reject(opCreate, '{"class_name":"TButton","name":"bad name"}', 'invalid requested new identifier');
  Reject(opCreate, '{"class_name":"TButton","parent":"Panel1","parent_mode":"root"}', 'ambiguous creation parent');
  Check(GEditor.ModuleObject.SaveCount = 0, 'creation never saves');
end;

procedure TestProtection;
var LResult: TJSONObject;
begin
  NewFixture;
  GEditor.DesignerObject.ReadOnly := True;
  Reject(opSet, '{"component":"Label1","property":"Caption","value":"blocked"}', 'read-only designer');
  Reject(opMove, '{"component":"Label1","x":20}', 'read-only movement');
  Reject(opCreate, '{"class_name":"TButton"}', 'read-only creation');
  LResult := Invoke(opRead, '{"component":"Label1","properties":["Caption"]}');
  try Check(LResult.GetValue<TJSONArray>('properties').Count = 1, 'read-only property reads remain available'); finally LResult.Free; end;
  GEditor.DesignerObject.ReadOnly := False;
  TDAIOTA.ReferenceFile := True;
  Reject(opSet, '{"component":"Label1","property":"Caption","value":"blocked"}', 'reference-file mutation');
  Reject(opCreate, '{"class_name":"TButton"}', 'reference-file creation');
  TDAIOTA.ReferenceFile := False;
  TDAIOTA.WorkspaceAllowed := False;
  Reject(opSet, '{"component":"Label1","property":"Caption","value":"blocked"}', 'outside-workspace mutation');
  TDAIOTA.WorkspaceAllowed := True;
  TDAIOTA.DeniedPath := GEditor.ModuleObject.GetFileName;
  Reject(opSet, '{"component":"Label1","property":"Caption","value":"blocked"}',
    'actual Pascal module outside workspace despite allowed form path');
  TDAIOTA.DeniedPath := '';
  TDAIOTA.ReferencePath := GEditor.ModuleObject.GetFileName;
  Reject(opMove, '{"component":"Label1","x":20}', 'actual Pascal module is read-only reference');
  TDAIOTA.ReferencePath := '';
  TDAIOTA.RejectReparsePath := True;
  Reject(opCreate, '{"class_name":"TButton"}', 'reparse write-path protection');
  TDAIOTA.RejectReparsePath := False;
  Check(TDAIOTA.ReparseChecks > 0, 'writes pass through reparse path guard');
  Check(GEditor.ModuleObject.SaveCount = 0, 'protection failures never save');
end;

function MutationFailure(const AOperation: TOperation; const AJson: string): string;
var
  LResult: TJSONObject;
begin
  Result := '';
  try
    LResult := Invoke(AOperation, AJson);
    LResult.Free;
  except
    on E: EInvalidOperation do Result := E.Message;
  end;
  Check(Pos('fixture', Result) > 0, 'custom setter failure preserves original error');
  Check(Pos('teilweise', Result) > 0, 'custom setter failure reports possibly partial changes');
  Check(Pos('nicht gespeichert', Result) > 0, 'custom setter failure reports no saving');
end;

procedure TestPartialSetterFailures;
var
  LLabel: TTestLabel;
  LMessage: string;
begin
  NewFixture;
  LLabel := TTestLabel(GEditor.Root.FindComponent('Label1'));
  LMessage := MutationFailure(opSet, '{"component":"Label1","property":"FailingText","value":"applied before exception"}');
  Check(LLabel.FailingText = 'applied before exception', 'failing registered setter really changed state');
  Check(GEditor.ModifiedFlag and (GEditor.DesignerObject.ModifiedCount > 0),
    'setter which raises before its own dirty notification still marks designer modified');
  Check(GEditor.ModuleObject.SaveCount = 0, 'failing property setter never saves');

  NewFixture;
  LLabel := TTestLabel(GEditor.Root.FindComponent('Label1'));
  WidthPropertyRaises := True;
  Reject(opMove, '{"component":"Label1","parent":"Panel2","x":44,"width":101,"height":-1}',
    'invalid later dimension prevents all parent and setter changes');
  Check(WidthPropertyCalls = 0, 'failed prevalidation does not call custom width editor');
  LMessage := MutationFailure(opMove, '{"component":"Label1","parent":"Panel2","x":44,"width":101}');
  Check((LLabel.Parent = GEditor.Root.FindComponent('Panel2')) and (LLabel.Owner = GEditor.Root),
    'move parent changed before a later editor failure while preserving Owner');
  Check(LLabel.Left = 44, 'earlier movement property applied before later failure');
  Check((LLabel.Width = 101) and (WidthPropertyCalls = 1), 'failing width editor applied value before raising');
  Check(GEditor.ModifiedFlag and (GEditor.DesignerObject.ModifiedCount > 0), 'partial move remains marked modified');
  Check(GEditor.ModuleObject.SaveCount = 0, 'partial move never saves');
  WidthPropertyRaises := False;
end;

procedure TestFloatLocale;
var
  LSavedFormat: TFormatSettings;
  LResult: TJSONObject;
  LLabel: TTestLabel;
begin
  NewFixture;
  LLabel := TTestLabel(GEditor.Root.FindComponent('Label1'));
  LSavedFormat := FormatSettings;
  try
    FormatSettings.DecimalSeparator := ',';
    FormatSettings.ThousandSeparator := '.';
    LResult := Invoke(opSet, '{"component":"Label1","property":"FloatValue","value":1.25}');
    try
      Check(LLabel.FloatValue = 1.25, 'invariant JSON decimal converted for comma-locale registered float editor');
      Check(GEditor.NativeSetCount = 0, 'float property uses registered editor');
      Check(GEditor.ModuleObject.SaveCount = 0, 'float property does not save');
    finally
      LResult.Free;
    end;
  finally
    FormatSettings := LSavedFormat;
  end;
  Check(FormatSettings.DecimalSeparator = LSavedFormat.DecimalSeparator, 'test restores locale settings');
end;

begin
  try
    RegisterTestPropertyEditors;
    TestSearch;
    TestSelection;
    TestProperties;
    TestMovement;
    TestCreation;
    TestProtection;
    TestPartialSetterFailures;
    TestFloatLocale;
    TDAIOTA.TestEditor := nil;
    GEditorInterface := nil;
    Writeln('PASS: ', GChecks, ' designer operation SDK checks');
  except
    on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
