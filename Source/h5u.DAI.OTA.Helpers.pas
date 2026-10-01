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
    class function FindFormEditor(const AFileName: string): IOTAFormEditor; static;
    class function FormFileName(const AFileName: string): string; static;
    class function EnsureFormTextEditor(const AFileName: string): IOTASourceEditor; static;
    class function EnsureFormDesigner(const AFileName: string): IOTAFormEditor; static;
    class function ProjectContainsFile(const AProject: IOTAProject; const AFileName: string): Boolean; static;
    class function ProjectForFile(const AFileName: string): IOTAProject; static;
    class function IsFileOpenInEditor(const AFileName: string): Boolean; static;
    class function IsFormLoadedForFile(const AFileName: string): Boolean; static;
    class function ReadEditorText(const ASourceEditor: IOTASourceEditor): string; static;
    class function ReadFormText(const AFileName: string; const AMaximumBytes: Integer; out AText: string): Boolean; static;
    class function ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string): Boolean; overload; static;
    class function ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string; out AActualText: string): Boolean; overload; static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const ALeft: string; const ARight: string): Boolean; static;
    class function IsPathWithin(const AFileName: string; const ARootDirectory: string): Boolean; static;
    class function IsReadOnlyReferenceFile(const AFileName: string): Boolean; static;
    class procedure RequireNoReparseWritePath(const APath: string); static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function WorkspaceRoots: TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Settings,
  h5u.DAI.Text.Encoding,
  h5u.DAI.Types;

const
  CEditReaderChunkSize = 8192;
  CFormViewWaitMilliseconds = 2000;
  CFormViewProbeMilliseconds = 25;

type
  TDAIFormViewRequest = record
    TextMode: Boolean;
    Waiters: Integer;
  end;

var
  GFormViewRequests: TDictionary<string, TDAIFormViewRequest>;

// Accessed only on the IDE thread. Matching requests share one posted action;
// an opposite transition must wait for the current request to finish.
procedure ObserveFormViewRequest(const AFileName: string);
var
  LCompleted: Boolean;
  LKey: string;
  LRequest: TDAIFormViewRequest;
begin
  LKey := LowerCase(TDAIOTA.NormalizeFileName(AFileName));
  if not GFormViewRequests.TryGetValue(LKey, LRequest) then
    Exit;
  if LRequest.Waiters <> 0 then
    Exit;
  if LRequest.TextMode then
    LCompleted := Assigned(TDAIOTA.FindSourceEditor(AFileName))
  else
    LCompleted := Assigned(TDAIOTA.FindFormEditor(AFileName));
  // A timeout cannot cancel a posted IDE message. Keep its guard until completion
  // is observed (or the module is actually gone), so a late post cannot toggle back.
  if LCompleted or not Assigned(TDAIOTA.FindModuleByFileName(AFileName)) then
    GFormViewRequests.Remove(LKey);
end;

function BeginFormViewRequest(const AFileName: string; const ATextMode: Boolean; out AShouldPost: Boolean): Boolean;
var
  LKey: string;
  LRequest: TDAIFormViewRequest;
begin
  AShouldPost := False;
  ObserveFormViewRequest(AFileName);
  LKey := LowerCase(TDAIOTA.NormalizeFileName(AFileName));
  if GFormViewRequests.TryGetValue(LKey, LRequest) then
  begin
    if LRequest.TextMode <> ATextMode then
      Exit(False);
    Inc(LRequest.Waiters);
  end
  else
  begin
    LRequest.TextMode := ATextMode;
    LRequest.Waiters := 1;
    AShouldPost := True;
  end;
  GFormViewRequests.AddOrSetValue(LKey, LRequest);
  Result := True;
end;

procedure EndFormViewRequest(const AFileName: string);
var
  LKey: string;
  LRequest: TDAIFormViewRequest;
