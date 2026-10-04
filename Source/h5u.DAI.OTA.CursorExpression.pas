unit h5u.DAI.OTA.CursorExpression;

interface

uses
  System.JSON;

type
  TDAICursorExpressionService = class sealed
  public
    class function CurrentFileName: string; static;
    class function Read(const AExpectedFile: string = ''): TJSONObject; static;
  end;

implementation

uses
  System.Classes,
  System.Hash,
  System.SysUtils,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Source.Expression;

const
  CMaximumSourceBytes = 16 * 1024 * 1024;
  CMaximumExpression = 4096;
  CMaximumLine = 65536;

function ActiveSource(out ASource: IOTASourceEditor; out AView: IOTAEditView; out AReason: string): Boolean;
var
  LModules: IOTAModuleServices;
  LEditors: IOTAEditorServices;
  LModule: IOTAModule;
  LBuffer: IOTAEditBuffer;
  LCandidate: IOTAEditView;
  LIndex, LCount: Integer;
begin
  Result := False;
  ASource := nil;
  AView := nil;
  AReason := 'editor_unavailable';
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModules) then
    Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, LEditors) then
    Exit;
  LModule := LModules.CurrentModule;
  if not Assigned(LModule) then
    Exit;
  if not Supports(LModule.CurrentEditor, IOTASourceEditor, ASource) then
  begin
    AReason := 'source_editor_not_active';
    Exit;
  end;
  AView := LEditors.TopView;
  if not Assigned(AView) then
    Exit;
  LBuffer := AView.Buffer;
  if not Assigned(LBuffer) then
    Exit;
  if not TDAIOTA.SameFile(ASource.FileName, LBuffer.FileName) then
    Exit;
  LCount := ASource.EditViewCount;
  if (LCount < 1) or (LCount > 4096) then
    Exit;
  for LIndex := 0 to LCount - 1 do
  begin
    LCandidate := ASource.EditViews[LIndex];
    if not Assigned(LCandidate) then
      Continue;
    if LCandidate.SameView(AView) then
      Exit(True);
  end;
end;

function ValidUTF8(const ABytes: TBytes): Boolean;
var
  LIndex, LRemaining, LStep: Integer;
  LCode, LMinimum: Cardinal;
  LByte: Byte;
begin
  Result := False;
  LIndex := 0;
  while LIndex < Length(ABytes) do
  begin
    LByte := ABytes[LIndex];
    if LByte = 0 then
      Exit;
    if LByte < $80 then
    begin
      Inc(LIndex);
      Continue;
    end;
    if (LByte >= $C2) and (LByte <= $DF) then
    begin
      LRemaining := 1;
      LCode := LByte and $1F;
      LMinimum := $80;
    end
    else if (LByte >= $E0) and (LByte <= $EF) then
    begin
      LRemaining := 2;
      LCode := LByte and $0F;
      LMinimum := $800;
    end
    else if (LByte >= $F0) and (LByte <= $F4) then
    begin
      LRemaining := 3;
      LCode := LByte and $07;
      LMinimum := $10000;
    end
    else
      Exit;
    if LIndex + LRemaining >= Length(ABytes) then
      Exit;
    for LStep := 1 to LRemaining do
    begin
      LByte := ABytes[LIndex + LStep];
      if (LByte and $C0) <> $80 then
        Exit;
      LCode := (LCode shl 6) or (LByte and $3F);
    end;
    if (LCode < LMinimum) or (LCode > $10FFFF) or ((LCode >= $D800) and (LCode <= $DFFF)) then
      Exit;
    Inc(LIndex, LRemaining + 1);
  end;
  Result := True;
end;

function ReadSource(const ASource: IOTASourceEditor; out ABytes: TBytes; out AText, AReason: string): Boolean;
var
  LReader: IOTAEditReader;
  LChunk: TBytes;
  LRead, LSize, LRequest, LCapacity: Integer;
