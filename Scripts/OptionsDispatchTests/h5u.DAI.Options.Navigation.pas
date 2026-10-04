unit h5u.DAI.Options.Navigation;

interface

uses System.JSON;

type
{$I DAI.OptionsDispatch.Request.inc}

  TDAIOptionsNavigationService = class sealed
  public
    class var OpenCalls, StatusCalls, OpenPermissionCount, StatusPermissionCount: Integer;
    class var LastRequest: TDAIOptionsNavigationRequest;
    class var LastRequestId: string;
    class var LastResponse: TJSONObject;
    class procedure Reset; static;
    class function Open(const ARequest: TDAIOptionsNavigationRequest): TJSONObject; static;
    class function Status(const ARequestId: string): TJSONObject; static;
  end;

implementation

uses h5u.DAI.Permissions.Manager;

function Response(const AKind: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('service_response', 'final-options-' + AKind + '-response');
  Result.AddPair('request_id', 'actual-final-request-id');
  Result.AddPair('state', 'unsupported');
  Result.AddPair('option_focused', TJSONBool.Create(False));
  TDAIOptionsNavigationService.LastResponse := Result;
end;

class procedure TDAIOptionsNavigationService.Reset;
begin
  OpenCalls := 0;
  StatusCalls := 0;
  OpenPermissionCount := -1;
  StatusPermissionCount := -1;
  LastRequest := Default(TDAIOptionsNavigationRequest);
  LastRequestId := '';
  LastResponse := nil;
end;

class function TDAIOptionsNavigationService.Open(const ARequest: TDAIOptionsNavigationRequest): TJSONObject;
begin
  Inc(OpenCalls);
  LastRequest := ARequest;
  OpenPermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := Response('open');
end;

class function TDAIOptionsNavigationService.Status(const ARequestId: string): TJSONObject;
begin
  Inc(StatusCalls);
  LastRequestId := ARequestId;
  StatusPermissionCount := Length(TDAIPermissionManager.Instance.Requests);
  Result := Response('status');
end;

end.
