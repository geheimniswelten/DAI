unit h5u.DAI.Options.Navigation;

interface

uses
  System.JSON;

type
  TDAIOptionsNavigationRequest = record
    Scope, Project, Area, Page, Option, Control, Query, Configuration, Platform: string;
  end;

  TDAIOptionsNavigationService = class sealed
  public
    class function Open(const ARequest: TDAIOptionsNavigationRequest): TJSONObject; static;
    class function Status(const ARequestId: string): TJSONObject; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Grids,
  Vcl.ValEdit,
  Vcl.ExtCtrls,
  ToolsAPI,
  h5u.DAI.OTA.Helpers,
  h5u.DAI.Options.Search,
  h5u.DAI.Windows.Inspection;

const
  CMaximumNames = 10000;
  CMaximumControls = 2000;
  CNavigationMilliseconds = 5000;

type
  TNavigationJob = class
    Request: TDAIOptionsNavigationRequest;
    Id, State, Reason, ProjectFile, Configuration, Platform, ExpectedConfiguration, ExpectedPlatform, RollbackError: string;
    DialogOpened, PageSelected, OptionFocused, NativeFocus, PageAttempted, SDKOptionKnown: Boolean;
    FocusVerified: Integer;
    Started: UInt64;
    function ToJson: TJSONObject;
  end;

  TFocusCandidate = record
    Control: TWinControl;
    Row, Col: Integer;
  end;

  TNavigationGrid = class(TCustomGrid)
  public
    property Row;
    property Col;
    property FixedRows;
  end;

  TNavigationPump = class(TComponent)
  private
    FJobs: TObjectList<TNavigationJob>;
    FActive: TNavigationJob;
    FTimer: TTimer;
    FDialog: TCustomForm;
    FProbe: TComponent;
    FRunning, FDestroying, FStopped: Boolean;
    FPreviousForms: TList<TCustomForm>;
    procedure RunQueued;
    procedure Tick(Sender: TObject);
    procedure Probe(const AComponent: TComponent);
    function SelectPage(const APage: string): Boolean;
    function FocusOption: Boolean;
    procedure ObserveDialog;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create; reintroduce;
    destructor Destroy; override;
    function Enqueue(const ARequest: TDAIOptionsNavigationRequest): TJSONObject;
    function FindStatus(const AId: string): TJSONObject;
    procedure Stop;
  end;

var
  GPump: TNavigationPump;
  GServiceStopped: Boolean;

