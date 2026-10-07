type
  TPopupItemSnapshot = record
    Caption: string;
    NativeCaption: string;
    NativeState: UINT;
    Bounds: TRect;
  end;

  TPopupStabilityProbe = class
  private
    FTimer: TTimer;
    FPopup: TPopupMenu;
    FStarted: UInt64;
    FNativeMenu: HMENU;
    FItems: TArray<TPopupItemSnapshot>;
    FInitialCaption: string;
    FInitialHint: string;
    FInitialImage: Integer;
    FChangeRuntime: Boolean;
    FRuntimeChanged: Boolean;
    procedure Tick(Sender: TObject);
    procedure Cancel;
    function NativeItem(const AIndex: Integer): TPopupItemSnapshot;
    procedure Capture;
    procedure CheckStable;
  public
    Failure: string;
    TrackingTicks: Integer;
    constructor Create(APopup: TPopupMenu; const AChangeRuntime: Boolean);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TPopupStabilityProbe.Create(APopup: TPopupMenu; const AChangeRuntime: Boolean);
begin
  inherited Create;
  FPopup := APopup;
  FChangeRuntime := AChangeRuntime;
  FInitialCaption := GHost.DAIAction.Caption;
  FInitialHint := GHost.DAIAction.Hint;
  FInitialImage := GHost.DAIAction.ImageIndex;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
end;

destructor TPopupStabilityProbe.Destroy;
begin
  FTimer.Free;
  inherited;
end;

procedure TPopupStabilityProbe.Cancel;
var
  LInfo: TGUIThreadInfo;
begin
  FTimer.Enabled := False;
  EndMenu;
  LInfo := Default(TGUIThreadInfo);
  LInfo.cbSize := SizeOf(LInfo);
  if GetGUIThreadInfo(MainThreadID, LInfo) and (LInfo.hwndMenuOwner <> 0) then
    PostMessage(LInfo.hwndMenuOwner, WM_CANCELMODE, 0, 0);
end;

function TPopupStabilityProbe.NativeItem(const AIndex: Integer): TPopupItemSnapshot;
var
  LInfo: TMenuItemInfo;
  LText: array[0..1023] of Char;
begin
  Result := Default(TPopupItemSnapshot);
  Result.Caption := FPopup.Items[AIndex].Caption;
  LInfo := Default(TMenuItemInfo);
  LInfo.cbSize := SizeOf(LInfo);
  LInfo.fMask := MIIM_STRING or MIIM_STATE;
  LInfo.dwTypeData := @LText[0];
  LInfo.cch := Length(LText);
  Check(GetMenuItemInfo(FNativeMenu, AIndex, True, LInfo), 'Native popup item exists during tracking');
  Result.NativeCaption := string(LText);
  Result.NativeState := LInfo.fState and not MFS_HILITE;
  Check(GetMenuItemRect(0, FNativeMenu, AIndex, Result.Bounds), 'Native popup item has visible bounds');
  Check((Result.Bounds.Right > Result.Bounds.Left) and (Result.Bounds.Bottom > Result.Bounds.Top),
    'Displayed popup item keeps a positive native rectangle');
end;

procedure TPopupStabilityProbe.Capture;
var
  LIndex: Integer;
begin
  FNativeMenu := FPopup.Handle;
  Check(IsMenu(FNativeMenu), 'The probe tracks a real native HMENU');
  Check(GetMenuItemCount(FNativeMenu) = FPopup.Items.Count, 'Every VCL item is present in the displayed native menu');
  SetLength(FItems, FPopup.Items.Count);
  for LIndex := 0 to High(FItems) do
    FItems[LIndex] := NativeItem(LIndex);
end;

procedure TPopupStabilityProbe.CheckStable;
var
  LIndex: Integer;
  LItem: TPopupItemSnapshot;
begin
  for LIndex := 0 to High(FItems) do
    Check(FPopup.Items[LIndex].Caption = FItems[LIndex].Caption,
      Format('Displayed popup caption remains stable across the status timer: "%s" -> "%s"',
        [FItems[LIndex].Caption, FPopup.Items[LIndex].Caption]));
  Check(IsMenu(FNativeMenu), 'The displayed native menu is not destroyed by a status refresh');
  Check(FPopup.Handle = FNativeMenu, 'The same native HMENU remains active until the popup closes');
  Check(GetMenuItemCount(FNativeMenu) = Length(FItems), 'The displayed menu retains every native item');
  for LIndex := 0 to High(FItems) do
  begin
    LItem := NativeItem(LIndex);
    Check(LItem.NativeCaption = FItems[LIndex].NativeCaption, 'Native popup text is unchanged while displayed');
    Check(LItem.NativeState = FItems[LIndex].NativeState, 'Native popup enabled/checked state is unchanged while displayed');
    Check(EqualRect(LItem.Bounds, FItems[LIndex].Bounds), 'Native menu item bounds remain stable while displayed');
  end;
  Check(GHost.DAIAction.Caption = FInitialCaption, 'Status caption is deferred while any popup is tracking');
  Check(GHost.DAIAction.Hint = FInitialHint, 'Status hint is deferred while any popup is tracking');
  Check(GHost.DAIAction.ImageIndex = FInitialImage, 'Toolbar icon is deferred while any popup is tracking');
