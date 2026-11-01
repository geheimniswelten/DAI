program TestProcess;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.IOUtils, System.SysUtils, Winapi.Windows,
  h5u.DAI.Process, h5u.DAI.Types;
var Checks: Integer;
procedure Check(const AValue: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not AValue then raise Exception.Create('FAIL: ' + AMessage);
end;
procedure Emit;
var
  LEncoding: TEncoding;
  LBytes, LPreamble: TBytes;
  LWritten: DWORD;
  LText: string;
  LCodePage: Cardinal;
begin
  LCodePage := StrToInt(ParamStr(2));
  if LCodePage = 0 then LCodePage := GetOEMCP;
  LText := 'Prüfung ÄÖÜ ß';
  if LCodePage = 932 then LText := '日本語の確認';
  LEncoding := TEncoding.GetEncoding(LCodePage);
  try
    if ParamStr(3) = 'bom' then
    begin
      LPreamble := LEncoding.GetPreamble;
      if Length(LPreamble) > 0 then
        if not WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), LPreamble[0], Length(LPreamble), LWritten, nil) then RaiseLastOSError;
    end;
    LBytes := LEncoding.GetBytes(LText);
    if not WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), LBytes[0], Length(LBytes), LWritten, nil) then RaiseLastOSError;
  finally LEncoding.Free; end;
end;
procedure CaptureCase(const AEmitted, ARequested, AExpected: Cardinal; const ABom: Boolean; const AText: string);
var LValue: TDAIProcessResult; LFlag: string;
begin
  LFlag := '';
  if ABom then LFlag := 'bom';
  LValue := TDAIProcess.Execute(ParamStr(0), ['--emit', IntToStr(AEmitted), LFlag], TPath.GetTempPath, 5000, ARequested);
  Check(LValue.Started and not LValue.TimedOut and (LValue.ExitCode = 0), 'real child process completes');
  Check(LValue.Output = AText, 'captured Unicode text has the expected characters');
  Check(LValue.OutputCodePage = AExpected, 'the response reports the actual output codepage');
end;
procedure CompilerCase(const ACompiler, AArgument: string);
var LValue: TDAIProcessResult;
begin
  LValue := TDAIProcess.Execute(ACompiler, [AArgument], TPath.GetTempPath, 10000);
  Check(LValue.Started and (LValue.ExitCode <> 0), 'real compiler rejects only the deliberately invalid argument');
  Check(Pos('Prüfung_ÄÖÜ', LValue.Output) > 0, 'real compiler diagnostics retain umlauts');
  Check(LValue.OutputCodePage = GetOEMCP, 'compiler output uses the OS OEM codepage');
end;
var LFailed: Boolean;
begin
  try
    if ParamStr(1) = '--emit' then begin Emit; Exit; end;
    CaptureCase(0, 0, GetOEMCP, False, 'Prüfung ÄÖÜ ß');
    CaptureCase(1252, 1252, 1252, False, 'Prüfung ÄÖÜ ß');
    CaptureCase(65001, 65001, 65001, False, 'Prüfung ÄÖÜ ß');
    CaptureCase(65001, 0, 65001, True, 'Prüfung ÄÖÜ ß');
    CaptureCase(1200, 0, 1200, True, 'Prüfung ÄÖÜ ß');
    CaptureCase(1201, 0, 1201, True, 'Prüfung ÄÖÜ ß');
    CaptureCase(932, 932, 932, False, '日本語の確認');
    LFailed := False;
    try TDAIProcess.Execute(ParamStr(0), [], TPath.GetTempPath, 5000, 65534);
    except on E: EArgumentException do LFailed := True; end;
    Check(LFailed, 'an invalid requested codepage is rejected before starting a process');
    if ParamCount >= 1 then CompilerCase(ParamStr(1), TPath.Combine(TPath.GetTempPath, 'DAI_Prüfung_ÄÖÜ_8C76_missing.dpr'));
    if ParamCount >= 2 then CompilerCase(ParamStr(2), '/DAI_Prüfung_ÄÖÜ_invalid_switch');
    Writeln('PASS: ', Checks, ' real process-output checks');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
