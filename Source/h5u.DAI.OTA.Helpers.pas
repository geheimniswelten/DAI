unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes,
  ToolsAPI;

type
  TDAIOTA = class sealed
  public
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function ActiveProject: IOTAProject; static;
    class function ActiveProjectFileName: string; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
    class function ProjectConfiguration(const AProject: IOTAProject): string; static;
    class function ProjectPlatform(const AProject: IOTAProject): string; static;
    class function ProjectTargetName(const AProject: IOTAProject): string; static;
    class function MainProjectGroup: IOTAProjectGroup; static;
    class function ProjectByNameOrPath(const ANameOrPath: string): IOTAProject; static;
    class function Projects: TArray<IOTAProject>; static;
    class function FindModuleByFileName(const AFileName: string): IOTAModule; static;
    class function FindSourceEditor(const AFileName: string): IOTASourceEditor; static;
    class function ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean; static;
    class function ProjectForFile(const AFileName: string): IOTAProject; static;
    class function IsFileOpenInEditor(const AFileName: string): Boolean; static;
    class function IsFormLoadedForFile(const AFileName: string): Boolean; static;
    class function ReadEditorText(const ASourceEditor: IOTASourceEditor): string; static;
    class function ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string): Boolean; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const ALeft: string; const ARight: string): Boolean; static;
    class function IsPathWithin(const AFileName: string; const ARootDirectory: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function WorkspaceRoots: TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Settings;

const
  CEditReaderChunkSize = 8192;

class function TDAIOTA.ActiveProject: IOTAProject;
var
  LResult: IOTAProject;
begin
  LResult := nil;
  RunOnMainThread(
    procedure var LModuleServices: IOTAModuleServices;
    begin
      if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        LResult := LModuleServices.GetActiveProject;
    end);
  Result := LResult;
end;

class function TDAIOTA.ActiveProjectFileName: string;
var
  LResult: string;
begin
  LResult := '';
  RunOnMainThread(
    procedure var LModuleServices: IOTAModuleServices;
      LProject: IOTAProject;
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        Exit;
      LProject := LModuleServices.GetActiveProject;
      if Assigned(LProject) then
        LResult := NormalizeFileName(LProject.FileName);
    end);
  Result := LResult;
end;

class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
var
  LResult: string;
begin
  LResult := '';
  RunOnMainThread(
    procedure
    begin
      if Assigned(AProject) then
        LResult := NormalizeFileName(AProject.FileName);
    end);
  Result := LResult;
end;

class function TDAIOTA.ProjectConfiguration(const AProject: IOTAProject): string;
var
  LResult: string;
begin
  LResult := '';
  RunOnMainThread(
    procedure
    begin
      if Assigned(AProject) then
        LResult := AProject.CurrentConfiguration;
    end);
  Result := LResult;
end;

class function TDAIOTA.ProjectPlatform(const AProject: IOTAProject): string;
var
  LResult: string;
begin
  LResult := '';
  RunOnMainThread(
    procedure
    begin
      if Assigned(AProject) then
        LResult := AProject.CurrentPlatform;
    end);
  Result := LResult;
end;

class function TDAIOTA.ProjectTargetName(const AProject: IOTAProject): string;
var
  LResult: string;
begin
  LResult := '';
  RunOnMainThread(
    procedure
    begin
      if Assigned(AProject) and Assigned(AProject.ProjectOptions) then
        LResult := AProject.ProjectOptions.TargetName;
    end);
  Result := LResult;
end;

class function TDAIOTA.FindModuleByFileName(const AFileName: string): IOTAModule;
var
  LResult: IOTAModule;
begin
  LResult := nil;
  RunOnMainThread(
    procedure var LEditorIndex: Integer;
      LModuleIndex: Integer;
      LModuleServices: IOTAModuleServices;
      LModule: IOTAModule;
      LEditor: IOTAEditor;
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        Exit;

      LResult := LModuleServices.FindModule(AFileName);
      if Assigned(LResult) then
        Exit;

      for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
      begin
        LModule := LModuleServices.Modules[LModuleIndex];
        if not Assigned(LModule) then
          Continue;
        if SameFile(LModule.FileName, AFileName) then
        begin
          LResult := LModule;
          Exit;
        end;

        for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
        begin
          LEditor := LModule.ModuleFileEditors[LEditorIndex];
          if Assigned(LEditor) and SameFile(LEditor.FileName, AFileName) then
          begin
            LResult := LModule;
            Exit;
          end;
        end;
      end;
    end);
  Result := LResult;
end;

class function TDAIOTA.FindSourceEditor(const AFileName: string): IOTASourceEditor;
var
  LResult: IOTASourceEditor;
begin
  LResult := nil;
  RunOnMainThread(
    procedure var LEditorIndex: Integer;
      LModuleIndex: Integer;
      LModuleServices: IOTAModuleServices;
      LModule: IOTAModule;
      LSourceEditor: IOTASourceEditor;
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        Exit;

      for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
      begin
        LModule := LModuleServices.Modules[LModuleIndex];
        if not Assigned(LModule) then
          Continue;

        for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
          if Supports(LModule.ModuleFileEditors[LEditorIndex], IOTASourceEditor, LSourceEditor) and
             SameFile(LSourceEditor.FileName, AFileName) then
          begin
            LResult := LSourceEditor;
            Exit;
          end;
      end;
    end);
  Result := LResult;
end;

class function TDAIOTA.IsFileOpenInEditor(const AFileName: string): Boolean;
begin
  Result := Assigned(FindSourceEditor(AFileName));
end;

class function TDAIOTA.IsFormLoadedForFile(const AFileName: string): Boolean;
var
  LResult: Boolean;
begin
  LResult := False;
  RunOnMainThread(
    procedure var LEditorIndex: Integer;
      LModule: IOTAModule;
      LFormEditor: IOTAFormEditor;
    begin
      LModule := FindModuleByFileName(AFileName);
      if not Assigned(LModule) then
        Exit;
      for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
        if Supports(LModule.ModuleFileEditors[LEditorIndex], IOTAFormEditor, LFormEditor) then
        begin
          LResult := True;
          Exit;
        end;
    end);
  Result := LResult;
end;

class function TDAIOTA.IsPathWithin(const AFileName: string; const ARootDirectory: string): Boolean;
var
  LFileName: string;
  LRoot: string;
begin
  Result := False;
  if (Trim(AFileName) = '') or (Trim(ARootDirectory) = '') then
    Exit;

  try
    LFileName := NormalizeFileName(AFileName);
    LRoot := IncludeTrailingPathDelimiter(NormalizeFileName(ARootDirectory));
    Result := LFileName.StartsWith(LRoot, True);
  except
    Result := False;
  end;
end;

class function TDAIOTA.IsReadOnlyReferenceFile(const AFileName: string): Boolean;
var
  LRoot: string;
begin
  Result := False;
  for LRoot in TDAISettings.Instance.ReadOnlyRootDirectories do
    if IsPathWithin(AFileName, LRoot) then
      Exit(True);
end;

class function TDAIOTA.IsWorkspaceFile(const AFileName: string): Boolean;
var
  LProject: IOTAProject;
  LRoot: string;
begin
  if IsReadOnlyReferenceFile(AFileName) then
    Exit(False);

  for LProject in Projects do
    if ProjectContainsFile(LProject, AFileName) then
      Exit(True);

  for LRoot in WorkspaceRoots do
    if IsPathWithin(AFileName, LRoot) then
      Exit(True);

  Result := IsFileOpenInEditor(AFileName);
end;

class function TDAIOTA.MainProjectGroup: IOTAProjectGroup;
var
  LResult: IOTAProjectGroup;
begin
  LResult := nil;
  RunOnMainThread(
    procedure var LModuleServices: IOTAModuleServices;
    begin
      if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        LResult := LModuleServices.MainProjectGroup;
    end);
  Result := LResult;
end;

class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin
  if Trim(AFileName) = '' then
    Exit('');
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AFileName));
end;

