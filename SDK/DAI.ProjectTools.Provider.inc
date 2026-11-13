// Include these declarations in an independently named package unit.
// Providers must be TComponents owned directly by Vcl.Forms.Application.
// Every method runs on the IDE main thread. Do not pump messages or open UI.
// Metadata methods must not connect to a backend or change application state.
// The host authorizes project reads before discovering or invoking providers.
// For write tools it authorizes project writes separately before CallToolJSON.
// Exchange JSON strings only; do not return package-owned objects or callbacks.
// Method order, calling convention and GUID are an immutable ABI contract.
type
  IDAIMCPReadOnlyExtensionV1 = interface(IInterface)
    ['{A654C97E-9D37-46BF-B96C-1A41936582DA}']
    function GetInfoJSON: string; stdcall;
    function SupportsProject(const AProjectFile: string): Boolean; stdcall;
    function GetToolsJSON(const AProjectFile: string): string; stdcall;
    function CallToolJSON(const AProjectFile, AToolName, AArgumentsJSON: string): string; stdcall;
  end;

  // Implement V2 on the component to offer both read and write tools.
  // Each V2 tool must declare a Boolean annotations.readOnlyHint.
  // annotations.destructiveHint defaults to False for reads and True for writes.
  // Metadata must be stable across authorization and invocation.
  IDAIMCPProjectExtensionV2 = interface(IDAIMCPReadOnlyExtensionV1)
    ['{189368BA-3C0D-4A6D-AB33-36AC559C2862}']
  end;
