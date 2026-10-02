unit DAI.Toolbar.PackageProbe;

interface

procedure PrepareHost(const AHost: IInterface); stdcall;
procedure InstallToolbar; stdcall;

implementation

uses
  ToolsAPI,
  h5u.DAI.IDE.Toolbar;

procedure PrepareHost(const AHost: IInterface);
begin
  BorlandIDEServices := AHost;
end;

procedure InstallToolbar;
begin
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
end;

end.
