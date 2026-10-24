unit h5u.DAI.Permissions.Dialog;

interface

uses
  h5u.DAI.Types;

type
  TDAIPermissionPromptResult = record
    Level: TDAIPermissionLevel;
    ApplyGlobally: Boolean;
  end;

  TDAIPermissionDialog = class sealed
  private
    class var FPending: Boolean;
    class var FDecision: TDAIPermissionPromptResult;
  public
    class procedure QueueDecision(const ALevel: TDAIPermissionLevel; const AGlobal: Boolean); static;
    class function Ask(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
      const AContext: TDAIRequestContext): TDAIPermissionPromptResult; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils;

class function TDAIPermissionDialog.Ask(const ACategory: TDAIPermissionCategory; const AOperation, AResource: string;
  const AContext: TDAIRequestContext): TDAIPermissionPromptResult;
begin
  if not FPending then
    raise EInvalidOperation.Create('The isolated permission-options tests must not display an authorization dialog.');
  FPending := False;
  Result := FDecision;
end;

class procedure TDAIPermissionDialog.QueueDecision(const ALevel: TDAIPermissionLevel; const AGlobal: Boolean);
begin
  FDecision.Level := ALevel;
  FDecision.ApplyGlobally := AGlobal;
  FPending := True;
end;

end.
