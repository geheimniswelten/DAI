function BuildToolbarStream(const ALegacyCount, AOwnCount: Integer; const AForeignLink: Boolean = False; const AFixedLayout: Boolean = False;
  const AMarker: NativeInt = 0; const AAnonymous: Boolean = False; const AInterposedMac: Boolean = False): TMemoryStream;
var
  LOwner: TForm;
  LToolbar: TToolBar;
  LAnchorAction: TAction;
  LAction: TAction;
  LPopup: TPopupMenu;
  LButton: TToolButton;
  LWriter: TWriter;
  LText: TStringStream;
  LInput: TStringStream;
  LIndex: Integer;
  LNames: string;
begin
  Result := TMemoryStream.Create;
  LOwner := TForm.CreateNew(nil);
  try
    LOwner.Name := 'TestIDE';
    LToolbar := TToolBar.Create(LOwner);
    LToolbar.Name := sDebugToolBar;
    LToolbar.Parent := LOwner;
    if AFixedLayout then
    begin
      LToolbar.Align := alNone;
      LToolbar.AutoSize := False;
      LToolbar.Wrapable := False;
      LToolbar.ButtonWidth := 27;
      LToolbar.ButtonHeight := 28;
      LToolbar.SetBounds(11, 17, 218, 24);
      for LIndex := 1 to 7 do
      begin
        LButton := TToolButton.Create(LOwner);
        LButton.Name := 'SyntheticStandardButton' + IntToStr(LIndex);
        LButton.Left := LToolbar.ButtonCount * 64;
        LButton.Parent := LToolbar;
      end;
    end;
    LAnchorAction := TAction.Create(LOwner);
    LAnchorAction.Name := 'RunUntilReturnCommand';
    LButton := TToolButton.Create(LOwner);
    LButton.Name := 'SyntheticAnchorButton';
    LButton.Left := LToolbar.ButtonCount * 64;
    LButton.Parent := LToolbar;
    LButton.Action := LAnchorAction;
    for LIndex := 1 to ALegacyCount do
      NewInertDropdown(LOwner, LToolbar);
    if AInterposedMac then
    begin
      LButton := NewInertDropdown(LOwner, LToolbar);
      LButton.Name := 'h5uDMacStatusButton';
      LButton.Tag := $444D4143;
    end;
    LAction := TAction.Create(LOwner);
    if AForeignLink then
      LAction.Name := 'RunUntilReturnCommandForeign'
    else
      LAction.Name := 'DAIServerToggleAction';
    LPopup := TPopupMenu.Create(LOwner);
    LPopup.Name := 'DAIServerPopupMenu';
    for LIndex := 1 to AOwnCount do
    begin
      LButton := TToolButton.Create(LOwner);
      if LIndex = 1 then
        LButton.Name := 'DAIServerToolButton'
      else
        LButton.Name := 'DAIServerToolButtonDuplicate';
      LButton.Left := LToolbar.ButtonCount * 64;
      LButton.Parent := LToolbar;
      LButton.Style := tbsDropDown;
      LButton.Action := LAction;
      LButton.DropdownMenu := LPopup;
      LButton.ParentShowHint := False;
      LButton.ShowHint := True;
      LButton.Tag := AMarker;
      if AAnonymous then
        LButton.Name := '';
    end;
    LWriter := TWriter.Create(Result, 4096);
    try
      LWriter.WriteRootComponent(LToolbar);
      LWriter.WriteListEnd;
    finally
      LWriter.Free;
    end;
  finally
    LOwner.Free;
  end;
  // A reader normalizes both duplicate original names before assigning them.
  // Modify only this deliberately ambiguous record's name, after real writing.
  if AOwnCount > 1 then
  begin
    Result.Position := 0;
    LText := TStringStream.Create('', TEncoding.UTF8);
    try
      ObjectBinaryToText(Result, LText);
      LNames := LText.DataString.Replace('DAIServerToolButtonDuplicate:', 'DAIServerToolButton:');
      LInput := TStringStream.Create(LNames, TEncoding.UTF8);
      try
        Result.Clear;
        ObjectTextToBinary(LInput, Result);
        LWriter := TWriter.Create(Result, 4096);
        try
          LWriter.WriteListEnd;
        finally
          LWriter.Free;
        end;
      finally
        LInput.Free;
      end;
    finally
      LText.Free;
    end;
  end;
  Result.Position := 0;
