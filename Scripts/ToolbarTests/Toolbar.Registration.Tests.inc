procedure CheckHealthGlyph(const AName, ADescription: string);
begin
  Check(Pos('ServerGlyph.v4.' + AName, GHost.DAIAction.ImageName) > 0, ADescription);
  Check(GHost.DAIButton.ImageName = GHost.DAIAction.ImageName, 'The toolbar follows the exact health action image');
end;

procedure TestRegistrationHealthCaching;
var
  LCount: Integer;
  LIndex: Integer;
begin
  NewHost;
  TDAIClientRegistration.HealthState := rhNotRegistered;
  TDAIClientRegistration.HealthDetails := 'No matching registration in this isolated client.';
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = 1, 'Package activation scans registrations exactly once');
  CheckHealthGlyph('Inactive', 'An inactive server retains Pause despite a missing registration');
  Check(GHost.DAIAction.Caption = 'DAI inaktiv', 'Missing registration does not override the inactive caption');
  Check(Pos(TDAIClientRegistration.HealthDetails, GHost.DAIAction.Hint) > 0, 'Missing-registration details appear in the hint');
  Check(Pos('kein aktiver Port', GHost.DAIAction.Hint) > 0, 'Inactive warning still states the inactive runtime');
  LCount := TDAIClientRegistration.HealthCount;
  for LIndex := 1 to 5 do
    TDAIIDEToolbar.Refresh;
  PumpFor(1150);
  Check(TDAIClientRegistration.HealthCount = LCount, 'Ordinary refresh and timer ticks reuse cached registration health');
  TDAIClientRegistration.HealthState := rhCurrent;
  TDAIClientRegistration.HealthDetails := '';
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'Unchanged inactive status does not poll external fixtures');
  Check(Pos('No matching registration', GHost.DAIAction.Hint) > 0, 'Cached registration diagnostics remain until invalidation');
  TDAIIDEToolbar.CheckRegistrations;
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = LCount + 1, 'Explicit registration check performs one fresh scan');
  CheckHealthGlyph('Inactive', 'Current registrations restore the inactive glyph');
  Check(Pos('No matching registration', GHost.DAIAction.Hint) = 0, 'A current registration clears obsolete health details');
  TDAIClientRegistration.HealthState := rhUpdateRecommended;
  TDAIClientRegistration.HealthDetails := 'Client fixture needs its new launcher entry.';
  Inc(TDAIClientRegistration.Version);
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = LCount + 2, 'A changed registration revision invalidates the cache');
  CheckHealthGlyph('Inactive', 'Changed registration revision retains Pause while inactive');
  Check(Pos(TDAIClientRegistration.HealthDetails, GHost.DAIAction.Hint) > 0, 'Changed registration revision updates the diagnostic hint');
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = LCount + 2, 'The scanned revision is retained after refresh');
  TDAIRuntime.Active := True;
  TDAIRuntime.Port := 7444;
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = LCount + 3, 'An externally activated server triggers a fresh registration check');
  CheckHealthGlyph('RegistrationUpdate', 'An active server may still require a registration update');
  Check(Pos('7444', GHost.DAIAction.Hint) > 0, 'Active registration warning shows the actual live port');
  TDAIRuntime.Active := False;
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = LCount + 4, 'An externally deactivated server also refreshes registrations');
  GHost.DAIAction.Execute;
  Check(TDAIClientRegistration.HealthCount = LCount + 5, 'The toolbar activation action checks registrations again');
  GHost.DAIAction.Execute;
  Check(TDAIClientRegistration.HealthCount = LCount + 6, 'The toolbar deactivation action checks registrations again');
end;

