unit h5u.DAI.Launcher.Processes;

interface

uses
  System.JSON,
  Winapi.Windows;

type
  TDAIIDEProcess = record
    ProcessId: Cardinal;
    Executable: string;
    CreationTime: string;
    Architecture: string;
    Verified: Boolean;
  end;

  TDAILauncherProcesses = class sealed
  public
    class function List: TArray<TDAIIDEProcess>; static;
    class function Inspect(const AHandle: THandle; const AProcessId: Cardinal; out AProcess: TDAIIDEProcess): Boolean; static;
    class function OpenVerified(const AProcess: TDAIIDEProcess; const ATerminate: Boolean): THandle; static;
    class function MainWindow(const AProcessId: Cardinal): HWND; static;
    class function FileInfo(const AExecutable: string): TJSONObject; static;
    class function ProcessJson(const AProcess: TDAIIDEProcess; const ARegisteredExecutable: string): TJSONObject; static;
    class function SameExecutable(const ALeft, ARight: string): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  Winapi.TlHelp32;

const
  CQueryLimitedInformation = $1000;

type
  TQueryProcessImage = function(AProcess: THandle; AFlags: DWORD; AFileName: PWideChar; var ASize: DWORD): BOOL; stdcall;
  TIsWow64Process2 = function(AProcess: THandle; AProcessMachine, ANativeMachine: PWord): BOOL; stdcall;

  TMainWindowSearch = record
    ProcessId: Cardinal;
    Window: HWND;
    Count: Integer;
  end;
  PMainWindowSearch = ^TMainWindowSearch;

function TokenUserBytes(const AProcess: THandle; out ABytes: TBytes): Boolean;
var
  LSize: DWORD;
  LToken: THandle;
begin
  Result := False;
  if not OpenProcessToken(AProcess, TOKEN_QUERY, LToken) then
    Exit;
  try
    LSize := 0;
    GetTokenInformation(LToken, TokenUser, nil, 0, LSize);
    if LSize = 0 then
      Exit;
    SetLength(ABytes, LSize);
    Result := GetTokenInformation(LToken, TokenUser, @ABytes[0], LSize, LSize);
  finally
    CloseHandle(LToken);
  end;
end;

function SameUserAndSession(const AHandle: THandle; const AProcessId: Cardinal): Boolean;
var
  LCurrentSession, LTargetSession: DWORD;
  LCurrentUser, LTargetUser: TBytes;
begin
  Result := ProcessIdToSessionId(GetCurrentProcessId, LCurrentSession) and ProcessIdToSessionId(AProcessId, LTargetSession);
  if not Result or (LCurrentSession <> LTargetSession) then
    Exit(False);
  if not TokenUserBytes(GetCurrentProcess, LCurrentUser) or not TokenUserBytes(AHandle, LTargetUser) then
    Exit(False);
  Result := EqualSid(PTokenUser(@LCurrentUser[0])^.User.Sid, PTokenUser(@LTargetUser[0])^.User.Sid);
end;

function ProcessArchitecture(const AHandle: THandle): string;
var
  LFunction: TIsWow64Process2;
  LNativeMachine, LProcessMachine: Word;
  LSystemInfo: TSystemInfo;
  LWow64: BOOL;
begin
  Result := 'unknown';
  LFunction := TIsWow64Process2(GetProcAddress(GetModuleHandle('kernel32.dll'), 'IsWow64Process2'));
  if Assigned(LFunction) then
    if LFunction(AHandle, @LProcessMachine, @LNativeMachine) then
  begin
    if LProcessMachine = IMAGE_FILE_MACHINE_I386 then
      Exit('Win32');
    if (LProcessMachine = IMAGE_FILE_MACHINE_AMD64) or
      ((LProcessMachine = IMAGE_FILE_MACHINE_UNKNOWN) and (LNativeMachine = IMAGE_FILE_MACHINE_AMD64)) then
      Exit('Win64');
    if LNativeMachine = IMAGE_FILE_MACHINE_I386 then
      Exit('Win32');
    Exit;
  end;
  if not IsWow64Process(AHandle, LWow64) then
    Exit;
  if LWow64 then
    Exit('Win32');
  GetNativeSystemInfo(LSystemInfo);
  if LSystemInfo.wProcessorArchitecture = PROCESSOR_ARCHITECTURE_AMD64 then
    Result := 'Win64'
  else if LSystemInfo.wProcessorArchitecture = PROCESSOR_ARCHITECTURE_INTEL then
    Result := 'Win32';
end;

class function TDAILauncherProcesses.Inspect(const AHandle: THandle; const AProcessId: Cardinal; out AProcess: TDAIIDEProcess): Boolean;
var
  LCreation, LExit, LKernel, LUser: TFileTime;
  LFunction: TQueryProcessImage;
  LSize: DWORD;
