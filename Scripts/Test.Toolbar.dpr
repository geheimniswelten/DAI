program Test.Toolbar;

{$APPTYPE CONSOLE}

uses
  System.Actions,
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  Winapi.Windows,
  Winapi.CommCtrl,
  ToolsAPI,
  Vcl.ActnList,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.ImgList,
  Vcl.ImageCollection,
  Vcl.Imaging.pngimage,
  Vcl.VirtualImageList,
  Vcl.Menus,
  Vcl.ExtCtrls,
  h5u.DAI.IDE.Toolbar,
  h5u.DAI.Log,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Settings;

type
  TForeignToolButton = class(TToolButton)
  public
    ClickCount: Integer;
    procedure Click; override;
  end;

  TTestHost = class(TInterfacedObject, INTAServices, IOTAServices, IOTAEnvironmentOptions)
  private
    FImageIds: TStringList;
    FNotifiers: TDictionary<Integer, IOTANotifier>;
    FNextNotifier: Integer;
  public
    Form: TForm;
    Toolbar: TToolBar;
    ActionList: TActionList;
    Images: TVirtualImageList;
    ImageCollection: TImageCollection;
    Glyphs: TObjectList<TPngImage>;
    ImageCalls: Integer;
    RejectImages: Boolean;
    ForeignAction: TAction;
    ForeignButton: TToolButton;
    LookupCount: Integer;
    AddCount: Integer;
    OptionsCount: Integer;
    LastLookup: string;
    LastAddBar: string;
    LastArea: string;
    LastPage: string;
    ReturnNilButton: Boolean;
    ReturnUnsupportedButton: Boolean;
    RegisterCount: Integer;
    UnregisterCount: Integer;
    RejectNotifier: Boolean;
    StopDuringRegister: Boolean;
    RaiseUnregister: Boolean;
    LastReadButton: TToolButton;
    LastReadToolbar: TToolBar;
    ReadCount: Integer;
    ReadNameCount: Integer;
    MissingDependenciesDuringName: Boolean;
    OfficialToolbarAbsentDuringName: Boolean;
    constructor Create;
    destructor Destroy; override;
    function GetActionList: TCustomActionList;
    function GetImageList: TCustomImageList;
    function GetToolBar(const ToolBarName: string): TToolBar;
    function AddMasked(Image: TBitmap; MaskColor: TColor; const Ident: string): Integer;
    function AddImage(const AImageName: string; const AImage: TGraphicArray): Integer;
    function AddToolButton(const ToolBarName, ButtonName: string; AAction: TCustomAction;
      const IsDivider: Boolean = False; const ReferenceButton: string = ''; InsertBefore: Boolean = False): TControl;
    function RegisterToolbarNotifier(const ANotifier: IOTANotifier): Integer;
    procedure UnregisterToolbarNotifier(AIndex: Integer);
    function ActiveNotifier: IOTANotifier;
    procedure ReaderSetName(Reader: TReader; Component: TComponent; var Name: string);
    procedure ReaderComponent(Component: TComponent);
    function GetEnvironmentOptions: IOTAEnvironmentOptions;
    procedure EditOptions(const Area: string; const PageCaption: string = '');
    procedure DummyClick(Sender: TObject);
    function DAIAction: TAction;
    function DAIButton: TToolButton;
  end;

var
  GChecks: Integer;
  GHost: TTestHost;
  GHostKeepAlive: IInterface;

type
  TPreparePackageHost = procedure(const AHost: IInterface); stdcall;
  TPackageToolbarOperation = procedure; stdcall;