class function TDAIOTA.ProjectByNameOrPath(const ANameOrPath: string): IOTAProject;
var
  LResult: IOTAProject;
begin
  LResult := nil;
  RunOnMainThread(
    procedure var LGroup: IOTAProjectGroup;
      LIndex: Integer;
      LModuleServices: IOTAModuleServices;
      LProject: IOTAProject;
      LProjectBase: string;
      LProjectFile: string;
      LQuery: string;
      LQueryBase: string;
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        Exit;
      LQuery := Trim(ANameOrPath);
      if TPath.IsPathRooted(LQuery) then
      begin
        LQuery := NormalizeFileName(LQuery);
        LQueryBase := ChangeFileExt(LQuery, '');
      end
      else
        LQueryBase := LQuery;

      LGroup := LModuleServices.MainProjectGroup;
      if Assigned(LGroup) then
      begin
        for LIndex := 0 to LGroup.ProjectCount - 1 do
        begin
          LProject := LGroup.Projects[LIndex];
          if not Assigned(LProject) then
            Continue;
          if LQuery = '' then
          begin
            LResult := LProject;
            Exit;
          end;
          LProjectFile := NormalizeFileName(LProject.FileName);
          LProjectBase := ChangeFileExt(LProjectFile, '');
          if SameText(LProjectFile, LQuery) or SameText(LProjectBase, LQueryBase) or
             SameText(TPath.GetFileName(LProjectFile), ANameOrPath) or
             SameText(TPath.GetFileNameWithoutExtension(LProjectFile), ANameOrPath) then
          begin
            LResult := LProject;
            Exit;
          end;
        end;
        Exit;
      end;

      LProject := LModuleServices.GetActiveProject;
      if not Assigned(LProject) then
        Exit;
      if LQuery = '' then
      begin
        LResult := LProject;
        Exit;
      end;
      LProjectFile := NormalizeFileName(LProject.FileName);
      LProjectBase := ChangeFileExt(LProjectFile, '');
      if SameText(LProjectFile, LQuery) or SameText(LProjectBase, LQueryBase) or
         SameText(TPath.GetFileName(LProjectFile), ANameOrPath) or
         SameText(TPath.GetFileNameWithoutExtension(LProjectFile), ANameOrPath) then
        LResult := LProject;
    end);
  Result := LResult;
