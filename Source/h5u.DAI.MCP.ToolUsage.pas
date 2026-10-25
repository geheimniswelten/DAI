unit h5u.DAI.MCP.ToolUsage;

interface

uses
  System.JSON;

type
  TDAIMCPToolUsage = class sealed
  public
    class function TryClassify(const AName: string; const AArguments: TJSONObject; out ACanonicalName: string; out AShowsActivity: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

type
  TDAIToolActivity = (taQuiet, taActive, taDirectory, taProjectContext);

  TDAIToolUsageDefinition = record
    Name: string;
    Activity: TDAIToolActivity;
  end;

const
  // Keep this catalog explicit: an unrecognized client-supplied name must never become a persistent usage key.
  // Test.ToolUsage verifies exact coverage of the production ListTools catalog.
  CToolUsageDefinitions: array[0..86] of TDAIToolUsageDefinition = (
    (Name: 'breakpoint_remove'; Activity: taActive),
    (Name: 'breakpoint_set'; Activity: taActive),
    (Name: 'breakpoints_list'; Activity: taActive),
    (Name: 'clients_register'; Activity: taActive),
    (Name: 'clients_registration_status'; Activity: taQuiet),
    (Name: 'clients_unregister'; Activity: taActive),
    (Name: 'code_definition'; Activity: taActive),
    (Name: 'code_hover'; Activity: taActive),
    (Name: 'code_insight_status'; Activity: taQuiet),
    (Name: 'codex_register'; Activity: taActive),
    (Name: 'codex_registration_status'; Activity: taQuiet),
    (Name: 'codex_unregister'; Activity: taActive),
    (Name: 'dcc32_execute'; Activity: taActive),
    (Name: 'debugger_control'; Activity: taActive),
    (Name: 'debugger_cursor_expression'; Activity: taActive),
    (Name: 'debugger_evaluate'; Activity: taActive),
    (Name: 'debugger_evaluation_status'; Activity: taActive),
    (Name: 'debugger_expression_ui'; Activity: taActive),
    (Name: 'debugger_modify'; Activity: taActive),
    (Name: 'debugger_stacktrace'; Activity: taActive),
    (Name: 'debugger_status'; Activity: taQuiet),
    (Name: 'debugger_threads_list'; Activity: taActive),
    (Name: 'debugger_windows_list'; Activity: taActive),
    (Name: 'directory_files_list'; Activity: taDirectory),
    (Name: 'file_activate'; Activity: taActive),
    (Name: 'file_close'; Activity: taActive),
    (Name: 'file_diagnostics'; Activity: taActive),
    (Name: 'file_open'; Activity: taActive),
    (Name: 'file_read'; Activity: taActive),
    (Name: 'file_write'; Activity: taActive),
    (Name: 'form_component_create'; Activity: taActive),
    (Name: 'form_component_move'; Activity: taActive),
    (Name: 'form_component_properties'; Activity: taActive),
    (Name: 'form_component_set_property'; Activity: taActive),
    (Name: 'form_components_search'; Activity: taActive),
    (Name: 'form_components_select'; Activity: taActive),
    (Name: 'form_designer_inspect'; Activity: taActive),
    (Name: 'form_palette_list'; Activity: taActive),
    (Name: 'form_show_as_text'; Activity: taActive),
    (Name: 'form_show_designer'; Activity: taActive),
    (Name: 'form_unit_create'; Activity: taActive),
    (Name: 'ide_ai_status'; Activity: taQuiet),
    (Name: 'ide_dialog_click'; Activity: taActive),
    (Name: 'ide_dialog_close'; Activity: taActive),
    (Name: 'ide_dialog_inspect'; Activity: taActive),
    (Name: 'ide_logs_read'; Activity: taActive),
    (Name: 'ide_status'; Activity: taQuiet),
    (Name: 'ide_window_control'; Activity: taActive),
    (Name: 'ide_windows_list'; Activity: taActive),
    (Name: 'msbuild_execute'; Activity: taActive),
    (Name: 'open_files_list'; Activity: taQuiet),
    (Name: 'options_open'; Activity: taActive),
    (Name: 'options_search'; Activity: taActive),
    (Name: 'package_install'; Activity: taActive),
    (Name: 'package_is_installed'; Activity: taQuiet),
    (Name: 'package_uninstall'; Activity: taActive),
    (Name: 'project_activate'; Activity: taActive),
    (Name: 'project_compile'; Activity: taActive),
    (Name: 'project_context'; Activity: taProjectContext),
    (Name: 'project_create'; Activity: taActive),
    (Name: 'project_directory_files_list'; Activity: taDirectory),
    (Name: 'project_file_remove'; Activity: taActive),
    (Name: 'project_files_list'; Activity: taQuiet),
    (Name: 'project_group_compile'; Activity: taActive),
    (Name: 'project_index_build'; Activity: taActive),
    (Name: 'project_index_delete'; Activity: taActive),
    (Name: 'project_index_status'; Activity: taQuiet),
    (Name: 'project_open'; Activity: taActive),
    (Name: 'project_option_remove'; Activity: taActive),
    (Name: 'project_option_set'; Activity: taActive),
    (Name: 'project_options_configurations'; Activity: taQuiet),
    (Name: 'project_options_read'; Activity: taActive),
    (Name: 'project_remove'; Activity: taActive),
    (Name: 'project_run'; Activity: taActive),
    (Name: 'project_save'; Activity: taActive),
    (Name: 'project_stop'; Activity: taActive),
    (Name: 'projects_list'; Activity: taQuiet),
    (Name: 'reference_file_read'; Activity: taActive),
    (Name: 'reference_files_list'; Activity: taDirectory),
    (Name: 'reference_roots_list'; Activity: taQuiet),
    (Name: 'source_search'; Activity: taActive),
    (Name: 'symbols_query'; Activity: taActive),
    (Name: 'symbols_search'; Activity: taActive),
    (Name: 'ui_balloon_hint'; Activity: taActive),
    (Name: 'ui_input_box'; Activity: taActive),
    (Name: 'ui_message_box'; Activity: taActive),
    (Name: 'unit_create'; Activity: taActive)
  );

class function TDAIMCPToolUsage.TryClassify(const AName: string; const AArguments: TJSONObject; out ACanonicalName: string; out AShowsActivity: Boolean): Boolean;
var
  LDefinition: TDAIToolUsageDefinition;
  LValue: TJSONValue;
begin
  ACanonicalName := '';
  AShowsActivity := False;
  for LDefinition in CToolUsageDefinitions do
    if SameText(AName, LDefinition.Name) then
    begin
      ACanonicalName := LDefinition.Name;
      case LDefinition.Activity of
        taQuiet:
          AShowsActivity := False;
        taActive:
          AShowsActivity := True;
        taDirectory:
          begin
            LValue := nil;
            if Assigned(AArguments) then
              LValue := AArguments.GetValue('content_query');
            if LValue is TJSONString then
              AShowsActivity := LValue.Value <> '';
          end;
        taProjectContext:
          begin
            // Match CallTool's ArgumentBoolean: absent/invalid values keep its True default.
            AShowsActivity := True;
            LValue := nil;
            if Assigned(AArguments) then
              LValue := AArguments.GetValue('include_compiler_options');
            if Assigned(LValue) then
              if SameText(LValue.Value, 'false') then
                AShowsActivity := False;
          end;
      end;
      Exit(True);
    end;
  Result := False;
end;

end.
