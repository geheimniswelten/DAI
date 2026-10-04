program Test.CursorExpression;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.JSON, System.Hash, ToolsAPI,
  h5u.DAI.OTA.Helpers, h5u.DAI.Source.Expression, h5u.DAI.OTA.CursorExpression, DAI.CursorExpression.Fixture;

var
  Checks: Integer;
  Source: TSourceStub;
  View: TViewStub;
  Module: TModuleStub;
  IDE: TIDEStub;
  Block: TBlockStub;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then raise Exception.Create(AMessage);
end;

procedure Parse(const AMarked, AExpected: string);
var LText, LExpression, LReason: string;
  LCursor, LStart, LAfter: Integer;
  LSuccess: Boolean;
begin
  LCursor := Pos('|', AMarked) - 1;
  LText := AMarked;
  Delete(LText, LCursor + 1, 1);
  LSuccess := TDAISourceExpression.AtCursor(LText, LCursor, LStart, LAfter, LExpression, LReason);
  Check(LSuccess = (AExpected <> ''), 'availability: ' + AMarked + ' reason=' + LReason);
  Check(LExpression = AExpected, 'expression: ' + AMarked + ' actual=' + LExpression);
  if LSuccess then
    Check(Copy(LText, LStart + 1, LAfter - LStart) = AExpected, 'range: ' + AMarked);
end;

procedure Setup(const AText: string; const ACursor: Integer);
begin
  BorlandIDEServices := nil;
  IDE := TIDEStub.Create;
  BorlandIDEServices := IDE;
  Module := TModuleStub.Create;
  IDE.Module := Module;
  Source := TSourceStub.Create;
  Module.Editor := Source;
  Source.Name := 'C:\workspace\Unit1.pas';
  Source.SetText(AText);
  View := TViewStub.Create(Source);
  SetLength(Source.Views, 1);
  Source.Views[0] := View;
  IDE.View := View;
  View.SetCursorIndex(ACursor);
  Block := TBlockStub.Create;
  View.Selection := Block;
  WorkspaceAllowed := True;
  ReferenceAllowed := False;
end;

procedure ReadOK(const AExpected, AKind: string);
var LResult: TJSONObject;
begin
  LResult := TDAICursorExpressionService.Read(Source.Name);
  try
    Check(LResult.GetValue<Boolean>('available'), 'service available: ' + LResult.ToJSON);
    Check(LResult.GetValue<string>('expression') = AExpected, 'service expression');
    Check(LResult.GetValue<string>('source_kind') = AKind, 'service kind');
    Check(LResult.GetValue<string>('source_sha256') = THashSHA2.GetHashString(Source.Text), 'buffer hash');
  finally LResult.Free; end;
end;

procedure ReadNo(const AReason: string; const AExpectedFile: string = '');
var LResult: TJSONObject;
begin
  LResult := TDAICursorExpressionService.Read(AExpectedFile);
  try
    Check(not LResult.GetValue<Boolean>('available'), 'service unexpectedly available: ' + LResult.ToJSON);
    Check(LResult.GetValue<string>('reason_code') = AReason, 'reason expected=' + AReason + ' actual=' + LResult.ToJSON);
    Check(LResult.GetValue('expression') is TJSONNull, 'no expression on failure');
  finally LResult.Free; end;
end;

procedure PureTests;
var LExpression, LReason, LText: string;
  LStart, LAfter, LIndex: Integer;
