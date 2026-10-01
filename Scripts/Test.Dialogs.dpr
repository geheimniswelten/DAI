program TestDialogs;

{$APPTYPE CONSOLE}

// The production UI and window guard units run unchanged against isolated VCL
// forms from this process. No IDE, settings, registry, agent or project is used.
uses
  System.Classes,
  System.JSON,
  System.SysUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Winapi.Windows,
  h5u.DAI.UI,
  h5u.DAI.Windows.Inspection;

type
  TButtonAccess = class(TButton);
  TDialogFixture = class(TForm)
  private
    FTimer: TTimer;
    FButton: TButton;
    FHidden: TButton;
    FDisabled: TButton;
    FLabel: TLabel;
    FStatic: TStaticText;
    FGroup: TGroupBox;
    FInput: TEdit;
    FSecretLabel: TLabel;
    FPanel: TPanel;
    FScenario: Integer;
    FStage: Integer;
    FToken: string;
    FError: string;
    FClickCount: Integer;
    FReentrantDenied: Boolean;
    procedure Tick(Sender: TObject);
    procedure Clicked(Sender: TObject);
    function Snapshot: string;
    procedure RejectClick(const AToken, AButtonName, ADescription: string);
    procedure RejectClose(const AToken, ADescription: string; const AResult: Integer = mrCancel);
    procedure Details;
    procedure Integrity;
    procedure WorkerAccess;
  public
    constructor CreateFixture(const AScenario: Integer);
  end;
  TDAIPermissionFixture = class(TDialogFixture);

var CheckCount: Integer;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function NamedItem(const AItems: TJSONArray; const AName: string): TJSONObject;
var LItem: TJSONValue;
begin
  Result := nil;
  for LItem in AItems do
    if SameText(TJSONObject(LItem).GetValue<string>('name'), AName) then
      Exit(TJSONObject(LItem));
end;

constructor TDialogFixture.CreateFixture(const AScenario: Integer);
begin
  inherited CreateNew(nil);
  FScenario := AScenario;
  Name := 'FixtureModal';
  Caption := 'DAI isolated dialog regression';
  Width := 480;
  Height := 270;
  Position := poScreenCenter;
  FPanel := TPanel.Create(Self);
  FPanel.Parent := Self;
  FPanel.Name := 'ButtonPanel';
  FPanel.SetBounds(12, 155, 420, 55);
  FPanel.Caption := '';
  FButton := TButton.Create(Self);
  FButton.Parent := FPanel;
  FButton.Name := 'AcceptButton';
  FButton.Caption := 'Accept';
  FButton.ModalResult := mrOk;
  FButton.SetBounds(8, 10, 90, 28);
  FButton.OnClick := Clicked;
  FHidden := TButton.Create(Self);
  FHidden.Parent := FPanel;
  FHidden.Name := 'HiddenButton';
  FHidden.Visible := False;
  FDisabled := TButton.Create(Self);
  FDisabled.Parent := FPanel;
  FDisabled.Name := 'DisabledButton';
  FDisabled.Enabled := False;
  FDisabled.SetBounds(115, 10, 90, 28);
  FLabel := TLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.Name := 'MessageLabel';
  FLabel.Caption := 'Public dialog text: Grüße 日本語';
  FLabel.SetBounds(12, 10, 350, 20);
  FStatic := TStaticText.Create(Self);
  FStatic.Parent := Self;
  FStatic.Name := 'StaticMessage';
  FStatic.Caption := 'Readonly status';
  FStatic.SetBounds(12, 35, 160, 20);
  FGroup := TGroupBox.Create(Self);
  FGroup.Parent := Self;
  FGroup.Name := 'PublicGroup';
  FGroup.Caption := 'Public group';
  FGroup.SetBounds(12, 60, 160, 70);
  FInput := TEdit.Create(Self);
  FInput.Parent := Self;
  FInput.Name := 'UserInput';
  FInput.Text := 'PRIVATE-INPUT-MARKER';
  FInput.SetBounds(200, 65, 190, 24);
  FSecretLabel := TLabel.Create(Self);
  FSecretLabel.Parent := Self;
  FSecretLabel.Name := 'ApiKeyLabel';
  FSecretLabel.Caption := 'PRIVATE-CREDENTIAL-MARKER';
  FSecretLabel.SetBounds(200, 95, 190, 20);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50;
  FTimer.OnTimer := Tick;
end;

function TDialogFixture.Snapshot: string;
var LJson: TJSONObject;
begin
  LJson := TDAIUIService.InspectActiveDialog;
  try
    Check(LJson.GetValue<Boolean>('available'), 'active visible fixture is available');
    Result := LJson.GetValue<string>('snapshot_token');
    Check(Result <> '', 'opaque token provided');
  finally LJson.Free; end;
end;

