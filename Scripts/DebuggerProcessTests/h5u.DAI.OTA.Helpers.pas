unit h5u.DAI.OTA.Helpers;

interface

uses
  System.Classes;

type
  TDAIOTA = class sealed
  public
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function IsWorkspaceFile(const AFileName: string): Boolean; static;
    class function IsFileOpenInEditor(const AFileName: string): Boolean; static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows;

class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  if GetCurrentThreadId = MainThreadID then
    AAction()
  else
    TThread.Synchronize(nil, AAction);
end;

class function TDAIOTA.IsWorkspaceFile(const AFileName: string): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected workspace lookup');
end;

class function TDAIOTA.IsFileOpenInEditor(const AFileName: string): Boolean;
begin
  raise EInvalidOperation.Create('Unexpected editor lookup');
end;

class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(ALeft, ARight);
end;

end.
