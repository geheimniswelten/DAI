unit h5u.DAI.Source.Regex;

interface

uses
  System.RegularExpressionsAPI;

type
  TDAIRegexMatch = record
    Success: Boolean;
    Index: Integer;
    Length: Integer;
  end;

  TDAIRegex = class sealed
  strict private
    FPattern: PPCRE;
    FExtra: TPCREExtra;
    FOffsets: TArray<Integer>;
  public
    constructor Create(const APattern: string; const ACaseSensitive: Boolean);
    destructor Destroy; override;
    function IsMatch(const AContent: string): Boolean;
    function Match(const AContent: string; const AStartPosition: Integer = 1): TDAIRegexMatch;
  end;

implementation

uses
  System.Character,
  System.Classes,
  System.Diagnostics,
  System.SysUtils;

const
  CMaximumMatchCalls = 100000;
  CMaximumRecursionDepth = 256;
  CMaximumMatchMilliseconds = 500;

procedure ValidateScanControls(const APattern: string);
var
  LIndex: Integer;
  LEscaped: Boolean;
begin
  // Each candidate start gets a separate anchored exec, so constructs whose
  // meaning depends on the original unanchored scan cannot be represented.
  LEscaped := False;
  for LIndex := 1 to Length(APattern) do
  begin
    if LEscaped then
    begin
      if APattern[LIndex] = 'G' then
        raise EArgumentException.Create('Regex \G is unsupported by bounded candidate scanning.');
      LEscaped := False;
    end
    else if APattern[LIndex] = '\' then
      LEscaped := True;
  end;
  if (Pos('(*SKIP', APattern) <> 0) or (Pos('(*COMMIT', APattern) <> 0) or
    (Pos('(*PRUNE', APattern) <> 0) or (Pos('(*THEN', APattern) <> 0) then
    raise EArgumentException.Create('Regex scan-control verbs SKIP, COMMIT, PRUNE and THEN are unsupported.');
end;

constructor TDAIRegex.Create(const APattern: string; const ACaseSensitive: Boolean);
var
  LError: MarshaledAString;
  LErrorOffset: Integer;
  LOptions: Integer;
  LCaptureCount: Integer;
begin
  inherited Create;
  if (APattern = '') or (Length(APattern) > 256) or (Pos(#0, APattern) <> 0) or
    (Pos(#10, APattern) <> 0) or (Pos(#13, APattern) <> 0) then
    raise EArgumentException.Create('Regex must contain 1 to 256 characters without NUL or line breaks.');
  ValidateScanControls(APattern);
  // The Windows RTL uses PCRE16: offsets are UTF-16 code units, like IDE coordinates.
  LOptions := PCRE_UTF16 or PCRE_UCP or PCRE_NEWLINE_ANY;
  if not ACaseSensitive then
    LOptions := LOptions or PCRE_CASELESS;
  LError := nil;
  LErrorOffset := 0;
  FPattern := pcre_compile(PCRE_STR(PChar(APattern)), LOptions, @LError, @LErrorOffset, nil);
  if FPattern = nil then
    raise EArgumentException.CreateFmt('Invalid regex at position %d: %s', [LErrorOffset + 1, string(LError)]);
  LCaptureCount := 0;
  if pcre_fullinfo(FPattern, nil, PCRE_INFO_CAPTURECOUNT, @LCaptureCount) <> 0 then
    raise EInvalidOperation.Create('Regex capture information is unavailable.');
  SetLength(FOffsets, (LCaptureCount + 1) * 3);
  // Caller limits cannot be raised by pattern directives. Do not enable JIT, which
  // has different recursion-limit semantics. Never use RTL TRegEx here: it hides
  // negative pcre_exec statuses, including exhausted limits, as ordinary misses.
  FExtra := Default(TPCREExtra);
  FExtra.flags := PCRE_EXTRA_MATCH_LIMIT or PCRE_EXTRA_MATCH_LIMIT_RECURSION;
  FExtra.match_limit := CMaximumMatchCalls;
  FExtra.match_limit_recursion := CMaximumRecursionDepth;
end;

destructor TDAIRegex.Destroy;
begin
  pcre_dispose(FPattern, nil, nil);
  inherited;
end;

function TDAIRegex.IsMatch(const AContent: string): Boolean;
begin
  Result := Match(AContent).Success;
end;

function TDAIRegex.Match(const AContent: string; const AStartPosition: Integer): TDAIRegexMatch;
var
  LStatus: Integer;
  LPosition: Integer;
  LClock: TStopwatch;
  LExecOptions: Integer;
begin
  if (AStartPosition < 1) or (AStartPosition > Length(AContent) + 1) then
    raise EArgumentOutOfRangeException.Create('Regex start position is outside the content.');
  Result := Default(TDAIRegexMatch);
  LClock := TStopwatch.StartNew;
  LPosition := AStartPosition;
  LExecOptions := PCRE_ANCHORED;
  while LPosition <= Length(AContent) + 1 do
  begin
    if LClock.ElapsedMilliseconds >= CMaximumMatchMilliseconds then
      raise EInvalidOperation.Create('Regex execution time limit exceeded.');
    // PCRE's match-limit counter resets for every attempted start. Anchoring
    // makes the candidate loop observable here, so a long unanchored miss
    // cannot multiply bounded backtracking work without a time-budget check.
    LStatus := pcre_exec(FPattern, @FExtra, PCRE_STR(PChar(AContent)), Length(AContent),
      LPosition - 1, LExecOptions, @FOffsets[0], Length(FOffsets));
    if (LStatus = PCRE_ERROR_MATCHLIMIT) or (LStatus = PCRE_ERROR_RECURSIONLIMIT) then
      raise EInvalidOperation.Create('Regex execution limit exceeded.');
    if LStatus <> PCRE_ERROR_NOMATCH then
    begin
      if LStatus <= 0 then
        raise EInvalidOperation.CreateFmt('Regex execution failed (PCRE status %d).', [LStatus]);
      Result.Success := True;
      Result.Index := FOffsets[0] + 1;
      Result.Length := FOffsets[1] - FOffsets[0];
      if (Result.Index < LPosition) or (Result.Index > Length(AContent) + 1) or (Result.Length < 0) or
        (FOffsets[1] > Length(AContent)) then
        raise EInvalidOperation.Create('Regex returned an invalid match span.');
      Exit;
    end;
    // A normal no-match status also confirms UTF-16 validity. This immutable
    // subject needs validation only once, not for each candidate in the scan.
    LExecOptions := PCRE_ANCHORED or PCRE_NO_UTF16_CHECK;
    if LPosition > Length(AContent) then
      Exit;
    if AContent[LPosition].IsHighSurrogate then
      if LPosition < Length(AContent) then
        if AContent[LPosition + 1].IsLowSurrogate then
          Inc(LPosition);
    Inc(LPosition);
  end;
end;

end.
