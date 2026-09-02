unit CodexMCP.TextFiles;

interface

uses
  System.SysUtils;

type
  TCodexTextEncoding = (
    cteAnsi,
    cteUtf8,
    cteUtf8Bom,
    cteUtf16LE,
    cteUtf16BE
  );

function ReadTextFilePreservingEncoding(
  const AFileName: string;
  out AText: string;
  out AEncoding: TCodexTextEncoding
): Boolean;
procedure WriteTextFilePreservingEncoding(
  const AFileName,
  AText: string;
  const AEncoding: TCodexTextEncoding
);
function TextEncodingName(const AEncoding: TCodexTextEncoding): string;
function SHA256Text(const AText: string): string;

implementation

uses
  System.Classes,
  System.Hash,
  System.IOUtils;

function HasPrefix(
  const ABytes: TBytes;
  const APrefix: array of Byte
): Boolean;
var
  LIndex: Integer;
begin
  Result := Length(ABytes) >= Length(APrefix);
  if not Result then
    Exit;
  for LIndex := Low(APrefix) to High(APrefix) do
    if ABytes[LIndex] <> APrefix[LIndex] then
      Exit(False);
end;

function IsValidUtf8(const ABytes: TBytes; const AStart: Integer): Boolean;
var
  LContinuationCount: Integer;
  LIndex: Integer;
  LLead: Byte;
  LSubIndex: Integer;
begin
  Result := True;
  LIndex := AStart;
  while LIndex < Length(ABytes) do
  begin
    LLead := ABytes[LIndex];
    if LLead < $80 then
    begin
      Inc(LIndex);
      Continue;
    end;
    if (LLead and $E0) = $C0 then
      LContinuationCount := 1
    else if (LLead and $F0) = $E0 then
      LContinuationCount := 2
    else if (LLead and $F8) = $F0 then
      LContinuationCount := 3
    else
      Exit(False);
    if LIndex + LContinuationCount >= Length(ABytes) then
      Exit(False);
    for LSubIndex := 1 to LContinuationCount do
      if (ABytes[LIndex + LSubIndex] and $C0) <> $80 then
        Exit(False);
    Inc(LIndex, LContinuationCount + 1);
  end;
end;

function CreateEncoding(
  const AEncoding: TCodexTextEncoding;
  out AOwnsEncoding: Boolean
): TEncoding;
begin
  AOwnsEncoding := False;
  case AEncoding of
    cteAnsi:
      Result := TEncoding.Default;
    cteUtf8:
      begin
        Result := TUTF8Encoding.Create(False);
        AOwnsEncoding := True;
      end;
    cteUtf8Bom:
      begin
        Result := TUTF8Encoding.Create(True);
        AOwnsEncoding := True;
      end;
    cteUtf16LE:
      Result := TEncoding.Unicode;
    cteUtf16BE:
      Result := TEncoding.BigEndianUnicode;
  else
    begin
      Result := TUTF8Encoding.Create(False);
      AOwnsEncoding := True;
    end;
  end;
end;

function ReadTextFilePreservingEncoding(
  const AFileName: string;
  out AText: string;
  out AEncoding: TCodexTextEncoding
): Boolean;
var
  LBytes: TBytes;
  LEncoding: TEncoding;
  LOffset: Integer;
  LOwnsEncoding: Boolean;
begin
  AText := '';
  AEncoding := cteUtf8;
  Result := TFile.Exists(AFileName);
  if not Result then
    Exit;

  LBytes := TFile.ReadAllBytes(AFileName);
  LOffset := 0;
  if HasPrefix(LBytes, [$EF, $BB, $BF]) then
  begin
    AEncoding := cteUtf8Bom;
    LOffset := 3;
  end
  else if HasPrefix(LBytes, [$FF, $FE]) then
  begin
    AEncoding := cteUtf16LE;
    LOffset := 2;
  end
  else if HasPrefix(LBytes, [$FE, $FF]) then
  begin
    AEncoding := cteUtf16BE;
    LOffset := 2;
  end
  else if IsValidUtf8(LBytes, 0) then
    AEncoding := cteUtf8
  else
    AEncoding := cteAnsi;

  LEncoding := CreateEncoding(AEncoding, LOwnsEncoding);
  try
    AText := LEncoding.GetString(LBytes, LOffset, Length(LBytes) - LOffset);
  finally
    if LOwnsEncoding then
      LEncoding.Free;
  end;
end;

function SHA256Text(const AText: string): string;
begin
  Result := THashSHA2.GetHashString(AText);
end;

function TextEncodingName(const AEncoding: TCodexTextEncoding): string;
begin
  case AEncoding of
    cteAnsi:
      Result := 'ansi';
    cteUtf8:
      Result := 'utf-8';
    cteUtf8Bom:
      Result := 'utf-8-bom';
    cteUtf16LE:
      Result := 'utf-16-le';
    cteUtf16BE:
      Result := 'utf-16-be';
  else
    Result := 'unknown';
  end;
end;

procedure WriteTextFilePreservingEncoding(
  const AFileName,
  AText: string;
  const AEncoding: TCodexTextEncoding
);
var
  LDirectory: string;
  LEncoding: TEncoding;
  LOwnsEncoding: Boolean;
begin
  LDirectory := TPath.GetDirectoryName(AFileName);
  if LDirectory <> '' then
    ForceDirectories(LDirectory);
  LEncoding := CreateEncoding(AEncoding, LOwnsEncoding);
  try
    TFile.WriteAllText(AFileName, AText, LEncoding);
  finally
    if LOwnsEncoding then
      LEncoding.Free;
  end;
end;

end.
