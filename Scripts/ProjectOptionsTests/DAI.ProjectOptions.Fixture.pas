unit DAI.ProjectOptions.Fixture;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI;

type
  // Complete implementations of the installed public OTA interfaces; unused operations fail loudly.
  TTestProject = class(TInterfacedObject, IOTAProject)
  public
    FileNameValue: string;
    OptionsValue: IOTAProjectOptions;
    ConfigurationValue: string;
    PlatformValue: string;
    ModifiedCount: Integer;
    SaveCount: Integer;
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
    ProjectsValue: TArray<IOTAProject>;
    ActiveProjectValue: IOTAProject;
    ActivationCount: Integer;
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

  TTestConfiguration = class(TInterfacedObject, IOTABuildConfiguration)
  private
    FValues: TDictionary<string, string>;
    FNativeEffectiveValues: TDictionary<string, string>;
    FMergeFlags: TDictionary<string, Boolean>;
    FPlatforms: TDictionary<string, TTestConfiguration>;
    function ResolveValue(const PropName: string; const IncludeInheritedValues: Boolean; const ADepth: Integer): string;
  public
    KeyValue: string;
    NameValue: string;
    PlatformValue: string;
    ParentValue: TTestConfiguration;
    ChildrenValue: TArray<TTestConfiguration>;
    ModifiedValue: Boolean;
    EmptyStringRemoves: Boolean;
    EmptyMergeValueNames: TArray<string>;
    IgnoredMergeValueNames: TArray<string>;
    SetValueCount: Integer;
    SetMergedCount: Integer;
    RemoveCount: Integer;
    PlatformGetterCount: Integer;
    constructor Create(const AKey, AName, APlatform: string; AParent: TTestConfiguration);
    destructor Destroy; override;
    procedure Define(const AName, AValue: string; const AMerged: Boolean = False);
    procedure DefineNativeEffectiveValue(const AName, AValue: string);
    procedure LinkPlatform(const APlatform: string; AConfiguration: TTestConfiguration);
    function GetName: string;
    procedure SetName(const Value: string);
    function GetKey: string;
    function GetParent: IOTABuildConfiguration;
    function GetChildCount: Integer;
    function GetChild(Index: Integer): IOTABuildConfiguration;
    function GetPropertyCount: Integer;
    function GetPropertyName(Index: Integer): string;
    function IsEmpty: Boolean;
    function IsModified: Boolean;
    procedure Remove(const PropName: string);
    procedure Clear;
    function PropertyExists(const PropName: string): Boolean;
    function GetValue(const PropName: string): string; overload;
    function GetValue(const PropName: string; IncludeInheritedValues: Boolean): string; overload;
    procedure SetValue(const PropName, Value: string);
    function GetBoolean(const PropName: string): Boolean; overload;
    function GetBoolean(const PropName: string; IncludeInheritedValues: Boolean): Boolean; overload;
    procedure SetBoolean(const PropName: string; const Value: Boolean);
    function GetInteger(const PropName: string): Integer; overload;
    function GetInteger(const PropName: string; IncludeInheritedValues: Boolean): Integer; overload;
    procedure SetInteger(const PropName: string; const Value: Integer);
    function InheritedValue(const PropName: string): string;
    procedure GetValues(const PropName: string; Values: TStrings; IncludeInheritedValues: Boolean = True);
    function ContainsValue(const PropName, Value: string): Boolean;
    procedure InsertValues(const PropName: string; const Values: array of string; Location: Integer = -1);
    procedure SetValues(const PropName: string; const Values: TStrings);
    procedure RemoveValues(const PropName: string; const Values: array of string);
    procedure InheritedValues(const PropName: string; Values: TStrings; IgnoreMerged: Boolean = False);
    function GetMerged(const PropName: string): Boolean;
    procedure SetMerged(const PropName: string; Value: Boolean);
    function GetPlatformConfiguration(const PlatformName: string): IOTABuildConfiguration;
    function GetPlatform: string;
    function GetPlatforms: TArray<string>;
    function GetLocalOverride(const Filename: string): IOTABuildConfiguration;
  end;

  TTestProjectOptions = class(TInterfacedObject, IOTAProjectOptions, IOTAProjectOptionsConfigurations)
  public
    ConfigurationsValue: TArray<IOTABuildConfiguration>;
    ActiveConfigurationValue: IOTABuildConfiguration;
    BaseConfigurationValue: IOTABuildConfiguration;
    ModifiedValue: Boolean;
    ModifiedSetterCount: Integer;
    CurrentConfigurationValue: string;
    CurrentPlatformValue: string;
    procedure EditOptions;
    function GetOptionValue(const ValueName: string): Variant;
    procedure SetOptionValue(const ValueName: string; const Value: Variant);
    function GetOptionNames: TOTAOptionNameArray;
    procedure SetModifiedState(State: Boolean);
    function GetModifiedState: Boolean;
    function GetTargetName: string;
    function GetConfigurationCount: Integer;
    function GetConfiguration(Index: Integer): IOTABuildConfiguration;
    function GetActiveConfiguration: IOTABuildConfiguration;
    procedure SetActiveConfiguration(const Value: IOTABuildConfiguration);
    function GetBaseConfiguration: IOTABuildConfiguration;
    function AddConfiguration(const Name: string; Parent: IOTABuildConfiguration): IOTABuildConfiguration;
    procedure RemoveConfiguration(const Name: string);
    function GetCurrentConfigurationName: string;
    function GetCurrentPlatformName: string;
    function GetActiveMobileDevice(const PlatformName: string): string;
  end;