begin
  Result := False;
  ABytes := nil;
  AText := '';
  AReason := 'reader_unavailable';
  LReader := ASource.CreateReader;
  if not Assigned(LReader) then
    Exit;
  SetLength(LChunk, 16384);
  LSize := 0;
  LCapacity := 0;
  repeat
    LRequest := Length(LChunk);
    if LSize + LRequest > CMaximumSourceBytes + 1 then
      LRequest := CMaximumSourceBytes + 1 - LSize;
    if LRequest < 1 then
    begin
      AReason := 'source_too_large';
      Exit;
    end;
    LRead := LReader.GetText(LSize, PAnsiChar(@LChunk[0]), LRequest);
    if (LRead < 0) or (LRead > LRequest) then
    begin
      AReason := 'reader_invalid_result';
      Exit;
    end;
    if LRead > 0 then
    begin
      if LSize + LRead > LCapacity then
      begin
        LCapacity := LCapacity * 2;
        if LCapacity < LSize + LRead then
          LCapacity := LSize + LRead;
        if LCapacity > CMaximumSourceBytes + 1 then
          LCapacity := CMaximumSourceBytes + 1;
        SetLength(ABytes, LCapacity);
      end;
      Move(LChunk[0], ABytes[LSize], LRead);
      Inc(LSize, LRead);
    end;
    if LSize > CMaximumSourceBytes then
    begin
      AReason := 'source_too_large';
      Exit;
    end;
  until LRead < LRequest;
  LReader := nil;
  SetLength(ABytes, LSize);
  // ToolsAPI readers may include a final terminator; embedded NULs are rejected.
  if LSize > 0 then
    if ABytes[LSize - 1] = 0 then
      SetLength(ABytes, LSize - 1);
  if not ValidUTF8(ABytes) then
  begin
    AReason := 'invalid_utf8';
    Exit;
  end;
  AText := TEncoding.UTF8.GetString(ABytes);
  if not TDAISourceExpression.ValidUnicode(AText) then
  begin
    AReason := 'invalid_unicode';
    Exit;
  end;
  AReason := '';
  Result := True;
end;

function ReasonText(const AReason: string): string;
begin
  if AReason = 'source_editor_not_active' then
    Exit('Der aktive Editor ist kein Quelleditor, zum Beispiel ein Designer.');
  if AReason = 'editor_changed' then
    Exit('Der aktive Quelleditor hat sich seit der Dateiauswahl geändert.');
  if AReason = 'unsupported_selection' then
    Exit('Nur eine einzeilige normale Textauswahl wird als Ausdruck unterstützt.');
  if AReason = 'empty_selection' then
    Exit('Die ausgewählte Textstelle enthält keinen Ausdruck.');
  if AReason = 'virtual_cursor' then
    Exit('Der Cursor liegt außerhalb einer eindeutigen tatsächlichen Textposition.');
  if AReason = 'unsupported_expression' then
    Exit('Die automatische Erkennung unterstützt nur vollständige Delphi-Variablenpfade ohne Funktionsaufrufe.');
  if AReason = 'not_expression' then
    Exit('Am Cursor wurde kein vollständiger Variablenpfad erkannt.');
  if AReason = 'access_denied' then
    Exit('Die Quelldatei liegt außerhalb der freigegebenen Lesebereiche.');
  Result := 'Der Ausdruck ist nicht verfügbar (' + AReason + ').';
end;

function EmptyResult: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('available', TJSONBool.Create(False));
  Result.AddPair('expression', TJSONNull.Create);
  Result.AddPair('source_kind', TJSONNull.Create);
  Result.AddPair('file', TJSONNull.Create);
  Result.AddPair('line', TJSONNull.Create);
  Result.AddPair('column', TJSONNull.Create);
end;

procedure ReplaceValue(const AObject: TJSONObject; const AName: string; const AValue: TJSONValue);
var
  LOld: TJSONPair;
begin
  LOld := AObject.RemovePair(AName);
  LOld.Free;
  AObject.AddPair(AName, AValue);
end;

procedure Failure(const AObject: TJSONObject; const AReason: string);
begin
  AObject.AddPair('reason_code', AReason);
  AObject.AddPair('reason', ReasonText(AReason));
end;