end;

procedure ReadToolbarStream(AStream: TStream; const ADeferredParentAlign: Boolean = False);
var
  LReader: TReader;
  LStreamNotifier: INTAToolbarStreamNotifier;
  LBeforeNotifier: INTAToolbarStreamNotifier190;
  LPreviousAdds: Integer;
begin
  LPreviousAdds := GHost.AddCount;
  if Supports(GHost.ActiveNotifier, INTAToolbarStreamNotifier190, LBeforeNotifier) then
    LBeforeNotifier.BeforeLoad(GHost.Toolbar);
  GHost.ForeignButton.Free;
  GHost.ForeignButton := nil;
  GHost.Toolbar.Free;
  GHost.Toolbar := nil;
  GHost.LastReadButton := nil;
  GHost.LastReadToolbar := nil;
  AStream.Position := 0;
  if ADeferredParentAlign then
    GHost.Form.DisableAlign;
  LReader := TReader.Create(AStream, 4096);
  try
    LReader.OnSetName := GHost.ReaderSetName;
    LReader.ReadComponents(GHost.Form, GHost.Form, GHost.ReaderComponent);
  finally
    LReader.Free;
    if ADeferredParentAlign then
      GHost.Form.EnableAlign;
  end;
  Check(Assigned(GHost.LastReadToolbar), 'The genuine reader constructed the streamed debugger toolbar');
  if Supports(GHost.ActiveNotifier, INTAToolbarStreamNotifier, LStreamNotifier) then
    LStreamNotifier.ToolbarLoaded(GHost.LastReadToolbar);
  Check(GHost.Toolbar = nil, 'ToolbarLoaded can still precede the SDK public toolbar assignment');
  TDAIIDEToolbar.Refresh;
  Check(GHost.AddCount = LPreviousAdds, 'Refresh during the public-pointer gap cannot create a duplicate own button');
  GHost.Toolbar := GHost.LastReadToolbar;
  GHost.Toolbar.Images := GHost.Images;
  if GHost.Toolbar.ButtonCount > 0 then
    GHost.ForeignButton := GHost.Toolbar.Buttons[0];
end;

procedure TestStreamRestore(const ALegacyCount: Integer; const ARepeated: Boolean);
var
  LStream: TMemoryStream;
  LRestored: TToolButton;
  LNewBlank: TToolButton;
  LIndex: Integer;
  LRepeatCount: Integer;
  LCurrentAdds: Integer;