implementation

uses
  h5u.DAI.OTA.Helpers;

procedure RequireDispatch;
begin
  if TDAIOTA.DispatchDepth = 0 then
    raise EInvalidOperation.Create('Project options OTA access must run inside the IDE dispatcher.');
end;

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
  Inc(SaveCount);
  raise EInvalidOperation.Create('Options mutations must never save project files automatically.');
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
  RequireDispatch;
  Inc(ModifiedCount);
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
  RequireDispatch;
  Result := OptionsValue;
end;

function TTestProject.GetProjectBuilder: IOTAProjectBuilder;
begin
  Result := nil;
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
  RequireDispatch;
  Result := ConfigurationValue;
end;

function TTestProject.GetFrameworkType: string;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestProject.GetFrameworkType');
end;

function TTestProject.GetPlatform: string;
begin
  RequireDispatch;
  Result := PlatformValue;
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
  Result := ['Win32', 'Win64'];
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
  RequireDispatch;
  Result := ActiveProjectValue;
end;

function TTestGroup.GetProjectCount: Integer;
begin
  RequireDispatch;
  Result := Length(ProjectsValue);
end;

function TTestGroup.GetProject(Index: Integer): IOTAProject;
begin
  RequireDispatch;
  Result := ProjectsValue[Index];
end;

procedure TTestGroup.RemoveProject(const AProject: IOTAProject);
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.RemoveProject');
end;

procedure TTestGroup.SetActiveProject(const AProject: IOTAProject);
begin
  RequireDispatch;
  ActiveProjectValue := AProject;
  Inc(ActivationCount);
end;

function TTestGroup.FindProject(const FileName: string): IOTAProject;
begin
  raise EInvalidOperation.Create('Unexpected synthetic OTA call: TTestGroup.FindProject');
end;


constructor TTestConfiguration.Create(const AKey, AName, APlatform: string; AParent: TTestConfiguration);
begin
  inherited Create;
  KeyValue := AKey;
  NameValue := AName;
  PlatformValue := APlatform;
  ParentValue := AParent;
  FValues := TDictionary<string, string>.Create;
  FNativeEffectiveValues := TDictionary<string, string>.Create;
  FMergeFlags := TDictionary<string, Boolean>.Create;
  FPlatforms := TDictionary<string, TTestConfiguration>.Create;
end;

destructor TTestConfiguration.Destroy;
begin
  FPlatforms.Free;
  FMergeFlags.Free;
  FNativeEffectiveValues.Free;
  FValues.Free;
  inherited;
