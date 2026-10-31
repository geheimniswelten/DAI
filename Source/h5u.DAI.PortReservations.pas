unit h5u.DAI.PortReservations;

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  Winapi.Windows;

type
  EDAIPortReservation = class(EInvalidOperation);

  TDAIPortReservations = class sealed
  private
    FDirectory: string;
    FMutexName: string;
    FUserSid: string;
    FUserName: string;
    function AcquireLock: THandle;
    function FindOwnFile: string;
    function GetAppRange(out AStart, ACount: Integer): Boolean;
    function ReadReservations(const AOwnFile: string; const ALines: TStrings; out AOwnText: string; out AOwnExists: Boolean): TArray<Boolean>;
    procedure WriteOwnFile(const AFileName: string; const ALines: TStrings; const AExpectedText: string; const AExpectedExists: Boolean);
  public
    constructor Create(const ADirectory: string = ''; const AMutexName: string = '');
    class function DefaultDirectory: string; static;
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
    property Directory: string read FDirectory;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Winapi.ActiveX,
  Winapi.KnownFolders,
  Winapi.ShlObj,
  h5u.DAI.Clients.SafeFiles,
  h5u.DAI.WinAPI.TCP;

const
  CReservationMutex = 'Global\h5uPortReservation.v1';
  COperatingSystemAnyServer = 29; // Windows IsOS: OS_ANYSERVER.
  CAppFile = '.DAI';
  CDefaultStartPort = 17331;
  CDefaultPortCount = 100;
  CSddlRevision = 1;
  CMaximumLines = 65536;
  CDeleteAccess = $00010000;

function DAIIsOS(AValue: DWORD): BOOL; stdcall; external 'shlwapi.dll' name 'IsOS';

function DAICreateMutexExW(var AAttributes: TSecurityAttributes; AName: PWideChar; AFlags, AAccess: DWORD): THandle; stdcall;
  external kernel32 name 'CreateMutexExW';

function ConvertStringSecurityDescriptorToSecurityDescriptorW(StringSecurityDescriptor: PWideChar; StringSDRevision: DWORD;
  var SecurityDescriptor: PSECURITY_DESCRIPTOR; SecurityDescriptorSize: PDWORD): BOOL; stdcall;
  external advapi32 name 'ConvertStringSecurityDescriptorToSecurityDescriptorW';

function ConvertSidToStringSidW(Sid: PSID; var StringSid: PWideChar): BOOL; stdcall;
  external advapi32 name 'ConvertSidToStringSidW';

function SecurityDescriptor(const ASddl: string): PSECURITY_DESCRIPTOR;
begin
  Result := nil;
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PChar(ASddl), CSddlRevision, Result, nil) then
    RaiseLastOSError;
end;

function CurrentUserSid: string;
var
  LToken: THandle;
  LSize: DWORD;
  LUser: TBytes;
  LString: PWideChar;
begin
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, LToken) then
    RaiseLastOSError;
  try
    LSize := 0;
    GetTokenInformation(LToken, TokenUser, nil, 0, LSize);
    if LSize = 0 then
      RaiseLastOSError;
    SetLength(LUser, LSize);
    if not GetTokenInformation(LToken, TokenUser, @LUser[0], LSize, LSize) then
      RaiseLastOSError;
    LString := nil;
    if not ConvertSidToStringSidW(PTokenUser(@LUser[0])^.User.Sid, LString) then
      RaiseLastOSError;
    try
      Result := string(LString);
    finally
      LocalFree(HLOCAL(LString));
    end;
  finally
    CloseHandle(LToken);
  end;
end;

function CurrentUserName: string;
var
  LSize: DWORD;
begin
  LSize := 256;
  SetLength(Result, LSize);
  if not GetUserName(PChar(Result), LSize) then
  begin
    if GetLastError <> ERROR_INSUFFICIENT_BUFFER then
      RaiseLastOSError;
    SetLength(Result, LSize);
    if not GetUserName(PChar(Result), LSize) then
      RaiseLastOSError;
  end;
  SetLength(Result, LSize - 1);
end;

function SafeUserName(const AName: string): string;
var
  LChar: Char;
