unit h5u.DAI.Process;

interface

uses
  h5u.DAI.Types;

type
  TDAIProcess = class sealed
  public
    class function Execute( const AExecutable: string;
      const AArguments: TArray<string>;
      const AWorkingDirectory: string;
      const ATimeoutMs: Cardinal
    ): TDAIProcessResult; static;
    class function StartDetached( const AExecutable: string;
      const AArguments: TArray<string>;
      const AWorkingDirectory: string;
      out AProcessHandle: THandle;
      out AProcessId: Cardinal
    ): Boolean; static;
    class function ResolveMSBuildExecutable(const ARequestedFileName: string): string; static;
    class function ResolveDCC32Executable: string; static;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Helpers;

function QuoteWindowsArgument(const AValue: string): string;
var
  LBackslashes: Integer;
  LCharacter: Char;
begin
  if (AValue <> '') and not AValue.Contains(' ') and not AValue.Contains(#9) and not AValue.Contains('"') then
    Exit(AValue);

  Result := '"';
  LBackslashes := 0;
  for LCharacter in AValue do
  begin
    if LCharacter = '\' then
    begin
      Inc(LBackslashes);
      Continue;
    end;

    if LCharacter = '"' then
    begin
      Result := Result + StringOfChar('\', LBackslashes * 2 + 1) + '"';
      LBackslashes := 0;
      Continue;
    end;

    if LBackslashes > 0 then
    begin
      Result := Result + StringOfChar('\', LBackslashes);
      LBackslashes := 0;
    end;
    Result := Result + LCharacter;
  end;

  if LBackslashes > 0 then
    Result := Result + StringOfChar('\', LBackslashes * 2);
  Result := Result + '"';
end;

function BuildCommandLine(const AExecutable: string; const AArguments: TArray<string>): string;
var
  LArgument: string;
begin
  Result := QuoteWindowsArgument(AExecutable);
  for LArgument in AArguments do
    Result := Result + ' ' + QuoteWindowsArgument(LArgument);
end;

function IDEDirectory: string;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices) then
    Result := ExcludeTrailingPathDelimiter((BorlandIDEServices as IOTAServices).GetRootDirectory);
end;

function IsUnderKnownCompilerRoot(const AFileName: string): Boolean;
var
  LRoot: string;
begin
  Result := False;
  for LRoot in [
    IDEDirectory,
    GetEnvironmentVariable('WINDIR'),
    GetEnvironmentVariable('ProgramFiles'),
    GetEnvironmentVariable('ProgramFiles(x86)')
  ] do
    if (Trim(LRoot) <> '') and TDAIOTA.IsPathWithin(AFileName, LRoot) then
      Exit(True);
end;

function ReadCapturedOutput(const AFileName: string): string;
var
  LBytes: TBytes;
  LLength: Integer;
begin
  Result := '';
  if not TFile.Exists(AFileName) then
    Exit;

  LBytes := TFile.ReadAllBytes(AFileName);
  LLength := Length(LBytes);
  if LLength > CDAIMaxProcessOutputBytes then
    LLength := CDAIMaxProcessOutputBytes;
  if LLength > 0 then
    Result := TEncoding.Default.GetString(LBytes, 0, LLength);
  if Length(LBytes) > LLength then
    Result := Result + sLineBreak + '[DAI: Ausgabe wurde gekürzt.]';
end;

class function TDAIProcess.Execute( const AExecutable: string;
  const AArguments: TArray<string>;
  const AWorkingDirectory: string;
  const ATimeoutMs: Cardinal
): TDAIProcessResult;
var
  LCommandLine: string;
  LExitCode: Cardinal;
  LOutputFileName: string;
  LOutputHandle: THandle;
  LProcessInformation: TProcessInformation;
  LSecurityAttributes: TSecurityAttributes;
  LStartupInfo: TStartupInfo;
  LStopwatch: TStopwatch;
  LTimeout: Cardinal;
  LWaitResult: Cardinal;
  LWorkingDirectory: string;
begin
  Result := Default(TDAIProcessResult);
  if not TFile.Exists(AExecutable) then
  begin
    Result.ErrorText := 'Programm nicht gefunden: ' + AExecutable;
    Exit;
  end;

  LWorkingDirectory := AWorkingDirectory;
  if Trim(LWorkingDirectory) = '' then
    LWorkingDirectory := TPath.GetDirectoryName(AExecutable);
  LWorkingDirectory := TPath.GetFullPath(LWorkingDirectory);
  if not TDirectory.Exists(LWorkingDirectory) then
  begin
    Result.ErrorText := 'Arbeitsverzeichnis nicht gefunden: ' + LWorkingDirectory;
    Exit;
  end;

  LTimeout := ATimeoutMs;
  if LTimeout = 0 then
    LTimeout := CDAIDefaultProcessTimeoutMs;

  LOutputFileName := TPath.Combine(TPath.GetTempPath, Format('dai-process-%d-%d.log', [GetCurrentProcessId, GetTickCount]));
  FillChar(LSecurityAttributes, SizeOf(LSecurityAttributes), 0);
  LSecurityAttributes.nLength := SizeOf(LSecurityAttributes);
  LSecurityAttributes.bInheritHandle := True;

  LOutputHandle := CreateFile(
    PChar(LOutputFileName),
    GENERIC_WRITE,
    FILE_SHARE_READ,
    @LSecurityAttributes,
    CREATE_ALWAYS,
    FILE_ATTRIBUTE_TEMPORARY,
    0
  );
  if LOutputHandle = INVALID_HANDLE_VALUE then
  begin
    Result.ErrorText := SysErrorMessage(GetLastError);
    Exit;
  end;

  try
    FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
    LStartupInfo.cb := SizeOf(LStartupInfo);
    LStartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    LStartupInfo.wShowWindow := SW_HIDE;
    LStartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    LStartupInfo.hStdOutput := LOutputHandle;
    LStartupInfo.hStdError := LOutputHandle;

    FillChar(LProcessInformation, SizeOf(LProcessInformation), 0);
    LCommandLine := BuildCommandLine(AExecutable, AArguments);
    LStopwatch := TStopwatch.StartNew;

    if not CreateProcess(
      PChar(AExecutable),
      PChar(LCommandLine),
      nil,
      nil,
      True,
      CREATE_NO_WINDOW,
      nil,
      PChar(LWorkingDirectory),
      LStartupInfo,
      LProcessInformation
    ) then
    begin
      Result.ErrorText := SysErrorMessage(GetLastError);
      Exit;
    end;

    Result.Started := True;
    try
      LWaitResult := WaitForSingleObject(LProcessInformation.hProcess, LTimeout);
      if LWaitResult = WAIT_TIMEOUT then
      begin
        Result.TimedOut := True;
        TerminateProcess(LProcessInformation.hProcess, 3);
        WaitForSingleObject(LProcessInformation.hProcess, 5000);
      end
      else if LWaitResult <> WAIT_OBJECT_0 then
        Result.ErrorText := SysErrorMessage(GetLastError);

      LExitCode := Cardinal(-1);
      GetExitCodeProcess(LProcessInformation.hProcess, LExitCode);
      Result.ExitCode := LExitCode;
    finally
      CloseHandle(LProcessInformation.hThread);
      CloseHandle(LProcessInformation.hProcess);
    end;

    LStopwatch.Stop;
    Result.DurationMs := LStopwatch.ElapsedMilliseconds;
  finally
    CloseHandle(LOutputHandle);
    Result.Output := ReadCapturedOutput(LOutputFileName);
    DeleteFile(PChar(LOutputFileName));
  end;
end;

class function TDAIProcess.ResolveDCC32Executable: string;
begin
  Result := TPath.Combine(IDEDirectory, 'bin\dcc32.exe');
  if not TFile.Exists(Result) then
    raise EFileNotFoundException.CreateFmt('DCC32.exe wurde nicht unterhalb von %%BDS%% gefunden: %s', [Result]);
end;

class function TDAIProcess.ResolveMSBuildExecutable(const ARequestedFileName: string): string;
var
  LCandidates: TArray<string>;
  LCandidate: string;
  LPathDirectory: string;
begin
  if Trim(ARequestedFileName) <> '' then
  begin
    Result := TPath.GetFullPath(ARequestedFileName);
    if not SameText(TPath.GetFileName(Result), 'MSBuild.exe') then
      raise EArgumentException.Create('Als ausführbare Datei ist ausschließlich MSBuild.exe erlaubt.');
    if not TFile.Exists(Result) then
      raise EFileNotFoundException.CreateFmt('MSBuild.exe nicht gefunden: %s', [Result]);
    if not IsUnderKnownCompilerRoot(Result) then
      raise EInvalidOperation.Create('Die angegebene MSBuild.exe liegt außerhalb der bekannten Compilerverzeichnisse.');
    Exit;
  end;

  LCandidates := [
    TPath.Combine(IDEDirectory, 'bin\MSBuild.exe'),
    TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe'),
    TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe')
  ];

  for LCandidate in LCandidates do
    if TFile.Exists(LCandidate) then
      Exit(TPath.GetFullPath(LCandidate));

  for LPathDirectory in GetEnvironmentVariable('PATH').Split([';'], TStringSplitOptions.ExcludeEmpty) do
  begin
    LCandidate := TPath.Combine(Trim(LPathDirectory), 'MSBuild.exe');
    if TFile.Exists(LCandidate) and IsUnderKnownCompilerRoot(LCandidate) then
      Exit(TPath.GetFullPath(LCandidate));
  end;

  raise EFileNotFoundException.Create('MSBuild.exe konnte nicht ermittelt werden. Der Pfad kann dem MCP-Werkzeug explizit übergeben werden.');
end;

class function TDAIProcess.StartDetached( const AExecutable: string;
  const AArguments: TArray<string>;
  const AWorkingDirectory: string;
  out AProcessHandle: THandle;
  out AProcessId: Cardinal
): Boolean;
var
  LCommandLine: string;
  LProcessInformation: TProcessInformation;
  LStartupInfo: TStartupInfo;
  LWorkingDirectory: string;
begin
  Result := False;
  AProcessHandle := 0;
  AProcessId := 0;
  if not TFile.Exists(AExecutable) then
    Exit;

  LWorkingDirectory := AWorkingDirectory;
  if Trim(LWorkingDirectory) = '' then
    LWorkingDirectory := TPath.GetDirectoryName(AExecutable);

  FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
  LStartupInfo.cb := SizeOf(LStartupInfo);
  FillChar(LProcessInformation, SizeOf(LProcessInformation), 0);
  LCommandLine := BuildCommandLine(AExecutable, AArguments);

  Result := CreateProcess(
    PChar(AExecutable),
    PChar(LCommandLine),
    nil,
    nil,
    False,
    CREATE_NEW_PROCESS_GROUP,
    nil,
    PChar(LWorkingDirectory),
    LStartupInfo,
    LProcessInformation
  );
  if not Result then
    Exit;

  CloseHandle(LProcessInformation.hThread);
  AProcessHandle := LProcessInformation.hProcess;
  AProcessId := LProcessInformation.dwProcessId;
end;

end.
