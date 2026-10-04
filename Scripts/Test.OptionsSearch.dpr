program Test.OptionsSearch;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Options.Search;

type
  TTestOptions = class(TInterfacedObject, IOTAProjectOptions, IOTAEnvironmentOptions)
  public
    Names: TOTAOptionNameArray;
    ReadCount: Integer;
    FailRead: Boolean;
    function GetOptionNames: TOTAOptionNameArray;
  end;

  TTestProject = class(TInterfacedObject, IOTAProject)
  public
    Options: IOTAProjectOptions;
    function GetFileName: string;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetProjectOptions: IOTAProjectOptions;
  end;

  TTestItem = class(TInterfacedObject, INTAIDEInsightItem)
  public
    TitleText, DescriptionText: string;
    VisibleValue: Boolean;
    class var ExecuteCount, UpdateCount: Integer;
    function GetTitle: string;
    function GetDescription: string;
    function GetVisible: Boolean;
    procedure Execute;
    procedure Update;
  end;

  TTestCategory = class(TInterfacedObject, IOTAIDEInsightCategory)
  public
    CaptionText: string;
    DisabledValue: Boolean;
    ItemsValue: TArray<INTAIDEInsightItem>;
    function GetCaption: string;
    function GetDisabled: Boolean;
    function GetItem(const AIndex: Integer): INTAIDEInsightItem;
    function ItemCount: Integer;
  end;

  TTestServices = class(TInterfacedObject, IOTAServices, IOTAIDEInsightService)
  public
    Environment: IOTAEnvironmentOptions;
    Categories: TArray<IOTAIDEInsightCategory>;
    FailInsight: Boolean;
    InsightReads: Integer;
    class var InvokeCount, FilterCount: Integer;
    function GetEnvironmentOptions: IOTAEnvironmentOptions;
    function CategoryCount: Integer;
    function GetCategory(const AIndexOrName: Variant): IOTAIDEInsightCategory;
    procedure Invoke;
    procedure Filter(const AText: string);
  end;

var
  CheckCount: Integer;
  OptionsObject, EnvironmentObject: TTestOptions;
  OptionsInterface: IOTAProjectOptions;
  EnvironmentInterface: IOTAEnvironmentOptions;
  ServicesObject: TTestServices;
  ServicesInterface: IInterface;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise EInvalidOperation.Create(AMessage);
end;

procedure RequireIDEThread;
begin
  if TDAIOTA.DispatchDepth = 0 then
    raise EInvalidOperation.Create('Metadata must be captured on the IDE thread.');
end;

function Value(const AObject: TJSONObject; const AName: string): string;
var
  LValue: TJSONValue;
begin
  LValue := AObject.GetValue(AName);
  Check(Assigned(LValue), 'Missing field: ' + AName);
  Result := LValue.Value;
end;

function Names(const AKeys: array of string): TOTAOptionNameArray;
var
  LIndex: Integer;
begin
  SetLength(Result, Length(AKeys));
  for LIndex := 0 to High(AKeys) do
  begin
    Result[LIndex].Name := AKeys[LIndex];
    Result[LIndex].Kind := tkUString;
  end;
end;

function TTestOptions.GetOptionNames: TOTAOptionNameArray;
begin
  RequireIDEThread;
  Inc(ReadCount);
  if FailRead then
    raise EInvalidOperation.Create('SDK names unavailable.');
  Result := Names;
end;

function TTestProject.GetFileName: string;
begin
  RequireIDEThread;
  Result := 'C:\SyntheticOptionsTest\Selected.dproj';
end;

function TTestProject.GetConfiguration: string;
begin
  RequireIDEThread;
  Result := 'Release';
end;

function TTestProject.GetPlatform: string;
begin
  RequireIDEThread;
  Result := 'Win64';
end;

function TTestProject.GetProjectOptions: IOTAProjectOptions;
begin
  RequireIDEThread;
  Result := Options;
end;

function TTestItem.GetTitle: string;
begin
  RequireIDEThread;
  Result := TitleText;
end;

function TTestItem.GetDescription: string;
begin
  RequireIDEThread;
  Result := DescriptionText;
end;

function TTestItem.GetVisible: Boolean;
begin
  RequireIDEThread;
  Result := VisibleValue;
end;

procedure TTestItem.Execute;
begin
  Inc(ExecuteCount);
  raise EInvalidOperation.Create('Search must never execute a cached item.');
end;

procedure TTestItem.Update;
begin
  Inc(UpdateCount);
  raise EInvalidOperation.Create('Search must never update cached providers.');
