unit h5u.DAI.Symbols.Parser;

interface

uses
  System.JSON;

type
  TDAISymbolParser = class sealed
  public
    // Lexical declaration index: conditional defines and include files are not evaluated.
    // The caller owns the returned array. Line positions describe this exact source text.
    class function Parse(const ASource: string): TJSONArray; static;
  end;

implementation

{$BOOLEVAL OFF}

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils;

type
  TSymbolToken = record
    Text: string;
    Lower: string;
    Line: Integer;
    EndLine: Integer;
    Identifier: Boolean;
  end;

  TSymbolTokens = TArray<TSymbolToken>;

  TDeclarationParser = class
  private
    FTokens: TSymbolTokens;
    FPosition: Integer;
    FUnitName: string;
    FHasInterface: Boolean;
    FSymbols: TJSONArray;
    function At(const AText: string; const AOffset: Integer = 0): Boolean;
    function Identifier(const APosition: Integer): string;
    function Signature(const AStart, AFinish: Integer): string;
    function Qualified(const AOwner, AName: string): string;
    function GenericOpening(const APosition: Integer): Boolean;
    function DeclarationEnd(const AStart: Integer): Integer;
    function RoutineEnd(const AStart: Integer): Integer;
    function SkipBalanced(const AStart: Integer; const AOpen, AClose: string): Integer;
    function TypeHeaderEnd(const AKindPosition: Integer; out AAncestor: string): Integer;
    function ReadTypeName(const AStart: Integer): Integer;
    procedure AddSymbol(const AName, AOwner, AKind, ASignature: string; const AStart, AFinish: Integer);
    procedure ParseType(const AOwner: string);
    procedure ParseComposite(const AStart, AKindPosition: Integer; const AName, AOwner, AKind: string);
    procedure ParseValue(const AOwner, AKind: string);
    procedure ParseRoutine(const AOwner: string);
    procedure SkipRoutineBody;
    procedure ParseDeclarations;
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Execute: TJSONArray;
  end;

function IsIdentifierStart(const ACharacter: Char): Boolean;
begin
  Result := CharInSet(ACharacter, ['A'..'Z', 'a'..'z', '_', '&']) or (Ord(ACharacter) > 127);
end;

function IsIdentifierPart(const ACharacter: Char): Boolean;
begin
  Result := IsIdentifierStart(ACharacter) or CharInSet(ACharacter, ['0'..'9']);
end;

