program TestProjectOpenPackage;
{$APPTYPE CONSOLE}
uses System.Classes, System.SysUtils, Vcl.Forms, Winapi.Windows;
type
  TStartJob = procedure; stdcall;
  TSetHook = procedure(AHook: Pointer); stdcall;
  TFinished = function: LongBool; stdcall;
var
  Checks: Integer;
  Module: HMODULE;
  ModuleName: string;
  HookCalled, RetainedDuringCall: Boolean;
procedure Check(const AValue: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not AValue then raise Exception.Create('FAIL: ' + AMessage);
end;
procedure UnloadDuringCall; stdcall;
var LModule: HMODULE;
begin
  HookCalled := True;
  LModule := Module;
  Module := 0;
  UnloadPackage(LModule);
  RetainedDuringCall := GetModuleHandle(PChar(ModuleName)) = LModule;
end;
procedure WaitForUnmapped;
var LStarted: UInt64;
begin
  LStarted := GetTickCount64;
  while GetModuleHandle(PChar(ModuleName)) <> 0 do
  begin
    CheckSynchronize(1);
    if GetTickCount64 - LStarted > 5000 then raise Exception.Create('Package callback reference was not released');
    Sleep(1);
  end;
  Check(True, 'package reference is released after its callback returns');
end;
procedure RunCase(const AMode: Integer);
var LStart: TStartJob; LHook: TSetHook; LFinished: TFinished; LStarted: UInt64;
begin
  Module := LoadPackage(ExpandFileName(ParamStr(1)));
  Check(Module <> 0, 'isolated package loads');
  try
    {$IFDEF WIN64}
    LStart := TStartJob(GetProcAddress(Module, '_ZN3Dai11Projectopen12Packageprobe8StartJobEv'));
    LHook := TSetHook(GetProcAddress(Module, '_ZN3Dai11Projectopen12Packageprobe7SetHookEPv'));
    LFinished := TFinished(GetProcAddress(Module, '_ZN3Dai11Projectopen12Packageprobe8FinishedEv'));
    {$ELSE}
    LStart := TStartJob(GetProcAddress(Module, '@Dai@Projectopen@Packageprobe@StartJob$qqsv'));
    LHook := TSetHook(GetProcAddress(Module, '@Dai@Projectopen@Packageprobe@SetHook$qqspv'));
    LFinished := TFinished(GetProcAddress(Module, '@Dai@Projectopen@Packageprobe@Finished$qqsv'));
    {$ENDIF}
    Check(Assigned(LStart) and Assigned(LHook) and Assigned(LFinished), 'typed package probe exports available');
    if AMode = 2 then LHook(@UnloadDuringCall);
    LStart;
    if AMode = 1 then
    begin
      LStarted := GetTickCount64;
      while not LFinished do
      begin
        CheckSynchronize(1);
        if GetTickCount64 - LStarted > 5000 then raise Exception.Create('Normal package request did not finish');
        Sleep(1);
      end;
      Check(True, 'normal package job completes');
    end;
    if AMode = 2 then
    begin
      LStarted := GetTickCount64;
      while not HookCalled do
      begin
        CheckSynchronize(1);
        if GetTickCount64 - LStarted > 5000 then raise Exception.Create('Reentrant unload hook did not run');
      end;
      Check(RetainedDuringCall, 'BPL stays mapped inside the finalized native call');
    end
    else
    begin
      UnloadPackage(Module);
      Module := 0;
    end;
    WaitForUnmapped;
  finally if Module <> 0 then begin UnloadPackage(Module); Module := 0; end; end;
end;
begin
  try
    Check(ParamCount = 1, 'probe package path supplied');
    Application.Initialize;
    Application.ShowMainForm := False;
    ModuleName := ExtractFileName(ParamStr(1));
    RunCase(0); // Queued work: finalization must cancel and join it.
    RunCase(1); // Finished work: no permanent module pin is left behind.
    RunCase(2); // Reentrant unload while a native IDE call owns the main thread.
    Writeln('PASS: ', Checks, ' project-open BPL lifetime checks');
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); Halt(1); end; end;
end.
