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
    FChangeRegistration: Boolean;
    FChangeUpdate: Boolean;
    FChangePermissions: Boolean;
    FUpdateChanged: Boolean;
    FRegistrationChanged: Boolean;
    FInitialHealthCount: Integer;
    FRuntimeChanged: Boolean;
    FPermissionsChanged: Boolean;
    FInitialPermissionCount: Integer;
    procedure Tick(Sender: TObject);
    procedure Cancel;
    function NativeItem(const AIndex: Integer): TPopupItemSnapshot;
    procedure Capture;
    procedure CheckStable;
  public
    Failure: string;
    TrackingTicks: Integer;
    constructor Create(APopup: TPopupMenu; const AChangeRuntime, AChangeRegistration, AChangeUpdate, AChangePermissions: Boolean);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TPopupStabilityProbe.Create(APopup: TPopupMenu; const AChangeRuntime, AChangeRegistration, AChangeUpdate, AChangePermissions: Boolean);
begin
  inherited Create;
  FPopup := APopup;
  FChangeRuntime := AChangeRuntime;
  FChangeRegistration := AChangeRegistration;
  FChangeUpdate := AChangeUpdate;
  FChangePermissions := AChangePermissions;
  FInitialHealthCount := TDAIClientRegistration.HealthCount;
  FInitialPermissionCount := TDAIPermissionManager.SummaryCount;
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
  LText[0] := #0;
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
    if FChangeRegistration and not FRegistrationChanged and (LElapsed >= 200) then
    begin
      TDAIClientRegistration.HealthState := rhNotRegistered;
      TDAIClientRegistration.HealthDetails := 'Registration removed while the native popup is tracking.';
      Inc(TDAIClientRegistration.Version);
      FRegistrationChanged := True;
      TDAIIDEToolbar.CheckRegistrations;
      CheckStable;
    end;
    if FChangeUpdate and not FUpdateChanged and (LElapsed >= 200) then
    begin
      FUpdateChanged := True;
      TDAIIDEToolbar.SetUpdateAvailable(True, '4.0.0');
      CheckStable;
    end;
    if FChangePermissions and not FPermissionsChanged and (LElapsed >= 200) then
    begin
      TDAIPermissionManager.IDESummary := 'schreiben';
      TDAIPermissionManager.ProjectSummary := 'Vollzugriff';
      TDAIOTA.ActiveProjectName := 'C:\ToolbarFixture\Deferred.dproj';
      Inc(TDAIPermissionManager.Version);
      FPermissionsChanged := True;
      TDAIIDEToolbar.Refresh;
      CheckStable;
    end;
    if FChangePermissions then
      Check(TDAIPermissionManager.SummaryCount = FInitialPermissionCount, 'Permission IO is deferred throughout native popup tracking');
    if FChangeRegistration or FChangeUpdate then
      Check(TDAIClientRegistration.HealthCount = FInitialHealthCount, 'Registration IO is deferred throughout native popup tracking');
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
  if FChangeRegistration then
  begin
    Check(FRegistrationChanged, 'The registration changes while the popup is tracking');
    PumpFor(650);
    Check(TDAIClientRegistration.HealthCount = FInitialHealthCount + 1, 'One registration scan runs after native popup close');
    CheckHealthGlyph('Inactive', 'Deferred registration diagnostics do not override Pause after native popup close');
    Check(Pos(TDAIClientRegistration.HealthDetails, GHost.DAIAction.Hint) > 0, 'Deferred registration details appear after native popup close');
  end;
  if FChangeUpdate then
  begin
    Check(FUpdateChanged, 'The software-update flag changes while the popup is tracking');
    PumpFor(650);
    Check(TDAIClientRegistration.HealthCount = FInitialHealthCount, 'A software update does not rescan registrations after popup close');
    CheckHealthGlyph('Inactive', 'The deferred software-update notice does not override Pause after native popup close');
    CheckUpdateHint('4.0.0');
  end;
  if FChangeRuntime then
  begin
    Check(FRuntimeChanged, 'Runtime status changes while the popup is open');
    PumpFor(650);
    Check(GHost.DAIAction.Caption = 'DAI aktiv', 'Deferred status is applied by the first timer tick after popup close');
    Check(Pos('7444', GHost.DAIAction.Hint) > 0, 'Deferred live port is applied after popup close');
    Check(Pos('ServerGlyph.v4.RecentAccess', GHost.DAIAction.ImageName) > 0, 'Deferred recent activity is applied after popup close');
  end;
  if FChangePermissions then
  begin
    Check(FPermissionsChanged, 'Effective permissions change while the native popup is tracking');
    PumpFor(650);
    Check(TDAIPermissionManager.SummaryCount = FInitialPermissionCount + 2, 'Permission summaries refresh once after native popup close');
    Check(GHost.DAIButton.DropdownMenu.Items[4].Caption = 'IDE : schreiben', 'The IDE permission caption updates after popup close');
    Check(GHost.DAIButton.DropdownMenu.Items[5].Caption = 'Projekt : Vollzugriff', 'The project permission caption updates after popup close');
  end;
