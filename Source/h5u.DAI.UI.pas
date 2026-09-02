unit h5u.DAI.UI;

interface

uses
  System.JSON;

type
  TDAIUIService = class sealed
  public
    class function ShowMessage(const ATitle: string; const AText: string; const AKind: string): TJSONObject; static;
    class function AskInput(const ATitle: string; const APrompt: string; const ADefaultValue: string): TJSONObject; static;
    class function ShowBalloon(const ATitle: string; const AText: string; const ATimeoutMs: Integer): TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms;

var
  GBalloonHint: TBalloonHint;

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
  FreeAndNil(GBalloonHint);
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

finalization
  TDAIUIService.Shutdown;

end.
