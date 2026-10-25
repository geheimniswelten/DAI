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
    raise EInvalidOperation.Create('Die DAI-Indexverwaltung muss auf dem IDE-Hauptthread geöffnet werden.');
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
  Result := Format('Teilweise aktualisiert: %s Dateien nicht indiziert — Fehlerdetails …', [CountCaption(IndexErrorCount(AObject))]);
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
    Result := 'Projektgruppe'
  else if AScope = 'project' then
    Result := 'Projekt'
  else
    Result := AScope;
end;

function StateCaption(const AState: string): string;
begin
  if AState = 'missing' then
    Result := 'Nicht erstellt'
  else if AState = 'ready' then
    Result := 'Vorhanden'
  else if (AState = 'building') or (AState = 'queued') or (AState = 'running') then
    Result := 'Wird erstellt'
  else if AState = 'error' then
    Result := 'Fehler'
  else if AState = 'outdated' then
    Result := 'Aktualisieren erforderlich'
  else if AState = 'incomplete' then
    Result := 'Unvollständig'
  else if AState = 'cancelled' then
    Result := 'Abgebrochen'
  else if AState = 'completed_with_errors' then
    Result := 'Teilweise aktualisiert'
  else if (AState = 'completed') or (AState = 'done') then
    Result := 'Abgeschlossen'
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
  Name := 'DAISymbolIndexDetailsForm';
  Caption := 'DAI — Fehlerdetails';
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
  LButton.Caption := 'Alles kopieren';
  LButton.SetBounds(12, 12, 130, 28);
  LButton.OnClick := CopyClick;
  LButton := TButton.Create(Self);
  LButton.Parent := LPanel;
  LButton.Name := 'CloseIndexErrorsButton';
  LButton.Caption := 'Schließen';
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
  Caption := 'DAI — Fehlerdetails: ' + ATitle;
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

  function AddButton(const AName, ACaption: string; const ALeft, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := LActions;
    Result.Name := AName;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, 12, AWidth, 28);
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
  Name := 'DAISymbolIndexForm';
  Caption := 'DAI — Quelltextindizes';
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
  FInformation.Caption := 'Indizes sind Suchhilfen. Zuletzt geänderte oder ungespeicherte Quellen können abweichen oder fehlen.';
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
  FUpdate := AddButton('UpdateIndexButton', 'Aktualisieren', 12, 135, UpdateClick);
  FDelete := AddButton('DeleteIndexButton', 'Löschen', 155, 100, DeleteClick);
  FRefresh := AddButton('RefreshIndexListButton', 'Liste neu laden', 263, 125, RefreshClick);
  FDetails := AddButton('IndexErrorDetailsButton', 'Fehlerdetails …', 396, 135, DetailsClick);
  LClose := AddButton('CloseIndexManagerButton', 'Schließen', 888, 100, CloseClick);
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
  AddColumn('Index', 220);
  AddColumn('Bereich', 120);
  AddColumn('Erstellt / aktualisiert', 160);
  AddColumn('Dateien', 75, taRightJustify);
  AddColumn('Deklarationen', 100, taRightJustify);
  AddColumn('Größe', 80, taRightJustify);
  AddColumn('Status', 125);
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
    FUpdate.Caption := 'Aktualisieren'
  else
    FUpdate.Caption := 'Index erstellen';
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
    FStatus.Caption := 'Indexfehler: ' + ErrorSummary(JSONText(LRow, 'error')) + ' — Fehlerdetails …'
  else if (LState = 'incomplete') or (LState = 'cancelled') then
  begin
    FStatus.Caption := 'Index ' + LowerCase(StateCaption(LState));
    if IndexErrorCount(LRow) > 0 then
      FStatus.Caption := FStatus.Caption + Format(': %s Dateien nicht indiziert', [CountCaption(IndexErrorCount(LRow))]);
    if IndexDetailsAvailable(LRow) then
      FStatus.Caption := FStatus.Caption + ' — Fehlerdetails …';
  end
  else if IndexErrorCount(LRow) > 0 then
    if LState = 'error' then
      FStatus.Caption := Format('Indexerstellung fehlgeschlagen: %s Dateien nicht indiziert — Fehlerdetails …', [CountCaption(IndexErrorCount(LRow))])
    else
      FStatus.Caption := PartialIndexMessage(LRow)
  else if IndexDetailsAvailable(LRow) then
    FStatus.Caption := 'Details zum letzten Indexauftrag verfügbar — Fehlerdetails …'
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
      raise EInvalidOperation.Create('Die Indexliste enthält keine gültigen Einträge.');
    LRows := TJSONArray(LIndexes.Clone);
    FDefaultStatus := JSONText(LResult, 'warning', 'Bereit.');
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
        LItem.Caption := JSONText(LRow, 'name', ScopeCaption(LScope));
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
      FProvider.Caption := 'Smart CodeInsight: KI-Anbieter aktiviert. Der Deklarationsindex wird lokal ohne KI-Aufruf erstellt.'
    else
      FProvider.Caption := 'Der Deklarationsindex wird lokal ohne KI-Aufruf erstellt; ein KI-Anbieter ist dafür nicht erforderlich.';
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
      FStatus.Caption := JSONText(LResult, 'message', 'Indexerstellung angefordert.');
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
        LMessage := 'Index gelöscht.'
      else
        LMessage := 'Kein Index vorhanden.';
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
  LName := JSONText(LRow, 'name', ScopeCaption(LScope));
  LText := TStringBuilder.Create;
  try
    LText.AppendLine('Index: ' + LName);
    LText.AppendLine('Bereich: ' + ScopeCaption(LScope));
    LText.AppendLine('Indexstand: ' + DateCaption(JSONText(LRow, 'indexed_at')));
    if Trim(JSONText(LRow, 'error')) <> '' then
      LText.AppendLine('Fehler aus dem Indexstatus:').AppendLine(JSONText(LRow, 'error')).AppendLine;
    LOffset := 0;
    LCount := 0;
    LTotal := -1;
    LReportId := '';
    try
      repeat
        LPage := TDAISymbolService.IndexErrors(LScope, LIdentity, LOffset, 500);
        try
          if IndexReportUpdating(LPage) then
            raise EInvalidOperation.Create('Der Fehlerbericht wird noch aktualisiert. Bitte nach Abschluss des Indexauftrags erneut öffnen.');
          LErrors := LPage.GetValue<TJSONArray>('errors', nil);
          if not Assigned(LErrors) then
            raise EInvalidOperation.Create('Die Fehlerliste enthält keine gültigen Einträge.');
          if LTotal < 0 then
          begin
            LTotal := LPage.GetValue<Integer>('total_count', LErrors.Count);
            LReportId := JSONText(LPage, 'request_id');
            LText.AppendLine('Letzter Indexauftrag: ' + StateCaption(JSONText(LPage, 'state')));
            LText.AppendLine('Begonnen: ' + DateCaption(JSONText(LPage, 'started_at')));
            LText.AppendLine('Beendet: ' + DateCaption(JSONText(LPage, 'finished_at')));
            if JSONText(LPage, 'storage_warning') <> '' then
              LText.AppendLine(JSONText(LPage, 'storage_warning')).AppendLine;
            if JSONText(LPage, 'error') <> '' then
            begin
              if JSONText(LPage, 'error') <> JSONText(LRow, 'error') then
                LText.AppendLine('Allgemeiner Fehler / Grund:').AppendLine(JSONText(LPage, 'error'));
            end
            else if Trim(JSONText(LRow, 'error')) = '' then
            begin
              if JSONText(LPage, 'state') = 'incomplete' then
                LText.AppendLine('Der letzte Indexauftrag wurde nicht vollständig abgeschlossen. Ein genauerer Fehlergrund wurde nicht aufgezeichnet.')
              else if JSONText(LPage, 'state') = 'error' then
                LText.AppendLine('Der Indexauftrag ist fehlgeschlagen. Ein genauerer Fehlergrund wurde nicht aufgezeichnet.')
              else if JSONText(LPage, 'state') = 'cancelled' then
                LText.AppendLine('Der Indexauftrag wurde abgebrochen. Ein genauerer Grund wurde nicht aufgezeichnet.');
            end;
            LText.AppendLine;
            LText.AppendLine('Dateien und Gründe für die fehlende Indizierung:').AppendLine;
          end
          else if (LTotal <> LPage.GetValue<Integer>('total_count', LTotal)) or (LReportId <> JSONText(LPage, 'request_id')) then
            raise EInvalidOperation.Create('Die Fehlerliste wurde während des Lesens geändert. Bitte die Liste neu laden und erneut öffnen.');
          for LValue in LErrors do
          begin
            if not (LValue is TJSONObject) then
              raise EInvalidOperation.Create('Die Fehlerliste enthält einen ungültigen Eintrag.');
            LError := TJSONObject(LValue);
            Inc(LCount);
            LText.AppendLine(CountCaption(LCount) + '. ' + JSONText(LError, 'file', '(Dateipfad nicht verfügbar)'));
            LText.AppendLine(JSONText(LError, 'error', '(Fehlergrund nicht verfügbar)')).AppendLine;
          end;
          LMore := JSONFlag(LPage, 'has_more');
          if LMore and (LErrors.Count = 0) then
            raise EInvalidOperation.Create('Die Fehlerliste konnte nicht vollständig geladen werden. Bitte erneut öffnen.');
          Inc(LOffset, LErrors.Count);
        finally
          LPage.Free;
        end;
      until not LMore;
      if LCount <> LTotal then
        raise EInvalidOperation.Create('Die Fehlerliste konnte nicht vollständig geladen werden. Bitte die Liste neu laden und erneut öffnen.');
      if LCount > 0 then
        LText.AppendLine(Format('%s Dateien nicht indiziert.', [CountCaption(LCount)]))
      else
        LText.AppendLine('Keine einzelnen Dateifehler aufgezeichnet.');
    except
      on E: Exception do
        LText.AppendLine('Fehler beim Laden der Details:').AppendLine(E.Message);
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
          LMessage := 'Index aktualisiert.'
        else if LState = 'completed_with_errors' then
          LMessage := PartialIndexMessage(LResult)
        else if LState = 'error' then
          LMessage := 'Indexerstellung fehlgeschlagen.'
        else if LState = 'cancelled' then
          LMessage := 'Indexerstellung abgebrochen.'
        else
          LMessage := StateCaption(LState) + ': ' + JSONCountCaption(LResult, 'processed_files') + ' / ' +
            JSONCountCaption(LResult, 'total_files') + ' Dateien';
      if (LState = 'completed_with_errors') and (IndexErrorCount(LResult) > 0) then
        LMessage := PartialIndexMessage(LResult);
      if ((LState = 'error') or (LState = 'cancelled')) and (Trim(JSONText(LResult, 'error')) <> '') then
      begin
        if LState = 'error' then
          LMessage := 'Indexerstellung fehlgeschlagen'
        else
          LMessage := 'Indexerstellung abgebrochen';
        LMessage := LMessage + ': ' + ErrorSummary(JSONText(LResult, 'error')) + ' — Fehlerdetails …';
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
            LMessage := LMessage + sLineBreak + 'Die Indexliste konnte nicht aktualisiert werden: ' + ErrorSummary(E.Message);
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
