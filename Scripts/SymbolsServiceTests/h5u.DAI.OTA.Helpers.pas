unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class var TestActiveProject: IOTAProject;
    class var TestGroup: IOTAProjectGroup;
    class var TestProjects: TArray<IOTAProject>;
    class function ActiveProject: IOTAProject; static;
    class function MainProjectGroup: IOTAProjectGroup; static;
    class function Projects: TArray<IOTAProject>; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class procedure RequireNoReparseWritePath(const AFileName: string); static;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows;

class function TDAIOTA.ActiveProject: IOTAProject;
begin
  Result := TestActiveProject;
end;

class function TDAIOTA.MainProjectGroup: IOTAProjectGroup;
begin
  Result := TestGroup;
end;

class function TDAIOTA.Projects: TArray<IOTAProject>;
begin
  Result := TestProjects;
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  Result := TPath.GetFullPath(AFileName);
end;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  // The test model is immutable while worker reads are in progress.
  AAction();
end;

class procedure TDAIOTA.RequireNoReparseWritePath(const AFileName: string);
var
  LPath: string;
  LAttributes: DWORD;
begin
  LPath := TPath.GetFullPath(AFileName);
  while LPath <> '' do
  begin
    LAttributes := GetFileAttributes(PChar(LPath));
    if (LAttributes <> INVALID_FILE_ATTRIBUTES) and ((LAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
      raise EInvalidOperation.Create('Test fixture refused a reparse write path.');
    LPath := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(LPath));
  end;
end;

end.
