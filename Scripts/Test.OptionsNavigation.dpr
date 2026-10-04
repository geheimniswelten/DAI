program Test.OptionsNavigation;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.SysUtils, System.JSON, System.TypInfo, System.Variants,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Grids, Vcl.ValEdit, Vcl.ComCtrls,
  ToolsAPI, h5u.DAI.OTA.Helpers, h5u.DAI.Windows.Inspection, h5u.DAI.Options.Navigation;
type
  TConfig = class(TInterfacedObject, IOTABuildConfiguration)
    NameText, PlatformText: string;
    function GetName: string;
    function GetPlatform: string;
    function GetPlatformConfiguration(const AName: string): IOTABuildConfiguration;
  end;
  TOptions = class(TInterfacedObject, IOTAProjectOptions, IOTAEnvironmentOptions, IOTAProjectOptionsConfigurations)
    class var Calls, AreaCalls: Integer;
    function GetOptionNames: TOTAOptionNameArray;
    procedure EditOptions; overload;
    procedure EditOptions(const AArea, APage: string); overload;
    function GetConfigurationCount: Integer;
    function GetConfiguration(const AIndex: Integer): IOTABuildConfiguration;
  end;
  TProject = class(TInterfacedObject, IOTAProject)
    FileText, ConfigText, PlatformText: string;
    Options: IOTAProjectOptions;
    ConfigSets, PlatformSets, FailPlatform: Integer;
    FailConfiguration, IgnoreConfiguration, ConfigChangesPlatform: Boolean;
    function GetFileName: string;
    function GetProjectOptions: IOTAProjectOptions;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetSupportedPlatforms: TArray<string>;
    procedure SetConfiguration(const AValue: string);
    procedure SetPlatform(const AValue: string);
  end;
  TItem = class(TInterfacedObject, INTAIDEInsightItem)
    TitleText: string;
    VisibleValue: Boolean;
    class var Executes: Integer;
    function GetTitle: string;
    function GetDescription: string;
    function GetVisible: Boolean;
    procedure Execute;
  end;
  TCategory = class(TInterfacedObject, IOTAIDEInsightCategory)
    CaptionText: string;
    DisabledValue: Boolean;
    Items: TArray<INTAIDEInsightItem>;
    function GetCaption: string;
    function GetDisabled: Boolean;
    function ItemCount: Integer;
    function GetItem(const AIndex: Integer): INTAIDEInsightItem;
  end;
  TServices = class(TInterfacedObject, IOTAServices, IOTAIDEInsightService, INTAIDEInsightService)
    Environment: IOTAEnvironmentOptions;
    Categories: TArray<IOTAIDEInsightCategory>;
    SearchControl: TWinControl;
    FilterCount: Integer;
    SwitchDuringFilter, StopDuringFilter: Boolean;
    function GetEnvironmentOptions: IOTAEnvironmentOptions;
    function CategoryCount: Integer;
    function GetCategory(const AIndex: Variant): IOTAIDEInsightCategory;
    procedure Filter(const AText: string);
    function GetEditSearchControl: TWinControl;
  end;
  TProjectOptionsDialog = class(TForm)
    CloseTimer, FreeTimer: TTimer;
    Edit: TEdit;
    Grid: TStringGrid;
    Values: TValueListEditor;
    Tree: TTreeView;
    Pages: TPageControl;
    procedure CloseNow(Sender: TObject);
    procedure FreeEdit(Sender: TObject);
    procedure CancelOnEnter(Sender: TObject);
    constructor Create(AOwner: TComponent); override;
  end;
  TBaseEnvironmentDialog = class(TProjectOptionsDialog);
  TGridAccess = class(TCustomGrid) public property Row; property Col; end;
var
  Checks, FixtureMode, MidRow, MidCol: Integer;
  ProjectObject: TProject;
  ServicesObject: TServices;
  RequestId: string;
  MidJson: TJSONObject;
  FixtureScope: string;
procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then raise EInvalidOperation.Create(AMessage);
end;
function Field(const AJson: TJSONObject; const AName: string): string;
var LValue: TJSONValue;
begin
  LValue := AJson.GetValue(AName);
  Check(LValue <> nil, 'Missing ' + AName);
  Result := LValue.Value;
