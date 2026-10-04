unit h5u.DAI.OTA.Helpers;
interface
uses System.Classes, ToolsAPI;
type TDAIOTA = class sealed
  public
    class var TestProject, OtherProject, Active: IOTAProject;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function ActiveProject: IOTAProject; static;
    class function ProjectByNameOrPath(const AName: string): IOTAProject; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
  end;
implementation
uses System.SysUtils, Winapi.Windows;
class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  if GetCurrentThreadId <> MainThreadID then raise EInvalidOperation.Create('Wrong IDE thread.');
  AAction();
end;
class function TDAIOTA.ActiveProject: IOTAProject;
begin Result := Active; end;
class function TDAIOTA.ProjectByNameOrPath(const AName: string): IOTAProject;
begin
  Result := nil;
  if TestProject <> nil then
    if SameText(AName, 'Selected') or SameText(AName, TestProject.FileName) then Exit(TestProject);
  if OtherProject <> nil then
    if SameText(AName, 'Other') or SameText(AName, OtherProject.FileName) then Exit(OtherProject);
end;
class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin Result := SameText(ALeft, ARight); end;
end.
