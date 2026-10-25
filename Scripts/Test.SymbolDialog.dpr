program Test.SymbolDialog;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  System.Types,
  Winapi.Windows,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Vcl.StdCtrls,
  h5u.DAI.Symbols.Service,
  h5u.DAI.Symbols.Dialog in '..\Source\h5u.DAI.Symbols.Dialog.pas';

var
  GChecks: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function Manager: TForm;
begin
  Result := nil;
  for var LIndex := 0 to Screen.FormCount - 1 do
    if Screen.Forms[LIndex].Name = 'DAISymbolIndexForm' then
      Exit(Screen.Forms[LIndex]);
end;

function Button(const AName: string): TButton;
begin
  Result := TButton(Manager.FindComponent(AName));
  Check(Assigned(Result), 'A named manager button exists: ' + AName);
end;

function PollTimer: TTimer;
begin
  Result := nil;
  for var LIndex := 0 to Manager.ComponentCount - 1 do
    if Manager.Components[LIndex] is TTimer then
      Exit(TTimer(Manager.Components[LIndex]));
end;

procedure TestManager;
var
  LList: TListView;
  LForm: TForm;
begin
  TDAISymbolService.Reset;
  TDAISymbolService.Existing[0] := True;
  TDAISymbolIndexDialog.Show;
  LForm := Manager;
  Check(Assigned(LForm) and LForm.Visible, 'The manager is visible and modeless');
  Check(TDAISymbolService.BuildCount = 0, 'Showing the manager never creates an index');
  Check(TDAISymbolService.ListCount = 1, 'Opening obtains one metadata snapshot');
  Check(TDAISymbolService.ProviderCount = 1, 'Opening checks provider availability metadata');
  LList := TListView(LForm.FindComponent('SymbolIndexList'));
  Check(LList.Items.Count = 4, 'All four index scopes are listed');
  Check(LList.Columns.Count = 7, 'Name, scope, date, file count, symbol count, database size and state are displayed');
  Check(LList.Items[0].SubItems[1] <> '—', 'Existing index has a displayable date');
  Check(LList.Items[1].SubItems[1] = '—', 'Missing index has no invented date');
  Check(LForm.FindComponent('CreateProjectIndexScope') = nil, 'Creation uses list selection without a redundant scope combo');
  Check(LForm.FindComponent('CreateProjectIndexButton') = nil, 'One shared action replaces the separate create button');
  Check(Button('UpdateIndexButton').Enabled, 'Existing reference index can be updated');
  Check(Button('UpdateIndexButton').Caption = 'Aktualisieren', 'An existing selected index uses the update caption');
  Check(Button('DeleteIndexButton').Enabled, 'Existing reference index can be deleted');
  TDAISymbolIndexDialog.Show('group');
  Check(LList.Selected.Index = 2, 'The selected project-group row supplies the creation target');
  Check(Button('UpdateIndexButton').Enabled, 'A missing saved group index can be explicitly created');
  Check(Button('UpdateIndexButton').Caption = 'Index erstellen', 'A missing selected index uses the creation caption');
  Check(not Button('DeleteIndexButton').Enabled, 'An index cannot be deleted before it exists');
  Check(TDAISymbolService.BuildCount = 0, 'Selecting a missing index never starts a build');
  Button('UpdateIndexButton').Click;
  Check(TDAISymbolService.BuildCount = 1, 'One explicit button click starts one build');
  Check(TDAISymbolService.LastScope = 'group', 'Creation passes the chosen group scope');
  Check(TDAISymbolService.LastIdentity = 'snapshot-group', 'Creation uses the displayed project-group identity');
  Check(PollTimer.Enabled, 'Only an active job enables polling');
  Check(not Button('UpdateIndexButton').Enabled and not Button('DeleteIndexButton').Enabled,
    'Mutations are disabled while the manager owns an active job');
  Button('UpdateIndexButton').OnClick(Button('UpdateIndexButton'));
  Button('DeleteIndexButton').OnClick(Button('DeleteIndexButton'));
  Check((TDAISymbolService.BuildCount = 1) and (TDAISymbolService.DeleteCount = 0), 'Direct handlers cannot bypass a manager-owned active job');
  PollTimer.OnTimer(PollTimer);
  Check(not PollTimer.Enabled, 'Completed job stops polling');
  Check(TDAISymbolService.PollCount = 1, 'Job status is read once for completion');
  Check(TDAISymbolService.Existing[2], 'The completed group index is reflected in the refreshed list');
  Check(Button('UpdateIndexButton').Caption = 'Aktualisieren', 'The shared button switches to updating after successful creation');
  TDAISymbolIndexDialog.Show('project');
  Check(LList.Selected.Index = 3, 'Selecting the project row replaces the former creation combo');
  Check(Button('UpdateIndexButton').Enabled, 'The separate missing project index remains creatable');
  Button('UpdateIndexButton').Click;
  Check(TDAISymbolService.LastScope = 'project', 'Project creation passes project scope');
  LForm.Close;
  Check(not LForm.Visible, 'Closing the manager hides it without a modal loop');
  Check(not PollTimer.Enabled, 'A hidden manager does not poll');
  TDAISymbolIndexDialog.Show('project');
  Check(Manager = LForm, 'Reopening preserves the modeless form');
  Check(PollTimer.Enabled, 'Reopening resumes an outstanding job');
  PollTimer.OnTimer(PollTimer);
  Check(LList.Selected.Index = 3, 'An individual menu scope selects the matching row');
  Check(Button('DeleteIndexButton').Enabled, 'The newly created project index can be deleted');
  Button('DeleteIndexButton').Click;
  Check(TDAISymbolService.DeleteCount = 1, 'One delete click deletes one index');
  Check(TDAISymbolService.LastScope = 'project', 'Deletion targets the selected project scope');
  Check(TDAISymbolService.LastIdentity = 'snapshot-project', 'Deletion uses the displayed project identity');
  Check(not TDAISymbolService.Existing[3], 'Deletion is reflected in the metadata');
  Check(not Button('DeleteIndexButton').Enabled, 'A missing index cannot be deleted twice');
  Check(Button('UpdateIndexButton').Enabled, 'Deleting re-enables explicit creation through the shared button');
  Check(Button('UpdateIndexButton').Caption = 'Index erstellen', 'Deleting changes the shared action back to creation');
  TDAISymbolService.CompletionState := 'completed_with_errors';
  Button('UpdateIndexButton').Click;
  PollTimer.OnTimer(PollTimer);
  Check(not PollTimer.Enabled, 'Partial completion also stops polling');
  TDAISymbolService.FailListing := True;
  Button('RefreshIndexListButton').Click;
  Check(Manager = LForm, 'A metadata failure leaves the manager usable');
  TDAISymbolService.FailListing := False;
  TDAISymbolIndexDialog.Shutdown;
  Check(Manager = nil, 'Package shutdown destroys the form and timer');
  TDAISymbolService.Reset;
  TDAISymbolService.GroupAvailable := False;
  TDAISymbolService.ProjectAvailable := False;
  TDAISymbolIndexDialog.Show('group');
  Check(not Button('UpdateIndexButton').Enabled, 'Group creation is disabled without a saved target');
  Button('UpdateIndexButton').OnClick(Button('UpdateIndexButton'));
  TDAISymbolIndexDialog.Show('project');
  Check(not Button('UpdateIndexButton').Enabled, 'Project creation is disabled without a saved target');
  Button('UpdateIndexButton').OnClick(Button('UpdateIndexButton'));
  Check(TDAISymbolService.BuildCount = 0, 'Neither opening nor listing sends a build request');
  TDAISymbolIndexDialog.Shutdown;
