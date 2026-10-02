function BuildToolbarStream(const ALegacyCount, AOwnCount: Integer; const AForeignLink: Boolean = False; const AFixedLayout: Boolean = False): TMemoryStream;
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
end;
