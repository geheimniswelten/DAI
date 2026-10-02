unit h5u.DAI.Options.Frame;

interface

uses
  System.Classes,
  System.JSON,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  h5u.DAI.Types;

type
  TDAIOptionsFrame = class(TFrame)
  private
    FServerEnabledCheckBox: TCheckBox;
    FServerStatusLabel: TLabel;
    FStartServerButton: TButton;
    FStopServerButton: TButton;
    FLoggingCheckBox: TCheckBox;
    FPortEdit: TEdit;
    FTokenEdit: TEdit;
    FGenerateTokenButton: TButton;
    FDirectoriesMemo: TMemo;
    FDirectoryHintLabel: TLabel;
    FScopeComboBox: TComboBox;
    FProjectLabel: TLabel;
    FPermissionComboBoxes: array[TDAIPermissionCategory] of TComboBox;
    FClientComboBox: TComboBox;
    FClientStatusMemo: TMemo;
    FCodexStatusLabel: TLabel;
    FSkillStatusLabel: TLabel;
    FRegisterButton: TButton;
    FUnregisterButton: TButton;
    FShowToolsButton: TButton;
    procedure BuildControls;
    procedure RefreshServerStatus;
    procedure DisplayClientStatus(const AStatus: TJSONObject);
    procedure AddPermissionRow(const AParent: TWinControl; const ACategory: TDAIPermissionCategory; var ATop: Integer);
    procedure PopulatePermissionCombo(const AComboBox: TComboBox);
    procedure ScopeChanged(Sender: TObject);
    procedure LoadPermissionSettings;
    procedure StartServerClicked(Sender: TObject);
    procedure StopServerClicked(Sender: TObject);
    procedure GenerateTokenClicked(Sender: TObject);
    procedure ClientChanged(Sender: TObject);
    function SelectedClient: string;
    procedure RegisterClicked(Sender: TObject);
    procedure UnregisterClicked(Sender: TObject);
    procedure ShowToolsClicked(Sender: TObject);
    function SelectedPermissionScope: TDAIPermissionScope;
    function PermissionLevelFromCombo(const AComboBox: TComboBox): TDAIPermissionLevel;
    procedure SetPermissionComboLevel(const AComboBox: TComboBox; const ALevel: TDAIPermissionLevel);
    function PermissionContext: TDAIRequestContext;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromSettings;
    procedure StoreToSettings;
    function ValidateContents: Boolean;
    procedure RefreshRegistrationStatus;
  end;

implementation

{$R *.dfm}

uses
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Graphics,
  h5u.DAI.Clients.Registration,
  h5u.DAI.Codex.Registration,
  h5u.DAI.Consts,
  h5u.DAI.MCP.Tools,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Settings;

procedure AddIndentedLines(const ALines: TStrings; const AText: string);
var
  LLine: string;
  LParts: TStringList;
begin
  LParts := TStringList.Create;
  try
    LParts.Text := AText;
    for LLine in LParts do
      if Trim(LLine) <> '' then
        ALines.Add('    ' + Trim(LLine));
  finally
    LParts.Free;
  end;
end;

function NewLabel(const AParent: TWinControl; const ACaption: string; const ALeft: Integer; const ATop: Integer): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.AutoSize := True;
end;

constructor TDAIOptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AutoScroll := False;
  BuildControls;
end;

procedure TDAIOptionsFrame.AddPermissionRow(const AParent: TWinControl; const ACategory: TDAIPermissionCategory; var ATop: Integer);
var
  LComboBox: TComboBox;
begin
  NewLabel(AParent, DAIPermissionCategoryName(ACategory), 24, ATop + 4);
  LComboBox := TComboBox.Create(AParent);
  LComboBox.Parent := AParent;
  LComboBox.Left := 320;
  LComboBox.Top := ATop;
  LComboBox.Width := 220;
  LComboBox.Style := csDropDownList;
  PopulatePermissionCombo(LComboBox);
  FPermissionComboBoxes[ACategory] := LComboBox;
  Inc(ATop, 34);
end;

procedure TDAIOptionsFrame.BuildControls;
var
  LCategory: TDAIPermissionCategory;
  LInfoLabel: TLabel;
  LTop: Integer;
