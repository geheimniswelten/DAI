unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var TestProject: IOTAProject;
    class var DispatchDepth, DispatchCount, LookupCount: Integer;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function ProjectByNameOrPath(const AProject: string): IOTAProject; static;
    class function NormalizeFileName(const AFile: string): string; static;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  Inc(DispatchDepth);
  Inc(DispatchCount);
  try AAction(); finally Dec(DispatchDepth); end;
end;

class function TDAIOTA.ProjectByNameOrPath(const AProject: string): IOTAProject;
begin
  if DispatchDepth = 0 then
    raise EInvalidOperation.Create('Lookup must use the IDE thread.');
  Inc(LookupCount);
  Result := nil;
  if Assigned(TestProject) then
    if (AProject = '') or SameText(AProject, TestProject.FileName) or SameText(AProject, 'Selected') then
      Result := TestProject;
end;

class function TDAIOTA.NormalizeFileName(const AFile: string): string;
begin
  Result := TPath.GetFullPath(AFile);
end;

end.
