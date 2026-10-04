unit h5u.DAI.OTA.Helpers;
interface
uses System.Classes;
type TDAIOTA = class sealed
  public
    class procedure RunOnMainThread(const AAction: TThreadProcedure); static;
    class function SameFile(const ALeft, ARight: string): Boolean; static;
    class function NormalizeFileName(const AFileName: string): string; static;
  end;
implementation
uses System.SysUtils, Winapi.Windows;
class procedure TDAIOTA.RunOnMainThread(const AAction: TThreadProcedure);
begin
  if GetCurrentThreadId <> MainThreadID then raise EInvalidOperation.Create('SDK used outside IDE thread.');
  AAction();
end;
class function TDAIOTA.SameFile(const ALeft, ARight: string): Boolean;
begin Result := SameText(NormalizeFileName(ALeft), NormalizeFileName(ARight)); end;
class function TDAIOTA.NormalizeFileName(const AFileName: string): string;
begin Result := ExpandFileName(AFileName); end;
end.
