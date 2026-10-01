unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function FindModuleByFileName(const AFileName: string): IOTAModule; static;
    class function FindSourceEditor(const AFileName: string): IOTASourceEditor; static;
    class function IsFileOpenInEditor(const AFileName: string): Boolean; static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function ProjectByNameOrPath(const AProjectName: string): IOTAProject; static;
  end;

var
  TestSourceEditor: IOTASourceEditor;

implementation

uses
  System.IOUtils,
  Winapi.Windows;

class function TDAIOTA.FindModuleByFileName(const AFileName: string): IOTAModule;
begin
  Result := nil;
end;

class function TDAIOTA.FindSourceEditor(const AFileName: string): IOTASourceEditor;
begin
  Result := TestSourceEditor;
end;

class function TDAIOTA.IsFileOpenInEditor(const AFileName: string): Boolean;
begin
  Result := True;
end;

class function TDAIOTA.IsWorkspaceFile(const AFileName: string): Boolean;
begin
  Result := True;
end;

class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
begin
  Result := False;
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  Result := TPath.GetFullPath(AFileName);
end;

class function TDAIOTA.ProjectByNameOrPath(const AProjectName: string): IOTAProject;
begin
  Result := nil;
end;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  if GetCurrentThreadId = MainThreadID then
    AAction()
  else
    TThread.Synchronize(nil, AAction);
end;

end.
