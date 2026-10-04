unit DAI.CursorExpression.Fixture;
interface
uses System.SysUtils, ToolsAPI;
type
  TSourceStub = class;
  TBlockStub = class(TInterfacedObject, IOTAEditBlock)
  public
    IsVisible, IsValid: Boolean;
    SizeOverride: Integer;
    StartRow, EndRow: Integer;
    BlockStyle: TOTABlockType;
    BlockText: string;
    constructor Create;
    function GetVisible: Boolean;
    function GetIsValid: Boolean;
    function GetSize: Integer;
    function GetStyle: TOTABlockType;
    function GetStartingRow: Integer;
    function GetEndingRow: Integer;
    function GetText: string;
  end;
  TViewStub = class(TInterfacedObject, IOTAEditView)
  public
    Source: TSourceStub;
    Cursor: TOTAEditPos;
    Selection: IOTAEditBlock;
    OffsetOverride: Integer;
    constructor Create(const ASource: TSourceStub);
    procedure SetCursorIndex(const AIndex: Integer);
    function GetCursorPos: TOTAEditPos;
    function GetBuffer: IOTAEditBuffer;
    function GetBlock: IOTAEditBlock;
    procedure ConvertPos(EdPosToCharPos: Boolean; var EditPos: TOTAEditPos; var CharPos: TOTACharPos);
    function CharPosToPos(CharPos: TOTACharPos): Longint;
    function SameView(const EditView: IOTAEditView): Boolean;
  end;
  TSourceStub = class(TInterfacedObject, IOTAEditor, IOTASourceEditor, IOTAEditBuffer)
  public
    Name, Text: string;
    Bytes: TBytes;
    Views: TArray<IOTAEditView>;
    SelectionStart, SelectionAfter: Integer;
    ReaderMissing, ReaderBadCount: Boolean;
    ReadersCreated: Integer;
    ReaderMutation: TProc;
    procedure SetText(const AText: string);
    function CharPosition(const AIndex: Integer): TOTACharPos;
    function LineStart(const ALine: Integer): Integer;
    function GetFileName: string;
    function CreateReader: IOTAEditReader;
    function GetEditViewCount: Integer;
    function GetEditView(Index: Integer): IOTAEditView;
    function GetBlockStart: TOTACharPos;
    function GetBlockAfter: TOTACharPos;
  end;
  TModuleStub = class(TInterfacedObject, IOTAModule)
  public
    Editor: IOTAEditor;
    function GetCurrentEditor: IOTAEditor;
  end;
  TIDEStub = class(TInterfacedObject, IOTAModuleServices, IOTAEditorServices)
  public
    Module: IOTAModule;
    View: IOTAEditView;
    function CurrentModule: IOTAModule;
    function GetTopView: IOTAEditView;
  end;
  TPlainEditorStub = class(TInterfacedObject, IOTAEditor)
    function GetFileName: string;
  end;
implementation
type
  TReaderStub = class(TInterfacedObject, IOTAEditReader)
  private
    FBytes: TBytes;
    FBadCount: Boolean;
  public
    constructor Create(const ASource: TSourceStub);
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
constructor TBlockStub.Create;
begin
  inherited;
  SizeOverride := -1;
  StartRow := 1;
  EndRow := 1;
  BlockStyle := btInclusive;
end;
function TBlockStub.GetVisible: Boolean; begin Result := IsVisible; end;
function TBlockStub.GetIsValid: Boolean; begin Result := IsValid; end;
function TBlockStub.GetSize: Integer;
begin
  Result := SizeOverride;
  if Result < 0 then Result := Length(BlockText);
end;
function TBlockStub.GetStyle: TOTABlockType; begin Result := BlockStyle; end;
function TBlockStub.GetStartingRow: Integer; begin Result := StartRow; end;
function TBlockStub.GetEndingRow: Integer; begin Result := EndRow; end;
function TBlockStub.GetText: string; begin Result := BlockText; end;
constructor TViewStub.Create(const ASource: TSourceStub);
begin
  inherited Create;
  Source := ASource;
  OffsetOverride := -1;
  Cursor.Line := 1;
  Cursor.Col := 1;
end;
function TViewStub.GetCursorPos: TOTAEditPos; begin Result := Cursor; end;
function TViewStub.GetBuffer: IOTAEditBuffer; begin Result := Source; end;
function TViewStub.GetBlock: IOTAEditBlock; begin Result := Selection; end;
function TViewStub.SameView(const EditView: IOTAEditView): Boolean;
begin
  Result := (Self as IOTAEditView) = EditView;