begin
  NewHost;
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  LRestored := nil;
  LStream := BuildToolbarStream(ALegacyCount, 1);
  try
    TDAIIDEToolbar.Install;
    Check(GHost.RegisterCount = 1, 'Install registers the synchronous read hook immediately');
    Check(GHost.AddCount = 0, 'Early notifier registration creates no toolbar UI');
    LRepeatCount := 1;
    if ARepeated then
      LRepeatCount := 3;
    for LIndex := 1 to LRepeatCount do
    begin
      ReadToolbarStream(LStream);
      LRestored := GHost.LastReadButton;
      Check(Assigned(LRestored), 'Original exact own stream name is observed');
      Check(LRestored.Name = '', 'IDE normalization occurred after positive capture');
      Check(GHost.MissingDependenciesDuringName, 'SetName observes properties before dependency fixups');
      Check(GHost.OfficialToolbarAbsentDuringName, 'SDK toolbar is deliberately unavailable during SetName');
      LCurrentAdds := GHost.AddCount;
      TDAIIDEToolbar.Refresh;
      Check(GHost.DAIButton = LRestored, 'Refresh adopts the exact positively captured object');
      Check(GHost.AddCount = LCurrentAdds, 'Restore does not create a duplicate factory button');
      Check(GHost.Toolbar.ButtonCount = 2, 'Historical single and known groups migrate only with positive own capture');
      Check(Assigned(LRestored.Action), 'Adoption binds the new or retained own action');
      Check(Assigned(LRestored.DropdownMenu), 'Adoption restores its own popup dependency');
      Check(GHost.RegisterCount = 1, 'Repeated desktop restoration does not duplicate notifier registrations');
      TDAIIDEToolbar.Refresh;
      Check(GHost.DAIButton = LRestored, 'Repeated ready refresh preserves the adopted object');
    end;
    LNewBlank := NewInertDropdown(GHost.Form, GHost.Toolbar);
    LRestored.Left := GHost.Toolbar.ButtonCount * 64;
    TDAIIDEToolbar.Refresh;
    Check(GHost.Toolbar.ButtonCount = 3, 'Consumed original-name evidence never authorizes a later anonymous single');
    Check(GHost.Toolbar.Buttons[1] = LNewBlank, 'A later anonymous single remains intact');
    TDAIIDEToolbar.Shutdown;
    Check(GHost.UnregisterCount = 1, 'Shutdown unregisters exactly once');
    Check(GHost.ActiveNotifier = nil, 'No own SDK notifier remains registered after shutdown');
    Check(GHost.Toolbar.ButtonCount = 2, 'Shutdown removes the adopted own button, preserving the later foreign single');
    TDAIIDEToolbar.Shutdown;
    Check(GHost.UnregisterCount = 1, 'Repeated shutdown cannot unregister a stale index');
  finally
    LStream.Free;
  end;
end;

procedure TestRejectedStreamRestore(const AVariant: Integer);
var
  LStream: TMemoryStream;
  LObserved: TToolButton;
  LForeignAction: TAction;
  LExpected: Integer;
begin
  NewHost;
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  LForeignAction := nil;
  if AVariant = 1 then
  begin
    LForeignAction := TAction.Create(GHost.Form);
    LForeignAction.Name := 'RunUntilReturnCommandForeign';
    LForeignAction.ActionList := GHost.ActionList;
  end;
  if AVariant = 2 then
    LStream := BuildToolbarStream(0, 2)
  else
    LStream := BuildToolbarStream(0, 1, AVariant = 1);
  try
    TDAIIDEToolbar.Install;
    ReadToolbarStream(LStream);
    LObserved := GHost.LastReadButton;
    Check(Assigned(LObserved), 'Rejected restoration still supplies a concrete original-name record');
    LExpected := 3;
    case AVariant of
      1: Check(Assigned(LObserved.Action), 'A pre-existing foreign action really resolved in the genuine reader');
      2: LExpected := 4;
      3:
        begin
          LObserved.Free;
          LObserved := nil;
          LExpected := 2;
        end;
      4: LObserved.OnClick := GHost.DummyClick;
      5: LObserved.Tag := 47;
      6: LObserved.DragMode := dmAutomatic;
      7: LObserved.DragKind := dkDock;
    end;
    TDAIIDEToolbar.Refresh;
    Check(GHost.AddCount = 1, 'Rejected, ambiguous or destroyed capture uses the ordinary own factory');
    Check(GHost.Toolbar.ButtonCount = LExpected, 'Untrusted or ambiguous streamed controls remain intact');
    Check(GHost.DAIButton <> LObserved, 'Rejected capture is never repurposed as the current DAI control');
    if AVariant = 1 then
      Check(LObserved.Action = LForeignAction, 'Rejecting an action-linked record preserves its foreign action');
    TDAIIDEToolbar.Shutdown;
    Check(GHost.Toolbar.ButtonCount = LExpected - 1, 'Shutdown does not remove the rejected restored record');
  finally
    LStream.Free;
  end;