begin
  Parse('|Self.Tag', 'Self.Tag');
  Parse('Sel|f.Tag', 'Self.Tag');
  Parse('Self|.Tag', 'Self.Tag');
  Parse('Self.|Tag', 'Self.Tag');
  Parse('Self.Tag|', 'Self.Tag');
  Parse('if Self.T|ag then', 'Self.Tag');
  Parse('obj.Field[|index]', 'obj.Field[index]');
  Parse('obj.F|ield[0].Value^', 'obj.Field[0].Value^');
  Parse('obj.Field[$|FF]', 'obj.Field[$FF]');
  Parse('obj.Field[-|1]', 'obj.Field[-1]');
  Parse('arrayValue[i,|j]', 'arrayValue[i,j]');
  Parse('arrayValue[indices[|0]]', 'arrayValue[indices[0]]');
  Parse('Po|inter^', 'Pointer^');
  Parse('P^.|Field', 'P^.Field');
  Parse('obj . |Field', 'obj . Field');
  Parse('&type.|&end', '&type.&end');
  Parse('Größe.|Wert', 'Größe.Wert');
  Parse('{x}' + #9 + 'Self.|Tag', 'Self.Tag');
  Parse('obj.Field[1|.5]', '');
  Parse('obj.Field[inde|x + 1]', '');
  Parse('obj.Field[|GetIndex()]', '');
  Parse('ob|j.GetValue()', '');
  Parse('TObj|ect(obj).Tag', '');
  Parse('TObject(obj).T|ag', '');
  Parse('@|Pointer', '');
  Parse('Self.|', '');
  Parse('a.|.b', '');
  Parse('true|', '');
  Parse('beg|in', '');
  Parse('// Self.|Tag', '');
  Parse('{ Self.|Tag }', '');
  Parse('(* Self.|Tag *)', '');
  Parse('''Self.|Tag''', '');
  Parse('Self {x}.|Tag', '');
  Parse('{a' + #13#10 + 'Self.|Tag' + #13#10 + '}', '');
  Parse('(*a' + #13#10 + 'Self.|Tag' + #13#10 + '*)', '');
  Parse('''''''' + #13#10 + 'Self.|Tag' + #13#10 + '''''''', '');
  Parse('(* {nested} Self.|Tag *)', '');
  Parse('( |', '');
  Check(not TDAISourceExpression.AtCursor('', -1, LStart, LAfter, LExpression, LReason), 'negative cursor');
  Check(not TDAISourceExpression.AtCursor('x', 2, LStart, LAfter, LExpression, LReason), 'past EOF');
  LText := #$D801 + #$DC00 + '.Value';
  Check(TDAISourceExpression.AtCursor(LText, 3, LStart, LAfter, LExpression, LReason), 'supplementary letter');
  Check(LExpression = LText, 'complete supplementary identifier');
  Check(not TDAISourceExpression.AtCursor(LText, 1, LStart, LAfter, LExpression, LReason), 'split surrogate cursor');
  Check(not TDAISourceExpression.ValidUnicode(#$D800), 'lone high surrogate');
  Check(not TDAISourceExpression.ValidUnicode(#$DC00), 'lone low surrogate');
  Check(not TDAISourceExpression.ValidUnicode('x' + #0), 'embedded NUL');
  LText := StringOfChar('a', 4097);
  Check(not TDAISourceExpression.AtCursor(LText, 2, LStart, LAfter, LExpression, LReason), 'expression bound');
  Check(LReason = 'expression_too_long', 'expression bound reason');
  LText := StringOfChar(' ', 65537) + 'x';
  Check(not TDAISourceExpression.AtCursor(LText, Length(LText), LStart, LAfter, LExpression, LReason), 'line bound');
  Check(LReason = 'line_too_long', 'line bound reason');
  // A full line of punctuation must stay bounded and safe under complete Boolean evaluation.
  LText := StringOfChar('.', 65536);
  Check(not TDAISourceExpression.AtCursor(LText, 32000, LStart, LAfter, LExpression, LReason), 'many tokens');
  for LIndex := 0 to Length('obj.Field[index]^') do
    Check(TDAISourceExpression.AtCursor('obj.Field[index]^', LIndex, LStart, LAfter, LExpression, LReason), 'chain caret consistency');
end;

procedure ServiceTests;
var LResult: TJSONObject;
  LIndex, LExpectedStart: Integer;
  LOtherView: IOTAEditView;
begin
  BorlandIDEServices := nil;
  Check(TDAICursorExpressionService.CurrentFileName = '', 'no editor metadata');
  ReadNo('editor_unavailable');
  Setup('Self.Tag', 6);
  Check(TDAICursorExpressionService.CurrentFileName = Source.Name, 'actual source metadata');
  Check(Source.ReadersCreated = 0, 'metadata reads no source text');
  ReadOK('Self.Tag', 'cursor');
  ReadNo('editor_changed', 'C:\workspace\Other.pas');
  Check(Source.ReadersCreated = 1, 'expected file mismatch does not create reader');
  Source.ReaderMutation := procedure begin View.SetCursorIndex(0); end;
  ReadNo('editor_changed');
  Source.ReaderMutation := nil;
  Module.Editor := TPlainEditorStub.Create;
  Check(TDAICursorExpressionService.CurrentFileName = '', 'designer is no source cursor');
  ReadNo('source_editor_not_active');
  Setup('Self.Tag', 5);
  IDE.View := nil;
  ReadNo('editor_unavailable');
  IDE.View := View;
  Source.Views[0] := nil;
  ReadNo('editor_unavailable');
  SetLength(Source.Views, 2);
  Source.Views[1] := View;
  ReadOK('Self.Tag', 'cursor');
  LOtherView := TViewStub.Create(Source);
  IDE.View := LOtherView;
  ReadNo('editor_unavailable');
  IDE.View := View;
  Source.ReaderMissing := True;
  ReadNo('reader_unavailable');
  Source.ReaderMissing := False;
  Source.ReaderBadCount := True;
  ReadNo('reader_invalid_result');
  Setup('X', 0);
  Source.Bytes := TBytes.Create($C0, $AF);
  ReadNo('invalid_utf8');
  Source.Bytes := TBytes.Create($ED, $A0, $80);
  ReadNo('invalid_utf8');
  Source.Bytes := TBytes.Create($F4, $90, $80, $80);
  ReadNo('invalid_utf8');
  Source.Bytes := TBytes.Create($E2, $82);
  ReadNo('invalid_utf8');
  Source.Bytes := TBytes.Create(Ord('X'), 0, Ord('Y'));
  ReadNo('invalid_utf8');
  Setup('Self.Tag', 4);
  SetLength(Source.Bytes, Length(Source.Bytes) + 1);
  Source.Bytes[High(Source.Bytes)] := 0;
  ReadOK('Self.Tag', 'cursor');
  Setup('Self.Tag', 4);
  View.Cursor.Col := 100;
  ReadNo('virtual_cursor');
  Check(Source.ReadersCreated = 0, 'virtual cursor causes no read');
  Setup('{é' + #$D83D + #$DE00 + '}' + #9 + 'Self.Tag', 0);
  LIndex := Pos('Tag', Source.Text) - 1;
  View.SetCursorIndex(LIndex);
  ReadOK('Self.Tag', 'cursor');
  LExpectedStart := TEncoding.UTF8.GetByteCount(Copy(Source.Text, 1, Pos('Self', Source.Text) - 1));
  LResult := TDAICursorExpressionService.Read;
  try
    Check(LResult.GetValue<Integer>('expression_start') = LExpectedStart, 'UTF8 range after Unicode and tab');
    Check(LResult.GetValue<Integer>('expression_end') = LExpectedStart + 8, 'UTF8 exclusive range');
    Check(LResult.GetValue<Integer>('column') > LIndex, 'SDK expanded tab column preserved');
  finally LResult.Free; end;
  Setup('Größe.Wert', 4);
  View.OffsetOverride := 3; // Inside the UTF-8 encoding of ö.
  ReadNo('invalid_cursor');
  Setup('Self.Tag', 6);
  Source.Name := 'C:\workspace\Unit1.txt';
  ReadNo('unsupported_language');
  Source.Name := 'C:\workspace\Unit1.pas';
  WorkspaceAllowed := False;
  ReadNo('access_denied');
  ReferenceAllowed := True;
  ReadOK('Self.Tag', 'cursor');
  Setup('  a + b  ', 2);
  Block.IsVisible := True;
  Block.IsValid := True;
  Block.BlockText := Source.Text;
  Source.SelectionStart := 0;
  Source.SelectionAfter := Length(Source.Text);
  ReadOK('a + b', 'selection');
  Block.BlockStyle := btColumn;
  ReadNo('unsupported_selection');
  Block.BlockStyle := btInclusive;
  Block.EndRow := 2;
  ReadNo('unsupported_selection');
  Block.EndRow := 1;
  Block.BlockText := 'a' + #13#10 + 'b';
  ReadNo('unsupported_selection');
  Block.BlockText := ' ';
  ReadNo('empty_selection');
  Block.BlockText := StringOfChar('x', 4097);
  ReadNo('expression_too_long');
  Block.BlockText := #$D800;
  ReadNo('invalid_unicode');
  Setup('Self.Tag', 5);
  Block.IsValid := True;
  Block.IsVisible := False;
  Block.BlockText := 'Other.Value';
  ReadOK('Self.Tag', 'cursor');
  Setup(StringOfChar(' ', 16 * 1024 * 1024 + 1), 0);
  ReadNo('source_too_large');
  Setup(StringOfChar(' ', 65537), 0);
  ReadNo('line_too_long');
  BorlandIDEServices := nil;
end;

begin
  try
    PureTests;
    ServiceTests;
    Writeln('PASS: ', Checks, ' cursor expression checks');
  except
    on E: Exception do
    begin
      Writeln('FAIL after ', Checks, ' checks: ', E.Message);
      Halt(1);
    end;
  end;
end.
