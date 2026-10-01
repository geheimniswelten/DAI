unit h5u.DAI.UI;

interface

uses
  System.JSON;

type
  TDAIUIService = class sealed
  public
    class function InspectActiveDialog: TJSONObject; static;
    class function ClickDialogButton(const ASnapshotToken: string; const AButtonName: string): TJSONObject; static;
    class function CloseDialog(const ASnapshotToken: string; const AModalResult: Integer): TJSONObject; static;
    class function ShowMessage(const ATitle: string; const AText: string; const AKind: string): TJSONObject; static;
    class function AskInput(const ATitle: string; const APrompt: string; const ADefaultValue: string): TJSONObject; static;
    class function ShowBalloon(const ATitle: string; const AText: string; const ATimeoutMs: Integer): TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Hash,
  System.Math,
  System.SysUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.StdCtrls,
  Winapi.Windows,
  h5u.DAI.Windows.Inspection;

const
  CDialogSnapshotLifetimeMs = 30000;
  CMaximumDialogControls = 256;
  CMaximumDialogDepth = 16;
  CMaximumDialogTextCharacters = 4096;

type
  TControlAccess = class(TControl);

  TDialogButtonSnapshot = class
  public
    Button: TCustomButton;
    Name: string;
    ButtonClassName: string;
    Caption: string;
    HandleAllocated: Boolean;
    Handle: HWND;
    ModalResult: TModalResult;
  end;

  TDialogSnapshot = class(TComponent)
  private
    FForm: TCustomForm;
    FFormName: string;
    FFormClass: string;
    FFormCaption: string;
    FTextFingerprint: string;
    FHandleAllocated: Boolean;
    FHandle: HWND;
    FToken: string;
    FExpiresAt: UInt64;
    FButtons: TObjectList<TDialogButtonSnapshot>;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(const AForm: TCustomForm); reintroduce;
    destructor Destroy; override;
    procedure AddButton(const AButton: TCustomButton);
    function RequireForm(const ASnapshotToken: string): TCustomForm;
    function RequireButton(const AButtonName: string): TCustomButton;
    property Token: string read FToken;
  end;

var
  GBalloonHint: TBalloonHint;
  GDialogSnapshot: TDialogSnapshot;

procedure RunOnUIThread(const AAction: TThreadProcedure);
begin
  if GetCurrentThreadId = MainThreadID then
    AAction()
  else
    TThread.Synchronize(nil, AAction);
end;

function SensitiveName(const AName: string): Boolean;
var
  LName: string;
begin
  LName := LowerCase(AName);
  Result := LName.Contains('password') or LName.Contains('passwd') or LName.Contains('token') or LName.Contains('secret') or
    LName.Contains('credential') or LName.Contains('apikey') or LName.Contains('api_key');
end;

function ProtectedDialog(const AForm: TCustomForm): Boolean;
var
  LClassName: string;
  LName: string;
begin
  LClassName := LowerCase(AForm.ClassName);
  LName := LowerCase(AForm.Name);
  Result := LClassName.Contains('daipermission') or LClassName.Contains('permissionsdialog') or LName.Contains('daipermission') or
    LName.Contains('permissionsdialog') or SensitiveName(AForm.Name) or SensitiveName(AForm.ClassName);
  if not Result and AForm.HandleAllocated then
    Result := TDAIWindowService.IsProtectedPermissionWindow(AForm.Handle);
end;

function ActiveModalDialog: TCustomForm;
var
  LActiveWindow: HWND;
begin
  Result := Screen.ActiveCustomForm;
  if not Assigned(Result) then
    Exit;
  if (csDestroying in Result.ComponentState) or not Result.Visible or not Result.Enabled or not (fsModal in Result.FormState) then
    Exit(nil);
  if ProtectedDialog(Result) then
    Exit(nil);

  // A native task dialog may cover the VCL form retained by Screen.ActiveCustomForm.
  LActiveWindow := GetActiveWindow;
  if (LActiveWindow <> 0) and Result.HandleAllocated then
    if GetAncestor(LActiveWindow, GA_ROOT) <> Result.Handle then
      Exit(nil);
end;

function VisibleControl(const AControl: TControl; const AForm: TCustomForm): Boolean;
var
  LControl: TControl;
