unit h5u.DAI.Launcher;

interface

uses
  System.JSON,
  h5u.DAI.Launcher.Processes;

type
  TDAILauncher = class sealed
  private
    FURL: string;
    FExecutable: string;
    FProfile: string;
    FRegisteredVersion: string;
    FToken: string;
    FPort: Word;
    FStartedProcess: TDAIIDEProcess;
    function ProbeDAI(const AProcesses: TArray<TDAIIDEProcess>): TJSONObject;
    function StartIDE(const ATimeoutMs: Cardinal): TJSONObject;
    function StopIDE(const AArguments: TJSONObject; const ATimeoutMs: Cardinal): TJSONObject;
  public
    constructor CreateFromCommandLine;
    function Status: TJSONObject;
    function Call(const AName: string; const AArguments: TJSONObject): TJSONObject;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Hash,
  System.IOUtils,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SysUtils,
  Winapi.Messages,
  Winapi.Windows,
  h5u.DAI.Consts,
  h5u.DAI.Lifecycle.Policy,
  h5u.DAI.WinAPI.TCP;

procedure RequireLifecycleAllowed;
var
  LReason: string;
begin
  if TDAILifecyclePolicy.ReadAllowed(LReason) then
    Exit;
  if LReason = 'disabled_in_dai_options' then
    raise EInvalidOperation.Create('Das Starten und Beenden der Delphi-IDE durch die KI ist in den DAI-Optionen gesperrt.');
  raise EInvalidOperation.Create('Die DAI-Einstellung zum Starten und Beenden der Delphi-IDE ist nicht lesbar. Der Zugriff ist gesperrt.');
end;

function QuoteArgument(const AValue: string): string;
var
  LBackslashes: Integer;
  LCharacter: Char;
