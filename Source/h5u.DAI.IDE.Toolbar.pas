unit h5u.DAI.IDE.Toolbar;

interface

type
  TDAIIDEToolbar = class sealed
  private
    class var FUpdateAvailable: Boolean;
    class var FUpdateVersion: string;
  public
    // The IDE owns the UI thread; callers must not marshal these during teardown.
    class procedure Install; static;
    class procedure Refresh; static;
    class procedure CheckRegistrations; static;
    // Optional result from a future update check; no network access here.
    class procedure SetUpdateAvailable(const AAvailable: Boolean; const AVersion: string = ''); static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Actions,
  System.Classes,
  System.JSON,
  System.SysUtils,
  System.Types,
  Winapi.CommCtrl,
  Winapi.Windows,
  ToolsAPI,
  Vcl.ActnList,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Vcl.ImgList,
  Vcl.Menus,
  h5u.DAI.Clients.Registration,
  h5u.DAI.Localization,
  h5u.DAI.Log,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Manager,
  h5u.DAI.Runtime,
  h5u.DAI.Settings,
  h5u.DAI.Symbols.Dialog,
  h5u.DAI.Symbols.Service;

type
  TDAIServerGlyphState = (sgInactive, sgActive, sgError, sgRecentAccess, sgEarlierAccess, sgNotRegistered, sgRegistrationUpdate, sgUpdateAvailable);

const
  CDAIActionName = 'DAIServerToggleAction';
  CDAIButtonName = 'DAIServerToolButton';
  // Standard VCL Tag survives toolbar streaming even when the IDE clears Name.
  CDAIButtonTag = $44414931;
  // New identifiers replace earlier glyphs even within the same IDE session.
  CDAIImageIds: array[TDAIServerGlyphState] of string = ('h5u.DAI.ServerGlyph.v4.Inactive', 'h5u.DAI.ServerGlyph.v4.Active',
    'h5u.DAI.ServerGlyph.v4.Error', 'h5u.DAI.ServerGlyph.v4.RecentAccess', 'h5u.DAI.ServerGlyph.v4.EarlierAccess',
    'h5u.DAI.ServerGlyph.v4.NotRegistered', 'h5u.DAI.ServerGlyph.v4.RegistrationUpdate', 'h5u.DAI.ServerGlyph.v4.UpdateAvailable');
  CDAIImageColors: array[TDAIServerGlyphState] of TColor = ($00808080, $004AA52A, $003636D9, $0000D0FF, $000B86B8, $00B04B91, $002B8CE6, $00D78324);
  CDAIImageSizes: array[0..4] of Integer = (16, 20, 24, 32, 48);

