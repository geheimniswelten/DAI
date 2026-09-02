unit h5u.DAI.Register;

interface

procedure Register;

implementation

uses
  ToolsAPI,
  h5u.DAI.Wizard;

procedure Register;
begin
  RegisterPackageWizard(TDAIWizard.Create);
end;

end.