end;

procedure TestPopupTracking(const AForeignPopup, AChangeRuntime: Boolean;
  const AChangeRegistration: Boolean = False; const AChangeUpdate: Boolean = False; const AChangePermissions: Boolean = False);
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
  LProbe := TPopupStabilityProbe.Create(LPopup, AChangeRuntime, AChangeRegistration, AChangeUpdate, AChangePermissions);
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

procedure TestIndexMenu;
var
  LPopup: TPopupMenu;
  LIndex: Integer;
  LShowCount: Integer;
  LScreenCursor: TCursor;
  LNativeCursor: HCURSOR;
begin
  NewHost;
  TDAISymbolService.Reset;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LPopup := GHost.DAIButton.DropdownMenu;
  Check(LPopup.Items.Count = 12, 'Index entries follow the existing commands and permission shortcuts at the bottom');
  Check(LPopup.Items[3].IsLine, 'Permission shortcuts retain their own separator');
  Check(LPopup.Items[4].Caption = 'IDE : lesen', 'The IDE permission shortcut precedes the index section');
  Check(LPopup.Items[5].Caption = 'Projekt : kein Projekt', 'The project permission shortcut precedes the index section');
  Check(LPopup.Items[6].IsLine, 'Index entries begin with their own separator after the permission shortcuts');
  Check(LPopup.Items[7].Caption = 'Index: Delphi / ToolsAPI', 'The final index section starts with Delphi sources');
  Check(LPopup.Items[11].Caption = 'Indizes verwalten …', 'Index management remains the last menu entry');
  Check(Assigned(LPopup.OnPopup), 'Index availability is refreshed only when opening the menu');
  Check(TDAISymbolService.ListCount = 0, 'Toolbar installation performs no index IO');
  PumpFor(650);
  Check(TDAISymbolService.ListCount = 0, 'The 500-ms status timer performs no index IO');
  LScreenCursor := Screen.Cursor;
  LNativeCursor := Winapi.Windows.GetCursor;
  try
    Winapi.Windows.SetCursor(Screen.Cursors[crIBeam]);
    LPopup.OnPopup(LPopup);
    Check(Winapi.Windows.GetCursor = Screen.Cursors[crArrow], 'Opening replaces a native editor text cursor with the menu arrow');
    Check(Screen.Cursor = LScreenCursor, 'Opening preserves the global VCL cursor policy');
  finally
    Winapi.Windows.SetCursor(LNativeCursor);
  end;
  Check(TDAISymbolService.ListCount = 1, 'Opening the popup reads one index snapshot');
  Check(LPopup.Items[7].Enabled and LPopup.Items[8].Enabled, 'Reference index managers can be opened before creating their indices');
  Check(not LPopup.Items[9].Enabled and not LPopup.Items[10].Enabled, 'Missing project and group indices have disabled individual entries');
  Check(LPopup.Items[11].Enabled, 'Index manager remains available for explicit creation');
  TDAISymbolService.Existing[2] := True;
  TDAISymbolService.Existing[3] := True;
  LPopup.OnPopup(LPopup);
  Check(LPopup.Items[9].Enabled and LPopup.Items[10].Enabled, 'Existing project and group indices can be selected');
  LShowCount := TDAISymbolIndexDialog.ShowCount;
  for LIndex := 7 to 10 do
  begin
    LPopup.Items[LIndex].Click;
    Check(TDAISymbolIndexDialog.ShowCount = LShowCount + LIndex - 6, 'Clicking an index opens the modeless manager once');
    case LIndex of
      7: Check(TDAISymbolIndexDialog.LastScope = 'delphi', 'Delphi entry selects its scope');
      8: Check(TDAISymbolIndexDialog.LastScope = 'getit', 'GetIt entry selects its scope');
      9: Check(TDAISymbolIndexDialog.LastScope = 'group', 'Group entry selects its scope');
      10: Check(TDAISymbolIndexDialog.LastScope = 'project', 'Project entry selects its scope');
    end;
  end;
  LPopup.Items[11].Click;
  Check(TDAISymbolIndexDialog.LastScope = '', 'General manager entry preserves its previous selection');
  Check(TDAISymbolService.BuildCount = 0, 'Menu navigation never creates an index');
  TDAISymbolService.FailListing := True;
  LPopup.OnPopup(LPopup);
  Check(LPopup.Items[11].Enabled, 'The index manager remains accessible after a listing error');
  Check(not LPopup.Items[9].Enabled and not LPopup.Items[10].Enabled, 'A failed refresh clears stale project index availability');
  TDAISymbolService.Reset;
end;

