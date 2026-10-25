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
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Winapi.Messages,
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
  h5u.DAI.Localization,
  h5u.DAI.Types,
  h5u.DAI.Options.Frame in '..\Source\h5u.DAI.Options.Frame.pas';

const
  CManualTitles: array[TDAILanguage] of string = ('DAI – Manual client registration', 'DAI – Manuelle Client-Registrierung',
    'DAI – Inscription manuelle du client', 'DAI – クライアントの手動登録');
  CCopyCaptions: array[TDAILanguage] of string = ('Copy details', 'Angaben kopieren', 'Copier les informations', '詳細をコピー');
  CCloseCaptions: array[TDAILanguage] of string = ('Close', 'Schließen', 'Fermer', '閉じる');

type
  TCatalogProbe = class
  public
    Failure: string;
    Seen: Boolean;
    Variant: Integer;
    Timer: TTimer;
    procedure InspectDialog(Sender: TObject);
  end;

  TManualRegistrationProbe = class
  public
    Failure: string;
    Seen: Boolean;
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

function ManualRegistrationControl(const AFrame: TDAIOptionsFrame): TCheckBox;
var
  LComponent: TComponent;
begin
  LComponent := AFrame.FindComponent('DAIManualClientRegistrationCheckBox');
  Check(LComponent is TCheckBox, 'Manual registration has a named checkbox');
  Result := TCheckBox(LComponent);
end;

procedure TManualRegistrationProbe.InspectDialog(Sender: TObject);
var
  LDialog: TCustomForm;
  LMemo: TMemo;
  LCopy: TButton;
  LClose: TButton;
  LComponent: TComponent;
begin
  Timer.Enabled := False;
  LDialog := Screen.ActiveCustomForm;
  try
    Check(Assigned(LDialog), 'Manual registration opens a native modal form');
    Check(LDialog.Name = 'DAIManualRegistrationDialog', 'Manual registration opens its intended isolated dialog');
    Seen := True;
    Check(LDialog.Caption = CManualTitles[DAILanguage], 'Manual dialog title follows the IDE language');
    LMemo := LDialog.FindComponent('DAIManualRegistrationMemo') as TMemo;
    LCopy := LDialog.FindComponent('DAIManualRegistrationCopyButton') as TButton;
    Check(Assigned(LMemo) and Assigned(LCopy), 'Manual registration memo and explicit copy button are named');
    Check(LCopy.Caption = CCopyCaptions[DAILanguage], 'Manual copy action follows the IDE language');
    Check(LMemo.ReadOnly, 'Registration preview cannot edit connection details');
    Check(LMemo.ScrollBars = ssBoth, 'Manual registration text supports both scrollbars');
    Check(not LMemo.WordWrap, 'Manual registration preserves configuration formatting');
    Check(LMemo.Anchors = [akLeft, akTop, akRight, akBottom], 'Manual registration text grows with its dialog');
    Check(Pos('Synthetic manual registration for ' + TDAIClientRegistration.LastManualClient, LMemo.Text) > 0,
      'Manual dialog displays the exact selected client backend result');
    Check(Pos(TDAIClientRegistration.LastManualToken, LMemo.Text) > 0, 'Manual registration displays the current synthetic draft token');
    Check(Assigned(LCopy.OnClick) and LCopy.Enabled, 'Copying is available through an explicit button');
    LClose := nil;
    for LComponent in LDialog do
      if LComponent is TButton then
        if TButton(LComponent).Cancel then
          LClose := TButton(LComponent);
    Check(Assigned(LClose), 'Manual registration dialog offers an Escape-enabled close button');
    Check(LClose.Caption = CCloseCaptions[DAILanguage], 'Manual close action follows the IDE language');
    Check(Pos('{"mcpServers":{"dai":{"type":"http"}}}', LMemo.Text) > 0, 'Manual dialog preserves the exact JSON example');
    Check(Pos('C:\Synthetic\日本語\client.json', LMemo.Text) > 0, 'Manual dialog preserves Unicode configuration paths');
    Check(LClose.ModalResult <> mrNone, 'Manual registration close button has a modal result');
    LClose.Click;
    Check(LDialog.ModalResult <> mrNone, 'Close button exits the actual modal loop');
  except
    on E: Exception do
    begin
      Failure := E.Message;
      if Assigned(LDialog) then
        if LDialog.Name = 'DAIManualRegistrationDialog' then
          LDialog.ModalResult := mrCancel;
    end;
  end;
end;

procedure CheckManualRegistrationOptions;
const
  CClientIndices: array[0..2] of Integer = (0, 1, 3);
  CClients: array[0..2] of string = ('all', 'codex', 'claude-desktop');
var
  LHost: TForm;
  LFrame: TDAIOptionsFrame;
  LApplicationHandle: HWND;
  LManual: TCheckBox;
  LScope: TCheckBox;
  LButton: TButton;
  LClient: TComboBox;
  LProbe: TManualRegistrationProbe;
  LIndex: Integer;
  LHealthCount: Integer;
  LReadCount: Integer;
  LWriteCount: Integer;
  LFailed: Boolean;

  procedure CreateFrame;
  begin
    LFrame := TDAIOptionsFrame.Create(nil);
    LFrame.Visible := False;
    LFrame.Parent := LHost;
    LFrame.LoadFromSettings;
    LManual := ManualRegistrationControl(LFrame);
    LScope := SharedConnectionControl(LFrame);
  end;

