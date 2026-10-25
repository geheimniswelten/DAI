"""Read-only DelphiLSP protocol probe using an isolated process and a virtual unit.

Run with Python 3, optionally passing --bds-root <RAD Studio installation>.
No source/configuration files are created; no existing IDE process is contacted.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time
import uuid


class ProbeError(RuntimeError):
    pass


class DelphiLSPProbe:
    def __init__(self, executable: Path) -> None:
        creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        self.process = subprocess.Popen(
            [str(executable)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=creation_flags,
        )
        self.messages: queue.Queue[object] = queue.Queue()
        self.next_request = 0
        self.initialized = False
        self.open_uri: str | None = None
        self.stderr_tail: list[str] = []
        threading.Thread(target=self._read_messages, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _read_messages(self) -> None:
        try:
            while True:
                content_length = None
                while True:
                    line = self.process.stdout.readline()
                    if not line:
                        raise ProbeError("DelphiLSP closed stdout.")
                    if line in (b"\r\n", b"\n"):
                        break
                    if line.lower().startswith(b"content-length:"):
                        content_length = int(line.split(b":", 1)[1].strip())
                if content_length is None or not 0 <= content_length <= 8 * 1024 * 1024:
                    raise ProbeError("Invalid/missing LSP Content-Length.")
                payload = self.process.stdout.read(content_length)
                if len(payload) != content_length:
                    raise ProbeError("Incomplete LSP message.")
                self.messages.put(json.loads(payload))
        except Exception as error:
            self.messages.put(error)

    def _read_stderr(self) -> None:
        try:
            for line in self.process.stderr:
                self.stderr_tail.append(line.decode("utf-8", errors="replace").rstrip()[:2000])
                del self.stderr_tail[:-16]
        except (OSError, ValueError):
            pass

    def send(self, message: dict) -> None:
        payload = json.dumps(message, ensure_ascii=False).encode("utf-8")
        header = f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii")
        self.process.stdin.write(header + payload)
        self.process.stdin.flush()

    def notify(self, method: str, params: object) -> None:
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method: str, params: object, timeout: float) -> dict:
        self.next_request += 1
        request_id = self.next_request
        self.send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ProbeError(f"Timed out waiting for {method} after {timeout:g} seconds.")
            try:
                message = self.messages.get(timeout=remaining)
            except queue.Empty as error:
                raise ProbeError(f"Timed out waiting for {method} after {timeout:g} seconds.") from error
            if isinstance(message, Exception):
                raise ProbeError(str(message)) from message
            if not isinstance(message, dict):
                raise ProbeError("LSP response is not an object.")
            if message.get("id") == request_id and "method" not in message:
                if "error" in message:
                    raise ProbeError(f"{method}: {json.dumps(message['error'])}")
                return message
            if "id" in message and "method" in message:
                # The isolated probe exposes no workspace service or configuration store.
                self.send({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "error": {"code": -32601, "message": "Probe does not implement this client method."},
                })

    def close(self) -> None:
        # All process operations below target only the Popen object created by this probe.
        if self.process.poll() is None:
            if self.open_uri:
                try:
                    self.notify("textDocument/didClose", {"textDocument": {"uri": self.open_uri}})
                except (OSError, ValueError):
                    pass
            if self.initialized:
                try:
                    self.request("shutdown", None, 2)
                except (ProbeError, OSError, ValueError):
                    pass
            try:
                self.notify("exit", None)
            except (OSError, ValueError):
                pass
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            try:
                stream.close()
            except (OSError, ValueError):
                pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ProbeError(message)


def flatten(nodes: list[dict]) -> list[dict]:
    result = []
    for node in nodes:
        require(isinstance(node, dict), "Document symbol is not an object.")
        result.append(node)
        children = node.get("children", [])
        require(isinstance(children, list), "Symbol children must be an array.")
        result.extend(flatten(children))
    return result


def validate_range(node: dict, key: str) -> None:
    value = node.get(key)
    require(isinstance(value, dict), f"Missing {key} for {node.get('name')}.")
    start = value.get("start", {})
    end = value.get("end", {})
    for position in (start, end):
        require(isinstance(position.get("line"), int) and position["line"] >= 0, "Invalid LSP line.")
        require(isinstance(position.get("character"), int) and position["character"] >= 0, "Invalid LSP character.")
    require((start["line"], start["character"]) <= (end["line"], end["character"]), "Reversed source range.")


def run(executable: Path, timeout: float) -> dict:
    virtual_name = "DAILSPProbe_" + uuid.uuid4().hex
    virtual_file = Path(tempfile.gettempdir()) / (virtual_name + ".pas")
    virtual_uri = virtual_file.as_uri()
    source = f"""unit {virtual_name};