function DAIGetModuleHandleExW(const AFlags: DWORD; const AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExW';

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create(ADescription);
end;

procedure TForeignToolButton.Click;
begin
  Inc(ClickCount);
end;

constructor TTestHost.Create;
begin
  inherited;
  FImageIds := TStringList.Create;
  FNotifiers := TDictionary<Integer, IOTANotifier>.Create;
  Form := TForm.CreateNew(nil);
  Form.Name := 'TestIDE';
  ImageCollection := TImageCollection.Create(Form);
  Images := TVirtualImageList.Create(Form);
  Images.ImageCollection := ImageCollection;
  Glyphs := TObjectList<TPngImage>.Create(True);
  Images.Width := 16;
  Images.Height := 16;
  ActionList := TActionList.Create(Form);
  ActionList.Name := 'MainActionList';
  ActionList.Images := Images;
  Toolbar := TToolBar.Create(Form);
  Toolbar.Name := sDebugToolBar;
  Toolbar.Parent := Form;
  Toolbar.Images := Images;
  ForeignAction := TAction.Create(Form);
  ForeignAction.Name := 'ForeignDebuggerAction';
  ForeignAction.ActionList := ActionList;
  ForeignAction.Caption := 'Foreign debugger action';
  ForeignButton := TToolButton.Create(Form);
  ForeignButton.Name := 'ForeignDebuggerButton';
  ForeignButton.Parent := Toolbar;
  ForeignButton.Action := ForeignAction;
end;

destructor TTestHost.Destroy;
begin
  Form.Free;
  Glyphs.Free;
  FImageIds.Free;
  FNotifiers.Free;
  inherited;
end;

function TTestHost.GetActionList: TCustomActionList;
begin
  Result := ActionList;
end;

function TTestHost.GetImageList: TCustomImageList;
begin
  Result := Images;
end;

function TTestHost.GetToolBar(const ToolBarName: string): TToolBar;
begin
  Inc(LookupCount);
  LastLookup := ToolBarName;
  if ToolBarName = sDebugToolBar then
    Result := Toolbar
  else
    Result := nil;
end;

function TTestHost.AddMasked(Image: TBitmap; MaskColor: TColor; const Ident: string): Integer;
begin
  raise EInvalidOperation.Create('Production must use the modern multi-resolution AddImage API.');
end;

function TTestHost.AddImage(const AImageName: string; const AImage: TGraphicArray): Integer;
var
  LIndex: Integer;
  LItem: TImageCollectionItem;
  LGraphic: TGraphic;
  LPng: TPngImage;
  LStream: TMemoryStream;
begin
  Inc(ImageCalls);
  if RejectImages then
    Exit(-1);
  LIndex := FImageIds.IndexOfName(AImageName);
  if LIndex >= 0 then
    Exit(StrToInt(FImageIds.ValueFromIndex[LIndex]));
  LItem := ImageCollection.Images.Add;
  LItem.Name := AImageName;
  for LGraphic in AImage do
  begin
    Check(LGraphic is TPngImage, 'The IDE receives alpha-capable PNG glyphs');
    LPng := TPngImage.Create;
    LPng.Assign(LGraphic);
    Glyphs.Add(LPng);
    LStream := TMemoryStream.Create;
    try
      LGraphic.SaveToStream(LStream);
      LStream.Position := 0;
      LItem.SourceImages.Add.Image.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
  end;
  LItem.Change;
  Images.Images.Add.CollectionIndex := LItem.Index;
  Result := Images.GetIndexByName(AImageName);
  FImageIds.Values[AImageName] := IntToStr(Result);
end;

function TTestHost.AddToolButton(const ToolBarName, ButtonName: string; AAction: TCustomAction;
  const IsDivider: Boolean; const ReferenceButton: string; InsertBefore: Boolean): TControl;
var
  LButton: TToolButton;
  LPanel: TPanel;
begin
  Inc(AddCount);
  LastAddBar := ToolBarName;
  Check(ToolBarName = sDebugToolBar, 'Factory uses the official existing Debug toolbar');
  Check(Assigned(AAction), 'Toolbar factory gets a registered action');
  Check(not IsDivider, 'No unrelated toolbar separator is created');
  Check(ReferenceButton = '', 'No guessed native debugger button name is used');
  if ReturnNilButton then
    Exit(nil);
  if ReturnUnsupportedButton then
  begin
    LPanel := TPanel.Create(Form);
    LPanel.Name := ButtonName;
    LPanel.Parent := Toolbar;
    Exit(LPanel);
  end;
  LButton := TToolButton.Create(Form);
  LButton.Name := ButtonName;
  LButton.Left := Toolbar.ButtonCount * 64;
  LButton.Parent := Toolbar;
  LButton.Action := AAction;
  Result := LButton;
end;

function TTestHost.GetEnvironmentOptions: IOTAEnvironmentOptions;
begin
  Result := Self;
end;

function TTestHost.RegisterToolbarNotifier(const ANotifier: IOTANotifier): Integer;
begin
  Inc(RegisterCount);
  if RejectNotifier then
    Exit(-1);
  Inc(FNextNotifier);
  Result := FNextNotifier;
  FNotifiers.Add(Result, ANotifier);
  if StopDuringRegister then
    TDAIIDEToolbar.Shutdown;
end;

procedure TTestHost.UnregisterToolbarNotifier(AIndex: Integer);
begin
  Inc(UnregisterCount);
  Check(FNotifiers.ContainsKey(AIndex), 'Only the exact accepted notifier index is unregistered once');
  if RaiseUnregister then
    raise EInvalidOperation.Create('Synthetic unregister failure with retained SDK receiver');
  FNotifiers.Remove(AIndex);
end;

function TTestHost.ActiveNotifier: IOTANotifier;
var
  LPair: TPair<Integer, IOTANotifier>;
begin
  Result := nil;
  for LPair in FNotifiers do
    Exit(LPair.Value);
end;

procedure TTestHost.ReaderSetName(Reader: TReader; Component: TComponent; var Name: string);
var
  LReadNotifier: INTAReadToolbarNotifier;
  LHandled: Boolean;
  LOriginalName: string;
begin
  LOriginalName := Name;
  LHandled := False;
  if Supports(ActiveNotifier, INTAReadToolbarNotifier, LReadNotifier) then
    LReadNotifier.SetName(Reader, Component, Name, LHandled);
  if (LOriginalName = 'DAIServerToolButton') and (Component is TToolButton) then
  begin
    Inc(ReadNameCount);
    LastReadButton := TToolButton(Component);
    Check(Reader.Root = Form, 'Real ReadComponents supplies AppBuilder/IDE form as Reader.Root');
    Check(Component.Owner = Form, 'Streamed DAI button has the IDE form as owner');
    Check(Component.GetParentComponent is TToolBar, 'Parent is assigned before the SetName reader hook');
    MissingDependenciesDuringName := (LastReadButton.Action = nil) and (LastReadButton.DropdownMenu = nil);
    OfficialToolbarAbsentDuringName := Toolbar = nil;
    Check(Name = LOriginalName, 'DAI leaves the incoming stream name unchanged');
    Check(not LHandled, 'DAI leaves the IDE normalization decision unchanged');
  end;
  // Reproduce the verified bds.exe bridge: normalization follows the notifier.
  if (Component.ClassType = TToolButton) and not LHandled then
    Name := '';
end;

procedure TTestHost.ReaderComponent(Component: TComponent);
begin
  Inc(ReadCount);
  if Component is TToolBar then
    LastReadToolbar := TToolBar(Component);
end;

procedure TTestHost.EditOptions(const Area: string; const PageCaption: string);
begin
  Inc(OptionsCount);
  LastArea := Area;
  LastPage := PageCaption;
end;

procedure TTestHost.DummyClick(Sender: TObject);
begin
  raise EInvalidOperation.Create('A preserved foreign callback must never execute during toolbar cleanup.');
end;

function TTestHost.DAIAction: TAction;
var
  LIndex: Integer;
begin
  Result := nil;
  if not Assigned(ActionList) then
    Exit;
  for LIndex := 0 to ActionList.ActionCount - 1 do
    if ActionList.Actions[LIndex].Name = 'DAIServerToggleAction' then
      Exit(TAction(ActionList.Actions[LIndex]));
end;

function TTestHost.DAIButton: TToolButton;
var
  LIndex: Integer;
begin
  Result := nil;
  if not Assigned(Toolbar) then
    Exit;
  for LIndex := 0 to Toolbar.ButtonCount - 1 do
    if Toolbar.Buttons[LIndex].Name = 'DAIServerToolButton' then
      Exit(Toolbar.Buttons[LIndex]);
end;

procedure NewHost;
begin
  TDAIIDEToolbar.Shutdown;
  BorlandIDEServices := nil;
  GHostKeepAlive := nil;
  GHost := TTestHost.Create;
  GHostKeepAlive := GHost;
  BorlandIDEServices := GHostKeepAlive;
  TDAIRuntime.Reset;
  TDAISettings.Instance.Port := 7331;
  TDAILog.Messages.Clear;
  TDAIPermissionManager.ClearCount := 0;
end;

procedure PumpFor(AMilliseconds: Cardinal);
var
  LUntil: UInt64;
begin
  LUntil := GetTickCount64 + AMilliseconds;
  repeat
    Application.ProcessMessages;
    CheckSynchronize;
    Sleep(5);
  until GetTickCount64 >= LUntil;
end;

procedure TestReadinessAndStatus;
var
  LToolbar: TToolBar;
  LAction: TAction;
  LInactiveImage: Integer;
  LActiveImage: Integer;
  LImages: Integer;
  LLookups: Integer;
begin
  NewHost;
  BorlandIDEServices := nil;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(GHost.AddCount = 0, 'No UI factory call before IDE services are ready');
  BorlandIDEServices := GHostKeepAlive;
  LToolbar := GHost.Toolbar;
  GHost.Toolbar := nil;
  TDAIIDEToolbar.Refresh;
  Check(GHost.AddCount = 0, 'An absent Debug toolbar never creates another toolbar');
  Check(GHost.LastLookup = sDebugToolBar, 'Readiness probes only the official Debug toolbar');
  GHost.Toolbar := LToolbar;
  PumpFor(650);
  Check(Assigned(GHost.DAIAction()), 'Delayed main-thread timer installs when IDE UI becomes ready');
  Check(GHost.AddCount = 1, 'Install is idempotent');
  Check(GHost.Toolbar.ButtonCount = 2, 'One DAI button joins the existing native toolbar');
  Check(not GHost.Toolbar.ShowCaptions, 'DAI does not change global toolbar caption preferences');
  LAction := GHost.DAIAction;
  Check(LAction.Caption = 'DAI inaktiv', 'Initial inactive status is visible in the action');
  Check(Pos('kein aktiver Port', LAction.Hint) > 0, 'Inactive status does not claim a live endpoint');
  Check(Pos('7331', LAction.Hint) > 0, 'Inactive hint identifies the saved start port');
  LInactiveImage := LAction.ImageIndex;
  Check(GHost.Images.Count = 3, 'Three independent state glyphs are registered');
  Check(GHost.DAIButton.DropdownMenu.Owner = GHost.DAIButton.Owner, 'Dropdown follows official ownership contract');
  Check(GHost.DAIButton.ShowHint, 'Toolbar button exposes its status tooltip');
  Check(GHost.DAIButton.Style = tbsDropDown, 'Options are reachable from a native dropdown');
  LAction.Execute;
  Check(TDAIRuntime.StartCount = 1, 'Toolbar action starts through Runtime.StartServer');
  Check(TDAIRuntime.Active, 'Server start changes active state');
  Check(LAction.Caption = 'DAI aktiv', 'Successful start refreshes active status immediately');
  LActiveImage := LAction.ImageIndex;
  Check(LActiveImage <> LInactiveImage, 'Active and inactive states use different glyphs');
  TDAIRuntime.Port := 7444;
  TDAISettings.Instance.Port := 7333;
  TDAIIDEToolbar.Refresh;
  Check(Pos('7444', LAction.Hint) > 0, 'Active hint uses the actual temporary live port');
  Check(Pos('7333', LAction.Hint) = 0, 'Active hint does not substitute the saved port');
  GHost.DAIButton.DropdownMenu.Items[0].Click;
  Check(TDAIRuntime.StopCount = 1, 'Dropdown command also stops through Runtime.StopServer');
  Check(not TDAIRuntime.Active, 'Stop command changes inactive state');
  Check(LAction.ImageIndex = LInactiveImage, 'Stop restores the inactive glyph');
  GHost.DAIButton.DropdownMenu.Items[1].Click;
  Check(GHost.OptionsCount = 1, 'Options shortcut uses the official environment-options service');
  Check(GHost.LastArea = '', 'Options uses the existing page area');
  Check(GHost.LastPage = 'DAI', 'Options opens the existing DAI permissions page');
  Check(TDAIPermissionManager.ClearCount = 0, 'Opening options does not grant or reset permissions');
  GHost.DAIButton.DropdownMenu.Items[2].Click;
  Check(TDAIPermissionManager.ClearCount = 1, 'Only explicit reset command clears session decisions');
  LImages := GHost.Images.Count;
  LLookups := GHost.LookupCount;
  TDAIIDEToolbar.Shutdown;
  TDAIIDEToolbar.Shutdown;
  Check(GHost.Toolbar.ButtonCount = 1, 'Shutdown removes only its own native button');
  Check(GHost.ActionList.ActionCount = 1, 'Shutdown removes only its own action');
  Check(GHost.ForeignButton.Action = GHost.ForeignAction, 'Foreign toolbar action remains intact');
  Check(GHost.Form.FindComponent('DAIServerPopupMenu') = nil, 'Shutdown frees its IDE-owned dropdown');
  Check(GHost.Images.Count = LImages, 'Shared image indices remain stable on shutdown');
  PumpFor(650);
  Check(GHost.LookupCount = LLookups, 'Stopped timer makes no later OTA calls');
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(GHost.Images.Count = LImages, 'Reload deduplicates official image identifiers');
end;

procedure TestFailures;
var
  LAction: TAction;
  LErrorImage: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LAction := GHost.DAIAction;
  TDAIRuntime.FailStart := True;
  LAction.Execute;
  Check(LAction.Caption = 'DAI Fehler', 'Bind failure becomes an error status');
  Check(Pos('isolated bind failed', LAction.Hint) > 0, 'Bind failure is available in the tooltip');
  Check(not TDAIRuntime.Active, 'Failed start does not claim activation');
  LErrorImage := LAction.ImageIndex;
  TDAIRuntime.FailStart := False;
  LAction.Execute;
  Check(LAction.Caption = 'DAI aktiv', 'Successful retry clears the failure state');
  Check(LAction.ImageIndex <> LErrorImage, 'Successful retry restores the active glyph');
  TDAIRuntime.FailStop := True;
  LAction.Execute;
  Check(TDAIRuntime.Active, 'Failed drain does not falsely report a stopped server');
  Check(LAction.Caption = 'DAI Fehler', 'Failed stop becomes an error status');
  Check(Pos('aktiv auf Port 7331', LAction.Hint) > 0, 'Failed stop retains the actual live endpoint');
  Check(Pos('isolated drain failed', LAction.Hint) > 0, 'Failed stop exposes its reason');
  TDAIRuntime.FailStop := False;
  TDAIRuntime.RaiseStop := True;
  LAction.Execute;
  Check(LAction.Enabled, 'Unexpected runtime exceptions restore action availability');
  Check(Pos('isolated stop exception', LAction.Hint) > 0, 'Unexpected runtime exceptions become tooltip errors');
  TDAIRuntime.RaiseStop := False;
  LAction.Execute;
  Check(LAction.Caption = 'DAI inaktiv', 'Successful stop clears a caught exception');
  TDAIRuntime.RaiseStart := True;
  LAction.Execute;
  Check(Pos('isolated start exception', LAction.Hint) > 0, 'Unexpected start exceptions are also contained');
  TDAIRuntime.RaiseStart := False;
  LAction.Execute;
  Check(TDAIRuntime.Active, 'The action remains usable after a start exception');
end;

procedure TestGlyphs;
const
  CSizes: array[0..4] of Integer = (16, 20, 24, 32, 48);
var
  LBitmap: TBitmap;
  LPreview: TPngImage;
  LPng: TPngImage;
  LIndex: Integer;
  LX: Integer;
  LY: Integer;
  LOpaque: Integer;
  LPartial: Integer;
  LTransparent: Integer;
  LShapes: array[0..2] of TBytes;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(GHost.Glyphs.Count = 15, 'Three glyphs each have five independently rendered resolutions');
  Check(GHost.Images is TVirtualImageList, 'Regression uses the real modern VCL virtual image list');
  Check(GHost.ImageCollection.Images.Count = 3, 'All state glyphs enter the real VCL image collection');
  for LIndex := 0 to GHost.Glyphs.Count - 1 do
  begin
    LPng := GHost.Glyphs[LIndex];
    Check(LPng.Width = CSizes[LIndex mod 5], 'Resolution width is exact');
    Check(LPng.Height = LPng.Width, 'Status glyph is square');
    Check(Assigned(LPng.AlphaScanline[0]), 'Every resolution retains genuine alpha');
    Check(LPng.AlphaScanline[0]^[0] = 0, 'Background corner remains transparent');
    LOpaque := 0;
    LPartial := 0;
    LTransparent := 0;
    for LY := 0 to LPng.Height - 1 do
      for LX := 0 to LPng.Width - 1 do
        case LPng.AlphaScanline[LY]^[LX] of
          0: Inc(LTransparent);
          255: Inc(LOpaque);
        else
          Inc(LPartial);
        end;
    Check(LOpaque > LPng.Width * LPng.Height div 4, 'Glyph has a substantial visible body');
    Check(LTransparent > LPng.Width * LPng.Height div 8, 'Glyph does not carry an opaque square background');
    Check(LPartial > 0, 'Native coverage downsampling keeps antialiased edges');
    if LIndex mod 5 = 0 then
    begin
      SetLength(LShapes[LIndex div 5], 256);
      for LY := 0 to 15 do
        for LX := 0 to 15 do
          LShapes[LIndex div 5][LY * 16 + LX] := LPng.AlphaScanline[LY]^[LX];
    end;
  end;
  Check(not CompareMem(@LShapes[0][0], @LShapes[1][0], 256), 'Inactive/active shapes differ independently of colour');
  Check(not CompareMem(@LShapes[0][0], @LShapes[2][0], 256), 'Inactive/error shapes differ independently of colour');
  Check(not CompareMem(@LShapes[1][0], @LShapes[2][0], 256), 'Active/error shapes differ independently of colour');
  Check(Pos('ServerGlyph.v2.Inactive', GHost.DAIAction.ImageName) > 0, 'Action receives the real VCL inactive image name');
  Check(GHost.DAIButton.ImageName = GHost.DAIAction.ImageName, 'Button uses the exact registered image name');
  TDAIRuntime.Active := True;
  TDAIIDEToolbar.Refresh;
  Check(Pos('ServerGlyph.v2.Active', GHost.DAIAction.ImageName) > 0, 'Active state switches the named image');
  Check(GHost.DAIButton.ImageName = GHost.DAIAction.ImageName, 'Button follows the real VCL action image-name change');
  if ParamCount >= 2 then
  begin
    LBitmap := TBitmap.Create;
    LPreview := TPngImage.Create;
    try
      LBitmap.SetSize(240, 160);
      LBitmap.Canvas.Brush.Color := clWhite;
      LBitmap.Canvas.FillRect(Rect(0, 0, 240, 80));
      LBitmap.Canvas.Brush.Color := $00332E28;
      LBitmap.Canvas.FillRect(Rect(0, 80, 240, 160));
      for LIndex := 0 to 2 do
      begin
        LPng := GHost.Glyphs[LIndex * 5];
        LBitmap.Canvas.Draw(LIndex * 80 + 6, 6, LPng);
        LBitmap.Canvas.StretchDraw(Rect(LIndex * 80 + 24, 24, LIndex * 80 + 72, 72), LPng);
        LBitmap.Canvas.Draw(LIndex * 80 + 6, 86, LPng);
        LBitmap.Canvas.StretchDraw(Rect(LIndex * 80 + 24, 104, LIndex * 80 + 72, 152), LPng);
      end;
      LPreview.Assign(LBitmap);
      LPreview.SaveToFile(ParamStr(2));
    finally
      LPreview.Free;
      LBitmap.Free;
    end;
  end;
  TDAIIDEToolbar.Shutdown;
  GHost.RejectImages := True;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(not Assigned(GHost.DAIAction()), 'A rejected image index cannot display an unrelated IDE icon');
  Check(not Assigned(GHost.DAIButton()), 'Rejected registration leaves no misleading button');
  GHost.RejectImages := False;
  TDAIIDEToolbar.Refresh;
  Check(Assigned(GHost.DAIButton()), 'Image-registration failure recovers when the IDE becomes ready');
end;

procedure TestPinnedPackageLifecycle;
var
  LModule: HMODULE;
  LPinned: HMODULE;
  LPrepare: TPreparePackageHost;
  LInstall: TPackageToolbarOperation;
  LFinalized: Boolean;
  LImageCount: Integer;
begin
  Check(ParamCount >= 1, 'Actual production-toolbar BPL fixture path supplied');
  NewHost;
  TDAIIDEToolbar.Shutdown;
  LModule := LoadPackage(ExpandFileName(ParamStr(1)));
  LFinalized := False;
  try
    {$IFDEF WIN64}
    LPrepare := TPreparePackageHost(GetProcAddress(LModule, '_ZN3Dai7Toolbar12Packageprobe11PrepareHostEN6System15DelphiInterfaceINS2_10IInterfaceEEE'));
    LInstall := TPackageToolbarOperation(GetProcAddress(LModule, '_ZN3Dai7Toolbar12Packageprobe14InstallToolbarEv'));
    {$ELSE}
    LPrepare := TPreparePackageHost(GetProcAddress(LModule, '@Dai@Toolbar@Packageprobe@PrepareHost$qqsx44System@%DelphiInterface$17System@IInterface%'));
    LInstall := TPackageToolbarOperation(GetProcAddress(LModule, '@Dai@Toolbar@Packageprobe@InstallToolbar$qqsv'));
    {$ENDIF}
    Check(Assigned(LPrepare) and Assigned(LInstall), 'Real BPL exports are available');
    LPrepare(GHostKeepAlive);
    LInstall();
    Check(Assigned(GHost.DAIButton()), 'New package registration installs its toolbar');
    Check(GHost.Toolbar.ButtonCount = 2, 'Initial BPL adds exactly one button');
    LImageCount := GHost.Images.Count;
    Check(DAIGetModuleHandleExW($00000005, PChar(GetProcAddress(LModule, 'Initialize')), LPinned), 'Native fixture pins its callback-bearing image');
    UnloadPackage(LModule);
    LFinalized := True;
    Check(GetModuleHandle(PChar(ExtractFileName(ParamStr(1)))) = LModule, 'Pinned image remains mapped');
    Check(not Assigned(GHost.DAIButton()), 'Actual unit finalization removes the owned toolbar');
    Check(GHost.Toolbar.ButtonCount = 1, 'Finalization preserves foreign controls');
    PumpFor(650);
    Check(not Assigned(GHost.DAIButton()), 'An unregistered finalized package never blindly recreates UI');
    InitializePackage(LModule);
    LFinalized := False;
    LPrepare(GHostKeepAlive);
    LInstall();
    Check(Assigned(GHost.DAIButton()), 'New registration reinstalls even a finalized/reinitialized pinned image');
    Check(GHost.Toolbar.ButtonCount = 2, 'Reload does not duplicate foreign or owned buttons');
    Check(GHost.Images.Count = LImageCount, 'Reload preserves named VCL image indices');
    Check(Pos('ServerGlyph.v2.Inactive', GHost.DAIAction.ImageName) > 0, 'Reload does not fall back to an old D glyph');
    FinalizePackage(LModule);
    LFinalized := True;
    Check(not Assigned(GHost.DAIButton()), 'Second real finalization cleans up again');
    PumpFor(650);
    Check(not Assigned(GHost.DAIButton()), 'Finalized timers cannot execute another toolbar callback');
  finally
    if not LFinalized then
      UnloadPackage(LModule);
  end;
end;

procedure TestExternalDestructionAndCollisions;
var
  LToolbar: TToolBar;
  LActionList: TActionList;
  LForeign: TAction;
  LCount: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  GHost.DAIButton.Free;
  TDAIIDEToolbar.Refresh;
  Check(Assigned(GHost.DAIButton()), 'Destroyed toolbar button is safely reconstructed');
  Check(GHost.Toolbar.ButtonCount = 2, 'Button reconstruction does not duplicate foreign controls');
  GHost.DAIButton.DropdownMenu.Free;
  TDAIIDEToolbar.Refresh;
  Check(Assigned(GHost.DAIButton.DropdownMenu), 'Destroyed IDE-owned popup has no stale receiver');
  GHost.DAIAction.Free;
  TDAIIDEToolbar.Refresh;
  Check(Assigned(GHost.DAIAction()), 'Destroyed action is safely reconstructed');
  LToolbar := GHost.Toolbar;
  GHost.Toolbar := nil;
  LToolbar.Free;
  TDAIIDEToolbar.Refresh;
  Check(not Assigned(GHost.DAIAction()), 'Destroyed host toolbar releases residual DAI controls');
  Check(GHost.ActionList.ActionCount = 1, 'Destroyed toolbar cleanup preserves foreign actions');
  GHost.Toolbar := TToolBar.Create(GHost.Form);
  GHost.Toolbar.Parent := GHost.Form;
  GHost.Toolbar.Images := GHost.Images;
  TDAIIDEToolbar.Refresh;
  Check(Assigned(GHost.DAIButton()), 'A recreated official Debug toolbar can be bound again');
  LActionList := GHost.ActionList;
  GHost.ActionList := nil;
  LActionList.Free;
  TDAIIDEToolbar.Refresh;
  Check(not Assigned(GHost.DAIButton()), 'Destroyed action list is never dereferenced during refresh');
  TDAIIDEToolbar.Shutdown;

  NewHost;
  GHost.ForeignAction.Name := 'DAIServerToggleAction';
  LForeign := GHost.ForeignAction;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LCount := TDAILog.Messages.Count;
  Check(GHost.AddCount = 0, 'A foreign action-name collision never replaces existing controls');
  Check(LCount = 1, 'A collision is reported once');
  TDAIIDEToolbar.Refresh;
  Check(TDAILog.Messages.Count = LCount, 'Repeated readiness failures do not flood the message pane');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.ActionList.Actions[0] = LForeign, 'Collision shutdown does not remove the foreign action');

  NewHost;
  GHost.ReturnNilButton := True;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(GHost.ActionList.ActionCount = 1, 'A nil factory result leaves no residual registered action');
  GHost.ReturnNilButton := False;
  GHost.ReturnUnsupportedButton := True;
  TDAIIDEToolbar.Refresh;
  Check(GHost.Form.FindComponent('DAIServerToolButton') = nil, 'An unsupported factory result is removed safely');
  Check(GHost.ActionList.ActionCount = 1, 'Unsupported controls leave no residual action');
  GHost.ReturnUnsupportedButton := False;
  TDAIIDEToolbar.Refresh;
  Check(Assigned(GHost.DAIButton()), 'A later correct factory result can recover');
