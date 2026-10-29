program TestEditorChanges;
{$APPTYPE CONSOLE}

// Test.EditorChanges.ps1 extracts the production methods without rewriting them.
// Doubles enforce original UTF-8 byte offsets and commit on writer release. The
// undo stack is a simulation of that transaction, not a test of a running IDE.

uses
  System.Generics.Collections,
  System.SysUtils,
  h5u.DAI.Text.Changes,
  h5u.DAI.Text.Encoding;

type
  TOTACharPos = record
    Line, CharIndex: Integer;
  end;
  TOTAEditPos = record
    Line, Col: Integer;
  end;
  IOTAEditView = interface ['{66D8D413-9D17-47B9-9BC4-6D7550437D1E}']
    procedure SetCursorPos(const AValue: TOTAEditPos);
    procedure MoveViewToCursor;
    function PosToCharPos(APosition: Longint): TOTACharPos;
    procedure ConvertPos(AEdPosToCharPos: Boolean; var AEditPos: TOTAEditPos; var ACharPos: TOTACharPos);
    property CursorPos: TOTAEditPos write SetCursorPos;
  end;
  IOTAEditBuffer = interface ['{EB6465CE-D901-43C4-AB69-240A7400B9AA}']
    function GetTopView: IOTAEditView;
    property TopView: IOTAEditView read GetTopView;
  end;
  IOTAEditReader = interface ['{26EB0E4F-F97B-11D1-AB27-00C04FB16FB3}']
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
  IOTAEditWriter = interface ['{26EB0E50-F97B-11D1-AB27-00C04FB16FB3}']
    procedure CopyTo(Pos: Longint);
    procedure DeleteTo(Pos: Longint);
    procedure Insert(Text: PAnsiChar);
  end;
  IOTASourceEditor = interface ['{4D460588-10A6-4CAD-87E7-5654266073F9}']
    function CreateReader: IOTAEditReader;
    function CreateUndoableWriter: IOTAEditWriter;
    function GetEditViewCount: Integer;
    function GetEditView(AIndex: Integer): IOTAEditView;
    property EditViewCount: Integer read GetEditViewCount;
    property EditViews[AIndex: Integer]: IOTAEditView read GetEditView;
  end;
  TDAIOTA = class
    class function ReadEditorText(const ASourceEditor: IOTASourceEditor): string; static;
    class function ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string): Boolean; overload; static;
    class function ReplaceEditorText(const ASourceEditor: IOTASourceEditor; const AText: string; out AActualText: string): Boolean; overload; static;
  end;

{$I DAI.EditorChanges.Constants.inc}
{$I DAI.EditorChanges.Methods.inc}

type
  TFakeSource = class;
  TFakeView = class(TInterfacedObject, IOTAEditView)
  private
    FSource: TFakeSource;
  public
    PosCount, ConvertCount, SetCount, ScrollCount, LastByteOffset: Integer;
    Cursor: TOTAEditPos;
    constructor Create(ASource: TFakeSource);
    procedure SetCursorPos(const AValue: TOTAEditPos);
    procedure MoveViewToCursor;
    function PosToCharPos(APosition: Longint): TOTACharPos;
    procedure ConvertPos(AEdPosToCharPos: Boolean; var AEditPos: TOTAEditPos; var ACharPos: TOTACharPos);
  end;
  TByteRange = record
    FirstByte, EndByte: Integer;
  end;
  TFakeReader = class(TInterfacedObject, IOTAEditReader)
  private
    FSource: TFakeSource;
    FBytes: UTF8String;
  public
    constructor Create(ASource: TFakeSource);
    destructor Destroy; override;
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
  TFakeWriter = class(TInterfacedObject, IOTAEditWriter)
  private
    FSource: TFakeSource;
    FOriginal, FWritten: UTF8String;
    FCursor: Integer;
    procedure RequirePosition(APosition: Integer);
  public
    constructor Create(ASource: TFakeSource);
    destructor Destroy; override;
    procedure CopyTo(Pos: Longint);
    procedure DeleteTo(Pos: Longint);
    procedure Insert(Text: PAnsiChar);
  end;
  TFakeSource = class(TInterfacedObject, IOTASourceEditor)
  public
    Content: UTF8String;
    ReaderCount, ReadersAlive, WriterCount, Commits, InsertCount, DeletedBytes: Integer;
    WriterAlive, DenyWriter, HasViews: Boolean;
    ViewCountReads, ViewFetches, TopViewReads: Integer;
    ExpectedAnchorByte: Integer;
    FallbackView: IOTAEditView;
    RawFallback, ExpectedView: TFakeView;
    CursorPhases: TList<Integer>;
    UndoStack: TList<UTF8String>;
    DeletedRanges: TList<TByteRange>;
    constructor Create(const AText: string);
    destructor Destroy; override;
    function CreateReader: IOTAEditReader;
    function CreateUndoableWriter: IOTAEditWriter;
    procedure Undo;
    function GetEditViewCount: Integer;
    function GetEditView(AIndex: Integer): IOTAEditView;
  end;
  TFakeBufferSource = class(TFakeSource, IOTAEditBuffer)
  public
    Top: IOTAEditView;
    function GetTopView: IOTAEditView;
  end;