begin
  TestStage := 'ManualRegistrationOptions';
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  TDAIIDEToolbar.Reset;
  TDAIClientRegistration.RegisterCount := 0;
  TDAIClientRegistration.UnregisterCount := 0;
  TDAIClientRegistration.ManualInfoCount := 0;
  TDAISettings.Instance.SavedManualClientRegistration[False] := True;
  LHost := TForm.CreateNew(nil);
  LFrame := nil;
  LProbe := nil;
  LApplicationHandle := Application.Handle;
  try
    LHost.Visible := False;
    Application.Handle := LHost.Handle;
    CreateFrame;
    Check(not LManual.Checked and not TDAISettings.Instance.ManualClientRegistration,
      'Manual registration defaults to false in the active shared connection scope');
    Check(LManual.Caption = 'Manuell registriert', 'Manual registration checkbox has the requested caption');
    LManual.Checked := True;
    Check(not TDAISettings.Instance.ManualClientRegistration, 'Checkbox changes remain an options draft');
    TDAISettings.Instance.FailConnectionRead := True;
    LFailed := False;
    try
      LScope.Checked := False;
    except
      on E: Exception do
        LFailed := E.Message = 'Synthetic connection-preview failure';
    end;
    TDAISettings.Instance.FailConnectionRead := False;
    Check(LFailed and LScope.Checked and LManual.Checked, 'Failed connection preview restores its original scope and manual flag draft');
    Check(TDAISettings.Instance.UseSharedConnectionSettings, 'Failed preview leaves the effective saved scope unchanged');
    TDAISettings.Instance.FailManualRegistrationRead := True;
    LFailed := False;
    try
      LScope.Checked := False;
    except
      on E: Exception do
        LFailed := E.Message = 'Synthetic manual-registration-preview failure';
    end;
    TDAISettings.Instance.FailManualRegistrationRead := False;
    Check(LFailed and LScope.Checked and LManual.Checked, 'Failed flag preview restores the previous scope and unsaved acknowledgement');
    Check(EditControl(LFrame, True).Text = IntToStr(TDAISettings.Instance.Port), 'Failed flag preview restores its matching port');
    Check(EditControl(LFrame, False).Text = TDAISettings.Instance.Token, 'Failed flag preview restores its matching token');
    LScope.Checked := False;
    Check(LManual.Checked, 'Switching connection scope loads its separately saved manual flag');
    LManual.Checked := False;
    Check(TDAISettings.Instance.SavedManualClientRegistration[False], 'Editing local manual flag does not persist it');
    LScope.Checked := True;
    Check(LManual.Checked, 'Returning to the shared scope restores its unsaved manual registration draft');
    LScope.Checked := False;
    Check(not LManual.Checked, 'Returning to the local scope restores its separate unsaved draft');
    FreeAndNil(LFrame);
    Check((TDAISettings.Instance.SaveCount = 0) and (TDAISettings.Instance.ManualRegistrationWriteCount = 0),
      'Cancelling manual registration drafts saves neither settings nor flags');
    Check(not TDAISettings.Instance.ManualClientRegistration and TDAISettings.Instance.UseSharedConnectionSettings,
      'Cancellation preserves the effective shared scope and its saved false flag');
    CreateFrame;
    Check(not LManual.Checked, 'Reopening options discards the cancelled shared manual flag');
    LScope.Checked := False;
    Check(LManual.Checked, 'Reopening also preserves the saved local manual flag');

    LClient := LFrame.FindComponent('DAIClientComboBox') as TComboBox;
    LButton := LFrame.FindComponent('DAIManualRegistrationButton') as TButton;
    Check(Assigned(LClient) and Assigned(LButton), 'Manual registration button and client selector have stable names');
    Check(LButton.Caption = 'Manuell registrieren…', 'Manual registration button has the requested caption');
    LProbe := TManualRegistrationProbe.Create;
    LProbe.Timer := TTimer.Create(nil);
    LProbe.Timer.Enabled := False;
    LProbe.Timer.Interval := 25;
    LProbe.Timer.OnTimer := LProbe.InspectDialog;
    EditControl(LFrame, True).Text := ' 7457 ';
    EditControl(LFrame, False).Text := ' synthetic-manual-preview-draft ';
    LHealthCount := TDAIIDEToolbar.CheckCount;
    LReadCount := TDAISettings.Instance.ConnectionRefreshCount;
    LManual.Checked := False;
    for LIndex := Low(CClientIndices) to High(CClientIndices) do
    begin
      LClient.ItemIndex := CClientIndices[LIndex];
      LClient.OnChange(LClient);
      LProbe.Seen := False;
      LProbe.Failure := '';
      LProbe.Timer.Enabled := True;
      LButton.Click;
      LProbe.Timer.Enabled := False;
      Check(LProbe.Seen and (LProbe.Failure = ''), 'Manual registration inspection: ' + LProbe.Failure);
      Check(TDAIClientRegistration.ManualInfoCount = LIndex + 1, 'Each manual preview obtains its contents exactly once');
      Check(TDAIClientRegistration.LastManualClient = CClients[LIndex], 'Manual preview uses the selected client');
      Check(TDAIClientRegistration.LastManualPort = 7457, 'Manual preview uses the current trimmed draft port');
      Check(TDAIClientRegistration.LastManualToken = 'synthetic-manual-preview-draft', 'Manual preview uses the current trimmed draft token');
      Check(not TDAIClientRegistration.LastManualShared, 'Manual preview uses the current unsaved destination scope');
      Check(EditControl(LFrame, True).Text = ' 7457 ', 'Closing manual preview preserves the port draft');
      Check(EditControl(LFrame, False).Text = ' synthetic-manual-preview-draft ', 'Closing manual preview preserves the token draft');
      Check(not LManual.Checked, 'Opening manual instructions never marks the client as manually registered');
      CheckNoPersistence;
    end;
    Check(TDAISettings.Instance.ConnectionRefreshCount = LReadCount, 'Manual preview does not reload effective connection settings');
    Check(TDAIIDEToolbar.CheckCount = LHealthCount, 'Manual preview does not change effective toolbar health');
    Check((TDAIRuntime.StartCount = 0) and (TDAIRuntime.StopCount = 0), 'Manual preview does not start or stop the server');
    LProbe.Timer.Free;
    FreeAndNil(LProbe);

    LScope.Checked := True;
    LManual.Checked := True;
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.SavedManualClientRegistration[True], 'Accepting shared settings saves the manual registration acknowledgement');
    Check(TDAISettings.Instance.ManualRegistrationWriteCount = 1, 'A changed acknowledgement is persisted once');
    Check(TDAIIDEToolbar.LastManualClientRegistration, 'Toolbar health refresh sees the newly saved acknowledgement');
    Check(TDAIIDEToolbar.CheckCount = LHealthCount + 1, 'Saving the manual registration acknowledgement refreshes toolbar health once');
    LScope.Checked := False;
    LManual.Checked := False;
    LFrame.StoreToSettings;
    Check(not TDAISettings.Instance.SavedManualClientRegistration[False], 'Accepting local settings changes only the local acknowledgement');
    Check(TDAISettings.Instance.SavedManualClientRegistration[True], 'Local save preserves the shared acknowledgement');
    Check(not TDAIIDEToolbar.LastManualClientRegistration, 'Toolbar health sees the saved local acknowledgement removal');
    LWriteCount := TDAISettings.Instance.ManualRegistrationWriteCount;
    LHealthCount := TDAIIDEToolbar.CheckCount;
    LManual.Checked := True;
    TDAISettings.Instance.FailSave := True;
    LFailed := False;
    try
      LFrame.StoreToSettings;
    except
      on E: Exception do
        LFailed := E.Message = 'Synthetic settings-save failure';
    end;
    Check(LFailed, 'Failed settings save is reported without accepting the manual registration draft');
    Check(not TDAISettings.Instance.ManualClientRegistration, 'Failed save discards the staged effective manual registration flag');
    Check(TDAISettings.Instance.ManualRegistrationWriteCount = LWriteCount, 'Failed save persists no manual registration flag');
    Check(TDAISettings.Instance.ManualRegistrationDiscardCount = 1, 'Failure clears the pending manual flag through its explicit API');
    Check(TDAIIDEToolbar.CheckCount = LHealthCount, 'Failed save does not refresh toolbar health with an unaccepted flag');
    TDAISettings.Instance.FailSave := False;
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.ManualClientRegistration, 'Retry accepts the preserved checkbox draft');
    Check(TDAISettings.Instance.ManualRegistrationWriteCount = LWriteCount + 1, 'Retry persists the changed manual flag once');
    Check(TDAIIDEToolbar.LastManualClientRegistration, 'Retry refreshes toolbar health after successful persistence');
    LWriteCount := TDAISettings.Instance.ManualRegistrationWriteCount;
    TDAISettings.Instance.SavedManualClientRegistration[False] := False;
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.ManualRegistrationWriteCount = LWriteCount, 'Unchanged save does not overwrite a separately changed acknowledgement');
    Check(not TDAISettings.Instance.ManualClientRegistration, 'Unchanged save preserves an external acknowledgement removal');
  finally
    if Assigned(LProbe) then
    begin
      LProbe.Timer.Free;
      LProbe.Free;
    end;
    LFrame.Free;
    Application.Handle := LApplicationHandle;
    LHost.Free;
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