begin
  LKey := LowerCase(TDAIOTA.NormalizeFileName(AFileName));
  if not GFormViewRequests.TryGetValue(LKey, LRequest) then
    Exit;
  Dec(LRequest.Waiters);
  GFormViewRequests.AddOrSetValue(LKey, LRequest);
  ObserveFormViewRequest(AFileName);
end;

function HasOppositeFormViewRequest(const AFileName: string; const ATextMode: Boolean): Boolean;
var
  LRequest: TDAIFormViewRequest;
begin
  Result := False;
  ObserveFormViewRequest(AFileName);
  if GFormViewRequests.TryGetValue(LowerCase(TDAIOTA.NormalizeFileName(AFileName)), LRequest) then
    Result := LRequest.TextMode <> ATextMode;
end;

procedure RequireSavedPascalSource(const ASourceEditor: IOTASourceEditor);
var
  LFileName, LSavedText, LEditorText: string;
  LFormat: TDAITextFileFormat;
begin
  LFileName := ASourceEditor.FileName;
  if not SameText(TPath.GetExtension(LFileName), '.pas') then
    Exit;
  if TFile.Exists(LFileName) then
  begin
    LSavedText := TDAITextEncoding.ReadFile(LFileName, LFormat);
    LEditorText := TDAIOTA.ReadEditorText(ASourceEditor);
    // Modified can reflect a dirty DFM in the same module. Compare the actual
    // complete Pascal source, decoding disk encoding and normalizing line ends.
    if TDAITextEncoding.ApplyLineEnding(LSavedText, lekCRLF) = TDAITextEncoding.ApplyLineEnding(LEditorText, lekCRLF) then
      Exit;
  end;
  raise EInvalidOperation.CreateFmt('Der native Formular-Textmodus ersetzt den Pascal-Editor. ' +
    'Die Pascal-Unit ist noch nicht gespeichert oder hat ungespeicherte Änderungen: %s', [LFileName]);
end;

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
      LAdditionalFiles: IOTAAdditionalModuleFiles;
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
        if Supports(LModule, IOTAAdditionalModuleFiles, LAdditionalFiles) then
          for LEditorIndex := 0 to LAdditionalFiles.AdditionalModuleFileCount - 1 do
          begin
            LEditor := LAdditionalFiles.AdditionalModuleFileEditors[LEditorIndex];
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
      LAdditionalFiles: IOTAAdditionalModuleFiles;
      LEditorServices: IOTAEditorServices;
      LIterator: IOTAEditBufferIterator;
      LSourceEditor: IOTASourceEditor;
    begin
      if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
        for LModuleIndex := 0 to LModuleServices.ModuleCount - 1 do
        begin
          LModule := LModuleServices.Modules[LModuleIndex];
          if not Assigned(LModule) then
            Continue;

          for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
            if Supports(LModule.ModuleFileEditors[LEditorIndex], IOTASourceEditor, LSourceEditor) then
              if SameFile(LSourceEditor.FileName, AFileName) then
              begin
                LResult := LSourceEditor;
                Exit;
              end;
          if Supports(LModule, IOTAAdditionalModuleFiles, LAdditionalFiles) then
            for LEditorIndex := 0 to LAdditionalFiles.AdditionalModuleFileCount - 1 do
              if Supports(LAdditionalFiles.AdditionalModuleFileEditors[LEditorIndex], IOTASourceEditor, LSourceEditor) then
                if SameFile(LSourceEditor.FileName, AFileName) then
                begin
                  LResult := LSourceEditor;
                  Exit;
                end;
        end;

      // Form text buffers need not appear among the module's regular file editors.
      if not Supports(BorlandIDEServices, IOTAEditorServices, LEditorServices) then
        Exit;
      if not LEditorServices.GetEditBufferIterator(LIterator) or not Assigned(LIterator) then
        Exit;
      for LEditorIndex := 0 to LIterator.Count - 1 do
      begin
        LSourceEditor := LIterator.EditBuffers[LEditorIndex];
        if Assigned(LSourceEditor) and SameFile(LSourceEditor.FileName, AFileName) then
        begin
          LResult := LSourceEditor;
          Exit;
        end;
      end;
    end);
  Result := LResult;