end;

class function TDAIOTA.ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean;
var
  LResult: Boolean;
begin
  LResult := False;
  RunOnMainThread(
    procedure var LIndex: Integer;
      LModuleInfo: IOTAModuleInfo;
    begin
      if not Assigned(AProject) then
        Exit;
      for LIndex := 0 to AProject.GetModuleCount - 1 do
      begin
        LModuleInfo := AProject.GetModule(LIndex);
        if Assigned(LModuleInfo) and SameFile(LModuleInfo.FileName, AFileName) then
        begin
          LResult := True;
          Exit;
        end;
      end;
    end);
  Result := LResult;
end;

class function TDAIOTA.ProjectForFile(const AFileName: string): IOTAProject;
var
  LProject: IOTAProject;
  LProjectFileName: string;
begin
  Result := nil;
  for LProject in Projects do
  begin
    LProjectFileName := ProjectFileName(LProject);
    if ProjectContainsFile(LProject, AFileName) or IsPathWithin(AFileName, TPath.GetDirectoryName(LProjectFileName)) then
      Exit(LProject);
  end;
end;

class function TDAIOTA.Projects: TArray<IOTAProject>;
var
  LResult: TArray<IOTAProject>;
begin
  LResult := [];
  RunOnMainThread(
    procedure var LGroup: IOTAProjectGroup;
      LIndex: Integer;
      LModuleServices: IOTAModuleServices;
      LProject: IOTAProject;
    begin
      if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        Exit;

      LGroup := LModuleServices.MainProjectGroup;
      if Assigned(LGroup) then
      begin
        SetLength(LResult, LGroup.ProjectCount);
        for LIndex := 0 to LGroup.ProjectCount - 1 do
          LResult[LIndex] := LGroup.Projects[LIndex];
        Exit;
      end;

      LProject := LModuleServices.GetActiveProject;
      if Assigned(LProject) then
        LResult := [LProject];
    end);
  Result := LResult;
end;

class function TDAIOTA.ReadEditorText(const ASourceEditor: IOTASourceEditor): string;
var
  LBuffer: TBytes;
  LBytesRead: Integer;
  LOffset: Integer;
  LReader: IOTAEditReader;
  LTextBytes: TBytes;
begin
  Result := '';
  if not Assigned(ASourceEditor) then
    Exit;

  LReader := ASourceEditor.CreateReader;
  if not Assigned(LReader) then
    Exit;

  SetLength(LBuffer, CEditReaderChunkSize);
  LOffset := 0;
  repeat
    LBytesRead := LReader.GetText(LOffset, PAnsiChar(@LBuffer[0]), Length(LBuffer));
    if LBytesRead > 0 then
    begin
      SetLength(LTextBytes, Length(LTextBytes) + LBytesRead);
      Move(LBuffer[0], LTextBytes[Length(LTextBytes) - LBytesRead], LBytesRead);
      Inc(LOffset, LBytesRead);
    end;
  until LBytesRead < Length(LBuffer);

  if Length(LTextBytes) > 0 then
    Result := TEncoding.UTF8.GetString(LTextBytes);
  if Result.EndsWith(#0) then
    Delete(Result, Length(Result), 1);
end;

class function TDAIOTA.ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string): Boolean;
var
  LCurrentBytes: TBytes;
  LCurrentText: string;
  LNewText: UTF8String;
  LWriter: IOTAEditWriter;
begin
  Result := False;
  if not Assigned(ASourceEditor) then
    Exit;

  LCurrentText := ReadEditorText(ASourceEditor);
  LCurrentBytes := TEncoding.UTF8.GetBytes(LCurrentText);
  LWriter := ASourceEditor.CreateUndoableWriter;
  if not Assigned(LWriter) then
    Exit;

  LWriter.CopyTo(0);
  if Length(LCurrentBytes) > 0 then
    LWriter.DeleteTo(Length(LCurrentBytes));
  LNewText := UTF8Encode(AText);
  LWriter.Insert(PAnsiChar(LNewText));
  LWriter := nil;
  Result := ReadEditorText(ASourceEditor) = AText;
end;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  if GetCurrentThreadId = MainThreadID then
    AAction()
  else
    TThread.Synchronize(nil, AAction);
end;

class function TDAIOTA.SameFile(const ALeft: string; const ARight: string): Boolean;
begin
  Result := False;
  if (Trim(ALeft) = '') or (Trim(ARight) = '') then
    Exit;
  try
    Result := SameText(NormalizeFileName(ALeft), NormalizeFileName(ARight));
  except
    Result := SameText(ALeft, ARight);
  end;
end;

class function TDAIOTA.WorkspaceRoots: TArray<string>;
var
  LList: TList<string>;
  LProject: IOTAProject;
  LRoot: string;
begin
  LList := TList<string>.Create;
  try
    for LProject in Projects do
    begin
      LRoot := NormalizeFileName(TPath.GetDirectoryName(ProjectFileName(LProject)));
      if (LRoot <> '') and not LList.Contains(LRoot) then
        LList.Add(LRoot);
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

end.
