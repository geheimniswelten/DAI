unit DAI.Designer.Fixture;

interface

uses
  System.Classes, System.Generics.Collections, System.IniFiles,
  System.SysUtils, System.Types, System.TypInfo,
  Winapi.ActiveX, ToolsAPI, DesignIntf, DesignEditors,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TTestFormEditor = class;

  TTestFlag = (flFirst, flSecond);
  TTestFlags = set of TTestFlag;
  TTestLabel = class(TLabel)
  private
    FFlags: TTestFlags;
    FBigInteger: Int64;
    FFloatValue: Double;
    FFailingText: string;
    procedure SetFailingText(const Value: string);
  published
    property Flags: TTestFlags read FFlags write FFlags;
    property BigInteger: Int64 read FBigInteger write FBigInteger;
    property FloatValue: Double read FFloatValue write FFloatValue;
    property FailingText: string read FFailingText write SetFailingText;
  end;

  TUnregisteredPaletteButton = class(TButton);

  TTestNameProperty = class(TStringProperty)
  public
    procedure SetValue(const Value: string); override;
  end;

  TTestWidthProperty = class(TIntegerProperty)
  public
    procedure SetValue(const Value: string); override;
  end;

  TTestComponent = class(TInterfacedObject, IOTAComponent, INTAComponent)
  public
    Instance: TComponent;
    Editor: TTestFormEditor;
    constructor Create(AInstance: TComponent; AEditor: TTestFormEditor);
    function GetComponentType: string;
    function GetComponentHandle: TOTAHandle;
    function GetParent: IOTAComponent;
    function IsTControl: Boolean;
    function GetPropCount: Integer;
    function GetPropName(Index: Integer): string;
    function GetPropType(Index: Integer): System.TypInfo.TTypeKind;
    function GetPropTypeByName(const Name: string): System.TypInfo.TTypeKind;
    function GetPropValue(Index: Integer; var Value): Boolean;
    function GetPropValueByName(const Name: string; var Value): Boolean;
    function SetProp(Index: Integer; const Value): Boolean;
    function SetPropByName(const Name: string; const Value): Boolean;
    function GetChildren(Param: Pointer; Proc: TOTAGetChildCallback): Boolean;
    function GetControlCount: Integer;
    function GetControl(Index: Integer): IOTAComponent;
    function GetComponentCount: Integer;
    function GetComponent(Index: Integer): IOTAComponent; overload;
    function Select(AddToSelection: Boolean): Boolean;
    function Focus(AddToSelection: Boolean): Boolean;
    function Delete: Boolean;
    function GetPersistent: TPersistent;
    function GetComponent: TComponent; overload;
  end;

  TTestDesigner = class(TInterfacedObject, IDesigner)
  public
    Editor: TTestFormEditor;
    ReadOnly: Boolean;
    ModifiedCount: Integer;
    procedure Activate;
    procedure Modified;
    function CreateMethod(const Name: string; TypeData: PTypeData): TMethod; overload;
    function GetMethodName(const Method: TMethod): string;
    procedure GetMethods(TypeData: PTypeData; Proc: TGetStrProc); overload;
    function GetPathAndBaseExeName: string;
    function GetPrivateDirectory: string;
    function GetBaseRegKey: string;
    function GetIDEOptions: TCustomIniFile;
    procedure GetSelections(const List: IDesignerSelections);
    function MethodExists(const Name: string): Boolean;
    procedure RenameMethod(const CurName, NewName: string);
    procedure SelectComponent(Instance: TPersistent); overload;
    procedure SetSelections(const List: IDesignerSelections);
    procedure ShowMethod(const Name: string);
    procedure GetComponentNames(TypeData: PTypeData; Proc: TGetStrProc);
    function GetComponent(const Name: string): TComponent;
    function GetComponentName(Component: TComponent): string;
    function GetObject(const Name: string): TPersistent;
    function GetObjectName(Instance: TPersistent): string;
    procedure GetObjectNames(TypeData: PTypeData; Proc: TGetStrProc);
    function MethodFromAncestor(const Method: TMethod): Boolean;
    function CreateComponent(ComponentClass: TComponentClass; Parent: TComponent; Left, Top, Width, Height: Integer): TComponent;
    function CreateCurrentComponent(Parent: TComponent; const Rect: TRect): TComponent;
    function IsComponentLinkable(Component: TComponent): Boolean;
    function IsComponentHidden(Component: TComponent): Boolean;
    procedure MakeComponentLinkable(Component: TComponent);
    procedure Revert(Instance: TPersistent; PropInfo: PPropInfo);
    function GetIsDormant: Boolean;
    procedure GetProjectModules(Proc: TGetModuleProc);
    function GetAncestorDesigner: IDesigner;
    function IsSourceReadOnly: Boolean;
    function GetScrollRanges(const ScrollPosition: TPoint): TPoint;
    procedure Edit(const Component: TComponent);
    procedure ChainCall(const MethodName, InstanceName, InstanceMethod: string; TypeData: PTypeData); overload;
    procedure ChainCall(const MethodName, InstanceName, InstanceMethod: string; const AEventInfo: IEventInfo); overload;
    procedure CopySelection;
    procedure CutSelection;
    function CanPaste: Boolean;
    procedure PasteSelection;
    procedure DeleteSelection(ADoAll: Boolean = False);
    procedure ClearSelection;
    procedure NoSelection;
    procedure ModuleFileNames(var ImplFileName, IntfFileName, FormFileName: string);
    function GetRootClassName: string;
    function UniqueName(const BaseName: string): string;
    function GetRoot: TComponent;
    function GetShiftState: TShiftState;
    procedure ModalEdit(EditKey: Char; const ReturnWindow: IActivatable);
    procedure SelectItemName(const PropertyName: string);
    procedure Resurrect;
    function GetActiveClassGroup: TPersistentClass;
    function FindRootAncestor(const AClassName: string): TComponent;
    function CreateMethod(const Name: string; const AEventInfo: IEventInfo): TMethod; overload;
    procedure GetMethods(const AEventInfo: IEventInfo; Proc: TGetStrProc); overload;
    procedure SelectComponent(const ADesignObject: IDesignObject); overload;
    function GetDesignerExtension: string;
    function GetAppDataDirectory(Local: Boolean = False): string;
    function GetCurrentParent: TComponent;
    function CreateCurrentComponentScaled(Parent: TComponent; const Rect: TRect; ScaleRect: Boolean): TComponent;
    function CreateChild(ComponentClass: TComponentClass; Parent: TComponent): TComponent;
  end;

  TTestModule = class(TInterfacedObject, IOTAModule)
  public
    Editor: TTestFormEditor;
    SaveCount: Integer;
    function AddNotifier(const ANotifier: IOTAModuleNotifier): Integer;
    procedure AddToInterface;
    function Close: Boolean;
    function GetFileName: string;
    function GetFileSystem: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(Index: Integer): IOTAEditor;
    function GetOwnerCount: Integer; deprecated;
    function GetOwner(Index: Integer): IOTAProject; deprecated;
    function HasCoClasses: Boolean;
    procedure RemoveNotifier(Index: Integer);
    function Save(ChangeName, ForceSave: Boolean): Boolean;
    procedure SetFileName(const AFileName: string);
    procedure SetFileSystem(const AFileSystem: string);
    function CloseModule(ForceClosed: Boolean): Boolean;
    function GetCurrentEditor: IOTAEditor;
    function GetOwnerModuleCount: Integer;
    function GetOwnerModule(Index: Integer): IOTAModule;
    procedure MarkModified;
    procedure Show;
    procedure ShowFilename(const FileName: string);
    procedure Refresh(ForceRefresh: Boolean);
    procedure GetAssociatedFilesFromModule(FileList: TStrings);
  end;

  TTestFormEditor = class(TInterfacedObject, IOTAEditor, IOTAFormEditor, INTAFormEditor)
  public
    Root: TForm;
    Components: TList<IOTAComponent>;
    Selection: TList<IOTAComponent>;
    DesignerObject: TTestDesigner;
    DesignerInterface: IDesigner;
    ModuleObject: TTestModule;
    ModuleInterface: IOTAModule;
    CreateCount, SelectCount, FocusCount: Integer;
    NativeSetCount: Integer;
    LastX, LastY, LastW, LastH: Integer;
    LastContainer: string;
    CreateParent: TComponent;
    ModifiedFlag: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Wrap(AInstance: TComponent): IOTAComponent;
    function Native(const AComponent: IOTAComponent): TComponent;
    function AddNotifier(const ANotifier: IOTANotifier): Integer;
    function GetFileName: string;
    function GetModified: Boolean;
    function GetModule: IOTAModule;
    function MarkModified: Boolean;
    procedure RemoveNotifier(Index: Integer);
    procedure Show;
    function GetRootComponent: IOTAComponent;
    function FindComponent(const Name: string): IOTAComponent;
    function GetComponentFromHandle(ComponentHandle: TOTAHandle): IOTAComponent;
    function GetSelCount: Integer;
    function GetSelComponent(Index: Integer): IOTAComponent;
    function GetCreateParent: IOTAComponent;
    function CreateComponent(const Container: IOTAComponent; const TypeName: string; X, Y, W, H: Integer): IOTAComponent;
    procedure GetFormResource(const Stream: IStream); overload;
    function GetFormDesigner: DesignIntf.IDesigner;
    procedure GetFormResource(Stream: TStream); overload;
  end;

