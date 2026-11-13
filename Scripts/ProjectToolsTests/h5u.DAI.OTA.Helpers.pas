unit h5u.DAI.OTA.Helpers;
interface
uses System.SysUtils, ToolsAPI;
type
  TDAIOTA = class sealed
  public
    class procedure RunOnMainThread(const AProc: TProc); static;
    class function ProjectByNameOrPath(const AName: string): IOTAProject; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
  end;
var
  TestProjectFile: string;
  TestProjectLoaded: Boolean = True;
  TestDispatchDepth: Integer;
implementation
uses System.Classes, Winapi.Windows;
type
  TTestProject = class(TInterfacedObject, IOTAProject)
    function FileName: string;
  end;
function TTestProject.FileName: string;
begin Result := TestProjectFile; end;
class procedure TDAIOTA.RunOnMainThread(const AProc: TProc);
begin
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('Fixture requires its main thread.');
  Inc(TestDispatchDepth);
  try AProc(); finally Dec(TestDispatchDepth); end;
end;
class function TDAIOTA.ProjectByNameOrPath(const AName: string): IOTAProject;
begin
  if TestDispatchDepth = 0 then raise EInvalidOperation.Create('Project lookup outside main-thread dispatch.');
  Result := nil;
  if TestProjectLoaded and SameText(AName, TestProjectFile) then Result := TTestProject.Create;
end;
class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin Result := AProject.FileName; end;
end.