end;

procedure TestSelectedCreation;
const
  CScopes: array[0..3] of string = ('delphi', 'getit', 'group', 'project');
var
  LButton: TButton;
begin
  for var LIndex := Low(CScopes) to High(CScopes) do
  begin
    TDAISymbolService.Reset;
    TDAISymbolIndexDialog.Show(CScopes[LIndex]);
    Check(Manager.FindComponent('CreateProjectIndexScope') = nil, 'Every scope uses the list selection without an extra combo');
    Check(Manager.FindComponent('CreateProjectIndexButton') = nil, 'Every scope uses the same create/update button');
    LButton := Button('UpdateIndexButton');
    Check(LButton.Enabled and (LButton.Caption = 'Index erstellen'), 'Each missing valid index scope is creatable through the shared action');
    Check(not Button('DeleteIndexButton').Enabled, 'Missing scopes cannot be deleted');
    Check(TDAISymbolService.BuildCount = 0, 'Opening a missing scope performs no implicit creation');
    LButton.Click;
    Check(TDAISymbolService.BuildCount = 1, 'One explicit shared-button click creates one index');
    Check(TDAISymbolService.LastScope = CScopes[LIndex], 'Creation targets exactly the selected index scope');
    Check(TDAISymbolService.LastIdentity = 'snapshot-' + CScopes[LIndex], 'Creation passes the selected row identity');
    PollTimer.OnTimer(PollTimer);
    Check(TDAISymbolService.Existing[LIndex], 'Completion updates the selected scope metadata');
    Check(LButton.Enabled and (LButton.Caption = 'Aktualisieren'), 'Successful creation changes the shared action to update');
    Check(Button('DeleteIndexButton').Enabled, 'An existing selected scope becomes deletable');
    LButton.Click;
    Check(TDAISymbolService.BuildCount = 2, 'The same shared action updates an existing index');
    Check(TDAISymbolService.LastScope = CScopes[LIndex], 'Updating retains the selected scope');
    Check(TDAISymbolService.LastIdentity = 'snapshot-' + CScopes[LIndex], 'Updating retains the selected identity');
    PollTimer.OnTimer(PollTimer);
    TDAISymbolIndexDialog.Shutdown;
  end;
end;

function LabelByName(const AName: string): TLabel;
begin
  Result := TLabel(Manager.FindComponent(AName));
  Check(Assigned(Result), 'The layout has its named wrapped label: ' + AName);
end;

function TextHeight(const ALabel: TLabel): Integer;
var
  LBitmap: TBitmap;
  LRect: TRect;
  LFlags: Cardinal;
begin
  LBitmap := TBitmap.Create;
  try
    LBitmap.SetSize(1, 1);
    LBitmap.Canvas.Font.Assign(ALabel.Font);
    LRect := Rect(0, 0, ALabel.ClientWidth, 0);
    LFlags := DT_CALCRECT or DT_EXPANDTABS;
    if ALabel.WordWrap then
      LFlags := LFlags or DT_WORDBREAK;
    if not ALabel.ShowAccelChar then
      LFlags := LFlags or DT_NOPREFIX;
    DrawText(LBitmap.Canvas.Handle, PChar(ALabel.Caption), Length(ALabel.Caption), LRect, LFlags);
    Result := LRect.Height;
  finally
    LBitmap.Free;
  end;
end;

procedure CheckWrappedLabel(const ALabel: TLabel; const APPI: Integer);
var
  LRequiredHeight: Integer;
