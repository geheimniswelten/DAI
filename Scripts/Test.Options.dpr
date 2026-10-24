program TestOptions;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  System.UITypes,
  Vcl.Buttons,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Winapi.Windows,
  h5u.DAI.Clients.Registration in 'OptionsTests\h5u.DAI.Clients.Registration.pas',
  h5u.DAI.Codex.Registration in 'OptionsTests\h5u.DAI.Codex.Registration.pas',
  h5u.DAI.IDE.Toolbar in 'OptionsTests\h5u.DAI.IDE.Toolbar.pas',
  h5u.DAI.MCP.Tools in 'OptionsTests\h5u.DAI.MCP.Tools.pas',
  h5u.DAI.OTA.Helpers in 'OptionsTests\h5u.DAI.OTA.Helpers.pas',
  h5u.DAI.Permissions.Dialog in 'OptionsTests\h5u.DAI.Permissions.Dialog.pas',
  h5u.DAI.Permissions.Manager in 'OptionsTests\h5u.DAI.Permissions.Manager.pas',
  h5u.DAI.Runtime in 'OptionsTests\h5u.DAI.Runtime.pas',
  h5u.DAI.Registry.Editor in 'OptionsTests\h5u.DAI.Registry.Editor.pas',
  h5u.DAI.Settings in 'OptionsTests\h5u.DAI.Settings.pas',
  h5u.DAI.Consts,
  h5u.DAI.Types,
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

  TCleanupProbe = class
  public
    Failure: string;
    Seen: Boolean;
    Timer: TTimer;
    Variant: Integer;
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

function PermissionCombo(const AFrame: TDAIOptionsFrame; const AScopeName: string; const ACategory: TDAIPermissionCategory): TComboBox;
var
  LComponent: TComponent;
begin
  LComponent := AFrame.FindComponent(Format('DAIPermission%s%dComboBox', [AScopeName, Ord(ACategory)]));
  Check(LComponent is TComboBox, AScopeName + ' named permission combo exists');
  Result := TComboBox(LComponent);
end;

function PermissionDialogButton(const AFrame: TDAIOptionsFrame; const ACategory: TDAIPermissionCategory): TControl;
var
  LComponent: TComponent;
begin
  LComponent := AFrame.FindComponent(Format('DAIPermission%dDialogButton', [Ord(ACategory)]));
  Check(LComponent is TBitBtn, 'Named permission row icon button exists');
  Result := TControl(LComponent);
end;

procedure ClickPermissionDialog(const AFrame: TDAIOptionsFrame; const ACategory: TDAIPermissionCategory);
var
  LControl: TControl;
begin
  LControl := PermissionDialogButton(AFrame, ACategory);
  if LControl is TButton then
    TButton(LControl).Click
  else if LControl is TBitBtn then
    TBitBtn(LControl).Click
  else
    TSpeedButton(LControl).Click;
end;

procedure ChoosePermission(const AFrame: TDAIOptionsFrame; const AScopeName: string;
  const ACategory: TDAIPermissionCategory; const AIndex: Integer);
var
  LCombo: TComboBox;
begin
  LCombo := PermissionCombo(AFrame, AScopeName, ACategory);
  LCombo.ItemIndex := AIndex;
  if Assigned(LCombo.OnChange) then
    LCombo.OnChange(LCombo);
end;

function LifecycleControl(const AFrame: TDAIOptionsFrame): TCheckBox;
var
  LComponent: TComponent;
begin
  LComponent := AFrame.FindComponent('DAIAllowIDEStartStopCheckBox');
  Check(LComponent is TCheckBox, 'Lifecycle permission has a named checkbox');
  Result := TCheckBox(LComponent);
end;

function SharedConnectionControl(const AFrame: TDAIOptionsFrame): TCheckBox;
var
  LComponent: TComponent;