begin
  LControl := AControl;
  while Assigned(LControl) do
  begin
    if (csDestroying in LControl.ComponentState) or not LControl.Visible then
      Exit(False);
    if LControl = AForm then
      Exit(True);
    LControl := LControl.Parent;
  end;
  Result := False;
end;

function EnabledControl(const AControl: TControl; const AForm: TCustomForm): Boolean;
var
  LControl: TControl;
begin
  LControl := AControl;
  while Assigned(LControl) do
  begin
    if not LControl.Enabled then
      Exit(False);
    if LControl = AForm then
      Exit(True);
    LControl := LControl.Parent;
  end;
  Result := False;
end;

function LimitedCaption(const AControl: TControl): string;
begin
  Result := TControlAccess(AControl).Caption;
  if Length(Result) > CMaximumDialogTextCharacters then
    SetLength(Result, CMaximumDialogTextCharacters);
end;

function DialogTextFingerprint(const AForm: TCustomForm): string;
var
  LBuilder: TStringBuilder;
  LSeenCount: Integer;

  procedure AppendText(const AValue: string);
  begin
    LBuilder.Append(Length(AValue)).Append(':').Append(AValue);
  end;

  procedure ReadLabels(const AParent: TWinControl; const ADepth: Integer; const AParentSensitive: Boolean);
  var
    LControl: TControl;
    LIndex: Integer;
    LSensitive: Boolean;
  begin
    if ADepth > CMaximumDialogDepth then
      Exit;
    for LIndex := 0 to AParent.ControlCount - 1 do
    begin
      if LSeenCount >= CMaximumDialogControls then
        Exit;
      Inc(LSeenCount);
      LControl := AParent.Controls[LIndex];
      if csDestroying in LControl.ComponentState then
        Continue;
      LSensitive := AParentSensitive or SensitiveName(LControl.Name) or SensitiveName(LControl.ClassName);
      if not LSensitive and ((LControl is TCustomLabel) or (LControl is TCustomStaticText) or (LControl is TCustomGroupBox)) then
        if VisibleControl(LControl, AForm) then
        begin
          AppendText(LControl.Name);
          AppendText(LControl.ClassName);
          AppendText(TControlAccess(LControl).Caption);
        end;
      if LControl is TWinControl then
        ReadLabels(TWinControl(LControl), ADepth + 1, LSensitive);
    end;
  end;
begin
  LBuilder := TStringBuilder.Create;
  try
    AppendText(TControlAccess(AForm).Caption);
    LSeenCount := 0;
    ReadLabels(AForm, 0, False);
    Result := THashSHA2.GetHashString(LBuilder.ToString);
  finally
    LBuilder.Free;
  end;
end;

constructor TDialogSnapshot.Create(const AForm: TCustomForm);
var
  LGuid: TGUID;
begin
  inherited Create(nil);
  FButtons := TObjectList<TDialogButtonSnapshot>.Create(True);
  FForm := AForm;
  FFormName := AForm.Name;
  FFormClass := AForm.ClassName;
  FFormCaption := TControlAccess(AForm).Caption;
  FTextFingerprint := DialogTextFingerprint(AForm);
  FHandleAllocated := AForm.HandleAllocated;
  FHandle := 0;
  if FHandleAllocated then
    FHandle := AForm.Handle;
  CreateGUID(LGuid);
  FToken := GUIDToString(LGuid);
  FExpiresAt := GetTickCount64 + CDialogSnapshotLifetimeMs;
  AForm.FreeNotification(Self);
end;

destructor TDialogSnapshot.Destroy;
var
  LButton: TDialogButtonSnapshot;
begin
  if Assigned(FForm) then
    FForm.RemoveFreeNotification(Self);
  if Assigned(FButtons) then
    for LButton in FButtons do
      if Assigned(LButton.Button) then
        LButton.Button.RemoveFreeNotification(Self);
  FreeAndNil(FButtons);
  inherited;
end;

procedure TDialogSnapshot.Notification(AComponent: TComponent; Operation: TOperation);
var
  LButton: TDialogButtonSnapshot;
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = FForm then
  begin
    FForm := nil;
    FExpiresAt := 0;
  end;
  if Assigned(FButtons) then
    for LButton in FButtons do
      if AComponent = LButton.Button then
        LButton.Button := nil;
