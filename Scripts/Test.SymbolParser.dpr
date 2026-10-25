program Test.SymbolParser;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Symbols.Parser;

var
  GChecks: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(GChecks);
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function Find(const AItems: TJSONArray; const AName: string): TJSONObject;
var
  LItem: TJSONValue;
  LObject: TJSONObject;
begin
  Result := nil;
  for LItem in AItems do
    if LItem is TJSONObject then
    begin
      LObject := LItem as TJSONObject;
      if LObject.GetValue<string>('qualified_name') = AName then
        Exit(LObject);
    end;
end;

function Require(const AItems: TJSONArray; const AName: string): TJSONObject;
begin
  Result := Find(AItems, AName);
  Check(Result <> nil, 'Missing symbol: ' + AName);
end;

procedure CheckMembers;
const
  CSource = 'unit Demo;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TBox<T: class; U: constructor> = class(TObject)'#13#10 +
    '  strict private'#13#10 +
    '    FValue: Integer;'#13#10 +
    '  strict protected'#13#10 +
    '    procedure SetValue(const AValue: Integer); virtual;'#13#10 +
    '  public'#13#10 +
    '    class function CreatePair(const A: T; B: U): TBox<T, U>; static;'#13#10 +
    '    property Value: Integer read FValue write SetValue stored False default 0;'#13#10 +
    '    property Items[Index: Integer]: T read GetItem; default;'#13#10 +
    '  published'#13#10 +
    '    property Caption: string read FCaption write FCaption;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'var Hidden: Integer;'#13#10 +
    'end.';
var
  LItems: TJSONArray;
  LClass: TJSONObject;
  LText: string;
begin
  LItems := TDAISymbolParser.Parse(CSource);
  try
    Check(LItems.Count = 1, 'Class member declarations must not become global symbols');
    LClass := Require(LItems, 'Demo.TBox');
    Check(LClass.GetValue<string>('kind') = 'class', 'Class kind');
    Check(LClass.GetValue<Integer>('start_line') = 4, 'Class start line');
    Check(LClass.GetValue<Integer>('end_line') = 15, 'Class end line');
    Check(LClass.GetValue<string>('ancestor') = 'TObject', 'Class ancestor');
    Check(Pos('FValue: Integer;', LClass.GetValue<string>('members_private')) > 0, 'Strict private field');
    Check(Pos('SetValue(const AValue: Integer); virtual;', LClass.GetValue<string>('members_protected')) > 0, 'Protected method');
    LText := LClass.GetValue<string>('members_public');
    Check(Pos('class function CreatePair(const A: T; B: U): TBox<T, U>; static;', LText) > 0, 'Class function signature');
    Check(Pos('property Value: Integer;', LText) > 0, 'Simplified property');
    Check(Pos('property Items[Index: Integer]: T;', LText) > 0, 'Indexed property');
    Check(Pos(' read ', LText) = 0, 'Property getter omitted');
    Check(Pos(' write ', LText) = 0, 'Property setter omitted');
    Check(Pos('stored', LText) = 0, 'Property storage omitted');
    Check(Pos('property Caption: string;', LClass.GetValue<string>('members_published')) > 0, 'Published property');
    Check(Find(LItems, 'Demo.Hidden') = nil, 'Implementation variable excluded');
  finally
    LItems.Free;
  end;
end;