end;

class function TDAIOTA.FindFormEditor(const AFileName: string): IOTAFormEditor;
var
  LResult: IOTAFormEditor;
begin
  LResult := nil;
  RunOnMainThread(
    procedure
    var
      LFormEditor: IOTAFormEditor;
      LIndex: Integer;
      LModule: IOTAModule;
    begin
      LModule := FindModuleByFileName(AFileName);
      if not Assigned(LModule) and not SameText(TPath.GetExtension(AFileName), '.pas') then
        LModule := FindModuleByFileName(ChangeFileExt(AFileName, '.pas'));
      if not Assigned(LModule) then
        Exit;
      for LIndex := 0 to LModule.ModuleFileCount - 1 do
        if Supports(LModule.ModuleFileEditors[LIndex], IOTAFormEditor, LFormEditor) then
        begin
          if SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx') then
            if not SameFile(LFormEditor.FileName, AFileName) then
              Continue;
          LResult := LFormEditor;
          Exit;
        end;
    end);
  Result := LResult;
end;

class function TDAIOTA.FormFileName(const AFileName: string): string;
var
  LResult: string;
begin
  LResult := '';
  RunOnMainThread(
    procedure
    var
      LFormEditor: IOTAFormEditor;
      LIndex: Integer;
      LModule: IOTAModule;
    begin
      LModule := FindModuleByFileName(AFileName);
      if Assigned(LModule) then
        for LIndex := 0 to LModule.ModuleFileCount - 1 do
          if Supports(LModule.ModuleFileEditors[LIndex], IOTAFormEditor, LFormEditor) then
          begin
            if SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx') then
              if not SameFile(LFormEditor.FileName, AFileName) then
                Continue;
            LResult := LFormEditor.FileName;
            Exit;
          end;

      if SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx') then
      begin
        if TFile.Exists(AFileName) or Assigned(FindSourceEditor(AFileName)) then
          LResult := AFileName;
      end
      else if Assigned(FindSourceEditor(ChangeFileExt(AFileName, '.dfm'))) or TFile.Exists(ChangeFileExt(AFileName, '.dfm')) then
        LResult := ChangeFileExt(AFileName, '.dfm')
      else if Assigned(FindSourceEditor(ChangeFileExt(AFileName, '.fmx'))) or TFile.Exists(ChangeFileExt(AFileName, '.fmx')) then
        LResult := ChangeFileExt(AFileName, '.fmx');
    end);
  Result := LResult;
end;

class function TDAIOTA.EnsureFormTextEditor(const AFileName: string): IOTASourceEditor;
var
  LCanWait: Boolean;
  LDeadline: UInt64;
  LResult: IOTASourceEditor;
  LViewChangeRequested: Boolean;