end;

procedure TPopupStabilityProbe.Tick(Sender: TObject);
var
  LInfo: TGUIThreadInfo;
  LElapsed: UInt64;
begin
  // Exceptions must be caught here: an uncaught VCL timer exception displays a
  // modal error dialog instead of failing this isolated console test.
  try
    LElapsed := GetTickCount64 - FStarted;
    LInfo := Default(TGUIThreadInfo);
    LInfo.cbSize := SizeOf(LInfo);
    Check(GetGUIThreadInfo(MainThreadID, LInfo), 'The native GUI state can be queried on the fixture main thread');
    if LInfo.flags and (GUI_INMENUMODE or GUI_POPUPMENUMODE or GUI_SYSTEMMENUMODE) = 0 then
    begin
      Check(LElapsed < 2200, 'The bounded fixture must enter a native menu tracking loop');
      Exit;
    end;
    Inc(TrackingTicks);
    if TrackingTicks = 1 then
      Capture
    else
      CheckStable;
    if FChangeRuntime and not FRuntimeChanged and (LElapsed >= 200) then
    begin
      TDAIRuntime.Active := True;
      TDAIRuntime.Port := 7444;
      TDAIRuntime.HasMCPAccess := True;
      TDAIRuntime.MCPAccessAgeMs := 0;
      FRuntimeChanged := True;
      TDAIIDEToolbar.Refresh;
      CheckStable;
    end;
    if LElapsed >= 1100 then
      Cancel;
  except
    on E: Exception do
    begin
      Failure := E.ClassName + ': ' + E.Message;
      Cancel;
    end;
  end;
end;

procedure TPopupStabilityProbe.Run;
var
  LPoint: TPoint;
begin
  GHost.Form.HandleNeeded;
  FPopup.PopupComponent := GHost.DAIButton;
  LPoint := GHost.Form.ClientToScreen(Point(40, 40));
  FStarted := GetTickCount64;
  FTimer.Enabled := True;
  try
    FPopup.Popup(LPoint.X, LPoint.Y);
  finally
    FTimer.Enabled := False;
  end;
  Check(Failure = '', Failure);
  Check(TrackingTicks >= 8, 'Native tracking spans at least two 500-ms production timer intervals');
  if FChangeRuntime then
  begin
    Check(FRuntimeChanged, 'Runtime status changes while the popup is open');
    PumpFor(650);
    Check(GHost.DAIAction.Caption = 'DAI aktiv', 'Deferred status is applied by the first timer tick after popup close');
    Check(Pos('7444', GHost.DAIAction.Hint) > 0, 'Deferred live port is applied after popup close');
    Check(Pos('ServerGlyph.v3.RecentAccess', GHost.DAIAction.ImageName) > 0, 'Deferred recent activity is applied after popup close');
  end;
end;

procedure TestPopupTracking(const AForeignPopup, AChangeRuntime: Boolean);
var
  LPopup: TPopupMenu;
  LProbe: TPopupStabilityProbe;
  LItem: TMenuItem;
  LIndex: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LPopup := GHost.DAIButton.DropdownMenu;
  if AForeignPopup then
  begin
    LPopup := TPopupMenu.Create(GHost.Form);
    LPopup.AutoHotkeys := maManual;
    for LIndex := 0 to 2 do
    begin
      LItem := TMenuItem.Create(LPopup);
      LItem.Caption := Format('Foreign IDE recent project %d', [LIndex]);
      LPopup.Items.Add(LItem);
    end;
  end;
  LProbe := TPopupStabilityProbe.Create(LPopup, AChangeRuntime);
  try
    LProbe.Run;
  finally
    LProbe.Free;
    if AForeignPopup then
      LPopup.Free;
  end;
  // A dismissed and stable native popup must retain all original callbacks.
  GHost.DAIButton.DropdownMenu.Items[0].Click;
  if AChangeRuntime then
    Check(TDAIRuntime.StopCount = 1, 'The preserved popup callback stops the changed live runtime')
  else
    Check(TDAIRuntime.StartCount = 1, 'The preserved popup callback starts an inactive runtime');
  GHost.DAIButton.DropdownMenu.Items[1].Click;
  Check(GHost.OptionsCount = 1, 'The preserved options entry still invokes the official IDE service');
  GHost.DAIButton.DropdownMenu.Items[2].Click;
  Check(TDAIPermissionManager.ClearCount = 1, 'The preserved permission-reset entry still invokes its callback');
  TDAIIDEToolbar.Shutdown;
end;

procedure TestToolbarPopup;
begin
  TestPopupTracking(False, False);
  TestPopupTracking(False, True);
  TestPopupTracking(True, True);
end;
