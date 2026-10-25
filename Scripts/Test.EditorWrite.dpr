program TestEditorWrite;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Hash,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.Types,
  h5u.DAI.OTA.Files,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Text.Encoding;

type
  TDAIFormTextFixture = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

var
  CheckCount: Integer;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + ADescription);
end;

procedure CheckMatch(const ARequested, AActual: string; AExpected: Boolean; const ADescription: string);
begin
  Check(TDAITextEncoding.EditorWriteMatches(ARequested, AActual) = AExpected, ADescription);
end;

procedure CheckResult(const AWriteResult: TJSONObject; const ADescription: string);
var
  ReadResult: TJSONObject;
begin
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0, False);
  try
    Check(AWriteResult.GetValue<string>('sha256') = ReadResult.GetValue<string>('sha256'), ADescription + ' hash matches readback');
    Check(AWriteResult.GetValue<string>('line_ending') = ReadResult.GetValue<string>('line_ending'), ADescription + ' line ending matches readback');
    Check(AWriteResult.GetValue<string>('target') = 'editor_buffer', ADescription + ' editor target');
  finally
    ReadResult.Free;
  end;
end;

procedure CheckInterfaceReads;
const
  CPublicText = 'unit IsolatedBuffer;' + #13#10 + 'interface' + #13#10 +
    'const PublicValue = ''implementation'';' + #13#10 + '{ implementation is a comment }' + #13#10;
  CCompleteText = CPublicText + 'ImPlEmEnTaTiOn' + #13#10 + 'const PrivateValue = 123;' + #13#10 + 'end.' + #13#10;
var
  ReadResult: TJSONObject;
  FullHash: string;
begin
  TDAIOTA.Reset(CCompleteText);
  FullHash := THashSHA2.GetHashString(CCompleteText);
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0);
  try
    Check(ReadResult.GetValue<string>('content') = CPublicText, 'default read excludes actual implementation only');
    Check(ReadResult.GetValue<Boolean>('interfaces_only'), 'default read interfaces_only true');
    Check(ReadResult.GetValue<Boolean>('implementation_omitted'), 'interface omission explicitly marked');
    Check(not ReadResult.GetValue<Boolean>('truncated'), 'omitted implementation is distinct from maximum-character limit');
    Check(not ReadResult.GetValue<Boolean>('content_complete'), 'interface read is not complete content');
    Check(ReadResult.GetValue<Integer>('original_characters') = Length(CCompleteText), 'original characters cover complete buffer');
    Check(ReadResult.GetValue<Integer>('view_characters') = Length(CPublicText), 'view characters cover interface before maximum limit');
    Check(ReadResult.GetValue<string>('sha256') = FullHash, 'interface read retains full content hash');
    Check(ReadResult.GetValue<string>('sha256_scope') = 'complete_content', 'full hash scope explicitly marked');
    Check(ReadResult.GetValue<string>('source') = 'editor_buffer', 'interface read retains source metadata');
    Check(TDAIOTA.Buffer = CCompleteText, 'interface read does not change editor buffer');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0, False);
  try
    Check(ReadResult.GetValue<string>('content') = CCompleteText, 'explicit false includes implementation');
    Check(not ReadResult.GetValue<Boolean>('interfaces_only'), 'explicit false mode marked');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'full read has no omission');
    Check(ReadResult.GetValue<Boolean>('content_complete'), 'full unlimited read complete');
    Check(ReadResult.GetValue<string>('sha256') = FullHash, 'full read and interface read share full hash');
    Check(ReadResult.GetValue<Integer>('view_characters') = Length(CCompleteText), 'full view length');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 10);
  try
    Check(ReadResult.GetValue<string>('content') = Copy(CPublicText, 1, 10), 'maximum characters applied after interface view');
    Check(ReadResult.GetValue<Boolean>('truncated'), 'limited view marked truncated');
    Check(ReadResult.GetValue<Boolean>('implementation_omitted'), 'limited view retains implementation omission');
    Check(not ReadResult.GetValue<Boolean>('content_complete'), 'limited interface view incomplete');
    Check(ReadResult.GetValue<Integer>('view_characters') = Length(CPublicText), 'view length before character limit');
    Check(ReadResult.GetValue<string>('sha256') = FullHash, 'limited interface view retains complete hash');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 10, False);
  try
    Check(ReadResult.GetValue<Boolean>('truncated'), 'full-source maximum limit still marked');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'full-source maximum limit is not interface omission');
    Check(not ReadResult.GetValue<Boolean>('content_complete'), 'limited full-source view incomplete');
  finally
    ReadResult.Free;
  end;
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.dfm', 0);
  try
    Check(ReadResult.GetValue<string>('content') = CCompleteText, 'non-PAS content unmodified');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'non-PAS has no implementation omission');
    Check(ReadResult.GetValue<Boolean>('content_complete'), 'non-PAS unlimited content complete');
  finally
    ReadResult.Free;
  end;
  TDAIOTA.Reset('unit Incomplete; interface' + #10 + 'const PublicValue = 1;');
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0);
  try
    Check(ReadResult.GetValue<string>('content') = TDAIOTA.Buffer, 'missing implementation retains complete content');
    Check(not ReadResult.GetValue<Boolean>('implementation_omitted'), 'missing implementation not marked omitted');
    Check(ReadResult.GetValue<Boolean>('content_complete'), 'missing implementation can be complete current buffer');
  finally
    ReadResult.Free;
  end;
