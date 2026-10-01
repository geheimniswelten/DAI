program TestEditorWrite;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Hash,
  System.JSON,
  System.SysUtils,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Text.Encoding;

var
  CheckCount: Integer;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure CheckMatch(const ARequested, AActual: string; AExpected: Boolean; const ADescription: string);
begin
  Check(TDAITextEncoding.EditorWriteMatches(ARequested, AActual) = AExpected, ADescription);
end;

procedure CheckResult(const AWriteResult: TJSONObject; const ADescription: string);
var
  ReadResult: TJSONObject;
begin
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0);
  try
    Check(AWriteResult.GetValue<string>('sha256') = ReadResult.GetValue<string>('sha256'), ADescription + ' hash matches readback');
    Check(AWriteResult.GetValue<string>('line_ending') = ReadResult.GetValue<string>('line_ending'), ADescription + ' line ending matches readback');
    Check(AWriteResult.GetValue<string>('target') = 'editor_buffer', ADescription + ' editor target');
  finally
    ReadResult.Free;
  end;
end;

procedure RunChecks;
const
  CUnicode = 'Grüße 漢字 ' + #$D83D#$DE00;
var
  ResultJson: TJSONObject;
  UsedEditor: Boolean;
  Hash: string;
  Denied: Boolean;
begin
  CheckMatch('', '', True, 'empty exact');
  CheckMatch('', #13#10, True, 'empty plus IDE CRLF');
  CheckMatch('unit Sample;', 'unit Sample;', True, 'exact source');
  CheckMatch('unit Sample;', 'unit Sample;' + #13#10, True, 'one extra IDE CRLF');
  CheckMatch(CUnicode, CUnicode, True, 'Unicode exact');
  CheckMatch(CUnicode, CUnicode + #13#10, True, 'Unicode plus IDE CRLF');
  CheckMatch('a' + #10, 'a' + #10, True, 'requested trailing LF exact');
  CheckMatch('a' + #10, 'a' + #10#13#10, True, 'requested LF preserved plus IDE CRLF');
  CheckMatch('a' + #13#10, 'a' + #13#10, True, 'requested trailing CRLF exact');
  CheckMatch('a' + #13#10, 'a' + #13#10#13#10, True, 'requested CRLF preserved plus one IDE CRLF');
  CheckMatch('a' + #13#10#13#10, 'a' + #13#10#13#10, True, 'requested empty trailing line preserved');
  CheckMatch('a', 'a' + #13#10#13#10, False, 'two extra CRLF denied');
  CheckMatch('a' + #13#10, 'a' + #13#10#13#10#13#10, False, 'two extra CRLF after existing terminator denied');
  CheckMatch('a' + #10, 'a', False, 'lost LF denied');
  CheckMatch('a' + #13#10#13#10, 'a' + #13#10, False, 'lost trailing empty line denied');
  CheckMatch('a', 'a' + #10, False, 'extra bare LF denied');
  CheckMatch('a', 'a' + #13, False, 'extra bare CR denied');
  CheckMatch('a ', 'a' + #13#10, False, 'lost trailing whitespace denied');
  CheckMatch('a' + #13#10 + 'b', 'a' + #13#10, False, 'lost content denied');
  CheckMatch('a' + #0 + 'b', 'a', False, 'NUL truncation denied');
  CheckMatch('a' + #0 + 'b', 'a' + #0 + 'b', False, 'NUL request unsupported by OTA insert');
  CheckMatch('a', 'a' + #0#13#10, False, 'unexpected NUL denied');

  TDAIOTA.Reset('original');
  TDAIOTA.AppendOnWrite := #13#10;
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CUnicode, '', False, UsedEditor);
  try
    Check(UsedEditor, 'writer reports editor buffer');
    Check(TDAIOTA.Buffer = CUnicode + #13#10, 'simulated IDE appended one CRLF');
    Check(not ResultJson.GetValue<Boolean>('saved'), 'unsaved editor response');
    Check(ResultJson.GetValue<string>('sha256') <> THashSHA2.GetHashString(CUnicode), 'returned hash includes actual CRLF');
    CheckResult(ResultJson, 'write without save');
    Hash := ResultJson.GetValue<string>('sha256');
  finally
    ResultJson.Free;
  end;
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', 'next', Hash, False, UsedEditor);
  try
    CheckResult(ResultJson, 'next write accepts previous returned hash');
  finally
    ResultJson.Free;
  end;

  TDAIOTA.Reset('original');
  TDAIOTA.AppendOnSave := #10;
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', 'saved', '', True, UsedEditor);
  try
    Check(TDAIOTA.SaveCount = 1, 'save called once');
    Check(TDAIOTA.Buffer = 'saved' + #10, 'save changed the buffer');
    Check(ResultJson.GetValue<Boolean>('saved'), 'saved response');
    CheckResult(ResultJson, 'readback after save');
  finally
    ResultJson.Free;
  end;

  TDAIOTA.Reset('original');
  Denied := False;
  try
    ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', 'a' + #0 + 'b', '', False, UsedEditor);
    ResultJson.Free;
  except
    on E: EInvalidOperation do
      Denied := True;
  end;
  Check(Denied and (TDAIOTA.WriteCount = 0) and (TDAIOTA.Buffer = 'original'), 'NUL rejected before any write');

  TDAIOTA.Reset('original');
  TDAIOTA.AppendOnWrite := #13#10#13#10;
  Denied := False;
  try
    ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', 'a', '', False, UsedEditor);
    ResultJson.Free;
  except
    on E: EInvalidOperation do
      Denied := True;
  end;
  Check(Denied, 'file_write rejects two extra CRLF');
end;

begin
  try
    RunChecks;
    Writeln('PASS: ', CheckCount, ' isolated native editor write checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
