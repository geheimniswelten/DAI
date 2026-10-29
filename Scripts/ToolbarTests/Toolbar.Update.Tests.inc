procedure CheckUpdateHint(const AVersion: string);
begin
  Check(Pos('Neue DAI-Version verfügbar', GHost.DAIAction.Hint) > 0, 'The hint states that a new DAI version is available');
  if AVersion <> '' then
    Check(Pos(AVersion, GHost.DAIAction.Hint) > 0, 'The available version is included in the update hint');
end;

procedure TestSoftwareUpdateFlag;
var
  LHealthCount: Integer;
begin
  NewHost;
  TDAIIDEToolbar.SetUpdateAvailable(True, '2.0.5');
  Check(GHost.AddCount = 0, 'Setting an update before Install does not create IDE controls');
  Check(TDAIClientRegistration.HealthCount = 0, 'Setting an update before Install does not scan client registrations');
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'An update set before Install does not override Pause when the toolbar becomes ready');
  CheckUpdateHint('2.0.5');
  Check(Pos('kein aktiver Port', GHost.DAIAction.Hint) > 0, 'The update hint still describes the inactive runtime');
  LHealthCount := TDAIClientRegistration.HealthCount;
  TDAIIDEToolbar.SetUpdateAvailable(True, '2.0.6');
  CheckHealthGlyph('Inactive', 'Changing the available version retains Pause while inactive');
  CheckUpdateHint('2.0.6');
  Check(Pos('2.0.5', GHost.DAIAction.Hint) = 0, 'Changing the available version clears the previous hint version');
  TDAIIDEToolbar.SetUpdateAvailable(True, '2.0.6');
  Check(TDAIClientRegistration.HealthCount = LHealthCount, 'Changing or repeating an update flag does not rescan registrations');
  TDAIIDEToolbar.Shutdown;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'Software-update state survives controller recreation without overriding Pause');
  CheckUpdateHint('2.0.6');
  LHealthCount := TDAIClientRegistration.HealthCount;
  TDAIIDEToolbar.SetUpdateAvailable(False);
  CheckHealthGlyph('Inactive', 'Clearing the update flag restores the normal inactive glyph');
  Check(Pos('Neue DAI-Version verfügbar', GHost.DAIAction.Hint) = 0, 'Clearing the update flag removes its hint');
  TDAIIDEToolbar.SetUpdateAvailable(True);
  CheckHealthGlyph('Inactive', 'A versionless update does not override Pause');
  CheckUpdateHint('');
  Check(Pos('2.0.6', GHost.DAIAction.Hint) = 0, 'A versionless update does not retain a previously cleared version');
  TDAIIDEToolbar.SetUpdateAvailable(False, 'ignored-when-cleared');
  CheckHealthGlyph('Inactive', 'A false update flag wins even when the caller supplies a version');
  Check(Pos('ignored-when-cleared', GHost.DAIAction.Hint) = 0, 'A version supplied with a cleared flag is not displayed');
  Check(TDAIClientRegistration.HealthCount = LHealthCount, 'Enabling and clearing update notices use the cached registration health');
  TDAIRuntime.Active := True;
  TDAIRuntime.Port := 7444;
  TDAIIDEToolbar.Refresh;
  LHealthCount := TDAIClientRegistration.HealthCount;
  TDAIIDEToolbar.SetUpdateAvailable(True, '2.1.0');
  CheckHealthGlyph('UpdateAvailable', 'An available update also replaces the idle active glyph');
  CheckUpdateHint('2.1.0');
  Check(Pos('7444', GHost.DAIAction.Hint) > 0, 'The update hint retains the actual active port');
  TDAIIDEToolbar.SetUpdateAvailable(False);
  CheckHealthGlyph('Active', 'Clearing the update notice restores the idle active glyph');
  Check(TDAIClientRegistration.HealthCount = LHealthCount, 'Software-update flag changes do not invalidate active registration health');
end;

