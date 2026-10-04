unit ToolsAPI;

interface

uses
  System.Classes;

const
  sApplication = 'Application';
  sConsole = 'Console';
  sLibrary = 'Library';
  sPackage = 'Package';

type
  IOTAEditReader = interface
    ['{98A8BD1B-3F56-4AC4-9453-04050128BE01}']
  end;

  IOTASourceEditor = interface
    ['{98A8BD1B-3F56-4AC4-9453-04050128BE02}']
    function CreateReader: IOTAEditReader;
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;

  IOTABuildConfiguration = interface
    ['{98A8BD1B-3F56-4AC4-9453-04050128BE03}']
    function GetName: string;
    function GetKey: string;
    function GetPlatform: string;
    function GetPlatformConfiguration(const APlatform: string): IOTABuildConfiguration;
    property Name: string read GetName;
    property Key: string read GetKey;
    property Platform: string read GetPlatform;
    property PlatformConfiguration[const APlatform: string]: IOTABuildConfiguration read GetPlatformConfiguration;
  end;

  IOTAProjectOptions = interface
    ['{98A8BD1B-3F56-4AC4-9453-04050128BE04}']
    function GetTargetName: string;
    property TargetName: string read GetTargetName;
  end;

  IOTAProjectOptionsConfigurations = interface
    ['{98A8BD1B-3F56-4AC4-9453-04050128BE05}']
    function GetConfigurationCount: Integer;
    function GetConfiguration(AIndex: Integer): IOTABuildConfiguration;
    function GetActiveConfiguration: IOTABuildConfiguration;
    property ConfigurationCount: Integer read GetConfigurationCount;
    property Configurations[AIndex: Integer]: IOTABuildConfiguration read GetConfiguration;
    property ActiveConfiguration: IOTABuildConfiguration read GetActiveConfiguration;
  end;

  IOTAProject = interface
    ['{98A8BD1B-3F56-4AC4-9453-04050128BE06}']
    function GetFileName: string;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetProjectType: string;
    function GetApplicationType: string;
    function GetFrameworkType: string;
    function GetProjectOptions: IOTAProjectOptions;
    property FileName: string read GetFileName;
    property CurrentConfiguration: string read GetConfiguration;
    property CurrentPlatform: string read GetPlatform;
    property ProjectType: string read GetProjectType;
    property ApplicationType: string read GetApplicationType;
    property FrameworkType: string read GetFrameworkType;
    property ProjectOptions: IOTAProjectOptions read GetProjectOptions;
  end;

implementation

end.