var
  NamePropertyCalls: Integer;
  WidthPropertyCalls: Integer;
  WidthPropertyRaises: Boolean;

procedure RegisterTestPropertyEditors;

implementation

uses h5u.DAI.OTA.Helpers;

procedure RegisterTestPropertyEditors;
begin
  RegisterClasses([TButton, TPanel, TTimer, TTestLabel]);
  DesignIntf.RegisterPropertyEditor(GetPropInfo(TTestLabel, 'Name').PropType^,
    TTestLabel, 'Name', TTestNameProperty);
  DesignIntf.RegisterPropertyEditor(GetPropInfo(TTestLabel, 'Width').PropType^,
    TTestLabel, 'Width', TTestWidthProperty);
end;

procedure TTestNameProperty.SetValue(const Value: string);
begin
  Inc(NamePropertyCalls);
  inherited SetValue(Value);
end;

procedure TTestWidthProperty.SetValue(const Value: string);
begin
  Inc(WidthPropertyCalls);
  inherited SetValue(Value);
  if WidthPropertyRaises then
    raise EPropertyError.Create('fixture width editor failed after applying value');
end;

procedure TTestLabel.SetFailingText(const Value: string);
begin
  FFailingText := Value;
  raise EPropertyError.Create('fixture text setter failed after applying value');