function ReadCurrent(const AExpectedFile: string): TJSONObject;
var
  LSource, LAfterSource: IOTASourceEditor;
  LView, LAfterView: IOTAEditView;
  LBlock: IOTAEditBlock;
  LCursor, LRoundTrip: TOTAEditPos;
  LCharPos: TOTACharPos;
  LBytes: TBytes;
  LText, LExpression, LReason, LKind, LFile, LExtension: string;
  LByteOffset, LCursorIndex, LStart, LAfter, LLineStart, LLineAfter, LSelectionStart, LSelectionAfter: Integer;
  LSelected, LRawSelected: string;
begin
  Result := EmptyResult;
  try
    if not ActiveSource(LSource, LView, LReason) then
    begin
      Failure(Result, LReason);
      Exit;
    end;
    LFile := LSource.FileName;
    ReplaceValue(Result, 'file', TJSONString.Create(LFile));
    if AExpectedFile <> '' then
      if not TDAIOTA.SameFile(LFile, AExpectedFile) then
      begin
        Failure(Result, 'editor_changed');
        Exit;
      end;
    if not TDAIOTA.IsWorkspaceFile(LFile) and not TDAIOTA.IsReadOnlyReferenceFile(LFile) then
    begin
      Failure(Result, 'access_denied');
      Exit;
    end;
    LExtension := LowerCase(ExtractFileExt(LFile));
    if not ((LExtension = '.pas') or (LExtension = '.dpr') or (LExtension = '.dpk') or (LExtension = '.inc')) then
    begin
      Failure(Result, 'unsupported_language');
      Exit;
    end;
    LCursor := LView.CursorPos;
    ReplaceValue(Result, 'line', TJSONNumber.Create(LCursor.Line));
    ReplaceValue(Result, 'column', TJSONNumber.Create(LCursor.Col));
    if (LCursor.Line < 1) or (LCursor.Col < 1) then
    begin
      Failure(Result, 'invalid_cursor');
      Exit;
    end;
    LCharPos := Default(TOTACharPos);
    LRoundTrip := LCursor;
    LView.ConvertPos(True, LRoundTrip, LCharPos);
    if (LCharPos.Line < 1) or (LCharPos.CharIndex < 0) then
    begin
      Failure(Result, 'invalid_cursor');
      Exit;
    end;
    LByteOffset := LView.CharPosToPos(LCharPos);
    LView.ConvertPos(False, LRoundTrip, LCharPos);
    if (LRoundTrip.Line <> LCursor.Line) or (LRoundTrip.Col <> LCursor.Col) then
    begin
      Failure(Result, 'virtual_cursor');
      Exit;
    end;
    if not ReadSource(LSource, LBytes, LText, LReason) then
    begin
      Failure(Result, LReason);
      Exit;
    end;
    if (LByteOffset < 0) or (LByteOffset > Length(LBytes)) then
    begin
      Failure(Result, 'invalid_cursor');
      Exit;
    end;
    if LByteOffset < Length(LBytes) then
      if (LBytes[LByteOffset] and $C0) = $80 then
      begin
        Failure(Result, 'invalid_cursor');
        Exit;
      end;
    LCursorIndex := TEncoding.UTF8.GetCharCount(LBytes, 0, LByteOffset);
    LLineStart := LCursorIndex + 1;
    while LLineStart > 1 do
    begin
      if CharInSet(LText[LLineStart - 1], [#10, #13]) then
        Break;
      Dec(LLineStart);
    end;
    LLineAfter := LCursorIndex + 1;
    while LLineAfter <= Length(LText) do
    begin
      if CharInSet(LText[LLineAfter], [#10, #13]) then
        Break;
      Inc(LLineAfter);
    end;
    if LLineAfter - LLineStart > CMaximumLine then
    begin
      Failure(Result, 'line_too_long');
      Exit;
    end;
    LBlock := LView.Block;
    LKind := 'cursor';
    LStart := 0;
    LAfter := 0;
    if Assigned(LBlock) then
      if LBlock.Visible and LBlock.IsValid and (LBlock.Size > 0) then
      begin
        LKind := 'selection';
        if (LBlock.Style in [btColumn, btUnknown]) or (LBlock.StartingRow <> LBlock.EndingRow) then
        begin
          Failure(Result, 'unsupported_selection');
          Exit;
        end;
        // The SDK does not document the unit of Size; the returned string is checked in UTF-16 units below.
        if LBlock.Size > CMaximumExpression * 4 then
        begin
          Failure(Result, 'expression_too_long');
          Exit;
        end;
        LRawSelected := LBlock.Text;
        LSelected := Trim(LRawSelected);
        if (Pos(#10, LRawSelected) > 0) or (Pos(#13, LRawSelected) > 0) then
        begin
          Failure(Result, 'unsupported_selection');
          Exit;
        end;
        if LSelected = '' then
        begin
          Failure(Result, 'empty_selection');
          Exit;
        end;
        if Length(LRawSelected) > CMaximumExpression then
        begin
          Failure(Result, 'expression_too_long');
          Exit;
        end;
        if not TDAISourceExpression.ValidUnicode(LRawSelected) then
        begin
          Failure(Result, 'invalid_unicode');
          Exit;
        end;
        LExpression := LSelected;
        LSelectionStart := LView.CharPosToPos(LSource.BlockStart);
        LSelectionAfter := LView.CharPosToPos(LSource.BlockAfter);
        if (LSelectionStart >= 0) and (LSelectionAfter >= LSelectionStart) and (LSelectionAfter <= Length(LBytes)) then
        begin
          if TEncoding.UTF8.GetString(LBytes, LSelectionStart, LSelectionAfter - LSelectionStart) = LRawSelected then
          begin
            LStart := LSelectionStart + TEncoding.UTF8.GetByteCount(Copy(LRawSelected, 1, Pos(LSelected, LRawSelected) - 1));
            LAfter := LStart + TEncoding.UTF8.GetByteCount(LExpression);
          end;
        end;
      end;
    if LKind = 'cursor' then
    begin
      if not TDAISourceExpression.AtCursor(LText, LCursorIndex, LStart, LAfter, LExpression, LReason) then
      begin
        Failure(Result, LReason);
        Exit;
      end;
      LAfter := TEncoding.UTF8.GetByteCount(Copy(LText, 1, LAfter));
      LStart := TEncoding.UTF8.GetByteCount(Copy(LText, 1, LStart));
    end;
    if not ActiveSource(LAfterSource, LAfterView, LReason) then
    begin
      Failure(Result, 'editor_changed');
      Exit;
    end;
    if not TDAIOTA.SameFile(LAfterSource.FileName, LFile) or not LAfterView.SameView(LView) then
    begin
      Failure(Result, 'editor_changed');
      Exit;
    end;
    LRoundTrip := LAfterView.CursorPos;
    if (LRoundTrip.Line <> LCursor.Line) or (LRoundTrip.Col <> LCursor.Col) then
    begin
      Failure(Result, 'editor_changed');
      Exit;
    end;
    ReplaceValue(Result, 'available', TJSONBool.Create(True));
    ReplaceValue(Result, 'expression', TJSONString.Create(LExpression));
    ReplaceValue(Result, 'source_kind', TJSONString.Create(LKind));
    Result.AddPair('offset_unit', 'utf8_bytes');
    if LAfter > LStart then
    begin
      Result.AddPair('expression_start', TJSONNumber.Create(LStart));
      Result.AddPair('expression_end', TJSONNumber.Create(LAfter));
    end;
    Result.AddPair('source_sha256', THashSHA2.GetHashString(LText));
    Result.AddPair('reason_code', TJSONNull.Create);
    Result.AddPair('reason', TJSONNull.Create);
  except
    on E: Exception do
    begin
      Result.Free;
      Result := EmptyResult;
      Failure(Result, 'editor_read_failed');
    end;
  end;
end;

class function TDAICursorExpressionService.CurrentFileName: string;
var
  LSource: IOTASourceEditor;
  LView: IOTAEditView;
  LReason, LResult: string;
begin
  LResult := '';
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      try
        if ActiveSource(LSource, LView, LReason) then
          LResult := LSource.FileName;
      except
        LResult := '';
      end;
    end);
  Result := LResult;
end;

class function TDAICursorExpressionService.Read(const AExpectedFile: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(
    procedure
    begin
      LResult := ReadCurrent(AExpectedFile);
    end);
  Result := LResult;
end;

end.