end;

procedure CheckUnitWriteGuards;
const
  COriginal = 'unit IsolatedBuffer; interface implementation const Preserved = 1; end.';
  CInvalidContents: array[0..5] of string = (
    '',
    'unit IsolatedBuffer; interface const PublicValue = 1;',
    'unit IsolatedBuffer; implementation end.',
    'unit IsolatedBuffer; interface { implementation end. }',
    'unit IsolatedBuffer; interface const Fake = ''implementation end.'';',
    'unit IsolatedBuffer; interface implementation');
var
  Content: string;
  Denied: Boolean;
  ReadResult: TJSONObject;
  WriteResult: TJSONObject;
  UsedEditor: Boolean;
begin
  for Content in CInvalidContents do
  begin
    TDAIOTA.Reset(COriginal);
    Denied := False;
    try
      WriteResult := TDAIFileService.WriteFile('IsolatedBuffer.pas', Content, THashSHA2.GetHashString(COriginal), True, UsedEditor);
      WriteResult.Free;
    except
      on E: EArgumentException do
        Denied := True;
    end;
    Check(Denied, 'incomplete PAS unit rejected');
    Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0) and (TDAIOTA.Buffer = COriginal), 'PAS guard runs before writer/save');
  end;
  TDAIOTA.Reset(COriginal);
  ReadResult := TDAIFileService.ReadFile('IsolatedBuffer.pas', 0);
  try
    Denied := False;
    try
      WriteResult := TDAIFileService.WriteFile('IsolatedBuffer.pas', ReadResult.GetValue<string>('content'),
        ReadResult.GetValue<string>('sha256'), False, UsedEditor);
      WriteResult.Free;
    except
      on E: EArgumentException do
        Denied := True;
    end;
    Check(Denied, 'accidental write of interface view rejected despite valid full hash');
    Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.Buffer = COriginal), 'interface view write preserves implementation');
  finally
    ReadResult.Free;
  end;
end;

function ParseNativeFormCaption(const AText: string): string;
var
  Input: TStringStream;
  Binary: TMemoryStream;
  Component: TDAIFormTextFixture;
begin
  // The native DFM parser uses ANSI without a BOM. These are the same UTF-8
  // bytes that the OTA writer transfers to the IDE, not a simulated parser.
  Input := TStringStream.Create(AText, TEncoding.UTF8);
  Binary := TMemoryStream.Create;
  Component := nil;
  try
    ObjectTextToBinary(Input, Binary);
    Binary.Position := 0;
    Component := TDAIFormTextFixture(Binary.ReadComponent(nil));
    Result := Component.Caption;
  finally
    Component.Free;
    Binary.Free;
    Input.Free;
  end;
end;

procedure CheckFormUnicode(const AExtension: string);
const
  CCaption = 'DAI Designer - Grüße 漢字 Ελληνικά Кириллица ' + #$D83D#$DE00;
