unit ToolsAPI;

// Isolated doubles expose only the documented SDK methods used by the real stack unit.
// Test.Stack.ps1 also compiles that unit separately against the installed, complete ToolsAPI.
interface

type
  TOTAThreadState = (tsStopped, tsRunnable, tsBlocked, tsNone, tsOther);
  TOTAProcessState = (psNothing, psRunning, psStopping, psStopped, psFault, psResFault, psTerminated, psException, psNoProcess);
  TOTACallStackState = (csAccessible, csInaccessible, csWait);
  IOTAProcess = interface;

  IOTAThread = interface
    ['{2CBF37C1-8845-4C06-8658-79E11F6D76EA}']
    function GetOSThreadID: LongWord;
    function GetState: TOTAThreadState;
    function GetOwningProcess: IOTAProcess;
    function StartCallStackAccess: TOTACallStackState;
    procedure EndCallStackAccess;
    function GetCallCount: Integer;
    function GetCallHeader(Index: Integer): string;
    procedure GetCallPos(Index: Integer; out FileName: string; out LineNum: Integer);
    procedure Run;
    procedure Pause;
    property State: TOTAThreadState read GetState;
    property OwningProcess: IOTAProcess read GetOwningProcess;
  end;

  IOTAThread110 = interface
    ['{3A96CD8F-A5CD-4AFE-8A73-DAE1265095D9}']
    function GetSimpleCallHeader(Index: Integer): string;
  end;

  IOTAProcess = interface
    ['{FBECB2A2-80BF-400D-B4A6-0BCEABC2FF7D}']
    function GetOSProcessId: LongWord;
    function GetProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    function GetCurrentThread: IOTAThread;
    procedure SetCurrentThread(const Value: IOTAThread);
    function GetThreadCount: Integer;
    function GetThread(Index: Integer): IOTAThread;
    procedure Run;
    procedure Pause;
    procedure Terminate;
    property OSProcessId: LongWord read GetOSProcessId;
    property ProcessId: LongWord read GetProcessId;
    property ProcessState: TOTAProcessState read GetProcessState;
    property CurrentThread: IOTAThread read GetCurrentThread write SetCurrentThread;
    property ThreadCount: Integer read GetThreadCount;
    property Threads[Index: Integer]: IOTAThread read GetThread;
  end;

  IOTADebuggerServices = interface
    ['{587EAFAE-B8B2-4007-A233-BE09052BB67A}']
    function GetCurrentProcess: IOTAProcess;
    procedure SetCurrentProcess(const Value: IOTAProcess);
    function GetProcessCount: Integer;
    function GetProcess(Index: Integer): IOTAProcess;
    property CurrentProcess: IOTAProcess read GetCurrentProcess write SetCurrentProcess;
    property ProcessCount: Integer read GetProcessCount;
    property Processes[Index: Integer]: IOTAProcess read GetProcess;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
