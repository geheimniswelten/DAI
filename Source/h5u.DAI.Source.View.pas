unit h5u.DAI.Source.View;

interface

type
  TDAISourceView = class sealed
  public
    class function InterfaceText(const AFileName, AContent: string; out AImplementationOmitted: Boolean): string; static;
    class procedure RequireCompleteUnit(const AFileName, AContent: string); static;
  end;

implementation

uses
  System.SysUtils;

type
  TSourceTokenKind = (stkEnd, stkIdentifier, stkString, stkSymbol, stkOther);

  TSourceToken = record
    Kind: TSourceTokenKind;
    Offset: Integer;
    Count: Integer;
    Escaped: Boolean;
  end;

  TSourceLexer = record
  private
    FContent: string;
    FIndex: Integer;
    FUnterminatedToken: Boolean;
    function Peek(AOffset: Integer = 0): Char;
    procedure SkipString;
    procedure SkipTrivia;
  public
    procedure Initialize(const AContent: string);
    function Next: TSourceToken;
    function IsKeyword(const AToken: TSourceToken; const AKeyword: string): Boolean;
    function IsSymbol(const AToken: TSourceToken; ASymbol: Char): Boolean;
    property UnterminatedToken: Boolean read FUnterminatedToken;
  end;

function IsIdentifierCharacter(ACharacter: Char): Boolean;
begin
  // Treat non-ASCII UTF-16 characters conservatively as part of an identifier.
  // This also keeps supplementary characters and combining marks with their word.
  Result := CharInSet(ACharacter, ['a'..'z', 'A'..'Z', '0'..'9', '_']) or (Ord(ACharacter) >= 128);
end;

function IsIdentifierStart(ACharacter: Char): Boolean;
begin
  Result := CharInSet(ACharacter, ['a'..'z', 'A'..'Z', '_']) or (Ord(ACharacter) >= 128);
end;

procedure TSourceLexer.Initialize(const AContent: string);
begin
  FContent := AContent;
  FIndex := 1;
  FUnterminatedToken := False;
  if Peek = #$FEFF then
    Inc(FIndex);
end;

function TSourceLexer.IsKeyword(const AToken: TSourceToken; const AKeyword: string): Boolean;
begin
  Result := False;
  if (AToken.Kind <> stkIdentifier) or AToken.Escaped or (AToken.Count <> Length(AKeyword)) then
    Exit;
  Result := SameText(Copy(FContent, AToken.Offset, AToken.Count), AKeyword);
end;

function TSourceLexer.IsSymbol(const AToken: TSourceToken; ASymbol: Char): Boolean;
begin
  Result := False;
  if AToken.Kind = stkSymbol then
    Result := FContent[AToken.Offset] = ASymbol;
end;

function TSourceLexer.Next: TSourceToken;
var
  LCharacter: Char;
