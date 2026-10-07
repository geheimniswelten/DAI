program TestFormText;
{$APPTYPE CONSOLE}

// Test.Designer.ps1 copies exact production methods from OTA.Helpers into the generated include.
// The local interface subsets provide isolated module, designer, action and buffer doubles.
// Path normalization below is a test environment adapter; RunOnMainThread is included verbatim.
// Actual production units are also compiled by Test.ReadOnlyPolicy.ps1 against original ToolsAPI.

uses System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils, Winapi.Windows,
  h5u.DAI.Text.Encoding;
type
  IOTAEditReader = interface ['{26EB0E4F-F97B-11D1-AB27-00C04FB16FB3}']
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
  IOTAEditView = interface ['{66D8D413-9D17-47B9-9BC4-6D7550437D1E}'] end;
  IOTAEditActions = interface ['{332DBE22-AB36-44B7-B835-BC95F6F9E688}']
    procedure SwapSourceFormView;
  end;
  IOTAEditor = interface ['{F17A7BD0-E07D-11D1-AB0B-00C04FB16FB3}']
    function GetFileName: string;
    procedure Show;
    function GetModified: Boolean;
    property Modified: Boolean read GetModified;
    property FileName: string read GetFileName;
  end;
  IOTASourceEditor = interface(IOTAEditor) ['{4D460588-10A6-4CAD-87E7-5654266073F9}']
    function CreateReader: IOTAEditReader;
    function GetEditViewCount: Integer;
    function GetEditView(AIndex: Integer): IOTAEditView;
    property EditViewCount: Integer read GetEditViewCount;
    property EditViews[AIndex: Integer]: IOTAEditView read GetEditView;
  end;
  IOTAEditBuffer = interface(IOTASourceEditor) ['{EB6465CE-D901-43C4-AB69-240A7400B9AA}'] end;
  IOTAFormEditor = interface(IOTAEditor) ['{F17A7BD2-E07D-11D1-AB0B-00C04FB16FB3}'] end;
  IOTAModule = interface ['{C0D4CBA8-54A3-48EA-BE63-98CE3D9F0F43}']
    function GetFileName: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(AIndex: Integer): IOTAEditor;
    property FileName: string read GetFileName;
    property ModuleFileCount: Integer read GetModuleFileCount;
    property ModuleFileEditors[AIndex: Integer]: IOTAEditor read GetModuleFileEditor;
  end;
  IOTAAdditionalModuleFiles = interface ['{2D73A12F-6FB3-11D4-A4B8-00C04F6BB853}']
    function GetAdditionalModuleFileCount: Integer;
    function GetAdditionalModuleFileEditor(AIndex: Integer): IOTAEditor;
    property AdditionalModuleFileCount: Integer read GetAdditionalModuleFileCount;
    property AdditionalModuleFileEditors[AIndex: Integer]: IOTAEditor read GetAdditionalModuleFileEditor;
  end;
  IOTAModuleServices = interface ['{55A5E848-27FB-4880-8E7C-7F05A9802482}']
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    function FindModule(const AFileName: string): IOTAModule;
    property ModuleCount: Integer read GetModuleCount;
    property Modules[AIndex: Integer]: IOTAModule read GetModule;
  end;
  IOTAEditBufferIterator = interface ['{8ECB33AA-D0BD-11D2-ABD6-00C04FB16FB3}']
    function GetCount: Integer;
    function GetEditBuffer(AIndex: Integer): IOTAEditBuffer;
    property Count: Integer read GetCount;
    property EditBuffers[AIndex: Integer]: IOTAEditBuffer read GetEditBuffer;
  end;
  IOTAEditorServices = interface ['{CAC82350-3885-4CAE-84AE-F1C3B38A6E91}']
    function GetEditBufferIterator(out AIterator: IOTAEditBufferIterator): Boolean;
  end;
  IOTAActionServices = interface ['{F17A7BC9-E07D-11D1-AB0B-00C04FB16FB3}']
    function OpenFile(const AFileName: string): Boolean;
  end;
  TDAIOTA = class
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function NormalizeFileName(const AFileName: string): string; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
    class function FindModuleByFileName(const AFileName: string): IOTAModule; static;
    class function FindSourceEditor(const AFileName: string): IOTASourceEditor; static;
    class function FindFormEditor(const AFileName: string): IOTAFormEditor; static;
    class function EnsureFormDesigner(const AFileName: string): IOTAFormEditor; static;
    class function FormFileName(const AFileName: string): string; static;
    class function EnsureFormTextEditor(const AFileName: string): IOTASourceEditor; static;
    class function ReadEditorText(const ASourceEditor: IOTASourceEditor): string; static;
  end;
