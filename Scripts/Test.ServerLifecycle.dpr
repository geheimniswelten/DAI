program TestServerLifecycle;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  IdHTTP,
  IdHTTPServer,
  IdSocketHandle,
  IdStack,
  h5u.DAI.Consts,
  h5u.DAI.MCP.Server,
  h5u.DAI.MCP.Sessions,
  h5u.DAI.WinAPI.TCP;

const
  CCycles = 20;
  CFixtureToken = 'dai-isolated-lifecycle-token';

var
  CheckCount: Integer;
  HostPeerPackages: TArray<HMODULE>;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function HasArgument(const AArgument: string): Boolean;
var
  LIndex: Integer;
begin
  for LIndex := 1 to ParamCount do
    if SameText(ParamStr(LIndex), AArgument) then
      Exit(True);
  Result := False;
end;

procedure RunInheritedHandleChild;
var
  LReady, LQuit: THandle;
begin
  if ParamCount <> 3 then
    raise EArgumentException.Create('The inherited-handle child requires READY and QUIT event names.');
  LReady := OpenEvent(EVENT_MODIFY_STATE, False, PChar(ParamStr(2)));
  if LReady = 0 then
    RaiseLastOSError;
  try
    LQuit := OpenEvent(SYNCHRONIZE, False, PChar(ParamStr(3)));
    if LQuit = 0 then
      RaiseLastOSError;
    try
      // Deliberately retain every handle inherited by CreateProcess; do not create any socket here.
      if not SetEvent(LReady) then
        RaiseLastOSError;
      if WaitForSingleObject(LQuit, 30000) <> WAIT_OBJECT_0 then
        raise EInvalidOperation.Create('The inherited-handle fixture did not receive its bounded QUIT signal.');
    finally
      CloseHandle(LQuit);
    end;
  finally
    CloseHandle(LReady);
  end;
end;

function ModulePath(const AName: string): string;
var
  LModule: HMODULE;
  LLength: Cardinal;
begin
  Result := '';
  LModule := GetModuleHandle(PChar(AName));
  if LModule = 0 then
    Exit;
  SetLength(Result, 32768);
  LLength := GetModuleFileName(LModule, PChar(Result), Length(Result));
  SetLength(Result, LLength);
end;

function AddressModulePath(const AAddress: Pointer): string;
var
  LInfo: TMemoryBasicInformation;
  LLength: Cardinal;
begin
  Result := '';
  if VirtualQuery(AAddress, LInfo, SizeOf(LInfo)) = 0 then
    Exit;
  SetLength(Result, 32768);
  LLength := GetModuleFileName(HMODULE(LInfo.AllocationBase), PChar(Result), Length(Result));
  SetLength(Result, LLength);
end;

procedure PrintStackDetails;
var
  LModuleName, LPath: string;
begin
  Writeln('CLASS: TIdHTTPServer = ' + AddressModulePath(Pointer(TIdHTTPServer)));
  Writeln('CLASS: TIdSocketHandle = ' + AddressModulePath(Pointer(TIdSocketHandle)));
  if Assigned(GStack) then
    Writeln('STACK: ' + GStack.ClassName + ' = ' + AddressModulePath(Pointer(GStack.ClassType)));
  for LModuleName in ['IndyIPClient370.bpl', 'IndyIPCommon370.bpl', 'IndyIPServer370.bpl'] do
  begin
    LPath := ModulePath(LModuleName);
    if LPath = '' then
      LPath := '(not loaded)';
    Writeln('OPTIONAL PACKAGE: ' + LModuleName + ' = ' + LPath);
  end;
end;

procedure CheckLinkage;
var
  LModuleName, LPath: string;
begin
  for LModuleName in ['rtl370.bpl', 'IndySystem370.bpl', 'IndyCore370.bpl', 'IndyProtocols370.bpl'] do
  begin
    LPath := ModulePath(LModuleName);
    {$IFDEF DAI_LIFECYCLE_PACKAGES}
    Check(LPath <> '', 'Manufacturer runtime package loaded: ' + LModuleName);
    Writeln('PACKAGE: ' + LPath);
    {$ELSE}
    Check(LPath = '', 'Static executable does not load runtime package: ' + LModuleName);
    {$ENDIF}
  end;
end;

procedure LoadHostPeers;
const
  CNames: array[0..2] of string = ('IndyIPCommon370.bpl', 'IndyIPClient370.bpl', 'IndyIPServer370.bpl');
var
  LName, LPath, LDirectory: string;
  LHandle: HMODULE;
