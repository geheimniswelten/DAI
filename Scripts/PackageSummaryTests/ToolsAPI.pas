unit ToolsAPI;

interface

type
  IOTAServices = interface(IInterface)
    ['{D1358CFB-9B5C-4E6C-BC4B-C6D06C6689C1}']
    function GetBaseRegistryKey: string;
    function ExpandRootMacro(const S: string): string;
  end;

  IOTABuildConfiguration = interface(IInterface)
    ['{94D4EC42-9402-49E6-8FDA-6D3E02645B93}']
    function GetValue(const PropName: string; IncludeInheritedValues: Boolean): string;
  end;

  IOTAPackageInfo = interface(IInterface)
    ['{F41DB233-500B-4B0D-93A0-9072E10EE069}']
    function GetFileName: string;
    function GetLoaded: Boolean;
    property FileName: string read GetFileName;
    property Loaded: Boolean read GetLoaded;
  end;

  IOTAPackageServices = interface(IInterface)
    ['{1E8AB2DA-CC56-4FA5-851A-9CDC957D1D65}']
    function GetPackageCount: Integer;
    function GetPackage(Index: Integer): IOTAPackageInfo;
    property PackageCount: Integer read GetPackageCount;
    property Package[Index: Integer]: IOTAPackageInfo read GetPackage;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