end;

procedure TDialogSnapshot.AddButton(const AButton: TCustomButton);
var
  LButton: TDialogButtonSnapshot;
begin
  LButton := TDialogButtonSnapshot.Create;
  try
    LButton.Button := AButton;
    LButton.Name := AButton.Name;
    LButton.ButtonClassName := AButton.ClassName;
    LButton.Caption := TControlAccess(AButton).Caption;
    LButton.HandleAllocated := AButton.HandleAllocated;
    if LButton.HandleAllocated then
      LButton.Handle := AButton.Handle;
    LButton.ModalResult := AButton.ModalResult;
    AButton.FreeNotification(Self);
    FButtons.Add(LButton);
  except
    AButton.RemoveFreeNotification(Self);
    LButton.Free;
    raise;
  end;
end;

function TDialogSnapshot.RequireForm(const ASnapshotToken: string): TCustomForm;
begin
  if (ASnapshotToken = '') or (ASnapshotToken <> FToken) or (GetTickCount64 >= FExpiresAt) then
    raise EInvalidOperation.Create('Die Dialog-Momentaufnahme ist ungültig oder abgelaufen. Lesen Sie den aktiven Dialog erneut.');
  Result := ActiveModalDialog;
  if not Assigned(Result) or (Result <> FForm) then
    raise EInvalidOperation.Create('Der aktive modale Dialog hat sich geändert. Lesen Sie den Dialog erneut.');
  if (Result.Name <> FFormName) or (Result.ClassName <> FFormClass) or (Result.HandleAllocated <> FHandleAllocated) then
    raise EInvalidOperation.Create('Der Dialog stimmt nicht mehr mit der Momentaufnahme überein.');
  if FHandleAllocated then
    if Result.Handle <> FHandle then
      raise EInvalidOperation.Create('Das Dialogfenster wurde seit der Momentaufnahme neu erstellt.');
  if (TControlAccess(Result).Caption <> FFormCaption) or (DialogTextFingerprint(Result) <> FTextFingerprint) then
    raise EInvalidOperation.Create('Titel oder Dialogtext haben sich seit der Momentaufnahme geändert. Lesen Sie den Dialog erneut.');
end;

function TDialogSnapshot.RequireButton(const AButtonName: string): TCustomButton;
var
  LButton: TDialogButtonSnapshot;
  LMatch: TDialogButtonSnapshot;
begin
  if Trim(AButtonName) = '' then
    raise EArgumentException.Create('Ein Buttonname aus der Dialog-Momentaufnahme ist erforderlich.');
  LMatch := nil;
  for LButton in FButtons do
    if SameText(LButton.Name, AButtonName) then
    begin
      if Assigned(LMatch) then
        raise EInvalidOperation.Create('Der Buttonname ist im Dialog nicht eindeutig.');
      LMatch := LButton;
    end;
  if not Assigned(LMatch) then
    raise EInvalidOperation.Create('Der angegebene Button ist nicht mehr in der Dialog-Momentaufnahme verfügbar.');
  if not Assigned(LMatch.Button) then
    raise EInvalidOperation.Create('Der angegebene Button ist nicht mehr in der Dialog-Momentaufnahme verfügbar.');
  Result := LMatch.Button;
  if (csDestroying in Result.ComponentState) or (Result.Name <> LMatch.Name) or (Result.ClassName <> LMatch.ButtonClassName) or
    (TControlAccess(Result).Caption <> LMatch.Caption) or (Result.ModalResult <> LMatch.ModalResult) or
    (Result.HandleAllocated <> LMatch.HandleAllocated) then
    raise EInvalidOperation.Create('Der Button hat sich seit der Dialog-Momentaufnahme geändert.');
  if LMatch.HandleAllocated then
    if Result.Handle <> LMatch.Handle then
      raise EInvalidOperation.Create('Das Buttonfenster wurde seit der Momentaufnahme neu erstellt.');
  if not VisibleControl(Result, FForm) or not EnabledControl(Result, FForm) then
    raise EInvalidOperation.Create('Der Button ist nicht sichtbar oder nicht aktiviert.');
