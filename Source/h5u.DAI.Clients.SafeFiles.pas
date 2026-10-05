unit h5u.DAI.Clients.SafeFiles;

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.Classes,
  System.SysUtils;

type
  EDAIClientConfigConflict = class(EInvalidOperation);

  TDAIClientSafeFiles = class sealed
  public
    class procedure ValidatePath(const AFileName: string; ARequireWritable: Boolean = False); static;
    class function ReadTextIfExists(const AFileName: string): string; static;
    class function WriteTextWithBackup(const AFileName, AText: string): string; overload; static;
    class function WriteTextWithBackup(const AFileName, AText, AExpectedText: string; AExpectedExists: Boolean): string; overload; static;
    class function DeleteFileWithBackup(const AFileName: string): string; overload; static;
    class function DeleteFileWithBackup(const AFileName, AExpectedText: string; AExpectedExists: Boolean): string; overload; static;
  end;

implementation

uses
  System.IOUtils,
  Winapi.Windows;

const
  CMaxConfigBytes = 4 * 1024 * 1024;
  CSddlRevision = 1;
  CProtectedDaclSecurityInformation = $80000000;
  CUnprotectedDaclSecurityInformation = $20000000;

function ConvertStringSecurityDescriptorToSecurityDescriptorW(StringSecurityDescriptor: PWideChar; StringSDRevision: DWORD;
  var SecurityDescriptor: PSECURITY_DESCRIPTOR; SecurityDescriptorSize: PDWORD): BOOL; stdcall;
  external advapi32 name 'ConvertStringSecurityDescriptorToSecurityDescriptorW';

function ConvertSidToStringSidW(Sid: PSID; var StringSid: PWideChar): BOOL; stdcall;
  external advapi32 name 'ConvertSidToStringSidW';

procedure Conflict(const AMessage: string);
begin
  raise EDAIClientConfigConflict.Create(AMessage);
end;

function UniqueSuffix: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := StringReplace(StringReplace(GUIDToString(LGuid), '{', '', []), '}', '', []);
end;

function BytesEqual(const ALeft, ARight: TBytes): Boolean;
begin
  Result := Length(ALeft) = Length(ARight);
  if Result and (Length(ALeft) > 0) then
    Result := CompareMem(@ALeft[0], @ARight[0], Length(ALeft));
end;

function ReadBytes(const AFileName: string): TBytes;
var
  LFile: THandle;
  LInfo: TByHandleFileInformation;
  LRead: DWORD;
begin
  Result := nil;
  if not TFile.Exists(AFileName) then
    Exit;
  LFile := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT or FILE_FLAG_SEQUENTIAL_SCAN, 0);
  if LFile = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  try
    if not GetFileInformationByHandle(LFile, LInfo) then
      RaiseLastOSError;
    if (LInfo.dwFileAttributes and (FILE_ATTRIBUTE_DIRECTORY or FILE_ATTRIBUTE_REPARSE_POINT)) <> 0 then
      Conflict('Verknüpfte oder unpassende Konfigurationsdateien werden nicht bearbeitet.');
    if LInfo.nNumberOfLinks <> 1 then
      Conflict('Konfigurationsdateien mit mehreren Hardlinks werden nicht bearbeitet.');
    if (LInfo.nFileSizeHigh <> 0) or (LInfo.nFileSizeLow > CMaxConfigBytes) then
      Conflict('Die Konfiguration ist größer als 4 MiB.');
    SetLength(Result, LInfo.nFileSizeLow);
    if Length(Result) > 0 then
    begin
      if not ReadFile(LFile, Result[0], Length(Result), LRead, nil) then
        RaiseLastOSError;
      if LRead <> DWORD(Length(Result)) then
        Conflict('Die Konfiguration konnte nicht vollständig gelesen werden.');
    end;
  finally
    CloseHandle(LFile);
  end;
end;

function DecodeText(const ABytes: TBytes): string;
var
  LOffset: Integer;
  LEncoding: TUTF8Encoding;
begin
  LOffset := 0;
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    LOffset := 3;
  // Decoding does not emit a BOM; the parameterless constructor works on Delphi 11.
  LEncoding := TUTF8Encoding.Create;
  try
    try
      Result := LEncoding.GetString(ABytes, LOffset, Length(ABytes) - LOffset);
    except
      on E: EEncodingError do
        Conflict('Die Konfiguration ist kein gültiges UTF-8.');
    end;
  finally
    LEncoding.Free;
  end;
end;

function PrivateSecurityDescriptor: PSECURITY_DESCRIPTOR;
var
  LToken: THandle;
  LSize: DWORD;
  LUser: TBytes;
  LSid: PWideChar;
  LSddl: string;