begin
  LCanWait := GetCurrentThreadId <> MainThreadID;
  LResult := nil;
  LViewChangeRequested := False;
  try
    RunOnMainThread(
      procedure
      var
        LActionServices: IOTAActionServices;
        LEditActions: IOTAEditActions;
        LEditorIndex: Integer;
        LFormEditor: IOTAFormEditor;
        LModule: IOTAModule;
        LShouldPost: Boolean;
        LSourceEditor: IOTASourceEditor;
      begin
        if HasOppositeFormViewRequest(AFileName, True) then
          Exit;
        LResult := FindSourceEditor(AFileName);
        if Assigned(LResult) then
        begin
          LResult.Show;
          Exit;
        end;
        if not (SameText(TPath.GetExtension(AFileName), '.dfm') or SameText(TPath.GetExtension(AFileName), '.fmx')) then
          Exit;

        LModule := FindModuleByFileName(AFileName);
        if not Assigned(LModule) then
        begin
          if not TFile.Exists(AFileName) then
            Exit;
          if not Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
            Exit;
          if not LActionServices.OpenFile(AFileName) then
            Exit;
          LResult := FindSourceEditor(AFileName);
          if Assigned(LResult) then
          begin
            LResult.Show;
            Exit;
          end;
          LModule := FindModuleByFileName(AFileName);
          if not Assigned(LModule) then
            Exit;
        end;

        LFormEditor := nil;
        for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
          if Supports(LModule.ModuleFileEditors[LEditorIndex], IOTAFormEditor, LFormEditor) then
            if SameFile(LFormEditor.FileName, AFileName) then
              Break
            else
              LFormEditor := nil;
        if not Assigned(LFormEditor) then
          Exit;

        for LEditorIndex := 0 to LModule.ModuleFileCount - 1 do
          if Supports(LModule.ModuleFileEditors[LEditorIndex], IOTASourceEditor, LSourceEditor) then
          begin
            // View as Text replaces the Pascal module in the native IDE. Never
            // sacrifice a new or modified in-memory unit to obtain a form buffer.
            RequireSavedPascalSource(LSourceEditor);
            LSourceEditor.Show;
            if LSourceEditor.EditViewCount = 0 then
              Continue;
            if not Supports(LSourceEditor.EditViews[0], IOTAEditActions, LEditActions) then
              Continue;
            // A posted transition cannot complete inside a direct main-thread caller.
            if not LCanWait then
              Exit;
            if not BeginFormViewRequest(AFileName, True, LShouldPost) then
              Exit;
            LViewChangeRequested := True;
            if not LShouldPost then
              Exit;
            LFormEditor.Show;
            // The native action posts an IDE message; its result may appear after this callback.
            LEditActions.SwapSourceFormView;
            LResult := FindSourceEditor(AFileName);
            if Assigned(LResult) then
              LResult.Show;
            Exit;
          end;
      end);

    // Never wait or pump messages inside an IDE/main-thread callback. The HTTP worker
    // releases it first, then probes briefly while the IDE processes its posted action.
    if LViewChangeRequested and not Assigned(LResult) and (GetCurrentThreadId <> MainThreadID) then
    begin
      LDeadline := GetTickCount64 + CFormViewWaitMilliseconds;
      repeat
        TThread.Sleep(CFormViewProbeMilliseconds);
        LResult := FindSourceEditor(AFileName);
      until Assigned(LResult) or (GetTickCount64 >= LDeadline);
      if Assigned(LResult) then
        RunOnMainThread(procedure begin LResult.Show; end);
    end;
    Result := LResult;
  finally
    if LViewChangeRequested then
      RunOnMainThread(procedure begin EndFormViewRequest(AFileName); end);
  end;
end;

class function TDAIOTA.EnsureFormDesigner(const AFileName: string): IOTAFormEditor;
var
  LCanWait: Boolean;
  LDeadline: UInt64;
  LFormFileName: string;
  LResult: IOTAFormEditor;
  LViewChangeRequested: Boolean;