function NavigationGetModuleHandleExW(const AFlags: DWORD; const AAddress: PWideChar; out AModule: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExW';

procedure PinNavigationModule;
var
  LModule: HMODULE;
begin
  // The IDE may pump package-unload actions inside a modal SDK call. A module
  // containing this queued callback must remain mapped until the IDE exits.
  if not NavigationGetModuleHandleExW($00000004 or $00000001,
    PChar(Pointer(@PinNavigationModule)), LModule) then RaiseLastOSError;
end;

procedure NullableString(const AJson: TJSONObject; const AName, AValue: string);
begin
  if AValue = '' then AJson.AddPair(AName, TJSONNull.Create) else AJson.AddPair(AName, AValue);
end;

function TNavigationJob.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('request_id', Id);
  Result.AddPair('status', State);
  Result.AddPair('scope', Request.Scope);
  Result.AddPair('dialog_opened', TJSONBool.Create(DialogOpened));
  Result.AddPair('page_selected', TJSONBool.Create(PageSelected));
  Result.AddPair('option_focused', TJSONBool.Create(OptionFocused));
  Result.AddPair('focus_owned_by_ide', TJSONBool.Create(NativeFocus));
  if FocusVerified < 0 then Result.AddPair('focus_verified', TJSONNull.Create)
  else Result.AddPair('focus_verified', TJSONBool.Create(FocusVerified = 1));
  NullableString(Result, 'project', ProjectFile);
  NullableString(Result, 'configuration', Configuration);
  NullableString(Result, 'platform', Platform);
  NullableString(Result, 'message', Reason);
  NullableString(Result, 'rollback_error', RollbackError);
end;

function CaptionKey(const AText: string): string;
begin
  Result := LowerCase(Trim(StringReplace(AText, '&', '', [rfReplaceAll])));
  Result := StringReplace(Result, ' > ', '/', [rfReplaceAll]);
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
  if Result.EndsWith(':') then Delete(Result, Length(Result), 1);
end;

function MatchesLabel(const AText: string; const ALabels: TArray<string>): Boolean;
var
  LLabel: string;
begin
  Result := False;
  for LLabel in ALabels do
    if (LLabel <> '') and (CaptionKey(AText) = CaptionKey(LLabel)) then Exit(True);
end;

function SelectedProject(const ASelector: string): IOTAProject;
var
  LActive: IOTAProject;
begin
  LActive := TDAIOTA.ActiveProject;
  if ASelector = '' then Result := LActive else Result := TDAIOTA.ProjectByNameOrPath(ASelector);
  if Result = nil then raise EInvalidOperation.Create('Das gewünschte Projekt ist nicht geöffnet.');
  if LActive = nil then raise EInvalidOperation.Create('Es ist kein Projekt aktiv.');
  if not TDAIOTA.SameFile(Result.FileName, LActive.FileName) then
    raise EInvalidOperation.Create('Optionsnavigation erfordert das bereits aktive Projekt.');
end;

function SDKOptionExists(const AOptions: IOTAOptions; const AName: string): Boolean;
var
  LNames: TOTAOptionNameArray;
  LName: TOTAOptionName;
begin
  Result := False;
  if AName = '' then Exit;
  if AOptions = nil then raise EInvalidOperation.Create('Der IDE-Optionsdienst ist nicht verfügbar.');
  LNames := AOptions.GetOptionNames;
  if Length(LNames) > CMaximumNames then raise EInvalidOperation.Create('Die SDK-Optionsliste ist zu groß.');
  for LName in LNames do if SameText(LName.Name, AName) then Exit(True);
end;

function ConfigurationByName(const AProject: IOTAProject; const AName: string): IOTABuildConfiguration;
var
  LConfigurations: IOTAProjectOptionsConfigurations;
  LConfiguration: IOTABuildConfiguration;
  I, LCount: Integer;
begin
  Result := nil;
  if SameText(AName, 'Base') or SameText(AName, 'active') or (AName = '') then
    raise EArgumentException.Create('Es ist ein konkreter Konfigurationsname erforderlich.');
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, LConfigurations) then
    raise EInvalidOperation.Create('Der Konfigurationsdienst ist nicht verfügbar.');
  LCount := LConfigurations.ConfigurationCount;
  if (LCount < 0) or (LCount > 1000) then raise EInvalidOperation.Create('Ungültige SDK-Konfigurationsliste.');
  for I := 0 to LCount - 1 do
  begin
    LConfiguration := LConfigurations.Configurations[I];
    if LConfiguration = nil then Continue;
    if (LConfiguration.Platform = '') and SameText(LConfiguration.Name, AName) then
    begin
      if Result <> nil then raise EArgumentException.Create('Der Konfigurationsname ist mehrdeutig.');
      Result := LConfiguration;
    end;
  end;
  if Result = nil then raise EArgumentException.CreateFmt('Unbekannte Konfiguration: %s', [AName]);
end;

procedure ValidateSelection(const AProject: IOTAProject; const AConfiguration, APlatform: string);
var
  LConfiguration, LPlatformConfiguration: IOTABuildConfiguration;
  LName: string;
  LFound: Boolean;
begin
  LConfiguration := ConfigurationByName(AProject, AConfiguration);
  LFound := False;
  for LName in AProject.SupportedPlatforms do if SameText(LName, APlatform) then LFound := True;
  if not LFound then raise EArgumentException.CreateFmt('Nicht unterstützte Plattform: %s', [APlatform]);
  LPlatformConfiguration := LConfiguration.PlatformConfiguration[APlatform];
  if LPlatformConfiguration = nil then
    raise EArgumentException.Create('Die Konfiguration enthält keinen Plattformscope.');
  if not SameText(LPlatformConfiguration.Platform, APlatform) then
    raise EArgumentException.Create('Die Konfiguration enthält keinen passenden Plattformscope.');
end;

procedure ReadSelection(const AProject: IOTAProject; const AJob: TNavigationJob);
begin
  AJob.Configuration := AProject.CurrentConfiguration;
  AJob.Platform := AProject.CurrentPlatform;
end;

procedure ApplySelection(const AProject: IOTAProject; const AJob: TNavigationJob);
var
  LOldConfiguration, LOldPlatform, LConfiguration, LPlatform: string;
  procedure Rollback;
  begin
    try AProject.CurrentConfiguration := LOldConfiguration;
    except on E: Exception do AJob.RollbackError := 'Konfiguration: ' + E.Message; end;
    try AProject.CurrentPlatform := LOldPlatform;
    except on E: Exception do AJob.RollbackError := AJob.RollbackError + ' Plattform: ' + E.Message; end;
    try
      ReadSelection(AProject, AJob);
      if not SameText(AJob.Configuration, LOldConfiguration) or not SameText(AJob.Platform, LOldPlatform) then
        AJob.RollbackError := AJob.RollbackError + ' Die ursprüngliche SDK-Auswahl wurde nicht wiederhergestellt.';
    except on E: Exception do AJob.RollbackError := AJob.RollbackError + ' Auswahl: ' + E.Message; end;
  end;
