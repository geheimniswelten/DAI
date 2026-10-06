unit h5u.DAI.IDE.Toolbar;

interface

type
  TDAIIDEToolbar = class sealed
  public
    // The IDE owns the UI thread; callers must not marshal these during teardown.
    class procedure Install; static;
    class procedure Refresh; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Actions,
  System.Classes,
  System.SysUtils,
  System.Types,
  Winapi.CommCtrl,
  Winapi.Windows,
  ToolsAPI,
  Vcl.ActnList,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Vcl.ImgList,
  Vcl.Menus,
  h5u.DAI.Log,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Settings;

const
  CDAIActionName = 'DAIServerToggleAction';
  CDAIButtonName = 'DAIServerToolButton';
  // New identifiers replace the old D glyphs even within the same IDE session.
  CDAIImageIds: array[0..2] of string = ('h5u.DAI.ServerGlyph.v2.Inactive', 'h5u.DAI.ServerGlyph.v2.Active', 'h5u.DAI.ServerGlyph.v2.Error');
  CDAIImageColors: array[0..2] of TColor = ($00857769, $004AA52A, $004244DB);
  CDAIImageSizes: array[0..4] of Integer = (16, 20, 24, 32, 48);

type
  TDAIActionAccess = class(TAction);
  TDAIControlActionLinkAccess = class(TControlActionLink);
  TDAIToolButtonAccess = class(TToolButton);

  TDAIToolbarController = class;

  // The IDE can retain a local notifier interface across Unregister. It owns no
  // controller or VCL object; Detach retires the weak receiver before shutdown.
  TDAIToolbarReadNotifier = class(TNotifierObject, IOTANotifier, INTAReadToolbarNotifier, INTAToolbarStreamNotifier, INTAToolbarStreamNotifier190)
  private
    FController: TDAIToolbarController;
  public
    procedure AfterSave; reintroduce; overload;
    procedure BeforeSave; reintroduce; overload;
    procedure AfterSave(Toolbar: TWinControl); overload;
    procedure BeforeSave(Toolbar: TWinControl); overload;
    constructor Create(AController: TDAIToolbarController);
    procedure Detach;
    procedure FindMethodInstance(Reader: TReader; const MethodName: string; var Method: TMethod; var Error: Boolean);
    procedure SetName(Reader: TReader; Component: TComponent; var Name: string; var Handled: Boolean);
    procedure ReadError(Reader: TReader; const Message: string; var Handled: Boolean);
    procedure ToolbarLoaded(Toolbar: TWinControl);
    procedure BeforeLoad(Toolbar: TWinControl);
  end;

  // Separate weak notifications survive RemoveUI's own notification cleanup.
  TDAIStreamedButtonCapture = class(TComponent)
  private
    FButton: TToolButton;
    FToolbar: TToolBar;
    FRoot: TComponent;
    FAmbiguous: Boolean;
    FConsumed: Boolean;
    FSeen: Boolean;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;
    procedure Clear;
    procedure Capture(AButton: TToolButton; AToolbar: TToolBar; ARoot: TComponent);
    procedure Consume;
    function Ready: Boolean;
    property Button: TToolButton read FButton;
    property Toolbar: TToolBar read FToolbar;
    property Root: TComponent read FRoot;
  end;

  TDAIToolbarController = class(TComponent)
  private
    FTimer: TTimer;
    FReadNotifier: TDAIToolbarReadNotifier;
    FReadNotifierInterface: IOTANotifier;
    FReadNotifierServices: INTAServices;
    FReadNotifierIndex: Integer;
    FStreamCapture: TDAIStreamedButtonCapture;
    FToolbar: TToolBar;
    FActionList: TCustomActionList;
    FAction: TAction;
    FButton: TToolButton;
    FPopup: TPopupMenu;
    FToggleItem: TMenuItem;
    FOptionsItem: TMenuItem;
    FResetItem: TMenuItem;
    FImages: array[0..2] of Integer;
    FCallbackDepth: Integer;
    FBusy: Boolean;
    FRefreshing: Boolean;
    FShuttingDown: Boolean;
    FLastInstallError: string;
    FActionError: string;
    procedure LeaveCallback;
    procedure RemoveUI;
    procedure RemoveActionButtons;
    procedure RemoveLegacyButtons(const AAllowSingle: Boolean = False);
    procedure EnsureReadNotifier;
    procedure RetireReadNotifier;
    procedure CaptureReadButton(Reader: TReader; Component: TComponent; const AName: string);
    procedure BeginToolbarRead(AToolbar: TWinControl);
    function RestoredButton(AToolbar: TToolBar; AActionList: TCustomActionList): TToolButton;
    procedure ReportError(const AError: string);
    procedure InstallImages(const AServices: INTAServices; AImages: TCustomImageList);
    procedure CreatePopup;
    procedure EnsureOwnButtonFitsHorizontally;
    procedure EnsureInstalled;
    procedure UpdateStatus;
    procedure TimerTick(Sender: TObject);
    procedure ToggleServer(Sender: TObject);
    procedure OpenOptions(Sender: TObject);
    procedure ResetSessionPermissions(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create; reintroduce;
    destructor Destroy; override;
    procedure ActivateReadHooks;
    procedure Refresh;
    procedure Shutdown;
  end;

var
  GController: TDAIToolbarController;

function DAIGetModuleHandleExW(const AFlags: DWORD; const AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExW';

procedure RequireMainThread;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('Die DAI-Werkzeugleiste muss auf dem IDE-Hauptthread verwaltet werden.');
end;

function IDEMenuTracking: Boolean;
var
  LInfo: TGUIThreadInfo;
begin
  LInfo := Default(TGUIThreadInfo);
  LInfo.cbSize := SizeOf(LInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, LInfo) and
    ((LInfo.flags and (GUI_INMENUMODE or GUI_POPUPMENUMODE or GUI_SYSTEMMENUMODE)) <> 0);
end;

procedure UnregisterToolbarReadNotifier(const AServices: INTAServices; const AIndex: Integer);
var
  LModule: HMODULE;
begin
  if not Assigned(AServices) or (AIndex < 0) then
    Exit;
  try
    AServices.UnregisterToolbarNotifier(AIndex);
  except
    on E: Exception do
    begin
      // The already detached receiver can be retained by the IDE after failure.
      // Only this exceptional path pins its code; normal reload remains unpinned.
      DAIGetModuleHandleExW($00000001 or $00000004, PWideChar(@RequireMainThread), LModule);
      TDAILog.Error('DAI-Toolbar-Notifier konnte nicht abgemeldet werden: ' + E.ClassName + ': ' + E.Message);
    end;
  end;
end;

constructor TDAIToolbarReadNotifier.Create(AController: TDAIToolbarController);
begin
  inherited Create;
  FController := AController;
end;

procedure TDAIToolbarReadNotifier.Detach;
begin
  FController := nil;
end;

procedure TDAIToolbarReadNotifier.FindMethodInstance(Reader: TReader; const MethodName: string; var Method: TMethod; var Error: Boolean);
begin
end;

procedure TDAIToolbarReadNotifier.SetName(Reader: TReader; Component: TComponent; var Name: string; var Handled: Boolean);
begin
  if Assigned(FController) then
    FController.CaptureReadButton(Reader, Component, Name);
  // Leave Name and Handled untouched. The IDE normalizes toolbutton names after
  // this callback, and preserving them here can collide with an existing button.
end;

procedure TDAIToolbarReadNotifier.ReadError(Reader: TReader; const Message: string; var Handled: Boolean);
begin
end;

procedure TDAIToolbarReadNotifier.AfterSave;
begin
end;

procedure TDAIToolbarReadNotifier.BeforeSave;
begin
end;

procedure TDAIToolbarReadNotifier.AfterSave(Toolbar: TWinControl);
begin
end;

procedure TDAIToolbarReadNotifier.BeforeSave(Toolbar: TWinControl);
begin
end;

procedure TDAIToolbarReadNotifier.ToolbarLoaded(Toolbar: TWinControl);
begin
  // No VCL mutation inside the reader. The timer's Refresh validates after the
  // IDE has assigned its public toolbar pointer, which is nil during ReadComponents.
end;

procedure TDAIToolbarReadNotifier.BeforeLoad(Toolbar: TWinControl);
begin
  if Assigned(FController) then
    FController.BeginToolbarRead(Toolbar);
end;

destructor TDAIStreamedButtonCapture.Destroy;
begin
  Clear;
  inherited;
end;

procedure TDAIStreamedButtonCapture.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = FButton then
    FButton := nil;
  if AComponent = FToolbar then
    FToolbar := nil;
  if AComponent = FRoot then
    FRoot := nil;
end;

procedure TDAIStreamedButtonCapture.Clear;
begin
  if Assigned(FButton) then
    FButton.RemoveFreeNotification(Self);
  if Assigned(FToolbar) then
    FToolbar.RemoveFreeNotification(Self);
  if Assigned(FRoot) then
    FRoot.RemoveFreeNotification(Self);
  FButton := nil;
  FToolbar := nil;
  FRoot := nil;
  FAmbiguous := False;
  FConsumed := False;
  FSeen := False;
end;

procedure TDAIStreamedButtonCapture.Capture(AButton: TToolButton; AToolbar: TToolBar; ARoot: TComponent);
begin
  if FConsumed then
    Clear;
  if FAmbiguous then
    Exit;
  if FSeen then
  begin
    if (FButton <> AButton) or (FToolbar <> AToolbar) or (FRoot <> ARoot) then
      FAmbiguous := True;
    Exit;
  end;
  FButton := AButton;
  FToolbar := AToolbar;
  FRoot := ARoot;
  FSeen := True;
  FButton.FreeNotification(Self);
  FToolbar.FreeNotification(Self);
  FRoot.FreeNotification(Self);
end;

procedure TDAIStreamedButtonCapture.Consume;
begin
  FConsumed := True;
end;

function TDAIStreamedButtonCapture.Ready: Boolean;
begin
  Result := False;
  if FConsumed or FAmbiguous then
    Exit;
  if not Assigned(FButton) or not Assigned(FToolbar) or not Assigned(FRoot) then
    Exit;
  if csDestroying in FButton.ComponentState then
    Exit;
  if csDestroying in FToolbar.ComponentState then
    Exit;
  if csDestroying in FRoot.ComponentState then
    Exit;
  if FButton.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  if FToolbar.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  if FRoot.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  Result := True;
end;

procedure TDAIToolbarController.ActivateReadHooks;
begin
  Inc(FCallbackDepth);
  try
    try
      EnsureReadNotifier;
    except
      on E: Exception do
        if not FShuttingDown then
          ReportError(E.ClassName + ': ' + E.Message);
    end;
  finally
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.EnsureReadNotifier;
var
  LServices: INTAServices;
  LNotifier: TDAIToolbarReadNotifier;
  LInterface: IOTANotifier;
  LIndex: Integer;
begin
  if FShuttingDown or Assigned(FReadNotifierInterface) then
    Exit;
  if not Supports(BorlandIDEServices, INTAServices, LServices) then
    Exit;
  LNotifier := TDAIToolbarReadNotifier.Create(Self);
  LInterface := LNotifier;
  try
    LIndex := LServices.RegisterToolbarNotifier(LInterface);
    if LIndex < 0 then
      raise EInvalidOperation.Create('Die IDE hat die DAI-Toolbar-Lesenotification nicht registriert.');
    if FShuttingDown then
    begin
      LNotifier.Detach;
      UnregisterToolbarReadNotifier(LServices, LIndex);
      Exit;
    end;
    FReadNotifier := LNotifier;
    FReadNotifierInterface := LInterface;
    FReadNotifierServices := LServices;
    FReadNotifierIndex := LIndex;
  except
    LNotifier.Detach;
    raise;
  end;
end;

procedure TDAIToolbarController.RetireReadNotifier;
var
  LNotifier: TDAIToolbarReadNotifier;
  LInterface: IOTANotifier;
  LServices: INTAServices;
  LIndex: Integer;
begin
  LNotifier := FReadNotifier;
  LInterface := FReadNotifierInterface;
  LServices := FReadNotifierServices;
  LIndex := FReadNotifierIndex;
  FReadNotifier := nil;
  FReadNotifierInterface := nil;
  FReadNotifierServices := nil;
  FReadNotifierIndex := -1;
  if Assigned(LNotifier) then
    LNotifier.Detach;
  UnregisterToolbarReadNotifier(LServices, LIndex);
  LInterface := nil;
end;

procedure TDAIToolbarController.CaptureReadButton(Reader: TReader; Component: TComponent; const AName: string);
var
  LButton: TToolButton;
  LToolbar: TToolBar;
begin
  if FShuttingDown or (AName <> CDAIButtonName) then
    Exit;
  if not Assigned(Reader) or not Assigned(Component) then
    Exit;
  if Component.ClassType <> TToolButton then
    Exit;
  LButton := TToolButton(Component);
  if not (LButton.Parent is TToolBar) then
    Exit;
  LToolbar := TToolBar(LButton.Parent);
  if LToolbar.Name <> sDebugToolBar then
    Exit;
  if not Assigned(Reader.Root) then
    Exit;
  if (LButton.Owner <> Reader.Root) or (LToolbar.Owner <> Reader.Root) then
    Exit;
  if (Reader.Owner <> Reader.Root) or (Reader.Parent <> LToolbar) then
    Exit;
  if csDestroying in LButton.ComponentState then
    Exit;
  if csDestroying in LToolbar.ComponentState then
    Exit;
  if csDestroying in Reader.Root.ComponentState then
    Exit;
  // ReadComponents uses AOwner/AppBuilder as Root. Public ToolBar[sDebugToolBar]
  // is temporarily nil here; its exact object identity is checked at adoption.
  FStreamCapture.Capture(LButton, LToolbar, Reader.Root);
end;

procedure TDAIToolbarController.BeginToolbarRead(AToolbar: TWinControl);
begin
  if FShuttingDown then
    Exit;
  if not (AToolbar is TToolBar) then
    Exit;
  if AToolbar.Name = sDebugToolBar then
    FStreamCapture.Clear;
end;

function TDAIToolbarController.RestoredButton(AToolbar: TToolBar; AActionList: TCustomActionList): TToolButton;
var
  LButton: TToolButton;
  LOwnClick: TNotifyEvent;
  LClick: TNotifyEvent;
begin
  Result := nil;
  if not FStreamCapture.Ready then
    Exit;
  LButton := FStreamCapture.Button;
  // A plausible stream name alone never authorizes reuse: match the actual SDK
  // toolbar and its IDE action-list owner after ReadToolbar assigns its pointer.
  if (FStreamCapture.Toolbar <> AToolbar) or (FStreamCapture.Root <> AActionList.Owner) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  if (LButton.Parent <> AToolbar) or (LButton.Owner <> AActionList.Owner) or (AToolbar.Owner <> AActionList.Owner) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  if (LButton.Name <> '') and (LButton.Name <> CDAIButtonName) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  LOwnClick := ToggleServer;
  LClick := LButton.OnClick;
  if Assigned(LClick) then
    if (TMethod(LClick).Code <> TMethod(LOwnClick).Code) or (TMethod(LClick).Data <> Self) then
    begin
      FStreamCapture.Consume;
      Exit;
    end;
  if ((LButton.Action <> nil) and (LButton.Action <> FAction)) or
    ((LButton.DropdownMenu <> nil) and (LButton.DropdownMenu <> FPopup)) or
    (LButton.PopupMenu <> nil) or (LButton.MenuItem <> nil) or (LButton.Style <> tbsDropDown) or
    (LButton.Tag <> 0) or (LButton.DragMode <> dmManual) or (LButton.DragKind <> dkDrag) or
    Assigned(TDAIToolButtonAccess(LButton).OnDblClick) or Assigned(LButton.OnContextPopup) or
    Assigned(LButton.OnMouseDown) or Assigned(LButton.OnMouseMove) or Assigned(LButton.OnMouseUp) or
    Assigned(LButton.OnDragDrop) or Assigned(LButton.OnDragOver) or Assigned(LButton.OnStartDrag) or
    Assigned(LButton.OnEndDrag) or Assigned(LButton.OnMouseEnter) or Assigned(LButton.OnMouseLeave) or
    Assigned(LButton.OnMouseActivate) or Assigned(LButton.OnStartDock) or Assigned(LButton.OnEndDock) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  Result := LButton;
end;

constructor TDAIToolbarController.Create;
begin
  inherited Create(nil);
  FReadNotifierIndex := -1;
  FStreamCapture := TDAIStreamedButtonCapture.Create(Self);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 500;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TDAIToolbarController.Destroy;
begin
  FShuttingDown := True;
  RetireReadNotifier;
  if Assigned(FStreamCapture) then
    FStreamCapture.Clear;
  if Assigned(FTimer) then
  begin
    FTimer.Enabled := False;
    FTimer.OnTimer := nil;
  end;
  RemoveUI;
  inherited;
end;

procedure TDAIToolbarController.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = FToolbar then
    FToolbar := nil;
  if AComponent = FActionList then
    FActionList := nil;
  if AComponent = FAction then
    FAction := nil;
  if AComponent = FButton then
    FButton := nil;
  if AComponent = FPopup then
    FPopup := nil;
  if AComponent = FToggleItem then
    FToggleItem := nil;
  if AComponent = FOptionsItem then
    FOptionsItem := nil;
  if AComponent = FResetItem then
    FResetItem := nil;
end;

procedure TDAIToolbarController.RemoveUI;
begin
  // Desktop/customization can create more than the one factory-returned button.
  // Remove exact action clients before freeing the action loses their identity.
  RemoveActionButtons;
  if Assigned(FButton) then
  begin
    FButton.Action := nil;
    FButton.DropdownMenu := nil;
  end;
  FreeAndNil(FPopup);
  FreeAndNil(FButton);
  FreeAndNil(FAction);
  if Assigned(FToolbar) then
    FToolbar.RemoveFreeNotification(Self);
  FToolbar := nil;
  if Assigned(FActionList) then
    FActionList.RemoveFreeNotification(Self);
  FActionList := nil;
end;

procedure TDAIToolbarController.RemoveActionButtons;
var
  LIndex: Integer;
  LLink: TBasicActionLink;
  LControl: TControl;
  LButton: TToolButton;
begin
  if not Assigned(FAction) then
    Exit;
  for LIndex := TDAIActionAccess(FAction).ClientCount - 1 downto 0 do
  begin
    if LIndex >= TDAIActionAccess(FAction).ClientCount then
      Continue;
    LLink := TDAIActionAccess(FAction).Clients[LIndex];
    if not (LLink is TControlActionLink) then
      Continue;
    LControl := TDAIControlActionLinkAccess(LLink).FClient;
    if not (LControl is TToolButton) then
      Continue;
    LButton := TToolButton(LControl);
    if (LButton.Action <> FAction) or (csDestroying in LButton.ComponentState) then
      Continue;
    LButton.Action := nil;
    LButton.DropdownMenu := nil;
    LButton.Free;
  end;
end;

procedure TDAIToolbarController.RemoveLegacyButtons(const AAllowSingle: Boolean);
var
  LAnchorAction: TContainedAction;
  LAction: TContainedAction;
  LAnchor: Integer;
  LIndex: Integer;
  LCount: Integer;
  LButton: TToolButton;
  LCandidates: array[0..4] of TToolButton;

  function IsInertLegacyButton(const AButton: TToolButton): Boolean;
  begin
    if not Assigned(AButton) then
      Exit(False);
    Result := (AButton.ClassType = TToolButton) and (AButton.Owner = FButton.Owner) and (AButton.Name = '') and (AButton.Action = nil) and
      (AButton.Style = tbsDropDown) and (AButton.DropdownMenu = nil) and (AButton.PopupMenu = nil) and
      (AButton.MenuItem = nil) and not AButton.EnableDropdown and not AButton.Down and not AButton.Grouped and
      not AButton.AllowAllUp and not AButton.AutoSize and not AButton.Marked and not AButton.Indeterminate and not AButton.Wrap and
      (AButton.Caption = '') and (AButton.Hint = '') and (AButton.ImageName = '') and (AButton.ImageIndex = -1) and
      (AButton.DragMode = dmManual) and (AButton.DragKind = dkDrag) and
      (AButton.Tag = 0) and AButton.Visible and AButton.Enabled and AButton.ShowHint and not AButton.ParentShowHint and
      not Assigned(AButton.OnClick) and not Assigned(TDAIToolButtonAccess(AButton).OnDblClick) and not Assigned(AButton.OnContextPopup) and
      not Assigned(AButton.OnMouseDown) and not Assigned(AButton.OnMouseMove) and not Assigned(AButton.OnMouseUp) and
      not Assigned(AButton.OnDragDrop) and not Assigned(AButton.OnDragOver) and not Assigned(AButton.OnStartDrag) and
      not Assigned(AButton.OnEndDrag) and not Assigned(AButton.OnMouseEnter) and not Assigned(AButton.OnMouseLeave) and
      not Assigned(AButton.OnMouseActivate) and not Assigned(AButton.OnStartDock) and not Assigned(AButton.OnEndDock) and
      not (csDestroying in AButton.ComponentState);
  end;

begin
  if not Assigned(FToolbar) or not Assigned(FActionList) or not Assigned(FButton) or not Assigned(FAction) then
    Exit;
  if csDestroying in FToolbar.ComponentState then
    Exit;
  if csDestroying in FActionList.ComponentState then
    Exit;
  if csDestroying in FButton.ComponentState then
    Exit;
  if csDestroying in FAction.ComponentState then
    Exit;
  if (FButton.Parent <> FToolbar) or (FButton.Action <> FAction) then
    Exit;
  // IDE toolbar streaming leaves standard button names empty. Resolve the exact
  // action from the official IDE list, then match its object identity, not text
  // or an unstable button name. Any ambiguity leaves the toolbar untouched.
  LAnchorAction := nil;
  for LIndex := 0 to FActionList.ActionCount - 1 do
  begin
    LAction := FActionList.Actions[LIndex];
    if not Assigned(LAction) then
      Continue;
    if LAction.Name <> 'RunUntilReturnCommand' then
      Continue;
    if csDestroying in LAction.ComponentState then
      Exit;
    if Assigned(LAnchorAction) then
      Exit;
    LAnchorAction := LAction;
  end;
  if not Assigned(LAnchorAction) then
    Exit;
  LAnchor := -1;
  for LIndex := 0 to FToolbar.ButtonCount - 1 do
  begin
    LButton := FToolbar.Buttons[LIndex];
    if not Assigned(LButton) then
      Exit;
    if LButton.Action <> LAnchorAction then
      Continue;
    if LAnchor >= 0 then
      Exit;
    LAnchor := LIndex;
  end;
  if LAnchor < 0 then
    Exit;
  // Only the verified three/four/five inert records directly between the IDE's
  // Run Until Return action button and this controller's current button qualify.
  LCount := 0;
  LIndex := LAnchor + 1;
  while (LIndex < FToolbar.ButtonCount) and (LCount < Length(LCandidates)) do
  begin
    LButton := FToolbar.Buttons[LIndex];
    if LButton = FButton then
      Break;
    if not IsInertLegacyButton(LButton) then
      Exit;
    LCandidates[LCount] := LButton;
    Inc(LCount);
    Inc(LIndex);
  end;
  if (LCount < 3) and not (AAllowSingle and (LCount = 1)) then
    Exit;
  if LIndex >= FToolbar.ButtonCount then
    Exit;
  if FToolbar.Buttons[LIndex] <> FButton then
    Exit;
  for LIndex := LCount - 1 downto 0 do
    LCandidates[LIndex].Free;
end;

procedure TDAIToolbarController.LeaveCallback;
begin
  Dec(FCallbackDepth);
  if FShuttingDown and (FCallbackDepth = 0) then
    Free;
end;

procedure TDAIToolbarController.Shutdown;
begin
  FShuttingDown := True;
  RetireReadNotifier;
  FStreamCapture.Clear;
  FTimer.Enabled := False;
  FTimer.OnTimer := nil;
  if Assigned(FAction) then
  begin
    FAction.OnExecute := nil;
    FAction.Enabled := False;
  end;
  if Assigned(FToggleItem) then
    FToggleItem.OnClick := nil;
  if Assigned(FOptionsItem) then
    FOptionsItem.OnClick := nil;
  if Assigned(FResetItem) then
    FResetItem.OnClick := nil;
  // StopServer may pump synchronized workers. A reentrant IDE shutdown must
  // not destroy this receiver while one of its UI callbacks is still running.
  if FCallbackDepth = 0 then
    Free;
end;

procedure TDAIToolbarController.ReportError(const AError: string);
begin
  if AError = FLastInstallError then
    Exit;
  FLastInstallError := AError;
  TDAILog.Error('DAI-Werkzeugleiste: ' + AError);
end;

function CreateServerGlyph(const AState: Integer; const ASize: Integer): TPngImage;
var
  LBitmap: TBitmap;
  LSmallBitmap: TBitmap;
  LCanvas: TCanvas;
  LSource: PRGBTriple;
  LTarget: PByteArray;
  LAlpha: PByteArray;
  LRed: Integer;
  LGreen: Integer;
  LBlue: Integer;
  LCoverage: Integer;
  LX: Integer;
  LY: Integer;
  LSampleX: Integer;
  LSampleY: Integer;
  LSuccess: Boolean;

  function P(const ACoordinate: Integer): Integer;
  begin
    Result := MulDiv(ACoordinate, ASize * 4, 16);
  end;

begin
  // Draw at four times the target size, then retain actual coverage as alpha.
  // No font, image file, mask-colour halo or theme-coloured background is needed.
  LBitmap := TBitmap.Create;
  LSmallBitmap := nil;
  Result := nil;
  LSuccess := False;
  try
    LBitmap.PixelFormat := pf24bit;
    LBitmap.SetSize(ASize * 4, ASize * 4);
    LCanvas := LBitmap.Canvas;
    LCanvas.Brush.Color := clFuchsia;
    LCanvas.FillRect(Rect(0, 0, LBitmap.Width, LBitmap.Height));
    LCanvas.Pen.Width := P(1);
    LCanvas.Pen.Color := $00956436;
    LCanvas.Brush.Color := $00F8F0E5;
    LCanvas.RoundRect(P(1), P(1), P(13), P(13), P(3), P(3));
    LCanvas.Pen.Color := $00956436;
    LCanvas.MoveTo(P(5), P(4));
    LCanvas.LineTo(P(10), P(4));
    LCanvas.MoveTo(P(5), P(8));
    LCanvas.LineTo(P(8), P(8));
    LCanvas.Pen.Color := CDAIImageColors[AState];
    LCanvas.Brush.Color := CDAIImageColors[AState];
    LCanvas.Ellipse(P(2), P(3), P(4), P(5));
    LCanvas.Ellipse(P(2), P(7), P(4), P(9));
    LCanvas.Pen.Color := clWhite;
    case AState of
      0:
        begin
          LCanvas.RoundRect(P(8), P(8), P(15), P(15), P(2), P(2));
          LCanvas.Brush.Color := clWhite;
          LCanvas.FillRect(Rect(P(10), P(10), P(11), P(13)));
          LCanvas.FillRect(Rect(P(12), P(10), P(13), P(13)));
        end;
      1:
        LCanvas.Polygon([Point(P(9), P(8)), Point(P(15), P(11)), Point(P(9), P(15))]);
      2:
        begin
          LCanvas.Polygon([Point(P(11), P(7)), Point(P(15), P(15)), Point(P(7), P(15))]);
          LCanvas.Brush.Color := clWhite;
          LCanvas.FillRect(Rect(P(11), P(10), P(12), P(12)));
          LCanvas.FillRect(Rect(P(11), P(13), P(12), P(14)));
        end;
    end;
    LSmallBitmap := TBitmap.Create;
    LSmallBitmap.PixelFormat := pf24bit;
    LSmallBitmap.SetSize(ASize, ASize);
    Result := TPngImage.Create;
    Result.Assign(LSmallBitmap);
    Result.CreateAlpha;
    for LY := 0 to ASize - 1 do
    begin
      LTarget := Result.Scanline[LY];
      LAlpha := Result.AlphaScanline[LY];
      for LX := 0 to ASize - 1 do
      begin
        LRed := 0;
        LGreen := 0;
        LBlue := 0;
        LCoverage := 0;
        for LSampleY := 0 to 3 do
          for LSampleX := 0 to 3 do
          begin
            LSource := LBitmap.ScanLine[ASize * 4 - 1 - (LY * 4 + LSampleY)];
            Inc(LSource, LX * 4 + LSampleX);
            if (LSource.rgbtRed = 255) and (LSource.rgbtGreen = 0) and (LSource.rgbtBlue = 255) then
              Continue;
            Inc(LCoverage);
            Inc(LRed, LSource.rgbtRed);
            Inc(LGreen, LSource.rgbtGreen);
            Inc(LBlue, LSource.rgbtBlue);
          end;
        if LCoverage > 0 then
        begin
          LTarget[LX * 3] := LBlue div LCoverage;
          LTarget[LX * 3 + 1] := LGreen div LCoverage;
          LTarget[LX * 3 + 2] := LRed div LCoverage;
        end
        else
        begin
          LTarget[LX * 3] := 0;
          LTarget[LX * 3 + 1] := 0;
          LTarget[LX * 3 + 2] := 0;
        end;
        LAlpha[LX] := LCoverage * 255 div 16;
      end;
    end;
    LSuccess := True;
  finally
    if not LSuccess then
      Result.Free;
    LSmallBitmap.Free;
    LBitmap.Free;
  end;
end;

procedure TDAIToolbarController.InstallImages(const AServices: INTAServices; AImages: TCustomImageList);
var
  LGraphics: TGraphicArray;
  LState: Integer;
  LSize: Integer;
begin
  if (AImages.Width < 8) or (AImages.Height < 8) then
    raise EInvalidOperation.Create('Die IDE-Bildliste ist noch nicht bereit.');
  SetLength(LGraphics, Length(CDAIImageSizes));
  for LState := Low(FImages) to High(FImages) do
  begin
    try
      for LSize := Low(CDAIImageSizes) to High(CDAIImageSizes) do
        LGraphics[LSize] := CreateServerGlyph(LState, CDAIImageSizes[LSize]);
      // The modern IDE path copies all resolutions into its image collection.
      // Stable names deduplicate on reload; never delete shared image indices.
      FImages[LState] := AServices.AddImage(CDAIImageIds[LState], LGraphics);
      if (FImages[LState] < 0) or (FImages[LState] >= AImages.Count) then
        raise EInvalidOperation.Create('Die IDE hat kein gültiges DAI-Statusbild registriert.');
    finally
      for LSize := Low(LGraphics) to High(LGraphics) do
        FreeAndNil(LGraphics[LSize]);
    end;
  end;
end;

procedure TDAIToolbarController.CreatePopup;
begin
  // AddToolButton requires dropdown ownership to match its returned button.
  FPopup := TPopupMenu.Create(FButton.Owner);
  FPopup.Name := 'DAIServerPopupMenu';
  // VCL's automatic '&' insertion must not conflict with later status captions.
  FPopup.AutoHotkeys := maManual;
  FPopup.FreeNotification(Self);
  FToggleItem := TMenuItem.Create(FPopup);
  FToggleItem.FreeNotification(Self);
  FToggleItem.OnClick := ToggleServer;
  FPopup.Items.Add(FToggleItem);
  FOptionsItem := TMenuItem.Create(FPopup);
  FOptionsItem.FreeNotification(Self);
  FOptionsItem.Caption := 'DAI-&Optionen und Berechtigungen …';
  FOptionsItem.OnClick := OpenOptions;
  FPopup.Items.Add(FOptionsItem);
  FResetItem := TMenuItem.Create(FPopup);
  FResetItem.FreeNotification(Self);
  FResetItem.Caption := 'Sitzungsfreigaben &zurücksetzen';
  FResetItem.OnClick := ResetSessionPermissions;
  FPopup.Items.Add(FResetItem);
  FButton.DropdownMenu := FPopup;
end;

procedure TDAIToolbarController.EnsureOwnButtonFitsHorizontally;
var
  LParent: TWinControl;
  LHandle: HWND;
  LIndex: Integer;
  LPPI: Integer;
  LNativeButton: TTBButton;
  LButtonRect: TRect;
  LClientRect: TRect;
  LRequiredWidth: Int64;
begin
  RequireMainThread;
  if FShuttingDown then
    Exit;
  if not Assigned(FToolbar) or not Assigned(FButton) or not Assigned(FAction) or not Assigned(FPopup) then
    Exit;
  if FToolbar.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  if FButton.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  if csDestroying in FAction.ComponentState then
    Exit;
  if csDestroying in FPopup.ComponentState then
    Exit;
  if (FButton.Parent <> FToolbar) or (FButton.Action <> FAction) or (FButton.DropdownMenu <> FPopup) then
    Exit;
  // Never create an HWND merely to inspect layout during IDE restoration.
  if not FToolbar.HandleAllocated then
    Exit;
  LHandle := FToolbar.Handle;
  if not IsWindow(LHandle) then
    Exit;
  LIndex := FButton.Index;
  if LIndex < 0 then
    Exit;
  if SendMessage(LHandle, TB_BUTTONCOUNT, 0, 0) <= LIndex then
    Exit;
  LNativeButton := Default(TTBButton);
  if SendMessage(LHandle, TB_GETBUTTON, WPARAM(LIndex), LPARAM(@LNativeButton)) = 0 then
    Exit;
  if LNativeButton.dwData <> UIntPtr(FButton) then
    Exit;
  if (LNativeButton.fsState and TBSTATE_HIDDEN) <> 0 then
    Exit;
  LPPI := FToolbar.CurrentPPI;
  if LPPI <= 0 then
    Exit;
  if SendMessage(LHandle, TB_GETITEMRECT, WPARAM(LIndex), LPARAM(@LButtonRect)) = 0 then
    Exit;
  if not GetClientRect(LHandle, LClientRect) then
    Exit;
  if LButtonRect.Right <= LButtonRect.Left then
    Exit;
  if LClientRect.Right <= LClientRect.Left then
    Exit;
  if LButtonRect.Right <= LClientRect.Right then
    Exit;
  // VCL bounds, constraints and native client rectangles already use the
  // current DPI's pixels. Add the client deficit without scaling it again.
  LRequiredWidth := Int64(FToolbar.Width) + Int64(LButtonRect.Right) - Int64(LClientRect.Right);
  if LRequiredWidth < FToolbar.Constraints.MinWidth then
    LRequiredWidth := FToolbar.Constraints.MinWidth;
  if FToolbar.Constraints.MaxWidth > 0 then
    if LRequiredWidth > FToolbar.Constraints.MaxWidth then
      Exit;
  if (LRequiredWidth <= FToolbar.Width) or (LRequiredWidth > High(Integer)) then
    Exit;
  if FToolbar.CurrentPPI <> LPPI then
    Exit;
  // Width preserves Left, Top, Height, AutoSize and Wrapable. Call this only
  // after creation or positive restore adoption, never on ordinary refreshes.
  FToolbar.Width := Integer(LRequiredWidth);
  // Width requests alignment of this child only. The shared control bar also
  // needs a full band layout so toolbars to the right follow the new width.
  // Width changes can invoke callbacks which retire our UI; inspect it again.
  if FShuttingDown or not Assigned(FToolbar) then
    Exit;
  if FToolbar.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  LParent := FToolbar.Parent;
  if not Assigned(LParent) then
    Exit;
  if LParent.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  if LParent.HandleAllocated then
    LParent.Realign;
end;

procedure TDAIToolbarController.EnsureInstalled;
var
  LServices: INTAServices;
  LToolbar: TToolBar;
  LActionList: TCustomActionList;
  LImages: TCustomImageList;
  LControl: TControl;
  LRestored: TToolButton;
  LIndex: Integer;
begin
  EnsureReadNotifier;
  if not Supports(BorlandIDEServices, INTAServices, LServices) then
    Exit;
  LToolbar := LServices.ToolBar[sDebugToolBar];
  LActionList := LServices.ActionList;
  LImages := LServices.ImageList;
  if not Assigned(LToolbar) or not Assigned(LActionList) or not Assigned(LImages) then
  begin
    // A live capture can precede assignment of the public toolbar pointer.
    // Otherwise preserve the existing cleanup contract after host destruction.
    if not Assigned(FStreamCapture.Toolbar) then
      RemoveUI;
    Exit;
  end;
  if csDestroying in LToolbar.ComponentState then
    Exit;
  if csDestroying in LActionList.ComponentState then
    Exit;
  if Assigned(FAction) then
    if csDestroying in FAction.ComponentState then
      Exit;
  if LToolbar.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  LRestored := RestoredButton(LToolbar, LActionList);
  if Assigned(FToolbar) and Assigned(FActionList) and Assigned(FAction) and Assigned(FButton) and Assigned(FPopup) then
    if (FToolbar = LToolbar) and (FActionList = LActionList) then
      if not Assigned(LRestored) or (LRestored = FButton) then
      begin
        if Assigned(LRestored) then
        begin
          FButton.Name := CDAIButtonName;
          FButton.Action := FAction;
          FButton.DropdownMenu := FPopup;
          FStreamCapture.Consume;
          // Positive original-name evidence permits one historical single only
          // during this adoption. Subsequent Ready refreshes remain three..five.
          RemoveLegacyButtons(True);
          EnsureOwnButtonFitsHorizontally;
        end
        else
          RemoveLegacyButtons;
        Exit;
      end;
  if Assigned(LRestored) then
  begin
    // Protect the validated restored object while retiring our old action clients.
    LRestored.Action := nil;
    LRestored.DropdownMenu := nil;
    LRestored.OnClick := nil;
    if LRestored = FButton then
    begin
      FButton.RemoveFreeNotification(Self);
      FButton := nil;
    end;
  end;
  RemoveUI;
  if Assigned(LRestored) then
    if FStreamCapture.Button <> LRestored then
      LRestored := nil;
  for LIndex := 0 to LToolbar.ButtonCount - 1 do
    if LToolbar.Buttons[LIndex] <> LRestored then
      if SameText(LToolbar.Buttons[LIndex].Name, CDAIButtonName) then
        raise EInvalidOperation.Create('Der DAI-Schalter ist bereits durch eine andere Instanz registriert.');
  for LIndex := 0 to LActionList.ActionCount - 1 do
    if SameText(LActionList.Actions[LIndex].Name, CDAIActionName) then
      raise EInvalidOperation.Create('Die DAI-Aktion ist bereits durch eine andere Instanz registriert.');
  InstallImages(LServices, LImages);
  FToolbar := LToolbar;
  FToolbar.FreeNotification(Self);
  FActionList := LActionList;
  FActionList.FreeNotification(Self);
  try
    FAction := TAction.Create(FActionList.Owner);
    FAction.Name := CDAIActionName;
    FAction.Category := 'DAI';
    FAction.Caption := 'DAI inaktiv';
    FAction.ActionList := FActionList;
    FAction.ImageIndex := FImages[0];
    FAction.OnExecute := ToggleServer;
    FAction.FreeNotification(Self);
    if Assigned(LRestored) then
      FButton := LRestored
    else
    begin
      LControl := LServices.AddToolButton(sDebugToolBar, CDAIButtonName, FAction);
      if not (LControl is TToolButton) then
      begin
        LControl.Free;
        raise EInvalidOperation.Create('Die Debugger-Werkzeugleiste liefert keinen VCL-ToolButton.');
      end;
      FButton := TToolButton(LControl);
    end;
    FButton.FreeNotification(Self);
    FButton.Name := CDAIButtonName;
    FButton.Action := FAction;
    FButton.Style := tbsDropDown;
    FButton.ShowHint := True;
    FButton.ParentShowHint := False;
    CreatePopup;
    if Assigned(LRestored) then
    begin
      FStreamCapture.Consume;
      RemoveLegacyButtons(True);
    end
    else
      RemoveLegacyButtons;
    EnsureOwnButtonFitsHorizontally;
    FLastInstallError := '';
  except
    RemoveUI;
    raise;
  end;
end;

procedure TDAIToolbarController.UpdateStatus;
var
  LActive: Boolean;
  LError: string;
  LCaption: string;
  LHint: string;
  LCommand: string;
  LImage: Integer;
begin
  if not Assigned(FAction) or IDEMenuTracking then
    Exit;
  LActive := TDAIRuntime.ServerActive;
  LError := TDAIRuntime.LastServerError;
  if FActionError <> '' then
    LError := FActionError;
  if LActive then
  begin
    LCaption := 'DAI aktiv';
    LHint := Format('DAI aktiv auf Port %d. Klicken zum Stoppen.', [TDAIRuntime.ServerPort]);
    LCommand := 'Server &stoppen';
    LImage := FImages[1];
  end
  else
  begin
    LCaption := 'DAI inaktiv';
    LHint := Format('DAI inaktiv; kein aktiver Port. Klicken zum Starten mit gespeichertem Port %d.', [TDAISettings.Instance.Port]);
    LCommand := 'Server &starten';
    LImage := FImages[0];
  end;
  if LError <> '' then
  begin
    LCaption := 'DAI Fehler';
    LHint := LHint + sLineBreak + 'Fehler: ' + LError;
    LImage := FImages[2];
  end;
  if FBusy then
  begin
    LCaption := 'DAI …';
    LHint := 'DAI: Serverzustand wird geändert.';
  end;
  if FAction.Caption <> LCaption then
    FAction.Caption := LCaption;
  if FAction.Hint <> LHint then
    FAction.Hint := LHint;
  if FAction.ImageIndex <> LImage then
    FAction.ImageIndex := LImage;
  FAction.Enabled := not FBusy;
  if Assigned(FToggleItem) then
  begin
    if FToggleItem.Caption <> LCommand then
      FToggleItem.Caption := LCommand;
    if FToggleItem.Enabled <> not FBusy then
      FToggleItem.Enabled := not FBusy;
  end;
end;

procedure TDAIToolbarController.Refresh;
begin
  // Timers run inside TrackPopupMenu too. Leave all IDE menu/toolbar UI stable
  // until tracking ends; the next refresh then applies the latest state.
  if FShuttingDown or FRefreshing or IDEMenuTracking then
    Exit;
  if Application.Terminated or (csDestroying in Application.ComponentState) then
    Exit;
  Inc(FCallbackDepth);
  FRefreshing := True;
  try
    try
      EnsureInstalled;
      if not FShuttingDown then
        UpdateStatus;
    except
      on E: Exception do
        if not FShuttingDown then
          ReportError(E.ClassName + ': ' + E.Message);
    end;
  finally
    FRefreshing := False;
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.TimerTick(Sender: TObject);
begin
  Refresh;
end;

procedure TDAIToolbarController.ToggleServer(Sender: TObject);
var
  LResult: Boolean;
begin
  if FShuttingDown or FBusy then
    Exit;
  Inc(FCallbackDepth);
  FBusy := True;
  FActionError := '';
  try
    UpdateStatus;
    try
      if TDAIRuntime.ServerActive then
        LResult := TDAIRuntime.StopServer
      else
        LResult := TDAIRuntime.StartServer;
      if not LResult and (TDAIRuntime.LastServerError = '') then
        FActionError := 'Der Serverzustand konnte nicht geändert werden.';
    except
      on E: Exception do
        FActionError := E.ClassName + ': ' + E.Message;
    end;
  finally
    FBusy := False;
    if not FShuttingDown then
      UpdateStatus;
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.OpenOptions(Sender: TObject);
var
  LServices: IOTAServices;
  LOptions: IOTAEnvironmentOptions;
begin
  if FShuttingDown then
    Exit;
  Inc(FCallbackDepth);
  try
    if Supports(BorlandIDEServices, IOTAServices, LServices) then
    begin
      LOptions := LServices.GetEnvironmentOptions;
      if Assigned(LOptions) then
        LOptions.EditOptions('', 'DAI');
      LOptions := nil;
      LServices := nil;
    end;
  finally
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.ResetSessionPermissions(Sender: TObject);
begin
  if FShuttingDown then
    Exit;
  Inc(FCallbackDepth);
  try
    TDAIPermissionManager.Instance.ClearAllSessions;
  finally
    LeaveCallback;
  end;
end;

class procedure TDAIIDEToolbar.Install;
begin
  RequireMainThread;
  if not Assigned(GController) then
  begin
    GController := TDAIToolbarController.Create;
    // Register before toolbar desktop restoration; UI creation still waits.
    GController.ActivateReadHooks;
  end;
end;

class procedure TDAIIDEToolbar.Refresh;
begin
  RequireMainThread;
  if Assigned(GController) then
    GController.Refresh;
end;

class procedure TDAIIDEToolbar.Shutdown;
var
  LController: TDAIToolbarController;
begin
  RequireMainThread;
  LController := GController;
  GController := nil;
  if Assigned(LController) then
    LController.Shutdown;
end;

initialization

finalization
  TDAIIDEToolbar.Shutdown;

end.
