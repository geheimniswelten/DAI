unit ToolsAPI;

interface

type
  TOTAEditPos = packed record
    Col: SmallInt;
    Line: LongInt;
  end;

  IOTAEditor = interface
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE1}']
    function GetFileName: string;
    function GetModified: Boolean;
    procedure Show;
    property FileName: string read GetFileName;
    property Modified: Boolean read GetModified;
  end;
  IOTASourceEditor = interface(IOTAEditor)
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE2}']
    function GetLinesInBuffer: LongInt;
  end;
  IOTAEditBuffer = interface(IOTASourceEditor)
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE9}']
  end;
  IOTAEditView = interface
    ['{51798E1E-FB21-413D-B94E-16C474CE2FEA}']
    function GetBuffer: IOTAEditBuffer;
    function GetCursorPos: TOTAEditPos;
    procedure SetCursorPos(const AValue: TOTAEditPos);
    procedure MoveViewToCursor;
    function SameView(const AView: IOTAEditView): Boolean;
    property Buffer: IOTAEditBuffer read GetBuffer;
    property CursorPos: TOTAEditPos read GetCursorPos write SetCursorPos;
  end;
  IOTAEditorServices = interface
    ['{51798E1E-FB21-413D-B94E-16C474CE2FEB}']
    function GetTopView: IOTAEditView;
    property TopView: IOTAEditView read GetTopView;
  end;
  IOTAModule = interface
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE3}']
    function GetFileName: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(AIndex: Integer): IOTAEditor;
    function Save(AForceSave, AForceSaveAs: Boolean): Boolean;
    function CloseModule(AForceClosed: Boolean): Boolean;
    procedure ShowFileName(const AFileName: string);
    property FileName: string read GetFileName;
    property ModuleFileCount: Integer read GetModuleFileCount;
    property ModuleFileEditors[AIndex: Integer]: IOTAEditor read GetModuleFileEditor;
  end;
  IOTAProject = interface(IOTAModule)
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE4}']
    procedure RemoveFile(const AFileName: string);
  end;
  IOTAProjectGroup = interface(IOTAModule)
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE5}']
    procedure RemoveProject(const AProject: IOTAProject);
    function GetProjectCount: Integer;
    function GetProject(AIndex: Integer): IOTAProject;
    function GetActiveProject: IOTAProject;
    procedure SetActiveProject(const AProject: IOTAProject);
    property ProjectCount: Integer read GetProjectCount;
    property Projects[AIndex: Integer]: IOTAProject read GetProject;
    property ActiveProject: IOTAProject read GetActiveProject write SetActiveProject;
  end;
  IOTACreator = interface
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE6}']
    function GetOwner: IOTAModule;
    function GetUnnamed: Boolean;
    function GetFileName: string;
    function GetCreatorType: string;
  end;
  IOTAModuleServices = interface
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE7}']
    function GetMainProjectGroup: IOTAProjectGroup;
    function GetActiveProject: IOTAProject;
    function CreateModule(const ACreator: IOTACreator): IOTAModule;
    function CloseAll: Boolean;
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    property MainProjectGroup: IOTAProjectGroup read GetMainProjectGroup;
    property ModuleCount: Integer read GetModuleCount;
    property Modules[AIndex: Integer]: IOTAModule read GetModule;
  end;
  IOTAActionServices = interface
    ['{51798E1E-FB21-413D-B94E-16C474CE2FE8}']
    function OpenFile(const AFileName: string): Boolean;
    function OpenProject(const AFileName: string; ANewProjectGroup: Boolean): Boolean;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