procedure TDialogFixture.RejectClick(const AToken, AButtonName, ADescription: string);
var LDenied: Boolean; LJson: TJSONObject;
begin
  LDenied := False;
  try
    LJson := TDAIUIService.ClickDialogButton(AToken, AButtonName);
    LJson.Free;
  except
    on E: EInvalidOperation do LDenied := True;
    on E: EArgumentException do LDenied := True;
  end;
  Check(LDenied, ADescription);
end;

procedure TDialogFixture.RejectClose(const AToken, ADescription: string; const AResult: Integer);
var LDenied: Boolean; LJson: TJSONObject;
begin
  LDenied := False;
  try
    LJson := TDAIUIService.CloseDialog(AToken, AResult);
    LJson.Free;
  except
    on E: EInvalidOperation do LDenied := True;
    on E: EArgumentException do LDenied := True;
  end;
  Check(LDenied, ADescription);
end;

procedure TDialogFixture.Clicked(Sender: TObject);
var LJson: TJSONObject;
begin
  Inc(FClickCount);
  try
    LJson := TDAIUIService.CloseDialog(FToken, mrCancel);
    LJson.Free;
  except on E: EInvalidOperation do FReentrantDenied := True; end;
end;

procedure TDialogFixture.Details;
var LJson, LItem: TJSONObject; LOldToken: string;
begin
  LJson := TDAIUIService.InspectActiveDialog;
  try
    Check(LJson.GetValue<Boolean>('available'), 'visible modal is available');
    Check(LJson.GetValue<Boolean>('modal') and LJson.GetValue<Boolean>('visible'), 'modal and visible flags');
    Check(LJson.GetValue<string>('name') = Name, 'exact form name');
    Check(LJson.GetValue<string>('class_name') = ClassName, 'exact form class');
    Check(LJson.GetValue<string>('caption') = Caption, 'form caption');
    Check(LJson.GetValue<Integer>('expires_after_ms') = 30000, 'real 30-second expiry advertised');
    Check(not LJson.GetValue<Boolean>('controls_truncated'), 'small fixture not truncated');
    LItem := NamedItem(LJson.GetValue<TJSONArray>('buttons'), 'AcceptButton');
    Check(Assigned(LItem), 'normal button enumerated');
    Check(LItem.GetValue<Boolean>('visible') and LItem.GetValue<Boolean>('enabled'), 'button usable flags');
    Check(LItem.GetValue<Integer>('modal_result') = mrOk, 'button modal result');
    LItem := NamedItem(LJson.GetValue<TJSONArray>('buttons'), 'HiddenButton');
    Check(not LItem.GetValue<Boolean>('visible'), 'hidden button state exposed');
    LItem := NamedItem(LJson.GetValue<TJSONArray>('buttons'), 'DisabledButton');
    Check(not LItem.GetValue<Boolean>('enabled'), 'disabled button state exposed');
    LItem := NamedItem(LJson.GetValue<TJSONArray>('labels'), 'MessageLabel');
    Check(LItem.GetValue<string>('caption') = FLabel.Caption, 'Unicode readonly text preserved');
    Check(LItem.GetValue<Boolean>('read_only'), 'label readonly flag');
    Check(Assigned(NamedItem(LJson.GetValue<TJSONArray>('labels'), 'StaticMessage')), 'static text enumerated');
    Check(Assigned(NamedItem(LJson.GetValue<TJSONArray>('labels'), 'PublicGroup')), 'group caption enumerated');
    Check(not LJson.ToJSON.Contains('PRIVATE-INPUT-MARKER'), 'input contents omitted');
    Check(not LJson.ToJSON.Contains('PRIVATE-CREDENTIAL-MARKER'), 'credential label contents omitted');
    Check(not LJson.ToJSON.Contains('ApiKeyLabel'), 'sensitive control name omitted');
    LOldToken := LJson.GetValue<string>('snapshot_token');
  finally LJson.Free; end;
  FToken := Snapshot;
  Check(FToken <> LOldToken, 'new inspection produces fresh token');
  RejectClick(LOldToken, 'AcceptButton', 'previous inspection invalidated');
  RejectClick('', 'AcceptButton', 'empty token rejected');
  RejectClick('wrong-token', 'AcceptButton', 'foreign token rejected');
  RejectClick(FToken, '', 'empty button name rejected');
  RejectClick(FToken, 'MissingButton', 'unknown button rejected');
  RejectClick(FToken, 'HiddenButton', 'hidden button cannot be clicked');
  RejectClick(FToken, 'DisabledButton', 'disabled button cannot be clicked');
  RejectClose(FToken, 'zero modal result rejected', 0);
  RejectClose(FToken, 'negative modal result rejected', -1);
  RejectClose(FToken, 'overflow modal result rejected', 65536);
  LJson := TDAIUIService.CloseDialog(FToken, 65535);
  try
    Check(LJson.GetValue<Boolean>('close_requested'), 'valid close requested');
    Check(LJson.GetValue<Integer>('modal_result') = 65535, 'maximum valid modal result preserved');
  finally LJson.Free; end;
  RejectClose(FToken, 'close consumes token before returning');
