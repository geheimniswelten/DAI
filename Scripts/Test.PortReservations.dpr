program TestPortReservations;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  Winapi.Windows,
  h5u.DAI.PortReservations in '..\Source\h5u.DAI.PortReservations.pas';

var
  Checks: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then
    raise Exception.Create('FAILED: ' + AMessage);
end;

procedure ExpectFailure(const AManager: TDAIPortReservations; const AMessage: string);
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    AManager.Reserve('DAI:failure', 0, 0);
  except
    on E: EDAIPortReservation do
      LRaised := True;
  end;
  Check(LRaised, AMessage);
end;

procedure RunTests(const ADirectory, AMutex: string);
var
  LManager: TDAIPortReservations;
  LFiles: TArray<string>;
  LFile, LForeign, LData, LRenamed: string;
  LFirst, LSecond, LThird, LFourth, LManualPort, LSearchPort, LRangeStart, LRangeEnd: Integer;
  LFailed, LUsesSharedRange: Boolean;
  LAttributes: DWORD;
begin
  LManager := TDAIPortReservations.Create(ADirectory, AMutex);
  try
    Check(not LManager.Exists, 'missing directory is detected without creating it');
    Check(not LManager.ConfiguredRange(LRangeStart, LRangeEnd), 'a missing shared configuration has no range');
    LManualPort := LManager.FindAvailablePort(24000, LRangeStart, LRangeEnd, LUsesSharedRange);
    Check(not LUsesSharedRange and (LRangeStart = 24000) and (LRangeEnd = 65535), 'standalone search starts at the entered port');
    Check((LManualPort >= 24000) and (LManualPort <= 65535), 'standalone search returns an available port at or after the input');
    Check(not LManager.Exists, 'standalone search does not create the shared directory');
    LFailed := False;
    try
      LManager.FindAvailablePort(0, LRangeStart, LRangeEnd, LUsesSharedRange);
    except
      on E: EDAIPortReservation do
        LFailed := True;
    end;
    Check(LFailed, 'standalone search rejects an invalid starting port');
    LManager.Initialize;
    Check(LManager.Exists, 'setup creates directory');
    Check(LManager.ConfiguredRange(LRangeStart, LRangeEnd) and (LRangeStart = 17331) and (LRangeEnd = 17430),
      'shared application configuration exposes its complete range');
    Check(LManager.CanWrite, 'current user can create and update reservation files');
    Check(TFile.Exists(TPath.Combine(ADirectory, '.DAI')), 'setup creates application description');
    LData := TFile.ReadAllText(TPath.Combine(ADirectory, '.DAI'), TEncoding.UTF8);
    Check(StartsStr('Delphi AI', LData), 'application description starts with human-readable name');
    LManager.Initialize;
    Check(TFile.ReadAllText(TPath.Combine(ADirectory, '.DAI'), TEncoding.UTF8) = LData, 'setup preserves existing description');
    Check(LManager.OwnPorts('DAI:dai') = '', 'no reservation before explicit action');
    Check(LManager.Reserve('DAI:outside', LManualPort, 0, False) = LManualPort, 'manual port outside the range remains available');
    Check(LManager.OwnPorts('DAI:outside') = IntToStr(LManualPort), 'outside port is recorded unchanged');
    Check(not LManager.ReservedByOther('DAI:outside', LManualPort), 'the matching own reservation is allowed');
    Check(LManager.ReservedByOther('DAI:dai', LManualPort), 'another scope cannot claim the same reserved port');
    LSearchPort := LManager.FindAvailablePort(50000, LRangeStart, LRangeEnd, LUsesSharedRange);
    Check(LUsesSharedRange and (LRangeStart = 17331) and (LRangeEnd = 17430), 'shared search uses the configured range');
    Check((LSearchPort >= LRangeStart) and (LSearchPort <= LRangeEnd), 'shared search returns a port inside the configured range');
    Check(LManager.OwnPorts('DAI:dai') = '', 'search does not reserve a port');
    LFirst := LManager.Reserve('DAI:dai', 0, 0);
    Check((LFirst >= 17331) and (LFirst <= 17430), 'fallback uses application range');
    Check(LManager.OwnPorts('DAI:dai') = IntToStr(LFirst), 'reservation is discoverable');
    LSearchPort := LManager.FindAvailablePort(50000, LRangeStart, LRangeEnd, LUsesSharedRange);
    Check(LSearchPort <> LFirst, 'shared search skips a reserved port even when it is not listening');
    Check(LManager.OwnPorts('DAI:dai') = IntToStr(LFirst), 'search leaves existing reservations unchanged');
    Check(LManager.Reserve('DAI:dai', LFirst, 0) = LFirst, 'same reservation is idempotent');
    LSecond := LManager.Reserve('DAI:dai_bds37_0', LFirst, 0);
    Check(LSecond <> LFirst, 'another scope cannot claim the first port');
    Check(LManager.OwnPorts('DAI:dai_bds37_0') = IntToStr(LSecond), 'local profile uses its own reservation');
    LFiles := TDirectory.GetFiles(ADirectory, 'S-1-*');
    Check(Length(LFiles) = 1, 'one shared user file');
    LFile := LFiles[0];
    LData := TFile.ReadAllText(LFile, TEncoding.UTF8);
    Check(LManager.CanWrite, 'current user can replace the owned reservation file');
    LAttributes := GetFileAttributes(PChar(LFile));
    Check((LAttributes <> INVALID_FILE_ATTRIBUTES) and SetFileAttributes(PChar(LFile), LAttributes or FILE_ATTRIBUTE_READONLY),
      'test can mark its own file read-only');
    try
      Check(not LManager.CanWrite, 'read-only user file is detected without changing it');
      Check(LManager.OwnPorts('DAI:dai') = IntToStr(LFirst), 'read-only reservation remains visible');
    finally
      if not SetFileAttributes(PChar(LFile), LAttributes) then
        RaiseLastOSError;
    end;
    Check(StartsStr('# Benutzer: ', LData), 'username is recorded for humans');
    Check(ContainsStr(ExtractFileName(LFile), '_'), 'filename contains SID and username separator');
    LRenamed := Copy(LFile, 1, LastDelimiter('_', LFile)) + 'PreviousName';
    TFile.Move(LFile, LRenamed);
    LFile := LRenamed;
    Check(LManager.OwnPorts('DAI:dai') = IntToStr(LFirst), 'username suffix is ignored when finding the current SID');
    Check(Length(TDirectory.GetFiles(ADirectory, 'S-1-*')) = 1, 'renamed account does not create a second file');
    LForeign := TPath.Combine(ADirectory, 'S-1-5-21-987-654-321-987_Foreign');
    LThird := 17430;
    if (LThird = LFirst) or (LThird = LSecond) then
      LThird := 17429;
    TFile.WriteAllText(LForeign, IntToStr(LThird) + #9 + 'FirefoxMCP:http' + sLineBreak, TEncoding.UTF8);
    Check(LManager.ReservedByOther('DAI:dai', LThird), 'another user reservation is detected');
    TFile.Move(TPath.Combine(ADirectory, '.DAI'), TPath.Combine(ADirectory, '.temporary-app'));
    try
      LSearchPort := LManager.FindAvailablePort(LThird, LRangeStart, LRangeEnd, LUsesSharedRange);
      Check(not LUsesSharedRange and (LRangeStart = LThird), 'without app configuration search starts at current port');
      Check(LSearchPort > LThird, 'shared reservations are respected even without an app-specific range');
    finally
      TFile.Move(TPath.Combine(ADirectory, '.temporary-app'), TPath.Combine(ADirectory, '.DAI'));
    end;
    Check(LManager.Reserve('DAI:foreign', LThird, 0) <> LThird, 'ports of other users and applications are respected');
    LFailed := False;
    try
      LManager.Reserve('DAI:exact', LThird, 0, False);
    except
      on E: EDAIPortReservation do
        LFailed := True;
    end;
    Check(LFailed, 'exact reservation rejects a conflict without silently choosing another port');
    Check(LManager.OwnPorts('DAI:exact') = '', 'failed exact reservation writes nothing');
    LFourth := LManager.Reserve('DAI:dai', LThird, 0);
    Check((LFourth <> LFirst) and (LFourth <> LThird), 'changed port receives a separate free reservation');
    Check(LManager.OwnPorts('DAI:dai') = IntToStr(LFirst) + ', ' + IntToStr(LFourth),
      'changing a port does not silently release the previous registration');
    Check(TFile.ReadAllText(LForeign, TEncoding.UTF8) = IntToStr(LThird) + #9 + 'FirefoxMCP:http' + sLineBreak,
      'foreign user file is not changed');
    Check(not LManager.Release('DAI:other', LFirst), 'cannot release a different key');
    Check(LManager.Release('DAI:dai', LFirst), 'own reservation can be released');
    Check(LManager.OwnPorts('DAI:dai') = IntToStr(LFourth), 'only the explicitly released port disappears');
    Check(LManager.OwnPorts('DAI:dai_bds37_0') = IntToStr(LSecond), 'other scopes survive release');
    TFile.WriteAllText(LForeign, 'kaputt', TEncoding.UTF8);
    ExpectFailure(LManager, 'malformed user file stops allocation');
    Check(TFile.ReadAllText(LForeign, TEncoding.UTF8) = 'kaputt', 'malformed data is not overwritten');
    TFile.WriteAllText(LForeign, IntToStr(LSecond) + #9 + 'FirefoxMCP:http' + sLineBreak, TEncoding.UTF8);
    ExpectFailure(LManager, 'duplicate reservations stop allocation');
    TFile.Delete(LForeign);
    TFile.WriteAllText(TPath.Combine(ADirectory, '.DAI'), '', TEncoding.UTF8);
    ExpectFailure(LManager, 'empty application description is rejected cleanly');
    TFile.WriteAllText(TPath.Combine(ADirectory, '.DAI'), 'Delphi AI' + sLineBreak + 'Schema=99' + sLineBreak +
      'StartPort=17331' + sLineBreak + 'MaxAnzahl=100' + sLineBreak, TEncoding.UTF8);
    ExpectFailure(LManager, 'unknown application schema is rejected');
    // Restore a valid app description for the concurrent-process phase.
    TFile.WriteAllText(TPath.Combine(ADirectory, '.DAI'), 'Delphi AI' + sLineBreak + 'Schema=1' + sLineBreak +
      'StartPort=17331' + sLineBreak + 'MaxAnzahl=100' + sLineBreak + 'Protokoll=TCP' + sLineBreak +
      'BindAdresse=127.0.0.1' + sLineBreak, TEncoding.UTF8);
    Writeln('PASS ', Checks, ' checks');
  finally
    LManager.Free;
  end;
end;

var
  LManager: TDAIPortReservations;
  LRangeStart, LRangeEnd: Integer;
  LUsesSharedRange: Boolean;
begin
  try
    if (ParamCount = 1) and SameText(ParamStr(1), '--default-directory') then
    begin
      LManager := TDAIPortReservations.Create;
      try
        Writeln(LManager.Directory);
      finally
        LManager.Free;
      end;
    end
    else if (ParamCount = 4) and SameText(ParamStr(1), '--search') then
    begin
      LManager := TDAIPortReservations.Create(ParamStr(2), ParamStr(3));
      try
        Writeln(LManager.FindAvailablePort(StrToInt(ParamStr(4)), LRangeStart, LRangeEnd, LUsesSharedRange));
      finally
        LManager.Free;
      end;
    end
    else if (ParamCount >= 4) and SameText(ParamStr(1), '--worker') then
    begin
      LManager := TDAIPortReservations.Create(ParamStr(2), ParamStr(3));
      try
        Writeln(LManager.Reserve(ParamStr(4), StrToIntDef(ParamStr(5), 0), 0));
      finally
        LManager.Free;
      end;
    end
    else if ParamCount = 2 then
      RunTests(ParamStr(1), ParamStr(2))
    else
      raise Exception.Create('Expected directory and mutex name.');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