end;

function NewInertDropdown(AOwner: TComponent; AToolbar: TToolBar): TToolButton;
begin
  Result := TToolButton.Create(AOwner);
  Result.Left := AToolbar.ButtonCount * 64;
  Result.Parent := AToolbar;
  Result.Style := tbsDropDown;
  Result.ParentShowHint := False;
  Result.ShowHint := True;
end;

procedure TestActionOwnerAndCloneCleanup;
var
  LClones: array[0..2] of TToolButton;
  LBlank: TToolButton;
  LForeign: TToolButton;
  LLookalike: TToolButton;
  LOtherBar: TToolBar;
  LOtherOwner: TComponent;
  LLookalikeAction: TAction;
  LAction: TAction;
  LBinary: TMemoryStream;
  LText: TStringStream;
  LIndex: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LAction := GHost.DAIAction;
  Check(LAction.Owner = GHost.ActionList.Owner, 'Action has the IDE action-list owner, not an unnamed private controller');
  Check(GHost.Form.FindComponent('DAIServerToggleAction') = LAction, 'Desktop external-reference lookup finds the actual DAI action');
  LBinary := TMemoryStream.Create;
  LText := TStringStream.Create('', TEncoding.UTF8);
  try
    LBinary.WriteComponent(GHost.Toolbar);
    LBinary.Position := 0;
    ObjectBinaryToText(LBinary, LText);
    Check(Pos('DAIServerToggleAction', LText.DataString) > 0, 'Native VCL streaming records the DAI action reference');
    Check(Pos('DAIServerToggleAction.Owner', LText.DataString) = 0, 'Action reference does not require an unnamed Owner path');
  finally
    LText.Free;
    LBinary.Free;
  end;
  for LIndex := Low(LClones) to High(LClones) do
  begin
    LClones[LIndex] := NewInertDropdown(GHost.Form, GHost.Toolbar);
    LClones[LIndex].Action := LAction;
    LClones[LIndex].Caption := '';
    LClones[LIndex].Hint := '';
    LClones[LIndex].ImageName := '';
    LClones[LIndex].ImageIndex := -1;
    Check(LClones[LIndex].DropdownMenu = nil, 'A cloned DAI dropdown can have no popup');
  end;
  LBlank := NewInertDropdown(GHost.Form, GHost.Toolbar);
  LForeign := NewInertDropdown(GHost.Form, GHost.Toolbar);
  LForeign.Action := GHost.ForeignAction;
  LOtherOwner := TComponent.Create(GHost.Form);
  LLookalikeAction := TAction.Create(LOtherOwner);
  LLookalikeAction.Name := LAction.Name;
  LLookalike := NewInertDropdown(GHost.Form, GHost.Toolbar);
  LLookalike.Action := LLookalikeAction;
  LOtherBar := TToolBar.Create(GHost.Form);
  LOtherBar.Parent := GHost.Form;
  NewInertDropdown(GHost.Form, LOtherBar).Action := LAction;
  Check(GHost.Toolbar.ButtonCount = 8, 'Disposable host contains three DAI clones and three foreign lookalikes');
  Check(LOtherBar.ButtonCount = 1, 'Exact DAI action can also be cloned to another toolbar');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.Toolbar.ButtonCount = 4, 'Cleanup removes all exact DAI clients, not just the factory button');
  Check(LOtherBar.ButtonCount = 0, 'An exact action clone is removed without guessing its parent toolbar');
  Check(LBlank.Action = nil, 'A generic unnamed actionless dropdown is preserved');
  Check(LForeign.Action = GHost.ForeignAction, 'A foreign action dropdown remains unchanged');
  Check(LLookalike.Action = LLookalikeAction, 'Identical action name on a different object is preserved');
  Check(GHost.Form.FindComponent('DAIServerToggleAction') = nil, 'IDE ownership still releases the DAI action during shutdown');
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(GHost.Toolbar.ButtonCount = 5, 'Reload adds exactly one new DAI button beside preserved foreign controls');
end;