procedure CheckDeclarations;
const
  CSource = 'unit Demo.Nested;'#10 +
    'interface'#10 +
    'uses System.Classes;'#10 +
    'type'#10 +
    '  TForward = class;'#10 +
    '  TMeta = class of TObject;'#10 +
    '  TCallback = procedure(const S: string) of object;'#10 +
    '  TEnum = (One, Two);'#10 +
    '  TAlias = TArray<TPair<string, Integer>>;'#10 +
    '  IExample = interface(IInterface)'#10 +
    '    [''{11111111-2222-3333-4444-555555555555}'']'#10 +
    '    function GetValue: Integer;'#10 +
    '  end;'#10 +
    '  TOuter = class'#10 +
    '  public type'#10 +
    '    TInner = record'#10 +
    '      X: Integer;'#10 +
    '    end;'#10 +
    '    TAlias = string;'#10 +
    '  public'#10 +
    '    procedure Test;'#10 +
    '  end;'#10 +
    'var Alpha, Beta: Integer;'#10 +
    'threadvar ThreadValue: Pointer;'#10 +
    'const Answer = 42;'#10 +
    'resourcestring Hello = ''hello; implementation end'';'#10 +
    'function PublicFunc(const A: Integer; const B: string = ''a; b''): Boolean; overload;'#10 +
    'procedure PublicProc; stdcall;'#10 +
    'implementation'#10 +
    'function PublicFunc(const A: Integer; const B: string): Boolean;'#10 +
    'var LocalValue: Integer;'#10 +
    'begin end;'#10 +
    'end.';
var
  LItems: TJSONArray;
  LItem: TJSONObject;
begin
  LItems := TDAISymbolParser.Parse(CSource);
  try
    Check(LItems.Count = 16, 'Expected 16 unique public declarations, got ' + IntToStr(LItems.Count));
    LItem := Require(LItems, 'Demo.Nested.TForward');
    Check(LItem.GetValue<string>('kind') = 'class', 'Forward class kind');
    LItem := Require(LItems, 'Demo.Nested.TMeta');
    Check(LItem.GetValue<string>('kind') = 'type', 'Class-of is type alias');
    Require(LItems, 'Demo.Nested.TCallback');
    Require(LItems, 'Demo.Nested.TEnum');
    Require(LItems, 'Demo.Nested.TAlias');
    LItem := Require(LItems, 'Demo.Nested.IExample');
    Check(LItem.GetValue<string>('ancestor') = 'IInterface', 'Interface inheritance');
    Check(Pos('GetValue', LItem.GetValue<string>('members_public')) > 0, 'Interface method');
    Require(LItems, 'Demo.Nested.TOuter');
    LItem := Require(LItems, 'Demo.Nested.TOuter.TInner');
    Check(Pos('X: Integer', LItem.GetValue<string>('members_public')) > 0, 'Nested record fields');
    Require(LItems, 'Demo.Nested.TOuter.TAlias');
    Require(LItems, 'Demo.Nested.Alpha');
    Require(LItems, 'Demo.Nested.Beta');
    Require(LItems, 'Demo.Nested.ThreadValue');
    Require(LItems, 'Demo.Nested.Answer');
    Require(LItems, 'Demo.Nested.Hello');
    LItem := Require(LItems, 'Demo.Nested.PublicFunc');
    Check(Pos('overload;', LItem.GetValue<string>('signature')) > 0, 'Routine directive retained');
    Require(LItems, 'Demo.Nested.PublicProc');
    Check(Find(LItems, 'Demo.Nested.LocalValue') = nil, 'Implementation locals excluded');
  finally
    LItems.Free;
  end;
end;

procedure CheckRecordsAndHelpers;
const
  CSource = 'unit Test;'#13 +
    'interface'#13 +
    'type'#13 +
    '  TData = packed record'#13 +
    '  private'#13 +
    '    FTag: Integer;'#13 +
    '  public'#13 +
    '    class operator Add(const A, B: TData): TData;'#13 +
    '    case Byte of'#13 +
    '      0: (X, Y: Integer);'#13 +
    '      1: (Values: array[0..1] of Integer);'#13 +
    '  end;'#13 +
    '  THelp = record helper for TData'#13 +
    '    procedure Reset;'#13 +
    '  end;'#13 +
    '  TObjHelp = class helper for System.TObject'#13 +
    '    function Name: string;'#13 +
    '  end;'#13 +
    '  TContainer = record'#13 +
    '    Inner: record'#13 +
    '      A: Integer;'#13 +
    '    end;'#13 +
    '    Other: Integer;'#13 +
    '  end;'#13 +
    'implementation'#13 +
    'end.';
var
  LItems: TJSONArray;
  LItem: TJSONObject;
  LText: string;
