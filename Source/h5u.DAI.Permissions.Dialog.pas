unit h5u.DAI.Permissions.Dialog;

interface

uses
  System.JSON,
  h5u.DAI.Types;

type
  TDAIPermissionPromptResult = record
  public
    Level: TDAIPermissionLevel;
    ApplyToLowerLevels: Boolean;
  end;

  TDAIPermissionDialog = class sealed
  public
    class function Ask(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext):
      TDAIPermissionPromptResult; static;
    class function SelectForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext; const ACurrentLevel: TDAIPermissionLevel;
      out AResult: TDAIPermissionPromptResult): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Forms,
  Winapi.Windows,
  h5u.DAI.Windows.Inspection;

type
  TPermissionWindowObserver = class
  private
    FHandle: HWND;
  public
    destructor Destroy; override;
    procedure DialogCreated(ASender: TObject);
    procedure DialogDestroyed(ASender: TObject);
  end;

const
  mrDAINever = 1101;
  mrDAIDeny = 1102;
  mrDAIOnce = 1103;
  mrDAISession = 1104;
  mrDAIAlways = 1105;
  mrDAIAsk = 1106;

destructor TPermissionWindowObserver.Destroy;
begin
  TDAIWindowService.UnregisterPermissionWindow(FHandle);
  inherited;
end;

procedure TPermissionWindowObserver.DialogCreated(ASender: TObject);
begin
  FHandle := TTaskDialog(ASender).Handle;
  TDAIWindowService.RegisterPermissionWindow(FHandle);
end;

procedure TPermissionWindowObserver.DialogDestroyed(ASender: TObject);
begin
  TDAIWindowService.UnregisterPermissionWindow(FHandle);
  FHandle := 0;
end;

procedure AddCommandButton(const ADialog: TTaskDialog; const ACaption: string; const AHint: string; const AModalResult: TModalResult; const ADefault: Boolean = False);
var
  LButton: TTaskDialogButtonItem;
begin
  LButton := TTaskDialogButtonItem(ADialog.Buttons.Add);
  LButton.Caption := ACaption;
  LButton.CommandLinkHint := AHint;
  LButton.ModalResult := AModalResult;
  LButton.Default := ADefault;
end;

function BuildDialogText(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext): string;
var
  LContextText: string;
begin
  LContextText := '';
  if Trim(AContext.ThreadId) <> '' then
    LContextText := sLineBreak + sLineBreak + 'KI-Chat: ' + AContext.ThreadId
  else if Trim(AContext.TransportSessionId) <> '' then
    LContextText := sLineBreak + sLineBreak + 'MCP-Sitzung: ' + AContext.TransportSessionId
  else
    LContextText := sLineBreak + sLineBreak + 'Hinweis: Der anfragende KI-Chat konnte nicht eindeutig identifiziert werden.';
  if AContext.ClientName <> '' then
    LContextText := LContextText + sLineBreak + 'Client: ' + AContext.ClientName;

  Result := DAIPermissionCategoryName(ACategory) + sLineBreak + sLineBreak + AOperation;
  if Trim(AResource) <> '' then
    Result := Result + sLineBreak + sLineBreak + 'Ziel: ' + AResource;
  if Trim(AContext.ProjectKey) = '' then
    Result := Result + sLineBreak + sLineBreak + 'Berechtigungsbereich: global'
  else
    Result := Result + sLineBreak + sLineBreak + 'Projekt: ' + AContext.ProjectKey;
  Result := Result + LContextText;
end;

function BuildOptionsText(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext): string;
begin
  Result := DAIPermissionCategoryName(ACategory) + sLineBreak + sLineBreak;
  if Trim(AContext.ProjectKey) = '' then
    Result := Result + 'Globaler Standard für Projekte ohne eigene Festlegung.'
  else
    Result := Result + 'Aktuelles Projekt: ' + AContext.ProjectKey;
  Result := Result + sLineBreak + sLineBreak + 'Die Auswahl wird erst beim Speichern der IDE-Optionen oder beim Registrieren übernommen.';
end;

function ExecutePermissionDialog(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext;
  const AForOptions: Boolean; const ACurrentLevel: TDAIPermissionLevel; out AResult: TDAIPermissionPromptResult): Boolean;
var
  LDialog: TTaskDialog;
  LObserver: TPermissionWindowObserver;
  LScopeText: string;
  LSessionCaption: string;
  LSessionHint: string;
