function ActualButtonRect(AButton: TToolButton): TRect;
var
  LToolbar: TToolBar;
  LNative: TTBButton;
begin
  Check(Assigned(AButton), 'Layout fixture has an actual own button');
  Check(AButton.Parent is TToolBar, 'Layout fixture button belongs to the native toolbar');
  LToolbar := TToolBar(AButton.Parent);
  Check(LToolbar.HandleAllocated, 'Native layout is inspected only with an already existing HWND');
  Check(SendMessage(LToolbar.Handle, TB_GETBUTTON, WPARAM(AButton.Index), LPARAM(@LNative)) <> 0,
    'Actual native button record exists at the public VCL index');
  Check(LNative.dwData = NativeUInt(Pointer(AButton)), 'Native layout refers to this exact VCL object');
  Check(SendMessage(LToolbar.Handle, TB_GETITEMRECT, WPARAM(AButton.Index), LPARAM(@Result)) <> 0,
    'Actual native common control returns the own item rectangle');
end;

procedure ConfigureFixedToolbar(AToolbar: TToolBar; const AWidth: Integer);
begin
  AToolbar.Align := alNone;
  AToolbar.AutoSize := False;
  AToolbar.Wrapable := False;
  AToolbar.ButtonWidth := 27;
  AToolbar.ButtonHeight := 28;
  AToolbar.SetBounds(11, 17, AWidth, 24);
end;

procedure CheckLayoutPreserved(AToolbar: TToolBar);
begin
  Check(AToolbar.Left = 11, 'Horizontal repair preserves toolbar Left');
  Check(AToolbar.Top = 17, 'Horizontal repair preserves toolbar Top');
  Check(AToolbar.Height = 24, 'Horizontal repair preserves the IDE toolbar height');
  Check(not AToolbar.AutoSize, 'Horizontal repair preserves AutoSize=False');
  Check(not AToolbar.Wrapable, 'Horizontal repair preserves Wrapable=False');
  Check(AToolbar.Align = alNone, 'Horizontal repair preserves the existing alignment');
end;

procedure TestInitialLayoutGrowth(const AWide: Boolean; const ALegacyCount: Integer = 0);
var
  LButton: TToolButton;
  LRect: TRect;
  LIndex: Integer;
  LOriginalWidth: Integer;
  LWidthAfterRepair: Integer;
begin
  NewHost;
  GHost.Form.Width := 1200;
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  // Eight native standard buttons reproduce the last debugger anchor followed
  // by our dropdown, rather than assuming the width of a drawn icon.
  for LIndex := 1 to 7 do
  begin
    LButton := TToolButton.Create(GHost.Form);
    LButton.Left := GHost.Toolbar.ButtonCount * 64;
    LButton.Parent := GHost.Toolbar;
  end;
  GHost.ForeignButton.Left := GHost.Toolbar.ButtonCount * 64;
  LOriginalWidth := 218;
  if AWide then
    LOriginalWidth := 900;
  ConfigureFixedToolbar(GHost.Toolbar, LOriginalWidth);
  for LIndex := 1 to ALegacyCount do
    NewInertDropdown(GHost.Form, GHost.Toolbar);
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LButton := GHost.DAIButton;
  Check(LButton.Style = tbsDropDown, 'Growth measures the real dropdown style, including its arrow');
  Check(Assigned(LButton.DropdownMenu), 'Growth happens after assigning the actual own popup');
  Check(GHost.Toolbar.ButtonCount = 9, 'Legacy migration completes before measuring the final own dropdown');
  LRect := ActualButtonRect(LButton);
  Check(LRect.Right <= GHost.Toolbar.ClientWidth, 'Own native rectangle fits horizontally within the repaired client area');
  CheckLayoutPreserved(GHost.Toolbar);
  if AWide then
    Check(GHost.Toolbar.Width = LOriginalWidth, 'Existing broad toolbar is never shrunk')
  else
    Check(GHost.Toolbar.Width > LOriginalWidth, 'The observed fixed-width toolbar grows only when necessary');
  LWidthAfterRepair := GHost.Toolbar.Width;
  TDAIIDEToolbar.Refresh;
  Check(GHost.Toolbar.Width = LWidthAfterRepair, 'Ordinary ready-state refresh does not resize an already installed toolbar');
  GHost.Toolbar.Width := 218;
  LRect := ActualButtonRect(LButton);
  Check(LRect.Right > GHost.Toolbar.ClientWidth, 'Fixture can independently reproduce the original clipping geometry');
  TDAIIDEToolbar.Refresh;
  Check(GHost.Toolbar.Width = 218, 'User narrowing after install is preserved by ordinary periodic refresh');
  TDAIIDEToolbar.Shutdown;
end;

procedure TestRestoredLayoutGrowth(const ALegacyCount: Integer; const AReload: Boolean);
var
  LStream: TMemoryStream;
  LRestored: TToolButton;
  LRect: TRect;
  LWidth: Integer;