procedure CheckScrollableOptionsHost(const AScrollBoxHost: Boolean; const APPI: Integer);
var
  LHost: TForm;
  LViewport: TWinControl;
  LFrame: TDAIOptionsFrame;
  LApplicationHandle: HWND;
  LWarning: TLabel;
  LManualRegistration: TCheckBox;
  LComponent: TComponent;
  LPortEdit, LTokenEdit: TEdit;
  LContentHeight, LSaveCount, LPermissionWrites: Integer;
  LScrollInfo: TScrollInfo;

  function HasNativeBar(const AControl: TWinControl; const AStyle: NativeInt): Boolean;
  begin
    Result := (GetWindowLong(AControl.Handle, GWL_STYLE) and AStyle) <> 0;
  end;

  procedure CheckSingleScrollOwner;
  begin
    Check(not HasNativeBar(LHost, WS_VSCROLL), 'The outer form does not add a second vertical scrollbar');
    if AScrollBoxHost then
    begin
      Check(TScrollBox(LViewport).VertScrollBar.Range = 0, 'An outer ScrollBox excludes the client-aligned frame from its range');
      Check(not HasNativeBar(LViewport, WS_VSCROLL), 'The old ScrollBox host does not add a second vertical scrollbar');
    end;
  end;

  procedure ResizeViewport(const ALogicalHeight: Integer);
  begin
    LHost.ClientHeight := MulDiv(ALogicalHeight, APPI, 96);
    LHost.Realign;
    LViewport.Realign;
    LFrame.Realign;
    Check((LFrame.Top = 0) and (LFrame.Height = LViewport.ClientHeight), 'Frame height follows the available host viewport');
  end;

  procedure CheckSmallViewport(const ALogicalHeight: Integer);
  begin
    ResizeViewport(ALogicalHeight);
    Check(LFrame.VertScrollBar.Range > LFrame.ClientHeight, 'The complete options content has a vertical scroll range');
    Check(HasNativeBar(LFrame, WS_VSCROLL), 'A native vertical scrollbar is visible on the frame');
    FillChar(LScrollInfo, SizeOf(LScrollInfo), 0);
    LScrollInfo.cbSize := SizeOf(LScrollInfo);
    LScrollInfo.fMask := SIF_RANGE or SIF_PAGE or SIF_POS;
    Check(GetScrollInfo(LFrame.Handle, SB_VERT, LScrollInfo), 'The native scrollbar exposes its range and viewport');
    Check((LScrollInfo.nMax >= LContentHeight - 1) and (LScrollInfo.nPage > 0), 'The native scrollbar includes the final options controls');
    LFrame.Perform(WM_VSCROLL, SB_BOTTOM, 0);
    Check(LFrame.VertScrollBar.Position > 0, 'The native bottom-scroll action moves the options content');
    Check((LWarning.Top >= 0) and (LWarning.Top + LWarning.Height <= LFrame.ClientHeight), 'The full final warning is reachable at the bottom');
    Check((LManualRegistration.Top >= 0) and (LManualRegistration.Top + LManualRegistration.Height <= LFrame.ClientHeight),
      'The last editable option remains fully reachable');
    LFrame.Perform(WM_VSCROLL, SB_TOP, 0);
    Check(LFrame.VertScrollBar.Position = 0, 'The native top-scroll action restores the content origin');
    LFrame.ScrollInView(LManualRegistration);
    Check((LManualRegistration.Top >= 0) and (LManualRegistration.Top + LManualRegistration.Height <= LFrame.ClientHeight),
      'VCL ScrollInView can bring the final editable option into view');
    CheckSingleScrollOwner;
  end;

