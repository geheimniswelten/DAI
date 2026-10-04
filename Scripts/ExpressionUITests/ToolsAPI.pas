unit ToolsAPI;
interface
type
  TOTAEditPos = packed record Col: SmallInt; Line: Longint; end;
  TOTACharPos = packed record CharIndex: SmallInt; Line: Longint; end;
  TOTABlockType = (btInclusive, btLine, btColumn, btNonInclusive, btUnknown);
  TOTAThreadState = (tsStopped, tsRunnable, tsBlocked, tsNone, tsOther);
  TOTAProcessState = (psNothing, psRunning, psStopping, psStopped, psFault, psResFault, psTerminated, psException, psNoProcess);
  IOTAEditView = interface;
  IOTAEditBuffer = interface;
  IOTAProcess = interface;
  IOTAEditor = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D101}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;
  IOTAEditReader = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D102}']
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
  IOTASourceEditor = interface(IOTAEditor)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D103}']
    function CreateReader: IOTAEditReader;
    function GetEditViewCount: Integer;
    function GetEditView(Index: Integer): IOTAEditView;
    function GetBlockStart: TOTACharPos;
    function GetBlockAfter: TOTACharPos;
    function GetBlockType: TOTABlockType;
    function GetBlockVisible: Boolean;
    property EditViewCount: Integer read GetEditViewCount;
    property EditViews[Index: Integer]: IOTAEditView read GetEditView;
    property BlockStart: TOTACharPos read GetBlockStart;
    property BlockAfter: TOTACharPos read GetBlockAfter;
    property BlockType: TOTABlockType read GetBlockType;
    property BlockVisible: Boolean read GetBlockVisible;
  end;
  IOTAEditBuffer = interface(IOTASourceEditor)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D104}']
  end;
  IOTAEditView = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D105}']
    function GetBuffer: IOTAEditBuffer;
    function GetCursorPos: TOTAEditPos;
    function SameView(const EditView: IOTAEditView): Boolean;
    property Buffer: IOTAEditBuffer read GetBuffer;
    property CursorPos: TOTAEditPos read GetCursorPos;
  end;
  IOTAEditActions = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D106}']
    procedure AddWatch;
    procedure AddWatchAtCursor;
    procedure EvaluateModify;
    procedure InspectAtCursor;
  end;
  IOTAModule = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D107}']
    function GetCurrentEditor: IOTAEditor;
    property CurrentEditor: IOTAEditor read GetCurrentEditor;
  end;
  IOTAModuleServices = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D108}']
    function CurrentModule: IOTAModule;
  end;
  IOTAEditorServices = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D109}']
    function GetTopView: IOTAEditView;
    property TopView: IOTAEditView read GetTopView;
  end;
  IOTAThread = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D110}']
    function GetState: TOTAThreadState;
    function GetOSThreadID: LongWord;
    function GetOwningProcess: IOTAProcess;
    property State: TOTAThreadState read GetState;
    property OSThreadID: LongWord read GetOSThreadID;
    property OwningProcess: IOTAProcess read GetOwningProcess;
  end;
  IOTAProcess = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D111}']
    function GetCurrentThread: IOTAThread;
    function GetOSProcessId: LongWord;
    function GetProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    property CurrentThread: IOTAThread read GetCurrentThread;
    property OSProcessId: LongWord read GetOSProcessId;
    property ProcessId: LongWord read GetProcessId;
    property ProcessState: TOTAProcessState read GetProcessState;
  end;
  IOTADebuggerServices = interface(IInterface)
    ['{E4612E48-CCFE-4B55-B758-E07B00A3D112}']
    function GetCurrentProcess: IOTAProcess;
    property CurrentProcess: IOTAProcess read GetCurrentProcess;
  end;
var BorlandIDEServices: IInterface;
implementation
end.
