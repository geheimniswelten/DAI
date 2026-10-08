unit h5u.DAI.Clients.ConfigText;

interface

type
  TDAIClientConfigText = class sealed
  public
    class function ExtractEntry(const AText, AFormat: string; const AKeys: TArray<string>; out AEntry: string): Boolean; static;
    class function Merge(const AText, AFormat: string; const AKeys: TArray<string>; const AEntry: string; ARemove: Boolean): string; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.RegularExpressions,
  h5u.DAI.Clients.SafeFiles;

type
  TConfigNode = class
  public
    Key: string;
    KeyStart: Integer;
    Start: Integer;
    Finish: Integer;
    Comma: Integer;
    IsObject: Boolean;
    Children: TObjectList<TConfigNode>;
    constructor Create;
    destructor Destroy; override;
    function Child(const AKey: string): TConfigNode;
  end;

  TConfigParser = class
  private
    FText: string;
    FPosition: Integer;
    FRelaxed: Boolean;
    procedure Fail;
    procedure Skip;
    function ReadString: string;
    function ReadKey: string;
    function Value(ADepth: Integer): TConfigNode;
  public
    constructor Create(const AText: string; ARelaxed: Boolean);
    function Parse: TConfigNode;
  end;

procedure Conflict(const AMessage: string);
begin
  raise EDAIClientConfigConflict.Create(AMessage);
end;