end;

procedure TestDetachedReadNotifier;
var
  LRetained: IOTANotifier;
  LRead: INTAReadToolbarNotifier;
  LStreamHook: INTAToolbarStreamNotifier190;
  LStream: TMemoryStream;
  LReader: TReader;
  LButton: TToolButton;
  LName: string;
  LHandled: Boolean;
  LIndex: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  LRetained := GHost.ActiveNotifier;
  Check(Supports(LRetained, INTAReadToolbarNotifier, LRead), 'Actual registered receiver supports the official reader IID');
  Check(Supports(LRetained, INTAToolbarStreamNotifier190, LStreamHook), 'Actual receiver also supports the stream lifecycle IID');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.UnregisterCount = 1, 'Unregister releases only the own accepted SDK registration');
  LStream := TMemoryStream.Create;
  LReader := TReader.Create(LStream, 4096);
  LButton := NewInertDropdown(GHost.Form, GHost.Toolbar);
  try
    LReader.Root := GHost.Form;
    LReader.Owner := GHost.Form;
    LReader.Parent := GHost.Toolbar;
    for LIndex := 1 to 3 do
    begin
      LName := 'DAIServerToolButton';
      LHandled := False;
      LRead.SetName(LReader, LButton, LName, LHandled);
      LStreamHook.BeforeLoad(GHost.Toolbar);
      LStreamHook.ToolbarLoaded(GHost.Toolbar);
      Check(LName = 'DAIServerToolButton', 'A retained detached notifier leaves the incoming name unchanged');
      Check(not LHandled, 'A retained detached notifier leaves normalization untouched');
      Check(GHost.Toolbar.ButtonCount = 2, 'Late synchronous local interfaces cannot recreate or mutate toolbar UI');
    end;
  finally
    LButton.Free;
    LReader.Free;
    LStream.Free;
  end;
  TDAIIDEToolbar.Install;
  Check(GHost.RegisterCount = 2, 'An ordinary later installation obtains a new notifier registration');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.UnregisterCount = 2, 'Each installation retires its own accepted index exactly once');
end;

procedure TestReadNotifierFailures;
var
  LRetained: INTAReadToolbarNotifier;
  LName: string;
  LHandled: Boolean;
begin
  NewHost;
  GHost.RejectNotifier := True;
  TDAIIDEToolbar.Install;
  Check(GHost.RegisterCount = 1, 'Rejected early registration is attempted once');
  Check(GHost.ActiveNotifier = nil, 'Rejected notifier is not recorded as active');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.UnregisterCount = 0, 'A rejected negative registration index is never unregistered');
  NewHost;
  GHost.StopDuringRegister := True;
  TDAIIDEToolbar.Install;
  Check(GHost.ActiveNotifier = nil, 'Reentrant shutdown during SDK registration retires its local accepted receiver');
  Check(GHost.UnregisterCount = 1, 'Reentrant registration shutdown unregisters exactly the returned accepted index');
  Check(GHost.AddCount = 0, 'Reentrant registration shutdown creates no toolbar UI');
  NewHost;
  GHost.StopDuringRegister := True;
  GHost.RaiseUnregister := True;
  TDAIIDEToolbar.Install;
  Check(GHost.UnregisterCount = 1, 'Reentrant unregister failure still uses exactly its returned accepted index');
  Check(Supports(GHost.ActiveNotifier, INTAReadToolbarNotifier, LRetained), 'Failed SDK removal really retains its interface');
  Check(TDAILog.Messages.Count = 1, 'Failed reentrant unregister is reported by the common protected cleanup helper');
  LName := 'DAIServerToolButton';
  LHandled := False;
  LRetained.SetName(nil, nil, LName, LHandled);
  Check(LName = 'DAIServerToolButton', 'Retained receiver is detached after exceptional unregister');
  Check(not LHandled, 'Exceptional unregister cannot leave an active reader callback');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.UnregisterCount = 1, 'Retired exceptional registration is never unregistered again');
  Check(GHost.AddCount = 0, 'Failed unregister after registration shutdown cannot create toolbar UI');
