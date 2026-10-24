unit h5u.DAI.OTA.Projects;

interface

uses System.JSON;

type
  TDAIProjectService = class
  public
    class var CreateCalls, OpenCalls, PermissionCountAtCall: Integer;
    class var LastName, LastDirectory, LastKind, LastFile: string;
    class var LastSave, LastCloseOthers: Boolean;
    class procedure Reset; static;
    class function CreateProject(const AName, ADirectory, AKind: string; const ASave, ACloseOthers: Boolean): TJSONObject; static;
    class function OpenProject(const AFile: string; const ACloseOthers: Boolean): TJSONObject; static;
  end;

implementation

uses h5u.DAI.Permissions.Manager;

class procedure TDAIProjectService.Reset;
begin
  CreateCalls := 0;
  OpenCalls := 0;
  PermissionCountAtCall := 0;
  LastName := '';
  LastDirectory := '';
  LastKind := '';
  LastFile := '';
  LastSave := False;
  LastCloseOthers := False;
end;

class function TDAIProjectService.CreateProject(const AName, ADirectory, AKind: string; const ASave, ACloseOthers: Boolean): TJSONObject;
begin
  Inc(CreateCalls);
  PermissionCountAtCall := Length(TDAIPermissionManager.Instance.Requests);
  LastName := AName;
  LastDirectory := ADirectory;
  LastKind := AKind;
  LastSave := ASave;
  LastCloseOthers := ACloseOthers;
  Result := TJSONObject.Create;
  Result.AddPair('created', TJSONBool.Create(True));
end;

class function TDAIProjectService.OpenProject(const AFile: string; const ACloseOthers: Boolean): TJSONObject;
begin
  Inc(OpenCalls);
  PermissionCountAtCall := Length(TDAIPermissionManager.Instance.Requests);
  LastFile := AFile;
  LastCloseOthers := ACloseOthers;
  Result := TJSONObject.Create;
  Result.AddPair('opened', TJSONBool.Create(True));
end;

end.