function EndOfLine(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

constructor TConfigNode.Create;
begin
  inherited Create;
  Children := TObjectList<TConfigNode>.Create(True);
end;

destructor TConfigNode.Destroy;
begin
  Children.Free;
  inherited Destroy;
end;

function TConfigNode.Child(const AKey: string): TConfigNode;
var
  LChild: TConfigNode;
begin
  for LChild in Children do
    if LChild.Key = AKey then
      Exit(LChild);
  Result := nil;
end;

constructor TConfigParser.Create(const AText: string; ARelaxed: Boolean);
begin
  inherited Create;
  FText := AText;
  FRelaxed := ARelaxed;
  FPosition := 1;
end;

procedure TConfigParser.Fail;
begin
  Conflict('Die Konfiguration ist ungültig oder verwendet nicht unterstützte JSON-/JSON5-Syntax; sie bleibt unverändert.');
end;

procedure TConfigParser.Skip;
begin
  while FPosition <= Length(FText) do
  begin
    if CharInSet(FText[FPosition], [#9, #10, #13, ' ']) then
      Inc(FPosition)
    else if FRelaxed and (FText[FPosition] = '/') and (FPosition < Length(FText)) then
    begin
      if FText[FPosition + 1] = '/' then
      begin
        Inc(FPosition, 2);
        while (FPosition <= Length(FText)) and not CharInSet(FText[FPosition], [#10, #13]) do
          Inc(FPosition);
      end
      else if FText[FPosition + 1] = '*' then
      begin
        Inc(FPosition, 2);
        while (FPosition < Length(FText)) and (Copy(FText, FPosition, 2) <> '*/') do
          Inc(FPosition);
        if FPosition >= Length(FText) then
          Fail;
        Inc(FPosition, 2);
      end
      else
        Fail;
    end
    else
      Break;
  end;
end;

function TConfigParser.ReadString: string;
var
  LQuote: Char;
  LCharacter: Char;
  LCode: Integer;
  LDigits: string;
begin
  Result := '';
  if FPosition > Length(FText) then
    Fail;
  LQuote := FText[FPosition];
  if (LQuote <> '"') and not (FRelaxed and (LQuote = '''')) then
    Fail;
  Inc(FPosition);
  while FPosition <= Length(FText) do
  begin
    LCharacter := FText[FPosition];
    Inc(FPosition);
    if LCharacter = LQuote then
      Exit;
    if Ord(LCharacter) < 32 then
      Fail;
    if LCharacter = '\' then
    begin
      if FPosition > Length(FText) then
        Fail;
      LCharacter := FText[FPosition];
      Inc(FPosition);
      case LCharacter of
        '"', '/', '\': ;
        '''': if not FRelaxed then Fail;
        'b': LCharacter := #8;
        'f': LCharacter := #12;
        'n': LCharacter := #10;
        'r': LCharacter := #13;
        't': LCharacter := #9;
        'u':
          begin
            LDigits := Copy(FText, FPosition, 4);
            if (Length(LDigits) <> 4) or not TRegEx.IsMatch(LDigits, '^[0-9a-fA-F]{4}$') or not TryStrToInt('$' + LDigits, LCode) then
              Fail;
            LCharacter := Char(LCode);
            Inc(FPosition, 4);
          end;
      else
        Fail;
      end;
    end;
    Result := Result + LCharacter;
  end;
  Fail;
end;

function TConfigParser.ReadKey: string;
var
  LStart: Integer;
begin
  Skip;
  if FPosition > Length(FText) then
    Fail;
  if CharInSet(FText[FPosition], ['"', '''']) then
    Exit(ReadString);
  if not FRelaxed or not CharInSet(FText[FPosition], ['a'..'z', 'A'..'Z', '_', '$']) then
    Fail;
  LStart := FPosition;
  while (FPosition <= Length(FText)) and CharInSet(FText[FPosition], ['a'..'z', 'A'..'Z', '0'..'9', '_', '$']) do
    Inc(FPosition);
  Result := Copy(FText, LStart, FPosition - LStart);
end;

function TConfigParser.Value(ADepth: Integer): TConfigNode;
var
  LClose: Char;
  LChild: TConfigNode;
  LKey: string;
  LKeyStart: Integer;
  LStart: Integer;
  LScalar: string;
begin
  Skip;
  if (ADepth > 64) or (FPosition > Length(FText)) then
    Fail;
  Result := TConfigNode.Create;
  try
    Result.Start := FPosition;
    if CharInSet(FText[FPosition], ['{', '[']) then
    begin
      Result.IsObject := FText[FPosition] = '{';
      if Result.IsObject then LClose := '}' else LClose := ']';
      Inc(FPosition);
      Skip;
      if (FPosition <= Length(FText)) and (FText[FPosition] = LClose) then
        Inc(FPosition)
      else
      begin
        while True do
        begin
          LKey := '';
          LKeyStart := FPosition;
          if Result.IsObject then
          begin
            LKey := ReadKey;
            if Result.Child(LKey) <> nil then
              Conflict('Doppelte Konfigurationsschlüssel werden nicht automatisch bearbeitet.');
            Skip;
            if (FPosition > Length(FText)) or (FText[FPosition] <> ':') then
              Fail;
            Inc(FPosition);
          end;
          LChild := Value(ADepth + 1);
          LChild.Key := LKey;
          LChild.KeyStart := LKeyStart;
          Result.Children.Add(LChild);
          Skip;
          if FPosition > Length(FText) then
            Fail;
          if FText[FPosition] = LClose then
          begin
            Inc(FPosition);
            Break;
          end;
          if FText[FPosition] <> ',' then
            Fail;
          LChild.Comma := FPosition;
          Inc(FPosition);
          Skip;
          if (FPosition <= Length(FText)) and (FText[FPosition] = LClose) then
          begin
            if not FRelaxed then
              Fail;
            Inc(FPosition);
            Break;
          end;
        end;
      end;
    end
    else if CharInSet(FText[FPosition], ['"', '''']) then
      ReadString
    else
    begin
      LStart := FPosition;
      while (FPosition <= Length(FText)) and CharInSet(FText[FPosition], ['a'..'z', 'A'..'Z', '0'..'9', '.', '+', '-']) do
        Inc(FPosition);
      LScalar := Copy(FText, LStart, FPosition - LStart);
      if (LScalar <> 'true') and (LScalar <> 'false') and (LScalar <> 'null') and
        not TRegEx.IsMatch(LScalar, '^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$') then
        Fail;
    end;
    Result.Finish := FPosition - 1;
  except
    Result.Free;
    raise;
  end;
end;

function TConfigParser.Parse: TConfigNode;
begin
  Result := Value(0);
  try
    Skip;
    if (FPosition <= Length(FText)) or not Result.IsObject then
      Fail;
  except
    Result.Free;
    raise;
  end;
end;

function ParseJson(const AText, AFormat: string): TConfigNode;
var
  LParser: TConfigParser;
  LText: string;
begin
  LText := AText;
  if Trim(LText) = '' then
    LText := '{}';
  LParser := TConfigParser.Create(LText, SameText(AFormat, 'json5') or SameText(AFormat, 'jsonc'));
  try
    Result := LParser.Parse;
  finally
    LParser.Free;
  end;
end;

function Locate(const ARoot: TConfigNode; const AKeys: TArray<string>): TConfigNode;
var
  LKey: string;
begin
  Result := ARoot;
  for LKey in AKeys do
  begin
    if Result = nil then
      Exit;
    if not Result.IsObject then
      Conflict('Der MCP-Konfigurationsbereich ist kein Objekt.');
    Result := Result.Child(LKey);
  end;
end;

function JsonQuote(const AValue: string): string;
var
  LValue: TJSONString;
begin
  LValue := TJSONString.Create(AValue);
  try
    Result := LValue.ToJSON;
  finally
    LValue.Free;
  end;
end;

function JsonMerge(const AText, AFormat: string; const AKeys: TArray<string>; const AEntry: string; ARemove: Boolean): string;
var
  LRoot: TConfigNode;
  LParent: TConfigNode;
  LNode: TConfigNode;
  LLast: TConfigNode;
  LCheck: TConfigNode;
  LIndex: Integer;
  LChildIndex: Integer;
  LAddition: string;
  LPosition: Integer;
  LIndent: string;
  LEndOfLine: string;
begin
  Result := AText;
  if (Trim(Result) = '') and not ARemove then
    Result := '{}';
  LRoot := ParseJson(Result, AFormat);
  try
    LParent := LRoot;
    for LIndex := 0 to High(AKeys) do
    begin
      if not LParent.IsObject then
        Conflict('Der MCP-Konfigurationsbereich ist kein Objekt.');
      LNode := LParent.Child(AKeys[LIndex]);
      if LNode = nil then
      begin
        if ARemove then
          Exit;
        LAddition := AEntry;
        for LChildIndex := High(AKeys) downto LIndex + 1 do
          LAddition := '{' + JsonQuote(AKeys[LChildIndex]) + ': ' + LAddition + '}';
        LEndOfLine := EndOfLine(Result);
        LIndent := StringOfChar(' ', (LIndex + 1) * 2);
        LAddition := LEndOfLine + LIndent + JsonQuote(AKeys[LIndex]) + ': ' + LAddition + LEndOfLine + StringOfChar(' ', LIndex * 2);
        LPosition := LParent.Finish;
        if LParent.Children.Count > 0 then
        begin
          LLast := LParent.Children.Last;
          if LLast.Comma = 0 then
          begin
            Insert(',', Result, LLast.Finish + 1);
            Inc(LPosition);
          end;
        end;
        Insert(LAddition, Result, LPosition);
        Break;
      end;
      if LIndex = High(AKeys) then
      begin
        if ARemove then
        begin
          LPosition := LNode.Comma;
          if LPosition > 0 then
            Delete(Result, LPosition, 1)
          else
          begin
            LChildIndex := LParent.Children.IndexOf(LNode);
            if LChildIndex > 0 then
              LPosition := LParent.Children[LChildIndex - 1].Comma;
          end;
          Delete(Result, LNode.KeyStart, LNode.Finish - LNode.KeyStart + 1);
          if (LNode.Comma = 0) and (LPosition > 0) then
            Delete(Result, LPosition, 1);
        end
        else
        begin
          Delete(Result, LNode.Start, LNode.Finish - LNode.Start + 1);
          Insert(AEntry, Result, LNode.Start);
        end;
        Break;
      end;
      LParent := LNode;
    end;
    LCheck := ParseJson(Result, AFormat);
    LCheck.Free;
  finally
    LRoot.Free;
  end;
end;

function YamlRanges(const AText, AServerName: string; out AHeaderStart, AHeaderEnd, AEntryStart, AEntryEnd, ASectionEnd, AIndent: Integer): Boolean;
var
  LLines: TStringList;
  LRoots: TDictionary<string, Boolean>;
  LServers: TDictionary<string, Boolean>;
  LIndex: Integer;
  LOffset: Integer;
  LLine: string;
  LTrim: string;
  LMatch: TMatch;
  LIndent: Integer;
  LHeader: Boolean;
  LInEntry: Boolean;
  LRootKey: string;
  LQuote: Char;
  LCharacterIndex: Integer;
  LEmptyMapping: Boolean;
begin
  AHeaderStart := 0;
  AHeaderEnd := 0;
  AEntryStart := 0;
  AEntryEnd := 0;
  ASectionEnd := Length(AText) + 1;
  AIndent := 2;
  if TRegEx.IsMatch(AText, '[\t]|(^|\s)[&*!][a-zA-Z0-9_-]|^\s*(---|\.\.\.|%)', [roMultiLine]) then
    Conflict('YAML mit Tabs, Ankern, Aliasen, Tags, Direktiven oder mehreren Dokumenten wird nicht automatisch bearbeitet.');
  LLines := TStringList.Create;
  LRoots := TDictionary<string, Boolean>.Create;
  LServers := TDictionary<string, Boolean>.Create;
  try
    LLines.Text := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
    LOffset := 1;
    LHeader := False;
    LInEntry := False;
    LEmptyMapping := False;
    for LIndex := 0 to LLines.Count - 1 do
    begin
      LLine := LLines[LIndex];
      LTrim := Trim(LLine);
      LIndent := Length(LLine) - Length(TrimLeft(LLine));
      if (LTrim <> '') and not LTrim.StartsWith('#') then
      begin
        // Conservatively reject strings spanning physical lines before locating a mapping in their contents.
        LQuote := #0;
        LCharacterIndex := 1;
        while LCharacterIndex <= Length(LLine) do
        begin
          if (LQuote = #0) and (LLine[LCharacterIndex] = '#') then
            Break;
          if (LQuote = #0) and CharInSet(LLine[LCharacterIndex], ['"', '''']) then
            LQuote := LLine[LCharacterIndex]
          else if (LQuote = '"') and (LLine[LCharacterIndex] = '\') then
            Inc(LCharacterIndex)
          else if (LQuote <> #0) and (LLine[LCharacterIndex] = LQuote) then
          begin
            if (LQuote = '''') and (LCharacterIndex < Length(LLine)) and (LLine[LCharacterIndex + 1] = '''') then
              Inc(LCharacterIndex)
            else
              LQuote := #0;
          end;
          Inc(LCharacterIndex);
        end;
        if LQuote <> #0 then
          Conflict('Mehrzeilige YAML-Zeichenfolgen werden konservativ nicht automatisch bearbeitet.');
        if LIndent = 0 then
        begin
          LMatch := TRegEx.Match(LLine, '^([a-zA-Z_][a-zA-Z0-9_-]*):(?:\s|$)');
          if not LMatch.Success then
            Conflict('Nur einfache YAML-Root-Mappings werden automatisch bearbeitet.');
          LRootKey := LMatch.Groups[1].Value;
          if LRoots.ContainsKey(LRootKey) then
            Conflict('Doppelte YAML-Root-Schlüssel werden nicht bearbeitet.');
          LRoots.Add(LRootKey, True);
          if LHeader then
          begin
            ASectionEnd := LOffset;
            if LInEntry then AEntryEnd := LOffset;
            LHeader := False;
            LInEntry := False;
          end;
          if LRootKey = 'mcp_servers' then
          begin
            if not TRegEx.IsMatch(LLine, '^mcp_servers:\s*(\{\})?\s*(#.*)?$') then
              Conflict('Das YAML-MCP-Mapping verwendet nicht unterstützte Inline-Syntax.');
            AHeaderStart := LOffset;
            AHeaderEnd := LOffset + Length(LLine);
            LEmptyMapping := Pos('{}', LLine) > 0;
            LHeader := True;
          end;
        end
        else if LHeader then
        begin
          if LEmptyMapping then
            Conflict('Das leere YAML-Inline-Mapping besitzt zusätzlich eingerückte Werte.');
          if TRegEx.IsMatch(LTrim, ':\s*[|>]') then
            Conflict('Mehrzeilige YAML-Skalare im MCP-Bereich werden nicht automatisch bearbeitet.');
          if LServers.Count = 0 then
            AIndent := LIndent;
          if LIndent < AIndent then
            Conflict('Die Einrückung im YAML-MCP-Mapping ist mehrdeutig.');
          if LIndent = AIndent then
          begin
            LMatch := TRegEx.Match(LTrim, '^([a-zA-Z_][a-zA-Z0-9_-]*):(?:\s|$)');
            if not LMatch.Success then
              Conflict('Nur einfache YAML-MCP-Server-Schlüssel werden automatisch bearbeitet.');
            LRootKey := LMatch.Groups[1].Value;
            if LServers.ContainsKey(LRootKey) then
              Conflict('Doppelte YAML-MCP-Server werden nicht automatisch bearbeitet.');
            LServers.Add(LRootKey, True);
            if LInEntry then
              AEntryEnd := LOffset;
            LInEntry := LRootKey = AServerName;
            if LInEntry then
              AEntryStart := LOffset;
          end;
        end;
      end;
      Inc(LOffset, Length(LLine));
      if (LOffset <= Length(AText)) and (AText[LOffset] = #13) then
        Inc(LOffset);
      if (LOffset <= Length(AText)) and (AText[LOffset] = #10) then
        Inc(LOffset);
    end;
    if LInEntry then
      AEntryEnd := Length(AText) + 1;
    Result := AEntryStart > 0;
  finally
    LServers.Free;
    LRoots.Free;
    LLines.Free;
  end;
end;

function YamlMerge(const AText, AEntry, AServerName: string; ARemove: Boolean): string;
var
  LHeaderStart, LHeaderEnd, LEntryStart, LEntryEnd, LSectionEnd, LIndent: Integer;
  LExists: Boolean;
  LAddition: string;
  LLine: string;
  LLines: TStringList;
  LEndOfLine: string;
  LHeader: string;
  LHeaderSuffix: string;
  LInsertionPosition: Integer;
begin
  Result := AText;
  LExists := YamlRanges(AText, AServerName, LHeaderStart, LHeaderEnd, LEntryStart, LEntryEnd, LSectionEnd, LIndent);
  if ARemove and not LExists then
    Exit;
  if LExists then
    Delete(Result, LEntryStart, LEntryEnd - LEntryStart);
  if ARemove then
    Exit;
  LEndOfLine := EndOfLine(AText);
  LLines := TStringList.Create;
  try
    LLines.Text := AEntry;
    LAddition := '';
    for LLine in LLines do
      LAddition := LAddition + StringOfChar(' ', LIndent) + LLine + LEndOfLine;
  finally
    LLines.Free;
  end;
  if LExists then
    Insert(LAddition, Result, LEntryStart)
  else if LHeaderStart > 0 then
  begin
    LHeader := Copy(Result, LHeaderStart, LHeaderEnd - LHeaderStart);
    if Pos('{}', LHeader) > 0 then
    begin
      // Remove only the empty inline value and retain any comment on its header.
      LHeaderSuffix := Copy(LHeader, Pos('{}', LHeader) + 2, MaxInt);
      LHeader := 'mcp_servers:' + LHeaderSuffix;
      Delete(Result, LHeaderStart, LHeaderEnd - LHeaderStart);
      Insert(LHeader, Result, LHeaderStart);
      LHeaderEnd := LHeaderStart + Length(LHeader);
    end;
    LInsertionPosition := LHeaderEnd;
    if (LInsertionPosition <= Length(Result)) and (Result[LInsertionPosition] = #13) then
      Inc(LInsertionPosition);
    if (LInsertionPosition <= Length(Result)) and (Result[LInsertionPosition] = #10) then
      Inc(LInsertionPosition)
    else
    begin
      Insert(LEndOfLine, Result, LInsertionPosition);
      Inc(LInsertionPosition, Length(LEndOfLine));
    end;
    Insert(LAddition, Result, LInsertionPosition);
  end
  else
  begin
    if (Result <> '') and not Result.EndsWith(#10) then
      Result := Result + LEndOfLine;
    Result := Result + 'mcp_servers:' + LEndOfLine + LAddition;
  end;
  YamlRanges(Result, AServerName, LHeaderStart, LHeaderEnd, LEntryStart, LEntryEnd, LSectionEnd, LIndent);
end;

class function TDAIClientConfigText.ExtractEntry(const AText, AFormat: string; const AKeys: TArray<string>; out AEntry: string): Boolean;
var
  LRoot: TConfigNode;
  LEntry: TConfigNode;
  LHeaderStart, LHeaderEnd, LEntryStart, LEntryEnd, LSectionEnd, LIndent: Integer;
begin
  AEntry := '';
  if SameText(AFormat, 'yaml') then
  begin
    if (Length(AKeys) <> 2) or (AKeys[0] <> 'mcp_servers') or
      not TRegEx.IsMatch(AKeys[1], '^[a-zA-Z_][a-zA-Z0-9_-]*$') then
      Conflict('Der YAML-MCP-Konfigurationspfad wird nicht unterstützt.');
    Result := YamlRanges(AText, AKeys[1], LHeaderStart, LHeaderEnd, LEntryStart, LEntryEnd, LSectionEnd, LIndent);
    if Result then
      AEntry := Trim(Copy(AText, LEntryStart, LEntryEnd - LEntryStart));
    Exit;
  end;
  LRoot := ParseJson(AText, AFormat);
  try
    LEntry := Locate(LRoot, AKeys);
    Result := LEntry <> nil;
    if Result then
      AEntry := Copy(AText, LEntry.Start, LEntry.Finish - LEntry.Start + 1);
  finally
    LRoot.Free;
  end;
end;

class function TDAIClientConfigText.Merge(const AText, AFormat: string; const AKeys: TArray<string>; const AEntry: string; ARemove: Boolean): string;
begin
  if Length(AKeys) = 0 then
    Conflict('Der MCP-Konfigurationspfad fehlt.');
  if SameText(AFormat, 'yaml') then
  begin
    if (Length(AKeys) <> 2) or (AKeys[0] <> 'mcp_servers') or
      not TRegEx.IsMatch(AKeys[1], '^[a-zA-Z_][a-zA-Z0-9_-]*$') then
      Conflict('Der YAML-MCP-Konfigurationspfad wird nicht unterstützt.');
    Result := YamlMerge(AText, AEntry, AKeys[1], ARemove);
  end
  else if SameText(AFormat, 'json') or SameText(AFormat, 'jsonc') or SameText(AFormat, 'json5') then
    Result := JsonMerge(AText, AFormat, AKeys, AEntry, ARemove)
  else
    Conflict('Das Konfigurationsformat wird nicht unterstützt.');
end;

end.
