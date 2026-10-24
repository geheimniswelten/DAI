unit h5u.DAI.Usage;

interface

type
  TDAIUsage = class sealed
  public
    class var CallCount: Integer;
    class var LastToolName: string;
    class procedure RecordToolCall(const ACanonicalToolName: string; const AShowsActivity: Boolean); static;
    class function LastActivityTick: UInt64; static;
    class procedure ResetActivity; static;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs;

var
  GActivityTick: Int64;

class procedure TDAIUsage.RecordToolCall(const ACanonicalToolName: string; const AShowsActivity: Boolean);
begin
  LastToolName := ACanonicalToolName;
  TInterlocked.Increment(CallCount);
  if AShowsActivity then
    TInterlocked.Exchange(GActivityTick, Int64(TThread.GetTickCount64));
end;

class function TDAIUsage.LastActivityTick: UInt64;
begin
  Result := UInt64(TInterlocked.Read(GActivityTick));
end;

class procedure TDAIUsage.ResetActivity;
begin
  TInterlocked.Exchange(GActivityTick, Int64(0));
end;

end.
