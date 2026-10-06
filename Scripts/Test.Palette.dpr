program TestPalette;
{$APPTYPE CONSOLE}

// The generated include contains the exact production routines. Doubles implement the SDK
// palette interfaces; no running IDE, registry, file changes or palette execution is involved.
uses
  System.Classes, System.Generics.Collections, System.JSON, System.StrUtils, System.SysUtils, PaletteAPI;

type
  TFakePaletteItem = class(TInterfacedObject, IOTABasePaletteItem)
  public
    DisplayName: string;
    IsEnabled: Boolean;
    IsVisible: Boolean;
    constructor Create(const AName: string; const AEnabled: Boolean = True; const AVisible: Boolean = True);
    function GetCanDelete: Boolean;
    function GetEnabled: Boolean;
    function GetHelpName: string;
    function GetHintText: string;
    function GetIDString: string;
    function GetName: string;
    function GetVisible: Boolean;
    procedure SetEnabled(Value: Boolean);
    procedure SetHelpName(const Value: string);
    procedure SetName(const Value: string);
    procedure SetVisible(const Value: Boolean);
    procedure SetHintText(const Value: string);
    procedure Execute;
    procedure Delete;
    function GetImageIndex: Integer;
    procedure SetImageIndex(const Value: Integer);
  end;
  TFakeComponentItem = class(TFakePaletteItem, IOTAComponentPaletteItem)
  public
    ComponentClass: string;
    ComponentUnit: string;
    ComponentPackage: string;
    constructor Create(const AName, AClassName, AUnitName, APackageName: string;
      const AEnabled: Boolean = True; const AVisible: Boolean = True);
    procedure SetPackageName(const Value: string);
    procedure SetClassName(const Value: string);
    procedure SetUnitName(const Value: string);
    function GetClassName: string;
    function GetPackageName: string;
    function GetUnitName: string;
  end;
  TFakePaletteGroup = class(TFakePaletteItem, IOTAPaletteGroup)
  private
    FItems: TList<IOTABasePaletteItem>;
  public
    SyntheticCount: Integer;
    SyntheticItem: IOTABasePaletteItem;
    constructor Create(const AName: string; const AEnabled: Boolean = True; const AVisible: Boolean = True);
    destructor Destroy; override;
    procedure AddFixture(const AItem: IOTABasePaletteItem);
    procedure ClearFixture;
    function GetCount: Integer;
    function GetItem(const Index: Integer): IOTABasePaletteItem;
    function AddGroup(const Name, IDString: string): IOTAPaletteGroup;
    function AddItem(const Item: IOTABasePaletteItem): Integer;
    procedure Clear;
    function FindItem(const IDString: string; Recurse: Boolean): IOTABasePaletteItem;
    function FindItemByName(const Name: string; Recurse: Boolean): IOTABasePaletteItem;
    function FindItemGroup(const IDString: string): IOTAPaletteGroup;
    function FindItemGroupByName(const Name: string): IOTAPaletteGroup;
    procedure InsertItem(const Index: Integer; const Item: IOTABasePaletteItem);
    function IndexOf(const Item: IOTABasePaletteItem): Integer;
    procedure Move(const CurIndex, NewIndex: Integer);
    function RemoveItem(const IDString: string; Recurse: Boolean): Boolean;
  end;

var
  GChecks: Integer;