end;

function PropertyAt(const AInstance: TComponent; const AIndex: Integer): PPropInfo;
var
  LList: PPropList;
  LCount: Integer;
begin
  LCount := GetPropList(AInstance, LList);
  try
    if (AIndex < 0) or (AIndex >= LCount) then
      raise EArgumentOutOfRangeException.Create('Property index out of range');
    Result := LList[AIndex];
  finally
    FreeMem(LList);
  end;
end;

procedure RequireMainThreadDispatch;
begin
  if TDAIOTA.DispatchDepth = 0 then
    raise Exception.Create('OTA access occurred outside the main-thread dispatcher');
end;

constructor TTestComponent.Create(AInstance: TComponent; AEditor: TTestFormEditor);
begin
  inherited Create;
  Instance := AInstance;
  Editor := AEditor;
end;

constructor TTestFormEditor.Create;
var
  LPanel: TPanel;
  LLabel: TTestLabel;
  LButton: TButton;
  LTimer: TTimer;
begin
  inherited Create;
  Components := TList<IOTAComponent>.Create;
  Selection := TList<IOTAComponent>.Create;
  Root := TForm.CreateNew(nil);
  Root.Name := 'Form1';
  LPanel := TPanel.Create(Root); LPanel.Name := 'Panel1'; LPanel.Parent := Root;
  LPanel := TPanel.Create(Root); LPanel.Name := 'Panel2'; LPanel.Parent := Root;
  LLabel := TTestLabel.Create(Root); LLabel.Name := 'Label1'; LLabel.Parent := TWinControl(Root.FindComponent('Panel1'));
  LLabel.Caption := 'Original caption'; LLabel.SetBounds(10, 20, 80, 24); LLabel.AutoSize := False;
  LButton := TButton.Create(Root); LButton.Name := 'Button1'; LButton.Parent := TWinControl(Root.FindComponent('Panel1'));
  LTimer := TTimer.Create(Root); LTimer.Name := 'Timer1'; LTimer.Enabled := False;
  Wrap(Root);
  DesignerObject := TTestDesigner.Create; DesignerObject.Editor := Self;
  DesignerInterface := DesignerObject;
  ModuleObject := TTestModule.Create; ModuleObject.Editor := Self;
  ModuleInterface := ModuleObject;