end;

function TTestCategory.GetCaption: string;
begin
  RequireIDEThread;
  Result := CaptionText;
end;

function TTestCategory.GetDisabled: Boolean;
begin
  RequireIDEThread;
  Result := DisabledValue;
end;

function TTestCategory.GetItem(const AIndex: Integer): INTAIDEInsightItem;
begin
  RequireIDEThread;
  Result := ItemsValue[AIndex];
end;

function TTestCategory.ItemCount: Integer;
begin
  RequireIDEThread;
  Result := Length(ItemsValue);
end;

function TTestServices.GetEnvironmentOptions: IOTAEnvironmentOptions;
begin
  RequireIDEThread;
  Result := Environment;
end;

function TTestServices.CategoryCount: Integer;
begin
  RequireIDEThread;
  Inc(InsightReads);
  if FailInsight then
    raise EInvalidOperation.Create('Cached Insight service unavailable.');
  Result := Length(Categories);
end;

function TTestServices.GetCategory(const AIndexOrName: Variant): IOTAIDEInsightCategory;
begin
  RequireIDEThread;
  Result := Categories[Integer(AIndexOrName)];
end;

procedure TTestServices.Invoke;
begin
  Inc(InvokeCount);
  raise EInvalidOperation.Create('Search must not invoke IDE Insight.');
end;

procedure TTestServices.Filter(const AText: string);
begin
  Inc(FilterCount);
  raise EInvalidOperation.Create('Search must not filter the IDE popup.');
end;

function Search(const AQuery: string; const AScope: string = 'project'; const AMaximum: Integer = 100): TJSONObject;
begin
  Result := TDAIOptionsSearchService.Search(AQuery, AScope, '', AMaximum);
end;

procedure CheckBadArguments(const AQuery, AScope, AProject: string; const AMaximum: Integer);
var
  LJson: TJSONObject;
  LRaised: Boolean;
begin
  LRaised := False;
  try
    LJson := TDAIOptionsSearchService.Search(AQuery, AScope, AProject, AMaximum);
    LJson.Free;
  except
    on E: EArgumentException do LRaised := True;
  end;
  Check(LRaised, 'Invalid search request must fail explicitly.');
end;

function Item(const ATitle, ADescription: string; const AVisible: Boolean): INTAIDEInsightItem;
var
  LItem: TTestItem;
begin
  LItem := TTestItem.Create;
  LItem.TitleText := ATitle;
  LItem.DescriptionText := ADescription;
  LItem.VisibleValue := AVisible;
  Result := LItem;
end;

procedure RunTests;
var
  LCategory: TTestCategory;
  LProject: TTestProject;
  LJson, LResult, LStatus: TJSONObject;
  LResults, LSources: TJSONArray;
  LLabels: TArray<string>;
  LIndex, LBeforeCount: Integer;
  LId: string;
