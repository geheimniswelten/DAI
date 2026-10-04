unit ToolsAPI;
interface
type
  TOTAEditPos = packed record
    Col: SmallInt;
    Line: Longint;
  end;
  TOTACharPos = packed record
    CharIndex: SmallInt;
    Line: Longint;
  end;
  TOTABlockType = (btInclusive, btLine, btColumn, btNonInclusive, btUnknown);
  IOTAEditView = interface;
  IOTAEditBuffer = interface;
  IOTAEditReader = interface
    ['{65A1D861-1A4A-4383-84F6-D95EE8380511}']
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
  IOTAEditor = interface
    ['{65A1D861-1A4A-4383-84F6-D95EE8380512}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;
  IOTASourceEditor = interface(IOTAEditor)
    ['{65A1D861-1A4A-4383-84F6-D95EE8380513}']
    function CreateReader: IOTAEditReader;
    function GetEditViewCount: Integer;
    function GetEditView(Index: Integer): IOTAEditView;
    function GetBlockStart: TOTACharPos;
    function GetBlockAfter: TOTACharPos;
    property EditViewCount: Integer read GetEditViewCount;
    property EditViews[Index: Integer]: IOTAEditView read GetEditView;
    property BlockStart: TOTACharPos read GetBlockStart;
    property BlockAfter: TOTACharPos read GetBlockAfter;
  end;
  IOTAEditBuffer = interface(IOTASourceEditor)
    ['{65A1D861-1A4A-4383-84F6-D95EE8380514}']
  end;
  IOTAEditBlock = interface
    ['{65A1D861-1A4A-4383-84F6-D95EE8380515}']
    function GetVisible: Boolean;
    function GetIsValid: Boolean;
    function GetSize: Integer;
    function GetStyle: TOTABlockType;
    function GetStartingRow: Integer;
    function GetEndingRow: Integer;
    function GetText: string;
    property Visible: Boolean read GetVisible;
    property IsValid: Boolean read GetIsValid;
    property Size: Integer read GetSize;
    property Style: TOTABlockType read GetStyle;
    property StartingRow: Integer read GetStartingRow;
    property EndingRow: Integer read GetEndingRow;
    property Text: string read GetText;
  end;
  IOTAEditView = interface
    ['{65A1D861-1A4A-4383-84F6-D95EE8380516}']
    function GetCursorPos: TOTAEditPos;
    function GetBuffer: IOTAEditBuffer;
    function GetBlock: IOTAEditBlock;
    procedure ConvertPos(EdPosToCharPos: Boolean; var EditPos: TOTAEditPos; var CharPos: TOTACharPos);
    function CharPosToPos(CharPos: TOTACharPos): Longint;
    function SameView(const EditView: IOTAEditView): Boolean;
    property CursorPos: TOTAEditPos read GetCursorPos;
    property Buffer: IOTAEditBuffer read GetBuffer;
    property Block: IOTAEditBlock read GetBlock;
  end;
  IOTAModule = interface
    ['{65A1D861-1A4A-4383-84F6-D95EE8380517}']
    function GetCurrentEditor: IOTAEditor;
    property CurrentEditor: IOTAEditor read GetCurrentEditor;
  end;
  IOTAModuleServices = interface
    ['{65A1D861-1A4A-4383-84F6-D95EE8380518}']
    function CurrentModule: IOTAModule;
  end;
  IOTAEditorServices = interface
    ['{65A1D861-1A4A-4383-84F6-D95EE8380519}']
    function GetTopView: IOTAEditView;
    property TopView: IOTAEditView read GetTopView;
  end;
var
  BorlandIDEServices: IInterface;
implementation
end.