interface
type
  TSample = class
  private
    FValue: Integer;
  public
    procedure SetValue(const AValue: Integer);
    property Value: Integer read FValue write SetValue;
  end;
function Sum(A, B: Integer): Integer;
implementation
procedure TSample.SetValue(const AValue: Integer);
begin
  FValue := AValue;
end;
function Sum(A, B: Integer): Integer;
begin
  Result := A + B;
end;
end.
"""
    probe = DelphiLSPProbe(executable)
    try:
        initialized = probe.request("initialize", {
            "processId": os.getpid(),
            "rootUri": virtual_file.parent.as_uri(),
            "capabilities": {"textDocument": {"documentSymbol": {"hierarchicalDocumentSymbolSupport": True}}},
            "initializationOptions": {
                "serverType": "agent",
                "agentCount": 1,
                "storeProjectSettings": False,
                "enableFileWatcher": False,
            },
        }, timeout)
        capabilities = initialized.get("result", {}).get("capabilities", {})
        provider = capabilities.get("documentSymbolProvider")
        require(provider is True or isinstance(provider, dict), "Server does not advertise documentSymbolProvider.")
        probe.notify("initialized", {})
        probe.initialized = True
        probe.notify("textDocument/didOpen", {
            "textDocument": {"uri": virtual_uri, "languageId": "pascal", "version": 1, "text": source},
        })
        probe.open_uri = virtual_uri
        response = probe.request("textDocument/documentSymbol", {"textDocument": {"uri": virtual_uri}}, timeout)
        roots = response.get("result")
        require(isinstance(roots, list) and len(roots) > 0, "No document symbols returned.")
        nodes = flatten(roots)
        classes = [node for node in nodes if node.get("name") == "TSample" and node.get("kind") == 5]
        require(len(classes) == 1, "Expected one TSample class symbol.")
        members = flatten(classes[0].get("children", []))
        require(any(node.get("name", "").startswith("FValue:") for node in members), "Missing field symbol.")
        require(any(node.get("name", "").startswith("SetValue(") and node.get("kind") == 6 for node in members), "Missing method signature.")
        require(any(node.get("name", "").startswith("Value:") and node.get("kind") == 7 for node in members), "Missing property symbol.")
        require(any(node.get("name", "").startswith("Sum(") for node in nodes), "Missing global function signature.")
        for node in nodes:
            validate_range(node, "range")
            validate_range(node, "selectionRange")
        require(not virtual_file.exists(), "Virtual probe file unexpectedly exists on disk.")
        return {
            "executable": str(executable),
            "documentSymbolProvider": provider,
            # Absence in this response is a runtime observation, not a claim about all versions.
            "workspaceSymbolProvider": capabilities.get("workspaceSymbolProvider", "not advertised"),
            "symbol_count": len(nodes),
            "class_members": [node["name"] for node in members],
            "ranges_validated": len(nodes),
            "virtual_file_written": False,
        }
    finally:
        probe.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bds-root", type=Path, default=Path(os.environ.get("BDS") or r"C:\Program Files (x86)\Embarcadero\Studio\37.0"))
    parser.add_argument("--timeout", type=float, default=12.0, help="Timeout per LSP request in seconds (1..60).")
    args = parser.parse_args()
    if not 1 <= args.timeout <= 60:
        parser.error("--timeout must be between 1 and 60 seconds")
    executable = args.bds_root / "bin" / "DelphiLSP.exe"
    if not executable.is_file():
        parser.error(f"DelphiLSP executable not found: {executable}")
    try:
        print(json.dumps(run(executable, args.timeout), ensure_ascii=False, indent=2))
        print("DelphiLSP protocol probe passed; isolated process closed.")
        return 0
    except (ProbeError, OSError, subprocess.SubprocessError) as error:
        print(f"DelphiLSP protocol probe failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
