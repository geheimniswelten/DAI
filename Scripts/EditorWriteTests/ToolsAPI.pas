unit ToolsAPI;

interface

uses
  System.Classes;

type
  IOTAEditor = interface
    ['{6BB33D70-158F-44D8-8111-A507DC43D10B}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;

  IOTASourceEditor = interface(IOTAEditor)
    ['{4D1D3E81-BF48-4B9F-BD83-90A737EDC006}']
  end;

  IOTAModule = interface
    ['{34FB6276-488B-4529-9DC5-8985BF6F6F89}']
    function GetFileName: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(AIndex: Integer): IOTAEditor;
    property FileName: string read GetFileName;
    property ModuleFileCount: Integer read GetModuleFileCount;
    property ModuleFileEditors[AIndex: Integer]: IOTAEditor read GetModuleFileEditor;
  end;

  IOTAModuleServices = interface
    ['{746F7B6D-2F94-411D-95AF-4D42993613C0}']
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    property ModuleCount: Integer read GetModuleCount;
    property Modules[AIndex: Integer]: IOTAModule read GetModule;
  end;

  IOTAModuleInfo = interface
    ['{5FB149AB-C21A-4A6E-9E6C-2D7F86D51D6B}']
    function GetFileName: string;
    procedure GetAdditionalFiles(AFiles: TStrings);
    property FileName: string read GetFileName;
  end;

  IOTAProject = interface
    ['{B1C03BE2-725C-4D12-9F29-5A74621970C8}']
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModuleInfo;
  end;

  IOTAActionServices = interface
    ['{3508BF35-98C9-4D62-AC62-59122257A1B0}']
    function OpenFile(const AFileName: string): Boolean;
    function SaveFile(const AFileName: string): Boolean;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