begin
  LTop := 18;
  with NewLabel(Self, 'MCP-Server', 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 30);

  FServerEnabledCheckBox := TCheckBox.Create(Self);
  FServerEnabledCheckBox.Parent := Self;
  FServerEnabledCheckBox.Left := 24;
  FServerEnabledCheckBox.Top := LTop;
  FServerEnabledCheckBox.Caption := 'MCP-Server beim IDE-Start automatisch starten';
  FServerEnabledCheckBox.Width := 540;
  Inc(LTop, 32);

  NewLabel(Self, 'Port', 24, LTop + 4);
  FPortEdit := TEdit.Create(Self);
  FPortEdit.Parent := Self;
  FPortEdit.Left := 160;
  FPortEdit.Top := LTop;
  FPortEdit.Width := 100;
  FPortEdit.NumbersOnly := True;
  with NewLabel(Self, Format('Standard: %d', [CDAIDefaultPort]), FPortEdit.Left + FPortEdit.Width + 12, LTop + 4) do
    Font.Color := clGrayText;
  Inc(LTop, 32);

  NewLabel(Self, 'Bearer-Token', 24, LTop + 4);
  FTokenEdit := TEdit.Create(Self);
  FTokenEdit.Parent := Self;
  FTokenEdit.Left := 160;
  FTokenEdit.Top := LTop;
  FTokenEdit.Width := 330;

  FGenerateTokenButton := TButton.Create(Self);
  FGenerateTokenButton.Parent := Self;
  FGenerateTokenButton.Left := FTokenEdit.Left + FTokenEdit.Width + 12;
  FGenerateTokenButton.Top := LTop;
  FGenerateTokenButton.Width := 158;
  FGenerateTokenButton.Caption := 'Token erzeugen';
  FGenerateTokenButton.Hint := 'Erzeugt eine neue GUID. Danach „Registrieren“ und den KI-Client neu starten, damit die neue Verbindung verwendet wird.';
  FGenerateTokenButton.ShowHint := True;
  FGenerateTokenButton.OnClick := GenerateTokenClicked;
  Inc(LTop, 32);

  FServerStatusLabel := NewLabel(Self, '', 24, LTop);
  FServerStatusLabel.AutoSize := False;
  FServerStatusLabel.WordWrap := True;
  FServerStatusLabel.Width := 760;
  FServerStatusLabel.Height := 72;
  Inc(LTop, 76);

  FStartServerButton := TButton.Create(Self);
  FStartServerButton.Parent := Self;
  FStartServerButton.SetBounds(24, LTop, 160, 28);
  FStartServerButton.Caption := 'Server starten';
  FStartServerButton.Hint := 'Startet mit dem hier eingetragenen Port und Bearer-Token. „Speichern“ oder „Registrieren“ übernimmt die Werte dauerhaft.';
  FStartServerButton.ShowHint := True;
  FStartServerButton.OnClick := StartServerClicked;

  FStopServerButton := TButton.Create(Self);
  FStopServerButton.Parent := Self;
  FStopServerButton.SetBounds(196, LTop, 160, 28);
  FStopServerButton.Caption := 'Server stoppen';
  FStopServerButton.Hint := 'Stoppt den Server dieser IDE. Danach kann eine andere IDE ihn manuell starten.';
  FStopServerButton.ShowHint := True;
  FStopServerButton.OnClick := StopServerClicked;
  Inc(LTop, 36);
  with NewLabel(Self, 'Starten/Stoppen wirkt sofort. „Speichern“ oder „Registrieren“ übernimmt Port und Token dauerhaft.', 24, LTop) do
    Font.Color := clGrayText;
  Inc(LTop, 28);

  FLoggingCheckBox := TCheckBox.Create(Self);
  FLoggingCheckBox.Parent := Self;
  FLoggingCheckBox.Left := 24;
  FLoggingCheckBox.Top := LTop;
  FLoggingCheckBox.Caption := 'Alle Zugriffspunkte mit IOTAMessageServices.AddTitleMessage protokollieren';
  FLoggingCheckBox.Width := 650;
  Inc(LTop, 40);

  with NewLabel(Self, 'Zusätzliche schreibgeschützte Verzeichnisse', 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 28);

  FDirectoryHintLabel := NewLabel(Self, '', 24, LTop);
  Inc(LTop, 24);

  FDirectoriesMemo := TMemo.Create(Self);
  FDirectoriesMemo.Parent := Self;
  FDirectoriesMemo.Left := 24;
  FDirectoriesMemo.Top := LTop;
  FDirectoriesMemo.Width := 636;
  FDirectoriesMemo.Height := 100;
  FDirectoriesMemo.ScrollBars := ssVertical;
  FDirectoriesMemo.WordWrap := False;
  Inc(LTop, 122);

  with NewLabel(Self, 'Berechtigungen', 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 30);

  NewLabel(Self, 'Geltungsbereich', 24, LTop + 4);
  FScopeComboBox := TComboBox.Create(Self);
  FScopeComboBox.Parent := Self;
  FScopeComboBox.Left := 160;
  FScopeComboBox.Top := LTop;
  FScopeComboBox.Width := 240;
  FScopeComboBox.Style := csDropDownList;
  FScopeComboBox.Items.Add('Globaler Standard');
  FScopeComboBox.Items.Add('Aktuelles Projekt');
  FScopeComboBox.ItemIndex := 1;
  FScopeComboBox.OnChange := ScopeChanged;
  Inc(LTop, 34);

  FProjectLabel := NewLabel(Self, '', 24, LTop);
  FProjectLabel.Width := 636;
  FProjectLabel.AutoSize := False;
  FProjectLabel.WordWrap := True;
  FProjectLabel.Height := 44;
  Inc(LTop, 52);

  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    AddPermissionRow(Self, LCategory, LTop);

  LInfoLabel := NewLabel(
    Self,
    '„Verweigern“, „Nur diesmal“ und „Für diese Session“ sind Laufzeitentscheidungen. „Nie“ und „Immer“ werden projektbezogen gespeichert.',
    24,
    LTop
  );
  LInfoLabel.AutoSize := False;
  LInfoLabel.WordWrap := True;
  LInfoLabel.Width := 760;
  LInfoLabel.Height := 36;
  Inc(LTop, 42);

  with NewLabel(Self, 'KI-Client- und Skill-Registrierung', 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 30);

  FClientComboBox := TComboBox.Create(Self);
  FClientComboBox.Parent := Self;
  FClientComboBox.Left := 24;
  FClientComboBox.Top := LTop;
  FClientComboBox.Width := 330;
  FClientComboBox.Style := csDropDownList;
  FClientComboBox.Items.Add('Alle erkannten Clients');
  FClientComboBox.Items.Add('Codex');
  FClientComboBox.Items.Add('Claude Code (CLI / VS Code)');
  FClientComboBox.Items.Add('Claude Desktop');
  FClientComboBox.Items.Add('Eigent');
  FClientComboBox.Items.Add('Gemini CLI / Code Assist');
  FClientComboBox.Items.Add('Gemini Desktop');
  FClientComboBox.Items.Add('Hermes');
  FClientComboBox.Items.Add('LM Studio');
  FClientComboBox.Items.Add('OpenClaw');
  FClientComboBox.ItemIndex := 0;
  FClientComboBox.OnChange := ClientChanged;
  Inc(LTop, 34);

  FClientStatusMemo := TMemo.Create(Self);
  FClientStatusMemo.Parent := Self;
  FClientStatusMemo.Left := 24;
  FClientStatusMemo.Top := LTop;
  FClientStatusMemo.Width := 736;
  FClientStatusMemo.Height := 154;
  FClientStatusMemo.ReadOnly := True;
  FClientStatusMemo.ScrollBars := ssBoth;
  FClientStatusMemo.WordWrap := False;
  Inc(LTop, 164);

  FCodexStatusLabel := NewLabel(Self, '', 24, LTop);
  FCodexStatusLabel.AutoSize := False;
  FCodexStatusLabel.WordWrap := True;
  FCodexStatusLabel.Width := 736;
  FCodexStatusLabel.Height := 36;
  Inc(LTop, 40);
  FSkillStatusLabel := NewLabel(Self, '', 24, LTop);
  FSkillStatusLabel.AutoSize := False;
  FSkillStatusLabel.WordWrap := True;
  FSkillStatusLabel.Width := 736;
  FSkillStatusLabel.Height := 36;
  Inc(LTop, 44);

  FRegisterButton := TButton.Create(Self);
  FRegisterButton.Parent := Self;
  FRegisterButton.Left := 24;
  FRegisterButton.Top := LTop;
  FRegisterButton.Width := 160;
  FRegisterButton.Caption := 'Registrieren';
  FRegisterButton.OnClick := RegisterClicked;

  FUnregisterButton := TButton.Create(Self);
  FUnregisterButton.Parent := Self;
  FUnregisterButton.Left := 196;
  FUnregisterButton.Top := LTop;
  FUnregisterButton.Width := 160;
  FUnregisterButton.Caption := 'Deregistrieren';
  FUnregisterButton.OnClick := UnregisterClicked;

  FShowToolsButton := TButton.Create(Self);
  FShowToolsButton.Parent := Self;
  FShowToolsButton.Name := 'DAIFunctionsButton';
  FShowToolsButton.SetBounds(368, LTop, 280, 28);
  FShowToolsButton.Caption := 'Skill und MCP-Werkzeuge';
  FShowToolsButton.OnClick := ShowToolsClicked;
  Inc(LTop, 48);

  LInfoLabel := NewLabel(
    Self,
    'Betroffene KI-Clients müssen ihre MCP-Verbindung neu laden oder neu gestartet werden. ' +
    'Hinweis: Nach dem Ändern von Port oder Bearer-Token sowie nach dem Registrieren oder Deregistrieren muss die Codex-App neu gestartet werden.',
    24,
    LTop
  );
  LInfoLabel.AutoSize := False;
  LInfoLabel.WordWrap := True;
  LInfoLabel.Width := 760;
  LInfoLabel.Height := 60;
  LInfoLabel.Font.Style := [fsBold];
  LInfoLabel.Font.Color := clGrayText;
  Inc(LTop, 76);

  Align := alTop;
  Height := LTop;
