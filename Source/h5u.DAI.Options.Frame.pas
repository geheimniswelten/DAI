unit h5u.DAI.Options.Frame;

interface

uses
  System.Classes,
  System.JSON,
  Vcl.Buttons,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  h5u.DAI.Types;

type
  TDAIOptionsFrame = class(TFrame)
  private
    FServerEnabledCheckBox: TCheckBox;
    FAllowIDEStartStopCheckBox: TCheckBox;
    FLoadedAllowIDEStartStop: Boolean;
    FServerStatusLabel: TLabel;
    FStartServerButton: TButton;
    FStopServerButton: TButton;
    FLoggingCheckBox: TCheckBox;
    FPortEdit: TEdit;
    FTokenEdit: TEdit;
    FGenerateTokenButton: TButton;
    FDirectoriesMemo: TMemo;
    FDirectoryHintLabel: TLabel;
    FProjectLabel: TLabel;
    FPermissionProjectKey: string;
    FLoadingPermissions: Boolean;
    FPermissionComboBoxes: array[TDAIPermissionScope, TDAIPermissionCategory] of TComboBox;
    FPermissionButtons: array[TDAIPermissionCategory] of TBitBtn;
    FPermissionModified: array[TDAIPermissionScope, TDAIPermissionCategory] of Boolean;
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
    procedure PermissionChanged(Sender: TObject);
    procedure PermissionDialogClicked(Sender: TObject);
    procedure RefreshInheritedPermissionHints;
    procedure UpdateProjectPermissionState;
    procedure LoadPermissionSettings;
    procedure StartServerClicked(Sender: TObject);
    procedure StopServerClicked(Sender: TObject);
    procedure GenerateTokenClicked(Sender: TObject);
    procedure ClientChanged(Sender: TObject);
    function SelectedClient: string;
    procedure RegisterClicked(Sender: TObject);
    procedure UnregisterClicked(Sender: TObject);
    procedure ShowToolsClicked(Sender: TObject);
    function PermissionLevelFromCombo(const AComboBox: TComboBox): TDAIPermissionLevel;
    procedure SetPermissionComboLevel(const AComboBox: TComboBox; const ALevel: TDAIPermissionLevel);
    function PermissionContext(const AScope: TDAIPermissionScope): TDAIRequestContext;
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
  System.Types,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Graphics,
  h5u.DAI.Clients.Registration,
  h5u.DAI.Codex.Registration,
  h5u.DAI.Consts,
  h5u.DAI.MCP.Tools,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Dialog,
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
  FLoadedAllowIDEStartStop := True;
  BuildControls;
end;

procedure DrawPermissionGlyph(const ABitmap: TBitmap);
begin
  ABitmap.PixelFormat := pf24bit;
  ABitmap.SetSize(16, 16);
  with ABitmap.Canvas do
  begin
    Brush.Color := clBtnFace;
    FillRect(Rect(0, 0, 16, 16));
    Pen.Style := psClear;
    Brush.Color := $0048C8F0;
    Polygon([Point(2, 2), Point(13, 2), Point(13, 9), Point(8, 14), Point(2, 9)]);
    Brush.Color := $00D09040;
    Polygon([Point(2, 2), Point(8, 2), Point(8, 14), Point(2, 9)]);
    Pen.Style := psSolid;
    Pen.Color := clGrayText;
    Brush.Style := bsClear;
    Polygon([Point(2, 2), Point(13, 2), Point(13, 9), Point(8, 14), Point(2, 9)]);
    Brush.Style := bsSolid;
  end;
end;

procedure TDAIOptionsFrame.AddPermissionRow(const AParent: TWinControl; const ACategory: TDAIPermissionCategory; var ATop: Integer);
var
  LButton: TBitBtn;
  LComboBox: TComboBox;
  LLeft: Integer;
  LName: string;
  LScope: TDAIPermissionScope;
