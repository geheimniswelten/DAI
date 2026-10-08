program TestOptions;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Winapi.Windows,
  h5u.DAI.Clients.Registration in 'OptionsTests\h5u.DAI.Clients.Registration.pas',
  h5u.DAI.Codex.Registration in 'OptionsTests\h5u.DAI.Codex.Registration.pas',
  h5u.DAI.MCP.Tools in 'OptionsTests\h5u.DAI.MCP.Tools.pas',
  h5u.DAI.OTA.Helpers in 'OptionsTests\h5u.DAI.OTA.Helpers.pas',
  h5u.DAI.Permissions.Manager in 'OptionsTests\h5u.DAI.Permissions.Manager.pas',
  h5u.DAI.Runtime in 'OptionsTests\h5u.DAI.Runtime.pas',
  h5u.DAI.Settings in 'OptionsTests\h5u.DAI.Settings.pas',
  h5u.DAI.Consts,
  h5u.DAI.Options.Frame in '..\Source\h5u.DAI.Options.Frame.pas';

type
  TCatalogProbe = class
  public
    Failure: string;
    Seen: Boolean;
    Variant: Integer;
    Timer: TTimer;
    procedure InspectDialog(Sender: TObject);
  end;

var
  CheckCount: Integer;
  TestStage: string;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function EditControl(AFrame: TDAIOptionsFrame; APort: Boolean): TEdit;
var
  LComponent: TComponent;
begin
  Result := nil;
  for LComponent in AFrame do
    if LComponent is TEdit then
      if TEdit(LComponent).NumbersOnly = APort then
      begin
        Check(not Assigned(Result), 'Port/token edit is unique');
        Result := TEdit(LComponent);
      end;
  Check(Assigned(Result), 'Port/token edit exists');
end;

function ButtonControl(AFrame: TDAIOptionsFrame; const ACaption: string): TButton;
var
  LComponent: TComponent;
begin
  Result := nil;
  for LComponent in AFrame do
    if LComponent is TButton then
      if TButton(LComponent).Caption = ACaption then
        Result := TButton(LComponent);
  Check(Assigned(Result), 'Server button exists');
end;

function StatusControl(AFrame: TDAIOptionsFrame): TLabel;
var
  LComponent: TComponent;
begin
  Result := nil;
  for LComponent in AFrame do
    if LComponent is TLabel then
      if StartsText('Status:', TLabel(LComponent).Caption) then
      begin
        Check(not Assigned(Result), 'Server status label is unique');
        Result := TLabel(LComponent);
      end;
  Check(Assigned(Result), 'Server status label exists');
end;

function ScopeControl(AFrame: TDAIOptionsFrame): TComboBox;
var
  LComponent: TComponent;
begin
  Result := nil;
  for LComponent in AFrame do
    if LComponent is TComboBox then
      if TComboBox(LComponent).Items.IndexOf('Globaler Standard') >= 0 then
        Result := TComboBox(LComponent);
  Check(Assigned(Result), 'Permission scope combo exists');
end;

function LifecycleControl(const AFrame: TDAIOptionsFrame): TCheckBox;
var
  LComponent: TComponent;
begin
  LComponent := AFrame.FindComponent('DAIAllowIDEStartStopCheckBox');
  Check(LComponent is TCheckBox, 'Lifecycle permission has a named checkbox');
  Result := TCheckBox(LComponent);
end;

procedure CheckNoPersistence;
begin
  Check(TDAISettings.Instance.SaveCount = 0, 'Manual start/stop does not save settings');
  Check(TDAIRuntime.ApplyCount = 0, 'Manual start/stop does not apply persisted settings');
  Check(TDAIPermissionManager.Instance.WriteCount = 0, 'Manual start/stop does not persist permissions');
  Check(TDAIClientRegistration.RegisterCount = 0, 'Manual start/stop does not register clients');
  Check(TDAIClientRegistration.UnregisterCount = 0, 'Manual start/stop does not unregister clients');
end;

