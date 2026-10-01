program TestSourceView;

{$APPTYPE CONSOLE}

uses
  System.Diagnostics,
  System.SysUtils,
  h5u.DAI.Source.View;

var
  CheckCount: Integer;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure ExpectCut(const AFileName, APrefix, AImplementation, ADescription: string);
var
  LContent: string;
  LOmitted: Boolean;
  LResult: string;
begin
  LContent := APrefix + AImplementation;
  LOmitted := False;
  LResult := TDAISourceView.InterfaceText(AFileName, LContent, LOmitted);
  Check(LOmitted, ADescription + ': implementation omitted');
  Check(LResult = APrefix, ADescription + ': exact original prefix');
  Check(Copy(LContent, 1, Length(LResult)) = LResult, ADescription + ': unchanged UTF-16 offsets');
end;

procedure ExpectUnchanged(const AFileName, AContent, ADescription: string);
var
  LOmitted: Boolean;
  LResult: string;
begin
  LOmitted := True;
  LResult := TDAISourceView.InterfaceText(AFileName, AContent, LOmitted);
  Check(not LOmitted, ADescription + ': omission flag reset');
  Check(LResult = AContent, ADescription + ': complete content retained');
end;

procedure TestRealSections;
begin
  ExpectCut('Test.pas', 'unit Test; interface ', 'implementation end.', 'Minimal unit');
  ExpectCut('TEST.PAS', 'UnIt TeSt; InTeRfAcE ', 'ImPlEmEnTaTiOn end.', 'Case-insensitive extension and keywords');
  ExpectCut('C:\Sources\Test.pas', 'unit Company.Product.Test;' + #13#10 + 'interface' + #13#10 + 'type TThing = class end;' + #13#10,
    'implementation' + #13#10 + 'end.', 'Qualified unit name and CRLF');
  ExpectCut('Test.pas', 'unit Test;' + #10 + 'interface' + #10 + 'type TThing = class end;' + #10, 'implementation' + #10 + 'end.', 'LF retained');
  ExpectCut('Test.pas', 'unit Test;' + #13 + 'interface' + #13, 'implementation' + #13 + 'end.', 'CR retained');
  ExpectCut('Test.pas', 'unit Test;' + #13#10 + 'interface' + #10 + 'const C = 1;' + #13 + '  ', 'implementation end.', 'Mixed endings and indentation retained');
  ExpectCut('Test.pas', #$FEFF + 'unit Test; interface ', 'implementation end.', 'Leading Unicode BOM retained');
  ExpectCut('Test.pas', #9 + #11 + #12 + 'unit Test; interface ', 'implementation end.', 'Leading whitespace retained');
  ExpectCut('Test.pas', 'unit Grüße; interface type TÄnderung = class end; ', 'implementation end.', 'Unicode unit and declaration');
  ExpectCut('Test.pas', 'unit Test; interface const Smile = ''' + #$D83D#$DE00 + '''; ', 'implementation end.', 'Supplementary UTF-16 preserved');
  ExpectCut('Test.pas', 'unit Test; interface const C = 1; ', 'implementation const Hidden = 2; end.', 'Same-line body fully omitted');
  ExpectCut('Test.pas', 'unit Test; interface ', 'implementation', 'Final token without newline');
  ExpectCut('Test.pas', 'unit &unit.Company.&interface; interface ', 'implementation end.', 'Escaped qualified unit identifiers');
  ExpectCut('Test.pas', 'unit Test deprecated ''use NewTest'' platform; interface ', 'implementation end.', 'Unit hint directives');
  ExpectCut('Test.pas', 'unit Test experimental library; interface ', 'implementation end.', 'Additional unit hints');
  ExpectCut('Test.pas', 'unit Test; interface type IThing = interface end; ', 'implementation end.', 'Interface type declaration is not section boundary');
end;

procedure TestIgnoredTokens;
begin
  ExpectCut('Test.pas', '// unit False; interface implementation' + #13#10 + 'unit Test; interface ', 'implementation end.', 'Line comment before unit');
  ExpectCut('Test.pas', '{unit False; interface implementation} unit Test; interface ', 'implementation end.', 'Brace comment before unit');
  ExpectCut('Test.pas', '(*unit False; interface implementation*) unit Test; interface ', 'implementation end.', 'Parenthesis comment before unit');
  ExpectCut('Test.pas', 'unit {implementation} Test (*interface*); {$IFDEF WIN32} {$ENDIF} interface ', 'implementation end.', 'Trivia in unit header');
  ExpectCut('Test.pas', 'unit Test; interface {implementation}' + #13#10, 'implementation end.', 'Brace comment in interface');
  ExpectCut('Test.pas', 'unit Test; interface (*implementation*)' + #10, 'implementation end.', 'Parenthesis comment in interface');
  ExpectCut('Test.pas', 'unit Test; interface //implementation' + #10, 'implementation end.', 'LF line comment in interface');
  ExpectCut('Test.pas', 'unit Test; interface //implementation' + #13, 'implementation end.', 'CR line comment in interface');
  ExpectCut('Test.pas', 'unit Test; interface //implementation' + #13#10, 'implementation end.', 'CRLF line comment in interface');
  ExpectCut('Test.pas', 'unit Test; interface { (*implementation*) } ', 'implementation end.', 'Mixed nested comment content');
  ExpectCut('Test.pas', 'unit Test; interface (* {implementation} *) ', 'implementation end.', 'Reverse mixed nested comment content');
  ExpectCut('Test.pas', '{$IFDEF implementation} unit Test; {$ENDIF} interface {$MESSAGE ''implementation''} ', 'implementation end.', 'Compiler directives ignored');
  ExpectCut('Test.pas', 'unit Test; interface const C = ''implementation''; ', 'implementation end.', 'Quoted keyword');
  ExpectCut('Test.pas', 'unit Test; interface const C = ''it''''s implementation''; ', 'implementation end.', 'Doubled apostrophe');
  ExpectCut('Test.pas', 'unit Test; interface const C = ''''; ', 'implementation end.', 'Empty string');
  ExpectCut('Test.pas', 'unit Test; interface const C = ' + StringOfChar('''', 4) + '; ', 'implementation end.', 'Apostrophe string');
  ExpectCut('Test.pas', 'unit Test; interface const C = ''{implementation} (*implementation*) //implementation''; ', 'implementation end.', 'Comment delimiters inside string');
  ExpectCut('Test.pas', 'unit Test; interface const C = ''implementation''#13''implementation''; ', 'implementation end.', 'Adjacent strings and character constants');
  ExpectCut('Test.pas', 'unit Test; interface const MyImplementation = 1; ImplementationDetail = 2; _implementation = 3; ',
    'implementation end.', 'Longer ASCII identifiers');
  ExpectCut('Test.pas', 'unit Test; interface const implementation2 = 1; Implementation_ = 2; ', 'implementation end.', 'Trailing digit and underscore');
  ExpectCut('Test.pas', 'unit Test; interface const Äimplementation = 1; implementationÄ = 2; implementation' + #$0301 + ' = 3; ',
    'implementation end.', 'Unicode identifiers and combining mark');
  ExpectCut('Test.pas', 'unit Test; interface const implementation' + #$D801#$DC28 + ' = 1; ', 'implementation end.', 'Supplementary identifier suffix');
  ExpectCut('Test.pas', 'unit Test; interface const &implementation = 1; &IMPLEMENTATION = 2; &interface = 3; ',
    'implementation end.', 'Escaped reserved identifiers');
  ExpectCut('Test.pas', 'unit Test; interface const C = 123implementation; ', 'implementation end.', 'Whole numeric word is not keyword');
end;

procedure TestMultilineStrings;
var
  LPrefix: string;
begin
  LPrefix := 'unit Test; interface const C = ' + StringOfChar('''', 3) + #13#10 +
    '  SELECT ''implementation'' // {implementation}' + #13#10 + '  implementation' + #13#10 + '  ' + StringOfChar('''', 3) + ';' + #13#10;
  ExpectCut('Test.pas', LPrefix, 'implementation end.', 'Delphi multiline string with SQL quotes and keyword');
  LPrefix := 'unit Test; interface const C = ' + StringOfChar('''', 5) + #10 +
    '  ' + StringOfChar('''', 3) + #10 + '  implementation' + #10 + '  ' + StringOfChar('''', 5) + ';' + #10;
  ExpectCut('Test.pas', LPrefix, 'implementation end.', 'Five-quote multiline delimiter containing triple quotes');
  LPrefix := 'unit Test; interface const C = ' + StringOfChar('''', 7) + #10 +
    '  implementation '''' ''implementation''' + #10 + #9 + StringOfChar('''', 7) + ';' + #10;
  ExpectCut('Test.pas', LPrefix, 'implementation end.', 'Seven-quote multiline delimiter and tab indentation');
  LPrefix := 'unit Test; interface const C = ' + StringOfChar('''', 3) + #10 +
    'text ' + StringOfChar('''', 3) + ' implementation' + #10 + '  ' + StringOfChar('''', 3) + ';' + #10;
  ExpectCut('Test.pas', LPrefix, 'implementation end.', 'Multiline closing delimiter starts its own line');
  ExpectUnchanged('Test.pas', 'unit Test; interface const C = ' + StringOfChar('''', 3) + #10 +
    '''implementation''', 'Unterminated multiline string fails open');
  ExpectCut('Test.pas', 'unit Test; interface const C = ' + StringOfChar('''', 6) + '; ',
    'implementation end.', 'Even apostrophe count remains classic string');
  ExpectCut('Test.pas', 'unit Test; interface const C = ' + StringOfChar('''', 3) + 'implementation''; ',
    'implementation end.', 'Triple apostrophe without newline remains classic string');
end;

procedure TestUnchangedContent;
const
  UnitContent = 'unit Test; interface implementation end.';
var
  LExtension: string;
begin
  ExpectUnchanged('Test.pas', '', 'Empty source');
  ExpectUnchanged('Test.pas', 'unit Test; interface', 'Interface only');
  ExpectUnchanged('Test.pas', 'unit Test; interface const C = ''implementation'';', 'No actual implementation');
  ExpectUnchanged('Test.pas', 'unit Test; interface // implementation', 'Final line comment without newline');
  ExpectUnchanged('Test.pas', 'unit Test; interface { implementation', 'Unterminated brace comment');
  ExpectUnchanged('Test.pas', 'unit Test; interface (* implementation', 'Unterminated parenthesis comment');
  ExpectUnchanged('Test.pas', 'unit Test; interface const C = ''implementation', 'Unterminated quoted string');
  ExpectUnchanged('Test.pas', 'unit Test; interface const &implementation = 1;', 'Only escaped implementation');
  ExpectUnchanged('Test.pas', 'unit Test; implementation end.', 'No interface section');
  ExpectUnchanged('Test.pas', 'unit Test; &interface implementation', 'Escaped interface is not section');
  ExpectUnchanged('Test.pas', '&unit Test; interface implementation', 'Escaped unit is not header');
  ExpectUnchanged('Test.pas', 'unit Test interface implementation', 'No unit header semicolon');
  ExpectUnchanged('Test.pas', 'unit ; interface implementation', 'No unit name');
  ExpectUnchanged('Test.pas', 'unit Company.; interface implementation', 'Incomplete scoped unit name');
  ExpectUnchanged('Test.pas', 'unit 123; interface implementation', 'Numeric unit name');
  ExpectUnchanged('Test.pas', 'unit Test; type IFoo = interface; implementation', 'Type interface is not unit interface section');
  ExpectUnchanged('Test.pas', 'program Test; interface implementation end.', 'Program in PAS extension');
  ExpectUnchanged('Test.pas', 'library Test; interface implementation end.', 'Library in PAS extension');
  ExpectUnchanged('Test.pas', 'package Test; interface implementation end.', 'Package in PAS extension');
  ExpectUnchanged('Test.pas', '''unit Test; interface implementation''', 'String containing a whole unit');
  ExpectUnchanged('Test.pas', '{unit Test; interface implementation}', 'Comment containing a whole unit');
  ExpectUnchanged('Test.pas', '// unit Test; interface implementation', 'Only a line comment');
  ExpectUnchanged('Test.pas', 'notunit Test; interface implementation', 'Longer unit-like identifier');
  ExpectUnchanged('Test.pas', 'unit Test; interface_extra implementation', 'Longer interface-like identifier');
  ExpectUnchanged('Test.pas', 'unit Test; interface const implementationExtra = 1;', 'Longer implementation without section');
  for LExtension in TArray<string>.Create('.inc', '.dpr', '.dpk', '.dfm', '.fmx', '.cpp', '.hpp', '.txt', '.pas.txt', '') do
    ExpectUnchanged('Test' + LExtension, UnitContent, 'Non-unit extension ' + LExtension);
end;

procedure TestLinearScan;
var
  LClock: TStopwatch;
  LPrefix: string;
begin
  LPrefix := 'unit Test; interface {' + StringOfChar('x', 2 * 1024 * 1024) + 'implementation}' + #13#10;
  LClock := TStopwatch.StartNew;
  ExpectCut('Test.pas', LPrefix, 'implementation end.', 'Bounded linear scan of a large comment');
  Check(LClock.ElapsedMilliseconds < 2000, 'Large source scan completes within two seconds');
end;

procedure ExpectCompleteUnit(const AFileName, AContent, ADescription: string);
var
  LOriginal: string;
begin
  LOriginal := AContent;
  TDAISourceView.RequireCompleteUnit(AFileName, AContent);
  Check(True, ADescription + ': complete source accepted');
  Check(AContent = LOriginal, ADescription + ': source not changed');
end;

procedure ExpectIncompleteUnit(const AContent, AReason, ADescription: string);
var
  LError: string;
  LOriginal: string;
  LRejected: Boolean;
begin
  LOriginal := AContent;
  LRejected := False;
  LError := '';
  try
    TDAISourceView.RequireCompleteUnit('Test.pas', AContent);
  except
    on E: EArgumentException do
    begin
      LRejected := True;
      LError := E.Message;
    end;
  end;
  Check(LRejected, ADescription + ': EArgumentException raised');
  Check(Pos(LowerCase(AReason), LowerCase(LError)) > 0, ADescription + ': specific rejection reason');
  Check(AContent = LOriginal, ADescription + ': rejected source not changed');
end;

procedure TestCompleteUnitGuard;
var
  LContent: string;
  LExtension: string;
begin
  ExpectCompleteUnit('Test.pas', 'unit Test; interface implementation end.', 'Minimal empty-interface unit');
  ExpectCompleteUnit('Test.PAS', #$FEFF + 'UnIt Company.Grüße; InTeRfAcE ImPlEmEnTaTiOn EnD.', 'Case and Unicode complete unit');
  ExpectCompleteUnit('Test.pas', 'unit &unit.Company.&interface; interface implementation end.', 'Escaped scoped unit name');
  ExpectCompleteUnit('Test.pas', 'unit Test deprecated ''implementation end.'' platform; interface implementation end.', 'Unit header hint messages');
  LContent := 'unit Test;' + #13#10 + 'interface' + #13#10 + 'procedure Foo;' + #13#10 + 'implementation' + #13#10 +
    'procedure Foo; begin end;' + #13#10 + 'initialization' + #13#10 + 'finalization' + #13#10 + 'end.' + #13#10;
  ExpectCompleteUnit('Test.pas', LContent, 'Unit declarations, routine, initialization and finalization');
  ExpectCompleteUnit('Test.pas', 'unit Test; interface const &implementation = 1; implementation const &end = 2; end.',
    'Escaped words do not fake required section or terminal keyword');
  ExpectCompleteUnit('Test.pas', 'unit Test; interface implementation const C = ''implementation end.''; end. {trailing implementation end.}',
    'Keywords in string and trailing brace comment ignored');
  ExpectCompleteUnit('Test.pas', 'unit Test; interface implementation end. (*trailing implementation end.*) //end.',
    'Trailing parenthesis and line comments ignored');
  ExpectCompleteUnit('Test.pas', '{$IFDEF WIN32} {$ENDIF} unit Test; interface implementation end {$MESSAGE ''end.''} . {$IFDEF WIN64} {$ENDIF}',
    'Compiler directives around required tokens are trivia');
  ExpectCompleteUnit('Test.pas', 'unit Test; interface implementation const C = ' + StringOfChar('''', 3) + #10 +
    '  ''implementation end.'' ' + #10 + '  ' + StringOfChar('''', 3) + ';' + #10 + 'end.', 'Multiline implementation string');

  ExpectIncompleteUnit('', 'Unit-Kopf', 'Empty PAS content');
  ExpectIncompleteUnit('program Test; interface implementation end.', 'Unit-Kopf', 'Program is not a PAS unit');
  ExpectIncompleteUnit('library Test; interface implementation end.', 'Unit-Kopf', 'Library is not a PAS unit');
  ExpectIncompleteUnit('package Test; interface implementation end.', 'Unit-Kopf', 'Package is not a PAS unit');
  ExpectIncompleteUnit('&unit Test; interface implementation end.', 'Unit-Kopf', 'Escaped unit keyword is not header');
  ExpectIncompleteUnit('notunit Test; interface implementation end.', 'Unit-Kopf', 'Longer unit identifier is not header');
  ExpectIncompleteUnit('{unit Test; interface implementation end.}', 'Unit-Kopf', 'Whole unit in comment is not source');
  ExpectIncompleteUnit('''unit Test; interface implementation end.''', 'Unit-Kopf', 'Whole unit in string is not source');
  ExpectIncompleteUnit('unit ; interface implementation end.', 'Unit-Name', 'Missing unit name');
  ExpectIncompleteUnit('unit Company.; interface implementation end.', 'Unit-Name', 'Incomplete scoped unit name');
  ExpectIncompleteUnit('unit 123; interface implementation end.', 'Unit-Name', 'Numeric unit name');
  ExpectIncompleteUnit('unit Test interface implementation end.', 'Semikolon', 'Unit header semicolon required');
  ExpectIncompleteUnit('unit Test; implementation end.', 'interface', 'Missing interface section');
  ExpectIncompleteUnit('unit Test; &interface implementation end.', 'interface', 'Escaped interface token');
  ExpectIncompleteUnit('unit Test; interface_detail implementation end.', 'interface', 'Longer interface-like identifier');
  ExpectIncompleteUnit('unit Test; type IFoo = interface end; implementation end.', 'interface', 'Type interface is not unit section');
  ExpectIncompleteUnit('unit Test; interface', 'implementation', 'Only an interface view');
  ExpectIncompleteUnit('unit Test; interface const C = ''implementation''; end.', 'implementation', 'Implementation only inside string');
  ExpectIncompleteUnit('unit Test; interface {implementation} (*implementation*) //implementation' + #10 + 'end.',
    'implementation', 'Implementation only inside comments');
  ExpectIncompleteUnit('unit Test; interface const &implementation = 1; end.', 'implementation', 'Implementation only as escaped identifier');
  ExpectIncompleteUnit('unit Test; interface const MyImplementation = 1; end.', 'implementation', 'Implementation only inside longer identifier');
  ExpectIncompleteUnit('unit Test; interface implementation', 'end.', 'No terminal tokens after implementation');
  ExpectIncompleteUnit('unit Test; interface implementation end', 'end.', 'Terminal dot required');
  ExpectIncompleteUnit('unit Test; interface implementation .', 'end.', 'Terminal end keyword required');
  ExpectIncompleteUnit('unit Test; interface implementation end;', 'end.', 'Semicolon does not complete unit');
  ExpectIncompleteUnit('unit Test; interface implementation &end.', 'end.', 'Escaped end does not complete unit');
  ExpectIncompleteUnit('unit Test; interface implementation weekend.', 'end.', 'Longer end identifier does not complete unit');
  ExpectIncompleteUnit('unit Test; interface implementation const C = ''end.'';', 'end.', 'Terminal end-dot only in string');
  ExpectIncompleteUnit('unit Test; interface implementation //end.', 'end.', 'Terminal end-dot only in line comment');
  ExpectIncompleteUnit('unit Test; interface implementation {end.}', 'end.', 'Terminal end-dot only in brace comment');
  ExpectIncompleteUnit('unit Test; interface implementation end. Foo', 'end.', 'Tokens after completed unit rejected');
  ExpectIncompleteUnit('unit Test; interface implementation end. ''trailing''', 'end.', 'Trailing string is not trivia');
  ExpectIncompleteUnit('unit Test; interface implementation end. &end', 'end.', 'Trailing escaped identifier is not trivia');
  ExpectIncompleteUnit('unit Test; interface implementation end. {unclosed', 'unterminiert', 'Unterminated trailing brace comment');
  ExpectIncompleteUnit('unit Test; interface implementation end. (*unclosed', 'unterminiert', 'Unterminated trailing parenthesis comment');
  ExpectIncompleteUnit('unit Test; interface implementation const C = ''end.', 'unterminiert', 'Unterminated implementation string');
  ExpectIncompleteUnit('unit Test; interface implementation const C = ' + StringOfChar('''', 3) + #10 + 'end.',
    'unterminiert', 'Unterminated implementation multiline string');

  for LExtension in TArray<string>.Create('.inc', '.dpr', '.dpk', '.dfm', '.fmx', '.cpp', '.hpp', '.txt', '.pas.txt', '') do
    ExpectCompleteUnit('Test' + LExtension, 'any non-unit content', 'Non-PAS content bypasses unit guard ' + LExtension);
end;

begin
  try
    TestRealSections;
    TestIgnoredTokens;
    TestMultilineStrings;
    TestUnchangedContent;
    TestLinearScan;
    TestCompleteUnitGuard;
    Writeln('PASS: ', CheckCount, ' native source interface view checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