end;

destructor TTestFormEditor.Destroy;
begin
  Selection.Free;
  Components.Free;
  Root.Free;
  inherited Destroy;
end;

function TTestFormEditor.Wrap(AInstance: TComponent): IOTAComponent;
var
  LItem: IOTAComponent;
  LNative: INTAComponent;
begin
  Result := nil;
  if AInstance = nil then Exit;
  for LItem in Components do
    if Supports(LItem, INTAComponent, LNative) and (LNative.GetComponent = AInstance) then
      Exit(LItem);
  Result := TTestComponent.Create(AInstance, Self);
  Components.Add(Result);
end;

function TTestFormEditor.Native(const AComponent: IOTAComponent): TComponent;
var
  LNative: INTAComponent;
begin
  Result := nil;
  if Supports(AComponent, INTAComponent, LNative) then
    Result := LNative.GetComponent;
end;

function TTestComponent.GetComponentType: string;
begin
  RequireMainThreadDispatch;
  Result := Instance.ClassName;
end;

function TTestComponent.GetComponentHandle: TOTAHandle;
begin
  Result := Instance;
end;

function TTestComponent.GetParent: IOTAComponent;
begin
  if Instance is TControl then Result := Editor.Wrap(TControl(Instance).Parent) else Result := nil;
end;

function TTestComponent.IsTControl: Boolean;
begin
  Result := Instance is TControl;
end;

function TTestComponent.GetPropCount: Integer;
var LList: PPropList;
begin
  Result := GetPropList(Instance, LList);
  FreeMem(LList);
end;

function TTestComponent.GetPropName(Index: Integer): string;
begin
  Result := string(PropertyAt(Instance, Index).Name);
end;

function TTestComponent.GetPropType(Index: Integer): System.TypInfo.TTypeKind;
begin
  Result := PropertyAt(Instance, Index).PropType^.Kind;
end;

function TTestComponent.GetPropTypeByName(const Name: string): System.TypInfo.TTypeKind;
var LInfo: PPropInfo;
begin
  LInfo := GetPropInfo(Instance, Name);
  if Assigned(LInfo) then Result := LInfo.PropType^.Kind else Result := tkUnknown;
end;

function TTestComponent.GetPropValue(Index: Integer; var Value): Boolean;
begin
  Result := GetPropValueByName(GetPropName(Index), Value);
end;

function TTestComponent.GetPropValueByName(const Name: string; var Value): Boolean;
var LInfo: PPropInfo;
begin
  RequireMainThreadDispatch;
  LInfo := GetPropInfo(Instance, Name);
  Result := Assigned(LInfo);
  if not Result then Exit;
  case LInfo.PropType^.Kind of
    tkUString: PUnicodeString(@Value)^ := GetStrProp(Instance, LInfo);
    tkLString: PAnsiString(@Value)^ := AnsiString(GetStrProp(Instance, LInfo));
    tkWString: PWideString(@Value)^ := WideString(GetStrProp(Instance, LInfo));
    tkString: PShortString(@Value)^ := ShortString(GetStrProp(Instance, LInfo));
    tkInteger, tkEnumeration: PInteger(@Value)^ := GetOrdProp(Instance, LInfo);
    tkInt64: PInt64(@Value)^ := GetInt64Prop(Instance, LInfo);
  else Result := False;
  end;