var BorlandIDEServices: IInterface;
class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin Result := TPath.GetFullPath(AFileName); end;
class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin Result := SameText(TPath.GetFullPath(ALeft), TPath.GetFullPath(ARight)); end;

{$I DAI.FormText.State.inc}
{$I DAI.FormText.Methods.inc}

type
  TTestExceptionClass = class of Exception;
  TFakeReader = class(TInterfacedObject, IOTAEditReader)
    Bytes: TBytes;
    constructor Create(const AText: string);
    function GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
  end;
  TFakeEditor = class(TInterfacedObject, IOTAEditor)
    FileName: string;
    ShowCount: Integer;
    IsModified: Boolean;
    constructor Create(const AFileName: string);
    function GetFileName: string;
    function GetModified: Boolean;
    procedure Show;
  end;
  TFakeSource = class(TFakeEditor, IOTASourceEditor, IOTAEditBuffer)
    Content: string;
    View: IOTAEditView;
    function CreateReader: IOTAEditReader;
    function GetEditViewCount: Integer;
    function GetEditView(AIndex: Integer): IOTAEditView;
  end;
  TFakeForm = class(TFakeEditor, IOTAFormEditor) end;
  TFakeModule = class(TInterfacedObject, IOTAModule, IOTAAdditionalModuleFiles)
    FileName: string;
    Editors, Additional: TArray<IOTAEditor>;
    PascalSource: IOTASourceEditor;
    Designer: IOTAFormEditor;
    TextMode: Boolean;
    function GetFileName: string;
    function GetModuleFileCount: Integer;
    function GetModuleFileEditor(AIndex: Integer): IOTAEditor;
    function GetAdditionalModuleFileCount: Integer;
    function GetAdditionalModuleFileEditor(AIndex: Integer): IOTAEditor;
  end;
  TFakeServices = class(TInterfacedObject, IOTAModuleServices, IOTAEditorServices, IOTAActionServices, IOTAEditBufferIterator)
    Modules: TArray<IOTAModule>;
    Buffers: TArray<IOTAEditBuffer>;
    OpenCount: Integer;
    function GetModuleCount: Integer;
    function GetModule(AIndex: Integer): IOTAModule;
    function FindModule(const AFileName: string): IOTAModule;
    function GetEditBufferIterator(out AIterator: IOTAEditBufferIterator): Boolean;
    function GetCount: Integer;
    function GetEditBuffer(AIndex: Integer): IOTAEditBuffer;
    function OpenFile(const AFileName: string): Boolean;
  end;
  TFakeView = class(TInterfacedObject, IOTAEditView, IOTAEditActions)
    TargetModule: TFakeModule;
    SwapCount: Integer;
    Effective, DeferDelivery, Pending: Boolean;
    procedure SwapSourceFormView;
    procedure Deliver;
  end;
  TFakeUnsupportedView = class(TInterfacedObject, IOTAEditView) end;

var GChecks: Integer;
procedure Check(ACondition: Boolean; const AName: string);
begin if not ACondition then raise Exception.Create('FAIL: '+AName); Inc(GChecks); end;
procedure RunWorker(const AAction: TThreadProcedure);
var LWorker: TThread;
begin
  LWorker := TThread.CreateAnonymousThread(AAction);
  LWorker.FreeOnTerminate := False;
  try
    LWorker.Start;
    LWorker.WaitFor;
    if Assigned(LWorker.FatalException) then
      raise TTestExceptionClass(LWorker.FatalException.ClassType).Create(Exception(LWorker.FatalException).Message);
  finally LWorker.Free; end;