begin
  TestStage := Format('ScrollableOptionsHost ScrollBox=%s PPI=%d', [BoolToStr(AScrollBoxHost, True), APPI]);
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  LHost := TForm.CreateNew(nil);
  LApplicationHandle := Application.Handle;
  try
    // Native windows remain hidden; all settings and dependencies are the existing in-memory test doubles.
    LHost.AutoScroll := False;
    // The fit-all-content case may exceed the monitor height after virtual DPI scaling.
    LHost.Constraints.MaxHeight := 12000;
    LHost.ClientWidth := 900;
    LHost.ClientHeight := 600;
    Application.Handle := LHost.Handle;
    if AScrollBoxHost then
    begin
      LViewport := TScrollBox.Create(LHost);
      TScrollBox(LViewport).AutoScroll := True;
      TScrollBox(LViewport).BorderStyle := bsNone;
    end
    else
    begin
      LViewport := TPanel.Create(LHost);
      TPanel(LViewport).BevelOuter := bvNone;
    end;
    LViewport.Parent := LHost;
    LViewport.Align := alClient;
    LFrame := TDAIOptionsFrame.Create(LHost);
    LFrame.Parent := LViewport;
    LFrame.LoadFromSettings;
    LWarning := nil;
    for LComponent in LFrame do
      if (LComponent is TLabel) and StartsText('Betroffene KI-Clients', TLabel(LComponent).Caption) then
        LWarning := TLabel(LComponent);
    Check(Assigned(LWarning), 'The final multiline options warning exists');
    LManualRegistration := TCheckBox(LFrame.FindComponent('DAIManualClientRegistrationCheckBox'));
    Check(Assigned(LManualRegistration), 'The final editable option exists');
    LPortEdit := EditControl(LFrame, True);
    LTokenEdit := EditControl(LFrame, False);
    LPortEdit.Text := '7654';
    LTokenEdit.Text := 'synthetic-unsaved-scroll-draft';
    LManualRegistration.Checked := not LManualRegistration.Checked;
    LSaveCount := TDAISettings.Instance.SaveCount;
    LPermissionWrites := TDAIPermissionManager.Instance.WriteCount;
    LViewport.HandleNeeded;
    LFrame.HandleNeeded;
    LHost.ScaleForPPI(APPI);
    Check(LHost.PixelsPerInch = APPI, 'The isolated host uses the requested VCL DPI');
    Check(LFrame.AutoScroll and (LFrame.Align = alClient), 'The options frame owns scrolling inside its available viewport');
    LFrame.VertScrollBar.Position := 0;
    LContentHeight := LWarning.Top + LWarning.Height;
    CheckSmallViewport(600);
    CheckSmallViewport(400);
    LHost.ClientHeight := LContentHeight + MulDiv(48, APPI, 96);
    LHost.Realign;
    LViewport.Realign;
    LFrame.Realign;
    Check(not HasNativeBar(LFrame, WS_VSCROLL), Format('The frame removes its native scrollbar when all content fits (range=%d, client=%d, content=%d)',
      [LFrame.VertScrollBar.Range, LFrame.ClientHeight, LContentHeight]));
    Check(LFrame.VertScrollBar.Position = 0, 'Enlarging the viewport resets the previous scroll position');
    Check((LWarning.Top >= 0) and (LWarning.Top + LWarning.Height <= LFrame.ClientHeight), 'All final options content fits in the enlarged viewport');
    CheckSingleScrollOwner;
    CheckSmallViewport(400);
    Check((LPortEdit.Text = '7654') and (LTokenEdit.Text = 'synthetic-unsaved-scroll-draft'), 'Scrolling and resizing preserve unsaved connection drafts');
    Check((TDAISettings.Instance.SaveCount = LSaveCount) and (TDAIPermissionManager.Instance.WriteCount = LPermissionWrites),
      'Scrolling, native navigation and DPI changes never save options or permissions');
    Check(not LHost.Visible, 'Scroll regression checks never display an IDE or fixture window');
  finally
    Application.Handle := LApplicationHandle;
    LHost.Free;
  end;