begin
  AProcess := Default(TDAIIDEProcess);
  AProcess.ProcessId := AProcessId;
  Result := False;
  if (AHandle = 0) or not SameUserAndSession(AHandle, AProcessId) then
    Exit;
  if WaitForSingleObject(AHandle, 0) <> WAIT_TIMEOUT then
    Exit;
  LFunction := TQueryProcessImage(GetProcAddress(GetModuleHandle('kernel32.dll'), 'QueryFullProcessImageNameW'));
  if not Assigned(LFunction) then
    Exit;
  SetLength(AProcess.Executable, 32768);
  LSize := Length(AProcess.Executable);
  if not LFunction(AHandle, 0, PWideChar(AProcess.Executable), LSize) then
    Exit;
  SetLength(AProcess.Executable, LSize);
  if not SameText(TPath.GetFileName(AProcess.Executable), 'bds.exe') then
    Exit;
  if not GetProcessTimes(AHandle, LCreation, LExit, LKernel, LUser) then
    Exit;
  AProcess.CreationTime := UIntToStr((UInt64(LCreation.dwHighDateTime) shl 32) or LCreation.dwLowDateTime);
  AProcess.Architecture := ProcessArchitecture(AHandle);
  AProcess.Verified := True;
  Result := True;
end;

class function TDAILauncherProcesses.List: TArray<TDAIIDEProcess>;
var
  LEntry: TProcessEntry32;
  LHandle, LSnapshot: THandle;
  LItems: TList<TDAIIDEProcess>;
  LProcess: TDAIIDEProcess;
  LCurrentSession, LTargetSession: DWORD;
begin
  LItems := TList<TDAIIDEProcess>.Create;
  try
    LSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if LSnapshot = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    try
      LEntry := Default(TProcessEntry32);
      LEntry.dwSize := SizeOf(LEntry);
      if not Process32First(LSnapshot, LEntry) then
      begin
        if GetLastError <> ERROR_NO_MORE_FILES then
          RaiseLastOSError;
      end
      else
      begin
        repeat
          if not SameText(string(LEntry.szExeFile), 'bds.exe') then
            Continue;
          if not ProcessIdToSessionId(GetCurrentProcessId, LCurrentSession) or
            not ProcessIdToSessionId(LEntry.th32ProcessID, LTargetSession) then
            Continue;
          if LCurrentSession <> LTargetSession then
            Continue;
          LHandle := OpenProcess(CQueryLimitedInformation or SYNCHRONIZE, False, LEntry.th32ProcessID);
          if LHandle = 0 then
          begin
            LProcess := Default(TDAIIDEProcess);
            LProcess.ProcessId := LEntry.th32ProcessID;
            LItems.Add(LProcess);
            Continue;
          end;
          try
            if Inspect(LHandle, LEntry.th32ProcessID, LProcess) then
              LItems.Add(LProcess)
            else if WaitForSingleObject(LHandle, 0) = WAIT_TIMEOUT then
            begin
              LProcess := Default(TDAIIDEProcess);
              LProcess.ProcessId := LEntry.th32ProcessID;
              LItems.Add(LProcess);
            end;
          finally
            CloseHandle(LHandle);
          end;
        until not Process32Next(LSnapshot, LEntry);
        if GetLastError <> ERROR_NO_MORE_FILES then
          RaiseLastOSError;
      end;
    finally
      CloseHandle(LSnapshot);
    end;
    Result := LItems.ToArray;
  finally
    LItems.Free;
  end;
end;

class function TDAILauncherProcesses.SameExecutable(const ALeft, ARight: string): Boolean;
begin
  Result := (ALeft <> '') and (ARight <> '') and SameText(TPath.GetFullPath(ALeft), TPath.GetFullPath(ARight));
end;

class function TDAILauncherProcesses.OpenVerified(const AProcess: TDAIIDEProcess; const ATerminate: Boolean): THandle;
var
  LActual: TDAIIDEProcess;
  LAccess: DWORD;
begin
  if not AProcess.Verified then
    raise EInvalidOperation.Create('Die IDE-Prozessidentität ist nicht verifiziert.');
  LAccess := CQueryLimitedInformation or SYNCHRONIZE;
  if ATerminate then
    LAccess := LAccess or PROCESS_TERMINATE;
  Result := OpenProcess(LAccess, False, AProcess.ProcessId);
  if Result = 0 then
    RaiseLastOSError;
  if not Inspect(Result, AProcess.ProcessId, LActual) or
    not SameExecutable(LActual.Executable, AProcess.Executable) or (LActual.CreationTime <> AProcess.CreationTime) then
  begin
    CloseHandle(Result);
    raise EInvalidOperation.Create('Die IDE wurde zwischenzeitlich beendet oder die Prozessidentität hat sich geändert.');
  end;
end;