procedure CheckStatusFormatting(const AFrame: TDAIOptionsFrame);
var
  LStatus: TJSONObject;
  LClients: TJSONArray;
  LComponent: TComponent;
  LMemo: TMemo;
  LIndex: Integer;
  LLine: string;
begin
  LStatus := TJSONObject.Create;
  try
    LClients := TJSONArray.Create;
    LStatus.AddPair('clients', LClients);
    LClients.AddElement(TJSONObject.Create.AddPair('label', 'Codex').AddPair('status', 'registered')
      .AddPair('path', 'C:\Synthetic\codex.toml').AddPair('message', 'Nachricht eins.' + #13#10 + #13#10 + '  Nachricht zwei.  ')
      .AddPair('backup', 'C:\Synthetic\codex.toml.dai.backup'));
    LClients.AddElement(TJSONObject.Create.AddPair('label', 'Claude Desktop').AddPair('status', 'unsupported')
      .AddPair('path', '').AddPair('message', #10 + 'Hinweis.' + #10).AddPair('backup', ''));
    TDAIClientRegistration.StatusJSON := LStatus.ToJSON;
    AFrame.RefreshRegistrationStatus;
    LMemo := nil;
    for LComponent in AFrame do
      if LComponent is TMemo then
        if TMemo(LComponent).ReadOnly then
          LMemo := TMemo(LComponent);
    Check(Assigned(LMemo), 'Client status memo exists and is readonly');
    Check(LMemo.Lines.Count = 9, 'Client details consume no empty separator lines');
    Check(LMemo.Lines[0] = 'Codex', 'First client has its own name header');
    Check(LMemo.Lines[6] = 'Claude Desktop', 'Second client has its own name header');
    Check(LMemo.Lines[1] = '    Status: registriert', 'Translated status is indented below client name');
    Check(LMemo.Lines[2] = '    C:\Synthetic\codex.toml', 'Configuration path has four spaces');
    Check(LMemo.Lines[3] = '    Nachricht eins.', 'First message line has four spaces');
    Check(LMemo.Lines[4] = '    Nachricht zwei.', 'Multiline message trims inner whitespace and uses four spaces');
    Check(LMemo.Lines[5] = '    Sicherung: C:\Synthetic\codex.toml.dai.backup', 'Backup detail has four spaces');
    Check(LMemo.Lines[7] = '    Status: manuelle Einrichtung erforderlich', 'Manual client status remains translated');
    Check(LMemo.Lines[8] = '    Hinweis.', 'Empty path and backup produce no blank lines');
    for LIndex := 0 to LMemo.Lines.Count - 1 do
    begin
      LLine := LMemo.Lines[LIndex];
      Check(Trim(LLine) <> '', 'Each rendered client status line contains content');
      Check(Pos(#9, LLine) = 0, 'Status indentation never uses tabs');
      if (LIndex <> 0) and (LIndex <> 6) then
        Check(StartsStr('    ', LLine) and (LLine[5] <> ' '), 'Every detail line starts with exactly four spaces');
    end;
    CheckNoPersistence;
  finally
    TDAIClientRegistration.StatusJSON := '';
    LStatus.Free;
  end;
end;

procedure TCatalogProbe.InspectDialog(Sender: TObject);
var
  LDialog: TCustomForm;
  LComponent: TComponent;
  LMemo: TMemo;
  LOK: TButton;
  LCount: Integer;
begin
  Timer.Enabled := False;
  LDialog := Screen.ActiveCustomForm;
  try
    Check(Assigned(LDialog), 'Actual catalog ShowModal activates its own VCL form');
    Check(LDialog.Name = 'DAIToolCatalogDialog', 'Catalog opens the intended isolated dialog');
    Seen := True;
    LMemo := nil;
    LOK := nil;
    for LComponent in LDialog do
      if LComponent is TMemo then
        LMemo := TMemo(LComponent)
      else if LComponent is TButton then
        LOK := TButton(LComponent);
    Check(Assigned(LMemo) and Assigned(LOK), 'Catalog has memo and close button');
    Check(LMemo.ReadOnly, 'Catalog text cannot be edited');
    Check(LMemo.ScrollBars = ssBoth, 'Long catalog has vertical and horizontal scrollbars');
    Check(not LMemo.WordWrap, 'Catalog preserves name/description indentation');
    Check(LMemo.Anchors = [akLeft, akTop, akRight, akBottom], 'Catalog memo grows when dialog is resized');
    Check(LMemo.Lines[0] = 'Skill: ' + CDAISkillDirectoryName, 'Catalog identifies the current registered skill');
    case Variant of
      1: LCount := 2;
      2: LCount := 0;
    else LCount := 3;
    end;
    Check(LMemo.Lines[1] = 'MCP-Werkzeuge: ' + IntToStr(LCount), 'Catalog count reflects the current ListTools result');
    if Variant <> 2 then
    begin
      Check(LMemo.Lines[2] = 'ide_status', 'Catalog displays real fixture tool name');
      Check(LMemo.Lines[3] = '    Liest den aktuellen IDE-Status.', 'Description uses four spaces');
      if Variant = 1 then
      begin
        Check(LMemo.Lines[4] = 'dynamic_fixture_added_tool', 'Next opening displays a newly available tool');
        Check(Pos('source_search', LMemo.Text) = 0, 'Next opening removes stale tools');
      end
      else
      begin
        Check(LMemo.Lines[4] = 'source_search', 'Catalog preserves current tool order');
        Check(LMemo.Lines[5] = '    Sucht hilfreiche Quellen.', 'First multiline description line is indented');
        Check(LMemo.Lines[6] = '    Nur Interfaces als Standard.', 'Further description lines have four spaces and no blank row');
        Check(LMemo.Lines[7] = 'ui_active_dialog', 'Catalog includes later tools');
      end;
    end
    else
      Check(LMemo.Lines.Count = 2, 'Empty dynamic catalog is displayed without stale entries');
    Check(Pos('DO_NOT_DISPLAY_SCHEMA', LMemo.Text) = 0, 'Catalog omits schema contents');
    Check(Pos(TDAISettings.Instance.Token, LMemo.Text) = 0, 'Catalog omits stored synthetic bearer token');
    Check((LOK.Caption = 'OK') and LOK.Default and LOK.Cancel, 'Catalog supports OK, Enter and Escape');
    Check(LOK.ModalResult = mrOK, 'Catalog close button has OK modal result');
    LOK.Click;
    Check(LDialog.ModalResult = mrOK, 'Actual OK click closes the catalog');
  except
    on E: Exception do
    begin
      Failure := E.Message;
      if Assigned(LDialog) then
        if LDialog.Name = 'DAIToolCatalogDialog' then
          LDialog.ModalResult := mrCancel;
    end;
  end;
end;

procedure CheckCatalogDialog(const AFrame: TDAIOptionsFrame);
var
  LButton: TButton;
  LProbe: TCatalogProbe;
  LVariant: Integer;
  LStartCount, LStopCount, LStatusCount: Integer;
begin
  LButton := ButtonControl(AFrame, 'Skill und MCP-Werkzeuge');
  Check(Assigned(LButton.OnClick), 'Catalog button has production click handler');
  Check(TDAIMCPTools.ListCount = 0, 'Frame creation does not obtain catalog unnecessarily');
  LStartCount := TDAIRuntime.StartCount;
  LStopCount := TDAIRuntime.StopCount;
  LStatusCount := TDAIClientRegistration.StatusCount;
  LProbe := TCatalogProbe.Create;
  LProbe.Timer := TTimer.Create(nil);
  try
    LProbe.Timer.Enabled := False;
    LProbe.Timer.Interval := 25;
    LProbe.Timer.OnTimer := LProbe.InspectDialog;
    for LVariant := 0 to 2 do
    begin
      TDAIMCPTools.CatalogVariant := LVariant;
      LProbe.Variant := LVariant;
      LProbe.Seen := False;
      LProbe.Failure := '';
      LProbe.Timer.Enabled := True;
      LButton.Click;
      LProbe.Timer.Enabled := False;
      Check(LProbe.Failure = '', 'Catalog inspection: ' + LProbe.Failure);
      Check(LProbe.Seen, 'Catalog was inspected inside its real modal loop');
      Check(TDAIMCPTools.ListCount = LVariant + 1, 'Each opening obtains the catalog exactly once');
      CheckNoPersistence;
    end;
    Check(TDAIRuntime.StartCount = LStartCount, 'Catalog does not start any server');
    Check(TDAIRuntime.StopCount = LStopCount, 'Catalog does not stop any server');
    Check(TDAIClientRegistration.StatusCount = LStatusCount, 'Catalog does not refresh registrations');
  finally
    LProbe.Timer.Free;
    LProbe.Free;
  end;
end;

procedure RunChecks;
var
  LFrame: TDAIOptionsFrame;
  LHost: TForm;
  LApplicationHandle: HWND;
  LPortEdit: TEdit;
  LTokenEdit: TEdit;
  LStart: TButton;
  LStop: TButton;
  LStatus: TLabel;
  LScope: TComboBox;
  LPermissionReadCount: Integer;
  LStoredPort: Integer;
  LStoredToken: string;
begin
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  LStoredPort := TDAISettings.Instance.Port;
  LStoredToken := TDAISettings.Instance.Token;
  LHost := TForm.CreateNew(nil);
  LApplicationHandle := Application.Handle;
  try
    LHost.Visible := False;
    // Console programs have no VCL application HWND. TFrame.CreateParams needs one.
    // Use the hidden fixture host only; restore the application handle before cleanup.
    Application.Handle := LHost.Handle;
    TestStage := 'CreateFrame';
    LFrame := TDAIOptionsFrame.Create(nil);
    try
      // The actual production frame builds real VCL controls and loads its real DFM.
      // Its native parent stays hidden. Only the isolated catalog opens its own modal dialog.
      TestStage := 'LoadSettings';
      LFrame.Visible := False;
      LFrame.Parent := LHost;
      LFrame.LoadFromSettings;
      TestStage := 'DiscoverControls';
      LPortEdit := EditControl(LFrame, True);
      LTokenEdit := EditControl(LFrame, False);
      LStart := ButtonControl(LFrame, 'Server starten');
      LStop := ButtonControl(LFrame, 'Server stoppen');
      LStatus := StatusControl(LFrame);
      LScope := ScopeControl(LFrame);
      Check(not LFrame.Visible, 'Frame remains hidden');
      Check(LPortEdit.Text = IntToStr(LStoredPort), 'Initial port loaded from synthetic settings');
      Check(LTokenEdit.Text = LStoredToken, 'Initial token loaded from synthetic settings');
      Check(LStart.Enabled and not LStop.Enabled, 'Stopped server button state');
      Check(TDAIRuntime.ServerPort = 0, 'Stopped runtime reports zero port');

      LPortEdit.Text := ' 7102 ';
      LTokenEdit.Text := '  synthetic-current-options-token  ';
      TestStage := 'ClientStatusFormatting';
      CheckStatusFormatting(LFrame);
      TestStage := 'CatalogDialog';
      CheckCatalogDialog(LFrame);
      Check(LPortEdit.Text = ' 7102 ', 'Catalog preserves draft port');
      Check(LTokenEdit.Text = '  synthetic-current-options-token  ', 'Catalog preserves draft bearer token');
      TestStage := 'StartStopSettings';
      LPermissionReadCount := TDAIPermissionManager.Instance.ReadCount;
      Check(Assigned(LScope.OnChange), 'Actual permission scope handler is attached');
      LScope.ItemIndex := 0;
      LScope.OnChange(LScope);
      Check(LPortEdit.Text = ' 7102 ', 'Scope change preserves draft port');
      Check(LTokenEdit.Text = '  synthetic-current-options-token  ', 'Scope change preserves draft token');
      Check(TDAIPermissionManager.Instance.ReadCount > LPermissionReadCount, 'Scope change refreshes permission levels');
      Check(TDAIPermissionManager.Instance.LastProjectKey = '', 'Global scope reads global permissions');
      LScope.ItemIndex := 1;
      LScope.OnChange(LScope);
      Check(LPortEdit.Text = ' 7102 ', 'Project scope preserves draft port');
      Check(LTokenEdit.Text = '  synthetic-current-options-token  ', 'Project scope preserves draft token');
      Check(TDAIPermissionManager.Instance.LastProjectKey = TDAIOTA.ActiveProjectFileName, 'Project scope reads synthetic project permissions');

      Check(Assigned(LStart.OnClick), 'Actual start handler is attached');
      LStart.Click;
      Check(TDAIRuntime.StartCount = 1, 'One actual button click starts runtime once');
      Check(TDAIRuntime.LegacyStartCount = 0, 'Manual start uses explicit current configuration');
      Check(TDAIRuntime.CapturedPort = 7102, 'Start receives current trimmed UI port');
      Check(TDAIRuntime.CapturedToken = 'synthetic-current-options-token', 'Start receives current trimmed UI token');
      Check(TDAIRuntime.ServerActive, 'Started runtime is active');
      Check(TDAIRuntime.ServerPort = 7102, 'Runtime reports actual started port');
      Check(TDAISettings.Instance.Port = LStoredPort, 'Start leaves stored port unchanged');
      Check(TDAISettings.Instance.Token = LStoredToken, 'Start leaves stored token unchanged');
      Check(not TDAISettings.Instance.Enabled, 'Manual start leaves autostart disabled');
      Check(not LStart.Enabled and LStop.Enabled, 'Active server button state');
      Check(Pos('http://' + CDAIDefaultBindAddress + ':7102' + CDAIMcpPath, LStatus.Caption) > 0, 'Status displays actual runtime port');
      Check(Pos(':' + IntToStr(LStoredPort) + CDAIMcpPath, LStatus.Caption) = 0, 'Status does not display differing stored port');
      CheckNoPersistence;

      // Simulate a separately changed stored value; an active listener keeps its own port.
      TDAISettings.Instance.Port := 7109;
      LFrame.LoadFromSettings;
      Check(TDAIRuntime.StartCount = 1, 'Refreshing frame does not restart runtime');
      Check(LPortEdit.Text = '7109', 'Refresh loads newly stored synthetic port into edit');
      Check(Pos(':7102' + CDAIMcpPath, LStatus.Caption) > 0, 'Refresh still displays runtime listener port');
      Check(Pos(':7109' + CDAIMcpPath, LStatus.Caption) = 0, 'Refresh does not confuse edit and listener ports');
      CheckNoPersistence;

      LStop.Click;
      Check(TDAIRuntime.StopCount = 1, 'Actual stop button stops runtime once');
      Check(not TDAIRuntime.ServerActive, 'Stop clears active state');
      Check(TDAIRuntime.ServerPort = 0, 'Stop clears listener port');
      Check(LStart.Enabled and not LStop.Enabled, 'Stopped buttons refreshed');
      Check(Pos('gestoppt', LStatus.Caption) > 0, 'Stopped status refreshed');
      Check(TDAISettings.Instance.Port = 7109, 'Stop leaves stored synthetic port unchanged');
      Check(TDAISettings.Instance.Token = LStoredToken, 'Stop leaves stored token unchanged');
      CheckNoPersistence;

      LPortEdit.Text := '65535';
      LTokenEdit.Text := ' synthetic-options-test-token-2 ';
      LStart.Click;
      Check(TDAIRuntime.StartCount = 2, 'Second start captures new current values');
      Check(TDAIRuntime.LegacyStartCount = 0, 'Second start also avoids persisted configuration API');
      Check(TDAIRuntime.CapturedPort = 65535, 'Second start accepts valid upper port bound');
      Check(TDAIRuntime.CapturedToken = 'synthetic-options-test-token-2', 'Second start trims replacement token');
      Check(Pos(':65535' + CDAIMcpPath, LStatus.Caption) > 0, 'Second start status uses replacement runtime port');
      Check(TDAISettings.Instance.Port = 7109, 'Second start leaves stored port unchanged');
      Check(TDAISettings.Instance.Token = LStoredToken, 'Second start leaves stored token unchanged');
      CheckNoPersistence;
    finally
      LFrame.Free;
    end;
  finally
    Application.Handle := LApplicationHandle;
    LHost.Free;
  end;
end;

procedure CheckLifecycleOptions;
var
  LHost: TForm;
  LFrame: TDAIOptionsFrame;
  LCheckBox: TCheckBox;
  LApplicationHandle: HWND;
  LFailed: Boolean;
  LSaveCount: Integer;
begin
  TestStage := 'LifecycleOptions';
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  LHost := TForm.CreateNew(nil);
  LFrame := nil;
  LApplicationHandle := Application.Handle;
  try
    LHost.Visible := False;
    Application.Handle := LHost.Handle;
    LFrame := TDAIOptionsFrame.Create(nil);
    LFrame.Visible := False;
    LFrame.Parent := LHost;
    LFrame.LoadFromSettings;
    LCheckBox := LifecycleControl(LFrame);
    Check(LCheckBox.Caption = 'KI darf die Delphi-IDE starten und beenden', 'Lifecycle checkbox states the permission positively');
    Check(LCheckBox.Checked, 'Lifecycle permission defaults to enabled');
    Check(LCheckBox.ShowHint, 'Lifecycle scope is explained in its hint');
    Check(Pos('alle Delphi-Versionen und Profile', LCheckBox.Hint) > 0, 'Hint explains the shared IDE/profile scope');
    Check(Pos('Windows-Benutzers', LCheckBox.Hint) > 0, 'Hint explains the Windows-user scope');
    Check(Pos('Speichern oder Registrieren', LCheckBox.Hint) > 0, 'Hint explains when permission changes are persisted');
    Check(Pos('Statusabfragen', LCheckBox.Hint) > 0, 'Hint explains that launcher status stays available');
    LCheckBox.Checked := False;
    Check(TDAISettings.Instance.AllowIDEStartStop, 'Draft checkbox does not change the effective stored permission');
    Check(TDAISettings.Instance.PersistedAllowIDEStartStop, 'Draft checkbox does not write the synthetic policy');
    CheckNoPersistence;

    // DialogClosed(False) never calls StoreToSettings. Destroy its draft frame like a cancelled options dialog.
    FreeAndNil(LFrame);
    Check(TDAISettings.Instance.AllowIDEStartStop, 'Cancelling a draft leaves lifecycle permission enabled');
    Check(TDAISettings.Instance.PolicyWriteCount = 0, 'Cancelling does not write the lifecycle policy');
    LFrame := TDAIOptionsFrame.Create(nil);
    LFrame.Visible := False;
    LFrame.Parent := LHost;
    LFrame.LoadFromSettings;
    LCheckBox := LifecycleControl(LFrame);
    Check(LCheckBox.Checked, 'Reopening after cancellation reloads the saved enabled value');
    LCheckBox.Checked := False;
    LFrame.StoreToSettings;
    Check(not TDAISettings.Instance.PersistedAllowIDEStartStop, 'Accepting options persists disabled permission');
    Check(TDAISettings.Instance.PolicyWriteCount = 1, 'Explicit checkbox change writes policy once');
    Check(TDAISettings.Instance.SaveCount = 1, 'Accepted options use the normal settings-save path');
    Check(not LCheckBox.Checked, 'Accepted checkbox remains disabled');
    Check(TDAIClientRegistration.RegisterCount = 0, 'Saving lifecycle permission does not register clients');
    Check(TDAIClientRegistration.UnregisterCount = 0, 'Saving lifecycle permission does not unregister clients');
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.PolicyWriteCount = 1, 'Unchanged options do not rewrite the shared policy');

    // Another IDE can change the shared flag while this options frame stays open.
    TDAISettings.Instance.PersistedAllowIDEStartStop := True;
    Check(TDAISettings.Instance.AllowIDEStartStop, 'Settings getter reads an externally changed shared permission');
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.PersistedAllowIDEStartStop, 'Stale unchanged unchecked frame preserves another IDE enable');
    Check(TDAISettings.Instance.PolicyWriteCount = 1, 'Unchanged stale frame performs no policy write');
    Check(LCheckBox.Checked, 'Saved frame refreshes checkbox from the current shared policy');
    TDAISettings.Instance.PersistedAllowIDEStartStop := False;
    Check(not TDAISettings.Instance.AllowIDEStartStop, 'Settings getter also observes external disable');
    EditControl(LFrame, True).Text := '7111';
    LFrame.StoreToSettings;
    Check(not TDAISettings.Instance.PersistedAllowIDEStartStop, 'Port-only save preserves another IDE disable');
    Check(TDAISettings.Instance.PolicyWriteCount = 1, 'Port-only save does not write shared policy');
    Check(not LCheckBox.Checked, 'Port-only save refreshes checkbox to externally disabled state');
    LCheckBox.Checked := True;
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.PersistedAllowIDEStartStop, 'Explicit checkbox change can enable shared permission');
    Check(TDAISettings.Instance.PolicyWriteCount = 2, 'Explicit enable writes policy exactly once');

    TDAISettings.Instance.FailSave := True;
    LCheckBox.Checked := False;
    LFailed := False;
    try
      LFrame.StoreToSettings;
    except
      on E: Exception do
        LFailed := E.Message = 'Synthetic settings-save failure';
    end;
    Check(LFailed, 'Actual StoreToSettings propagates the synthetic save failure');
    Check(TDAISettings.Instance.PersistedAllowIDEStartStop, 'Failed save preserves the effective stored permission');
    Check(TDAISettings.Instance.AllowIDEStartStop, 'Failed save rolls back the pending in-memory lifecycle change');
    Check(TDAISettings.Instance.DiscardCount = 1, 'Failed save discards the pending lifecycle change once');
    Check(TDAISettings.Instance.PolicyWriteCount = 2, 'Failed save never writes policy');
    TDAISettings.Instance.FailSave := False;
    TDAISettings.Instance.Save;
    Check(TDAISettings.Instance.PolicyWriteCount = 2, 'Later unrelated settings save cannot replay the failed draft');
    LFrame.StoreToSettings;
    Check(not TDAISettings.Instance.PersistedAllowIDEStartStop, 'User can retry the same unchecked draft after a save failure');
    Check(TDAISettings.Instance.PolicyWriteCount = 3, 'Successful retry writes policy once');

    LCheckBox.Checked := True;
    EditControl(LFrame, True).Text := '0';
    LSaveCount := TDAISettings.Instance.SaveCount;
    LFailed := False;
    try
      LFrame.StoreToSettings;
    except
      on E: EArgumentException do
        LFailed := True;
    end;
    Check(LFailed, 'Invalid options fail before lifecycle permission is changed');
    Check(TDAISettings.Instance.SaveCount = LSaveCount, 'Invalid configuration does not enter settings save');
    Check(not TDAISettings.Instance.AllowIDEStartStop, 'Invalid configuration leaves effective lifecycle permission disabled');
    Check(TDAISettings.Instance.PolicyWriteCount = 3, 'Invalid configuration does not write policy');
    EditControl(LFrame, True).Text := '7112';
    ButtonControl(LFrame, 'Registrieren').Click;
    Check(TDAISettings.Instance.PersistedAllowIDEStartStop, 'Explicit Register button also persists the draft lifecycle permission');
    Check(TDAISettings.Instance.PolicyWriteCount = 4, 'Explicit Register writes a changed lifecycle policy once');
    Check(TDAIClientRegistration.RegisterCount = 1, 'Only explicit Register invokes client registration');
    Check(TDAIClientRegistration.UnregisterCount = 0, 'Lifecycle permission never removes launcher registration');
  finally
    LFrame.Free;
    Application.Handle := LApplicationHandle;
    LHost.Free;
  end;
end;

begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    RunChecks;
    CheckLifecycleOptions;
    Writeln('PASS: ', CheckCount, ' native options-frame UI checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Writeln('Stage: ', TestStage);
      ExitCode := 1;
    end;
  end;
end.