begin
  Result := False;
  AResult.Level := plDeny;
  AResult.ApplyToLowerLevels := False;

  LDialog := TTaskDialog.Create(nil);
  LObserver := nil;
  try
    LObserver := TPermissionWindowObserver.Create;
    LDialog.OnDialogCreated := LObserver.DialogCreated;
    LDialog.OnDialogDestroyed := LObserver.DialogDestroyed;
    LDialog.Caption := 'DAI';
    if AForOptions then
    begin
      if Trim(AContext.ProjectKey) = '' then
      begin
        LDialog.Title := 'Berechtigung festlegen – global';
        LScopeText := 'als globalen Standard';
        LSessionCaption := 'Für diese IDE-Sitzung';
        LSessionHint := 'Für alle KI-Chats und Projekte dieser IDE bis zum Zurücksetzen der Sitzungsfreigaben oder zum Schließen der IDE zulassen.';
      end
      else
      begin
        LDialog.Title := 'Berechtigung festlegen – aktuelles Projekt';
        LScopeText := 'für das aktuelle Projekt';
        LSessionCaption := 'Für diese Projektsession';
        LSessionHint := 'Für alle KI-Chats des aktuellen Projekts bis zum Schließen des Projekts oder der IDE zulassen.';
      end;
      LDialog.Text := BuildOptionsText(ACategory, AContext);
    end
    else
    begin
      LDialog.Title := 'Zugriff durch Delphi AI';
      LDialog.Text := BuildDialogText(ACategory, AOperation, AResource, AContext);
      if Trim(AContext.ProjectKey) = '' then
      begin
        LScopeText := 'als globalen Standard';
        LSessionHint := 'Für diesen KI-Chat bis zum Zurücksetzen der Sitzungsfreigaben oder zum Schließen der Delphi-IDE zulassen.';
      end
      else
      begin
        LScopeText := 'für dieses Projekt';
        LSessionHint := 'Für diesen KI-Chat in diesem Projekt bis zum Zurücksetzen der Sitzungsfreigaben oder zum Schließen des Projekts oder der IDE zulassen.';
      end;
    end;
    LDialog.MainIcon := tdiShield;
    LDialog.CommonButtons := [];
    LDialog.Flags := [tfAllowDialogCancellation, tfUseCommandLinks];
    LDialog.VerificationText := 'Diese Auswahl für alle anderen Funktionalitäten mit einer geringeren Erlaubnisstufe übernehmen';

    AddCommandButton(
      LDialog,
      'Nie erlauben',
      'Diese Funktionalität ' + LScopeText + ' dauerhaft sperren.',
      mrDAINever,
      AForOptions and (ACurrentLevel = plNever)
    );
    if AForOptions then
    begin
      AddCommandButton(
        LDialog,
        'Nachfragen',
        'Für Zugriffe ' + LScopeText + ' jeweils nachfragen.',
        mrDAIAsk,
        ACurrentLevel = plAsk
      );
      AddCommandButton(
        LDialog,
        'Verweigern – nächste Anfrage',
        'Die nächste passende Anfrage ablehnen; danach wieder die gespeicherte Berechtigung verwenden.',
        mrDAIDeny,
        ACurrentLevel = plDeny
      );
      AddCommandButton(
        LDialog,
        'Nur einmal – nächste Anfrage',
        'Die nächste passende Anfrage zulassen; danach wieder die gespeicherte Berechtigung verwenden.',
        mrDAIOnce,
        ACurrentLevel = plOnce
      );
      AddCommandButton(
        LDialog,
        LSessionCaption,
        LSessionHint,
        mrDAISession,
        ACurrentLevel = plSession
      );
    end
    else
    begin
      AddCommandButton(
        LDialog,
        'Verweigern',
        'Nur diese konkrete Anfrage ablehnen. Bei der nächsten Anfrage erneut fragen.',
        mrDAIDeny
      );
      AddCommandButton(
        LDialog,
        'Nur diesmal',
        'Nur diese konkrete Anfrage zulassen.',
        mrDAIOnce,
        True
      );
      AddCommandButton(
        LDialog,
        'Für diese Session',
        LSessionHint,
        mrDAISession
      );
    end;
    AddCommandButton(
      LDialog,
      'Immer erlauben',
      'Diese Funktionalität ' + LScopeText + ' dauerhaft zulassen.',
      mrDAIAlways,
      AForOptions and (ACurrentLevel = plAlways)
    );

    if not LDialog.Execute then
      Exit;

    AResult.ApplyToLowerLevels := tfVerificationFlagChecked in LDialog.Flags;
    case LDialog.ModalResult of
      mrDAINever:
        AResult.Level := plNever;
      mrDAIDeny:
        AResult.Level := plDeny;
      mrDAIAsk:
        AResult.Level := plAsk;
      mrDAIOnce:
        AResult.Level := plOnce;
      mrDAISession:
        AResult.Level := plSession;
      mrDAIAlways:
        AResult.Level := plAlways;
    else
      Exit;
    end;
    Result := True;
  finally
    try
      LDialog.Free;
    finally
      LObserver.Free;
    end;
  end;
end;

class function TDAIPermissionDialog.Ask(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext):
  TDAIPermissionPromptResult;
begin
  ExecutePermissionDialog(ACategory, AOperation, AResource, AContext, False, plOnce, Result);
end;

class function TDAIPermissionDialog.SelectForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext;
  const ACurrentLevel: TDAIPermissionLevel; out AResult: TDAIPermissionPromptResult): Boolean;
begin
  Result := ExecutePermissionDialog(ACategory, '', '', AContext, True, ACurrentLevel, AResult);
end;

end.