procedure TestLegacyLayout(const ACount: Integer; const AVariant: Integer);
var
  LButtons: TArray<TToolButton>;
  LExtra: TToolButton;
  LOtherAction: TAction;
  LExtraAction: TAction;
  LOriginalAnchorAction: TBasicAction;
  LIndex: Integer;
  LExpectedRemoval: Boolean;
  LExpectedCount: Integer;
  LOtherOwner: TComponent;
begin
  NewHost;
  GHost.ForeignButton.Name := '';
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  LOtherAction := TAction.Create(GHost.Form);
  LOtherAction.Name := 'OtherPluginCommand';
  LOtherAction.ActionList := GHost.ActionList;
  LExpectedRemoval := (AVariant = 0) and (ACount >= 3) and (ACount <= 5);
  if AVariant = 16 then
  begin
    LExtra := NewInertDropdown(GHost.Form, GHost.Toolbar);
    LExtra.Action := LOtherAction;
  end;
  SetLength(LButtons, ACount);
  for LIndex := 0 to ACount - 1 do
    if (AVariant = 28) and (LIndex = 1) then
    begin
      LButtons[LIndex] := TForeignToolButton.Create(GHost.Form);
      LButtons[LIndex].Left := GHost.Toolbar.ButtonCount * 64;
      LButtons[LIndex].Parent := GHost.Toolbar;
      LButtons[LIndex].Style := tbsDropDown;
      LButtons[LIndex].ParentShowHint := False;
      LButtons[LIndex].ShowHint := True;
    end
    else
      LButtons[LIndex] := NewInertDropdown(GHost.Form, GHost.Toolbar);
  if AVariant <> 0 then
  begin
    case AVariant of
      1: LButtons[1].Action := LOtherAction;
      2: LButtons[1].DropdownMenu := TPopupMenu.Create(GHost.Form);
      3: LButtons[1].Caption := 'foreign caption';
      4: LButtons[1].Hint := 'foreign hint';
      5: LButtons[1].ImageName := 'Other.Plugin.Image';
      6: LButtons[1].ImageIndex := 0;
      7: LButtons[1].Tag := 1;
      8: LButtons[1].OnClick := GHost.DummyClick;
      9: LButtons[1].Visible := False;
      10: LButtons[1].Enabled := False;
      11: LButtons[1].ParentShowHint := True;
      12: LButtons[1].ShowHint := False;
      13: LButtons[1].Name := 'OtherPluginButton';
      14: LButtons[1].MenuItem := TMenuItem.Create(GHost.Form);
      15: LButtons[1].Marked := True;
      17: GHost.ForeignAction.Name := 'rununtilreturncommand';
      18:
        begin
          LExtra := NewInertDropdown(GHost.Form, GHost.Toolbar);
          LExtra.Action := GHost.ForeignAction;
        end;
      19:
        begin
          LExtra := NewInertDropdown(GHost.Form, GHost.Toolbar);
          LExtra.Action := LOtherAction;
        end;
      20:
        begin
          LButtons[1].Free;
          LOtherOwner := TComponent.Create(GHost.Form);
          LButtons[1] := NewInertDropdown(LOtherOwner, GHost.Toolbar);
        end;
      21: LButtons[1].Style := tbsButton;
      22: LButtons[1].PopupMenu := TPopupMenu.Create(GHost.Form);
      23: LButtons[1].Down := True;
      24: LButtons[1].EnableDropdown := True;
      25: LButtons[1].AutoSize := True;
      26: LButtons[1].Indeterminate := True;
      27: LButtons[1].Wrap := True;
      29, 30:
        begin
          LOtherOwner := TComponent.Create(GHost.Form);
          LExtraAction := TAction.Create(LOtherOwner);
          LExtraAction.Name := 'RunUntilReturnCommand';
          if AVariant = 29 then
            GHost.ForeignButton.Action := LExtraAction
          else
            LExtraAction.ActionList := GHost.ActionList;
        end;
      31: GHost.ForeignAction.ActionList := nil;
      32:
        begin
          GHost.ForeignButton.Name := 'RunUntilReturn';
          GHost.ForeignAction.Name := 'OtherDebuggerCommand';
        end;
      33: LButtons[1].DragMode := dmAutomatic;
      34: LButtons[1].DragKind := dkDock;
    end;
  end;
  LOriginalAnchorAction := GHost.ForeignButton.Action;
  LExpectedCount := GHost.Toolbar.ButtonCount + 1;
  if LExpectedRemoval then
    Dec(LExpectedCount, ACount);
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  if GHost.Toolbar.ButtonCount <> LExpectedCount then
    for LIndex := 0 to GHost.Toolbar.ButtonCount - 1 do
      with GHost.Toolbar.Buttons[LIndex] do
        Writeln('Legacy candidate ', LIndex, ' name=', Name, ' action=', Assigned(Action), ' caption=', Caption,
          ' hint=', Hint, ' img=', ImageIndex, ' imageName=', ImageName, ' style=', Ord(Style), ' showhint=', ShowHint,
          ' parenthint=', ParentShowHint, ' enabledrop=', EnableDropdown, ' autosize=', AutoSize);
  Check(Assigned(GHost.DAIButton()), 'Legacy-layout migration still installs the named current DAI button');
  Check(GHost.Toolbar.ButtonCount = LExpectedCount,
    Format('Legacy count %d variant %d is either entirely migrated or entirely preserved', [ACount, AVariant]));
  if AVariant = 28 then
  begin
    LButtons[1].Click;
    Check(TForeignToolButton(LButtons[1]).ClickCount = 1, 'A foreign subclass with virtual behavior remains alive and usable');
  end;
  Check(GHost.ForeignButton.Action = LOriginalAnchorAction, 'Original action anchor is never removed or modified');
  TDAIIDEToolbar.Refresh;
  Check(GHost.Toolbar.ButtonCount = LExpectedCount, 'Legacy migration is idempotent');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.Toolbar.ButtonCount = LExpectedCount - 1, 'Later shutdown removes only the current DAI action client');
