program Test.CodeInsightPackage;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  DAI.CodeInsight.Fixture;

type
  TPrepareEditor = procedure(const AEditor: IOTASourceEditor); stdcall;
  TInvokeRequest = function(const AExpectTimeout: LongBool): LongBool; stdcall;
  TRequestsRejected = function: LongBool; stdcall;

var
  CheckCount: Integer;

procedure Check(const ACondition: Boolean; const AMessage: string);
begin
  Inc(CheckCount);
  if not ACondition then
    raise Exception.Create('FAIL: ' + AMessage);
end;

procedure RunTests;
var
  LDefinition: TInvokeRequest;
  LEditor: IOTASourceEditor;
  LEditorObject: TTestSourceEditor;
  LFinalized: Boolean;
  LHint: TInvokeRequest;
  LHoldProvider: IOTACodeInsightManager;
  LModule: HMODULE;
  LPrepare: TPrepareEditor;
  LProvider: TTestCodeInsightProviderEx;
  LRejected: TRequestsRejected;
  LServices: TTestCodeInsightServices;
  LStoredDefinitions: Integer;
  LStoredHints: Integer;
begin
  Check(ParamCount = 1, 'isolated probe BPL path supplied');
  Check(not Assigned(BorlandIDEServices), 'standalone probe starts without a live IDE');
  LServices := TTestCodeInsightServices.Create;
  BorlandIDEServices := LServices;
  LProvider := TTestCodeInsightProviderEx.Create('PackageProbe');
  LHoldProvider := LProvider;
  LServices.Provider := LHoldProvider;
  LEditorObject := TTestSourceEditor.Create;
  LEditor := LEditorObject;
  LEditorObject.View := TTestEditView.Create;
  LModule := 0;
  LFinalized := False;
  try
    LModule := LoadPackage(ExpandFileName(ParamStr(1)));
    Check(LModule <> 0, 'isolated production-unit package loaded');
    {$IFDEF WIN64}
    LPrepare := TPrepareEditor(GetProcAddress(LModule,
      '_ZN3Dai11Codeinsight12Packageprobe13PrepareEditorEN6System15DelphiInterfaceIN8Toolsapi16IOTASourceEditorEEE'));
    LDefinition := TInvokeRequest(GetProcAddress(LModule, '_ZN3Dai11Codeinsight12Packageprobe16InvokeDefinitionEi'));
    LHint := TInvokeRequest(GetProcAddress(LModule, '_ZN3Dai11Codeinsight12Packageprobe11InvokeHoverEi'));
    LRejected := TRequestsRejected(GetProcAddress(LModule, '_ZN3Dai11Codeinsight12Packageprobe19NewRequestsRejectedEv'));
    {$ELSE}
    LPrepare := TPrepareEditor(GetProcAddress(LModule,
      '@Dai@Codeinsight@Packageprobe@PrepareEditor$qqsx52System@%DelphiInterface$25Toolsapi@IOTASourceEditor%'));
    LDefinition := TInvokeRequest(GetProcAddress(LModule, '@Dai@Codeinsight@Packageprobe@InvokeDefinition$qqsxi'));
    LHint := TInvokeRequest(GetProcAddress(LModule, '@Dai@Codeinsight@Packageprobe@InvokeHover$qqsxi'));
    LRejected := TRequestsRejected(GetProcAddress(LModule, '@Dai@Codeinsight@Packageprobe@NewRequestsRejected$qqsv'));
    {$ENDIF}
    Check(Assigned(LPrepare), 'typed editor bridge export available');
    Check(Assigned(LDefinition), 'typed definition bridge export available');
    Check(Assigned(LHint), 'typed hover bridge export available');
    Check(Assigned(LRejected), 'typed closed-admission bridge export available');
    LPrepare(LEditor);
    Check(LDefinition(False), 'normal production callback succeeds in a real BPL');
    Check(LHint(False), 'normal production hover succeeds in a real BPL');
    Check(LProvider.StoredDefinitionCount = 0, 'normal definition does not retain a method pointer');
    Check(LProvider.StoredHintCount = 0, 'normal hover does not retain a method pointer');

    LProvider.Mode := pmTimeout;
    Check(LDefinition(True), 'definition timeout leaves the provider callback pending');
    Check(LHint(True), 'hover timeout leaves the provider callback pending');
    Check(LProvider.StoredDefinitionCount = 1, 'one real BPL definition receiver retained');
    Check(LProvider.StoredHintCount = 1, 'one real BPL hover receiver retained');
    Check(LProvider.CancelCount = 2, 'provider cancellation does not revoke saved pointers');
    Check(LServices.ContextSetCount = LServices.ContextResetCount, 'all package query contexts cleared');
    LPrepare(nil);
    LStoredDefinitions := LProvider.DefinitionCount;
    LStoredHints := LProvider.HintCount;

    // UnloadPackage invokes Delphi unit finalization even when Windows pins the DLL.
    // This is the path an EXE-only shutdown test cannot exercise.
    UnloadPackage(LModule);
    LFinalized := True;
    Check(GetModuleHandle(PChar(ExtractFileName(ParamStr(1)))) = LModule, 'callback-bearing BPL remains mapped after UnloadPackage');
    Check(LRejected(), 'finalized unit rejects requests without touching freed service globals');
    LProvider.DeliverStoredDefinitions;
    Check(LProvider.StoredDefinitionCount = 0, 'late definition executes after real unit finalization');

    // Pinning is permanent. Reinitializing the same image must not create another
    // orphan pool, nor depend on the finalized broker for the remaining old hint.
    InitializePackage(LModule);
    LFinalized := False;
    Check(LRejected(), 'reinitializing a pinned image does not reopen callback admission');
    LProvider.DeliverStoredHints;
    Check(LProvider.StoredHintCount = 0, 'late hint completes across finalize/initialize');
    Check(LProvider.DefinitionCount = LStoredDefinitions, 'closed package never invokes another definition');
    Check(LProvider.HintCount = LStoredHints, 'closed package never invokes another hover');
    FinalizePackage(LModule);
    LFinalized := True;
    Check(LRejected(), 'second finalization is safe and remains closed');
  finally
    if (LModule <> 0) and not LFinalized then
      UnloadPackage(LModule);
    LProvider.DeliverStoredDefinitions;
    LProvider.DeliverStoredHints;
    LEditor := nil;
    LServices.Provider := nil;
    BorlandIDEServices := nil;
    LHoldProvider := nil;
  end;
end;

begin
  try
    RunTests;
    Writeln('PASS: ', CheckCount, ' Code Insight real BPL shutdown/finalization checks');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