begin
  Result := '';
  for LChar in AName do
    if (Ord(LChar) < 32) or CharInSet(LChar, ['<', '>', ':', '"', '/', '\', '|', '?', '*']) then
      Result := Result + '_'
    else
      Result := Result + LChar;
  Result := Trim(Result);
  while Result <> '' do
  begin
    if not CharInSet(Result[Length(Result)], ['.', ' ']) then
      Break;
    Delete(Result, Length(Result), 1);
  end;
  if Result = '' then
    Result := 'User';
  if Length(Result) > 80 then
    SetLength(Result, 80);
end;

procedure CheckDirectory(const ADirectory: string);
var
  LAttributes: DWORD;
begin
  LAttributes := GetFileAttributes(PChar(ADirectory));
  if LAttributes = INVALID_FILE_ATTRIBUTES then
    RaiseLastOSError;
  if ((LAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or ((LAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
    raise EDAIPortReservation.Create('Der gemeinsame Portordner ist kein reguläres Verzeichnis.');
end;

procedure CreateSharedDirectory(const ADirectory: string);
var
  LDescriptor: PSECURITY_DESCRIPTOR;
  LAttributes: TSecurityAttributes;
  LError: DWORD;
begin
  LDescriptor := SecurityDescriptor('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICIIO;GA;;;CO)' +
    '(A;OICI;GRGX;;;AU)(A;;0x00000002;;;AU)S:(ML;OICI;NW;;;ME)');
  try
    LAttributes.nLength := SizeOf(LAttributes);
    LAttributes.lpSecurityDescriptor := LDescriptor;
    LAttributes.bInheritHandle := False;
    if not CreateDirectory(PChar(ADirectory), @LAttributes) then
    begin
      LError := GetLastError;
      if LError <> ERROR_ALREADY_EXISTS then
        RaiseLastOSError(LError);
    end;
  finally
    LocalFree(HLOCAL(LDescriptor));
  end;
  CheckDirectory(ADirectory);
end;

procedure CreateSharedFile(const AFileName, AText, ASid: string);
var
  LDescriptor: PSECURITY_DESCRIPTOR;
  LAttributes: TSecurityAttributes;
  LFile: THandle;
  LBytes: TBytes;
  LWritten: DWORD;
begin
  LDescriptor := SecurityDescriptor('O:' + ASid + 'D:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FA;;;' + ASid + ')(A;;FR;;;AU)S:(ML;;NW;;;ME)');
  try
    LAttributes.nLength := SizeOf(LAttributes);
    LAttributes.lpSecurityDescriptor := LDescriptor;
    LAttributes.bInheritHandle := False;
    LFile := CreateFile(PChar(AFileName), GENERIC_WRITE, 0, @LAttributes, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
    if LFile = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    try
      try
        LBytes := TEncoding.UTF8.GetBytes(AText);
        if Length(LBytes) > 0 then
        begin
          if not WriteFile(LFile, LBytes[0], Length(LBytes), LWritten, nil) then
            RaiseLastOSError;
          if LWritten <> DWORD(Length(LBytes)) then
            raise EDAIPortReservation.Create('Die Portdatei konnte nicht vollständig geschrieben werden.');
        end;
        if not FlushFileBuffers(LFile) then
          RaiseLastOSError;
      finally
        CloseHandle(LFile);
      end;
    except
      DeleteFile(PChar(AFileName));
      raise;
    end;
  finally
    LocalFree(HLOCAL(LDescriptor));
  end;
end;

function FileOwnerSid(const AFileName: string): string;
var
  LSize: DWORD;
  LDescriptor: TBytes;
  LOwner: PSID;
  LDefaulted: BOOL;
  LString: PWideChar;
begin
  LSize := 0;
  GetFileSecurity(PChar(AFileName), OWNER_SECURITY_INFORMATION, nil, 0, LSize);
  if LSize = 0 then
    RaiseLastOSError;
  SetLength(LDescriptor, LSize);
  if not GetFileSecurity(PChar(AFileName), OWNER_SECURITY_INFORMATION, @LDescriptor[0], LSize, LSize) then
    RaiseLastOSError;
  LOwner := nil;
  if not GetSecurityDescriptorOwner(@LDescriptor[0], LOwner, LDefaulted) or (LOwner = nil) then
    RaiseLastOSError;
  LString := nil;
  if not ConvertSidToStringSidW(LOwner, LString) then
    RaiseLastOSError;
  try
    Result := string(LString);
  finally
    LocalFree(HLOCAL(LString));
  end;
end;

procedure CheckOwnedFile(const AFileName, ASid: string; const ARequireWritable: Boolean = True);
begin
  TDAIClientSafeFiles.ValidatePath(AFileName, ARequireWritable);
  if not SameText(FileOwnerSid(AFileName), ASid) then
    raise EDAIPortReservation.Create('Die vorhandene Benutzerdatei gehört einem anderen Windows-Konto: ' + AFileName);
end;

procedure PreserveDacl(const ASourceFile, ATargetFile: string);
var
  LSize: DWORD;
  LDescriptor: TBytes;
begin
  LSize := 0;
  GetFileSecurity(PChar(ASourceFile), DACL_SECURITY_INFORMATION, nil, 0, LSize);
  if LSize = 0 then
    RaiseLastOSError;
  SetLength(LDescriptor, LSize);
  if not GetFileSecurity(PChar(ASourceFile), DACL_SECURITY_INFORMATION, @LDescriptor[0], LSize, LSize) then
    RaiseLastOSError;
  if not SetFileSecurity(PChar(ATargetFile), DACL_SECURITY_INFORMATION or $80000000, @LDescriptor[0]) then
    RaiseLastOSError;
end;

function IsUserFile(const AFileName: string): Boolean;
var
  LIndex, LSeparator: Integer;
  LName: string;
begin
  Result := False;
  LName := ExtractFileName(AFileName);
  if not StartsText('S-1-', LName) then
    Exit;
  LSeparator := Pos('_', LName);
  if (LSeparator < 6) or (LSeparator = Length(LName)) then
    Exit;
  for LIndex := 3 to LSeparator - 1 do
    if not CharInSet(LName[LIndex], ['0'..'9', '-']) then
      Exit;
  Result := True;
end;

procedure ParseEntry(const ALine, AFileName: string; out APort: Integer; out AKey: string);
var
  LSeparator, LIndex: Integer;
  LPortText: string;
begin
  LSeparator := Pos(#9, ALine);
  if (LSeparator < 2) or (Pos(#9, Copy(ALine, LSeparator + 1, MaxInt)) <> 0) then
    raise EDAIPortReservation.Create('Ungültige Portzeile in ' + AFileName + ': ' + ALine);
  LPortText := Copy(ALine, 1, LSeparator - 1);
  AKey := Copy(ALine, LSeparator + 1, MaxInt);
  if (LPortText <> Trim(LPortText)) or (AKey = '') or (AKey <> Trim(AKey)) then
    raise EDAIPortReservation.Create('Ungültige Portzeile in ' + AFileName + ': ' + ALine);
  for LIndex := 1 to Length(LPortText) do
    if not CharInSet(LPortText[LIndex], ['0'..'9']) then
      raise EDAIPortReservation.Create('Ungültige Portnummer in ' + AFileName + ': ' + LPortText);
  if not TryStrToInt(LPortText, APort) or (APort < 1) or (APort > 65535) then
    raise EDAIPortReservation.Create('Ungültige Portnummer in ' + AFileName + ': ' + LPortText);
  for LIndex := 1 to Length(AKey) do
    if not CharInSet(AKey[LIndex], ['a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.', ':']) then
      raise EDAIPortReservation.Create('Ungültige Anwendungskennung in ' + AFileName + ': ' + AKey);
end;

procedure ValidateKey(const AKey: string);
var
  LPort: Integer;
  LParsed: string;
begin
  ParseEntry('1' + #9 + AKey, 'DAI', LPort, LParsed);
end;

procedure ReleaseLock(const AMutex: THandle);
begin
  ReleaseMutex(AMutex);
  CloseHandle(AMutex);
end;

class function TDAIPortReservations.DefaultDirectory: string;
var
  LPath: PWideChar;
  LResult: HRESULT;
begin
  LPath := nil;
  LResult := SHGetKnownFolderPath(FOLDERID_ProgramData, 0, 0, LPath);
  if LResult < 0 then
    raise EOSError.CreateFmt('Der ProgramData-Pfad ist nicht verfügbar (HRESULT %.8x).', [Cardinal(LResult)]);
  try
    Result := TPath.Combine(string(LPath), 'h5uPortReservation');
  finally
    CoTaskMemFree(LPath);
  end;
end;

class function TDAIPortReservations.IsWindowsServer: Boolean;
begin
  Result := DAIIsOS(COperatingSystemAnyServer);
end;

constructor TDAIPortReservations.Create(const ADirectory, AMutexName: string);
begin
  inherited Create;
  if ADirectory = '' then
    FDirectory := DefaultDirectory
  else
    FDirectory := TPath.GetFullPath(ADirectory);
  if AMutexName = '' then
    FMutexName := CReservationMutex
  else
    FMutexName := AMutexName;
  FUserSid := CurrentUserSid;
  FUserName := CurrentUserName;
end;

function TDAIPortReservations.AcquireLock: THandle;
var
  LDescriptor: PSECURITY_DESCRIPTOR;
  LAttributes: TSecurityAttributes;
  LWait, LError: DWORD;
begin
  LDescriptor := SecurityDescriptor('D:P(A;;0x00100001;;;AU)(A;;GA;;;SY)(A;;GA;;;BA)S:(ML;;NW;;;ME)');
  try
    LAttributes.nLength := SizeOf(LAttributes);
    LAttributes.lpSecurityDescriptor := LDescriptor;
    LAttributes.bInheritHandle := False;
    Result := DAICreateMutexExW(LAttributes, PChar(FMutexName), 0, SYNCHRONIZE or MUTEX_MODIFY_STATE);
    if Result = 0 then
      RaiseLastOSError;
  finally
    LocalFree(HLOCAL(LDescriptor));
  end;
  LWait := WaitForSingleObject(Result, 10000);
  if (LWait = WAIT_OBJECT_0) or (LWait = WAIT_ABANDONED) then
    Exit;
  LError := GetLastError;
  CloseHandle(Result);
  if LWait = WAIT_TIMEOUT then
    raise EDAIPortReservation.Create('Die gemeinsame Portverwaltung ist beschäftigt. Bitte erneut versuchen.');
  RaiseLastOSError(LError);
end;

function TDAIPortReservations.Exists: Boolean;
var
  LAttributes, LError: DWORD;
begin
  LAttributes := GetFileAttributes(PChar(FDirectory));
  if LAttributes = INVALID_FILE_ATTRIBUTES then
  begin
    LError := GetLastError;
    if (LError = ERROR_FILE_NOT_FOUND) or (LError = ERROR_PATH_NOT_FOUND) then
      Exit(False);
    RaiseLastOSError(LError);
  end;
  CheckDirectory(FDirectory);
  Result := True;
end;

function TDAIPortReservations.CanWrite: Boolean;
var
  LFile, LHandle: THandle;
  LError: DWORD;
  LOwnFile: string;
begin
  Result := False;
  CheckDirectory(FDirectory);
  LHandle := CreateFile(PChar(FDirectory), FILE_ADD_FILE, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT, 0);
  if LHandle = INVALID_HANDLE_VALUE then
  begin
    LError := GetLastError;
    if LError = ERROR_ACCESS_DENIED then
      Exit;
    RaiseLastOSError(LError);
  end;
  CloseHandle(LHandle);
  LOwnFile := FindOwnFile;
  if TFile.Exists(LOwnFile) then
  begin
    LFile := CreateFile(PChar(LOwnFile), FILE_WRITE_DATA or CDeleteAccess, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, 0);
    if LFile = INVALID_HANDLE_VALUE then
    begin
      LError := GetLastError;
      if LError = ERROR_ACCESS_DENIED then
        Exit;
      RaiseLastOSError(LError);
    end;
    CloseHandle(LFile);
  end;
  Result := True;
end;

function TDAIPortReservations.AppExists: Boolean;
begin
  Result := TFile.Exists(TPath.Combine(FDirectory, CAppFile));
end;

function TDAIPortReservations.ConfiguredRange(out AStartPort, AEndPort: Integer): Boolean;
var
  LMutex: THandle;
  LCount: Integer;
begin
  Result := False;
  AStartPort := 0;
  AEndPort := 0;
  if not Exists then
    Exit;
  LMutex := AcquireLock;
  try
    CheckDirectory(FDirectory);
    Result := GetAppRange(AStartPort, LCount);
    if Result then
      AEndPort := AStartPort + LCount - 1;
  finally
    ReleaseLock(LMutex);
  end;
end;

procedure TDAIPortReservations.Initialize;
var
  LMutex: THandle;
  LAppFile: string;
begin
  CreateSharedDirectory(FDirectory);
  LMutex := AcquireLock;
  try
    CheckDirectory(FDirectory);
    LAppFile := TPath.Combine(FDirectory, CAppFile);
    if not TFile.Exists(LAppFile) then
      CreateSharedFile(LAppFile, 'Delphi AI' + sLineBreak + 'Schema=1' + sLineBreak +
        'StartPort=' + IntToStr(CDefaultStartPort) + sLineBreak + 'MaxAnzahl=' + IntToStr(CDefaultPortCount) + sLineBreak +
        'Protokoll=TCP' + sLineBreak + 'BindAdresse=127.0.0.1' + sLineBreak, FUserSid);
  finally
    ReleaseLock(LMutex);
  end;
end;

function TDAIPortReservations.FindOwnFile: string;
var
  LFile, LName, LPrefix: string;
begin
  Result := '';
  LPrefix := FUserSid + '_';
  for LFile in TDirectory.GetFiles(FDirectory) do
  begin
    LName := ExtractFileName(LFile);
    if StartsText(LPrefix, LName) and IsUserFile(LFile) then
    begin
      if Result <> '' then
        raise EDAIPortReservation.Create('Mehrere Portdateien gehören zur selben Benutzer-SID: ' + FUserSid);
      CheckOwnedFile(LFile, FUserSid, False);
      Result := LFile;
    end;
  end;
  if Result = '' then
    Result := TPath.Combine(FDirectory, LPrefix + SafeUserName(FUserName));
end;

function TDAIPortReservations.GetAppRange(out AStart, ACount: Integer): Boolean;
var
  LLines: TStringList;
  LFile, LLine, LName, LValue: string;
  LIndex, LSeparator, LSchema: Integer;
  LSeenStart, LSeenCount, LSeenSchema: Boolean;
begin
  Result := False;
  AStart := 0;
  ACount := 0;
  LSchema := 0;
  LSeenStart := False;
  LSeenCount := False;
  LSeenSchema := False;
  LFile := TPath.Combine(FDirectory, CAppFile);
  if not TFile.Exists(LFile) then
    Exit;
  LLines := TStringList.Create;
  try
    LLines.Text := TDAIClientSafeFiles.ReadTextIfExists(LFile);
    if LLines.Count < 2 then
      raise EDAIPortReservation.Create('Die DAI-Anwendungsdatei ist unvollständig: ' + LFile);
    if Trim(LLines[0]) = '' then
      raise EDAIPortReservation.Create('Die DAI-Anwendungsdatei ist unvollständig: ' + LFile);
    for LIndex := 1 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[LIndex]);
      if (LLine = '') or StartsStr('#', LLine) then
        Continue;
      LSeparator := Pos('=', LLine);
      if LSeparator < 2 then
        raise EDAIPortReservation.Create('Ungültiger Eintrag in ' + LFile + ': ' + LLine);
      LName := Trim(Copy(LLine, 1, LSeparator - 1));
      LValue := Trim(Copy(LLine, LSeparator + 1, MaxInt));
      if SameText(LName, 'Schema') then
      begin
        if LSeenSchema or not TryStrToInt(LValue, LSchema) then
          raise EDAIPortReservation.Create('Ungültiges Schema in ' + LFile);
        LSeenSchema := True;
      end
      else if SameText(LName, 'StartPort') then
      begin
        if LSeenStart or not TryStrToInt(LValue, AStart) then
          raise EDAIPortReservation.Create('Ungültiger StartPort in ' + LFile);
        LSeenStart := True;
      end
      else if SameText(LName, 'MaxAnzahl') then
      begin
        if LSeenCount or not TryStrToInt(LValue, ACount) then
          raise EDAIPortReservation.Create('Ungültige MaxAnzahl in ' + LFile);
        LSeenCount := True;
      end;
    end;
    if not LSeenSchema or (LSchema <> 1) or not LSeenStart or not LSeenCount then
      raise EDAIPortReservation.Create('Unbekanntes Schema oder fehlender Portbereich in ' + LFile);
    if (AStart < 1024) or (AStart > 65535) then
      raise EDAIPortReservation.Create('Ungültiger StartPort in ' + LFile);
    if (ACount < 1) or (ACount > 65536 - AStart) then
      raise EDAIPortReservation.Create('Ungültige MaxAnzahl in ' + LFile);
    Result := True;
  finally
    LLines.Free;
  end;
end;

function TDAIPortReservations.ReadReservations(const AOwnFile: string; const ALines: TStrings; out AOwnText: string; out AOwnExists: Boolean): TArray<Boolean>;
var
  LFile, LLine, LKey, LText: string;
  LFileLines: TStringList;
  LPort, LIndex: Integer;
begin
  SetLength(Result, 65536);
  ALines.Clear;
  AOwnText := '';
  AOwnExists := False;
  for LFile in TDirectory.GetFiles(FDirectory) do
  begin
    if not IsUserFile(LFile) then
      Continue;
    LFileLines := TStringList.Create;
    try
      LText := TDAIClientSafeFiles.ReadTextIfExists(LFile);
      LFileLines.Text := LText;
      if LFileLines.Count > CMaximumLines then
        raise EDAIPortReservation.Create('Zu viele Einträge in der Portdatei: ' + LFile);
      for LIndex := 0 to LFileLines.Count - 1 do
      begin
        LLine := LFileLines[LIndex];
        if (Trim(LLine) = '') or StartsStr('#', TrimLeft(LLine)) then
          Continue;
        ParseEntry(LLine, LFile, LPort, LKey);
        if Result[LPort] then
          raise EDAIPortReservation.CreateFmt('Der Port %d ist mehrfach reserviert. Bitte die gemeinsame Portverwaltung prüfen.', [LPort]);
        Result[LPort] := True;
      end;
      if SameText(LFile, AOwnFile) then
      begin
        AOwnExists := True;
        AOwnText := LText;
        ALines.Assign(LFileLines);
      end;
    finally
      LFileLines.Free;
    end;
  end;
end;

procedure ReplaceOwnFile(const ATemp, AFileName, ASid, AOriginalText: string; const AExisted: Boolean);
const
  CMaxAttempts = 60;
  CRetryDelayMs = 25;
var
  LFlags, LError: DWORD;
  LAttempt: Integer;
begin
  LFlags := MOVEFILE_WRITE_THROUGH;
  if AExisted then
    LFlags := LFlags or MOVEFILE_REPLACE_EXISTING;
  for LAttempt := 1 to CMaxAttempts do
  begin
    if MoveFileEx(PChar(ATemp), PChar(AFileName), LFlags) then
      Exit;
    LError := GetLastError;
    if (LAttempt = CMaxAttempts) or
      ((LError <> ERROR_ACCESS_DENIED) and (LError <> ERROR_SHARING_VIOLATION) and (LError <> ERROR_LOCK_VIOLATION)) then
      RaiseLastOSError(LError);
    Sleep(CRetryDelayMs);
    if AExisted then
    begin
      CheckOwnedFile(AFileName, ASid);
      if TDAIClientSafeFiles.ReadTextIfExists(AFileName) <> AOriginalText then
        raise EDAIPortReservation.Create('Die Benutzerdatei wurde zwischenzeitlich geändert. Bitte erneut versuchen.');
    end
    else if TFile.Exists(AFileName) then
      raise EDAIPortReservation.Create('Die Benutzerdatei wurde zwischenzeitlich erstellt. Bitte erneut versuchen.');
  end;
end;

procedure TDAIPortReservations.WriteOwnFile(const AFileName: string; const ALines: TStrings; const AExpectedText: string; const AExpectedExists: Boolean);
var
  LGuid: TGUID;
  LTemp, LOld, LPhase: string;
  LExisted, LTempCreated: Boolean;
begin
  LPhase := 'Benutzerdatei vor dem Schreiben prüfen';
  try
    LExisted := TFile.Exists(AFileName);
    if LExisted <> AExpectedExists then
      raise EDAIPortReservation.Create('Die Benutzerdatei wurde zwischenzeitlich erstellt oder entfernt. Bitte erneut versuchen.');
    if LExisted then
    begin
      CheckOwnedFile(AFileName, FUserSid);
      LOld := TDAIClientSafeFiles.ReadTextIfExists(AFileName);
      if LOld <> AExpectedText then
        raise EDAIPortReservation.Create('Die Benutzerdatei wurde zwischenzeitlich geändert. Bitte erneut versuchen.');
    end;
    if CreateGUID(LGuid) <> 0 then
      raise EDAIPortReservation.Create('Die Kennung für die temporäre Portdatei konnte nicht erzeugt werden.');
    LTemp := TPath.Combine(FDirectory, '.tmp-' + GUIDToString(LGuid));
    LTempCreated := False;
    try
      LPhase := 'Temporäre Benutzerdatei erstellen';
      CreateSharedFile(LTemp, ALines.Text, FUserSid);
      LTempCreated := True;
      if LExisted then
      begin
        LPhase := 'Benutzerdatei erneut prüfen';
        CheckOwnedFile(AFileName, FUserSid);
        if TDAIClientSafeFiles.ReadTextIfExists(AFileName) <> LOld then
          raise EDAIPortReservation.Create('Die Benutzerdatei wurde zwischenzeitlich geändert. Bitte erneut versuchen.');
        LPhase := 'Dateirechte übernehmen';
        PreserveDacl(AFileName, LTemp);
      end
      else if TFile.Exists(AFileName) then
        raise EDAIPortReservation.Create('Die Benutzerdatei wurde zwischenzeitlich erstellt. Bitte erneut versuchen.');
      LPhase := 'Benutzerdatei ersetzen';
      ReplaceOwnFile(LTemp, AFileName, FUserSid, LOld, LExisted);
    finally
      if LTempCreated and TFile.Exists(LTemp) then
        DeleteFile(PChar(LTemp));
    end;
  except
    on E: EOSError do
      raise EOSError.Create(LPhase + ': ' + E.Message);
  end;
end;

function TDAIPortReservations.OwnPorts(const AKey: string): string;
var
  LMutex: THandle;
  LFile, LLine, LEntryKey: string;
  LLines: TStringList;
  LPort, LIndex: Integer;
begin
  ValidateKey(AKey);
  Result := '';
  LMutex := AcquireLock;
  try
    CheckDirectory(FDirectory);
    LFile := FindOwnFile;
    LLines := TStringList.Create;
    try
      if TFile.Exists(LFile) then
        LLines.Text := TDAIClientSafeFiles.ReadTextIfExists(LFile);
      for LIndex := 0 to LLines.Count - 1 do
      begin
        LLine := LLines[LIndex];
        if (Trim(LLine) = '') or StartsStr('#', TrimLeft(LLine)) then
          Continue;
        ParseEntry(LLine, LFile, LPort, LEntryKey);
        if SameText(LEntryKey, AKey) then
        begin
          if Result <> '' then
            Result := Result + ', ';
          Result := Result + IntToStr(LPort);
        end;
      end;
    finally
      LLines.Free;
    end;
  finally
    ReleaseLock(LMutex);
  end;
end;

function TDAIPortReservations.ReservedByOther(const AKey: string; const APort: Integer): Boolean;
var
  LMutex: THandle;
  LFile, LLine, LEntryKey, LOwnText: string;
  LLines: TStringList;
  LUsed: TArray<Boolean>;
  LPort, LIndex: Integer;
  LOwnExists: Boolean;
begin
  ValidateKey(AKey);
  if (APort < 1024) or (APort > 65535) then
    raise EDAIPortReservation.Create('Der Port muss zwischen 1024 und 65535 liegen.');
  if not Exists then
    Exit(False);
  LMutex := AcquireLock;
  try
    CheckDirectory(FDirectory);
    LFile := FindOwnFile;
    LLines := TStringList.Create;
    try
      LUsed := ReadReservations(LFile, LLines, LOwnText, LOwnExists);
      if not LUsed[APort] then
        Exit(False);
      for LIndex := 0 to LLines.Count - 1 do
      begin
        LLine := LLines[LIndex];
        if (Trim(LLine) = '') or StartsStr('#', TrimLeft(LLine)) then
          Continue;
        ParseEntry(LLine, LFile, LPort, LEntryKey);
        if (LPort = APort) and SameText(LEntryKey, AKey) then
          Exit(False);
      end;
      Result := True;
    finally
      LLines.Free;
    end;
  finally
    ReleaseLock(LMutex);
  end;
end;

function TDAIPortReservations.FindAvailablePort(const ACurrentPort: Integer; out AStartPort, AEndPort: Integer; out ASharedRange: Boolean): Integer;
var
  LMutex: THandle;
  LFile, LOwnText: string;
  LLines: TStringList;
  LUsed: TArray<Boolean>;
  LOwnExists: Boolean;
  LCount, LPort: Integer;
  LProbe: TDAITCPPortProbe;
begin
  ASharedRange := False;
  AStartPort := 0;
  AEndPort := 0;
  SetLength(LUsed, 65536);
  if Exists then
  begin
    LMutex := AcquireLock;
    try
      CheckDirectory(FDirectory);
      LFile := FindOwnFile;
      LLines := TStringList.Create;
      try
        LUsed := ReadReservations(LFile, LLines, LOwnText, LOwnExists);
        ASharedRange := GetAppRange(AStartPort, LCount);
        if ASharedRange then
          AEndPort := AStartPort + LCount - 1;
      finally
        LLines.Free;
      end;
    finally
      ReleaseLock(LMutex);
    end;
  end;
  if not ASharedRange then
  begin
    if (ACurrentPort < 1024) or (ACurrentPort > 65535) then
      raise EDAIPortReservation.Create('Für die Suche einen Startport zwischen 1024 und 65535 eingeben.');
    AStartPort := ACurrentPort;
    AEndPort := 65535;
  end;
  LProbe := TDAITCPPortProbe.Create;
  try
    for LPort := AStartPort to AEndPort do
      if not LUsed[LPort] then
        if LProbe.CanBindLoopback(LPort) then
          Exit(LPort);
  finally
    LProbe.Free;
  end;
  raise EDAIPortReservation.CreateFmt('Im Suchbereich %d–%d wurde kein freier TCP-Port gefunden.', [AStartPort, AEndPort]);
end;

function TDAIPortReservations.Reserve(const AKey: string; const APreferredPort, AActivePort: Integer; const AAllowFallback: Boolean): Integer;
var
  LMutex: THandle;
  LFile, LLine, LEntryKey, LOwnText, LPhase: string;
  LLines: TStringList;
  LUsed: TArray<Boolean>;
  LStart, LCount, LPort, LIndex: Integer;
  LOwnPreferred, LOwnExists: Boolean;
  LOwner: TDAITCPListenerOwner;
  LProbe: TDAITCPPortProbe;

  function Available(const APort: Integer): Boolean;
  begin
    if (APort < 1024) or (APort > 65535) then
      Exit(False);
    if (APort = APreferredPort) and LOwnPreferred then
      Exit(True);
    if LUsed[APort] then
      Exit(False);
    if APort = AActivePort then
      if TDAITCPListener.TryFindIPv4Owner(APort, LOwner) then
        if LOwner.IsCurrentProcess then
          Exit(True);
    if not Assigned(LProbe) then
      LProbe := TDAITCPPortProbe.Create;
    Result := LProbe.CanBindLoopback(APort);
  end;

begin
  ValidateKey(AKey);
  LProbe := nil;
  LPhase := 'Portverwaltung sperren';
  try
    LMutex := AcquireLock;
    try
      LPhase := 'Portverwaltung prüfen';
      CheckDirectory(FDirectory);
      if not GetAppRange(LStart, LCount) then
        raise EDAIPortReservation.Create('Die DAI-Anwendungsdatei fehlt. Bitte zuerst die Portverwaltung einrichten.');
      LPhase := 'Benutzerdatei suchen';
      LFile := FindOwnFile;
      LLines := TStringList.Create;
      try
        LPhase := 'Reservierungen lesen';
        LUsed := ReadReservations(LFile, LLines, LOwnText, LOwnExists);
        LOwnPreferred := False;
        for LIndex := 0 to LLines.Count - 1 do
        begin
          LLine := LLines[LIndex];
          if (Trim(LLine) = '') or StartsStr('#', TrimLeft(LLine)) then
            Continue;
          ParseEntry(LLine, LFile, LPort, LEntryKey);
          if (LPort = APreferredPort) and SameText(LEntryKey, AKey) then
            LOwnPreferred := True;
        end;
        LPhase := 'TCP-Port prüfen';
        Result := 0;
        if Available(APreferredPort) then
          Result := APreferredPort
        else if not AAllowFallback then
          raise EDAIPortReservation.CreateFmt('Port %d ist belegt oder anderweitig reserviert. Bitte einen freien Port auswählen.', [APreferredPort])
        else
          for LPort := LStart to LStart + LCount - 1 do
            if Available(LPort) then
            begin
              Result := LPort;
              Break;
            end;
        if Result = 0 then
          raise EDAIPortReservation.Create('Im DAI-Portbereich wurde kein freier Port gefunden.');
        if LOwnPreferred and (Result = APreferredPort) then
          Exit;
        if LLines.Count = 0 then
          LLines.Add('# Benutzer: ' + SafeUserName(FUserName));
        LLines.Add(IntToStr(Result) + #9 + AKey);
        LPhase := 'Benutzerdatei schreiben';
        WriteOwnFile(LFile, LLines, LOwnText, LOwnExists);
      finally
        LLines.Free;
      end;
    finally
      LProbe.Free;
      ReleaseLock(LMutex);
    end;
  except
    on E: EOSError do
      raise EOSError.Create(LPhase + ': ' + E.Message);
  end;
end;

function TDAIPortReservations.Release(const AKey: string; const APort: Integer): Boolean;
var
  LMutex: THandle;
  LFile, LLine, LEntryKey, LOwnText: string;
  LLines: TStringList;
  LPort, LIndex: Integer;
  LOwnExists: Boolean;
begin
  ValidateKey(AKey);
  Result := False;
  LMutex := AcquireLock;
  try
    CheckDirectory(FDirectory);
    LFile := FindOwnFile;
    LLines := TStringList.Create;
    try
      ReadReservations(LFile, LLines, LOwnText, LOwnExists);
      for LIndex := LLines.Count - 1 downto 0 do
      begin
        LLine := LLines[LIndex];
        if (Trim(LLine) = '') or StartsStr('#', TrimLeft(LLine)) then
          Continue;
        ParseEntry(LLine, LFile, LPort, LEntryKey);
        if (LPort = APort) and SameText(LEntryKey, AKey) then
        begin
          LLines.Delete(LIndex);
          Result := True;
        end;
      end;
      if Result then
        WriteOwnFile(LFile, LLines, LOwnText, LOwnExists);
    finally
      LLines.Free;
    end;
  finally
    ReleaseLock(LMutex);
  end;
end;

end.
