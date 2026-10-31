unit h5u.DAI.PortReservations;

interface

type
  TDAIPortReservations = class
  public
    class var Available: Boolean;
    class var WindowsServer: Boolean;
    class var InitializeCount: Integer;
    class var ApplicationAvailable: Boolean;
    class var DenyWrite: Boolean;
    class var Ports: string;
    class var ReserveCount: Integer;
    class var LastKey: string;
    class var LastPort: Integer;
    class var LastAllowFallback: Boolean;
    class var FailReserve: Boolean;
    class var RangeAvailable: Boolean;
    class var RangeStart: Integer;
    class var RangeEnd: Integer;
    class var OtherPortReserved: Boolean;
    class var SearchCount: Integer;
    class var SearchPort: Integer;
    class var LastSearchPort: Integer;
    constructor Create(const ADirectory: string = ''; const AMutexName: string = '');
    class function IsWindowsServer: Boolean; static;
    function Exists: Boolean;
    function CanWrite: Boolean;
    function AppExists: Boolean;
    function ConfiguredRange(out AStartPort, AEndPort: Integer): Boolean;
    procedure Initialize;
    function OwnPorts(const AKey: string): string;
    function ReservedByOther(const AKey: string; const APort: Integer): Boolean;
    function FindAvailablePort(const ACurrentPort: Integer; out AStartPort, AEndPort: Integer; out ASharedRange: Boolean): Integer;
    function Reserve(const AKey: string; const APreferredPort, AActivePort: Integer; const AAllowFallback: Boolean = True): Integer;
    function Release(const AKey: string; const APort: Integer): Boolean;
    function GetDirectory: string;
    property Directory: string read GetDirectory;
  end;

implementation

uses
  System.SysUtils;

constructor TDAIPortReservations.Create(const ADirectory, AMutexName: string);
begin
  inherited Create;
end;

class function TDAIPortReservations.IsWindowsServer: Boolean;
begin
  Result := WindowsServer;
end;

function TDAIPortReservations.Exists: Boolean;
begin
  Result := Available;
end;

function TDAIPortReservations.CanWrite: Boolean;
begin
  Result := not DenyWrite;
end;

function TDAIPortReservations.AppExists: Boolean;
begin
  Result := ApplicationAvailable;
end;

function TDAIPortReservations.ConfiguredRange(out AStartPort, AEndPort: Integer): Boolean;
begin
  AStartPort := RangeStart;
  AEndPort := RangeEnd;
  Result := RangeAvailable;
end;

function TDAIPortReservations.ReservedByOther(const AKey: string; const APort: Integer): Boolean;
begin
  LastKey := AKey;
  LastPort := APort;
  Result := OtherPortReserved;
end;

function TDAIPortReservations.FindAvailablePort(const ACurrentPort: Integer; out AStartPort, AEndPort: Integer;
  out ASharedRange: Boolean): Integer;
begin
  Inc(SearchCount);
  LastSearchPort := ACurrentPort;
  ASharedRange := RangeAvailable;
  if RangeAvailable then
  begin
    AStartPort := RangeStart;
    AEndPort := RangeEnd;
  end
  else
  begin
    AStartPort := ACurrentPort;
    AEndPort := 65535;
  end;
  Result := SearchPort;
end;

procedure TDAIPortReservations.Initialize;
begin
  Inc(InitializeCount);
  Available := True;
  ApplicationAvailable := True;
end;

function TDAIPortReservations.OwnPorts(const AKey: string): string;
begin
  LastKey := AKey;
  Result := Ports;
end;

function TDAIPortReservations.Reserve(const AKey: string; const APreferredPort, AActivePort: Integer;
  const AAllowFallback: Boolean): Integer;
begin
  Inc(ReserveCount);
  LastKey := AKey;
  LastPort := APreferredPort;
  LastAllowFallback := AAllowFallback;
  if FailReserve then
    raise Exception.Create('Synthetic reservation conflict');
  Result := APreferredPort;
end;

function TDAIPortReservations.Release(const AKey: string; const APort: Integer): Boolean;
begin
  Result := False;
end;

function TDAIPortReservations.GetDirectory: string;
begin
  Result := 'C:\SyntheticDAITest\PortReservations';
end;

end.
