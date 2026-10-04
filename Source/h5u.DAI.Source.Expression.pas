unit h5u.DAI.Source.Expression;

interface

type
  TDAISourceExpression = class sealed
  public
    // Offsets are zero-based UTF-16 code units; AAfter is exclusive.
    class function AtCursor(const ASource: string; const ACursor: Integer; out AStart, AAfter: Integer; out AExpression, AReasonCode: string): Boolean; static;
    class function ValidUnicode(const AText: string): Boolean; static;
  end;

implementation

uses
  System.Character,
  System.SysUtils;

type
  TExpressionTokenKind = (etIdentifier, etNumber, etDot, etDeref, etOpen, etClose, etComma, etOther);
  TExpressionToken = record
    Kind: TExpressionTokenKind;
    First, After: Integer;
    Escaped: Boolean;
  end;
  TExpressionTokens = TArray<TExpressionToken>;

const
  CMaximumExpression = 4096;
  CMaximumLine = 65536;
  CKeywords = '|and|array|as|asm|begin|case|class|const|constructor|destructor|dispinterface|div|do|downto|else|end|' +
    'except|exports|file|finalization|finally|for|function|goto|if|implementation|in|inherited|initialization|' +
    'inline|interface|is|label|library|mod|nil|not|object|of|or|out|packed|procedure|program|property|raise|' +
    'record|repeat|resourcestring|set|shl|shr|string|then|threadvar|to|try|type|unit|until|uses|var|while|with|xor|true|false|';

class function TDAISourceExpression.ValidUnicode(const AText: string): Boolean;
var
  LIndex: Integer;
  LCode: Word;
begin
  Result := False;
  LIndex := 1;
  while LIndex <= Length(AText) do
  begin
    LCode := Ord(AText[LIndex]);
    if LCode = 0 then
      Exit;
    if (LCode >= $D800) and (LCode <= $DBFF) then
    begin
      Inc(LIndex);
      if LIndex > Length(AText) then
        Exit;
      LCode := Ord(AText[LIndex]);
      if (LCode < $DC00) or (LCode > $DFFF) then
        Exit;
    end
    else if (LCode >= $DC00) and (LCode <= $DFFF) then
      Exit;
    Inc(LIndex);
  end;
  Result := True;
end;

function IdentifierStart(const AText: string; const AIndex: Integer): Boolean;
begin
  Result := False;
  if (AIndex < 1) or (AIndex > Length(AText)) then
    Exit;
  if (Ord(AText[AIndex]) >= $DC00) and (Ord(AText[AIndex]) <= $DFFF) then
    Exit;
  Result := (AText[AIndex] = '_') or AText[AIndex].IsLetter(AText, AIndex - 1);
end;

function IdentifierPart(const AText: string; const AIndex: Integer): Boolean;
var
  LCategory: TUnicodeCategory;
begin
  Result := False;
  if (AIndex < 1) or (AIndex > Length(AText)) then
    Exit;
  if AText[AIndex] = '_' then
    Exit(True);
  LCategory := AText[AIndex].GetUnicodeCategory(AText, AIndex - 1);
  Result := LCategory in [TUnicodeCategory.ucUppercaseLetter, TUnicodeCategory.ucLowercaseLetter, TUnicodeCategory.ucTitlecaseLetter,
    TUnicodeCategory.ucModifierLetter, TUnicodeCategory.ucOtherLetter, TUnicodeCategory.ucLetterNumber, TUnicodeCategory.ucDecimalNumber,
    TUnicodeCategory.ucNonSpacingMark, TUnicodeCategory.ucCombiningMark, TUnicodeCategory.ucConnectPunctuation];
end;

procedure AdvanceCharacter(const AText: string; var AIndex: Integer);
begin
  if (Ord(AText[AIndex]) >= $D800) and (Ord(AText[AIndex]) <= $DBFF) then
    Inc(AIndex);
  Inc(AIndex);
end;