begin
  if not HasArgument('--host-peers') then
    Exit;
  {$IFNDEF DAI_LIFECYCLE_PACKAGES}
  raise EInvalidOperation.Create('Host peers are allowed only in the manufacturer package variant.');
  {$ENDIF}
  if ParamCount < 2 then
    raise EArgumentException.Create('The --host-peers switch requires a manufacturer BPL directory.');
  LDirectory := ParamStr(2);
  for LName in CNames do
  begin
    LPath := IncludeTrailingPathDelimiter(LDirectory) + LName;
    // Run the real Delphi package initialization, not merely Windows LoadLibrary.
    LHandle := LoadPackage(LPath);
    SetLength(HostPeerPackages, Length(HostPeerPackages) + 1);
    HostPeerPackages[High(HostPeerPackages)] := LHandle;
    Check(ModulePath(LName) <> '', 'Explicit host-peer package initialized: ' + LName);
    Writeln('HOST PEER: ' + ModulePath(LName));
  end;
end;

procedure UnloadHostPeers;
var
  LIndex: Integer;
begin
  for LIndex := High(HostPeerPackages) downto 0 do
    UnloadPackage(HostPeerPackages[LIndex]);
  HostPeerPackages := nil;
end;

function StartOnFreePort(const AServer: TDAIMCPServer): Integer;
var
  LPort: Integer;
begin
  // Fixture-only high ports; the real DAI port and registry/settings are not accessed.
  for LPort := 40000 + Integer(GetCurrentProcessId mod 10000) to 60000 do
    if AServer.Start(LPort, CFixtureToken) then
      Exit(LPort);
  raise EInvalidOperation.Create('No fixture port could be started: ' + AServer.LastError);
end;

procedure CheckNoListener(const APort: Integer; const AContext: string);
var
  LOwner: TDAITCPListenerOwner;
  LFound: Boolean;
begin
  LFound := TDAITCPListener.TryFindIPv4Owner(APort, LOwner);
  Check(not LFound, AContext + ': no actual TCP_LISTEN entry on fixture port; ' + TDAITCPListener.DescribeIPv4Owner(APort));
end;

procedure CheckOwnListener(const APort: Integer);
var
  LOwner: TDAITCPListenerOwner;
begin
  Check(TDAITCPListener.TryFindIPv4Owner(APort, LOwner), 'Started server exists in the actual TCP_LISTEN table');
  Check(LOwner.ProcessId = GetCurrentProcessId, 'Actual listener belongs to this isolated process');
end;

procedure Ping(const AHTTP: TIdHTTP; const APort: Integer);
var
  LResponse: TJSONValue;
begin
  AHTTP.Disconnect;
  // Keep the connection alive after reading: Stop must also retire a real HTTP worker.
  AHTTP.Request.Connection := 'keep-alive';
  LResponse := TJSONObject.ParseJSONValue(AHTTP.Get(Format('http://127.0.0.1:%d/health', [APort])));
  try
    Check(AHTTP.ResponseCode = 200, 'Real HTTP health request succeeds');
    Check(LResponse is TJSONObject, 'Health response is JSON');
    Check(TJSONObject(LResponse).GetValue<string>('name') = CDAIName, 'Health request reaches the actual DAI server');
    Check(TJSONObject(LResponse).GetValue<Boolean>('active'), 'Health reports actual active state');
  finally
    LResponse.Free;
  end;
end;

procedure IndependentBind(const APort: Integer);
var
  LBlocker: TIdHTTPServer;
  LBinding: TIdSocketHandle;
begin
  LBlocker := TIdHTTPServer.Create(nil);
  try
    LBinding := LBlocker.Bindings.Add;
    LBinding.IP := '127.0.0.1';
    LBinding.Port := APort;
    LBlocker.Active := True;
    Check(LBlocker.Active, 'Independent Indy server binds the just-stopped port immediately');
    CheckOwnListener(APort);
    LBlocker.Active := False;
    Check(not LBlocker.Active, 'Independent Indy listener stops successfully');
    CheckNoListener(APort, 'Independent bind released');
  finally
    LBlocker.Free;
  end;
end;

procedure RunInheritedListener;
var
  LGuid: TGUID;
  LName, LCommandLine, LBindError: string;
  LReady, LQuit: THandle;
  LStartup: TStartupInfo;
  LProcess: TProcessInformation;
  LServer: TDAIMCPServer;
  LHTTP: TIdHTTP;
  LIndependent: TIdHTTPServer;
  LBinding: TIdSocketHandle;
  LPort: Integer;
  LOwner: TDAITCPListenerOwner;
  LListenerRemained, LIndependentBound: Boolean;
  LChildExit: Cardinal;
