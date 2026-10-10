unit h5u.DAI.Permissions.Dialog;

interface

uses
  h5u.DAI.Types;

type
  TDAIPermissionPromptResult = record
    Level: TDAIPermissionLevel;
    ApplyToLowerLevels: Boolean;
  end;

  // Options tests stage synthetic answers without displaying a permission dialog.
  TDAIPermissionDialog = class sealed
  public
    class var NextAccepted: Boolean;
    class var NextLevel: TDAIPermissionLevel;
    class var NextApplyToLowerLevels: Boolean;
    class var CallCount: Integer;
    class var LastCategory: TDAIPermissionCategory;
    class var LastProjectKey: string;
    class var LastCurrentLevel: TDAIPermissionLevel;
    class procedure Reset; static;
    class function SelectForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext;
      const ACurrentLevel: TDAIPermissionLevel; out APrompt: TDAIPermissionPromptResult): Boolean; static;
  end;

implementation

class procedure TDAIPermissionDialog.Reset;
begin
  NextAccepted := False;
  NextLevel := plAsk;
  NextApplyToLowerLevels := False;
  CallCount := 0;
  LastProjectKey := '';
  LastCurrentLevel := plAsk;
end;

class function TDAIPermissionDialog.SelectForOptions(const ACategory: TDAIPermissionCategory; const AContext: TDAIRequestContext;
  const ACurrentLevel: TDAIPermissionLevel; out APrompt: TDAIPermissionPromptResult): Boolean;
begin
  Inc(CallCount);
  LastCategory := ACategory;
  LastProjectKey := AContext.ProjectKey;
  LastCurrentLevel := ACurrentLevel;
  APrompt.Level := NextLevel;
  APrompt.ApplyToLowerLevels := NextApplyToLowerLevels;
  Result := NextAccepted;
end;

end.
