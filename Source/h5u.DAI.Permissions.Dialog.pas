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
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Forms;
const
  mrDAINever = 1101;
  mrDAIDeny = 1102;
  mrDAIOnce = 1103;
  mrDAISession = 1104;
  mrDAIAlways = 1105;

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
  Result := Result + LContextText;
end;

class function TDAIPermissionDialog.Ask(const ACategory: TDAIPermissionCategory; const AOperation: string; const AResource: string; const AContext: TDAIRequestContext):
  TDAIPermissionPromptResult;
var
  LDialog: TTaskDialog;
begin
  Result.Level := plDeny;
  Result.ApplyToLowerLevels := False;

  LDialog := TTaskDialog.Create(nil);
  try
    LDialog.Caption := 'DAI';
    LDialog.Title := 'Zugriff durch Delphi AI';
    LDialog.Text := BuildDialogText(ACategory, AOperation, AResource, AContext);
    LDialog.MainIcon := tdiShield;
    LDialog.CommonButtons := [];
    LDialog.Flags := [tfAllowDialogCancellation, tfUseCommandLinks];
    LDialog.VerificationText := 'Diese Auswahl für alle anderen Funktionalitäten mit einer geringeren Erlaubnisstufe übernehmen';

    AddCommandButton(
      LDialog,
      'Nie erlauben',
      'Diese Funktionalität für das aktuelle Projekt dauerhaft sperren.',
      mrDAINever
    );
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
      'Bis zum Schließen des Projekts oder der Delphi-IDE für diesen KI-Chat zulassen.',
      mrDAISession
    );
    AddCommandButton(
      LDialog,
      'Immer erlauben',
      'Diese Funktionalität für das aktuelle Projekt dauerhaft zulassen.',
      mrDAIAlways
    );

    if not LDialog.Execute then
      Exit;

    case LDialog.ModalResult of
      mrDAINever:
        Result.Level := plNever;
      mrDAIDeny:
        Result.Level := plDeny;
      mrDAIOnce:
        Result.Level := plOnce;
      mrDAISession:
        Result.Level := plSession;
      mrDAIAlways:
        Result.Level := plAlways;
    else
      Result.Level := plDeny;
    end;

    Result.ApplyToLowerLevels := tfVerificationFlagChecked in LDialog.Flags;
  finally
    LDialog.Free;
  end;
end;

end.
