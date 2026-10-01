unit DAI.CodeInsight.PackageProbe;

interface

uses
  ToolsAPI;

procedure PrepareEditor(const AEditor: IOTASourceEditor); stdcall;
function InvokeDefinition(const AExpectTimeout: LongBool): LongBool; stdcall;
function InvokeHover(const AExpectTimeout: LongBool): LongBool; stdcall;
function NewRequestsRejected: LongBool; stdcall;

implementation

uses
  System.Classes,
  System.JSON,
  System.SysUtils,
  h5u.DAI.OTA.CodeInsight,
  h5u.DAI.OTA.Helpers;

const
  CInputFile = 'C:\SyntheticDAICodeInsight\Input.pas';

procedure PrepareEditor(const AEditor: IOTASourceEditor);
begin
  TestSourceEditor := AEditor;
end;

function InvokeDefinition(const AExpectTimeout: LongBool): LongBool;
var
  LResult: TJSONObject;
begin
  LResult := TDAICodeInsightService.Definition(CInputFile, 11, 3, 100);
  try
    if AExpectTimeout then
      Result := LResult.GetValue<Boolean>('timed_out') and not LResult.GetValue<Boolean>('success')
    else
      Result := LResult.GetValue<Boolean>('success') and LResult.GetValue<Boolean>('found');
  finally
    LResult.Free;
  end;
end;

function InvokeHover(const AExpectTimeout: LongBool): LongBool;
var
  LResult: TJSONObject;
begin
  LResult := TDAICodeInsightService.Hover(CInputFile, 11, 4, 100);
  try
    if AExpectTimeout then
      Result := LResult.GetValue<Boolean>('timed_out') and not LResult.GetValue<Boolean>('success')
    else
      Result := LResult.GetValue<Boolean>('success') and LResult.GetValue<Boolean>('found');
  finally
    LResult.Free;
  end;
end;

function NewRequestsRejected: LongBool;
var
  LRejected: Integer;
begin
  LRejected := 0;
  try
    InvokeDefinition(False);
  except
    on E: EInvalidOperation do
      if Pos('IDE-Neustart', E.Message) > 0 then
        Inc(LRejected);
  end;
  try
    InvokeHover(False);
  except
    on E: EInvalidOperation do
      if Pos('IDE-Neustart', E.Message) > 0 then
        Inc(LRejected);
  end;
  Result := LRejected = 2;
end;

end.