begin
  SkipTrivia;
  Result := Default(TSourceToken);
  Result.Offset := FIndex;
  if FIndex > Length(FContent) then
    Exit;
  LCharacter := Peek;
  if LCharacter = '''' then
  begin
    Result.Kind := stkString;
    SkipString;
  end
  else if (LCharacter = '&') and IsIdentifierStart(Peek(1)) then
  begin
    Result.Kind := stkIdentifier;
    Result.Escaped := True;
    Inc(FIndex, 2);
    while IsIdentifierCharacter(Peek) do
      Inc(FIndex);
  end
  else if IsIdentifierCharacter(LCharacter) then
  begin
    if IsIdentifierStart(LCharacter) then
      Result.Kind := stkIdentifier
    else
      Result.Kind := stkOther;
    Inc(FIndex);
    while IsIdentifierCharacter(Peek) do
      Inc(FIndex);
  end
  else
  begin
    Result.Kind := stkSymbol;
    Inc(FIndex);
  end;
  Result.Count := FIndex - Result.Offset;
end;

function TSourceLexer.Peek(AOffset: Integer = 0): Char;
begin
  Result := #0;
  if FIndex + AOffset <= Length(FContent) then
    Result := FContent[FIndex + AOffset];
end;

procedure TSourceLexer.SkipString;
var
  LClosingQuotes: Integer;
  LLinePrefix: Boolean;
  LOpeningQuotes: Integer;
begin
  LOpeningQuotes := 0;
  while Peek(LOpeningQuotes) = '''' do
    Inc(LOpeningQuotes);
  if (LOpeningQuotes >= 3) and Odd(LOpeningQuotes) and CharInSet(Peek(LOpeningQuotes), [#10, #13]) then
  begin
    // Delphi 12+ multiline literals use an odd quote count followed by a newline.
    // A matching closing delimiter starts its own line after optional indentation.
    Inc(FIndex, LOpeningQuotes);
    LLinePrefix := True;
    while FIndex <= Length(FContent) do
    begin
      if CharInSet(Peek, [#10, #13]) then
      begin
        LLinePrefix := True;
        Inc(FIndex);
      end
      else if LLinePrefix and CharInSet(Peek, [' ', #9]) then
        Inc(FIndex)
      else if LLinePrefix and (Peek = '''') then
      begin
        LClosingQuotes := 0;
        while Peek(LClosingQuotes) = '''' do
          Inc(LClosingQuotes);
        Inc(FIndex, LClosingQuotes);
        if LClosingQuotes = LOpeningQuotes then
          Exit;
        LLinePrefix := False;
      end
      else
      begin
        LLinePrefix := False;
        Inc(FIndex);
      end;
    end;
    FUnterminatedToken := True;
    Exit;
  end;
  Inc(FIndex);
  while FIndex <= Length(FContent) do
  begin
    if Peek = '''' then
    begin
      Inc(FIndex);
      if Peek <> '''' then
        Exit;
    end;
    Inc(FIndex);
  end;
  FUnterminatedToken := True;
end;

procedure TSourceLexer.SkipTrivia;
var
  LClosed: Boolean;
begin
  while FIndex <= Length(FContent) do
  begin
    if CharInSet(Peek, [#9, #10, #11, #12, #13, ' ']) then
      Inc(FIndex)
    else if Peek = '{' then
    begin
      Inc(FIndex);
      LClosed := False;
      while FIndex <= Length(FContent) do
      begin
        if Peek = '}' then
        begin
          Inc(FIndex);
          LClosed := True;
          Break;
        end;
        Inc(FIndex);
      end;
      if not LClosed then
        FUnterminatedToken := True;
    end
    else if (Peek = '(') and (Peek(1) = '*') then
    begin
      Inc(FIndex, 2);
      LClosed := False;
      while FIndex <= Length(FContent) do
      begin
        if (Peek = '*') and (Peek(1) = ')') then
        begin
          Inc(FIndex, 2);
          LClosed := True;
          Break;
        end;
        Inc(FIndex);
      end;
      if not LClosed then
        FUnterminatedToken := True;
    end
    else if (Peek = '/') and (Peek(1) = '/') then
    begin
      Inc(FIndex, 2);
      while FIndex <= Length(FContent) do
      begin
        if CharInSet(Peek, [#10, #13]) then
          Break;
        Inc(FIndex);
      end;
    end
    else
      Break;
  end;
end;

function BeginUnitInterface(var ALexer: TSourceLexer; out AError: string): Boolean;
var
  LToken: TSourceToken;
begin
  Result := False;
  AError := 'Der Inhalt beginnt nicht mit einem Delphi-Unit-Kopf (unit Name;).';
  LToken := ALexer.Next;
  if not ALexer.IsKeyword(LToken, 'unit') then
    Exit;
  AError := 'Der Delphi-Unit-Kopf enthält keinen gültigen Unit-Namen.';
  LToken := ALexer.Next;
  if LToken.Kind <> stkIdentifier then
    Exit;
  LToken := ALexer.Next;
  while ALexer.IsSymbol(LToken, '.') do
  begin
    LToken := ALexer.Next;
    if LToken.Kind <> stkIdentifier then
      Exit;
    LToken := ALexer.Next;
  end;
  // Unit hint directives can include a quoted deprecation message.
  while ALexer.IsKeyword(LToken, 'deprecated') or ALexer.IsKeyword(LToken, 'platform') or
    ALexer.IsKeyword(LToken, 'experimental') or ALexer.IsKeyword(LToken, 'library') do
  begin
    LToken := ALexer.Next;
    if LToken.Kind = stkString then
      LToken := ALexer.Next;
  end;
  AError := 'Der Delphi-Unit-Kopf muss mit einem Semikolon enden.';
  if not ALexer.IsSymbol(LToken, ';') then
    Exit;
  AError := 'Nach dem Delphi-Unit-Kopf fehlt der interface-Abschnitt.';
  LToken := ALexer.Next;
  if not ALexer.IsKeyword(LToken, 'interface') then
    Exit;
  AError := '';
  Result := True;
end;

class function TDAISourceView.InterfaceText(const AFileName, AContent: string; out AImplementationOmitted: Boolean): string;
var
  LError: string;
  LLexer: TSourceLexer;
  LToken: TSourceToken;
begin
  Result := AContent;
  AImplementationOmitted := False;
  if not SameText(ExtractFileExt(AFileName), '.pas') then
    Exit;
  LLexer.Initialize(AContent);
  if not BeginUnitInterface(LLexer, LError) then
    Exit;
  while True do
  begin
    LToken := LLexer.Next;
    if LToken.Kind = stkEnd then
      Exit;
    if LLexer.IsKeyword(LToken, 'implementation') then
    begin
      Result := Copy(AContent, 1, LToken.Offset - 1);
      AImplementationOmitted := True;
      Exit;
    end;
  end;
end;

class procedure TDAISourceView.RequireCompleteUnit(const AFileName, AContent: string);
var
  LError: string;
  LHasImplementation: Boolean;
  LLexer: TSourceLexer;
  LPreviousToken: TSourceToken;
  LToken: TSourceToken;
  LLastToken: TSourceToken;
begin
  if not SameText(ExtractFileExt(AFileName), '.pas') then
    Exit;
  LLexer.Initialize(AContent);
  if not BeginUnitInterface(LLexer, LError) then
    raise EArgumentException.Create(LError);
  LHasImplementation := False;
  LPreviousToken := Default(TSourceToken);
  LLastToken := Default(TSourceToken);
  while True do
  begin
    LToken := LLexer.Next;
    if LToken.Kind = stkEnd then
      Break;
    if LLexer.IsKeyword(LToken, 'implementation') then
      LHasImplementation := True;
    LPreviousToken := LLastToken;
    LLastToken := LToken;
  end;
  if LLexer.UnterminatedToken then
    raise EArgumentException.Create('Die Delphi-Unit enthält einen unterminierten Kommentar oder String.');
  if not LHasImplementation then
    raise EArgumentException.Create('Die vollständige Delphi-Unit benötigt einen implementation-Abschnitt; eine reine Interface-Ansicht darf nicht geschrieben werden.');
  if not LLexer.IsKeyword(LPreviousToken, 'end') or not LLexer.IsSymbol(LLastToken, '.') then
    raise EArgumentException.Create('Die vollständige Delphi-Unit muss mit end. abschließen.');
  // This is a structural completeness check. Delphi syntax and semantics still require the compiler.
end;

end.
