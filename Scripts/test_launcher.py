"""Blackbox launcher tests using only copied, native bds.exe test fixtures.

No installed Delphi IDE is started, closed or terminated. Cleanup retains a
handle to each fixture and verifies its exact image path before termination.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import ctypes
from ctypes import wintypes
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import queue
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import uuid
import winreg


TOKEN = "launcher-isolated-test-token"
VERSION = "launcher-fixture-version"
POLICY_KEY = r"Software\DelphiAI\DAI"
POLICY_VALUE = "AllowIDEStartStop"
TEST_REGISTRY_PREFIX = "Software\\DelphiAI\\DAI-Launcher-Tests\\"
MODERN_META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
               "io.modelcontextprotocol/clientCapabilities": {}}
CHECKS = 0
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                               wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.restype = wintypes.DWORD
kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
advapi32.RegDeleteTreeW.argtypes = [wintypes.HKEY, wintypes.LPCWSTR]
advapi32.RegDeleteTreeW.restype = wintypes.LONG
advapi32.RegSetValueExW.argtypes = [wintypes.HKEY, wintypes.LPCWSTR, wintypes.DWORD,
                                  wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD]
advapi32.RegSetValueExW.restype = wintypes.LONG


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        raise AssertionError(message)


def same_path(first: str | Path, second: str | Path) -> bool:
    return os.path.normcase(os.path.abspath(first)) == os.path.normcase(os.path.abspath(second))


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class FixtureLease:
    """Pin exact fixture identity; never clean up by executable name or bare PID."""
    def __init__(self, pid: int, executable: Path):
        self.pid = pid
        self.executable = executable
        self.handle = kernel32.OpenProcess(0x1000 | 0x100000 | 0x0001, False, pid)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            path = ctypes.create_unicode_buffer(32768)
            length = wintypes.DWORD(len(path))
            if not kernel32.QueryFullProcessImageNameW(self.handle, 0, path, ctypes.byref(length)):
                raise ctypes.WinError(ctypes.get_last_error())
            check(same_path(path.value, executable), f"Fixture PID {pid} image path mismatch")
            times = [wintypes.FILETIME() for _ in range(4)]
            if not kernel32.GetProcessTimes(self.handle, *(ctypes.byref(value) for value in times)):
                raise ctypes.WinError(ctypes.get_last_error())
            self.creation_time = str((times[0].dwHighDateTime << 32) | times[0].dwLowDateTime)
        except BaseException:
            kernel32.CloseHandle(self.handle)
            self.handle = None
            raise

    @property
    def alive(self) -> bool:
        return kernel32.WaitForSingleObject(self.handle, 0) == 258

    def wait(self, timeout_ms: int = 5000) -> bool:
        return kernel32.WaitForSingleObject(self.handle, timeout_ms) == 0

    def close(self) -> None:
        if self.handle:
            if self.alive:
                # The handle pins the identity validated above, even if Windows
                # reuses its numeric PID after process exit.
                if not kernel32.TerminateProcess(self.handle, 195):
                    raise ctypes.WinError(ctypes.get_last_error())
                check(self.wait(), f"Fixture cleanup timed out for PID {self.pid}")
            kernel32.CloseHandle(self.handle)
            self.handle = None


class Bridge:
    def __init__(self, executable: Path, ide: Path, endpoint: str,
                 fixture_environment: dict[str, str], token: str | None = TOKEN,
                 profile: str = ""):
        self.profile = profile
        environment = {**os.environ, **fixture_environment}
        if token is None:
            environment.pop("DAI_MCP_TOKEN", None)
        else:
            environment["DAI_MCP_TOKEN"] = token
        command = [str(executable), "--launcher", "--url", endpoint, "--ide", str(ide),
                   "--dai-version", VERSION]
        if profile:
            command.extend(["--ide-profile", profile])
        self.process = subprocess.Popen(command,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            encoding="utf-8", env=environment,
            creationflags=subprocess.CREATE_NO_WINDOW)
        self.output: queue.Queue[str | None] = queue.Queue()
        self.errors: list[str] = []
        self.transcript: list[str] = []
        self.next_id = 0
        def read_output() -> None:
            for line in self.process.stdout:
                self.output.put(line)
            self.output.put(None)
        def read_errors() -> None:
            self.errors.extend(self.process.stderr.readlines())
        self.readers = [threading.Thread(target=read_output, daemon=True),
                        threading.Thread(target=read_errors, daemon=True)]
        for reader in self.readers:
            reader.start()

    def notify(self, method: str, params: dict | None = None) -> None:
        request = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            request["params"] = params
        self.process.stdin.write(json.dumps(request) + "\n")
        self.process.stdin.flush()

    def request(self, method: str, params: dict | None = None, timeout: float = 10) -> dict:
        self.next_id += 1
        request = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            request["params"] = params
        self.process.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        try:
            line = self.output.get(timeout=timeout)
        except queue.Empty:
            raise AssertionError(f"Launcher response timed out: {method}") from None
        if line is None:
            self.process.wait(timeout=2)
            self.readers[1].join(timeout=1)
        check(line is not None, f"Launcher exited before {method}: {''.join(self.errors)}")
        self.transcript.append(line)
        response = json.loads(line)
        check(response.get("jsonrpc") == "2.0" and response.get("id") == self.next_id,
              f"Unexpected STDIO response: {response}")
        return response

    def initialize(self) -> None:
        response = self.request("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "DAI isolated launcher tests", "version": "1"}})
        check(response["result"]["protocolVersion"] == "2025-11-25", "Offline initialize version")
        self.notify("notifications/initialized")
        check(self.request("ping").get("result") is not None, "Offline ping after notification")

    def tool_response(self, name: str, arguments: dict | None = None, timeout: float = 10) -> dict:
        return self.request("tools/call", {"name": name, "arguments": arguments or {}}, timeout)

    def tool(self, name: str, arguments: dict | None = None, timeout: float = 10) -> dict:
        response = self.tool_response(name, arguments, timeout)
        check("error" not in response, f"{name} JSON-RPC error: {response}")
        check(not response["result"].get("isError", False), f"{name} tool failed: {response}")
        data = response["result"].get("structuredContent")
        check(isinstance(data, dict), f"{name} missing structuredContent: {response}")
        return data

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
                raise AssertionError("Launcher did not exit at STDIN EOF") from None
        for reader in self.readers:
            reader.join(timeout=1)
        check(self.process.returncode == 0, f"Launcher failed: {''.join(self.errors)}")
        check(TOKEN not in "".join(self.transcript + self.errors), "Launcher leaked test token")


class TestEnvironment:
    def __init__(self, bridge: Path, fixture: Path, platform: str, directory: Path,
                 policy_isolated: bool = False):
        self.bridge = bridge
        self.platform = platform
        self.directory = directory
        self.ide = directory / "registered" / "bds.exe"
        self.other_ide = directory / "different-instance" / "bds.exe"
        self.marker = directory / "markers"
        for target in (self.ide, self.other_ide):
            target.parent.mkdir(parents=True)
            shutil.copyfile(fixture, target)
        self.marker.mkdir()
        self.leases: dict[int, FixtureLease] = {}
        self.bridges: list[Bridge] = []
        self.registry_root = None
        if policy_isolated:
            self.registry_root = TEST_REGISTRY_PREFIX + "{" + str(uuid.uuid4()) + "}"
            with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, self.registry_root, 0,
                                    winreg.KEY_READ | winreg.KEY_WRITE | winreg.KEY_WOW64_64KEY):
                pass

    def environment(self, mode: str = "normal", port: int | None = None) -> dict[str, str]:
        result = {
            "DAI_LAUNCHER_FIXTURE_MODE": mode,
            "DAI_LAUNCHER_FIXTURE_MARKER_DIR": str(self.marker),
            "DAI_LAUNCHER_FIXTURE_TOKEN": TOKEN,
            "DAI_LAUNCHER_FIXTURE_VERSION": VERSION,
            # Explicit empty value prevents a parent test environment leaking a port.
            "DAI_LAUNCHER_FIXTURE_PORT": "",
        }
        if port is not None:
            result["DAI_LAUNCHER_FIXTURE_PORT"] = str(port)
        if self.registry_root is not None:
            result["DAI_LAUNCHER_TEST_HKCU_ROOT"] = self.registry_root
        return result

    def policy(self, value: int | str | bytes | None = None,
               value_type: int = winreg.REG_DWORD, malformed_size: bool = False) -> None:
        check(self.registry_root is not None, "Policy changes require a test-only HKCU override")
        # Never write the real HKCU policy. The test main redirects HKCU into
        # this fresh GUID root before any productive launcher code runs.
        path = self.registry_root + "\\" + POLICY_KEY
        with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, path, 0,
                               winreg.KEY_READ | winreg.KEY_WRITE | winreg.KEY_WOW64_64KEY) as key:
            if value is None:
                try:
                    winreg.DeleteValue(key, POLICY_VALUE)
                except FileNotFoundError:
                    pass
            elif malformed_size:
                data = ctypes.c_ubyte(1)
                result = advapi32.RegSetValueExW(int(key), POLICY_VALUE, 0, winreg.REG_DWORD,
                                                ctypes.byref(data), 1)
                if result:
                    raise ctypes.WinError(result)
            else:
                winreg.SetValueEx(key, POLICY_VALUE, 0, value_type, value)

    def make_bridge(self, mode: str = "normal", port: int | None = None,
                    token: str | None = TOKEN, ide: Path | None = None,
                    profile: str = "") -> Bridge:
        endpoint_port = port if port is not None else free_port()
        bridge = Bridge(self.bridge, ide or self.ide,
                        f"http://127.0.0.1:{endpoint_port}/mcp", self.environment(mode, port), token, profile)
        self.bridges.append(bridge)
        bridge.initialize()
        return bridge

    def adopt(self, pid: int, executable: Path | None = None) -> FixtureLease:
        if pid not in self.leases:
            self.leases[pid] = FixtureLease(pid, executable or self.ide)
        return self.leases[pid]

    def wait_ready(self, pid: int, executable: Path | None = None) -> FixtureLease:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if (self.marker / f"ready-{pid}.txt").exists():
                return self.adopt(pid, executable)
            time.sleep(0.02)
        raise AssertionError(f"Fixture ready marker missing: {pid}")

    def launch_other(self) -> FixtureLease:
        process = subprocess.Popen([str(self.other_ide)], env={**os.environ, **self.environment()},
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        return self.wait_ready(process.pid, self.other_ide)

    def close(self) -> None:
        errors = []
        for bridge in self.bridges:
            try:
                bridge.close()
            except BaseException as error:
                errors.append(error)
        # Adopt only marker records belonging to this run and its two exact paths,
        # including children started just before a test assertion failed.
        for marker in self.marker.glob("ready-*.txt"):
            pid = int(marker.stem.partition("-")[2])
            if pid in self.leases:
                continue
            path = marker.read_text(encoding="utf-8-sig").splitlines()[0]
            if not any(same_path(path, candidate) for candidate in (self.ide, self.other_ide)):
                continue
            try:
                self.adopt(pid, Path(path))
            except OSError:
                pass  # Child already exited; no bare-PID fallback is permitted.
        for lease in self.leases.values():
            lease.close()
        if self.registry_root is not None:
            check(self.registry_root.startswith(TEST_REGISTRY_PREFIX), "Registry cleanup stays in the GUID test root")
            uuid.UUID(self.registry_root[len(TEST_REGISTRY_PREFIX):])
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, self.registry_root, 0,
                                winreg.KEY_READ | winreg.KEY_WRITE | winreg.KEY_WOW64_64KEY) as key:
                result = advapi32.RegDeleteTreeW(int(key), None)
                if result:
                    raise ctypes.WinError(result)
            winreg.DeleteKeyEx(winreg.HKEY_CURRENT_USER, self.registry_root, winreg.KEY_WOW64_64KEY)
            self.registry_root = None
        if errors:
            raise errors[0]


def check_status(status: dict, env: TestEnvironment, fixture: FixtureLease | None = None,
                 profile: str = "") -> None:
    check(status["registered_dai_version"] == VERSION, "Registered DAI version retained")
    check(bool(status["helper_version"]), "Helper reports its own version")
    policy = status["lifecycle_control"]
    check(isinstance(policy["allowed"], bool) and isinstance(policy["reason"], str), "Lifecycle permission is reported")
    check(policy["scope"] == "windows_user", "Lifecycle permission applies to this Windows user")
    registered = status["registered_ide"]
    check(same_path(registered["executable"], env.ide), "Status retains exact registered IDE path")
    check(registered["exists"] is True, "Registered fixture exists")
    expected_architecture = "Win64" if env.platform == "Win64" else "Win32"
    check(registered["architecture"] in (expected_architecture, expected_architecture.lower(),
          "x64" if env.platform == "Win64" else "x86"), f"Fixture PE architecture: {registered}")
    check(registered["profile"] == profile, "IDE profile retained")
    check(isinstance(status["running_ides"], list), "Running IDEs are a list")
    for process in status["running_ides"]:
        check(all(key in process for key in ("process_id", "executable", "creation_time",
              "architecture", "ide_version", "file_version", "delphi_version", "matches_registered_ide")),
              f"Process identity fields missing: {process}")
    if fixture:
        matches = [process for process in status["running_ides"] if process["process_id"] == fixture.pid]
        check(len(matches) == 1 and matches[0]["matches_registered_ide"], "Registered fixture enumerated once")
        check(matches[0]["creation_time"] == fixture.creation_time, "Raw FILETIME identifies fixture")
        check(status["ide_running"] is True, "Registered fixture is running")
        check(status["registered_ide_running"] is True, "Exact registered executable is running")


def invalid_arguments(bridge: Bridge) -> None:
    for name, arguments in (
        ("delphi_status", {"extra": True}),
        ("delphi_start", {"timeout_ms": -1}),
        ("delphi_start", {"timeout_ms": 30001}),
        ("delphi_start", {"timeout_ms": "100"}),
        ("delphi_start", {"other": True}),
        ("delphi_stop", {"mode": "kill"}),
        ("delphi_stop", {"process_id": 1}),
        ("delphi_stop", {"process_id": "1", "creation_time": "1"}),
        ("delphi_stop", {"process_id": 4294967296, "creation_time": "1"}),
        ("delphi_stop", {"process_id": 1, "creation_time": "not-a-filetime"}),
        ("delphi_stop", {"creation_time": "1"}),
        ("delphi_stop", {"timeout_ms": 30001}),
    ):
        response = bridge.tool_response(name, arguments)
        check(response.get("error", {}).get("code") == -32602,
              f"Invalid arguments not rejected as -32602: {name}/{arguments}: {response}")


def check_rejected_target(bridge: Bridge, lease: FixtureLease, creation_time: str) -> None:
    response = bridge.tool_response("delphi_stop", {
        "mode": "terminate", "process_id": lease.pid,
        "creation_time": creation_time, "timeout_ms": 100})
    check(response.get("result", {}).get("isError") is True, f"Unsafe stop target not rejected: {response}")
    check(lease.alive, "Rejected target remains alive")


def run_offline(env: TestEnvironment) -> None:
    bridge = env.make_bridge()
    tools = bridge.request("tools/list")["result"]["tools"]
    check({tool["name"] for tool in tools} == {"delphi_status", "delphi_start", "delphi_stop"},
          f"Offline tools: {tools}")
    check_status(bridge.tool("delphi_status"), env)
    check(bridge.tool("delphi_status")["dai"]["state"] == "unreachable", "Offline endpoint classified")
    no_token = env.make_bridge(token=None)
    check_status(no_token.tool("delphi_status"), env)
    check(no_token.tool("delphi_stop", {"timeout_ms": 100})["outcome"] == "not_running",
          "OS launcher functions remain available without token")
    profile_bridge = env.make_bridge(profile="DAI-Isolated-Launcher-Test")
    check_status(profile_bridge.tool("delphi_status"), env, profile=profile_bridge.profile)
    response = profile_bridge.tool_response("delphi_stop", {"timeout_ms": 100})
    check(response.get("error", {}).get("code") == -32602,
          "Profile selection requires explicit process identity for stop")
    discovery = bridge.request("server/discover", {"_meta": MODERN_META})
    check("2026-07-28" in discovery["result"]["supportedVersions"], "Offline modern discovery")
    modern_tools = bridge.request("tools/list", {"_meta": MODERN_META})["result"]
    check(modern_tools["resultType"] == "complete" and len(modern_tools["tools"]) == 3,
          "Modern offline tool discovery")
    modern_status = bridge.request("tools/call", {"name": "delphi_status", "arguments": {}, "_meta": MODERN_META})["result"]
    check(modern_status["resultType"] == "complete", "Modern offline tool result metadata")
    check_status(modern_status["structuredContent"], env)
    invalid_arguments(bridge)
    check(bridge.tool("delphi_stop", {"timeout_ms": 100})["outcome"] == "not_running", "Stop while offline")

    started = bridge.tool("delphi_start", {"timeout_ms": 150})
    check(started["started"] is True and started["outcome"] == "ide_running", f"Offline start: {started}")
    lease = env.wait_ready(started["process_id"])
    check(started["creation_time"] == lease.creation_time and not started["dai_ready"], "Start identity and readiness")
    check_status(bridge.tool("delphi_status"), env, lease)
    second = bridge.tool("delphi_start", {"timeout_ms": 100})
    check(not second["started"] and second["process_id"] == lease.pid, "Repeated start avoids duplicate IDE")
    bridge.notify("tools/call", {"name": "delphi_stop", "arguments": {
        "mode": "terminate", "process_id": lease.pid, "creation_time": lease.creation_time}})
    bridge.request("ping")
    check(lease.alive, "Notifications cannot execute destructive RPCs")
    other = env.launch_other()
    check_rejected_target(bridge, lease, str(int(lease.creation_time) + 1))
    stopped = bridge.tool("delphi_stop", {"timeout_ms": 2000})
    check(stopped["outcome"] == "exited" and stopped["exited"] and not stopped["terminated"], "Normal WM_CLOSE exits")
    check(lease.wait(), "Normal fixture exited")
    check((env.marker / f"close-query-{lease.pid}.txt").exists(), "Normal close used VCL close query")
    check(other.alive, "Different registered-path fixture remains alive")
    # Closing STDIO ends only the helper, preserving independently running IDEs.
    bridge.close()
    check(other.alive, "STDIO EOF does not stop another IDE")
    explicit = env.make_bridge()
    result = explicit.tool("delphi_stop", {"mode": "terminate", "process_id": other.pid,
        "creation_time": other.creation_time, "timeout_ms": 2000})
    check(result["exited"] and result["terminated"] and other.wait(),
          "Explicit identity can select a verified fixture from another IDE path")


def run_cancellation(env: TestEnvironment, mode: str) -> None:
    bridge = env.make_bridge(mode)
    started = bridge.tool("delphi_start", {"timeout_ms": 100})
    lease = env.wait_ready(started["process_id"])
    before = time.monotonic()
    result = bridge.tool("delphi_stop", {"timeout_ms": 200}, timeout=4)
    check(time.monotonic() - before < 3, f"{mode} close has bounded response")
    check(result["outcome"] == "still_running" and not result["exited"] and not result["terminated"],
          f"{mode} close does not auto-terminate: {result}")
    check(lease.alive, f"{mode} fixture remains alive")
    check((env.marker / f"wm-close-{lease.pid}.txt").exists(), f"{mode} received WM_CLOSE")
    if mode == "cancel":
        check((env.marker / f"close-query-{lease.pid}.txt").exists(), "Cancelled close reached VCL CloseQuery")
    result = bridge.tool("delphi_stop", {"mode": "terminate", "process_id": lease.pid,
        "creation_time": lease.creation_time, "timeout_ms": 2000})
    check(result["exited"] and result["terminated"] and result["outcome"] == "exited", "Explicit termination exits exact target")
    check(lease.wait(), "Explicitly terminated fixture exited")


def run_online(env: TestEnvironment, legacy: bool = False) -> None:
    port = free_port()
    bridge = env.make_bridge(mode="legacy" if legacy else "normal", port=port)
    result = bridge.tool("delphi_start", {"timeout_ms": 2000})
    lease = env.wait_ready(result["process_id"])
    check(result["started"] and result["dai_ready"] and result["outcome"] == "ready", f"Online start: {result}")
    status = bridge.tool("delphi_status")
    check_status(status, env, lease)
    dai = status["dai"]
    check(dai["state"] == "active" and dai["http_reachable"] and dai["authenticated"], f"Authenticated endpoint: {dai}")
    check(dai["process_id"] == lease.pid and dai["matches_registered_ide"], "DAI listener belongs to fixture")
    check(dai["version"] == VERSION, "Active DAI version comes from discovery")
    if legacy:
        check((env.marker / f"legacy-initialize-{lease.pid}.txt").exists(), "Old DAI probed through initialize fallback")
        check((env.marker / f"legacy-delete-{lease.pid}.txt").exists(), "Probe removes its temporary legacy session")
    bad_token = env.make_bridge(port=port, token="wrong-isolated-test-token")
    dai = bad_token.tool("delphi_status")["dai"]
    check(dai["http_reachable"] and not dai["authenticated"] and dai["state"] != "active", f"Failed authentication: {dai}")
    stopped = bridge.tool("delphi_stop", {"timeout_ms": 2000})
    check(stopped["exited"] and lease.wait(), "Online fixture closed normally")


def run_simultaneous_start(env: TestEnvironment) -> None:
    first = env.make_bridge()
    second = env.make_bridge()
    before = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(bridge.tool_response, "delphi_start", {"timeout_ms": 100}) for bridge in (first, second)]
        responses = [future.result(timeout=10) for future in futures]
    check(time.monotonic() - before < 3, "Simultaneous starts have bounded responses")
    check(all("result" in response for response in responses), f"Concurrent tool responses: {responses}")
    results = [response["result"]["structuredContent"] for response in responses
               if not response["result"].get("isError")]
    check(sum(bool(result["started"]) for result in results) == 1, f"Concurrent helpers start exactly one IDE: {responses}")
    check(len({result["process_id"] for result in results}) == 1,
          "Concurrent helpers either identify the same IDE or report an operation in progress")
    lease = env.wait_ready(results[0]["process_id"])
    status = first.tool("delphi_status")
    registered = [process for process in status["running_ides"] if process["matches_registered_ide"]]
    check(len(registered) == 1 and registered[0]["process_id"] == lease.pid, "Concurrent starts did not duplicate fixture")
    stopped = first.tool("delphi_stop", {"timeout_ms": 2000})
    check(stopped["exited"] and lease.wait(), "Concurrent-start fixture closed")


def run_missing_executable(env: TestEnvironment) -> None:
    missing = env.directory / "not-installed" / "bds.exe"
    bridge = env.make_bridge(ide=missing)
    status = bridge.tool("delphi_status")
    check(same_path(status["registered_ide"]["executable"], missing), "Missing registered IDE path retained")
    check(not status["registered_ide"]["exists"] and not status["registered_ide_running"], "Missing registered IDE reported offline")
    response = bridge.tool_response("delphi_start", {"timeout_ms": 100})
    check(response.get("result", {}).get("isError") is True, "Missing IDE start returns tool error")


def run_early_exit(env: TestEnvironment) -> None:
    bridge = env.make_bridge(mode="early-exit")
    result = bridge.tool("delphi_start", {"timeout_ms": 2000})
    check(result["started"] and result["outcome"] == "exited" and not result["dai_ready"],
          f"A started IDE that exits before readiness is reported accurately: {result}")
    check((env.marker / f"ready-{result['process_id']}.txt").exists(), "Early-exit fixture ran")
    check(not bridge.tool("delphi_status")["registered_ide_running"], "Early-exit fixture is no longer running")


def run_foreign_listener(env: TestEnvironment) -> None:
    requests = []
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *arguments):
            pass

        def do_POST(self):
            requests.append(dict(self.headers))
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"{}")

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        bridge = env.make_bridge(port=server.server_port)
        dai = bridge.tool("delphi_status")["dai"]
        check(dai["state"] == "unverified" and not dai["authenticated"], "Foreign listener classified as unverified")
        check(dai["process_id"] == os.getpid(), "Listener PID reports the isolated foreign server")
        check(not requests, "Credential is never sent to a foreign listener")
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=2)


def lifecycle_denied(bridge: Bridge, name: str, arguments: dict | None = None) -> None:
    response = bridge.tool_response(name, arguments)
    check("error" not in response and response.get("result", {}).get("isError") is True,
          f"Lifecycle denial is a tool error: {name}: {response}")
    message = response["result"]["structuredContent"].get("error", "")
    check("gesperrt" in message and "DAI" in message, "Lifecycle denial explains the DAI setting in German")


def check_policy_status(bridge: Bridge, allowed: bool, reason: str) -> None:
    policy = bridge.tool("delphi_status")["lifecycle_control"]
    check(policy == {"allowed": allowed, "reason": reason, "scope": "windows_user"},
          f"Current lifecycle policy: {policy}")


def run_lifecycle_policy(env: TestEnvironment) -> None:
    bridge = env.make_bridge()
    check_policy_status(bridge, True, "allowed_by_default")
    tools = bridge.request("tools/list")["result"]["tools"]
    env.policy(1)
    check_policy_status(bridge, True, "allowed")
    started = bridge.tool("delphi_start", {"timeout_ms": 100})
    lease = env.wait_ready(started["process_id"])
    other = env.launch_other()
    env.policy(0)
    check_policy_status(bridge, False, "disabled_in_dai_options")
    check(bridge.request("tools/list")["result"]["tools"] == tools, "Disabling keeps the three launcher tools discoverable")
    lifecycle_denied(bridge, "delphi_start", {"timeout_ms": 100})
    for mode in ("close", "terminate"):
        lifecycle_denied(bridge, "delphi_stop", {"mode": mode, "timeout_ms": 100})
        lifecycle_denied(bridge, "delphi_stop", {"mode": mode, "process_id": other.pid,
            "creation_time": other.creation_time, "timeout_ms": 100})
        check(lease.alive and other.alive, "Disabled lifecycle leaves both exact fixture processes alive")
    check(not (env.marker / f"wm-close-{lease.pid}.txt").exists(), "Disabled close never sends WM_CLOSE")
    check(not (env.marker / f"wm-close-{other.pid}.txt").exists(), "Explicit other-PID close never sends WM_CLOSE")
    bridge.notify("tools/call", {"name": "delphi_stop", "arguments": {
        "mode": "terminate", "process_id": lease.pid, "creation_time": lease.creation_time}})
    bridge.request("ping")
    check(lease.alive and other.alive, "Disabled notifications do not mutate fixture processes")
    for value, value_type, malformed in ((2, winreg.REG_DWORD, False),
                                         ("1", winreg.REG_SZ, False),
                                         (b"\x01\x00\x00\x00", winreg.REG_BINARY, False),
                                         (1, winreg.REG_DWORD, True)):
        env.policy(value, value_type, malformed_size=malformed)
        check_policy_status(bridge, False, "settings_unreadable")
        lifecycle_denied(bridge, "delphi_start", {"timeout_ms": 0})
        lifecycle_denied(bridge, "delphi_stop", {"mode": "close", "timeout_ms": 0})
        lifecycle_denied(bridge, "delphi_stop", {"mode": "terminate", "process_id": other.pid,
            "creation_time": other.creation_time, "timeout_ms": 0})
        check(lease.alive and other.alive, "Malformed policy fails closed for both fixture identities")
    env.policy(1)
    check_policy_status(bridge, True, "allowed")
    reused = bridge.tool("delphi_start", {"timeout_ms": 0})
    check(not reused["started"] and reused["process_id"] == lease.pid,
          "The same helper session observes re-enabling and reuses its live IDE")
    stopped = bridge.tool("delphi_stop", {"timeout_ms": 2000})
    check(stopped["exited"] and lease.wait(), "Re-enabled normal close exits the registered fixture")
    env.policy(0)
    before = set(env.marker.glob("ready-*.txt"))
    lifecycle_denied(bridge, "delphi_start", {"timeout_ms": 0})
    check(set(env.marker.glob("ready-*.txt")) == before, "Disabled offline start creates no fixture")
    env.policy(None)
    check_policy_status(bridge, True, "allowed_by_default")
    started_again = bridge.tool("delphi_start", {"timeout_ms": 100})
    restarted = env.wait_ready(started_again["process_id"])
    check(started_again["started"] and restarted.alive, "Removing the setting restores the default start permission")
    bridge.tool("delphi_stop", {"timeout_ms": 2000})
    check(restarted.wait() and other.alive, "Default stop closes only the registered fixture")
    bridge.tool("delphi_stop", {"mode": "terminate", "process_id": other.pid,
        "creation_time": other.creation_time, "timeout_ms": 2000})
    check(other.wait(), "Re-enabled explicit stop closes the other verified fixture")


def cli_validation(bridge: Path, ide: Path, fixture_environment: dict[str, str]) -> None:
    base = [str(bridge), "--launcher", "--url", "http://127.0.0.1:7331/mcp", "--ide", str(ide), "--dai-version", VERSION]
    for arguments, token in ((base, "invalid\r\nheader"),
                             (base[:3] + ["http://localhost.evil:7331/mcp"] + base[4:], TOKEN)):
        environment = {**os.environ, **fixture_environment}
        if token is None:
            environment.pop("DAI_MCP_TOKEN", None)
        else:
            environment["DAI_MCP_TOKEN"] = token
        result = subprocess.run(arguments, input="", capture_output=True, encoding="utf-8",
                                env=environment, timeout=5, creationflags=subprocess.CREATE_NO_WINDOW)
        check(result.returncode != 0 and not result.stdout, "Invalid CLI/token rejected before STDIO protocol")
        check(TOKEN not in result.stdout + result.stderr, "Invalid CLI does not disclose token")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bridge", required=True, type=Path)
    parser.add_argument("--fixture", required=True, type=Path)
    parser.add_argument("--platform", required=True, choices=("Win32", "Win64"))
    parser.add_argument("--helper-platform", choices=("Win32", "Win64"))
    parser.add_argument("--policy-isolated", action="store_true",
                        help="The generated test helper redirects HKCU into a GUID root; never use with a production bridge")
    parser.add_argument("--case", action="append", choices=("offline", "cancel", "hang", "online", "simultaneous", "missing-executable", "foreign-listener", "legacy-online", "early-exit", "lifecycle-policy"))
    arguments = parser.parse_args()
    label = f"{arguments.helper_platform or arguments.platform}->{arguments.platform}"
    for executable in (arguments.bridge, arguments.fixture):
        check(executable.is_file(), f"Missing compiled executable: {executable}")
    with tempfile.TemporaryDirectory(prefix="DAI-Launcher-Isolated-") as directory:
        root = Path(directory)
        for name, test in (("offline", run_offline), ("cancel", lambda env: run_cancellation(env, "cancel")),
                           ("hang", lambda env: run_cancellation(env, "hang")),
                           ("online", run_online), ("simultaneous", run_simultaneous_start),
                           ("missing-executable", run_missing_executable),
                           ("foreign-listener", run_foreign_listener),
                           ("legacy-online", lambda env: run_online(env, legacy=True)),
                           ("early-exit", run_early_exit), ("lifecycle-policy", run_lifecycle_policy)):
            if arguments.case and name not in arguments.case:
                continue
            if name == "lifecycle-policy" and not arguments.policy_isolated:
                if arguments.case:
                    raise ValueError("Lifecycle policy tests require the generated test helper with --policy-isolated")
                print(f"SKIP {label}: lifecycle-policy (external bridge without per-process registry isolation)", flush=True)
                continue
            env = TestEnvironment(arguments.bridge, arguments.fixture, arguments.platform, root / name,
                                  arguments.policy_isolated)
            try:
                test(env)
            finally:
                env.close()
            print(f"PASS {label}: {name}", flush=True)
        env = TestEnvironment(arguments.bridge, arguments.fixture, arguments.platform, root / "cli-validation",
                              arguments.policy_isolated)
        try:
            cli_validation(arguments.bridge, arguments.fixture, env.environment())
        finally:
            env.close()
    case_description = ", ".join(arguments.case) if arguments.case else "all cases"
    print(f"Launcher blackbox tests passed ({label}, {CHECKS} checks, {case_description}): offline MCP, exact IDE identity, "
          "startup/readiness/authentication, duplicate-start prevention, WM_CLOSE/cancel/hang, explicit termination, "
          "different-instance, lifecycle permission and stale-FILETIME protection. PID reuse is tested through mismatched creation identity; "
          "Windows PID allocation itself is not forced.")


if __name__ == "__main__":
    main()