begin
  ReadSelection(AProject, AJob);
  if (AJob.Request.Configuration = '') and (AJob.Request.Platform = '') then Exit;
  LOldConfiguration := AJob.Configuration;
  LOldPlatform := AJob.Platform;
  LConfiguration := AJob.Request.Configuration;
  if LConfiguration = '' then LConfiguration := LOldConfiguration;
  LPlatform := AJob.Request.Platform;
  if LPlatform = '' then LPlatform := LOldPlatform;
  ValidateSelection(AProject, LConfiguration, LPlatform);
  try
    if not SameText(AProject.CurrentConfiguration, LConfiguration) then AProject.CurrentConfiguration := LConfiguration;
    if not SameText(AProject.CurrentPlatform, LPlatform) then AProject.CurrentPlatform := LPlatform;
    ReadSelection(AProject, AJob);
    if not SameText(AJob.Configuration, LConfiguration) or not SameText(AJob.Platform, LPlatform) then
      raise EInvalidOperation.Create('Das SDK hat die angeforderte Auswahl nicht übernommen.');
  except
    Rollback;
    raise;
  end;
end;

function OptionsCategory(const AScope, ACaption: string): Boolean;
begin
  if AScope = 'project' then
    Result := SameText(ACaption, 'Project Options') or SameText(ACaption, 'Projektoptionen')
  else
    Result := SameText(ACaption, 'Preferences') or SameText(ACaption, 'Einstellungen') or SameText(ACaption, 'Voreinstellungen');
end;

function NativeOptionsItem(const ARequest: TDAIOptionsNavigationRequest; const ASDKOptionKnown: Boolean): INTAIDEInsightItem;
var
  LInsight: INTAIDEInsightService;
  LCatalog: IOTAIDEInsightService;
  LCategory: IOTAIDEInsightCategory;
  LItem: INTAIDEInsightItem;
  LLabels: TArray<string>;
  LFilter: string;
  I, J, LCount, LItems, LMatches, LTotalItems: Integer;
begin
  Result := nil;
  if ARequest.Option = '' then Exit;
  if not Supports(BorlandIDEServices, INTAIDEInsightService, LInsight) or
     not Supports(BorlandIDEServices, IOTAIDEInsightService, LCatalog) then Exit;
  if ASDKOptionKnown then LLabels := TDAIOptionsSearchService.OptionLabels(ARequest.Option)
  else LLabels := TArray<string>.Create(ARequest.Option);
  LFilter := ARequest.Query;
  if (LFilter = '') and (Length(LLabels) > 0) then LFilter := LLabels[0];
  LInsight.Filter(LFilter);
  LCount := LCatalog.CategoryCount;
  if (LCount < 0) or (LCount > 200) then Exit;
  LMatches := 0;
  LTotalItems := 0;
  for I := 0 to LCount - 1 do
  begin
    LCategory := LCatalog.Categories[I];
    if LCategory = nil then Continue;
    if LCategory.Disabled or not OptionsCategory(ARequest.Scope, LCategory.Caption) then Continue;
    LItems := LCategory.ItemCount;
    if (LItems < 0) or (LItems > CMaximumNames) then Exit(nil);
    Inc(LTotalItems, LItems);
    if LTotalItems > CMaximumNames then Exit(nil);
    for J := 0 to LItems - 1 do
    begin
      LItem := LCategory.Items[J];
      if LItem = nil then Continue;
      if LItem.Visible and
         (MatchesLabel(LItem.Title, LLabels) or (ASDKOptionKnown and MatchesLabel(LItem.Description, LLabels))) then
      begin
        Inc(LMatches);
        Result := LItem;
      end;
    end;
  end;
  if LMatches <> 1 then Result := nil;
end;

function IsOptionsForm(const AForm: TCustomForm; const AScope: string): Boolean;
var
  LClass: TClass;
  LName: string;
begin
  Result := False;
  if AForm = nil then Exit;
  if not AForm.Visible or not (fsModal in AForm.FormState) then Exit;
  if TDAIWindowService.IsProtectedPermissionWindow(AForm.Handle) then Exit;
  LClass := AForm.ClassType;
  while LClass <> nil do
  begin
    LName := LClass.ClassName;
    if SameText(LName, 'TProjectOptionsDialog') or SameText(LName, 'TDelphiProjectOptionsDialog') then Exit(AScope = 'project');
    if SameText(LName, 'TBaseEnvironmentDialog') or SameText(LName, 'TDefaultEnvironmentDialog') or
       SameText(LName, 'TSingleBaseEnvironmentDialog') then Exit(AScope = 'ide');
    LClass := LClass.ClassParent;
  end;
end;

procedure CollectControls(const AParent: TWinControl; const AControls: TList<TControl>);
var
  I: Integer;
  LControl: TControl;
begin
  for I := 0 to AParent.ControlCount - 1 do
  begin
    if AControls.Count >= CMaximumControls then raise EInvalidOperation.Create('Der Optionsdialog enthält zu viele Controls.');
    LControl := AParent.Controls[I];
    AControls.Add(LControl);
    if LControl is TWinControl then CollectControls(TWinControl(LControl), AControls);
  end;