end;

procedure TDAIOptionsFrame.ShowToolsClicked(Sender: TObject);
var
  LDialog: TForm;
  LMemo: TMemo;
  LOKButton: TButton;
  LTool: TJSONValue;
  LTools: TJSONArray;
  LObject: TJSONObject;
begin
  LTools := TDAIMCPTools.ListTools;
  try
    LDialog := TForm.CreateNew(nil);
    try
      LDialog.Name := 'DAIToolCatalogDialog';
      LDialog.Caption := 'DAI – Skill und MCP-Werkzeuge';
      LDialog.Position := poScreenCenter;
      LDialog.BorderStyle := bsSizeable;
      LDialog.ClientWidth := 820;
      LDialog.ClientHeight := 560;
      LDialog.Constraints.MinWidth := 520;
      LDialog.Constraints.MinHeight := 320;
      LDialog.Font.Name := 'Segoe UI';
      LDialog.Font.Size := 9;

      LMemo := TMemo.Create(LDialog);
      LMemo.Name := 'DAIToolCatalogMemo';
      LMemo.Parent := LDialog;
      LMemo.SetBounds(16, 16, LDialog.ClientWidth - 32, LDialog.ClientHeight - 72);
      LMemo.Anchors := [akLeft, akTop, akRight, akBottom];
      LMemo.ReadOnly := True;
      LMemo.ScrollBars := ssBoth;
      LMemo.WordWrap := False;
      LMemo.Font.Name := 'Consolas';
      LMemo.Font.Size := 10;
      LMemo.Clear;
      LMemo.Lines.Add('Skill: ' + CDAISkillDirectoryName);
      LMemo.Lines.Add('MCP-Werkzeuge: ' + IntToStr(LTools.Count));
      for LTool in LTools do
        if LTool is TJSONObject then
        begin
          LObject := TJSONObject(LTool);
          LMemo.Lines.Add(LObject.GetValue<string>('name', ''));
          AddIndentedLines(LMemo.Lines, LObject.GetValue<string>('description', ''));
        end;

      LOKButton := TButton.Create(LDialog);
      LOKButton.Parent := LDialog;
      LOKButton.SetBounds(LDialog.ClientWidth - 112, LDialog.ClientHeight - 44, 96, 28);
      LOKButton.Anchors := [akRight, akBottom];
      LOKButton.Caption := 'OK';
      LOKButton.Default := True;
      LOKButton.Cancel := True;
      LOKButton.ModalResult := mrOK;
      LDialog.ActiveControl := LOKButton;
      LDialog.ShowModal;
    finally
      LDialog.Free;
    end;
  finally
    LTools.Free;
  end;