procedure TestLocalizedToolbar;
const
  CInactive: array[TDAILanguage] of string = ('DAI inactive', 'DAI inaktiv', 'DAI inactif', 'DAI 停止中');
  CStart: array[TDAILanguage] of string = ('&Start server', 'Server &starten', '&Démarrer le serveur', 'サーバーを起動');
  CManage: array[TDAILanguage] of string = ('Manage indexes …', 'Indizes verwalten …', 'Gérer les index …', 'インデックスの管理 …');
  CGroup: array[TDAILanguage] of string =
    ('Index: Project group', 'Index: Projektgruppe', 'Index : Groupe de projets', 'インデックス: プロジェクトグループ');
  CRead: array[TDAILanguage] of string = ('IDE : read', 'IDE : lesen', 'IDE : lecture', 'IDE : 読み取り');
  CNoProject: array[TDAILanguage] of string =
    ('Project : no project', 'Projekt : kein Projekt', 'Projet : aucun projet', 'プロジェクト : プロジェクトなし');
  CFull: array[TDAILanguage] of string = ('IDE : full access', 'IDE : Vollzugriff', 'IDE : accès complet', 'IDE : フルアクセス');
  CHealth: array[TDAILanguage] of string =
    ('Update the registration or launcher.', 'Registrierung oder Starthelfer aktualisieren.',
    'Mettez à jour l’inscription ou le lanceur.', '登録または起動ヘルパーを更新してください。');
var
  LPopup: TPopupMenu;
  LInfo: TMenuItemInfo;
  LNativeText: array[0..255] of Char;
begin
  try
    for var LLanguage := Low(TDAILanguage) to High(TDAILanguage) do
    begin
      DAISetLanguageForTests(LLanguage);
      NewHost;
      TDAISymbolService.Reset;
      TDAIIDEToolbar.Install;
      TDAIIDEToolbar.Refresh;
      LPopup := GHost.DAIButton.DropdownMenu;
      Check(GHost.DAIAction.Caption = CInactive[LLanguage], 'Toolbar state uses the selected language');
      Check(LPopup.Items[0].Caption = CStart[LLanguage], 'The server menu command uses the selected language');
      Check(LPopup.Items[4].Caption = CRead[LLanguage], 'Known permission summaries are localized for display');
      Check(LPopup.Items[5].Caption = CNoProject[LLanguage], 'The absent-project permission caption is localized');
      Check(LPopup.Items[9].Caption = CGroup[LLanguage], 'Index scope menu labels use the selected language');
      Check(LPopup.Items[11].Caption = CManage[LLanguage], 'The index manager menu command is localized');
      Check(TDAISymbolService.ListCount = 0, 'Localized toolbar installation performs no index scan');
      LPopup.OnPopup(LPopup);
      LPopup.Items[7].Click;
      Check(TDAISymbolIndexDialog.LastScope = 'delphi', 'Localized navigation retains the technical scope token');
      Check(TDAISymbolService.BuildCount = 0, 'Localized menu navigation never builds an index');
      LInfo := Default(TMenuItemInfo);
      LInfo.cbSize := SizeOf(LInfo);
      LInfo.fMask := MIIM_STRING;
      LInfo.dwTypeData := @LNativeText[0];
      LInfo.cch := Length(LNativeText);
      Check(GetMenuItemInfo(LPopup.Handle, 11, True, LInfo), 'The localized command has a native menu item');
      Check(string(LNativeText) = CManage[LLanguage], 'The native menu retains the complete Unicode caption');
      Check(Pos(#$FFFD, GHost.DAIAction.Hint) = 0, 'Localized status hints contain valid Unicode text');
      TDAIPermissionManager.IDESummary := 'Vollzugriff';
      Inc(TDAIPermissionManager.Version);
      TDAIClientRegistration.HealthDetails := 'Claude Desktop: Registrierung oder Starthelfer aktualisieren.';
      TDAIClientRegistration.HealthState := rhUpdateRecommended;
      Inc(TDAIClientRegistration.Version);
      TDAIIDEToolbar.Refresh;
      Check(LPopup.Items[4].Caption = CFull[LLanguage], 'Changed effective permission summaries keep localized captions');
      Check(TDAIPermissionManager.IDESummary = 'Vollzugriff', 'Localization does not change permission data');
      Check(Pos('Claude Desktop: ' + CHealth[LLanguage], GHost.DAIAction.Hint) > 0,
        'Authored registration hints are localized while the technical client name is preserved');
      TDAIIDEToolbar.Shutdown;
    end;
  finally
    TDAIIDEToolbar.Shutdown;
    DAISetLanguageForTests(dlGerman);
  end;
end;

procedure TestToolbarPopup;
begin
  TestIndexMenu;
  TestLocalizedToolbar;
  TestPopupTracking(False, False);
  TestPopupTracking(False, True);
  TestPopupTracking(True, True);
  TestPopupTracking(False, False, True);
  TestPopupTracking(True, False, True);
  TestPopupTracking(False, False, False, True);
  TestPopupTracking(False, False, False, False, True);
end;
