unit CodexMCP.Json;

interface

uses
  System.JSON,
  System.SysUtils;

function JsonString(
  const AObject: TJSONObject;
  const AName: string;
  const ADefault: string = ''
): string;
function JsonBoolean(
  const AObject: TJSONObject;
  const AName: string;
  const ADefault: Boolean = False
): Boolean;
function JsonInteger(
  const AObject: TJSONObject;
  const AName: string;
  const ADefault: Integer = 0
): Integer;
function JsonObject(
  const AObject: TJSONObject;
  const AName: string
): TJSONObject;
function RequireJsonString(
  const AObject: TJSONObject;
  const AName: string
): string;
function JsonStringArray(const AValues: TArray<string>): TJSONArray;
function JsonSuccess: TJSONObject;
function JsonSuccessPair(
  const AName: string;
  const AValue: string
): TJSONObject;
function JsonFailure(const AMessage: string): TJSONObject;

implementation

function JsonString(
  const AObject: TJSONObject;
  const AName,
  ADefault: string
): string;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObject) then
    Exit;
  LValue := AObject.Values[AName];
  if LValue is TJSONString then
    Result := TJSONString(LValue).Value;
end;

function JsonBoolean(
  const AObject: TJSONObject;
  const AName: string;
  const ADefault: Boolean
): Boolean;
var
  LText: string;
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObject) then
    Exit;
  LValue := AObject.Values[AName];
  if LValue is TJSONBool then
    Exit(TJSONBool(LValue).AsBoolean);
  if LValue is TJSONString then
  begin
    LText := TJSONString(LValue).Value;
    if SameText(LText, 'true') then
      Exit(True);
    if SameText(LText, 'false') then
      Exit(False);
  end;
end;

function JsonInteger(
  const AObject: TJSONObject;
  const AName: string;
  const ADefault: Integer
): Integer;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObject) then
    Exit;
  LValue := AObject.Values[AName];
  if LValue is TJSONNumber then
    Result := TJSONNumber(LValue).AsInt;
end;

function JsonObject(
  const AObject: TJSONObject;
  const AName: string
): TJSONObject;
var
  LValue: TJSONValue;
begin
  Result := nil;
  if not Assigned(AObject) then
    Exit;
  LValue := AObject.Values[AName];
  if LValue is TJSONObject then
    Result := TJSONObject(LValue);
end;

function JsonFailure(const AMessage: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONBool.Create(False));
  Result.AddPair('error', AMessage);
end;

function JsonStringArray(const AValues: TArray<string>): TJSONArray;
var
  LValue: string;
begin
  Result := TJSONArray.Create;
  for LValue in AValues do
    Result.Add(LValue);
end;

function JsonSuccess: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONBool.Create(True));
end;

function JsonSuccessPair(
  const AName,
  AValue: string
): TJSONObject;
begin
  Result := JsonSuccess;
  Result.AddPair(AName, AValue);
end;

function RequireJsonString(
  const AObject: TJSONObject;
  const AName: string
): string;
begin
  Result := Trim(JsonString(AObject, AName));
  if Result = '' then
    raise EArgumentException.CreateFmt(
      'Das erforderliche Argument "%s" fehlt.',
      [AName]
    );
end;

end.