end;

procedure TestLegacyMigration;
var
  LVariant: Integer;
begin
  TestLegacyLayout(0, 0);
  TestLegacyLayout(1, 0);
  TestLegacyLayout(2, 0);
  TestLegacyLayout(3, 0);
  TestLegacyLayout(4, 0);
  TestLegacyLayout(5, 0);
  TestLegacyLayout(6, 0);
  for LVariant := 1 to 32 do
  begin
    TestLegacyLayout(3, LVariant);
    TestLegacyLayout(4, LVariant);
    TestLegacyLayout(5, LVariant);
  end;
end;

procedure TestLateLegacyMigration(const ACount: Integer; const AUnavailableTarget: Integer = 0);
var
  LButton: TToolButton;
  LIndex: Integer;
  LAddCount: Integer;
  LExpectedCount: Integer;
  LOtherAction: TAction;
begin
  NewHost;
  GHost.ForeignButton.Name := '';
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LButton := GHost.DAIButton;
  LAddCount := GHost.AddCount;
  for LIndex := 1 to ACount do
    NewInertDropdown(GHost.Form, GHost.Toolbar);
  // A desktop restore can retain both the toolbar and our current button while
  // inserting legacy records before it. Keep object identities unchanged.
  LButton.Left := GHost.Toolbar.ButtonCount * 64;
  Check(GHost.Toolbar.ButtonCount = ACount + 2, 'Late restoration inserted the observed complete legacy group');
  Check(GHost.Toolbar.Buttons[GHost.Toolbar.ButtonCount - 1] = LButton, 'Late legacy group is adjacent before the current button');
  LExpectedCount := 2;
  if AUnavailableTarget <> 0 then
  begin
    LExpectedCount := ACount + 2;
    case AUnavailableTarget of
      1: GHost.Toolbar.Destroying;
      2: GHost.ActionList.Destroying;
      3: LButton.Destroying;
      4: GHost.DAIAction.Destroying;
      5: GHost.ForeignAction.Destroying;
      6:
        begin
          LOtherAction := TAction.Create(GHost.Form);
          LOtherAction.Name := 'ForeignReplacementAction';
          LOtherAction.ActionList := GHost.ActionList;
          LButton.Action := LOtherAction;
        end;
    end;
  end;
  TDAIIDEToolbar.Refresh;
  Check(GHost.Toolbar.ButtonCount = LExpectedCount,
    Format('Late count %d unavailable target %d either migrates completely or stays intact', [ACount, AUnavailableTarget]));
  Check(GHost.DAIButton = LButton, 'Late migration preserves the existing DAI button object');
  Check(GHost.AddCount = LAddCount, 'Late migration does not recreate the toolbar button');
  TDAIIDEToolbar.Refresh;
  Check(GHost.Toolbar.ButtonCount = LExpectedCount, 'Repeated ready-state migration remains idempotent');