var
  Content: string;
  Original: string;
  ResultJson: TJSONObject;
  ReadJson: TJSONObject;
  UsedEditor: Boolean;
  Denied: Boolean;
  ActualCaption: string;
begin
  Original := 'object Fixture: TDAIFormTextFixture' + #13#10 + '  Caption = ''original''' + #13#10 + 'end' + #13#10;
  Content := StringReplace(Original, 'original', CCaption, []);
  Check(ParseNativeFormCaption(Content) <> CCaption, 'raw UTF-8 form reproduces native ANSI interpretation');
  TDAIOTA.Reset(Original);
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.' + AExtension, Content, THashSHA2.GetHashString(Original), False, UsedEditor);
  try
    Check(UsedEditor, 'Unicode form uses the IDE text buffer');
    Check(not ResultJson.GetValue<Boolean>('saved') and (TDAIOTA.SaveCount = 0), 'Unicode form save=false never saves');
    Check(ParseNativeFormCaption(TDAIOTA.Buffer) = CCaption, 'native form conversion preserves all Unicode characters');
    Check(Pos('#252', TDAIOTA.Buffer) > 0, 'native serializer emits Unicode character escapes');
    Check(ResultJson.GetValue<string>('sha256') = THashSHA2.GetHashString(TDAIOTA.Buffer), 'Unicode form returns actual normalized buffer hash');
    ReadJson := TDAIFileService.ReadFile('IsolatedBuffer.' + AExtension, 0, False);
    try
      Check(ReadJson.GetValue<string>('content') = TDAIOTA.Buffer, 'Unicode form readback includes actual canonical text');
      Check(ReadJson.GetValue<string>('sha256') = ResultJson.GetValue<string>('sha256'), 'Unicode form read/write hashes agree');
    finally
      ReadJson.Free;
    end;
  finally
    ResultJson.Free;
  end;
  Content := 'object Fixture: TDAIFormTextFixture' + #13#10 + '  Caption = ''Grüße ''''quoted''''''#9 + ' + #13#10 +
    '    ''漢字''#13#10#55357#56832' + #13#10 + 'end' + #13#10;
  TDAIOTA.Reset(Original);
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.' + AExtension, Content, '', False, UsedEditor);
  try
    ActualCaption := ParseNativeFormCaption(TDAIOTA.Buffer);
    Check(ActualCaption = 'Grüße ''quoted''' + #9 + '漢字' + #13#10 + #$D83D#$DE00,
      'native form conversion preserves quotes, concatenation, numeric controls and surrogate pairs');
  finally
    ResultJson.Free;
  end;
  Content := 'object GrüßeFixture: TDAIFormTextFixture' + #13#10 + '  Caption = #256''Grüße''' + #13#10 + 'end' + #13#10;
  TDAIOTA.Reset(Original);
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.' + AExtension, Content, '', True, UsedEditor);
  try
    Check(ParseNativeFormCaption(TDAIOTA.Buffer) = #$0100 + 'Grüße', 'raw Unicode beside existing wide escape preserves string values');
    Check(TDAIOTA.Buffer.StartsWith(#$FEFF), 'Unicode object identifier retains native UTF-8 BOM');
    Check(ResultJson.GetValue<Boolean>('saved') and (TDAIOTA.SaveCount = 1), 'canonical Unicode form also supports explicit save');
    Check(ResultJson.GetValue<string>('sha256') = THashSHA2.GetHashString(TDAIOTA.Buffer), 'explicit save returns actual Unicode form hash');
  finally
    ResultJson.Free;
  end;
  TDAIOTA.Reset(Original);
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.' + AExtension, Original, '', False, UsedEditor);
  try
    Check(TDAIOTA.Buffer = Original, 'ASCII form source is preserved exactly');
  finally
    ResultJson.Free;
  end;
  TDAIOTA.Reset(Original);
  Denied := False;
  try
    ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.' + AExtension, 'object Invalid Grüße', '', False, UsedEditor);
    ResultJson.Free;
  except
    on E: Exception do
      Denied := True;
  end;
  Check(Denied and (TDAIOTA.WriteCount = 0) and (TDAIOTA.Buffer = Original), 'invalid Unicode form is rejected before editor mutation');
end;

procedure CheckOpenForeignFileGuards;
const
  COriginal = 'unit IsolatedBuffer; interface implementation end.';
  CChanged = 'unit IsolatedBuffer; interface implementation { changed } end.';
var
  LDenied: Boolean;
  LUsedEditor: Boolean;
  LResult: TJSONObject;
begin
  TDAIOTA.Reset(COriginal);
  Check(Assigned(TDAIOTA.FindSourceEditor('Foreign.pas')) and TDAIOTA.IsFileOpenInEditor('Foreign.pas'), 'foreign fixture has an open editor');
  LResult := TDAIFileService.ReadFile('Foreign.pas', 0, False);
  try
    Check(LResult.GetValue<string>('content') = COriginal, 'an explicitly allowed open foreign file can be read');
  finally
    LResult.Free;
  end;
  LResult := TDAIFileService.WriteFile('Foreign.pas', CChanged, THashSHA2.GetHashString(COriginal), False, LUsedEditor);
  try
    Check(LUsedEditor and (TDAIOTA.Buffer = CChanged), 'an allowed open foreign file uses the existing editor buffer for writes');
    Check((TDAIOTA.WriteCount = 1) and (TDAIOTA.SaveCount = 0), 'open foreign writes preserve the requested unsaved state');
  finally
    LResult.Free;
  end;
  TDAIOTA.Reset(COriginal);
  TDAIOTA.OpenEditor := False;
  TDAIOTA.WorkspaceAllowed := False;
  LDenied := False;
  try
    LResult := TDAIFileService.ReadFile('Foreign.pas', 0, False);
    LResult.Free;
  except
    on E: EDAIAccessDenied do
      LDenied := True;
  end;
  Check(LDenied, 'a closed external file cannot bypass the file read boundary');
  LDenied := False;
  try
    LResult := TDAIFileService.WriteFile('Foreign.pas', COriginal, '', False, LUsedEditor);
    LResult.Free;
  except
    on E: EDAIAccessDenied do
      LDenied := True;
  end;
  Check(LDenied, 'a closed external file cannot bypass the project write boundary');
  Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0) and (TDAIOTA.Buffer = COriginal), 'foreign write preserves editor and save state');

  TDAIOTA.ReadOnlyReference := True;
  TDAIOTA.OpenEditor := True;
  LResult := TDAIFileService.ReadFile('Foreign.pas', 0, False);
  try
    Check(LResult.GetValue<string>('content') = COriginal, 'read-only reference can be read through its open buffer');
  finally
    LResult.Free;
  end;
  TDAIOTA.WorkspaceAllowed := True;
  LDenied := False;
  try
    LResult := TDAIFileService.WriteFile('IsolatedBuffer.pas', COriginal, '', True, LUsedEditor);
    LResult.Free;
  except
    on E: EDAIAccessDenied do
      LDenied := True;
  end;
  Check(LDenied and (TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0), 'read-only reference denies writes even when also a workspace file');
end;

procedure CheckPermissionPolicyWriteGuards;
const
  COriginal = '{"version":2,"permissions":{"compile":"never","execute":"never"}}';
  CChanged = '{"version":2,"permissions":{"compile":"always","execute":"always"}}';
  CNames: array[0..3] of string = ('Policy.dai.permissions.json', 'POLICY.DAI.PERMISSIONS.JSON',
    'Policy.dai.permissions.json.', 'Policy.dai.permissions.json::$DATA');
var
  LDirectory: string;
  LPolicyFile: string;
  LName: string;
  LShortPath: string;
  LRequired: DWORD;
  LWritten: DWORD;
  LExists: Boolean;
  LOpenEditor: Boolean;
  LDenied: Boolean;
  LUsedEditor: Boolean;
  LResult: TJSONObject;
begin
  LDirectory := TPath.Combine(TPath.GetTempPath, 'DAI-Policy-Write-Test-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LDirectory);
  LPolicyFile := TPath.Combine(LDirectory, 'Policy.dai.permissions.json');
  try
    for LName in CNames do
      for LExists in TArray<Boolean>.Create(False, True) do
        for LOpenEditor in TArray<Boolean>.Create(False, True) do
        begin
          if LExists then
            TFile.WriteAllText(LPolicyFile, COriginal, TEncoding.UTF8);
          try
            TDAIOTA.Reset(COriginal);
            TDAIOTA.OpenEditor := LOpenEditor;
            LDenied := False;
            LUsedEditor := True;
            try
              LResult := TDAIFileService.WriteFile(IncludeTrailingPathDelimiter(LDirectory) + LName, CChanged, '', True, LUsedEditor);
              LResult.Free;
            except
              on E: EDAIAccessDenied do
                LDenied := True;
            end;
            Check(LDenied, 'permission policy writes are denied for existing/new files, buffers, case and Windows aliases');
            Check(not LUsedEditor, 'permission policy denial does not expose or select an editor buffer');
            Check((TDAIOTA.ReadCount = 0) and (TDAIOTA.FindCount = 0), 'permission policy guard precedes editor lookup and content reads');
            Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0), 'permission policy denial invokes neither editor writer nor save');
            Check(TDAIOTA.Buffer = COriginal, 'permission policy denial preserves the original editor contents');
            Check(TFile.Exists(LPolicyFile) = LExists, 'permission policy denial never creates a new policy file');
            if LExists then
              Check(TFile.ReadAllText(LPolicyFile, TEncoding.UTF8) = COriginal, 'permission policy denial preserves existing disk contents');
          finally
            if TFile.Exists(LPolicyFile) then
              TFile.Delete(LPolicyFile);
          end;
        end;
    TFile.WriteAllText(LPolicyFile, COriginal, TEncoding.UTF8);
    try
      LRequired := GetShortPathNameW(PWideChar(LPolicyFile), nil, 0);
      LShortPath := '';
      if LRequired > 0 then
      begin
        SetLength(LShortPath, LRequired);
        LWritten := GetShortPathNameW(PWideChar(LPolicyFile), PWideChar(LShortPath), LRequired);
        if (LWritten > 0) and (LWritten < LRequired) then
          SetLength(LShortPath, LWritten)
        else
          LShortPath := '';
      end;
      if (LShortPath <> '') and not SameText(TPath.GetFileName(LShortPath), TPath.GetFileName(LPolicyFile)) then
      begin
        TDAIOTA.Reset(COriginal);
        LDenied := False;
        try
          LResult := TDAIFileService.WriteFile(LShortPath, CChanged, '', True, LUsedEditor);
          LResult.Free;
        except
          on E: EDAIAccessDenied do
            LDenied := True;
        end;
        Check(LDenied, 'an existing 8.3 alias cannot bypass the permission policy write guard');
        Check((TDAIOTA.ReadCount = 0) and (TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0), '8.3 policy denial precedes editor access');
        Check(TDAIOTA.Buffer = COriginal, '8.3 policy denial preserves the editor buffer');
        Check(TFile.ReadAllText(LPolicyFile, TEncoding.UTF8) = COriginal, '8.3 policy denial preserves the existing disk contents');
      end
      else
        Writeln('SKIP: no distinct 8.3 policy filename is available on the isolated test volume.');
    finally
      TFile.Delete(LPolicyFile);
    end;
    TDAIOTA.Reset(COriginal);
    LResult := TDAIFileService.WriteFile(TPath.Combine(LDirectory, 'Notes.dai.permissions.json.txt'), CChanged, '', False, LUsedEditor);
    try
      Check(LUsedEditor and (TDAIOTA.WriteCount = 1), 'a similar ordinary filename remains editable through its existing buffer');
      Check(TDAIOTA.Buffer = CChanged, 'the policy guard matches the basename suffix rather than an arbitrary substring');
    finally
      LResult.Free;
    end;
  finally
    TDirectory.Delete(LDirectory);
  end;
