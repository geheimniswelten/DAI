program TestIndentationTabs;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  h5u.DAI.Text.Encoding;

procedure Check(const AName, AFile, AInput, AStops, AExpected: string);
var
  LResult: string;
begin
  LResult := TDAITextEncoding.ExpandPascalIndentationTabs(AFile, AInput, AStops);
  if LResult <> AExpected then
    raise Exception.Create('Failed: ' + AName);
  if TDAITextEncoding.ExpandPascalIndentationTabs(AFile, LResult, AStops) <> LResult then
    raise Exception.Create('Not idempotent: ' + AName);
end;

var
  LInput, LExpected, LQuotes: string;
begin
  try
    Check('width 2', 'x.PAS', #9'unit X;'#13#10' '#9'x'#10#9#9'end.', '2',
      '  unit X;'#13#10'  x'#10'    end.');
    Check('width 4', 'x.dpr', ' '#9'x'#13#9'y', '4', '    x'#13'    y');
    Check('text after code', 'x.dpk', #9'//XML'#9'text', '2', '  //XML'#9'text');
    Check('XML doc', 'x.inc', #9'///'#9'text', '2', '  ///'#9'text');
    Check('brace comment', 'x.pas', '{'#10#9'inside'#10'}'#10#9'x', '2',
      '{'#10#9'inside'#10'}'#10'  x');
    Check('paren comment', 'x.pas', '(*'#13#9'inside'#13'*)'#13#9'x', '2',
      '(*'#13#9'inside'#13'*)'#13'  x');
    Check('quotes', 'x.pas', #9's := '#39'a'#39#39'b'#9'c'#39';'#10#9'x', '2',
      '  s := '#39'a'#39#39'b'#9'c'#39';'#10'  x');
    LQuotes := StringOfChar(#39, 3);
    LInput := 's := ' + LQuotes + #13#10#9'string'#13#10#9 + LQuotes + ';'#10#9'x';
    LExpected := 's := ' + LQuotes + #13#10#9'string'#13#10#9 + LQuotes + ';'#10'  x';
    Check('multiline literal', 'x.pas', LInput, '2', LExpected);
    Check('end of input tab', 'x.pas', #9, '2', '  ');
    Check('end of input quote', 'x.pas', #9#39, '2', '  '#39);
    Check('end of input comment opener', 'x.pas', #9'(', '2', '  (');
    Check('nested comments', 'x.pas', '{ (* }'#10#9'inside *) }'#10#9'x', '2',
      '{ (* }'#10#9'inside *) }'#10'  x');
    Check('nested reverse', 'x.pas', '(* { *)'#10#9'inside } *)'#10#9'x', '2',
      '(* { *)'#10#9'inside } *)'#10'  x');
    Check('unicode', 'x.pas', #9#$00E4#$4E2D, '2', '  '#$00E4#$4E2D);
    Check('invalid', 'x.pas', #9'x', '2,4,6', #9'x');
    Check('zero', 'x.pas', #9'x', '0', #9'x');
    Check('large width', 'x.pas', #9'x', '9999999999', #9'x');
    Check('non Pascal', 'x.txt', #9'x', '2', #9'x');
    LInput := StringOfChar('x', 16 * 1024 * 1024) + #9;
    Check('input limit', 'x.pas', LInput, '2', LInput);
    LInput := #9 + StringOfChar('x', 16 * 1024 * 1024 - 1);
    Check('output limit', 'x.pas', LInput, '2', LInput);
    Writeln('All indentation tests passed.');
  except
    on E: Exception do
    begin
      Writeln(E.Message);
      ExitCode := 1;
    end;
  end;
end.
