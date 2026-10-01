unit ToolsAPI;

interface

uses
  System.Classes,
  System.SysUtils;

type
  IOTAMessageServices = interface(IInterface)
    ['{BDACE546-3E84-49D5-93FA-3494C2A11FF4}']
    procedure AddTitleMessage(const AText: string);
  end;

  TLogMessageSink = class(TInterfacedObject, IOTAMessageServices)
  public
    Messages: TStringList;
    LastThreadId: Cardinal;
    RaiseOnMessage: Boolean;
    OnMessage: TProc;
    constructor Create;
    destructor Destroy; override;
    procedure AddTitleMessage(const AText: string);
  end;

var
  BorlandIDEServices: IInterface;

implementation

uses
  Winapi.Windows;

constructor TLogMessageSink.Create;
begin
  inherited;
  Messages := TStringList.Create;
end;

destructor TLogMessageSink.Destroy;
begin
  Messages.Free;
  inherited;
end;

procedure TLogMessageSink.AddTitleMessage(const AText: string);
begin
  LastThreadId := GetCurrentThreadId;
  Messages.Add(AText);
  if Assigned(OnMessage) then
    OnMessage();
  if RaiseOnMessage then
    raise EInvalidOperation.Create('Isolated message-service failure');
end;

end.
