unit h5u.DAI.Text.Encoding;

interface

uses
  System.SysUtils;

type
  TDAITextEncodingKind = (
    tekIDEBuffer,
    tekANSI,
    tekUTF8,
    tekUTF8BOM,
    tekUTF16LEBOM,
    tekUTF16BEBOM
  );

  TDAILineEndingKind = (
    lekNone,
    lekCRLF,
    lekLF,
    lekCR,
    lekMixed
  );

  TDAITextFileFormat = record
  public
    EncodingKind: TDAITextEncodingKind;
    LineEndingKind: TDAILineEndingKind;
  end;

  TDAITextEncoding = class sealed
  strict private
    class function ByteIsContinuation(const AValue: Byte): Boolean; static;
    class function CanEncodeWithSystemANSI(const AText: string): Boolean; static;
    class function DecodeBytes(const ABytes: TBytes; const AEncodingKind: TDAITextEncodingKind): string; static;
    class function DetectEncoding(const AFileName: string; const ABytes: TBytes): TDAITextEncodingKind; static;
    class function EncodeBytes(const AText: string; const AEncodingKind: TDAITextEncodingKind): TBytes; static;
    class function HasUTF16BEBOM(const ABytes: TBytes): Boolean; static;
    class function HasUTF16LEBOM(const ABytes: TBytes): Boolean; static;
    class function HasUTF32BEBOM(const ABytes: TBytes): Boolean; static;
    class function HasUTF32LEBOM(const ABytes: TBytes): Boolean; static;
    class function HasUTF8BOM(const ABytes: TBytes): Boolean; static;
    class function IsDelphiTextFile(const AFileName: string): Boolean; static;
    class function IsPascalSourceFile(const AFileName: string): Boolean; static;
    class function IsValidUTF8(const ABytes: TBytes): Boolean; static;
    class function NormalizeLineEndings(const AText: string; const ALineEndingKind: TDAILineEndingKind): string; static;
    class function PreferredUnicodeEncoding(const AFileName: string): TDAITextEncodingKind; static;
    class function ResolveLineEndingKind(const AText: string; const APreferredLineEndingKind: TDAILineEndingKind): TDAILineEndingKind; static;
    class function UsesUTF8BOMByDefault(const AFileName: string): Boolean; static;
    class function WithPreamble(const ATextBytes: TBytes; const APreamble: TBytes): TBytes; static;
    class procedure InspectFile(const AFileName: string; out AFormat: TDAITextFileFormat); static;
  public
    class function ApplyLineEnding(const AText: string; const ALineEndingKind: TDAILineEndingKind): string; static;
    class function DetectLineEnding(const AText: string): TDAILineEndingKind; static;
    class function EncodingName(const AEncodingKind: TDAITextEncodingKind): string; static;
    class function EditorWriteMatches(const ARequestedText, AActualText: string): Boolean; static;
    class function LineEndingName(const ALineEndingKind: TDAILineEndingKind): string; static;
    class function PrepareText(const AFileName, AText: string; const APreferredLineEndingKind: TDAILineEndingKind): string; static;
    class function PrepareWrite(const AFileName: string; const AText: string; out AWrittenText: string; out AFormat: TDAITextFileFormat): TBytes; static;
    class function ReadFile(const AFileName: string; out AFormat: TDAITextFileFormat): string; static;
  end;

implementation

uses
  System.IOUtils;

class function TDAITextEncoding.ApplyLineEnding(const AText: string; const ALineEndingKind: TDAILineEndingKind): string;
begin
  Result := NormalizeLineEndings(AText, ResolveLineEndingKind(AText, ALineEndingKind));
end;

class function TDAITextEncoding.ByteIsContinuation(const AValue: Byte): Boolean;
begin
  Result := (AValue and $C0) = $80;
end;

