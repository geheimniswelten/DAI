unit h5u.DAI.Text.Changes;

{$BOOLEVAL OFF} // Bounds checks in the diff use short-circuit guards.

interface

type
  TDAITextChange = record
    // Zero-based UTF-8 offsets into the original editor buffer; EndByte is exclusive.
    StartByte: Integer;
    EndByte: Integer;
    NewTextUtf8: UTF8String;
  end;

  TDAITextChanges = class sealed
  public
    class function Between(const AOldText, ANewText: string): TArray<TDAITextChange>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils;

const
  CMaximumLines = 131072;
  CMaximumAtoms = 65536;
  CMaximumDistance = 256;
  CMaximumChanges = 4096;
  CMinimumWork = 4 * 1024 * 1024;
  CMaximumWork = 64 * 1024 * 1024;

type
  TTextUnit = record
    StartByte: Integer;
    EndByte: Integer;
  end;

  TSequenceChange = record
    OldStart: Integer;
    OldEnd: Integer;
    NewStart: Integer;
    NewEnd: Integer;
  end;

  TMatch = record
    OldIndex: Integer;
    NewIndex: Integer;
  end;

function IsBoundary(const AText: UTF8String; const APosition: Integer): Boolean;
begin
  Result := (APosition <= 0) or (APosition >= Length(AText));
  if Result then
    Exit;
  Result := ((Byte(AText[APosition + 1]) and $C0) <> $80) and
    not ((AText[APosition] = #13) and (AText[APosition + 1] = #10));
end;

procedure TrimRange(const AOld, ANew: UTF8String; var AOldStart, AOldEnd, ANewStart, ANewEnd: Integer);
var
  LOldStart, LOldEnd: Integer;
begin
  LOldStart := AOldStart;
  LOldEnd := AOldEnd;
  while (AOldStart < AOldEnd) and (ANewStart < ANewEnd) and
    (AOld[AOldStart + 1] = ANew[ANewStart + 1]) do
  begin
    Inc(AOldStart);
    Inc(ANewStart);
  end;
  while (AOldStart > LOldStart) and
    (not IsBoundary(AOld, AOldStart) or not IsBoundary(ANew, ANewStart)) do
  begin
    Dec(AOldStart);
    Dec(ANewStart);
  end;
  while (AOldEnd > AOldStart) and (ANewEnd > ANewStart) and
    (AOld[AOldEnd] = ANew[ANewEnd]) do
  begin
    Dec(AOldEnd);
    Dec(ANewEnd);
  end;
  while (AOldEnd < LOldEnd) and
    (not IsBoundary(AOld, AOldEnd) or not IsBoundary(ANew, ANewEnd)) do
  begin
    Inc(AOldEnd);
    Inc(ANewEnd);
  end;
end;

function SplitUnits(const AText: UTF8String; const AStart, AEnd: Integer; const ALines: Boolean; out AUnits: TArray<TTextUnit>): Boolean;
var
  LLimit, LPosition, LCount, LStart: Integer;
begin
  if ALines then
    LLimit := CMaximumLines
  else
    LLimit := CMaximumAtoms;
  SetLength(AUnits, 0);
  LCount := 0;
  LPosition := AStart;
  while LPosition < AEnd do
  begin
    if LCount = LLimit then
      Exit(False);
    LStart := LPosition;
    if ALines then
    begin
      while (LPosition < AEnd) and (AText[LPosition + 1] <> #13) and (AText[LPosition + 1] <> #10) do
        Inc(LPosition);
      if LPosition < AEnd then
      begin
        Inc(LPosition);
        if (AText[LPosition] = #13) and (LPosition < AEnd) and (AText[LPosition + 1] = #10) then
          Inc(LPosition);
      end;
    end
    else
    begin
      Inc(LPosition);
      while (LPosition < AEnd) and ((Byte(AText[LPosition + 1]) and $C0) = $80) do
        Inc(LPosition);
      if (AText[LStart + 1] = #13) and (LPosition < AEnd) and (AText[LPosition + 1] = #10) then
        Inc(LPosition);
    end;
    if LCount = Length(AUnits) then
      if LCount = 0 then
        SetLength(AUnits, 16)
      else if LCount * 2 < LLimit then
        SetLength(AUnits, LCount * 2)
      else
        SetLength(AUnits, LLimit);
    AUnits[LCount].StartByte := LStart;
    AUnits[LCount].EndByte := LPosition;
    Inc(LCount);
  end;
  SetLength(AUnits, LCount);
  Result := True;
end;

function UnitsEqual(const AOld, ANew: UTF8String; const AOldUnit, ANewUnit: TTextUnit; var AWork: Integer): Boolean;
var
  LLength: Integer;
begin
  LLength := AOldUnit.EndByte - AOldUnit.StartByte;
  Dec(AWork);
  Result := False;
  if (AWork < 0) or (LLength <> ANewUnit.EndByte - ANewUnit.StartByte) then
    Exit;
  if LLength > AWork then
  begin
    AWork := -1;
    Exit;
  end;
  Dec(AWork, LLength);
  Result := CompareMem(PAnsiChar(AOld) + AOldUnit.StartByte, PAnsiChar(ANew) + ANewUnit.StartByte, LLength);
end;

// Bounded Myers diff. Both trace memory and comparison work have explicit limits.
// Large replacements fall back to their already-trimmed changed range, never an unbounded quadratic scan.
function SequenceChanges(const AOld, ANew: UTF8String; const AOldUnits, ANewUnits: TArray<TTextUnit>; var AWork: Integer; out AChanges: TArray<TSequenceChange>): Boolean;
var
  LTrace: TArray<TArray<Integer>>;
  LFrontier: TArray<Integer>;
  LMatches: TList<TMatch>;
  LChanges: TList<TSequenceChange>;
  LDistance, LDiagonal, LOffset, LX, LY, LOldCount, LNewCount, LPreviousDiagonal: Integer;
  LPreviousX, LPreviousY, LFoundDistance, LIndex, LOldCursor, LNewCursor: Integer;
  LMatch: TMatch;
  LChange: TSequenceChange;
begin
  AChanges := nil;
  Result := False;
  LOldCount := Length(AOldUnits);
  LNewCount := Length(ANewUnits);
  if Abs(LOldCount - LNewCount) > CMaximumDistance then
    Exit;
  LOffset := CMaximumDistance + 1;
  SetLength(LFrontier, 2 * CMaximumDistance + 3);
  SetLength(LTrace, CMaximumDistance + 1);
  LFoundDistance := -1;
  for LDistance := 0 to CMaximumDistance do
  begin
    LDiagonal := -LDistance;
    while LDiagonal <= LDistance do
    begin
      Dec(AWork);
      if AWork < 0 then
        Exit;
      if (LDiagonal = -LDistance) or ((LDiagonal <> LDistance) and
        (LFrontier[LOffset + LDiagonal - 1] < LFrontier[LOffset + LDiagonal + 1])) then
        LX := LFrontier[LOffset + LDiagonal + 1]
      else
        LX := LFrontier[LOffset + LDiagonal - 1] + 1;
      LY := LX - LDiagonal;
      while (LX < LOldCount) and (LY < LNewCount) and
        UnitsEqual(AOld, ANew, AOldUnits[LX], ANewUnits[LY], AWork) do
      begin
        Inc(LX);
        Inc(LY);
      end;
      if AWork < 0 then
        Exit;
      LFrontier[LOffset + LDiagonal] := LX;
      if (LX >= LOldCount) and (LY >= LNewCount) then
      begin
        LFoundDistance := LDistance;
        Break;
      end;
      Inc(LDiagonal, 2);
    end;
    LTrace[LDistance] := Copy(LFrontier);
    if LFoundDistance >= 0 then
      Break;
  end;
  if LFoundDistance < 0 then
    Exit;

  LMatches := TList<TMatch>.Create;
  LChanges := TList<TSequenceChange>.Create;
  try
    LX := LOldCount;
    LY := LNewCount;
    for LDistance := LFoundDistance downto 1 do
    begin
      LDiagonal := LX - LY;
      LFrontier := LTrace[LDistance - 1];
      if (LDiagonal = -LDistance) or ((LDiagonal <> LDistance) and
        (LFrontier[LOffset + LDiagonal - 1] < LFrontier[LOffset + LDiagonal + 1])) then
        LPreviousDiagonal := LDiagonal + 1
      else
        LPreviousDiagonal := LDiagonal - 1;
      LPreviousX := LFrontier[LOffset + LPreviousDiagonal];
      LPreviousY := LPreviousX - LPreviousDiagonal;
      while (LX > LPreviousX) and (LY > LPreviousY) do
      begin
        Dec(LX);
        Dec(LY);
        LMatch.OldIndex := LX;
        LMatch.NewIndex := LY;
        LMatches.Add(LMatch);
      end;
      LX := LPreviousX;
      LY := LPreviousY;
    end;
    while (LX > 0) and (LY > 0) do
    begin
      Dec(LX);
      Dec(LY);
      LMatch.OldIndex := LX;
      LMatch.NewIndex := LY;
      LMatches.Add(LMatch);
    end;
    LOldCursor := 0;
    LNewCursor := 0;
    for LIndex := LMatches.Count - 1 downto 0 do
    begin
      LMatch := LMatches[LIndex];
      if (LOldCursor < LMatch.OldIndex) or (LNewCursor < LMatch.NewIndex) then
      begin
        LChange.OldStart := LOldCursor;
        LChange.OldEnd := LMatch.OldIndex;
        LChange.NewStart := LNewCursor;
        LChange.NewEnd := LMatch.NewIndex;
        LChanges.Add(LChange);
      end;
      LOldCursor := LMatch.OldIndex + 1;
      LNewCursor := LMatch.NewIndex + 1;
    end;
    if (LOldCursor < LOldCount) or (LNewCursor < LNewCount) then
    begin
      LChange.OldStart := LOldCursor;
      LChange.OldEnd := LOldCount;
      LChange.NewStart := LNewCursor;
      LChange.NewEnd := LNewCount;
      LChanges.Add(LChange);
    end;
    AChanges := LChanges.ToArray;
    Result := True;
  finally
    LChanges.Free;
    LMatches.Free;
  end;
end;

function UnitOffset(const AUnits: TArray<TTextUnit>; const AIndex, AEnd: Integer): Integer;
begin
  if AIndex < Length(AUnits) then
    Result := AUnits[AIndex].StartByte
  else
    Result := AEnd;
end;

procedure AddChange(const AOld, ANew: UTF8String; AOldStart, AOldEnd, ANewStart, ANewEnd: Integer; const AChanges: TList<TDAITextChange>);
var
  LChange: TDAITextChange;
begin
  TrimRange(AOld, ANew, AOldStart, AOldEnd, ANewStart, ANewEnd);
  if (AOldStart = AOldEnd) and (ANewStart = ANewEnd) then
    Exit;
  LChange.StartByte := AOldStart;
  LChange.EndByte := AOldEnd;
  LChange.NewTextUtf8 := Copy(ANew, ANewStart + 1, ANewEnd - ANewStart);
  AChanges.Add(LChange);
end;

procedure RefineChange(const AOld, ANew: UTF8String; AOldStart, AOldEnd, ANewStart, ANewEnd: Integer; var AWork: Integer; const AChanges: TList<TDAITextChange>);
var
  LOldUnits, LNewUnits: TArray<TTextUnit>;
  LChanges: TArray<TSequenceChange>;
  LChange: TSequenceChange;
begin
  TrimRange(AOld, ANew, AOldStart, AOldEnd, ANewStart, ANewEnd);
  if (AOldStart = AOldEnd) or (ANewStart = ANewEnd) or (AWork < 0) or
    not SplitUnits(AOld, AOldStart, AOldEnd, False, LOldUnits) or
    not SplitUnits(ANew, ANewStart, ANewEnd, False, LNewUnits) or
    not SequenceChanges(AOld, ANew, LOldUnits, LNewUnits, AWork, LChanges) then
  begin
    AddChange(AOld, ANew, AOldStart, AOldEnd, ANewStart, ANewEnd, AChanges);
    Exit;
  end;
  for LChange in LChanges do
    AddChange(AOld, ANew, UnitOffset(LOldUnits, LChange.OldStart, AOldEnd),
      UnitOffset(LOldUnits, LChange.OldEnd, AOldEnd), UnitOffset(LNewUnits, LChange.NewStart, ANewEnd),
      UnitOffset(LNewUnits, LChange.NewEnd, ANewEnd), AChanges);
end;

class function TDAITextChanges.Between(const AOldText, ANewText: string): TArray<TDAITextChange>;
var
  LOld, LNew: UTF8String;
  LOldStart, LOldEnd, LNewStart, LNewEnd, LWork: Integer;
  LWorkLimit: Int64;
  LOldLines, LNewLines: TArray<TTextUnit>;
  LLineChanges: TArray<TSequenceChange>;
  LLineChange: TSequenceChange;
  LChanges: TList<TDAITextChange>;
begin
  Result := nil;
  if AOldText = ANewText then
    Exit;
  LOld := UTF8Encode(AOldText);
  LNew := UTF8Encode(ANewText);
  LOldStart := 0;
  LNewStart := 0;
  LOldEnd := Length(LOld);
  LNewEnd := Length(LNew);
  TrimRange(LOld, LNew, LOldStart, LOldEnd, LNewStart, LNewEnd);
  LWorkLimit := (Int64(LOldEnd - LOldStart) + LNewEnd - LNewStart) * 4;
  if LWorkLimit < CMinimumWork then
    LWork := CMinimumWork
  else if LWorkLimit > CMaximumWork then
    LWork := CMaximumWork
  else
    LWork := LWorkLimit;
  LChanges := TList<TDAITextChange>.Create;
  try
    if (LOldStart = LOldEnd) or (LNewStart = LNewEnd) or
      not SplitUnits(LOld, LOldStart, LOldEnd, True, LOldLines) or
      not SplitUnits(LNew, LNewStart, LNewEnd, True, LNewLines) or
      not SequenceChanges(LOld, LNew, LOldLines, LNewLines, LWork, LLineChanges) then
      RefineChange(LOld, LNew, LOldStart, LOldEnd, LNewStart, LNewEnd, LWork, LChanges)
    else
      for LLineChange in LLineChanges do
      begin
        RefineChange(LOld, LNew, UnitOffset(LOldLines, LLineChange.OldStart, LOldEnd),
          UnitOffset(LOldLines, LLineChange.OldEnd, LOldEnd), UnitOffset(LNewLines, LLineChange.NewStart, LNewEnd),
          UnitOffset(LNewLines, LLineChange.NewEnd, LNewEnd), LWork, LChanges);
        if LChanges.Count > CMaximumChanges then
          Break;
      end;
    if LChanges.Count > CMaximumChanges then
    begin
      LChanges.Clear;
      AddChange(LOld, LNew, LOldStart, LOldEnd, LNewStart, LNewEnd, LChanges);
    end;
    Result := LChanges.ToArray;
  finally
    LChanges.Free;
  end;
end;

end.