begin
  LRequiredHeight := TextHeight(ALabel);
  Check(ALabel.AutoSize and ALabel.WordWrap, 'Label auto-size and wrapping are enabled at PPI ' + IntToStr(APPI));
  Check(ALabel.Width > 0, 'The wrapped label has a usable line width');
  Check(ALabel.Height >= LRequiredHeight, Format('%s reserves the full measured text height (%d >= %d) at PPI %d',
    [ALabel.Name, ALabel.Height, LRequiredHeight, APPI]));
  Check(ALabel.Height <= LRequiredHeight + 1, 'A wrapped label has no unused fixed-height text area');
  Check((ALabel.Left >= 0) and (ALabel.Top >= 0), 'The wrapped label starts inside its parent');
  Check(ALabel.Left + ALabel.Width <= ALabel.Parent.ClientWidth, 'The wrapped label fits the full parent width');
  Check(ALabel.Top + ALabel.Height <= ALabel.Parent.ClientHeight,
    Format('%s is vertically visible inside its auto-sized parent (%d <= %d) at PPI %d',
      [ALabel.Name, ALabel.Top + ALabel.Height, ALabel.Parent.ClientHeight, APPI]));
end;

procedure SaveLayoutPreview(const AFileName: string; const AForm: TForm = nil);
var
  LBitmap: TBitmap;
  LPNG: TPngImage;
begin
  if Assigned(AForm) then
    LBitmap := AForm.GetFormImage
  else
    LBitmap := Manager.GetFormImage;
  try
    LPNG := TPngImage.Create;
    try
      LPNG.Assign(LBitmap);
      LPNG.SaveToFile(AFileName);
    finally
      LPNG.Free;
    end;
  finally
    LBitmap.Free;
  end;
end;

procedure TestLayout;
const
  CIndexWarning = 'Deklarationsindex: seit der Erfassung geänderte und ungespeicherte Quellen können abweichen oder fehlen. ' +
    'Vor Verwendung den aktuellen Quelltext lesen. Bedingte Deklarationen sind nicht compilersemantisch aufgelöst.';
  CWidths: array[0..2] of Integer = (900, 1200, 900);
var
  LForm: TForm;
  LInformation, LProvider, LStatus: TLabel;
  LHeader, LFooter, LActions: TPanel;
  LFirstStatusHeight, LFirstHeaderHeight, LGap: Integer;
  LFontHeight96: Integer;
  LOutput: string;
begin
  TDAISymbolService.Reset;
  TDAISymbolService.Existing[0] := True;
  TDAISymbolService.FileCounts[0] := 2275;
  TDAISymbolService.SymbolCounts[0] := 228342;
  TDAISymbolService.SizeKnown[0] := True;
  TDAISymbolService.SizeBytes[0] := 1572864;
  TDAISymbolIndexDialog.Show;
  LForm := Manager;
  LInformation := LabelByName('IndexInformationLabel');
  LProvider := LabelByName('IndexProviderLabel');
  LStatus := LabelByName('IndexStatusLabel');
  LHeader := TPanel(LForm.FindComponent('IndexHeaderPanel'));
  LFooter := TPanel(LForm.FindComponent('IndexFooterPanel'));
  LActions := TPanel(LForm.FindComponent('IndexActionsPanel'));
  Check(Assigned(LHeader) and Assigned(LFooter) and Assigned(LActions), 'Header, footer and action layout panels exist');
  Check(LHeader.AutoSize and LFooter.AutoSize, 'Header and footer derive height from their visible children');
  Check((LHeader.Caption = '') and (LFooter.Caption = '') and (LActions.Caption = ''), 'Layout panel names are not rendered as visible captions');
  Check(LActions.ControlCount = 5, 'The single action row contains only create/update, delete, refresh, details and close');
  LStatus.Caption := CIndexWarning;
  LOutput := ExtractFilePath(ParamStr(0));
  LFontHeight96 := 0;
  for var LPPI in TArray<Integer>.Create(96, 144, 192) do
  begin
    LForm.ScaleForPPI(LPPI);
    // CurrentPPI queries the physical test monitor via GetDPIForWindow. The
    // explicit VCL scaling state is PixelsPerInch when exercising other DPIs.
    Check(LForm.PixelsPerInch = LPPI, 'The real VCL form is scaled to the tested PPI');
    if LPPI = 96 then
      LFontHeight96 := Abs(LStatus.Font.Height)
    else
      Check(Abs(LStatus.Font.Height) > LFontHeight96, 'DPI scenarios scale the actual text font in addition to control widths');
    LFirstStatusHeight := 0;
    LFirstHeaderHeight := 0;
    for var LStep := Low(CWidths) to High(CWidths) do
    begin
      LForm.ClientWidth := MulDiv(CWidths[LStep], LPPI, 96);
      LForm.Realign;
      LForm.Update;
      CheckWrappedLabel(LInformation, LPPI);
      CheckWrappedLabel(LProvider, LPPI);
      CheckWrappedLabel(LStatus, LPPI);
      Check(LStatus.Caption = CIndexWarning, 'The complete long status warning is retained while resizing');
      Check(LActions.ClientHeight <= MulDiv(56, LPPI, 96), 'The compact action panel reserves only one row at each DPI');
      for var LControlIndex := 0 to LActions.ControlCount - 1 do
      begin
        var LControl := LActions.Controls[LControlIndex];
        Check((LControl.Left >= 0) and (LControl.Top >= 0), 'Every action begins inside its panel at each width and DPI');
        Check(LControl.Top = LActions.Controls[0].Top, 'All actions share one row after removing the redundant creation controls');
        Check((LControl.Left + LControl.Width <= LActions.ClientWidth) and (LControl.Top + LControl.Height <= LActions.ClientHeight),
          Format('%s remains completely visible inside its action panel at width %d / PPI %d', [LControl.Name, CWidths[LStep], LPPI]));
      end;
      Check(LStatus.Top >= LActions.Top + LActions.Height, 'The wrapped status starts below the single action row');
      LGap := LProvider.Top - (LInformation.Top + LInformation.Height);
      Check((LGap >= 0) and (LGap <= MulDiv(10, LPPI, 96)), 'The provider follows the information text without a large vertical gap');
      Check(LHeader.ClientHeight - (LProvider.Top + LProvider.Height) <= MulDiv(16, LPPI, 96),
        'Header trailing space remains compact at all tested widths and DPI values');
      if LStep = 0 then
      begin
        LFirstStatusHeight := LStatus.Height;
        LFirstHeaderHeight := LHeader.Height;
        Check(LStatus.Height > LStatus.Canvas.TextHeight('Wq'), 'The long warning exercises multiple wrapped lines');
      end
      else if LStep = 2 then
      begin
        Check(LStatus.Height = LFirstStatusHeight, 'Returning to the narrow width restores the measured status height');
        Check(LHeader.Height = LFirstHeaderHeight, 'Returning to the narrow width restores the compact header height');
      end;
      if LStep < 2 then
        SaveLayoutPreview(TPath.Combine(LOutput, Format('Layout-%d-PPI-%d.png', [CWidths[LStep], LPPI])));
    end;
  end;
  LForm.ScaleForPPI(96);
  LForm.ClientWidth := 900;
  LForm.Update;
  CheckWrappedLabel(LInformation, 96);
  CheckWrappedLabel(LProvider, 96);
  CheckWrappedLabel(LStatus, 96);
  Check(TDAISymbolService.BuildCount = 0, 'Layout and preview rendering never create an index or send a model request');
  TDAISymbolIndexDialog.Shutdown;