procedure TestSoftwareUpdatePriority;
var
  LHealth: TDAIRegistrationHealth;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  TDAIRuntime.Active := True;
  TDAIRuntime.Port := 7444;
  TDAIIDEToolbar.Refresh;
  TDAIIDEToolbar.SetUpdateAvailable(True, '3.0.0');
  CheckHealthGlyph('UpdateAvailable', 'Software updates appear when higher-priority states are absent');
  for LHealth in [rhNotRegistered, rhUpdateRecommended, rhCheckRecommended] do
  begin
    TDAIClientRegistration.HealthState := LHealth;
    TDAIClientRegistration.HealthDetails := 'Isolated registration attention details.';
    TDAIIDEToolbar.CheckRegistrations;
    if LHealth = rhNotRegistered then
      CheckHealthGlyph('NotRegistered', 'Missing registration takes precedence over a software update')
    else
      CheckHealthGlyph('RegistrationUpdate', 'Registration update/check notices take precedence over a software update');
    CheckUpdateHint('3.0.0');
    Check(Pos(TDAIClientRegistration.HealthDetails, GHost.DAIAction.Hint) > 0, 'Both registration and software update details remain in the hint');
  end;
  TDAIRuntime.HasMCPAccess := True;
  TDAIRuntime.MCPAccessAgeMs := 0;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RecentAccess', 'Recent access takes precedence over software and registration updates');
  CheckUpdateHint('3.0.0');
  TDAIRuntime.MCPAccessAgeMs := 15000;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RecentAccess', 'Access at exactly 15 seconds takes precedence over software updates');
  TDAIRuntime.MCPAccessAgeMs := 15001;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('EarlierAccess', 'Earlier access takes precedence over software and registration updates');
  CheckUpdateHint('3.0.0');
  TDAIRuntime.MCPAccessAgeMs := 900000;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('EarlierAccess', 'Access at exactly 15 minutes takes precedence over software updates');
  TDAIRuntime.MCPAccessAgeMs := 900001;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RegistrationUpdate', 'Expired access restores registration notice before the software update');
  TDAIClientRegistration.HealthState := rhCurrent;
  TDAIClientRegistration.HealthDetails := '';
  TDAIIDEToolbar.CheckRegistrations;
  CheckHealthGlyph('UpdateAvailable', 'Current registrations expose the pending software-update notice');
  TDAIRuntime.FailStop := True;
  GHost.DAIAction.Execute;
  CheckHealthGlyph('Error', 'Runtime errors take precedence over a software-update notice');
  CheckUpdateHint('3.0.0');
  TDAIIDEToolbar.SetUpdateAvailable(False);
  CheckHealthGlyph('Error', 'Clearing an update flag does not clear an existing runtime error');
  Check(Pos('Neue DAI-Version verfügbar', GHost.DAIAction.Hint) = 0, 'Clearing a masked update also removes its hint');
end;

procedure TestSoftwareUpdateThreadGuard;
var
  LThread: TThread;
  LRejected: Integer;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  LRejected := 0;
  LThread := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        TDAIIDEToolbar.SetUpdateAvailable(True, 'worker-version');
      except
        on E: EInvalidOperation do
          Inc(LRejected);
      end;
    end);
  LThread.FreeOnTerminate := False;
  try
    LThread.Start;
    LThread.WaitFor;
    Check(not Assigned(LThread.FatalException), 'Worker update-flag misuse is rejected without uncaught exceptions');
  finally
    LThread.Free;
  end;
  Check(LRejected = 1, 'SetUpdateAvailable requires the IDE main thread');
  CheckHealthGlyph('Inactive', 'A rejected worker call leaves the UI update state unchanged');
  Check(Pos('worker-version', GHost.DAIAction.Hint) = 0, 'A rejected worker call cannot publish its version');
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'A rejected worker call does not leave an update flag for a later refresh');
end;

procedure TestToolbarSoftwareUpdate;
begin
  TestSoftwareUpdateFlag;
  TestSoftwareUpdatePriority;
  TestSoftwareUpdateThreadGuard;
end;