begin
  LCanWait := GetCurrentThreadId <> MainThreadID;
  LResult := nil;
  LFormFileName := '';
  LViewChangeRequested := False;
  try
    RunOnMainThread(
      procedure
      var
        LActionServices: IOTAActionServices;
        LEditActions: IOTAEditActions;
        LShouldPost: Boolean;
        LSourceEditor: IOTASourceEditor;
      begin
        LFormFileName := FormFileName(AFileName);
        if LFormFileName <> '' then
          if HasOppositeFormViewRequest(LFormFileName, False) then
            Exit;
        LResult := FindFormEditor(AFileName);
        if Assigned(LResult) then
        begin
          LResult.Show;
          Exit;
        end;
        LSourceEditor := nil;
        if LFormFileName <> '' then
          LSourceEditor := FindSourceEditor(LFormFileName);
        if not Assigned(LSourceEditor) then
        begin
          if not TFile.Exists(AFileName) then
            Exit;
          if not Supports(BorlandIDEServices, IOTAActionServices, LActionServices) then
            Exit;
          if not LActionServices.OpenFile(AFileName) then
            Exit;
          LResult := FindFormEditor(AFileName);
          if Assigned(LResult) then
            LResult.Show;
          Exit;
        end;
        LSourceEditor.Show;
        if LSourceEditor.EditViewCount = 0 then
          Exit;
        if not Supports(LSourceEditor.EditViews[0], IOTAEditActions, LEditActions) then
          Exit;
        if not LCanWait then
          Exit;
        if not BeginFormViewRequest(LFormFileName, False, LShouldPost) then
          Exit;
        LViewChangeRequested := True;
        if not LShouldPost then
          Exit;
        LEditActions.SwapSourceFormView;
        LResult := FindFormEditor(LFormFileName);
        if Assigned(LResult) then
          LResult.Show;
      end);

    if LViewChangeRequested and not Assigned(LResult) and (GetCurrentThreadId <> MainThreadID) then
    begin
      LDeadline := GetTickCount64 + CFormViewWaitMilliseconds;
      repeat
        TThread.Sleep(CFormViewProbeMilliseconds);
        LResult := FindFormEditor(LFormFileName);
      until Assigned(LResult) or (GetTickCount64 >= LDeadline);
      if Assigned(LResult) then
        RunOnMainThread(procedure begin LResult.Show; end);
    end;
    Result := LResult;
  finally
    if LViewChangeRequested then
      RunOnMainThread(procedure begin EndFormViewRequest(LFormFileName); end);
  end;
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

class procedure TDAIOTA.RequireNoReparseWritePath(const APath: string);
var
  LAttributes, LError: DWORD;
  LCurrent, LParent: string;
