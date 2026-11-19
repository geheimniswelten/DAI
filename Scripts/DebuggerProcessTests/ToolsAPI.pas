unit ToolsAPI;

interface

type
  TOTAThreadState = (tsStopped, tsRunnable, tsBlocked, tsNone, tsOther);
  TOTAProcessState = (psNothing, psRunning, psStopping, psStopped, psFault, psResFault, psTerminated, psException, psNoProcess);
  TOTARunMode = (ormRun, ormStmtStepInto, ormStmtStepOver, ormRunUntilReturn, ormUnused);

  IOTAThread = interface
    function GetOSThreadID: LongWord;
    function GetState: TOTAThreadState;
    function GetCurrentFile: string;
    function GetCurrentLine: LongWord;
    property State: TOTAThreadState read GetState;
    property CurrentFile: string read GetCurrentFile;
    property CurrentLine: LongWord read GetCurrentLine;
  end;

  IOTAProcess = interface
    ['{FBECB2A2-80BF-400D-B4A6-0BCEABC2FF7D}']
    function GetCurrentThread: IOTAThread;
    function GetThreadCount: Integer;
    function GetProcessId: LongWord;
    function GetOSProcessId: LongWord;
    function GetProcessState: TOTAProcessState;
    function GetExeName: string;
    function GetState: string;
    function GetStatus: string;
    procedure Detach;
    procedure Pause;
    procedure Run(Mode: TOTARunMode);
    property CurrentThread: IOTAThread read GetCurrentThread;
    property ThreadCount: Integer read GetThreadCount;
    property ProcessId: LongWord read GetProcessId;
    property OSProcessId: LongWord read GetOSProcessId;
    property ProcessState: TOTAProcessState read GetProcessState;
    property ExeName: string read GetExeName;
    property State: string read GetState;
    property Status: string read GetStatus;
  end;

  IOTABreakpoint = interface
    ['{BAC29393-8C12-4CA8-A7C9-661876907544}']
    function GetFileName: string;
    function GetLineNumber: Integer;
    function GetEnabled: Boolean;
    procedure SetEnabled(Value: Boolean);
    function GetExpression: string;
    procedure SetExpression(const Value: string);
    function GetPassCount: Integer;
    procedure SetPassCount(Value: Integer);
    function GetCurPassCount: Integer;
    function GetGroupName: string;
    function GetValidInCurrentProcess: Boolean;
    property FileName: string read GetFileName;
    property LineNumber: Integer read GetLineNumber;
    property Enabled: Boolean read GetEnabled write SetEnabled;
    property Expression: string read GetExpression write SetExpression;
    property PassCount: Integer read GetPassCount write SetPassCount;
    property CurPassCount: Integer read GetCurPassCount;
    property GroupName: string read GetGroupName;
    property ValidInCurrentProcess: Boolean read GetValidInCurrentProcess;
  end;

  IOTASourceBreakpoint = interface(IOTABreakpoint)
    ['{8F1645BC-4C77-48A4-96B9-AADB48A3F88C}']
  end;

  TEnumerateProcessesCallback = procedure (Pid: LongWord; const ProcessName: string; Param: Pointer);

  IOTADebuggerServices = interface
    ['{587EAFAE-B8B2-4007-A233-BE09052BB67A}']
    function GetCurrentProcess: IOTAProcess;
    function GetProcessCount: Integer;
    function GetProcess(Index: Integer): IOTAProcess;
    function GetSourceBkptCount: Integer;
    function GetAddressBkptCount: Integer;
    function GetSourceBkpt(Index: Integer): IOTASourceBreakpoint;
    function NewSourceBreakpoint(const FileName: string; LineNumber: Integer; const AProcess: IOTAProcess): IOTABreakpoint;
    procedure RemoveBreakpoint(const Breakpoint: IOTABreakpoint);
    procedure CreateProcess(const ExeName, Args: string; const RemoteHost: string = '');
    procedure AttachProcess(Pid: Integer; PauseAfterAttach: Boolean; DetachOnReset: Boolean; const RemoteHost: string = '');
    procedure EnumerateRunningProcesses(Callback: TEnumerateProcessesCallback; Param: Pointer; const HostName: string = '');
    property CurrentProcess: IOTAProcess read GetCurrentProcess;
    property ProcessCount: Integer read GetProcessCount;
    property Processes[Index: Integer]: IOTAProcess read GetProcess;
    property SourceBkptCount: Integer read GetSourceBkptCount;
    property AddressBkptCount: Integer read GetAddressBkptCount;
    property SourceBkpts[Index: Integer]: IOTASourceBreakpoint read GetSourceBkpt;
  end;

var
  BorlandIDEServices: IInterface;

implementation

end.
