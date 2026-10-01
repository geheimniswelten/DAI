unit h5u.DAI.OTA.Helpers;

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var TestProjects: TArray<IOTAProject>;
    class var TestGroup: IOTAProjectGroup;
    class var LastSelectedProject: IOTAProject;
    class var DispatchDepth: Integer;
    class var WritePreflightCount: Integer;
    class procedure RunOnMainThread(const AProc: TProc); static;
    class function ProjectByNameOrPath(const AProjectNameOrPath: string): IOTAProject; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
    class function ProjectTargetName(const AProject: IOTAProject): string; static;
    class function MainProjectGroup: IOTAProjectGroup; static;
    class function Projects: TArray<IOTAProject>; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const AFirst, ASecond: string): Boolean; static;
    class procedure RequireNoReparseWritePath(const AFileName: string); static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.IOUtils;

class procedure TDAIOTA.RunOnMainThread(const AProc: TProc);
begin
  // Synthetic dispatcher; the actual production Build service owns the complete call/return sequence.
  Inc(DispatchDepth);
  try
    AProc();
  finally
    Dec(DispatchDepth);
  end;
end;

class function TDAIOTA.ProjectByNameOrPath(const AProjectNameOrPath: string): IOTAProject;
var
  LProject: IOTAProject;
begin
  Result := nil;
  for LProject in TestProjects do
    if Assigned(LProject) and SameText(LProject.FileName, AProjectNameOrPath) then
      Exit(LProject);
end;

class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin
  Result := AProject.FileName;
end;

class function TDAIOTA.ProjectTargetName(const AProject: IOTAProject): string;
begin
  Result := ChangeFileExt(AProject.FileName, '.exe');
end;

class function TDAIOTA.MainProjectGroup: IOTAProjectGroup;
begin
  Result := TestGroup;
end;

class function TDAIOTA.Projects: TArray<IOTAProject>;
begin
  Result := Copy(TestProjects);
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  Result := TPath.GetFullPath(AFileName);
end;

class function TDAIOTA.SameFile(const AFirst, ASecond: string): Boolean;
begin
  Result := SameText(NormalizeFileName(AFirst), NormalizeFileName(ASecond));
end;

class procedure TDAIOTA.RequireNoReparseWritePath(const AFileName: string);
begin
  Inc(WritePreflightCount);
end;

class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin
  Result := False;
end;

end.
