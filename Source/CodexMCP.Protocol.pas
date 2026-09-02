unit CodexMCP.Protocol;

interface

type
  TCodexMCPProtocol = class sealed
  public
    class function HandleRequest(
      const ARequestBody: string;
      out AResponseBody: string;
      out AHttpStatus: Integer
    ): Boolean; static;
  end;

implementation

uses
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  CodexMCP.Constants,
  CodexMCP.Json,
  CodexMCP.OTA.Dispatcher;

type
  TCodexToolHints = record
    ReadOnly: Boolean;
    Destructive: Boolean;
    Idempotent: Boolean;
    OpenWorld: Boolean;
    class function Create(
      const AReadOnly,
      ADestructive,
      AIdempotent,
      AOpenWorld: Boolean
    ): TCodexToolHints; static;
  end;

class function TCodexToolHints.Create(
  const AReadOnly,
  ADestructive,
  AIdempotent,
  AOpenWorld: Boolean
): TCodexToolHints;
begin
  Result.ReadOnly := AReadOnly;
  Result.Destructive := ADestructive;
  Result.Idempotent := AIdempotent;
  Result.OpenWorld := AOpenWorld;
end;

function CloneJsonValue(const AValue: TJSONValue): TJSONValue;
begin
  if not Assigned(AValue) then
    Exit(TJSONNull.Create);
  Result := TJSONObject.ParseJSONValue(AValue.ToJSON);
  if not Assigned(Result) then
    Result := TJSONNull.Create;
end;

function NewObjectSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('properties', TJSONObject.Create);
  Result.AddPair('additionalProperties', TJSONBool.Create(False));
end;

function SchemaProperties(const ASchema: TJSONObject): TJSONObject;
begin
  Result := ASchema.Values['properties'] as TJSONObject;
end;

procedure RequireSchemaProperty(
  const ASchema: TJSONObject;
  const AName: string
);
var
  LRequired: TJSONArray;
begin
  LRequired := ASchema.Values['required'] as TJSONArray;
  if not Assigned(LRequired) then
  begin
    LRequired := TJSONArray.Create;
    ASchema.AddPair('required', LRequired);
  end;
  LRequired.Add(AName);
end;

procedure AddStringProperty(
  const ASchema: TJSONObject;
  const AName,
  ADescription: string;
  const ARequired: Boolean = False;
  const ADefault: string = '';
  const AEnum: TArray<string> = nil
);
var
  LProperty: TJSONObject;
begin
  LProperty := TJSONObject.Create;
  LProperty.AddPair('type', 'string');
  if ADescription <> '' then
    LProperty.AddPair('description', ADescription);
  if ADefault <> '' then
    LProperty.AddPair('default', ADefault);
  if Length(AEnum) > 0 then
    LProperty.AddPair('enum', JsonStringArray(AEnum));
  SchemaProperties(ASchema).AddPair(AName, LProperty);
  if ARequired then
    RequireSchemaProperty(ASchema, AName);
end;

procedure AddBooleanProperty(
  const ASchema: TJSONObject;
  const AName,
  ADescription: string;
  const ADefault: Boolean;
  const ARequired: Boolean = False
);
var
  LProperty: TJSONObject;
begin
  LProperty := TJSONObject.Create;
  LProperty.AddPair('type', 'boolean');
  if ADescription <> '' then
    LProperty.AddPair('description', ADescription);
  LProperty.AddPair('default', TJSONBool.Create(ADefault));
  SchemaProperties(ASchema).AddPair(AName, LProperty);
  if ARequired then
    RequireSchemaProperty(ASchema, AName);
end;

procedure AddIntegerProperty(
  const ASchema: TJSONObject;
  const AName,
  ADescription: string;
  const ADefault,
  AMinimum,
  AMaximum: Integer;
  const ARequired: Boolean = False
);
var
  LProperty: TJSONObject;