end;

procedure TDialogFixture.Integrity;
var LJson: TJSONObject; LOther: TForm;
begin
  FToken := Snapshot; FButton.Name := 'ChangedButton';
  RejectClick(FToken, 'AcceptButton', 'renamed button is stale'); FButton.Name := 'AcceptButton';
  FToken := Snapshot; FButton.Caption := 'Changed caption';
  RejectClick(FToken, 'AcceptButton', 'changed button caption is stale'); FButton.Caption := 'Accept';
  FToken := Snapshot; FButton.ModalResult := mrCancel;
  RejectClick(FToken, 'AcceptButton', 'changed modal result is stale'); FButton.ModalResult := mrOk;
  FToken := Snapshot; FButton.Visible := False;
  RejectClick(FToken, 'AcceptButton', 'newly hidden button rejected'); FButton.Visible := True;
  FToken := Snapshot; FButton.Enabled := False;
  RejectClick(FToken, 'AcceptButton', 'newly disabled button rejected'); FButton.Enabled := True;
  FToken := Snapshot; FPanel.Enabled := False;
  RejectClick(FToken, 'AcceptButton', 'disabled ancestor rejected'); FPanel.Enabled := True;
  FToken := Snapshot; TButtonAccess(FButton).RecreateWnd;
  RejectClick(FToken, 'AcceptButton', 'recreated button HWND is stale');
  FToken := Snapshot; Name := 'RenamedModal';
  RejectClose(FToken, 'changed form name rejected'); Name := 'FixtureModal';
  FToken := Snapshot; Caption := 'Changed modal title';
  RejectClose(FToken, 'changed form caption rejected'); Caption := 'DAI isolated dialog regression';
  FToken := Snapshot; FLabel.Caption := 'Changed readonly text';
  RejectClose(FToken, 'changed readonly label invalidates snapshot'); FLabel.Caption := 'Public dialog text: Grüße 日本語';
  FToken := Snapshot; FStatic.Caption := 'Changed status';
  RejectClick(FToken, 'AcceptButton', 'changed readonly static text invalidates snapshot'); FStatic.Caption := 'Readonly status';
  FToken := Snapshot; FGroup.Caption := 'Changed group';
  RejectClose(FToken, 'changed readonly group caption invalidates snapshot'); FGroup.Caption := 'Public group';
  FToken := Snapshot; FLabel.Name := 'RenamedLabel';
  RejectClose(FToken, 'changed readonly label identity rejected'); FLabel.Name := 'MessageLabel';
  FToken := Snapshot; FLabel.Visible := False;
  RejectClose(FToken, 'removed visible readonly text rejected'); FLabel.Visible := True;
  FToken := Snapshot;
  LOther := TForm.CreateNew(nil);
  try
    FButton.Parent := LOther;
    RejectClick(FToken, 'AcceptButton', 'button moved outside snapshotted form rejected');
    FButton.Parent := FPanel;
  finally LOther.Free; end;
  FToken := Snapshot; FButton.Free;
  FButton := TButton.Create(Self); FButton.Parent := FPanel;
  FButton.Name := 'AcceptButton'; FButton.Caption := 'Accept'; FButton.ModalResult := mrOk;
  FButton.OnClick := Clicked;
  RejectClick(FToken, 'AcceptButton', 'freed and replaced same-name button rejected');
  Check(FClickCount = 0, 'all stale checks precede actions');
  FToken := Snapshot;
  FInput.Text := 'CHANGED-PRIVATE-INPUT'; FSecretLabel.Caption := 'CHANGED-PRIVATE-CREDENTIAL';
  LJson := TDAIUIService.ClickDialogButton(FToken, 'acceptbutton');
  try Check(LJson.GetValue<Boolean>('clicked'), 'input-only changes preserve valid snapshot');
  finally LJson.Free; end;
  Check(FClickCount = 1, 'actual button OnClick executes exactly once');
  Check(FReentrantDenied, 'token already consumed inside OnClick');
  RejectClick(FToken, 'AcceptButton', 'button click token cannot be replayed');
end;