begin
  LComponent := AFrame.FindComponent('DAIUseSharedConnectionSettingsCheckBox');
  Check(LComponent is TCheckBox, 'Connection scope has a named checkbox');
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
      .AddPair('server_name', 'dai_bds37_0').AddPair('launcher_server', 'dai_bds37_0_start')
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
    Check(LMemo.Lines.Count = 11, 'Client details consume no empty separator lines');
    Check(LMemo.Lines[0] = 'Codex', 'First client has its own name header');
    Check(LMemo.Lines[8] = 'Claude Desktop', 'Second client has its own name header');
    Check(LMemo.Lines[1] = '    Status: registriert', 'Translated status is indented below client name');
    Check(LMemo.Lines[2] = '    MCP-Server: dai_bds37_0', 'Actual scoped MCP registration name is visible');
    Check(LMemo.Lines[3] = '    Starthelfer: dai_bds37_0_start', 'Matching scoped start helper name is visible');
    Check(LMemo.Lines[4] = '    C:\Synthetic\codex.toml', 'Configuration path has four spaces');
    Check(LMemo.Lines[5] = '    Nachricht eins.', 'First message line has four spaces');
    Check(LMemo.Lines[6] = '    Nachricht zwei.', 'Multiline message trims inner whitespace and uses four spaces');
    Check(LMemo.Lines[7] = '    Sicherung: C:\Synthetic\codex.toml.dai.backup', 'Backup detail has four spaces');
    Check(LMemo.Lines[9] = '    Status: manuelle Einrichtung erforderlich', 'Manual client status remains translated');
    Check(LMemo.Lines[10] = '    Hinweis.', 'Empty path and backup produce no blank lines');
    for LIndex := 0 to LMemo.Lines.Count - 1 do
    begin
      LLine := LMemo.Lines[LIndex];
      Check(Trim(LLine) <> '', 'Each rendered client status line contains content');
      Check(Pos(#9, LLine) = 0, 'Status indentation never uses tabs');
      if (LIndex <> 0) and (LIndex <> 8) then
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

procedure TCleanupProbe.InspectDialog(Sender: TObject);
var
  LDialog: TCustomForm;
  LList: TListView;
  LRemove: TButton;
  LDetails: TMemo;
  LLabel: TLabel;
  LComponent: TComponent;
begin
  Timer.Enabled := False;
  LDialog := Screen.ActiveCustomForm;
  try
    Check(Assigned(LDialog), 'Cleanup opens a native modal form');
    Check(LDialog.Name = 'DAIRegistrationCleanupDialog', 'Cleanup button opens its intended dialog');
    Seen := True;
    LList := LDialog.FindComponent('DAIRegistrationsList') as TListView;
    LRemove := LDialog.FindComponent('DAIRemoveRegistrationButton') as TButton;
    LDetails := LDialog.FindComponent('DAIRegistrationDetails') as TMemo;
    Check(Assigned(LList) and Assigned(LRemove) and Assigned(LDetails), 'Cleanup controls have stable native names');
    Check(LList.ViewStyle = vsReport, 'Cleanup presents client, names, scope and status as columns');
    Check(LList.Columns.Count = 4, 'Cleanup list contains four readable columns');
    Check(not LRemove.Enabled, 'Removing requires an explicit row selection');
    Check(LDetails.ReadOnly, 'Cleanup preview cannot edit configuration contents');
    if Variant = 0 then
    begin
      Check(LList.Items.Count = 0, 'Empty search remains empty without stale rows');
      Check(TDAIClientRegistration.RemoveFoundCount = 0, 'Empty search never removes anything');
    end
    else
    begin
      Check(LList.Items.Count = 2, 'Cleanup displays both removable and changed registrations');
      Check(LList.Items[0].SubItems[0] = 'dai_bds22_0 / dai_bds22_0_start', 'Old Delphi registration is identified by name');
      LList.Items[1].Selected := True;
      Check(not LRemove.Enabled, 'Changed or unowned registrations cannot be removed');
      Check(Pos('Unverändertheit nicht bestätigt', LDetails.Text) > 0, 'Nonremovable reason is visible in preview');
      Check(Pos('DO_NOT_DISPLAY_SECRET', LDetails.Text) = 0, 'Cleanup preview omits unrelated secret fields');
      LList.Items[0].Selected := True;
      Check(LRemove.Enabled, 'Selecting the old managed registration enables removal');
      Check(Pos('C:\Synthetic\client.json', LDetails.Text) > 0, 'Preview identifies the exact configuration file');
      LRemove.Click;
      Check(TDAIClientRegistration.RemoveFoundCount = 1, 'Explicit removal invokes the targeted backend once');
      Check(TDAIClientRegistration.LastRemovedServer = 'dai_bds22_0', 'The selected old version is passed without changing settings');
      Check(TDAIClientRegistration.FindCount = 2, 'After removal the dialog refreshes the inventory');
      Check(not LRemove.Enabled, 'Fresh results require a new explicit selection');
      LLabel := nil;
      for LComponent in LDialog do
        if LComponent is TLabel then
          LLabel := TLabel(LComponent);
      Check(Assigned(LLabel), 'Cleanup has an outcome status label');
      if Variant = 2 then
        Check(LLabel.Caption = 'Die Registrierung wurde inzwischen geändert.', 'Stale-snapshot denial is visible without a success claim')
      else
        Check(LLabel.Caption = 'Die ausgewählte Registrierung wurde entfernt.', 'Successful removal is reported explicitly');
    end;
    LDialog.ModalResult := mrClose;
  except
    on E: Exception do
    begin
      Failure := E.Message;
      if Assigned(LDialog) then
        if LDialog.Name = 'DAIRegistrationCleanupDialog' then
          LDialog.ModalResult := mrCancel;
    end;
  end;
end;

procedure CheckCleanupDialog(const AFrame: TDAIOptionsFrame);
var
  LButton: TButton;
  LProbe: TCleanupProbe;
  LVariant: Integer;
  LHealthCount: Integer;
  LPortDraft, LTokenDraft: string;
  LSharedDraft: Boolean;
begin
  LButton := ButtonControl(AFrame, 'Registrierungen suchen und entfernen');
  Check(Assigned(LButton.OnClick), 'Registration search button has its production handler');
  LPortDraft := EditControl(AFrame, True).Text;
  LTokenDraft := EditControl(AFrame, False).Text;
  LSharedDraft := SharedConnectionControl(AFrame).Checked;
  LProbe := TCleanupProbe.Create;
  LProbe.Timer := TTimer.Create(nil);
  try
    LProbe.Timer.Enabled := False;
    LProbe.Timer.Interval := 25;
    LProbe.Timer.OnTimer := LProbe.InspectDialog;
    for LVariant := 0 to 2 do
    begin
      TDAIClientRegistration.FindCount := 0;
      TDAIClientRegistration.RemoveFoundCount := 0;
      TDAIClientRegistration.FindJSON := '';
      TDAIClientRegistration.RemoveJSON := '';
      if LVariant <> 0 then
        TDAIClientRegistration.FindJSON := '{"registrations":[' +
          '{"client":"codex","label":"Codex","server_name":"dai_bds22_0","launcher_server":"dai_bds22_0_start",' +
          '"path":"C:\\Synthetic\\client.json","removable":true,"current_scope":false,"message":"Alte Delphi-Registrierung."},' +
          '{"client":"codex","label":"Codex","server_name":"dai_bds37_0","launcher_server":"dai_bds37_0_start",' +
          '"path":"C:\\Synthetic\\client.json","removable":false,"current_scope":true,' +
          '"message":"Unverändertheit nicht bestätigt","token":"DO_NOT_DISPLAY_SECRET"}]}';
      if LVariant = 2 then
        TDAIClientRegistration.RemoveJSON := '{"removed":false,"message":"Die Registrierung wurde inzwischen geändert."}';
      LProbe.Variant := LVariant;
      LProbe.Seen := False;
      LProbe.Failure := '';
      LProbe.Timer.Enabled := True;
      LHealthCount := TDAIIDEToolbar.CheckCount;
      LButton.Click;
      LProbe.Timer.Enabled := False;
      Check(LProbe.Failure = '', 'Cleanup inspection: ' + LProbe.Failure);
      Check(LProbe.Seen, 'Cleanup dialog was inspected inside its actual modal loop');
      Check(TDAIIDEToolbar.CheckCount = LHealthCount + 1, 'Cleanup completion checks toolbar registrations once after its modal loop');
      Check(TDAIClientRegistration.FindCount >= 1, 'Opening cleanup obtains an inventory');
      Check(EditControl(AFrame, True).Text = LPortDraft, 'Cleanup preserves the draft port');
      Check(EditControl(AFrame, False).Text = LTokenDraft, 'Cleanup preserves the draft token');
      Check(SharedConnectionControl(AFrame).Checked = LSharedDraft, 'Cleanup preserves the selected connection scope');
      CheckNoPersistence;
    end;
  finally
    TDAIClientRegistration.FindJSON := '';
    TDAIClientRegistration.RemoveJSON := '';
    LProbe.Timer.Free;
    LProbe.Free;
  end;
end;

procedure CheckUsageRegistryLink(const AFrame: TDAIOptionsFrame);
var
  LLink: TLinkLabel;
  LPortDraft: string;
  LTokenDraft: string;
  LStartCount: Integer;
  LStopCount: Integer;
  LStatusCount: Integer;
  LOpenResult: Boolean;
begin
  LLink := AFrame.FindComponent('DAIUsageLogLink') as TLinkLabel;
  Check(Assigned(LLink), 'Usage counters have a named native link');
  Check(LLink.TabStop, 'Usage registry link participates in keyboard navigation');
  Check(Pos('Nutzungszähler in der Registry öffnen', LLink.Caption) > 0, 'Link describes its Registry Editor destination');
  Check(Pos('HKCU\Software\DelphiAI\DAI\UsageLog', LLink.Hint) > 0, 'Link hint identifies the exact usage registry root');
  Check(Pos('Monatszähler', LLink.Hint) > 0, 'Link explains local monthly counters');
  Check(Assigned(LLink.OnLinkClick), 'Registry link has its production click handler');
  LPortDraft := EditControl(AFrame, True).Text;
  LTokenDraft := EditControl(AFrame, False).Text;
  LStartCount := TDAIRuntime.StartCount;
  LStopCount := TDAIRuntime.StopCount;
  LStatusCount := TDAIClientRegistration.StatusCount;
  RegistryEditorOpenCount := 0;
  try
    // Invalid unsaved settings cannot prevent inspecting counters or be persisted by it.
    EditControl(AFrame, True).Text := '0';
    EditControl(AFrame, False).Text := '';
    for LOpenResult := False to True do
    begin
      RegistryEditorOpenResult := LOpenResult;
      LLink.OnLinkClick(LLink, 'usage', sltID);
      Check(EditControl(AFrame, True).Text = '0', 'Opening registry preserves the invalid draft port');
      Check(EditControl(AFrame, False).Text = '', 'Opening registry preserves the empty draft token');
      CheckNoPersistence;
    end;
    Check(RegistryEditorOpenCount = 2, 'Each link activation opens the registry helper once, including cancelled launch');
    Check(RegistryEditorOwner = AFrame.Handle, 'Registry Editor launch uses the options window as its owner');
    Check(TDAIRuntime.StartCount = LStartCount, 'Opening registry does not start a server');
    Check(TDAIRuntime.StopCount = LStopCount, 'Opening registry does not stop a server');
    Check(TDAIClientRegistration.StatusCount = LStatusCount, 'Opening registry does not inspect client registrations');
  finally
    RegistryEditorOpenResult := True;
    EditControl(AFrame, True).Text := LPortDraft;
    EditControl(AFrame, False).Text := LTokenDraft;
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
      Check(not LFrame.Visible, 'Frame remains hidden');
      Check(LPortEdit.Text = IntToStr(LStoredPort), 'Initial port loaded from synthetic settings');
      Check(LTokenEdit.Text = LStoredToken, 'Initial token loaded from synthetic settings');
      Check(LStart.Enabled and not LStop.Enabled, 'Stopped server button state');
      Check(TDAIRuntime.ServerPort = 0, 'Stopped runtime reports zero port');
      TestStage := 'UsageRegistryLink';
      CheckUsageRegistryLink(LFrame);

      LPortEdit.Text := ' 7102 ';
      LTokenEdit.Text := '  synthetic-current-options-token  ';
      TestStage := 'ClientStatusFormatting';
      CheckStatusFormatting(LFrame);
      TestStage := 'CatalogDialog';
      CheckCatalogDialog(LFrame);
      TestStage := 'CleanupDialog';
      CheckCleanupDialog(LFrame);
      Check(LPortEdit.Text = ' 7102 ', 'Catalog preserves draft port');
      Check(LTokenEdit.Text = '  synthetic-current-options-token  ', 'Catalog preserves draft bearer token');
      TestStage := 'StartStopSettings';
      Check(TDAIPermissionManager.Instance.GlobalReadCount > 0, 'Frame reads global permissions');
      Check(TDAIPermissionManager.Instance.ProjectReadCount > 0, 'Frame reads active project permissions');

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

procedure CheckConnectionScopeOptions;
var
  LFrame: TDAIOptionsFrame;
  LHost: TForm;
  LApplicationHandle: HWND;
  LCheckBox: TCheckBox;
  LPortEdit, LTokenEdit: TEdit;
  LStoredPort, LReadCount: Integer;
  LStoredToken: string;
  LFailed: Boolean;
begin
  TestStage := 'ConnectionScopeOptions';
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  TDAIClientRegistration.RegisterCount := 0;
  TDAIClientRegistration.UnregisterCount := 0;
  LStoredPort := TDAISettings.Instance.Port;
  LStoredToken := TDAISettings.Instance.Token;
  TDAISettings.Instance.SavedConnectionAvailable[True] := True;
  TDAISettings.Instance.SavedConnectionPort[True] := LStoredPort;
  TDAISettings.Instance.SavedConnectionToken[True] := LStoredToken;
  TDAISettings.Instance.SavedConnectionAvailable[False] := True;
  TDAISettings.Instance.SavedConnectionPort[False] := 7222;
  TDAISettings.Instance.SavedConnectionToken[False] := 'synthetic-local-connection-token';
  LHost := TForm.CreateNew(nil);
  LFrame := nil;
  LApplicationHandle := Application.Handle;
  try
    LHost.Visible := False;
    Application.Handle := LHost.Handle;
    LFrame := TDAIOptionsFrame.Create(nil);
    LFrame.Visible := False;
    LFrame.Parent := LHost;
    LCheckBox := SharedConnectionControl(LFrame);
    Check(LCheckBox.Checked, 'New connection scope checkbox defaults to shared');
    LFrame.LoadFromSettings;
    LPortEdit := EditControl(LFrame, True);
    LTokenEdit := EditControl(LFrame, False);
    Check(LCheckBox.Checked, 'Saved shared mode is shown after loading');
    Check(TDAISettings.Instance.ConnectionReadCount = 0, 'Programmatic load does not execute a destination preview');
    Check(TDAISettings.Instance.ConnectionRefreshCount = 1, 'Opening options refreshes external connection changes before displaying credentials');
    Check(LCheckBox.Top < LPortEdit.Top, 'Connection scope sits immediately before port and token controls');
    Check(LCheckBox.ShowHint and (Pos('IDE-Profil', LCheckBox.Hint) > 0), 'Connection scope hint explains the local IDE profile');
    Check(Pos('Andere DAI-Einstellungen bleiben IDE-spezifisch', LCheckBox.Hint) > 0, 'Connection scope does not imply sharing other options');
    Check(Pos('Speichern oder Registrieren', LCheckBox.Hint) > 0, 'Connection scope explains deferred persistence');
    LPortEdit.Text := ' 7223 ';
    LTokenEdit.Text := ' synthetic-shared-draft-token ';
    TDAISettings.Instance.FailConnectionRead := True;
    LFailed := False;
    try
      LCheckBox.Checked := False;
    except
      on E: Exception do
        LFailed := E.Message = 'Synthetic connection-preview failure';
    end;
    Check(LFailed, 'Destination preview failure remains visible to the options caller');
    Check(LCheckBox.Checked, 'Failed destination preview restores the previous checkbox scope');
    Check((LPortEdit.Text = ' 7223 ') and (LTokenEdit.Text = ' synthetic-shared-draft-token '), 'Failed preview preserves the previous scope draft pair');
    Check(TDAISettings.Instance.UseSharedConnectionSettings, 'Failed preview does not alter the singleton scope');
    Check(TDAISettings.Instance.SaveCount = 0, 'Failed preview performs no settings save');
    TDAISettings.Instance.FailConnectionRead := False;
    LCheckBox.Checked := False;
    Check(LPortEdit.Text = '7222', 'Switching to local previews its saved port');
    Check(LTokenEdit.Text = 'synthetic-local-connection-token', 'Switching to local previews its matching saved token');
    Check(TDAISettings.Instance.UseSharedConnectionSettings, 'Scope preview does not change the singleton mode');
    Check((TDAISettings.Instance.Port = LStoredPort) and (TDAISettings.Instance.Token = LStoredToken), 'Scope preview does not change the active singleton credentials');
    CheckNoPersistence;
    LPortEdit.Text := '7224';
    LTokenEdit.Text := ' synthetic-local-draft-token ';
    LCheckBox.Checked := True;
    Check((LPortEdit.Text = ' 7223 ') and (LTokenEdit.Text = ' synthetic-shared-draft-token '), 'Returning to shared restores its untouched draft');
    LReadCount := TDAISettings.Instance.ConnectionReadCount;
    LCheckBox.Checked := False;
    Check((LPortEdit.Text = '7224') and (LTokenEdit.Text = ' synthetic-local-draft-token '), 'Returning to local restores its own draft');
    Check(TDAISettings.Instance.ConnectionReadCount = LReadCount, 'Revisiting a scope preserves its draft without replacing it from storage');
    ButtonControl(LFrame, 'Server starten').Click;
    Check((TDAIRuntime.CapturedPort = 7224) and (TDAIRuntime.CapturedToken = 'synthetic-local-draft-token'), 'Manual start uses the displayed destination draft pair');
    Check(TDAISettings.Instance.UseSharedConnectionSettings, 'Transient server start does not persist the scope selection');
    CheckNoPersistence;
    ButtonControl(LFrame, 'Server stoppen').Click;
    LFrame.StoreToSettings;
    Check(not TDAISettings.Instance.UseSharedConnectionSettings, 'Accepting options stores the selected local scope');
    Check((TDAISettings.Instance.Port = 7224) and (TDAISettings.Instance.Token = 'synthetic-local-draft-token'), 'Accepting options stores the displayed pair with its scope');
    Check((TDAISettings.Instance.SavedConnectionPort[True] = LStoredPort) and
      (TDAISettings.Instance.SavedConnectionToken[True] = LStoredToken), 'Saving local credentials preserves the common destination');
    Check((TDAISettings.Instance.SavedConnectionPort[False] = 7224) and
      (TDAISettings.Instance.SavedConnectionToken[False] = 'synthetic-local-draft-token'), 'Saving targets only the selected destination');

    // A previously unconfigured scope adopts the current draft; it must not silently revert user edits.
    TDAISettings.Instance.SavedConnectionAvailable[True] := False;
    LPortEdit.Text := '7225';
    LTokenEdit.Text := 'synthetic-first-common-token';
    LCheckBox.Checked := True;
    Check((LPortEdit.Text = '7225') and (LTokenEdit.Text = 'synthetic-first-common-token'), 'Missing destination retains the current user-entered draft pair');
    Check(not TDAISettings.Instance.UseSharedConnectionSettings, 'Missing-destination preview also remains a draft');
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.UseSharedConnectionSettings, 'Accepting the new common destination stores shared mode');
    Check((TDAISettings.Instance.SavedConnectionPort[True] = 7225) and
      (TDAISettings.Instance.SavedConnectionToken[True] = 'synthetic-first-common-token'), 'New common destination receives the displayed draft pair');
    Check(TDAISettings.Instance.SavedConnectionPort[False] = 7224, 'Creating common credentials preserves the local destination');

    LCheckBox.Checked := False;
    Check(LPortEdit.Text = '7224', 'After saving, switching scopes refreshes the destination preview');
    FreeAndNil(LFrame);
    Check(TDAISettings.Instance.UseSharedConnectionSettings, 'Cancelling a local preview preserves the last saved common mode');
    Check(TDAISettings.Instance.Port = 7225, 'Cancelling a scope preview preserves the saved common credentials');
    LFrame := TDAIOptionsFrame.Create(nil);
    LFrame.Visible := False;
    LFrame.Parent := LHost;
    LFrame.LoadFromSettings;
    LCheckBox := SharedConnectionControl(LFrame);
    Check(LCheckBox.Checked, 'Reopening after cancellation reloads the common mode');
    LCheckBox.Checked := False;
    ButtonControl(LFrame, 'Registrieren').Click;
    Check(not TDAISettings.Instance.UseSharedConnectionSettings, 'Explicit registration stores the selected destination scope');
    Check(TDAISettings.Instance.Port = 7224, 'Explicit registration stores the selected saved destination pair');
    Check(TDAIClientRegistration.RegisterCount = 1, 'Explicit registration uses the ordinary client-registration path');
  finally
    LFrame.Free;
    Application.Handle := LApplicationHandle;
    LHost.Free;
  end;
end;

procedure CheckRegistrationHealthRefresh;
var
  LHost: TForm;
  LFrame: TDAIOptionsFrame;
  LApplicationHandle: HWND;
  LPort, LToken: TEdit;
  LScope: TCheckBox;
  LComponent: TComponent;
  LClient: TComboBox;
  LStoredPort: Integer;
  LStoredToken: string;

  procedure CreateFrame;
  begin
    LFrame := TDAIOptionsFrame.Create(nil);
    LFrame.Visible := False;
    LFrame.Parent := LHost;
    LFrame.LoadFromSettings;
    LPort := EditControl(LFrame, True);
    LToken := EditControl(LFrame, False);
    LScope := SharedConnectionControl(LFrame);
  end;

begin
  TestStage := 'RegistrationHealthRefresh';
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  TDAIIDEToolbar.Reset;
  TDAIClientRegistration.RegisterCount := 0;
  TDAIClientRegistration.UnregisterCount := 0;
  LStoredPort := TDAISettings.Instance.Port;
  LStoredToken := TDAISettings.Instance.Token;
  TDAISettings.Instance.SavedConnectionAvailable[False] := True;
  TDAISettings.Instance.SavedConnectionPort[False] := 7441;
  TDAISettings.Instance.SavedConnectionToken[False] := 'synthetic-local-health-token';
  LHost := TForm.CreateNew(nil);
  LFrame := nil;
  LApplicationHandle := Application.Handle;
  try
    LHost.Visible := False;
    Application.Handle := LHost.Handle;
    CreateFrame;
    Check(TDAIIDEToolbar.CheckCount = 1, 'Loading options performs one fresh toolbar registration check');
    Check(TDAIIDEToolbar.LastShared and (TDAIIDEToolbar.LastPort = LStoredPort), 'Initial health check uses effective saved settings');
    LPort.Text := '7442';
    LToken.Text := 'synthetic-shared-health-draft';
    LScope.Checked := False;
    LPort.Text := '7443';
    LToken.Text := 'synthetic-local-health-draft';
    LClient := nil;
    for LComponent in LFrame do
      if LComponent is TComboBox then
        if TComboBox(LComponent).Items.Count = 10 then
          LClient := TComboBox(LComponent);
    Check(Assigned(LClient), 'Client selector exists for isolated health refresh test');
    LClient.ItemIndex := 1;
    LClient.OnChange(LClient);
    Check(TDAIIDEToolbar.CheckCount = 1, 'Scope, credential and client drafts do not rescan or replace toolbar health');
    Check(TDAISettings.Instance.UseSharedConnectionSettings, 'Draft connection scope does not change effective health settings');
    FreeAndNil(LFrame);
    Check(TDAIIDEToolbar.CheckCount = 1, 'Cancelling draft options leaves toolbar health unchanged');
    Check((TDAISettings.Instance.Port = LStoredPort) and (TDAISettings.Instance.Token = LStoredToken), 'Cancellation preserves effective credential pair');
    Check(TDAISettings.Instance.SaveCount = 0, 'Cancellation never saves health-related drafts');

    CreateFrame;
    Check(TDAIIDEToolbar.CheckCount = 2, 'Reopening options checks the current effective registration state');
    Check(TDAIIDEToolbar.LastShared and (TDAIIDEToolbar.LastToken = LStoredToken), 'Reopening health ignores cancelled local scope and token');
    LScope.Checked := False;
    LPort.Text := '7444';
    LToken.Text := 'synthetic-local-health-accepted';
    ButtonControl(LFrame, 'Server starten').Click;
    Check(TDAIIDEToolbar.CheckCount = 3, 'Manual activation checks registration health once');
    Check(TDAIIDEToolbar.LastStartCount = 1, 'Activation refresh runs after the runtime start');
    Check(TDAIIDEToolbar.LastShared and (TDAIIDEToolbar.LastPort = LStoredPort), 'Transient activation does not commit scope or credentials to health settings');
    ButtonControl(LFrame, 'Server stoppen').Click;
    Check(TDAIIDEToolbar.CheckCount = 4, 'Manual deactivation checks registration health once');
    Check(TDAIIDEToolbar.LastStopCount = 1, 'Deactivation refresh runs after the runtime stop');
    LFrame.StoreToSettings;
    Check(TDAIIDEToolbar.CheckCount = 5, 'Accepting settings checks registration health once');
    Check((TDAIIDEToolbar.LastSaveCount = 1) and not TDAIIDEToolbar.LastShared, 'Health refresh sees the saved destination scope');
    Check((TDAIIDEToolbar.LastPort = 7444) and (TDAIIDEToolbar.LastToken = 'synthetic-local-health-accepted'), 'Health refresh sees the saved credential pair');
    Check(TDAIRuntime.ApplyCount = 1, 'Accepted settings apply runtime state before health refresh');
    LPort.Text := '7445';
    ButtonControl(LFrame, 'Registrieren').Click;
    Check(TDAIIDEToolbar.CheckCount = 6, 'Register performs one final health check without an intermediate save check');
    Check((TDAIIDEToolbar.LastSaveCount = 2) and (TDAIIDEToolbar.LastRegisterCount = 1), 'Registration health sees both the saved options and completed registration');
    Check(TDAIIDEToolbar.LastPort = 7445, 'Registration health sees the newly registered destination port');
    LPort.Text := '7446';
    LToken.Text := 'synthetic-unaccepted-after-registration';
    ButtonControl(LFrame, 'Deregistrieren').Click;
    Check(TDAIIDEToolbar.CheckCount = 7, 'Deregister performs one final health check');
    Check(TDAIIDEToolbar.LastUnregisterCount = 1, 'Deregistration health runs after client removal');
    Check((TDAIIDEToolbar.LastSaveCount = 2) and (TDAIIDEToolbar.LastPort = 7445), 'Deregistration health preserves unsaved connection drafts');
    Check(TDAIIDEToolbar.LastToken = 'synthetic-local-health-accepted', 'Deregistration health uses the effective saved token');
    Check(not TDAIIDEToolbar.OffMainThread, 'All options registration health hooks execute on the IDE UI thread');
  finally
    LFrame.Free;
    Application.Handle := LApplicationHandle;
    LHost.Free;
  end;
end;

procedure CheckPermissionColumns;
var
  LFrame: TDAIOptionsFrame;
  LHost: TForm;
  LApplicationHandle: HWND;
  LOriginalProject: string;
  LLoadedProject: string;
  LManager: TDAIPermissionManager;
  LCategory: TDAIPermissionCategory;
  LGlobal, LProject: TComboBox;
  LDialogButton: TControl;
  LWriteCount, LCallCount, LSettingsSaveCount: Integer;
  LWrite: TPermissionWrite;
  LFailed: Boolean;

  procedure CreateFrame;
  begin
    LFrame := TDAIOptionsFrame.Create(nil);
    LFrame.Visible := False;
    LFrame.Parent := LHost;
    LFrame.LoadFromSettings;
    LHost.ClientWidth := LFrame.Width;
    LHost.ClientHeight := LFrame.Height;
  end;

begin
  TestStage := 'PermissionColumns';
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  TDAIPermissionDialog.Reset;
  LManager := TDAIPermissionManager.Instance;
  LOriginalProject := SyntheticProjectFileName;
  LLoadedProject := 'C:\SyntheticDAITest\PermissionColumns.dproj';
  SyntheticProjectFileName := LLoadedProject;
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
  begin
    LManager.GlobalLevels[LCategory] := plNever;
    LManager.ProjectLevels[LCategory] := plNever;
    LManager.ProjectInherits[LCategory] := False;
  end;
  LManager.GlobalLevels[pcReadAccess] := plAlways;
  LManager.GlobalLevels[pcCompile] := plAsk;
  LManager.ProjectLevels[pcReadAccess] := plSession;
  LManager.ProjectInherits[pcEditOutsideIDE] := True;
  LHost := TForm.CreateNew(nil);
  LFrame := nil;
  LApplicationHandle := Application.Handle;
  try
    LHost.Visible := False;
    Application.Handle := LHost.Handle;
    CreateFrame;
    for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    begin
      LGlobal := PermissionCombo(LFrame, 'Global', LCategory);
      LProject := PermissionCombo(LFrame, 'Project', LCategory);
      Check(LGlobal.Enabled and LProject.Enabled, 'Both permission columns enabled with active project');
      Check((LGlobal.Width = 190) and (LProject.Width = 190), 'Permission combos use requested 190-pixel width');
      Check((LGlobal.Top = LProject.Top) and (LGlobal.Left + LGlobal.Width < LProject.Left), 'Permission choices share a row side by side');
      LDialogButton := PermissionDialogButton(LFrame, LCategory);
      Check(LDialogButton.Enabled, 'Permission row dialog button enabled');
      Check((LDialogButton.Left > LProject.Left + LProject.Width) and
        (Abs(LDialogButton.Top - LProject.Top) <= 2), 'Single permission dialog button sits to the right of both choices');
      Check((LFrame.FindComponent(Format('DAIPermissionGlobal%dDialogButton', [Ord(LCategory)])) = nil) and
        (LFrame.FindComponent(Format('DAIPermissionProject%dDialogButton', [Ord(LCategory)])) = nil), 'No per-column permission dialog buttons remain');
      Check(Pos('projekt', LowerCase(LDialogButton.Hint)) > 0, 'Row button hint identifies active project scope');
      Check((LGlobal.Items.Count = 6) and (LProject.Items.Count = 7), 'Only project choices include inheritance');
      Check(LProject.Items[6] = 'Default', 'Project inheritance label stays concise');
    end;
    Check(PermissionCombo(LFrame, 'Global', pcReadAccess).ItemIndex = 5, 'Global column loads its independent level');
    Check(PermissionCombo(LFrame, 'Project', pcReadAccess).ItemIndex = 4, 'Project column loads its independent override');
    Check(PermissionCombo(LFrame, 'Project', pcEditOutsideIDE).ItemIndex = 6, 'Inherited project value is visibly Default');
    LFrame.StoreToSettings;
    Check(LManager.WriteCount = 0, 'Unchanged save does not materialize inherited or explicit permission values');

    EditControl(LFrame, True).Text := '7123';
    EditControl(LFrame, False).Text := ' synthetic-permission-column-token ';
    ChoosePermission(LFrame, 'Global', pcCompile, 4);
    ChoosePermission(LFrame, 'Global', pcEditInsideIDE, 4);
    ChoosePermission(LFrame, 'Global', pcEditOutsideIDE, 4);
    ChoosePermission(LFrame, 'Global', pcExecute, 4);
    TDAIPermissionDialog.NextLevel := plSession;
    TDAIPermissionDialog.NextApplyToLowerLevels := True;
    ClickPermissionDialog(LFrame, pcCompile);
    Check(TDAIPermissionDialog.LastProjectKey = LLoadedProject, 'Row dialog defaults to captured active project');
    Check(TDAIPermissionDialog.LastCurrentLevel = plNever, 'Dialog sees current project draft');
    Check(PermissionCombo(LFrame, 'Project', pcCompile).ItemIndex = 1, 'Cancelled permission dialog preserves current project choice');
    Check(LManager.WriteCount = 0, 'Cancelled dialog writes no permission');

    TDAIPermissionDialog.NextAccepted := True;
    ClickPermissionDialog(LFrame, pcCompile);
    Check(PermissionCombo(LFrame, 'Project', pcCompile).ItemIndex = 4, 'Accepted row dialog stages project level');
    Check(PermissionCombo(LFrame, 'Project', pcEditInsideIDE).ItemIndex = 4, 'Lower project grant is raised in same draft');
    Check(PermissionCombo(LFrame, 'Project', pcExecute).ItemIndex = 4, 'Apply-to-lower also raises another project category');
    Check(PermissionCombo(LFrame, 'Project', pcReadAccess).ItemIndex = 4, 'Apply-to-lower preserves an equal existing project grant');
    Check(PermissionCombo(LFrame, 'Project', pcEditOutsideIDE).ItemIndex = 6, 'Equal effective inherited grant stays Default');
    Check(PermissionCombo(LFrame, 'Global', pcReadAccess).ItemIndex = 5, 'Project row dialog preserves stronger global grant');
    Check(PermissionCombo(LFrame, 'Global', pcCompile).ItemIndex = 4, 'Project row dialog preserves independently staged global choice');
    Check(LManager.WriteCount = 0, 'Accepted permission dialog stages without immediate persistence');
    Check(EditControl(LFrame, True).Text = '7123', 'Permission dialog preserves draft port');
    Check(EditControl(LFrame, False).Text = ' synthetic-permission-column-token ', 'Permission dialog preserves draft bearer token');

    TDAIPermissionDialog.NextLevel := plOnce;
    TDAIPermissionDialog.NextApplyToLowerLevels := False;
    ClickPermissionDialog(LFrame, pcExecute);
    Check(TDAIPermissionDialog.LastProjectKey = LLoadedProject, 'Project dialog uses captured active project');
    Check(PermissionCombo(LFrame, 'Project', pcExecute).ItemIndex = 3, 'Project selection is staged independently');
    Check(PermissionCombo(LFrame, 'Global', pcExecute).ItemIndex = 4, 'Project dialog leaves global selection unchanged');
    Check(LManager.WriteCount = 0, 'Both columns remain drafts until options are saved');
    SyntheticProjectFileName := 'C:\SyntheticDAITest\OtherProject.dproj';
    LSettingsSaveCount := TDAISettings.Instance.SaveCount;
    LFailed := False;
    try
      LFrame.StoreToSettings;
    except
      on E: EInvalidOperation do
        LFailed := Pos('aktive Projekt hat gewechselt', E.Message) > 0;
    end;
    Check(LFailed, 'Project switch rejects a captured permission draft');
    Check((LManager.WriteCount = 0) and (TDAISettings.Instance.SaveCount = LSettingsSaveCount), 'Project guard runs before any persistence');
    Check(not PermissionCombo(LFrame, 'Project', pcExecute).Enabled, 'Project switch disables captured project controls');
    SyntheticProjectFileName := LLoadedProject;
    LFrame.StoreToSettings;
    Check((LManager.GlobalWriteCount = 4) and (LManager.ProjectWriteCount = 3), 'Only changed fields in each scope are persisted');
    for LWrite in LManager.Writes do
      Check((LWrite.ProjectKey = '') or (LWrite.ProjectKey = LLoadedProject), 'Project switch cannot redirect a captured permission draft');
    Check(LManager.ProjectInherits[pcEditOutsideIDE], 'Saving other edits does not materialize inherited project values');
    LWriteCount := LManager.WriteCount;
    LManager.GlobalLevels[pcReadAccess] := plNever;
    LFrame.StoreToSettings;
    Check(LManager.WriteCount = LWriteCount, 'Repeated unchanged save does not replay permission grants');
    Check(LManager.GlobalLevels[pcReadAccess] = plNever, 'Unchanged stale field preserves an external permission update');

    ChoosePermission(LFrame, 'Project', pcExecute, 6);
    Check(LManager.ResetCount = 0, 'Selecting Default only stages an override reset');
    LFrame.StoreToSettings;
    Check((LManager.ResetCount = 1) and LManager.ProjectInherits[pcExecute], 'Accepted options reset project override to global inheritance');
    Check(LManager.Writes[High(LManager.Writes)].ProjectKey = LLoadedProject, 'Reset targets captured project');
    Check(LManager.Writes[High(LManager.Writes)].UseGlobal, 'Reset uses dedicated inheritance operation');
    LWriteCount := LManager.WriteCount;
    LFrame.StoreToSettings;
    Check(LManager.WriteCount = LWriteCount, 'Unchanged Default is not reset repeatedly');

    TDAIPermissionDialog.NextLevel := plSession;
    ClickPermissionDialog(LFrame, pcExecute);
    Check(TDAIPermissionDialog.LastCurrentLevel = plSession, 'Inherited dialog starts from the effective global value');
    Check(PermissionCombo(LFrame, 'Project', pcExecute).ItemIndex = 4, 'Accepting equal effective level stages an explicit override');
    Check(LManager.WriteCount = LWriteCount, 'Equal-level override remains a draft until saved');
    LFrame.StoreToSettings;
    Check((LManager.WriteCount = LWriteCount + 1) and not LManager.ProjectInherits[pcExecute], 'Explicit equal-level choice stops inheritance');
    ChoosePermission(LFrame, 'Project', pcExecute, 6);
    LFrame.StoreToSettings;
    Check((LManager.ResetCount = 2) and LManager.ProjectInherits[pcExecute], 'Explicit override can be returned to Default');
    LWriteCount := LManager.WriteCount;

    ChoosePermission(LFrame, 'Global', pcExecute, 3);
    TDAISettings.Instance.FailSave := True;
    LFailed := False;
    try
      LFrame.StoreToSettings;
    except
      on E: Exception do
        LFailed := E.Message = 'Synthetic settings-save failure';
    end;
    Check(LFailed and (LManager.WriteCount = LWriteCount), 'Failed settings save does not persist staged permission changes');
    TDAISettings.Instance.FailSave := False;
    LFrame.StoreToSettings;
    Check((LManager.WriteCount = LWriteCount + 1) and (LManager.GlobalLevels[pcExecute] = plOnce), 'Permission draft survives a failed save for retry');
    ChoosePermission(LFrame, 'Project', pcExecute, 5);
    LWriteCount := LManager.WriteCount;
    FreeAndNil(LFrame);
    Check((LManager.WriteCount = LWriteCount) and LManager.ProjectInherits[pcExecute], 'Cancelling options discards explicit project draft');

    SyntheticProjectFileName := '';
    CreateFrame;
    for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    begin
      Check(PermissionCombo(LFrame, 'Global', LCategory).Enabled, 'Global permissions remain editable without active project');
      Check(not PermissionCombo(LFrame, 'Project', LCategory).Enabled, 'Project permissions disabled without active project');
      LDialogButton := PermissionDialogButton(LFrame, LCategory);
      Check(LDialogButton.Enabled, 'Row permission dialog remains available without active project');
      Check(Pos('global', LowerCase(LDialogButton.Hint)) > 0, 'No-project row button hint identifies global scope');
    end;
    LCallCount := TDAIPermissionDialog.CallCount;
    TDAIPermissionDialog.NextLevel := plAlways;
    ClickPermissionDialog(LFrame, pcReadAccess);
    Check(TDAIPermissionDialog.CallCount = LCallCount + 1, 'No-project row button opens its permission selector');
    Check(TDAIPermissionDialog.LastProjectKey = '', 'No-project row dialog explicitly targets global scope');
    Check(PermissionCombo(LFrame, 'Global', pcReadAccess).ItemIndex = 5, 'No-project row dialog stages global permission choice');
    Check(LManager.WriteCount = LWriteCount, 'No-project dialog also waits for accepted options before persistence');
    ChoosePermission(LFrame, 'Project', pcReadAccess, 5);
    ChoosePermission(LFrame, 'Global', pcReadAccess, 5);
    LFrame.StoreToSettings;
    Check(LManager.WriteCount = LWriteCount + 1, 'No-project save persists only changed global field');
    Check((LManager.Writes[High(LManager.Writes)].ProjectKey = '') and not LManager.Writes[High(LManager.Writes)].UseGlobal,
      'Disabled project drafts never fall back to global writes');
  finally
    LFrame.Free;
    Application.Handle := LApplicationHandle;
    LHost.Free;
    SyntheticProjectFileName := LOriginalProject;
  end;
end;

begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    RunChecks;
    CheckLifecycleOptions;
    CheckConnectionScopeOptions;
    CheckPermissionColumns;
    CheckRegistrationHealthRefresh;
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