end;


const
  CTestDAIButtonTag = $44414931;
  CTestDMacButtonTag = $444D4143;

function FindTaggedButton(const AToolbar: TToolBar; const ATag: NativeInt): TToolButton;
var
  LIndex: Integer;
begin
  Result := nil;
  for LIndex := 0 to AToolbar.ButtonCount - 1 do
    if AToolbar.Buttons[LIndex].Tag = ATag then
      Exit(AToolbar.Buttons[LIndex]);
end;

procedure TestPersistentMarkerRestore;
var
  LStream: TMemoryStream;
  LText: TStringStream;
  LRestored, LMac, LFirstBlank, LSecondBlank: TToolButton;
  LCurrentAdds: Integer;
begin
  NewHost;
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  LStream := BuildToolbarStream(2, 1, False, False, CTestDAIButtonTag, True, True);
  LText := TStringStream.Create('', TEncoding.UTF8);
  try
    ObjectBinaryToText(LStream, LText);
    Check(Pos('Tag = ' + IntToStr(CTestDAIButtonTag), LText.DataString) > 0,
      'Genuine VCL writer persists the DAI marker as a standard Tag property');
    Check(Pos('DAIServerToolButton:', LText.DataString) = 0,
      'Anonymous-marker stream contains no original own button name to capture');
    TDAIIDEToolbar.Install;
    ReadToolbarStream(LStream);
    LRestored := FindTaggedButton(GHost.Toolbar, CTestDAIButtonTag);
    LMac := FindTaggedButton(GHost.Toolbar, CTestDMacButtonTag);
    Check(Assigned(LRestored), 'Genuine VCL reader preserves the marker without an original component name');
    Check(Assigned(LMac), 'Genuine VCL reader also preserves the unrelated plugin marker');
    Check(GHost.LastReadButton = nil, 'The positive original-name callback deliberately supplied no DAI evidence');
    Check(LRestored.Name = '', 'Recovered marker candidate has no current component name');
    Check(LRestored.Action = nil, 'Saved DAI action reference is unresolved in this native reader fixture');
    Check(LRestored.DropdownMenu = nil, 'Saved DAI popup reference is unresolved in this native reader fixture');
    Check(GHost.Toolbar.ButtonCount = 5, 'Restore includes anchor, two anonymous old records, DMac and the DAI marker');
    LFirstBlank := GHost.Toolbar.Buttons[1];
    LSecondBlank := GHost.Toolbar.Buttons[2];
    LCurrentAdds := GHost.AddCount;
    TDAIIDEToolbar.Refresh;
    Check(GHost.DAIButton = LRestored, 'DAI adopts the exact marked button independently of a stream name');
    Check(GHost.AddCount = LCurrentAdds, 'Marker recovery does not create a second DAI factory button');
    Check(LRestored.Tag = CTestDAIButtonTag, 'Recovery keeps the same stable persistent marker');
    Check(LRestored.Action = GHost.DAIAction, 'Marker recovery reconnects the own action');
    Check(Assigned(LRestored.DropdownMenu), 'Marker recovery reconnects its own popup');
    Check(LRestored.Index = 4, 'Marker recovery preserves its position behind the interposed foreign plugin');
    Check((GHost.Toolbar.Buttons[1] = LFirstBlank) and (GHost.Toolbar.Buttons[2] = LSecondBlank),
      'Unmarked historical records are not assigned an invented origin by marker recovery');
    Check(GHost.Toolbar.Buttons[3] = LMac, 'Interposed DMac record remains in its original position');
    TDAIIDEToolbar.Refresh;
    Check(GHost.AddCount = LCurrentAdds, 'Repeated marker recovery is idempotent');
    TDAIIDEToolbar.Shutdown;
    Check(GHost.Toolbar.ButtonCount = 4, 'Shutdown removes only the positively marked own button');
    Check(FindTaggedButton(GHost.Toolbar, CTestDAIButtonTag) = nil, 'No own marked record remains after shutdown');
    Check(FindTaggedButton(GHost.Toolbar, CTestDMacButtonTag) = LMac, 'Shutdown preserves another plugin marker');
  finally
    LText.Free;
    LStream.Free;
  end;