end;

function NodePath(const ANode: TTreeNode): string;
var
  LNode: TTreeNode;
begin
  Result := '';
  LNode := ANode;
  while LNode <> nil do
  begin
    if Result = '' then Result := LNode.Text else Result := LNode.Text + '/' + Result;
    LNode := LNode.Parent;
  end;
end;

constructor TNavigationPump.Create;
begin
  inherited Create(nil);
  FJobs := TObjectList<TNavigationJob>.Create(True);
  FPreviousForms := TList<TCustomForm>.Create;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := Tick;
end;

destructor TNavigationPump.Destroy;
begin
  FDestroying := True;
  Stop;
  FPreviousForms.Free;
  FJobs.Free;
  inherited;
end;

procedure TNavigationPump.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FDialog then FDialog := nil;
    if AComponent = FProbe then FProbe := nil;
  end;
end;

procedure TNavigationPump.Probe(const AComponent: TComponent);
begin
  if FProbe <> nil then FProbe.RemoveFreeNotification(Self);
  FProbe := AComponent;
  if FProbe <> nil then FProbe.FreeNotification(Self);
end;

function TNavigationPump.Enqueue(const ARequest: TDAIOptionsNavigationRequest): TJSONObject;
var
  LJob: TNavigationJob;
  LProject: IOTAProject;
  LServices: IOTAServices;
  LOptions: IOTAOptions;
  LId: TGUID;
  LConfiguration, LPlatform: string;