end;

procedure TTestConfiguration.Define(const AName, AValue: string; const AMerged: Boolean);
begin
  FNativeEffectiveValues.Remove(AName);
  FValues.AddOrSetValue(AName, AValue);
  FMergeFlags.AddOrSetValue(AName, AMerged);
end;

procedure TTestConfiguration.DefineNativeEffectiveValue(const AName, AValue: string);
begin
  // Native SDK evaluation may consider platform companions missing from the exposed Parent chain.
  FNativeEffectiveValues.AddOrSetValue(AName, AValue);
end;

procedure TTestConfiguration.LinkPlatform(const APlatform: string; AConfiguration: TTestConfiguration);
begin
  FPlatforms.AddOrSetValue(APlatform, AConfiguration);
end;

function TTestConfiguration.GetName: string;
begin
  RequireDispatch;
  Result := NameValue;
end;

procedure TTestConfiguration.SetName(const Value: string);
begin
  raise EInvalidOperation.Create('Configuration names must not be changed.');
end;

function TTestConfiguration.GetKey: string;
begin
  RequireDispatch;
  Result := KeyValue;
end;

function TTestConfiguration.GetParent: IOTABuildConfiguration;
begin
  RequireDispatch;
  Result := ParentValue;
end;

function TTestConfiguration.GetChildCount: Integer;
begin
  RequireDispatch;
  Result := Length(ChildrenValue);
end;

function TTestConfiguration.GetChild(Index: Integer): IOTABuildConfiguration;
begin
  RequireDispatch;
  Result := ChildrenValue[Index];
end;

function TTestConfiguration.GetPropertyCount: Integer;
begin
  RequireDispatch;
  Result := FValues.Count;
end;

function TTestConfiguration.GetPropertyName(Index: Integer): string;
var
  LNames: TStringList;
  LName: string;
begin
  RequireDispatch;
  LNames := TStringList.Create;
  try
    LNames.Sorted := True;
    for LName in FValues.Keys do
      LNames.Add(LName);
    Result := LNames[Index];
  finally
    LNames.Free;
  end;
end;

function TTestConfiguration.IsEmpty: Boolean;
begin
  RequireDispatch;
  Result := FValues.Count = 0;
end;

function TTestConfiguration.IsModified: Boolean;
begin
  RequireDispatch;
  Result := ModifiedValue;
end;

procedure TTestConfiguration.Remove(const PropName: string);
begin
  RequireDispatch;
  Inc(RemoveCount);
  FValues.Remove(PropName);
  FMergeFlags.Remove(PropName);
  ModifiedValue := True;
end;

procedure TTestConfiguration.Clear;
begin
  raise EInvalidOperation.Create('All configuration properties must not be cleared.');
end;

function TTestConfiguration.PropertyExists(const PropName: string): Boolean;
begin
  RequireDispatch;
  Result := FValues.ContainsKey(PropName);
end;

function TTestConfiguration.ResolveValue(const PropName: string; const IncludeInheritedValues: Boolean; const ADepth: Integer): string;
var
  LParentValue: string;
begin
  if ADepth > 256 then
    raise EInvalidOperation.Create('Synthetic configuration evaluation detected a cycle.');
  LParentValue := '';
  if IncludeInheritedValues and Assigned(ParentValue) then
    LParentValue := ParentValue.ResolveValue(PropName, True, ADepth + 1);
  if FValues.TryGetValue(PropName, Result) then
  begin
    if IncludeInheritedValues and GetMerged(PropName) then
    begin
      if (Result <> '') and (LParentValue <> '') then
        Result := Result + ';' + LParentValue
      else
        Result := Result + LParentValue;
    end;
  end
  else
    Result := LParentValue;
end;

function TTestConfiguration.GetValue(const PropName: string): string;
begin
  Result := GetValue(PropName, True);
end;

function TTestConfiguration.GetValue(const PropName: string; IncludeInheritedValues: Boolean): string;
begin
  RequireDispatch;
  if IncludeInheritedValues then
    if FNativeEffectiveValues.TryGetValue(PropName, Result) then
      Exit;
  Result := ResolveValue(PropName, IncludeInheritedValues, 0);
