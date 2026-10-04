unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var TestProjects: TArray<IOTAProject>;
    class var TestActiveProject: IOTAProject;
    class var DispatchDepth, DispatchCalls: Integer;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function ProjectByNameOrPath(const ANameOrPath: string): IOTAProject; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  Inc(DispatchCalls);
  Inc(DispatchDepth);
  try
    AAction();
  finally
    Dec(DispatchDepth);
  end;
end;

class function TDAIOTA.ProjectByNameOrPath(const ANameOrPath: string): IOTAProject;
var
  LProject: IOTAProject;
begin
  if DispatchDepth = 0 then
    raise EInvalidOperation.Create('Project lookup must run on the IDE thread.');
  if Trim(ANameOrPath) = '' then
    Exit(TestActiveProject);
  Result := nil;
  for LProject in TestProjects do
    if SameText(LProject.FileName, ANameOrPath) or SameText(TPath.GetFileNameWithoutExtension(LProject.FileName), ANameOrPath) then
      Exit(LProject);
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  if AFileName = '' then
    Exit('');
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AFileName));
end;

class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(NormalizeFileName(ALeft), NormalizeFileName(ARight));
end;

end.