begin
  if Trim(APath) = '' then
    Exit;
  LCurrent := NormalizeFileName(APath);
  while LCurrent <> '' do
  begin
    LAttributes := GetFileAttributesW(PWideChar(LCurrent));
    if LAttributes <> INVALID_FILE_ATTRIBUTES then
    begin
      if (LAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
        raise EDAIAccessDenied.CreateFmt('Schreibzugriffe über Verknüpfungen oder Reparse-Punkte sind nicht zulässig: %s', [LCurrent]);
    end
    else
    begin
      LError := GetLastError;
      if (LError <> ERROR_FILE_NOT_FOUND) and (LError <> ERROR_PATH_NOT_FOUND) then
        raise EDAIAccessDenied.CreateFmt('Der Schreibpfad konnte nicht sicher geprüft werden (Windows-Fehler %d): %s', [LError, LCurrent]);
    end;
    // Nonexistent children still require checking every existing ancestor, including a junction above them.
    LParent := TPath.GetDirectoryName(LCurrent);
    if SameText(LParent, LCurrent) then
      Break;
    LCurrent := LParent;
  end;
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
  Result := TPath.GetFullPath(AFileName);
  if not SameText(Result, TPath.GetPathRoot(Result)) then
    Result := ExcludeTrailingPathDelimiter(Result);
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
      if LQuery = '' then
      begin
        LResult := LModuleServices.GetActiveProject;
        Exit;
      end;
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
    procedure var LAdditionalFiles: TStringList;
      LAdditionalFile: string;
      LIndex: Integer;
      LModuleInfo: IOTAModuleInfo;
    begin
      if not Assigned(AProject) then
        Exit;
      if SameFile(AProject.FileName, AFileName) then
      begin
        LResult := True;
        Exit;
      end;
      for LIndex := 0 to AProject.GetModuleCount - 1 do
      begin
        LModuleInfo := AProject.GetModule(LIndex);
        if not Assigned(LModuleInfo) then
          Continue;
        if SameFile(LModuleInfo.FileName, AFileName) then
        begin
          LResult := True;
          Exit;
        end;
        LAdditionalFiles := TStringList.Create;
        try
          LModuleInfo.GetAdditionalFiles(LAdditionalFiles);
          for LAdditionalFile in LAdditionalFiles do
            if SameFile(LAdditionalFile, AFileName) then
            begin
              LResult := True;
              Exit;
            end;
        finally
          LAdditionalFiles.Free;
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

class function TDAIOTA.ReadFormText(const AFileName: string; const AMaximumBytes: Integer; out AText: string): Boolean;
var
  LFound: Boolean;
  LText: string;
begin
  LFound := False;
  LText := '';
  RunOnMainThread(
    procedure
    var
      LFormEditor: IOTAFormEditor;
      LIndex: Integer;
      LModule: IOTAModule;
      LNativeEditor: INTAFormEditor;
      LReader: TStreamReader;
      LResource: TMemoryStream;
      LSignature: Cardinal;
      LTextStream: TMemoryStream;
    begin
      LModule := FindModuleByFileName(AFileName);
      if not Assigned(LModule) then
        Exit;
      for LIndex := 0 to LModule.ModuleFileCount - 1 do
      begin
        if not Supports(LModule.ModuleFileEditors[LIndex], IOTAFormEditor, LFormEditor) or
          not SameFile(LFormEditor.FileName, AFileName) or not Supports(LFormEditor, INTAFormEditor, LNativeEditor) then
          Continue;
        LResource := TMemoryStream.Create;
        LTextStream := TMemoryStream.Create;
        try
          LNativeEditor.GetFormResource(LResource);
          if (AMaximumBytes > 0) and (LResource.Size > AMaximumBytes) then
            raise EInvalidOperation.Create('Die Formularressource überschreitet das Textdateilimit.');
          LResource.Position := 0;
          if TestStreamFormat(LResource) = sofBinary then
          begin
            LSignature := 0;
            LResource.Read(LSignature, SizeOf(LSignature));
            LResource.Position := 0;
            if LSignature = $30465054 then // TPF0: component stream without resource header
              ObjectBinaryToText(LResource, LTextStream)
            else
              ObjectResourceToText(LResource, LTextStream);
          end
          else
            LTextStream.CopyFrom(LResource, LResource.Size);
          if (AMaximumBytes > 0) and (LTextStream.Size > AMaximumBytes) then
            raise EInvalidOperation.Create('Der Formulartext überschreitet das Textdateilimit.');
          LTextStream.Position := 0;
          LReader := TStreamReader.Create(LTextStream, TEncoding.UTF8, True, 4096);
          try
            LText := LReader.ReadToEnd;
          finally
            LReader.Free;
          end;
          LFound := True;
          Exit;
        finally
          LTextStream.Free;
          LResource.Free;
        end;
      end;
    end);
  AText := LText;
  Result := LFound;
end;

class function TDAIOTA.ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string): Boolean;
var
  LActualText: string;
begin
  Result := ReplaceEditorText(ASourceEditor, AText, LActualText);
end;

class function TDAIOTA.ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string; out AActualText: string): Boolean;
var
  LCurrentBytes: TBytes;
  LCurrentText: string;
  LNewText: UTF8String;
  LWriter: IOTAEditWriter;
begin
  Result := False;
  AActualText := '';
  if not Assigned(ASourceEditor) or (Pos(#0, AText) <> 0) then
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
  AActualText := ReadEditorText(ASourceEditor);
  Result := TDAITextEncoding.EditorWriteMatches(AText, AActualText);
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
  LGroup: IOTAProjectGroup;
  LGroupFileName: string;
  LList: TList<string>;
  LProject: IOTAProject;
  LRoot: string;
begin
  LList := TList<string>.Create;
  try
    LGroup := MainProjectGroup;
    LGroupFileName := '';
    RunOnMainThread(
      procedure
      begin
        if Assigned(LGroup) then
          LGroupFileName := LGroup.FileName;
      end);
    if LGroupFileName <> '' then
    begin
      LRoot := NormalizeFileName(TPath.GetDirectoryName(LGroupFileName));
      if LRoot <> '' then
        LList.Add(LRoot);
    end;
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

initialization
  GFormViewRequests := TDictionary<string, TDAIFormViewRequest>.Create;

finalization
  GFormViewRequests.Free;

end.