end;

procedure TDAIOptionsFrame.StartServerClicked(Sender: TObject);
begin
  if not ValidateContents then
    Exit;
  if not TDAIRuntime.StartServer(StrToIntDef(Trim(FPortEdit.Text), 0), Trim(FTokenEdit.Text)) then
    TaskMessageDlg('DAI', TDAIRuntime.LastServerError, mtInformation, [mbOK], 0);
  RefreshServerStatus;
end;

procedure TDAIOptionsFrame.StopServerClicked(Sender: TObject);
begin
  if not TDAIRuntime.StopServer then
    TaskMessageDlg('DAI', TDAIRuntime.LastServerError, mtWarning, [mbOK], 0);
  RefreshServerStatus;
end;

procedure TDAIOptionsFrame.GenerateTokenClicked(Sender: TObject);
begin
  FTokenEdit.Text := TDAISettings.Instance.GenerateToken;
  FTokenEdit.SetFocus;
  FTokenEdit.SelectAll;
end;

function TDAIOptionsFrame.ValidateContents: Boolean;
var
  LError: string;
begin
  Result := TDAIRuntime.ValidateServerConfiguration(StrToIntDef(Trim(FPortEdit.Text), 0), Trim(FTokenEdit.Text), LError);
  if not Result then
    TaskMessageDlg('DAI', LError, mtError, [mbOK], 0);