end;

procedure TestLateUnavailableMigration;
var
  LTarget: Integer;
  LCount: Integer;
begin
  for LTarget := 1 to 6 do
    for LCount := 3 to 5 do
      TestLateLegacyMigration(LCount, LTarget);
end;

procedure TestLegacyDragSafety;
begin
  TestLegacyLayout(5, 0);
  TestLegacyLayout(5, 33);
  TestLegacyLayout(5, 34);
end;

procedure TestReentryAndThreadGuard;
var
  LExecute: TNotifyEvent;
  LThread: TThread;
  LRejected: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LExecute := GHost.DAIAction.OnExecute;
  TDAIRuntime.OnStart :=
    procedure
    begin
      Check(not GHost.DAIAction.Enabled, 'A transition disables its own action');
      LExecute(nil);
      TDAIIDEToolbar.Refresh;
    end;
  LExecute(nil);
  Check(TDAIRuntime.StartCount = 1, 'A nested transition cannot start the server twice');
  TDAIRuntime.OnStop :=
    procedure
    begin
      TDAIIDEToolbar.Shutdown;
      TDAIIDEToolbar.Shutdown;
      LExecute(nil);
      TDAIIDEToolbar.Refresh;
    end;
  LExecute(nil);
  Check(TDAIRuntime.StopCount = 1, 'A reentrant shutdown does not call StopServer recursively');
  Check(not Assigned(GHost.DAIAction()), 'Reentrant shutdown retires action only after its receiver returns');
  Check(GHost.Toolbar.ButtonCount = 1, 'Reentrant shutdown eventually removes the owned button');
  Check(GHost.Form.FindComponent('DAIServerPopupMenu') = nil, 'Reentrant shutdown also retires the owned popup');
  TDAIRuntime.OnStart := nil;
  TDAIRuntime.OnStop := nil;
  LRejected := 0;
  LThread := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        TDAIIDEToolbar.Install;
      except
        on E: EInvalidOperation do
          Inc(LRejected);
      end;
      try
        TDAIIDEToolbar.Refresh;
      except
        on E: EInvalidOperation do
          Inc(LRejected);
      end;
      try
        TDAIIDEToolbar.Shutdown;
      except
        on E: EInvalidOperation do
          Inc(LRejected);
      end;
    end);
  LThread.FreeOnTerminate := False;
  try
    LThread.Start;
    LThread.WaitFor;
    Check(not Assigned(LThread.FatalException), 'Worker misuse is rejected without uncaught exceptions');
  finally
    LThread.Free;
  end;
  Check(LRejected = 3, 'Every public UI entry point rejects worker-thread calls');
  Check(GHost.AddCount = 1, 'Worker calls never invoke the IDE factory');