end;

procedure TTestConfiguration.SetValue(const PropName, Value: string);
begin
  RequireDispatch;
  Inc(SetValueCount);
  FNativeEffectiveValues.Remove(PropName);
  if EmptyStringRemoves and (Value = '') then
  begin
    FValues.Remove(PropName);
    FMergeFlags.Remove(PropName);
    ModifiedValue := True;
    Exit;
  end;
  FValues.AddOrSetValue(PropName, Value);
  // Native setters may change the merge flag; preserve mode must restore it explicitly.
  FMergeFlags.AddOrSetValue(PropName, False);
  ModifiedValue := True;
end;

function TTestConfiguration.GetBoolean(const PropName: string): Boolean;
begin
  Result := GetBoolean(PropName, True);
end;

function TTestConfiguration.GetBoolean(const PropName: string; IncludeInheritedValues: Boolean): Boolean;
begin
  Result := StrToBool(GetValue(PropName, IncludeInheritedValues));
end;

procedure TTestConfiguration.SetBoolean(const PropName: string; const Value: Boolean);
begin
  SetValue(PropName, BoolToStr(Value, True));
end;

function TTestConfiguration.GetInteger(const PropName: string): Integer;
begin
  Result := GetInteger(PropName, True);
end;

function TTestConfiguration.GetInteger(const PropName: string; IncludeInheritedValues: Boolean): Integer;
begin
  Result := StrToInt(GetValue(PropName, IncludeInheritedValues));
end;

procedure TTestConfiguration.SetInteger(const PropName: string; const Value: Integer);
begin
  SetValue(PropName, IntToStr(Value));
end;

function TTestConfiguration.InheritedValue(const PropName: string): string;
begin
  RequireDispatch;
  if FNativeEffectiveValues.TryGetValue(PropName, Result) then
    Exit;
  Result := '';
  if Assigned(ParentValue) then
    Result := ParentValue.ResolveValue(PropName, True, 0);
end;

procedure TTestConfiguration.GetValues(const PropName: string; Values: TStrings; IncludeInheritedValues: Boolean);
begin
  Values.Delimiter := ';';
  Values.StrictDelimiter := True;
  Values.DelimitedText := GetValue(PropName, IncludeInheritedValues);
end;

function TTestConfiguration.ContainsValue(const PropName, Value: string): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected list mutation interface.');
end;

procedure TTestConfiguration.InsertValues(const PropName: string; const Values: array of string; Location: Integer);
begin
  raise EInvalidOperation.Create('Unexpected list insertion interface.');
end;

procedure TTestConfiguration.SetValues(const PropName: string; const Values: TStrings);
begin
  raise EInvalidOperation.Create('String SetValue is the intended options setter.');
end;

procedure TTestConfiguration.RemoveValues(const PropName: string; const Values: array of string);
begin
  raise EInvalidOperation.Create('Remove must delete the property itself.');
end;

procedure TTestConfiguration.InheritedValues(const PropName: string; Values: TStrings; IgnoreMerged: Boolean);
begin
  Values.Delimiter := ';';
  Values.StrictDelimiter := True;
  Values.DelimitedText := InheritedValue(PropName);
end;

function TTestConfiguration.GetMerged(const PropName: string): Boolean;
begin
  RequireDispatch;
  if not FMergeFlags.TryGetValue(PropName, Result) then
    Result := False;
end;

procedure TTestConfiguration.SetMerged(const PropName: string; Value: Boolean);
var
  LName: string;
begin
  RequireDispatch;
  Inc(SetMergedCount);
  for LName in IgnoredMergeValueNames do
    if SameText(LName, PropName) then
      Exit;
  if not FValues.ContainsKey(PropName) then
  begin
    for LName in EmptyMergeValueNames do
      if SameText(LName, PropName) then
      begin
        FValues.Add(PropName, '');
        Break;
      end;
    if not FValues.ContainsKey(PropName) then
      raise EInvalidOperation.Create('Merge flag must never recreate a removed unsupported property.');
  end;
  FMergeFlags.AddOrSetValue(PropName, Value);
  ModifiedValue := True;
