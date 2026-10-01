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
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0, False);
  try
    Check(AWriteResult.GetValue<string>('sha256') = ReadResult.GetValue<string>('sha256'), ADescription + ' hash matches readback');
    Check(AWriteResult.GetValue<string>('line_ending') = ReadResult.GetValue<string>('line_ending'), ADescription + ' line ending matches readback');
    Check(AWriteResult.GetValue<string>('target') = 'editor_buffer', ADescription + ' editor target');
  finally
    ReadResult.Free;
  end;
end;

procedure CheckInterfaceReads;
const
  CPublicText = 'unit IsolatedBuffer;' + #13#10 + 'interface' + #13#10 +
    'const PublicValue = ''implementation'';' + #13#10 + '{ implementation is a comment }' + #13#10;
  CCompleteText = CPublicText + 'ImPlEmEnTaTiOn' + #13#10 + 'const PrivateValue = 123;' + #13#10 + 'end.' + #13#10;
var
  ReadResult: TJSONObject;
  FullHash: string;
begin
  TDAIOTA.Reset(CCompleteText);
  FullHash := THashSHA2.GetHashString(CCompleteText);
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0);
  try
    Check(ReadResult.GetValue<string>('content') = CPublicText, 'default read excludes actual implementation only');
    Check(ReadResult.GetValue<Boolean>('interfaces_only'), 'default read interfaces_only true');
    Check(ReadResult.GetValue<Boolean>('implementation_omitted'), 'interface omission explicitly marked');
    Check(not ReadResult.GetValue<Boolean>('truncated'), 'omitted implementation is distinct from maximum-character limit');
    Check(not ReadResult.GetValue<Boolean>('content_complete'), 'interface read is not complete content');
    Check(ReadResult.GetValue<Integer>('original_characters') = Length(CCompleteText), 'original characters cover complete buffer');
    Check(ReadResult.GetValue<Integer>('view_characters') = Length(CPublicText), 'view characters cover interface before maximum limit');
    Check(ReadResult.GetValue<string>('sha256') = FullHash, 'interface read retains full content hash');
    Check(ReadResult.GetValue<string>('sha256_scope') = 'complete_content', 'full hash scope explicitly marked');
    Check(ReadResult.GetValue<string>('source') = 'editor_buffer', 'interface read retains source metadata');
    Check(TDAIOTA.Buffer = CCompleteText, 'interface read does not change editor buffer');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0, False);
  try
    Check(ReadResult.GetValue<string>('content') = CCompleteText, 'explicit false includes implementation');
    Check(not ReadResult.GetValue<Boolean>('interfaces_only'), 'explicit false mode marked');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'full read has no omission');
    Check(ReadResult.GetValue<Boolean>('content_complete'), 'full unlimited read complete');
    Check(ReadResult.GetValue<string>('sha256') = FullHash, 'full read and interface read share full hash');
    Check(ReadResult.GetValue<Integer>('view_characters') = Length(CCompleteText), 'full view length');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 10);
  try
    Check(ReadResult.GetValue<string>('content') = Copy(CPublicText, 1, 10), 'maximum characters applied after interface view');
    Check(ReadResult.GetValue<Boolean>('truncated'), 'limited view marked truncated');
    Check(ReadResult.GetValue<Boolean>('implementation_omitted'), 'limited view retains implementation omission');
    Check(not ReadResult.GetValue<Boolean>('content_complete'), 'limited interface view incomplete');
    Check(ReadResult.GetValue<Integer>('view_characters') = Length(CPublicText), 'view length before character limit');
    Check(ReadResult.GetValue<string>('sha256') = FullHash, 'limited interface view retains complete hash');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 10, False);
  try
    Check(ReadResult.GetValue<Boolean>('truncated'), 'full-source maximum limit still marked');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'full-source maximum limit is not interface omission');
    Check(not ReadResult.GetValue<Boolean>('content_complete'), 'limited full-source view incomplete');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.dfm', 0);
  try
    Check(ReadResult.GetValue<string>('content') = CCompleteText, 'non-PAS content unmodified');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'non-PAS has no implementation omission');
    Check(ReadResult.GetValue<Boolean>('content_complete'), 'non-PAS unlimited content complete');
  finally
    ReadResult.Free;
  end;
  TDAIOTA.Reset('unit Incomplete; interface' + #10 + 'const PublicValue = 1;');
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0);
  try
    Check(ReadResult.GetValue<string>('content') = TDAIOTA.Buffer, 'missing implementation retains complete content');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'missing implementation not marked omitted');
    Check(ReadResult.GetValue<Boolean>('content_complete'), 'missing implementation can be complete current buffer');
  finally
    ReadResult.Free;
  end;