end;

{$I ToolbarTests\Toolbar.Stream.Tests.inc}
{$I ToolbarTests\Toolbar.Layout.Tests.inc}

begin
  try
    Application.Initialize;
    if ParamStr(3) = 'LegacyDrag' then
      TestLegacyDragSafety
    else if ParamStr(3) = 'Stream' then
      TestToolbarStream
    else if ParamStr(3) = 'LayoutGrow' then
      TestToolbarLayoutGrowth
    else
    begin
      TestReadinessAndStatus;
      TestFailures;
      TestGlyphs;
      TestExternalDestructionAndCollisions;
      TestActionOwnerAndCloneCleanup;
      TestLegacyMigration;
      TestLateLegacyMigration(3);
      TestLateLegacyMigration(4);
      TestLateLegacyMigration(5);
      TestLateUnavailableMigration;
      TestLegacyDragSafety;
      TestReentryAndThreadGuard;
      TestPinnedPackageLifecycle;
      TestToolbarStream;
      TestToolbarLayoutGrowth;
    end;
    TDAIIDEToolbar.Shutdown;
    BorlandIDEServices := nil;
    GHostKeepAlive := nil;
    Writeln('DAI toolbar: ', GChecks, ' checks passed.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      TDAIIDEToolbar.Shutdown;
      BorlandIDEServices := nil;
      GHostKeepAlive := nil;
      ExitCode := 1;
    end;
  end;
end.