procedure TestRegistrationHealthPriority;
begin
  NewHost;
  TDAIClientRegistration.HealthState := rhUpdateRecommended;
  TDAIClientRegistration.HealthDetails := 'Update fixture needs its launcher registration.';
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'An update recommendation retains Pause while inactive');
  Check(GHost.DAIAction.Caption = 'DAI inaktiv', 'An old registration does not override the inactive caption');
  TDAIRuntime.Active := True;
  TDAIRuntime.Port := 7444;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RegistrationUpdate', 'An active server displays its registration update notice');
  Check(GHost.DAIAction.Caption = 'DAI: Registrierung aktualisieren', 'An active registration notice has a clear caption');
  TDAIRuntime.HasMCPAccess := True;
  TDAIRuntime.MCPAccessAgeMs := 0;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RecentAccess', 'Recent client activity takes precedence over an update notice');
  Check(Pos(TDAIClientRegistration.HealthDetails, GHost.DAIAction.Hint) > 0, 'Recent activity retains registration details in the hint');
  TDAIRuntime.MCPAccessAgeMs := 15000;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RecentAccess', 'Activity at exactly 15 seconds still takes precedence');
  TDAIRuntime.MCPAccessAgeMs := 15001;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('EarlierAccess', 'Earlier activity takes precedence over an update notice');
  TDAIRuntime.MCPAccessAgeMs := 900000;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('EarlierAccess', 'Activity at exactly 15 minutes still takes precedence');
  TDAIRuntime.MCPAccessAgeMs := 900001;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RegistrationUpdate', 'Expired activity restores the registration update notice');
  TDAIClientRegistration.HealthState := rhNotRegistered;
  TDAIIDEToolbar.CheckRegistrations;
  CheckHealthGlyph('NotRegistered', 'Missing registration also shows while the server is active');
  TDAIRuntime.MCPAccessAgeMs := 0;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RecentAccess', 'Recent activity takes precedence over a missing-registration notice');
  TDAIRuntime.MCPAccessAgeMs := 15001;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('EarlierAccess', 'Earlier activity takes precedence over a missing-registration notice');
  TDAIRuntime.Active := False;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'An inactive server displays Pause before stale activity and registration notices');
  TDAIRuntime.FailStart := True;
  GHost.DAIAction.Execute;
  CheckHealthGlyph('Inactive', 'A failed start retains Pause before a registration notice');
  Check(Pos('isolated bind failed', GHost.DAIAction.Hint) > 0, 'Registration notices do not conceal the runtime failure reason');
  TDAIRuntime.FailStart := False;
  GHost.DAIAction.Execute;
  CheckHealthGlyph('EarlierAccess', 'Clearing a runtime error restores activity precedence');
  TDAIRuntime.FailStop := True;
  GHost.DAIAction.Execute;
  CheckHealthGlyph('Error', 'Runtime stop errors also take precedence over activity and registration notices');
end;

procedure TestRegistrationHealthReadFailure;
var
  LCount: Integer;
begin
  NewHost;
  TDAIRuntime.Active := True;
  TDAIRuntime.Port := 7331;
  TDAIClientRegistration.HealthState := rhCheckRecommended;
  TDAIClientRegistration.HealthDetails := 'Client fixture contains an unrecognised registration.';
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RegistrationUpdate', 'Unknown registration status uses the check exclamation glyph');
  Check(GHost.DAIAction.Caption = 'DAI: Registrierung prüfen', 'An uncertain registration has a check caption');
  Check(Pos(TDAIClientRegistration.HealthDetails, GHost.DAIAction.Hint) > 0, 'Unknown-registration details appear in the tooltip');
  TDAIClientRegistration.RaiseHealth := True;
  TDAIIDEToolbar.CheckRegistrations;
  CheckHealthGlyph('RegistrationUpdate', 'A registration read exception is contained as a check notice');
  Check(GHost.DAIAction.Enabled, 'A registration read exception leaves the start action usable');
  Check(Pos('DAI-Optionen', GHost.DAIAction.Hint) > 0, 'The failed-check notice explains where to resolve its read failure');
  LCount := TDAIClientRegistration.HealthCount;
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = LCount, 'Failed registration scans are cached until a new trigger');
  TDAIClientRegistration.RaiseHealth := False;
  TDAIClientRegistration.HealthState := rhCurrent;
  TDAIClientRegistration.HealthDetails := '';
  TDAIIDEToolbar.CheckRegistrations;
  CheckHealthGlyph('Active', 'An explicit successful recheck clears the active registration read failure');