end;

function TTestComponent.SetProp(Index: Integer; const Value): Boolean;
begin
  Inc(Editor.NativeSetCount);
  Result := False;
end;

function TTestComponent.SetPropByName(const Name: string; const Value): Boolean;
begin
  Inc(Editor.NativeSetCount);
  Result := False;
end;

function TTestComponent.GetChildren(Param: Pointer; Proc: TOTAGetChildCallback): Boolean;
var LIndex: Integer;
begin
  Result := True;
  for LIndex := 0 to Instance.ComponentCount - 1 do
  begin
    Proc(Param, Editor.Wrap(Instance.Components[LIndex]), Result);
    if not Result then Break;
  end;
end;

function TTestComponent.GetControlCount: Integer;
begin
  if Instance is TWinControl then Result := TWinControl(Instance).ControlCount else Result := 0;
end;

function TTestComponent.GetControl(Index: Integer): IOTAComponent;
begin
  Result := Editor.Wrap(TWinControl(Instance).Controls[Index]);
end;

function TTestComponent.GetComponentCount: Integer;
begin
  Result := Instance.ComponentCount;
end;

function TTestComponent.GetComponent(Index: Integer): IOTAComponent;
begin
  Result := Editor.Wrap(Instance.Components[Index]);
end;

function TTestComponent.Select(AddToSelection: Boolean): Boolean;
begin
  RequireMainThreadDispatch;
  Inc(Editor.SelectCount);
  if not AddToSelection then Editor.Selection.Clear;
  if Editor.Selection.IndexOf(Self as IOTAComponent) < 0 then Editor.Selection.Add(Self as IOTAComponent);
  Result := True;
end;

function TTestComponent.Focus(AddToSelection: Boolean): Boolean;
begin
  RequireMainThreadDispatch;
  Inc(Editor.FocusCount);
  // OTA Focus for the root brings its designer forward without selecting it.
  if Instance = Editor.Root then Result := True else Result := Select(AddToSelection);
end;

function TTestComponent.Delete: Boolean;
var LInstance: TComponent;
begin
  RequireMainThreadDispatch;
  Result := Instance <> Editor.Root;
  if not Result then Exit;
  LInstance := Instance;
  Instance := nil;
  Editor.Selection.Remove(Self as IOTAComponent);
  Editor.Components.Remove(Self as IOTAComponent);
  LInstance.Free;
  Editor.ModifiedFlag := True;
end;

function TTestComponent.GetPersistent: TPersistent;
begin
  Result := Instance;
end;

function TTestComponent.GetComponent: TComponent;
begin
  Result := Instance;
end;

procedure TTestDesigner.Activate;
begin
end;

procedure TTestDesigner.Modified;
begin
  RequireMainThreadDispatch;
  Inc(ModifiedCount);
  Editor.ModifiedFlag := True;
end;

function TTestDesigner.CreateMethod(const Name: string; TypeData: PTypeData): TMethod;
begin
  Result := Default(TMethod);
end;

function TTestDesigner.GetMethodName(const Method: TMethod): string;
begin
  Result := Default(string);
end;

procedure TTestDesigner.GetMethods(TypeData: PTypeData; Proc: TGetStrProc);
begin
end;

function TTestDesigner.GetPathAndBaseExeName: string;
begin
  Result := Default(string);
end;

function TTestDesigner.GetPrivateDirectory: string;
begin
  Result := Default(string);
end;

function TTestDesigner.GetBaseRegKey: string;
begin
  Result := Default(string);
end;

function TTestDesigner.GetIDEOptions: TCustomIniFile;
begin
  Result := Default(TCustomIniFile);
end;

procedure TTestDesigner.GetSelections(const List: IDesignerSelections);
var LItem: IOTAComponent;
begin
  for LItem in Editor.Selection do List.Add(Editor.Native(LItem));
end;

function TTestDesigner.MethodExists(const Name: string): Boolean;
begin
  Result := Default(Boolean);
end;

procedure TTestDesigner.RenameMethod(const CurName, NewName: string);
begin
end;