begin
  LItems := TDAISymbolParser.Parse(CSource);
  try
    Check(LItems.Count = 4, 'Records and helpers count');
    LItem := Require(LItems, 'Test.TData');
    Check(LItem.GetValue<Integer>('end_line') = 12, 'Variant record end');
    LText := LItem.GetValue<string>('members_public');
    Check(Pos('class operator Add', LText) > 0, 'Class operator signature');
    Check(Pos('X, Y: Integer', LText) > 0, 'Variant fields');
    Check(Pos('Values: array[0..1] of Integer', LText) > 0, 'Second variant fields');
    LItem := Require(LItems, 'Test.THelp');
    Check(LItem.GetValue<string>('ancestor') = 'TData', 'Record helper target');
    Check(Pos('Reset', LItem.GetValue<string>('members_public')) > 0, 'Record helper method');
    LItem := Require(LItems, 'Test.TObjHelp');
    Check(LItem.GetValue<string>('ancestor') = 'System.TObject', 'Class helper target');
    LItem := Require(LItems, 'Test.TContainer');
    LText := LItem.GetValue<string>('members_public');
    Check(Pos('Inner: record A: Integer; end;', LText) > 0, 'Anonymous record field');
    Check(Pos('Other: Integer', LText) > 0, 'Field after anonymous record');
  finally
    LItems.Free;
  end;
end;

procedure CheckLexicalBoundaries;
var
  LItems: TJSONArray;
  LItem: TJSONObject;
  LSource: string;
