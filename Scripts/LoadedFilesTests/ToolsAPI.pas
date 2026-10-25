unit ToolsAPI;

interface

uses
  System.Classes;

type
  IOTAModule = interface;
  IOTAProject = interface;
  IOTAEditor = interface
    ['{F17A7BD0-E07D-11D1-AB0B-00C04FB16FB3}']
    function GetFileName: string;
    function GetModule: IOTAModule;
    property FileName: string read GetFileName;
    property Module: IOTAModule read GetModule;
  end;
  IOTASourceEditor = interface(IOTAEditor)
    ['{4D460588-10A6-4CAD-87E7-5654266073F9}']
  end;
  IOTAEditBuffer = interface(IOTASourceEditor)
    ['{EB6465CE-D901-43C4-AB69-240A7400B9AA}']
  end;
  IOTAModule = interface
    ['{C0D4CBA8-54A3-48EA-BE63-98CE3D9F0F43}']
    function GetFileName: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(AIndex: Integer): IOTAEditor;
    procedure GetAssociatedFilesFromModule(AFiles: TStrings);
    property FileName: string read GetFileName;
    property ModuleFileCount: Integer read GetModuleFileCount;
    property ModuleFileEditors[AIndex: Integer]: IOTAEditor read GetModuleFileEditor;
  end;
  IOTAAdditionalModuleFiles = interface
    ['{2D73A12F-6FB3-11D4-A4B8-00C04F6BB853}']
    function GetAdditionalModuleFileCount: Integer;
    function GetAdditionalModuleFileEditor(AIndex: Integer): IOTAEditor;
    property AdditionalModuleFileCount: Integer read GetAdditionalModuleFileCount;
    property AdditionalModuleFileEditors[AIndex: Integer]: IOTAEditor read GetAdditionalModuleFileEditor;
  end;
  IOTAProject = interface(IOTAModule)
    ['{0E4BFB1D-2F3B-4CD6-A9A2-4903713B59E0}']
    procedure GetAssociatedFiles(const AFileName: string; AFiles: TStrings);
  end;
  IOTAProjectGroup = interface(IOTAModule)
    ['{B9EAE73C-8A03-4729-A232-EEE626801A0B}']
    function GetProjectCount: Integer;
    function GetProject(AIndex: Integer): IOTAProject;
    property ProjectCount: Integer read GetProjectCount;
    property Projects[AIndex: Integer]: IOTAProject read GetProject;
  end;
  IOTAModuleServices = interface
    ['{55A5E848-27FB-4880-8E7C-7F05A9802482}']
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    function GetMainProjectGroup: IOTAProjectGroup;
    function GetActiveProject: IOTAProject;
    function FindModule(const AFileName: string): IOTAModule;
    property ModuleCount: Integer read GetModuleCount;
    property Modules[AIndex: Integer]: IOTAModule read GetModule;
    property MainProjectGroup: IOTAProjectGroup read GetMainProjectGroup;
  end;
  IOTAEditBufferIterator = interface
    ['{8ECB33AA-D0BD-11D2-ABD6-00C04FB16FB3}']
    function GetCount: Integer;
    function GetEditBuffer(AIndex: Integer): IOTAEditBuffer;
    property Count: Integer read GetCount;
    property EditBuffers[AIndex: Integer]: IOTAEditBuffer read GetEditBuffer;
  end;
  IOTAEditorServices = interface
    ['{CAC82350-3885-4CAE-84AE-F1C3B38A6E91}']
    function GetEditBufferIterator(out AIterator: IOTAEditBufferIterator): Boolean;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
