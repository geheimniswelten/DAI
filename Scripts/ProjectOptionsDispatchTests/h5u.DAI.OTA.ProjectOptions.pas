unit h5u.DAI.OTA.ProjectOptions;

interface

uses
  System.JSON;

type
  TDAIProjectOptionsService = class sealed
  public
    class var Calls: Integer;
    class var LastMethod: string;
    class var LastProject: string;
    class var LastConfiguration: string;
    class var LastPlatform: string;
    class var LastNames: TArray<string>;
    class var LastMaximumOptions: Integer;
    class var LastName: string;
    class var LastValue: string;
    class var LastMergeMode: string;
    class procedure Reset; static;
    class function Configurations(const AProject: string): TJSONObject; static;
    class function ReadOptions(const AProject, AConfiguration, APlatform: string;
      const ANames: TArray<string>; const AMaximumOptions: Integer): TJSONObject; static;
    class function SetOption(const AProject, AConfiguration, APlatform, AName, AValue, AMergeMode: string): TJSONObject; static;
    class function RemoveOption(const AProject, AConfiguration, APlatform, AName: string): TJSONObject; static;
    class function ActivateProject(const AProject: string): TJSONObject; static;
  end;

implementation

function Response(const AMethod: string): TJSONObject;
begin
  Inc(TDAIProjectOptionsService.Calls);
  TDAIProjectOptionsService.LastMethod := AMethod;
  Result := TJSONObject.Create;
  Result.AddPair('method', AMethod);
end;

class procedure TDAIProjectOptionsService.Reset;
begin
  Calls := 0;
  LastMethod := '';
  LastProject := '';
  LastConfiguration := '';
  LastPlatform := '';
  LastNames := nil;
  LastMaximumOptions := -1;
  LastName := '';
  LastValue := '';
  LastMergeMode := '';
end;

class function TDAIProjectOptionsService.ActivateProject(const AProject: string): TJSONObject;
begin
  LastProject := AProject;
  Result := Response('activate');
end;

class function TDAIProjectOptionsService.Configurations(const AProject: string): TJSONObject;
begin
  LastProject := AProject;
  Result := Response('configurations');
end;

class function TDAIProjectOptionsService.ReadOptions(const AProject, AConfiguration, APlatform: string;
  const ANames: TArray<string>; const AMaximumOptions: Integer): TJSONObject;
begin
  LastProject := AProject;
  LastConfiguration := AConfiguration;
  LastPlatform := APlatform;
  LastNames := Copy(ANames);
  LastMaximumOptions := AMaximumOptions;
  Result := Response('read');
end;

class function TDAIProjectOptionsService.SetOption(const AProject, AConfiguration, APlatform, AName, AValue, AMergeMode: string): TJSONObject;
begin
  LastProject := AProject;
  LastConfiguration := AConfiguration;
  LastPlatform := APlatform;
  LastName := AName;
  LastValue := AValue;
  LastMergeMode := AMergeMode;
  Result := Response('set');
end;

class function TDAIProjectOptionsService.RemoveOption(const AProject, AConfiguration, APlatform, AName: string): TJSONObject;
begin
  LastProject := AProject;
  LastConfiguration := AConfiguration;
  LastPlatform := APlatform;
  LastName := AName;
  Result := Response('remove');
end;

end.