begin
  LProperty := TJSONObject.Create;
  LProperty.AddPair('type', 'integer');
  if ADescription <> '' then
    LProperty.AddPair('description', ADescription);
  LProperty.AddPair('default', TJSONNumber.Create(ADefault));
  LProperty.AddPair('minimum', TJSONNumber.Create(AMinimum));
  LProperty.AddPair('maximum', TJSONNumber.Create(AMaximum));
  SchemaProperties(ASchema).AddPair(AName, LProperty);
  if ARequired then
    RequireSchemaProperty(ASchema, AName);
end;

function NewTool(
  const AName,
  ATitle,
  ADescription: string;
  const ASchema: TJSONObject;
  const AHints: TCodexToolHints
): TJSONObject;
var
  LAnnotations: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('title', ATitle);
  Result.AddPair('description', ADescription);
  Result.AddPair('inputSchema', ASchema);
  LAnnotations := TJSONObject.Create;
  LAnnotations.AddPair('readOnlyHint', TJSONBool.Create(AHints.ReadOnly));
  LAnnotations.AddPair(
    'destructiveHint',
    TJSONBool.Create(AHints.Destructive)
  );
  LAnnotations.AddPair(
    'idempotentHint',
    TJSONBool.Create(AHints.Idempotent)
  );
  LAnnotations.AddPair('openWorldHint', TJSONBool.Create(AHints.OpenWorld));
  Result.AddPair('annotations', LAnnotations);
end;

function NoArgumentsSchema: TJSONObject;
begin
  Result := NewObjectSchema;
end;

function ProjectArgumentSchema: TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(
    Result,
    'project',
    'Optional project name or absolute project path. The active project is used when omitted.'
  );
end;

function PathArgumentSchema(const ADescription: string): TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(Result, 'path', ADescription, True);
end;

function DirectoryListSchema(const AReadOnly: Boolean): TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(
    Result,
    'path',
    IfThen(
      AReadOnly,
      'Directory inside one of the configured read-only Delphi reference roots.',
      'Directory inside an open project. Omit it to use the active project directory.'
    ),
    AReadOnly
  );
  AddStringProperty(
    Result,
    'search_pattern',
    'File-name pattern accepted by TDirectory.GetFiles, without a directory component.',
    False,
    '*'
  );
  AddBooleanProperty(
    Result,
    'recursive',
    'Search subdirectories as well.',
    False
  );
  AddIntegerProperty(
    Result,
    'max_results',
    'Maximum number of returned paths.',
    5000,
    1,
    20000
  );
end;

function ReadFileSchema: TJSONObject;
begin
  Result := PathArgumentSchema(
    'Absolute or project-relative file path. For open files, the unsaved IDE editor buffer is authoritative.'
  );
end;

function WriteFileSchema: TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(
    Result,
    'path',
    'Absolute or active-project-relative workspace file path.',
    True
  );
  AddStringProperty(
    Result,
    'content',
    'Complete replacement text. Empty text is allowed.',
    True
  );
  AddStringProperty(
    Result,
    'expected_sha256',
    'Optional SHA-256 from ide_read_file. The write is rejected if the current buffer or disk text differs.'
  );
  AddBooleanProperty(
    Result,
    'save',
    'When an IDE editor buffer exists, save it to disk after replacing its contents.',
    False
  );
  AddBooleanProperty(
    Result,
    'create',
    'Allow creation of a new disk file inside an open project directory.',
    False
  );
end;

function CreateProjectSchema: TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(
    Result,
    'directory',
    'Target directory for the new project.',
    True
  );
  AddStringProperty(Result, 'name', 'Project name without extension.', True);
  AddStringProperty(
    Result,
    'kind',
    'Project kind.',
    False,
    'console',
    ['console', 'vcl']
  );
end;

function OpenProjectSchema: TJSONObject;
begin
  Result := PathArgumentSchema('Absolute path of an existing Delphi project file.');
end;

function SaveProjectSchema: TJSONObject;
begin
  Result := ProjectArgumentSchema;
  AddBooleanProperty(
    Result,
    'save_modules',
    'Save all modified project modules before saving the project.',
    True
  );
end;

function RemoveProjectSchema: TJSONObject;
begin
  Result := ProjectArgumentSchema;
  AddBooleanProperty(
    Result,
    'close',
    'Close the project module after removing it from the project group.',
    True
  );
  AddBooleanProperty(
    Result,
    'force',
    'Discard unsaved changes when closing the removed project.',
    False
  );