begin
  NewHost;
  GHost.Form.Width := 1200;
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  LStream := BuildToolbarStream(ALegacyCount, 1, False, True);
  try
    TDAIIDEToolbar.Install;
    if AReload then
      TDAIIDEToolbar.Refresh;
    // Stock TToolBar constructs with alTop, unlike the IDE's dock toolbar. Defer
    // host alignment until its serialized alNone and fixed bounds are loaded.
    ReadToolbarStream(LStream, True);
    LRestored := GHost.LastReadButton;
    Check(GHost.Toolbar.Width = 218, Format('Real stream restores fixed native width (actual %d)', [GHost.Toolbar.Width]));
    CheckLayoutPreserved(GHost.Toolbar);
    LRect := ActualButtonRect(LRestored);
    Check(LRect.Right > GHost.Toolbar.ClientWidth, 'Real restored own dropdown begins horizontally clipped');
    TDAIIDEToolbar.Refresh;
    Check(GHost.DAIButton = LRestored, 'Layout repair reuses the positively captured original-name object');
    Check(GHost.Toolbar.ButtonCount = 9, 'Restored legacy cleanup finishes before final layout repair');
    LRect := ActualButtonRect(LRestored);
    Check(LRect.Right <= GHost.Toolbar.ClientWidth, 'Reused native own button fits after horizontal repair');
    CheckLayoutPreserved(GHost.Toolbar);
    LWidth := GHost.Toolbar.Width;
    TDAIIDEToolbar.Refresh;
    Check(GHost.Toolbar.Width = LWidth, 'Reused toolbar is not periodically resized after adoption');
    TDAIIDEToolbar.Shutdown;
  finally
    LStream.Free;
  end;
end;

type
  TLayoutControlBar = class(TControlBar)
  public
    FullAlignments: Integer;
  protected
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
  end;

procedure TLayoutControlBar.AlignControls(AControl: TControl; var ARect: TRect);
begin
  if AControl = nil then
    Inc(FullAlignments);
  inherited;
end;

procedure TestAdjacentToolbarGrowth(const AWide: Boolean);
var
  LBar: TLayoutControlBar;
  LNext: TToolBar;
  LButton: TToolButton;
  LIndex: Integer;
  LBefore: Integer;
  LAlignments: Integer;
  LWidth: Integer;
  LRect: TRect;
begin
  NewHost;
  GHost.Form.Width := 1200;
  LBar := TLayoutControlBar.Create(GHost.Form);
  LBar.Parent := GHost.Form;
  LBar.SetBounds(0, 0, 1100, 70);
  LBar.HandleNeeded;
  ConfigureFixedToolbar(GHost.Toolbar, 218);
  GHost.Toolbar.Parent := LBar;
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  for LIndex := 1 to 7 do
  begin
    LButton := TToolButton.Create(GHost.Form);
    LButton.Left := GHost.Toolbar.ButtonCount * 64;
    LButton.Parent := GHost.Toolbar;
  end;
  LWidth := 218;
  if AWide then
    LWidth := 400;
  GHost.Toolbar.SetBounds(11, 2, LWidth, 24);
  LNext := TToolBar.Create(GHost.Form);
  LNext.Align := alNone;
  LNext.AutoSize := False;
  LNext.Wrapable := False;
  LNext.SetBounds(LWidth + 27, 2, 332, 28);
  LNext.Parent := LBar;
  LBar.Realign;
  LBefore := LNext.Left;
  LAlignments := LBar.FullAlignments;
  Check(LNext.Left >= GHost.Toolbar.Left + GHost.Toolbar.Width, 'Adjacent bars start without overlap');
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LRect := ActualButtonRect(GHost.DAIButton);
  Check(LRect.Right <= GHost.Toolbar.ClientWidth, 'Docked own button fits within its native toolbar');
  Check(LNext.Left >= GHost.Toolbar.Left + GHost.Toolbar.Width, 'Growing the docked toolbar moves its right neighbour clear');
  if AWide then
    Check(LNext.Left = LBefore, 'An already wide toolbar does not move its neighbour')
  else
    Check(LNext.Left > LBefore, 'The neighbouring toolbar follows the required horizontal growth');
  Check(LNext.Width = 332, 'Neighbouring toolbar width is preserved');
  if AWide then
    Check(LBar.FullAlignments = LAlignments, 'An already wide toolbar does not request a complete parent layout')
  else
    Check(LBar.FullAlignments > LAlignments, 'Growth requests a complete parent band layout, not only alignment of the changed child');
  LAlignments := LBar.FullAlignments;
  LBefore := LNext.Left;
  TDAIIDEToolbar.Refresh;
  Check(LBar.FullAlignments = LAlignments, 'Ordinary status refresh does not realign unrelated toolbars');
  Check(LNext.Left = LBefore, 'Ordinary status refresh preserves the neighbouring toolbar position');
  TDAIIDEToolbar.Shutdown;
end;

procedure TestToolbarLayoutGrowth;
begin
  TestAdjacentToolbarGrowth(False);
  TestAdjacentToolbarGrowth(True);
  System.Classes.RegisterClass(TToolBar);
  System.Classes.RegisterClass(TToolButton);
  TestInitialLayoutGrowth(False);
  TestInitialLayoutGrowth(True);
  TestInitialLayoutGrowth(False, 3);
  TestRestoredLayoutGrowth(0, False);
  TestRestoredLayoutGrowth(0, True);
  TestRestoredLayoutGrowth(1, True);
  TestRestoredLayoutGrowth(3, True);
end;