end;

function ErrorDetailsForm: TForm;
begin
  Result := nil;
  for var LIndex := 0 to Screen.FormCount - 1 do
    if Screen.Forms[LIndex].Name = 'DAISymbolIndexDetailsForm' then
      Exit(Screen.Forms[LIndex]);
end;

procedure TestErrorDetails;
var
  LDetails: TForm;
  LMemo: TMemo;
  LStatus: TLabel;
  LList: TListView;
  LPreviousReads: Integer;
  LError: string;
begin
  TDAISymbolService.Reset;
  TDAISymbolService.Existing[0] := True;
  TDAISymbolService.ErrorCounts[0] := 501;
  TDAISymbolIndexDialog.Show('delphi');
  LStatus := LabelByName('IndexStatusLabel');
  Check(TDAISymbolService.ErrorsReadCount = 0, 'Opening the index manager does not load per-file error details');
  Check(Button('IndexErrorDetailsButton').Enabled, 'A stored failed-file count enables the details button');
  Check(Pos('501 Dateien nicht indiziert', LStatus.Caption) > 0, 'The selected index reports how many files were not indexed');
  Button('IndexErrorDetailsButton').Click;
  LDetails := ErrorDetailsForm;
  Check(Assigned(LDetails) and LDetails.Visible, 'Error details open in a separate modeless window');
  LMemo := TMemo(LDetails.FindComponent('IndexErrorsMemo'));
  Check(Assigned(LMemo) and LMemo.ReadOnly, 'The full error report is a read-only text control');
  Check(not LMemo.WordWrap and (LMemo.ScrollBars = ssBoth), 'Long paths and reasons can be scrolled in both directions');
  Check(TDAISymbolService.ErrorsReadCount = 2, 'More than 500 failures are loaded through all required pages');
  Check((Length(TDAISymbolService.ErrorOffsets) = 2) and (TDAISymbolService.ErrorOffsets[0] = 0) and
    (TDAISymbolService.ErrorOffsets[1] = 500), 'Error pages use consecutive backend offsets');
  Check(TDAISymbolService.LastErrorScope = 'delphi', 'Details refer to the selected index scope');
  Check(TDAISymbolService.LastErrorIdentity = 'snapshot-delphi', 'Every page uses the displayed index owner identity');
  Check(Pos('C:\Test\Ausgelassen\Unit00000.pas', LMemo.Text) > 0, 'The first full file path is included');
  Check(Pos('C:\Test\Ausgelassen\Unit00500.pas', LMemo.Text) > 0, 'The final page full file path is included');
  Check(Pos('501 Dateien nicht indiziert.', LMemo.Text) > 0, 'The complete report includes its full loaded count');
  SaveLayoutPreview(TPath.Combine(ExtractFilePath(ParamStr(0)), 'Error-Details.png'), LDetails);
  Check(Assigned(TButton(LDetails.FindComponent('CopyIndexErrorsButton')).OnClick), 'The complete report has an explicit copy command');
  Check(LDetails.FindComponent('CancelIndexJobButton') = nil, 'Error details do not introduce an index cancellation command');
  TDAISymbolService.ChangeErrorReportAfterFirstPage := True;
  Button('IndexErrorDetailsButton').Click;
  Check(Pos('Die Fehlerliste wurde während des Lesens geändert', LMemo.Text) > 0,
    'A changed report identifier rejects mixed pages even when their file count is unchanged');
  Check(Pos('C:\Test\Ausgelassen\Unit00500.pas', LMemo.Text) = 0, 'The replacement report page is rejected before its errors are appended');
  TDAISymbolService.ChangeErrorReportAfterFirstPage := False;
  LDetails.Close;
  Check(not LDetails.Visible and Manager.Visible, 'Closing details leaves the index manager open');
  LPreviousReads := TDAISymbolService.ErrorsReadCount;
  Manager.Close;
  TDAISymbolIndexDialog.Show('delphi');
  Check(TDAISymbolService.ErrorsReadCount = LPreviousReads, 'Reopening the manager still loads metadata only');
  Button('IndexErrorDetailsButton').Click;
  Check(ErrorDetailsForm = LDetails, 'Reopening details preserves the modeless details form');
  Check(TDAISymbolService.ErrorsReadCount = LPreviousReads + 2, 'Explicitly reopening reloads all persisted detail pages');
  Manager.Close;
  Check(not LDetails.Visible, 'Closing the manager hides its details window');
  TDAISymbolIndexDialog.Show('getit');
  LList := TListView(Manager.FindComponent('SymbolIndexList'));
  Check(not Button('IndexErrorDetailsButton').Enabled, 'An index without failures disables error details');
  Check(Pos('501 Dateien nicht indiziert', LStatus.Caption) = 0, 'Selecting a clean index clears the previous partial-build summary');
  LList.Items[0].Selected := True;
  TDAISymbolService.FailErrorsRead := True;
  Button('IndexErrorDetailsButton').Click;
  Check(Pos('Die Projektauswahl wurde geändert', LMemo.Text) > 0, 'A stale owner rejection is displayed in the copyable report');
  TDAISymbolService.FailErrorsRead := False;
  TDAISymbolIndexDialog.Shutdown;
  Check(ErrorDetailsForm = nil, 'Package shutdown frees the details window');

  TDAISymbolService.Reset;
  TDAISymbolService.ErrorCounts[3] := 1;
  LError := 'Parserfehler / Datenbankfehler:' + sLineBreak;
  for var LLine := 1 to 500 do
    LError := LError + Format('Diagnose %.4d: Diese vollständige Detailmeldung muss lesbar und ohne Kürzung kopierbar bleiben.', [LLine]) + sLineBreak;
  LError := LError + 'ENDE-DER-VOLLSTAENDIGEN-FEHLERMELDUNG';
  Check(Length(LError) > 32768, 'The detailed error fixture exceeds the legacy 32 KiB text boundary');
  TDAISymbolService.ErrorReason := LError;
  TDAISymbolIndexDialog.Show('project');
  Check(not TDAISymbolService.Existing[3], 'This case has no successful previous index');
  Check(Button('IndexErrorDetailsButton').Enabled, 'A failed first build still exposes its file error details');
  Button('IndexErrorDetailsButton').Click;
  LDetails := ErrorDetailsForm;
  LMemo := TMemo(LDetails.FindComponent('IndexErrorsMemo'));
  Check(Pos(LError, LMemo.Text) > 0, 'A reason beyond 32 KiB reaches the memo without truncation');
  Check(Pos('ENDE-DER-VOLLSTAENDIGEN-FEHLERMELDUNG', LMemo.Text) > 0, 'The full final error marker remains available for copying');
  Check(Pos('nicht lesbar', LMemo.Text) = 0, 'Parser and database errors retain their specific reasons');
  SaveLayoutPreview(TPath.Combine(ExtractFilePath(ParamStr(0)), 'Error-Details-LongReason.png'), LDetails);
  TDAISymbolIndexDialog.Shutdown;

  TDAISymbolService.Reset;
  TDAISymbolIndexDialog.Show('group');
  Check(not Button('IndexErrorDetailsButton').Enabled, 'Before the first error there are no details to load');
  TDAISymbolService.CompletionState := 'completed_with_errors';
  TDAISymbolService.ErrorCounts[2] := 2;
  Button('UpdateIndexButton').Click;
  PollTimer.OnTimer(PollTimer);
  LStatus := LabelByName('IndexStatusLabel');
  Check(Pos('Teilweise aktualisiert: 2 Dateien nicht indiziert', LStatus.Caption) > 0, 'Partial completion reports skipped-file count and details');
  Check(Button('IndexErrorDetailsButton').Enabled, 'Completed partial builds enable the details action');
  Check(TDAISymbolService.ErrorsReadCount = 0, 'Progress polling never loads per-file details implicitly');
  Button('IndexErrorDetailsButton').Click;
  Check(TDAISymbolService.LastErrorScope = 'group', 'Details after creation target the newly selected project-group index');
  TDAISymbolIndexDialog.Shutdown;

  TDAISymbolService.Reset;
  TDAISymbolService.DetailsAvailable[1] := True;
  TDAISymbolService.BuildStates[1] := 'incomplete';
  TDAISymbolService.BuildError := 'Der Indexauftrag wurde durch das Beenden der IDE unterbrochen. Datenbankabschluss nicht erreicht.';
  TDAISymbolIndexDialog.Show('getit');
  LList := TListView(Manager.FindComponent('SymbolIndexList'));
  Check(LList.Selected.SubItems[5] = 'Unvollständig', 'An incomplete persisted index state is translated for the list');
  Check(Button('IndexErrorDetailsButton').Enabled, 'A persisted general failure enables details without per-file errors');
  LStatus := LabelByName('IndexStatusLabel');
  Check(Pos('Index unvollständig', LStatus.Caption) > 0, 'Incomplete status is explained outside the details dialog');
  Check(Assigned(LList.OnDblClick), 'An index row can open its details with a double-click');
  LList.OnDblClick(LList);
  LDetails := ErrorDetailsForm;
  LMemo := TMemo(LDetails.FindComponent('IndexErrorsMemo'));
  Check(Pos('Letzter Indexauftrag: Unvollständig', LMemo.Text) > 0, 'Details identify the incomplete last build');
  Check(Pos(TDAISymbolService.BuildError, LMemo.Text) > 0, 'The general interruption reason is shown without requiring a file error');
  Check(Pos('Begonnen: ' + DateToStr(EncodeDate(2026, 9, 17)), LMemo.Text) > 0, 'The original build start date remains available months later');
  Check(Pos('Beendet: ' + DateToStr(EncodeDate(2026, 9, 17)), LMemo.Text) > 0, 'The persisted last build end date is displayed');
  Check(Pos('Keine einzelnen Dateifehler aufgezeichnet.', LMemo.Text) > 0, 'No recorded file errors do not hide a general build failure');
  SaveLayoutPreview(TPath.Combine(ExtractFilePath(ParamStr(0)), 'Error-Details-Incomplete.png'), LDetails);
  TDAISymbolIndexDialog.Shutdown;
  TDAISymbolIndexDialog.Show('getit');
  Button('IndexErrorDetailsButton').Click;
  LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
  Check(Pos(TDAISymbolService.BuildError, LMemo.Text) > 0, 'General failure details survive closing and recreating both forms');
  Check(TDAISymbolService.BuildCount = 0, 'Viewing historical incomplete status does not restart indexing');
  TDAISymbolIndexDialog.Shutdown;
