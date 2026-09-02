unit CodexMCP.Options.Frame;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls;

type
  TCodexMCPOptionsFrame = class(TFrame)
  strict private
    FAdditionalRootsEdit: TMemo;
    FCodexConfigStatusLabel: TLabel;
    FCodexPathLabel: TLabel;
    FEnabledCheckBox: TCheckBox;
    FLoggingCheckBox: TCheckBox;
    FPortEdit: TEdit;
    FServerStatusLabel: TLabel;
    FSkillPathLabel: TLabel;
    FSkillStatusLabel: TLabel;
    FTokenEdit: TEdit;
    procedure AddSectionLabel(const ACaption: string; const ATop: Integer);
    procedure DeregisterCodexClick(Sender: TObject);
    procedure DeregisterSkillClick(Sender: TObject);
    procedure NewTokenClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure RegisterCodexClick(Sender: TObject);
    procedure RegisterSkillClick(Sender: TObject);
    function StatusText(
      const AExists,
      ARegistered: Boolean
    ): string;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromSettings;
    procedure StoreToSettings;
    procedure UpdateStatus;
    function ValidateSettings(out AMessage: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Dialogs,
  Vcl.ExtCtrls,
  CodexMCP.CodexRegistration,
  CodexMCP.Constants,
  CodexMCP.Host,
  CodexMCP.Settings;

const
  CLeft = 16;
  CLabelWidth = 145;
  CEditLeft = CLeft + CLabelWidth + 8;

function NewLabel(
  const AOwner: TComponent;
  const AParent: TWinControl;
  const ACaption: string;
  const ALeft,
  ATop,
  AWidth: Integer
): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.AutoSize := False;
end;

function NewButton(
  const AOwner: TComponent;
  const AParent: TWinControl;
  const ACaption: string;
  const ALeft,
  ATop,
  AWidth: Integer;
  const AOnClick: TNotifyEvent
): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, ATop, AWidth, 27);
  Result.OnClick := AOnClick;
end;

{ TCodexMCPOptionsFrame }

procedure TCodexMCPOptionsFrame.AddSectionLabel(
  const ACaption: string;
  const ATop: Integer
);
var
  LLabel: TLabel;
begin
  LLabel := NewLabel(Self, Self, ACaption, CLeft, ATop, 650);
  LLabel.Font.Style := [fsBold];
end;

constructor TCodexMCPOptionsFrame.Create(AOwner: TComponent);
var
  LBevel: TBevel;
  LButtonLeft: Integer;
  LLabel: TLabel;
