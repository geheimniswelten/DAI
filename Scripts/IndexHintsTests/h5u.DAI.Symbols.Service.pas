unit h5u.DAI.Symbols.Service;

interface

uses System.JSON;

type
  TDAISymbolService = class sealed
  public
    class var ContextCalls, ProjectCalls: Integer;
    class var FailContext: Boolean;
    class var FailProjectFile: string;
    class var Targets: TArray<string>;
    class procedure Reset; static;
    class function ContextSummary: TJSONObject; static;
    class function IndexSummary(const AScope: string; const AProjectFile: string = ''): TJSONObject; static;
  end;

implementation

uses System.Classes, System.SysUtils, h5u.DAI.OTA.Helpers;

class procedure TDAISymbolService.Reset;
begin
  ContextCalls := 0;
  ProjectCalls := 0;
  FailContext := False;
  FailProjectFile := '';
  Targets := nil;
end;

class function TDAISymbolService.ContextSummary: TJSONObject;
begin
  Inc(ContextCalls);
  if FailContext then
    raise EInvalidOperation.Create('PRIVATE source context from controlled summary failure');
  Result := TJSONObject.Create
    .AddPair('delphi', TJSONObject.Create.AddPair('scope', 'delphi').AddPair('state', 'ready').AddPair('exists', TJSONBool.Create(True)))
    .AddPair('getit', TJSONObject.Create.AddPair('scope', 'getit').AddPair('state', 'missing').AddPair('exists', TJSONBool.Create(False)))
    .AddPair('group', TJSONObject.Create.AddPair('scope', 'group').AddPair('state', 'ready').AddPair('exists', TJSONBool.Create(True)))
    .AddPair('project', TJSONObject.Create.AddPair('scope', 'project').AddPair('state', 'ready')
      .AddPair('exists', TJSONBool.Create(True)).AddPair('project_file', TDAIOTA.ActiveProjectFileName));
end;

class function TDAISymbolService.IndexSummary(const AScope, AProjectFile: string): TJSONObject;
begin
  if AScope <> 'project' then
    raise EArgumentException.Create('This fixture only expects per-project index summaries.');
  Inc(ProjectCalls);
  SetLength(Targets, Length(Targets) + 1);
  Targets[High(Targets)] := AProjectFile;
  if (FailProjectFile <> '') and SameText(AProjectFile, FailProjectFile) then
    raise EInvalidOperation.Create('PRIVATE project content from controlled index failure');
  Result := TJSONObject.Create.AddPair('scope', AScope).AddPair('project_file', AProjectFile)
    .AddPair('state', 'ready').AddPair('exists', TJSONBool.Create(True));
end;

end.
