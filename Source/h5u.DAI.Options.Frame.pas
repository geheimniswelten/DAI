unit h5u.DAI.Options.Frame;

interface

uses
  System.Classes,
  System.JSON,
  Vcl.Buttons,
  Vcl.Controls,
  Vcl.ExtCtrls,
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
    FUsageLogLink: TLinkLabel;
    FUseSharedConnectionSettingsCheckBox: TCheckBox;
    FLoadingConnectionSettings: Boolean;
    FDisplayedSharedConnectionSettings: Boolean;
    FConnectionDraftAvailable: array[Boolean] of Boolean;
    FConnectionPortDraft: array[Boolean] of string;
    FConnectionTokenDraft: array[Boolean] of string;
    FManualRegistrationLoaded: array[Boolean] of Boolean;
    FManualRegistrationDraft: array[Boolean] of Boolean;
    FPortEdit: TEdit;
    FTokenEdit: TEdit;
    FGenerateTokenButton: TButton;
    FDirectoriesMemo: TMemo;
    FDirectoriesAlwaysAllowedCheckBox: TCheckBox;
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
    FFindRegistrationsButton: TButton;
    FManualRegistrationButton: TButton;
    FManualClientRegistrationCheckBox: TCheckBox;
    FShowToolsButton: TButton;
    procedure BuildControls;
    procedure RefreshServerStatus;
    procedure DisplayClientStatus(const AStatus: TJSONObject);
    procedure AddPermissionRow(const AParent: TWinControl; const ACategory: TDAIPermissionCategory; var ATop: Integer);
    procedure PopulatePermissionCombo(const AComboBox: TComboBox);
    procedure PermissionChanged(Sender: TObject);
    procedure ResetProjectPermissionDraft(const ACategory: TDAIPermissionCategory);
    procedure PermissionDialogClicked(Sender: TObject);
    procedure RefreshInheritedPermissionHints;
    procedure UpdateProjectPermissionState;
    procedure LoadPermissionSettings;
    procedure LoadConnectionSettings;
    procedure StoreSettings(const ARefreshRegistrationHealth: Boolean);
    procedure ConnectionSettingsScopeClicked(Sender: TObject);
    procedure StartServerClicked(Sender: TObject);
    procedure StopServerClicked(Sender: TObject);
    procedure GenerateTokenClicked(Sender: TObject);
    procedure UsageLogLinkClicked(Sender: TObject; const Link: string; LinkType: TSysLinkType);
    procedure ClientChanged(Sender: TObject);
    function SelectedClient: string;
    procedure RegisterClicked(Sender: TObject);
    procedure UnregisterClicked(Sender: TObject);
    procedure FindRegistrationsClicked(Sender: TObject);
    procedure ShowToolsClicked(Sender: TObject);
    procedure ManualRegistrationClicked(Sender: TObject);
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
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  System.Types,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Clipbrd,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Winapi.Messages,
  h5u.DAI.Clients.Registration,
  h5u.DAI.Codex.Registration,
  h5u.DAI.Consts,
  h5u.DAI.IDE.Toolbar,
  h5u.DAI.Localization,
  h5u.DAI.MCP.Tools,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Dialog,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Registry.Editor,
  h5u.DAI.Settings;

type
  TDAIManualRegistrationDialog = class(TForm)
  private
    FInfoMemo: TMemo;
    procedure CopyClicked(Sender: TObject);
  public
    constructor CreateWithInfo(const AInfo: string);
  end;

  TDAIRegistrationCleanupDialog = class(TForm)
  private
    FClient: string;
    FCandidates: TJSONObject;
    FList: TListView;
    FDetails: TMemo;
    FStatus: TLabel;
    FRemove: TButton;
    FRefreshing: Boolean;
    function SelectedCandidate: TJSONObject;
    procedure SelectionChanged(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure SearchClicked(Sender: TObject);
    procedure RemoveClicked(Sender: TObject);
    procedure Reload;
  public
    constructor CreateForClient(const AClient: string);
    destructor Destroy; override;
  end;

constructor TDAIManualRegistrationDialog.CreateWithInfo(const AInfo: string);
var
  LCopyButton, LCloseButton: TButton;
begin
  inherited CreateNew(nil);
  Name := 'DAIManualRegistrationDialog';
  Caption := DAIText('DAI – Manuelle Client-Registrierung', 'DAI – Manual client registration', 'DAI – Inscription manuelle du client', 'DAI – クライアントの手動登録');
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  ClientWidth := 920;
  ClientHeight := 610;
  Constraints.MinWidth := 600;
  Constraints.MinHeight := 360;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  FInfoMemo := TMemo.Create(Self);
  FInfoMemo.Name := 'DAIManualRegistrationMemo';
  FInfoMemo.Parent := Self;
  FInfoMemo.SetBounds(16, 16, ClientWidth - 32, ClientHeight - 74);
  FInfoMemo.Anchors := [akLeft, akTop, akRight, akBottom];
  FInfoMemo.ReadOnly := True;
  FInfoMemo.ScrollBars := ssBoth;
  FInfoMemo.WordWrap := False;
  FInfoMemo.Font.Name := 'Consolas';
  FInfoMemo.Font.Size := 10;
  FInfoMemo.Text := AInfo;
  FInfoMemo.SelStart := 0;
  LCopyButton := TButton.Create(Self);
  LCopyButton.Name := 'DAIManualRegistrationCopyButton';
  LCopyButton.Parent := Self;
  LCopyButton.SetBounds(16, ClientHeight - 44, 200, 28);
  LCopyButton.Anchors := [akLeft, akBottom];
  LCopyButton.Caption := DAIText('Angaben kopieren', 'Copy details', 'Copier les informations', '詳細をコピー');
  LCopyButton.OnClick := CopyClicked;
  LCloseButton := TButton.Create(Self);
  LCloseButton.Parent := Self;
  LCloseButton.SetBounds(ClientWidth - 128, ClientHeight - 44, 112, 28);
  LCloseButton.Anchors := [akRight, akBottom];
  LCloseButton.Caption := DAIText('Schließen', 'Close', 'Fermer', '閉じる');
  LCloseButton.Default := True;
  LCloseButton.Cancel := True;
  LCloseButton.ModalResult := mrClose;
end;

procedure TDAIManualRegistrationDialog.CopyClicked(Sender: TObject);
begin
  Clipboard.AsText := FInfoMemo.Text;
end;

constructor TDAIRegistrationCleanupDialog.CreateForClient(const AClient: string);
var
  LButton: TButton;
begin
  inherited CreateNew(nil);
  Name := 'DAIRegistrationCleanupDialog';
  Caption := DAIText('DAI – Registrierungen suchen und entfernen', 'DAI – Find and remove registrations', 'DAI – Rechercher et supprimer des inscriptions', 'DAI – 登録の検索と削除');
  Position := poScreenCenter;
  ClientWidth := 960;
  ClientHeight := 560;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 440;
  FClient := AClient;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 16, 928, 24);
  FStatus.AutoSize := False;
  FStatus.Anchors := [akLeft, akTop, akRight];
  FList := TListView.Create(Self);
  FList.Name := 'DAIRegistrationsList';
  FList.Parent := Self;
  FList.SetBounds(16, 48, 928, 300);
  FList.Anchors := [akLeft, akTop, akRight, akBottom];
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.Columns.Add.Caption := DAIText('KI-Client', 'AI client', 'Client IA', 'AIクライアント');
  FList.Columns[0].Width := 180;
  FList.Columns.Add.Caption := DAIText('MCP-Server / Starthelfer', 'MCP server / launcher', 'Serveur MCP / lanceur', 'MCPサーバー / ランチャー');
  FList.Columns[1].Width := 310;
  FList.Columns.Add.Caption := DAIText('Bereich', 'Scope', 'Portée', '範囲');
  FList.Columns[2].Width := 160;
  FList.Columns.Add.Caption := DAIText('Status', 'Status', 'État', '状態');
  FList.Columns[3].Width := 240;
  FList.OnSelectItem := SelectionChanged;
  FDetails := TMemo.Create(Self);
  FDetails.Name := 'DAIRegistrationDetails';
  FDetails.Parent := Self;
  FDetails.SetBounds(16, 360, 928, 128);
  FDetails.Anchors := [akLeft, akRight, akBottom];
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssVertical;
  FDetails.WordWrap := True;
  LButton := TButton.Create(Self);
  LButton.Parent := Self;
  LButton.SetBounds(16, 510, 160, 30);
  LButton.Anchors := [akLeft, akBottom];
  LButton.Caption := DAIText('Erneut suchen', 'Search again', 'Relancer la recherche', '再検索');
  LButton.OnClick := SearchClicked;
  FRemove := TButton.Create(Self);
  FRemove.Name := 'DAIRemoveRegistrationButton';
  FRemove.Parent := Self;
  FRemove.SetBounds(188, 510, 230, 30);
  FRemove.Anchors := [akLeft, akBottom];
  FRemove.Caption := DAIText('Ausgewählte entfernen', 'Remove selected', 'Supprimer la sélection', '選択した登録を削除');
  FRemove.Enabled := False;
  FRemove.OnClick := RemoveClicked;
  LButton := TButton.Create(Self);
  LButton.Parent := Self;
  LButton.SetBounds(784, 510, 160, 30);
  LButton.Anchors := [akRight, akBottom];
  LButton.Caption := DAIText('Schließen', 'Close', 'Fermer', '閉じる');
  LButton.Cancel := True;
  LButton.ModalResult := mrClose;
  Reload;
