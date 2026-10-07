program TestDirectorySearch;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  h5u.DAI.Consts,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Settings,
  h5u.DAI.Types;

var
  CheckCount: Integer;
  FixtureDirectory: string;

procedure Check(const ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

function Path(const ARelative: string): string;
begin
  Result := TPath.Combine(FixtureDirectory, ARelative);
end;

procedure WriteFixture(const ARelative, AContent: string; const AEncoding: TEncoding = nil);
var
  LFileName: string;
begin
  LFileName := Path(ARelative);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(LFileName));
  if Assigned(AEncoding) then
    TFile.WriteAllText(LFileName, AContent, AEncoding)
  else
    TFile.WriteAllText(LFileName, AContent, TEncoding.UTF8);
end;

procedure SetBuffer(const ARelative, AContent, ASource: string; const AReaderAvailable: Boolean = True; const AReadFails: Boolean = False);
var
  LBuffer: TTestBuffer;
begin
  LBuffer.Content := AContent;
  LBuffer.Source := ASource;
  LBuffer.ReaderAvailable := AReaderAvailable;
  LBuffer.ReadFails := AReadFails;
  TDAIOTA.TestBuffers.AddOrSetValue(TDAIOTA.NormalizeFileName(Path(ARelative)), LBuffer);
end;

procedure CheckSearch(const APattern, AFilenameRegex, AQuery: string; const AExpected: Integer;
  const AUseRegex: Boolean = False; const ACaseSensitive: Boolean = False; const AWholeWord: Boolean = False;
  const ARecursive: Boolean = False; const ADirectory: string = 'Workspace'; const ALimit: Integer = 5000);
var
  LResult: TJSONArray;
begin
  LResult := TDAIFileService.DirectoryFiles(Path(ADirectory), APattern, ARecursive, ALimit, AFilenameRegex, AQuery, AUseRegex, ACaseSensitive, AWholeWord);
  try
    Check(LResult.Count = AExpected, ADirectory + '/' + APattern + '/' + AFilenameRegex + '/' + AQuery +
      ' expected ' + AExpected.ToString + ' files, actual ' + LResult.Count.ToString);
    for var LIndex := 1 to LResult.Count - 1 do
      Check(CompareStr(LResult[LIndex - 1].Value, LResult[LIndex].Value) <= 0, 'filtered files remain sorted');
  finally
    LResult.Free;
  end;
end;

procedure ExpectFailure(const AAction: TProc; const AClass: ExceptClass; const AMessagePart, ADescription: string);
var
  LFailed: Boolean;
begin
  LFailed := False;
  try
    AAction();
  except
    on E: Exception do
    begin
      Check(E.InheritsFrom(AClass), ADescription + ' exception class: ' + E.ClassName);
      Check(Pos(AMessagePart, E.Message) > 0, ADescription + ' identifies reason/file: ' + E.Message);
      LFailed := True;
    end;
  end;
  Check(LFailed, ADescription + ' is explicitly rejected');
end;

procedure CheckFilters;
var
  LResult, LUnfiltered: TJSONArray;
  LReadCount: Integer;
