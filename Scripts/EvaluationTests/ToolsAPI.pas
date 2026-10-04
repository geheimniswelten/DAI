unit ToolsAPI;
interface
type
  TOTAAddress = UInt64;
  TOTAEvaluateResult = (erOK, erError, erDeferred, erBusy);
  TOTAEvalSideEffects = (eseNone, eseAll, esePropertiesOnly);
  TOTAThreadState = (tsStopped, tsRunnable, tsBlocked, tsNone, tsOther);
  TOTAProcessState = (psNothing, psRunning, psStopping, psStopped, psFault, psResFault, psTerminated, psException, psNoProcess);
  TOTANotifyReason = (nrOther, nrRunning, nrStopped, nrException, nrFault);
  IOTANotifier = interface
    ['{F17A7BCF-E07D-11D1-AB0B-00C04FB16FB3}']
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
  end;
  IOTAThreadNotifier = interface(IOTANotifier)
    ['{34B2E2D7-E36F-11D1-AB0E-00C04FB16FB3}']
    procedure ThreadNotify(Reason: TOTANotifyReason);
    procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
      ResultAddress, ResultSize: LongWord; ReturnCode: Integer);
    procedure ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
  end;
  IOTAThreadNotifier160 = interface(IOTAThreadNotifier)
    ['{46F94C52-E225-4054-A5F0-F5E67E29B2C2}']
    procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
      ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer); overload;
  end;
  IOTAProcess = interface;
  IOTAThread = interface
    ['{2CBF37C1-8845-4C06-8658-79E11F6D76EA}']
    function GetOSThreadID: LongWord;
    function GetState: TOTAThreadState;
    function GetOwningProcess: IOTAProcess;
    function AddNotifier(const ANotifier: IOTAThreadNotifier): Integer;
    procedure RemoveNotifier(const AIndex: Integer);
    function Evaluate(const ExprStr: string; ResultStr: PChar; ResultStrSize: LongWord;
      out CanModify: Boolean; SideEffects: TOTAEvalSideEffects; FormatSpecifiers: PAnsiChar;
      out ResultAddr: TOTAAddress; out ResultSize, ResultVal: LongWord; FileName: string; LineNumber: Integer): TOTAEvaluateResult;
    function Modify(const ValueStr: string; ResultStr: PChar; ResultSize: LongWord; out ResultVal: Integer): TOTAEvaluateResult;
    property OSThreadID: LongWord read GetOSThreadID;
    property State: TOTAThreadState read GetState;
    property OwningProcess: IOTAProcess read GetOwningProcess;
  end;
  IOTAProcess = interface
    ['{FBECB2A2-80BF-400D-B4A6-0BCEABC2FF7D}']
    function GetOSProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    function GetCurrentThread: IOTAThread;
    function GetThreadCount: Integer;
    function GetThread(const AIndex: Integer): IOTAThread;
    property OSProcessId: LongWord read GetOSProcessId;
    property ProcessState: TOTAProcessState read GetProcessState;
    property CurrentThread: IOTAThread read GetCurrentThread;
    property ThreadCount: Integer read GetThreadCount;
    property Threads[const AIndex: Integer]: IOTAThread read GetThread;
  end;
  IOTADebuggerServices = interface
    ['{587EAFAE-B8B2-4007-A233-BE09052BB67A}']
    function GetCurrentProcess: IOTAProcess;
    function GetProcessCount: Integer;
    function GetProcess(const AIndex: Integer): IOTAProcess;
    procedure ProcessDebugEvents;
    property CurrentProcess: IOTAProcess read GetCurrentProcess;
    property ProcessCount: Integer read GetProcessCount;
    property Processes[const AIndex: Integer]: IOTAProcess read GetProcess;
  end;
var BorlandIDEServices: IInterface;
implementation
end.