end;

procedure TestUpdatingErrorReport;
var
  LList: TListView;
  LMemo: TMemo;
  LButton: TButton;
begin
  for var LState in TArray<string>.Create('building', 'queued', 'running') do
  begin
    TDAISymbolService.Reset;
    TDAISymbolService.Existing[0] := True;
    TDAISymbolService.ErrorCounts[0] := 2;
    TDAISymbolService.BuildStates[0] := LState;
    TDAISymbolIndexDialog.Show('delphi');
    LList := TListView(Manager.FindComponent('SymbolIndexList'));
    Check(not Button('UpdateIndexButton').Enabled, 'Updating is disabled for every active job state');
    Check(not Button('DeleteIndexButton').Enabled, 'Deleting an existing index is disabled for every active job state');
    Button('UpdateIndexButton').OnClick(Button('UpdateIndexButton'));
    Button('DeleteIndexButton').OnClick(Button('DeleteIndexButton'));
    Check((TDAISymbolService.BuildCount = 0) and (TDAISymbolService.DeleteCount = 0), 'Direct handlers cannot bypass active-job mutation guards');
    LButton := Button('IndexErrorDetailsButton');
    Check(not LButton.Enabled, 'A changing selected index report disables its details button');
    LButton.OnClick(LButton);
    LList.OnDblClick(LList);
    Check(TDAISymbolService.ErrorsReadCount = 0, 'Click and double-click guards prevent reading a changing selected report');
    Check(ErrorDetailsForm = nil, 'A changing selected report does not open a stale details window');
    TDAISymbolIndexDialog.Shutdown;

    TDAISymbolService.Reset;
    TDAISymbolService.ErrorCounts[0] := 2;
    TDAISymbolIndexDialog.Show('delphi');
    Check(Button('IndexErrorDetailsButton').Enabled, 'A report initially shown as complete can be requested');
    TDAISymbolService.BuildStates[0] := LState;
    Button('IndexErrorDetailsButton').Click;
    LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
    Check(Pos('Der Fehlerbericht wird noch aktualisiert', LMemo.Text) > 0, 'A build starting after the metadata snapshot is explained in the details window');
    Check(Pos('C:\Test\Ausgelassen\Unit00000.pas', LMemo.Text) = 0, 'A changing page is rejected before its file errors are appended');
    TDAISymbolIndexDialog.Shutdown;
  end;

  TDAISymbolService.Reset;
  TDAISymbolService.ErrorCounts[0] := 501;
  TDAISymbolService.ErrorStateAfterFirstPage := 'building';
  TDAISymbolIndexDialog.Show('delphi');
  Button('IndexErrorDetailsButton').Click;
  LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
  Check(TDAISymbolService.ErrorsReadCount = 2, 'This fixture reaches a second page with the same report identity and file count');
  Check(Pos('Der Fehlerbericht wird noch aktualisiert', LMemo.Text) > 0, 'A changing later page is rejected even with a stable report identifier');
  Check(Pos('C:\Test\Ausgelassen\Unit00500.pas', LMemo.Text) = 0, 'The changing second page is never appended');
  TDAISymbolIndexDialog.Shutdown;

  TDAISymbolService.Reset;
  TDAISymbolService.ErrorCounts[1] := 1;
  TDAISymbolIndexDialog.Show('group');
  Button('UpdateIndexButton').Click;
  Check(PollTimer.Enabled, 'An independent project-group build is running');
  LList := TListView(Manager.FindComponent('SymbolIndexList'));
  LList.Items[1].Selected := True;
  Check(Button('IndexErrorDetailsButton').Enabled, 'A completed reference report remains available while another scope builds');
  Button('IndexErrorDetailsButton').Click;
  Check(TDAISymbolService.LastErrorScope = 'getit', 'Details refer to the completed selected scope during an independent build');
  Check(TDAISymbolService.BuildCount = 1, 'Opening another scope report does not start or cancel indexing');
  TDAISymbolIndexDialog.Shutdown;