begin
  inherited Create(AOwner);
  Name := 'CodexMCPOptionsFrame';
  Width := 760;
  Height := 610;
  AutoScroll := True;

  AddSectionLabel('MCP-Server', 12);

  FEnabledCheckBox := TCheckBox.Create(Self);
  FEnabledCheckBox.Parent := Self;
  FEnabledCheckBox.Caption := 'MCP-Server für Codex aktivieren';
  FEnabledCheckBox.SetBounds(CLeft, 39, 330, 21);

  LLabel := NewLabel(Self, Self, 'Port:', CLeft, 72, CLabelWidth);
  FPortEdit := TEdit.Create(Self);
  FPortEdit.Parent := Self;
  FPortEdit.SetBounds(CEditLeft, 68, 90, 23);
  FPortEdit.NumbersOnly := True;
  FPortEdit.MaxLength := 5;

  FLoggingCheckBox := TCheckBox.Create(Self);
  FLoggingCheckBox.Parent := Self;
  FLoggingCheckBox.Caption :=
    'Alle MCP-Zugriffspunkte über IOTAMessageServices.AddTitleMessage protokollieren';
  FLoggingCheckBox.SetBounds(CLeft, 103, 650, 21);

  LLabel := NewLabel(Self, Self, 'Bearer-Token:', CLeft, 138, CLabelWidth);
  FTokenEdit := TEdit.Create(Self);
  FTokenEdit.Parent := Self;
  FTokenEdit.SetBounds(CEditLeft, 134, 405, 23);
  FTokenEdit.PasswordChar := '*';
  FTokenEdit.Anchors := [akLeft, akTop, akRight];
  NewButton(
    Self,
    Self,
    'Neu erzeugen',
    CEditLeft + 415,
    132,
    110,
    NewTokenClick
  );

  FServerStatusLabel := NewLabel(
    Self,
    Self,
    'Serverstatus:',
    CLeft,
    171,
    710
  );

  LBevel := TBevel.Create(Self);
  LBevel.Parent := Self;
  LBevel.Shape := bsTopLine;
  LBevel.SetBounds(CLeft, 202, 710, 2);
  LBevel.Anchors := [akLeft, akTop, akRight];

  AddSectionLabel('Zusätzliche schreibgeschützte Verzeichnisse', 216);
  LLabel := NewLabel(
    Self,
    Self,
    'Je Zeile ein Verzeichnis. Diese Pfade können gelesen, aber niemals über MCP geschrieben werden.',
    CLeft,
    242,
    710
  );
  FAdditionalRootsEdit := TMemo.Create(Self);
  FAdditionalRootsEdit.Parent := Self;
  FAdditionalRootsEdit.SetBounds(CLeft, 266, 710, 105);
  FAdditionalRootsEdit.ScrollBars := ssVertical;
  FAdditionalRootsEdit.WordWrap := False;
  FAdditionalRootsEdit.TextHint :=
    '%USERPROFILE%\Documents\Embarcadero\Studio\Projekte';
  FAdditionalRootsEdit.Anchors := [akLeft, akTop, akRight];

  LBevel := TBevel.Create(Self);
  LBevel.Parent := Self;
  LBevel.Shape := bsTopLine;
  LBevel.SetBounds(CLeft, 389, 710, 2);
  LBevel.Anchors := [akLeft, akTop, akRight];

  AddSectionLabel('Codex- und Agent-Registrierung', 403);
  FCodexPathLabel := NewLabel(Self, Self, '', CLeft, 430, 710);
  FCodexPathLabel.ShowHint := True;
  FCodexConfigStatusLabel := NewLabel(Self, Self, '', CLeft, 452, 710);
  LButtonLeft := CLeft;
  NewButton(Self, Self, 'Codex registrieren', LButtonLeft, 477, 145, RegisterCodexClick);
  Inc(LButtonLeft, 153);
  NewButton(Self, Self, 'Codex deregistrieren', LButtonLeft, 477, 155, DeregisterCodexClick);

  FSkillPathLabel := NewLabel(Self, Self, '', CLeft, 519, 710);
  FSkillPathLabel.ShowHint := True;
  FSkillStatusLabel := NewLabel(Self, Self, '', CLeft, 541, 710);
  LButtonLeft := CLeft;
  NewButton(Self, Self, 'Skill registrieren', LButtonLeft, 566, 145, RegisterSkillClick);
  Inc(LButtonLeft, 153);
  NewButton(Self, Self, 'Skill deregistrieren', LButtonLeft, 566, 155, DeregisterSkillClick);
  NewButton(Self, Self, 'Status aktualisieren', 565, 566, 160, RefreshClick);

  LoadFromSettings;
end;

procedure TCodexMCPOptionsFrame.DeregisterCodexClick(Sender: TObject);
begin
  try
    TCodexMCPRegistration.DeregisterCodex;
  except
    on E: Exception do
      MessageDlg(
        'Die Codex-Deregistrierung ist fehlgeschlagen:' + sLineBreak +
        E.Message,
        mtError,
        [mbOK],
        0
      );
  end;
  UpdateStatus;
end;

procedure TCodexMCPOptionsFrame.DeregisterSkillClick(Sender: TObject);
begin
  try
    TCodexMCPRegistration.DeregisterSkill;
  except
    on E: Exception do
      MessageDlg(
        'Die Skill-Deregistrierung ist fehlgeschlagen:' + sLineBreak +
        E.Message,
        mtError,
        [mbOK],
        0
      );
  end;
  UpdateStatus;
end;

procedure TCodexMCPOptionsFrame.LoadFromSettings;
var
  LSettings: TCodexMCPSettings;
begin
  LSettings := TCodexMCPSettings.Instance;
  FEnabledCheckBox.Checked := LSettings.Enabled;
  FPortEdit.Text := IntToStr(LSettings.Port);
  FLoggingCheckBox.Checked := LSettings.LoggingEnabled;
  FAdditionalRootsEdit.Text := LSettings.AdditionalReadOnlyRoots;
  FTokenEdit.Text := LSettings.AuthToken;
  UpdateStatus;
end;

procedure TCodexMCPOptionsFrame.NewTokenClick(Sender: TObject);
begin
  FTokenEdit.Text := TCodexMCPSettings.GenerateAuthToken;
