unit h5u.DAI.Process;

interface

uses
  h5u.DAI.Types;

type
  TDAIProcess = class sealed
  public
    class function Execute(const AExecutable: string; const AArguments: TArray<string>;
      const AWorkingDirectory: string; const ATimeoutMs: Cardinal): TDAIProcessResult; static;
    class function StartDetached(const AExecutable: string; const AArguments: TArray<string>;
      const AWorkingDirectory: string; out AProcessHandle: THandle; out AProcessId: Cardinal): Boolean; static;
    class function ResolveMSBuildExecutable(const ARequestedFileName: string): string; static;
    class function ResolveDCC32Executable: string; static;
  end;

implementation

uses
  System.Classes,
  System.SysUtils;

class function TDAIProcess.Execute(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDirectory: string; const ATimeoutMs: Cardinal): TDAIProcessResult;
begin
  Result := Default(TDAIProcessResult);
  raise EInvalidOperation.Create('External process execution is forbidden in isolated Build tests.');
end;

class function TDAIProcess.StartDetached(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDirectory: string; out AProcessHandle: THandle; out AProcessId: Cardinal): Boolean;
begin
  AProcessHandle := 0;
  AProcessId := 0;
  raise EInvalidOperation.Create('Detached process execution is forbidden in isolated Build tests.');
end;

class function TDAIProcess.ResolveMSBuildExecutable(const ARequestedFileName: string): string;
begin
  Result := '';
  raise EInvalidOperation.Create('External compiler resolution is forbidden in isolated Build tests.');
end;

class function TDAIProcess.ResolveDCC32Executable: string;
begin
  Result := '';
  raise EInvalidOperation.Create('External compiler resolution is forbidden in isolated Build tests.');
end;

end.