end;

function CreateUnitSchema(const AFormUnit: Boolean): TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(
    Result,
    'project',
    'Optional project name or path. The active project is used when omitted.'
  );
  AddStringProperty(Result, 'unit_name', 'Delphi unit identifier.', True);
  AddStringProperty(
    Result,
    'file_name',
    'Optional .pas file name. Relative paths are resolved inside the project directory.'
  );
  AddStringProperty(
    Result,
    'source',
    'Optional complete Pascal source. A compilable default skeleton is generated when omitted.'
  );
  if AFormUnit then
  begin
    AddStringProperty(Result, 'form_name', 'Form class identifier, for example MainForm.');
    AddStringProperty(
      Result,
      'ancestor',
      'Form ancestor class.',
      False,
      'TForm'
    );
    AddStringProperty(
      Result,
      'dfm_source',
      'Optional complete textual DFM source. A default form resource is generated when omitted.'
    );
    AddBooleanProperty(
      Result,
      'main_form',
      'Create the form as the project main form.',
      False
    );
  end;
end;

function CloseFileSchema: TJSONObject;
begin
  Result := PathArgumentSchema('Open module or editor file path.');
  AddBooleanProperty(
    Result,
    'force',
    'Discard unsaved changes instead of asking the user.',
    False
  );
end;

function RemoveFileSchema: TJSONObject;
begin
  Result := PathArgumentSchema('File to remove from the project. The disk file is not deleted.');
  AddStringProperty(
    Result,
    'project',
    'Optional project name or path. The active project is used when omitted.'
  );
end;

function CompileSchema(const AGroup: Boolean): TJSONObject;
begin
  Result := NewObjectSchema;
  if not AGroup then
    AddStringProperty(
      Result,
      'project',
      'Optional project name or path. The active project is used when omitted.'
    );
  AddStringProperty(
    Result,
    'mode',
    'make compiles changed units; build rebuilds the project.',
    False,
    'make',
    ['make', 'build']
  );
  AddBooleanProperty(
    Result,
    'clear_messages',
    'Clear existing compiler messages before the first build.',
    True
  );
end;

function RunProjectSchema: TJSONObject;
begin
  Result := ProjectArgumentSchema;
  AddBooleanProperty(
    Result,
    'debugger',
    'Run through the Delphi debugger. When false, the local Windows target executable is launched directly.',
    True
  );
  AddBooleanProperty(
    Result,
    'build_first',
    'Compile the selected project before starting it.',
    True
  );
end;

function MessageBoxSchema: TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(Result, 'title', 'Dialog title.', False, 'Codex');
  AddStringProperty(Result, 'text', 'Message shown to the IDE user.', True);
  AddStringProperty(
    Result,
    'kind',
    'Message icon.',
    False,
    'information',
    ['information', 'warning', 'error', 'confirmation']
  );
  AddStringProperty(
    Result,
    'buttons',
    'Button set.',
    False,
    'ok',
    ['ok', 'ok_cancel', 'yes_no', 'yes_no_cancel']
  );
end;

function InputBoxSchema: TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(Result, 'title', 'Dialog title.', False, 'Codex');
  AddStringProperty(Result, 'prompt', 'Prompt shown to the IDE user.', True);
  AddStringProperty(Result, 'default', 'Initial input value.');
end;

function BalloonSchema: TJSONObject;
begin
  Result := NewObjectSchema;
  AddStringProperty(Result, 'title', 'Balloon title.', False, 'Codex');
  AddStringProperty(Result, 'text', 'Balloon text.', True);
  AddIntegerProperty(
    Result,
    'timeout_ms',
    'Display duration in milliseconds.',
    5000,
    500,
    30000
  );
end;

function BuildTools: TJSONArray;
const
  CReadOnly = True;
  CReadWrite = False;
var
  LHints: TCodexToolHints;
