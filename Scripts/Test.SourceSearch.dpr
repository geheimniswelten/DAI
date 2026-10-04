program TestSourceSearch;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.Diagnostics,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Source.Regex,
  h5u.DAI.Source.Search;

var
  CheckCount: Integer;
  FixtureRoot: string;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function EmptyOptions: TDAISourceSearchOptions;
begin
  Result := Default(TDAISourceSearchOptions);
end;

function Matches(const AResult: TJSONObject): TJSONArray;
begin
  Result := AResult.GetValue<TJSONArray>('matches');
end;

function Hit(const AResult: TJSONObject; AIndex: Integer = 0): TJSONObject;
begin
  Result := Matches(AResult).Items[AIndex] as TJSONObject;
end;

function SnapshotResult(const AContent, AQuery: string; const AOptions: TDAISourceSearchOptions): TJSONObject;
var
  LSnapshots: TDictionary<string, TDAISourceSnapshot>;
  LSnapshot: TDAISourceSnapshot;
begin
  LSnapshots := TDictionary<string, TDAISourceSnapshot>.Create;
  try
    LSnapshot.Content := AContent;
    LSnapshot.Source := 'editor_buffer';
    LSnapshots.Add(TPath.Combine(FixtureRoot, 'Editor.pas'), LSnapshot);
    Result := TDAISourceSearch.Search(AQuery, nil, nil, nil, LSnapshots, AOptions);
  finally
    LSnapshots.Free;
  end;
end;

procedure ExpectInvalidQuery(const AQuery: string);
var
  LResult: TJSONObject;
  LRejected: Boolean;
begin
  LResult := nil;
  LRejected := False;
  try
    try
      LResult := TDAISourceSearch.Search(AQuery, nil, nil, nil, nil, EmptyOptions);
    except
      on E: EArgumentException do
        LRejected := True;
    end;
  finally
    LResult.Free;
  end;
  Check(LRejected, 'Invalid query rejected');
end;

procedure ExpectInvalidPatterns(const APatterns: TArray<string>);
var
  LRejected: Boolean;
  LOptions: TDAISourceSearchOptions;
  LResult: TJSONObject;
begin
  LRejected := False;
  try
    TDAISourceSearch.MatchesFilePatterns('File.pas', APatterns);
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'Public pattern check rejects unsupported/oversized patterns before any early match');
  LOptions := EmptyOptions;
  LOptions.FilePatterns := APatterns;
  LRejected := False;
  LResult := nil;
  try
    try
      LResult := TDAISourceSearch.Search('needle', nil, nil, nil, nil, LOptions);
    except
      on E: EArgumentException do
        LRejected := True;
    end;
  finally
    LResult.Free;
  end;
  Check(LRejected, 'Search rejects invalid patterns even without any files');
end;

procedure TestBoundedGlobs;
var
  LOptions: TDAISourceSearchOptions;
  LResult: TJSONObject;
  LSnapshots: TDictionary<string, TDAISourceSnapshot>;
  LSnapshot: TDAISourceSnapshot;
  LPatterns: TArray<string>;
  LPattern: string;
  LClock: TStopwatch;
  I: Integer;
begin
  Check(TDAISourceSearch.MatchesFilePatterns('C:\Folder\AbC.PAS', TArray<string>.Create('a?c.pas')), 'Filename-only case-insensitive ? wildcard');
  Check(TDAISourceSearch.MatchesFilePatterns('abc.pas', TArray<string>.Create('*a*b*c*.pas')), 'Several stars match');
  Check(TDAISourceSearch.MatchesFilePatterns('abc.pas', TArray<string>.Create('***.pas')), 'Consecutive stars');
  Check(not TDAISourceSearch.MatchesFilePatterns('abc.pas', TArray<string>.Create('*a*b*c*.inc')), 'Star suffix must match');
  Check(not TDAISourceSearch.MatchesFilePatterns('abc.pas', TArray<string>.Create('a?c')), 'Pattern matches the whole filename');
  Check(TDAISourceSearch.MatchesFilePatterns('Grüße.PAS', TArray<string>.Create('GRÜßE.pas')), 'Unicode filename case folding');
  Check(TDAISourceSearch.MatchesFilePatterns(#$D83D#$DE00 + '.pas', TArray<string>.Create('?.pas')), '? consumes one supplementary Unicode character');
  Check(TDAISourceSearch.MatchesFilePatterns(#$D801#$DC28 + '.pas', TArray<string>.Create(#$D801#$DC28 + '.PAS')), 'Supplementary filename literal and extension folding');
  Check(TDAISourceSearch.MatchesFilePatterns(StringOfChar('a', 255), TArray<string>.Create('*' + StringOfChar('a', 255))), '256-character pattern accepted');
  Check(not TDAISourceSearch.MatchesFilePatterns(StringOfChar('a', 256), nil), 'Filename component bounded to 255 UTF-16 characters');
  SetLength(LPatterns, 100);
  for I := 0 to High(LPatterns) do
    LPatterns[I] := '*.pas';
  Check(TDAISourceSearch.MatchesFilePatterns('File.pas', LPatterns), '100 patterns accepted');
  SetLength(LPatterns, 101);
  LPatterns[100] := '*.pas';
  ExpectInvalidPatterns(LPatterns);
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', ''));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', StringOfChar('a', 257)));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', '[abc].pas'));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', 'abc].pas'));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', '*' + #0));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', '*' + #10));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', '*' + #13));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', 'Folder\*.pas'));
  ExpectInvalidPatterns(TArray<string>.Create('*.pas', 'Folder/*.pas'));

  LPattern := '';
  for I := 1 to 30 do
    LPattern := LPattern + '*a';
  LPattern := LPattern + 'b';
  LClock := TStopwatch.StartNew;
  Check(not TDAISourceSearch.MatchesFilePatterns(StringOfChar('a', 120) + '.pas', TArray<string>.Create(LPattern)), 'Former exponential-backtracking mask fails normally');
  Check(LClock.ElapsedMilliseconds < 1000, 'Former ReDoS case completes within bounded time');

  LOptions := EmptyOptions;
  LOptions.TimeoutMs := 1;
  SetLength(LOptions.FilePatterns, 100);
  for I := 0 to High(LOptions.FilePatterns) do
    LOptions.FilePatterns[I] := '*' + StringOfChar('a', 119) + 'b';
  LSnapshots := TDictionary<string, TDAISourceSnapshot>.Create;
  try
    LSnapshot.Content := 'needle';
    LSnapshot.Source := 'editor_buffer';
    for I := 1 to 30 do
      LSnapshots.Add(TPath.Combine(FixtureRoot, StringOfChar('a', 240) + IntToStr(I) + '.pas'), LSnapshot);
    LClock := TStopwatch.StartNew;
    LResult := TDAISourceSearch.Search('needle', nil, nil, nil, LSnapshots, LOptions);
    try
      Check(LResult.GetValue<Boolean>('truncated'), 'Budget covers unsuccessful glob matching');
      Check(LResult.GetValue<string>('limit_reason') = 'timeout', 'Glob timeout reason');
      Check(LClock.ElapsedMilliseconds < 1000, 'Glob matching stops cooperatively within bounded time');
    finally
      LResult.Free;
    end;
  finally
    LSnapshots.Free;
  end;