end;

procedure TestPersistentMarkerDoesNotClaimOldSingle;
var
  LStream: TMemoryStream;
  LBlank, LMarked: TToolButton;
begin
  NewHost;
  GHost.ForeignAction.Name := 'RunUntilReturnCommand';
  LStream := BuildToolbarStream(1, 1, False, False, CTestDAIButtonTag, True);
  try
    TDAIIDEToolbar.Install;
    ReadToolbarStream(LStream);
    LBlank := GHost.Toolbar.Buttons[1];
    LMarked := FindTaggedButton(GHost.Toolbar, CTestDAIButtonTag);
    Check(GHost.LastReadButton = nil, 'Marker-only stream supplied no old original-name evidence');
    TDAIIDEToolbar.Refresh;
    Check(GHost.DAIButton = LMarked, 'Marker-only recovery reuses the positively marked record');
    Check(GHost.Toolbar.ButtonCount = 3, 'Marker recovery alone does not authorize deleting an adjacent unmarked single');
    Check(GHost.Toolbar.Buttons[1] = LBlank, 'The anonymous single keeps its unknown origin');
    TDAIIDEToolbar.Refresh;
    Check(GHost.Toolbar.ButtonCount = 3, 'Later refresh cannot promote marker evidence to historical-single ownership');
    TDAIIDEToolbar.Shutdown;
    Check(GHost.Toolbar.ButtonCount = 2, 'Shutdown preserves the unmarked single next to the native debugger action');
  finally
    LStream.Free;
  end;
end;

procedure TestPersistentMarkerLoading(const ALoadActionList: Boolean);
var
  LMarked: TToolButton;
  LTarget: TComponent;
  LText: TStringStream;
  LBinary: TMemoryStream;
  LReader: TReader;
  LObserved: Boolean;
begin
  NewHost;
  LMarked := NewInertDropdown(GHost.Form, GHost.Toolbar);
  LMarked.Tag := CTestDAIButtonTag;
  TDAIIDEToolbar.Install;
  if ALoadActionList then
    LTarget := GHost.ActionList
  else
    LTarget := GHost.Form;
  LObserved := False;
  LText := TStringStream.Create('object ' + LTarget.Name + ': ' + LTarget.ClassName + sLineBreak + 'end', TEncoding.UTF8);
  LBinary := TMemoryStream.Create;
  try
    ObjectTextToBinary(LText, LBinary);
    LBinary.Position := 0;
    LReader := TReader.Create(LBinary, 4096);
    try
      GDuringNativeRead :=
        procedure
        begin
          LObserved := True;
          Check(LTarget.ComponentState * [csLoading, csReading] <> [], 'Native reader really marks the selected host dependency as loading');
          TDAIIDEToolbar.Refresh;
          Check(GHost.AddCount = 0, 'Refresh during root or action-list loading cannot append a new factory button');
          Check(GHost.Toolbar.ButtonCount = 2, 'Refresh during host loading leaves the pending marked object intact');
          Check(LMarked.Name = '', 'A marker is not adopted while its root or action list is still loading');
          Check((LMarked.Action = nil) and (LMarked.DropdownMenu = nil), 'Loading deferral does not rebind dependencies prematurely');
        end;
      LReader.ReadRootComponent(LTarget);
    finally
      GDuringNativeRead := nil;
      LReader.Free;
    end;
    Check(LObserved, 'Loading deferral was tested from a genuine native ReadState callback');
    Check(LTarget.ComponentState * [csLoading, csReading] = [], 'Genuine reader completed the host loading cycle');
    TDAIIDEToolbar.Refresh;
    Check(GHost.DAIButton = LMarked, 'The same pending marker is adopted once host loading completes');
    Check(GHost.AddCount = 0, 'Completed loading still needs no duplicate factory record');
    TDAIIDEToolbar.Shutdown;
    Check(GHost.Toolbar.ButtonCount = 1, 'Loading deferral leaves no marked record after shutdown');
  finally
    GDuringNativeRead := nil;
    LBinary.Free;
    LText.Free;
  end;