begin
  LSource := #$FEFF + 'unit Lexical;'#10 +
    'interface'#10 +
    '{ type TFake = class end; }'#10 +
    '(* outer { mixed } type TFake2 = record end; *)'#10 +
    '// type TFake3 = Integer;'#10 +
    '{$IFDEF NEVER_DEFINED}'#10 +
    'type TConditional = Integer;'#10 +
    '{$ENDIF}'#10 +
    'const Quoted = ''it''''s a string: end; implementation'';'#10 +
    '  Quote = '''';'#10 +
    '  Multi = ' + StringOfChar('''', 3) + #10 +
    '    type TNotAType = class end;'#10 +
    '    implementation'#10 +
    '    ' + StringOfChar('''', 3) + ';'#10 +
    'type [SomeAttribute(''end'')] TMarked = record'#10 +
    '  [Another] FValue: Integer;'#10 +
    '  property &Read: Integer read FValue;'#10 +
    'end;'#10 +
    'implementation'#10 +
    'end.';
  LItems := TDAISymbolParser.Parse(LSource);
  try
    Check(LItems.Count = 5, 'Lexical boundaries count: ' + LItems.ToJSON);
    Require(LItems, 'Lexical.TConditional');
    Require(LItems, 'Lexical.Quoted');
    Require(LItems, 'Lexical.Quote');
    Require(LItems, 'Lexical.Multi');
    LItem := Require(LItems, 'Lexical.TMarked');
    Check(LItem.GetValue<Integer>('start_line') = 15, 'Comments, multiline literal and BOM line accounting');
    Check(Pos('property &Read: Integer;', LItem.GetValue<string>('members_public')) > 0, 'Escaped property name');
    Check(Find(LItems, 'Lexical.TNotAType') = nil, 'Multiline string content excluded');
  finally
    LItems.Free;
  end;
end;

procedure CheckMalformedAndSnippets;
const
  CCases: array[0..8] of string = ('', 'type', 'type T = class', 'type T = class end;', 'unit U; interface type T =',
    'unit U; interface type T = array[0..1] of record X: Integer; end; implementation end.',
    'unit U; interface type T<T: class; U> = class private type X = string; public procedure P; end;',
    'unit U; interface (* unterminated', 'const A = ''unterminated');
var
  LCase: string;
  LItems: TJSONArray;
  LItem: TJSONObject;
begin
  for LCase in CCases do
  begin
    LItems := TDAISymbolParser.Parse(LCase);
    try
      Check(LItems <> nil, 'Malformed source returns owned array');
    finally
      LItems.Free;
    end;
  end;
  LItems := TDAISymbolParser.Parse('type TItem = record Value: Integer; end; var X: Integer;');
  try
    Require(LItems, 'TItem');
    Require(LItems, 'X');
  finally
    LItems.Free;
  end;
  LItems := TDAISymbolParser.Parse('program Test; var Global: Integer; procedure P; var Local: Integer; begin Local := 1; end; begin end.');
  try
    Require(LItems, 'Test.Global');
    LItem := Require(LItems, 'Test.P');
    Check(LItem.GetValue<string>('kind') = 'procedure', 'Program routine');
    Check(Find(LItems, 'Test.Local') = nil, 'Program routine local excluded');
  finally
    LItems.Free;
  end;
end;

procedure CheckComparisonsAndNestedMethods;
const
  CSource = 'unit Cases; interface'#10 +
    'const Less = 1 < 2;'#10 +
    '  OtherLess = LeftValue < RightValue;'#10 +
    '  Greater = 3 > 2;'#10 +
    'type TClass = class public type TAlias = string;'#10 +
    '  procedure AfterNestedType; overload;'#10 +
    '  class function Make: TClass; static;'#10 +
    'end;'#10 +
    'type TProc = procedure(const Value: Integer) of object;'#10 +
    '  TOther = record Value: Integer; end;'#10 +
    'procedure GenericMethod<T: class; U: constructor>(const A: T; B: U);'#10 +
    'implementation end.';
var
  LItems: TJSONArray;
  LItem: TJSONObject;
  LText: string;
begin
  LItems := TDAISymbolParser.Parse(CSource);
  try
    Check(LItems.Count = 8, 'Comparisons and nested sections declaration count');
    Require(LItems, 'Cases.Less');
    Require(LItems, 'Cases.OtherLess');
    Require(LItems, 'Cases.Greater');
    Require(LItems, 'Cases.TProc');
    Require(LItems, 'Cases.TOther');
    LItem := Require(LItems, 'Cases.TClass');
    LText := LItem.GetValue<string>('members_public');
    Check(Pos('procedure AfterNestedType; overload;', LText) > 0, 'Method following nested type section');
    Check(Pos('class function Make: TClass; static;', LText) > 0, 'Class method following nested type section');
    Require(LItems, 'Cases.TClass.TAlias');
    Require(LItems, 'Cases.GenericMethod<T: class; U: constructor>');
  finally
    LItems.Free;
  end;
end;

procedure CheckProductionUnits;
var
  LSourceDirectory: string;
  LFile: string;
  LItems: TJSONArray;
  LValue: TJSONValue;
  LObject: TJSONObject;
  LCount: Integer;
  LFileCount: Integer;
  LStarted: UInt64;
begin
  LSourceDirectory := ParamStr(1);
  if LSourceDirectory = '' then
    Exit;
  LCount := 0;
  LFileCount := 0;
  LStarted := GetTickCount64;
  for LFile in TDirectory.GetFiles(LSourceDirectory, '*.pas') do
  begin
    LItems := TDAISymbolParser.Parse(TFile.ReadAllText(LFile));
    try
      Inc(LFileCount);
      Inc(LCount, LItems.Count);
      for LValue in LItems do
      begin
        LObject := LValue as TJSONObject;
        Check(LObject.GetValue<string>('name') <> '', 'Production symbol name: ' + LFile);
        Check(LObject.GetValue<Integer>('start_line') > 0, 'Production source line');
        Check(LObject.GetValue<Integer>('end_line') >= LObject.GetValue<Integer>('start_line'), 'Production source range');
      end;
    finally
      LItems.Free;
    end;
  end;
  Check(LFileCount > 30, 'Production source corpus found');
  Check(LCount > 100, 'Production source declarations found');
  Writeln('Production: ', LFileCount, ' units, ', LCount, ' symbols, ', GetTickCount64 - LStarted, ' ms');
end;

begin
  try
    CheckMembers;
    CheckDeclarations;
    CheckRecordsAndHelpers;
    CheckLexicalBoundaries;
    CheckMalformedAndSnippets;
    CheckComparisonsAndNestedMethods;
    CheckProductionUnits;
    Writeln('Symbol parser checks passed: ', GChecks);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