var
  GChecks: Integer;

procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    raise Exception.Create('FAIL: ' + AName);
  Inc(GChecks);
end;

function IsSafeBoundary(const ABytes: UTF8String; APosition: Integer): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= Length(ABytes));
  if not Result then
    Exit;
  if (APosition > 0) and (APosition < Length(ABytes)) then
  begin
    Result := (Byte(ABytes[APosition + 1]) and $C0) <> $80;
    if Result then
      Result := not ((ABytes[APosition] = #13) and (ABytes[APosition + 1] = #10));
  end;
end;

constructor TFakeSource.Create(const AText: string);
begin
  inherited Create;
  Content := UTF8Encode(AText);
  HasViews := True;
  ExpectedAnchorByte := -1;
  RawFallback := TFakeView.Create(Self);
  FallbackView := RawFallback;
  ExpectedView := RawFallback;
  CursorPhases := TList<Integer>.Create;
  UndoStack := TList<UTF8String>.Create;
  DeletedRanges := TList<TByteRange>.Create;
end;

destructor TFakeSource.Destroy;
begin
  DeletedRanges.Free;
  CursorPhases.Free;
  UndoStack.Free;
  inherited;
end;

function TFakeSource.CreateReader: IOTAEditReader;
begin
  Check(not WriterAlive, 'writer released before readback');
  if (Commits > 0) and Assigned(ExpectedView) then
  begin
    Check((CursorPhases.Count > 0) and (CursorPhases.Last = Commits), 'readback follows post-commit cursor restoration');
    Check(ExpectedView.ScrollCount = ExpectedView.SetCount, 'readback follows visible post-commit cursor restoration');
  end;
  Result := TFakeReader.Create(Self);
end;

function TFakeSource.CreateUndoableWriter: IOTAEditWriter;
begin
  Check(ReadersAlive = 0, 'reader released before writer acquisition');
  Check(not WriterAlive, 'one writer active at a time');
  Check(RefCount = 1, 'temporary edit-buffer interface released before writer');
  if Assigned(ExpectedView) then
  begin
    Check(ExpectedView.SetCount > 0, 'cursor set before writer acquisition');
    Check(ExpectedView.ScrollCount = ExpectedView.SetCount, 'cursor made visible before writer acquisition');
    Check(CursorPhases.Last = Commits, 'pre-writer cursor move belongs to the current committed buffer');
    Check(ExpectedView.PosCount = ExpectedView.SetCount, 'each cursor move converts one original byte offset');
    Check(ExpectedView.ConvertCount = ExpectedView.SetCount, 'native tab/character conversion precedes each cursor move');
    Check(ExpectedView.RefCount = 1, 'temporary edit-view interface released before writer');
    if ExpectedAnchorByte >= 0 then
      Check(ExpectedView.LastByteOffset = ExpectedAnchorByte, 'writer captures first original changed byte');
  end;
  if DenyWriter then
    Exit(nil);
  Inc(WriterCount);
  Result := TFakeWriter.Create(Self);
end;

function TFakeSource.GetEditViewCount: Integer;
begin
  Inc(ViewCountReads);
  if HasViews then Result := 1 else Result := 0;
end;

function TFakeSource.GetEditView(AIndex: Integer): IOTAEditView;
begin
  Check(HasViews and (AIndex = 0), 'source view lookup uses the first available fallback only');
  Inc(ViewFetches);
  Result := FallbackView;
end;

function TFakeBufferSource.GetTopView: IOTAEditView;
begin
  Inc(TopViewReads);
  Result := Top;
end;

constructor TFakeView.Create(ASource: TFakeSource);
begin
  inherited Create;
  FSource := ASource;
  Cursor.Line := 9999;
  Cursor.Col := 9999;
end;

function TFakeView.PosToCharPos(APosition: Longint): TOTACharPos;
begin
  Check(not FSource.WriterAlive, 'cursor byte conversion occurs outside an active writer');
  Check(IsSafeBoundary(FSource.Content, APosition), 'cursor anchor uses an unchanged UTF-8/CRLF prefix boundary');
  LastByteOffset := APosition;
  Inc(PosCount);
  // Deliberately unlike byte offsets. Production must use both native conversions,
  // rather than assume any UTF-8, UTF-16 or tab-expanded column relationship.
  Result.Line := APosition + 101;
  Result.CharIndex := 7;
end;

procedure TFakeView.ConvertPos(AEdPosToCharPos: Boolean; var AEditPos: TOTAEditPos; var ACharPos: TOTACharPos);
begin
  Check(not FSource.WriterAlive, 'visual cursor conversion occurs outside an active writer');
  Check(not AEdPosToCharPos, 'cursor conversion direction is native character-to-edit position');
  Check((ACharPos.Line = LastByteOffset + 101) and (ACharPos.CharIndex = 7), 'native character position passed through unchanged');
  Inc(ConvertCount);
  AEditPos.Line := ACharPos.Line + 3;
  AEditPos.Col := ACharPos.CharIndex + 5;
end;

procedure TFakeView.SetCursorPos(const AValue: TOTAEditPos);
begin
  Check(not FSource.WriterAlive, 'cursor move occurs before writer acquisition or after writer release');
  Check((AValue.Line = LastByteOffset + 104) and (AValue.Col = 12), 'cursor uses converted visual position');
  Cursor := AValue;
  Inc(SetCount);
  FSource.CursorPhases.Add(FSource.Commits);
end;

procedure TFakeView.MoveViewToCursor;
begin
  Check(not FSource.WriterAlive, 'view scroll occurs outside an active writer');
  Check(SetCount = ScrollCount + 1, 'each view scroll immediately follows its cursor move');
  Check((FSource.CursorPhases.Count > 0) and (FSource.CursorPhases.Last = FSource.Commits),
    'view scroll uses the cursor position of the current commit phase');
  Inc(ScrollCount);
end;

procedure TFakeSource.Undo;
begin
  Check(UndoStack.Count > 0, 'simulated undo transaction is available');
  Content := UndoStack.Last;
  UndoStack.Delete(UndoStack.Count - 1);
end;

constructor TFakeReader.Create(ASource: TFakeSource);
begin
  inherited Create;
  FSource := ASource;
  FBytes := ASource.Content;
  Inc(FSource.ReaderCount);
  Inc(FSource.ReadersAlive);
end;

destructor TFakeReader.Destroy;
begin
  Dec(FSource.ReadersAlive);
  inherited;
end;

function TFakeReader.GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
begin
  Check((Position >= 0) and (Count >= 0), 'reader offsets are nonnegative');
  Result := Length(FBytes) - Position;
  if Result < 0 then
    Result := 0;
  if Result > Count then
    Result := Count;
  if Result > 0 then
    Move(FBytes[Position + 1], Buffer^, Result);
end;

constructor TFakeWriter.Create(ASource: TFakeSource);
begin
  inherited Create;
  FSource := ASource;
  FOriginal := ASource.Content;
  FSource.WriterAlive := True;
end;

destructor TFakeWriter.Destroy;
begin
  // Unconsumed original bytes survive automatically, like IOTAEditWriter.
  FWritten := FWritten + Copy(FOriginal, FCursor + 1, MaxInt);
  FSource.UndoStack.Add(FOriginal);
  FSource.Content := FWritten;
  FSource.WriterAlive := False;
  Inc(FSource.Commits);
  inherited;
end;

procedure TFakeWriter.RequirePosition(APosition: Integer);
begin
  Check((APosition >= FCursor) and (APosition <= Length(FOriginal)), 'writer uses monotonic ORIGINAL byte offsets');
  Check(IsSafeBoundary(FOriginal, APosition), 'writer original offsets preserve UTF-8 and CRLF boundaries');
end;

procedure TFakeWriter.CopyTo(Pos: Longint);
begin
  RequirePosition(Pos);
  FWritten := FWritten + Copy(FOriginal, FCursor + 1, Pos - FCursor);
  FCursor := Pos;
end;

procedure TFakeWriter.DeleteTo(Pos: Longint);
var
  LRange: TByteRange;
begin
  RequirePosition(Pos);
  if Pos > FCursor then
  begin
    LRange.FirstByte := FCursor;
    LRange.EndByte := Pos;
    FSource.DeletedRanges.Add(LRange);
  end;
  Inc(FSource.DeletedBytes, Pos - FCursor);
  FCursor := Pos;
end;

procedure TFakeWriter.Insert(Text: PAnsiChar);
var
  LText: UTF8String;
begin
  LText := UTF8String(Text);
  Check(UTF8Encode(UTF8ToString(LText)) = LText, 'writer inserts complete UTF-8 code points');
  FWritten := FWritten + LText;
  Inc(FSource.InsertCount);
end;

function VerifyDiff(const AOldText, ANewText, AName: string): TArray<TDAITextChange>;
var
  LOldBytes, LNewBytes, LResult: UTF8String;
  LChange: TDAITextChange;
  LCursor: Integer;
begin
  LOldBytes := UTF8Encode(AOldText);
  LNewBytes := UTF8Encode(ANewText);
  Result := TDAITextChanges.Between(AOldText, ANewText);
  LCursor := 0;
  LResult := '';
  for LChange in Result do
  begin
    Check((LChange.StartByte >= LCursor) and (LChange.EndByte >= LChange.StartByte), AName + ': nonoverlapping ascending ranges');
    Check(IsSafeBoundary(LOldBytes, LChange.StartByte) and IsSafeBoundary(LOldBytes, LChange.EndByte), AName + ': safe old byte boundaries');
    Check(UTF8Encode(UTF8ToString(LChange.NewTextUtf8)) = LChange.NewTextUtf8, AName + ': valid inserted UTF-8');
    LResult := LResult + Copy(LOldBytes, LCursor + 1, LChange.StartByte - LCursor);
    Check(IsSafeBoundary(LNewBytes, Length(LResult)), AName + ': safe new start boundary');
    LResult := LResult + LChange.NewTextUtf8;
    Check(IsSafeBoundary(LNewBytes, Length(LResult)), AName + ': safe new end boundary');
    LCursor := LChange.EndByte;
  end;
  LResult := LResult + Copy(LOldBytes, LCursor + 1, MaxInt);
  Check(LResult = LNewBytes, AName + ': diff reconstructs requested bytes');
end;

procedure RunCase(const AOldText, ANewText, AName: string; AExpectedMaxDeleted: Integer = -1; AExpectedChanges: Integer = -1);
var
  LSource: TFakeSource;
  LEditor: IOTASourceEditor;
  LActualText: string;
  LChanges: TArray<TDAITextChange>;
begin
  LChanges := VerifyDiff(AOldText, ANewText, AName);
  if AExpectedChanges >= 0 then
    Check(Length(LChanges) = AExpectedChanges, AName + ': expected localized change count');
  LSource := TFakeSource.Create(AOldText);
  if Length(LChanges) > 0 then
    LSource.ExpectedAnchorByte := LChanges[0].StartByte;
  LEditor := LSource;
  LSource.UndoStack.Add(UTF8Encode('pre-existing user history'));
  try
    Check(TDAIOTA.ReplaceEditorText(LEditor, ANewText, LActualText), AName + ': production editor update succeeds');
    Check(LActualText = ANewText, AName + ': full readback matches');
    Check(UTF8ToString(LSource.Content) = ANewText, AName + ': committed editor bytes match');
    Check((LSource.ReadersAlive = 0) and not LSource.WriterAlive, AName + ': all native handles released');
    if AOldText = ANewText then
    begin
      Check(LSource.WriterCount = 0, AName + ': no-op creates no writer');
      Check((LSource.RawFallback.SetCount = 0) and (LSource.RawFallback.ScrollCount = 0) and
        (LSource.CursorPhases.Count = 0) and (LSource.ViewCountReads = 0) and
        (LSource.ViewFetches = 0), AName + ': no-op neither moves nor queries editor views');
      Check((LSource.Commits = 0) and (LSource.UndoStack.Count = 1), AName + ': no-op preserves undo stack');
    end
    else
    begin
      Check((LSource.WriterCount = 1) and (LSource.Commits = 1), AName + ': all hunks use one undoable writer');
      Check(LSource.UndoStack.Count = 2, AName + ': existing undo history preserved');
      Check((LSource.CursorPhases.Count = 2) and (LSource.CursorPhases[0] = 0) and (LSource.CursorPhases[1] = 1),
        AName + ': cursor anchors both before writer acquisition and after commit');
      Check(LSource.RawFallback.ScrollCount = 2, AName + ': view follows the anchor both before and after writing');
      if AExpectedMaxDeleted >= 0 then
        Check(LSource.DeletedBytes <= AExpectedMaxDeleted, AName + ': unchanged bytes not deleted');
      LSource.Undo;
      Check(UTF8ToString(LSource.Content) = AOldText, AName + ': transaction snapshot restores all old bytes');
      LSource.Undo;
      Check(UTF8ToString(LSource.Content) = 'pre-existing user history', AName + ': earlier undo history remains available');
    end;
  finally
    LEditor := nil;
  end;
end;

procedure TestCursorViewPaths;
var
  LSource: TFakeSource;
  LBuffer: TFakeBufferSource;
  LEditor: IOTASourceEditor;
  LTop: TFakeView;
  LActual: string;
begin
  LSource := TFakeSource.Create('prefix value');
  LSource.HasViews := False;
  LSource.ExpectedView := nil;
  LEditor := LSource;
  try
    Check(TDAIOTA.ReplaceEditorText(LEditor, 'prefix changed', LActual), 'source without buffer support or views remains writable');
    Check((LSource.RawFallback.SetCount = 0) and (LSource.RawFallback.ScrollCount = 0) and (LSource.ViewFetches = 0),
      'no view creates no cursor or scrolling side effect');
    Check(LSource.WriterCount = 1, 'no-view write retains the undoable writer');
  finally
    LEditor := nil;
  end;

  LBuffer := TFakeBufferSource.Create('original');
  LTop := TFakeView.Create(LBuffer);
  LBuffer.Top := LTop;
  LBuffer.ExpectedView := LTop;
  LBuffer.ExpectedAnchorByte := 0;
  LEditor := LBuffer;
  try
    Check(TDAIOTA.ReplaceEditorText(LEditor, 'changed', LActual), 'buffer top view update succeeds');
    Check((LBuffer.TopViewReads = 2) and (LTop.SetCount = 2) and (LTop.ScrollCount = 2),
      'buffer top view is visibly anchored before and after writing');
    Check((LBuffer.CursorPhases.Count = 2) and (LBuffer.CursorPhases[0] = 0) and (LBuffer.CursorPhases[1] = 1),
      'buffer top view cursor events bracket the writer commit');
    Check((LBuffer.ViewFetches = 0) and (LBuffer.RawFallback.SetCount = 0) and (LBuffer.RawFallback.ScrollCount = 0),
      'buffer top view never moves or scrolls the fallback view');
  finally
    LEditor := nil;
  end;

  LBuffer := TFakeBufferSource.Create('original');
  LEditor := LBuffer;
  try
    Check(TDAIOTA.ReplaceEditorText(LEditor, 'changed', LActual), 'nil buffer top view falls back successfully');
    Check((LBuffer.TopViewReads = 2) and (LBuffer.ViewFetches = 2) and (LBuffer.RawFallback.SetCount = 2),
      'nil buffer top view selects the first source view');
  finally
    LEditor := nil;
  end;

  LBuffer := TFakeBufferSource.Create('original');
  LBuffer.HasViews := False;
  LBuffer.ExpectedView := nil;
  LEditor := LBuffer;
  try
    Check(TDAIOTA.ReplaceEditorText(LEditor, 'changed', LActual), 'buffer with no views remains writable');
    Check((LBuffer.TopViewReads = 2) and (LBuffer.ViewFetches = 0) and (LBuffer.RawFallback.SetCount = 0),
      'buffer with no views neither queries a missing view nor moves a cursor');
  finally
    LEditor := nil;
  end;

  LBuffer := TFakeBufferSource.Create('same');
  LTop := TFakeView.Create(LBuffer);
  LBuffer.Top := LTop;
  LEditor := LBuffer;
  try
    Check(TDAIOTA.ReplaceEditorText(LEditor, 'same', LActual), 'buffer-backed no-op succeeds');
    Check((LBuffer.TopViewReads = 0) and (LTop.SetCount = 0) and (LTop.ScrollCount = 0) and
      (LBuffer.ViewFetches = 0) and (LBuffer.WriterCount = 0),
      'buffer-backed no-op preserves cursor and avoids all view access');
  finally
    LEditor := nil;
  end;
end;

procedure TestCursorOriginalByteAnchor;
const
  Prefix = 'line one' + #13#10 + #9 + 'ä😊漢' + #9 + 'value = ';
var
  LSource: TFakeSource;
  LEditor: IOTASourceEditor;
  LActual: string;
begin
  LSource := TFakeSource.Create(Prefix + '1;' + #13#10 + 'tail = 2;');
  LSource.ExpectedAnchorByte := Length(UTF8Encode(Prefix));
  LEditor := LSource;
  try
    Check(TDAIOTA.ReplaceEditorText(LEditor, Prefix + '3;' + #13#10 + 'tail = 4;', LActual),
      'UTF-8, tabs and separated hunks update succeeds');
    Check(LSource.RawFallback.LastByteOffset = Length(UTF8Encode(Prefix)), 'cursor receives exact first ORIGINAL UTF-8 byte offset');
    Check((LSource.RawFallback.PosCount = 2) and (LSource.RawFallback.ConvertCount = 2) and
      (LSource.RawFallback.SetCount = 2) and (LSource.RawFallback.ScrollCount = 2),
      'multiple hunks share one native cursor anchor visibly restored after writing');
    Check((LSource.CursorPhases.Count = 2) and (LSource.CursorPhases[0] = 0) and (LSource.CursorPhases[1] = 1),
      'original byte anchor is applied before creation and after commit');
    Check(LSource.UndoStack.Count = 1, 'cursor positioning does not add text undo records');
    LSource.Undo;
    Check(UTF8ToString(LSource.Content) = Prefix + '1;' + #13#10 + 'tail = 2;', 'cursor anchor preserves text undo snapshot');
  finally
    LEditor := nil;
  end;
end;

function RandomToken: string;
begin
  case Random(12) of
    0: Result := #13#10;
    1: Result := #10;
    2: Result := #13;
    3: Result := 'ä';
    4: Result := 'ß';
    5: Result := '😊';
    6: Result := '漢';
    7: Result := ' ';
    8: Result := '()';
    9: Result := '''';
    10: Result := 'ab';
  else
    Result := IntToStr(Random(100));
  end;
end;

procedure TestRandomRoundtrips;
var
  LIndex, LTokenIndex: Integer;
  LOld, LNew, LToken: string;
begin
  RandSeed := 207701;
  for LIndex := 1 to 500 do
  begin
    LOld := '';
    LNew := '';
    for LTokenIndex := 1 to Random(60) do
    begin
      LToken := RandomToken;
      LOld := LOld + LToken;
      case Random(9) of
        0: ;
        1: LNew := LNew + RandomToken;
        2: LNew := LNew + RandomToken + LToken;
      else
        LNew := LNew + LToken;
      end;
    end;
    if Random(2) = 0 then
      LNew := LNew + RandomToken;
    RunCase(LOld, LNew, 'seeded mixed UTF-8 roundtrip ' + IntToStr(LIndex));
  end;
end;

procedure TestFailureAndWrapper;
var
  LSource: TFakeSource;
  LEditor: IOTASourceEditor;
  LActual: string;
begin
  Check(not TDAIOTA.ReplaceEditorText(nil, 'new', LActual), 'missing editor rejected');
  LSource := TFakeSource.Create('original');
  LEditor := LSource;
  try
    Check(not TDAIOTA.ReplaceEditorText(LEditor, 'bad' + #0 + 'text', LActual), 'embedded NUL rejected before writer');
    Check((LSource.WriterCount = 0) and (LSource.Content = 'original'), 'invalid replacement leaves source untouched');
    Check(LSource.CursorPhases.Count = 0, 'invalid replacement never moves the cursor');
    LSource.DenyWriter := True;
    Check(not TDAIOTA.ReplaceEditorText(LEditor, 'changed', LActual), 'unavailable undoable writer reported');
    Check((LSource.Commits = 0) and (LSource.Content = 'original'), 'failed writer acquisition leaves source untouched');
    Check((LSource.CursorPhases.Count = 1) and (LSource.CursorPhases[0] = 0), 'failed acquisition has no post-commit cursor move');
    LSource.DenyWriter := False;
    Check(TDAIOTA.ReplaceEditorText(LEditor, 'changed'), 'Boolean-only overload uses production implementation');
    Check(LSource.Content = 'changed', 'Boolean-only overload updates source');
  finally
    LEditor := nil;
  end;
end;

procedure TestSeparatedChanges;
var
  LOld, LNew: string;
  LIndex: Integer;
begin
  LOld := 'first = 1;' + #13#10;
  for LIndex := 1 to 4000 do
    LOld := LOld + 'unchanged unique row ' + IntToStr(LIndex) + ' = ''ä😊'';' + #13#10;
  LOld := LOld + 'last = 2;' + #13#10;
  LNew := StringReplace(LOld, 'first = 1;', 'first = 3;', []);
  LNew := StringReplace(LNew, 'last = 2;', 'last = 4;', []);
  RunCase(LOld, LNew, 'separated edits preserve 4000 unchanged UTF-8 lines', 2, 2);
end;

procedure TestBoundedFallback;
var
  LOld, LNew: string;
  LIndex: Integer;
begin
  RunCase('prefix ' + StringOfChar('a', 70000) + ' suffix',
    'prefix ' + StringOfChar('b', 70000) + ' suffix', 'large single-line atom limit fallback');
  RunCase('A' + StringOfChar(#10, 140000) + 'B',
    'X' + StringOfChar(#10, 140000) + 'Y', 'large line-count limit fallback');
  LOld := '';
  LNew := '';
  for LIndex := 1 to 500 do
  begin
    LOld := LOld + 'old row ' + IntToStr(LIndex) + #13#10;
    LNew := LNew + 'new value ' + IntToStr(LIndex * 3) + #13#10;
  end;
  RunCase(LOld, LNew, 'large edit-distance limit fallback');
end;

begin
  try
    RunCase('', '', 'empty no-op', 0, 0);
    RunCase('same ä😊' + #13#10, 'same ä😊' + #13#10, 'nonempty no-op', 0, 0);
    RunCase('', 'unit New;' + #13#10, 'insert whole empty buffer', 0, 1);
    RunCase('remove ä😊' + #10, '', 'delete whole buffer', -1, 1);
    RunCase('abc', 'abXc', 'insert one byte', 0, 1);
    RunCase('abXc', 'abc', 'delete one byte', 1, 1);
    RunCase('abc', 'aXc', 'replace one byte', 1, 1);
    RunCase('abc', 'Xabc', 'insert at start', 0, 1);
    RunCase('abc', 'abcX', 'insert at end', 0, 1);
    RunCase('Grüße 😊 aus Delphi', 'Größe 😎 aus Delphi', 'shared UTF-8 lead bytes and surrogate pairs');
    RunCase('one' + #13#10 + 'two' + #13#10, 'one' + #13#10 + 'NEW' + #13#10 + 'two' + #13#10, 'insert CRLF line', 0, 1);
    RunCase('one' + #10 + 'two' + #10, 'one' + #10 + 'NEW' + #10 + 'two' + #10, 'insert LF line', 0, 1);
    RunCase('one' + #13#10 + 'two' + #13#10, 'one' + #10 + 'two' + #10, 'CRLF to LF conversion');
    RunCase('one' + #10 + 'two', 'one' + #13#10 + 'two', 'LF to CRLF conversion');
    RunCase('a' + #13#10, 'a' + #13, 'remove trailing LF without splitting CRLF');
    RunCase('a' + #13, 'a' + #13#10, 'complete trailing CRLF');
    RunCase(StringOfChar('x', 70000), StringOfChar('x', 70000) + 'ä😊', 'reader spans production chunk boundary', 0, 1);
    TestSeparatedChanges;
    TestBoundedFallback;
    TestRandomRoundtrips;
    TestFailureAndWrapper;
    TestCursorViewPaths;
    TestCursorOriginalByteAnchor;
    Writeln('PASS: ', GChecks, ' production diff/writer byte-offset, cursor anchor, readback and simulated undo checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