end;

procedure TDAIOptionsFrame.LoadFromSettings;
begin
  FServerEnabledCheckBox.Checked := TDAISettings.Instance.Enabled;
  FLoggingCheckBox.Checked := TDAISettings.Instance.LogAccessPoints;
  FPortEdit.Text := IntToStr(TDAISettings.Instance.Port);
  FTokenEdit.Text := TDAISettings.Instance.Token;
  FDirectoriesMemo.Lines.Assign(TDAISettings.Instance.CustomReadDirectories);
  FDirectoriesMemo.TextHint := TDAISettings.Instance.LocalizedProjectsDirectoryHint;
  FDirectoryHintLabel.Caption := 'Vorschlag für diese IDE-Sprache: ' + TDAISettings.Instance.LocalizedProjectsDirectoryHint;
  RefreshServerStatus;
  LoadPermissionSettings;
  RefreshRegistrationStatus;
end;

procedure TDAIOptionsFrame.LoadPermissionSettings;
var
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
begin
  if (FScopeComboBox.ItemIndex = 1) and (TDAIOTA.ActiveProjectFileName = '') then
    FScopeComboBox.ItemIndex := 0;

  LContext := PermissionContext;
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    SetPermissionComboLevel(
      FPermissionComboBoxes[LCategory],
      TDAIPermissionManager.Instance.GetEffectiveLevel(LCategory, LContext)
    );

  if SelectedPermissionScope = psProject then
    FProjectLabel.Caption := 'Aktuelles Projekt: ' + LContext.ProjectKey + sLineBreak +
      'Projektdatei: ' + ChangeFileExt(LContext.ProjectKey, '.dai.permissions.json')
  else
    FProjectLabel.Caption := 'Globaler Standard für Projekte ohne eigene DAI-Berechtigungsdatei.';
end;

function TDAIOptionsFrame.PermissionContext: TDAIRequestContext;
begin
  Result := Default(TDAIRequestContext);
  Result.ThreadId := '*';
  Result.TransportSessionId := 'options';
  Result.ClientName := 'IDE-Optionen';
  if SelectedPermissionScope = psProject then
    Result.ProjectKey := TDAIOTA.ActiveProjectFileName
  else
    Result.ProjectKey := '';
end;

function TDAIOptionsFrame.PermissionLevelFromCombo(const AComboBox: TComboBox): TDAIPermissionLevel;
begin
  case AComboBox.ItemIndex of
    1:
      Result := plNever;
    2:
      Result := plDeny;
    3:
      Result := plOnce;
    4:
      Result := plSession;
    5:
      Result := plAlways;
  else
    Result := plAsk;
  end;
end;

procedure TDAIOptionsFrame.PopulatePermissionCombo(const AComboBox: TComboBox);
begin
  AComboBox.Items.BeginUpdate;
  try
    AComboBox.Items.Clear;
    AComboBox.Items.Add('Nachfragen');
    AComboBox.Items.Add('Nie erlauben');
    AComboBox.Items.Add('Verweigern – nächste Anfrage');
    AComboBox.Items.Add('Nur einmal – nächste Anfrage');
    AComboBox.Items.Add('Für diese Projektsession');
    AComboBox.Items.Add('Immer erlauben');
  finally
    AComboBox.Items.EndUpdate;
  end;