end;

procedure TestPersistentMarkerDuplicates(const ALastNamed: Boolean);
var
  LFirst, LDuplicate: TToolButton;
  LOtherBar: TToolBar;
  LOtherBarButton: TToolButton;
begin
  NewHost;
  LFirst := NewInertDropdown(GHost.Form, GHost.Toolbar);
  LFirst.Tag := CTestDAIButtonTag;
  LDuplicate := NewInertDropdown(GHost.Form, GHost.Toolbar);
  LDuplicate.Tag := CTestDAIButtonTag;
  if ALastNamed then
    LDuplicate.Name := 'DAIServerToolButton';
  LOtherBar := TToolBar.Create(GHost.Form);
  LOtherBar.Parent := GHost.Form;
  LOtherBarButton := NewInertDropdown(GHost.Form, LOtherBar);
  LOtherBarButton.Tag := CTestDAIButtonTag;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(GHost.DAIButton = LFirst, 'Two own marked records reuse the first without a new factory button');
  Check(GHost.AddCount = 0, 'Marked duplicate cleanup does not append another control');
  Check(GHost.Toolbar.ButtonCount = 2, 'Only one own marker survives beside the native debugger control');
  Check(LOtherBar.ButtonCount = 1, 'Same marker on a different toolbar is outside the recovery scope');
  Check(LOtherBar.Buttons[0] = LOtherBarButton, 'Another toolbar is not searched for orphan candidates');
  TDAIIDEToolbar.Shutdown;
  Check(GHost.Toolbar.ButtonCount = 1, 'Recovered marker and duplicates cannot leak after shutdown');
  Check(LOtherBar.ButtonCount = 1, 'Shutdown preserves an unbound marker on a different toolbar');
end;

procedure TestPersistentMarkerForeign(const AVariant: Integer);
var
  LForeign: TToolButton;
  LOtherOwner: TComponent;
  LForeignPopup: TPopupMenu;
begin
  NewHost;
  LForeignPopup := nil;
  if AVariant = 1 then
  begin
    LOtherOwner := TComponent.Create(GHost.Form);
    LForeign := NewInertDropdown(LOtherOwner, GHost.Toolbar);
  end
  else if AVariant = 5 then
  begin
    LForeign := TForeignToolButton.Create(GHost.Form);
    LForeign.Left := GHost.Toolbar.ButtonCount * 64;
    LForeign.Parent := GHost.Toolbar;
    LForeign.Style := tbsDropDown;
    LForeign.ShowHint := True;
    LForeign.ParentShowHint := False;
  end
  else
    LForeign := NewInertDropdown(GHost.Form, GHost.Toolbar);
  LForeign.Tag := CTestDAIButtonTag;
  case AVariant of
    2: LForeign.Action := GHost.ForeignAction;
    3:
      begin
        LForeignPopup := TPopupMenu.Create(GHost.Form);
        LForeign.DropdownMenu := LForeignPopup;
      end;
    4: LForeign.OnClick := GHost.DummyClick;
    6: LForeign.Tag := CTestDMacButtonTag;
  end;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(GHost.Toolbar.ButtonCount = 3, 'A conflicting or foreign marker candidate is not removed or adopted');
  Check(GHost.AddCount = 1, 'Foreign candidate leaves normal own button creation available');
  Check(GHost.DAIButton <> LForeign, 'Marker is insufficient when owner, class or behavior belongs elsewhere');
  Check(GHost.DAIButton.Tag = CTestDAIButtonTag, 'A newly created own button always receives the persistent marker');
  if AVariant = 2 then
    Check(LForeign.Action = GHost.ForeignAction, 'Marker recovery cannot steal a foreign action');
  if AVariant = 3 then
    Check(LForeign.DropdownMenu = LForeignPopup, 'Marker recovery cannot replace a foreign popup');
  if AVariant = 5 then
  begin
    LForeign.Click;
    Check(TForeignToolButton(LForeign).ClickCount = 1, 'Foreign virtual behavior remains usable');
  end;
  TDAIIDEToolbar.Shutdown;
  Check(GHost.Toolbar.ButtonCount = 2, 'Shutdown preserves the conflicting or foreign marked control');