end;

procedure SaveOptionsPreview(const AHost: TForm; const AFrame: TDAIOptionsFrame; const APPI: Integer);
var
  LBitmap: Vcl.Graphics.TBitmap;
  LPNG: TPngImage;
  LComponent: TComponent;
  LContentBottom: Integer;
  LDirectory: string;
begin
  AFrame.VertScrollBar.Position := 0;
  AHost.Constraints.MaxHeight := 12000;
  AHost.ScaleForPPI(APPI);
  AHost.ClientWidth := MulDiv(820, APPI, 96);
  LContentBottom := 0;
  for LComponent in AFrame do
    if LComponent is TControl then
      if TControl(LComponent).Top + TControl(LComponent).Height > LContentBottom then
        LContentBottom := TControl(LComponent).Top + TControl(LComponent).Height;
  AHost.ClientHeight := LContentBottom + MulDiv(20, APPI, 96);
  AHost.Realign;
  AFrame.Realign;
  AFrame.HandleNeeded;
  Check((GetWindowLongPtr(AFrame.Handle, GWL_STYLE) and WS_VSCROLL) = 0,
    Format('Expanded preview fits the full content (PPI=%d, bottom=%d, host=%d, frame=%d, range=%d)',
      [APPI, LContentBottom, AHost.ClientHeight, AFrame.ClientHeight, AFrame.VertScrollBar.Range]));
  Check((AFrame.PixelsPerInch = APPI) and (AHost.PixelsPerInch = APPI), 'Native preview uses its requested DPI');
  // Only this test-owned fixture becomes showing, offscreen and unable to activate.
  // GetFormImage uses VCL's native painting; no desktop or IDE pixels are read.
  SetWindowPos(AHost.Handle, HWND_BOTTOM, -20000, -20000, 0, 0, SWP_NOSIZE or SWP_NOACTIVATE);
  SetWindowLongPtr(AHost.Handle, GWL_EXSTYLE, GetWindowLongPtr(AHost.Handle, GWL_EXSTYLE) or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW);
  AFrame.Visible := True;
  AHost.Visible := True;
  try
    AHost.Update;
    LBitmap := AHost.GetFormImage;
    try
      LPNG := TPngImage.Create;
      try
        LPNG.Assign(LBitmap);
        LDirectory := IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0))) + 'Preview';
        ForceDirectories(LDirectory);
        LPNG.SaveToFile(IncludeTrailingPathDelimiter(LDirectory) + Format('options-%s-%dppi.png', [DAILanguageCode, APPI]));
      finally
        LPNG.Free;
      end;
    finally
      LBitmap.Free;
    end;
  finally
    AHost.Visible := False;
  end;
end;

procedure CheckOptionsLanguages;
const
  CStartCaptions: array[TDAILanguage] of string = ('Start server', 'Server starten', 'Démarrer le serveur', 'サーバーを開始');
  CManualCaptions: array[TDAILanguage] of string = ('Register manually…', 'Manuell registrieren…', 'Inscription manuelle…', '手動で登録…');
  CAllClients: array[TDAILanguage] of string = ('All detected clients', 'Alle erkannten Clients',
    'Tous les clients détectés', '検出されたすべてのクライアント');
  CAlwaysCaptions: array[TDAILanguage] of string = ('Always allow', 'Immer erlauben', 'Toujours autoriser', '常に許可');
  CStatusLines: array[TDAILanguage] of string = ('    Status: registered', '    Status: registriert',
    '    État : inscrit', '    状態: 登録済み');
var
  LLanguage: TDAILanguage;
  LHost: TForm;
  LFrame: TDAIOptionsFrame;
  LApplicationHandle: HWND;
  LProbe: TManualRegistrationProbe;
  LButton: TButton;
  LClients: TComboBox;
  LComponent: TComponent;
  LMemo: TMemo;
  LStatus: TJSONObject;
  LStatusClients: TJSONArray;
  LPort: Integer;
  LToken: string;