end;

procedure TDAIOptionsFrame.RefreshServerStatus;
var
  LError: string;
begin
  FStartServerButton.Enabled := not TDAIRuntime.ServerActive;
  FStopServerButton.Enabled := TDAIRuntime.ServerActive;
  if TDAIRuntime.ServerActive then
    FServerStatusLabel.Caption := Format('Status: aktiv auf http://%s:%d%s', [CDAIDefaultBindAddress, TDAIRuntime.ServerPort, CDAIMcpPath])
  else
  begin
    LError := Trim(TDAIRuntime.LastServerError);
    if LError = '' then
    begin
      if TDAISettings.Instance.Enabled then
        FServerStatusLabel.Caption := 'Status: gestoppt; bereit zum Starten in dieser IDE.'
      else
        FServerStatusLabel.Caption := 'Status: gestoppt; automatischer Start deaktiviert.';
    end
    else
      FServerStatusLabel.Caption := 'Status: nicht aktiv. ' + LError;
  end;
end;

procedure TDAIOptionsFrame.RefreshRegistrationStatus;
var
  LStatus: TJSONObject;
begin
  LStatus := nil;
  try
    try
      LStatus := TDAICodexRegistration.Status;
      FCodexStatusLabel.Caption := 'Codex: ' + LStatus.GetValue<string>('codex_config') + ' – ' +
        IfThen(LStatus.GetValue<Boolean>('codex_entry_registered'), 'registriert', 'nicht registriert');
      FSkillStatusLabel.Caption := 'Skill: ' + LStatus.GetValue<string>('skill_file') + ' – ' +
        IfThen(LStatus.GetValue<Boolean>('skill_registered'), 'registriert', 'nicht registriert');
    except
      on E: Exception do
      begin
        FCodexStatusLabel.Caption := 'Codex-Status nicht lesbar; Details in der Ergebnisliste.';
        FSkillStatusLabel.Caption := 'Skill-Status konnte nicht geprüft werden.';
      end;
    end;
  finally
    LStatus.Free;
  end;
  LStatus := TDAIClientRegistration.Status(SelectedClient);
  try
    DisplayClientStatus(LStatus);
  finally
    LStatus.Free;
  end;
end;

procedure TDAIOptionsFrame.DisplayClientStatus(const AStatus: TJSONObject);
var
  LClient: TJSONValue;
  LClients: TJSONArray;
  LObject: TJSONObject;
  LText: string;
begin
  FClientStatusMemo.Lines.BeginUpdate;
  try
    FClientStatusMemo.Clear;
    LClients := AStatus.GetValue<TJSONArray>('clients', nil);
    if not Assigned(LClients) then
      Exit;
    for LClient in LClients do
    begin
      if not (LClient is TJSONObject) then
        Continue;
      LObject := TJSONObject(LClient);
      LText := LObject.GetValue<string>('status', '');
      if LText = 'registered' then LText := 'registriert'
      else if LText = 'unregistered' then LText := 'deregistriert'
      else if LText = 'not_registered' then LText := 'nicht registriert'
      else if LText = 'needs_update' then LText := 'Registrierung muss aktualisiert werden'
      else if LText = 'not_detected' then LText := 'nicht erkannt'
      else if LText = 'unsupported' then LText := 'manuelle Einrichtung erforderlich'
      else if LText = 'manual_configuration' then LText := 'manuelle Einrichtung erforderlich'
      else if LText = 'configured' then LText := 'registriert'
      else if LText = 'configured_pending' then LText := 'registriert; Verwaltungsabschluss offen'
      else if LText = 'removed' then LText := 'deregistriert'
      else if LText = 'unchanged' then LText := 'unverändert'
      else if LText = 'conflict' then LText := 'Konflikt'
      else if LText = 'missing_bridge' then LText := 'Delphi-Brücke fehlt'
      else if LText = 'error' then LText := 'Fehler';
      FClientStatusMemo.Lines.Add(LObject.GetValue<string>('label', ''));
      AddIndentedLines(FClientStatusMemo.Lines, 'Status: ' + LText);
      LText := LObject.GetValue<string>('path', '');
      AddIndentedLines(FClientStatusMemo.Lines, LText);
      LText := LObject.GetValue<string>('message', '');
      AddIndentedLines(FClientStatusMemo.Lines, LText);
      LText := LObject.GetValue<string>('backup', '');
      if LText <> '' then AddIndentedLines(FClientStatusMemo.Lines, 'Sicherung: ' + LText);
    end;
  finally
    FClientStatusMemo.Lines.EndUpdate;
  end;
