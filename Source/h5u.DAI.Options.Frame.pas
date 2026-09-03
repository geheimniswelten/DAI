unit h5u.DAI.Options.Frame;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  h5u.DAI.Types;

type
  TDAIOptionsFrame = class(TFrame)
  private
    FServerEnabledCheckBox: TCheckBox;
    FServerStatusLabel: TLabel;
    FLoggingCheckBox: TCheckBox;
    FPortEdit: TEdit;
    FTokenEdit: TEdit;
    FGenerateTokenButton: TButton;
    FDirectoriesMemo: TMemo;
    FDirectoryHintLabel: TLabel;
    FScopeComboBox: TComboBox;
    FProjectLabel: TLabel;
    FPermissionComboBoxes: array[TDAIPermissionCategory] of TComboBox;
    FCodexStatusLabel: TLabel;
    FSkillStatusLabel: TLabel;
    FRegisterButton: TButton;
    FUnregisterButton: TButton;
    procedure BuildControls;
    procedure RefreshServerStatus;
    procedure AddPermissionRow(const AParent: TWinControl; const ACategory: TDAIPermissionCategory; var ATop: Integer);
    procedure PopulatePermissionCombo(const AComboBox: TComboBox);
    procedure ScopeChanged(Sender: TObject);
    procedure GenerateTokenClicked(Sender: TObject);
    procedure RegisterClicked(Sender: TObject);
    procedure UnregisterClicked(Sender: TObject);
    function SelectedPermissionScope: TDAIPermissionScope;
    function PermissionLevelFromCombo(const AComboBox: TComboBox): TDAIPermissionLevel;
    procedure SetPermissionComboLevel(const AComboBox: TComboBox; const ALevel: TDAIPermissionLevel);
    function PermissionContext: TDAIRequestContext;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromSettings;
    procedure StoreToSettings;
    procedure RefreshRegistrationStatus;
  end;

implementation

{$R *.dfm}

uses
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Graphics,
  h5u.DAI.Codex.Registration,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Settings;

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
  FServerEnabledCheckBox.Caption := 'MCP-Server für Codex aktivieren';
  FServerEnabledCheckBox.Width := 300;
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
  FGenerateTokenButton.Hint := 'Erzeugt eine neue GUID. Danach „Registrieren“ und Codex neu starten, damit die neue Verbindung verwendet wird.';
  FGenerateTokenButton.ShowHint := True;
  FGenerateTokenButton.OnClick := GenerateTokenClicked;
  Inc(LTop, 32);

  FServerStatusLabel := NewLabel(Self, '', 24, LTop);
  FServerStatusLabel.AutoSize := False;
  FServerStatusLabel.WordWrap := True;
  FServerStatusLabel.Width := 760;
  FServerStatusLabel.Height := 72;
  Inc(LTop, 76);

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

  with NewLabel(Self, 'Codex- und Skill-Registrierung', 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 30);

  FCodexStatusLabel := NewLabel(Self, '', 24, LTop);
  Inc(LTop, 24);
  FSkillStatusLabel := NewLabel(Self, '', 24, LTop);
  Inc(LTop, 34);

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
  Inc(LTop, 48);

  Align := alTop;
  Height := LTop;
end;

procedure TDAIOptionsFrame.GenerateTokenClicked(Sender: TObject);
begin
  FTokenEdit.Text := TDAISettings.Instance.GenerateToken;
  FTokenEdit.SetFocus;
  FTokenEdit.SelectAll;
end;

procedure TDAIOptionsFrame.LoadFromSettings;
var
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
begin
  FServerEnabledCheckBox.Checked := TDAISettings.Instance.Enabled;
  FLoggingCheckBox.Checked := TDAISettings.Instance.LogAccessPoints;
  FPortEdit.Text := IntToStr(TDAISettings.Instance.Port);
  FTokenEdit.Text := TDAISettings.Instance.Token;
  FDirectoriesMemo.Lines.Assign(TDAISettings.Instance.CustomReadDirectories);
  FDirectoriesMemo.TextHint := TDAISettings.Instance.LocalizedProjectsDirectoryHint;
  FDirectoryHintLabel.Caption := 'Vorschlag für diese IDE-Sprache: ' + TDAISettings.Instance.LocalizedProjectsDirectoryHint;
  RefreshServerStatus;

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

  RefreshRegistrationStatus;
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
  if not TDAISettings.Instance.Enabled then
    FServerStatusLabel.Caption := 'Status: deaktiviert.'
  else if TDAIRuntime.ServerActive then
    FServerStatusLabel.Caption := Format('Status: aktiv auf http://%s:%d%s', [CDAIDefaultBindAddress, TDAISettings.Instance.Port, CDAIMcpPath])
  else
  begin
    LError := Trim(TDAIRuntime.LastServerError);
    if LError = '' then
      FServerStatusLabel.Caption := 'Status: aktiviert, aber nicht gestartet.'
    else
      FServerStatusLabel.Caption := 'Status: nicht aktiv. ' + LError;
  end;
end;

procedure TDAIOptionsFrame.RefreshRegistrationStatus;
var
  LStatus: TJSONObject;
begin
  LStatus := TDAICodexRegistration.Status;
  try
    FCodexStatusLabel.Caption := 'Codex: ' + LStatus.GetValue<string>('codex_config') + ' – ' +
      IfThen(LStatus.GetValue<Boolean>('codex_entry_registered'), 'registriert', 'nicht registriert');
    FSkillStatusLabel.Caption := 'Skill: ' + LStatus.GetValue<string>('skill_file') + ' – ' +
      IfThen(LStatus.GetValue<Boolean>('skill_registered'), 'registriert', 'nicht registriert');
  finally
    LStatus.Free;
  end;
end;

procedure TDAIOptionsFrame.RegisterClicked(Sender: TObject);
begin
  try
    StoreToSettings;
    TDAICodexRegistration.RegisterFiles;
    RefreshRegistrationStatus;
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
  LoadFromSettings;
end;

procedure TDAIOptionsFrame.StoreToSettings;
var
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
begin
  TDAISettings.Instance.Enabled := FServerEnabledCheckBox.Checked;
  TDAISettings.Instance.LogAccessPoints := FLoggingCheckBox.Checked;
  TDAISettings.Instance.Port := StrToIntDef(FPortEdit.Text, 0);
  TDAISettings.Instance.Token := Trim(FTokenEdit.Text);
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
begin
  try
    TDAICodexRegistration.UnregisterFiles;
    RefreshRegistrationStatus;
  except
    on E: Exception do
      TaskMessageDlg('DAI', E.Message, mtError, [mbOK], 0);
  end;
end;

end.