end;
procedure SDKThread;
begin if GetCurrentThreadId <> MainThreadID then raise EInvalidOperation.Create('SDK used outside IDE thread.'); end;
function TConfig.GetName: string; begin SDKThread; Result := NameText; end;
function TConfig.GetPlatform: string; begin SDKThread; Result := PlatformText; end;
function TConfig.GetPlatformConfiguration(const AName: string): IOTABuildConfiguration;
var LConfig: TConfig;
begin
  SDKThread;
  Result := nil;
  if not (SameText(AName, 'Win32') or SameText(AName, 'Win64')) then Exit;
  LConfig := TConfig.Create;
  LConfig.NameText := NameText;
  LConfig.PlatformText := AName;
  Result := LConfig;
end;
function TOptions.GetOptionNames: TOTAOptionNameArray;
begin
  SDKThread;
  SetLength(Result, 2);
  Result[0].Name := 'DCC_UnitSearchPath'; Result[0].Kind := tkUString;
  Result[1].Name := 'EnvironmentOption'; Result[1].Kind := tkUString;
end;
function TOptions.GetConfigurationCount: Integer; begin SDKThread; Result := 2; end;
function TOptions.GetConfiguration(const AIndex: Integer): IOTABuildConfiguration;
var LConfig: TConfig;
begin
  SDKThread; LConfig := TConfig.Create;
  if AIndex = 0 then LConfig.NameText := 'Debug' else LConfig.NameText := 'Release';
  Result := LConfig;
end;
function TProject.GetFileName: string; begin SDKThread; Result := FileText; end;
function TProject.GetProjectOptions: IOTAProjectOptions; begin SDKThread; Result := Options; end;
function TProject.GetConfiguration: string; begin SDKThread; Result := ConfigText; end;
function TProject.GetPlatform: string; begin SDKThread; Result := PlatformText; end;
function TProject.GetSupportedPlatforms: TArray<string>;
begin SDKThread; Result := TArray<string>.Create('Win32', 'Win64'); end;
procedure TProject.SetConfiguration(const AValue: string);
begin
  SDKThread; Inc(ConfigSets);
  if IgnoreConfiguration then Exit;
  ConfigText := AValue;
  if ConfigChangesPlatform then PlatformText := 'Win64';
  if FailConfiguration and (AValue = 'Release') then raise EInvalidOperation.Create('Configuration setter failed.');
end;
procedure TProject.SetPlatform(const AValue: string);
begin
  SDKThread; Inc(PlatformSets);
  if FailPlatform > 0 then begin Dec(FailPlatform); raise EInvalidOperation.Create('Platform setter failed.'); end;
  PlatformText := AValue;
end;
function TItem.GetTitle: string; begin SDKThread; Result := TitleText; end;
function TItem.GetDescription: string; begin SDKThread; Result := ''; end;
function TItem.GetVisible: Boolean; begin SDKThread; Result := VisibleValue; end;
function TCategory.GetCaption: string; begin SDKThread; Result := CaptionText; end;
function TCategory.GetDisabled: Boolean; begin SDKThread; Result := DisabledValue; end;
function TCategory.ItemCount: Integer; begin SDKThread; Result := Length(Items); end;
function TCategory.GetItem(const AIndex: Integer): INTAIDEInsightItem; begin SDKThread; Result := Items[AIndex]; end;
function TServices.GetEnvironmentOptions: IOTAEnvironmentOptions; begin SDKThread; Result := Environment; end;
function TServices.CategoryCount: Integer; begin SDKThread; Result := Length(Categories); end;
function TServices.GetCategory(const AIndex: Variant): IOTAIDEInsightCategory;
begin SDKThread; Result := Categories[Integer(AIndex)]; end;
procedure TServices.Filter(const AText: string);
begin
  SDKThread; Inc(FilterCount);
  if StopDuringFilter then TDAIOptionsNavigationService.Shutdown;
  if SwitchDuringFilter then TDAIOTA.Active := TDAIOTA.OtherProject;