procedure Tokenize(const ASource: string; const ALineStart, ALineAfter: Integer; out ATokens: TExpressionTokens);
var
  LIndex, LStart, LCount, LQuotes, LClosing, LDepth, LCapacity: Integer;
  LAtLineStart, LEscaped: Boolean;
  LKind: TExpressionTokenKind;
  LCommentStack: array[0..255] of Char;

  function PeekAt(const AIndex: Integer): Char;
  begin
    Result := #0;
    if (AIndex >= 1) and (AIndex <= Length(ASource)) then
      Result := ASource[AIndex];
  end;

  procedure AddToken;
  begin
    if (LStart < ALineStart) or (LStart >= ALineAfter) then
      Exit;
    if LCount = LCapacity then
    begin
      LCapacity := LCapacity * 2;
      if LCapacity = 0 then
        LCapacity := 64;
      SetLength(ATokens, LCapacity);
    end;
    ATokens[LCount].Kind := LKind;
    ATokens[LCount].First := LStart - 1;
    ATokens[LCount].After := LIndex - 1;
    ATokens[LCount].Escaped := LEscaped;
    Inc(LCount);
  end;

begin
  ATokens := nil;
  LCount := 0;
  LCapacity := 0;
  LIndex := 1;
  while LIndex < ALineAfter do
  begin
    if CharInSet(ASource[LIndex], [#9, #10, #11, #12, #13, ' ']) or (ASource[LIndex] = #$FEFF) then
    begin
      Inc(LIndex);
      Continue;
    end;
    if (ASource[LIndex] = '/') and (LIndex < Length(ASource)) then
      if ASource[LIndex + 1] = '/' then
      begin
        while LIndex < ALineAfter do
        begin
          if CharInSet(ASource[LIndex], [#10, #13]) then
            Break;
          Inc(LIndex);
        end;
        Continue;
      end;
    if (ASource[LIndex] = '{') or ((ASource[LIndex] = '(') and (PeekAt(LIndex + 1) = '*')) then
    begin
      LDepth := 1;
      LCommentStack[0] := ASource[LIndex];
      if ASource[LIndex] = '(' then
        Inc(LIndex);
      Inc(LIndex);
      while (LIndex < ALineAfter) and (LDepth > 0) do
      begin
        if (ASource[LIndex] = '{') or ((ASource[LIndex] = '(') and (PeekAt(LIndex + 1) = '*')) then
        begin
          if LDepth = Length(LCommentStack) then
          begin
            ATokens := nil;
            Exit;
          end;
          LCommentStack[LDepth] := ASource[LIndex];
          Inc(LDepth);
          if ASource[LIndex] = '(' then
            Inc(LIndex);
        end
        else if (LCommentStack[LDepth - 1] = '{') and (ASource[LIndex] = '}') then
          Dec(LDepth)
        else if (LCommentStack[LDepth - 1] = '(') and (ASource[LIndex] = '*') and (LIndex < Length(ASource)) then
          if ASource[LIndex + 1] = ')' then
          begin
            Dec(LDepth);
            Inc(LIndex);
          end;
        Inc(LIndex);
      end;
      Continue;
    end;
    if ASource[LIndex] = '''' then
    begin
      LQuotes := 0;
      while LIndex + LQuotes <= Length(ASource) do
      begin
        if ASource[LIndex + LQuotes] <> '''' then
          Break;
        Inc(LQuotes);
      end;
      if (LQuotes >= 3) and Odd(LQuotes) and CharInSet(PeekAt(LIndex + LQuotes), [#10, #13]) then
      begin
        Inc(LIndex, LQuotes);
        LAtLineStart := True;
        while LIndex < ALineAfter do
        begin
          if CharInSet(ASource[LIndex], [#10, #13]) then
          begin
            LAtLineStart := True;
            Inc(LIndex);
          end
          else if LAtLineStart and CharInSet(ASource[LIndex], [' ', #9]) then
            Inc(LIndex)
          else if LAtLineStart and (ASource[LIndex] = '''') then
          begin
            LClosing := 0;
            while LIndex + LClosing <= Length(ASource) do
            begin
              if ASource[LIndex + LClosing] <> '''' then
                Break;
              Inc(LClosing);
            end;
            Inc(LIndex, LClosing);
            if LClosing = LQuotes then
              Break;
            LAtLineStart := False;
          end
          else
          begin
            LAtLineStart := False;
            Inc(LIndex);
          end;
        end;
      end
      else
      begin
        Inc(LIndex);
        while LIndex < ALineAfter do
        begin
          if ASource[LIndex] = '''' then
          begin
            Inc(LIndex);
            if LIndex >= ALineAfter then
              Break;
            if ASource[LIndex] <> '''' then
              Break;
          end;
          Inc(LIndex);
        end;
      end;
      Continue;
    end;
    LStart := LIndex;
    LEscaped := False;
    if ASource[LIndex] = '&' then
      if IdentifierStart(ASource, LIndex + 1) then
      begin
        LEscaped := True;
        Inc(LIndex);
      end;
    if IdentifierStart(ASource, LIndex) then
    begin
      LKind := etIdentifier;
      AdvanceCharacter(ASource, LIndex);
      while IdentifierPart(ASource, LIndex) do
        AdvanceCharacter(ASource, LIndex);
      if not LEscaped then
        if Pos('|' + LowerCase(Copy(ASource, LStart, LIndex - LStart)) + '|', CKeywords) <> 0 then
          LKind := etOther;
    end
    else if CharInSet(ASource[LIndex], ['0'..'9', '$']) then
    begin
      LKind := etNumber;
      Inc(LIndex);
      while LIndex < ALineAfter do
      begin
        if not CharInSet(ASource[LIndex], ['0'..'9', 'a'..'f', 'A'..'F']) then
          Break;
        Inc(LIndex);
      end;
    end
    else
    begin
      case ASource[LIndex] of
        '.': LKind := etDot;
        '^': LKind := etDeref;
        '[': LKind := etOpen;
        ']': LKind := etClose;
        ',': LKind := etComma;
      else
        LKind := etOther;
      end;
      Inc(LIndex);
    end;
    AddToken;
  end;
  SetLength(ATokens, LCount);
end;

function TokensJoin(const ASource: string; const ATokens: TExpressionTokens; const AIndex: Integer): Boolean;
var
  LIndex: Integer;
begin
  Result := True;
  if (AIndex < 1) or (AIndex >= Length(ATokens)) then
    Exit;
  for LIndex := ATokens[AIndex - 1].After + 1 to ATokens[AIndex].First do
    if not CharInSet(ASource[LIndex], [' ', #9]) then
      Exit(False);
end;

function ParsePath(const ASource: string; const ATokens: TExpressionTokens; var AIndex: Integer; const ADepth: Integer): Boolean;
var
  LNumber: string;
  LDigit: Char;
begin
  Result := False;
  if (ADepth > 32) or (AIndex >= Length(ATokens)) then
    Exit;
  if ATokens[AIndex].Kind <> etIdentifier then
    Exit;
  if ADepth > 0 then
    if not TokensJoin(ASource, ATokens, AIndex) then
      Exit;
  Inc(AIndex);
  while AIndex < Length(ATokens) do
  begin
    if not TokensJoin(ASource, ATokens, AIndex) then
    begin
      if ATokens[AIndex].Kind in [etDot, etDeref, etOpen, etClose, etComma] then
        Exit;
      Break;
    end;
    case ATokens[AIndex].Kind of
      etDot:
        begin
          Inc(AIndex);
          if AIndex >= Length(ATokens) then
            Exit;
          if ATokens[AIndex].Kind <> etIdentifier then
            Exit;
          if not TokensJoin(ASource, ATokens, AIndex) then
            Exit;
          Inc(AIndex);
        end;
      etDeref: Inc(AIndex);
      etOpen:
        begin
          Inc(AIndex);
          repeat
            if AIndex >= Length(ATokens) then
              Exit;
            if not TokensJoin(ASource, ATokens, AIndex) then
              Exit;
            if ATokens[AIndex].Kind = etOther then
              if CharInSet(ASource[ATokens[AIndex].First + 1], ['+', '-']) then
              begin
                Inc(AIndex);
                if AIndex >= Length(ATokens) then
                  Exit;
                if ATokens[AIndex].Kind <> etNumber then
                  Exit;
                if not TokensJoin(ASource, ATokens, AIndex) then
                  Exit;
              end;
            if ATokens[AIndex].Kind = etNumber then
            begin
              LNumber := Copy(ASource, ATokens[AIndex].First + 1, ATokens[AIndex].After - ATokens[AIndex].First);
              if LNumber = '$' then
                Exit;
              if LNumber[1] <> '$' then
                for LDigit in LNumber do
                  if not CharInSet(LDigit, ['0'..'9']) then
                    Exit;
              Inc(AIndex);
            end
            else if not ParsePath(ASource, ATokens, AIndex, ADepth + 1) then
              Exit;
            if AIndex >= Length(ATokens) then
              Exit;
            if ATokens[AIndex].Kind <> etComma then
              Break;
            Inc(AIndex);
          until False;
          if ATokens[AIndex].Kind <> etClose then
            Exit;
          if not TokensJoin(ASource, ATokens, AIndex) then
            Exit;
          Inc(AIndex);
        end;
    else
      Break;
    end;
  end;
  // A callable/cast prefix must never be mistaken for a complete variable path.
  if AIndex < Length(ATokens) then
    if (ATokens[AIndex].Kind = etOther) and (ASource[ATokens[AIndex].First + 1] = '(') then
      Exit;
  Result := True;
end;

class function TDAISourceExpression.AtCursor(const ASource: string; const ACursor: Integer; out AStart, AAfter: Integer; out AExpression, AReasonCode: string): Boolean;
var
  LLineStart, LLineAfter, LIndex, LAfterToken, LFirst, LAfter, LPrevious: Integer;
  LTokens: TExpressionTokens;
  LParsed, LTouches: Boolean;
begin
  Result := False;
  AStart := 0;
  AAfter := 0;
  AExpression := '';
  AReasonCode := 'not_expression';
  if Length(ASource) > 16 * 1024 * 1024 then
  begin
    AReasonCode := 'source_too_large';
    Exit;
  end;
  if (ACursor < 0) or (ACursor > Length(ASource)) then
  begin
    AReasonCode := 'invalid_cursor';
    Exit;
  end;
  if not ValidUnicode(ASource) then
  begin
    AReasonCode := 'invalid_unicode';
    Exit;
  end;
  if (ACursor > 0) and (ACursor < Length(ASource)) then
    if (Ord(ASource[ACursor]) >= $D800) and (Ord(ASource[ACursor]) <= $DBFF) then
    begin
      AReasonCode := 'invalid_cursor';
      Exit;
    end;
  LLineStart := ACursor + 1;
  while LLineStart > 1 do
  begin
    if CharInSet(ASource[LLineStart - 1], [#10, #13]) then
      Break;
    Dec(LLineStart);
  end;
  LLineAfter := ACursor + 1;
  while LLineAfter <= Length(ASource) do
  begin
    if CharInSet(ASource[LLineAfter], [#10, #13]) then
      Break;
    Inc(LLineAfter);
  end;
  if LLineAfter - LLineStart > CMaximumLine then
  begin
    AReasonCode := 'line_too_long';
    Exit;
  end;
  Tokenize(ASource, LLineStart, LLineAfter, LTokens);
  for LIndex := 0 to Length(LTokens) - 1 do
  begin
    if LTokens[LIndex].Kind <> etIdentifier then
      Continue;
    LPrevious := LIndex - 1;
    if LPrevious >= 0 then
    begin
      if LTokens[LPrevious].Kind in [etDot, etDeref, etClose] then
        Continue;
      if LTokens[LPrevious].Kind = etOther then
        if CharInSet(ASource[LTokens[LPrevious].First + 1], [')', '@']) then
          Continue;
    end;
    LAfterToken := LIndex;
    LParsed := ParsePath(ASource, LTokens, LAfterToken, 0);
    if LAfterToken = LIndex then
      Continue;
    LFirst := LTokens[LIndex].First;
    LAfter := LTokens[LAfterToken - 1].After;
    LTouches := (ACursor >= LFirst) and (ACursor < LAfter);
    if ACursor = LAfter then
      LTouches := True;
    if not LTouches then
      Continue;
    if not LParsed then
    begin
      AReasonCode := 'unsupported_expression';
      Exit;
    end;
    if LAfter - LFirst > CMaximumExpression then
    begin
      AReasonCode := 'expression_too_long';
      Exit;
    end;
    AStart := LFirst;
    AAfter := LAfter;
    AExpression := Copy(ASource, AStart + 1, AAfter - AStart);
    AReasonCode := '';
    Exit(True);
  end;
end;

end.
