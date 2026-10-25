unit h5u.DAI.Symbols.Dialog;

interface

type
  TDAISymbolIndexDialog = class sealed
  public
    class procedure Show(const AScope: string = ''); static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.JSON,
  System.SysUtils,
  System.Types,
  Winapi.Windows,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.StdCtrls,
  h5u.DAI.Localization,
  h5u.DAI.Symbols.Service;

type
  TDAIWrappedLabel = class(TLabel)
  private
    FAdjustingHeight: Boolean;
  protected
    procedure AdjustBounds; override;
    procedure Resize; override;
  end;

  TDAISymbolErrorForm = class(TForm)
  private
    FMemo: TMemo;
    procedure CloseClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure FormClosed(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Display(const ATitle, AText: string);
  end;

  TDAISymbolIndexForm = class(TForm)
  private
    FList: TListView;
    FRows: TJSONArray;
    FInformation: TLabel;
    FProvider: TLabel;
    FStatus: TLabel;
    FUpdate: TButton;
    FDelete: TButton;
    FRefresh: TButton;
    FDetails: TButton;
    FDetailsForm: TDAISymbolErrorForm;
    FRefreshingList: Boolean;
    FDefaultStatus: string;
    FTimer: TTimer;
    FRequestId: string;
    FBusy: Boolean;
    procedure RefreshList(const AScope: string = '');
    procedure RefreshProviders;
    procedure UpdateButtons;
    procedure BeginBuild(const AScope, AIdentity: string);
    procedure SelectionChanged(Sender: TObject; Item: TListItem; Change: TItemChange);
    procedure UpdateClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure DetailsClick(Sender: TObject);
    procedure UpdateSelectionStatus;
    procedure TimerTick(Sender: TObject);
    procedure FormClosed(Sender: TObject; var Action: TCloseAction);
    procedure CloseClick(Sender: TObject);
    function SelectedRow: TJSONObject;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ShowScope(const AScope: string);
  end;

var
  GIndexForm: TDAISymbolIndexForm;

procedure TDAIWrappedLabel.AdjustBounds;
var
  LBounds: TRect;
  LDC: HDC;
begin
  if FAdjustingHeight or not AutoSize or (Width <= 0) or (csReading in ComponentState) then
    Exit;
  FAdjustingHeight := True;
  try
    LBounds := Rect(0, 0, Width, 0);
    LDC := GetDC(0);
    try
      Canvas.Handle := LDC;
      DoDrawText(LBounds, DT_CALCRECT or DT_EXPANDTABS or DT_WORDBREAK);
    finally
      Canvas.Handle := 0;
      ReleaseDC(0, LDC);
    end;
    // Keep the aligned width fixed; only the text height may change.
    SetBounds(Left, Top, Width, LBounds.Height);
  finally
    FAdjustingHeight := False;
  end;
end;

procedure TDAIWrappedLabel.Resize;
begin
  inherited;
  AdjustBounds;
end;

procedure RequireMainThread;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create(DAIText('Die DAI-Indexverwaltung muss auf dem IDE-Hauptthread geöffnet werden.',
      'The DAI index manager must be opened on the IDE main thread.',
      'Le gestionnaire d’index DAI doit être ouvert sur le thread principal de l’IDE.',
      'DAI インデックス管理は IDE のメインスレッドで開く必要があります。'));
end;

function JSONText(const AObject: TJSONObject; const AName: string; const ADefault: string = ''): string;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObject) then
    Exit;
  LValue := AObject.GetValue(AName);
  if Assigned(LValue) and not (LValue is TJSONNull) then
    Result := LValue.Value;
end;

function JSONFlag(const AObject: TJSONObject; const AName: string): Boolean;
begin
  Result := SameText(JSONText(AObject, AName), 'true');
end;

function IndexErrorCount(const AObject: TJSONObject): Int64;
begin
  if not TryStrToInt64(JSONText(AObject, 'error_count', '0'), Result) or (Result < 0) then
    Result := 0;
end;

function CountCaption(const ACount: Int64): string;
var
  LPosition: Integer;
begin
  // Keep Int64 counts exact on Win64, where Extended has Double precision.
  Result := IntToStr(ACount);
  if FormatSettings.ThousandSeparator = #0 then
    Exit;
  LPosition := Length(Result) - 2;
  while LPosition > 1 + Ord(ACount < 0) do
  begin
    Insert(FormatSettings.ThousandSeparator, Result, LPosition);
    Dec(LPosition, 3);
  end;
end;

function JSONCountCaption(const AObject: TJSONObject; const AName: string): string;
var
  LCount: Int64;
begin
  if not TryStrToInt64(JSONText(AObject, AName, '0'), LCount) then
    LCount := 0;
  Result := CountCaption(LCount);
end;

function IndexSizeCaption(const AObject: TJSONObject): string;
var
  LBytes: Int64;
begin
  if not TryStrToInt64(JSONText(AObject, 'size_bytes'), LBytes) or (LBytes < 0) then
    Exit('—');
  if LBytes >= 1024 * 1024 then
    Result := FormatFloat('#,##0.0', LBytes / (1024 * 1024)) + ' MB'
  else
    Result := FormatFloat('#,##0.0', LBytes / 1024) + ' KB';
end;

function PartialIndexMessage(const AObject: TJSONObject): string;
begin
  Result := Format(DAIText('Teilweise aktualisiert: %s Dateien nicht indiziert — Fehlerdetails …',
    'Partially updated: %s files not indexed — Error details …',
    'Mise à jour partielle : %s fichiers non indexés — Détails des erreurs …',
    '一部を更新しました: %s ファイルが未登録 — エラーの詳細 …'), [CountCaption(IndexErrorCount(AObject))]);
end;

