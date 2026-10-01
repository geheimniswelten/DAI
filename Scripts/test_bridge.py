"""Exercise the compiled Delphi stdio bridge against an isolated loopback server."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--bridge', type=Path, default=Path(__file__).resolve().parents[1] /
                        'Build/Win32/Release/Bpl/DAI.McpBridge.exe')
    args = parser.parse_args()
    seen: list[dict] = []
    deleted: list[str] = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_DELETE(self):
            assert self.headers['Authorization'] == 'Bearer bridge-test-token'
            assert self.headers['Mcp-Session-Id'] == 'bridge-test-session'
            assert self.headers['MCP-Protocol-Version'] == '2025-06-18'
            deleted.append(self.path)
            self.send_response(204)
            self.send_header('Content-Length', '0')
            self.end_headers()

        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            assert self.headers['Authorization'] == 'Bearer bridge-test-token'
            assert self.path == '/mcp'
            if request['method'] != 'initialize':
                assert self.headers['Mcp-Session-Id'] == 'bridge-test-session'
                assert self.headers['MCP-Protocol-Version'] == '2025-06-18'
            seen.append(request)
            if 'id' not in request:
                self.send_response(202)
                self.end_headers()
                return
            if request['method'] == 'http_failure':
                self.send_response(401)
                self.end_headers()
                return
            result = {'protocolVersion': '2025-06-18'} if request['method'] == 'initialize' else request.get('params', {})
            body = json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}, ensure_ascii=False).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Mcp-Session-Id', 'bridge-test-session')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    endpoint = f'http://127.0.0.1:{server.server_port}/mcp'
    env = {**os.environ, 'DAI_MCP_TOKEN': 'bridge-test-token'}
    messages = [
        {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 'unicode', 'method': 'tools/call', 'params': {'content': 'Grüße 日本語 😀\nzweite Zeile'}},
        {'jsonrpc': '2.0', 'id': 3, 'method': 'http_failure'},
    ]
    try:
        proc = subprocess.run([str(args.bridge), '--url', endpoint],
                              input=''.join(json.dumps(m, ensure_ascii=False) + '\n' for m in messages),
                              capture_output=True, encoding='utf-8', env=env, timeout=20)
        assert proc.returncode == 0, proc.stderr
        output = [json.loads(line) for line in proc.stdout.splitlines()]
        assert len(output) == 3, proc.stdout
        assert output[0]['result']['protocolVersion'] == '2025-06-18'
        assert output[1]['id'] == 'unicode'
        assert output[1]['result'] == messages[2]['params'], output[1]
        assert output[2]['error']['code'] == -32000
        assert len(seen) == 4, seen
        assert deleted == ['/mcp'], deleted
        assert 'bridge-test-token' not in proc.stdout + proc.stderr
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    invalid = subprocess.run([str(args.bridge), '--url', 'http://localhost.evil:7331/mcp'],
                             capture_output=True, encoding='utf-8', env=env, timeout=5)
    assert invalid.returncode != 0 and not invalid.stdout
    env.pop('DAI_MCP_TOKEN')
    missing = subprocess.run([str(args.bridge), '--url', 'http://127.0.0.1:7331/mcp'],
                             capture_output=True, encoding='utf-8', env=env, timeout=5)
    assert missing.returncode != 0 and not missing.stdout
    print('Delphi bridge tests passed: UTF-8, session/version, notifications, session DELETE at EOF, HTTP errors, endpoint/token validation.')


if __name__ == '__main__':
    main()