end;

procedure TestNumberFormatting;
var
  LList: TListView;
  LStatus: TLabel;
  LMemo: TMemo;
  LJSON: TJSONObject;
  LRawRow: TJSONObject;
  LLargeCount: string;
begin
  TDAISymbolService.Reset;
  for var LIndex := 0 to 3 do
    TDAISymbolService.Existing[LIndex] := True;
  TDAISymbolService.FileCounts[0] := 2275;
  TDAISymbolService.SymbolCounts[0] := 228342;
  TDAISymbolService.SizeKnown[0] := True;
  TDAISymbolService.SizeBytes[0] := 1572864;
  TDAISymbolService.SizeKnown[2] := True;
  TDAISymbolService.SizeBytes[2] := 1536;
  TDAISymbolService.SizeKnown[3] := True;
  TDAISymbolService.SizeBytes[3] := 0;
  TDAISymbolService.SymbolCounts[3] := 9007199254740993;
  TDAISymbolIndexDialog.Show('delphi');
  LList := TListView(Manager.FindComponent('SymbolIndexList'));
  Check(LList.Columns.Count = 7, 'The numeric presentation has seven columns');
  Check((LList.Columns[5].Caption = 'Größe') and (LList.Columns[6].Caption = 'Status'), 'Size appears immediately before status');
  for var LColumn := 3 to 5 do
    Check(LList.Columns[LColumn].Alignment = taRightJustify, 'File, declaration and size columns are right aligned');
  Check(LList.Items[0].SubItems[2] = FormatFloat('#,##0', 2275), 'File counts use the current thousands separator');
  Check(LList.Items[0].SubItems[3] = FormatFloat('#,##0', 228342), 'Declaration counts use the current thousands separator');
  Check(LList.Items[0].SubItems[4] = FormatFloat('#,##0.0', 1.5) + ' MB', 'A database of 1536 KiB displays MB with one local decimal place');
  Check(LList.Items[1].SubItems[4] = '—', 'A null database size is displayed as unknown');
  Check(LList.Items[2].SubItems[4] = FormatFloat('#,##0.0', 1.5) + ' KB', 'A small database displays KB with one local decimal place');
  Check(LList.Items[3].SubItems[4] = FormatFloat('#,##0.0', 0) + ' KB', 'A known zero-byte database remains distinct from an unknown size');
  LLargeCount := StringReplace('9|007|199|254|740|993', '|', string(FormatSettings.ThousandSeparator), [rfReplaceAll]);
  Check(LList.Items[3].SubItems[3] = LLargeCount, 'Int64 counts retain exact digits beyond Double precision on both architectures');
  LJSON := TDAISymbolService.ListIndexes;
  try
    LRawRow := TJSONObject(LJSON.GetValue<TJSONArray>('indexes').Items[0]);
    Check(LRawRow.GetValue('file_count') is TJSONNumber, 'The underlying file count remains a JSON number');
    Check(LRawRow.GetValue('file_count').Value = '2275', 'Formatting does not change the MCP-compatible numeric value');
    Check(LRawRow.GetValue('size_bytes').Value = '1572864', 'Byte counts remain unformatted in service metadata');
  finally
    LJSON.Free;
  end;
  TDAISymbolService.SizeBytes[0] := 1023 * 1024;
  Button('RefreshIndexListButton').Click;
  Check(LList.Items[0].SubItems[4] = FormatFloat('#,##0.0', 1023) + ' KB', 'Sizes below 1024 KB stay in KB');
  TDAISymbolService.SizeBytes[0] := 1024 * 1024;
  Button('RefreshIndexListButton').Click;
  Check(LList.Items[0].SubItems[4] = FormatFloat('#,##0.0', 1) + ' MB', 'The MB threshold begins at exactly 1024 KB');
  TDAISymbolService.OmitSize := True;
  Button('RefreshIndexListButton').Click;
  Check(LList.Items[0].SubItems[4] = '—', 'An absent size property is also displayed as unknown');
  TDAISymbolIndexDialog.Shutdown;

  TDAISymbolService.Reset;
  TDAISymbolService.FileCounts[2] := 12500;
  TDAISymbolIndexDialog.Show('group');
  Button('UpdateIndexButton').Click;
  TDAISymbolService.CompletionState := 'building';
  TDAISymbolService.ProcessedFiles := 2275;
  TDAISymbolService.TotalFiles := 12500;
  PollTimer.OnTimer(PollTimer);
  LStatus := LabelByName('IndexStatusLabel');
  Check(Pos(FormatFloat('#,##0', 2275) + ' / ' + FormatFloat('#,##0', 12500) + ' Dateien', LStatus.Caption) > 0,
    'Processed and total file progress counters use thousands separators');
  TDAISymbolService.CompletionState := 'completed_with_errors';
  TDAISymbolService.ErrorCounts[2] := 2275;
  PollTimer.OnTimer(PollTimer);
  Check(Pos(FormatFloat('#,##0', 2275) + ' Dateien nicht indiziert', LStatus.Caption) > 0, 'The completion error count is locally formatted');
  TDAISymbolService.BuildStates[2] := 'incomplete';
  Button('RefreshIndexListButton').Click;
  Check(Pos('Index unvollständig: ' + FormatFloat('#,##0', 2275), LStatus.Caption) > 0, 'An incomplete saved report formats its error count');
  TDAISymbolService.BuildStates[2] := 'error';
  Button('RefreshIndexListButton').Click;
  Check(Pos('Indexerstellung fehlgeschlagen: ' + FormatFloat('#,##0', 2275), LStatus.Caption) > 0, 'A failed saved report formats its error count');
  Button('IndexErrorDetailsButton').Click;
  LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
  Check(Pos(FormatFloat('#,##0', 2275) + ' Dateien nicht indiziert.', LMemo.Text) > 0, 'The full error report formats its final file count');
  Check(Pos(FormatFloat('#,##0', 1000) + '. C:\Test\Ausgelassen\Unit00999.pas', LMemo.Text) > 0,
    'File numbering in a long error report uses the same local thousands separator');
  TDAISymbolIndexDialog.Shutdown;
