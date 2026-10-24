unit h5u.DAI.Usage;

interface

const
  CDAIUsageRegistryRoot = 'Software\DelphiAI\DAI\UsageLog';

type
  TDAIUsage = class sealed
  public
    class procedure RecordToolCall(const ACanonicalToolName: string; const AShowsActivity: Boolean); static;
    class function LastActivityTick: UInt64; static;
    class procedure ResetActivity; static;
{$IFDEF DAI_USAGE_TESTS}
    class procedure TestRecordToolCallAt(const ACanonicalToolName: string; const AShowsActivity: Boolean; const ALocalDate: TDateTime); static;
    class function TestMutexName: string; static;
{$ENDIF}
  end;

implementation

uses
  System.SyncObjs,
  System.SysUtils,
  Winapi.Windows;

var
  GLastActivityTick: Int64;

function IsCanonicalToolName(const AName: string): Boolean;
var
  LCharacter: Char;
begin
  Result := False;
  if (Length(AName) = 0) or (Length(AName) > 96) then
    Exit;
  if not CharInSet(AName[1], ['a'..'z']) then
    Exit;
  for LCharacter in AName do
    if not CharInSet(LCharacter, ['a'..'z', '0'..'9', '_']) then
      Exit;
  Result := True;
end;

function UsageMutexName: string;
var
  LToken: THandle;
  LRequired: DWORD;
  LUser: TBytes;
  LSid: LPWSTR;
begin
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, LToken) then
    RaiseLastOSError;
  try
    LRequired := 0;
    GetTokenInformation(LToken, TokenUser, nil, 0, LRequired);
    if LRequired = 0 then
      RaiseLastOSError;
    SetLength(LUser, LRequired);
    if not GetTokenInformation(LToken, TokenUser, @LUser[0], LRequired, LRequired) then
      RaiseLastOSError;
    LSid := nil;
    if not ConvertSidToStringSidW(PTokenUser(@LUser[0])^.User.Sid, LSid) then
      RaiseLastOSError;
    try
      Result := 'Global\DelphiAI.DAI.Usage.' + string(LSid);
    finally
      LocalFree(HLOCAL(LSid));
    end;
  finally
    CloseHandle(LToken);
  end;
end;

procedure UpdateActivity;
var
  LTick: Int64;
  LPrevious: Int64;
  LObserved: Int64;
begin
  LTick := Int64(GetTickCount64);
  LPrevious := TInterlocked.Read(GLastActivityTick);
  while LTick > LPrevious do
  begin
    LObserved := TInterlocked.CompareExchange(GLastActivityTick, LTick, LPrevious);
    if LObserved = LPrevious then
      Exit;
    LPrevious := LObserved;
  end;
end;

procedure IncrementMonthlyCounter(const AName: string; const ALocalDate: TDateTime);
var
  LMutex: THandle;
  LWait: DWORD;
  LKey: HKEY;
  LPath: string;
  LYear: Word;
  LMonth: Word;
  LDay: Word;
  LType: DWORD;
  LSize: DWORD;
  LValue: UInt64;
  LError: Longint;
begin
  DecodeDate(ALocalDate, LYear, LMonth, LDay);
  LPath := CDAIUsageRegistryRoot + '\' + Format('%.4d_%.2d', [LYear, LMonth]);
  LMutex := CreateMutex(nil, False, PChar(UsageMutexName));
  if LMutex = 0 then
    RaiseLastOSError;
  try
    LWait := WaitForSingleObject(LMutex, 100);
    if (LWait <> WAIT_OBJECT_0) and (LWait <> WAIT_ABANDONED) then
    begin
      OutputDebugString('DAI: monthly usage counter skipped because its mutex is unavailable.');
      Exit;
    end;
    try
      LKey := 0;
      LError := RegCreateKeyEx(HKEY_CURRENT_USER, PChar(LPath), 0, nil, REG_OPTION_NON_VOLATILE,
        KEY_QUERY_VALUE or KEY_SET_VALUE or KEY_WOW64_64KEY, nil, LKey, nil);
      if LError <> ERROR_SUCCESS then
        RaiseLastOSError(LError);
      try
        LValue := 0;
        LType := REG_NONE;
        LSize := SizeOf(LValue);
        LError := RegQueryValueEx(LKey, PChar(AName), nil, @LType, PByte(@LValue), @LSize);
        if LError <> ERROR_FILE_NOT_FOUND then
        begin
          if LError <> ERROR_SUCCESS then
            RaiseLastOSError(LError);
          // Keep unexpected registry data intact. Valid counters saturate at the signed 64-bit maximum.
          if (LType <> REG_QWORD) or (LSize <> SizeOf(LValue)) or (LValue > UInt64(High(Int64))) then
          begin
            OutputDebugString('DAI: monthly usage counter has an unsupported registry value.');
            Exit;
          end;
        end;
        if LValue < UInt64(High(Int64)) then
          Inc(LValue);
        LError := RegSetValueEx(LKey, PChar(AName), 0, REG_QWORD, PByte(@LValue), SizeOf(LValue));
        if LError <> ERROR_SUCCESS then
          RaiseLastOSError(LError);
      finally
        RegCloseKey(LKey);
      end;
    finally
      ReleaseMutex(LMutex);
    end;
  finally
    CloseHandle(LMutex);
  end;
end;

procedure RecordToolCallAt(const ACanonicalToolName: string; const AShowsActivity: Boolean; const ALocalDate: TDateTime);
begin
  if not IsCanonicalToolName(ACanonicalToolName) then
    Exit;
  if AShowsActivity then
    UpdateActivity;
  try
    IncrementMonthlyCounter(ACanonicalToolName, ALocalDate);
  except
    // Statistics must never change the outcome of an IDE or launcher operation.
    on E: Exception do
      OutputDebugString(PChar('DAI: monthly usage counter skipped: ' + E.Message));
  end;
end;

class procedure TDAIUsage.RecordToolCall(const ACanonicalToolName: string; const AShowsActivity: Boolean);
begin
  RecordToolCallAt(ACanonicalToolName, AShowsActivity, Now);
end;

class function TDAIUsage.LastActivityTick: UInt64;
begin
  Result := UInt64(TInterlocked.Read(GLastActivityTick));
end;

class procedure TDAIUsage.ResetActivity;
begin
  TInterlocked.Exchange(GLastActivityTick, Int64(0));
end;

{$IFDEF DAI_USAGE_TESTS}
class procedure TDAIUsage.TestRecordToolCallAt(const ACanonicalToolName: string; const AShowsActivity: Boolean; const ALocalDate: TDateTime);
begin
  RecordToolCallAt(ACanonicalToolName, AShowsActivity, ALocalDate);
end;

class function TDAIUsage.TestMutexName: string;
begin
  Result := UsageMutexName;
end;
{$ENDIF}

end.