end;
function TServices.GetEditSearchControl: TWinControl; begin SDKThread; Result := SearchControl; end;
constructor TProjectOptionsDialog.Create(AOwner: TComponent);
var LLabel: TLabel; LPanel: TPanel; LTab: TTabSheet; LNode: TTreeNode;
begin
  inherited CreateNew(AOwner);
  Width := 450; Height := 260; Position := poScreenCenter;
  CloseTimer := TTimer.Create(Self); CloseTimer.Enabled := False;
  CloseTimer.Interval := 280; CloseTimer.OnTimer := CloseNow;
  if FixtureMode in [0, 3, 6, 7, 8, 11] then
  begin
    Edit := TEdit.Create(Self); Edit.Parent := Self; Edit.Name := 'PathEdit'; Edit.SetBounds(170, 50, 200, 24);
    Edit.Text := 'secret-value-that-must-never-be-returned';
    LLabel := TLabel.Create(Self); LLabel.Parent := Self; LLabel.Caption := '&Search path:'; LLabel.FocusControl := Edit;
    if FixtureMode = 3 then
    begin
      LPanel := TPanel.Create(Self); LPanel.Parent := Self; LPanel.SetBounds(0, 90, 400, 70);
      LLabel := TLabel.Create(Self); LLabel.Parent := LPanel; LLabel.Caption := 'Search path';
      LLabel.FocusControl := TEdit.Create(Self); LLabel.FocusControl.Parent := LPanel;
    end;
    if FixtureMode = 11 then Edit.OnEnter := CancelOnEnter;
  end;
  if FixtureMode = 1 then
  begin
    Grid := TStringGrid.Create(Self); Grid.Parent := Self; Grid.Align := alClient;
    Grid.ColCount := 2; Grid.FixedCols := 0; Grid.RowCount := 4; Grid.FixedRows := 1;
    Grid.Cells[0, 0] := 'Wert'; Grid.Cells[1, 0] := 'Eigenschaft';
    Grid.Cells[1, 1] := 'Other'; Grid.Cells[1, 2] := 'Suchpfad'; Grid.Cells[1, 3] := 'Unused';
    Grid.Cells[0, 2] := 'secret-grid-value';
  end;
  if FixtureMode = 2 then
  begin
    Values := TValueListEditor.Create(Self); Values.Parent := Self; Values.Align := alClient;
    Values.InsertRow('Other', 'secret-first', True); Values.InsertRow('Search path', 'secret-second', True);
  end;
  if FixtureMode in [4, 10] then begin LPanel := TPanel.Create(Self); LPanel.Parent := Self; LPanel.Name := 'NameValueList'; end;
  if FixtureMode = 5 then TDAIWindowService.ProtectedHandle := Handle;
  if FixtureMode = 6 then
  begin
    Tree := TTreeView.Create(Self); Tree.Parent := Self; Tree.SetBounds(0, 100, 200, 80);
    LNode := Tree.Items.Add(nil, 'Delphi Compiler'); Tree.Items.AddChild(LNode, 'Building');
    FreeTimer := TTimer.Create(Self); FreeTimer.Interval := 20; FreeTimer.OnTimer := FreeEdit;
  end;
  if FixtureMode = 7 then
  begin
    Pages := TPageControl.Create(Self); Pages.Parent := Self; Pages.SetBounds(0, 90, 400, 100);
    LTab := TTabSheet.Create(Self); LTab.PageControl := Pages; LTab.Caption := 'General';
    LTab := TTabSheet.Create(Self); LTab.PageControl := Pages; LTab.Caption := 'Compiler';
  end;
  CloseTimer.Enabled := True;
end;
procedure TProjectOptionsDialog.FreeEdit(Sender: TObject);
begin FreeTimer.Enabled := False; FreeAndNil(Edit); end;
procedure TProjectOptionsDialog.CancelOnEnter(Sender: TObject);
begin TDAIOptionsNavigationService.Shutdown; end;
procedure TProjectOptionsDialog.CloseNow(Sender: TObject);
begin
  CloseTimer.Enabled := False;
  FreeAndNil(MidJson);
  MidJson := TDAIOptionsNavigationService.Status(RequestId);
  if Grid <> nil then begin MidRow := Grid.Row; MidCol := Grid.Col; end;
  if Values <> nil then begin MidRow := TGridAccess(Values).Row; MidCol := TGridAccess(Values).Col; end;
  ModalResult := mrCancel;
