unit DAI.Build.Fixture;

interface

uses
  System.Classes,
  System.SysUtils,
  ToolsAPI;

type
  // Complete implementations of the installed public OTA interfaces; unused operations fail loudly.
  TTestProject = class(TInterfacedObject, IOTAProject)
  public
    FileNameValue: string;
    BuilderValue: IOTAProjectBuilder;
    function AddNotifier(const ANotifier: IOTAModuleNotifier): Integer;
    procedure AddToInterface;
    function Close: Boolean;
    function GetFileName: string;
    function GetFileSystem: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(Index: Integer): IOTAEditor;
    function GetOwnerCount: Integer;
    function GetOwner(Index: Integer): IOTAProject;
    function HasCoClasses: Boolean;
    procedure RemoveNotifier(Index: Integer);
    function Save(ChangeName, ForceSave: Boolean): Boolean;
    procedure SetFileName(const AFileName: string);
    procedure SetFileSystem(const AFileSystem: string);
    function CloseModule(ForceClosed: Boolean): Boolean;
    function GetCurrentEditor: IOTAEditor;
    function GetOwnerModuleCount: Integer;
    function GetOwnerModule(Index: Integer): IOTAModule;
    procedure MarkModified;
    procedure Show;
    procedure ShowFilename(const FileName: string);
    procedure Refresh(ForceRefresh: Boolean);
    procedure GetAssociatedFilesFromModule(FileList: TStrings);
    function GetModuleCount: Integer;
    function GetModule(Index: Integer): IOTAModuleInfo;
    function GetProjectOptions: IOTAProjectOptions;
    function GetProjectBuilder: IOTAProjectBuilder;
    procedure AddFile(const AFileName: string; IsUnitOrForm: Boolean);
    procedure RemoveFile(const AFileName: string);
    procedure AddFileWithParent(const AFileName: string; IsUnitOrForm: Boolean; const Parent: string);
    function GetProjectGUID: TGUID;
    function GetPersonality: string;
    function FindModuleInfo(const FileName: string): IOTAModuleInfo;
    function Rename(const OldFileName, NewFileName: string): Boolean;
    function GetProjectType: string;
    procedure GetCompleteFileList(FileList: TStrings);
    procedure GetAssociatedFiles(const FileName: string; FileList: TStrings);
    function GetFileTransaction(const FileName: string; var InitialName, CurrentName: string): Boolean;
    procedure BeginFileTransactionUpdate;
    procedure EndFileTransactionUpdate(CommitUpdate: Boolean);
    procedure GetAddedDeletedFiles(const FileList: IInterfaceList);
    function GetFileTransactionList(const FileName: string; FileList: IInterfaceList): Boolean;
    function GetConfiguration: string;
    function GetFrameworkType: string;
    function GetPlatform: string;
    procedure SetConfiguration(const Value: string);
    procedure SetPlatform(const Value: string);
    function GetSupportedPlatforms: TArray<string>;
    function GetApplicationType: string;
  end;

  TTestGroup = class(TInterfacedObject, IOTAProjectGroup)
  public
    FileNameValue: string;
    function AddNotifier(const ANotifier: IOTAModuleNotifier): Integer;
    procedure AddToInterface;
    function Close: Boolean;
    function GetFileName: string;
    function GetFileSystem: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(Index: Integer): IOTAEditor;
    function GetOwnerCount: Integer;
    function GetOwner(Index: Integer): IOTAProject;
    function HasCoClasses: Boolean;
    procedure RemoveNotifier(Index: Integer);
    function Save(ChangeName, ForceSave: Boolean): Boolean;
    procedure SetFileName(const AFileName: string);
    procedure SetFileSystem(const AFileSystem: string);
    function CloseModule(ForceClosed: Boolean): Boolean;
    function GetCurrentEditor: IOTAEditor;
    function GetOwnerModuleCount: Integer;
    function GetOwnerModule(Index: Integer): IOTAModule;
    procedure MarkModified;
    procedure Show;
    procedure ShowFilename(const FileName: string);
    procedure Refresh(ForceRefresh: Boolean);
    procedure GetAssociatedFilesFromModule(FileList: TStrings);
    procedure AddNewProject;
    procedure AddExistingProject;
    function GetActiveProject: IOTAProject;
    function GetProjectCount: Integer;
    function GetProject(Index: Integer): IOTAProject;
    procedure RemoveProject(const AProject: IOTAProject);
    procedure SetActiveProject(const AProject: IOTAProject);
    function FindProject(const FileName: string): IOTAProject;
  end;