class function TDAITextEncoding.EditorWriteMatches(const ARequestedText, AActualText: string): Boolean;
begin
  // OTA inserts a zero-terminated UTF-8 string and can append one final CRLF.
  // Do not trim: existing final empty lines and every requested character matter.
  if Pos(#0, ARequestedText) <> 0 then
    Exit(False);
  Result := (AActualText = ARequestedText) or (AActualText = ARequestedText + #13#10);
end;

class function TDAITextEncoding.CanEncodeWithSystemANSI(const AText: string): Boolean;
var
  LBytes: TBytes;
begin
  LBytes := TEncoding.ANSI.GetBytes(AText);
  Result := TEncoding.ANSI.GetString(LBytes) = AText;
end;

class function TDAITextEncoding.DecodeBytes(const ABytes: TBytes; const AEncodingKind: TDAITextEncodingKind): string;
var
  LContentBytes: TBytes;
begin
  case AEncodingKind of
    tekIDEBuffer:
      raise EEncodingError.Create('Der IDE-Editorpuffer besitzt keine direkt schreibbare Dateicodierung.');
    tekANSI:
      Result := TEncoding.ANSI.GetString(ABytes);
    tekUTF8:
      Result := TEncoding.UTF8.GetString(ABytes);
    tekUTF8BOM:
      begin
        LContentBytes := Copy(ABytes, 3, Length(ABytes) - 3);
        Result := TEncoding.UTF8.GetString(LContentBytes);
      end;
    tekUTF16LEBOM:
      begin
        LContentBytes := Copy(ABytes, 2, Length(ABytes) - 2);
        Result := TEncoding.Unicode.GetString(LContentBytes);
      end;
    tekUTF16BEBOM:
      begin
        LContentBytes := Copy(ABytes, 2, Length(ABytes) - 2);
        Result := TEncoding.BigEndianUnicode.GetString(LContentBytes);
      end;
  else
    raise EEncodingError.Create('Nicht unterstützte Textcodierung.');
  end;
end;

class function TDAITextEncoding.DetectEncoding(const AFileName: string; const ABytes: TBytes): TDAITextEncodingKind;
begin
  if HasUTF32LEBOM(ABytes) or HasUTF32BEBOM(ABytes) then
    raise EEncodingError.Create('UTF-32-Dateien werden von DAI nicht unterstützt.');
  if HasUTF8BOM(ABytes) then
    Exit(tekUTF8BOM);
  if HasUTF16LEBOM(ABytes) then
    Exit(tekUTF16LEBOM);
  if HasUTF16BEBOM(ABytes) then
    Exit(tekUTF16BEBOM);

  if IsDelphiTextFile(AFileName) then
    Exit(tekANSI);
  if IsValidUTF8(ABytes) then
    Result := tekUTF8
  else
    Result := tekANSI;
end;

class function TDAITextEncoding.DetectLineEnding(const AText: string): TDAILineEndingKind;
var
  LCRCount: Integer;
  LCRLFCount: Integer;
  LIndex: Integer;
  LLFCount: Integer;
  LKinds: Integer;
begin
  LCRCount := 0;
  LCRLFCount := 0;
  LLFCount := 0;
  LIndex := 1;
  while LIndex <= Length(AText) do
  begin
    if AText[LIndex] = #13 then
    begin
      if (LIndex < Length(AText)) and (AText[LIndex + 1] = #10) then
      begin
        Inc(LCRLFCount);
        Inc(LIndex, 2);
        Continue;
      end;
      Inc(LCRCount);
    end
    else if AText[LIndex] = #10 then
      Inc(LLFCount);
    Inc(LIndex);
  end;

  LKinds := Ord(LCRLFCount > 0) + Ord(LLFCount > 0) + Ord(LCRCount > 0);
  if LKinds = 0 then
    Exit(lekNone);
  if LKinds > 1 then
    Exit(lekMixed);
  if LCRLFCount > 0 then
    Exit(lekCRLF);
  if LLFCount > 0 then
    Exit(lekLF);
  Result := lekCR;
end;

class function TDAITextEncoding.EncodeBytes(const AText: string; const AEncodingKind: TDAITextEncodingKind): TBytes;
var
  LTextBytes: TBytes;
begin
  case AEncodingKind of
    tekIDEBuffer:
      raise EEncodingError.Create('Der IDE-Editorpuffer besitzt keine direkt schreibbare Dateicodierung.');
    tekANSI:
      Result := TEncoding.ANSI.GetBytes(AText);
    tekUTF8:
      Result := TEncoding.UTF8.GetBytes(AText);
    tekUTF8BOM:
      begin
        LTextBytes := TEncoding.UTF8.GetBytes(AText);
        Result := WithPreamble(LTextBytes, TEncoding.UTF8.GetPreamble);
      end;
    tekUTF16LEBOM:
      begin
        LTextBytes := TEncoding.Unicode.GetBytes(AText);
        Result := WithPreamble(LTextBytes, TEncoding.Unicode.GetPreamble);
      end;
    tekUTF16BEBOM:
      begin
        LTextBytes := TEncoding.BigEndianUnicode.GetBytes(AText);
        Result := WithPreamble(LTextBytes, TEncoding.BigEndianUnicode.GetPreamble);
      end;
  else
    raise EEncodingError.Create('Nicht unterstützte Textcodierung.');
  end;
end;

class function TDAITextEncoding.EncodingName(const AEncodingKind: TDAITextEncodingKind): string;
begin
  case AEncodingKind of
    tekIDEBuffer:
      Result := 'ide-buffer';
    tekANSI:
      Result := 'ansi';
    tekUTF8:
      Result := 'utf-8';
    tekUTF8BOM:
      Result := 'utf-8-bom';
    tekUTF16LEBOM:
      Result := 'utf-16le-bom';
    tekUTF16BEBOM:
      Result := 'utf-16be-bom';
  else
    Result := 'unknown';
  end;
end;

class function TDAITextEncoding.HasUTF16BEBOM(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF);
end;

class function TDAITextEncoding.HasUTF16LEBOM(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE);
end;

class function TDAITextEncoding.HasUTF32BEBOM(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 4) and (ABytes[0] = $00) and (ABytes[1] = $00) and (ABytes[2] = $FE) and (ABytes[3] = $FF);
end;

class function TDAITextEncoding.HasUTF32LEBOM(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 4) and (ABytes[0] = $FF) and (ABytes[1] = $FE) and (ABytes[2] = $00) and (ABytes[3] = $00);
end;

class function TDAITextEncoding.HasUTF8BOM(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF);
end;

class function TDAITextEncoding.IsDelphiTextFile(const AFileName: string): Boolean;
var
  LExtension: string;
begin
  LExtension := TPath.GetExtension(AFileName);
  Result := IsPascalSourceFile(AFileName) or SameText(LExtension, '.dfm') or SameText(LExtension, '.fmx');
end;

class function TDAITextEncoding.IsPascalSourceFile(const AFileName: string): Boolean;
var
  LExtension: string;
begin
  LExtension := TPath.GetExtension(AFileName);
  Result := SameText(LExtension, '.pas') or SameText(LExtension, '.dpr') or SameText(LExtension, '.dpk') or SameText(LExtension, '.inc');
end;

class function TDAITextEncoding.IsValidUTF8(const ABytes: TBytes): Boolean;
var
  LByte1: Byte;
  LByte2: Byte;
  LIndex: Integer;
  LLength: Integer;
begin
  LIndex := 0;
  LLength := Length(ABytes);
  while LIndex < LLength do
  begin
    LByte1 := ABytes[LIndex];
    if LByte1 <= $7F then
    begin
      Inc(LIndex);
      Continue;
    end;

    if (LByte1 >= $C2) and (LByte1 <= $DF) then
    begin
      if (LIndex + 1 >= LLength) or not ByteIsContinuation(ABytes[LIndex + 1]) then
        Exit(False);
      Inc(LIndex, 2);
      Continue;
    end;

    if (LByte1 >= $E0) and (LByte1 <= $EF) then
    begin
      if (LIndex + 2 >= LLength) or not ByteIsContinuation(ABytes[LIndex + 1]) or not ByteIsContinuation(ABytes[LIndex + 2]) then
        Exit(False);
      LByte2 := ABytes[LIndex + 1];
      if ((LByte1 = $E0) and (LByte2 < $A0)) or ((LByte1 = $ED) and (LByte2 > $9F)) then
        Exit(False);
      Inc(LIndex, 3);
      Continue;
    end;

    if (LByte1 >= $F0) and (LByte1 <= $F4) then
    begin
      if (LIndex + 3 >= LLength) or not ByteIsContinuation(ABytes[LIndex + 1]) or not ByteIsContinuation(ABytes[LIndex + 2]) or
         not ByteIsContinuation(ABytes[LIndex + 3]) then
        Exit(False);
      LByte2 := ABytes[LIndex + 1];
      if ((LByte1 = $F0) and (LByte2 < $90)) or ((LByte1 = $F4) and (LByte2 > $8F)) then
        Exit(False);
      Inc(LIndex, 4);
      Continue;
    end;

    Exit(False);
  end;
  Result := True;
end;

class function TDAITextEncoding.LineEndingName(const ALineEndingKind: TDAILineEndingKind): string;
begin
  case ALineEndingKind of
    lekNone:
      Result := 'none';
    lekCRLF:
      Result := 'crlf';
    lekLF:
      Result := 'lf';
    lekCR:
      Result := 'cr';
    lekMixed:
      Result := 'mixed';
  else
    Result := 'unknown';
  end;
end;

class function TDAITextEncoding.NormalizeLineEndings(const AText: string; const ALineEndingKind: TDAILineEndingKind): string;
begin
  if ALineEndingKind = lekNone then
    Exit(AText);

  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  case ALineEndingKind of
    lekCRLF, lekCR, lekMixed:
      Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
  end;
end;

class function TDAITextEncoding.PreferredUnicodeEncoding(const AFileName: string): TDAITextEncodingKind;
begin
  if IsPascalSourceFile(AFileName) then
    Result := tekUTF8BOM
  else
    Result := tekUTF8;
end;

class function TDAITextEncoding.PrepareText(const AFileName, AText: string; const APreferredLineEndingKind: TDAILineEndingKind): string;
begin
  Result := ApplyLineEnding(AText, APreferredLineEndingKind);
  if IsPascalSourceFile(AFileName) then
    Result := StringReplace(Result, #9, '  ', [rfReplaceAll]);
end;

class function TDAITextEncoding.PrepareWrite(const AFileName: string; const AText: string; out AWrittenText: string; out AFormat: TDAITextFileFormat): TBytes;
var
  LExistingFormat: TDAITextFileFormat;
begin
  if TFile.Exists(AFileName) then
  begin
    InspectFile(AFileName, LExistingFormat);
    AWrittenText := PrepareText(AFileName, AText, LExistingFormat.LineEndingKind);
    AFormat.EncodingKind := LExistingFormat.EncodingKind;
    if (AFormat.EncodingKind = tekANSI) and not CanEncodeWithSystemANSI(AWrittenText) then
      AFormat.EncodingKind := PreferredUnicodeEncoding(AFileName);
  end
  else
  begin
    AWrittenText := PrepareText(AFileName, AText, lekNone);
    if UsesUTF8BOMByDefault(AFileName) then
      AFormat.EncodingKind := tekUTF8BOM
    else
      AFormat.EncodingKind := tekUTF8;
  end;

  AFormat.LineEndingKind := DetectLineEnding(AWrittenText);
  Result := EncodeBytes(AWrittenText, AFormat.EncodingKind);
end;

class function TDAITextEncoding.ReadFile(const AFileName: string; out AFormat: TDAITextFileFormat): string;
var
  LBytes: TBytes;
begin
  LBytes := TFile.ReadAllBytes(AFileName);
  AFormat.EncodingKind := DetectEncoding(AFileName, LBytes);
  Result := DecodeBytes(LBytes, AFormat.EncodingKind);
  AFormat.LineEndingKind := DetectLineEnding(Result);
end;

class function TDAITextEncoding.ResolveLineEndingKind(const AText: string; const APreferredLineEndingKind: TDAILineEndingKind): TDAILineEndingKind;
begin
  case APreferredLineEndingKind of
    lekCRLF, lekLF:
      Result := APreferredLineEndingKind;
    lekCR, lekMixed:
      Result := lekCRLF;
    lekNone:
      begin
        Result := DetectLineEnding(AText);
        if Result in [lekCR, lekMixed] then
          Result := lekCRLF;
      end;
  else
    Result := lekCRLF;
  end;
end;

class function TDAITextEncoding.UsesUTF8BOMByDefault(const AFileName: string): Boolean;
begin
  Result := SameText(TPath.GetExtension(AFileName), '.pas');
end;

class function TDAITextEncoding.WithPreamble(const ATextBytes: TBytes; const APreamble: TBytes): TBytes;
begin
  SetLength(Result, Length(APreamble) + Length(ATextBytes));
  if Length(APreamble) > 0 then
    Move(APreamble[0], Result[0], Length(APreamble));
  if Length(ATextBytes) > 0 then
    Move(ATextBytes[0], Result[Length(APreamble)], Length(ATextBytes));
end;

class procedure TDAITextEncoding.InspectFile(const AFileName: string; out AFormat: TDAITextFileFormat);
var
  LBytes: TBytes;
  LText: string;
begin
  LBytes := TFile.ReadAllBytes(AFileName);
  AFormat.EncodingKind := DetectEncoding(AFileName, LBytes);
  LText := DecodeBytes(LBytes, AFormat.EncodingKind);
  AFormat.LineEndingKind := DetectLineEnding(LText);
end;

end.