end;

function TTestConfiguration.GetPlatformConfiguration(const PlatformName: string): IOTABuildConfiguration;
var
  LConfiguration: TTestConfiguration;
begin
  RequireDispatch;
  Inc(PlatformGetterCount);
  if PlatformValue <> '' then
    raise EInvalidOperation.Create('Platform configuration was applied twice to the selected scope.');
  Result := nil;
  if FPlatforms.TryGetValue(PlatformName, LConfiguration) then
    Result := LConfiguration;
end;

function TTestConfiguration.GetPlatform: string;
begin
  RequireDispatch;
  Result := PlatformValue;
end;

function TTestConfiguration.GetPlatforms: TArray<string>;
begin
  RequireDispatch;
  Result := FPlatforms.Keys.ToArray;
end;

function TTestConfiguration.GetLocalOverride(const Filename: string): IOTABuildConfiguration;
begin
  raise EInvalidOperation.Create('Project options do not change file-local overrides.');
end;

procedure TTestProjectOptions.EditOptions;
begin
  raise EInvalidOperation.Create('Project options tools must not open an options dialog.');
end;

function TTestProjectOptions.GetOptionValue(const ValueName: string): Variant;
begin
  raise EInvalidOperation.Create('Inherited option values must come from the selected configuration.');
end;

procedure TTestProjectOptions.SetOptionValue(const ValueName: string; const Value: Variant);
begin
  raise EInvalidOperation.Create('Legacy flat options setter must not override the active configuration.');
end;

function TTestProjectOptions.GetOptionNames: TOTAOptionNameArray;
begin
  RequireDispatch;
  Result := nil;
end;

procedure TTestProjectOptions.SetModifiedState(State: Boolean);
begin
  RequireDispatch;
  Inc(ModifiedSetterCount);
  ModifiedValue := State;
end;

function TTestProjectOptions.GetModifiedState: Boolean;
begin
  RequireDispatch;
  Result := ModifiedValue;
end;

function TTestProjectOptions.GetTargetName: string;
begin
  raise EInvalidOperation.Create('Project options do not resolve output binaries.');
end;

function TTestProjectOptions.GetConfigurationCount: Integer;
begin
  RequireDispatch;
  Result := Length(ConfigurationsValue);
end;

function TTestProjectOptions.GetConfiguration(Index: Integer): IOTABuildConfiguration;
begin
  RequireDispatch;
  Result := ConfigurationsValue[Index];
end;

function TTestProjectOptions.GetActiveConfiguration: IOTABuildConfiguration;
begin
  RequireDispatch;
  Result := ActiveConfigurationValue;
end;

procedure TTestProjectOptions.SetActiveConfiguration(const Value: IOTABuildConfiguration);
begin
  raise EInvalidOperation.Create('Reading or writing a scope must not switch the active build configuration.');
end;

function TTestProjectOptions.GetBaseConfiguration: IOTABuildConfiguration;
begin
  RequireDispatch;
  Result := BaseConfigurationValue;
end;

function TTestProjectOptions.AddConfiguration(const Name: string; Parent: IOTABuildConfiguration): IOTABuildConfiguration;
begin
  raise EInvalidOperation.Create('Only existing build configurations may be edited.');
end;

procedure TTestProjectOptions.RemoveConfiguration(const Name: string);
begin
  raise EInvalidOperation.Create('Build configurations must not be deleted.');
end;

function TTestProjectOptions.GetCurrentConfigurationName: string;
begin
  RequireDispatch;
  Result := CurrentConfigurationValue;
end;

function TTestProjectOptions.GetCurrentPlatformName: string;
begin
  RequireDispatch;
  Result := CurrentPlatformValue;
end;

function TTestProjectOptions.GetActiveMobileDevice(const PlatformName: string): string;
begin
  raise EInvalidOperation.Create('Desktop project options do not select mobile devices.');
end;

end.