type
  TDAIActionAccess = class(TAction);
  TDAIControlActionLinkAccess = class(TControlActionLink);
  TDAIToolButtonAccess = class(TToolButton);

  TDAIToolbarController = class;

  // The IDE can retain a local notifier interface across Unregister. It owns no
  // controller or VCL object; Detach retires the weak receiver before shutdown.
  TDAIToolbarReadNotifier = class(TNotifierObject, IOTANotifier, INTAReadToolbarNotifier, INTAToolbarStreamNotifier, INTAToolbarStreamNotifier190)
  private
    FController: TDAIToolbarController;
  public
    procedure AfterSave; reintroduce; overload;
    procedure BeforeSave; reintroduce; overload;
    procedure AfterSave(Toolbar: TWinControl); overload;
    procedure BeforeSave(Toolbar: TWinControl); overload;
    constructor Create(AController: TDAIToolbarController);
    procedure Detach;
    procedure FindMethodInstance(Reader: TReader; const MethodName: string; var Method: TMethod; var Error: Boolean);
    procedure SetName(Reader: TReader; Component: TComponent; var Name: string; var Handled: Boolean);
    procedure ReadError(Reader: TReader; const Message: string; var Handled: Boolean);
    procedure ToolbarLoaded(Toolbar: TWinControl);
    procedure BeforeLoad(Toolbar: TWinControl);
  end;

  // Separate weak notifications survive RemoveUI's own notification cleanup.
  TDAIStreamedButtonCapture = class(TComponent)
  private
    FButton: TToolButton;
    FToolbar: TToolBar;
    FRoot: TComponent;
    FAmbiguous: Boolean;
    FConsumed: Boolean;
    FSeen: Boolean;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;
    procedure Clear;
    procedure Capture(AButton: TToolButton; AToolbar: TToolBar; ARoot: TComponent);
    procedure Consume;
    function Ready: Boolean;
    property Button: TToolButton read FButton;
    property Toolbar: TToolBar read FToolbar;
    property Root: TComponent read FRoot;
  end;

  TDAIToolbarController = class(TComponent)
  private
    FTimer: TTimer;
    FReadNotifier: TDAIToolbarReadNotifier;
    FReadNotifierInterface: IOTANotifier;
    FReadNotifierServices: INTAServices;
    FReadNotifierIndex: Integer;
    FStreamCapture: TDAIStreamedButtonCapture;
    FToolbar: TToolBar;
    FActionList: TCustomActionList;
    FAction: TAction;
    FButton: TToolButton;
    FPopup: TPopupMenu;
    FToggleItem: TMenuItem;
    FOptionsItem: TMenuItem;
    FResetItem: TMenuItem;
    FIDEPermissionItem: TMenuItem;
    FProjectPermissionItem: TMenuItem;
    FIndexItems: array[0..3] of TMenuItem;
    FManageIndexesItem: TMenuItem;
    FImages: array[TDAIServerGlyphState] of Integer;
    FCallbackDepth: Integer;
    FBusy: Boolean;
    FRefreshing: Boolean;
    FShuttingDown: Boolean;
    FLastInstallError: string;
    FActionError: string;
    FRegistrationChecked: Boolean;
    FRegistrationDirty: Boolean;
    FRegistrationVersion: Integer;
    FRegistrationServerActive: Boolean;
    FRegistrationManual: Boolean;
    FRegistrationHealth: TDAIRegistrationHealth;
    FRegistrationDetails: string;
    FPermissionChecked: Boolean;
    FPermissionVersion: Integer;
    FPermissionProjectKey: string;
    FIDEPermissionSummary: string;
    FProjectPermissionSummary: string;
    procedure LeaveCallback;
    procedure RemoveUI(const APreserveButton: TToolButton = nil);
    procedure RemoveActionButtons;
    procedure RemoveMarkedButtons(const APreserveButton: TToolButton = nil);
    procedure RemoveLegacyButtons(const AAllowSingle: Boolean = False);
    procedure EnsureReadNotifier;
    procedure RetireReadNotifier;
    procedure CaptureReadButton(Reader: TReader; Component: TComponent; const AName: string);
    procedure BeginToolbarRead(AToolbar: TWinControl);
    function RestoredButton(AToolbar: TToolBar; AActionList: TCustomActionList): TToolButton;
    function IsMarkedButton(AButton: TToolButton; AToolbar: TToolBar; AActionList: TCustomActionList): Boolean;
    function MarkedButton(AToolbar: TToolBar; AActionList: TCustomActionList): TToolButton;
    procedure ReportError(const AError: string);
    procedure InstallImages(const AServices: INTAServices; AImages: TCustomImageList);
    procedure CreatePopup;
    procedure PopupOpening(Sender: TObject);
    procedure EnsureOwnButtonFitsHorizontally;
    procedure EnsureInstalled;
    procedure UpdateRegistrationStatus;
    procedure UpdatePermissionStatus;
    procedure UpdateStatus;
    procedure TimerTick(Sender: TObject);
    procedure ToggleServer(Sender: TObject);
    procedure OpenOptions(Sender: TObject);
    procedure ResetSessionPermissions(Sender: TObject);
    procedure OpenIndexes(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create; reintroduce;
    destructor Destroy; override;
    procedure ActivateReadHooks;
    procedure Refresh;
    procedure Shutdown;
  end;

var
  GController: TDAIToolbarController;

function PermissionSummaryCaption(const ASummary: string): string;
begin
  // PermissionManager's summaries are protocol data; translate only their presentation.
  if ASummary = 'kein Projekt' then
    Exit(DAIText('kein Projekt', 'no project', 'aucun projet', 'プロジェクトなし'));
  if ASummary = 'gesperrt' then
    Exit(DAIText('gesperrt', 'blocked', 'bloqué', 'アクセス不可'));
  if ASummary = 'nachfragen' then
    Exit(DAIText('nachfragen', 'ask', 'demander', '確認する'));
  if ASummary = 'lesen' then
    Exit(DAIText('lesen', 'read', 'lecture', '読み取り'));
  if ASummary = 'schreiben' then
    Exit(DAIText('schreiben', 'write', 'écriture', '書き込み'));
  if ASummary = 'Vollzugriff' then
    Exit(DAIText('Vollzugriff', 'full access', 'accès complet', 'フルアクセス'));
  if ASummary = 'Status unbekannt' then
    Exit(DAIText('Status unbekannt', 'status unknown', 'état inconnu', '状態不明'));
  Result := ASummary;
end;

function RegistrationDetailsCaption(const ADetails: string): string;

  procedure TranslateSuffix(const AGerman, AEnglish, AFrench, AJapanese: string);
  begin
    if Result.EndsWith(AGerman) then
      Result := Copy(Result, 1, Length(Result) - Length(AGerman)) + DAIText(AGerman, AEnglish, AFrench, AJapanese);
  end;

begin
  // Preserve the technical client/profile prefix and unknown diagnostics verbatim.
  Result := ADetails;
  TranslateSuffix('Keine Registrierung für die aktuellen Verbindungseinstellungen gefunden.',
    'No registration found for the current connection settings.',
    'Aucune inscription trouvée pour les paramètres de connexion actuels.',
    '現在の接続設定に対応する登録が見つかりません。');
  TranslateSuffix('Passend registriert.', 'Registration is current.', 'Inscription à jour.', '現在の設定で登録済みです。');
  TranslateSuffix('Registrierung oder Starthelfer aktualisieren.', 'Update the registration or launcher.',
    'Mettez à jour l’inscription ou le lanceur.', '登録または起動ヘルパーを更新してください。');
  TranslateSuffix('Registrierung konnte nicht eindeutig geprüft werden; DAI-Optionen öffnen.',
    'Registration could not be verified; open the DAI options.',
    'Impossible de vérifier l’inscription ; ouvrez les options DAI.', '登録を確認できませんでした。DAI オプションを開いてください。');
  TranslateSuffix('Registrierung, Delphi-Skill oder Starthelfer aktualisieren.',
    'Update the registration, Delphi skill or launcher.', 'Mettez à jour l’inscription, le skill Delphi ou le lanceur.',
    '登録、Delphi スキル、または起動ヘルパーを更新してください。');
  TranslateSuffix('Vorhandenen Delphi-Skill in den DAI-Optionen prüfen.',
    'Check the existing Delphi skill in the DAI options.', 'Vérifiez le skill Delphi existant dans les options DAI.',
    '既存の Delphi スキルを DAI オプションで確認してください。');
  TranslateSuffix('Vorhandene Codex-Registrierung in den DAI-Optionen prüfen.',
    'Check the existing Codex registration in the DAI options.', 'Vérifiez l’inscription Codex existante dans les options DAI.',
    '既存の Codex 登録を DAI オプションで確認してください。');
  TranslateSuffix('Registrierungen konnten nicht geprüft werden; DAI-Optionen öffnen.',
    'Registrations could not be checked; open the DAI options.',
    'Impossible de vérifier les inscriptions ; ouvrez les options DAI.', '登録を確認できませんでした。DAI オプションを開いてください。');
end;

function IndexMenuCaption(const AIndex: Integer): string;
begin
  case AIndex of
    0: Result := DAIText('Index: Delphi / ToolsAPI', 'Index: Delphi / ToolsAPI', 'Index : Delphi / ToolsAPI', 'インデックス: Delphi / ToolsAPI');
    1: Result := DAIText('Index: GetIt', 'Index: GetIt', 'Index : GetIt', 'インデックス: GetIt');
    2: Result := DAIText('Index: Projektgruppe', 'Index: Project group', 'Index : Groupe de projets', 'インデックス: プロジェクトグループ');
    3: Result := DAIText('Index: Projekt', 'Index: Project', 'Index : Projet', 'インデックス: プロジェクト');
  else
    Result := '';
  end;
end;

function DAIGetModuleHandleExW(const AFlags: DWORD; const AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExW';

procedure RequireMainThread;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create(DAIText('Die DAI-Werkzeugleiste muss auf dem IDE-Hauptthread verwaltet werden.',
      'The DAI toolbar must be managed on the IDE main thread.',
      'La barre d’outils DAI doit être gérée sur le thread principal de l’IDE.',
      'DAI ツールバーは IDE のメインスレッドで管理する必要があります。'));
end;

function IDEMenuTracking: Boolean;
var
  LInfo: TGUIThreadInfo;
begin
  LInfo := Default(TGUIThreadInfo);
  LInfo.cbSize := SizeOf(LInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, LInfo) and
    ((LInfo.flags and (GUI_INMENUMODE or GUI_POPUPMENUMODE or GUI_SYSTEMMENUMODE)) <> 0);
end;

procedure UnregisterToolbarReadNotifier(const AServices: INTAServices; const AIndex: Integer);
var
  LModule: HMODULE;
begin
  if not Assigned(AServices) or (AIndex < 0) then
    Exit;
  try
    AServices.UnregisterToolbarNotifier(AIndex);
  except
    on E: Exception do
    begin
      // The already detached receiver can be retained by the IDE after failure.
      // Only this exceptional path pins its code; normal reload remains unpinned.
      DAIGetModuleHandleExW($00000001 or $00000004, PWideChar(@RequireMainThread), LModule);
      TDAILog.Error(DAIText('DAI-Toolbar-Notifier konnte nicht abgemeldet werden: ',
        'Could not unregister the DAI toolbar notifier: ',
        'Impossible de désinscrire le notificateur de la barre d’outils DAI : ',
        'DAI ツールバー通知の登録を解除できませんでした: ') + E.ClassName + ': ' + E.Message);
    end;
  end;
end;

constructor TDAIToolbarReadNotifier.Create(AController: TDAIToolbarController);
begin
  inherited Create;
  FController := AController;
end;

procedure TDAIToolbarReadNotifier.Detach;
begin
  FController := nil;
end;

procedure TDAIToolbarReadNotifier.FindMethodInstance(Reader: TReader; const MethodName: string; var Method: TMethod; var Error: Boolean);
begin
end;

procedure TDAIToolbarReadNotifier.SetName(Reader: TReader; Component: TComponent; var Name: string; var Handled: Boolean);
begin
  if Assigned(FController) then
    FController.CaptureReadButton(Reader, Component, Name);
  // Leave Name and Handled untouched. The IDE normalizes toolbutton names after
  // this callback, and preserving them here can collide with an existing button.
end;

procedure TDAIToolbarReadNotifier.ReadError(Reader: TReader; const Message: string; var Handled: Boolean);
begin
end;

procedure TDAIToolbarReadNotifier.AfterSave;
begin
end;

procedure TDAIToolbarReadNotifier.BeforeSave;
begin
end;

procedure TDAIToolbarReadNotifier.AfterSave(Toolbar: TWinControl);
begin
end;

procedure TDAIToolbarReadNotifier.BeforeSave(Toolbar: TWinControl);
begin
end;

procedure TDAIToolbarReadNotifier.ToolbarLoaded(Toolbar: TWinControl);
begin
  // No VCL mutation inside the reader. The timer's Refresh validates after the
  // IDE has assigned its public toolbar pointer, which is nil during ReadComponents.
end;

procedure TDAIToolbarReadNotifier.BeforeLoad(Toolbar: TWinControl);
begin
  if Assigned(FController) then
    FController.BeginToolbarRead(Toolbar);
end;

destructor TDAIStreamedButtonCapture.Destroy;
begin
  Clear;
  inherited;
end;

procedure TDAIStreamedButtonCapture.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = FButton then
    FButton := nil;
  if AComponent = FToolbar then
    FToolbar := nil;
  if AComponent = FRoot then
    FRoot := nil;
end;

procedure TDAIStreamedButtonCapture.Clear;
begin
  if Assigned(FButton) then
    FButton.RemoveFreeNotification(Self);
  if Assigned(FToolbar) then
    FToolbar.RemoveFreeNotification(Self);
  if Assigned(FRoot) then
    FRoot.RemoveFreeNotification(Self);
  FButton := nil;
  FToolbar := nil;
  FRoot := nil;
  FAmbiguous := False;
  FConsumed := False;
  FSeen := False;
end;

procedure TDAIStreamedButtonCapture.Capture(AButton: TToolButton; AToolbar: TToolBar; ARoot: TComponent);
begin
  if FConsumed then
    Clear;
  if FAmbiguous then
    Exit;
  if FSeen then
  begin
    if (FButton <> AButton) or (FToolbar <> AToolbar) or (FRoot <> ARoot) then
      FAmbiguous := True;
    Exit;
  end;
  FButton := AButton;
  FToolbar := AToolbar;
  FRoot := ARoot;
  FSeen := True;
  FButton.FreeNotification(Self);
  FToolbar.FreeNotification(Self);
  FRoot.FreeNotification(Self);
end;

procedure TDAIStreamedButtonCapture.Consume;
begin
  FConsumed := True;
end;

function TDAIStreamedButtonCapture.Ready: Boolean;
begin
  Result := False;
  if FConsumed or FAmbiguous then
    Exit;
  if not Assigned(FButton) or not Assigned(FToolbar) or not Assigned(FRoot) then
    Exit;
  if csDestroying in FButton.ComponentState then
    Exit;
  if csDestroying in FToolbar.ComponentState then
    Exit;
  if csDestroying in FRoot.ComponentState then
    Exit;
  if FButton.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  if FToolbar.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  if FRoot.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  Result := True;
end;

procedure TDAIToolbarController.ActivateReadHooks;
begin
  Inc(FCallbackDepth);
  try
    try
      EnsureReadNotifier;
    except
      on E: Exception do
        if not FShuttingDown then
          ReportError(E.ClassName + ': ' + E.Message);
    end;
  finally
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.EnsureReadNotifier;
var
  LServices: INTAServices;
  LNotifier: TDAIToolbarReadNotifier;
  LInterface: IOTANotifier;
  LIndex: Integer;
begin
  if FShuttingDown or Assigned(FReadNotifierInterface) then
    Exit;
  if not Supports(BorlandIDEServices, INTAServices, LServices) then
    Exit;
  LNotifier := TDAIToolbarReadNotifier.Create(Self);
  LInterface := LNotifier;
  try
    LIndex := LServices.RegisterToolbarNotifier(LInterface);
    if LIndex < 0 then
      raise EInvalidOperation.Create(DAIText('Die IDE hat die DAI-Toolbar-Lesenotification nicht registriert.',
        'The IDE did not register the DAI toolbar read notifier.',
        'L’IDE n’a pas inscrit le notificateur de lecture de la barre d’outils DAI.',
        'IDE が DAI ツールバー読み取り通知を登録しませんでした。'));
    if FShuttingDown then
    begin
      LNotifier.Detach;
      UnregisterToolbarReadNotifier(LServices, LIndex);
      Exit;
    end;
    FReadNotifier := LNotifier;
    FReadNotifierInterface := LInterface;
    FReadNotifierServices := LServices;
    FReadNotifierIndex := LIndex;
  except
    LNotifier.Detach;
    raise;
  end;
end;

procedure TDAIToolbarController.RetireReadNotifier;
var
  LNotifier: TDAIToolbarReadNotifier;
  LInterface: IOTANotifier;
  LServices: INTAServices;
  LIndex: Integer;
begin
  LNotifier := FReadNotifier;
  LInterface := FReadNotifierInterface;
  LServices := FReadNotifierServices;
  LIndex := FReadNotifierIndex;
  FReadNotifier := nil;
  FReadNotifierInterface := nil;
  FReadNotifierServices := nil;
  FReadNotifierIndex := -1;
  if Assigned(LNotifier) then
    LNotifier.Detach;
  UnregisterToolbarReadNotifier(LServices, LIndex);
  LInterface := nil;
end;

procedure TDAIToolbarController.CaptureReadButton(Reader: TReader; Component: TComponent; const AName: string);
var
  LButton: TToolButton;
  LToolbar: TToolBar;
begin
  if FShuttingDown or (AName <> CDAIButtonName) then
    Exit;
  if not Assigned(Reader) or not Assigned(Component) then
    Exit;
  if Component.ClassType <> TToolButton then
    Exit;
  LButton := TToolButton(Component);
  if not (LButton.Parent is TToolBar) then
    Exit;
  LToolbar := TToolBar(LButton.Parent);
  if LToolbar.Name <> sDebugToolBar then
    Exit;
  if not Assigned(Reader.Root) then
    Exit;
  if (LButton.Owner <> Reader.Root) or (LToolbar.Owner <> Reader.Root) then
    Exit;
  if (Reader.Owner <> Reader.Root) or (Reader.Parent <> LToolbar) then
    Exit;
  if csDestroying in LButton.ComponentState then
    Exit;
  if csDestroying in LToolbar.ComponentState then
    Exit;
  if csDestroying in Reader.Root.ComponentState then
    Exit;
  // ReadComponents uses AOwner/AppBuilder as Root. Public ToolBar[sDebugToolBar]
  // is temporarily nil here; its exact object identity is checked at adoption.
  FStreamCapture.Capture(LButton, LToolbar, Reader.Root);
end;

procedure TDAIToolbarController.BeginToolbarRead(AToolbar: TWinControl);
begin
  if FShuttingDown then
    Exit;
  if not (AToolbar is TToolBar) then
    Exit;
  if AToolbar.Name = sDebugToolBar then
    FStreamCapture.Clear;
end;

function TDAIToolbarController.RestoredButton(AToolbar: TToolBar; AActionList: TCustomActionList): TToolButton;
var
  LButton: TToolButton;
  LOwnClick: TNotifyEvent;
  LClick: TNotifyEvent;
begin
  Result := nil;
  if not FStreamCapture.Ready then
    Exit;
  LButton := FStreamCapture.Button;
  // A plausible stream name alone never authorizes reuse: match the actual SDK
  // toolbar and its IDE action-list owner after ReadToolbar assigns its pointer.
  if (FStreamCapture.Toolbar <> AToolbar) or (FStreamCapture.Root <> AActionList.Owner) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  if (LButton.Parent <> AToolbar) or (LButton.Owner <> AActionList.Owner) or (AToolbar.Owner <> AActionList.Owner) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  if (LButton.Name <> '') and (LButton.Name <> CDAIButtonName) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  LOwnClick := ToggleServer;
  LClick := LButton.OnClick;
  if Assigned(LClick) then
    if (TMethod(LClick).Code <> TMethod(LOwnClick).Code) or (TMethod(LClick).Data <> Self) then
    begin
      FStreamCapture.Consume;
      Exit;
    end;
  if ((LButton.Action <> nil) and (LButton.Action <> FAction)) or
    ((LButton.DropdownMenu <> nil) and (LButton.DropdownMenu <> FPopup)) or
    (LButton.PopupMenu <> nil) or (LButton.MenuItem <> nil) or (LButton.Style <> tbsDropDown) or
    ((LButton.Tag <> 0) and (LButton.Tag <> CDAIButtonTag)) or (LButton.DragMode <> dmManual) or (LButton.DragKind <> dkDrag) or
    Assigned(TDAIToolButtonAccess(LButton).OnDblClick) or Assigned(LButton.OnContextPopup) or
    Assigned(LButton.OnMouseDown) or Assigned(LButton.OnMouseMove) or Assigned(LButton.OnMouseUp) or
    Assigned(LButton.OnDragDrop) or Assigned(LButton.OnDragOver) or Assigned(LButton.OnStartDrag) or
    Assigned(LButton.OnEndDrag) or Assigned(LButton.OnMouseEnter) or Assigned(LButton.OnMouseLeave) or
    Assigned(LButton.OnMouseActivate) or Assigned(LButton.OnStartDock) or Assigned(LButton.OnEndDock) then
  begin
    FStreamCapture.Consume;
    Exit;
  end;
  Result := LButton;
end;

function TDAIToolbarController.IsMarkedButton(AButton: TToolButton; AToolbar: TToolBar; AActionList: TCustomActionList): Boolean;
var
  LOwnClick, LClick: TNotifyEvent;
begin
  Result := False;
  if not Assigned(AButton) or not Assigned(AToolbar) or not Assigned(AActionList) then
    Exit;
  if not Assigned(AActionList.Owner) then
    Exit;
  if (AButton.ClassType <> TToolButton) or (AButton.Tag <> CDAIButtonTag) then
    Exit;
  if (AButton.Parent <> AToolbar) or (AButton.Owner <> AActionList.Owner) or (AToolbar.Owner <> AActionList.Owner) then
    Exit;
  if (AButton.ComponentState * [csDestroying, csLoading, csReading] <> []) or
    (AToolbar.ComponentState * [csDestroying, csLoading, csReading] <> []) or
    (AActionList.ComponentState * [csDestroying, csLoading, csReading] <> []) or
    (AActionList.Owner.ComponentState * [csDestroying, csLoading, csReading] <> []) then
    Exit;
  // The marker proves identity only together with the official toolbar/owner.
  // Never reclaim a marked object that has acquired another plug-in's behavior.
  LOwnClick := ToggleServer;
  LClick := AButton.OnClick;
  if Assigned(LClick) then
    if (TMethod(LClick).Code <> TMethod(LOwnClick).Code) or (TMethod(LClick).Data <> Self) then
      Exit;
  if ((AButton.Action <> nil) and (AButton.Action <> FAction)) or
    ((AButton.DropdownMenu <> nil) and (AButton.DropdownMenu <> FPopup)) or
    (AButton.PopupMenu <> nil) or (AButton.MenuItem <> nil) or (AButton.Style <> tbsDropDown) or
    (AButton.DragMode <> dmManual) or (AButton.DragKind <> dkDrag) or
    Assigned(TDAIToolButtonAccess(AButton).OnDblClick) or Assigned(AButton.OnContextPopup) or
    Assigned(AButton.OnMouseDown) or Assigned(AButton.OnMouseMove) or Assigned(AButton.OnMouseUp) or
    Assigned(AButton.OnDragDrop) or Assigned(AButton.OnDragOver) or Assigned(AButton.OnStartDrag) or
    Assigned(AButton.OnEndDrag) or Assigned(AButton.OnMouseEnter) or Assigned(AButton.OnMouseLeave) or
    Assigned(AButton.OnMouseActivate) or Assigned(AButton.OnStartDock) or Assigned(AButton.OnEndDock) then
    Exit;
  Result := True;
end;

function TDAIToolbarController.MarkedButton(AToolbar: TToolBar; AActionList: TCustomActionList): TToolButton;
var
  LIndex: Integer;
begin
  Result := nil;
  if IsMarkedButton(FButton, AToolbar, AActionList) then
    Exit(FButton);
  for LIndex := 0 to AToolbar.ButtonCount - 1 do
    if IsMarkedButton(AToolbar.Buttons[LIndex], AToolbar, AActionList) then
      Exit(AToolbar.Buttons[LIndex]);
end;

procedure TDAIToolbarController.RemoveMarkedButtons(const APreserveButton: TToolButton);
var
  LIndex: Integer;
  LButton: TToolButton;
begin
  if not Assigned(FToolbar) or not Assigned(FActionList) then
    Exit;
  if csDestroying in FToolbar.ComponentState then
    Exit;
  if csDestroying in FActionList.ComponentState then
    Exit;
  for LIndex := FToolbar.ButtonCount - 1 downto 0 do
  begin
    if LIndex >= FToolbar.ButtonCount then
      Continue;
    LButton := FToolbar.Buttons[LIndex];
    if (LButton = FButton) or (LButton = APreserveButton) then
      Continue;
    if not IsMarkedButton(LButton, FToolbar, FActionList) then
      Continue;
    LButton.Action := nil;
    LButton.DropdownMenu := nil;
    LButton.Free;
  end;
end;

constructor TDAIToolbarController.Create;
begin
  inherited Create(nil);
  FReadNotifierIndex := -1;
  FStreamCapture := TDAIStreamedButtonCapture.Create(Self);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 500;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TDAIToolbarController.Destroy;
begin
  FShuttingDown := True;
  RetireReadNotifier;
  if Assigned(FStreamCapture) then
    FStreamCapture.Clear;
  if Assigned(FTimer) then
  begin
    FTimer.Enabled := False;
    FTimer.OnTimer := nil;
  end;
  RemoveUI;
  inherited;
end;

procedure TDAIToolbarController.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = FToolbar then
    FToolbar := nil;
  if AComponent = FActionList then
    FActionList := nil;
  if AComponent = FAction then
    FAction := nil;
  if AComponent = FButton then
    FButton := nil;
  if AComponent = FPopup then
    FPopup := nil;
  if AComponent = FToggleItem then
    FToggleItem := nil;
  if AComponent = FOptionsItem then
    FOptionsItem := nil;
  if AComponent = FResetItem then
    FResetItem := nil;
  if AComponent = FIDEPermissionItem then
    FIDEPermissionItem := nil;
  if AComponent = FProjectPermissionItem then
    FProjectPermissionItem := nil;
  for var LIndex := Low(FIndexItems) to High(FIndexItems) do
    if AComponent = FIndexItems[LIndex] then
      FIndexItems[LIndex] := nil;
  if AComponent = FManageIndexesItem then
    FManageIndexesItem := nil;
end;

procedure TDAIToolbarController.RemoveUI(const APreserveButton: TToolButton);
begin
  RemoveMarkedButtons(APreserveButton);
  // Desktop/customization can create more than the one factory-returned button.
  // Remove exact action clients before freeing the action loses their identity.
  RemoveActionButtons;
  if Assigned(FButton) then
  begin
    FButton.Action := nil;
    FButton.DropdownMenu := nil;
  end;
  FreeAndNil(FPopup);
  FreeAndNil(FButton);
  FreeAndNil(FAction);
  if Assigned(FToolbar) then
    FToolbar.RemoveFreeNotification(Self);
  FToolbar := nil;
  if Assigned(FActionList) then
    FActionList.RemoveFreeNotification(Self);
  FActionList := nil;
end;

procedure TDAIToolbarController.RemoveActionButtons;
var
  LIndex: Integer;
  LLink: TBasicActionLink;
  LControl: TControl;
  LButton: TToolButton;
begin
  if not Assigned(FAction) then
    Exit;
  for LIndex := TDAIActionAccess(FAction).ClientCount - 1 downto 0 do
  begin
    if LIndex >= TDAIActionAccess(FAction).ClientCount then
      Continue;
    LLink := TDAIActionAccess(FAction).Clients[LIndex];
    if not (LLink is TControlActionLink) then
      Continue;
    LControl := TDAIControlActionLinkAccess(LLink).FClient;
    if not (LControl is TToolButton) then
      Continue;
    LButton := TToolButton(LControl);
    if (LButton.Action <> FAction) or (csDestroying in LButton.ComponentState) then
      Continue;
    LButton.Action := nil;
    LButton.DropdownMenu := nil;
    LButton.Free;
  end;
end;

procedure TDAIToolbarController.RemoveLegacyButtons(const AAllowSingle: Boolean);
var
  LAnchorAction: TContainedAction;
  LAction: TContainedAction;
  LAnchor: Integer;
  LIndex: Integer;
  LCount: Integer;
  LButton: TToolButton;
  LCandidates: array[0..4] of TToolButton;

  function IsInertLegacyButton(const AButton: TToolButton): Boolean;
  begin
    if not Assigned(AButton) then
      Exit(False);
    Result := (AButton.ClassType = TToolButton) and (AButton.Owner = FButton.Owner) and (AButton.Name = '') and (AButton.Action = nil) and
      (AButton.Style = tbsDropDown) and (AButton.DropdownMenu = nil) and (AButton.PopupMenu = nil) and
      (AButton.MenuItem = nil) and not AButton.EnableDropdown and not AButton.Down and not AButton.Grouped and
      not AButton.AllowAllUp and not AButton.AutoSize and not AButton.Marked and not AButton.Indeterminate and not AButton.Wrap and
      (AButton.Caption = '') and (AButton.Hint = '') and (AButton.ImageName = '') and (AButton.ImageIndex = -1) and
      (AButton.DragMode = dmManual) and (AButton.DragKind = dkDrag) and
      (AButton.Tag = 0) and AButton.Visible and AButton.Enabled and AButton.ShowHint and not AButton.ParentShowHint and
      not Assigned(AButton.OnClick) and not Assigned(TDAIToolButtonAccess(AButton).OnDblClick) and not Assigned(AButton.OnContextPopup) and
      not Assigned(AButton.OnMouseDown) and not Assigned(AButton.OnMouseMove) and not Assigned(AButton.OnMouseUp) and
      not Assigned(AButton.OnDragDrop) and not Assigned(AButton.OnDragOver) and not Assigned(AButton.OnStartDrag) and
      not Assigned(AButton.OnEndDrag) and not Assigned(AButton.OnMouseEnter) and not Assigned(AButton.OnMouseLeave) and
      not Assigned(AButton.OnMouseActivate) and not Assigned(AButton.OnStartDock) and not Assigned(AButton.OnEndDock) and
      not (csDestroying in AButton.ComponentState);
  end;

begin
  if not Assigned(FToolbar) or not Assigned(FActionList) or not Assigned(FButton) or not Assigned(FAction) then
    Exit;
  if csDestroying in FToolbar.ComponentState then
    Exit;
  if csDestroying in FActionList.ComponentState then
    Exit;
  if csDestroying in FButton.ComponentState then
    Exit;
  if csDestroying in FAction.ComponentState then
    Exit;
  if (FButton.Parent <> FToolbar) or (FButton.Action <> FAction) then
    Exit;
  // IDE toolbar streaming leaves standard button names empty. Resolve the exact
  // action from the official IDE list, then match its object identity, not text
  // or an unstable button name. Any ambiguity leaves the toolbar untouched.
  LAnchorAction := nil;
  for LIndex := 0 to FActionList.ActionCount - 1 do
  begin
    LAction := FActionList.Actions[LIndex];
    if not Assigned(LAction) then
      Continue;
    if LAction.Name <> 'RunUntilReturnCommand' then
      Continue;
    if csDestroying in LAction.ComponentState then
      Exit;
    if Assigned(LAnchorAction) then
      Exit;
    LAnchorAction := LAction;
  end;
  if not Assigned(LAnchorAction) then
    Exit;
  LAnchor := -1;
  for LIndex := 0 to FToolbar.ButtonCount - 1 do
  begin
    LButton := FToolbar.Buttons[LIndex];
    if not Assigned(LButton) then
      Exit;
    if LButton.Action <> LAnchorAction then
      Continue;
    if LAnchor >= 0 then
      Exit;
    LAnchor := LIndex;
  end;
  if LAnchor < 0 then
    Exit;
  // Only the verified three/four/five inert records directly between the IDE's
  // Run Until Return action button and this controller's current button qualify.
  LCount := 0;
  LIndex := LAnchor + 1;
  while (LIndex < FToolbar.ButtonCount) and (LCount < Length(LCandidates)) do
  begin
    LButton := FToolbar.Buttons[LIndex];
    if LButton = FButton then
      Break;
    if not IsInertLegacyButton(LButton) then
      Exit;
    LCandidates[LCount] := LButton;
    Inc(LCount);
    Inc(LIndex);
  end;
  if (LCount < 3) and not (AAllowSingle and (LCount = 1)) then
    Exit;
  if LIndex >= FToolbar.ButtonCount then
    Exit;
  if FToolbar.Buttons[LIndex] <> FButton then
    Exit;
  for LIndex := LCount - 1 downto 0 do
    LCandidates[LIndex].Free;
end;

procedure TDAIToolbarController.LeaveCallback;
begin
  Dec(FCallbackDepth);
  if FShuttingDown and (FCallbackDepth = 0) then
    Free;
end;

procedure TDAIToolbarController.Shutdown;
begin
  FShuttingDown := True;
  RetireReadNotifier;
  FStreamCapture.Clear;
  FTimer.Enabled := False;
  FTimer.OnTimer := nil;
  if Assigned(FAction) then
  begin
    FAction.OnExecute := nil;
    FAction.Enabled := False;
  end;
  if Assigned(FToggleItem) then
    FToggleItem.OnClick := nil;
  if Assigned(FOptionsItem) then
    FOptionsItem.OnClick := nil;
  if Assigned(FResetItem) then
    FResetItem.OnClick := nil;
  if Assigned(FIDEPermissionItem) then
    FIDEPermissionItem.OnClick := nil;
  if Assigned(FProjectPermissionItem) then
    FProjectPermissionItem.OnClick := nil;
  if Assigned(FPopup) then
    FPopup.OnPopup := nil;
  for var LIndex := Low(FIndexItems) to High(FIndexItems) do
    if Assigned(FIndexItems[LIndex]) then
      FIndexItems[LIndex].OnClick := nil;
  if Assigned(FManageIndexesItem) then
    FManageIndexesItem.OnClick := nil;
  // StopServer may pump synchronized workers. A reentrant IDE shutdown must
  // not destroy this receiver while one of its UI callbacks is still running.
  if FCallbackDepth = 0 then
    Free;
end;

procedure TDAIToolbarController.ReportError(const AError: string);
begin
  if AError = FLastInstallError then
    Exit;
  FLastInstallError := AError;
  TDAILog.Error(DAIText('DAI-Werkzeugleiste: ', 'DAI toolbar: ', 'Barre d’outils DAI : ', 'DAI ツールバー: ') + AError);
end;

function CreateServerGlyph(const AState: TDAIServerGlyphState; const ASize: Integer): TPngImage;
var
  LBitmap: TBitmap;
  LSmallBitmap: TBitmap;
  LCanvas: TCanvas;
  LSource: PRGBTriple;
  LTarget: PByteArray;
  LAlpha: PByteArray;
  LRed: Integer;
  LGreen: Integer;
  LBlue: Integer;
  LCoverage: Integer;
  LX: Integer;
  LY: Integer;
  LSampleX: Integer;
  LSampleY: Integer;
  LSuccess: Boolean;

  function P(const ACoordinate: Integer): Integer;
  begin
    Result := MulDiv(ACoordinate, ASize * 4, 16);
  end;

  function H(const AHalfCoordinate: Integer): Integer;
  begin
    Result := MulDiv(AHalfCoordinate, ASize * 4, 32);
  end;

begin
  // Draw at four times the target size, then retain actual coverage as alpha.
  // No font, image file, mask-colour halo or theme-coloured background is needed.
  LBitmap := TBitmap.Create;
  LSmallBitmap := nil;
  Result := nil;
  LSuccess := False;
  try
    LBitmap.PixelFormat := pf24bit;
    LBitmap.SetSize(ASize * 4, ASize * 4);
    LCanvas := LBitmap.Canvas;
    LCanvas.Brush.Color := clFuchsia;
    LCanvas.FillRect(Rect(0, 0, LBitmap.Width, LBitmap.Height));
    LCanvas.Pen.Width := P(1);
    LCanvas.Pen.Color := $00956436;
    LCanvas.Brush.Color := $00F8F0E5;
    LCanvas.RoundRect(P(1), P(1), P(13), P(13), P(3), P(3));
    LCanvas.Pen.Color := $00956436;
    LCanvas.MoveTo(P(5), P(4));
    LCanvas.LineTo(P(10), P(4));
    LCanvas.MoveTo(P(5), P(8));
    LCanvas.LineTo(P(8), P(8));
    LCanvas.Pen.Color := CDAIImageColors[AState];
    LCanvas.Brush.Color := CDAIImageColors[AState];
    LCanvas.Ellipse(P(2), P(3), P(4), P(5));
    LCanvas.Ellipse(P(2), P(7), P(4), P(9));
    LCanvas.Pen.Color := clWhite;
    case AState of
      sgInactive:
        begin
          LCanvas.RoundRect(P(7), P(7), P(15), P(15), P(2), P(2));
          LCanvas.Brush.Color := clWhite;
          LCanvas.FillRect(Rect(P(9), P(9), P(11), P(14)));
          LCanvas.FillRect(Rect(P(12), P(9), P(14), P(14)));
        end;
      sgActive:
        LCanvas.Polygon([Point(P(8), P(7)), Point(P(15), P(11)), Point(P(8), P(15))]);
      sgError:
        LCanvas.Polygon([Point(H(15), H(19)), Point(H(19), H(15)), Point(H(22), H(18)), Point(H(25), H(15)),
          Point(H(29), H(19)), Point(H(26), H(22)), Point(H(29), H(25)), Point(H(25), H(29)),
          Point(H(22), H(26)), Point(H(19), H(29)), Point(H(15), H(25)), Point(H(18), H(22))]);
      sgRecentAccess, sgEarlierAccess:
        LCanvas.Ellipse(P(7), P(7), P(15), P(15));
      sgNotRegistered:
        begin
          LCanvas.Ellipse(P(7), P(7), P(15), P(15));
          LCanvas.Pen.Width := H(2);
          LCanvas.Polyline([Point(H(19), H(20)), Point(H(19), H(19)), Point(H(21), H(18)), Point(H(24), H(18)),
            Point(H(26), H(20)), Point(H(26), H(22)), Point(H(22), H(24)), Point(H(22), H(25))]);
          LCanvas.Brush.Color := clWhite;
          LCanvas.FillRect(Rect(H(21), H(27), H(23), H(29)));
        end;
      sgRegistrationUpdate:
        begin
          LCanvas.Pen.Color := CDAIImageColors[AState];
          LCanvas.Polygon([Point(P(11), P(7)), Point(P(15), P(15)), Point(P(7), P(15))]);
          LCanvas.Brush.Color := clWhite;
          LCanvas.FillRect(Rect(H(21), H(20), H(23), H(25)));
          LCanvas.FillRect(Rect(H(21), H(27), H(23), H(29)));
        end;
      sgUpdateAvailable:
        begin
          LCanvas.Pen.Color := CDAIImageColors[AState];
          LCanvas.Polygon([Point(P(7), P(11)), Point(P(11), P(7)), Point(P(15), P(11)), Point(P(13), P(11)),
            Point(P(13), P(15)), Point(P(9), P(15)), Point(P(9), P(11))]);
        end;
    end;
    LSmallBitmap := TBitmap.Create;
    LSmallBitmap.PixelFormat := pf24bit;
    LSmallBitmap.SetSize(ASize, ASize);
    Result := TPngImage.Create;
    Result.Assign(LSmallBitmap);
    Result.CreateAlpha;
    for LY := 0 to ASize - 1 do
    begin
      LTarget := Result.Scanline[LY];
      LAlpha := Result.AlphaScanline[LY];
      for LX := 0 to ASize - 1 do
      begin
        LRed := 0;
        LGreen := 0;
        LBlue := 0;
        LCoverage := 0;
        for LSampleY := 0 to 3 do
          for LSampleX := 0 to 3 do
          begin
            LSource := LBitmap.ScanLine[ASize * 4 - 1 - (LY * 4 + LSampleY)];
            Inc(LSource, LX * 4 + LSampleX);
            if (LSource.rgbtRed = 255) and (LSource.rgbtGreen = 0) and (LSource.rgbtBlue = 255) then
              Continue;
            Inc(LCoverage);
            Inc(LRed, LSource.rgbtRed);
            Inc(LGreen, LSource.rgbtGreen);
            Inc(LBlue, LSource.rgbtBlue);
          end;
        if LCoverage > 0 then
        begin
          LTarget[LX * 3] := LBlue div LCoverage;
          LTarget[LX * 3 + 1] := LGreen div LCoverage;
          LTarget[LX * 3 + 2] := LRed div LCoverage;
        end
        else
        begin
          LTarget[LX * 3] := 0;
          LTarget[LX * 3 + 1] := 0;
          LTarget[LX * 3 + 2] := 0;
        end;
        LAlpha[LX] := LCoverage * 255 div 16;
      end;
    end;
    LSuccess := True;
  finally
    if not LSuccess then
      Result.Free;
    LSmallBitmap.Free;
    LBitmap.Free;
  end;
end;

procedure TDAIToolbarController.InstallImages(const AServices: INTAServices; AImages: TCustomImageList);
var
  LGraphics: TGraphicArray;
  LState: TDAIServerGlyphState;
  LSize: Integer;
begin
  if (AImages.Width < 8) or (AImages.Height < 8) then
    raise EInvalidOperation.Create(DAIText('Die IDE-Bildliste ist noch nicht bereit.',
      'The IDE image list is not ready yet.',
      'La liste d’images de l’IDE n’est pas encore prête.',
      'IDE の画像リストはまだ準備できていません。'));
  SetLength(LGraphics, Length(CDAIImageSizes));
  for LState := Low(FImages) to High(FImages) do
  begin
    try
      for LSize := Low(CDAIImageSizes) to High(CDAIImageSizes) do
        LGraphics[LSize] := CreateServerGlyph(LState, CDAIImageSizes[LSize]);
      // The modern IDE path copies all resolutions into its image collection.
      // Stable names deduplicate on reload; never delete shared image indices.
      FImages[LState] := AServices.AddImage(CDAIImageIds[LState], LGraphics);
      if (FImages[LState] < 0) or (FImages[LState] >= AImages.Count) then
        raise EInvalidOperation.Create(DAIText('Die IDE hat kein gültiges DAI-Statusbild registriert.',
          'The IDE did not register a valid DAI status image.',
          'L’IDE n’a pas inscrit d’image d’état DAI valide.',
          'IDE が有効な DAI 状態画像を登録しませんでした。'));
    finally
      for LSize := Low(LGraphics) to High(LGraphics) do
        FreeAndNil(LGraphics[LSize]);
    end;
  end;
end;

procedure TDAIToolbarController.CreatePopup;
var
  LSeparator: TMenuItem;
  LIndex: Integer;
begin
  // AddToolButton requires dropdown ownership to match its returned button.
  FPopup := TPopupMenu.Create(FButton.Owner);
  FPopup.Name := 'DAIServerPopupMenu';
  FPopup.OnPopup := PopupOpening;
  // VCL's automatic '&' insertion must not conflict with later status captions.
  FPopup.AutoHotkeys := maManual;
  FPopup.FreeNotification(Self);
  FToggleItem := TMenuItem.Create(FPopup);
  FToggleItem.FreeNotification(Self);
  FToggleItem.OnClick := ToggleServer;
  FPopup.Items.Add(FToggleItem);
  FOptionsItem := TMenuItem.Create(FPopup);
  FOptionsItem.FreeNotification(Self);
  FOptionsItem.Caption := DAIText('DAI-&Optionen und Berechtigungen …',
    'DAI &options and permissions …',
    '&Options et autorisations DAI …',
    'DAI のオプションと権限 …');
  FOptionsItem.OnClick := OpenOptions;
  FPopup.Items.Add(FOptionsItem);
  FResetItem := TMenuItem.Create(FPopup);
  FResetItem.FreeNotification(Self);
  FResetItem.Caption := DAIText('Sitzungsfreigaben &zurücksetzen',
    '&Reset session permissions',
    '&Réinitialiser les autorisations de session',
    'セッションの権限をリセット');
  FResetItem.OnClick := ResetSessionPermissions;
  FPopup.Items.Add(FResetItem);
  LSeparator := TMenuItem.Create(FPopup);
  LSeparator.Caption := '-';
  FPopup.Items.Add(LSeparator);
  FIDEPermissionItem := TMenuItem.Create(FPopup);
  FIDEPermissionItem.FreeNotification(Self);
  FIDEPermissionItem.OnClick := OpenOptions;
  FPopup.Items.Add(FIDEPermissionItem);
  FProjectPermissionItem := TMenuItem.Create(FPopup);
  FProjectPermissionItem.FreeNotification(Self);
  FProjectPermissionItem.OnClick := OpenOptions;
  FPopup.Items.Add(FProjectPermissionItem);
  LSeparator := TMenuItem.Create(FPopup);
  LSeparator.Caption := '-';
  FPopup.Items.Add(LSeparator);
  for LIndex := Low(FIndexItems) to High(FIndexItems) do
  begin
    FIndexItems[LIndex] := TMenuItem.Create(FPopup);
    FIndexItems[LIndex].FreeNotification(Self);
    FIndexItems[LIndex].Caption := IndexMenuCaption(LIndex);
    FIndexItems[LIndex].Tag := LIndex;
    FIndexItems[LIndex].Enabled := LIndex < 2;
    FIndexItems[LIndex].OnClick := OpenIndexes;
    FPopup.Items.Add(FIndexItems[LIndex]);
  end;
  FManageIndexesItem := TMenuItem.Create(FPopup);
  FManageIndexesItem.FreeNotification(Self);
  FManageIndexesItem.Caption := DAIText('Indizes verwalten …', 'Manage indexes …', 'Gérer les index …', 'インデックスの管理 …');
  FManageIndexesItem.Tag := -1;
  FManageIndexesItem.OnClick := OpenIndexes;
  FPopup.Items.Add(FManageIndexesItem);
  FButton.DropdownMenu := FPopup;
end;

procedure TDAIToolbarController.PopupOpening(Sender: TObject);
const
  LScopes: array[0..3] of string = ('delphi', 'getit', 'group', 'project');
var
  LResult: TJSONObject;
  LValue: TJSONValue;
  LIndexes: TJSONValue;
  LScope: string;
  LExists: Boolean;
  LIndex: Integer;
begin
  if FShuttingDown then
    Exit;
  Inc(FCallbackDepth);
  try
    // Cancel both a visible hint and its pending show timer before native menu tracking.
    Application.CancelHint;
    // Reset the visible editor caret cursor without installing a global Screen.Cursor override.
    Winapi.Windows.SetCursor(Screen.Cursors[crArrow]);
    // Query only while opening the popup, never from the toolbar status timer.
    // Keep item identities fixed throughout native menu tracking.
    for LIndex := Low(FIndexItems) to High(FIndexItems) do
      if Assigned(FIndexItems[LIndex]) then
        FIndexItems[LIndex].Enabled := LIndex < 2;
    try
      LResult := TDAISymbolService.ListIndexes;
      try
        LIndexes := LResult.GetValue('indexes');
        if LIndexes is TJSONArray then
          for LValue in TJSONArray(LIndexes) do
            if LValue is TJSONObject then
            begin
              LScope := TJSONObject(LValue).GetValue<string>('scope', '');
              LExists := TJSONObject(LValue).GetValue<Boolean>('exists', False);
              for LIndex := Low(FIndexItems) to High(FIndexItems) do
                if (LScope = LScopes[LIndex]) and Assigned(FIndexItems[LIndex]) then
                  FIndexItems[LIndex].Enabled := (LIndex < 2) or LExists;
            end;
      finally
        LResult.Free;
      end;
    except
      on E: Exception do
        TDAILog.Error(DAIText('DAI-Indexliste konnte nicht gelesen werden: ',
          'Could not read the DAI index list: ',
          'Impossible de lire la liste des index DAI : ',
          'DAI インデックス一覧を読み取れませんでした: ') + E.Message);
    end;
    // Index queries can change the cursor; restore the menu arrow immediately before tracking starts.
    Winapi.Windows.SetCursor(Screen.Cursors[crArrow]);
  finally
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.OpenIndexes(Sender: TObject);
const
  LScopes: array[0..3] of string = ('delphi', 'getit', 'group', 'project');
var
  LScope: string;
  LTag: NativeInt;
begin
  if FShuttingDown then
    Exit;
  Inc(FCallbackDepth);
  try
    LScope := '';
    if Sender is TMenuItem then
    begin
      LTag := TMenuItem(Sender).Tag;
      if (LTag >= Low(LScopes)) and (LTag <= High(LScopes)) then
        LScope := LScopes[LTag];
    end;
    TDAISymbolIndexDialog.Show(LScope);
  finally
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.EnsureOwnButtonFitsHorizontally;
var
  LParent: TWinControl;
  LHandle: HWND;
  LIndex: Integer;
  LPPI: Integer;
  LNativeButton: TTBButton;
  LButtonRect: TRect;
  LClientRect: TRect;
  LRequiredWidth: Int64;
begin
  RequireMainThread;
  if FShuttingDown then
    Exit;
  if not Assigned(FToolbar) or not Assigned(FButton) or not Assigned(FAction) or not Assigned(FPopup) then
    Exit;
  if FToolbar.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  if FButton.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  if csDestroying in FAction.ComponentState then
    Exit;
  if csDestroying in FPopup.ComponentState then
    Exit;
  if (FButton.Parent <> FToolbar) or (FButton.Action <> FAction) or (FButton.DropdownMenu <> FPopup) then
    Exit;
  // Never create an HWND merely to inspect layout during IDE restoration.
  if not FToolbar.HandleAllocated then
    Exit;
  LHandle := FToolbar.Handle;
  if not IsWindow(LHandle) then
    Exit;
  LIndex := FButton.Index;
  if LIndex < 0 then
    Exit;
  if SendMessage(LHandle, TB_BUTTONCOUNT, 0, 0) <= LIndex then
    Exit;
  LNativeButton := Default(TTBButton);
  if SendMessage(LHandle, TB_GETBUTTON, WPARAM(LIndex), LPARAM(@LNativeButton)) = 0 then
    Exit;
  if LNativeButton.dwData <> UIntPtr(FButton) then
    Exit;
  if (LNativeButton.fsState and TBSTATE_HIDDEN) <> 0 then
    Exit;
  LPPI := FToolbar.CurrentPPI;
  if LPPI <= 0 then
    Exit;
  if SendMessage(LHandle, TB_GETITEMRECT, WPARAM(LIndex), LPARAM(@LButtonRect)) = 0 then
    Exit;
  if not GetClientRect(LHandle, LClientRect) then
    Exit;
  if LButtonRect.Right <= LButtonRect.Left then
    Exit;
  if LClientRect.Right <= LClientRect.Left then
    Exit;
  if LButtonRect.Right <= LClientRect.Right then
    Exit;
  // VCL bounds, constraints and native client rectangles already use the
  // current DPI's pixels. Add the client deficit without scaling it again.
  LRequiredWidth := Int64(FToolbar.Width) + Int64(LButtonRect.Right) - Int64(LClientRect.Right);
  if LRequiredWidth < FToolbar.Constraints.MinWidth then
    LRequiredWidth := FToolbar.Constraints.MinWidth;
  if FToolbar.Constraints.MaxWidth > 0 then
    if LRequiredWidth > FToolbar.Constraints.MaxWidth then
      Exit;
  if (LRequiredWidth <= FToolbar.Width) or (LRequiredWidth > High(Integer)) then
    Exit;
  if FToolbar.CurrentPPI <> LPPI then
    Exit;
  // Width preserves Left, Top, Height, AutoSize and Wrapable. Call this only
  // after creation or positive restore adoption, never on ordinary refreshes.
  FToolbar.Width := Integer(LRequiredWidth);
  // Width requests alignment of this child only. The shared control bar also
  // needs a full band layout so toolbars to the right follow the new width.
  // Width changes can invoke callbacks which retire our UI; inspect it again.
  if FShuttingDown or not Assigned(FToolbar) then
    Exit;
  if FToolbar.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  LParent := FToolbar.Parent;
  if not Assigned(LParent) then
    Exit;
  if LParent.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  if LParent.HandleAllocated then
    LParent.Realign;
end;

procedure TDAIToolbarController.EnsureInstalled;
var
  LServices: INTAServices;
  LToolbar: TToolBar;
  LActionList: TCustomActionList;
  LImages: TCustomImageList;
  LControl: TControl;
  LRestored: TToolButton;
  LRestoreGuard: TDAIStreamedButtonCapture;
  LCaptured: Boolean;
  LIndex: Integer;
begin
  EnsureReadNotifier;
  if not Supports(BorlandIDEServices, INTAServices, LServices) then
    Exit;
  LToolbar := LServices.ToolBar[sDebugToolBar];
  LActionList := LServices.ActionList;
  LImages := LServices.ImageList;
  if not Assigned(LToolbar) or not Assigned(LActionList) or not Assigned(LImages) then
  begin
    // A live capture can precede assignment of the public toolbar pointer.
    // Otherwise preserve the existing cleanup contract after host destruction.
    if not Assigned(FStreamCapture.Toolbar) then
      RemoveUI;
    Exit;
  end;
  if csDestroying in LToolbar.ComponentState then
    Exit;
  if LActionList.ComponentState * [csDestroying, csLoading, csReading] <> [] then
    Exit;
  if Assigned(LActionList.Owner) then
    if LActionList.Owner.ComponentState * [csDestroying, csLoading, csReading] <> [] then
      Exit;
  if Assigned(FAction) then
    if csDestroying in FAction.ComponentState then
      Exit;
  if LToolbar.ComponentState * [csLoading, csReading] <> [] then
    Exit;
  LRestored := RestoredButton(LToolbar, LActionList);
  LCaptured := Assigned(LRestored);
  if not Assigned(LRestored) then
    LRestored := MarkedButton(LToolbar, LActionList);
  if Assigned(FToolbar) and Assigned(FActionList) and Assigned(FAction) and Assigned(FButton) and Assigned(FPopup) then
    if (FToolbar = LToolbar) and (FActionList = LActionList) then
      if not Assigned(LRestored) or (LRestored = FButton) then
      begin
        RemoveMarkedButtons;
        FButton.Name := CDAIButtonName;
        FButton.Tag := CDAIButtonTag;
        // RTL owner transfers send opRemove without destroying the dependency.
        // Rebind only our known objects; foreign replacements remain untouched.
        if FAction.ActionList = nil then
          FAction.ActionList := FActionList;
        if FButton.Action = nil then
          FButton.Action := FAction;
        if FButton.DropdownMenu = nil then
          FButton.DropdownMenu := FPopup;
        if LCaptured then
          FStreamCapture.Consume;
        // Only original-name capture authorizes the historical single migration.
        RemoveLegacyButtons(LCaptured);
        if LCaptured then
          EnsureOwnButtonFitsHorizontally;
        Exit;
      end;
  LRestoreGuard := TDAIStreamedButtonCapture.Create(nil);
  try
    if Assigned(LRestored) then
      LRestoreGuard.Capture(LRestored, LToolbar, LActionList.Owner);
    if Assigned(LRestored) then
    begin
      // Protect the validated restored object while retiring our old action clients.
      LRestored.Action := nil;
      LRestored.DropdownMenu := nil;
      LRestored.OnClick := nil;
      if LRestored = FButton then
      begin
        FButton.RemoveFreeNotification(Self);
        FButton := nil;
      end;
    end;
    RemoveUI(LRestored);
    if Assigned(LRestored) then
      if LRestoreGuard.Button <> LRestored then
        LRestored := nil;
    for LIndex := 0 to LToolbar.ButtonCount - 1 do
      if LToolbar.Buttons[LIndex] <> LRestored then
        if SameText(LToolbar.Buttons[LIndex].Name, CDAIButtonName) then
          if not IsMarkedButton(LToolbar.Buttons[LIndex], LToolbar, LActionList) then
            raise EInvalidOperation.Create(DAIText('Der DAI-Schalter ist bereits durch eine andere Instanz registriert.',
              'The DAI button is already registered by another instance.',
              'Le bouton DAI est déjà inscrit par une autre instance.',
              'DAI ボタンは別のインスタンスによって登録されています。'));
    for LIndex := 0 to LActionList.ActionCount - 1 do
      if SameText(LActionList.Actions[LIndex].Name, CDAIActionName) then
        raise EInvalidOperation.Create(DAIText('Die DAI-Aktion ist bereits durch eine andere Instanz registriert.',
          'The DAI action is already registered by another instance.',
          'L’action DAI est déjà inscrite par une autre instance.',
          'DAI アクションは別のインスタンスによって登録されています。'));
    InstallImages(LServices, LImages);
    FToolbar := LToolbar;
    FToolbar.FreeNotification(Self);
    FActionList := LActionList;
    FActionList.FreeNotification(Self);
    try
      // Release duplicate marked records before assigning the canonical Name.
      RemoveMarkedButtons(LRestored);
      FAction := TAction.Create(FActionList.Owner);
      FAction.Name := CDAIActionName;
      FAction.Category := 'DAI';
      FAction.Caption := DAIText('DAI inaktiv', 'DAI inactive', 'DAI inactif', 'DAI 停止中');
      FAction.ActionList := FActionList;
      FAction.ImageIndex := FImages[sgInactive];
      FAction.OnExecute := ToggleServer;
      FAction.FreeNotification(Self);
      if Assigned(LRestored) then
        FButton := LRestored
      else
      begin
        LControl := LServices.AddToolButton(sDebugToolBar, CDAIButtonName, FAction);
        if not (LControl is TToolButton) then
        begin
          LControl.Free;
          raise EInvalidOperation.Create(DAIText('Die Debugger-Werkzeugleiste liefert keinen VCL-ToolButton.',
            'The debugger toolbar did not provide a VCL ToolButton.',
            'La barre d’outils du débogueur n’a pas fourni de bouton VCL.',
            'デバッガーツールバーが VCL ToolButton を返しませんでした。'));
        end;
        FButton := TToolButton(LControl);
      end;
      FButton.FreeNotification(Self);
      FButton.Name := CDAIButtonName;
      FButton.Tag := CDAIButtonTag;
      FButton.Action := FAction;
      FButton.Style := tbsDropDown;
      FButton.ShowHint := True;
      FButton.ParentShowHint := False;
      CreatePopup;
      if LCaptured then
        FStreamCapture.Consume;
      RemoveLegacyButtons(LCaptured);
      RemoveMarkedButtons;
      EnsureOwnButtonFitsHorizontally;
      FLastInstallError := '';
    except
      RemoveUI;
      raise;
    end;
  finally
    LRestoreGuard.Free;
  end;
end;

procedure TDAIToolbarController.UpdateRegistrationStatus;
var
  LVersion: Integer;
  LActive: Boolean;
  LManual: Boolean;
begin
  if FShuttingDown or not Assigned(FAction) or IDEMenuTracking then
    Exit;
  LVersion := TDAIClientRegistration.ChangeVersion;
  LActive := TDAIRuntime.ServerActive;
  try
    LManual := TDAISettings.Instance.ManualClientRegistration;
  except
    FRegistrationChecked := True;
    FRegistrationDirty := True;
    FRegistrationHealth := rhCheckRecommended;
    FRegistrationDetails := DAIText('Die manuelle KI-Registrierung konnte nicht geprüft werden. Bitte die DAI-Optionen öffnen.',
      'The manual AI registration could not be checked. Open the DAI options.',
      'Impossible de vérifier l’inscription manuelle de l’IA. Ouvrez les options DAI.',
      '手動の AI 登録を確認できませんでした。DAI オプションを開いてください。');
    Exit;
  end;
  if FRegistrationChecked and not FRegistrationDirty and (FRegistrationVersion = LVersion) and
    (FRegistrationServerActive = LActive) and (FRegistrationManual = LManual) then
    Exit;
  // Registration files are read only on invalidation, never on each status tick.
  FRegistrationDirty := False;
  FRegistrationChecked := True;
  FRegistrationVersion := LVersion;
  FRegistrationServerActive := LActive;
  FRegistrationManual := LManual;
  try
    FRegistrationHealth := TDAIClientRegistration.Health(FRegistrationDetails);
    if (FRegistrationHealth = rhNotRegistered) and LManual then
    begin
      // This suppresses only a missing-registration notice, not update/read errors.
      FRegistrationHealth := rhCurrent;
      FRegistrationDetails := DAIText('Manuell registriert (vom Benutzer bestätigt).',
        'Manually registered (confirmed by the user).',
        'Inscription manuelle (confirmée par l’utilisateur).',
        '手動で登録済み（ユーザー確認済み）。');
    end;
  except
    on E: Exception do
    begin
      FRegistrationHealth := rhCheckRecommended;
      // Client-file parse errors may contain credentials; expose no raw exception.
      FRegistrationDetails := DAIText('Die KI-Registrierungen konnten nicht vollständig geprüft werden. Bitte die DAI-Optionen öffnen.',
        'The AI registrations could not be fully checked. Open the DAI options.',
        'Impossible de vérifier toutes les inscriptions de l’IA. Ouvrez les options DAI.',
        'AI 登録を完全に確認できませんでした。DAI オプションを開いてください。');
    end;
  end;
end;

procedure TDAIToolbarController.UpdatePermissionStatus;
var
  LVersion: Integer;
  LProjectKey: string;
begin
  if FShuttingDown or IDEMenuTracking then
    Exit;
  LVersion := TDAIPermissionManager.ChangeVersion;
  LProjectKey := TDAIOTA.ActiveProjectFileName;
  if FPermissionChecked and (FPermissionVersion = LVersion) and SameText(FPermissionProjectKey, LProjectKey) then
    Exit;
  FPermissionChecked := True;
  FPermissionVersion := LVersion;
  FPermissionProjectKey := LProjectKey;
  // Project policies are read only after permission or project changes.
  try
    FIDEPermissionSummary := TDAIPermissionManager.Instance.GetAccessSummary('', True);
    FProjectPermissionSummary := TDAIPermissionManager.Instance.GetAccessSummary(LProjectKey, False);
  except
    // A malformed policy must never be presented as an effective grant.
    FIDEPermissionSummary := 'Status unbekannt';
    FProjectPermissionSummary := 'Status unbekannt';
  end;
end;

procedure TDAIToolbarController.UpdateStatus;
var
  LActive: Boolean;
  LError: string;
  LCaption: string;
  LHint: string;
  LCommand: string;
  LImage: Integer;
  LAccessAgeMs: UInt64;
  LAccessShown: Boolean;
  LIDEPermissions, LProjectPermissions: string;
begin
  if not Assigned(FAction) or IDEMenuTracking then
    Exit;
  UpdatePermissionStatus;
  LIDEPermissions := PermissionSummaryCaption(FIDEPermissionSummary);
  LProjectPermissions := PermissionSummaryCaption(FProjectPermissionSummary);
  LActive := TDAIRuntime.ServerActive;
  LAccessShown := False;
  LError := TDAIRuntime.LastServerError;
  if FActionError <> '' then
    LError := FActionError;
  if LActive then
  begin
    LCaption := DAIText('DAI aktiv', 'DAI active', 'DAI actif', 'DAI 稼働中');
    LHint := Format(DAIText('DAI aktiv auf Port %d. Klicken zum Stoppen.',
      'DAI active on port %d. Click to stop.',
      'DAI actif sur le port %d. Cliquez pour arrêter.',
      'DAI はポート %d で稼働中です。クリックして停止します。'), [TDAIRuntime.ServerPort]);
    LCommand := DAIText('Server &stoppen', '&Stop server', '&Arrêter le serveur', 'サーバーを停止');
    LImage := FImages[sgActive];
    if TDAIRuntime.TryGetMCPAccessAgeMs(LAccessAgeMs) then
    begin
      if LAccessAgeMs <= 15000 then
      begin
        LImage := FImages[sgRecentAccess];
        LAccessShown := True;
        LHint := LHint + sLineBreak + DAIText('MCP-Zugriff in den letzten 15 Sekunden.',
          'MCP access within the last 15 seconds.',
          'Accès MCP au cours des 15 dernières secondes.',
          '過去 15 秒以内に MCP アクセスがありました。');
      end
      else if LAccessAgeMs <= 900000 then
      begin
        LImage := FImages[sgEarlierAccess];
        LAccessShown := True;
        LHint := LHint + sLineBreak + DAIText('MCP-Zugriff vor mehr als 15 Sekunden, innerhalb der letzten 15 Minuten.',
          'MCP access more than 15 seconds ago, within the last 15 minutes.',
          'Accès MCP il y a plus de 15 secondes, au cours des 15 dernières minutes.',
          '15 秒より前、過去 15 分以内に MCP アクセスがありました。');
      end;
    end;
  end
  else
  begin
    LCaption := DAIText('DAI inaktiv', 'DAI inactive', 'DAI inactif', 'DAI 停止中');
    LHint := Format(DAIText('DAI inaktiv; kein aktiver Port. Klicken zum Starten mit gespeichertem Port %d.',
      'DAI inactive; no active port. Click to start on saved port %d.',
      'DAI inactif ; aucun port actif. Cliquez pour démarrer sur le port enregistré %d.',
      'DAI は停止中です。クリックすると保存済みのポート %d で起動します。'), [TDAISettings.Instance.Port]);
    LCommand := DAIText('Server &starten', '&Start server', '&Démarrer le serveur', 'サーバーを起動');
    LImage := FImages[sgInactive];
  end;
  if TDAIIDEToolbar.FUpdateAvailable then
  begin
    if LActive and not LAccessShown then
    begin
      LImage := FImages[sgUpdateAvailable];
      LCaption := DAIText('DAI: Neue Version verfügbar',
        'DAI: New version available',
        'DAI : nouvelle version disponible',
        'DAI: 新しいバージョンがあります');
    end;
    LHint := LHint + sLineBreak + DAIText('Neue DAI-Version verfügbar',
      'New DAI version available',
      'Nouvelle version de DAI disponible',
      '新しい DAI バージョンがあります');
    if TDAIIDEToolbar.FUpdateVersion <> '' then
      LHint := LHint + ': ' + TDAIIDEToolbar.FUpdateVersion;
    LHint := LHint + '.';
  end;
  // A stopped MCP always displays Pause; retain all diagnostics in its hint.
  // Active registration problems retain priority over an optional update.
  if FRegistrationChecked then
  begin
    if LActive and not LAccessShown then
      case FRegistrationHealth of
        rhNotRegistered:
          begin
            LImage := FImages[sgNotRegistered];
            LCaption := DAIText('DAI nicht registriert', 'DAI not registered', 'DAI non inscrit', 'DAI 未登録');
          end;
        rhUpdateRecommended:
          begin
            LImage := FImages[sgRegistrationUpdate];
            LCaption := DAIText('DAI: Registrierung aktualisieren',
              'DAI: Update registration',
              'DAI : mettre à jour l’inscription',
              'DAI: 登録を更新してください');
          end;
        rhCheckRecommended:
          begin
            LImage := FImages[sgRegistrationUpdate];
            LCaption := DAIText('DAI: Registrierung prüfen', 'DAI: Check registration', 'DAI : vérifier l’inscription', 'DAI: 登録を確認してください');
          end;
      end;
    if FRegistrationDetails <> '' then
      LHint := LHint + sLineBreak + RegistrationDetailsCaption(FRegistrationDetails);
  end;
  if LError <> '' then
  begin
    LHint := LHint + sLineBreak + DAIText('Fehler: ', 'Error: ', 'Erreur : ', 'エラー: ') + LError;
    if LActive then
    begin
      LCaption := DAIText('DAI Fehler', 'DAI error', 'Erreur DAI', 'DAI エラー');
      LImage := FImages[sgError];
    end;
  end;
  if FBusy then
  begin
    LCaption := 'DAI …';
    LHint := DAIText('DAI: Serverzustand wird geändert.',
      'DAI: Changing server state.',
      'DAI : changement d’état du serveur.',
      'DAI: サーバーの状態を変更中です。');
  end;
  LHint := LHint + sLineBreak + 'IDE : ' + LIDEPermissions + sLineBreak +
    DAIText('Projekt : ', 'Project : ', 'Projet : ', 'プロジェクト : ') + LProjectPermissions;
  if FAction.Caption <> LCaption then
    FAction.Caption := LCaption;
  if FAction.Hint <> LHint then
    FAction.Hint := LHint;
  if FAction.ImageIndex <> LImage then
    FAction.ImageIndex := LImage;
  FAction.Enabled := not FBusy;
  if Assigned(FToggleItem) then
  begin
    if FToggleItem.Caption <> LCommand then
      FToggleItem.Caption := LCommand;
    if FToggleItem.Enabled <> not FBusy then
      FToggleItem.Enabled := not FBusy;
  end;
  if Assigned(FIDEPermissionItem) and (FIDEPermissionItem.Caption <> 'IDE : ' + LIDEPermissions) then
    FIDEPermissionItem.Caption := 'IDE : ' + LIDEPermissions;
  LCaption := DAIText('Projekt : ', 'Project : ', 'Projet : ', 'プロジェクト : ') + LProjectPermissions;
  if Assigned(FProjectPermissionItem) and (FProjectPermissionItem.Caption <> LCaption) then
    FProjectPermissionItem.Caption := LCaption;
end;

procedure TDAIToolbarController.Refresh;
begin
  // Timers run inside TrackPopupMenu too. Leave all IDE menu/toolbar UI stable
  // until tracking ends; the next refresh then applies the latest state.
  if FShuttingDown or FRefreshing or IDEMenuTracking then
    Exit;
  if Application.Terminated or (csDestroying in Application.ComponentState) then
    Exit;
  Inc(FCallbackDepth);
  FRefreshing := True;
  try
    try
      EnsureInstalled;
      if not FShuttingDown then
      begin
        UpdateRegistrationStatus;
        UpdateStatus;
      end;
    except
      on E: Exception do
        if not FShuttingDown then
          ReportError(E.ClassName + ': ' + E.Message);
    end;
  finally
    FRefreshing := False;
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.TimerTick(Sender: TObject);
begin
  Refresh;
end;

procedure TDAIToolbarController.ToggleServer(Sender: TObject);
var
  LResult: Boolean;
begin
  if FShuttingDown or FBusy then
    Exit;
  Inc(FCallbackDepth);
  FBusy := True;
  FActionError := '';
  try
    UpdateStatus;
    try
      if TDAIRuntime.ServerActive then
        LResult := TDAIRuntime.StopServer
      else
        LResult := TDAIRuntime.StartServer;
      if not LResult and (TDAIRuntime.LastServerError = '') then
        FActionError := DAIText('Der Serverzustand konnte nicht geändert werden.',
          'The server state could not be changed.',
          'Impossible de modifier l’état du serveur.',
          'サーバーの状態を変更できませんでした。');
    except
      on E: Exception do
        FActionError := E.ClassName + ': ' + E.Message;
    end;
  finally
    FBusy := False;
    if not FShuttingDown then
    begin
      FRegistrationDirty := True;
      UpdateRegistrationStatus;
      UpdateStatus;
    end;
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.OpenOptions(Sender: TObject);
var
  LServices: IOTAServices;
  LOptions: IOTAEnvironmentOptions;
begin
  if FShuttingDown then
    Exit;
  Inc(FCallbackDepth);
  try
    if Supports(BorlandIDEServices, IOTAServices, LServices) then
    begin
      LOptions := LServices.GetEnvironmentOptions;
      if Assigned(LOptions) then
        LOptions.EditOptions('', 'DAI');
      LOptions := nil;
      LServices := nil;
    end;
  finally
    if not FShuttingDown then
      UpdateStatus;
    LeaveCallback;
  end;
end;

procedure TDAIToolbarController.ResetSessionPermissions(Sender: TObject);
begin
  if FShuttingDown then
    Exit;
  Inc(FCallbackDepth);
  try
    TDAIPermissionManager.Instance.ClearAllSessions;
    UpdateStatus;
  finally
    LeaveCallback;
  end;
end;

class procedure TDAIIDEToolbar.Install;
begin
  RequireMainThread;
  if not Assigned(GController) then
  begin
    GController := TDAIToolbarController.Create;
    // Register before toolbar desktop restoration; UI creation still waits.
    GController.ActivateReadHooks;
  end;
end;

class procedure TDAIIDEToolbar.Refresh;
begin
  RequireMainThread;
  if Assigned(GController) then
    GController.Refresh;
end;

class procedure TDAIIDEToolbar.CheckRegistrations;
begin
  RequireMainThread;
  if Assigned(GController) then
  begin
    GController.FRegistrationDirty := True;
    GController.Refresh;
  end;
end;

class procedure TDAIIDEToolbar.SetUpdateAvailable(const AAvailable: Boolean; const AVersion: string);
begin
  RequireMainThread;
  FUpdateAvailable := AAvailable;
  if AAvailable then
    FUpdateVersion := Trim(AVersion)
  else
    FUpdateVersion := '';
  // Retain a known result before installation and across controller recreation.
  // Refresh defers all visible changes until native menu tracking has finished.
  Refresh;
end;

class procedure TDAIIDEToolbar.Shutdown;
var
  LController: TDAIToolbarController;
begin
  RequireMainThread;
  LController := GController;
  GController := nil;
  if Assigned(LController) then
    LController.Shutdown;
end;

initialization

finalization
  TDAIIDEToolbar.Shutdown;

end.