begin
  CheckSearch('*.pas', '', '', 4);
  CheckSearch('*.pas', '', '', 5, False, False, False, True);
  CheckSearch('A?pha*.pas', '', '', 1);
  CheckSearch('*.pas', '^alpha1\.pas$', '', 1);
  CheckSearch('*.pas', '^alpha1\.pas$', '', 0, False, True);
  CheckSearch('*.pas', '^Alpha1\.pas$', '', 1, False, True);
  CheckSearch('*.inc', '^Alpha1\.pas$', '', 0);
  CheckSearch('*.pas', 'Workspace.*Alpha1', '', 0);
  CheckSearch('*.pas', '', 'Needle', 2);
  CheckSearch('*.pas', '', 'Needle', 3, False, False, False, True);
  CheckSearch('*.pas', '', 'needle', 0, False, True);
  CheckSearch('*.pas', '^Alpha', 'MARK_IMPL', 1);
  CheckSearch('*.pas', '^Beta', 'MARK_IMPL', 0);
  CheckSearch('*.pas', '', 'T(Button|Edit)', 0);
  CheckSearch('*.pas', '', 'T(Button|Edit)', 1, True);
  CheckSearch('*.pas', '', 'Needle\s+second', 1, True);
  CheckSearch('*.pas', '', '(?m)^second$', 1, True);
  CheckSearch('*.pas', '^ALPHA', 'needle', 0, False, True);
  CheckSearch('*.pas', '^Alpha', 'needle', 1);
  CheckSearch('*.pas', '', 'Needle', 1, False, False, False, True, 'Workspace', 1);
  CheckSearch('*.txt', '', 'Caf' + #$00E9, 4, False, True, False, False, 'Encoding');
  CheckSearch('*.pas', '', 'Caf' + #$00E9, 1, False, True, False, False, 'Encoding');
  CheckSearch('Short*.txt', '', '.*', 4, True, False, False, False, 'Encoding');
  CheckSearch('TrailingCR.txt', '', 'x\r$', 1, True, False, False, False, 'Encoding');
  CheckSearch('TruncatedUTF8.txt', '', TEncoding.ANSI.GetString(TBytes.Create($F0, $9F)), 1, False, True, False, False, 'Encoding');
  CheckSearch('*.txt', '', 'Needle', 1, False, False, True, False, 'Words');
  CheckSearch('Blocked.txt', '', 'Needle', 0, False, False, True, False, 'Words');
  CheckSearch('Blocked.txt', '', 'Needle', 0, True, False, True, False, 'Words');
  CheckSearch('Blocked.txt', '', '(?=Needle)', 0, True, False, True, False, 'Words');
  CheckSearch('RejectedAlternative.dat', '', 'a.*a|needle', 1, True, False, True, False, 'Words');
  CheckSearch('Empty.txt', '', '^$', 1, True, False, True, False, 'Words');
  CheckSearch('Punctuation.txt', '', '^', 1, True, False, True, False, 'Words');
  CheckSearch('*.pas', '', 'readonly', 1, False, False, False, False, 'References');
  LReadCount := TDAIOTA.TestReadCount;
  SetBuffer('Workspace\Alpha1.pas', '', 'editor_buffer', True, True);
  CheckSearch('*.pas', '^Beta', 'Needle', 1);
  Check(TDAIOTA.TestReadCount = LReadCount, 'filename-rejected files are never read');
  CheckSearch('*.pas', '^Alpha', '', 1);
  Check(TDAIOTA.TestReadCount = LReadCount, 'empty content query reads no buffers');
  TDAIOTA.TestBuffers.Clear;

  // Use the exact RTL wildcard matcher even on the guarded content-filter path.
  LUnfiltered := TDAIFileService.DirectoryFiles(Path('Workspace'), '*.*', False, 5000);
  LResult := TDAIFileService.DirectoryFiles(Path('Workspace'), '*.*', False, 5000, '', 'ALL_FILES');
  try
    Check(LResult.ToJSON = LUnfiltered.ToJSON, '*.* retains the original GetFiles semantics, including extensionless files');
  finally
    LResult.Free;
    LUnfiltered.Free;
  end;
end;

procedure CheckBuffers;
var
  LLock: TFileStream;
begin
  SetBuffer('Workspace\Alpha1.pas', 'unit Alpha1; interface implementation const Value = ''MARK_EDITOR''; end.', 'editor_buffer');
  CheckSearch('Alpha1.pas', '', 'MARK_EDITOR', 1);
  CheckSearch('Alpha1.pas', '', 'MARK_IMPL', 0);
  Check(Pos('MARK_IMPL', TFile.ReadAllText(Path('Workspace\Alpha1.pas'), TEncoding.UTF8)) > 0, 'buffer search never saves source');
  LLock := TFileStream.Create(Path('Workspace\Alpha1.pas'), fmOpenReadWrite or fmShareExclusive);
  try
    CheckSearch('Alpha1.pas', '', 'MARK_EDITOR', 1);
  finally
    LLock.Free;
  end;
  SetBuffer('Workspace\Alpha1.pas', '', 'editor_buffer', False);
  ExpectFailure(procedure begin CheckSearch('Alpha1.pas', '', 'MARK_IMPL', 0); end, EInvalidOperation, 'Alpha1.pas', 'unavailable editor reader');
  SetBuffer('Workspace\Alpha1.pas', '', 'editor_buffer', True, True);
  ExpectFailure(procedure begin CheckSearch('Alpha1.pas', '', 'MARK_IMPL', 0); end, EInvalidOperation, 'Alpha1.pas', 'editor read failure');
  TDAIOTA.TestBuffers.Clear;
  SetBuffer('Forms\Main.dfm', 'object Main: TForm Caption = ''MARK_DESIGNER'' end', 'designer_buffer');
  CheckSearch('*.dfm', '', 'MARK_DESIGNER', 1, False, False, False, False, 'Forms');
  CheckSearch('*.dfm', '', 'stale-designer-disk', 0, False, False, False, False, 'Forms');
  SetBuffer('Forms\Main.dfm', '', 'designer_buffer', False);
  ExpectFailure(procedure begin CheckSearch('*.dfm', '', 'stale-designer-disk', 0, False, False, False, False, 'Forms'); end,
    EInvalidOperation, 'Main.dfm', 'unavailable designer text');
  TDAIOTA.TestBuffers.Clear;
  Check(TDAIOTA.WriteCount = 0, 'directory search never writes editor buffers');
  Check(TDAIOTA.SaveCount = 0, 'directory search never saves editor buffers');
end;

procedure CheckErrors;
var
  LLock: TFileStream;
begin
  ExpectFailure(procedure begin CheckSearch('*', '[', '', 0, False, False, False, False, 'Empty'); end,
    EArgumentException, 'regex', 'invalid filename regex on empty directory');
  ExpectFailure(procedure begin CheckSearch('*', '', '[', 0, True, False, False, False, 'Empty'); end,
    EArgumentException, 'regex', 'invalid content regex on empty directory');
  ExpectFailure(procedure begin CheckSearch('*', '', '', 0, True, False, False, False, 'DoesNotExist'); end,
    EArgumentException, 'content_query', 'content regex without query');
  ExpectFailure(procedure begin CheckSearch('*', StringOfChar('a', 257), '', 0); end,
    EArgumentException, '256', 'oversized filename regex');
  ExpectFailure(procedure begin CheckSearch('*', '', StringOfChar('a', 257), 0); end,
    EArgumentException, '256', 'oversized content query');
  ExpectFailure(procedure begin CheckSearch('*', '', 'a' + #0, 0); end,
    EArgumentException, 'NUL', 'NUL content query');
  ExpectFailure(procedure begin CheckSearch('*', '', 'a' + #10, 0, True); end,
    EArgumentException, 'Zeilenumbr', 'raw newline content regex');
  ExpectFailure(procedure begin CheckSearch('..\*.pas', '', '', 0); end,
    EArgumentException, 'Verzeichnispfad', 'path traversal glob');
  ExpectFailure(procedure begin CheckSearch('*.pas', '', 'Needle', 0, False, False, False, False, 'Outside'); end,
    EDAIAccessDenied, 'Workspace', 'outside authorized roots');
  CheckSearch('*.bin', '', '', 1, False, False, False, False, 'Errors');
  ExpectFailure(procedure begin CheckSearch('*.bin', '', 'Needle', 0, False, False, False, False, 'Errors'); end,
    EInvalidOperation, 'Binary.bin', 'binary content is explicit');
  CheckSearch('*.big', '', '', 1, False, False, False, False, 'Errors');
  ExpectFailure(procedure begin CheckSearch('*.big', '', 'Needle', 0, False, False, False, False, 'Errors'); end,
    EInvalidOperation, 'Oversized.big', 'oversized content is explicit');
  ExpectFailure(procedure begin CheckSearch('*.txt', '', 'Needle', 0, False, False, False, False, 'UnsupportedEncoding'); end,
    EInvalidOperation, 'UTF32.txt', 'unsupported encoding is explicit');
  ExpectFailure(procedure begin CheckSearch('RegexLimit.txt', '', '(a+)+$', 0, True, False, False, False, 'Errors'); end,
    EInvalidOperation, 'RegexLimit.txt', 'regex execution limit identifies the affected file');
  LLock := TFileStream.Create(Path('Workspace\Beta2.PAS'), fmOpenReadWrite or fmShareExclusive);
  try
    ExpectFailure(procedure begin CheckSearch('Beta2.PAS', '', 'Needle', 0); end, EInvalidOperation, 'Beta2.PAS', 'locked disk file');
  finally
    LLock.Free;
  end;
end;

procedure CheckJunctions;
var
  LResult: TJSONArray;
begin
  if ParamCount = 0 then
    Exit;
  TDAIOTA.TestWorkspaceRoots := TDAIOTA.TestWorkspaceRoots + [ParamStr(1)];
  ExpectFailure(procedure begin
    LResult := TDAIFileService.DirectoryFiles(ParamStr(1), '*.pas', True, 5000, '', 'MARK_OUTSIDE');
    LResult.Free;
  end, EDAIAccessDenied, 'Reparse', 'recursive junction is rejected before content reads');
  ExpectFailure(procedure begin
    LResult := TDAIFileService.DirectoryFiles(TPath.Combine(ParamStr(1), 'Alias'), '*.pas', False, 5000, '', 'MARK_OUTSIDE');
    LResult.Free;
  end, EDAIAccessDenied, 'Reparse', 'selected junction is rejected before content reads');
end;

procedure CreateFixtures;
var
  LGuid: TGUID;
  LStream: TFileStream;
begin
  CreateGUID(LGuid);
  FixtureDirectory := TPath.Combine(TPath.GetTempPath, 'DAI-DirectorySearch-Fixture-' + GUIDToString(LGuid));
  WriteFixture('Workspace\Alpha1.pas', 'unit Alpha1; interface implementation' + #13#10 + 'Needle' + #13#10 + 'second' + #13#10 + 'MARK_IMPL ALL_FILES end.');
  WriteFixture('Workspace\Beta2.PAS', 'Needle ALL_FILES');
  WriteFixture('Workspace\Regex.pas', 'TButton ALL_FILES');
  WriteFixture('Workspace\Other.pas', 'Other ALL_FILES');
  WriteFixture('Workspace\Extra.inc', 'Extra ALL_FILES');
  WriteFixture('Workspace\NoExtension', 'ALL_FILES');
  WriteFixture('Workspace\Nested\Gamma3.pas', 'Needle ALL_FILES');
  WriteFixture('Encoding\Utf16.txt', 'Caf' + #$00E9, TEncoding.Unicode);
  WriteFixture('Encoding\Utf16BE.txt', 'Caf' + #$00E9, TEncoding.BigEndianUnicode);
  WriteFixture('Encoding\Utf8.txt', 'Caf' + #$00E9);
  TFile.WriteAllBytes(Path('Encoding\Utf8NoBOM.txt'), TEncoding.UTF8.GetBytes('Caf' + #$00E9));
  WriteFixture('Encoding\Short0.txt', '');
  WriteFixture('Encoding\Short1.txt', 'x');
  WriteFixture('Encoding\Short2.txt', 'xy');
  WriteFixture('Encoding\Short3.txt', 'xyz');
  WriteFixture('Encoding\TrailingCR.txt', 'x' + #13);
  TFile.WriteAllBytes(Path('Encoding\TruncatedUTF8.txt'), [$F0, $9F]);
  TFile.WriteAllBytes(Path('Encoding\Ansi.pas'), TEncoding.ANSI.GetBytes('Caf' + #$00E9));
  WriteFixture('Words\Blocked.txt', 'XNeedleY Needle_ Needle' + #$0301 + ' ' + #$D801#$DC00 + 'Needle');
  WriteFixture('Words\RejectedAlternative.dat', 'xa needle a ');
  WriteFixture('Words\Whole.txt', '!Needle!');
  WriteFixture('Words\Empty.txt', '');
  WriteFixture('Words\Punctuation.txt', '!');
  WriteFixture('Forms\Main.dfm', 'stale-designer-disk');
  WriteFixture('References\Reference.pas', 'Needle readonly');
  TFile.SetAttributes(Path('References\Reference.pas'), [TFileAttribute.faReadOnly]);
  WriteFixture('Outside\Outside.pas', 'Needle');
  WriteFixture('Errors\Binary.bin', 'Needle' + #0 + 'binary');
  WriteFixture('Errors\RegexLimit.txt', StringOfChar('a', 30000) + 'X');
  LStream := TFileStream.Create(Path('Errors\Oversized.big'), fmCreate);
  try
    LStream.Size := CDAIMaxTextFileBytes + 1;
  finally
    LStream.Free;
  end;
  WriteFixture('UnsupportedEncoding\UTF32.txt', '');
  TFile.WriteAllBytes(Path('UnsupportedEncoding\UTF32.txt'), [$FF, $FE, $00, $00, $4E, $00, $00, $00]);
  TDirectory.CreateDirectory(Path('Empty'));
  TDAIOTA.TestWorkspaceRoots := [Path('Workspace'), Path('Encoding'), Path('Words'), Path('Forms'), Path('Errors'), Path('UnsupportedEncoding'), Path('Empty')];
  TDAISettings.TestReadRoots := [Path('References')];
end;

procedure CleanFixtures;
var
  LTemporaryDirectory: string;
begin
  TDAIOTA.TestBuffers.Clear;
  TDAIOTA.TestWorkspaceRoots := nil;
  TDAISettings.TestReadRoots := nil;
  LTemporaryDirectory := ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.GetTempPath));
  if FixtureDirectory = '' then
    Exit;
  if not SameText(TPath.GetDirectoryName(TPath.GetFullPath(FixtureDirectory)), LTemporaryDirectory) or
    not TPath.GetFileName(FixtureDirectory).StartsWith('DAI-DirectorySearch-Fixture-{') then
    raise EInvalidOperation.Create('Fixture cleanup path is outside the temporary directory.');
  if TFile.Exists(Path('References\Reference.pas')) then
    TFile.SetAttributes(Path('References\Reference.pas'), []);
  if TDirectory.Exists(FixtureDirectory) then
    TDirectory.Delete(FixtureDirectory, True);
end;

begin
  try
    try
      CreateFixtures;
      CheckFilters;
      CheckBuffers;
      CheckErrors;
      CheckJunctions;
      Writeln('PASS: ', CheckCount, ' isolated directory search checks; real file service/regex/encoding, no live IDE or client settings.');
    finally
      CleanFixtures;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