begin
  Result := TJSONArray.Create;

  LHints := TCodexToolHints.Create(CReadOnly, False, True, False);
  Result.AddElement(NewTool(
    'ide_status',
    'Delphi IDE MCP status',
    'Returns package settings, registration status, runtime state and available read-only roots.',
    NoArgumentsSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_list_open_files',
    'List open IDE files',
    'Lists all currently open project, source and form files, including modified editor buffers.',
    NoArgumentsSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_list_projects',
    'List projects',
    'Lists the projects and project paths in the current project group, or the single open project.',
    NoArgumentsSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_list_project_files',
    'List project units and files',
    'Lists all project members and matching PAS/DFM/FMX companion files.',
    ProjectArgumentSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_list_directory_files',
    'List files in a project directory',
    'Uses TDirectory.GetFiles inside a currently open project directory.',
    DirectoryListSchema(False),
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_read_file',
    'Read a workspace file',
    'Reads a writable workspace file. If it is loaded in the IDE, reads the unsaved editor buffer rather than stale disk contents.',
    ReadFileSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_list_readonly_roots',
    'List Delphi reference roots',
    'Lists Delphi source, samples, GetIt repositories and configured additional read-only directories.',
    NoArgumentsSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_list_readonly_files',
    'List files in a read-only root',
    'Lists files beneath an approved read-only Delphi reference root.',
    DirectoryListSchema(True),
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_read_readonly_file',
    'Read a Delphi reference file',
    'Reads a file beneath an approved read-only Delphi source, sample, GetIt or additional reference root.',
    ReadFileSchema,
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, True, False, False);
  Result.AddElement(NewTool(
    'ide_write_file',
    'Write a workspace file',
    'Replaces a workspace file. Open files are changed through an undoable IDE editor writer; optional SHA-256 optimistic concurrency is supported.',
    WriteFileSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_create_project',
    'Create a Delphi project',
    'Creates a console or VCL project and adds it to the current project group.',
    CreateProjectSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_open_project',
    'Open a Delphi project',
    'Opens an existing Delphi project in the IDE and current group.',
    OpenProjectSchema,
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, False, True, False);
  Result.AddElement(NewTool(
    'ide_save_project',
    'Save a Delphi project',
    'Saves the selected project and, optionally, all modified modules.',
    SaveProjectSchema,
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, True, False, False);
  Result.AddElement(NewTool(
    'ide_remove_project',
    'Remove a project from the group',
    'Removes a project from the current project group without deleting its files.',
    RemoveProjectSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_create_unit',
    'Create a Delphi unit',
    'Creates a unit in the selected project.',
    CreateUnitSchema(False),
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_create_form_unit',
    'Create a Delphi form unit',
    'Creates a VCL form unit and textual DFM in the selected project.',
    CreateUnitSchema(True),
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, False, True, False);
  Result.AddElement(NewTool(
    'ide_open_file',
    'Open an IDE file',
    'Opens and shows a file in the Delphi IDE.',
    PathArgumentSchema('File path to open.'),
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_activate_file',
    'Activate an IDE file',
    'Activates an already open file, or opens it when necessary.',
    PathArgumentSchema('File path to activate.'),
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, True, False, False);
  Result.AddElement(NewTool(
    'ide_close_file',
    'Close an IDE file',
    'Closes an IDE module or editor file.',
    CloseFileSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_remove_file_from_project',
    'Remove a file from a project',
    'Removes a file from a project without deleting it from disk.',
    RemoveFileSchema,
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, False, True, False);
  Result.AddElement(NewTool(
    'ide_show_form_as_text',
    'Show a form as text',
    'Switches a VCL DFM to textual editor mode so its resource text can be read or changed.',
    PathArgumentSchema('PAS or DFM path belonging to the form.'),
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_compile_project',
    'Compile a project',
    'Makes or rebuilds a selected project through IOTAProjectBuilder.',
    CompileSchema(False),
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_compile_project_group',
    'Compile all projects',
    'Makes or rebuilds every project in the current project group.',
    CompileSchema(True),
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, True, False, True);
  Result.AddElement(NewTool(
    'ide_run_project',
    'Run a project',
    'Builds and starts a selected project with the Delphi debugger or directly without a debugger.',
    RunProjectSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_stop_project',
    'Stop the running project',
    'Stops the current Delphi debug process or a process launched by ide_run_project without the debugger.',
    NoArgumentsSchema,
    LHints
  ));

  LHints := TCodexToolHints.Create(CReadWrite, False, False, True);
  Result.AddElement(NewTool(
    'ide_message_box',
    'Show a message box',
    'Shows a modal message box in the IDE and returns the selected button.',
    MessageBoxSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_input_box',
    'Ask the IDE user for text',
    'Shows an InputQuery dialog in the IDE and returns whether it was accepted and the entered value.',
    InputBoxSchema,
    LHints
  ));
  Result.AddElement(NewTool(
    'ide_balloon_hint',
    'Show an IDE balloon hint',
    'Shows a temporary non-modal balloon hint attached to the IDE main window.',
    BalloonSchema,
    LHints
  ));
end;

function RpcEnvelope(const AId: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', CloneJsonValue(AId));
end;

function RpcResult(
  const AId: TJSONValue;
  const AResult: TJSONValue
): TJSONObject;
begin
  Result := RpcEnvelope(AId);
  Result.AddPair('result', AResult);
end;

function RpcError(
  const AId: TJSONValue;
  const ACode: Integer;
  const AMessage: string;
  const AData: string = ''
): TJSONObject;
var
  LError: TJSONObject;
begin
  Result := RpcEnvelope(AId);
  LError := TJSONObject.Create;
  LError.AddPair('code', TJSONNumber.Create(ACode));
  LError.AddPair('message', AMessage);
  if AData <> '' then
    LError.AddPair('data', AData);
  Result.AddPair('error', LError);
end;

function IsSupportedHandshakeProtocol(const AVersion: string): Boolean;
begin
  Result := SameText(AVersion, '2025-03-26') or
    SameText(AVersion, '2025-06-18') or
    SameText(AVersion, '2025-11-25');
end;

function SelectHandshakeProtocol(const ARequestedVersion: string): string;
begin
  if IsSupportedHandshakeProtocol(Trim(ARequestedVersion)) then
    Result := Trim(ARequestedVersion)
  else
    Result := CCodexMCPProtocolVersion;
end;

function InitializeResult(const AParams: TJSONObject): TJSONObject;
var
  LCapabilities: TJSONObject;
  LProtocolVersion: string;
  LServerInfo: TJSONObject;
  LTools: TJSONObject;
begin
  LProtocolVersion := JsonString(
    AParams,
    'protocolVersion',
    CCodexMCPProtocolVersion
  );
  LProtocolVersion := SelectHandshakeProtocol(LProtocolVersion);

  Result := TJSONObject.Create;
  Result.AddPair('protocolVersion', LProtocolVersion);
  LCapabilities := TJSONObject.Create;
  LTools := TJSONObject.Create;
  LTools.AddPair('listChanged', TJSONBool.Create(False));
  LCapabilities.AddPair('tools', LTools);
  Result.AddPair('capabilities', LCapabilities);

  LServerInfo := TJSONObject.Create;
  LServerInfo.AddPair('name', CCodexMCPServerId);
  LServerInfo.AddPair('title', CCodexMCPProductName);
  LServerInfo.AddPair('version', CCodexMCPVersion);
  Result.AddPair('serverInfo', LServerInfo);
  Result.AddPair(
    'instructions',
    'The server controls the currently running Delphi 13 IDE. Read editor-backed files before writing, use expected_sha256 for concurrent edits, and treat Delphi source/sample/GetIt roots as read-only.'
  );
end;

function ToolsListResult: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('tools', BuildTools);
end;

function ToolCallResult(const AParams: TJSONObject): TJSONObject;
var
  LArguments: TJSONObject;
  LContent: TJSONArray;
  LContentItem: TJSONObject;
  LName: string;
  LOwnsArguments: Boolean;
  LStructured: TJSONValue;
begin
  LName := RequireJsonString(AParams, 'name');
  LArguments := JsonObject(AParams, 'arguments');
  LOwnsArguments := not Assigned(LArguments);
  if LOwnsArguments then
    LArguments := TJSONObject.Create;
  try
    try
      LStructured := TCodexMCPToolDispatcher.Execute(LName, LArguments);
      try
        Result := TJSONObject.Create;
        LContent := TJSONArray.Create;
        LContentItem := TJSONObject.Create;
        LContentItem.AddPair('type', 'text');
        LContentItem.AddPair('text', LStructured.ToJSON);
        LContent.AddElement(LContentItem);
        Result.AddPair('content', LContent);
        Result.AddPair('structuredContent', CloneJsonValue(LStructured));
        Result.AddPair('isError', TJSONBool.Create(False));
      finally
        LStructured.Free;
      end;
    except
      on E: Exception do
      begin
        Result := TJSONObject.Create;
        LContent := TJSONArray.Create;
        LContentItem := TJSONObject.Create;
        LContentItem.AddPair('type', 'text');
        LContentItem.AddPair('text', E.ClassName + ': ' + E.Message);
        LContent.AddElement(LContentItem);
        Result.AddPair('content', LContent);
        Result.AddPair('structuredContent', JsonFailure(E.Message));
        Result.AddPair('isError', TJSONBool.Create(True));
      end;
    end;
  finally
    if LOwnsArguments then
      LArguments.Free;
  end;
end;

function EmptyObject: TJSONObject;
begin
  Result := TJSONObject.Create;
end;

function DispatchRequest(const ARequest: TJSONObject): TJSONObject;
var
  LId: TJSONValue;
  LMethod: string;
  LParams: TJSONObject;
  LResultValue: TJSONValue;
begin
  Result := nil;
  if not Assigned(ARequest) then
    Exit(RpcError(nil, -32600, 'Invalid Request'));
  if not SameText(JsonString(ARequest, 'jsonrpc'), '2.0') then
    Exit(RpcError(ARequest.Values['id'], -32600, 'Invalid Request'));

  LMethod := JsonString(ARequest, 'method');
  if LMethod = '' then
    Exit(RpcError(ARequest.Values['id'], -32600, 'Invalid Request'));
  LId := ARequest.Values['id'];
  LParams := JsonObject(ARequest, 'params');

  if StartsText('notifications/', LMethod) then
    Exit(nil);

  try
    if SameText(LMethod, 'initialize') then
      LResultValue := InitializeResult(LParams)
    else if SameText(LMethod, 'ping') then
      LResultValue := EmptyObject
    else if SameText(LMethod, 'tools/list') then
      LResultValue := ToolsListResult
    else if SameText(LMethod, 'tools/call') then
    begin
      if not Assigned(LParams) then
        Exit(RpcError(LId, -32602, 'Invalid params'));
      LResultValue := ToolCallResult(LParams);
    end
    else
      Exit(RpcError(LId, -32601, 'Method not found', LMethod));
    Result := RpcResult(LId, LResultValue);
  except
    on E: EArgumentException do
      Result := RpcError(LId, -32602, 'Invalid params', E.Message);
    on E: Exception do
      Result := RpcError(LId, -32603, 'Internal error', E.Message);
  end;
end;

class function TCodexMCPProtocol.HandleRequest(
  const ARequestBody: string;
  out AResponseBody: string;
  out AHttpStatus: Integer
): Boolean;
var
  LRequest: TJSONValue;
  LResponse: TJSONObject;
begin
  AResponseBody := '';
  AHttpStatus := 200;
  LRequest := nil;
  LResponse := nil;
  try
    try
      LRequest := TJSONObject.ParseJSONValue(ARequestBody);
      if not (LRequest is TJSONObject) then
      begin
        LResponse := RpcError(nil, -32700, 'Parse error');
        AResponseBody := LResponse.ToJSON;
        Exit(True);
      end;
      LResponse := DispatchRequest(TJSONObject(LRequest));
      if not Assigned(LResponse) then
      begin
        AHttpStatus := 202;
        Exit(False);
      end;
      AResponseBody := LResponse.ToJSON;
      Result := True;
    except
      on E: Exception do
      begin
        FreeAndNil(LResponse);
        LResponse := RpcError(nil, -32700, 'Parse error', E.Message);
        AResponseBody := LResponse.ToJSON;
        Result := True;
      end;
    end;
  finally
    LResponse.Free;
    LRequest.Free;
  end;
end;

end.