end;

procedure CheckLoadedFileGuards;
const
  COriginal = 'unit Loaded; interface implementation { original } end.';
  CChanged = 'unit Loaded; interface implementation { changed } end.';
  CNames: array[0..8] of string = ('Loaded.dproj', 'Loaded.groupproj', 'Loaded.bdsgroup', 'Loaded.bpg', 'Loaded.dpk', 'Loaded.dpr',
    'PairedForm.pas', 'PairedForm.dfm', 'PairedForm.fmx');
var
  LDirectory, LFileName, LName: string;
  LDenied, LSave, LUsedEditor: Boolean;
  LOriginalBytes: TBytes;
  LResult: TJSONObject;
begin
  LDirectory := TPath.Combine(TPath.GetTempPath, 'DAI-Loaded-File-Test-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LDirectory);
  try
    for LName in CNames do
    begin
      LFileName := TPath.Combine(LDirectory, LName);
      TFile.WriteAllText(LFileName, COriginal, TEncoding.UTF8);
      try
        LOriginalBytes := TFile.ReadAllBytes(LFileName);
        TDAIOTA.Reset(COriginal);
        TDAIOTA.OpenEditor := False;
        TDAIOTA.LoadedModule := True;
        LDenied := False;
        try
          LResult := TDAIFileService.ReadFile(LFileName, 0, False);
          LResult.Free;
        except
          on E: EInvalidOperation do
          begin
            LDenied := True;
            Check(Pos('IDE', E.Message) > 0, 'loaded module read explains the unavailable IDE source');
          end;
        end;
        Check(LDenied, 'a loaded project, source or paired form cannot be read from stale disk without its buffer');
        for LSave in TArray<Boolean>.Create(False, True) do
        begin
          LDenied := False;
          try
            LResult := TDAIFileService.WriteFile(LFileName, CChanged, THashSHA2.GetHashString(COriginal), LSave, LUsedEditor);
            LResult.Free;
          except
            on E: EInvalidOperation do
              LDenied := True;
          end;
          Check(LDenied, 'loaded module without a buffer rejects file_write even with a matching hash and save=true');
          Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0), 'loaded module denial never writes or saves an editor');
          Check(CompareMem(Pointer(LOriginalBytes), Pointer(TFile.ReadAllBytes(LFileName)), Length(LOriginalBytes)),
            'loaded module denial preserves disk bytes exactly');
        end;
      finally
        TFile.Delete(LFileName);
      end;
    end;
    for LName in ['Loaded.dproj', 'Loaded.groupproj', 'Loaded.bdsgroup', 'Loaded.bpg'] do
    begin
      TDAIOTA.Reset(COriginal);
      LDenied := False;
      try
        LResult := TDAIFileService.WriteFile(TPath.Combine(LDirectory, LName), CChanged, '', True, LUsedEditor);
        LResult.Free;
      except
        on E: EInvalidOperation do
          LDenied := True;
      end;
      Check(LDenied, 'loaded project models require project OTA even if they expose a source editor');
      Check((TDAIOTA.ReadCount = 0) and (TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0),
        'loaded project model guard precedes editor access and all saves');
    end;
    for LName in ['Loaded.dpr', 'Loaded.dpk'] do
    begin
      TDAIOTA.Reset(COriginal);
      LResult := TDAIFileService.ReadFile(TPath.Combine(LDirectory, LName), 0, False);
      try
        Check(LResult.GetValue<string>('content') = COriginal, 'DPR and DPK use an available project source editor');
        Check(LResult.GetValue<string>('source') = 'editor_buffer', 'project source origin identifies the live buffer');
      finally
        LResult.Free;
      end;
      LResult := TDAIFileService.WriteFile(TPath.Combine(LDirectory, LName), CChanged, THashSHA2.GetHashString(COriginal), False, LUsedEditor);
      try
        Check(LUsedEditor and (TDAIOTA.Buffer = CChanged), 'DPR and DPK are editable through their live IDE source buffer');
        Check((TDAIOTA.WriteCount = 1) and (TDAIOTA.SaveCount = 0), 'project source save=false preserves the unsaved state');
        Check(not TFile.Exists(TPath.Combine(LDirectory, LName)), 'project source buffer edits do not create or overwrite disk files');
      finally
        LResult.Free;
      end;
    end;

    LFileName := TPath.Combine(LDirectory, 'LateLoaded.pas');
    TFile.WriteAllText(LFileName, COriginal, TEncoding.UTF8);
    try
      TDAIOTA.Reset(COriginal);
      TDAIOTA.OpenEditor := False;
      TDAIOTA.LoadOnFinalLookup := True;
      LDenied := False;
      try
        LResult := TDAIFileService.WriteFile(LFileName, CChanged, THashSHA2.GetHashString(COriginal), True, LUsedEditor);
        LResult.Free;
      except
        on E: EInvalidOperation do
          LDenied := True;
      end;
      Check(LDenied, 'a module loaded after the initial hash read cannot fall through to disk');
      Check(TFile.ReadAllText(LFileName, TEncoding.UTF8) = COriginal, 'late module loading preserves disk content');
      Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0), 'late module loading invokes no writer or save');

      TDAIOTA.Reset(COriginal);
      TDAIOTA.OpenEditor := False;
      TDAIOTA.OpenOnFinalLookup := True;
      TDAIOTA.FinalBuffer := COriginal + ' { user change }';
      LDenied := False;
      try
        LResult := TDAIFileService.WriteFile(LFileName, CChanged, THashSHA2.GetHashString(COriginal), True, LUsedEditor);
        LResult.Free;
      except
        on E: EInvalidOperation do
          LDenied := True;
      end;
      Check(LDenied, 'an editor opened during preflight retains newer unsaved user text');
      Check(TDAIOTA.Buffer = COriginal + ' { user change }', 'late editor conflict preserves unsaved contents');
      Check((TDAIOTA.WriteCount = 0) and (TDAIOTA.SaveCount = 0), 'late editor conflict neither replaces nor saves');
      Check(TFile.ReadAllText(LFileName, TEncoding.UTF8) = COriginal, 'late editor conflict also preserves disk');

      TDAIOTA.Reset(COriginal);
      TDAIOTA.OpenEditor := False;
      TDAIOTA.OpenOnFinalLookup := True;
      TDAIOTA.FinalBuffer := COriginal;
      LResult := TDAIFileService.WriteFile(LFileName, CChanged, THashSHA2.GetHashString(COriginal), False, LUsedEditor);
      try
        Check(LUsedEditor and (TDAIOTA.Buffer = CChanged), 'a matching newly opened editor is used instead of disk');
        Check(TDAIOTA.SaveCount = 0, 'newly opened editor save=false never saves user changes');
        Check(TFile.ReadAllText(LFileName, TEncoding.UTF8) = COriginal, 'the newly selected editor route leaves disk unchanged');
      finally
        LResult.Free;
      end;

      TDAIOTA.Reset(COriginal);
      TDAIOTA.OpenEditor := False;
      LResult := TDAIFileService.WriteFile(LFileName, CChanged, THashSHA2.GetHashString(COriginal), True, LUsedEditor);
      try
        Check(not LUsedEditor and (LResult.GetValue<string>('target') = 'disk'), 'a genuinely closed source remains writable to disk');
        Check(TFile.ReadAllText(LFileName, TEncoding.UTF8) = CChanged, 'closed source preserves the existing encoding-aware write route');
      finally
        LResult.Free;
      end;
    finally
      TFile.Delete(LFileName);
    end;
  finally
    TDirectory.Delete(LDirectory);
    TDAIOTA.Reset(COriginal);
  end;