procedure TTestDesigner.SelectComponent(Instance: TPersistent);
begin
  if Instance is TComponent then Editor.Wrap(TComponent(Instance)).Select(False);
end;

procedure TTestDesigner.SetSelections(const List: IDesignerSelections);
var LIndex: Integer;
begin
  Editor.Selection.Clear;
  for LIndex := 0 to List.Count - 1 do
    if List[LIndex] is TComponent then Editor.Selection.Add(Editor.Wrap(TComponent(List[LIndex])));
end;

procedure TTestDesigner.ShowMethod(const Name: string);
begin
end;

procedure TTestDesigner.GetComponentNames(TypeData: PTypeData; Proc: TGetStrProc);
begin
end;

function TTestDesigner.GetComponent(const Name: string): TComponent;
begin
  if SameText(Editor.Root.Name, Name) then Result := Editor.Root else Result := Editor.Root.FindComponent(Name);
end;

function TTestDesigner.GetComponentName(Component: TComponent): string;
begin
  if Assigned(Component) then Result := Component.Name else Result := '';
end;

function TTestDesigner.GetObject(const Name: string): TPersistent;
begin
  Result := GetComponent(Name);
end;

function TTestDesigner.GetObjectName(Instance: TPersistent): string;
begin
  if Instance is TComponent then Result := TComponent(Instance).Name else Result := '';
end;

procedure TTestDesigner.GetObjectNames(TypeData: PTypeData; Proc: TGetStrProc);
begin
end;

function TTestDesigner.MethodFromAncestor(const Method: TMethod): Boolean;
begin
  Result := Default(Boolean);
end;

function TTestDesigner.CreateComponent(ComponentClass: TComponentClass; Parent: TComponent; Left, Top, Width, Height: Integer): TComponent;
begin
  Result := Default(TComponent);
end;

function TTestDesigner.CreateCurrentComponent(Parent: TComponent; const Rect: TRect): TComponent;
begin
  Result := Default(TComponent);
end;

function TTestDesigner.IsComponentLinkable(Component: TComponent): Boolean;
begin
  Result := Default(Boolean);
end;

function TTestDesigner.IsComponentHidden(Component: TComponent): Boolean;
begin
  Result := Default(Boolean);
end;

procedure TTestDesigner.MakeComponentLinkable(Component: TComponent);
begin
end;

procedure TTestDesigner.Revert(Instance: TPersistent; PropInfo: PPropInfo);
begin
end;

function TTestDesigner.GetIsDormant: Boolean;
begin
  Result := Default(Boolean);
end;

procedure TTestDesigner.GetProjectModules(Proc: TGetModuleProc);
begin
end;

function TTestDesigner.GetAncestorDesigner: IDesigner;
begin
  Result := Default(IDesigner);
end;

function TTestDesigner.IsSourceReadOnly: Boolean;
begin
  Result := ReadOnly;
end;

function TTestDesigner.GetScrollRanges(const ScrollPosition: TPoint): TPoint;
begin
  Result := Default(TPoint);
end;

procedure TTestDesigner.Edit(const Component: TComponent);
begin
end;

procedure TTestDesigner.ChainCall(const MethodName, InstanceName, InstanceMethod: string; TypeData: PTypeData);
begin
end;

procedure TTestDesigner.ChainCall(const MethodName, InstanceName, InstanceMethod: string; const AEventInfo: IEventInfo);
begin
end;

procedure TTestDesigner.CopySelection;
begin
end;

procedure TTestDesigner.CutSelection;
begin
end;

function TTestDesigner.CanPaste: Boolean;
begin
  Result := Default(Boolean);
end;

procedure TTestDesigner.PasteSelection;
begin
end;

procedure TTestDesigner.DeleteSelection(ADoAll: Boolean);
begin
end;

procedure TTestDesigner.ClearSelection;
begin
  Editor.Selection.Clear;
end;

procedure TTestDesigner.NoSelection;
begin
end;

procedure TTestDesigner.ModuleFileNames(var ImplFileName, IntfFileName, FormFileName: string);
begin
end;