begin
  CreateGUID(LGuid);
  LName := 'Local\DAI.InheritedListener.' + GUIDToString(LGuid);
  LReady := CreateEvent(nil, True, False, PChar(LName + '.Ready'));
  if LReady = 0 then
    RaiseLastOSError;
  LQuit := 0;
  LServer := nil;
  LHTTP := nil;
  LIndependent := nil;
  FillChar(LProcess, SizeOf(LProcess), 0);
  try
    LQuit := CreateEvent(nil, True, False, PChar(LName + '.Quit'));
    if LQuit = 0 then
      RaiseLastOSError;
    LServer := TDAIMCPServer.Create(CDAIMCPSessionIdleTimeoutMs, 3, nil, LName + '.Lease');
    LHTTP := TIdHTTP.Create(nil);
    LHTTP.ConnectTimeout := 3000;
    LHTTP.ReadTimeout := 3000;
    LPort := StartOnFreePort(LServer);
    Ping(LHTTP, LPort);
    FillChar(LStartup, SizeOf(LStartup), 0);
    LStartup.cb := SizeOf(LStartup);
    LCommandLine := '"' + ParamStr(0) + '" --inherited-handles-child "' + LName + '.Ready" "' + LName + '.Quit"';
    UniqueString(LCommandLine);
    Check(CreateProcess(nil, PChar(LCommandLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, LStartup, LProcess),
      'CreateProcess starts the isolated child with bInheritHandles=True');
    Check(WaitForSingleObject(LReady, 10000) = WAIT_OBJECT_0, 'The inherited-handle child reports READY');
    Check(WaitForSingleObject(LProcess.hProcess, 0) = WAIT_TIMEOUT, 'The handle-retaining child is still alive');
    Writeln(Format('INHERITANCE: parent PID %d, child PID %d, fixture port %d.',
      [GetCurrentProcessId, LProcess.dwProcessId, LPort]));
    Check(LServer.Stop, 'Stop succeeds while an inheriting child remains alive: ' + LServer.LastError);
    Check(not LServer.Active, 'Stopped parent reports inactive while the child remains alive');
    Check(LServer.Port = 0, 'Stopped parent exposes status port zero');
    LHTTP.Disconnect;
    LListenerRemained := TDAITCPListener.TryFindIPv4Owner(LPort, LOwner);
    Writeln('INHERITANCE AFTER STOP: ' + TDAITCPListener.DescribeIPv4Owner(LPort));
    if LListenerRemained then
      Writeln(Format('INHERITANCE OWNER: TCP table PID %d; parent PID %d; child PID %d.',
        [LOwner.ProcessId, GetCurrentProcessId, LProcess.dwProcessId]));
    LIndependentBound := False;
    LBindError := '';
    LIndependent := TIdHTTPServer.Create(nil);
    LBinding := LIndependent.Bindings.Add;
    LBinding.IP := '127.0.0.1';
    LBinding.Port := LPort;
    try
      LIndependent.Active := True;
      LIndependentBound := LIndependent.Active;
    except
      on E: Exception do
      begin
        LBindError := E.ClassName + ': ' + E.Message;
        Writeln('INHERITANCE FOREIGN BIND: ' + LBindError);
      end;
    end;
    if LIndependentBound then
      Writeln('INHERITANCE FOREIGN BIND: succeeds while the child is alive.');
    LIndependent.Active := False;
    FreeAndNil(LIndependent);
    Check(SetEvent(LQuit), 'The child receives a normal QUIT request');
    Check(WaitForSingleObject(LProcess.hProcess, 10000) = WAIT_OBJECT_0, 'The child exits normally within the deadline');
    Check(GetExitCodeProcess(LProcess.hProcess, LChildExit), 'The normal child exit code is available');
    Check(LChildExit = 0, 'The inherited-handle child exits successfully');
    CheckNoListener(LPort, 'After the inheriting child exits');
    IndependentBind(LPort);
    // Assert after normal child cleanup, so even the unfixed reproduction never leaves a lingering fixture socket.
    Check(not LListenerRemained, 'Stopping DAI releases TCP_LISTEN even while an inheriting child remains alive');
    Check(LIndependentBound, 'An independent server can bind before the inheriting child exits: ' + LBindError);
    Check(LServer.Start(LPort, CFixtureToken), 'DAI restarts after the inheritance fixture: ' + LServer.LastError);
    Check(LServer.Stop, 'The inheritance fixture finishes with a clean stopped server: ' + LServer.LastError);
    CheckNoListener(LPort, 'Inheritance fixture final Stop');
  finally
    if LQuit <> 0 then
      SetEvent(LQuit);
    if LProcess.hProcess <> 0 then
    begin
      // The child has its own 30-second deadline; never terminate another process or retain its inherited sockets.
      WaitForSingleObject(LProcess.hProcess, 35000);
      CloseHandle(LProcess.hProcess);
    end;
    if LProcess.hThread <> 0 then
      CloseHandle(LProcess.hThread);
    LIndependent.Free;
    LHTTP.Free;
    LServer.Free;
    if LQuit <> 0 then
      CloseHandle(LQuit);
    CloseHandle(LReady);
  end;
end;

procedure RunLifecycle;
var
  LGuid: TGUID;
  LHTTP: TIdHTTP;
  LInstanceName: string;
  LOther: TDAIMCPServer;
  LPort: Integer;
  LServer: TDAIMCPServer;
  LCycle: Integer;
begin
  CreateGUID(LGuid);
  LInstanceName := 'Local\DAI.ServerLifecycle.' + GUIDToString(LGuid);
  LServer := TDAIMCPServer.Create(CDAIMCPSessionIdleTimeoutMs, 3, nil, LInstanceName);
  LOther := nil;
  LHTTP := nil;
  try
    LOther := TDAIMCPServer.Create(CDAIMCPSessionIdleTimeoutMs, 3, nil, LInstanceName);
    LHTTP := TIdHTTP.Create(nil);
    PrintStackDetails;
    LHTTP.ConnectTimeout := 3000;
    LHTTP.ReadTimeout := 3000;
    LPort := StartOnFreePort(LServer);
    Writeln(Format('FIXTURE: PID %d, loopback port %d, cycles %d.', [GetCurrentProcessId, LPort, CCycles]));
    Check(LServer.Active, 'Initial fixture start is active');
    Check(LServer.Port = LPort, 'Initial active status exposes the actual fixture port');
    for LCycle := 1 to CCycles do
    begin
      CheckOwnListener(LPort);
      Ping(LHTTP, LPort);
      Check(not LOther.Start(LPort, CFixtureToken), 'Active owner retains its isolated instance lease');
      Check(not LOther.Active, 'Rejected second owner remains inactive');
      Check(LOther.Port = 0, 'Rejected second owner has no active status port');
      Check(LServer.Stop, 'Toolbar-equivalent Stop succeeds: ' + LServer.LastError);
      Check(not LServer.Active, 'Stopped main fixture server is inactive');
      Check(LServer.Port = 0, 'Stopped main fixture status port is zero');
      CheckNoListener(LPort, 'DAI Stop');
      LHTTP.Disconnect;
      IndependentBind(LPort);
      Check(LOther.Start(LPort, CFixtureToken), 'Stop releases the GUID lease to another actual DAI server: ' + LOther.LastError);
      Check(LOther.Port = LPort, 'New lease owner exposes the same active fixture port');
      Check(LOther.Stop, 'Second GUID lease owner stops successfully: ' + LOther.LastError);
      Check(LOther.Port = 0, 'Second stopped lease owner status port is zero');
      CheckNoListener(LPort, 'Second owner Stop');
      Check(LServer.Start(LPort, CFixtureToken), 'Original server restarts on the same port immediately: ' + LServer.LastError);
      Check(LServer.Port = LPort, 'Immediate restart exposes the original port');
    end;
    Ping(LHTTP, LPort);
    Check(LServer.Stop, 'Final restarted server stops successfully: ' + LServer.LastError);
    Check(LServer.Port = 0, 'Final stopped status port is zero');
    CheckNoListener(LPort, 'Final Stop');
    LHTTP.Disconnect;
  finally
    LHTTP.Free;
    LOther.Free;
    LServer.Free;
  end;
end;

begin
  try
    if SameText(ParamStr(1), '--inherited-handles-child') then
    begin
      RunInheritedHandleChild;
      Exit;
    end;
    CheckLinkage;
    try
      LoadHostPeers;
      RunInheritedListener;
      if not HasArgument('--inheritance-only') then
        RunLifecycle;
    finally
      UnloadHostPeers;
    end;
    Writeln(Format('PASS: %d actual server lifecycle checks (%s, %s).', [CheckCount,
      {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF}, {$IFDEF DAI_LIFECYCLE_PACKAGES}'manufacturer BPLs'{$ELSE}'static'{$ENDIF}]));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
