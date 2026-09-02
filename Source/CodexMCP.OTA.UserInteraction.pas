unit CodexMCP.OTA.UserInteraction;

interface

uses
  System.JSON;

type
  TCodexMCPUserInteraction = class sealed
  strict private
    class var FBalloonHint: TObject;
    class constructor Create;
    class destructor Destroy;
  public
    class function ShowMessageBox(
      const ATitle,
      AText,
      AKind,
      AButtons: string
    ): TJSONObject; static;
    class function ShowInputBox(
      const ATitle,
      APrompt,
      ADefaultValue: string
    ): TJSONObject; static;
    class function ShowBalloonHint(
      const ATitle,
      AText: string;
      const ATimeoutMs: Integer
    ): TJSONObject; static;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms,
  CodexMCP.Json,
  CodexMCP.Threading;

function DialogType(const AKind: string): TMsgDlgType;
begin
  if SameText(AKind, 'warning') then
    Result := mtWarning
  else if SameText(AKind, 'error') then
    Result := mtError
  else if SameText(AKind, 'confirmation') then
    Result := mtConfirmation
  else
    Result := mtInformation;
end;

function DialogButtons(const AButtons: string): TMsgDlgButtons;
begin
  if SameText(AButtons, 'ok_cancel') then
    Result := [mbOK, mbCancel]
  else if SameText(AButtons, 'yes_no') then
    Result := [mbYes, mbNo]
  else if SameText(AButtons, 'yes_no_cancel') then
    Result := [mbYes, mbNo, mbCancel]
  else
    Result := [mbOK];
end;

function ModalResultName(const AResult: TModalResult): string;
begin
  case AResult of
    mrOK:
      Result := 'ok';
    mrCancel:
      Result := 'cancel';
    mrYes:
      Result := 'yes';
    mrNo:
      Result := 'no';
    mrAbort:
      Result := 'abort';
    mrRetry:
      Result := 'retry';
    mrIgnore:
      Result := 'ignore';
  else
    Result := IntToStr(AResult);
  end;
end;

{ TCodexMCPUserInteraction }

class constructor TCodexMCPUserInteraction.Create;
begin
  FBalloonHint := nil;
end;

class destructor TCodexMCPUserInteraction.Destroy;
begin
  FBalloonHint.Free;
  FBalloonHint := nil;
end;

class function TCodexMCPUserInteraction.ShowBalloonHint(
  const ATitle,
  AText: string;
  const ATimeoutMs: Integer
): TJSONObject;
var
  LShown: Boolean;
begin
  LShown := False;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    var
      LBalloon: TBalloonHint;
    begin
      if not Assigned(Application.MainForm) then
        raise EInvalidOpException.Create('Das Hauptfenster der IDE ist nicht verfügbar.');
      if not Assigned(FBalloonHint) then
        FBalloonHint := TBalloonHint.Create(nil);
      LBalloon := TBalloonHint(FBalloonHint);
      LBalloon.Delay := 0;
      LBalloon.HideAfter := EnsureRange(ATimeoutMs, 1000, 60000);
      LBalloon.Title := ATitle;
      LBalloon.Description := AText;
      LBalloon.ShowHint(Application.MainForm);
      LShown := True;
    end
  );
  Result := JsonSuccess;
  Result.AddPair('shown', TJSONBool.Create(LShown));
end;

class function TCodexMCPUserInteraction.ShowInputBox(
  const ATitle,
  APrompt,
  ADefaultValue: string
): TJSONObject;
var
  LAccepted: Boolean;
  LValue: string;
begin
  LValue := ADefaultValue;
  LAccepted := False;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    begin
      LAccepted := InputQuery(ATitle, APrompt, LValue);
    end
  );
  Result := JsonSuccess;
  Result.AddPair('accepted', TJSONBool.Create(LAccepted));
  Result.AddPair('value', LValue);
end;

class function TCodexMCPUserInteraction.ShowMessageBox(
  const ATitle,
  AText,
  AKind,
  AButtons: string
): TJSONObject;
var
  LModalResult: TModalResult;
begin
  LModalResult := mrNone;
  TCodexMCPThreading.RunInIDEThread(
    procedure
    begin
      LModalResult := MessageDlg(
        ATitle,
        AText,
        DialogType(AKind),
        DialogButtons(AButtons),
        0
      );
    end
  );
  Result := JsonSuccess;
  Result.AddPair('result', ModalResultName(LModalResult));
end;

end.