begin
  Result := nil;
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
    LSid := nil;
    if not ConvertSidToStringSidW(PTokenUser(@LUser[0])^.User.Sid, LSid) then
      RaiseLastOSError;
    try
      LSddl := 'D:P(A;;FA;;;SY)(A;;FA;;;' + string(LSid) + ')';
    finally
      LocalFree(HLOCAL(LSid));
    end;
    if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PChar(LSddl), CSddlRevision, Result, nil) then
      RaiseLastOSError;
  finally
    CloseHandle(LToken);
  end;
end;

procedure WritePrivateFile(const AFileName: string; const ABytes: TBytes);
var
  LFile: THandle;
  LWritten: DWORD;
  LAttributes: TSecurityAttributes;
  LDescriptor: PSECURITY_DESCRIPTOR;
begin
  LDescriptor := PrivateSecurityDescriptor;
  try
    LAttributes.nLength := SizeOf(LAttributes);
    LAttributes.lpSecurityDescriptor := LDescriptor;
    LAttributes.bInheritHandle := False;
    LFile := CreateFile(PChar(AFileName), GENERIC_WRITE, 0, @LAttributes, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
    if LFile = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    try
      if Length(ABytes) > 0 then
      begin
        if not WriteFile(LFile, ABytes[0], Length(ABytes), LWritten, nil) then
          RaiseLastOSError;
        if LWritten <> DWORD(Length(ABytes)) then
          Conflict('Die Konfiguration konnte nicht vollständig geschrieben werden.');
      end;
      if not FlushFileBuffers(LFile) then
        RaiseLastOSError;
    finally
      CloseHandle(LFile);
    end;
  finally
    LocalFree(HLOCAL(LDescriptor));
  end;
end;

procedure PreserveDacl(const ASourceFile, ATargetFile: string);
var
  LSize: DWORD;
  LDescriptor: TBytes;
  LControl: SECURITY_DESCRIPTOR_CONTROL;
  LRevision: DWORD;
  LInformation: SECURITY_INFORMATION;
begin
  LSize := 0;
  GetFileSecurity(PChar(ASourceFile), DACL_SECURITY_INFORMATION, nil, 0, LSize);
  if LSize = 0 then
    RaiseLastOSError;
  SetLength(LDescriptor, LSize);
  if not GetFileSecurity(PChar(ASourceFile), DACL_SECURITY_INFORMATION, @LDescriptor[0], LSize, LSize) then
    RaiseLastOSError;
  if not GetSecurityDescriptorControl(@LDescriptor[0], LControl, LRevision) then
    RaiseLastOSError;
  LInformation := DACL_SECURITY_INFORMATION;
  if (LControl and SE_DACL_PROTECTED) <> 0 then
    LInformation := LInformation or CProtectedDaclSecurityInformation
  else
    LInformation := LInformation or CUnprotectedDaclSecurityInformation;
  if not SetFileSecurity(PChar(ATargetFile), LInformation, @LDescriptor[0]) then
    RaiseLastOSError;
end;

class procedure TDAIClientSafeFiles.ValidatePath(const AFileName: string; ARequireWritable: Boolean);
var
  LCurrent: string;
  LParent: string;
  LAttributes: DWORD;
begin
  if (AFileName = '') or not TPath.IsPathRooted(AFileName) then
    Conflict('Der Konfigurationspfad muss absolut sein.');
  if (Length(AFileName) < 3) or (AFileName[2] <> ':') or not CharInSet(AFileName[3], ['\', '/']) then
    Conflict('Der Konfigurationspfad muss ein absoluter lokaler Windows-Pfad sein.');
  if (Pos(':', Copy(AFileName, 3, MaxInt)) > 0) or AFileName.StartsWith('\\') then
    Conflict('Netzwerk-, Geräte- und Stream-Pfade werden nicht automatisch bearbeitet.');
  LCurrent := TPath.GetFullPath(AFileName);
  LAttributes := GetFileAttributes(PChar(LCurrent));
  if LAttributes <> INVALID_FILE_ATTRIBUTES then
  begin
    if (LAttributes and (FILE_ATTRIBUTE_DIRECTORY or FILE_ATTRIBUTE_REPARSE_POINT)) <> 0 then
      Conflict('Verknüpfte oder unpassende Konfigurationsdateien werden nicht bearbeitet.');
    if ARequireWritable and ((LAttributes and FILE_ATTRIBUTE_READONLY) <> 0) then
      Conflict('Die Konfigurationsdatei ist schreibgeschützt.');
    DecodeText(ReadBytes(LCurrent));
  end
  else if GetLastError <> ERROR_FILE_NOT_FOUND then
    if GetLastError <> ERROR_PATH_NOT_FOUND then
      RaiseLastOSError;
  LCurrent := TPath.GetDirectoryName(LCurrent);
  while LCurrent <> '' do
  begin
    LAttributes := GetFileAttributes(PChar(LCurrent));
    if LAttributes <> INVALID_FILE_ATTRIBUTES then
      if ((LAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) or ((LAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0) then
        Conflict('Verknüpfte oder unpassende Konfigurationsordner werden nicht bearbeitet.');
    LParent := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(LCurrent));
    if SameText(LParent, LCurrent) then
      Break;
    LCurrent := LParent;
  end;
end;

class function TDAIClientSafeFiles.ReadTextIfExists(const AFileName: string): string;
begin
  ValidatePath(AFileName);
  Result := DecodeText(ReadBytes(AFileName));
end;

class function TDAIClientSafeFiles.WriteTextWithBackup(const AFileName, AText: string): string;
begin
  Result := WriteTextWithBackup(AFileName, AText, ReadTextIfExists(AFileName), TFile.Exists(AFileName));
end;

class function TDAIClientSafeFiles.WriteTextWithBackup(const AFileName, AText, AExpectedText: string; AExpectedExists: Boolean): string;
var
  LBefore: TBytes;
  LBytes: TBytes;
  LExisted: Boolean;
  LTemp: string;
  LBackup: string;
  LSuffix: string;
begin
  Result := '';
  ValidatePath(AFileName, True);
  LExisted := TFile.Exists(AFileName);
  LBefore := ReadBytes(AFileName);
  if (LExisted <> AExpectedExists) or (DecodeText(LBefore) <> AExpectedText) then
    Conflict('Die Konfiguration wurde seit der Prüfung geändert; bitte erneut versuchen.');
  LBytes := TEncoding.UTF8.GetBytes(AText);
  if (Length(LBefore) >= 3) and (LBefore[0] = $EF) and (LBefore[1] = $BB) and (LBefore[2] = $BF) then
    LBytes := TBytes.Create($EF, $BB, $BF) + LBytes;
  if Length(LBytes) > CMaxConfigBytes then
    Conflict('Die neue Konfiguration ist größer als 4 MiB.');
  if LExisted and BytesEqual(LBefore, LBytes) then
    Exit;
  ForceDirectories(TPath.GetDirectoryName(AFileName));
  ValidatePath(AFileName, True);
  LSuffix := UniqueSuffix;
  LTemp := AFileName + '.dai-' + LSuffix + '.tmp';
  LBackup := AFileName + '.dai-' + LSuffix + '.bak';
  try
    WritePrivateFile(LTemp, LBytes);
    if LExisted then
    begin
      // The backup remains private, even when the client configuration has a broader existing DACL.
      WritePrivateFile(LBackup, LBefore);
      PreserveDacl(AFileName, LTemp);
    end;
    ValidatePath(AFileName, True);
    if (LExisted <> TFile.Exists(AFileName)) or not BytesEqual(LBefore, ReadBytes(AFileName)) then
      Conflict('Die Konfiguration wurde gleichzeitig geändert; bitte erneut versuchen.');
    if LExisted then
    begin
      if not ReplaceFile(PChar(AFileName), PChar(LTemp), nil, 0, nil, nil) then
        RaiseLastOSError;
      Result := LBackup;
    end
    else if not MoveFileEx(PChar(LTemp), PChar(AFileName), MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  finally
    if TFile.Exists(LTemp) then
      TFile.Delete(LTemp);
  end;
end;

class function TDAIClientSafeFiles.DeleteFileWithBackup(const AFileName: string): string;
begin
  Result := DeleteFileWithBackup(AFileName, ReadTextIfExists(AFileName), TFile.Exists(AFileName));
end;

class function TDAIClientSafeFiles.DeleteFileWithBackup(const AFileName, AExpectedText: string; AExpectedExists: Boolean): string;
var
  LBytes: TBytes;
begin
  Result := '';
  ValidatePath(AFileName, True);
  if TFile.Exists(AFileName) <> AExpectedExists then
    Conflict('Die Datei wurde seit der Prüfung ersetzt; bitte erneut versuchen.');
  if not TFile.Exists(AFileName) then
    Exit;
  LBytes := ReadBytes(AFileName);
  if DecodeText(LBytes) <> AExpectedText then
    Conflict('Die Datei wurde seit der Prüfung geändert; bitte erneut versuchen.');
  Result := AFileName + '.dai-' + UniqueSuffix + '.bak';
  WritePrivateFile(Result, LBytes);
  ValidatePath(AFileName, True);
  if not BytesEqual(LBytes, ReadBytes(AFileName)) then
    Conflict('Die Konfiguration wurde gleichzeitig geändert; bitte erneut versuchen.');
  if not Winapi.Windows.DeleteFile(PChar(AFileName)) then
    RaiseLastOSError;
end;

end.