end;
function TextEditorOnWorker(const AFileName: string): IOTASourceEditor;
var LResult: IOTASourceEditor;
begin
  LResult := nil;
  RunWorker(procedure begin LResult := TDAIOTA.EnsureFormTextEditor(AFileName); end);
  Result := LResult;
end;
function DesignerOnWorker(const AFileName: string): IOTAFormEditor;
var LResult: IOTAFormEditor;
begin
  LResult := nil;
  RunWorker(procedure begin LResult := TDAIOTA.EnsureFormDesigner(AFileName); end);
  Result := LResult;
end;
constructor TFakeEditor.Create(const AFileName: string); begin inherited Create; FileName := AFileName; end;
constructor TFakeReader.Create(const AText: string);
begin inherited Create; Bytes := TEncoding.UTF8.GetBytes(AText); end;
function TFakeReader.GetText(Position: Longint; Buffer: PAnsiChar; Count: Longint): Longint;
begin
  Result := Length(Bytes) - Position;
  if Result < 0 then Result := 0;
  if Result > Count then Result := Count;
  if Result > 0 then Move(Bytes[Position], Buffer^, Result);
end;
function TFakeEditor.GetFileName: string; begin Result := FileName; end;
function TFakeEditor.GetModified: Boolean; begin Result := IsModified; end;
procedure TFakeEditor.Show; begin Inc(ShowCount); end;
function TFakeSource.CreateReader: IOTAEditReader; begin Result := TFakeReader.Create(Content); end;
function TFakeSource.GetEditViewCount: Integer; begin if Assigned(View) then Result := 1 else Result := 0; end;
function TFakeSource.GetEditView(AIndex: Integer): IOTAEditView; begin Result := View; end;
function TFakeModule.GetFileName: string; begin Result := FileName; end;
function TFakeModule.GetModuleFileCount: Integer; begin Result := Length(Editors); end;
function TFakeModule.GetModuleFileEditor(AIndex: Integer): IOTAEditor; begin Result := Editors[AIndex]; end;
function TFakeModule.GetAdditionalModuleFileCount: Integer; begin Result := Length(Additional); end;
function TFakeModule.GetAdditionalModuleFileEditor(AIndex: Integer): IOTAEditor; begin Result := Additional[AIndex]; end;
function TFakeServices.GetModuleCount: Integer; begin Result := Length(Modules); end;
function TFakeServices.GetModule(AIndex: Integer): IOTAModule; begin Result := Modules[AIndex]; end;
function TFakeServices.FindModule(const AFileName: string): IOTAModule;
var LModule: IOTAModule;
begin
  Result := nil;
  for LModule in Modules do
    if Assigned(LModule) then
      if SameText(LModule.FileName, AFileName) then Exit(LModule);
end;
function TFakeServices.GetEditBufferIterator(out AIterator: IOTAEditBufferIterator): Boolean;
begin AIterator := Self; Result := True; end;
function TFakeServices.GetCount: Integer; begin Result := Length(Buffers); end;
function TFakeServices.GetEditBuffer(AIndex: Integer): IOTAEditBuffer; begin Result := Buffers[AIndex]; end;
function TFakeServices.OpenFile(const AFileName: string): Boolean; begin Inc(OpenCount); Result := True; end;
procedure TFakeView.SwapSourceFormView;
begin
  Inc(SwapCount);
  Pending := True;
  if Effective and not DeferDelivery then
    // The real OTA method posts a window message. ForceQueue deliberately waits
    // until the current Synchronize callback has returned, just like the live IDE.
    TThread.ForceQueue(nil, TThreadProcedure(procedure begin Self.Deliver; end));
end;
procedure TFakeView.Deliver;
var LText: TFakeSource;
begin
  if not Pending then Exit;
  Pending := False;
  TargetModule.TextMode := not TargetModule.TextMode;
  if TargetModule.TextMode then
  begin
    TargetModule.FileName := TargetModule.Designer.FileName;
    LText := TFakeSource.Create(TargetModule.FileName);
    LText.View := Self;
    TargetModule.Editors := [];
    TargetModule.Additional := [LText];
  end
  else
  begin
    TargetModule.FileName := TargetModule.PascalSource.FileName;
    TargetModule.Additional := [];
    TargetModule.Editors := [TargetModule.PascalSource, TargetModule.Designer];
  end;