begin
  TestStage := 'OptionsLanguages';
  TDAIRuntime.Reset;
  TDAISettings.Reset;
  TDAIPermissionManager.Reset;
  TDAIClientRegistration.RegisterCount := 0;
  TDAIClientRegistration.UnregisterCount := 0;
  LPort := TDAISettings.Instance.Port;
  LToken := TDAISettings.Instance.Token;
  LStatus := TJSONObject.Create;
  LStatusClients := TJSONArray.Create;
  LStatus.AddPair('clients', LStatusClients);
  LStatusClients.AddElement(TJSONObject.Create
    .AddPair('label', 'Codex').AddPair('status', 'registered').AddPair('server_name', 'dai_bds37_0')
    .AddPair('launcher_server', 'dai_bds37_0_start').AddPair('path', 'C:\Synthetic\日本語\client.json')
    .AddPair('message', 'Original Unicode ✓'));
  TDAIClientRegistration.StatusJSON := LStatus.ToJSON;
  LHost := TForm.CreateNew(nil);
  LFrame := nil;
  LProbe := TManualRegistrationProbe.Create;
  LProbe.Timer := TTimer.Create(nil);
  LApplicationHandle := Application.Handle;
  try
    LHost.Visible := False;
    Application.Handle := LHost.Handle;
    LHost.ClientWidth := 820;
    LHost.ClientHeight := 600;
    LProbe.Timer.Enabled := False;
    LProbe.Timer.Interval := 25;
    LProbe.Timer.OnTimer := LProbe.InspectDialog;
    for LLanguage := Low(TDAILanguage) to High(TDAILanguage) do
    begin
      DAISetLanguageForTests(LLanguage);
      LHost.ScaleForPPI(96);
      LHost.ClientWidth := 820;
      LHost.ClientHeight := 600;
      LFrame := TDAIOptionsFrame.Create(LHost);
      LFrame.Parent := LHost;
      LFrame.LoadFromSettings;
      Check(Assigned(ButtonControl(LFrame, CStartCaptions[LLanguage])), 'Server action uses the selected IDE language');
      LButton := LFrame.FindComponent('DAIManualRegistrationButton') as TButton;
      Check(LButton.Caption = CManualCaptions[LLanguage], 'Manual registration action uses the selected IDE language');
      LClients := LFrame.FindComponent('DAIClientComboBox') as TComboBox;
      Check(LClients.Items[0] = CAllClients[LLanguage], 'All-clients choice is localized');
      Check((LClients.Items[1] = 'Codex') and (LClients.Items[2] = 'Claude Code (CLI / VS Code)'), 'Product names remain unchanged');
      Check(PermissionCombo(LFrame, 'Global', pcCompile).Items[5] = CAlwaysCaptions[LLanguage], 'Permission levels are localized');
      Check(PermissionCombo(LFrame, 'Project', pcCompile).ItemIndex = 6, 'Localized inheritance retains its semantic index');
      LMemo := nil;
      for LComponent in LFrame do
        if (LComponent is TMemo) and TMemo(LComponent).ReadOnly then
          LMemo := TMemo(LComponent);
      Check(Assigned(LMemo) and (LMemo.Lines[1] = CStatusLines[LLanguage]), 'Client state uses localized presentation text');
      Check((Pos('dai_bds37_0_start', LMemo.Text) > 0) and (Pos('日本語', LMemo.Text) > 0),
        'Technical server names and Unicode paths remain intact');
      Check(Pos('Original Unicode ✓', LMemo.Text) > 0, 'Backend and user-provided text remains intact');
      EditControl(LFrame, True).Text := '7457';
      EditControl(LFrame, False).Text := 'synthetic-日本語-token';
      LClients.ItemIndex := 3;
      LProbe.Seen := False;
      LProbe.Failure := '';
      LProbe.Timer.Enabled := True;
      LButton.Click;
      LProbe.Timer.Enabled := False;
      Check(LProbe.Seen and (LProbe.Failure = ''), 'Localized manual dialog inspection: ' + LProbe.Failure);
      Check(TDAIClientRegistration.LastManualClient = 'claude-desktop', 'Client index maps to a stable protocol identifier in every language');
      Check(TDAIClientRegistration.LastManualToken = 'synthetic-日本語-token', 'Unicode draft values reach manual preview unchanged');
      Check((EditControl(LFrame, True).Text = '7457') and (EditControl(LFrame, False).Text = 'synthetic-日本語-token'),
        'Opening localized instructions preserves unsaved connection drafts');
      CheckNoPersistence;
      SaveOptionsPreview(LHost, LFrame, 96);
      SaveOptionsPreview(LHost, LFrame, 192);
      CheckNoPersistence;
      FreeAndNil(LFrame);
    end;
    Check((TDAISettings.Instance.Port = LPort) and (TDAISettings.Instance.Token = LToken), 'Language changes do not modify saved connection values');
    CheckNoPersistence;
  finally
    DAISetLanguageForTests(dlGerman);
    TDAIClientRegistration.StatusJSON := '';
    LStatus.Free;
    LProbe.Timer.Free;
    LProbe.Free;
    LFrame.Free;
    Application.Handle := LApplicationHandle;
    LHost.Free;
  end;
end;

procedure CheckOptionsScrolling;
var
  LScrollBoxHost: Boolean;
  LPPI: Integer;
begin
  for LScrollBoxHost := False to True do
    for LPPI in [96, 144, 192] do
      CheckScrollableOptionsHost(LScrollBoxHost, LPPI);
end;

