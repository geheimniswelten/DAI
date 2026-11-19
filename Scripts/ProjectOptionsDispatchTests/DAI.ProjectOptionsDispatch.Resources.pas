unit DAI.ProjectOptionsDispatch.Resources;

interface

uses
  System.JSON;

const
  CResourceProject = 'C:\IsolatedProjectResourcesTest\Project.dproj';
  CResourceAlias = 'ResourceProject';

type
  IOTAProject = interface(IInterface)
  end;

  TDAIOTA = class sealed
  public
    class function ProjectByNameOrPath(const AProject: string): IOTAProject; static;
    class function ProjectFileName(const AProject: IOTAProject): string; static;
  end;

  TDAIProjectResourceAction = (praAdd, praUpdate, praRemove);

  TDAIProjectResourceChange = record
    Action: TDAIProjectResourceAction;
    ResourceType, ResourceId: string;
    FileName, NewResourceType, NewResourceId: string;
  end;

  TDAIProjectResourcesService = class sealed
  public
    class var Calls: Integer;
    class var LastList: Boolean;
    class var LastProject: string;
    class var LastChange: TDAIProjectResourceChange;
    class procedure Reset; static;
    class function ListResources(const AProjectFile: string): TJSONObject; static;
    class function ChangeResource(const AProjectFile: string; const AChange: TDAIProjectResourceChange): TJSONObject; static;
  end;

implementation

uses
  System.SysUtils;

type
  TFixtureProject = class(TInterfacedObject, IOTAProject)
  end;

class function TDAIOTA.ProjectByNameOrPath(const AProject: string): IOTAProject;
begin
  Result := nil;
  if (AProject = '') or SameText(AProject, CResourceAlias) or SameText(AProject, CResourceProject) then
    Result := TFixtureProject.Create;
end;

class function TDAIOTA.ProjectFileName(const AProject: IOTAProject): string;
begin
  Result := '';
  if Assigned(AProject) then
    Result := CResourceProject;
end;

class procedure TDAIProjectResourcesService.Reset;
begin
  Calls := 0;
  LastList := False;
  LastProject := '';
  LastChange := Default(TDAIProjectResourceChange);
end;

class function TDAIProjectResourcesService.ListResources(const AProjectFile: string): TJSONObject;
begin
  Inc(Calls);
  LastList := True;
  LastProject := AProjectFile;
  Result := TJSONObject.Create.AddPair('project', AProjectFile);
end;

class function TDAIProjectResourcesService.ChangeResource(const AProjectFile: string; const AChange: TDAIProjectResourceChange): TJSONObject;
begin
  Inc(Calls);
  LastProject := AProjectFile;
  LastChange := AChange;
  Result := TJSONObject.Create.AddPair('project', AProjectFile);
end;

end.