function IndexDetailsAvailable(const AObject: TJSONObject): Boolean;
begin
  Result := JSONFlag(AObject, 'details_available') or (IndexErrorCount(AObject) > 0) or (Trim(JSONText(AObject, 'error')) <> '');
end;

function ErrorSummary(const AError: string): string;
begin
  Result := Trim(StringReplace(StringReplace(AError, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > 240 then
    Result := Copy(Result, 1, 240) + ' …';
end;

function IndexReportUpdating(const AObject: TJSONObject): Boolean;
var
  LState: string;
begin
  LState := JSONText(AObject, 'state');
  Result := (LState = 'building') or (LState = 'queued') or (LState = 'running');
end;

function ScopeCaption(const AScope: string): string;
begin
  if AScope = 'delphi' then
    Result := 'Delphi / ToolsAPI'
  else if AScope = 'getit' then
    Result := 'GetIt'
  else if AScope = 'group' then
    Result := DAIText('Projektgruppe', 'Project group', 'Groupe de projets', 'プロジェクトグループ')
  else if AScope = 'project' then
    Result := DAIText('Projekt', 'Project', 'Projet', 'プロジェクト')
  else
    Result := AScope;
end;

function IndexNameCaption(const AObject: TJSONObject): string;
begin
  Result := JSONText(AObject, 'name', ScopeCaption(JSONText(AObject, 'scope')));
  // Only service-authored defaults are labels; project/file names retain their identity.
  if Result = 'Projekt' then
    Result := DAIText('Projekt', 'Project', 'Projet', 'プロジェクト')
  else if Result = 'Projektgruppe' then
    Result := DAIText('Projektgruppe', 'Project group', 'Groupe de projets', 'プロジェクトグループ')
  else if Result = 'Aktuelles Projekt' then
    Result := DAIText('Aktuelles Projekt', 'Current project', 'Projet actuel', '現在のプロジェクト');
end;

function IndexWarningCaption(const AWarning: string): string;
const
  CDefaultWarning = 'Deklarationsindex: seit der Erfassung geänderte und ungespeicherte Quellen können abweichen oder fehlen. ' +
    'Vor Verwendung den aktuellen Quelltext lesen. Bedingte Deklarationen sind nicht compilersemantisch aufgelöst.';
begin
  if AWarning = CDefaultWarning then
    Result := DAIText(CDefaultWarning,
      'Declaration index: sources changed since indexing and unsaved sources may differ or be missing. ' +
      'Read the current source before use. Conditional declarations are not resolved using compiler semantics.',
      'Index des déclarations : les sources modifiées depuis l’indexation et les sources non enregistrées peuvent différer ou manquer. ' +
      'Lisez la source actuelle avant utilisation. Les déclarations conditionnelles ne sont pas résolues selon la sémantique du compilateur.',
      '宣言インデックス: 作成後に変更されたソースや未保存のソースは、内容が異なるか含まれない場合があります。' +
      '使用前に現在のソースを確認してください。条件付き宣言はコンパイラーの意味解析では解決されていません。')
  else
    Result := AWarning;
end;

function StorageWarningCaption(const AWarning: string): string;
const
  CDefaultWarning = 'Dieser Fehlerbericht konnte nicht vollständig in der Indexdatei gespeichert werden und ist nur für den aktuellen IDE-Lauf verfügbar.';
begin
  if AWarning = CDefaultWarning then
    Result := DAIText(CDefaultWarning,
      'This error report could not be fully saved in the index file and is available only for the current IDE run.',
      'Ce rapport d’erreurs n’a pas pu être entièrement enregistré dans le fichier d’index et reste disponible uniquement pour cette session de l’IDE.',
      'このエラーレポートはインデックスファイルに完全に保存できなかったため、現在の IDE 起動中のみ利用できます。')
  else
    Result := AWarning;
end;

function StateCaption(const AState: string): string;
begin
  if AState = 'missing' then
    Result := DAIText('Nicht erstellt', 'Not created', 'Non créé', '未作成')
  else if AState = 'ready' then
    Result := DAIText('Vorhanden', 'Available', 'Disponible', '作成済み')
  else if (AState = 'building') or (AState = 'queued') or (AState = 'running') then
    Result := DAIText('Wird erstellt', 'Building', 'Création en cours', '作成中')
  else if AState = 'error' then
    Result := DAIText('Fehler', 'Error', 'Erreur', 'エラー')
  else if AState = 'outdated' then
    Result := DAIText('Aktualisieren erforderlich', 'Update required', 'Mise à jour requise', '更新が必要')
  else if AState = 'incomplete' then
    Result := DAIText('Unvollständig', 'Incomplete', 'Incomplet', '未完了')
  else if AState = 'unavailable' then
    Result := DAIText('Nicht verfügbar', 'Unavailable', 'Indisponible', '利用不可')
  else if AState = 'cancelled' then
    Result := DAIText('Abgebrochen', 'Cancelled', 'Annulé', 'キャンセル済み')
  else if AState = 'completed_with_errors' then
    Result := DAIText('Teilweise aktualisiert', 'Partially updated', 'Mise à jour partielle', '一部更新済み')
  else if (AState = 'completed') or (AState = 'done') then
    Result := DAIText('Abgeschlossen', 'Completed', 'Terminé', '完了')
  else
    Result := AState;
end;

function DateCaption(const AValue: string): string;
var
  LDate: TDateTime;
begin
  if AValue = '' then
    Exit('—');
  if TryISO8601ToDate(AValue, LDate, True) then
    Result := DateTimeToStr(TTimeZone.Local.ToLocalTime(LDate))
  else
    Result := AValue;
end;

constructor TDAISymbolErrorForm.Create(AOwner: TComponent);
var
  LPanel: TPanel;
  LButton: TButton;
begin
  inherited CreateNew(AOwner);
  if DAILanguage = dlJapanese then
    Font.Name := 'Yu Gothic UI';
  Name := 'DAISymbolIndexDetailsForm';
  Caption := DAIText('DAI — Fehlerdetails', 'DAI — Error details', 'DAI — Détails des erreurs', 'DAI — エラーの詳細');
  Position := poOwnerFormCenter;
  ClientWidth := 900;
  ClientHeight := 480;
  Constraints.MinWidth := 600;
  Constraints.MinHeight := 320;
  OnClose := FormClosed;
  LPanel := TPanel.Create(Self);
  LPanel.Parent := Self;
  LPanel.Caption := '';
  LPanel.Width := ClientWidth;
  LPanel.Align := alBottom;
  LPanel.Height := 52;
  LPanel.BevelOuter := bvNone;
  LButton := TButton.Create(Self);
  LButton.Parent := LPanel;
  LButton.Name := 'CopyIndexErrorsButton';
  LButton.Caption := DAIText('Alles kopieren', 'Copy all', 'Tout copier', 'すべてコピー');
  LButton.SetBounds(12, 12, 150, 28);
  LButton.OnClick := CopyClick;
  LButton := TButton.Create(Self);
  LButton.Parent := LPanel;
  LButton.Name := 'CloseIndexErrorsButton';
  LButton.Caption := DAIText('Schließen', 'Close', 'Fermer', '閉じる');
  LButton.SetBounds(ClientWidth - 112, 12, 100, 28);
  LButton.Anchors := [akTop, akRight];
  LButton.Cancel := True;
  LButton.OnClick := CloseClick;
  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Name := 'IndexErrorsMemo';
  FMemo.Align := alClient;
  FMemo.ReadOnly := True;
  FMemo.WordWrap := False;
  FMemo.ScrollBars := ssBoth;
  FMemo.HideSelection := False;
  FMemo.MaxLength := 0;
end;

procedure TDAISymbolErrorForm.Display(const ATitle, AText: string);
begin
  Caption := DAIText('DAI — Fehlerdetails: ', 'DAI — Error details: ', 'DAI — Détails des erreurs : ', 'DAI — エラーの詳細: ') + ATitle;
  FMemo.Text := AText;
  FMemo.SelStart := 0;
  FMemo.SelLength := 0;
  Show;
  BringToFront;
end;

procedure TDAISymbolErrorForm.CopyClick(Sender: TObject);
begin
  FMemo.SelectAll;
  FMemo.CopyToClipboard;
end;

procedure TDAISymbolErrorForm.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TDAISymbolErrorForm.FormClosed(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
end;

constructor TDAISymbolIndexForm.Create(AOwner: TComponent);
var
  LPanel: TPanel;
  LHeader: TPanel;
  LActions: TPanel;
  LClose: TButton;
  LUpdateWidth: Integer;

  function AddButton(const AName, ACaption: string; const ALeft, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  var
    LWidth: Integer;
  begin
    Result := TButton.Create(Self);
    Result.Parent := LActions;
    Result.Name := AName;
    Result.Caption := ACaption;
    Canvas.Font.Assign(Font);
    LWidth := Canvas.TextWidth(ACaption) + 24;
    if LWidth < AWidth then
      LWidth := AWidth;
    Result.SetBounds(ALeft, 12, LWidth, 28);
    Result.OnClick := AClick;
  end;

  procedure AddColumn(const ACaption: string; const AWidth: Integer; const AAlignment: TAlignment = taLeftJustify);
  begin
    with FList.Columns.Add do
    begin
      Caption := ACaption;
      Width := AWidth;
      Alignment := AAlignment;
    end;
  end;

begin
  inherited CreateNew(AOwner);
  if DAILanguage = dlJapanese then
    Font.Name := 'Yu Gothic UI';
  Name := 'DAISymbolIndexForm';
  Caption := DAIText('DAI — Quelltextindizes', 'DAI — Source indexes', 'DAI — Index des sources', 'DAI — ソースインデックス');
  Position := poMainFormCenter;
  BorderIcons := [biSystemMenu, biMinimize, biMaximize];
  ClientWidth := 1000;
  ClientHeight := 490;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 440;
  OnClose := FormClosed;
  LHeader := TPanel.Create(Self);
  LHeader.Parent := Self;
  LHeader.Name := 'IndexHeaderPanel';
  LHeader.Caption := '';
  LHeader.Width := ClientWidth;
  LHeader.Align := alTop;
  LHeader.BevelOuter := bvNone;
  FInformation := TDAIWrappedLabel.Create(Self);
  FInformation.Parent := LHeader;
  FInformation.Name := 'IndexInformationLabel';
  FInformation.SetBounds(12, 12, ClientWidth - 24, 16);
  FInformation.Align := alTop;
  FInformation.AlignWithMargins := True;
  FInformation.Margins.SetBounds(12, 12, 12, 8);
  FInformation.AutoSize := True;
  FInformation.WordWrap := True;
  FInformation.ShowAccelChar := False;
  FInformation.Caption := DAIText('Indizes sind Suchhilfen. Zuletzt geänderte oder ungespeicherte Quellen können abweichen oder fehlen.',
    'Indexes assist searches. Recently changed or unsaved sources may differ or be missing.',
    'Les index facilitent les recherches. Les sources modifiées récemment ou non enregistrées peuvent différer ou manquer.',
    'インデックスは検索を補助します。最近変更されたソースや未保存のソースは、内容が異なるか含まれない場合があります。');
  FProvider := TDAIWrappedLabel.Create(Self);
  FProvider.Parent := LHeader;
  FProvider.Name := 'IndexProviderLabel';
  FProvider.SetBounds(12, FInformation.BoundsRect.Bottom + 8, ClientWidth - 24, 16);
  FProvider.Align := alTop;
  FProvider.AlignWithMargins := True;
  FProvider.Margins.SetBounds(12, 0, 12, 12);
  FProvider.AutoSize := True;
  FProvider.WordWrap := True;
  FProvider.ShowAccelChar := False;
  LHeader.AutoSize := True;
  LPanel := TPanel.Create(Self);
  LPanel.Parent := Self;
  LPanel.Name := 'IndexFooterPanel';
  LPanel.Caption := '';
  LPanel.Width := ClientWidth;
  LPanel.Align := alBottom;
  LPanel.BevelOuter := bvNone;
  LActions := TPanel.Create(Self);
  LActions.Parent := LPanel;
  LActions.Name := 'IndexActionsPanel';
  LActions.Caption := '';
  LActions.Width := ClientWidth;
  LActions.Align := alTop;
  LActions.Height := 52;
  LActions.BevelOuter := bvNone;
  FUpdate := AddButton('UpdateIndexButton', DAIText('Aktualisieren', 'Update', 'Mettre à jour', '更新'), 12, 135, UpdateClick);
  FDelete := AddButton('DeleteIndexButton', DAIText('Löschen', 'Delete', 'Supprimer', '削除'), 155, 100, DeleteClick);
  FRefresh := AddButton('RefreshIndexListButton', DAIText('Liste neu laden', 'Reload list', 'Recharger la liste', '一覧を再読み込み'), 263, 125, RefreshClick);
  FDetails := AddButton('IndexErrorDetailsButton', DAIText('Fehlerdetails …', 'Error details …', 'Détails des erreurs …', 'エラーの詳細 …'), 396, 135, DetailsClick);
  LClose := AddButton('CloseIndexManagerButton', DAIText('Schließen', 'Close', 'Fermer', '閉じる'), 888, 100, CloseClick);
  // Reserve both shared-action captions and keep all translated buttons on one row.
  LUpdateWidth := Canvas.TextWidth(DAIText('Index erstellen', 'Create index', 'Créer l’index', 'インデックスを作成')) + 24;
  if FUpdate.Width < LUpdateWidth then
    FUpdate.Width := LUpdateWidth;
  FDelete.Left := FUpdate.Left + FUpdate.Width + 8;
  FRefresh.Left := FDelete.Left + FDelete.Width + 8;
  FDetails.Left := FRefresh.Left + FRefresh.Width + 8;
  LClose.Left := ClientWidth - LClose.Width - 12;
  LClose.Anchors := [akTop, akRight];
  LClose.Cancel := True;
  FStatus := TDAIWrappedLabel.Create(Self);
  FStatus.Parent := LPanel;
  FStatus.Name := 'IndexStatusLabel';
  FStatus.SetBounds(12, 52, ClientWidth - 24, 16);
  FStatus.Align := alTop;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(12, 0, 12, 12);
  FStatus.AutoSize := True;
  FStatus.WordWrap := True;
  FStatus.ShowAccelChar := False;
  LPanel.AutoSize := True;
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Name := 'SymbolIndexList';
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnChange := SelectionChanged;
  FList.OnDblClick := DetailsClick;
  AddColumn(DAIText('Index', 'Index', 'Index', 'インデックス'), 220);
  AddColumn(DAIText('Bereich', 'Scope', 'Portée', '範囲'), 120);
  AddColumn(DAIText('Erstellt / aktualisiert', 'Created / updated', 'Créé / mis à jour', '作成 / 更新日時'), 160);
  AddColumn(DAIText('Dateien', 'Files', 'Fichiers', 'ファイル'), 75, taRightJustify);
  AddColumn(DAIText('Deklarationen', 'Declarations', 'Déclarations', '宣言'), 100, taRightJustify);
  AddColumn(DAIText('Größe', 'Size', 'Taille', 'サイズ'), 80, taRightJustify);
  AddColumn(DAIText('Status', 'Status', 'État', '状態'), 125);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 750;
  FTimer.OnTimer := TimerTick;
end;

destructor TDAISymbolIndexForm.Destroy;
begin
  if GIndexForm = Self then
    GIndexForm := nil;
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  if Assigned(FList) then
    FList.OnChange := nil;
  FreeAndNil(FDetailsForm);
  FRows.Free;
  inherited;
end;

function TDAISymbolIndexForm.SelectedRow: TJSONObject;
begin
  Result := nil;
  if Assigned(FList.Selected) then
    Result := TJSONObject(FList.Selected.Data);
end;

procedure TDAISymbolIndexForm.UpdateButtons;
var
  LRow: TJSONObject;
  LScope: string;
  LRowBusy, LValidTarget: Boolean;
begin
  LRow := SelectedRow;
  LScope := JSONText(LRow, 'scope');
  LRowBusy := IndexReportUpdating(LRow);
  if (LScope = 'project') or (LScope = 'group') then
    LValidTarget := Trim(JSONText(LRow, 'owner')) <> ''
  else
    LValidTarget := ((LScope = 'delphi') or (LScope = 'getit')) and (Trim(JSONText(LRow, 'database')) <> '');
  FUpdate.Enabled := not FBusy and not LRowBusy and LValidTarget;
  if JSONFlag(LRow, 'exists') then
    FUpdate.Caption := DAIText('Aktualisieren', 'Update', 'Mettre à jour', '更新')
  else
    FUpdate.Caption := DAIText('Index erstellen', 'Create index', 'Créer l’index', 'インデックスを作成');
  FDelete.Enabled := not FBusy and not LRowBusy and JSONFlag(LRow, 'exists');
  FRefresh.Enabled := not FBusy;
  FDetails.Enabled := IndexDetailsAvailable(LRow) and not IndexReportUpdating(LRow);
end;

procedure TDAISymbolIndexForm.UpdateSelectionStatus;
var
  LRow: TJSONObject;
  LState: string;
begin
  if FBusy or FRefreshingList then
    Exit;
  LRow := SelectedRow;
  LState := JSONText(LRow, 'state');
  if Trim(JSONText(LRow, 'error')) <> '' then
    FStatus.Caption := DAIText('Indexfehler: ', 'Index error: ', 'Erreur d’index : ', 'インデックスエラー: ') +
      ErrorSummary(JSONText(LRow, 'error')) + DAIText(' — Fehlerdetails …', ' — Error details …', ' — Détails des erreurs …', ' — エラーの詳細 …')
  else if (LState = 'incomplete') or (LState = 'cancelled') then
  begin
    FStatus.Caption := Format(DAIText('Index %s', 'Index %s', 'Index %s', 'インデックス: %s'), [LowerCase(StateCaption(LState))]);
    if IndexErrorCount(LRow) > 0 then
      FStatus.Caption := FStatus.Caption + Format(DAIText(': %s Dateien nicht indiziert', ': %s files not indexed',
        ' : %s fichiers non indexés', ': %s ファイルが未登録'), [CountCaption(IndexErrorCount(LRow))]);
    if IndexDetailsAvailable(LRow) then
      FStatus.Caption := FStatus.Caption + DAIText(' — Fehlerdetails …', ' — Error details …', ' — Détails des erreurs …', ' — エラーの詳細 …');
  end
  else if IndexErrorCount(LRow) > 0 then
    if LState = 'error' then
      FStatus.Caption := Format(DAIText('Indexerstellung fehlgeschlagen: %s Dateien nicht indiziert — Fehlerdetails …',
        'Index build failed: %s files not indexed — Error details …',
        'Échec de création de l’index : %s fichiers non indexés — Détails des erreurs …',
        'インデックスの作成に失敗しました: %s ファイルが未登録 — エラーの詳細 …'), [CountCaption(IndexErrorCount(LRow))])
    else
      FStatus.Caption := PartialIndexMessage(LRow)
  else if IndexDetailsAvailable(LRow) then
    FStatus.Caption := DAIText('Details zum letzten Indexauftrag verfügbar — Fehlerdetails …',
      'Details of the last index job available — Error details …',
      'Les détails de la dernière tâche d’indexation sont disponibles — Détails des erreurs …',
      '前回のインデックス処理の詳細があります — エラーの詳細 …')
  else
    FStatus.Caption := FDefaultStatus;
end;

procedure TDAISymbolIndexForm.RefreshList(const AScope: string);
var
  LResult: TJSONObject;
  LIndexes: TJSONValue;
  LRows: TJSONArray;
  LValue: TJSONValue;
  LRow: TJSONObject;
  LItem: TListItem;
  LScope: string;
  LSelectedScope: string;
begin
  LSelectedScope := AScope;
  if LSelectedScope = '' then
    LSelectedScope := JSONText(SelectedRow, 'scope');
  LResult := TDAISymbolService.ListIndexes;
  try
    LIndexes := LResult.GetValue('indexes');
    if not (LIndexes is TJSONArray) then
      raise EInvalidOperation.Create(DAIText('Die Indexliste enthält keine gültigen Einträge.',
        'The index list contains no valid entries.',
        'La liste des index ne contient aucune entrée valide.',
        'インデックス一覧に有効な項目がありません。'));
    LRows := TJSONArray(LIndexes.Clone);
    FDefaultStatus := IndexWarningCaption(JSONText(LResult, 'warning', DAIText('Bereit.', 'Ready.', 'Prêt.', '準備完了。')));
    FRefreshingList := True;
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      FreeAndNil(FRows);
      FRows := LRows;
      for LValue in FRows do
      begin
        if not (LValue is TJSONObject) then
          Continue;
        LRow := TJSONObject(LValue);
        LScope := JSONText(LRow, 'scope');
        if not FBusy and (JSONText(LRow, 'state') = 'building') and (JSONText(LRow, 'request_id') <> '') then
        begin
          FRequestId := JSONText(LRow, 'request_id');
          FBusy := True;
          FTimer.Enabled := Visible;
        end;
        LItem := FList.Items.Add;
        LItem.Data := LRow;
        LItem.Caption := IndexNameCaption(LRow);
        LItem.SubItems.Add(ScopeCaption(LScope));
        LItem.SubItems.Add(DateCaption(JSONText(LRow, 'indexed_at')));
        LItem.SubItems.Add(JSONCountCaption(LRow, 'file_count'));
        LItem.SubItems.Add(JSONCountCaption(LRow, 'symbol_count'));
        LItem.SubItems.Add(IndexSizeCaption(LRow));
        LItem.SubItems.Add(StateCaption(JSONText(LRow, 'state')));
        if LScope = LSelectedScope then
          LItem.Selected := True;
      end;
      if not Assigned(FList.Selected) and (FList.Items.Count > 0) then
        FList.Items[0].Selected := True;
    finally
      FList.Items.EndUpdate;
      FRefreshingList := False;
    end;
    if not FBusy then
      FStatus.Caption := FDefaultStatus;
  finally
    LResult.Free;
  end;
  UpdateButtons;
  UpdateSelectionStatus;
end;

procedure TDAISymbolIndexForm.RefreshProviders;
var
  LResult: TJSONObject;
begin
  LResult := TDAISymbolService.AIStatus;
  try
    // Provider discovery is metadata only; listing indices never sends a model request.
    if JSONFlag(LResult, 'available') then
      FProvider.Caption := DAIText('Smart CodeInsight: KI-Anbieter aktiviert. Der Deklarationsindex wird lokal ohne KI-Aufruf erstellt.',
        'Smart CodeInsight: AI provider enabled. The declaration index is built locally without an AI request.',
        'Smart CodeInsight : fournisseur d’IA activé. L’index des déclarations est créé localement sans requête à l’IA.',
        'Smart CodeInsight: AI プロバイダーが有効です。宣言インデックスは AI を呼び出さずにローカルで作成されます。')
    else
      FProvider.Caption := DAIText('Der Deklarationsindex wird lokal ohne KI-Aufruf erstellt; ein KI-Anbieter ist dafür nicht erforderlich.',
        'The declaration index is built locally without an AI request; no AI provider is required.',
        'L’index des déclarations est créé localement sans requête à l’IA ; aucun fournisseur d’IA n’est nécessaire.',
        '宣言インデックスは AI を呼び出さずにローカルで作成されます。AI プロバイダーは不要です。');
  finally
    LResult.Free;
  end;
end;

procedure TDAISymbolIndexForm.ShowScope(const AScope: string);
begin
  try
    RefreshList(AScope);
    RefreshProviders;
  except
    on E: Exception do
      FStatus.Caption := E.Message;
  end;
  Show;
  FTimer.Enabled := FBusy;
  BringToFront;
end;

procedure TDAISymbolIndexForm.BeginBuild(const AScope, AIdentity: string);
var
  LResult: TJSONObject;
begin
  if FBusy or (AScope = '') then
    Exit;
  try
    LResult := TDAISymbolService.Build(AScope, AIdentity);
    try
      FRequestId := JSONText(LResult, 'request_id');
      FBusy := FRequestId <> '';
      FTimer.Enabled := FBusy;
      FStatus.Caption := JSONText(LResult, 'message', DAIText('Indexerstellung angefordert.', 'Index build requested.', 'Création de l’index demandée.', 'インデックスの作成を要求しました。'));
    finally
      LResult.Free;
    end;
    RefreshList(AScope);
  except
    on E: Exception do
      FStatus.Caption := E.Message;
  end;
  UpdateButtons;
end;

procedure TDAISymbolIndexForm.SelectionChanged(Sender: TObject; Item: TListItem; Change: TItemChange);
begin
  if Change = ctState then
  begin
    UpdateButtons;
    UpdateSelectionStatus;
  end;
end;

procedure TDAISymbolIndexForm.UpdateClick(Sender: TObject);
begin
  if FUpdate.Enabled then
    BeginBuild(JSONText(SelectedRow, 'scope'), JSONText(SelectedRow, 'identity'));
end;

procedure TDAISymbolIndexForm.DeleteClick(Sender: TObject);
var
  LResult: TJSONObject;
  LScope: string;
  LIdentity: string;
  LMessage: string;
begin
  if not FDelete.Enabled then
    Exit;
  LScope := JSONText(SelectedRow, 'scope');
  LIdentity := JSONText(SelectedRow, 'identity');
  try
    LResult := TDAISymbolService.Delete(LScope, LIdentity);
    try
      if JSONFlag(LResult, 'deleted') then
        LMessage := DAIText('Index gelöscht.', 'Index deleted.', 'Index supprimé.', 'インデックスを削除しました。')
      else
        LMessage := DAIText('Kein Index vorhanden.', 'No index available.', 'Aucun index disponible.', 'インデックスがありません。');
      LMessage := JSONText(LResult, 'message', LMessage);
    finally
      LResult.Free;
    end;
    RefreshList(LScope);
    FStatus.Caption := LMessage;
  except
    on E: Exception do
      FStatus.Caption := E.Message;
  end;
end;

procedure TDAISymbolIndexForm.RefreshClick(Sender: TObject);
begin
  try
    RefreshList;
    RefreshProviders;
  except
    on E: Exception do
      FStatus.Caption := E.Message;
  end;
end;

procedure TDAISymbolIndexForm.DetailsClick(Sender: TObject);
var
  LRow, LPage, LError: TJSONObject;
  LErrors: TJSONArray;
  LValue: TJSONValue;
  LText: TStringBuilder;
  LScope, LIdentity, LName, LReportId: string;
  LOffset, LCount, LTotal: Integer;
  LMore: Boolean;
begin
  LRow := SelectedRow;
  if not Assigned(LRow) or not IndexDetailsAvailable(LRow) or IndexReportUpdating(LRow) then
    Exit;
  LScope := JSONText(LRow, 'scope');
  LIdentity := JSONText(LRow, 'identity');
  LName := IndexNameCaption(LRow);
  LText := TStringBuilder.Create;
  try
    LText.AppendLine(DAIText('Index: ', 'Index: ', 'Index : ', 'インデックス: ') + LName);
    LText.AppendLine(DAIText('Bereich: ', 'Scope: ', 'Portée : ', '範囲: ') + ScopeCaption(LScope));
    LText.AppendLine(DAIText('Indexstand: ', 'Index date: ', 'Date de l’index : ', 'インデックス日時: ') + DateCaption(JSONText(LRow, 'indexed_at')));
    if Trim(JSONText(LRow, 'error')) <> '' then
      LText.AppendLine(DAIText('Fehler aus dem Indexstatus:',
        'Error from the index status:',
        'Erreur signalée par l’état de l’index :',
        'インデックス状態のエラー:')).AppendLine(JSONText(LRow, 'error')).AppendLine;
    LOffset := 0;
    LCount := 0;
    LTotal := -1;
    LReportId := '';
    try
      repeat
        LPage := TDAISymbolService.IndexErrors(LScope, LIdentity, LOffset, 500);
        try
          if IndexReportUpdating(LPage) then
            raise EInvalidOperation.Create(DAIText('Der Fehlerbericht wird noch aktualisiert. Bitte nach Abschluss des Indexauftrags erneut öffnen.',
              'The error report is still being updated. Reopen it after the index job completes.',
              'Le rapport d’erreurs est en cours de mise à jour. Rouvrez-le une fois la tâche d’indexation terminée.',
              'エラーレポートは更新中です。インデックス処理の完了後に開き直してください。'));
          LErrors := LPage.GetValue<TJSONArray>('errors', nil);
          if not Assigned(LErrors) then
            raise EInvalidOperation.Create(DAIText('Die Fehlerliste enthält keine gültigen Einträge.',
              'The error list contains no valid entries.',
              'La liste des erreurs ne contient aucune entrée valide.',
              'エラー一覧に有効な項目がありません。'));
          if LTotal < 0 then
          begin
            LTotal := LPage.GetValue<Integer>('total_count', LErrors.Count);
            LReportId := JSONText(LPage, 'request_id');
            LText.AppendLine(DAIText('Letzter Indexauftrag: ', 'Last index job: ', 'Dernière tâche d’indexation : ', '前回のインデックス処理: ') + StateCaption(JSONText(LPage, 'state')));
            LText.AppendLine(DAIText('Begonnen: ', 'Started: ', 'Début : ', '開始日時: ') + DateCaption(JSONText(LPage, 'started_at')));
            LText.AppendLine(DAIText('Beendet: ', 'Finished: ', 'Fin : ', '終了日時: ') + DateCaption(JSONText(LPage, 'finished_at')));
            if JSONText(LPage, 'storage_warning') <> '' then
              LText.AppendLine(StorageWarningCaption(JSONText(LPage, 'storage_warning'))).AppendLine;
            if JSONText(LPage, 'error') <> '' then
            begin
              if JSONText(LPage, 'error') <> JSONText(LRow, 'error') then
                LText.AppendLine(DAIText('Allgemeiner Fehler / Grund:', 'General error / reason:',
                  'Erreur générale / cause :', '全般的なエラー / 理由:')).AppendLine(JSONText(LPage, 'error'));
            end
            else if Trim(JSONText(LRow, 'error')) = '' then
            begin
              if JSONText(LPage, 'state') = 'incomplete' then
                LText.AppendLine(DAIText('Der letzte Indexauftrag wurde nicht vollständig abgeschlossen. Ein genauerer Fehlergrund wurde nicht aufgezeichnet.',
                  'The last index job did not finish completely. No more specific error reason was recorded.',
                  'La dernière tâche d’indexation est incomplète. Aucune cause d’erreur plus précise n’a été enregistrée.',
                  '前回のインデックス処理は完了しませんでした。詳しいエラーの理由は記録されていません。'))
              else if JSONText(LPage, 'state') = 'error' then
                LText.AppendLine(DAIText('Der Indexauftrag ist fehlgeschlagen. Ein genauerer Fehlergrund wurde nicht aufgezeichnet.',
                  'The index job failed. No more specific error reason was recorded.',
                  'La tâche d’indexation a échoué. Aucune cause d’erreur plus précise n’a été enregistrée.',
                  'インデックス処理に失敗しました。詳しいエラーの理由は記録されていません。'))
              else if JSONText(LPage, 'state') = 'cancelled' then
                LText.AppendLine(DAIText('Der Indexauftrag wurde abgebrochen. Ein genauerer Grund wurde nicht aufgezeichnet.',
                  'The index job was cancelled. No more specific reason was recorded.',
                  'La tâche d’indexation a été annulée. Aucune cause plus précise n’a été enregistrée.',
                  'インデックス処理はキャンセルされました。詳しい理由は記録されていません。'));
            end;
            LText.AppendLine;
            LText.AppendLine(DAIText('Dateien und Gründe für die fehlende Indizierung:',
              'Files and reasons for missing indexing:',
              'Fichiers et causes de l’absence d’indexation :',
              '未登録のファイルとその理由:')).AppendLine;
          end
          else if (LTotal <> LPage.GetValue<Integer>('total_count', LTotal)) or (LReportId <> JSONText(LPage, 'request_id')) then
            raise EInvalidOperation.Create(DAIText('Die Fehlerliste wurde während des Lesens geändert. Bitte die Liste neu laden und erneut öffnen.',
              'The error list changed while reading. Reload the list and reopen it.',
              'La liste des erreurs a changé pendant la lecture. Rechargez la liste et rouvrez-la.',
              '読み取り中にエラー一覧が変更されました。一覧を再読み込みして開き直してください。'));
          for LValue in LErrors do
          begin
            if not (LValue is TJSONObject) then
              raise EInvalidOperation.Create(DAIText('Die Fehlerliste enthält einen ungültigen Eintrag.',
                'The error list contains an invalid entry.',
                'La liste des erreurs contient une entrée invalide.',
                'エラー一覧に無効な項目があります。'));
            LError := TJSONObject(LValue);
            Inc(LCount);
            LText.AppendLine(CountCaption(LCount) + '. ' + JSONText(LError, 'file', DAIText('(Dateipfad nicht verfügbar)',
              '(File path unavailable)',
              '(Chemin du fichier indisponible)',
              '（ファイルパスを取得できません）')));
            LText.AppendLine(JSONText(LError, 'error', DAIText('(Fehlergrund nicht verfügbar)',
              '(Error reason unavailable)',
              '(Cause de l’erreur indisponible)',
              '（エラーの理由を取得できません）'))).AppendLine;
          end;
          LMore := JSONFlag(LPage, 'has_more');
          if LMore and (LErrors.Count = 0) then
            raise EInvalidOperation.Create(DAIText('Die Fehlerliste konnte nicht vollständig geladen werden. Bitte erneut öffnen.',
              'The complete error list could not be loaded. Reopen it.',
              'Impossible de charger toute la liste des erreurs. Rouvrez-la.',
              'エラー一覧を完全に読み込めませんでした。開き直してください。'));
          Inc(LOffset, LErrors.Count);
        finally
          LPage.Free;
        end;
      until not LMore;
      if LCount <> LTotal then
        raise EInvalidOperation.Create(DAIText('Die Fehlerliste konnte nicht vollständig geladen werden. Bitte die Liste neu laden und erneut öffnen.',
          'The complete error list could not be loaded. Reload the list and reopen it.',
          'Impossible de charger toute la liste des erreurs. Rechargez la liste et rouvrez-la.',
          'エラー一覧を完全に読み込めませんでした。一覧を再読み込みして開き直してください。'));
      if LCount > 0 then
        LText.AppendLine(Format(DAIText('%s Dateien nicht indiziert.', '%s files not indexed.', '%s fichiers non indexés.', '%s ファイルが未登録。'), [CountCaption(LCount)]))
      else
        LText.AppendLine(DAIText('Keine einzelnen Dateifehler aufgezeichnet.',
          'No individual file errors recorded.',
          'Aucune erreur de fichier individuelle enregistrée.',
          '個別のファイルエラーは記録されていません。'));
    except
      on E: Exception do
        LText.AppendLine(DAIText('Fehler beim Laden der Details:',
          'Error loading details:',
          'Erreur lors du chargement des détails :',
          '詳細の読み込みエラー:')).AppendLine(E.Message);
    end;
    if not Assigned(FDetailsForm) then
      FDetailsForm := TDAISymbolErrorForm.Create(Self);
    FDetailsForm.Display(LName, LText.ToString);
  finally
    LText.Free;
  end;
end;

procedure TDAISymbolIndexForm.TimerTick(Sender: TObject);
var
  LResult: TJSONObject;
  LState: string;
  LMessage: string;
begin
  if not Visible or not FBusy or (FRequestId = '') then
    Exit;
  try
    LResult := TDAISymbolService.JobStatus(FRequestId);
    try
      LState := JSONText(LResult, 'state', JSONText(LResult, 'status'));
      LMessage := JSONText(LResult, 'message');
      if LMessage = '' then
        if LState = 'completed' then
          LMessage := DAIText('Index aktualisiert.', 'Index updated.', 'Index mis à jour.', 'インデックスを更新しました。')
        else if LState = 'completed_with_errors' then
          LMessage := PartialIndexMessage(LResult)
        else if LState = 'error' then
          LMessage := DAIText('Indexerstellung fehlgeschlagen.', 'Index build failed.', 'Échec de création de l’index.', 'インデックスの作成に失敗しました。')
        else if LState = 'cancelled' then
          LMessage := DAIText('Indexerstellung abgebrochen.',
            'Index build cancelled.',
            'Création de l’index annulée.',
            'インデックスの作成はキャンセルされました。')
        else
          LMessage := StateCaption(LState) + ': ' + JSONCountCaption(LResult, 'processed_files') + ' / ' +
            JSONCountCaption(LResult, 'total_files') + DAIText(' Dateien', ' files', ' fichiers', ' ファイル');
      if (LState = 'completed_with_errors') and (IndexErrorCount(LResult) > 0) then
        LMessage := PartialIndexMessage(LResult);
      if ((LState = 'error') or (LState = 'cancelled')) and (Trim(JSONText(LResult, 'error')) <> '') then
      begin
        if LState = 'error' then
          LMessage := DAIText('Indexerstellung fehlgeschlagen', 'Index build failed', 'Échec de création de l’index', 'インデックスの作成に失敗しました')
        else
          LMessage := DAIText('Indexerstellung abgebrochen', 'Index build cancelled', 'Création de l’index annulée', 'インデックスの作成はキャンセルされました');
        LMessage := LMessage + ': ' + ErrorSummary(JSONText(LResult, 'error')) + DAIText(' — Fehlerdetails …', ' — Error details …', ' — Détails des erreurs …', ' — エラーの詳細 …');
      end;
      FStatus.Caption := LMessage;
      if (LState = 'ready') or (LState = 'completed') or (LState = 'completed_with_errors') or (LState = 'done') or (LState = 'error') or (LState = 'cancelled') then
      begin
        FBusy := False;
        FTimer.Enabled := False;
        FRequestId := '';
        try
          RefreshList;
        except
          on E: Exception do
            LMessage := LMessage + sLineBreak + DAIText('Die Indexliste konnte nicht aktualisiert werden: ',
              'The index list could not be refreshed: ',
              'Impossible d’actualiser la liste des index : ',
              'インデックス一覧を更新できませんでした: ') + ErrorSummary(E.Message);
        end;
        FStatus.Caption := LMessage;
      end;
    finally
      LResult.Free;
    end;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      FBusy := False;
      FStatus.Caption := E.Message;
    end;
  end;
  UpdateButtons;
end;

procedure TDAISymbolIndexForm.FormClosed(Sender: TObject; var Action: TCloseAction);
begin
  // Preserve the selection; the service owns any running job independently.
  FTimer.Enabled := False;
  if Assigned(FDetailsForm) then
    FDetailsForm.Hide;
  Action := caHide;
end;

procedure TDAISymbolIndexForm.CloseClick(Sender: TObject);
begin
  Close;
end;

class procedure TDAISymbolIndexDialog.Show(const AScope: string);
begin
  RequireMainThread;
  if not Assigned(GIndexForm) then
    GIndexForm := TDAISymbolIndexForm.Create(Application);
  GIndexForm.ShowScope(AScope);
end;

class procedure TDAISymbolIndexDialog.Shutdown;
begin
  RequireMainThread;
  FreeAndNil(GIndexForm);
end;

initialization

finalization
  TDAISymbolIndexDialog.Shutdown;

end.