function FindMainWindow(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
var
  LClassName: array[0..255] of Char;
  LProcessId: DWORD;
  LSearch: PMainWindowSearch;
begin
  Result := True;
  LSearch := PMainWindowSearch(AParam);
  GetWindowThreadProcessId(AWindow, LProcessId);
  if LProcessId <> LSearch.ProcessId then
    Exit;
  if GetClassName(AWindow, LClassName, Length(LClassName)) = 0 then
    Exit;
  // The Delphi IDE's VCL main form is TAppBuilder. Never close a modal dialog or splash screen instead.
  if not SameText(string(LClassName), 'TAppBuilder') then
    Exit;
  Inc(LSearch.Count);
  LSearch.Window := AWindow;
end;

class function TDAILauncherProcesses.MainWindow(const AProcessId: Cardinal): HWND;
var
  LSearch: TMainWindowSearch;
begin
  LSearch := Default(TMainWindowSearch);
  LSearch.ProcessId := AProcessId;
  if not EnumWindows(@FindMainWindow, LPARAM(@LSearch)) then
    RaiseLastOSError;
  if LSearch.Count = 1 then
    Result := LSearch.Window
  else
    Result := 0;
end;

function ExecutableArchitecture(const AExecutable: string): string;
var
  LStream: TFileStream;
  LOffset, LSignature: Cardinal;
  LMachine, LMagic: Word;
begin
  Result := 'unknown';
  if not TFile.Exists(AExecutable) then
    Exit;
  try
    LStream := TFileStream.Create(AExecutable, fmOpenRead or fmShareDenyNone);
    try
      if LStream.Size < 64 then
        Exit;
      LStream.ReadBuffer(LMagic, SizeOf(LMagic));
      if LMagic <> $5A4D then
        Exit;
      LStream.Position := $3C;
      LStream.ReadBuffer(LOffset, SizeOf(LOffset));
      if UInt64(LOffset) + 6 > UInt64(LStream.Size) then
        Exit;
      LStream.Position := LOffset;
      LStream.ReadBuffer(LSignature, SizeOf(LSignature));
      if LSignature <> $4550 then
        Exit;
      LStream.ReadBuffer(LMachine, SizeOf(LMachine));
      if LMachine = IMAGE_FILE_MACHINE_I386 then
        Result := 'Win32'
      else if LMachine = IMAGE_FILE_MACHINE_AMD64 then
        Result := 'Win64';
    finally
      LStream.Free;
    end;
  except
    Result := 'unknown';
  end;
end;

class function TDAILauncherProcesses.FileInfo(const AExecutable: string): TJSONObject;
var
  LBytes: TBytes;
  LDelphiVersion, LFileVersion, LIDEVersion: string;
  LHandle, LSize, LValueSize: DWORD;
  LInfo: PVSFixedFileInfo;
begin
  LIDEVersion := '';
  LFileVersion := '';
  LDelphiVersion := '';
  LSize := GetFileVersionInfoSize(PChar(AExecutable), LHandle);
  if (LSize > 0) and (LSize <= 16 * 1024 * 1024) then
  begin
    SetLength(LBytes, LSize);
    if GetFileVersionInfo(PChar(AExecutable), 0, LSize, @LBytes[0]) and
      VerQueryValue(@LBytes[0], '\', Pointer(LInfo), LValueSize) and (LValueSize >= SizeOf(TVSFixedFileInfo)) then
    begin
      LFileVersion := Format('%d.%d.%d.%d', [HiWord(LInfo.dwFileVersionMS), LoWord(LInfo.dwFileVersionMS),
        HiWord(LInfo.dwFileVersionLS), LoWord(LInfo.dwFileVersionLS)]);
      LIDEVersion := Format('%d.%d', [HiWord(LInfo.dwProductVersionMS), LoWord(LInfo.dwProductVersionMS)]);
      if LIDEVersion = '22.0' then
        LDelphiVersion := '11'
      else if LIDEVersion = '23.0' then
        LDelphiVersion := '12'
      else if LIDEVersion = '37.0' then
        LDelphiVersion := '13';
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ide_version', LIDEVersion);
  Result.AddPair('file_version', LFileVersion);
  Result.AddPair('delphi_version', LDelphiVersion);
  Result.AddPair('architecture', ExecutableArchitecture(AExecutable));
end;

class function TDAILauncherProcesses.ProcessJson(const AProcess: TDAIIDEProcess; const ARegisteredExecutable: string): TJSONObject;
begin
  Result := FileInfo(AProcess.Executable);
  Result.AddPair('process_id', TJSONNumber.Create(Int64(AProcess.ProcessId)));
  Result.AddPair('executable', AProcess.Executable);
  Result.AddPair('creation_time', AProcess.CreationTime);
  Result.RemovePair('architecture').Free;
  Result.AddPair('architecture', AProcess.Architecture);
  Result.AddPair('verified', TJSONBool.Create(AProcess.Verified));
  Result.AddPair('matches_registered_ide', TJSONBool.Create(SameExecutable(AProcess.Executable, ARegisteredExecutable)));
end;

end.