begin
  Result := '"';
  LBackslashes := 0;
  for LCharacter in AValue do
    if LCharacter = '\' then
      Inc(LBackslashes)
    else
    begin
      if LCharacter = '"' then
        Result := Result + StringOfChar('\', LBackslashes * 2 + 1) + '"'
      else
        Result := Result + StringOfChar('\', LBackslashes) + LCharacter;
      LBackslashes := 0;
    end;
  Result := Result + StringOfChar('\', LBackslashes * 2) + '"';
end;

function OperationLock(const AExecutable: string): THandle;
var
  LName: string;
  LWait: DWORD;
begin
  LName := 'Local\DAI.Launcher.' + THashSHA2.GetHashString(UpperCase(TPath.GetFullPath(AExecutable)));
  Result := CreateMutex(nil, False, PChar(LName));
  if Result = 0 then
    RaiseLastOSError;
  LWait := WaitForSingleObject(Result, 0);
  if (LWait <> WAIT_OBJECT_0) and (LWait <> WAIT_ABANDONED) then
  begin
    CloseHandle(Result);
    raise EInvalidOperation.Create('Für diese IDE läuft bereits ein Start- oder Beendigungsvorgang. Status erneut abfragen.');
  end;
end;

procedure ReleaseOperationLock(const AHandle: THandle);
begin
  ReleaseMutex(AHandle);
  CloseHandle(AHandle);
end;

function IntegerArgument(const AArguments: TJSONObject; const AName: string; const ADefault, AMaximum: Int64): Int64;
var
  LValue: TJSONValue;
begin
  LValue := AArguments.GetValue(AName);
  if not Assigned(LValue) then
    Exit(ADefault);
  if not (LValue is TJSONNumber) or not TryStrToInt64(LValue.Value, Result) or (Result < 0) or (Result > AMaximum) then
    raise EArgumentException.CreateFmt('%s muss eine ganze Zahl zwischen 0 und %d sein.', [AName, AMaximum]);
end;

function StringArgument(const AArguments: TJSONObject; const AName, ADefault: string): string;
var
  LValue: TJSONValue;
begin
  LValue := AArguments.GetValue(AName);
  if not Assigned(LValue) then
    Exit(ADefault);
  if not (LValue is TJSONString) then
    raise EArgumentException.CreateFmt('%s muss ein String sein.', [AName]);
  Result := LValue.Value;
end;

constructor TDAILauncher.CreateFromCommandLine;
var
  LIndex, LPort: Integer;
  LKey, LValue, LPortText: string;
  LSeen: TJSONObject;
begin
  inherited Create;
  LSeen := TJSONObject.Create;
  try
    if ParamStr(1) <> '--launcher' then
      raise EArgumentException.Create('Der Starthelfer benötigt --launcher.');
    LIndex := 2;
    while LIndex <= ParamCount do
    begin
      LKey := ParamStr(LIndex);
      if (LIndex = ParamCount) or Assigned(LSeen.GetValue(LKey)) then
        raise EArgumentException.Create('Fehlender oder doppelter Starthelfer-Parameter.');
      LValue := ParamStr(LIndex + 1);
      LSeen.AddPair(LKey, LValue);
      if LKey = '--url' then
        FURL := LValue
      else if LKey = '--ide' then
        FExecutable := LValue
      else if LKey = '--dai-version' then
        FRegisteredVersion := LValue
      else if LKey = '--ide-profile' then
        FProfile := LValue
      else
        raise EArgumentException.Create('Unbekannter Starthelfer-Parameter.');
      Inc(LIndex, 2);
    end;
  finally
    LSeen.Free;
  end;
  if not FURL.StartsWith('http://127.0.0.1:') or not FURL.EndsWith('/mcp') then
    raise EArgumentException.Create('Der Starthelfer unterstützt ausschließlich den lokalen DAI-Endpunkt.');
  LPortText := Copy(FURL, Length('http://127.0.0.1:') + 1, Length(FURL) - Length('http://127.0.0.1:') - Length('/mcp'));
  if not TryStrToInt(LPortText, LPort) or (LPort < 1024) or (LPort > 65535) then
    raise EArgumentException.Create('Ungültiger DAI-Port.');
  FPort := LPort;
  if not TPath.IsPathRooted(FExecutable) or not SameText(TPath.GetFileName(FExecutable), 'bds.exe') then
    raise EArgumentException.Create('--ide muss der vollständige Pfad einer bds.exe sein.');
  FExecutable := TPath.GetFullPath(FExecutable);
  if Trim(FRegisteredVersion) = '' then
    raise EArgumentException.Create('--dai-version fehlt. Bitte den Client erneut über DAI registrieren.');
  FToken := GetEnvironmentVariable('DAI_MCP_TOKEN');
  for LValue in [FProfile, FRegisteredVersion, FToken] do
    if (Pos(#0, LValue) > 0) or (Pos(#13, LValue) > 0) or (Pos(#10, LValue) > 0) then
      raise EArgumentException.Create('Die Starthelfer-Konfiguration enthält Steuerzeichen.');
end;

function ResponseDAIVersion(const AResponse: IHTTPResponse): string;
var
  LRoot, LValue: TJSONValue;
  LResult, LMeta, LInfo: TJSONObject;
begin
  Result := '';
  if AResponse.StatusCode <> 200 then
    Exit;
  LRoot := TJSONObject.ParseJSONValue(AResponse.ContentAsString(TEncoding.UTF8));
  try
    if not (LRoot is TJSONObject) then
      Exit;
    LResult := TJSONObject(LRoot).GetValue<TJSONObject>('result', nil);
    if not Assigned(LResult) then
      Exit;
    LInfo := nil;
    LMeta := LResult.GetValue<TJSONObject>('_meta', nil);
    if Assigned(LMeta) then
    begin
      LValue := LMeta.GetValue('io.modelcontextprotocol/serverInfo');
      if LValue is TJSONObject then
        LInfo := TJSONObject(LValue);
    end;
    if not Assigned(LInfo) then
      LInfo := LResult.GetValue<TJSONObject>('serverInfo', nil);
    if not Assigned(LInfo) then
      Exit;
    if LInfo.GetValue<string>('name', '') = 'DAI' then
      Result := LInfo.GetValue<string>('version', '');
  finally
    LRoot.Free;
  end;
end;

function LegacyProbe(AClient: THTTPClient; const AURL, AToken: string): string;
var
  LHeaders: TNetHeaders;
  LResponse: IHTTPResponse;
  LSession, LProtocolVersion: string;
  LRoot: TJSONValue;
  LResult: TJSONObject;
  LStream: TStringStream;
begin
  SetLength(LHeaders, 4);
  LHeaders[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AToken);
  LHeaders[1] := TNameValuePair.Create('Content-Type', 'application/json');
  LHeaders[2] := TNameValuePair.Create('Accept', 'application/json');
  LHeaders[3] := TNameValuePair.Create('Mcp-Method', 'initialize');
  LStream := TStringStream.Create('{"jsonrpc":"2.0","id":"dai-launcher-status","method":"initialize","params":{' +
    '"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"dai_start","version":"' + CDAIVersion + '"}}}', TEncoding.UTF8);
  try
    LResponse := AClient.Post(AURL, LStream, nil, LHeaders);
    LSession := LResponse.HeaderValue['Mcp-Session-Id'];
    LProtocolVersion := '2025-11-25';
    try
      Result := ResponseDAIVersion(LResponse);
      LRoot := TJSONObject.ParseJSONValue(LResponse.ContentAsString(TEncoding.UTF8));
      try
        if LRoot is TJSONObject then
        begin
          LResult := TJSONObject(LRoot).GetValue<TJSONObject>('result', nil);
          if Assigned(LResult) then
            LProtocolVersion := LResult.GetValue<string>('protocolVersion', LProtocolVersion);
        end;
      finally
        LRoot.Free;
      end;
    finally
      if LSession <> '' then
        try
          SetLength(LHeaders, 3);
          LHeaders[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AToken);
          LHeaders[1] := TNameValuePair.Create('Mcp-Session-Id', LSession);
          LHeaders[2] := TNameValuePair.Create('MCP-Protocol-Version', LProtocolVersion);
          AClient.Delete(AURL, nil, LHeaders);
        except
          // Older servers may not offer session DELETE; no IDE tools are invoked.
        end;
    end;
  finally
    LStream.Free;
  end;
end;

function TDAILauncher.ProbeDAI(const AProcesses: TArray<TDAIIDEProcess>): TJSONObject;
var
  LAuthenticated, LHTTPReachable, LMatches, LOwnerVerified: Boolean;
  LClient: THTTPClient;
  LHeaders: TNetHeaders;
  LOwner, LOwnerAfter: TDAITCPListenerOwner;
  LProcess, LOwnerProcess: TDAIIDEProcess;
  LOwnerHandle: THandle;
  LResponse: IHTTPResponse;
  LState, LVersion: string;
  LStream: TStringStream;
begin
  LState := 'unreachable';
  LHTTPReachable := False;
  LAuthenticated := False;
  LOwnerVerified := False;
  LMatches := False;
  LVersion := '';
  LOwner := Default(TDAITCPListenerOwner);
  LOwnerProcess := Default(TDAIIDEProcess);
  if TDAITCPListener.TryFindIPv4Owner(FPort, LOwner) then
  begin
    LState := 'unverified';
    for LProcess in AProcesses do
      if LProcess.Verified and (LProcess.ProcessId = LOwner.ProcessId) then
      begin
        LOwnerVerified := True;
        LOwnerProcess := LProcess;
        LMatches := TDAILauncherProcesses.SameExecutable(LProcess.Executable, FExecutable);
        Break;
      end;
    LOwnerHandle := 0;
    if LOwnerVerified then
      try
        LOwnerHandle := TDAILauncherProcesses.OpenVerified(LOwnerProcess, False);
      except
        LOwnerVerified := False;
      end;
    // Do not disclose the token to an unrelated or unverified listener occupying the configured port.
    try
      if LOwnerVerified and (FToken <> '') then
      begin
        LClient := THTTPClient.Create;
        try
          LClient.ConnectionTimeout := 500;
          LClient.ResponseTimeout := 1000;
          LClient.HandleRedirects := False;
          LClient.ProxySettings := TProxySettings.Create('', 0);
          SetLength(LHeaders, 5);
          LHeaders[0] := TNameValuePair.Create('Authorization', 'Bearer ' + FToken);
          LHeaders[1] := TNameValuePair.Create('Content-Type', 'application/json');
          LHeaders[2] := TNameValuePair.Create('Accept', 'application/json');
          LHeaders[3] := TNameValuePair.Create('MCP-Protocol-Version', '2026-07-28');
          LHeaders[4] := TNameValuePair.Create('Mcp-Method', 'server/discover');
          LStream := TStringStream.Create('{"jsonrpc":"2.0","id":"dai-launcher-status","method":"server/discover","params":{"_meta":{' +
            '"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}', TEncoding.UTF8);
          try
            try
              LResponse := LClient.Post(FURL, LStream, nil, LHeaders);
              LHTTPReachable := True;
              if LResponse.StatusCode = 401 then
                LState := 'unauthorized'
              else if (LResponse.StatusCode = 200) or (LResponse.StatusCode = 400) or (LResponse.StatusCode = 404) then
              begin
                LVersion := ResponseDAIVersion(LResponse);
                if (LVersion = '') and (WaitForSingleObject(LOwnerHandle, 0) = WAIT_TIMEOUT) and
                  TDAITCPListener.TryFindIPv4Owner(FPort, LOwnerAfter) and (LOwnerAfter.ProcessId = LOwner.ProcessId) then
                  LVersion := LegacyProbe(LClient, FURL, FToken);
                if (LVersion <> '') and (WaitForSingleObject(LOwnerHandle, 0) = WAIT_TIMEOUT) and
                  TDAITCPListener.TryFindIPv4Owner(FPort, LOwnerAfter) and (LOwnerAfter.ProcessId = LOwner.ProcessId) then
                begin
                  LAuthenticated := True;
                  LState := 'active';
                end
                else
                  LVersion := '';
              end;
            except
              // Never echo HTTP exception text: URLs/headers may contain credentials.
              LState := 'unverified';
            end;
          finally
            LStream.Free;
          end;
        finally
          LClient.Free;
        end;
      end;
    finally
      if LOwnerHandle <> 0 then
        CloseHandle(LOwnerHandle);
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('state', LState);
  Result.AddPair('http_reachable', TJSONBool.Create(LHTTPReachable));
  Result.AddPair('authenticated', TJSONBool.Create(LAuthenticated));
  Result.AddPair('version', LVersion);
  Result.AddPair('process_id', TJSONNumber.Create(Int64(LOwner.ProcessId)));
  Result.AddPair('matches_registered_ide', TJSONBool.Create(LMatches and LAuthenticated));
  Result.AddPair('endpoint', FURL);
end;

function TDAILauncher.Status: TJSONObject;
var
  LArray: TJSONArray;
  LIDE, LPolicy: TJSONObject;
  LIDEIsRunning, LComplete, LProfileVerified: Boolean;
  LAllowed: Boolean;
  LReason: string;
  LProcess: TDAIIDEProcess;
  LProcesses: TArray<TDAIIDEProcess>;
begin
  LProcesses := TDAILauncherProcesses.List;
  Result := TJSONObject.Create;
  try
    LAllowed := TDAILifecyclePolicy.ReadAllowed(LReason);
    LPolicy := TJSONObject.Create;
    Result.AddPair('lifecycle_control', LPolicy);
    LPolicy.AddPair('allowed', TJSONBool.Create(LAllowed));
    LPolicy.AddPair('reason', LReason);
    LPolicy.AddPair('scope', 'windows_user');
    LArray := TJSONArray.Create;
    Result.AddPair('running_ides', LArray);
    LIDEIsRunning := False;
    LComplete := True;
    LProfileVerified := False;
    for LProcess in LProcesses do
    begin
      LArray.AddElement(TDAILauncherProcesses.ProcessJson(LProcess, FExecutable));
      if not LProcess.Verified then
        LComplete := False;
      if TDAILauncherProcesses.SameExecutable(LProcess.Executable, FExecutable) then
        LIDEIsRunning := True;
      if (LProcess.ProcessId = FStartedProcess.ProcessId) and (LProcess.CreationTime = FStartedProcess.CreationTime) then
        LProfileVerified := True;
    end;
    LIDE := TDAILauncherProcesses.FileInfo(FExecutable);
    Result.AddPair('registered_ide', LIDE);
    LIDE.AddPair('executable', FExecutable);
    LIDE.AddPair('exists', TJSONBool.Create(TFile.Exists(FExecutable)));
    LIDE.AddPair('profile', FProfile);
    LIDE.AddPair('running_profile_verified', TJSONBool.Create(LProfileVerified));
    Result.AddPair('helper_version', CDAIVersion);
    Result.AddPair('registered_dai_version', FRegisteredVersion);
    Result.AddPair('registered_ide_running', TJSONBool.Create(LIDEIsRunning));
    Result.AddPair('ide_running', TJSONBool.Create(Length(LProcesses) > 0));
    Result.AddPair('enumeration_complete', TJSONBool.Create(LComplete));
    Result.AddPair('dai', ProbeDAI(LProcesses));
  except
    Result.Free;
    raise;
  end;
end;

function TDAILauncher.StartIDE(const ATimeoutMs: Cardinal): TJSONObject;
var
  LCreated, LReady, LExited: Boolean;
  LCommandLine, LOutcome: string;
  LHandle, LLock: THandle;
  LInfo: TProcessInformation;
  LProcess, LExisting: TDAIIDEProcess;
  LCount: Integer;
  LStartup: TStartupInfo;
  LStatus, LDAI: TJSONObject;
  LStopwatch: TStopwatch;
begin
  RequireLifecycleAllowed;
  LLock := OperationLock(FExecutable);
  try
    LCount := 0;
    LProcess := Default(TDAIIDEProcess);
    for LExisting in TDAILauncherProcesses.List do
    begin
      if not LExisting.Verified then
        raise EInvalidOperation.Create('Eine laufende IDE kann nicht verifiziert werden. Kein zusätzlicher Prozess wird gestartet.');
      if TDAILauncherProcesses.SameExecutable(LExisting.Executable, FExecutable) then
      begin
        Inc(LCount);
        LProcess := LExisting;
      end;
    end;
    if (LCount > 0) and (FProfile <> '') and
      ((FStartedProcess.ProcessId <> LProcess.ProcessId) or (FStartedProcess.CreationTime <> LProcess.CreationTime)) then
      raise EInvalidOperation.Create('Das Profil einer bereits laufenden IDE ist nicht verifiziert. Instanz über delphi_status gezielt prüfen.');
    if LCount > 1 then
      raise EInvalidOperation.Create('Mehrere Instanzen der registrierten IDE laufen. Über delphi_status eine konkrete Instanz auswählen.');
    LCreated := LCount = 0;
    if LCreated then
    begin
      if not TFile.Exists(FExecutable) then
        raise EInvalidOperation.Create('Die registrierte bds.exe wurde nicht gefunden.');
      LStartup := Default(TStartupInfo);
      LStartup.cb := SizeOf(LStartup);
      LInfo := Default(TProcessInformation);
      LCommandLine := QuoteArgument(FExecutable);
      if FProfile <> '' then
        LCommandLine := LCommandLine + ' -r' + QuoteArgument(FProfile);
      RequireLifecycleAllowed;
      if not CreateProcess(PChar(FExecutable), PChar(LCommandLine), nil, nil, False, CREATE_NEW_PROCESS_GROUP,
        nil, PChar(TPath.GetDirectoryName(FExecutable)), LStartup, LInfo) then
        RaiseLastOSError;
      CloseHandle(LInfo.hThread);
      LHandle := LInfo.hProcess;
      if not TDAILauncherProcesses.Inspect(LHandle, LInfo.dwProcessId, LProcess) then
      begin
        CloseHandle(LHandle);
        raise EInvalidOperation.Create('Der gestartete IDE-Prozess konnte nicht verifiziert werden. Status erneut abfragen.');
      end;
      FStartedProcess := LProcess;
    end
    else
      LHandle := TDAILauncherProcesses.OpenVerified(LProcess, False);
    try
      LStopwatch := TStopwatch.StartNew;
      repeat
        LStatus := Status;
        try
          LDAI := LStatus.GetValue<TJSONObject>('dai');
          LReady := LDAI.GetValue<Boolean>('authenticated', False) and
            (LDAI.GetValue<Int64>('process_id', 0) = LProcess.ProcessId);
        finally
          LStatus.Free;
        end;
        LExited := WaitForSingleObject(LHandle, 0) = WAIT_OBJECT_0;
        if LReady or LExited or (LStopwatch.ElapsedMilliseconds >= ATimeoutMs) then
          Break;
        WaitForSingleObject(LHandle, 200);
      until False;
      LOutcome := 'ide_running';
      if LExited then
        LOutcome := 'exited'
      else if LReady then
        LOutcome := 'ready';
      Result := TJSONObject.Create;
      try
        Result.AddPair('outcome', LOutcome);
        Result.AddPair('started', TJSONBool.Create(LCreated));
        Result.AddPair('process_id', TJSONNumber.Create(Int64(LProcess.ProcessId)));
        Result.AddPair('creation_time', LProcess.CreationTime);
        Result.AddPair('dai_ready', TJSONBool.Create(LReady and not LExited));
        Result.AddPair('status', Status);
      except
        Result.Free;
        raise;
      end;
    finally
      // The IDE deliberately survives EOF/client disconnect and readiness timeouts.
      CloseHandle(LHandle);
    end;
  finally
    ReleaseOperationLock(LLock);
  end;
end;

function TDAILauncher.StopIDE(const AArguments: TJSONObject; const ATimeoutMs: Cardinal): TJSONObject;
var
  LCloseRequested, LExited, LTerminate: Boolean;
  LCount: Integer;
  LCreationTime, LMode, LOutcome: string;
  LCharacter: Char;
  LCreationValue: UInt64;
  LHandle, LLock: THandle;
  LRequestedId, LWindowProcessId: Cardinal;
  LProcess, LExisting: TDAIIDEProcess;
  LWindow: HWND;
begin
  LMode := StringArgument(AArguments, 'mode', 'close');
  if (LMode <> 'close') and (LMode <> 'terminate') then
    raise EArgumentException.Create('mode muss close oder terminate sein.');
  LTerminate := LMode = 'terminate';
  LRequestedId := IntegerArgument(AArguments, 'process_id', 0, High(Cardinal));
  if (LRequestedId = 0) and (FProfile <> '') then
    raise EArgumentException.Create('Bei einem besonderen IDE-Profil process_id und creation_time aus delphi_status angeben.');
  LCreationTime := StringArgument(AArguments, 'creation_time', '');
  if LCreationTime <> '' then
  begin
    for LCharacter in LCreationTime do
      if not CharInSet(LCharacter, ['0'..'9']) then
        raise EArgumentException.Create('creation_time muss die dezimale Prozessstartzeit aus delphi_status sein.');
    if not TryStrToUInt64(LCreationTime, LCreationValue) then
      raise EArgumentException.Create('creation_time überschreitet den FILETIME-Wertebereich.');
  end;
  if Assigned(AArguments.GetValue('process_id')) and ((LRequestedId = 0) or (LCreationTime = '')) then
    raise EArgumentException.Create('Ein explizites process_id benötigt creation_time aus delphi_status.');
  if (LRequestedId = 0) and (LCreationTime <> '') then
    raise EArgumentException.Create('creation_time benötigt eine explizite process_id.');
  RequireLifecycleAllowed;
  LProcess := Default(TDAIIDEProcess);
  LCount := 0;
  for LExisting in TDAILauncherProcesses.List do
  begin
    if (LRequestedId = 0) and not LExisting.Verified then
      raise EInvalidOperation.Create('Eine laufende IDE kann nicht verifiziert werden. Prozessende kann nicht bestätigt werden.');
    if ((LRequestedId <> 0) and (LExisting.ProcessId = LRequestedId)) or
      ((LRequestedId = 0) and TDAILauncherProcesses.SameExecutable(LExisting.Executable, FExecutable)) then
    begin
      Inc(LCount);
      LProcess := LExisting;
    end;
  end;
  if LCount > 1 then
    raise EInvalidOperation.Create('Mehrere IDE-Instanzen passen. process_id und creation_time aus delphi_status angeben.');
  if (LCount = 1) and (LRequestedId <> 0) and (LProcess.CreationTime <> LCreationTime) then
    raise EInvalidOperation.Create('Die Prozessstartzeit passt nicht mehr. delphi_status erneut abfragen.');
  LExited := LCount = 0;
  LCloseRequested := False;
  LOutcome := 'not_running';
  if LCount = 1 then
  begin
    LLock := OperationLock(LProcess.Executable);
    try
      LHandle := TDAILauncherProcesses.OpenVerified(LProcess, LTerminate);
      try
        if LTerminate then
        begin
          RequireLifecycleAllowed;
          if not TerminateProcess(LHandle, 1) then
            RaiseLastOSError;
          LOutcome := 'still_running';
        end
        else
        begin
          LWindow := TDAILauncherProcesses.MainWindow(LProcess.ProcessId);
          if LWindow = 0 then
            LOutcome := 'no_main_window'
          else
          begin
            GetWindowThreadProcessId(LWindow, LWindowProcessId);
            if (LWindowProcessId <> LProcess.ProcessId) or (WaitForSingleObject(LHandle, 0) <> WAIT_TIMEOUT) then
              raise EInvalidOperation.Create('Das IDE-Hauptfenster gehört nicht mehr zur ausgewählten Instanz.');
            RequireLifecycleAllowed;
            if not PostMessage(LWindow, WM_CLOSE, 0, 0) then
              RaiseLastOSError;
            LCloseRequested := True;
            LOutcome := 'still_running';
          end;
        end;
        if LTerminate or LCloseRequested then
        begin
          case WaitForSingleObject(LHandle, ATimeoutMs) of
            WAIT_OBJECT_0: LExited := True;
            WAIT_TIMEOUT: LExited := False;
          else
            RaiseLastOSError;
          end;
          if LExited then
            LOutcome := 'exited';
        end;
      finally
        CloseHandle(LHandle);
      end;
    finally
      ReleaseOperationLock(LLock);
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('outcome', LOutcome);
  Result.AddPair('exited', TJSONBool.Create(LExited));
  Result.AddPair('process_id', TJSONNumber.Create(Int64(LProcess.ProcessId)));
  Result.AddPair('creation_time', LProcess.CreationTime);
  Result.AddPair('mode', LMode);
  Result.AddPair('close_requested', TJSONBool.Create(LCloseRequested));
  Result.AddPair('termination_requested', TJSONBool.Create(LTerminate and (LCount = 1)));
  Result.AddPair('terminated', TJSONBool.Create(LTerminate and (LCount = 1) and LExited));
end;

function TDAILauncher.Call(const AName: string; const AArguments: TJSONObject): TJSONObject;
var
  LPair: TJSONPair;
  LTimeout: Cardinal;
begin
  for LPair in AArguments do
    if not (((AName = 'delphi_start') and (LPair.JsonString.Value = 'timeout_ms')) or
      ((AName = 'delphi_stop') and ((LPair.JsonString.Value = 'timeout_ms') or (LPair.JsonString.Value = 'process_id') or
      (LPair.JsonString.Value = 'creation_time') or (LPair.JsonString.Value = 'mode')))) then
      raise EArgumentException.Create('Unbekanntes Werkzeugargument: ' + LPair.JsonString.Value);
  if AName = 'delphi_status' then
    Exit(Status);
  if AName = 'delphi_start' then
  begin
    LTimeout := IntegerArgument(AArguments, 'timeout_ms', 20000, 30000);
    Exit(StartIDE(LTimeout));
  end;
  if AName = 'delphi_stop' then
  begin
    LTimeout := IntegerArgument(AArguments, 'timeout_ms', 5000, 30000);
    Exit(StopIDE(AArguments, LTimeout));
  end;
  raise EArgumentException.Create('Unbekanntes Starthelfer-Werkzeug: ' + AName);
end;

end.