end;

procedure TestManualRegistrationConfirmation;
var
  LCount: Integer;
begin
  NewHost;
  TDAIClientRegistration.HealthState := rhNotRegistered;
  TDAIClientRegistration.HealthDetails := 'No managed registration fixture.';
  TDAIIDEToolbar.Install;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'A stopped fresh installation displays Pause while retaining registration details');
  LCount := TDAIClientRegistration.HealthCount;
  TDAISettings.Instance.ManualClientRegistration := True;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'User-confirmed manual registration suppresses only the missing-registration notice');
  Check(TDAIClientRegistration.HealthState = rhNotRegistered, 'Manual confirmation does not fabricate a verified managed registration');
  Check(Pos('vom Benutzer bestätigt', GHost.DAIAction.Hint) > 0, 'The tooltip identifies manual registration as a user confirmation');
  Check(Pos('No managed registration fixture', GHost.DAIAction.Hint) = 0, 'The suppressed missing-registration detail is removed');
  Check(TDAIClientRegistration.HealthCount = LCount + 1, 'A changed manual confirmation invalidates cached toolbar health');
  TDAIIDEToolbar.Refresh;
  Check(TDAIClientRegistration.HealthCount = LCount + 1, 'An unchanged manual confirmation retains cached registration scans');
  TDAIIDEToolbar.SetUpdateAvailable(True, '4.0.0');
  CheckHealthGlyph('Inactive', 'A software update does not override Pause after manual registration');
  Check(Pos('4.0.0', GHost.DAIAction.Hint) > 0, 'Manual registration retains the software-update version in its hint');
  TDAIRuntime.Active := True;
  TDAIRuntime.HasMCPAccess := True;
  TDAIRuntime.MCPAccessAgeMs := 0;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RecentAccess', 'Manual registration preserves recent-access activity');
  TDAIRuntime.MCPAccessAgeMs := 15001;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('EarlierAccess', 'Manual registration preserves earlier-access activity');
  TDAIRuntime.HasMCPAccess := False;
  TDAIClientRegistration.HealthState := rhUpdateRecommended;
  TDAIIDEToolbar.CheckRegistrations;
  CheckHealthGlyph('RegistrationUpdate', 'Manual confirmation never suppresses a registration-update notice');
  Check(GHost.DAIAction.Caption = 'DAI: Registrierung aktualisieren', 'Manual confirmation retains the update caption');
  TDAIClientRegistration.HealthState := rhCheckRecommended;
  TDAIIDEToolbar.CheckRegistrations;
  CheckHealthGlyph('RegistrationUpdate', 'Manual confirmation never suppresses an uncertain registration');
  TDAIClientRegistration.RaiseHealth := True;
  TDAIIDEToolbar.CheckRegistrations;
  CheckHealthGlyph('RegistrationUpdate', 'Manual confirmation never suppresses registration read failures');
  TDAIClientRegistration.RaiseHealth := False;
  TDAIClientRegistration.HealthState := rhNotRegistered;
  TDAIIDEToolbar.CheckRegistrations;
  TDAISettings.Instance.RaiseManualRead := True;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('RegistrationUpdate', 'A failed manual-confirmation read becomes a check notice');
  Check(Pos('manuelle KI-Registrierung', GHost.DAIAction.Hint) > 0, 'The hint identifies a failed manual-confirmation read');
  TDAISettings.Instance.RaiseManualRead := False;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('UpdateAvailable', 'The normal status returns after a manual-confirmation read succeeds');
  TDAIRuntime.FailStop := True;
  GHost.DAIAction.Execute;
  CheckHealthGlyph('Error', 'Manual registration never hides a runtime error');
  TDAIRuntime.FailStop := False;
  GHost.DAIAction.Execute;
  TDAIIDEToolbar.SetUpdateAvailable(False);
  TDAISettings.Instance.ManualClientRegistration := False;
  TDAIIDEToolbar.Refresh;
  CheckHealthGlyph('Inactive', 'Clearing manual confirmation retains Pause while the server is stopped');
  Check(Pos('No managed registration fixture', GHost.DAIAction.Hint) > 0, 'Clearing manual confirmation restores the missing-registration detail');
  Check(Pos('vom Benutzer bestätigt', GHost.DAIAction.Hint) = 0, 'Clearing manual confirmation removes its tooltip explanation');