implementation

uses
  h5u.DAI.OTA.Helpers;

function TTestProject.AddNotifier(const ANotifier: IOTAModuleNotifier): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.AddNotifier');
end;

procedure TTestProject.AddToInterface;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.AddToInterface');
end;

function TTestProject.Close: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.Close');
end;

function TTestProject.GetFileName: string;
begin
  Result := FileNameValue;
end;

function TTestProject.GetFileSystem: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetFileSystem');
end;

function TTestProject.GetModuleFileCount: Integer;
begin
  Result := 0;
end;

function TTestProject.GetModuleFileEditor(Index: Integer): IOTAEditor;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetModuleFileEditor');
end;

function TTestProject.GetOwnerCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetOwnerCount');
end;

function TTestProject.GetOwner(Index: Integer): IOTAProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetOwner');
end;

function TTestProject.HasCoClasses: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.HasCoClasses');
end;

procedure TTestProject.RemoveNotifier(Index: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.RemoveNotifier');
end;

function TTestProject.Save(ChangeName, ForceSave: Boolean): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.Save');
end;

procedure TTestProject.SetFileName(const AFileName: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.SetFileName');
end;

procedure TTestProject.SetFileSystem(const AFileSystem: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.SetFileSystem');
end;

function TTestProject.CloseModule(ForceClosed: Boolean): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.CloseModule');
end;

function TTestProject.GetCurrentEditor: IOTAEditor;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetCurrentEditor');
end;

function TTestProject.GetOwnerModuleCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetOwnerModuleCount');
end;

function TTestProject.GetOwnerModule(Index: Integer): IOTAModule;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetOwnerModule');
end;

procedure TTestProject.MarkModified;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.MarkModified');
end;

procedure TTestProject.Show;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.Show');
end;

procedure TTestProject.ShowFilename(const FileName: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.ShowFilename');
end;

procedure TTestProject.Refresh(ForceRefresh: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.Refresh');
end;

procedure TTestProject.GetAssociatedFilesFromModule(FileList: TStrings);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetAssociatedFilesFromModule');
end;

function TTestProject.GetModuleCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetModuleCount');
end;

function TTestProject.GetModule(Index: Integer): IOTAModuleInfo;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetModule');
end;

function TTestProject.GetProjectOptions: IOTAProjectOptions;
begin
  Result := nil;
end;

function TTestProject.GetProjectBuilder: IOTAProjectBuilder;
begin
  Result := BuilderValue;
end;

procedure TTestProject.AddFile(const AFileName: string; IsUnitOrForm: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.AddFile');
end;

procedure TTestProject.RemoveFile(const AFileName: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.RemoveFile');
end;

procedure TTestProject.AddFileWithParent(const AFileName: string; IsUnitOrForm: Boolean; const Parent: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.AddFileWithParent');
end;

function TTestProject.GetProjectGUID: TGUID;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetProjectGUID');
end;

function TTestProject.GetPersonality: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetPersonality');
end;

function TTestProject.FindModuleInfo(const FileName: string): IOTAModuleInfo;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.FindModuleInfo');
end;

function TTestProject.Rename(const OldFileName, NewFileName: string): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.Rename');
end;

function TTestProject.GetProjectType: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetProjectType');
end;

procedure TTestProject.GetCompleteFileList(FileList: TStrings);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetCompleteFileList');
end;

procedure TTestProject.GetAssociatedFiles(const FileName: string; FileList: TStrings);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetAssociatedFiles');
end;

function TTestProject.GetFileTransaction(const FileName: string; var InitialName, CurrentName: string): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetFileTransaction');
end;

procedure TTestProject.BeginFileTransactionUpdate;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.BeginFileTransactionUpdate');
end;

procedure TTestProject.EndFileTransactionUpdate(CommitUpdate: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.EndFileTransactionUpdate');
end;

procedure TTestProject.GetAddedDeletedFiles(const FileList: IInterfaceList);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetAddedDeletedFiles');
end;

function TTestProject.GetFileTransactionList(const FileName: string; FileList: IInterfaceList): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetFileTransactionList');
end;

function TTestProject.GetConfiguration: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetConfiguration');
end;

function TTestProject.GetFrameworkType: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetFrameworkType');
end;

function TTestProject.GetPlatform: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetPlatform');
end;

procedure TTestProject.SetConfiguration(const Value: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.SetConfiguration');
end;

procedure TTestProject.SetPlatform(const Value: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.SetPlatform');
end;

function TTestProject.GetSupportedPlatforms: TArray<string>;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetSupportedPlatforms');
end;

function TTestProject.GetApplicationType: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetApplicationType');
end;

function TTestGroup.AddNotifier(const ANotifier: IOTAModuleNotifier): Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.AddNotifier');
end;

procedure TTestGroup.AddToInterface;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.AddToInterface');
end;

function TTestGroup.Close: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.Close');
end;

function TTestGroup.GetFileName: string;
begin
  Result := FileNameValue;
end;

function TTestGroup.GetFileSystem: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetFileSystem');
end;

function TTestGroup.GetModuleFileCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetModuleFileCount');
end;

function TTestGroup.GetModuleFileEditor(Index: Integer): IOTAEditor;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetModuleFileEditor');
end;

function TTestGroup.GetOwnerCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetOwnerCount');
end;

function TTestGroup.GetOwner(Index: Integer): IOTAProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetOwner');
end;

function TTestGroup.HasCoClasses: Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.HasCoClasses');
end;

procedure TTestGroup.RemoveNotifier(Index: Integer);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.RemoveNotifier');
end;

function TTestGroup.Save(ChangeName, ForceSave: Boolean): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.Save');
end;

procedure TTestGroup.SetFileName(const AFileName: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.SetFileName');
end;

procedure TTestGroup.SetFileSystem(const AFileSystem: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.SetFileSystem');
end;

function TTestGroup.CloseModule(ForceClosed: Boolean): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.CloseModule');
end;

function TTestGroup.GetCurrentEditor: IOTAEditor;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetCurrentEditor');
end;

function TTestGroup.GetOwnerModuleCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetOwnerModuleCount');
end;

function TTestGroup.GetOwnerModule(Index: Integer): IOTAModule;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetOwnerModule');
end;

procedure TTestGroup.MarkModified;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.MarkModified');
end;

procedure TTestGroup.Show;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.Show');
end;

procedure TTestGroup.ShowFilename(const FileName: string);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.ShowFilename');
end;

procedure TTestGroup.Refresh(ForceRefresh: Boolean);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.Refresh');
end;

procedure TTestGroup.GetAssociatedFilesFromModule(FileList: TStrings);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetAssociatedFilesFromModule');
end;

procedure TTestGroup.AddNewProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.AddNewProject');
end;

procedure TTestGroup.AddExistingProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.AddExistingProject');
end;

function TTestGroup.GetActiveProject: IOTAProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetActiveProject');
end;

function TTestGroup.GetProjectCount: Integer;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetProjectCount');
end;

function TTestGroup.GetProject(Index: Integer): IOTAProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.GetProject');
end;

procedure TTestGroup.RemoveProject(const AProject: IOTAProject);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.RemoveProject');
end;

procedure TTestGroup.SetActiveProject(const AProject: IOTAProject);
begin
  TDAIOTA.LastSelectedProject := AProject;
end;

function TTestGroup.FindProject(const FileName: string): IOTAProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.FindProject');
end;

end.