end;

function TDAIOptionsFrame.SelectedClient: string;
const
  CClients: array[0..9] of string = ('all', 'codex', 'claude-code', 'claude-desktop', 'eigent', 'gemini',
    'gemini-desktop', 'hermes', 'lm-studio', 'openclaw');
begin
  if (FClientComboBox.ItemIndex < Low(CClients)) or (FClientComboBox.ItemIndex > High(CClients)) then
    Exit('all');
  Result := CClients[FClientComboBox.ItemIndex];
end;

procedure TDAIOptionsFrame.ClientChanged(Sender: TObject);
begin
  RefreshRegistrationStatus;
end;

procedure TDAIOptionsFrame.RegisterClicked(Sender: TObject);
var
  LResult: TJSONObject;
begin
  try
    StoreToSettings;
    LResult := TDAIClientRegistration.RegisterFiles(SelectedClient);
    try
      RefreshRegistrationStatus;
      DisplayClientStatus(LResult);
    finally
      LResult.Free;
    end;
  except
    on E: Exception do
      TaskMessageDlg('DAI', E.Message, mtError, [mbOK], 0);
  end;
end;

function TDAIOptionsFrame.SelectedPermissionScope: TDAIPermissionScope;
begin
  if FScopeComboBox.ItemIndex = 1 then
    Result := psProject
  else
    Result := psGlobal;
end;

procedure TDAIOptionsFrame.SetPermissionComboLevel(const AComboBox: TComboBox; const ALevel: TDAIPermissionLevel);
begin
  case ALevel of
    plNever:
      AComboBox.ItemIndex := 1;
    plDeny:
      AComboBox.ItemIndex := 2;
    plOnce:
      AComboBox.ItemIndex := 3;
    plSession:
      AComboBox.ItemIndex := 4;
    plAlways:
      AComboBox.ItemIndex := 5;
  else
    AComboBox.ItemIndex := 0;
  end;
end;

procedure TDAIOptionsFrame.ScopeChanged(Sender: TObject);
begin
  LoadPermissionSettings;
end;

procedure TDAIOptionsFrame.StoreToSettings;
var
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
  LPort: Integer;
  LToken: string;
  LError: string;
begin
  LPort := StrToIntDef(Trim(FPortEdit.Text), 0);
  LToken := Trim(FTokenEdit.Text);
  if not TDAIRuntime.ValidateServerConfiguration(LPort, LToken, LError) then
    raise EArgumentException.Create(LError);
  TDAISettings.Instance.Enabled := FServerEnabledCheckBox.Checked;
  TDAISettings.Instance.LogAccessPoints := FLoggingCheckBox.Checked;
  TDAISettings.Instance.Port := LPort;
  TDAISettings.Instance.Token := LToken;
  TDAISettings.Instance.CustomReadDirectories.Assign(FDirectoriesMemo.Lines);
  TDAISettings.Instance.Save;

  LContext := PermissionContext;
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    TDAIPermissionManager.Instance.SetLevelFromOptions(
      LCategory,
      PermissionLevelFromCombo(FPermissionComboBoxes[LCategory]),
      LContext
    );

  if not TDAIRuntime.ApplySettings then
    TaskMessageDlg('DAI', TDAIRuntime.LastServerError, mtWarning, [mbOK], 0);
  RefreshServerStatus;
end;

procedure TDAIOptionsFrame.UnregisterClicked(Sender: TObject);
var
  LResult: TJSONObject;
begin
  try
    LResult := TDAIClientRegistration.UnregisterFiles(SelectedClient);
    try
      RefreshRegistrationStatus;
      DisplayClientStatus(LResult);
    finally
      LResult.Free;
    end;
  except
    on E: Exception do
      TaskMessageDlg('DAI', E.Message, mtError, [mbOK], 0);
  end;
end;

end.