end;

function RequireDialogSnapshot(const ASnapshotToken: string): TCustomForm;
begin
  if not Assigned(GDialogSnapshot) then
    raise EInvalidOperation.Create('Es liegt keine Dialog-Momentaufnahme vor. Lesen Sie den aktiven Dialog zuerst.');
  Result := GDialogSnapshot.RequireForm(ASnapshotToken);
end;

class function TDAIUIService.InspectActiveDialog: TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  try
    RunOnUIThread(
      procedure
      var
        LButtons: TJSONArray;
        LForm: TCustomForm;
        LLabels: TJSONArray;
        LSeenCount: Integer;
        LTruncated: Boolean;

        procedure ReadControls(const AParent: TWinControl; const ADepth: Integer; const AParentSensitive: Boolean);
        var
          LControl: TControl;
          LIndex: Integer;
          LItem: TJSONObject;
          LSensitive: Boolean;
        begin
          if ADepth > CMaximumDialogDepth then
          begin
            LTruncated := True;
            Exit;
          end;
          for LIndex := 0 to AParent.ControlCount - 1 do
          begin
            if LSeenCount >= CMaximumDialogControls then
            begin
              LTruncated := True;
              Exit;
            end;
            Inc(LSeenCount);
            LControl := AParent.Controls[LIndex];
            if csDestroying in LControl.ComponentState then
              Continue;
            LSensitive := AParentSensitive or SensitiveName(LControl.Name) or SensitiveName(LControl.ClassName);
            if not LSensitive and (LControl is TCustomButton) then
            begin
              LItem := TJSONObject.Create;
              LItem.AddPair('name', LControl.Name);
              LItem.AddPair('class_name', LControl.ClassName);
              LItem.AddPair('caption', LimitedCaption(LControl));
              LItem.AddPair('visible', TJSONBool.Create(VisibleControl(LControl, LForm)));
              LItem.AddPair('enabled', TJSONBool.Create(EnabledControl(LControl, LForm)));
              LItem.AddPair('modal_result', TJSONNumber.Create(TCustomButton(LControl).ModalResult));
              LButtons.AddElement(LItem);
              GDialogSnapshot.AddButton(TCustomButton(LControl));
            end
            else if not LSensitive and ((LControl is TCustomLabel) or (LControl is TCustomStaticText) or (LControl is TCustomGroupBox)) then
            begin
              LItem := TJSONObject.Create;
              LItem.AddPair('name', LControl.Name);
              LItem.AddPair('class_name', LControl.ClassName);
              LItem.AddPair('caption', LimitedCaption(LControl));
              LItem.AddPair('visible', TJSONBool.Create(VisibleControl(LControl, LForm)));
              LItem.AddPair('read_only', TJSONBool.Create(True));
              LLabels.AddElement(LItem);
            end;
            if LControl is TWinControl then
              ReadControls(TWinControl(LControl), ADepth + 1, LSensitive);
          end;
        end;
      begin
        FreeAndNil(GDialogSnapshot);
        LResult := TJSONObject.Create;
        LForm := ActiveModalDialog;
        LResult.AddPair('available', TJSONBool.Create(Assigned(LForm)));
        if not Assigned(LForm) then
          Exit;
        GDialogSnapshot := TDialogSnapshot.Create(LForm);
        try
          LResult.AddPair('snapshot_token', GDialogSnapshot.Token);
          LResult.AddPair('expires_after_ms', TJSONNumber.Create(CDialogSnapshotLifetimeMs));
          LResult.AddPair('name', LForm.Name);
          LResult.AddPair('class_name', LForm.ClassName);
          LResult.AddPair('caption', LimitedCaption(LForm));
          LResult.AddPair('visible', TJSONBool.Create(True));
          LResult.AddPair('modal', TJSONBool.Create(True));
          LButtons := TJSONArray.Create;
          LResult.AddPair('buttons', LButtons);
          LLabels := TJSONArray.Create;
          LResult.AddPair('labels', LLabels);
          LSeenCount := 0;
          LTruncated := False;
          ReadControls(LForm, 0, False);
          LResult.AddPair('controls_truncated', TJSONBool.Create(LTruncated));
        except
          FreeAndNil(GDialogSnapshot);
          raise;
        end;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIUIService.ClickDialogButton(const ASnapshotToken: string; const AButtonName: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  try
    RunOnUIThread(
      procedure
      var
        LButton: TCustomButton;
      begin
        RequireDialogSnapshot(ASnapshotToken);
        LButton := GDialogSnapshot.RequireButton(AButtonName);
        LResult := TJSONObject.Create;
        LResult.AddPair('clicked', TJSONBool.Create(True));
        LResult.AddPair('button_name', LButton.Name);
        LResult.AddPair('modal_result', TJSONNumber.Create(LButton.ModalResult));
        // OnClick can close, free or replace the dialog and reenter this service.
        FreeAndNil(GDialogSnapshot);
        LButton.Click;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIUIService.CloseDialog(const ASnapshotToken: string; const AModalResult: Integer): TJSONObject;
var
  LResult: TJSONObject;
begin
  if (AModalResult < 1) or (AModalResult > 65535) then
    raise EArgumentException.Create('modal_result muss zwischen 1 und 65535 liegen.');
  LResult := nil;
  try
    RunOnUIThread(
      procedure
      var
        LForm: TCustomForm;
      begin
        LForm := RequireDialogSnapshot(ASnapshotToken);
        LResult := TJSONObject.Create;
        LResult.AddPair('close_requested', TJSONBool.Create(True));
        LResult.AddPair('modal_result', TJSONNumber.Create(AModalResult));
        FreeAndNil(GDialogSnapshot);
        LForm.ModalResult := AModalResult;
      end);
    Result := LResult;
  except
    LResult.Free;
    raise;
  end;
end;

class function TDAIUIService.AskInput(const ATitle: string; const APrompt: string; const ADefaultValue: string): TJSONObject;
var
  LAccepted: Boolean;
  LValue: string;
begin
  LValue := ADefaultValue;
  LAccepted := InputQuery(ATitle, APrompt, LValue);
  Result := TJSONObject.Create;
  Result.AddPair('accepted', TJSONBool.Create(LAccepted));
  Result.AddPair('value', LValue);
end;

class procedure TDAIUIService.Shutdown;
begin
  RunOnUIThread(
    procedure
    begin
      FreeAndNil(GDialogSnapshot);
      FreeAndNil(GBalloonHint);
    end);
end;

class function TDAIUIService.ShowBalloon(const ATitle: string; const AText: string; const ATimeoutMs: Integer): TJSONObject;
var
  LControl: TWinControl;
begin
  LControl := Application.MainForm;
  if not Assigned(LControl) then
    raise EInvalidOperation.Create('Das Hauptfenster der IDE ist nicht verfügbar.');

  FreeAndNil(GBalloonHint);
  GBalloonHint := TBalloonHint.Create(nil);
  GBalloonHint.Title := ATitle;
  GBalloonHint.Description := AText;
  GBalloonHint.Delay := 0;
  GBalloonHint.HideAfter := EnsureRange(ATimeoutMs, 1000, 60000);
  GBalloonHint.ShowHint(LControl);

  Result := TJSONObject.Create;
  Result.AddPair('shown', TJSONBool.Create(True));
  Result.AddPair('timeout_ms', TJSONNumber.Create(GBalloonHint.HideAfter));
end;

class function TDAIUIService.ShowMessage(const ATitle: string; const AText: string; const AKind: string): TJSONObject;
var
  LDialogType: TMsgDlgType;
  LModalResult: Integer;
begin
  if SameText(AKind, 'warning') then
    LDialogType := mtWarning
  else if SameText(AKind, 'error') then
    LDialogType := mtError
  else if SameText(AKind, 'confirmation') then
    LDialogType := mtConfirmation
  else
    LDialogType := mtInformation;

  LModalResult := TaskMessageDlg(ATitle, AText, LDialogType, [mbOK], 0);
  Result := TJSONObject.Create;
  Result.AddPair('shown', TJSONBool.Create(True));
  Result.AddPair('modal_result', TJSONNumber.Create(LModalResult));
end;

initialization
  GBalloonHint := nil;
  GDialogSnapshot := nil;

finalization
  TDAIUIService.Shutdown;

end.