end;

procedure TestInactiveStatusPriorityMatrix;
const
  CRegistrationDetail = 'Isolated registration diagnostics remain available.';
  CRuntimeError = 'Isolated port conflict remains available.';
var
  LActive, LUpdate, LError, LAccess: Integer;
  LHealth: TDAIRegistrationHealth;
  LExpectedGlyph, LCase: string;
begin
  NewHost;
  TDAIIDEToolbar.Install;
  for LActive := 0 to 1 do
    for LHealth := Low(TDAIRegistrationHealth) to High(TDAIRegistrationHealth) do
      for LUpdate := 0 to 1 do
        for LError := 0 to 1 do
          for LAccess := 0 to 3 do
          begin
            LCase := Format('active=%d health=%d update=%d error=%d access=%d', [LActive, Ord(LHealth), LUpdate, LError, LAccess]);
            TDAIRuntime.Active := LActive = 1;
            TDAIRuntime.Port := 7331;
            TDAIRuntime.HasMCPAccess := LAccess <> 0;
            case LAccess of
              1: TDAIRuntime.MCPAccessAgeMs := 0;
              2: TDAIRuntime.MCPAccessAgeMs := 15001;
              3: TDAIRuntime.MCPAccessAgeMs := 900001;
            end;
            if LError = 1 then
              TDAIRuntime.ErrorText := CRuntimeError
            else
              TDAIRuntime.ErrorText := '';
            TDAIClientRegistration.HealthState := LHealth;
            TDAIClientRegistration.HealthDetails := CRegistrationDetail;
            TDAIIDEToolbar.SetUpdateAvailable(LUpdate = 1, '9.9.9');
            TDAIIDEToolbar.CheckRegistrations;
            LExpectedGlyph := 'Inactive';
            if LActive = 1 then
            begin
              if LError = 1 then
                LExpectedGlyph := 'Error'
              else if LAccess = 1 then
                LExpectedGlyph := 'RecentAccess'
              else if LAccess = 2 then
                LExpectedGlyph := 'EarlierAccess'
              else if LHealth = rhNotRegistered then
                LExpectedGlyph := 'NotRegistered'
              else if LHealth in [rhUpdateRecommended, rhCheckRecommended] then
                LExpectedGlyph := 'RegistrationUpdate'
              else if LUpdate = 1 then
                LExpectedGlyph := 'UpdateAvailable'
              else
                LExpectedGlyph := 'Active';
            end;
            CheckHealthGlyph(LExpectedGlyph, 'Runtime state priority: ' + LCase);
            if LActive = 0 then
            begin
              Check(GHost.DAIAction.Caption = 'DAI inaktiv', 'Inactive caption has priority: ' + LCase);
              Check(GHost.DAIButton.DropdownMenu.Items[0].Caption = 'Server &starten', 'Inactive server remains startable: ' + LCase);
            end;
            Check(Pos(CRegistrationDetail, GHost.DAIAction.Hint) > 0, 'Registration diagnostics remain in the hint: ' + LCase);
            if LError = 1 then
              Check(Pos(CRuntimeError, GHost.DAIAction.Hint) > 0, 'Runtime diagnostics remain in the hint: ' + LCase);
            if LUpdate = 1 then
              Check(Pos('9.9.9', GHost.DAIAction.Hint) > 0, 'Software-update details remain in the hint: ' + LCase);
          end;
end;

procedure TestToolbarRegistrationHealth;
begin
  TestRegistrationHealthCaching;
  TestRegistrationHealthPriority;
  TestRegistrationHealthReadFailure;
  TestManualRegistrationConfirmation;
  TestInactiveStatusPriorityMatrix;
end;