function TTestDesigner.GetRootClassName: string;
begin
  Result := Editor.Root.ClassName;
end;

function TTestDesigner.UniqueName(const BaseName: string): string;
var LBase: string; LIndex: Integer;
begin
  LBase := BaseName;
  if (LBase <> '') and (LBase[1] = 'T') then Delete(LBase, 1, 1);
  LIndex := 1;
  repeat
    Result := LBase + IntToStr(LIndex);
    Inc(LIndex);
  until Editor.Root.FindComponent(Result) = nil;
end;

function TTestDesigner.GetRoot: TComponent;
begin
  Result := Editor.Root;
end;

function TTestDesigner.GetShiftState: TShiftState;
begin
  Result := Default(TShiftState);
end;

procedure TTestDesigner.ModalEdit(EditKey: Char; const ReturnWindow: IActivatable);
begin
end;

procedure TTestDesigner.SelectItemName(const PropertyName: string);
begin
end;

procedure TTestDesigner.Resurrect;
begin
end;

function TTestDesigner.GetActiveClassGroup: TPersistentClass;
begin
  Result := TControl;
end;

function TTestDesigner.FindRootAncestor(const AClassName: string): TComponent;
begin
  Result := Default(TComponent);
end;

function TTestDesigner.CreateMethod(const Name: string; const AEventInfo: IEventInfo): TMethod;
begin
  Result := Default(TMethod);
end;

procedure TTestDesigner.GetMethods(const AEventInfo: IEventInfo; Proc: TGetStrProc);
begin
end;

procedure TTestDesigner.SelectComponent(const ADesignObject: IDesignObject);
begin
end;

function TTestDesigner.GetDesignerExtension: string;
begin
  Result := Default(string);
end;

function TTestDesigner.GetAppDataDirectory(Local: Boolean): string;
begin
  Result := Default(string);
end;

function TTestDesigner.GetCurrentParent: TComponent;
begin
  Result := Editor.CreateParent;
end;

function TTestDesigner.CreateCurrentComponentScaled(Parent: TComponent; const Rect: TRect; ScaleRect: Boolean): TComponent;
begin
  Result := Default(TComponent);
end;

function TTestDesigner.CreateChild(ComponentClass: TComponentClass; Parent: TComponent): TComponent;
begin
  Result := Default(TComponent);
end;

function TTestModule.AddNotifier(const ANotifier: IOTAModuleNotifier): Integer;
begin
  Result := Default(Integer);
end;

procedure TTestModule.AddToInterface;
begin
end;

function TTestModule.Close: Boolean;
begin
  Result := Default(Boolean);
end;

function TTestModule.GetFileName: string;
begin
  Result := 'C:\Workspace\FormUnit.pas';
end;

function TTestModule.GetFileSystem: string;
begin
  Result := Default(string);
end;

function TTestModule.GetModuleFileCount: Integer;
begin
  Result := 1;
end;

function TTestModule.GetModuleFileEditor(Index: Integer): IOTAEditor;
begin
  Result := Editor as IOTAEditor;
end;

function TTestModule.GetOwnerCount: Integer;
begin
  Result := Default(Integer);
end;

function TTestModule.GetOwner(Index: Integer): IOTAProject;
begin
  Result := Default(IOTAProject);
end;

function TTestModule.HasCoClasses: Boolean;
begin
  Result := Default(Boolean);
end;

procedure TTestModule.RemoveNotifier(Index: Integer);
begin
end;

function TTestModule.Save(ChangeName, ForceSave: Boolean): Boolean;
begin
  Inc(SaveCount);
  raise Exception.Create('Designer operation attempted to save the test module');
end;

procedure TTestModule.SetFileName(const AFileName: string);
begin
end;

procedure TTestModule.SetFileSystem(const AFileSystem: string);
begin
end;

function TTestModule.CloseModule(ForceClosed: Boolean): Boolean;
begin
  Result := Default(Boolean);
end;

function TTestModule.GetCurrentEditor: IOTAEditor;
begin
  Result := Default(IOTAEditor);
end;