end;

procedure TestKnownButtonOwnerTransfer(const ATransferAction: Boolean);
var
  LButton: TToolButton;
  LAction: TAction;
  LPopup: TPopupMenu;
  LAlternateOwner: TComponent;
  LAdds: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LButton := GHost.DAIButton;
  LAction := GHost.DAIAction;
  LPopup := LButton.DropdownMenu;
  LAdds := GHost.AddCount;
  LAlternateOwner := TComponent.Create(nil);
  try
    if ATransferAction then
    begin
      GHost.Form.RemoveComponent(LAction);
      LAlternateOwner.InsertComponent(LAction);
      LAlternateOwner.RemoveComponent(LAction);
      GHost.Form.InsertComponent(LAction);
      Check(LButton.Action = nil, 'Real RTL owner transfer detached the existing button action');
    end
    else
    begin
      GHost.Form.RemoveComponent(LPopup);
      LAlternateOwner.InsertComponent(LPopup);
      LAlternateOwner.RemoveComponent(LPopup);
      GHost.Form.InsertComponent(LPopup);
      Check(LButton.DropdownMenu = nil, 'Real RTL owner transfer detached the existing dropdown menu');
    end;
    TDAIIDEToolbar.Refresh;
    Check(GHost.DAIButton = LButton, 'Owner transfer repairs the existing button object');
    Check(GHost.AddCount = LAdds, 'Owner transfer repair creates no duplicate factory record');
    Check(LButton.Action = LAction, 'Owner transfer repair reconnects the exact own action');
    Check(LButton.DropdownMenu = LPopup, 'Owner transfer repair reconnects the exact own popup');
    Check(LAction.ActionList = GHost.ActionList, 'Owner transfer retains the official IDE action-list registration');
    Check(LButton.Tag = CTestDAIButtonTag, 'Known current button retains its persistent identity');
    TDAIIDEToolbar.Shutdown;
    Check(GHost.Toolbar.ButtonCount = 1, 'Owner transfer leaves no inert own record after shutdown');
  finally
    LAlternateOwner.Free;
  end;
end;

procedure TestToolbarStream;
var
  LVariant: Integer;
begin
  System.Classes.RegisterClass(TToolBar);
  System.Classes.RegisterClass(TToolButton);
  TestStreamRestore(0, True);
  TestStreamRestore(1, True);
  TestStreamRestore(3, False);
  TestStreamRestore(4, False);
  TestStreamRestore(5, False);
  for LVariant := 1 to 7 do
    TestRejectedStreamRestore(LVariant);
  TestDetachedReadNotifier;
  TestReadNotifierFailures;
  TestPersistentMarkerRestore;
  TestPersistentMarkerDoesNotClaimOldSingle;
  TestPersistentMarkerLoading(False);
  TestPersistentMarkerLoading(True);
  TestPersistentMarkerDuplicates(False);
  TestPersistentMarkerDuplicates(True);
  for LVariant := 1 to 6 do
    TestPersistentMarkerForeign(LVariant);
  TestKnownButtonOwnerTransfer(True);
  TestKnownButtonOwnerTransfer(False);
end;
