unit h5u.DAI.IDE.Notifier;

interface

uses
  ToolsAPI;

type
  TDAIIDENotifier = class(TNotifierObject, IOTAIDENotifier)
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
    procedure AfterCompile(Succeeded: Boolean);
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  h5u.DAI.OTA.Build,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Permissions.Manager;

procedure TDAIIDENotifier.AfterCompile(Succeeded: Boolean);
begin
end;

procedure TDAIIDENotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TDAIIDENotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
var
  LExtension: string;
begin
  if NotifyCode <> ofnFileClosing then
    Exit;

  LExtension := LowerCase(TPath.GetExtension(FileName));
  if LExtension = '.groupproj' then
  begin
    TDAIPermissionManager.Instance.ClearAllSessions;
    Exit;
  end;

  if MatchStr(LExtension, ['.dproj', '.dpr', '.dpk', '.cbproj']) then
  begin
    TDAIPermissionManager.Instance.ClearProjectSession(FileName);
    TDAIBuildService.ClearProjectProcess(FileName);
  end;
end;

end.