procedure TDialogFixture.WorkerAccess;
var LWorker: TThread; LInspected, LClicked: Boolean;
begin
  LInspected := False; LClicked := False;
  LWorker := TThread.CreateAnonymousThread(
    procedure
    var LJson: TJSONObject; LToken: string;
    begin
      LJson := TDAIUIService.InspectActiveDialog;
      try
        LInspected := LJson.GetValue<Boolean>('available');
        LToken := LJson.GetValue<string>('snapshot_token');
      finally LJson.Free; end;
      FToken := LToken;
      LJson := TDAIUIService.ClickDialogButton(LToken, 'AcceptButton');
      try LClicked := LJson.GetValue<Boolean>('clicked'); finally LJson.Free; end;
    end);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start; LWorker.WaitFor;
    Check(not Assigned(LWorker.FatalException), 'worker calls marshal without exception');
    Check(LInspected and LClicked, 'worker inspection and click succeeded');
    Check(FClickCount = 1, 'worker click uses real main-thread button event');
    Check(FReentrantDenied, 'worker click consumes token before event');
  finally LWorker.Free; end;
end;

procedure TDialogFixture.Tick(Sender: TObject);
var LJson: TJSONObject; LNative: HWND;
begin
  FTimer.Enabled := False;
  try
    case FScenario of
      0: Details;
      1: Integrity;
      2: WorkerAccess;
      3:
        begin
          TDAIWindowService.RegisterPermissionWindow(Handle);
          try
            LJson := TDAIUIService.InspectActiveDialog;
            try Check(not LJson.GetValue<Boolean>('available'), 'registered permission window inaccessible'); finally LJson.Free; end;
          finally TDAIWindowService.UnregisterPermissionWindow(Handle); end;
        end;
      4:
        begin
          Name := 'PasswordDialog';
          LJson := TDAIUIService.InspectActiveDialog;
          try Check(not LJson.GetValue<Boolean>('available'), 'sensitive named dialog inaccessible'); finally LJson.Free; end;
        end;
      5:
        begin
          LJson := TDAIUIService.InspectActiveDialog;
          try Check(not LJson.GetValue<Boolean>('available'), 'permission dialog class inaccessible'); finally LJson.Free; end;
        end;
      6:
        begin
          LNative := CreateWindowEx(0, 'STATIC', 'DAI native fixture overlay', WS_OVERLAPPEDWINDOW or WS_VISIBLE,
            0, 0, 300, 120, Handle, 0, HInstance, nil);
          Check(LNative <> 0, 'isolated native overlay created');
          try
            SetActiveWindow(LNative);
            LJson := TDAIUIService.InspectActiveDialog;
            try Check(not LJson.GetValue<Boolean>('available'), 'covering native root window blocks VCL snapshot'); finally LJson.Free; end;
          finally DestroyWindow(LNative); SetActiveWindow(Handle); end;
          FToken := Snapshot;
        end;
      7:
        begin
          if FStage = 0 then
          begin
            FToken := Snapshot;
            FStage := 1; FTimer.Interval := 31000; FTimer.Enabled := True;
            Writeln('Checking real 30-second snapshot expiry...'); Flush(Output);
            Exit;
          end;
          RejectClick(FToken, 'AcceptButton', 'real 30-second token expiry enforced');
          Check(FClickCount = 0, 'expired token executes no button event');
        end;
      8: FToken := Snapshot;
    end;
    if ModalResult = mrNone then ModalResult := mrCancel;
  except
    on E: Exception do begin FError := E.ClassName + ': ' + E.Message; ModalResult := mrCancel; end;
  end;
end;

procedure RunModal(const AScenario: Integer; out AToken: string);
var LForm: TDialogFixture; LResult: Integer;
begin
  if AScenario = 5 then LForm := TDAIPermissionFixture.CreateFixture(AScenario)
  else LForm := TDialogFixture.CreateFixture(AScenario);
  try
    LResult := LForm.ShowModal;
    if LForm.FError <> '' then raise Exception.Create(LForm.FError);
    AToken := LForm.FToken;
    if AScenario = 0 then Check(LResult = 65535, 'CloseDialog sets real modal result')
    else if AScenario in [1, 2] then Check(LResult = mrOk, 'ClickDialogButton sets real modal result');
  finally LForm.Free; end;
end;

var
  LScenario: Integer;
  LToken: string;
  LJson: TJSONObject;
  LDenied: Boolean;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    LJson := TDAIUIService.InspectActiveDialog;
    try Check(not LJson.GetValue<Boolean>('available'), 'no modal dialog yields unavailable'); finally LJson.Free; end;
    for LScenario := 0 to 8 do RunModal(LScenario, LToken);
    LDenied := False;
    try LJson := TDAIUIService.CloseDialog(LToken, mrCancel); LJson.Free;
    except on E: EInvalidOperation do LDenied := True; end;
    Check(LDenied, 'destroyed form snapshot cannot close a replacement or stale object');
    TDAIUIService.Shutdown;
    Writeln('PASS: ', CheckCount, ' isolated native dialog snapshot/action checks (', SizeOf(Pointer) * 8, '-bit)');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