end;

procedure TCodexMCPOptionsFrame.RefreshClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TCodexMCPOptionsFrame.RegisterCodexClick(Sender: TObject);
var
  LMessage: string;
begin
  if not ValidateSettings(LMessage) then
  begin
    MessageDlg(LMessage, mtError, [mbOK], 0);
    Exit;
  end;
  try
    StoreToSettings;
    if not TCodexMCPRegistration.IsCodexRegistered then
      TCodexMCPRegistration.RegisterCodex;
  except
    on E: Exception do
      MessageDlg(
        'Die Codex-Registrierung ist fehlgeschlagen:' + sLineBreak +
        E.Message,
        mtError,
        [mbOK],
        0
      );
  end;
  UpdateStatus;
end;

procedure TCodexMCPOptionsFrame.RegisterSkillClick(Sender: TObject);
begin
  try
    TCodexMCPRegistration.RegisterSkill;
  except
    on E: Exception do
      MessageDlg(
        'Die Skill-Registrierung ist fehlgeschlagen:' + sLineBreak +
        E.Message,
        mtError,
        [mbOK],
        0
      );
  end;
  UpdateStatus;
end;

function TCodexMCPOptionsFrame.StatusText(
  const AExists,
  ARegistered: Boolean
): string;
begin
  Result := Format(
    'FileExists: %s; registriert: %s',
    [BoolToStr(AExists, True), BoolToStr(ARegistered, True)]
  );
end;

procedure TCodexMCPOptionsFrame.StoreToSettings;
var
  LPort: Integer;
  LSettings: TCodexMCPSettings;
  LWasCodexRegistered: Boolean;
begin
  if not TryStrToInt(Trim(FPortEdit.Text), LPort) then
    raise EConvertError.Create('Der MCP-Port ist keine gültige Ganzzahl.');
  LWasCodexRegistered := TCodexMCPRegistration.IsCodexRegistered;
  LSettings := TCodexMCPSettings.Instance;
  LSettings.Enabled := FEnabledCheckBox.Checked;
  LSettings.Port := LPort;
  LSettings.LoggingEnabled := FLoggingCheckBox.Checked;
  LSettings.AdditionalReadOnlyRoots := FAdditionalRootsEdit.Text;
  LSettings.AuthToken := Trim(FTokenEdit.Text);
  LSettings.Save;
  if LWasCodexRegistered then
    TCodexMCPRegistration.RegisterCodex;
  TCodexMCPHost.Instance.ApplySettings;
  UpdateStatus;
end;

procedure TCodexMCPOptionsFrame.UpdateStatus;
begin
  FCodexPathLabel.Caption :=
    'Codex: ' + TCodexMCPRegistration.CodexConfigFile;
  FCodexPathLabel.Hint := FCodexPathLabel.Caption;
  FCodexConfigStatusLabel.Caption := StatusText(
    TCodexMCPRegistration.CodexConfigExists,
    TCodexMCPRegistration.IsCodexRegistered
  );

  FSkillPathLabel.Caption :=
    'Skill: ' + TCodexMCPRegistration.SkillFile;
  FSkillPathLabel.Hint := FSkillPathLabel.Caption;
  FSkillStatusLabel.Caption := StatusText(
    TCodexMCPRegistration.SkillFileExists,
    TCodexMCPRegistration.IsSkillRegistered
  );
  FServerStatusLabel.Caption :=
    'Serverstatus: ' + TCodexMCPHost.Instance.StatusText;
end;

function TCodexMCPOptionsFrame.ValidateSettings(
  out AMessage: string
): Boolean;
var
  LPort: Integer;
begin
  AMessage := '';
  if not TryStrToInt(Trim(FPortEdit.Text), LPort) or
    (LPort < 1024) or (LPort > 65535) then
  begin
    AMessage := 'Der MCP-Port muss zwischen 1024 und 65535 liegen.';
    Exit(False);
  end;
  if Trim(FTokenEdit.Text) = '' then
  begin
    AMessage := 'Der Bearer-Token darf nicht leer sein.';
    Exit(False);
  end;
  if not TCodexMCPSettings.IsValidAuthToken(FTokenEdit.Text) then
  begin
    AMessage := 'Der Bearer-Token darf keine Leer- oder Steuerzeichen enthalten.';
    Exit(False);
  end;
  Result := True;
end;

end.
