unit CodexMCP.Threading;

interface

uses
  System.Classes,
  System.SysUtils;

type
  TCodexMCPThreading = class sealed
  public
    class procedure RunInIDEThread(const AAction: TThreadProcedure); static;
    class function CallInIDEThread<T>(const AFunction: TFunc<T>): T; static;
  end;

implementation

uses
  Winapi.Windows;

class function TCodexMCPThreading.CallInIDEThread<T>(
  const AFunction: TFunc<T>
): T;
var
  LAction: TThreadProcedure;
  LResult: T;
begin
  if not Assigned(AFunction) then
    raise EArgumentNilException.Create('AFunction');
  LAction :=
    procedure
    begin
      LResult := AFunction();
    end;
  RunInIDEThread(LAction);
  Result := LResult;
end;

class procedure TCodexMCPThreading.RunInIDEThread(
  const AAction: TThreadProcedure
);
begin
  if not Assigned(AAction) then
    Exit;
  if GetCurrentThreadId = MainThreadID then
    AAction()
  else
    TThread.Synchronize(nil, AAction);
end;

end.