end;

procedure TestLiteralAndCoordinates;
var
  LResult: TJSONObject;
  LOptions: TDAISourceSearchOptions;
begin
  LOptions := EmptyOptions;
  LResult := SnapshotResult('first' + #13#10 + 'α Grüße 漢字 ' + #$D83D#$DE00 + #10 + 'third' + #13 + 'fourth', '漢字', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Unicode literal found');
    Check(Hit(LResult).GetValue<Integer>('line') = 2, 'CRLF is one line break');
    Check(Hit(LResult).GetValue<Integer>('column') = 9, 'Unicode column is one-based UTF-16 position');
    Check(Hit(LResult).GetValue<string>('excerpt') = 'α Grüße 漢字 ' + #$D83D#$DE00, 'Unicode excerpt');
    Check(Hit(LResult).GetValue<Integer>('excerpt_column') = 1, 'Full excerpt begins at column one');
    Check(not Hit(LResult).GetValue<Boolean>('excerpt_truncated'), 'Short excerpt complete');
    Check(Hit(LResult).GetValue<string>('source') = 'editor_buffer', 'Snapshot source retained');
    Check(not LResult.GetValue<Boolean>('truncated'), 'Complete search not truncated');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('first' + #13#10 + 'second' + #10 + 'third' + #13 + 'fourth', 'fourth', LOptions);
  try
    Check(Hit(LResult).GetValue<Integer>('line') = 4, 'Mixed CRLF/LF/CR line counting');
    Check(Hit(LResult).GetValue<Integer>('column') = 1, 'First character column');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('aaa', 'aa', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Overlapping literal occurrences');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('a.b aXb', 'a.b', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Query is literal rather than a regex');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('  ', ' ', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Whitespace is a valid literal query');
  finally
    LResult.Free;
  end;
end;

procedure TestCaseAndWholeWord;
var
  LResult: TJSONObject;
  LOptions: TDAISourceSearchOptions;
begin
  LOptions := EmptyOptions;
  LResult := SnapshotResult('Grüße GRÜßE Grüße', 'grüße', LOptions);
  try
    Check(Matches(LResult).Count = 3, 'Ordinal Unicode case-insensitive matching');
  finally
    LResult.Free;
  end;
  LOptions.CaseSensitive := True;
  LResult := SnapshotResult('TButton tbutton TButton', 'TButton', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Case-sensitive matching');
  finally
    LResult.Free;
  end;
  LOptions.WholeWord := True;
  LResult := SnapshotResult('TButton TButtonX _TButton TButton_ αTButton TButton漢 TButton' + #$0301 + ' (TButton)', 'TButton', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Whole word excludes letters, Unicode, underscores and combining marks');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult(#$D801#$DC00 + 'TButton TButton' + #$D801#$DC00 + ' TButton', 'TButton', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Supplementary Unicode letters form whole-word boundaries');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('X' + #$D83D#$DE00 + 'Y', #$D83D#$DE00, EmptyOptions);
  try
    Check(Matches(LResult).Count = 1, 'Supplementary Unicode literal matches');
    Check(Hit(LResult).GetValue<Integer>('column') = 2, 'Supplementary query column');
  finally
    LResult.Free;
  end;
end;

procedure TestRegex;
var
  LOptions: TDAISourceSearchOptions;
  LResult: TJSONObject;
  LRegex: TDAIRegex;
  LMatch: TDAIRegexMatch;
  LRejected: Boolean;
  LClock: TStopwatch;
  LPattern: string;
  LContent: string;
  LFileName: string;
begin
  LOptions := EmptyOptions;
  LOptions.UseRegex := True;
  LResult := SnapshotResult('a.b aXb', 'a.b', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Regex explicitly enabled interprets dot');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('head' + #13#10 + #$D83D#$DE00 + ' needle42' + #10 + 'needle7', 'needle\d+', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Regex variable length matches');
    Check(Hit(LResult).GetValue<Integer>('line') = 2, 'Regex preserves CRLF line coordinates');
    Check(Hit(LResult).GetValue<Integer>('column') = 4, 'Regex columns count UTF-16 surrogate code units');
    Check(Hit(LResult, 1).GetValue<Integer>('line') = 3, 'Regex preserves LF line coordinates');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('first' + #13#10 + 'needle' + #13#10 + 'tail', '(?m)^needle\r\ntail$', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Multiline regex searches current full subject');
    Check(Hit(LResult).GetValue<Integer>('line') = 2, 'Multiline hit starts on its original line');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('prefix needle prefix needle', '(?<=prefix )needle', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Starting subsequent matches retains lookbehind context');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('TButton tbutton', 'TButton', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Regex uses case_sensitive=false');
  finally
    LResult.Free;
  end;
  LOptions.CaseSensitive := True;
  LResult := SnapshotResult('TButton tbutton', 'TButton', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Regex uses case_sensitive=true');
  finally
    LResult.Free;
  end;
  LOptions.WholeWord := True;
  LResult := SnapshotResult('TButton TEditX _TEdit TEdit' + #$0301 + ' (TEdit) ' + #$D801#$DC00 + 'TButton',
    'T(?:Button|Edit)', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Whole-word boundaries surround the entire variable regex match');
  finally
    LResult.Free;
  end;
  LOptions.WholeWord := False;
  LResult := SnapshotResult(#$D83D#$DE00, '(?=)', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Zero-length regex makes progress without splitting a surrogate pair');
    Check(Hit(LResult, 1).GetValue<Integer>('column') = 3, 'Zero-length EOF hit has one-based UTF-16 column');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('', '$', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Empty subject allows its single zero-length EOF match');
    Check(Hit(LResult).GetValue<Integer>('column') = 1, 'Empty subject EOF column');
  finally
    LResult.Free;
  end;
  LOptions.MaximumResults := 2;
  LResult := SnapshotResult('abcd', '.', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Regex honors maximum_results');
    Check(LResult.GetValue<string>('limit_reason') = 'maximum_results', 'Regex result truncation is explicit');
  finally
    LResult.Free;
  end;
  LOptions := EmptyOptions;
  LOptions.FilenameRegex := '^editor\.pas$';
  LResult := SnapshotResult('a.b aXb', 'a.b', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Filename regex does not reinterpret a literal query');
  finally
    LResult.Free;
  end;
  LOptions.CaseSensitive := True;
  LResult := SnapshotResult('needle', 'needle', LOptions);
  try
    Check(Matches(LResult).Count = 0, 'Filename regex obeys case_sensitive');
    Check(LResult.GetValue<Integer>('files_scanned') = 0, 'Filename regex excludes content before scanning');
  finally
    LResult.Free;
  end;
  LOptions.CaseSensitive := False;
  LOptions.FilePatterns := TArray<string>.Create('*.inc');
  LResult := SnapshotResult('needle', 'needle', LOptions);
  try
    Check(Matches(LResult).Count = 0, 'Filename regex and file_patterns are combined with AND');
  finally
    LResult.Free;
  end;
  LOptions := EmptyOptions;
  LOptions.UseRegex := True;
  LOptions.InterfacesOnly := True;
  LResult := SnapshotResult('unit Sample; interface procedure PublicAPI; implementation procedure PrivateAPI; begin end; end.',
    '(?:Public|Private)API', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Regex preserves interface-only source view');
    Check(LResult.GetValue<Integer>('implementation_files_omitted') = 1, 'Regex interface omission is counted');
  finally
    LResult.Free;
  end;

  LRejected := False;
  try
    LResult := TDAISourceSearch.Search('(', [TPath.Combine(FixtureRoot, 'MissingRoot')], nil, nil, nil, LOptions);
    LResult.Free;
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'Invalid content regex is rejected even without candidate files');
  LOptions := EmptyOptions;
  LOptions.FilenameRegex := '[';
  LRejected := False;
  try
    LResult := TDAISourceSearch.Search('needle', nil, nil, nil, nil, LOptions);
    LResult.Free;
  except
    on E: EArgumentException do
      LRejected := True;
  end;
  Check(LRejected, 'Invalid filename regex is rejected before file enumeration');

  LRegex := TDAIRegex.Create('$', True);
  try
    LMatch := LRegex.Match('x', 2);
    Check(LMatch.Success and (LMatch.Index = 2) and (LMatch.Length = 0), 'Wrapper supports a 1-based EOF start position');
    LRejected := False;
    try
      LRegex.Match('x', 3);
    except
      on E: EArgumentOutOfRangeException do
        LRejected := True;
    end;
    Check(LRejected, 'Wrapper rejects start beyond EOF');
  finally
    LRegex.Free;
  end;
  for LPattern in TArray<string>.Create('(*NO_START_OPT)^(a+)+$',
    '(*LIMIT_MATCH=999999999)(*NO_START_OPT)^(a+)+$', '^(a(?1)?b)$') do
  begin
    LRegex := TDAIRegex.Create(LPattern, True);
    try
      LRejected := False;
      LClock := TStopwatch.StartNew;
      try
        if LPattern = '^(a(?1)?b)$' then
          LRegex.IsMatch(StringOfChar('a', 400) + StringOfChar('b', 400))
        else
          LRegex.IsMatch(StringOfChar('a', 100) + '!');
      except
        on E: EInvalidOperation do
          LRejected := Pos('limit', E.Message) > 0;
      end;
      Check(LRejected, 'PCRE match/recursion budget failure is explicit, including raised inline limits');
      Check(LClock.ElapsedMilliseconds < 1000, 'Pathological regex is stopped within bounded time');
    finally
      LRegex.Free;
    end;
  end;
  LRegex := TDAIRegex.Create('\w+', True);
  try
    LMatch := LRegex.Match('漢字');
    Check(LMatch.Success and (LMatch.Length = 2), 'PCRE_UCP gives Unicode semantics to regex character classes');
  finally
    LRegex.Free;
  end;
  LRegex := TDAIRegex.Create('needle', True);
  try
    LClock := TStopwatch.StartNew;
    Check(not LRegex.IsMatch(StringOfChar('x', 128 * 1024)), 'Ordinary large no-hit regex scan completes normally');
    Check(LClock.ElapsedMilliseconds < 500, 'Ordinary no-hit does not revalidate the entire UTF-16 subject per candidate');
  finally
    LRegex.Free;
  end;
  LRegex := TDAIRegex.Create('(*NO_START_OPT)(a+)+b', True);
  try
    LRejected := False;
    LClock := TStopwatch.StartNew;
    try
      LRegex.IsMatch(StringOfChar('a', 100) + '!');
    except
      on E: EInvalidOperation do
        LRejected := Pos('limit', E.Message) > 0;
    end;
    Check(LRejected, 'Unanchored pathological regex hits explicit PCRE execution budget');
    Check(LClock.ElapsedMilliseconds < 1000, 'Unanchored pathological regex is bounded');
  finally
    LRegex.Free;
  end;
  LRegex := TDAIRegex.Create('(*NO_START_OPT)(?:a|aa){1,10}b', True);
  try
    LRejected := False;
    LClock := TStopwatch.StartNew;
    try
      LRegex.IsMatch(StringOfChar('a', 128 * 1024));
    except
      on E: EInvalidOperation do
        LRejected := Pos('time limit', E.Message) > 0;
    end;
    Check(LRejected, 'Many sub-budget candidate attempts hit the whole-scan time budget');
    Check(LClock.ElapsedMilliseconds < 1500, 'Whole-scan budget bounds repeated unanchored backtracking');
  finally
    LRegex.Free;
  end;
  LOptions := EmptyOptions;
  LOptions.UseRegex := True;
  LFileName := TPath.Combine(FixtureRoot, 'RegexBudget.pas');
  TFile.WriteAllText(LFileName, StringOfChar('a', 100) + '!', TEncoding.UTF8);
  LRejected := False;
  try
    LResult := TDAISourceSearch.Search('(*NO_START_OPT)(a+)+b', nil, [LFileName], nil, nil, LOptions);
    LResult.Free;
  except
    on E: EInvalidOperation do
      LRejected := Pos('limit', E.Message) > 0;
  end;
  Check(LRejected, 'Disk-source regex limit failure is propagated instead of reporting an ordinary miss');
  LRejected := False;
  try
    LResult := SnapshotResult(StringOfChar('a', 100) + '!', '(*NO_START_OPT)(a+)+b', LOptions);
    LResult.Free;
  except
    on E: EInvalidOperation do
      LRejected := Pos('limit', E.Message) > 0;
  end;
  Check(LRejected, 'Editor-source regex limit failure uses the same explicit failure path');
  for LPattern in TArray<string>.Create('\Gneedle', '(*SKIP)needle', '(*COMMIT)needle', '(*PRUNE)needle', '(*THEN)needle', '(', '[',
    StringOfChar('x', 257), 'x' + #0, 'x' + #10, 'x' + #13) do
  begin
    LRegex := nil;
    LRejected := False;
    try
      try
        LRegex := TDAIRegex.Create(LPattern, True);
      except
        on E: EArgumentException do
          LRejected := True;
      end;
      Check(LRejected, 'Unsupported, invalid and unbounded regex inputs fail safely during construction');
    finally
      LRegex.Free;
    end;
  end;
  LRegex := TDAIRegex.Create('.', True);
  try
    LContent := #$D83D#$DE00;
    LMatch := LRegex.Match(LContent);
    Check(LMatch.Success and (LMatch.Length = 2), 'PCRE16 dot consumes an entire supplementary character');
    LRejected := False;
    try
      LRegex.Match(LContent, 2);
    except
      on E: EInvalidOperation do
        LRejected := True;
    end;
    Check(LRejected, 'Wrapper rejects a start offset inside a UTF-16 surrogate pair');
    LRejected := False;
    try
      LRegex.Match(#$D83D);
    except
      on E: EInvalidOperation do
        LRejected := True;
    end;
    Check(LRejected, 'Malformed UTF-16 source is reported explicitly');
  finally
    LRegex.Free;
  end;
end;

procedure TestExcerptsAndLimits;
var
  LResult: TJSONObject;
  LOptions: TDAISourceSearchOptions;
begin
  LResult := SnapshotResult(StringOfChar('x', 500) + 'needle' + StringOfChar('x', 500), 'needle', EmptyOptions);
  try
    Check(Hit(LResult).GetValue<Integer>('column') = 501, 'Long-line actual match column');
    Check(Hit(LResult).GetValue<Integer>('excerpt_column') = 421, 'Excerpt offset disclosed');
    Check(Length(Hit(LResult).GetValue<string>('excerpt')) <= 240, 'Excerpt bounded');
    Check(Hit(LResult).GetValue<Boolean>('excerpt_truncated'), 'Excerpt truncation disclosed');
  finally
    LResult.Free;
  end;
  LOptions := EmptyOptions;
  LOptions.MaximumResults := 2;
  LResult := SnapshotResult('needle needle needle', 'needle', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Result limit');
    Check(LResult.GetValue<Boolean>('truncated'), 'Result limit truncation');
    Check(LResult.GetValue<string>('limit_reason') = 'maximum_results', 'Result limit reason');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult(StringOfChar('a', 250), 'a', EmptyOptions);
  try
    Check(Matches(LResult).Count = 200, 'Default result limit');
  finally
    LResult.Free;
  end;
  LOptions.MaximumResults := 5000;
  LResult := SnapshotResult(StringOfChar('a', 1200), 'a', LOptions);
  try
    Check(Matches(LResult).Count = 1000, 'Result cap');
  finally
    LResult.Free;
  end;
  LOptions := EmptyOptions;
  LOptions.TimeoutMs := 1;
  LResult := SnapshotResult(StringOfChar('x', 2 * 1024 * 1024), 'absent', LOptions);
  try
    Check(LResult.GetValue<Boolean>('truncated'), 'Timeout interrupts a long single line');
    Check(LResult.GetValue<string>('limit_reason') = 'timeout', 'Timeout reason');
    Check(LResult.GetValue<Integer>('elapsed_ms') < 1000, 'Timeout checked inside content scan');
  finally
    LResult.Free;
  end;
end;

procedure WriteFixture(const AFileName, AContent: string; const AEncoding: TEncoding);
begin
  ForceDirectories(TPath.GetDirectoryName(AFileName));
  TFile.WriteAllText(AFileName, AContent, AEncoding);
end;

procedure TestInterfaceSnapshots;
var
  LContent: string;
  LResult: TJSONObject;
  LOptions: TDAISourceSearchOptions;
  LBoundary: Integer;
begin
  LOptions := EmptyOptions;
  LOptions.InterfacesOnly := True;
  LContent := 'unit Sample;' + #13#10 + 'interface' + #13#10 + '// implementation in a comment' + #13#10 +
    'const Caption = ''implementation'';' + #13#10 + 'procedure PublicAPI;' + #13#10 + 'ImPlEmEnTaTiOn' + #13#10 +
    'procedure PublicAPI; begin end;' + #13#10 + 'procedure PrivateAPI; begin end;' + #13#10 + 'end.';
  LResult := SnapshotResult(LContent, 'PublicAPI', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Interface mode excludes an implementation declaration in an editor snapshot');
    Check(Hit(LResult).GetValue<Integer>('line') = 5, 'Interface mode retains original line numbers');
    Check(Hit(LResult).GetValue<Integer>('column') = 11, 'Interface mode retains original columns');
    Check(Hit(LResult).GetValue<string>('excerpt') = 'procedure PublicAPI;', 'Interface declaration excerpt');
    Check(LResult.GetValue<Boolean>('interfaces_only'), 'Interface mode disclosed in result');
    Check(LResult.GetValue<Integer>('implementation_files_omitted') = 1, 'Filtered snapshot counted once');
    Check(LResult.GetValue<Integer>('files_scanned') = 1, 'Interface filtering keeps file accounting');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult(LContent, 'PrivateAPI', LOptions);
  try
    Check(Matches(LResult).Count = 0, 'Private implementation content is not searched');
    Check(LResult.GetValue<Integer>('implementation_files_omitted') = 1, 'Omitted implementation counted even without a hit');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult(LContent, 'implementation', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Comment and string implementations do not end the interface view');
    Check(Hit(LResult, 1).GetValue<Integer>('line') = 4, 'String token remains in original interface line');
  finally
    LResult.Free;
  end;
  LOptions.InterfacesOnly := False;
  LResult := SnapshotResult(LContent, 'PublicAPI', LOptions);
  try
    Check(Matches(LResult).Count = 2, 'Explicit full-text mode searches editor implementation');
    Check(not LResult.GetValue<Boolean>('interfaces_only'), 'Full-text mode disclosed in result');
    Check(LResult.GetValue<Integer>('implementation_files_omitted') = 0, 'Full-text mode omits no implementations');
  finally
    LResult.Free;
  end;
  LOptions.InterfacesOnly := True;
  LContent := 'unit SameLine; interface procedure BoundaryAPI; implementation procedure SecretAPI; begin end; end.';
  LBoundary := Pos('implementation', LContent);
  LResult := SnapshotResult(LContent, 'BoundaryAPI', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Declaration immediately before same-line implementation retained');
    Check(Hit(LResult).GetValue<Integer>('column') = Pos('BoundaryAPI', LContent), 'Same-line boundary retains column');
    Check(Hit(LResult).GetValue<string>('excerpt') = Copy(LContent, 1, LBoundary - 1), 'Excerpt cannot leak same-line implementation');
    Check(not Hit(LResult).GetValue<Boolean>('excerpt_truncated'), 'Interface boundary is a complete view, not an excerpt length limit');
    Check(Pos('SecretAPI', LResult.ToJSON) = 0, 'Implementation never appears in interface response');
  finally
    LResult.Free;
  end;
  LResult := SnapshotResult('program Example; implementation needle', 'needle', LOptions);
  try
    Check(Matches(LResult).Count = 1, 'A non-unit Pascal source stays complete');
    Check(LResult.GetValue<Integer>('implementation_files_omitted') = 0, 'Non-unit source counted as unfiltered');
  finally
    LResult.Free;
  end;
end;

procedure TestInterfaceDiskAndFileKinds;
var
  LDirectory: string;
  LUnitFile: string;
  LContent: string;
  LFiles: TArray<string>;
  LFileName: string;
  LOptions: TDAISourceSearchOptions;
  LResult: TJSONObject;
  LSnapshots: TDictionary<string, TDAISourceSnapshot>;
  LSnapshot: TDAISourceSnapshot;
begin
  LDirectory := TPath.Combine(FixtureRoot, 'InterfaceSources');
  LUnitFile := TPath.Combine(LDirectory, 'Disk.PAS');
  LContent := 'unit Disk; interface procedure DiskAPI; implementation procedure DiskPrivate; begin end; end.';
  WriteFixture(LUnitFile, LContent, TEncoding.Unicode);
  LOptions := EmptyOptions;
  LOptions.InterfacesOnly := True;
  LResult := TDAISourceSearch.Search('DiskAPI', nil, TArray<string>.Create(LUnitFile), nil, nil, LOptions);
  try
    Check(Matches(LResult).Count = 1, 'Disk UTF-16 source interface declaration found');
    Check(Hit(LResult).GetValue<string>('source') = 'disk', 'Interface mode retains disk source');
    Check(Hit(LResult).GetValue<Integer>('column') = Pos('DiskAPI', LContent), 'Disk interface keeps original column');
    Check(LResult.GetValue<Integer>('implementation_files_omitted') = 1, 'Uppercase Pascal extension filtered');
  finally
    LResult.Free;
  end;
  LResult := TDAISourceSearch.Search('DiskPrivate', nil, TArray<string>.Create(LUnitFile), nil, nil, LOptions);
  try
    Check(Matches(LResult).Count = 0, 'Disk implementation is excluded');
  finally
    LResult.Free;
  end;
  LSnapshots := TDictionary<string, TDAISourceSnapshot>.Create;
  try
    LSnapshot.Content := 'unit Disk; interface procedure BufferAPI; implementation procedure BufferPrivate; begin end; end.';
    LSnapshot.Source := 'designer_buffer';
    LSnapshots.Add(LUnitFile, LSnapshot);
    LResult := TDAISourceSearch.Search('API', TArray<string>.Create(LDirectory), TArray<string>.Create(LUnitFile), nil, LSnapshots, LOptions);
    try
      Check(Matches(LResult).Count = 1, 'Filtered authoritative snapshot supersedes disk');
      Check(Hit(LResult).GetValue<string>('excerpt').Contains('BufferAPI'), 'Fresh snapshot interface is searched');
      Check(Hit(LResult).GetValue<string>('source') = 'designer_buffer', 'Filtered designer source classification');
      Check(LResult.GetValue<Integer>('implementation_files_omitted') = 1, 'Overlapping disk and snapshot filtered once');
    finally
      LResult.Free;
    end;
    LOptions.InterfacesOnly := False;
    LResult := TDAISourceSearch.Search('BufferPrivate', nil, TArray<string>.Create(LUnitFile), nil, LSnapshots, LOptions);
    try
      Check(Matches(LResult).Count = 1, 'Snapshot remains available for explicit full-text search');
    finally
      LResult.Free;
    end;
  finally
    LSnapshots.Free;
  end;
  LFiles := TArray<string>.Create(TPath.Combine(LDirectory, 'Include.inc'), TPath.Combine(LDirectory, 'Program.dpr'),
    TPath.Combine(LDirectory, 'Package.dpk'), TPath.Combine(LDirectory, 'Notes.txt'));
  for LFileName in LFiles do
    WriteFixture(LFileName, 'unit Borrowed; interface procedure PublicAPI; implementation needle', TEncoding.UTF8);
  LOptions.InterfacesOnly := True;
  LOptions.FilePatterns := TArray<string>.Create('*');
  LResult := TDAISourceSearch.Search('needle', nil, LFiles, nil, nil, LOptions);
  try
    Check(Matches(LResult).Count = 4, 'Include, program, package and other extensions remain complete');
    Check(LResult.GetValue<Integer>('implementation_files_omitted') = 0, 'Other file kinds are never counted as omitted');
  finally
    LResult.Free;
  end;
end;

procedure TestDiskSnapshotsAndPatterns;
var
  LProject: string;
  LNested: string;
  LFirst: string;
  LSecond: string;
  LResult: TJSONObject;
  LOptions: TDAISourceSearchOptions;
  LSnapshots: TDictionary<string, TDAISourceSnapshot>;
  LSnapshot: TDAISourceSnapshot;
  LMissing: TArray<string>;
  I: Integer;
begin
  Check(TDAISourceSearch.MatchesFilePatterns('Unit.PAS', nil), 'Default patterns case-insensitive');
  Check(TDAISourceSearch.MatchesFilePatterns('Package.dpk', nil), 'Default package pattern');
  Check(TDAISourceSearch.MatchesFilePatterns('Program.dpr', nil), 'Default program pattern');
  Check(TDAISourceSearch.MatchesFilePatterns('Include.inc', nil), 'Default include pattern');
  Check(not TDAISourceSearch.MatchesFilePatterns('Notes.txt', nil), 'Default non-source excluded');
  Check(TDAISourceSearch.MatchesFilePatterns('Notes.txt', TArray<string>.Create('*.txt')), 'Explicit patterns');
  LProject := TPath.Combine(FixtureRoot, 'Project');
  LNested := TPath.Combine(LProject, 'Nested');
  LFirst := TPath.Combine(LNested, 'First.pas');
  LSecond := TPath.Combine(LProject, 'Second.inc');
  WriteFixture(LFirst, 'disk stale TButton', TEncoding.UTF8);
  WriteFixture(LSecond, 'disk IOTADebuggerServices', TEncoding.Unicode);
  WriteFixture(TPath.Combine(LProject, 'Notes.txt'), 'IOTADebuggerServices', TEncoding.UTF8);
  LSnapshots := TDictionary<string, TDAISourceSnapshot>.Create;
  try
    LSnapshot.Content := 'buffer fresh IOTADebuggerServices';
    LSnapshot.Source := 'designer_buffer';
    LSnapshots.Add(UpperCase(LFirst), LSnapshot);
    LResult := TDAISourceSearch.Search('IOTADebuggerServices', TArray<string>.Create(LProject, LNested),
      TArray<string>.Create(LFirst, LowerCase(LFirst)), TArray<string>.Create(LNested), LSnapshots, EmptyOptions);
    try
      Check(Matches(LResult).Count = 2, 'Explicit/snapshot/root paths deduplicated with buffer priority');
      Check(Hit(LResult).GetValue<string>('source') = 'designer_buffer', 'Explicit snapshot searched before disk');
      Check(Hit(LResult).GetValue<string>('root') = LNested, 'Longest matching root');
      Check(Hit(LResult).GetValue<Boolean>('read_only_reference'), 'Read-only reference classification');
      Check(Hit(LResult, 1).GetValue<string>('source') = 'disk', 'Disk source classification');
      Check(not Hit(LResult, 1).GetValue<Boolean>('read_only_reference'), 'Sibling is outside nested reference root');
      Check(LResult.GetValue<Integer>('files_scanned') = 2, 'Files scanned counts unique source candidates');
    finally
      LResult.Free;
    end;
    LResult := TDAISourceSearch.Search('TButton', TArray<string>.Create(LProject), nil, nil, LSnapshots, EmptyOptions);
    try
      Check(Matches(LResult).Count = 0, 'Disk content hidden by authoritative buffer');
    finally
      LResult.Free;
    end;
    LSnapshot.Content := #0;
    LSnapshot.Source := 'unavailable';
    LSnapshots.AddOrSetValue(UpperCase(LFirst), LSnapshot);
    LResult := TDAISourceSearch.Search('TButton', nil, TArray<string>.Create(LFirst), nil, LSnapshots, EmptyOptions);
    try
      Check(Matches(LResult).Count = 0, 'Unavailable snapshot never falls back to stale disk');
      Check(LResult.GetValue<Integer>('files_skipped') = 1, 'Unavailable snapshot counted as skipped');
    finally
      LResult.Free;
    end;
    LSnapshot.Content := StringOfChar('x', 2 * 1024 * 1024 + 1);
    LSnapshots.AddOrSetValue(UpperCase(LFirst), LSnapshot);
    LResult := TDAISourceSearch.Search('TButton', nil, TArray<string>.Create(LFirst), nil, LSnapshots, EmptyOptions);
    try
      Check(Matches(LResult).Count = 0, 'Oversized snapshot never falls back to stale disk');
      Check(LResult.GetValue<Integer>('files_skipped') = 1, 'Oversized snapshot counted as skipped');
    finally
      LResult.Free;
    end;
  finally
    LSnapshots.Free;
  end;
  LResult := TDAISourceSearch.Search('TButton', nil, TArray<string>.Create(LFirst), nil, nil, EmptyOptions);
  try
    Check(Hit(LResult).GetValue<string>('root') = LNested, 'Explicit external filename root is its directory');
  finally
    LResult.Free;
  end;
  LOptions := EmptyOptions;
  LOptions.MaximumFiles := 1;
  LResult := TDAISourceSearch.Search('disk', nil, TArray<string>.Create(LFirst, LSecond), nil, nil, LOptions);
  try
    Check(LResult.GetValue<Integer>('files_scanned') = 1, 'File limit');
    Check(LResult.GetValue<string>('limit_reason') = 'maximum_files', 'File limit reason');
    Check(LResult.GetValue<Boolean>('truncated'), 'File limit truncation');
  finally
    LResult.Free;
  end;
  SetLength(LMissing, 30);
  for I := 0 to High(LMissing) do
    LMissing[I] := TPath.Combine(FixtureRoot, 'Missing' + IntToStr(I) + '.pas');
  LResult := TDAISourceSearch.Search('absent', nil, LMissing, nil, nil, EmptyOptions);
  try
    Check(LResult.GetValue<TJSONArray>('errors').Count = 20, 'Errors bounded');
    Check(LResult.GetValue<Boolean>('errors_truncated'), 'Error truncation disclosed');
    Check(LResult.GetValue<Integer>('files_skipped') = 30, 'Failed files counted');
  finally
    LResult.Free;
  end;
end;

procedure TestBinaryAndEncoding;
var
  LBinary: string;
  LLarge: string;
  LAnsi: string;
  LResult: TJSONObject;
begin
  LBinary := TPath.Combine(FixtureRoot, 'Binary.pas');
  LLarge := TPath.Combine(FixtureRoot, 'Large.pas');
  LAnsi := TPath.Combine(FixtureRoot, 'Ansi.pas');
  WriteFixture(LBinary, 'needle' + #0 + 'needle', TEncoding.UTF8);
  WriteFixture(LLarge, 'needle' + StringOfChar('x', 2 * 1024 * 1024), TEncoding.UTF8);
  WriteFixture(LAnsi, 'Grüße needle', TEncoding.ANSI);
  LResult := TDAISourceSearch.Search('needle', nil, TArray<string>.Create(LBinary, LLarge, LAnsi), nil, nil, EmptyOptions);
  try
    Check(Matches(LResult).Count = 1, 'Binary and oversized disk files skipped');
    Check(LResult.GetValue<Integer>('files_skipped') = 2, 'Binary and size skip count');
    Check(Hit(LResult).GetValue<string>('excerpt') = 'Grüße needle', 'Existing Delphi ANSI codepage policy retained');
  finally
    LResult.Free;
  end;
end;

procedure CreateJunction(const ALinkDirectory, ATargetDirectory: string);
const
  CSetReparsePoint = $000900A4;
  CMountPointTag = $A0000003;
var
  LHandle: THandle;
  LSubstitute: string;
  LPrint: string;
  LBytes: TBytes;
  LSubstituteBytes: TBytes;
  LPrintBytes: TBytes;
  LReturned: DWORD;
begin
  ForceDirectories(ALinkDirectory);
  LSubstitute := '\??\' + ATargetDirectory;
  LPrint := ATargetDirectory;
  LSubstituteBytes := TEncoding.Unicode.GetBytes(LSubstitute);
  LPrintBytes := TEncoding.Unicode.GetBytes(LPrint);
  SetLength(LBytes, 16 + Length(LSubstituteBytes) + 2 + Length(LPrintBytes) + 2);
  PDWORD(@LBytes[0])^ := CMountPointTag;
  PWord(@LBytes[4])^ := Length(LBytes) - 8;
  PWord(@LBytes[8])^ := 0;
  PWord(@LBytes[10])^ := Length(LSubstituteBytes);
  PWord(@LBytes[12])^ := Length(LSubstituteBytes) + 2;
  PWord(@LBytes[14])^ := Length(LPrintBytes);
  Move(LSubstituteBytes[0], LBytes[16], Length(LSubstituteBytes));
  Move(LPrintBytes[0], LBytes[18 + Length(LSubstituteBytes)], Length(LPrintBytes));
  LHandle := CreateFile(PChar(ALinkDirectory), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if LHandle = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  try
    if not DeviceIoControl(LHandle, CSetReparsePoint, @LBytes[0], Length(LBytes), nil, 0, LReturned, nil) then
      RaiseLastOSError;
  finally
    CloseHandle(LHandle);
  end;
end;

procedure TestReparsePaths;
var
  LTarget: string;
  LLink: string;
  LLinkedFile: string;
  LResult: TJSONObject;
  LSnapshots: TDictionary<string, TDAISourceSnapshot>;
  LSnapshot: TDAISourceSnapshot;
begin
  LTarget := TPath.Combine(FixtureRoot, 'JunctionTarget');
  LLink := TPath.Combine(FixtureRoot, 'Junction');
  WriteFixture(TPath.Combine(LTarget, 'Linked.pas'), 'needle on disk', TEncoding.UTF8);
  CreateJunction(LLink, LTarget);
  try
    LLinkedFile := TPath.Combine(LLink, 'Linked.pas');
    LResult := TDAISourceSearch.Search('needle', TArray<string>.Create(LLink), nil, nil, nil, EmptyOptions);
    try
      Check(Matches(LResult).Count = 0, 'Reparse root not traversed');
      Check(LResult.GetValue<TJSONArray>('errors').Count = 1, 'Reparse root reported');
    finally
      LResult.Free;
    end;
    LResult := TDAISourceSearch.Search('needle', nil, TArray<string>.Create(LLinkedFile), nil, nil, EmptyOptions);
    try
      Check(Matches(LResult).Count = 0, 'Explicit disk file under reparse parent blocked');
      Check(LResult.GetValue<Integer>('files_skipped') = 1, 'Reparse explicit file counted');
    finally
      LResult.Free;
    end;
    LSnapshots := TDictionary<string, TDAISourceSnapshot>.Create;
    try
      LSnapshot.Content := 'needle in trusted IDE buffer';
      LSnapshot.Source := 'editor_buffer';
      LSnapshots.Add(LLinkedFile, LSnapshot);
      LResult := TDAISourceSearch.Search('needle', nil, TArray<string>.Create(LLinkedFile), nil, LSnapshots, EmptyOptions);
      try
        Check(Matches(LResult).Count = 1, 'IDE snapshot allowed without disk traversal through junction');
        Check(Hit(LResult).GetValue<string>('source') = 'editor_buffer', 'Trusted snapshot source');
      finally
        LResult.Free;
      end;
    finally
      LSnapshots.Free;
    end;
  finally
    // Remove the link itself before recursive cleanup, leaving its target intact.
    if not RemoveDirectory(PChar(LLink)) then
      RaiseLastOSError;
  end;
end;

procedure RunChecks;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FixtureRoot := TPath.Combine(TPath.GetTempPath, 'DAISourceSearch-' + GUIDToString(LGuid));
  ForceDirectories(FixtureRoot);
  try
    ExpectInvalidQuery('');
    ExpectInvalidQuery(StringOfChar('x', 257));
    ExpectInvalidQuery('a' + #0);
    ExpectInvalidQuery('a' + #10);
    ExpectInvalidQuery('a' + #13);
    TestBoundedGlobs;
    TestLiteralAndCoordinates;
    TestCaseAndWholeWord;
    TestRegex;
    TestExcerptsAndLimits;
    TestInterfaceSnapshots;
    TestInterfaceDiskAndFileKinds;
    TestDiskSnapshotsAndPatterns;
    TestBinaryAndEncoding;
    TestReparsePaths;
  finally
    // The only recursive removal target is the unique fixture directory created above.
    Check(TPath.GetDirectoryName(FixtureRoot) = ExcludeTrailingPathDelimiter(TPath.GetTempPath), 'Cleanup stays inside temp');
    TDirectory.Delete(FixtureRoot, True);
  end;
end;

begin
  try
    RunChecks;
    Writeln('PASS: ', CheckCount, ' native source-search checks.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
