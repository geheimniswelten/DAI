unit h5u.DAI.Symbols.Service;

interface

uses System.JSON;

type
  TDAISymbolService = class sealed
  public
    class var Calls, SnapshotCalls: Integer;
    class var LastMethod, LastScope, LastIdentity, LastQuery, LastVisibility, LastRequestId: string;
    class var LastMaximum: Integer;
    class var LastParameters: TJSONObject;
    class var SnapshotIdentity, JobScope: string;
    class var Projects: TArray<string>;
    class procedure Reset; static;
    class function PermissionSnapshot(const AScope: string): TJSONObject; static;
    class function ListIndexes: TJSONObject; static;
    class function JobStatus(const ARequestId: string): TJSONObject; static;
    class function AIStatus: TJSONObject; static;
    class function Build(const AScope, AIdentity: string): TJSONObject; static;
    class function Delete(const AScope, AIdentity: string): TJSONObject; static;
    class function Search(const AScope, AQuery, AVisibility: string; const AMaximum: Integer; const AIdentity: string): TJSONObject; static;
    class function Query(const AScope, ASQL: string; const AParameters: TJSONObject; const AMaximum: Integer; const AIdentity: string): TJSONObject; static;
  end;

implementation

uses System.SysUtils;

function Called(const AMethod: string): TJSONObject;
begin
  Inc(TDAISymbolService.Calls);
  TDAISymbolService.LastMethod := AMethod;
  Result := TJSONObject.Create.AddPair('method', AMethod);
end;

class procedure TDAISymbolService.Reset;
begin
  Calls := 0;
  SnapshotCalls := 0;
  LastMethod := '';
  LastScope := '';
  LastIdentity := '';
  LastQuery := '';
  LastVisibility := '';
  LastRequestId := '';
  LastMaximum := 0;
  LastParameters := nil;
  SnapshotIdentity := 'captured-owner-and-membership-identity';
  JobScope := 'group';
  SetLength(Projects, 80);
  for var LIndex := 0 to High(Projects) do
    Projects[LIndex] := Format('C:\SymbolsDispatchFixture\Project%.3d.dproj', [LIndex]);
end;

class function TDAISymbolService.PermissionSnapshot(const AScope: string): TJSONObject;
var
  LProjects: TJSONArray;
begin
  Inc(SnapshotCalls);
  if (AScope <> 'project') and (AScope <> 'group') and (AScope <> 'delphi') and (AScope <> 'getit') then
    raise EArgumentException.Create('Unknown index scope.');
  LProjects := TJSONArray.Create;
  if AScope = 'group' then
    for var LProject in Projects do
      LProjects.Add(LProject)
  else if (AScope = 'project') and (Length(Projects) > 0) then
    LProjects.Add(Projects[0]);
  Result := TJSONObject.Create.AddPair('identity', SnapshotIdentity).AddPair('projects', LProjects);
end;

class function TDAISymbolService.ListIndexes: TJSONObject;
begin
  Result := Called('list');
end;

class function TDAISymbolService.JobStatus(const ARequestId: string): TJSONObject;
var
  LErrors: TJSONArray;
begin
  LastRequestId := ARequestId;
  Result := Called('job');
  LErrors := TJSONArray.Create;
  LErrors.AddElement(TJSONObject.Create.AddPair('file', 'C:\PrivateProject\Hidden.pas').AddPair('error', 'Private source context'));
  Result.AddPair('scope', JobScope).AddPair('error', 'Private project failure text')
    .AddPair('error_count', TJSONNumber.Create(1)).AddPair('errors', LErrors);
end;

class function TDAISymbolService.AIStatus: TJSONObject;
begin
  Result := Called('ai');
end;

class function TDAISymbolService.Build(const AScope, AIdentity: string): TJSONObject;
begin
  LastScope := AScope;
  LastIdentity := AIdentity;
  Result := Called('build');
end;

class function TDAISymbolService.Delete(const AScope, AIdentity: string): TJSONObject;
begin
  LastScope := AScope;
  LastIdentity := AIdentity;
  Result := Called('delete');
end;

class function TDAISymbolService.Search(const AScope, AQuery, AVisibility: string; const AMaximum: Integer;
  const AIdentity: string): TJSONObject;
begin
  LastScope := AScope;
  LastIdentity := AIdentity;
  LastQuery := AQuery;
  LastVisibility := AVisibility;
  LastMaximum := AMaximum;
  Result := Called('search');
end;

class function TDAISymbolService.Query(const AScope, ASQL: string; const AParameters: TJSONObject; const AMaximum: Integer;
  const AIdentity: string): TJSONObject;
begin
  LastScope := AScope;
  LastIdentity := AIdentity;
  LastQuery := ASQL;
  LastParameters := AParameters;
  LastMaximum := AMaximum;
  Result := Called('query');
end;

end.