end;

destructor TDAIRegistrationCleanupDialog.Destroy;
begin
  if Assigned(FList) then
    FList.OnSelectItem := nil;
  FCandidates.Free;
  inherited Destroy;
end;

function TDAIRegistrationCleanupDialog.SelectedCandidate: TJSONObject;
var
  LArray: TJSONArray;
  LIndex: NativeInt;
begin
  Result := nil;
  if FRefreshing or not Assigned(FCandidates) or not Assigned(FList.Selected) then
    Exit;
  LArray := FCandidates.GetValue<TJSONArray>('registrations', nil);
  LIndex := NativeInt(FList.Selected.Data) - 1;
  if not Assigned(LArray) then
    Exit;
  if (LIndex < 0) or (LIndex >= LArray.Count) then
    Exit;
  if LArray.Items[LIndex] is TJSONObject then
    Result := TJSONObject(LArray.Items[LIndex]);
end;

procedure TDAIRegistrationCleanupDialog.SelectionChanged(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  LCandidate: TJSONObject;
begin
  if FRefreshing then
    Exit;
  LCandidate := SelectedCandidate;
  FRemove.Enabled := False;
  FDetails.Clear;
  if not Assigned(LCandidate) then
    Exit;
  FRemove.Enabled := LCandidate.GetValue<Boolean>('removable', False);
  FDetails.Lines.Add(DAIText('Konfigurationsdatei: ', 'Configuration file: ', 'Fichier de configuration : ', '設定ファイル: ') + LCandidate.GetValue<string>('path', ''));
  FDetails.Lines.Add(DAIText('MCP-Server: ', 'MCP server: ', 'Serveur MCP : ', 'MCPサーバー: ') + LCandidate.GetValue<string>('server_name', ''));
  FDetails.Lines.Add(DAIText('Starthelfer: ', 'Launcher: ', 'Lanceur : ', 'ランチャー: ') + LCandidate.GetValue<string>('launcher_server', ''));
  if LCandidate.GetValue<string>('registry_root', '') <> '' then
    FDetails.Lines.Add(DAIText('Einstellungsprofil: ', 'Settings profile: ', 'Profil de paramètres : ', '設定プロファイル: ') + LCandidate.GetValue<string>('registry_root'));
  FDetails.Lines.Add(LCandidate.GetValue<string>('message', ''));
end;

procedure TDAIRegistrationCleanupDialog.Reload;
var
  LArray: TJSONArray;
  LCandidate: TJSONObject;
  LItem: TListItem;
  LIndex: Integer;
begin
  FRefreshing := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    FRemove.Enabled := False;
    FDetails.Clear;
    FreeAndNil(FCandidates);
    try
      FCandidates := TDAIClientRegistration.FindRegistrations(FClient);
      LArray := FCandidates.GetValue<TJSONArray>('registrations', nil);
      if Assigned(LArray) then
        for LIndex := 0 to LArray.Count - 1 do
          if LArray.Items[LIndex] is TJSONObject then
          begin
            LCandidate := TJSONObject(LArray.Items[LIndex]);
            LItem := FList.Items.Add;
            LItem.Data := Pointer(NativeInt(LIndex + 1));
            LItem.Caption := LCandidate.GetValue<string>('label', LCandidate.GetValue<string>('client', ''));
            LItem.SubItems.Add(LCandidate.GetValue<string>('server_name', '') + ' / ' + LCandidate.GetValue<string>('launcher_server', ''));
            if LCandidate.GetValue<Boolean>('current_scope', False) then
              LItem.SubItems.Add(DAIText('Aktueller Bereich', 'Current scope', 'Portée actuelle', '現在の範囲'))
            else
              LItem.SubItems.Add(DAIText('Anderer Bereich', 'Other scope', 'Autre portée', '別の範囲'));
            if LCandidate.GetValue<Boolean>('removable', False) then
              LItem.SubItems.Add(DAIText('Entfernbar', 'Removable', 'Suppression possible', '削除可能'))
            else
              LItem.SubItems.Add(DAIText('Prüfen: ', 'Review: ', 'À vérifier : ', '確認: ') + LCandidate.GetValue<string>('message', DAIText('nicht verwaltet',
                'unmanaged', 'non géré', '管理対象外')));
          end;
      FStatus.Caption := Format(DAIText(
        '%d DAI-Registrierungen gefunden. Zum Entfernen einen Eintrag auswählen.',
        '%d DAI registrations found. Select an entry to remove.',
        '%d inscriptions DAI trouvées. Sélectionnez une entrée à supprimer.',
        'DAIの登録が%d件見つかりました。削除する項目を選択してください。'), [FList.Items.Count]);
    except
      FStatus.Caption := DAIText(
        'Die Registrierungen konnten nicht gelesen werden. Konfigurationspfade und Zugriffsrechte prüfen.',
        'Could not read registrations. Check configuration paths and access permissions.',
        'Impossible de lire les inscriptions. Vérifiez les chemins de configuration et les droits d’accès.',
        '登録を読み取れませんでした。設定ファイルのパスとアクセス権を確認してください。');
    end;
  finally
    FList.Items.EndUpdate;
    FRefreshing := False;
  end;
end;

procedure TDAIRegistrationCleanupDialog.SearchClicked(Sender: TObject);
begin
  Reload;
end;

procedure TDAIRegistrationCleanupDialog.RemoveClicked(Sender: TObject);
var
  LCandidate, LResult: TJSONObject;
  LMessage: string;
begin
  LCandidate := SelectedCandidate;
  if not Assigned(LCandidate) then
    Exit;
  if not LCandidate.GetValue<Boolean>('removable', False) then
    Exit;
  FRemove.Enabled := False;
  try
    LResult := TDAIClientRegistration.RemoveFoundRegistration(LCandidate);
    try
      LMessage := LResult.GetValue<string>('message', DAIText('Die Registrierung wurde geprüft.', 'The registration was checked.', 'L’inscription a été vérifiée.', '登録を確認しました。'));
    finally
      LResult.Free;
    end;
    Reload;
    FStatus.Caption := LMessage;
  except
    Reload;
    FStatus.Caption := DAIText(
      'Die Registrierung konnte nicht entfernt werden. Erneut suchen und den aktuellen Zustand prüfen.',
      'Could not remove the registration. Search again and review its current state.',
      'Impossible de supprimer l’inscription. Relancez la recherche et vérifiez son état actuel.',
      '登録を削除できませんでした。再検索して現在の状態を確認してください。');
  end;
end;

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

function NewWrappedLabel(const AParent: TWinControl; const ACaption: string; const ALeft, ATop, AWidth, AHeight: Integer): TLabel;
begin
  Result := NewLabel(AParent, ACaption, ALeft, ATop);
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.SetBounds(ALeft, ATop, AWidth, AHeight);
end;

function PermissionCategoryCaption(const ACategory: TDAIPermissionCategory): string;
begin
  case ACategory of
    pcReferenceRead:
      Result := DAIText('Delphi-/GetIt-Sourcen und IDE-Optionen lesen', 'Read Delphi/GetIt sources and IDE settings',
        'Lire les sources Delphi/GetIt et les paramètres IDE', 'Delphi/GetItソースとIDE設定の読み取り');
    pcIDEOptions:
      Result := DAIText('IDE-Optionen ändern', 'Change IDE settings', 'Modifier les paramètres IDE', 'IDE設定の変更');
    pcProjectRead:
      Result := DAIText('Projekt und Projektdateien lesen', 'Read project and project files',
        'Lire le projet et ses fichiers', 'プロジェクトとプロジェクトファイルの読み取り');
    pcProjectWrite:
      Result := DAIText('Projekt und Projektdateien ändern', 'Change project and project files',
        'Modifier le projet et ses fichiers', 'プロジェクトとプロジェクトファイルの変更');
    pcCompile:
      Result := DAIText('Kompilieren', 'Compile', 'Compiler', 'コンパイル');
    pcExecute:
      Result := DAIText('Projekt ausführen und debuggen', 'Run and debug project',
        'Exécuter et déboguer le projet', 'プロジェクトの実行とデバッグ');
  else
    Result := DAIText('Unbekannte Funktionalität', 'Unknown functionality', 'Fonctionnalité inconnue', '不明な機能');
  end;
end;

constructor TDAIOptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AutoScroll := True;
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
  NewWrappedLabel(AParent, PermissionCategoryCaption(ACategory), 24, ATop + 2, 284, 44);
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
      LComboBox.Items.Add(IfThen(DAIPermissionCategoryIsGlobal(ACategory), DAIText('Nur global', 'Global only', 'Globale uniquement', 'グローバルのみ'), DAIText('Default',
        'Default', 'Par défaut', '既定')))
    else
      LComboBox.Items[4] := DAIText('Für diese IDE-Sitzung', 'For this IDE session', 'Pour cette session IDE', 'このIDEセッション中');
    LComboBox.Tag := Ord(LScope) * (Ord(High(TDAIPermissionCategory)) + 1) + Ord(ACategory);
    LComboBox.ShowHint := True;
    LComboBox.OnChange := PermissionChanged;
    FPermissionComboBoxes[LScope, ACategory] := LComboBox;
  end;
  LButton := TBitBtn.Create(AParent);
  LButton.Parent := AParent;
  LButton.Name := 'DAIPermission' + IntToStr(Ord(ACategory)) + 'DialogButton';
  LButton.Caption := ''; // SetName supplies a caption; keep only the shield glyph.
  LButton.SetBounds(744, ATop - 1, 24, 24);
  LButton.Tag := Ord(ACategory);
  LButton.Hint := PermissionCategoryCaption(ACategory) + DAIText(' – Berechtigung auswählen', ' – Select permission', ' – Choisir une autorisation', ' – 権限を選択');
  LButton.ShowHint := True;
  DrawPermissionGlyph(LButton.Glyph);
  LButton.OnClick := PermissionDialogClicked;
  FPermissionButtons[ACategory] := LButton;
  Inc(ATop, 50);
end;

procedure TDAIOptionsFrame.BuildControls;
var
  LCategory: TDAIPermissionCategory;
  LInfoLabel: TLabel;
  LTop: Integer;
begin
  LTop := 18;
  with NewLabel(Self, DAIText('MCP-Server', 'MCP server', 'Serveur MCP', 'MCPサーバー'), 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 30);

  FServerEnabledCheckBox := TCheckBox.Create(Self);
  FServerEnabledCheckBox.Parent := Self;
  FServerEnabledCheckBox.Left := 24;
  FServerEnabledCheckBox.Top := LTop;
  FServerEnabledCheckBox.Caption := DAIText(
    'MCP-Server beim IDE-Start automatisch starten',
    'Start the MCP server automatically when the IDE starts',
    'Démarrer automatiquement le serveur MCP au lancement de l’IDE',
    'IDEの起動時にMCPサーバーを自動的に開始する');
  FServerEnabledCheckBox.Width := 736;
  FServerEnabledCheckBox.Height := 36;
  FServerEnabledCheckBox.WordWrap := True;
  Inc(LTop, 44);

  FAllowIDEStartStopCheckBox := TCheckBox.Create(Self);
  FAllowIDEStartStopCheckBox.Parent := Self;
  FAllowIDEStartStopCheckBox.Name := 'DAIAllowIDEStartStopCheckBox';
  FAllowIDEStartStopCheckBox.SetBounds(24, LTop, 736, 36);
  FAllowIDEStartStopCheckBox.WordWrap := True;
  FAllowIDEStartStopCheckBox.Caption := DAIText(
    'KI darf die Delphi-IDE starten und beenden',
    'Allow AI to start and close the Delphi IDE',
    'Autoriser l’IA à démarrer et à fermer l’IDE Delphi',
    'AIによるDelphi IDEの起動と終了を許可する');
  FAllowIDEStartStopCheckBox.Checked := True;
  FAllowIDEStartStopCheckBox.Hint := DAIText(
    'Gilt für alle Delphi-Versionen und Profile dieses Windows-Benutzers. Wird beim Speichern oder Registrieren wirksam. dai_start ' +
      'bleibt für Statusabfragen registriert.',
    'Applies to all Delphi versions and profiles for this Windows user. Takes effect when saving or registering. dai_start remains ' +
      'registered for status queries.',
    'S’applique à toutes les versions et à tous les profils Delphi de cet utilisateur Windows. Prend effet lors de l’enregistrement ou ' +
      'de l’inscription. dai_start reste inscrit pour consulter l’état.',
    'このWindowsユーザーのすべてのDelphiバージョンとプロファイルに適用されます。保存時または登録時に反映されます。状態の照会用にdai_startの登録は維持されます。');
  FAllowIDEStartStopCheckBox.ShowHint := True;
  Inc(LTop, 44);

  FUseSharedConnectionSettingsCheckBox := TCheckBox.Create(Self);
  FUseSharedConnectionSettingsCheckBox.Parent := Self;
  FUseSharedConnectionSettingsCheckBox.Name := 'DAIUseSharedConnectionSettingsCheckBox';
  FUseSharedConnectionSettingsCheckBox.SetBounds(24, LTop, 736, 36);
  FUseSharedConnectionSettingsCheckBox.WordWrap := True;
  FUseSharedConnectionSettingsCheckBox.Caption := DAIText(
    'Port und Bearer-Token für alle Delphi-Versionen und Profile gemeinsam verwenden',
    'Share the port and bearer token across all Delphi versions and profiles',
    'Partager le port et le jeton Bearer entre toutes les versions et tous les profils Delphi',
    'すべてのDelphiバージョンとプロファイルでポートとBearerトークンを共有する');
  FUseSharedConnectionSettingsCheckBox.Checked := True;
  FUseSharedConnectionSettingsCheckBox.Hint := DAIText(
    'Standard: gemeinsame Verbindungseinstellungen für diesen Windows-Benutzer. Ohne Häkchen gelten Port und Bearer-Token nur für ' +
      'diese Delphi-Version und dieses IDE-Profil. Andere DAI-Einstellungen bleiben IDE-spezifisch. Umschalten zeigt die vorhandenen ' +
      'Werte; erst Speichern oder Registrieren übernimmt die Auswahl.',
    'Default: shared connection settings for this Windows user. When unchecked, the port and bearer token apply only to this Delphi ' +
      'version and IDE profile. Other DAI settings remain specific to the IDE. Switching previews existing values; saving or registering ' +
      'applies the selection.',
    'Par défaut : paramètres de connexion partagés pour cet utilisateur Windows. Sans cette option, le port et le jeton Bearer ' +
      'concernent uniquement cette version de Delphi et ce profil IDE. Les autres paramètres DAI restent propres à l’IDE. Le changement ' +
      'affiche les valeurs existantes ; l’enregistrement ou l’inscription applique la sélection.',
    '既定では、このWindowsユーザーの接続設定を共有します。オフの場合、ポートとBearerトークンはこのDelphiバージョンとIDEプロファイルにのみ適用されます。他のDAI設定はIDEごとに保持されます。切り替えると既存の値を表示し、保存時または登録' +
      '時に選択を適用します。');
  FUseSharedConnectionSettingsCheckBox.ShowHint := True;
  FUseSharedConnectionSettingsCheckBox.OnClick := ConnectionSettingsScopeClicked;
  Inc(LTop, 44);

  NewLabel(Self, DAIText('Port', 'Port', 'Port', 'ポート'), 24, LTop + 4);
  FPortEdit := TEdit.Create(Self);
  FPortEdit.Parent := Self;
  FPortEdit.Left := 160;
  FPortEdit.Top := LTop;
  FPortEdit.Width := 100;
  FPortEdit.NumbersOnly := True;
  with NewLabel(Self, Format(DAIText('Standard: %d', 'Default: %d', 'Par défaut : %d', '既定: %d'), [CDAIDefaultPort]), FPortEdit.Left + FPortEdit.Width + 12, LTop + 4) do
    Font.Color := clGrayText;
  Inc(LTop, 32);

  NewLabel(Self, DAIText('Bearer-Token', 'Bearer token', 'Jeton Bearer', 'Bearerトークン'), 24, LTop + 4);
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
  FGenerateTokenButton.Caption := DAIText('Token erzeugen', 'Generate token', 'Générer un jeton', 'トークンを生成');
  FGenerateTokenButton.Hint := DAIText(
    'Erzeugt eine neue GUID. Danach „Registrieren“ und den KI-Client neu starten, damit die neue Verbindung verwendet wird.',
    'Generates a new GUID. Then register and restart the AI client to use the new connection.',
    'Génère un nouvel identifiant GUID. Inscrivez ensuite le client IA et redémarrez-le pour utiliser la nouvelle connexion.',
    '新しいGUIDを生成します。その後、登録を行い、AIクライアントを再起動して新しい接続を使用してください。');
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
  FStartServerButton.Caption := DAIText('Server starten', 'Start server', 'Démarrer le serveur', 'サーバーを開始');
  FStartServerButton.Hint := DAIText(
    'Startet mit dem hier eingetragenen Port und Bearer-Token. „Speichern“ oder „Registrieren“ übernimmt die Werte dauerhaft.',
    'Starts using the port and bearer token entered here. Saving or registering stores the values permanently.',
    'Démarre avec le port et le jeton Bearer saisis ici. L’enregistrement ou l’inscription conserve ces valeurs.',
    'ここに入力したポートとBearerトークンで開始します。保存または登録すると値が永続的に保存されます。');
  FStartServerButton.ShowHint := True;
  FStartServerButton.OnClick := StartServerClicked;

  FStopServerButton := TButton.Create(Self);
  FStopServerButton.Parent := Self;
  FStopServerButton.SetBounds(196, LTop, 160, 28);
  FStopServerButton.Caption := DAIText('Server stoppen', 'Stop server', 'Arrêter le serveur', 'サーバーを停止');
  FStopServerButton.Hint := DAIText(
    'Stoppt den Server dieser IDE. Danach kann eine andere IDE ihn manuell starten.',
    'Stops this IDE’s server. Another IDE can then start it manually.',
    'Arrête le serveur de cet IDE. Un autre IDE peut ensuite le démarrer manuellement.',
    'このIDEのサーバーを停止します。その後、別のIDEで手動起動できます。');
  FStopServerButton.ShowHint := True;
  FStopServerButton.OnClick := StopServerClicked;
  Inc(LTop, 36);
  with NewWrappedLabel(Self, DAIText(
    'Starten/Stoppen wirkt sofort. „Speichern“ oder „Registrieren“ übernimmt Port und Token dauerhaft.',
    'Starting or stopping takes effect immediately. Saving or registering stores the port and token permanently.',
    'Le démarrage et l’arrêt sont immédiats. L’enregistrement ou l’inscription conserve le port et le jeton.',
    '開始と停止は即座に反映されます。保存または登録するとポートとトークンが永続的に保存されます。'), 24, LTop, 760, 40) do
    Font.Color := clGrayText;
  Inc(LTop, 48);

  FLoggingCheckBox := TCheckBox.Create(Self);
  FLoggingCheckBox.Parent := Self;
  FLoggingCheckBox.Left := 24;
  FLoggingCheckBox.Top := LTop;
  FLoggingCheckBox.Caption := DAIText(
    'Alle Zugriffspunkte mit IOTAMessageServices.AddTitleMessage protokollieren',
    'Log all access points with IOTAMessageServices.AddTitleMessage',
    'Journaliser tous les points d’accès avec IOTAMessageServices.AddTitleMessage',
    'IOTAMessageServices.AddTitleMessageですべてのアクセスポイントを記録する');
  FLoggingCheckBox.Width := 736;
  FLoggingCheckBox.Height := 36;
  FLoggingCheckBox.WordWrap := True;
  Inc(LTop, 44);

  FUsageLogLink := TLinkLabel.Create(Self);
  FUsageLogLink.Parent := Self;
  FUsageLogLink.Name := 'DAIUsageLogLink';
  FUsageLogLink.SetBounds(24, LTop, 736, 24);
  FUsageLogLink.Caption := DAIText(
    '<a id="usage">Nutzungszähler in der Registry öffnen</a>',
    '<a id="usage">Open usage counters in the registry</a>',
    '<a id="usage">Ouvrir les compteurs d’utilisation dans le Registre</a>',
    '<a id="usage">レジストリで使用回数を表示</a>');
  FUsageLogLink.TabStop := True;
  FUsageLogLink.Hint := DAIText(
    'Lokale Monatszähler für Toolaufrufe aller Delphi-Versionen, einschließlich Status- und Listenabfragen. Es werden keine Inhalte ' +
      'gespeichert oder Daten hochgeladen. Öffnet HKCU\Software\DelphiAI\DAI\UsageLog.',
    'Local monthly tool-call counters for all Delphi versions, including status and list queries. No content is saved and no data is ' +
      'uploaded. Opens HKCU\Software\DelphiAI\DAI\UsageLog.',
    'Compteurs mensuels locaux des appels d’outils de toutes les versions Delphi, y compris les consultations d’état et de listes. ' +
      'Aucun contenu n’est enregistré et aucune donnée n’est envoyée. Ouvre HKCU\Software\DelphiAI\DAI\UsageLog.',
    '状態や一覧の照会を含む、すべてのDelphiバージョンのツール呼び出し回数を月別にローカルで記録します。内容の保存やデータの送信は行いません。HKCU\Software\DelphiAI\DAI\UsageLogを開きます。');
  FUsageLogLink.ShowHint := True;
  FUsageLogLink.OnLinkClick := UsageLogLinkClicked;
  Inc(LTop, 26);
  with NewWrappedLabel(Self, DAIText(
    'Toolaufrufe werden lokal je Monat gezählt, unabhängig vom Zugriffsprotokoll. Keine Inhalte, kein Upload.',
    'Tool calls are counted locally each month, independently of access logging. No content, no upload.',
    'Les appels d’outils sont comptés localement par mois, indépendamment du journal d’accès. Aucun contenu ni envoi.',
    'ツール呼び出し回数はアクセスログとは別に月ごとにローカルで記録されます。内容の保存や送信はありません。'), 24, LTop, 760, 40) do
    Font.Color := clGrayText;
  Inc(LTop, 48);

  with NewLabel(Self, DAIText('Zusätzliche schreibgeschützte Verzeichnisse', 'Additional read-only directories', 'Répertoires supplémentaires en lecture seule',
    '追加の読み取り専用ディレクトリ'), 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 28);

  FDirectoryHintLabel := NewWrappedLabel(Self, '', 24, LTop, 736, 40);
  Inc(LTop, 48);

  FDirectoriesMemo := TMemo.Create(Self);
  FDirectoriesMemo.Parent := Self;
  FDirectoriesMemo.Left := 24;
  FDirectoriesMemo.Top := LTop;
  FDirectoriesMemo.Width := 636;
  FDirectoriesMemo.Height := 100;
  FDirectoriesMemo.ScrollBars := ssVertical;
  FDirectoriesMemo.WordWrap := False;
  Inc(LTop, 108);

  FDirectoriesAlwaysAllowedCheckBox := TCheckBox.Create(Self);
  FDirectoriesAlwaysAllowedCheckBox.Parent := Self;
  FDirectoriesAlwaysAllowedCheckBox.Name := 'DAICustomReadDirectoriesAlwaysAllowedCheckBox';
  FDirectoriesAlwaysAllowedCheckBox.SetBounds(24, LTop, 736, 24);
  FDirectoriesAlwaysAllowedCheckBox.Caption := DAIText('Lesen immer erlaubt', 'Always allow reading', 'Toujours autoriser la lecture', '読み取りを常に許可');
  FDirectoriesAlwaysAllowedCheckBox.Hint := DAIText(
    'Globales Setting für die zusätzlichen Verzeichnisse. Ohne Häkchen gilt die Leseberechtigung des aktuellen Projekts, ohne aktives ' +
      'Projekt die globale Leseberechtigung. Schreibzugriffe bleiben gesperrt.',
    'Global setting for additional directories. When unchecked, the current project’s read permission applies, or the global read ' +
      'permission if no project is active. Write access remains blocked.',
    'Paramètre global des répertoires supplémentaires. Sans cette option, l’autorisation de lecture du projet actuel s’applique, ou ' +
      'l’autorisation globale si aucun projet n’est actif. L’écriture reste interdite.',
    '追加ディレクトリのグローバル設定です。オフの場合、現在のプロジェクトの読み取り権限を使用し、プロジェクトがない場合はグローバルの読み取り権限を使用します。書き込みは禁止されたままです。');
  FDirectoriesAlwaysAllowedCheckBox.ShowHint := True;
  Inc(LTop, 38);

  with NewLabel(Self, DAIText('Berechtigungen', 'Permissions', 'Autorisations', '権限'), 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 30);

  NewLabel(Self, DAIText('Global', 'Global', 'Globales', 'グローバル'), 320, LTop + 4);
  NewLabel(Self, DAIText('Aktuelles Projekt', 'Current project', 'Projet actuel', '現在のプロジェクト'), 548, LTop + 4);
  Inc(LTop, 34);

  FProjectLabel := NewLabel(Self, '', 24, LTop);
  FProjectLabel.Width := 744;
  FProjectLabel.AutoSize := False;
  FProjectLabel.WordWrap := True;
  FProjectLabel.Height := 64;
  Inc(LTop, 72);

  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
    AddPermissionRow(Self, LCategory, LTop);

  LInfoLabel := NewLabel(
    Self,
    DAIText(
      'Globale Änderungen setzen die entsprechende Auswahl des aktuellen Projekts auf „Default“. Delphi-Sourcen, GetIt und ' +
        'IDE-Lesezugriffe sind immer erlaubt.',
      'Global changes reset the corresponding current-project choice to “Default”. Reading Delphi sources, GetIt and IDE settings is ' +
        'always allowed.',
      'Les modifications globales rétablissent le choix correspondant du projet actuel sur « Par défaut ». La lecture des sources ' +
        'Delphi, de GetIt et des paramètres IDE est toujours autorisée.',
      'グローバル設定を変更すると、現在のプロジェクトの対応する選択は「既定」に戻ります。Delphiソース、GetIt、IDE設定の読み取りは常に許可されます。'),
    24,
    LTop
  );
  LInfoLabel.AutoSize := False;
  LInfoLabel.WordWrap := True;
  LInfoLabel.Width := 760;
  LInfoLabel.Height := 60;
  Inc(LTop, 68);

  with NewLabel(Self, DAIText('KI-Client- und Skill-Registrierung', 'AI client and skill registration', 'Inscription des clients IA et du skill', 'AIクライアントとスキルの登録'), 16, LTop) do
    Font.Style := [fsBold];
  Inc(LTop, 30);

  FClientComboBox := TComboBox.Create(Self);
  FClientComboBox.Parent := Self;
  FClientComboBox.Name := 'DAIClientComboBox';
  FClientComboBox.Left := 24;
  FClientComboBox.Top := LTop;
  FClientComboBox.Width := 330;
  FClientComboBox.Style := csDropDownList;
  FClientComboBox.Items.Add(DAIText('Alle erkannten Clients', 'All detected clients', 'Tous les clients détectés', '検出されたすべてのクライアント'));
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
  FRegisterButton.Caption := DAIText('Registrieren', 'Register', 'Inscrire', '登録');
  FRegisterButton.OnClick := RegisterClicked;

  FUnregisterButton := TButton.Create(Self);
  FUnregisterButton.Parent := Self;
  FUnregisterButton.Left := 196;
  FUnregisterButton.Top := LTop;
  FUnregisterButton.Width := 160;
  FUnregisterButton.Caption := DAIText('Deregistrieren', 'Unregister', 'Désinscrire', '登録解除');
  FUnregisterButton.OnClick := UnregisterClicked;

  FShowToolsButton := TButton.Create(Self);
  FShowToolsButton.Parent := Self;
  FShowToolsButton.Name := 'DAIFunctionsButton';
  FShowToolsButton.SetBounds(368, LTop, 280, 28);
  FShowToolsButton.Caption := DAIText('Skill und MCP-Werkzeuge', 'Skill and MCP tools', 'Skill et outils MCP', 'スキルとMCPツール');
  FShowToolsButton.OnClick := ShowToolsClicked;
  Inc(LTop, 36);

  FFindRegistrationsButton := TButton.Create(Self);
  FFindRegistrationsButton.Name := 'DAIFindRegistrationsButton';
  FFindRegistrationsButton.Parent := Self;
  FFindRegistrationsButton.SetBounds(24, LTop, 332, 28);
  FFindRegistrationsButton.Caption := DAIText('Registrierungen suchen und entfernen', 'Find and remove registrations', 'Rechercher et supprimer les inscriptions', '登録の検索と削除');
  FFindRegistrationsButton.Hint := DAIText(
    'Sucht auch DAI-Registrierungen anderer Delphi-Versionen und Profile beim ausgewählten KI-Client.',
    'Also finds DAI registrations for other Delphi versions and profiles in the selected AI client.',
    'Recherche aussi les inscriptions DAI d’autres versions et profils Delphi dans le client IA sélectionné.',
    '選択したAIクライアントで、他のDelphiバージョンとプロファイルのDAI登録も検索します。');
  FFindRegistrationsButton.ShowHint := True;
  FFindRegistrationsButton.OnClick := FindRegistrationsClicked;

  FManualRegistrationButton := TButton.Create(Self);
  FManualRegistrationButton.Name := 'DAIManualRegistrationButton';
  FManualRegistrationButton.Parent := Self;
  FManualRegistrationButton.SetBounds(368, LTop, 280, 28);
  FManualRegistrationButton.Caption := DAIText('Manuell registrieren…', 'Register manually…', 'Inscription manuelle…', '手動で登録…');
  FManualRegistrationButton.Hint := DAIText(
    'Zeigt Verbindungsdaten und Konfigurationsbeispiele für die manuelle Registrierung beim ausgewählten KI-Client.',
    'Shows connection details and configuration examples for manual registration in the selected AI client.',
    'Affiche les données de connexion et des exemples de configuration pour l’inscription manuelle dans le client IA sélectionné.',
    '選択したAIクライアントで手動登録するための接続情報と設定例を表示します。');
  FManualRegistrationButton.ShowHint := True;
  FManualRegistrationButton.OnClick := ManualRegistrationClicked;
  Inc(LTop, 36);

  FManualClientRegistrationCheckBox := TCheckBox.Create(Self);
  FManualClientRegistrationCheckBox.Name := 'DAIManualClientRegistrationCheckBox';
  FManualClientRegistrationCheckBox.Parent := Self;
  FManualClientRegistrationCheckBox.SetBounds(24, LTop, 736, 24);
  FManualClientRegistrationCheckBox.Caption := DAIText('Manuell registriert', 'Manually registered', 'Inscrit manuellement', '手動登録済み');
  FManualClientRegistrationCheckBox.Hint := DAIText(
    'Für die ausgewählte Verbindung: Der DAI-Button ignoriert „Nicht registriert“. Hinweise auf veraltete oder fehlerhafte automatisch ' +
      'erkannte Registrierungen bleiben sichtbar. Wird beim Speichern oder Registrieren übernommen.',
    'For the selected connection, the DAI button ignores “Not registered”. Warnings about outdated or faulty automatically detected ' +
      'registrations remain visible. Applied when saving or registering.',
    'Pour la connexion sélectionnée, le bouton DAI ignore « Non inscrit ». Les avertissements concernant les inscriptions détectées ' +
      'automatiquement qui sont obsolètes ou incorrectes restent visibles. Prend effet lors de l’enregistrement ou de l’inscription.',
    '選択した接続では、DAIボタンは「未登録」を無視します。自動検出された登録が古い場合や不正な場合の警告は引き続き表示されます。保存時または登録時に反映されます。');
  FManualClientRegistrationCheckBox.ShowHint := True;
  Inc(LTop, 42);

  LInfoLabel := NewLabel(
    Self,
    DAIText(
      'Betroffene KI-Clients müssen ihre MCP-Verbindung neu laden oder neu gestartet werden. Hinweis: Nach dem Ändern von Port oder ' +
        'Bearer-Token sowie nach dem Registrieren oder Deregistrieren muss die Codex-App neu gestartet werden.',
      'Affected AI clients must reload their MCP connection or restart. Note: restart the Codex app after changing the port or bearer ' +
        'token, or after registering or unregistering.',
      'Les clients IA concernés doivent recharger leur connexion MCP ou redémarrer. Remarque : redémarrez l’application Codex après ' +
        'toute modification du port ou du jeton Bearer, ou après une inscription ou une désinscription.',
      '対象のAIクライアントでMCP接続を再読み込みするか、クライアントを再起動してください。ポートやBearerトークンの変更、登録、登録解除の後は、Codexアプリを再起動してください。'),
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

  Align := alClient;
  Height := LTop;
end;

procedure TDAIOptionsFrame.ManualRegistrationClicked(Sender: TObject);
var
  LDialog: TDAIManualRegistrationDialog;
  LInfo: string;
begin
  if not ValidateContents then
    Exit;
  LInfo := TDAIClientRegistration.ManualRegistrationInfo(SelectedClient, StrToInt(Trim(FPortEdit.Text)),
    Trim(FTokenEdit.Text), FUseSharedConnectionSettingsCheckBox.Checked);
  LDialog := TDAIManualRegistrationDialog.CreateWithInfo(LInfo);
  try
    LDialog.ShowModal;
  finally
    LDialog.Free;
  end;
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
      LDialog.Caption := DAIText('DAI – Skill und MCP-Werkzeuge', 'DAI – Skill and MCP tools', 'DAI – Skill et outils MCP', 'DAI – スキルとMCPツール');
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
      LMemo.Lines.Add(DAIText('Skill: ', 'Skill: ', 'Skill : ', 'スキル: ') + CDAISkillDirectoryName);
      LMemo.Lines.Add(DAIText('MCP-Werkzeuge: ', 'MCP tools: ', 'Outils MCP : ', 'MCPツール: ') + IntToStr(LTools.Count));
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
      LOKButton.Caption := DAIText('OK', 'OK', 'OK', 'OK');
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
  TDAIIDEToolbar.CheckRegistrations;
end;

procedure TDAIOptionsFrame.StopServerClicked(Sender: TObject);
begin
  if not TDAIRuntime.StopServer then
    TaskMessageDlg('DAI', TDAIRuntime.LastServerError, mtWarning, [mbOK], 0);
  RefreshServerStatus;
  TDAIIDEToolbar.CheckRegistrations;
end;

procedure TDAIOptionsFrame.GenerateTokenClicked(Sender: TObject);
begin
  FTokenEdit.Text := TDAISettings.Instance.GenerateToken;
  FTokenEdit.SetFocus;
  FTokenEdit.SelectAll;
end;

procedure TDAIOptionsFrame.UsageLogLinkClicked(Sender: TObject; const Link: string; LinkType: TSysLinkType);
var
  LError: string;
begin
  if not DAIOpenUsageLogInRegistryEditor(Handle, LError) then
    if LError <> '' then
      TaskMessageDlg('DAI', LError, mtError, [mbOK], 0);
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
  TDAISettings.Instance.RefreshConnectionSettings;
  FServerEnabledCheckBox.Checked := TDAISettings.Instance.Enabled;
  FLoadedAllowIDEStartStop := TDAISettings.Instance.AllowIDEStartStop;
  FAllowIDEStartStopCheckBox.Checked := FLoadedAllowIDEStartStop;
  FLoggingCheckBox.Checked := TDAISettings.Instance.LogAccessPoints;
  LoadConnectionSettings;
  FDirectoriesMemo.Lines.Assign(TDAISettings.Instance.CustomReadDirectories);
  FDirectoriesAlwaysAllowedCheckBox.Checked := TDAISettings.Instance.CustomReadDirectoriesAlwaysAllowed;
  FDirectoriesMemo.TextHint := TDAISettings.Instance.LocalizedProjectsDirectoryHint;
  FDirectoryHintLabel.Caption := DAIText('Vorschlag für diese IDE-Sprache: ', 'Suggestion for this IDE language: ', 'Suggestion pour la langue de cet IDE : ',
    'このIDE言語の候補: ') + TDAISettings.Instance.LocalizedProjectsDirectoryHint;
  RefreshServerStatus;
  LoadPermissionSettings;
  RefreshRegistrationStatus;
  TDAIIDEToolbar.CheckRegistrations;
end;

procedure TDAIOptionsFrame.LoadConnectionSettings;
begin
  FLoadingConnectionSettings := True;
  try
    FConnectionDraftAvailable[False] := False;
    FConnectionDraftAvailable[True] := False;
    FDisplayedSharedConnectionSettings := TDAISettings.Instance.UseSharedConnectionSettings;
    FUseSharedConnectionSettingsCheckBox.Checked := FDisplayedSharedConnectionSettings;
    FPortEdit.Text := IntToStr(TDAISettings.Instance.Port);
    FTokenEdit.Text := TDAISettings.Instance.Token;
    FConnectionPortDraft[FDisplayedSharedConnectionSettings] := FPortEdit.Text;
    FConnectionTokenDraft[FDisplayedSharedConnectionSettings] := FTokenEdit.Text;
    FConnectionDraftAvailable[FDisplayedSharedConnectionSettings] := True;
    FManualRegistrationLoaded[FDisplayedSharedConnectionSettings] :=
      TDAISettings.Instance.ReadManualClientRegistration(FDisplayedSharedConnectionSettings);
    FManualRegistrationDraft[FDisplayedSharedConnectionSettings] := FManualRegistrationLoaded[FDisplayedSharedConnectionSettings];
    FManualClientRegistrationCheckBox.Checked := FManualRegistrationDraft[FDisplayedSharedConnectionSettings];
  finally
    FLoadingConnectionSettings := False;
  end;
end;

procedure TDAIOptionsFrame.ConnectionSettingsScopeClicked(Sender: TObject);
var
  LShared: Boolean;
  LPort: Integer;
  LToken: string;
begin
  if FLoadingConnectionSettings then
    Exit;
  LShared := FUseSharedConnectionSettingsCheckBox.Checked;
  if LShared = FDisplayedSharedConnectionSettings then
    Exit;
  FConnectionPortDraft[FDisplayedSharedConnectionSettings] := FPortEdit.Text;
  FConnectionTokenDraft[FDisplayedSharedConnectionSettings] := FTokenEdit.Text;
  FManualRegistrationDraft[FDisplayedSharedConnectionSettings] := FManualClientRegistrationCheckBox.Checked;
  FConnectionDraftAvailable[FDisplayedSharedConnectionSettings] := True;
  try
    if not FConnectionDraftAvailable[LShared] then
    begin
      if TDAISettings.Instance.ReadConnectionSettings(LShared, LPort, LToken) then
      begin
        FConnectionPortDraft[LShared] := IntToStr(LPort);
        FConnectionTokenDraft[LShared] := LToken;
      end
      else
      begin
        FConnectionPortDraft[LShared] := FPortEdit.Text;
        FConnectionTokenDraft[LShared] := FTokenEdit.Text;
      end;
      FManualRegistrationLoaded[LShared] := TDAISettings.Instance.ReadManualClientRegistration(LShared);
      FManualRegistrationDraft[LShared] := FManualRegistrationLoaded[LShared];
      FConnectionDraftAvailable[LShared] := True;
    end;
    FPortEdit.Text := FConnectionPortDraft[LShared];
    FTokenEdit.Text := FConnectionTokenDraft[LShared];
    FManualClientRegistrationCheckBox.Checked := FManualRegistrationDraft[LShared];
    FDisplayedSharedConnectionSettings := LShared;
  except
    // Keep the scope and its displayed credentials together after a failed preview.
    FLoadingConnectionSettings := True;
    try
      FUseSharedConnectionSettingsCheckBox.Checked := FDisplayedSharedConnectionSettings;
      FPortEdit.Text := FConnectionPortDraft[FDisplayedSharedConnectionSettings];
      FTokenEdit.Text := FConnectionTokenDraft[FDisplayedSharedConnectionSettings];
      FManualClientRegistrationCheckBox.Checked := FManualRegistrationDraft[FDisplayedSharedConnectionSettings];
    finally
      FLoadingConnectionSettings := False;
    end;
    raise;
  end;
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
        if (LScope = psGlobal) and (LCategory = pcReferenceRead) then
          SetPermissionComboLevel(FPermissionComboBoxes[LScope, LCategory], plAlways)
        else if (LScope = psProject) and ((FPermissionProjectKey = '') or DAIPermissionCategoryIsGlobal(LCategory)) then
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
    FPermissionComboBoxes[psGlobal, LCategory].Enabled := LCategory <> pcReferenceRead;
    FPermissionComboBoxes[psProject, LCategory].Enabled := LAvailable and not DAIPermissionCategoryIsGlobal(LCategory);
    FPermissionButtons[LCategory].Enabled := LCategory <> pcReferenceRead;
    FPermissionButtons[LCategory].Hint := PermissionCategoryCaption(LCategory) + ' – ' +
      IfThen(LAvailable and not DAIPermissionCategoryIsGlobal(LCategory),
        DAIText(
          'Berechtigung für das angezeigte Projekt oder global auswählen',
          'Select a permission for the displayed project or globally',
          'Choisir une autorisation pour le projet affiché ou globalement',
          '表示中のプロジェクトまたはグローバルの権限を選択'), DAIText('globale Berechtigung auswählen', 'Select a global permission', 'Choisir une autorisation globale', 'グローバル権限を選択'));
    if LCategory = pcReferenceRead then
      FPermissionComboBoxes[psGlobal, LCategory].Hint := DAIText(
        'Delphi-Sourcen, GetIt-Projekte und IDE-Optionen dürfen immer gelesen werden.',
        'Reading Delphi sources, GetIt projects and IDE settings is always allowed.',
        'La lecture des sources Delphi, des projets GetIt et des paramètres IDE est toujours autorisée.',
        'Delphiソース、GetItプロジェクト、IDE設定の読み取りは常に許可されます。');
  end;
  if LAvailable then
    FProjectLabel.Caption := DAIText('Aktuelles Projekt: ', 'Current project: ', 'Projet actuel : ', '現在のプロジェクト: ') + FPermissionProjectKey + sLineBreak +
      DAIText('Projektdatei: ', 'Project file: ', 'Fichier du projet : ', 'プロジェクトファイル: ') + ChangeFileExt(FPermissionProjectKey, '.dai.permissions.json')
  else if TDAIOTA.ActiveProjectFileName = '' then
    FProjectLabel.Caption := DAIText(
      'Kein aktives Projekt. Projektberechtigungen sind deaktiviert.',
      'No active project. Project permissions are disabled.',
      'Aucun projet actif. Les autorisations du projet sont désactivées.',
      'アクティブなプロジェクトがありません。プロジェクトの権限は無効です。')
  else
    FProjectLabel.Caption := DAIText(
      'Das aktive Projekt hat gewechselt. Die Optionen für das neue Projekt erneut öffnen.',
      'The active project has changed. Reopen the options for the new project.',
      'Le projet actif a changé. Rouvrez les options du nouveau projet.',
      'アクティブなプロジェクトが変わりました。新しいプロジェクトのオプションを開き直してください。');
end;

procedure TDAIOptionsFrame.RefreshInheritedPermissionHints;
var
  LCategory: TDAIPermissionCategory;
  LComboBox: TComboBox;
begin
  for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
  begin
    LComboBox := FPermissionComboBoxes[psProject, LCategory];
    if DAIPermissionCategoryIsGlobal(LCategory) then
      LComboBox.Hint := DAIText(
        'Diese Berechtigung gilt ausschließlich global.',
        'This permission applies globally only.',
        'Cette autorisation s’applique uniquement globalement.',
        'この権限はグローバルにのみ適用されます。')
    else if not LComboBox.Enabled then
      LComboBox.Hint := DAIText('Kein passendes aktives Projekt.', 'No matching active project.', 'Aucun projet actif correspondant.', '一致するアクティブなプロジェクトがありません。')
    else if LComboBox.ItemIndex = 6 then
      LComboBox.Hint := DAIText('Default: globalen Standard verwenden (', 'Default: use the global setting (', 'Par défaut : utiliser le paramètre global (',
        '既定: グローバル設定を使用（') + FPermissionComboBoxes[psGlobal, LCategory].Text + DAIText('). ', '). ', '). ', '）。') +
        DAIText(
          'Beim Speichern wird eine eigene Projektvorgabe entfernt.',
          'Saving removes the project-specific override.',
          'L’enregistrement supprime la valeur propre au projet.',
          '保存時にプロジェクト固有の設定を削除します。')
    else
      LComboBox.Hint := DAIText(
        'Eigene Projektberechtigung. Mit „Default“ wieder den globalen Standard verwenden.',
        'Project-specific permission. Choose “Default” to use the global setting again.',
        'Autorisation propre au projet. Choisissez « Par défaut » pour utiliser à nouveau le paramètre global.',
        'プロジェクト固有の権限です。「既定」を選択するとグローバル設定に戻ります。');
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
  AComboBox.Perform(CB_SETDROPPEDWIDTH, 330, 0);
  AComboBox.Items.BeginUpdate;
  try
    AComboBox.Items.Clear;
    AComboBox.Items.Add(DAIText('Nachfragen', 'Ask', 'Demander', '確認する'));
    AComboBox.Items.Add(DAIText('Nie erlauben', 'Never allow', 'Ne jamais autoriser', '常に拒否'));
    AComboBox.Items.Add(DAIText('Verweigern – nächste Anfrage', 'Deny next request', 'Refuser la prochaine demande', '次の要求を拒否'));
    AComboBox.Items.Add(DAIText('Nur einmal – nächste Anfrage', 'Allow next request once', 'Autoriser la prochaine demande une fois', '次の要求を一度だけ許可'));
    AComboBox.Items.Add(DAIText('Für diese Projektsession', 'For this project session', 'Pour cette session du projet', 'このプロジェクトセッション中'));
    AComboBox.Items.Add(DAIText('Immer erlauben', 'Always allow', 'Toujours autoriser', '常に許可'));
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
    FServerStatusLabel.Caption := Format(DAIText('Status: aktiv auf http://%s:%d%s', 'Status: active at http://%s:%d%s', 'État : actif sur http://%s:%d%s',
      '状態: 稼働中 http://%s:%d%s'), [CDAIDefaultBindAddress, TDAIRuntime.ServerPort, CDAIMcpPath])
  else
  begin
    LError := Trim(TDAIRuntime.LastServerError);
    if LError = '' then
    begin
      if TDAISettings.Instance.Enabled then
        FServerStatusLabel.Caption := DAIText(
          'Status: gestoppt; bereit zum Starten in dieser IDE.',
          'Status: stopped; ready to start in this IDE.',
          'État : arrêté ; prêt à démarrer dans cet IDE.',
          '状態: 停止中。このIDEで開始できます。')
      else
        FServerStatusLabel.Caption := DAIText(
          'Status: gestoppt; automatischer Start deaktiviert.',
          'Status: stopped; automatic startup disabled.',
          'État : arrêté ; démarrage automatique désactivé.',
          '状態: 停止中。自動起動は無効です。');
    end
    else
      FServerStatusLabel.Caption := DAIText('Status: nicht aktiv. ', 'Status: inactive. ', 'État : inactif. ', '状態: 稼働していません。') + LError;
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
        IfThen(LStatus.GetValue<Boolean>('codex_entry_registered'), DAIText('registriert', 'registered', 'inscrit', '登録済み'), DAIText('nicht registriert',
          'not registered', 'non inscrit', '未登録'));
      FSkillStatusLabel.Caption := DAIText('Skill: ', 'Skill: ', 'Skill : ', 'スキル: ') + LStatus.GetValue<string>('skill_file') + ' – ' +
        IfThen(LStatus.GetValue<Boolean>('skill_registered'), DAIText('registriert', 'registered', 'inscrit', '登録済み'), DAIText('nicht registriert', 'not registered',
          'non inscrit', '未登録'));
    except
      on E: Exception do
      begin
        FCodexStatusLabel.Caption := DAIText(
          'Codex-Status nicht lesbar; Details in der Ergebnisliste.',
          'Cannot read Codex status; see the result list for details.',
          'Impossible de lire l’état de Codex ; consultez la liste des résultats.',
          'Codexの状態を読み取れません。結果一覧で詳細を確認してください。');
        FSkillStatusLabel.Caption := DAIText('Skill-Status konnte nicht geprüft werden.', 'Could not check skill status.', 'Impossible de vérifier l’état du skill.',
          'スキルの状態を確認できませんでした。');
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
      if LText = 'registered' then LText := DAIText('registriert', 'registered', 'inscrit', '登録済み')
      else if LText = 'unregistered' then LText := DAIText('deregistriert', 'unregistered', 'désinscrit', '登録解除済み')
      else if LText = 'not_registered' then LText := DAIText('nicht registriert', 'not registered', 'non inscrit', '未登録')
      else if LText = 'needs_update' then LText := DAIText('Registrierung muss aktualisiert werden', 'registration needs updating', 'inscription à mettre à jour', '登録の更新が必要')
      else if LText = 'not_detected' then LText := DAIText('nicht erkannt', 'not detected', 'non détecté', '未検出')
      else if LText = 'unsupported' then LText := DAIText('manuelle Einrichtung erforderlich', 'manual setup required', 'configuration manuelle requise', '手動設定が必要')
      else if LText = 'manual_configuration' then LText := DAIText('manuelle Einrichtung erforderlich', 'manual setup required', 'configuration manuelle requise', '手動設定が必要')
      else if LText = 'configured' then LText := DAIText('registriert', 'registered', 'inscrit', '登録済み')
      else if LText = 'configured_pending' then LText := DAIText('registriert; Verwaltungsabschluss offen', 'registered; management finalization pending',
        'inscrit ; finalisation de la gestion en attente', '登録済み。管理処理の完了待ち')
      else if LText = 'removed' then LText := DAIText('deregistriert', 'unregistered', 'désinscrit', '登録解除済み')
      else if LText = 'unchanged' then LText := DAIText('unverändert', 'unchanged', 'inchangé', '変更なし')
      else if LText = 'conflict' then LText := DAIText('Konflikt', 'conflict', 'conflit', '競合')
      else if LText = 'missing_bridge' then LText := DAIText('Delphi-Brücke fehlt', 'Delphi bridge missing', 'passerelle Delphi absente', 'Delphiブリッジがありません')
      else if LText = 'error' then LText := DAIText('Fehler', 'error', 'erreur', 'エラー');
      FClientStatusMemo.Lines.Add(LObject.GetValue<string>('label', ''));
      AddIndentedLines(FClientStatusMemo.Lines, DAIText('Status: ', 'Status: ', 'État : ', '状態: ') + LText);
      LText := LObject.GetValue<string>('server_name', '');
      if LText <> '' then AddIndentedLines(FClientStatusMemo.Lines, DAIText('MCP-Server: ', 'MCP server: ', 'Serveur MCP : ', 'MCPサーバー: ') + LText);
      LText := LObject.GetValue<string>('launcher_server', '');
      if LText <> '' then AddIndentedLines(FClientStatusMemo.Lines, DAIText('Starthelfer: ', 'Launcher: ', 'Lanceur : ', 'ランチャー: ') + LText);
      LText := LObject.GetValue<string>('path', '');
      AddIndentedLines(FClientStatusMemo.Lines, LText);
      LText := LObject.GetValue<string>('message', '');
      AddIndentedLines(FClientStatusMemo.Lines, LText);
      LText := LObject.GetValue<string>('backup', '');
      if LText <> '' then AddIndentedLines(FClientStatusMemo.Lines, DAIText('Sicherung: ', 'Backup: ', 'Sauvegarde : ', 'バックアップ: ') + LText);
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
    StoreSettings(False);
    try
      LResult := TDAIClientRegistration.RegisterFiles(SelectedClient);
      try
        RefreshRegistrationStatus;
        DisplayClientStatus(LResult);
      finally
        LResult.Free;
      end;
    finally
      TDAIIDEToolbar.CheckRegistrations;
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
  if LScope = psGlobal then
    ResetProjectPermissionDraft(LCategory);
  RefreshInheritedPermissionHints;
end;

procedure TDAIOptionsFrame.ResetProjectPermissionDraft(const ACategory: TDAIPermissionCategory);
begin
  if (FPermissionProjectKey = '') or DAIPermissionCategoryIsGlobal(ACategory) then
    Exit;
  FPermissionComboBoxes[psProject, ACategory].ItemIndex := 6;
  FPermissionModified[psProject, ACategory] := True;
end;

procedure TDAIOptionsFrame.PermissionDialogClicked(Sender: TObject);
var
  LButton: TBitBtn;
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
  LCurrentLevel: TDAIPermissionLevel;
  LDecision: TDAIPermissionPromptResult;
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
  if LDecision.ApplyGlobally or DAIPermissionCategoryIsGlobal(LCategory) then
    LScope := psGlobal;
  SetPermissionComboLevel(FPermissionComboBoxes[LScope, LCategory], LDecision.Level);
  FPermissionModified[LScope, LCategory] := True;
  if LScope = psGlobal then
    ResetProjectPermissionDraft(LCategory);
  RefreshInheritedPermissionHints;
end;

procedure TDAIOptionsFrame.StoreToSettings;
begin
  StoreSettings(True);
end;

procedure TDAIOptionsFrame.StoreSettings(const ARefreshRegistrationHealth: Boolean);
var
  LCategory: TDAIPermissionCategory;
  LContext: TDAIRequestContext;
  LScope: TDAIPermissionScope;
  LPort: Integer;
  LToken: string;
  LError: string;
begin
  UpdateProjectPermissionState;
  if (FPermissionProjectKey <> '') and not SameText(FPermissionProjectKey, TDAIOTA.ActiveProjectFileName) then
    for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
      if FPermissionModified[psProject, LCategory] then
        raise EInvalidOperation.Create(DAIText(
          'Das aktive Projekt hat gewechselt. Projektberechtigungen wurden nicht gespeichert; die Optionen erneut öffnen.',
          'The active project has changed. Project permissions were not saved; reopen the options.',
          'Le projet actif a changé. Les autorisations du projet n’ont pas été enregistrées ; rouvrez les options.',
          'アクティブなプロジェクトが変わりました。プロジェクトの権限は保存されていません。オプションを開き直してください。'));
  LPort := StrToIntDef(Trim(FPortEdit.Text), 0);
  LToken := Trim(FTokenEdit.Text);
  if not TDAIRuntime.ValidateServerConfiguration(LPort, LToken, LError) then
    raise EArgumentException.Create(LError);
  TDAISettings.Instance.Enabled := FServerEnabledCheckBox.Checked;
  TDAISettings.Instance.LogAccessPoints := FLoggingCheckBox.Checked;
  TDAISettings.Instance.UseSharedConnectionSettings := FUseSharedConnectionSettingsCheckBox.Checked;
  TDAISettings.Instance.Port := LPort;
  TDAISettings.Instance.Token := LToken;
  TDAISettings.Instance.CustomReadDirectories.Assign(FDirectoriesMemo.Lines);
  TDAISettings.Instance.CustomReadDirectoriesAlwaysAllowed := FDirectoriesAlwaysAllowedCheckBox.Checked;
  if FAllowIDEStartStopCheckBox.Checked <> FLoadedAllowIDEStartStop then
    TDAISettings.Instance.AllowIDEStartStop := FAllowIDEStartStopCheckBox.Checked;
  if FManualClientRegistrationCheckBox.Checked <> FManualRegistrationLoaded[FUseSharedConnectionSettingsCheckBox.Checked] then
    TDAISettings.Instance.ManualClientRegistration := FManualClientRegistrationCheckBox.Checked;
  try
    TDAISettings.Instance.Save;
  except
    TDAISettings.Instance.DiscardLifecycleChange;
    TDAISettings.Instance.DiscardManualRegistrationChange;
    raise;
  end;
  FLoadedAllowIDEStartStop := TDAISettings.Instance.AllowIDEStartStop;
  FAllowIDEStartStopCheckBox.Checked := FLoadedAllowIDEStartStop;
  LoadConnectionSettings;

  for LScope := Low(TDAIPermissionScope) to High(TDAIPermissionScope) do
  begin
    if (LScope = psProject) and (FPermissionProjectKey = '') then
      Continue;
    LContext := PermissionContext(LScope);
    for LCategory := Low(TDAIPermissionCategory) to High(TDAIPermissionCategory) do
      if FPermissionModified[LScope, LCategory] and (LCategory <> pcReferenceRead) and
        ((LScope = psGlobal) or not DAIPermissionCategoryIsGlobal(LCategory)) then
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
  if ARefreshRegistrationHealth then
    TDAIIDEToolbar.CheckRegistrations;
end;

procedure TDAIOptionsFrame.UnregisterClicked(Sender: TObject);
var
  LResult: TJSONObject;
begin
  try
    try
      LResult := TDAIClientRegistration.UnregisterFiles(SelectedClient);
      try
        RefreshRegistrationStatus;
        DisplayClientStatus(LResult);
      finally
        LResult.Free;
      end;
    finally
      TDAIIDEToolbar.CheckRegistrations;
    end;
  except
    on E: Exception do
      TaskMessageDlg('DAI', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TDAIOptionsFrame.FindRegistrationsClicked(Sender: TObject);
var
  LDialog: TDAIRegistrationCleanupDialog;
begin
  LDialog := TDAIRegistrationCleanupDialog.CreateForClient(SelectedClient);
  try
    LDialog.ShowModal;
  finally
    LDialog.Free;
    TDAIIDEToolbar.CheckRegistrations;
  end;
  RefreshRegistrationStatus;
end;

end.
