unit ToolsAPI;
interface
uses System.TypInfo, System.Variants, Vcl.Controls;
type
  TOTAOptionName = record Name: string; Kind: TTypeKind; end;
  TOTAOptionNameArray = array of TOTAOptionName;
  IOTAOptions = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3001}']
    function GetOptionNames: TOTAOptionNameArray;
    procedure EditOptions;
  end;
  IOTAProjectOptions = interface(IOTAOptions)
    ['{F0296240-74E0-42A4-955A-E715E4CC3002}']
  end;
  IOTAEnvironmentOptions = interface(IOTAOptions)
    ['{F0296240-74E0-42A4-955A-E715E4CC3003}']
    procedure EditOptions(const AArea, APage: string); overload;
  end;
  IOTABuildConfiguration = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3004}']
    function GetName: string;
    function GetPlatform: string;
    function GetPlatformConfiguration(const AName: string): IOTABuildConfiguration;
    property Name: string read GetName;
    property Platform: string read GetPlatform;
    property PlatformConfiguration[const AName: string]: IOTABuildConfiguration read GetPlatformConfiguration;
  end;
  IOTAProjectOptionsConfigurations = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3005}']
    function GetConfigurationCount: Integer;
    function GetConfiguration(const AIndex: Integer): IOTABuildConfiguration;
    property ConfigurationCount: Integer read GetConfigurationCount;
    property Configurations[const AIndex: Integer]: IOTABuildConfiguration read GetConfiguration;
  end;
  IOTAProject = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3006}']
    function GetFileName: string;
    function GetProjectOptions: IOTAProjectOptions;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetSupportedPlatforms: TArray<string>;
    procedure SetConfiguration(const AValue: string);
    procedure SetPlatform(const AValue: string);
    property FileName: string read GetFileName;
    property ProjectOptions: IOTAProjectOptions read GetProjectOptions;
    property CurrentConfiguration: string read GetConfiguration write SetConfiguration;
    property CurrentPlatform: string read GetPlatform write SetPlatform;
    property SupportedPlatforms: TArray<string> read GetSupportedPlatforms;
  end;
  IOTAServices = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3007}']
    function GetEnvironmentOptions: IOTAEnvironmentOptions;
  end;
  INTAIDEInsightItem = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3008}']
    function GetTitle: string;
    function GetDescription: string;
    function GetVisible: Boolean;
    procedure Execute;
    property Title: string read GetTitle;
    property Description: string read GetDescription;
    property Visible: Boolean read GetVisible;
  end;
  IOTAIDEInsightCategory = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3009}']
    function GetCaption: string;
    function GetDisabled: Boolean;
    function ItemCount: Integer;
    function GetItem(const AIndex: Integer): INTAIDEInsightItem;
    property Caption: string read GetCaption;
    property Disabled: Boolean read GetDisabled;
    property Items[const AIndex: Integer]: INTAIDEInsightItem read GetItem;
  end;
  IOTAIDEInsightService = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3010}']
    function CategoryCount: Integer;
    function GetCategory(const AIndex: Variant): IOTAIDEInsightCategory;
    property Categories[const AIndex: Variant]: IOTAIDEInsightCategory read GetCategory;
  end;
  INTAIDEInsightService = interface
    ['{F0296240-74E0-42A4-955A-E715E4CC3011}']
    procedure Filter(const AText: string);
    function GetEditSearchControl: TWinControl;
    property EditSearchControl: TWinControl read GetEditSearchControl;
  end;
var BorlandIDEServices: IInterface;
implementation
end.