begin
  NewLabel(AParent, DAIPermissionCategoryName(ACategory), 24, ATop + 4);
  for LScope := Low(TDAIPermissionScope) to High(TDAIPermissionScope) do
  begin
    if LScope = psGlobal then
      LLeft := 320
    else
      LLeft := 548;
    LName := 'DAIPermission' + IfThen(LScope = psGlobal, 'Global', 'Project') + IntToStr(Ord(ACategory));
    LComboBox := TComboBox.Create(AParent);
    LComboBox.Parent := AParent;
    LComboBox.Name := LName + 'ComboBox';
    LComboBox.SetBounds(LLeft, ATop, 190, 24);
    LComboBox.Style := csDropDownList;
    PopulatePermissionCombo(LComboBox);
    if LScope = psProject then
      LComboBox.Items.Add('Default')
    else
      LComboBox.Items[4] := 'Für diese IDE-Sitzung';
    LComboBox.Tag := Ord(LScope) * (Ord(High(TDAIPermissionCategory)) + 1) + Ord(ACategory);
    LComboBox.ShowHint := True;
    LComboBox.OnChange := PermissionChanged;
    FPermissionComboBoxes[LScope, ACategory] := LComboBox;
  end;
  LButton := TBitBtn.Create(AParent);
  LButton.Parent := AParent;
  LButton.Name := 'DAIPermission' + IntToStr(Ord(ACategory)) + 'DialogButton';
  LButton.SetBounds(744, ATop - 1, 24, 24);
  LButton.Tag := Ord(ACategory);
  LButton.Hint := DAIPermissionCategoryName(ACategory) + ' – Berechtigung auswählen';
  LButton.ShowHint := True;
  DrawPermissionGlyph(LButton.Glyph);
  LButton.OnClick := PermissionDialogClicked;
  FPermissionButtons[ACategory] := LButton;
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

  FAllowIDEStartStopCheckBox := TCheckBox.Create(Self);
  FAllowIDEStartStopCheckBox.Parent := Self;
  FAllowIDEStartStopCheckBox.Name := 'DAIAllowIDEStartStopCheckBox';
  FAllowIDEStartStopCheckBox.SetBounds(24, LTop, 650, 24);
  FAllowIDEStartStopCheckBox.Caption := 'KI darf die Delphi-IDE starten und beenden';
  FAllowIDEStartStopCheckBox.Checked := True;
  FAllowIDEStartStopCheckBox.Hint := 'Gilt für alle Delphi-Versionen und Profile dieses Windows-Benutzers. ' +
    'Wird beim Speichern oder Registrieren wirksam. dai_start bleibt für Statusabfragen registriert.';
  FAllowIDEStartStopCheckBox.ShowHint := True;
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

  NewLabel(Self, 'Global', 320, LTop + 4);
  NewLabel(Self, 'Aktuelles Projekt', 548, LTop + 4);
  Inc(LTop, 34);

  FProjectLabel := NewLabel(Self, '', 24, LTop);
  FProjectLabel.Width := 744;
  FProjectLabel.AutoSize := False;
  FProjectLabel.WordWrap := True;
  FProjectLabel.Height := 44;
  Inc(LTop, 52);

  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    AddPermissionRow(Self, LCategory, LTop);

  LInfoLabel := NewLabel(
    Self,
    '„Verweigern“, „Nur diesmal“ und „Für diese Session“ sind Laufzeitentscheidungen. „Nie“ und „Immer“ gelten im jeweiligen Bereich.',
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
  FLoadedAllowIDEStartStop := TDAISettings.Instance.AllowIDEStartStop;
  FAllowIDEStartStopCheckBox.Checked := FLoadedAllowIDEStartStop;
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
  LInheritsGlobal: Boolean;
  LLevel: TDAIPermissionLevel;
  LScope: TDAIPermissionScope;
begin
  FPermissionProjectKey := TDAIOTA.ActiveProjectFileName;
  FLoadingPermissions := True;
  try
    for LScope := Low(TDAIPermissionScope) to High(TDAIPermissionScope) do
    begin
      LContext := PermissionContext(LScope);
      for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
      begin
        if (LScope = psProject) and (FPermissionProjectKey = '') then
          FPermissionComboBoxes[LScope, LCategory].ItemIndex := 6
        else
        begin
          LLevel := TDAIPermissionManager.Instance.GetLevelForOptions(LCategory, LContext, LInheritsGlobal);
          if (LScope = psProject) and LInheritsGlobal then
            FPermissionComboBoxes[LScope, LCategory].ItemIndex := 6
          else
            SetPermissionComboLevel(FPermissionComboBoxes[LScope, LCategory], LLevel);
        end;
        FPermissionModified[LScope, LCategory] := False;
      end;
    end;
  finally
    FLoadingPermissions := False;
  end;
  UpdateProjectPermissionState;
  RefreshInheritedPermissionHints;
end;

procedure TDAIOptionsFrame.UpdateProjectPermissionState;
var
  LAvailable: Boolean;
  LCategory: TDAIPermissionCategory;
begin
  LAvailable := (FPermissionProjectKey <> '') and SameText(FPermissionProjectKey, TDAIOTA.ActiveProjectFileName);
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
  begin
    FPermissionComboBoxes[psProject, LCategory].Enabled := LAvailable;
    FPermissionButtons[LCategory].Enabled := True;
    FPermissionButtons[LCategory].Hint := DAIPermissionCategoryName(LCategory) + ' – ' +
      IfThen(LAvailable, 'Berechtigung für das angezeigte Projekt auswählen', 'globale Berechtigung auswählen');
  end;
  if LAvailable then
    FProjectLabel.Caption := 'Aktuelles Projekt: ' + FPermissionProjectKey + sLineBreak +
      'Projektdatei: ' + ChangeFileExt(FPermissionProjectKey, '.dai.permissions.json')
  else if TDAIOTA.ActiveProjectFileName = '' then
    FProjectLabel.Caption := 'Kein aktives Projekt. Projektberechtigungen sind deaktiviert.'
  else
    FProjectLabel.Caption := 'Das aktive Projekt hat gewechselt. Die Optionen für das neue Projekt erneut öffnen.';
end;

procedure TDAIOptionsFrame.RefreshInheritedPermissionHints;
var
  LCategory: TDAIPermissionCategory;
  LComboBox: TComboBox;
begin
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
  begin
    LComboBox := FPermissionComboBoxes[psProject, LCategory];
    if not LComboBox.Enabled then
      LComboBox.Hint := 'Kein passendes aktives Projekt.'
    else if LComboBox.ItemIndex = 6 then
      LComboBox.Hint := 'Default: globalen Standard verwenden (' + FPermissionComboBoxes[psGlobal, LCategory].Text + '). ' +
        'Beim Speichern wird eine eigene Projektvorgabe entfernt.'
    else
      LComboBox.Hint := 'Eigene Projektberechtigung. Mit „Default“ wieder den globalen Standard verwenden.';
  end;
end;

function TDAIOptionsFrame.PermissionContext(const AScope: TDAIPermissionScope): TDAIRequestContext;
begin
  Result := Default(TDAIRequestContext);
  Result.ThreadId := '*';
  Result.TransportSessionId := 'options';
  Result.ClientName := 'IDE-Optionen';
  if AScope = psProject then
    Result.ProjectKey := FPermissionProjectKey;
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

procedure TDAIOptionsFrame.PermissionChanged(Sender: TObject);
var
  LCategory: TDAIPermissionCategory;
  LComboBox: TComboBox;
  LScope: TDAIPermissionScope;
begin
  if FLoadingPermissions or not (Sender is TComboBox) then
    Exit;
  LComboBox := TComboBox(Sender);
  LScope := TDAIPermissionScope(LComboBox.Tag div (Ord(High(TDAIPermissionCategory)) + 1));
  LCategory := TDAIPermissionCategory(LComboBox.Tag mod (Ord(High(TDAIPermissionCategory)) + 1));
  if not LComboBox.Enabled then
    Exit;
  FPermissionModified[LScope, LCategory] := True;
  RefreshInheritedPermissionHints;
end;

procedure TDAIOptionsFrame.PermissionDialogClicked(Sender: TObject);
var
  LButton: TBitBtn;
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
  LCurrentLevel: TDAIPermissionLevel;
  LDecision: TDAIPermissionPromptResult;
  LOtherCategory: TDAIPermissionCategory;
  LOtherLevel: TDAIPermissionLevel;
  LScope: TDAIPermissionScope;
begin
  if not (Sender is TBitBtn) then
    Exit;
  UpdateProjectPermissionState;
  LButton := TBitBtn(Sender);
  if not LButton.Enabled then
    Exit;
  LCategory := TDAIPermissionCategory(LButton.Tag);
  if FPermissionComboBoxes[psProject, LCategory].Enabled then
    LScope := psProject
  else
    LScope := psGlobal;
  LContext := PermissionContext(LScope);
  LCurrentLevel := PermissionLevelFromCombo(FPermissionComboBoxes[LScope, LCategory]);
  if (LScope = psProject) and (FPermissionComboBoxes[LScope, LCategory].ItemIndex = 6) then
    LCurrentLevel := PermissionLevelFromCombo(FPermissionComboBoxes[psGlobal, LCategory]);
  if not TDAIPermissionDialog.SelectForOptions(LCategory, LContext, LCurrentLevel, LDecision) then
    Exit;
  SetPermissionComboLevel(FPermissionComboBoxes[LScope, LCategory], LDecision.Level);
  FPermissionModified[LScope, LCategory] := True;
  if LDecision.ApplyToLowerLevels then
    for LOtherCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    begin
      if LOtherCategory = LCategory then
        Continue;
      LOtherLevel := PermissionLevelFromCombo(FPermissionComboBoxes[LScope, LOtherCategory]);
      if (LScope = psProject) and (FPermissionComboBoxes[LScope, LOtherCategory].ItemIndex = 6) then
        LOtherLevel := PermissionLevelFromCombo(FPermissionComboBoxes[psGlobal, LOtherCategory]);
      if DAIPermissionLevelRank(LOtherLevel) < DAIPermissionLevelRank(LDecision.Level) then
      begin
        SetPermissionComboLevel(FPermissionComboBoxes[LScope, LOtherCategory], LDecision.Level);
        FPermissionModified[LScope, LOtherCategory] := True;
      end;
    end;
  RefreshInheritedPermissionHints;
end;

procedure TDAIOptionsFrame.StoreToSettings;
var
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
  LScope: TDAIPermissionScope;
  LPort: Integer;
  LToken: string;
  LError: string;
begin
  UpdateProjectPermissionState;
  if (FPermissionProjectKey <> '') and not FPermissionComboBoxes[psProject, Low(TDAIPermissionCategory)].Enabled then
    for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
      if FPermissionModified[psProject, LCategory] then
        raise EInvalidOperation.Create('Das aktive Projekt hat gewechselt. Projektberechtigungen wurden nicht gespeichert; die Optionen erneut öffnen.');
  LPort := StrToIntDef(Trim(FPortEdit.Text), 0);
  LToken := Trim(FTokenEdit.Text);
  if not TDAIRuntime.ValidateServerConfiguration(LPort, LToken, LError) then
    raise EArgumentException.Create(LError);
  TDAISettings.Instance.Enabled := FServerEnabledCheckBox.Checked;
  TDAISettings.Instance.LogAccessPoints := FLoggingCheckBox.Checked;
  TDAISettings.Instance.Port := LPort;
  TDAISettings.Instance.Token := LToken;
  TDAISettings.Instance.CustomReadDirectories.Assign(FDirectoriesMemo.Lines);
  if FAllowIDEStartStopCheckBox.Checked <> FLoadedAllowIDEStartStop then
    TDAISettings.Instance.AllowIDEStartStop := FAllowIDEStartStopCheckBox.Checked;
  try
    TDAISettings.Instance.Save;
  except
    TDAISettings.Instance.DiscardLifecycleChange;
    raise;
  end;
  FLoadedAllowIDEStartStop := TDAISettings.Instance.AllowIDEStartStop;
  FAllowIDEStartStopCheckBox.Checked := FLoadedAllowIDEStartStop;

  for LScope := Low(TDAIPermissionScope) to High(TDAIPermissionScope) do
  begin
    if (LScope = psProject) and (FPermissionProjectKey = '') then
      Continue;
    LContext := PermissionContext(LScope);
    for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
      if FPermissionModified[LScope, LCategory] then
      begin
        if (LScope = psProject) and (FPermissionComboBoxes[LScope, LCategory].ItemIndex = 6) then
          TDAIPermissionManager.Instance.UseGlobalLevelFromOptions(LCategory, LContext)
        else
          TDAIPermissionManager.Instance.SetLevelFromOptions(
            LCategory,
            PermissionLevelFromCombo(FPermissionComboBoxes[LScope, LCategory]),
            LContext
          );
        FPermissionModified[LScope, LCategory] := False;
      end;
  end;

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