end;

procedure CheckUnitWriteGuards;
const
  COriginal = 'unit IsolatedBuffer; interface implementation const Preserved = 1; end.';
  CInvalidContents: array[0..5] of string = (
    '',
    'unit IsolatedBuffer; interface const PublicValue = 1;',
    'unit IsolatedBuffer; implementation end.',
    'unit IsolatedBuffer; interface { implementation end. }',
    'unit IsolatedBuffer; interface const Fake = ''implementation end.'';',
    'unit IsolatedBuffer; interface implementation');
var
  Content: string;
  Denied: Boolean;
  ReadResult: TJSONObject;
  WriteResult: TJSONObject;
  UsedEditor: Boolean;
begin
  for Content in CInvalidContents do
  begin
    TDAIOTA.Reset(COriginal);
    Denied := False;
    try
      WriteResult := TDAIFileService.WriteFile('IsolatedBuffer.pas', Content, THashSHA2.GetHashString(COriginal), True, UsedEditor);
      WriteResult.Free;
    except
      on E: EArgumentException do
        Denied := True;
    end;
    Check(Denied, 'incomplete PAS unit rejected');
    Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0) and (TDAIOTA.Buffer = COriginal), 'PAS guard runs before writer/save');
  end;
  TDAIOTA.Reset(COriginal);
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0);
  try
    Denied := False;
    try
      WriteResult := TDAIFileService.WriteFile('IsolatedBuffer.pas', ReadResult.GetValue<string>('content'),
        ReadResult.GetValue<string>('sha256'), False, UsedEditor);
      WriteResult.Free;
    except
      on E: EArgumentException do
        Denied := True;
    end;
    Check(Denied, 'accidental write of interface view rejected despite valid full hash');
    Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.Buffer = COriginal), 'interface view write preserves implementation');
  finally
    ReadResult.Free;
  end;
end;

procedure RunChecks;
const
  CUnicode = 'unit IsolatedBuffer; interface { Grüße 漢字 ' + #$D83D#$DE00 + ' } implementation end.';
  CNextUnit = 'unit IsolatedBuffer; interface implementation { next } end.';
  CSavedUnit = 'unit IsolatedBuffer; interface implementation { saved } end.';
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
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CNextUnit, Hash, False, UsedEditor);
  try
    CheckResult(ResultJson, 'next write accepts previous returned hash');
  finally
    ResultJson.Free;
  end;

  TDAIOTA.Reset('original');
  TDAIOTA.AppendOnSave := #10;
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CSavedUnit, '', True, UsedEditor);
  try
    Check(TDAIOTA.SaveCount = 1, 'save called once');
    Check(TDAIOTA.Buffer = CSavedUnit + #10, 'save changed the buffer');
    Check(ResultJson.GetValue<Boolean>('saved'), 'saved response');
    CheckResult(ResultJson, 'readback after save');
  finally
    ResultJson.Free;
  end;

  TDAIOTA.Reset('original');
  Denied := False;
  try
    ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', 'unit IsolatedBuffer; interface implementation { a' + #0 + 'b } end.', '', False, UsedEditor);
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
    ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CNextUnit, '', False, UsedEditor);
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
    CheckInterfaceReads;
    CheckUnitWriteGuards;
    Writeln('PASS: ', CheckCount, ' isolated native editor write/read-view checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