end;
procedure ShowFixture;
var LForm: TForm;
begin
  if FixtureMode = 9 then LForm := TForm.CreateNew(nil)
  else if FixtureScope = 'ide' then LForm := TBaseEnvironmentDialog.Create(nil)
  else LForm := TProjectOptionsDialog.Create(nil);
  try
    if FixtureMode <> 9 then LForm.ShowModal;
  finally LForm.Free; TDAIWindowService.ProtectedHandle := 0; end;
end;
procedure TOptions.EditOptions; begin SDKThread; Inc(Calls); ShowFixture; end;
procedure TOptions.EditOptions(const AArea, APage: string);
begin SDKThread; Inc(AreaCalls); ShowFixture; end;
procedure TItem.Execute; begin SDKThread; Inc(Executes); ShowFixture; end;
function Request: TDAIOptionsNavigationRequest;
begin Result := Default(TDAIOptionsNavigationRequest); Result.Option := 'DCC_UnitSearchPath'; end;
function Run(const ARequest: TDAIOptionsNavigationRequest; const AMode: Integer): TJSONObject;
var LQueued: TJSONObject; LCalls: Integer;
begin
  FixtureMode := AMode; FixtureScope := ARequest.Scope;
  FreeAndNil(MidJson); MidRow := -1; MidCol := -1;
  LCalls := TOptions.Calls + TItem.Executes + TOptions.AreaCalls;
  LQueued := TDAIOptionsNavigationService.Open(ARequest);
  try
    Check(Field(LQueued, 'status') = 'queued', 'Must queue modal call.');
    Check(TOptions.Calls + TItem.Executes + TOptions.AreaCalls = LCalls, 'Open must not run SDK synchronously.');
    RequestId := Field(LQueued, 'request_id');
  finally LQueued.Free; end;
  CheckSynchronize;
  Result := TDAIOptionsNavigationService.Status(RequestId);
  Check(Pos('secret-', Result.ToJSON) = 0, 'Must not return input values.');
end;
procedure ExpectRejected(const ARequest: TDAIOptionsNavigationRequest);
var LJson: TJSONObject; LRejected: Boolean;
begin
  LRejected := False;
  try LJson := TDAIOptionsNavigationService.Open(ARequest); LJson.Free;
  except on E: Exception do LRejected := True; end;
  Check(LRejected, 'Request must be rejected.');
end;
procedure SetCategory(const ACaption: string; const ACount: Integer; const AVisible, ADisabled: Boolean);
var LCategory: TCategory; LItem: TItem; I: Integer;
begin
  LCategory := TCategory.Create; LCategory.CaptionText := ACaption; LCategory.DisabledValue := ADisabled;
  SetLength(LCategory.Items, ACount);
  for I := 0 to ACount - 1 do
  begin LItem := TItem.Create; LItem.TitleText := 'Search path'; LItem.VisibleValue := AVisible; LCategory.Items[I] := LItem; end;
  ServicesObject.Categories := TArray<IOTAIDEInsightCategory>.Create(LCategory);