begin
  OptionsObject := TTestOptions.Create;
  OptionsInterface := OptionsObject;
  OptionsObject.Names := Names(['DCC_ExeOutput', 'DCC_DcuOutput', 'DCC_BplOutput', 'DCC_DcpOutput', 'DCC_UnitSearchPath',
    'DCC_IncludePath', 'DCC_ResourcePath', 'DCC_Define', 'DCC_Namespace', 'DCC_UnitAlias', 'DCC_UsePackage', 'DCC_LibraryPath']);
  EnvironmentObject := TTestOptions.Create;
  EnvironmentInterface := EnvironmentObject;
  EnvironmentObject.Names := Names(['EditorFont', 'OutputDir']);
  ServicesObject := TTestServices.Create;
  ServicesInterface := ServicesObject;
  ServicesObject.Environment := EnvironmentInterface;
  BorlandIDEServices := ServicesInterface;
  LProject := TTestProject.Create;
  LProject.Options := OptionsInterface;
  TDAIOTA.TestProject := LProject;
  CheckBadArguments('', 'all', '', 100);
  CheckBadArguments(StringOfChar('a', 257), 'all', '', 100);
  CheckBadArguments('abc' + #0, 'all', '', 100);
  CheckBadArguments('---', 'all', '', 100);
  CheckBadArguments('output', 'unknown', '', 100);
  CheckBadArguments('output', 'all', '', 0);
  CheckBadArguments('output', 'all', '', 501);
  CheckBadArguments('output', 'ide', 'Missing', 100);
  LLabels := TDAIOptionsSearchService.OptionLabels('DCC_ExeOutput');
  Check(Length(LLabels) = 4, 'Known option has display aliases and key.');
  Check(LLabels[High(LLabels)] = 'DCC_ExeOutput', 'Technical key preserved.');
  Check(TDAIOptionsSearchService.OptionLabels('UnknownOption')[0] = 'UnknownOption', 'Unknown labels do not manufacture metadata.');
  Check(Length(TDAIOptionsSearchService.OptionLabels('')) = 0, 'Empty option labels.');
  LJson := Search('Ausgabepfad');
  try
    Check(Value(LJson, 'result_count') = '4', 'Four real SDK output options match German keyword.');
    Check(Value(LJson, 'complete') = 'false', 'Catalog does not claim UI completeness.');
    Check(Value(LJson, 'truncated') = 'false', 'Untruncated keyword results.');
    LResults := LJson.GetValue<TJSONArray>('results');
    LResult := TJSONObject(LResults.Items[0]);
    Check(Value(LResult, 'id') = 'project:DCC_ExeOutput', 'Stable SDK option ID.');
    Check(Value(LResult, 'name') = 'DCC_ExeOutput', 'Actual SDK name.');
    Check(Value(LResult, 'option_type') = 'tkUString', 'Actual SDK kind.');
    Check(Value(LResult, 'configuration') = 'Release', 'Own current configuration.');
    Check(Value(LResult, 'platform') = 'Win64', 'Own current platform.');
    Check(Value(LResult, 'project') = 'C:\SyntheticOptionsTest\Selected.dproj', 'Own project path.');
    Check(Value(LResult, 'navigation_mode') = 'dialog', 'Dialog navigation only.');
    Check(LResult.GetValue('focus_supported') is TJSONNull, 'Search cannot promise field focus.');
  finally LJson.Free; end;
  LJson := Search('aUSGABEpfad EXE');
  try Check(Value(LJson, 'result_count') = '1', 'Case-insensitive AND keywords.'); finally LJson.Free; end;
  LJson := Search('resource search');
  try Check(Value(LJson, 'result_count') = '1', 'English label keyword search.'); finally LJson.Free; end;
  LJson := Search('bedingte symbole');
  try Check(Value(LJson, 'result_count') = '1', 'German conditional symbol aliases.'); finally LJson.Free; end;
  LJson := Search('Ausgabepfad', 'project', 2);
  try
    Check(Value(LJson, 'result_count') = '2', 'Maximum results enforced.');
    Check(Value(LJson, 'matched_count') = '4', 'Count remaining keyword matches.');
    Check(Value(LJson, 'truncated') = 'true', 'Result truncation indicated.');
  finally LJson.Free; end;
  LJson := Search('Ausgabepfad', 'ide');
  try
    LResults := LJson.GetValue<TJSONArray>('results');
    Check(LResults.Count = 1, 'Legacy actual SDK output name searchable.');
    Check(Value(TJSONObject(LResults.Items[0]), 'name') = 'OutputDir', 'Legacy key remains legacy; no fake DCC key.');
  finally LJson.Free; end;
  LBeforeCount := ServicesObject.InsightReads;
  LJson := Search('not-present');
  try Check(Value(LJson, 'result_count') = '0', 'No guessed options from aliases.'); finally LJson.Free; end;
  Check(ServicesObject.InsightReads = LBeforeCount, 'Project-only search leaves Insight untouched.');
  OptionsObject.Names := Names(['DCC_ExeOutput', 'dcc_exeoutput', '', 'bad' + #0]);
  LJson := Search('output');
  try Check(Value(LJson, 'catalog_count') = '1', 'Deduplicate real keys and skip malformed SDK names.'); finally LJson.Free; end;
  OptionsObject.Names := Names(['DCC_ExeOutput']);

  LCategory := TTestCategory.Create;
  LCategory.CaptionText := 'Project Options';
  LCategory.ItemsValue := [nil, Item('Ausgabepfad', 'EXE directory', True), Item('Ausgabepfad hidden', '', False)];
  ServicesObject.Categories := [nil, LCategory];
  LCategory := TTestCategory.Create;
  LCategory.CaptionText := 'Commands';
  LCategory.ItemsValue := [Item('Delete project', 'Ausgabepfad command metadata', True)];
  ServicesObject.Categories := ServicesObject.Categories + [LCategory];
  LCategory := TTestCategory.Create;
  LCategory.CaptionText := 'Voreinstellungen';
  LCategory.DisabledValue := True;
  LCategory.ItemsValue := [Item('Ausgabepfad disabled', '', True)];
  ServicesObject.Categories := ServicesObject.Categories + [LCategory];
  LJson := Search('Ausgabepfad', 'insight');
  try
    LResults := LJson.GetValue<TJSONArray>('results');
    Check(LResults.Count = 4, 'Read cached visible, hidden and disabled metadata honestly.');
    LResult := TJSONObject(LResults.Items[0]);
    LId := Value(LResult, 'id');
    Check(LId.StartsWith('insight:'), 'Insight semantic ID.');
    Check(LResult.GetValue('index') = nil, 'No popup result indices.');
    Check(Value(LResult, 'navigation_mode') = 'insight_option', 'Visible known option category can delegate explicit navigation.');
    Check(LResult.GetValue('focus_supported') is TJSONNull, 'No Insight focus promise.');
    Check(TJSONObject(LResults.Items[1]).GetValue('navigation_mode') is TJSONNull, 'Hidden entry has no selection promise.');
    Check(TJSONObject(LResults.Items[2]).GetValue('navigation_mode') is TJSONNull, 'Commands cannot masquerade as options.');
    Check(TJSONObject(LResults.Items[3]).GetValue('navigation_mode') is TJSONNull, 'Disabled category has no selection promise.');
    LSources := LJson.GetValue<TJSONArray>('sources');
    LStatus := TJSONObject(LSources.Items[0]);
    Check(Value(LStatus, 'cached') = 'true', 'Cached source reported.');
    Check(Value(LStatus, 'complete') = 'false', 'Cached Insight never claimed complete or fresh.');
  finally LJson.Free; end;
  LJson := Search('Ausgabepfad', 'insight');
  try
    LResults := LJson.GetValue<TJSONArray>('results');
    Check(Value(TJSONObject(LResults.Items[0]), 'id') = LId, 'Insight IDs remain stable across snapshots.');
  finally LJson.Free; end;
  LJson := Search('Ausgabepfad', '');
  try
    Check(Value(LJson, 'scope') = 'all', 'Default scope all.');
    Check(LJson.GetValue<TJSONArray>('sources').Count = 3, 'Combined scopes give availability for all sources.');
    Check(Value(LJson, 'matched_count') = '6', 'Actual combined source matches.');
  finally LJson.Free; end;
  Check(TTestItem.ExecuteCount = 0, 'No item execution.');
  Check(TTestItem.UpdateCount = 0, 'No provider refresh.');
  Check(TTestServices.InvokeCount = 0, 'No Insight popup invocation.');
  Check(TTestServices.FilterCount = 0, 'No popup filter mutation.');

  OptionsObject.FailRead := True;
  LJson := Search('output');
  try
    LStatus := TJSONObject(LJson.GetValue<TJSONArray>('sources').Items[0]);
    Check(Value(LStatus, 'available') = 'false', 'Failed names reader is unavailable.');
    Check(LStatus.GetValue('error') <> nil, 'Reader failure retained.');
  finally LJson.Free; end;
  OptionsObject.FailRead := False;
  BorlandIDEServices := nil;
  TDAIOTA.TestProject := nil;
  LJson := Search('output', 'all');
  try
    LSources := LJson.GetValue<TJSONArray>('sources');
    for LIndex := 0 to LSources.Count - 1 do
      Check(Value(TJSONObject(LSources.Items[LIndex]), 'available') = 'false', 'Unavailable services stay unavailable.');
    Check(Value(LJson, 'result_count') = '0', 'No data for absent sources.');
  finally LJson.Free; end;
  BorlandIDEServices := ServicesInterface;
  LProject := TTestProject.Create;
  LProject.Options := OptionsInterface;
  TDAIOTA.TestProject := LProject;
  SetLength(OptionsObject.Names, 10001);
  for LIndex := 0 to High(OptionsObject.Names) do
  begin
    OptionsObject.Names[LIndex].Name := 'ManyOption' + IntToStr(LIndex);
    OptionsObject.Names[LIndex].Kind := tkInteger;
  end;
  LJson := Search('ManyOption', 'project', 1);
  try
    Check(Value(LJson, 'catalog_count') = '10000', 'Catalog bounded to ten thousand.');
    Check(Value(LJson, 'matched_count') = '10000', 'Bounded match count.');
    Check(Value(LJson, 'catalog_limit_reached') = 'true', 'Catalog truncation visible.');
    Check(Value(LJson, 'result_count') = '1', 'Maximum still applies for large catalog.');
  finally LJson.Free; end;
  Check(TDAIOTA.DispatchDepth = 0, 'Main-thread dispatch is released.');
end;

begin
  try
    RunTests;
    Writeln('Options search tests passed: ', CheckCount, ' checks.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
