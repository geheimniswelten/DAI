unit ToolsAPI;

interface

uses
  System.Classes;

const
  sPackage = 'Package';

type
  IOTAProjectOptions = interface(IInterface)
    ['{2888E741-E7FB-4BBC-A093-4B0903D9D990}']
    function GetTargetName: string;
    property TargetName: string read GetTargetName;
  end;

  IOTAProject = interface(IInterface)
    ['{3D7E07CB-392D-4EFB-841D-A6C6E338CF13}']
    function GetFileName: string;
    function GetApplicationType: string;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetOptions: IOTAProjectOptions;
    property FileName: string read GetFileName;
    property ApplicationType: string read GetApplicationType;
    property CurrentConfiguration: string read GetConfiguration;
    property CurrentPlatform: string read GetPlatform;
    property ProjectOptions: IOTAProjectOptions read GetOptions;
  end;

  IOTAPackageInfo = interface(IInterface)
    ['{F41DB233-500B-4B0D-93A0-9072E10EE069}']
    function GetFileName: string;
    function GetIDEPackage: Boolean;
    procedure GetRequiredByList(List: TStrings);
    property FileName: string read GetFileName;
    property IDEPackage: Boolean read GetIDEPackage;
  end;

  IOTAPackageServices210 = interface(IInterface)
    ['{2C96711A-267A-4024-9C54-B11FCC596A6F}']
    function GetPackageCount: Integer;
    function GetPackage(Index: Integer): IOTAPackageInfo;
    function InstallPackage(const PackageName: string): Boolean;
    function UninstallPackage(const PackageName: string): Boolean;
    property PackageCount: Integer read GetPackageCount;
    property Package[Index: Integer]: IOTAPackageInfo read GetPackage;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