function Tokenize(const ASource: string): TSymbolTokens;
var
  LTokens: TList<TSymbolToken>;
  LToken: TSymbolToken;
  LPosition: Integer;
  LStart: Integer;
  LLine: Integer;
  LLength: Integer;
  LQuoteCount: Integer;
  LRunLength: Integer;
  LDelimiter: Char;
  LComments: TList<Char>;
  LIsUnit: Boolean;

  procedure Advance;
  begin
    if ASource[LPosition] = #10 then
      Inc(LLine)
    else if (ASource[LPosition] = #13) and ((LPosition = LLength) or (ASource[LPosition + 1] <> #10)) then
      Inc(LLine);
    Inc(LPosition);
  end;

  function NextIs(const ACharacter: Char): Boolean;
  begin
    Result := (LPosition < LLength) and (ASource[LPosition + 1] = ACharacter);
  end;

begin
  LTokens := TList<TSymbolToken>.Create;
  LComments := TList<Char>.Create;
  try
    LPosition := 1;
    LLine := 1;
    LLength := Length(ASource);
    LIsUnit := False;
    while LPosition <= LLength do
    begin
      if (ASource[LPosition] <= ' ') or (ASource[LPosition] = #$FEFF) then
      begin
        Advance;
        Continue;
      end;
      if (ASource[LPosition] = '/') and NextIs('/') then
      begin
        while (LPosition <= LLength) and not CharInSet(ASource[LPosition], [#10, #13]) do
          Advance;
        Continue;
      end;
      if (ASource[LPosition] = '{') or ((ASource[LPosition] = '(') and NextIs('*')) then
      begin
        LComments.Clear;
        if ASource[LPosition] = '{' then
        begin
          LComments.Add('}');
          Advance;
        end
        else
        begin
          LComments.Add(')');
          Advance;
          Advance;
        end;
        while (LPosition <= LLength) and (LComments.Count > 0) do
        begin
          LDelimiter := LComments.Last;
          if (LDelimiter = '}') and (ASource[LPosition] = '}') then
          begin
            LComments.Delete(LComments.Count - 1);
            Advance;
          end
          else if (LDelimiter = ')') and (ASource[LPosition] = '*') and NextIs(')') then
          begin
            LComments.Delete(LComments.Count - 1);
            Advance;
            Advance;
          end
          else if (ASource[LPosition] = '{') and (LDelimiter <> '}') then
          begin
            LComments.Add('}');
            Advance;
          end
          else if (ASource[LPosition] = '(') and NextIs('*') and (LDelimiter <> ')') then
          begin
            LComments.Add(')');
            Advance;
            Advance;
          end
          else
            Advance;
        end;
        Continue;
      end;
      LStart := LPosition;
      LToken.Line := LLine;
      LToken.Identifier := False;
      if ASource[LPosition] = '''' then
      begin
        LQuoteCount := 0;
        while (LPosition + LQuoteCount <= LLength) and (ASource[LPosition + LQuoteCount] = '''') do
          Inc(LQuoteCount);
        // Delphi multiline literals use three (or more) quotes followed by a newline.
        // Runs such as '''' on one line remain ordinary strings containing one quote.
        if (LQuoteCount >= 3) and (LPosition + LQuoteCount <= LLength) and
          CharInSet(ASource[LPosition + LQuoteCount], [#10, #13]) then
        begin
          Inc(LPosition, LQuoteCount);
          while LPosition <= LLength do
          begin
            if ASource[LPosition] = '''' then
            begin
              LRunLength := 0;
              while (LPosition + LRunLength <= LLength) and (ASource[LPosition + LRunLength] = '''') do
                Inc(LRunLength);
              Inc(LPosition, LRunLength);
              if LRunLength >= LQuoteCount then
                Break;
            end
            else
              Advance;
          end;
        end
        else
        begin
          Advance;
          while LPosition <= LLength do
          begin
            if ASource[LPosition] = '''' then
            begin
              Advance;
              if (LPosition <= LLength) and (ASource[LPosition] = '''') then
                Advance
              else
                Break;
            end
            else
              Advance;
          end;
        end;
      end
      else if IsIdentifierStart(ASource[LPosition]) then
      begin
        LToken.Identifier := True;
        Advance;
        while (LPosition <= LLength) and IsIdentifierPart(ASource[LPosition]) do
          Advance;
      end
      else if CharInSet(ASource[LPosition], ['0'..'9', '$']) then
      begin
        Advance;
        while (LPosition <= LLength) and CharInSet(ASource[LPosition], ['0'..'9', 'A'..'F', 'a'..'f', '_']) do
          Advance;
      end
      else
        Advance;
      LToken.Text := Copy(ASource, LStart, LPosition - LStart);
      LToken.Lower := LowerCase(LToken.Text);
      LToken.EndLine := LLine;
      LTokens.Add(LToken);
      if LTokens.Count = 1 then
        LIsUnit := LToken.Lower = 'unit';
      if LIsUnit and (LToken.Lower = 'implementation') then
        Break;
    end;
    Result := LTokens.ToArray;
  finally
    LComments.Free;
    LTokens.Free;
  end;
end;

constructor TDeclarationParser.Create(const ASource: string);
begin
  inherited Create;
  FTokens := Tokenize(ASource);
  FSymbols := TJSONArray.Create;
end;

destructor TDeclarationParser.Destroy;
begin
  FSymbols.Free;
  inherited;
end;

function TDeclarationParser.At(const AText: string; const AOffset: Integer): Boolean;
var
  LIndex: Integer;
begin
  LIndex := FPosition + AOffset;
  Result := (LIndex >= 0) and (LIndex < Length(FTokens)) and (FTokens[LIndex].Lower = AText);
end;

function TDeclarationParser.Identifier(const APosition: Integer): string;
begin
  Result := '';
  if (APosition < 0) or (APosition >= Length(FTokens)) or not FTokens[APosition].Identifier then
    Exit;
  Result := FTokens[APosition].Text;
  if (Result <> '') and (Result[1] = '&') then
    Delete(Result, 1, 1);
end;

function TDeclarationParser.Signature(const AStart, AFinish: Integer): string;
var
  LBuilder: TStringBuilder;
  LIndex: Integer;
  LPrevious: string;
  LText: string;
  LSpace: Boolean;
begin
  LBuilder := TStringBuilder.Create;
  try
    LPrevious := '';
    for LIndex := AStart to AFinish do
    begin
      if (LIndex < 0) or (LIndex >= Length(FTokens)) then
        Continue;
      LText := FTokens[LIndex].Text;
      LSpace := LBuilder.Length > 0;
      if (LText = '.') or (LText = ',') or (LText = ';') or (LText = ':') or (LText = ')') or (LText = ']') or (LText = '>') then
        LSpace := False;
      if (LPrevious = '.') or (LPrevious = '(') or (LPrevious = '[') or (LPrevious = '<') or (LPrevious = '^') or (LPrevious = '@') then
        LSpace := False;
      if ((LText = '(') or (LText = '[') or (LText = '<')) and (LIndex > AStart) and FTokens[LIndex - 1].Identifier then
        LSpace := False;
      if LSpace then
        LBuilder.Append(' ');
      LBuilder.Append(LText);
      LPrevious := LText;
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TDeclarationParser.Qualified(const AOwner, AName: string): string;
begin
  if AOwner <> '' then
    Result := AOwner + '.' + AName
  else if FUnitName <> '' then
    Result := FUnitName + '.' + AName
  else
    Result := AName;
end;

function TDeclarationParser.GenericOpening(const APosition: Integer): Boolean;
var
  LIndex: Integer;
  LDepth: Integer;
  LConstraint: Boolean;
  LText: string;
begin
  Result := False;
  if (APosition <= 0) or (APosition + 1 >= Length(FTokens)) then
    Exit;
  if not FTokens[APosition - 1].Identifier or not FTokens[APosition + 1].Identifier then
    Exit;
  LDepth := 1;
  LConstraint := False;
  LIndex := APosition + 1;
  while LIndex < Length(FTokens) do
  begin
    LText := FTokens[LIndex].Lower;
    if (LText = 'implementation') or (LText = 'begin') or (LText = 'end') or (LText = '=') then
      Exit;
    if (LText = ';') and (LDepth = 1) and not LConstraint then
      Exit;
    if LText = ':' then
      LConstraint := True
    else if LText = '<' then
      Inc(LDepth)
    else if LText = '>' then
    begin
      Dec(LDepth);
      if LDepth = 0 then
        Exit(True);
    end;
    Inc(LIndex);
  end;
end;

function TDeclarationParser.DeclarationEnd(const AStart: Integer): Integer;
var
  LParen: Integer;
  LSquare: Integer;
  LAngle: Integer;
  LRecord: Integer;
  LText: string;
begin
  LParen := 0;
  LSquare := 0;
  LAngle := 0;
  LRecord := 0;
  Result := AStart;
  while Result < Length(FTokens) do
  begin
    LText := FTokens[Result].Lower;
    if (LText = 'end') and (LRecord = 0) then
      Exit(Result - 1);
    if ((LText = 'implementation') or (LText = 'initialization') or (LText = 'finalization')) and (LRecord = 0) then
      Exit(Result - 1);
    if LText = '(' then
      Inc(LParen)
    else if LText = ')' then
      Dec(LParen)
    else if LText = '[' then
      Inc(LSquare)
    else if LText = ']' then
      Dec(LSquare)
    else if (LText = '<') and (LParen = 0) and (LSquare = 0) and GenericOpening(Result) then
      Inc(LAngle)
    else if (LText = '>') and (LAngle > 0) then
      Dec(LAngle)
    else if (LText = 'record') or ((LText = 'object') and ((Result = 0) or (FTokens[Result - 1].Lower <> 'of'))) then
      Inc(LRecord)
    else if (LText = 'end') and (LRecord > 0) then
      Dec(LRecord);
    if (LText = ';') and (LParen <= 0) and (LSquare <= 0) and (LAngle = 0) and (LRecord = 0) then
      Exit;
    Inc(Result);
  end;
  Dec(Result);
end;

function IsRoutineDirective(const AText: string): Boolean;
begin
  Result := (AText = 'overload') or (AText = 'override') or (AText = 'reintroduce') or (AText = 'virtual') or
    (AText = 'dynamic') or (AText = 'abstract') or (AText = 'final') or (AText = 'static') or (AText = 'inline') or
    (AText = 'deprecated') or (AText = 'platform') or (AText = 'library') or (AText = 'safecall') or (AText = 'cdecl') or
    (AText = 'stdcall') or (AText = 'pascal') or (AText = 'register') or (AText = 'varargs') or (AText = 'assembler') or
    (AText = 'experimental') or (AText = 'message') or (AText = 'dispid') or (AText = 'unsafe') or (AText = 'noreturn') or
    (AText = 'forward') or (AText = 'external');
end;

function TDeclarationParser.RoutineEnd(const AStart: Integer): Integer;
var
  LNext: Integer;
begin
  Result := DeclarationEnd(AStart);
  LNext := Result + 1;
  while (LNext < Length(FTokens)) and IsRoutineDirective(FTokens[LNext].Lower) do
  begin
    Result := DeclarationEnd(LNext);
    if Result < LNext then
      Break;
    LNext := Result + 1;
  end;
end;

function TDeclarationParser.SkipBalanced(const AStart: Integer; const AOpen, AClose: string): Integer;
var
  LDepth: Integer;
begin
  LDepth := 0;
  Result := AStart;
  while Result < Length(FTokens) do
  begin
    if FTokens[Result].Lower = AOpen then
      Inc(LDepth)
    else if FTokens[Result].Lower = AClose then
    begin
      Dec(LDepth);
      if LDepth = 0 then
        Exit(Result + 1);
    end;
    Inc(Result);
  end;
end;

function TDeclarationParser.ReadTypeName(const AStart: Integer): Integer;
begin
  Result := AStart;
  if Result >= Length(FTokens) then
    Exit;
  if FTokens[Result].Text = '^' then
    Inc(Result);
  if (Result < Length(FTokens)) and FTokens[Result].Identifier then
    Inc(Result);
  while Result < Length(FTokens) do
  begin
    if FTokens[Result].Text = '<' then
      Result := SkipBalanced(Result, '<', '>')
    else if FTokens[Result].Text = '.' then
    begin
      Inc(Result);
      if (Result < Length(FTokens)) and FTokens[Result].Identifier then
        Inc(Result);
    end
    else
      Break;
  end;
end;

function TDeclarationParser.TypeHeaderEnd(const AKindPosition: Integer; out AAncestor: string): Integer;
var
  LAncestorStart: Integer;
begin
  AAncestor := '';
  Result := AKindPosition + 1;
  while (Result < Length(FTokens)) and ((FTokens[Result].Lower = 'abstract') or (FTokens[Result].Lower = 'sealed')) do
    Inc(Result);
  if (Result < Length(FTokens)) and (FTokens[Result].Text = '(') then
  begin
    LAncestorStart := Result + 1;
    Result := SkipBalanced(Result, '(', ')');
    AAncestor := Signature(LAncestorStart, Result - 2);
  end;
  if (Result < Length(FTokens)) and (FTokens[Result].Lower = 'helper') then
  begin
    Inc(Result);
    if (Result < Length(FTokens)) and (FTokens[Result].Text = '(') then
      Result := SkipBalanced(Result, '(', ')');
    if (Result < Length(FTokens)) and (FTokens[Result].Lower = 'for') then
    begin
      Inc(Result);
      LAncestorStart := Result;
      Result := ReadTypeName(Result);
      AAncestor := Signature(LAncestorStart, Result - 1);
    end;
  end;
  if (Result < Length(FTokens)) and (FTokens[Result].Text = '[') then
    Result := SkipBalanced(Result, '[', ']');
end;

procedure TDeclarationParser.AddSymbol(const AName, AOwner, AKind, ASignature: string; const AStart, AFinish: Integer);
var
  LSymbol: TJSONObject;
  LFinish: Integer;
begin
  if (AName = '') or (AStart < 0) or (AStart >= Length(FTokens)) then
    Exit;
  LFinish := AFinish;
  if (LFinish < AStart) or (LFinish >= Length(FTokens)) then
    LFinish := AStart;
  LSymbol := TJSONObject.Create;
  try
    LSymbol.AddPair('name', AName);
    LSymbol.AddPair('qualified_name', Qualified(AOwner, AName));
    LSymbol.AddPair('kind', AKind);
    LSymbol.AddPair('signature', ASignature);
    LSymbol.AddPair('start_line', TJSONNumber.Create(FTokens[AStart].Line));
    LSymbol.AddPair('end_line', TJSONNumber.Create(FTokens[LFinish].EndLine));
    FSymbols.AddElement(LSymbol);
    LSymbol := nil;
  finally
    LSymbol.Free;
  end;
end;

procedure TDeclarationParser.ParseType(const AOwner: string);
var
  LStart: Integer;
  LName: string;
  LEquals: Integer;
  LKindPosition: Integer;
  LFinish: Integer;
  LKind: string;
begin
  LStart := FPosition;
  LName := Identifier(FPosition);
  if LName = '' then
  begin
    Inc(FPosition);
    Exit;
  end;
  LEquals := ReadTypeName(FPosition);
  if (LEquals >= Length(FTokens)) or (FTokens[LEquals].Text <> '=') then
  begin
    Inc(FPosition);
    Exit;
  end;
  LKindPosition := LEquals + 1;
  if (LKindPosition < Length(FTokens)) and (FTokens[LKindPosition].Lower = 'packed') then
    Inc(LKindPosition);
  if LKindPosition >= Length(FTokens) then
  begin
    FPosition := LKindPosition;
    Exit;
  end;
  LKind := FTokens[LKindPosition].Lower;
  if LKind = 'object' then
    LKind := 'class'
  else if LKind = 'dispinterface' then
    LKind := 'interface';
  if ((LKind = 'class') or (LKind = 'record') or (LKind = 'interface')) and
    ((LKindPosition + 1 >= Length(FTokens)) or (FTokens[LKindPosition + 1].Lower <> 'of')) then
    ParseComposite(LStart, LKindPosition, LName, AOwner, LKind)
  else
  begin
    LFinish := DeclarationEnd(LStart);
    AddSymbol(LName, AOwner, 'type', Signature(LStart, LFinish), LStart, LFinish);
    FPosition := LFinish + 1;
    if FPosition <= LStart then
      FPosition := LStart + 1;
  end;
end;

function IsRoutineStart(const AText: string): Boolean;
begin
  Result := (AText = 'function') or (AText = 'procedure') or (AText = 'constructor') or (AText = 'destructor') or (AText = 'operator');
end;

function IsPropertySpecifier(const AText: string): Boolean;
begin
  Result := (AText = 'read') or (AText = 'write') or (AText = 'stored') or (AText = 'default') or (AText = 'nodefault') or
    (AText = 'implements') or (AText = 'index') or (AText = 'dispid');
end;

procedure TDeclarationParser.ParseComposite(const AStart, AKindPosition: Integer; const AName, AOwner, AKind: string);
var
  LMembers: array[0..3] of TStringBuilder;
  LVisibility: Integer;
  LIndex: Integer;
  LHeaderEnd: Integer;
  LAncestor: string;
  LStart: Integer;
  LFinish: Integer;
  LPropertyEnd: Integer;
  LParen: Integer;
  LSquare: Integer;
  LMode: string;
  LSymbol: TJSONObject;
  LMember: string;
  LQualified: string;
begin
  LHeaderEnd := TypeHeaderEnd(AKindPosition, LAncestor);
  FPosition := LHeaderEnd;
  // A forward class/interface declaration has no members or closing end.
  if At(';') or (FPosition >= Length(FTokens)) then
  begin
    AddSymbol(AName, AOwner, AKind, Signature(AStart, FPosition), AStart, FPosition);
    if At(';') then
      Inc(FPosition);
    Exit;
  end;
  for LIndex := Low(LMembers) to High(LMembers) do
    LMembers[LIndex] := nil;
  try
    for LIndex := Low(LMembers) to High(LMembers) do
      LMembers[LIndex] := TStringBuilder.Create;
    LVisibility := 2;
    LMode := '';
    LQualified := Qualified(AOwner, AName);
    while (FPosition < Length(FTokens)) and not At('end') and not At('implementation') do
    begin
      LStart := FPosition;
      if At('strict') and (At('private', 1) or At('protected', 1)) then
        Inc(FPosition);
      if At('private') or At('protected') or At('public') or At('published') or At('automated') then
      begin
        if At('private') then
          LVisibility := 0
        else if At('protected') then
          LVisibility := 1
        else if At('public') then
          LVisibility := 2
        else
          LVisibility := 3;
        Inc(FPosition);
        LMode := '';
        Continue;
      end;
      if At('[') then
      begin
        FPosition := SkipBalanced(FPosition, '[', ']');
        Continue;
      end;
      if At(';') then
      begin
        Inc(FPosition);
        Continue;
      end;
      if At('type') or At('const') or At('var') then
      begin
        LMode := FTokens[FPosition].Lower;
        Inc(FPosition);
        Continue;
      end;
      if (LMode = 'type') and FTokens[FPosition].Identifier and not IsRoutineStart(FTokens[FPosition].Lower) and not At('class') then
      begin
        ParseType(LQualified);
        Continue;
      end;
      if IsRoutineStart(FTokens[FPosition].Lower) or (At('class') and (FPosition + 1 < Length(FTokens)) and
        IsRoutineStart(FTokens[FPosition + 1].Lower)) then
      begin
        LFinish := RoutineEnd(FPosition);
        LMember := Signature(LStart, LFinish);
        LMode := '';
      end
      else if At('property') or (At('class') and At('property', 1)) then
      begin
        LFinish := DeclarationEnd(FPosition);
        LPropertyEnd := LFinish;
        LParen := 0;
        LSquare := 0;
        for LIndex := FPosition + 1 to LFinish do
        begin
          if FTokens[LIndex].Text = '(' then
            Inc(LParen)
          else if FTokens[LIndex].Text = ')' then
            Dec(LParen)
          else if FTokens[LIndex].Text = '[' then
            Inc(LSquare)
          else if FTokens[LIndex].Text = ']' then
            Dec(LSquare);
          if (LParen = 0) and (LSquare = 0) and IsPropertySpecifier(FTokens[LIndex].Lower) then
          begin
            LPropertyEnd := LIndex - 1;
            Break;
          end;
        end;
        LMember := Signature(LStart, LPropertyEnd);
        if (LMember <> '') and (LMember[Length(LMember)] <> ';') then
          LMember := LMember + ';';
        if (LFinish + 2 < Length(FTokens)) and (FTokens[LFinish + 1].Lower = 'default') and (FTokens[LFinish + 2].Text = ';') then
          Inc(LFinish, 2);
        LMode := '';
      end
      else
      begin
        LFinish := DeclarationEnd(FPosition);
        LMember := Signature(LStart, LFinish);
      end;
      if LMember <> '' then
      begin
        if LMembers[LVisibility].Length > 0 then
          LMembers[LVisibility].Append(#10);
        LMembers[LVisibility].Append(FTokens[LStart].Line).Append(': ').Append(LMember);
      end;
      FPosition := LFinish + 1;
      if FPosition <= LStart then
        FPosition := LStart + 1;
    end;
    LFinish := FPosition;
    if At('end') then
    begin
      Inc(FPosition);
      if At(';') then
      begin
        LFinish := FPosition;
        Inc(FPosition);
      end;
    end;
    AddSymbol(AName, AOwner, AKind, Signature(AStart, LHeaderEnd - 1), AStart, LFinish);
    LSymbol := FSymbols.Items[FSymbols.Count - 1] as TJSONObject;
    if LAncestor <> '' then
      LSymbol.AddPair('ancestor', LAncestor);
    LSymbol.AddPair('members_private', LMembers[0].ToString);
    LSymbol.AddPair('members_protected', LMembers[1].ToString);
    LSymbol.AddPair('members_public', LMembers[2].ToString);
    LSymbol.AddPair('members_published', LMembers[3].ToString);
  finally
    for LIndex := Low(LMembers) to High(LMembers) do
      LMembers[LIndex].Free;
  end;
end;

procedure TDeclarationParser.ParseValue(const AOwner, AKind: string);
var
  LStart: Integer;
  LFinish: Integer;
  LIndex: Integer;
  LName: string;
  LSignature: string;
begin
  LStart := FPosition;
  LFinish := DeclarationEnd(LStart);
  LSignature := Signature(LStart, LFinish);
  LIndex := LStart;
  while LIndex <= LFinish do
  begin
    LName := Identifier(LIndex);
    if LName = '' then
      Break;
    AddSymbol(LName, AOwner, AKind, LSignature, LStart, LFinish);
    Inc(LIndex);
    if (LIndex > LFinish) or (FTokens[LIndex].Text <> ',') then
      Break;
    Inc(LIndex);
  end;
  FPosition := LFinish + 1;
  if FPosition <= LStart then
    FPosition := LStart + 1;
end;

procedure TDeclarationParser.ParseRoutine(const AOwner: string);
var
  LStart: Integer;
  LFinish: Integer;
  LNameStart: Integer;
  LNameEnd: Integer;
  LName: string;
  LKind: string;
begin
  LStart := FPosition;
  if At('class') then
    Inc(FPosition);
  LKind := 'procedure';
  if At('function') or At('operator') then
    LKind := 'function';
  LNameStart := FPosition + 1;
  LNameEnd := ReadTypeName(LNameStart);
  LName := Signature(LNameStart, LNameEnd - 1);
  LFinish := RoutineEnd(LStart);
  AddSymbol(LName, AOwner, LKind, Signature(LStart, LFinish), LStart, LFinish);
  FPosition := LFinish + 1;
  if FPosition <= LStart then
    FPosition := LStart + 1;
end;

procedure TDeclarationParser.SkipRoutineBody;
var
  LDepth: Integer;
  LHasBody: Boolean;
begin
  if FHasInterface or (FPosition >= Length(FTokens)) then
    Exit;
  if not (At('begin') or At('asm') or At('var') or At('const') or At('type') or At('label') or At('threadvar')) then
    Exit;
  LDepth := 0;
  LHasBody := False;
  while FPosition < Length(FTokens) do
  begin
    if At('begin') or At('asm') or At('case') or At('try') then
    begin
      Inc(LDepth);
      LHasBody := True;
    end
    else if At('end') then
    begin
      Dec(LDepth);
      if LHasBody and (LDepth <= 0) then
      begin
        Inc(FPosition);
        if At(';') then
          Inc(FPosition);
        Exit;
      end;
    end;
    Inc(FPosition);
  end;
end;

procedure TDeclarationParser.ParseDeclarations;
var
  LMode: string;
begin
  LMode := '';
  while FPosition < Length(FTokens) do
  begin
    if At('implementation') or At('initialization') or At('finalization') or At('begin') or At('end') then
      Exit;
    if At('uses') or At('exports') or At('requires') or At('contains') then
    begin
      FPosition := DeclarationEnd(FPosition) + 1;
      Continue;
    end;
    if At('type') or At('var') or At('threadvar') or At('const') or At('resourcestring') then
    begin
      LMode := FTokens[FPosition].Lower;
      Inc(FPosition);
      Continue;
    end;
    if At('[') then
    begin
      FPosition := SkipBalanced(FPosition, '[', ']');
      Continue;
    end;
    if IsRoutineStart(FTokens[FPosition].Lower) then
    begin
      ParseRoutine('');
      SkipRoutineBody;
      LMode := '';
      Continue;
    end;
    if FTokens[FPosition].Identifier then
    begin
      if LMode = 'type' then
        ParseType('')
      else if (LMode = 'var') or (LMode = 'threadvar') then
        ParseValue('', 'variable')
      else if (LMode = 'const') or (LMode = 'resourcestring') then
        ParseValue('', 'constant')
      else
        Inc(FPosition);
    end
    else
      Inc(FPosition);
  end;
end;

function TDeclarationParser.Execute: TJSONArray;
var
  LStart: Integer;
begin
  FPosition := 0;
  if At('unit') or At('program') or At('library') or At('package') then
  begin
    LStart := FPosition + 1;
    FPosition := DeclarationEnd(FPosition);
    FUnitName := Signature(LStart, FPosition - 1);
    Inc(FPosition);
    if (Length(FTokens) > 0) and (FTokens[0].Lower = 'unit') then
    begin
      while (FPosition < Length(FTokens)) and not At('interface') do
        Inc(FPosition);
      FHasInterface := At('interface');
      if FHasInterface then
        Inc(FPosition);
    end;
  end;
  ParseDeclarations;
  Result := FSymbols;
  FSymbols := nil;
end;

class function TDAISymbolParser.Parse(const ASource: string): TJSONArray;
var
  LParser: TDeclarationParser;
begin
  LParser := TDeclarationParser.Create(ASource);
  try
    Result := LParser.Execute;
  finally
    LParser.Free;
  end;
end;

end.