procedure Check(const ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    raise Exception.Create('FAIL: ' + AName);
  Inc(GChecks);
end;

procedure UnexpectedMutation;
begin
  raise Exception.Create('Palette listing must not call mutation or execution methods');
end;

constructor TFakePaletteItem.Create(const AName: string; const AEnabled, AVisible: Boolean);
begin
  inherited Create;
  DisplayName := AName;
  IsEnabled := AEnabled;
  IsVisible := AVisible;
end;
function TFakePaletteItem.GetCanDelete: Boolean; begin Result := False; end;
function TFakePaletteItem.GetEnabled: Boolean; begin Result := IsEnabled; end;
function TFakePaletteItem.GetHelpName: string; begin Result := ''; end;
function TFakePaletteItem.GetHintText: string; begin Result := ''; end;
function TFakePaletteItem.GetIDString: string; begin Result := DisplayName; end;
function TFakePaletteItem.GetName: string; begin Result := DisplayName; end;
function TFakePaletteItem.GetVisible: Boolean; begin Result := IsVisible; end;
procedure TFakePaletteItem.SetEnabled(Value: Boolean); begin UnexpectedMutation; end;
procedure TFakePaletteItem.SetHelpName(const Value: string); begin UnexpectedMutation; end;
procedure TFakePaletteItem.SetName(const Value: string); begin UnexpectedMutation; end;
procedure TFakePaletteItem.SetVisible(const Value: Boolean); begin UnexpectedMutation; end;
procedure TFakePaletteItem.SetHintText(const Value: string); begin UnexpectedMutation; end;
procedure TFakePaletteItem.Execute; begin UnexpectedMutation; end;
procedure TFakePaletteItem.Delete; begin UnexpectedMutation; end;
function TFakePaletteItem.GetImageIndex: Integer; begin Result := -1; end;
procedure TFakePaletteItem.SetImageIndex(const Value: Integer); begin UnexpectedMutation; end;

constructor TFakeComponentItem.Create(const AName, AClassName, AUnitName, APackageName: string;
  const AEnabled, AVisible: Boolean);
begin
  inherited Create(AName, AEnabled, AVisible);
  ComponentClass := AClassName;
  ComponentUnit := AUnitName;
  ComponentPackage := APackageName;
end;
procedure TFakeComponentItem.SetPackageName(const Value: string); begin UnexpectedMutation; end;
procedure TFakeComponentItem.SetClassName(const Value: string); begin UnexpectedMutation; end;
procedure TFakeComponentItem.SetUnitName(const Value: string); begin UnexpectedMutation; end;
function TFakeComponentItem.GetClassName: string; begin Result := ComponentClass; end;
function TFakeComponentItem.GetPackageName: string; begin Result := ComponentPackage; end;
function TFakeComponentItem.GetUnitName: string; begin Result := ComponentUnit; end;

constructor TFakePaletteGroup.Create(const AName: string; const AEnabled, AVisible: Boolean);
begin
  inherited Create(AName, AEnabled, AVisible);
  FItems := TList<IOTABasePaletteItem>.Create;
end;
destructor TFakePaletteGroup.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;
procedure TFakePaletteGroup.AddFixture(const AItem: IOTABasePaletteItem); begin FItems.Add(AItem); end;
procedure TFakePaletteGroup.ClearFixture; begin FItems.Clear; SyntheticItem := nil; end;
function TFakePaletteGroup.GetCount: Integer;
begin
  if SyntheticCount > 0 then Result := SyntheticCount else Result := FItems.Count;
end;
function TFakePaletteGroup.GetItem(const Index: Integer): IOTABasePaletteItem;
begin
  if SyntheticCount > 0 then
  begin
    if (Index < 0) or (Index >= SyntheticCount) then
      raise EArgumentOutOfRangeException.Create('Synthetic index out of range');
    Result := SyntheticItem;
  end
  else Result := FItems[Index];
end;
function TFakePaletteGroup.AddGroup(const Name, IDString: string): IOTAPaletteGroup; begin UnexpectedMutation; Result := nil; end;
function TFakePaletteGroup.AddItem(const Item: IOTABasePaletteItem): Integer; begin UnexpectedMutation; Result := -1; end;
procedure TFakePaletteGroup.Clear; begin UnexpectedMutation; end;
function TFakePaletteGroup.FindItem(const IDString: string; Recurse: Boolean): IOTABasePaletteItem; begin Result := nil; end;
function TFakePaletteGroup.FindItemByName(const Name: string; Recurse: Boolean): IOTABasePaletteItem; begin Result := nil; end;
function TFakePaletteGroup.FindItemGroup(const IDString: string): IOTAPaletteGroup; begin Result := nil; end;
function TFakePaletteGroup.FindItemGroupByName(const Name: string): IOTAPaletteGroup; begin Result := nil; end;
procedure TFakePaletteGroup.InsertItem(const Index: Integer; const Item: IOTABasePaletteItem); begin UnexpectedMutation; end;
function TFakePaletteGroup.IndexOf(const Item: IOTABasePaletteItem): Integer; begin Result := FItems.IndexOf(Item); end;
procedure TFakePaletteGroup.Move(const CurIndex, NewIndex: Integer); begin UnexpectedMutation; end;
function TFakePaletteGroup.RemoveItem(const IDString: string; Recurse: Boolean): Boolean; begin UnexpectedMutation; Result := False; end;

{$I DAI.Palette.Functions.inc}

procedure InvalidArguments(const AJson: string);
var
  LArguments: TJSONObject;
  LRejected: Boolean;
begin
  LArguments := TJSONObject(TJSONObject.ParseJSONValue(AJson));
  try
    LRejected := False;
    try
      ParsePaletteArguments(LArguments);
    except
      on E: EArgumentException do LRejected := True;
    end;
    Check(LRejected, 'reject invalid arguments ' + AJson);
  finally
    LArguments.Free;
  end;
end;

procedure TestQueries;
var
  LArguments: TJSONObject;
  LBase, LStandard, LNested, LHidden: TFakePaletteGroup;
  LRoot, LKeepStandard, LKeepNested, LKeepHidden: IOTAPaletteGroup;
  LResult, LItem: TJSONObject;
  LOptions: TDAIPaletteOptions;
begin
  LBase := TFakePaletteGroup.Create('Palette root', False, False);
  LRoot := LBase;
  LStandard := TFakePaletteGroup.Create('Standard'); LKeepStandard := LStandard;
  LNested := TFakePaletteGroup.Create('Nested'); LKeepNested := LNested;
  LHidden := TFakePaletteGroup.Create('Hidden', False, False); LKeepHidden := LHidden;
  LBase.AddFixture(LStandard);
  LBase.AddFixture(LHidden);
  LBase.AddFixture(TFakePaletteItem.Create('New Delphi project wizard'));
  LStandard.AddFixture(TFakeComponentItem.Create('Button', 'TButton', 'Vcl.StdCtrls', 'vcl'));
  LStandard.AddFixture(TFakeComponentItem.Create('Label', 'TLabel', 'Vcl.StdCtrls', 'vcl', False));
  LStandard.AddFixture(LNested);
  LNested.AddFixture(TFakeComponentItem.Create('CIM caption', 'TCimLabel', 'Cim.Labels', 'CimComponents'));
  LNested.AddFixture(TFakeComponentItem.Create('Literal[*]', 'TLiteral', '', 'Custom'));
  LNested.AddFixture(LStandard); // Verify recursion-cycle protection using SDK identity.
  LHidden.AddFixture(TFakeComponentItem.Create('HiddenButton', 'THiddenButton', 'Hidden.Unit', 'HiddenPkg'));
  try
    LOptions := ParsePaletteArguments(nil);
    Check(LOptions.MaximumResults = 500, 'default result limit');
    Check(not LOptions.IncludeUnavailable, 'default only currently available items');
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try
      Check(LResult.GetValue<Integer>('count') = 3, 'only enabled visible components and no wizards');
      Check(LResult.GetValue<Integer>('total_examined') = 5, 'examines disabled and hidden components');
      Check(LResult.GetValue<Integer>('repeated_groups_skipped') = 1, 'cycle visited once');
      Check(not LResult.GetValue<Boolean>('truncated'), 'cycle does not truncate valid unique subtree');
      LItem := TJSONObject(LResult.GetValue<TJSONArray>('components').Items[0]);
      Check(LItem.GetValue<string>('class_name') = 'TButton', 'class metadata');
      Check(LItem.GetValue<string>('display_name') = 'Button', 'display metadata');
      Check(LItem.GetValue<string>('unit_name') = 'Vcl.StdCtrls', 'unit metadata');
      Check(LItem.GetValue<string>('package_name') = 'vcl', 'package metadata');
      Check(LItem.GetValue<string>('category') = 'Standard', 'base root name not part of category');
      LItem := TJSONObject(LResult.GetValue<TJSONArray>('components').Items[1]);
      Check(LItem.GetValue<string>('category') = 'Standard/Nested', 'nested category path');
    finally LResult.Free; end;

    LOptions.IncludeUnavailable := True;
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try
      Check(LResult.GetValue<Integer>('count') = 5, 'include unavailable components');
      LItem := TJSONObject(LResult.GetValue<TJSONArray>('components').Items[4]);
      Check(not LItem.GetValue<Boolean>('enabled'), 'disabled category influences effective availability');
      Check(not LItem.GetValue<Boolean>('visible'), 'hidden category influences effective visibility');
      Check(LItem.GetValue<Boolean>('item_enabled'), 'own component enabled state remains visible');
      Check(LItem.GetValue<Boolean>('item_visible'), 'own component visible state remains visible');
    finally LResult.Free; end;

    LOptions.Query := 'cimlabel';
    LOptions.Category := 'STANDARD/nested';
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try
      Check(LResult.GetValue<Integer>('count') = 1, 'case insensitive class query and category together');
    finally LResult.Free; end;
    LOptions.Query := 'CIM caption';
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try Check(LResult.GetValue<Integer>('count') = 1, 'display-name query'); finally LResult.Free; end;
    LOptions.Query := '[*]';
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try Check(LResult.GetValue<Integer>('count') = 1, 'query treats mask characters literally'); finally LResult.Free; end;
    LOptions.Query := '';
    LOptions.Category := 'absent';
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try Check(LResult.GetValue<Integer>('count') = 0, 'no category matches'); finally LResult.Free; end;
    LOptions.Category := '';
    LOptions.MaximumResults := 1;
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try
      Check(LResult.GetValue<Integer>('count') = 1, 'result limit enforced');
      Check(LResult.GetValue<Integer>('matched_count') = 5, 'matched count independent of result limit');
      Check(LResult.GetValue<Boolean>('truncated'), 'reports result truncation');
      Check(not LResult.GetValue<Boolean>('traversal_truncated'), 'result limit does not falsely mark traversal incomplete');
    finally LResult.Free; end;

    LArguments := TJSONObject(TJSONObject.ParseJSONValue('{"query":"x","category":"y","include_unavailable":true,"maximum_results":4096}'));
    try
      LOptions := ParsePaletteArguments(LArguments);
      Check((LOptions.Query = 'x') and (LOptions.Category = 'y') and LOptions.IncludeUnavailable and
        (LOptions.MaximumResults = 4096), 'valid arguments and upper result limit');
    finally LArguments.Free; end;
  finally
    // Remove the deliberate cycle before releasing the SDK interfaces.
    LNested.ClearFixture;
    LStandard.ClearFixture;
  end;
end;

procedure TestBounds;
var
  LBase, LGroup, LNext: TFakePaletteGroup;
  LGroups: TList<IOTAPaletteGroup>;
  LRoot: IOTAPaletteGroup;
  LResult: TJSONObject;
  LOptions: TDAIPaletteOptions;
  LIndex: Integer;
  LRejected: Boolean;
begin
  LOptions := ParsePaletteArguments(nil);
  LBase := TFakePaletteGroup.Create('Budget');
  LRoot := LBase;
  LBase.SyntheticCount := CMaximumPaletteItems + 1;
  LBase.SyntheticItem := TFakeComponentItem.Create('Button', 'TButton', 'Vcl.StdCtrls', 'vcl');
  LResult := PaletteComponentsJson(LRoot, LOptions);
  try
    Check(LResult.GetValue<Integer>('palette_items_examined') = CMaximumPaletteItems, 'hard palette-item budget');
    Check(LResult.GetValue<Integer>('count') = 500, 'output bounded during large traversal');
    Check(LResult.GetValue<Boolean>('traversal_truncated'), 'reports traversal budget');
  finally LResult.Free; end;
  LRoot := nil;

  LGroups := TList<IOTAPaletteGroup>.Create;
  try
    LBase := TFakePaletteGroup.Create('Depth'); LRoot := LBase;
    LGroups.Add(LRoot);
    LGroup := LBase;
    for LIndex := 1 to CMaximumPaletteDepth + 1 do
    begin
      LNext := TFakePaletteGroup.Create('Level' + IntToStr(LIndex));
      LGroups.Add(LNext);
      LGroup.AddFixture(LNext);
      LGroup := LNext;
    end;
    LGroup.AddFixture(TFakeComponentItem.Create('Beyond depth', 'TDeep', '', ''));
    LResult := PaletteComponentsJson(LRoot, LOptions);
    try
      Check(LResult.GetValue<Boolean>('traversal_truncated'), 'recursion depth bounded');
      Check(LResult.GetValue<Integer>('count') = 0, 'over-depth component excluded');
    finally LResult.Free; end;
  finally LGroups.Free; end;
  LRejected := False;
  try PaletteComponentsJson(nil, LOptions); except on E: EInvalidOperation do LRejected := True; end;
  Check(LRejected, 'missing base group is explicit error');
end;

begin
  try
    TestQueries;
    TestBounds;
    InvalidArguments('{"query":true}');
    InvalidArguments('{"category":null}');
    InvalidArguments('{"include_unavailable":"true"}');
    InvalidArguments('{"maximum_results":0}');
    InvalidArguments('{"maximum_results":4097}');
    InvalidArguments('{"maximum_results":1.5}');
    InvalidArguments('{"maximum_results":"2"}');
    InvalidArguments('{"maximum_results":9223372036854775807}');
    InvalidArguments('{"unknown":true}');
    Writeln('PASS: ', GChecks, ' palette SDK checks');
  except
    on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end;
  end;
end.