end;
procedure TestAll;
var LRequest: TDAIOptionsNavigationRequest; LJson, LQueued: TJSONObject; LOldCount: Integer; LSearchForm: TForm; LSearch: TEdit;
begin
  LRequest := Request;
  LRequest.Scope := 'wrong'; ExpectRejected(LRequest);
  LRequest := Request; LRequest.Project := 'Other'; ExpectRejected(LRequest);
  LRequest := Request; LRequest.Query := 'x' + #0; ExpectRejected(LRequest);
  LRequest := Request; LRequest.Control := StringOfChar('x', 257); ExpectRejected(LRequest);
  LRequest := Request; LRequest.Configuration := 'Base'; ExpectRejected(LRequest);
  LRequest := Request; LRequest.Configuration := 'active'; ExpectRejected(LRequest);
  LRequest := Request; LRequest.Configuration := 'Missing'; ExpectRejected(LRequest);
  LRequest := Request; LRequest.Platform := 'Android'; ExpectRejected(LRequest);
  LRequest := Request; LRequest.Scope := 'ide'; LRequest.Project := 'Selected'; ExpectRejected(LRequest);
  LRequest := Default(TDAIOptionsNavigationRequest); LRequest.Scope := 'insight'; LRequest.Query := 'search';
  LRequest.Page := 'Compiler'; ExpectRejected(LRequest);
  Check(ProjectObject.ConfigSets + ProjectObject.PlatformSets = 0, 'Invalid selection must not mutate SDK.');
  LRequest := Request; LQueued := TDAIOptionsNavigationService.Open(LRequest);
  RequestId := Field(LQueued, 'request_id'); LQueued.Free; ExpectRejected(LRequest);
  TDAIOTA.Active := TDAIOTA.OtherProject; CheckSynchronize;
  LJson := TDAIOptionsNavigationService.Status(RequestId);
  Check(Field(LJson, 'status') = 'error', 'Queued project switch must fail.'); LJson.Free;
  Check(TOptions.Calls = 0, 'Stale project must not open UI.'); TDAIOTA.Active := TDAIOTA.TestProject;
  LQueued := TDAIOptionsNavigationService.Open(Request); RequestId := Field(LQueued, 'request_id'); LQueued.Free;
  ProjectObject.PlatformText := 'Win64'; CheckSynchronize;
  LJson := TDAIOptionsNavigationService.Status(RequestId);
  Check(Field(LJson, 'status') = 'error', 'Queued platform switch must fail.'); LJson.Free;
  Check(TOptions.Calls = 0, 'Stale platform must not open UI.'); ProjectObject.PlatformText := 'Win32';
  LRequest := Request; LRequest.Option := 'missing';
  LJson := Run(LRequest, 4); Check(Field(LJson, 'status') = 'unsupported', 'Unknown explicit option unsupported.'); LJson.Free;
  LJson := Run(Request, 0);
  Check(Field(LJson, 'status') = 'closed', 'Modal closure lifecycle.');
  Check(Field(MidJson, 'status') = 'focused', 'Label focus lifecycle.');
  Check(Field(LJson, 'dialog_opened') = 'true', 'Actual modal identified.');
  Check(Field(LJson, 'option_focused') = 'true', 'Label matched edit.');
  Check(Field(LJson, 'focus_verified') = 'true', 'Focused control verified.'); LJson.Free;
  LJson := Run(Request, 1); Check(MidRow = 2, 'StringGrid name row.'); Check(MidCol = 0, 'StringGrid actual value column.');
  Check(Field(LJson, 'option_focused') = 'true', 'StringGrid focused.'); LJson.Free;
  LJson := Run(Request, 2); Check(MidRow = 2, 'ValueList row.'); Check(MidCol = 1, 'ValueList value column.'); LJson.Free;
  LJson := Run(Request, 3); Check(Field(LJson, 'option_focused') = 'false', 'Ambiguous focus rejected.'); LJson.Free;
  LJson := Run(Request, 4); Check(Field(LJson, 'option_focused') = 'false', 'Unknown NameValueList not cast.'); LJson.Free;
  LJson := Run(Request, 5); Check(Field(LJson, 'dialog_opened') = 'false', 'Permission form excluded.'); LJson.Free;
  LRequest := Request; LRequest.Page := 'Delphi Compiler/Building';
  LJson := Run(LRequest, 6); Check(Field(LJson, 'page_selected') = 'true', 'Tree path selected.');
  Check(Field(LJson, 'option_focused') = 'false', 'Freed edit handled.'); LJson.Free;
  LRequest := Request; LRequest.Page := 'Compiler';
  LJson := Run(LRequest, 7); Check(Field(LJson, 'page_selected') = 'true', 'Actual tab selected.'); LJson.Free;
  LRequest := Request; LRequest.Option := ''; LRequest.Control := 'PathEdit';
  LJson := Run(LRequest, 8); Check(Field(LJson, 'option_focused') = 'true', 'Exact ControlName focus.'); LJson.Free;
  LJson := Run(Request, 9); Check(Field(LJson, 'status') = 'unsupported', 'Unknown modal class unsupported.'); LJson.Free;
  LRequest := Request; LRequest.Configuration := 'Release'; ProjectObject.ConfigChangesPlatform := True;
  LJson := Run(LRequest, 0); Check(ProjectObject.ConfigText = 'Release', 'Requested real SDK config changed.');
  Check(ProjectObject.PlatformText = 'Win32', 'Omitted platform preserved.');
  Check(Field(LJson, 'configuration') = 'Release', 'Actual config reported.'); LJson.Free;
  ProjectObject.ConfigText := 'Debug'; ProjectObject.PlatformText := 'Win32'; ProjectObject.FailPlatform := 1;
  ProjectObject.ConfigChangesPlatform := False;
  LRequest := Request; LRequest.Configuration := 'Release'; LRequest.Platform := 'Win64';
  LJson := Run(LRequest, 0); Check(Field(LJson, 'status') = 'error', 'Setter failure surfaced.');
  Check(ProjectObject.ConfigText = 'Debug', 'Config rolled back.'); Check(ProjectObject.PlatformText = 'Win32', 'Platform rolled back.'); LJson.Free;
  ProjectObject.FailConfiguration := True;
  LJson := Run(LRequest, 0); Check(Field(LJson, 'status') = 'error', 'Config setter exception surfaced.');
  Check(ProjectObject.ConfigText = 'Debug', 'Partially changed config rolled back.'); LJson.Free; ProjectObject.FailConfiguration := False;
  ProjectObject.IgnoreConfiguration := True;
  LJson := Run(LRequest, 0); Check(Field(LJson, 'status') = 'error', 'Ignored setter surfaced.'); LJson.Free;
  ProjectObject.IgnoreConfiguration := False; ProjectObject.ConfigChangesPlatform := False;
  ProjectObject.ConfigChangesPlatform := True; ProjectObject.FailPlatform := 2;
  LRequest := Request; LRequest.Configuration := 'Release'; LRequest.Platform := 'Win32';
  LJson := Run(LRequest, 0); Check(Field(LJson, 'status') = 'error', 'Rollback setter failure surfaced.');
  Check(not (LJson.GetValue('rollback_error') is TJSONNull), 'Rollback error is reported.');
  Check(Field(LJson, 'platform') = 'Win64', 'Actual state after failed rollback reported.'); LJson.Free;
  ProjectObject.PlatformText := 'Win32'; ProjectObject.ConfigChangesPlatform := False;
  SetCategory('Commands', 1, True, False); LOldCount := TItem.Executes;
  LJson := Run(Request, 0); Check(TItem.Executes = LOldCount, 'Command category never executed.'); LJson.Free;
  SetCategory('Project Options', 2, True, False);
  LJson := Run(Request, 0); Check(TItem.Executes = LOldCount, 'Ambiguous native option not executed.'); LJson.Free;
  SetCategory('Project Options', 1, False, False);
  LJson := Run(Request, 0); Check(TItem.Executes = LOldCount, 'Hidden native option not executed.'); LJson.Free;
  SetCategory('Project Options', 1, True, True);
  LJson := Run(Request, 0); Check(TItem.Executes = LOldCount, 'Disabled native category not executed.'); LJson.Free;
  SetCategory('Projektoptionen', 1, True, False);
  LJson := Run(Request, 10); Check(TItem.Executes = LOldCount + 1, 'Unique native option executed.');
  Check(Field(LJson, 'focus_owned_by_ide') = 'true', 'Native private focus belongs to SDK.');
  Check(LJson.GetValue('focus_verified') is TJSONNull, 'Private native focus remains unknown.'); LJson.Free;
  LRequest := Request; LRequest.Option := 'Search path'; LOldCount := TItem.Executes;
  LJson := Run(LRequest, 10); Check(TItem.Executes = LOldCount + 1, 'Actual Insight title opened without invented SDK key.');
  Check(Field(LJson, 'focus_owned_by_ide') = 'true', 'Native title focus belongs to SDK.'); LJson.Free;
  LRequest := Request; LRequest.Option := ''; LRequest.Query := 'Search path'; LOldCount := TItem.Executes;
  LJson := Run(LRequest, 0); Check(TItem.Executes = LOldCount, 'Query-only does not execute items.'); LJson.Free;
  ServicesObject.SwitchDuringFilter := True;
  LJson := Run(Request, 0); Check(Field(LJson, 'status') = 'error', 'Project rechecked after filter.');
  Check(TItem.Executes = LOldCount, 'Filter project switch never executes.'); LJson.Free;
  ServicesObject.SwitchDuringFilter := False; TDAIOTA.Active := TDAIOTA.TestProject;
  ServicesObject.Categories := nil;
  LRequest := Default(TDAIOptionsNavigationRequest); LRequest.Scope := 'ide'; LRequest.Page := 'Compiler';
  LOldCount := TOptions.AreaCalls; LJson := Run(LRequest, 7);
  Check(TOptions.AreaCalls = LOldCount, 'Page-only uses generic SDK dialog.');
  Check(Field(LJson, 'page_selected') = 'true', 'IDE page selected by actual tab.'); LJson.Free;
  LRequest.Area := 'ThirdParty'; LJson := Run(LRequest, 7);
  Check(TOptions.AreaCalls = LOldCount + 1, 'Explicit Area uses SDK overload.'); LJson.Free;
  LSearchForm := TForm.CreateNew(nil);
  LOldCount := TItem.Executes;
  try
    LSearch := TEdit.Create(LSearchForm); LSearch.Parent := LSearchForm; LSearchForm.Show;
    ServicesObject.SearchControl := LSearch;
    LRequest := Default(TDAIOptionsNavigationRequest); LRequest.Scope := 'insight'; LRequest.Query := 'search';
    LJson := Run(LRequest, 0); Check(Field(LJson, 'status') = 'focused', 'Insight query search control focused.');
    Check(TItem.Executes = LOldCount, 'Insight query must not execute.'); LJson.Free;
    ServicesObject.SearchControl := nil;
    LJson := Run(LRequest, 0); Check(Field(LJson, 'status') = 'error', 'Missing Insight focus control handled.'); LJson.Free;
  finally LSearchForm.Free; end;
  LJson := Run(Request, 11); Check(Field(LJson, 'status') = 'cancelled', 'Reentrant shutdown retains cancellation.'); LJson.Free;
  ExpectRejected(Request); TDAIOptionsNavigationService.Shutdown; ExpectRejected(Request);