begin
  if FDestroying or FStopped then raise EInvalidOperation.Create('Die Optionsnavigation wurde beendet.');
  if FRunning or (FActive <> nil) then raise EInvalidOperation.Create('Eine Optionsnavigation ist bereits aktiv.');
  for LConfiguration in TArray<string>.Create(ARequest.Scope, ARequest.Project, ARequest.Area, ARequest.Page, ARequest.Option,
    ARequest.Control, ARequest.Configuration, ARequest.Platform) do
    if (Pos(#0, LConfiguration) <> 0) or (Length(LConfiguration) > 1024) then
      raise EArgumentException.Create('Optionsnavigation erwartet Zeichenfolgen ohne NUL mit höchstens 1024 Zeichen.');
  if (Pos(#0, ARequest.Query) <> 0) or (Length(ARequest.Query) > 1024) then
    raise EArgumentException.Create('query darf kein NUL enthalten und höchstens 1024 Zeichen lang sein.');
  for LConfiguration in TArray<string>.Create(ARequest.Scope, ARequest.Area, ARequest.Option, ARequest.Control,
    ARequest.Configuration, ARequest.Platform) do
    if Length(LConfiguration) > 256 then raise EArgumentException.Create('SDK-Namen dürfen höchstens 256 Zeichen lang sein.');
  LJob := TNavigationJob.Create;
  try
    LJob.Request := ARequest;
    LJob.Request.Scope := LowerCase(Trim(ARequest.Scope));
    if LJob.Request.Scope = '' then LJob.Request.Scope := 'project';
    if not MatchText(LJob.Request.Scope, ['project', 'ide', 'insight']) then
      raise EArgumentException.Create('scope muss project, ide oder insight sein.');
    if LJob.Request.Scope = 'project' then
    begin
      LProject := SelectedProject(ARequest.Project);
      LJob.ProjectFile := LProject.FileName;
      ReadSelection(LProject, LJob);
      LJob.ExpectedConfiguration := LJob.Configuration;
      LJob.ExpectedPlatform := LJob.Platform;
      LOptions := LProject.ProjectOptions;
      if (ARequest.Configuration <> '') or (ARequest.Platform <> '') then
      begin
        LConfiguration := ARequest.Configuration;
        if LConfiguration = '' then LConfiguration := LJob.Configuration;
        LPlatform := ARequest.Platform;
        if LPlatform = '' then LPlatform := LJob.Platform;
        ValidateSelection(LProject, LConfiguration, LPlatform);
      end;
    end
    else
    begin
      if (ARequest.Project <> '') or (ARequest.Configuration <> '') or (ARequest.Platform <> '') then
        raise EArgumentException.Create('Projekt, Konfiguration und Plattform sind nur für scope project zulässig.');
      if LJob.Request.Scope = 'ide' then
      begin
        if not Supports(BorlandIDEServices, IOTAServices, LServices) then
          raise EInvalidOperation.Create('Der IDE-Optionsdienst ist nicht verfügbar.');
        LOptions := LServices.GetEnvironmentOptions;
      end
      else if (ARequest.Query = '') or (ARequest.Option <> '') or (ARequest.Control <> '') or
              (ARequest.Page <> '') or (ARequest.Area <> '') then
        raise EArgumentException.Create('scope insight erwartet nur query.');
    end;
    LJob.SDKOptionKnown := SDKOptionExists(LOptions, ARequest.Option);
    CreateGUID(LId);
    LJob.Id := GUIDToString(LId);
    LJob.State := 'queued';
    LJob.FocusVerified := -1;
    while FJobs.Count >= 16 do FJobs.Delete(0);
    PinNavigationModule;
    FJobs.Add(LJob);
    FActive := LJob;
    LJob := nil;
    TThread.ForceQueue(nil, RunQueued);
    Result := FActive.ToJson;
  finally
    LJob.Free;
  end;
end;

function TNavigationPump.FindStatus(const AId: string): TJSONObject;
var
  LJob: TNavigationJob;
begin
  for LJob in FJobs do if LJob.Id = AId then Exit(LJob.ToJson);
  raise EArgumentException.Create('Die Optionsnavigation ist unbekannt oder nicht mehr gespeichert.');
end;

procedure TNavigationPump.Stop;
begin
  FStopped := True;
  TThread.RemoveQueuedEvents(nil, RunQueued);
  FTimer.Enabled := False;
  Probe(nil);
  if FDialog <> nil then FDialog.RemoveFreeNotification(Self);
  FDialog := nil;
  if FActive <> nil then
  begin
    FActive.State := 'cancelled';
    FActive.Reason := 'Die Optionsnavigation wurde beim Serverstopp abgebrochen.';
    if not FRunning then FActive := nil;
  end;
end;

procedure TNavigationPump.RunQueued;
var
  LJob: TNavigationJob;
  LProject: IOTAProject;
  LServices: IOTAServices;
  LEnvironment: IOTAEnvironmentOptions;
  LInsight: INTAIDEInsightService;
  LItem: INTAIDEInsightItem;
  LControl: TWinControl;
  I: Integer;
begin
  LJob := FActive;
  if LJob = nil then Exit;
  FRunning := True;
  try
    try
      if LJob.Request.Scope = 'project' then
      begin
        LProject := SelectedProject(LJob.ProjectFile);
        if not SameText(LProject.CurrentConfiguration, LJob.ExpectedConfiguration) or
           not SameText(LProject.CurrentPlatform, LJob.ExpectedPlatform) then
          raise EInvalidOperation.Create('Die aktive Konfiguration oder Plattform hat sich seit der Anforderung geändert.');
        if LJob.SDKOptionKnown then
          if not SDKOptionExists(LProject.ProjectOptions, LJob.Request.Option) then
            raise EInvalidOperation.Create('Die angeforderte SDK-Option ist nicht mehr verfügbar.');
        ApplySelection(LProject, LJob);
      end;
      if LJob.State = 'cancelled' then Exit;
      if LJob.Request.Scope = 'insight' then
      begin
        if not Supports(BorlandIDEServices, INTAIDEInsightService, LInsight) then
          raise EInvalidOperation.Create('IDE Insight ist nicht verfügbar.');
        LInsight.Filter(LJob.Request.Query);
        if LJob.State = 'cancelled' then Exit;
        LControl := LInsight.EditSearchControl;
        if LControl = nil then raise EInvalidOperation.Create('Das IDE-Insight-Suchfeld ist nicht verfügbar.');
        if not LControl.CanFocus then
          raise EInvalidOperation.Create('Das IDE-Insight-Suchfeld kann nicht fokussiert werden.');
        Probe(LControl);
        LControl.SetFocus;
        if LJob.State = 'cancelled' then Exit;
        if FProbe = nil then raise EInvalidOperation.Create('Das IDE-Insight-Suchfeld wurde geschlossen.');
        LJob.OptionFocused := LControl.Focused;
        LJob.FocusVerified := Ord(LJob.OptionFocused);
        if LJob.OptionFocused then LJob.State := 'focused' else LJob.State := 'unsupported';
        Exit;
      end;
      LJob.Started := GetTickCount64;
      FPreviousForms.Clear;
      for I := 0 to Screen.CustomFormCount - 1 do
        if Screen.CustomForms[I].Visible then FPreviousForms.Add(Screen.CustomForms[I]);
      FTimer.Enabled := True;
      LItem := NativeOptionsItem(LJob.Request, LJob.SDKOptionKnown);
      if LJob.State = 'cancelled' then Exit;
      if LProject <> nil then
      begin
        LProject := SelectedProject(LJob.ProjectFile);
        if not SameText(LProject.CurrentConfiguration, LJob.Configuration) or not SameText(LProject.CurrentPlatform, LJob.Platform) then
          raise EInvalidOperation.Create('Das Projekt oder seine Auswahl hat sich während der Insight-Abfrage geändert.');
      end;
      if LItem <> nil then
      begin
        LJob.NativeFocus := True;
        LItem.Execute;
      end
      else if LProject <> nil then LProject.ProjectOptions.EditOptions
      else
      begin
        if not Supports(BorlandIDEServices, IOTAServices, LServices) then
          raise EInvalidOperation.Create('Der IDE-Optionsdienst ist nicht verfügbar.');
        LEnvironment := LServices.GetEnvironmentOptions;
        if LEnvironment = nil then raise EInvalidOperation.Create('Der IDE-Optionsdienst ist nicht verfügbar.');
        if LJob.SDKOptionKnown then
          if not SDKOptionExists(LEnvironment, LJob.Request.Option) then
            raise EInvalidOperation.Create('Die angeforderte SDK-Option ist nicht mehr verfügbar.');
        if LJob.Request.Area = '' then IOTAOptions(LEnvironment).EditOptions
        else LEnvironment.EditOptions(LJob.Request.Area, LJob.Request.Page);
      end;
      if LJob.State <> 'cancelled' then
      begin
        if LJob.DialogOpened then
        begin
          if ((LJob.Request.Option <> '') or (LJob.Request.Control <> '') or (LJob.Request.Query <> '')) and
             not LJob.OptionFocused and not LJob.NativeFocus then
          begin
            if LJob.State <> 'error' then LJob.State := 'unsupported';
            LJob.FocusVerified := 0;
            if LJob.Reason = '' then
              LJob.Reason := 'Die gewünschte Option besitzt kein eindeutig fokussierbares Standard-VCL-Control.';
          end
          else if (LJob.State <> 'error') and (LJob.State <> 'unsupported') then LJob.State := 'closed';
          if LJob.NativeFocus and not LJob.OptionFocused and (LJob.Reason = '') then
            LJob.Reason := 'Die IDE steuert den Optionsfokus; das private Control bietet keine verifizierbare Standard-VCL-Zeile.';
        end
        else
        begin
          LJob.State := 'unsupported';
          LJob.Reason := 'Der SDK-Aufruf lieferte keinen erkennbaren modalen Optionsdialog.';
        end;
      end;
    except
      on E: Exception do
        if LJob.State <> 'cancelled' then
        begin
          LJob.State := 'error';
          LJob.Reason := E.Message;
        end;
    end;
  finally
    FTimer.Enabled := False;
    Probe(nil);
    if FDialog <> nil then FDialog.RemoveFreeNotification(Self);
    FDialog := nil;
    FActive := nil;
    FRunning := False;
  end;
end;

procedure TNavigationPump.ObserveDialog;
var
  I: Integer;
  LForm, LFound: TCustomForm;
begin
  if FDialog <> nil then Exit;
  LFound := nil;
  for I := 0 to Screen.CustomFormCount - 1 do
  begin
    LForm := Screen.CustomForms[I];
    if not IsOptionsForm(LForm, FActive.Request.Scope) then Continue;
    if FPreviousForms.Contains(LForm) then Continue;
    if LFound <> nil then Exit;
    LFound := LForm;
  end;
  FDialog := LFound;
  if FDialog <> nil then
  begin
    FDialog.FreeNotification(Self);
    FActive.DialogOpened := True;
    FActive.State := 'opened';
  end;
end;

function TNavigationPump.SelectPage(const APage: string): Boolean;
var
  LControls: TList<TControl>;
  LControl: TControl;
  LTree, LFoundTree: TTreeView;
  LNode, LFoundNode: TTreeNode;
  LPages, LFoundPages: TPageControl;
  LTab, LFoundTab: TTabSheet;
  LCount, I, LVisited: Integer;
begin
  Result := False;
  if (FDialog = nil) or FStopped then Exit;
  LCount := 0;
  LVisited := 0;
  LFoundTree := nil;
  LFoundNode := nil;
  LFoundPages := nil;
  LFoundTab := nil;
  LControls := TList<TControl>.Create;
  try
    CollectControls(FDialog, LControls);
    for LControl in LControls do
    begin
      if not LControl.Visible then Continue;
      if LControl is TTreeView then
      begin
        LTree := TTreeView(LControl);
        LNode := LTree.Items.GetFirstNode;
        while LNode <> nil do
        begin
          Inc(LVisited);
          if LVisited > CMaximumNames then Exit;
          if (CaptionKey(LNode.Text) = CaptionKey(APage)) or (CaptionKey(NodePath(LNode)) = CaptionKey(APage)) then
          begin
            Inc(LCount);
            LFoundTree := LTree;
            LFoundNode := LNode;
          end;
          LNode := LNode.GetNext;
        end;
      end
      else if LControl is TPageControl then
      begin
        LPages := TPageControl(LControl);
        for I := 0 to LPages.PageCount - 1 do
        begin
          LTab := LPages.Pages[I];
          if LTab.TabVisible and (CaptionKey(LTab.Caption) = CaptionKey(APage)) then
          begin
            Inc(LCount);
            LFoundPages := LPages;
            LFoundTab := LTab;
          end;
        end;
      end;
    end;
    if LCount <> 1 then Exit;
    if LFoundTree <> nil then
    begin
      Probe(LFoundTree);
      LFoundTree.Selected := LFoundNode;
      if FProbe <> nil then Result := LFoundTree.Selected = LFoundNode;
    end
    else
    begin
      Probe(LFoundPages);
      LFoundPages.ActivePage := LFoundTab;
      if FProbe <> nil then Result := LFoundPages.ActivePage = LFoundTab;
    end;
  finally
    LControls.Free;
    Probe(nil);
  end;
end;

function EditableControl(const AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomEdit) or (AControl is TCustomComboBox) or (AControl is TStringGrid) or (AControl is TValueListEditor);
end;

function TNavigationPump.FocusOption: Boolean;
var
  LControls: TList<TControl>;
  LCandidates: TList<TFocusCandidate>;
  LControl: TControl;
  LGrid: TStringGrid;
  LValues: TValueListEditor;
  LLabels: TArray<string>;
  LCandidate: TFocusCandidate;
  LNameCol, LValueCol, LCol, LRow: Integer;
  procedure Add(const AControl: TControl; const ARow: Integer = -1; const ACol: Integer = -1);
  var
    LExisting: TFocusCandidate;
  begin
    if not EditableControl(AControl) then Exit;
    if not AControl.Visible then Exit;
    if not TWinControl(AControl).CanFocus then Exit;
    for LExisting in LCandidates do
      if (LExisting.Control = AControl) and (LExisting.Row = ARow) and (LExisting.Col = ACol) then Exit;
    LCandidate.Control := TWinControl(AControl);
    LCandidate.Row := ARow;
    LCandidate.Col := ACol;
    LCandidates.Add(LCandidate);
  end;
begin
  Result := False;
  if (FDialog = nil) or FStopped then Exit;
  if FActive.Request.Option <> '' then LLabels := TDAIOptionsSearchService.OptionLabels(FActive.Request.Option)
  else LLabels := TArray<string>.Create(FActive.Request.Query);
  LControls := TList<TControl>.Create;
  LCandidates := TList<TFocusCandidate>.Create;
  try
    CollectControls(FDialog, LControls);
    for LControl in LControls do
    begin
      if not LControl.Visible then Continue;
      if FActive.Request.Control <> '' then
      begin
        if SameText(LControl.Name, FActive.Request.Control) then Add(LControl);
        Continue;
      end;
      if LControl is TLabel then
      begin
        if MatchesLabel(TLabel(LControl).Caption, LLabels) then Add(TLabel(LControl).FocusControl);
      end
      else if LControl is TValueListEditor then
      begin
        LValues := TValueListEditor(LControl);
        if LValues.RowCount > CMaximumNames then Continue;
        for LRow := TNavigationGrid(LValues).FixedRows to LValues.RowCount - 1 do
          if MatchesLabel(LValues.Cells[0, LRow], LLabels) then Add(LValues, LRow, 1);
      end
      else if LControl is TStringGrid then
      begin
        LGrid := TStringGrid(LControl);
        if (LGrid.RowCount > CMaximumNames) or (LGrid.ColCount > 64) then Continue;
        LNameCol := -1;
        LValueCol := -1;
        if LGrid.FixedRows > 0 then
          for LCol := 0 to LGrid.ColCount - 1 do
          begin
            if MatchText(CaptionKey(LGrid.Cells[LCol, 0]), ['name', 'option', 'property', 'eigenschaft']) then
            begin
              if LNameCol <> -1 then begin LNameCol := -1; Break; end;
              LNameCol := LCol;
            end;
            if MatchText(CaptionKey(LGrid.Cells[LCol, 0]), ['value', 'wert']) then
            begin
              if LValueCol <> -1 then begin LValueCol := -1; Break; end;
              LValueCol := LCol;
            end;
          end;
        if (LNameCol < 0) or (LValueCol < 0) or (LValueCol >= LGrid.ColCount) or (LNameCol = LValueCol) then Continue;
        for LRow := LGrid.FixedRows to LGrid.RowCount - 1 do
          if MatchesLabel(LGrid.Cells[LNameCol, LRow], LLabels) then Add(LGrid, LRow, LValueCol);
      end
      else if MatchesLabel(LControl.Name, LLabels) or MatchesLabel(LControl.Hint, LLabels) then Add(LControl);
    end;
    if LCandidates.Count <> 1 then Exit;
    LCandidate := LCandidates[0];
    Probe(LCandidate.Control);
    if LCandidate.Row >= 0 then
    begin
      TNavigationGrid(LCandidate.Control).Row := LCandidate.Row;
      if FProbe = nil then Exit;
      TNavigationGrid(LCandidate.Control).Col := LCandidate.Col;
      if FProbe = nil then Exit;
    end;
    LCandidate.Control.SetFocus;
    if FProbe = nil then Exit;
    Result := LCandidate.Control.Focused;
    if Result and (LCandidate.Row >= 0) then
      Result := (TNavigationGrid(LCandidate.Control).Row = LCandidate.Row) and (TNavigationGrid(LCandidate.Control).Col = LCandidate.Col);
  finally
    Probe(nil);
    LCandidates.Free;
    LControls.Free;
  end;
end;

procedure TNavigationPump.Tick(Sender: TObject);
var
  LJob: TNavigationJob;
  LPage: string;
begin
  LJob := FActive;
  if LJob = nil then Exit;
  if LJob.State = 'cancelled' then Exit;
  try
    ObserveDialog;
    if FDialog = nil then
    begin
      if GetTickCount64 - LJob.Started >= CNavigationMilliseconds then FTimer.Enabled := False;
      Exit;
    end;
    if not IsOptionsForm(FDialog, LJob.Request.Scope) then
    begin
      FTimer.Enabled := False;
      LJob.State := 'closed';
      Exit;
    end;
    if (LJob.State = 'focused') or (LJob.State = 'unsupported') then Exit;
    if not LJob.PageAttempted then
    begin
      LJob.PageAttempted := True;
      if LJob.Request.Page <> '' then
      begin
        LJob.PageSelected := SelectPage(LJob.Request.Page);
        if LJob.State = 'cancelled' then Exit;
        if not LJob.PageSelected then
        begin
          LJob.State := 'unsupported';
          LJob.Reason := 'Die gewünschte Optionsseite wurde nicht eindeutig gefunden.';
          Exit;
        end;
        Exit;
      end;
      if not LJob.NativeFocus and LJob.Request.Option.StartsWith('DCC_', True) then
        for LPage in TArray<string>.Create('Delphi Compiler/Building', 'Delphi-Compiler/Erzeugen', 'Delphi Compiler', 'Delphi-Compiler') do
        begin
          if LJob.State = 'cancelled' then Exit;
          if SelectPage(LPage) then
          begin
            if LJob.State = 'cancelled' then Exit;
            LJob.PageSelected := True;
            Exit;
          end;
        end;
    end;
    if (LJob.Request.Option = '') and (LJob.Request.Control = '') and (LJob.Request.Query = '') then Exit;
    if FocusOption then
    begin
      if LJob.State = 'cancelled' then Exit;
      LJob.OptionFocused := True;
      LJob.FocusVerified := 1;
      LJob.State := 'focused';
    end
    else if GetTickCount64 - LJob.Started >= CNavigationMilliseconds then
    begin
      if LJob.State = 'cancelled' then Exit;
      if LJob.NativeFocus then
      begin
        LJob.FocusVerified := -1;
        LJob.Reason := 'Die IDE steuert den Optionsfokus; das private Control bietet keine verifizierbare Standard-VCL-Zeile.';
      end
      else
      begin
        LJob.State := 'unsupported';
        LJob.FocusVerified := 0;
        LJob.Reason := 'Die gewünschte Option besitzt kein eindeutig fokussierbares Standard-VCL-Control.';
      end;
      FTimer.Enabled := False;
    end;
  except
    on E: Exception do
    begin
      if LJob.State <> 'cancelled' then
      begin
        LJob.State := 'error';
        LJob.Reason := E.Message;
      end;
      FTimer.Enabled := False;
    end;
  end;
end;

class function TDAIOptionsNavigationService.Open(const ARequest: TDAIOptionsNavigationRequest): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(procedure
    begin
      if GServiceStopped then raise EInvalidOperation.Create('Die Optionsnavigation wurde beendet.');
      if GPump = nil then GPump := TNavigationPump.Create;
      LResult := GPump.Enqueue(ARequest);
    end);
  Result := LResult;
end;

class function TDAIOptionsNavigationService.Status(const ARequestId: string): TJSONObject;
var
  LResult: TJSONObject;
begin
  LResult := nil;
  TDAIOTA.RunOnMainThread(procedure
    begin
      if GPump = nil then raise EArgumentException.Create('Es ist keine Optionsnavigation gespeichert.');
      LResult := GPump.FindStatus(ARequestId);
    end);
  Result := LResult;
end;

class procedure TDAIOptionsNavigationService.Shutdown;
begin
  TDAIOTA.RunOnMainThread(procedure
    begin
      GServiceStopped := True;
      if GPump <> nil then GPump.Stop;
    end);
end;

initialization
  GPump := nil;
  GServiceStopped := False;

finalization
  GServiceStopped := True;
  if GPump <> nil then
  begin
    GPump.Stop;
    // Never destroy data that a reentrant modal SDK stack still references.
    if not GPump.FRunning then FreeAndNil(GPump) else GPump := nil;
  end;

end.
