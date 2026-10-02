unit ToolsAPI;

interface

type
  TOTAThreadState = (tsStopped, tsRunnable, tsBlocked, tsNone, tsOther);
  TOTAProcessState = (psNothing, psRunning, psStopping, psStopped, psFault, psResFault, psTerminated, psException, psNoProcess);

  IOTAThread = interface
    ['{2CBF37C1-8845-4C06-8658-79E11F6D76EA}']
    function GetOSThreadID: LongWord;
    function GetState: TOTAThreadState;
    function GetCurrentFile: string;
    function GetCurrentLine: LongWord;
    property State: TOTAThreadState read GetState;
    property CurrentFile: string read GetCurrentFile;
    property CurrentLine: LongWord read GetCurrentLine;
  end;

  // The optional capabilities are separate in this fixture so unsupported
  // debugger providers can be tested; real signatures are also SDK-compiled.
  IOTAThread90 = interface
    ['{175F985B-4F54-41B2-A0A1-54F3B66ECD07}']
    function GetDisplayString: string;
  end;

  IOTAThread140 = interface
    ['{BC146984-1E20-4695-879A-25E6A82F52F7}']
    function GetThreadName: string;
    procedure SetThreadName(const Name: string);
  end;

  IOTAProcess = interface
    ['{FBECB2A2-80BF-400D-B4A6-0BCEABC2FF7D}']
    function GetCurrentThread: IOTAThread;
    procedure SetCurrentThread(Value: IOTAThread);
    function GetThreadCount: Integer;
    function GetThread(Index: Integer): IOTAThread;
    function GetProcessId: LongWord;
    function GetOSProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    procedure SetProcessState(const NewState: TOTAProcessState);
    property CurrentThread: IOTAThread read GetCurrentThread write SetCurrentThread;
    property ThreadCount: Integer read GetThreadCount;
    property Threads[Index: Integer]: IOTAThread read GetThread;
    property ProcessId: LongWord read GetProcessId;
    property OSProcessId: LongWord read GetOSProcessId;
    property ProcessState: TOTAProcessState read GetProcessState write SetProcessState;
  end;

  IOTADebuggerServices = interface
    ['{0E3B9D7A-E119-11D1-AB0C-00C04FB16FB3}']
    function GetCurrentProcess: IOTAProcess;
    procedure SetCurrentProcess(const Process: IOTAProcess);
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