procedure CheckPermissionColumns;
var
  LFrame: TDAIOptionsFrame;
  LHost: TForm;
  LApplicationHandle: HWND;
  LOriginalProject, LLoadedProject: string;
  LManager: TDAIPermissionManager;
  LCategory: TDAIPermissionCategory;
  LGlobal, LProject: TComboBox;
  LDialogButton: TControl;
  LDirectoriesCheckBox: TCheckBox;
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
  LManager.GlobalLevels[pcProjectRead] := plAlways;
  LManager.GlobalLevels[pcCompile] := plAsk;
  LManager.ProjectLevels[pcProjectRead] := plSession;
  LManager.ProjectInherits[pcProjectWrite] := True;
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
      Check(LGlobal.Enabled = (LCategory <> pcReferenceRead), 'Reference read is fixed; other global permissions are editable');
      Check(LProject.Enabled = not DAIPermissionCategoryIsGlobal(LCategory), 'Only project permissions have editable overrides');
      Check((LGlobal.Width = 190) and (LProject.Width = 190), 'Permission combos use requested 190-pixel width');
      Check((LGlobal.Top = LProject.Top) and (LGlobal.Left + LGlobal.Width < LProject.Left), 'Permission choices share a row side by side');
      LDialogButton := PermissionDialogButton(LFrame, LCategory);
      Check(LDialogButton.Enabled = (LCategory <> pcReferenceRead), 'Fixed reference reading cannot open a permission selector');
      Check((LDialogButton.Left > LProject.Left + LProject.Width) and
        (Abs(LDialogButton.Top - LProject.Top) <= 2), 'Single selector sits to the right of both choices');
      Check((LGlobal.Items.Count = 6) and (LProject.Items.Count = 7), 'Global/project choices retain their expected sizes');
      if DAIPermissionCategoryIsGlobal(LCategory) then
        Check(LProject.Items[6] = 'Nur global', 'Global-only rows explain the unavailable project override')
      else
        Check(LProject.Items[6] = 'Default', 'Project inheritance label stays concise');
    end;
    Check(PermissionCombo(LFrame, 'Global', pcReferenceRead).ItemIndex = 5, 'Reference reading always displays Always despite synthetic saved deny');
    Check(PermissionCombo(LFrame, 'Project', pcReferenceRead).ItemIndex = 6, 'Fixed reference reading has no project override');
    Check(PermissionCombo(LFrame, 'Global', pcProjectRead).ItemIndex = 5, 'Project reading loads its global setting');
    Check(PermissionCombo(LFrame, 'Project', pcProjectRead).ItemIndex = 4, 'Project reading loads an independent project override');
    Check(PermissionCombo(LFrame, 'Project', pcProjectWrite).ItemIndex = 6, 'Inherited project writing is visibly Default');
    LDirectoriesCheckBox := TCheckBox(LFrame.FindComponent('DAICustomReadDirectoriesAlwaysAllowedCheckBox'));
    Check(Assigned(LDirectoriesCheckBox), 'Additional directories have a named global reading checkbox');
    Check((LDirectoriesCheckBox.Caption = 'Lesen immer erlaubt') and not LDirectoriesCheckBox.Checked,
      'Additional directory reading defaults to the project permission');
    Check(Pos('Schreibzugriffe bleiben gesperrt', LDirectoriesCheckBox.Hint) > 0, 'Directory checkbox explains immutable write protection');
    LFrame.StoreToSettings;
    Check(LManager.WriteCount = 0, 'Unchanged save does not materialize any permission value');

    EditControl(LFrame, True).Text := '7123';
    EditControl(LFrame, False).Text := ' synthetic-permission-column-token ';
    ChoosePermission(LFrame, 'Global', pcCompile, 4);
    ChoosePermission(LFrame, 'Global', pcIDEOptions, 4);
    Check(PermissionCombo(LFrame, 'Project', pcCompile).ItemIndex = 6, 'Global combo change resets the corresponding project draft to Default');
    Check(PermissionCombo(LFrame, 'Project', pcProjectRead).ItemIndex = 4, 'Global change preserves other project categories');
    TDAIPermissionDialog.NextLevel := plAlways;
    TDAIPermissionDialog.NextApplyGlobally := True;
    ClickPermissionDialog(LFrame, pcProjectRead);
    Check(TDAIPermissionDialog.LastProjectKey = LLoadedProject, 'Row dialog starts with the captured active project');
    Check(TDAIPermissionDialog.LastCurrentLevel = plSession, 'Dialog sees the selected project draft');
    Check(PermissionCombo(LFrame, 'Project', pcProjectRead).ItemIndex = 4, 'Cancelled global selection preserves the project override');
    Check(LManager.WriteCount = 0, 'Cancelled dialog writes no permission');
    TDAIPermissionDialog.NextAccepted := True;
    ClickPermissionDialog(LFrame, pcProjectRead);
    Check(PermissionCombo(LFrame, 'Global', pcProjectRead).ItemIndex = 5, 'Global dialog selection stages the global level');
    Check(PermissionCombo(LFrame, 'Project', pcProjectRead).ItemIndex = 6, 'Global dialog selection resets only its project override');
    Check(PermissionCombo(LFrame, 'Project', pcExecute).ItemIndex = 1, 'Global selection never raises other permissions');
    Check(LManager.WriteCount = 0, 'Accepted dialog stages without immediate persistence');
    Check(EditControl(LFrame, True).Text = '7123', 'Permission selector preserves draft port');
    Check(EditControl(LFrame, False).Text = ' synthetic-permission-column-token ', 'Permission selector preserves draft token');

    TDAIPermissionDialog.NextLevel := plOnce;
    TDAIPermissionDialog.NextApplyGlobally := False;
    ClickPermissionDialog(LFrame, pcExecute);
    Check(PermissionCombo(LFrame, 'Project', pcExecute).ItemIndex = 3, 'Unchecked scope checkbox stages an explicit project selection');
    Check(PermissionCombo(LFrame, 'Global', pcExecute).ItemIndex = 1, 'Project selection preserves the global level');
    SyntheticProjectFileName := 'C:\SyntheticDAITest\OtherProject.dproj';
    LSettingsSaveCount := TDAISettings.Instance.SaveCount;
    LFailed := False;
    try
      LFrame.StoreToSettings;
    except
      on E: EInvalidOperation do
        LFailed := Pos('aktive Projekt hat gewechselt', E.Message) > 0;
    end;
    Check(LFailed, 'Project switch rejects captured permission drafts');
    Check((LManager.WriteCount = 0) and (TDAISettings.Instance.SaveCount = LSettingsSaveCount), 'Project guard runs before all persistence');
    SyntheticProjectFileName := LLoadedProject;
    LFrame.StoreToSettings;
    Check((LManager.GlobalWriteCount = 3) and (LManager.ProjectWriteCount = 3), 'Save writes global drafts, their resets and the explicit project choice');
    Check((LManager.ResetCount = 2) and LManager.ProjectInherits[pcProjectRead] and LManager.ProjectInherits[pcCompile],
      'Global changes persist Default for each corresponding current project permission');
    Check(not LManager.ProjectInherits[pcExecute], 'Independent explicit project selection is saved');
    for LWrite in LManager.Writes do
    begin
      Check(LWrite.Category <> pcReferenceRead, 'Fixed reference reading is never persisted');
      Check((LWrite.ProjectKey = '') or (LWrite.ProjectKey = LLoadedProject), 'Save cannot redirect captured project changes');
      Check((LWrite.ProjectKey = '') or not DAIPermissionCategoryIsGlobal(LWrite.Category), 'Global-only rights never create project records');
    end;
    LWriteCount := LManager.WriteCount;
    LManager.GlobalLevels[pcProjectRead] := plNever;
    LFrame.StoreToSettings;
    Check((LManager.WriteCount = LWriteCount) and (LManager.GlobalLevels[pcProjectRead] = plNever),
      'Repeated unchanged save preserves external permission updates');

    ChoosePermission(LFrame, 'Project', pcExecute, 6);
    LFrame.StoreToSettings;
    Check((LManager.ResetCount = 3) and LManager.ProjectInherits[pcExecute], 'Selecting Default removes only the explicit project override');
    TDAIPermissionDialog.NextLevel := plSession;
    ClickPermissionDialog(LFrame, pcExecute);
    Check(TDAIPermissionDialog.LastCurrentLevel = plNever, 'Inherited selector starts with the effective global draft');
    LFrame.StoreToSettings;
    Check(not LManager.ProjectInherits[pcExecute] and (LManager.ProjectLevels[pcExecute] = plSession), 'Project session choice stops inheritance');
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
    Check(LFailed and (LManager.WriteCount = LWriteCount), 'Settings failure does not persist permission drafts');
    TDAISettings.Instance.FailSave := False;
    LFrame.StoreToSettings;
    Check((LManager.WriteCount = LWriteCount + 2) and (LManager.GlobalLevels[pcExecute] = plOnce) and LManager.ProjectInherits[pcExecute],
      'Retry retains both the global selection and its project reset');
    LWriteCount := LManager.WriteCount;
    ChoosePermission(LFrame, 'Project', pcProjectWrite, 5);
    LDirectoriesCheckBox.Checked := True;
    FreeAndNil(LFrame);
    Check((LManager.WriteCount = LWriteCount) and LManager.ProjectInherits[pcProjectWrite], 'Cancel discards explicit permission drafts');
    Check(not TDAISettings.Instance.CustomReadDirectoriesAlwaysAllowed, 'Cancel discards the additional directory checkbox draft');
    CreateFrame;
    LDirectoriesCheckBox := TCheckBox(LFrame.FindComponent('DAICustomReadDirectoriesAlwaysAllowedCheckBox'));
    Check(not LDirectoriesCheckBox.Checked, 'Reopening reloads the saved directory permission');
    LDirectoriesCheckBox.Checked := True;
    LFrame.StoreToSettings;
    Check(TDAISettings.Instance.CustomReadDirectoriesAlwaysAllowed, 'Accepted settings save the global directory reading flag');
    FreeAndNil(LFrame);

    SyntheticProjectFileName := '';
    CreateFrame;
    for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    begin
      Check(PermissionCombo(LFrame, 'Global', LCategory).Enabled = (LCategory <> pcReferenceRead), 'Global rights remain editable without a project');
      Check(not PermissionCombo(LFrame, 'Project', LCategory).Enabled, 'All project choices are disabled without a project');
      Check(PermissionDialogButton(LFrame, LCategory).Enabled = (LCategory <> pcReferenceRead), 'Only configurable rights expose a selector');
    end;
    LCallCount := TDAIPermissionDialog.CallCount;
    ClickPermissionDialog(LFrame, pcReferenceRead);
    Check(TDAIPermissionDialog.CallCount = LCallCount, 'Disabled fixed-read selector does not prompt');
    TDAIPermissionDialog.NextLevel := plAlways;
    ClickPermissionDialog(LFrame, pcIDEOptions);
    Check(TDAIPermissionDialog.LastProjectKey = '', 'Global-only selector targets the global scope');
    Check(PermissionCombo(LFrame, 'Global', pcIDEOptions).ItemIndex = 5, 'No-project selector stages the global choice');
    ChoosePermission(LFrame, 'Project', pcIDEOptions, 5);
    ChoosePermission(LFrame, 'Global', pcReferenceRead, 1);
    LFrame.StoreToSettings;
    Check(LManager.WriteCount = LWriteCount + 1, 'Disabled controls cannot persist reference or project changes');
    Check((LManager.Writes[High(LManager.Writes)].ProjectKey = '') and (LManager.Writes[High(LManager.Writes)].Category = pcIDEOptions),
      'No-project save persists only the intended global IDE setting');
  finally
    LFrame.Free;
    Application.Handle := LApplicationHandle;
    LHost.Free;
    SyntheticProjectFileName := LOriginalProject;
  end;
end;

begin
  try
    DAISetLanguageForTests(dlGerman);
    Application.Initialize;
    Application.ShowMainForm := False;
    RunChecks;
    CheckLifecycleOptions;
    CheckConnectionScopeOptions;
    CheckPermissionColumns;
    CheckRegistrationHealthRefresh;
    CheckManualRegistrationOptions;
    CheckOptionsScrolling;
    CheckOptionsLanguages;
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
