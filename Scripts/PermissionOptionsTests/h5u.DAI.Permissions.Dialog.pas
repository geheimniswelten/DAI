unit h5u.DAI.Permissions.Dialog;

interface

uses
  h5u.DAI.Types;

type
  TDAIPermissionPromptResult = record
    Level: TDAIPermissionLevel;
    ApplyToLowerLevels: Boolean;
  end;

  TDAIPermissionDialog = class sealed
  public
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
  raise EInvalidOperation.Create('The isolated permission-options tests must not display an authorization dialog.');
end;

end.