end;

procedure RunCase(const AExtension: string);
var
  LServices: TFakeServices;
  LModule, LOther: TFakeModule;
  LSource, LOtherSource: TFakeSource;
  LForm: TFakeForm;
  LView, LOtherView: TFakeView;
  LResult, LFirst, LSecond: IOTASourceEditor;
  LFormName, LUnitName, LSavedContent: string;
  LDenied: Boolean;
  LWorker1, LWorker2: TThread;
  LDeadline: UInt64;
  LState: TDAIFormViewRequest;
  LSwapCount: Integer;
begin
  LServices := TFakeServices.Create;
  BorlandIDEServices := LServices;
  LUnitName := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'DAI-FormText-'+TGUID.NewGuid.ToString+'.pas');
  LFormName := ChangeFileExt(LUnitName, '.'+AExtension);
  LSavedContent := 'unit Fixture; interface implementation end.';
  LModule := TFakeModule.Create; LModule.FileName := LUnitName;
  LOther := TFakeModule.Create; LOther.FileName := 'Unrelated.pas';
  LServices.Modules := [nil, LOther, LModule];
  LOtherSource := TFakeSource.Create('Unrelated.pas');
  LOtherView := TFakeView.Create; LOtherSource.View := LOtherView;
  LOther.Editors := [LOtherSource];
  LSource := TFakeSource.Create(LUnitName);
  LSource.Content := LSavedContent;
  LForm := TFakeForm.Create(LFormName);
  LModule.PascalSource := LSource; LModule.Designer := LForm;
  LView := TFakeView.Create; LView.TargetModule := LModule;
  LView.Effective := True; LSource.View := LView;
  LModule.Editors := [LSource, LForm];
  try
    Check(not TFile.Exists(LUnitName), 'unsafe fixture starts as never saved Pascal unit');
    LDenied := False;
    try LResult := TextEditorOnWorker(LFormName);
    except on E: EInvalidOperation do LDenied := True; end;
    Check(LDenied, 'never saved Pascal unit rejects native destructive transition');
    Check(LView.SwapCount = 0, 'unsaved Pascal protection runs before any posted swap');
    Check(not TFile.Exists(LUnitName), 'preflight never saves Pascal implicitly');

    // Only a disposable fixture in the Build test output directory is saved; no IDE/project file is written.
    TFile.WriteAllText(LUnitName, LSavedContent);
    LSource.IsModified := True;
    LSource.Content := LSavedContent + ' { changed }';
    LDenied := False;
    try LResult := TextEditorOnWorker(LFormName);
    except on E: EInvalidOperation do LDenied := True; end;
    Check(LDenied, 'saved Pascal with modified editor also rejects destructive transition');
    Check(LView.SwapCount = 0, 'modified Pascal protection runs before swap');
    Check(TFile.ReadAllText(LUnitName) = LSavedContent, 'modified editor preflight leaves saved source byte content unchanged');
    LSource.IsModified := False;
    LDenied := False;
    try LResult := TextEditorOnWorker(LFormName);
    except on E: EInvalidOperation do LDenied := True; end;
    Check(LDenied, 'Pascal content change is protected even when Modified is false');
    Check(LView.SwapCount = 0, 'content comparison protection runs before swap');
    LSource.Content := LSavedContent;
    Check(TDAIOTA.FormFileName(LUnitName) = LFormName, 'actual designer resolves unsaved '+AExtension+' sidecar');
    Check(not TFile.Exists(LFormName), 'form sidecar still exists only in memory');
    Check(not Assigned(TDAIOTA.EnsureFormTextEditor(LFormName)), 'direct main-thread transition cannot block or post');
    Check(LView.SwapCount = 0, 'direct main-thread call leaves asynchronous state untouched');
    LResult := TextEditorOnWorker(LFormName);
    Check(Assigned(LResult), 'delayed posted transition resolves on the worker after callback return');
    Check(LView.SwapCount = 1, 'delayed native swap posted once');
    Check(LOtherView.SwapCount = 0, 'unrelated module remains untouched');
    Check(LServices.OpenCount = 0, 'loaded form uses no disk OpenFile');
    Check(not TFile.Exists(LFormName), 'form text switch never creates a sidecar');
    Check(TDAIOTA.FormFileName(LUnitName) = LFormName, 'Pascal path resolves existing text buffer with FormEditor temporarily absent');
    Check(not Assigned(TDAIOTA.FindFormEditor(LFormName)), 'text mode temporarily has no designer interface');
    Check(not Assigned(TDAIOTA.FindSourceEditor(LUnitName)), 'double models live native Pascal module replacement');
    Check(TDAIOTA.FindSourceEditor(LFormName) = LResult, 'additional form buffer found');
    Check(TextEditorOnWorker(LFormName) = LResult, 'existing text mode operation is idempotent');
    Check(LView.SwapCount = 1, 'idempotent text mode does not post again');
    Check(GFormViewRequests.Count = 0, 'completed transition releases pending guard');
    Check(Assigned(DesignerOnWorker(LUnitName)), 'Pascal path switches existing form text buffer back to designer');
    Check(LView.SwapCount = 2, 'reverse transition posts once');
    Check(Assigned(TDAIOTA.FindSourceEditor(LUnitName)), 'Pascal module reappears after reverse transition');
    Check(Assigned(DesignerOnWorker(LFormName)), 'already visible designer is idempotent');
    Check(LView.SwapCount = 2, 'idempotent designer does not post again');
    Check(TFile.ReadAllText(LUnitName) = LSavedContent, 'safe transitions never rewrite saved Pascal source');
    LResult := nil;

    // A changed DFM may set the PAS editor's module-wide Modified flag. It must
    // not block a second text-mode roundtrip when the full Pascal text is saved.
    LSource.IsModified := True;
    Check(Assigned(TextEditorOnWorker(LFormName)), 'DFM-only Modified flag permits another form text transition');
    Check(Assigned(DesignerOnWorker(LFormName)), 'DFM-only Modified flag permits return to designer');
    LSource.IsModified := False;
    LView.SwapCount := 2;

    LSavedContent := 'unit Fixture;' + #10 + 'interface { Grüße }' + #10 + 'implementation' + #10 + 'end.' + #10;
    LSource.Content := TDAITextEncoding.ApplyLineEnding(LSavedContent, lekCRLF);
    TFile.WriteAllText(LUnitName, LSavedContent, TEncoding.UTF8);
    Check(Assigned(TextEditorOnWorker(LFormName)), 'UTF-8 BOM disk and CRLF editor compare complete decoded Pascal text');
    Check(Assigned(DesignerOnWorker(LFormName)), 'UTF-8 Pascal guard allows reverse transition');
    TFile.WriteAllText(LUnitName, LSavedContent, TEncoding.Unicode);
    Check(Assigned(TextEditorOnWorker(LFormName)), 'UTF-16 BOM disk compares decoded Pascal text');
    Check(Assigned(DesignerOnWorker(LFormName)), 'UTF-16 Pascal guard allows reverse transition');
    TFile.WriteAllText(LUnitName, LSavedContent, TEncoding.ANSI);
    Check(Assigned(TextEditorOnWorker(LFormName)), 'system ANSI disk compares decoded Pascal text');
    Check(Assigned(DesignerOnWorker(LFormName)), 'ANSI Pascal guard allows reverse transition');
    LView.SwapCount := 2;

    LView.DeferDelivery := True;
    LFirst := nil; LSecond := nil;
    LWorker1 := TThread.CreateAnonymousThread(procedure begin LFirst := TDAIOTA.EnsureFormTextEditor(LFormName); end);
    LWorker2 := TThread.CreateAnonymousThread(procedure begin LSecond := TDAIOTA.EnsureFormTextEditor(LFormName); end);
    LWorker1.FreeOnTerminate := False; LWorker2.FreeOnTerminate := False;
    try
      LWorker1.Start; LWorker2.Start;
      LDeadline := GetTickCount64 + 1000;
      LState.Waiters := 0;
      repeat
        CheckSynchronize(1);
        if GFormViewRequests.TryGetValue(LowerCase(TDAIOTA.NormalizeFileName(LFormName)), LState) then
          if LState.Waiters = 2 then Break;
      until GetTickCount64 >= LDeadline;
      Check(LState.Waiters = 2, 'two concurrent requests share pending transition');
      Check(LView.SwapCount = 3, 'concurrent requests post only one native swap');
      Check(not Assigned(TDAIOTA.EnsureFormDesigner(LUnitName)), 'opposite request cannot claim stale current state while transition is pending');
      Check(LView.SwapCount = 3, 'opposite pending request does not post a second toggle');
      LView.Deliver;
      LWorker1.WaitFor; LWorker2.WaitFor;
      Check(not Assigned(LWorker1.FatalException) and not Assigned(LWorker2.FatalException), 'coalesced workers complete without errors');
      Check(Assigned(LFirst) and Assigned(LSecond), 'both concurrent requests observe actual target buffer');
      Check(LFirst = LSecond, 'coalesced requests return the same resolved buffer');
      Check(GFormViewRequests.Count = 0, 'last joined worker releases pending guard');
    finally LWorker1.Free; LWorker2.Free; end;
    LFirst := nil; LSecond := nil;
    LView.DeferDelivery := False;
    Check(Assigned(DesignerOnWorker(LFormName)), 'designer return after concurrent transition');
    LSource.View := TFakeUnsupportedView.Create;
    Check(not Assigned(TextEditorOnWorker(LFormName)), 'unsupported edit actions cannot claim text mode');
    LSource.View := LView; LView.Effective := False;
    Check(not Assigned(TextEditorOnWorker(LFormName)), 'ineffective posted action times out honestly');
    Check(GFormViewRequests.Count = 1, 'timeout retains guard because a posted native action can still arrive');
    LSwapCount := LView.SwapCount;
    Check(not Assigned(TDAIOTA.EnsureFormDesigner(LUnitName)), 'opposite request cannot overtake a timed out native post');
    Check(LView.SwapCount = LSwapCount, 'timeout guard does not post an opposite toggle');
    LView.Deliver;
    Check(Assigned(TextEditorOnWorker(LFormName)), 'late native post is observed without reposting');
    Check(LView.SwapCount = LSwapCount, 'late completion never triggers a duplicate toggle');
    Check(GFormViewRequests.Count = 0, 'observed late completion removes timeout guard');
    LView.Effective := True;
    Check(Assigned(DesignerOnWorker(LFormName)), 'reverse transition remains usable after late completion');
    LSource.View := nil;
    Check(not Assigned(TextEditorOnWorker(LFormName)), 'missing view returns no buffer');
    Check(not Assigned(TextEditorOnWorker(ChangeFileExt(LUnitName, '.absent'))), 'missing non-form file unchanged');
    LServices.Buffers := [nil, TFakeSource.Create(LFormName)];
    LResult := TDAIOTA.FindSourceEditor(LFormName);
    Check(Assigned(LResult), 'official buffer iterator finds independent form text buffer');
    Check(TextEditorOnWorker(LFormName) = LResult, 'iterator buffer reused without posting');
    LResult := nil; LServices.Buffers := []; LServices.Modules := [];
    Check(not Assigned(TextEditorOnWorker(LFormName)), 'missing form module does not touch disk');
    Check(LServices.OpenCount = 0, 'missing unsaved form never attempts OpenFile');
  finally
    if TFile.Exists(LUnitName) then TFile.Delete(LUnitName);
    BorlandIDEServices := nil;
  end;
end;

begin
  GFormViewRequests := TDictionary<string, TDAIFormViewRequest>.Create;
  try
    try
      RunCase('dfm'); RunCase('fmx');
      Check(not Assigned(TDAIOTA.FindSourceEditor('Missing.dfm')), 'missing IDE service returns no source editor');
      Check(TDAIOTA.FormFileName('Missing.pas') = '', 'missing form and sidecar returns no filename');
      Writeln('PASS: ', GChecks, ' native asynchronous form routing and Pascal preservation checks');
    except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
  finally GFormViewRequests.Free; end;
end.