end;

procedure TestGlobalIndexErrors;
var
  LStatus: TLabel;
  LMemo: TMemo;
  LError: string;
begin
  TDAISymbolService.Reset;
  TDAISymbolService.BuildStates[0] := 'error';
  LError := '[FireDAC][Phys][SQLite] Datei kann nicht geöffnet werden: C:\Test\DelphiIndex.sqlite' + sLineBreak +
    StringOfChar('x', 40000) + ' ENDE-DES-VOLLSTAENDIGEN-INDEXFEHLERS';
  TDAISymbolService.RowErrors[0] := LError;
  TDAISymbolService.FailErrorsRead := True;
  TDAISymbolIndexDialog.Show('delphi');
  LStatus := LabelByName('IndexStatusLabel');
  Check(Button('IndexErrorDetailsButton').Enabled, 'A global row error enables details without a persisted error count or details flag');
  Check(Pos('[FireDAC][Phys][SQLite]', LStatus.Caption) > 0, 'The short status includes the concrete global database failure');
  Check(Length(LStatus.Caption) < 320, 'A large global error cannot expand the status label to the entire exception length');
  Button('IndexErrorDetailsButton').Click;
  LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
  Check(Pos(LError, LMemo.Text) > 0, 'The complete row error survives failure to read the persisted error report');
  Check(Pos('ENDE-DES-VOLLSTAENDIGEN-INDEXFEHLERS', LMemo.Text) > 0, 'The final marker of a global error beyond 32 KiB remains available');
  Check(Pos('Fehler beim Laden der Details:', LMemo.Text) > 0, 'The secondary persistence/read failure is shown alongside the original index error');
  TDAISymbolIndexDialog.Shutdown;

  TDAISymbolService.Reset;
  TDAISymbolService.Existing[0] := True;
  TDAISymbolIndexDialog.Show('delphi');
  Button('UpdateIndexButton').Click;
  TDAISymbolService.CompletionState := 'error';
  TDAISymbolService.JobError := '[FireDAC][Phys][SQLite] Duplicate column name: last_build_state';
  TDAISymbolService.RowErrors[0] := TDAISymbolService.JobError;
  TDAISymbolService.BuildStates[0] := 'error';
  PollTimer.OnTimer(PollTimer);
  LStatus := LabelByName('IndexStatusLabel');
  Check(Pos('Indexerstellung fehlgeschlagen: ' + TDAISymbolService.JobError, LStatus.Caption) > 0,
    'A failed JobStatus.error overrides the generic completion message in the status');
  Check(Button('IndexErrorDetailsButton').Enabled, 'Backend-reported global failure metadata keeps details available after the failed update');
  Button('IndexErrorDetailsButton').Click;
  LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
  Check(Pos(TDAISymbolService.JobError, LMemo.Text) > 0, 'A stale empty persisted report cannot hide the global index status error');
  Check(Pos('Fehler aus dem Indexstatus:', LMemo.Text) > 0, 'The source of the preserved global error is labelled clearly');
  TDAISymbolIndexDialog.Shutdown;

  TDAISymbolService.Reset;
  TDAISymbolService.Existing[0] := True;
  TDAISymbolIndexDialog.Show('delphi');
  Button('UpdateIndexButton').Click;
  TDAISymbolService.CompletionState := 'error';
  TDAISymbolService.JobError := '[SQLite] Originaler Fehler beim Starten des Indexauftrags';
  TDAISymbolService.FailListing := True;
  PollTimer.OnTimer(PollTimer);
  LStatus := LabelByName('IndexStatusLabel');
  Check(Pos(TDAISymbolService.JobError, LStatus.Caption) > 0, 'A subsequent list refresh failure does not replace the original job error');
  Check(Pos('Die Indexliste konnte nicht aktualisiert werden:', LStatus.Caption) > 0, 'The secondary list refresh failure remains distinguishable');
  Check(not PollTimer.Enabled, 'A failed terminal job remains stopped even when metadata refresh fails');
  TDAISymbolIndexDialog.Shutdown;

  for var LState in TArray<string>.Create('error', 'cancelled') do
  begin
    TDAISymbolService.Reset;
    TDAISymbolService.BuildStates[0] := LState;
    TDAISymbolService.DetailsAvailable[0] := True;
    TDAISymbolIndexDialog.Show('delphi');
    Button('IndexErrorDetailsButton').Click;
    LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
    Check(Pos('wurde nicht aufgezeichnet', LMemo.Text) > 0, 'An unavailable general reason is explicitly identified instead of leaving an unexplained empty report');
    TDAISymbolIndexDialog.Shutdown;
  end;

  TDAISymbolService.Reset;
  TDAISymbolService.BuildStates[0] := 'error';
  TDAISymbolService.DetailsAvailable[0] := True;
  TDAISymbolService.BuildError := '[SQLite] Fehlerbericht konnte wegen einer gesperrten Indexdatei nicht gespeichert werden.';
  TDAISymbolService.StorageWarning := 'Dieser Fehlerbericht konnte nicht vollständig in der Indexdatei gespeichert werden und ist nur für den aktuellen IDE-Lauf verfügbar.';
  TDAISymbolIndexDialog.Show('delphi');
  Button('IndexErrorDetailsButton').Click;
  LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
  Check(Pos(TDAISymbolService.StorageWarning, LMemo.Text) > 0, 'The full non-persistence warning is visible in the details report');
  Check(Pos('nur für den aktuellen IDE-Lauf verfügbar', LMemo.Text) > 0, 'The temporary lifetime of a runtime-only report is explicit');
  Check(Pos(TDAISymbolService.BuildError, LMemo.Text) > 0, 'The lifetime warning does not replace the original storage failure');
  Manager.Close;
  TDAISymbolIndexDialog.Show('delphi');
  Button('IndexErrorDetailsButton').Click;
  LMemo := TMemo(ErrorDetailsForm.FindComponent('IndexErrorsMemo'));
  Check(Pos(TDAISymbolService.StorageWarning, LMemo.Text) > 0, 'Reopening details keeps the runtime-only lifetime warning visible');
  TDAISymbolIndexDialog.Shutdown;
end;

begin
  try
    Application.Initialize;
    TestManager;
    TestSelectedCreation;
    TestLayout;
    TestErrorDetails;
    TestUpdatingErrorReport;
    TestNumberFormatting;
    TestGlobalIndexErrors;
    Writeln('DAI symbol dialog: ', GChecks, ' checks passed.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      TDAISymbolIndexDialog.Shutdown;
      ExitCode := 1;
    end;
  end;
end.