function TTestModule.GetOwnerModuleCount: Integer;
begin
  Result := Default(Integer);
end;

function TTestModule.GetOwnerModule(Index: Integer): IOTAModule;
begin
  Result := Default(IOTAModule);
end;

procedure TTestModule.MarkModified;
begin
end;

procedure TTestModule.Show;
begin
end;

procedure TTestModule.ShowFilename(const FileName: string);
begin
end;

procedure TTestModule.Refresh(ForceRefresh: Boolean);
begin
end;

procedure TTestModule.GetAssociatedFilesFromModule(FileList: TStrings);
begin
end;

function TTestFormEditor.AddNotifier(const ANotifier: IOTANotifier): Integer;
begin
  Result := Default(Integer);
end;

function TTestFormEditor.GetFileName: string;
begin
  Result := 'C:\Workspace\FormUnit.dfm';
end;

function TTestFormEditor.GetModified: Boolean;
begin
  Result := ModifiedFlag;
end;

function TTestFormEditor.GetModule: IOTAModule;
begin
  Result := ModuleInterface;
end;

function TTestFormEditor.MarkModified: Boolean;
begin
  ModifiedFlag := True;
  Result := True;
end;

procedure TTestFormEditor.RemoveNotifier(Index: Integer);
begin
end;

procedure TTestFormEditor.Show;
begin
end;

function TTestFormEditor.GetRootComponent: IOTAComponent;
begin
  Result := Wrap(Root);
end;

function TTestFormEditor.FindComponent(const Name: string): IOTAComponent;
begin
  RequireMainThreadDispatch;
  if SameText(Name, Root.Name) then Result := Wrap(Root) else Result := Wrap(Root.FindComponent(Name));
end;

function TTestFormEditor.GetComponentFromHandle(ComponentHandle: TOTAHandle): IOTAComponent;
begin
  Result := Wrap(TComponent(ComponentHandle));
end;

function TTestFormEditor.GetSelCount: Integer;
begin
  Result := Selection.Count;
end;

function TTestFormEditor.GetSelComponent(Index: Integer): IOTAComponent;
begin
  Result := Selection[Index];
end;

function TTestFormEditor.GetCreateParent: IOTAComponent;
begin
  Result := Wrap(CreateParent);
end;

function TTestFormEditor.CreateComponent(const Container: IOTAComponent; const TypeName: string; X, Y, W, H: Integer): IOTAComponent;
var LInstance, LParent: TComponent; LControl: TControl;
begin
  RequireMainThreadDispatch;
  Inc(CreateCount);
  LParent := Native(Container);
  if Assigned(LParent) then LastContainer := LParent.Name else LastContainer := '';
  LastX := X; LastY := Y; LastW := W; LastH := H;
  if SameText(TypeName, 'TButton') then LInstance := TButton.Create(Root)
  else if SameText(TypeName, 'TUnregisteredPaletteButton') then LInstance := TUnregisteredPaletteButton.Create(Root)
  else if SameText(TypeName, 'TPanel') then LInstance := TPanel.Create(Root)
  else if SameText(TypeName, 'TTimer') then LInstance := TTimer.Create(Root)
  else raise EArgumentException.Create('Unsupported fixture class: ' + TypeName);
  LInstance.Name := DesignerObject.UniqueName(TypeName);
  if LInstance is TControl then
  begin
    LControl := TControl(LInstance);
    if not (LParent is TWinControl) then raise EArgumentException.Create('Fixture parent is not a container');
    LControl.Parent := TWinControl(LParent);
    if X >= 0 then LControl.Left := X;
    if Y >= 0 then LControl.Top := Y;
    if W >= 0 then LControl.Width := W;
    if H >= 0 then LControl.Height := H;
  end;
  ModifiedFlag := True;
  Result := Wrap(LInstance);
end;

procedure TTestFormEditor.GetFormResource(const Stream: IStream);
begin
end;

function TTestFormEditor.GetFormDesigner: DesignIntf.IDesigner;
begin
  Result := DesignerInterface;
end;

procedure TTestFormEditor.GetFormResource(Stream: TStream);
begin
end;

end.