end;
procedure TViewStub.SetCursorIndex(const AIndex: Integer);
var LChar: TOTACharPos;
begin
  LChar := Source.CharPosition(AIndex);
  ConvertPos(False, Cursor, LChar);
end;
procedure TViewStub.ConvertPos(EdPosToCharPos: Boolean; var EditPos: TOTAEditPos; var CharPos: TOTACharPos);
var LStart, LIndex, LColumn, LNext, LMaximum: Integer;
begin
  if EdPosToCharPos then
  begin
    LStart := Source.LineStart(EditPos.Line);
    LIndex := LStart;
    LColumn := 1;
    while LIndex <= Length(Source.Text) do
    begin
      if CharInSet(Source.Text[LIndex], [#10, #13]) then Break;
      if Source.Text[LIndex] = #9 then LNext := ((LColumn - 1) div 8 + 1) * 8 + 1
      else LNext := LColumn + 1;
      if LNext > EditPos.Col then Break;
      LColumn := LNext;
      Inc(LIndex);
    end;
    CharPos.Line := EditPos.Line;
    CharPos.CharIndex := LIndex - LStart;
  end
  else
  begin
    LStart := Source.LineStart(CharPos.Line);
    LMaximum := LStart + CharPos.CharIndex;
    LColumn := 1;
    for LIndex := LStart to LMaximum - 1 do
      if Source.Text[LIndex] = #9 then LColumn := ((LColumn - 1) div 8 + 1) * 8 + 1
      else Inc(LColumn);
    EditPos.Line := CharPos.Line;
    EditPos.Col := LColumn;
  end;
end;
function TViewStub.CharPosToPos(CharPos: TOTACharPos): Longint;
begin
  if OffsetOverride >= 0 then Exit(OffsetOverride);
  Result := TEncoding.UTF8.GetByteCount(Copy(Source.Text, 1, Source.LineStart(CharPos.Line) - 1 + CharPos.CharIndex));
end;
procedure TSourceStub.SetText(const AText: string);
begin
  Text := AText;
  Bytes := TEncoding.UTF8.GetBytes(AText);
end;
function TSourceStub.LineStart(const ALine: Integer): Integer;
var LLine: Integer;
begin
  Result := 1;
  LLine := 1;
  while (Result <= Length(Text)) and (LLine < ALine) do
  begin
    if Text[Result] = #10 then Inc(LLine);
    Inc(Result);
  end;
end;
function TSourceStub.CharPosition(const AIndex: Integer): TOTACharPos;
var LIndex, LStart: Integer;
begin
  Result.Line := 1;
  LStart := 0;
  for LIndex := 1 to AIndex do
    if Text[LIndex] = #10 then
    begin
      Inc(Result.Line);
      LStart := LIndex;
    end;
  Result.CharIndex := AIndex - LStart;
end;
function TSourceStub.GetFileName: string; begin Result := Name; end;
function TSourceStub.CreateReader: IOTAEditReader;
begin
  Inc(ReadersCreated);
  Result := nil;
  if not ReaderMissing then Result := TReaderStub.Create(Self);
  if Assigned(ReaderMutation) then ReaderMutation();
end;
function TSourceStub.GetEditViewCount: Integer; begin Result := Length(Views); end;
function TSourceStub.GetEditView(Index: Integer): IOTAEditView; begin Result := Views[Index]; end;
function TSourceStub.GetBlockStart: TOTACharPos; begin Result := CharPosition(SelectionStart); end;
function TSourceStub.GetBlockAfter: TOTACharPos; begin Result := CharPosition(SelectionAfter); end;
constructor TReaderStub.Create(const ASource: TSourceStub);
begin
  inherited Create;
  FBytes := Copy(ASource.Bytes);
  FBadCount := ASource.ReaderBadCount;
end;
function TReaderStub.GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
begin
  if FBadCount then Exit(Count + 1);
  Result := Length(FBytes) - Position;
  if Result < 0 then Result := 0;
  if Result > Count then Result := Count;
  if Result > 0 then Move(FBytes[Position], Buffer^, Result);
end;
function TModuleStub.GetCurrentEditor: IOTAEditor; begin Result := Editor; end;
function TIDEStub.CurrentModule: IOTAModule; begin Result := Module; end;
function TIDEStub.GetTopView: IOTAEditView; begin Result := View; end;
function TPlainEditorStub.GetFileName: string; begin Result := 'C:\workspace\Designer.dfm'; end;
end.