end;
procedure TestShutdownOnly;
var LQueued, LJson: TJSONObject; LRequest: TDAIOptionsNavigationRequest;
begin
  if ParamStr(1) = '--empty-shutdown' then
  begin
    TDAIOptionsNavigationService.Shutdown;
    ExpectRejected(Request);
  end
  else if ParamStr(1) = '--queued-shutdown' then
  begin
    LQueued := TDAIOptionsNavigationService.Open(Request);
    RequestId := Field(LQueued, 'request_id'); LQueued.Free;
    TDAIOptionsNavigationService.Shutdown;
    CheckSynchronize;
    LJson := TDAIOptionsNavigationService.Status(RequestId);
    Check(Field(LJson, 'status') = 'cancelled', 'Shutdown cancels published queue.'); LJson.Free;
    Check(TOptions.Calls + TItem.Executes = 0, 'Cancelled queue never calls SDK.');
    ExpectRejected(Request);
  end
  else if ParamStr(1) = '--insight-shutdown' then
  begin
    ServicesObject.StopDuringFilter := True;
    LRequest := Default(TDAIOptionsNavigationRequest); LRequest.Scope := 'insight'; LRequest.Query := 'search';
    LJson := Run(LRequest, 0); Check(Field(LJson, 'status') = 'cancelled', 'Insight filter shutdown preserved.'); LJson.Free;
    Check(TItem.Executes = 0, 'Cancelled Insight does not execute.'); ExpectRejected(Request);
  end;
  TDAIOptionsNavigationService.Shutdown;
  ExpectRejected(Request);
end;
var LOptions: TOptions; LOther: TProject;
begin
  try
    Application.Initialize;
    LOptions := TOptions.Create;
    ProjectObject := TProject.Create; ProjectObject.FileText := 'C:\OptionsFixture\Selected.dproj';
    ProjectObject.ConfigText := 'Debug'; ProjectObject.PlatformText := 'Win32'; ProjectObject.Options := LOptions;
    TDAIOTA.TestProject := ProjectObject; TDAIOTA.Active := TDAIOTA.TestProject;
    LOther := TProject.Create; LOther.FileText := 'C:\OptionsFixture\Other.dproj'; LOther.Options := LOptions;
    TDAIOTA.OtherProject := LOther;
    ServicesObject := TServices.Create; ServicesObject.Environment := LOptions; BorlandIDEServices := ServicesObject;
    if ParamCount = 0 then TestAll else TestShutdownOnly;
    Writeln('PASS: ', Checks, ' checks (production navigation, SDK doubles, isolated VCL forms).');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
  MidJson.Free;
  TDAIOTA.Active := nil; TDAIOTA.TestProject := nil; TDAIOTA.OtherProject := nil; BorlandIDEServices := nil;
end.
