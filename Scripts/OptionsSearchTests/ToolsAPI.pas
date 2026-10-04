unit ToolsAPI;

interface

uses
  System.TypInfo,
  System.Variants;

type
  TOTAOptionName = record
    Name: string;
    Kind: TTypeKind;
  end;
  TOTAOptionNameArray = array of TOTAOptionName;

  IOTAProjectOptions = interface
    ['{3CC4E4F0-2609-4D33-89AC-6958A2AA9601}']
    function GetOptionNames: TOTAOptionNameArray;
  end;

  IOTAEnvironmentOptions = interface
    ['{3CC4E4F0-2609-4D33-89AC-6958A2AA9602}']
    function GetOptionNames: TOTAOptionNameArray;
  end;

  IOTAServices = interface
    ['{3CC4E4F0-2609-4D33-89AC-6958A2AA9603}']
    function GetEnvironmentOptions: IOTAEnvironmentOptions;
  end;

  IOTAProject = interface
    ['{3CC4E4F0-2609-4D33-89AC-6958A2AA9604}']
    function GetFileName: string;
    function GetConfiguration: string;
    function GetPlatform: string;
    function GetProjectOptions: IOTAProjectOptions;
    property FileName: string read GetFileName;
    property CurrentConfiguration: string read GetConfiguration;
    property CurrentPlatform: string read GetPlatform;
    property ProjectOptions: IOTAProjectOptions read GetProjectOptions;
  end;

  INTAIDEInsightItem = interface
    ['{3CC4E4F0-2609-4D33-89AC-6958A2AA9605}']
    function GetTitle: string;
    function GetDescription: string;
    function GetVisible: Boolean;
    procedure Execute;
    procedure Update;
    property Title: string read GetTitle;
    property Description: string read GetDescription;
    property Visible: Boolean read GetVisible;
  end;

  IOTAIDEInsightCategory = interface
    ['{3CC4E4F0-2609-4D33-89AC-6958A2AA9606}']
    function GetCaption: string;
    function GetDisabled: Boolean;
    function GetItem(const AIndex: Integer): INTAIDEInsightItem;
    function ItemCount: Integer;
    property Caption: string read GetCaption;
    property Disabled: Boolean read GetDisabled;
    property Items[const AIndex: Integer]: INTAIDEInsightItem read GetItem;
  end;

  IOTAIDEInsightService = interface
    ['{3CC4E4F0-2609-4D33-89AC-6958A2AA9607}']
    function CategoryCount: Integer;
    function GetCategory(const AIndexOrName: Variant): IOTAIDEInsightCategory;
    procedure Invoke;
    procedure Filter(const AText: string);
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
