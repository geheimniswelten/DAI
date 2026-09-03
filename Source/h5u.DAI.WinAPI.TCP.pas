unit h5u.DAI.WinAPI.TCP;

interface

type
  TDAITCPListenerOwner = record
    ProcessId: Cardinal;
    ProcessName: string;
    IsCurrentProcess: Boolean;
  end;

  TDAITCPListener = class sealed
  public
    class function TryFindIPv4Owner(const APort: Word; out AOwner: TDAITCPListenerOwner): Boolean; static;
    class function DescribeIPv4Owner(const APort: Word): string; static;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows;

const
  CAddressFamilyInet = 2;
  CErrorInsufficientBuffer = 122;
  CIPv4Any = 0;
  CIPv4LoopbackNetworkOrder = $0100007F;
  CIPv4LoopbackHostOrder = $7F000001;
  CMaxProcessPathChars = 32768;
  CProcessQueryLimitedInformation = $1000;
  CTcpTableOwnerPidListener = 3;

type
  TMibTcpRowOwnerPid = record
    State: DWORD;
    LocalAddress: DWORD;
    LocalPort: DWORD;
    RemoteAddress: DWORD;
    RemotePort: DWORD;
    OwningProcessId: DWORD;
  end;

  PMibTcpRowOwnerPid = ^TMibTcpRowOwnerPid;

  TGetExtendedTcpTable = function(ATcpTable: Pointer; var ASize: DWORD; AOrder: BOOL; AAddressFamily: Cardinal; ATableClass: Integer;
    AReserved: Cardinal): DWORD; stdcall;

  TQueryFullProcessImageNameW = function(AProcess: THandle; AFlags: DWORD; AFileName: PWideChar; var ASize: DWORD): BOOL; stdcall;

function PortFromNetworkOrder(const APort: DWORD): Word;
var
  LPort: Word;
begin
  LPort := Word(APort and $FFFF);
  Result := Word(((LPort and $00FF) shl 8) or ((LPort and $FF00) shr 8));
end;

function IsRelevantLocalAddress(const AAddress: DWORD): Boolean;
begin
  Result := (AAddress = CIPv4Any) or (AAddress = CIPv4LoopbackNetworkOrder) or (AAddress = CIPv4LoopbackHostOrder);
end;

function TryGetProcessPath(const AProcessId: Cardinal; out AProcessPath: string): Boolean;
var
  LKernelModule: HMODULE;
  LProcess: THandle;
  LQueryFullProcessImageNameW: TQueryFullProcessImageNameW;
  LSize: DWORD;
begin
  Result := False;
  AProcessPath := '';
  LKernelModule := GetModuleHandle('kernel32.dll');
  if LKernelModule = 0 then
    Exit;

  LQueryFullProcessImageNameW := TQueryFullProcessImageNameW(GetProcAddress(LKernelModule, 'QueryFullProcessImageNameW'));
  if not Assigned(LQueryFullProcessImageNameW) then
    Exit;

  LProcess := OpenProcess(CProcessQueryLimitedInformation, False, AProcessId);
  if LProcess = 0 then
    Exit;
  try
    SetLength(AProcessPath, CMaxProcessPathChars);
    UniqueString(AProcessPath);
    LSize := Length(AProcessPath);
    if not LQueryFullProcessImageNameW(LProcess, 0, PWideChar(AProcessPath), LSize) then
    begin
      AProcessPath := '';
      Exit;
    end;

    SetLength(AProcessPath, LSize);
    Result := AProcessPath <> '';
  finally
    CloseHandle(LProcess);
  end;
end;

class function TDAITCPListener.DescribeIPv4Owner(const APort: Word): string;
var
  LOwner: TDAITCPListenerOwner;
begin
  try
    if not TryFindIPv4Owner(APort, LOwner) then
      Exit('Der belegende Prozess konnte über die Windows-TCP-Tabelle nicht ermittelt werden.');

    if LOwner.ProcessName <> '' then
      Result := Format('Listener: PID %d, Prozess %s.', [LOwner.ProcessId, LOwner.ProcessName])
    else
      Result := Format('Listener: PID %d; der Prozessname konnte nicht gelesen werden.', [LOwner.ProcessId]);

    if LOwner.IsCurrentProcess then
      Result := Result + ' Die PID gehört zur aktuellen Delphi-IDE-Instanz; das verantwortliche Package oder Plugin ist über die TCP-Tabelle nicht ermittelbar.';
  except
    on E: Exception do
      Result := Format('Der belegende Prozess konnte nicht ermittelt werden: %s: %s', [E.ClassName, E.Message]);
  end;
end;

class function TDAITCPListener.TryFindIPv4Owner(const APort: Word; out AOwner: TDAITCPListenerOwner): Boolean;
var
  LBuffer: TBytes;
  LCount: DWORD;
  LError: DWORD;
  LGetExtendedTcpTable: TGetExtendedTcpTable;
  LIndex: DWORD;
  LModule: HMODULE;
  LProcessPath: string;
  LRequiredSize: UInt64;
  LRow: PMibTcpRowOwnerPid;
  LSize: DWORD;
begin
  Result := False;
  AOwner := Default(TDAITCPListenerOwner);
  LModule := LoadLibrary('iphlpapi.dll');
  if LModule = 0 then
    Exit;
  try
    LGetExtendedTcpTable := TGetExtendedTcpTable(GetProcAddress(LModule, 'GetExtendedTcpTable'));
    if not Assigned(LGetExtendedTcpTable) then
      Exit;

    LSize := 0;
    LError := LGetExtendedTcpTable(nil, LSize, False, CAddressFamilyInet, CTcpTableOwnerPidListener, 0);
    if (LError <> ERROR_SUCCESS) and (LError <> CErrorInsufficientBuffer) then
      Exit;
    if LSize < SizeOf(DWORD) then
      Exit;

    SetLength(LBuffer, LSize);
    LError := LGetExtendedTcpTable(@LBuffer[0], LSize, False, CAddressFamilyInet, CTcpTableOwnerPidListener, 0);
    if LError <> ERROR_SUCCESS then
      Exit;

    LCount := PDWORD(@LBuffer[0])^;
    LRequiredSize := UInt64(SizeOf(DWORD)) + UInt64(LCount) * UInt64(SizeOf(TMibTcpRowOwnerPid));
    if LRequiredSize > UInt64(Length(LBuffer)) then
      Exit;

    if LCount = 0 then
      Exit;

    for LIndex := 0 to LCount - 1 do
    begin
      LRow := PMibTcpRowOwnerPid(NativeUInt(@LBuffer[0]) + SizeOf(DWORD) + NativeUInt(LIndex) * SizeOf(TMibTcpRowOwnerPid));
      if (PortFromNetworkOrder(LRow.LocalPort) = APort) and IsRelevantLocalAddress(LRow.LocalAddress) then
      begin
        AOwner.ProcessId := LRow.OwningProcessId;
        AOwner.IsCurrentProcess := AOwner.ProcessId = GetCurrentProcessId;
        if TryGetProcessPath(AOwner.ProcessId, LProcessPath) then
          AOwner.ProcessName := ExtractFileName(LProcessPath)
        else if AOwner.IsCurrentProcess then
          AOwner.ProcessName := ExtractFileName(ParamStr(0));
        Result := True;
        Exit;
      end;
    end;
  finally
    FreeLibrary(LModule);
  end;
end;

end.