end;

procedure RunChecks;
const
  CUnicode = 'unit IsolatedBuffer; interface { Grüße 漢字 ' + #$D83D#$DE00 + ' } implementation end.';
  CNextUnit = 'unit IsolatedBuffer; interface implementation { next } end.';
  CSavedUnit = 'unit IsolatedBuffer; interface implementation { saved } end.';
var
  ResultJson: TJSONObject;
  UsedEditor: Boolean;
  Hash: string;
  Denied: Boolean;
begin
  CheckMatch('', '', True, 'empty exact');
  CheckMatch('', #13#10, True, 'empty plus IDE CRLF');
  CheckMatch('unit Sample;', 'unit Sample;', True, 'exact source');
  CheckMatch('unit Sample;', 'unit Sample;' + #13#10, True, 'one extra IDE CRLF');
  CheckMatch(CUnicode, CUnicode, True, 'Unicode exact');
  CheckMatch(CUnicode, CUnicode + #13#10, True, 'Unicode plus IDE CRLF');
  CheckMatch('a' + #10, 'a' + #10, True, 'requested trailing LF exact');
  CheckMatch('a' + #10, 'a' + #10#13#10, True, 'requested LF preserved plus IDE CRLF');
  CheckMatch('a' + #13#10, 'a' + #13#10, True, 'requested trailing CRLF exact');
  CheckMatch('a' + #13#10, 'a' + #13#10#13#10, True, 'requested CRLF preserved plus one IDE CRLF');
  CheckMatch('a' + #13#10#13#10, 'a' + #13#10#13#10, True, 'requested empty trailing line preserved');
  CheckMatch('a', 'a' + #13#10#13#10, False, 'two extra CRLF denied');
  CheckMatch('a' + #13#10, 'a' + #13#10#13#10#13#10, False, 'two extra CRLF after existing terminator denied');
  CheckMatch('a' + #10, 'a', False, 'lost LF denied');
  CheckMatch('a' + #13#10#13#10, 'a' + #13#10, False, 'lost trailing empty line denied');
  CheckMatch('a', 'a' + #10, False, 'extra bare LF denied');
  CheckMatch('a', 'a' + #13, False, 'extra bare CR denied');
  CheckMatch('a ', 'a' + #13#10, False, 'lost trailing whitespace denied');
  CheckMatch('a' + #13#10 + 'b', 'a' + #13#10, False, 'lost content denied');
  CheckMatch('a' + #0 + 'b', 'a', False, 'NUL truncation denied');
  CheckMatch('a' + #0 + 'b', 'a' + #0 + 'b', False, 'NUL request unsupported by OTA insert');
  CheckMatch('a', 'a' + #0#13#10, False, 'unexpected NUL denied');

  TDAIOTA.Reset('original');
  TDAIOTA.AppendOnWrite := #13#10;
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CUnicode, '', False, UsedEditor);
  try
    Check(UsedEditor, 'writer reports editor buffer');
    Check(TDAIOTA.Buffer = CUnicode + #13#10, 'simulated IDE appended one CRLF');
    Check(not ResultJson.GetValue<Boolean>('saved'), 'unsaved editor response');
    Check(ResultJson.GetValue<string>('sha256') <> THashSHA2.GetHashString(CUnicode), 'returned hash includes actual CRLF');
    CheckResult(ResultJson, 'write without save');
    Hash := ResultJson.GetValue<string>('sha256');
  finally
    ResultJson.Free;
  end;
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CNextUnit, Hash, False, UsedEditor);
  try
    CheckResult(ResultJson, 'next write accepts previous returned hash');
  finally
    ResultJson.Free;
  end;

  TDAIOTA.Reset('original');
  TDAIOTA.AppendOnSave := #10;
  ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CSavedUnit, '', True, UsedEditor);
  try
    Check(TDAIOTA.SaveCount = 1, 'save called once');
    Check(TDAIOTA.Buffer = CSavedUnit + #10, 'save changed the buffer');
    Check(ResultJson.GetValue<Boolean>('saved'), 'saved response');
    CheckResult(ResultJson, 'readback after save');
  finally
    ResultJson.Free;
  end;

  TDAIOTA.Reset('original');
  Denied := False;
  try
    ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', 'unit IsolatedBuffer; interface implementation { a' + #0 + 'b } end.', '', False, UsedEditor);
    ResultJson.Free;
  except
    on E: EInvalidOperation do
      Denied := True;
  end;
  Check(Denied and (TDAIOTA.WriteCount = 0) and (TDAIOTA.Buffer = 'original'), 'NUL rejected before any write');

  TDAIOTA.Reset('original');
  TDAIOTA.AppendOnWrite := #13#10#13#10;
  Denied := False;
  try
    ResultJson := TDAIFileService.WriteFile('IsolatedBuffer.pas', CNextUnit, '', False, UsedEditor);
    ResultJson.Free;
  except
    on E: EInvalidOperation do
      Denied := True;
  end;
  Check(Denied, 'file_write rejects two extra CRLF');
end;

begin
  try
    System.Classes.RegisterClass(TDAIFormTextFixture);
    RunChecks;
    CheckOpenForeignFileGuards;
    CheckPermissionPolicyWriteGuards;
    CheckLoadedFileGuards;
    CheckInterfaceReads;
    CheckUnitWriteGuards;
    CheckFormUnicode('dfm');
    CheckFormUnicode('fmx');
    Writeln('PASS: ', CheckCount, ' isolated native editor write/read-view checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
