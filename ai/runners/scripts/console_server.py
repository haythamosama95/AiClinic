#!/usr/bin/env python3
"""Serve the runner console static UI and localhost-only runtime control APIs."""

from __future__ import annotations

import json
import mimetypes
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

SCRIPTS_DIR = Path(__file__).resolve().parent
RUNNERS_ROOT = SCRIPTS_DIR.parent
CONSOLE_DIR = RUNNERS_ROOT.parent / "runner-console"
OLLAMA_COMPOSE = SCRIPTS_DIR / "ollama_compose.sh"
DEFAULT_HOST = os.environ.get("RUNNER_CONSOLE_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.environ.get("RUNNER_CONSOLE_PORT", "11435"))
OLLAMA_URL = os.environ.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_PROXY_PREFIX = "/api/runner"
_HOP_BY_HOP_HEADERS = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
    }
)


def _run_script(*args: str, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(OLLAMA_COMPOSE), *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def _gpu_enabled() -> bool:
    result = _run_script("gpu-enabled", timeout=5)
    return result.stdout.strip() == "1"


def _gpu_available() -> bool:
    result = _run_script("gpu-available", timeout=30)
    return result.stdout.strip() == "yes"


def _ollama_ps() -> list[dict[str, Any]]:
    result = _run_script("ps-json", timeout=15)
    raw = result.stdout.strip()
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if isinstance(data, dict):
        return [data]
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    return []


def _ollama_online() -> bool:
    try:
        with urllib.request.urlopen(f"{OLLAMA_URL}/v1/models", timeout=3) as resp:
            return resp.status == HTTPStatus.OK
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def runtime_status() -> dict[str, Any]:
    ps_rows = _ollama_ps()
    processor = ps_rows[0].get("processor") if ps_rows else None
    loaded_model = ps_rows[0].get("name") if ps_rows else None
    gpu_on = _gpu_enabled()
    gpu_ready = _gpu_available()
    return {
        "ollama_online": _ollama_online(),
        "ollama_url": OLLAMA_URL,
        "gpu_enabled": gpu_on,
        "gpu_available": gpu_ready,
        "processor": processor,
        "loaded_model": loaded_model,
        "loaded_models": ps_rows,
    }


def set_gpu(enabled: bool) -> dict[str, Any]:
    if enabled and not _gpu_available():
        return {
            "ok": False,
            "error": "NVIDIA GPU passthrough is not available. Install NVIDIA Container Toolkit and ensure nvidia-smi works.",
        }

    _run_script("set-gpu", "1" if enabled else "0", timeout=5)
    down = _run_script("down", timeout=60)
    up = _run_script("up", timeout=120)
    if up.returncode != 0:
        return {
            "ok": False,
            "error": (up.stderr or up.stdout or "Failed to restart Ollama").strip(),
            "gpu_enabled": _gpu_enabled(),
        }

    # Wait briefly for Ollama to accept connections after restart.
    for _ in range(20):
        if _ollama_online():
            break
        subprocess.run(["sleep", "0.5"], check=False)

    status = runtime_status()
    status["ok"] = True
    status["message"] = (
        "Ollama restarted with NVIDIA GPU enabled."
        if enabled
        else "Ollama restarted in CPU-only mode."
    )
    if down.stderr:
        status["restart_note"] = down.stderr.strip()
    return status


class ConsoleHandler(BaseHTTPRequestHandler):
    server_version = "AiClinicRunnerConsole/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), fmt % args))

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON body: {exc}") from exc
        if not isinstance(data, dict):
            raise ValueError("JSON body must be an object")
        return data

    def _proxy_to_ollama(self, method: str) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if not parsed.path.startswith(OLLAMA_PROXY_PREFIX):
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        upstream_path = parsed.path[len(OLLAMA_PROXY_PREFIX) :] or "/"
        if parsed.query:
            upstream_path = f"{upstream_path}?{parsed.query}"
        url = f"{OLLAMA_URL}{upstream_path}"

        body: bytes | None = None
        if method in {"POST", "PUT", "PATCH"}:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else None

        req = urllib.request.Request(url, data=body, method=method)
        for header in ("Content-Type", "Accept"):
            if header in self.headers:
                req.add_header(header, self.headers[header])

        try:
            upstream = urllib.request.urlopen(req, timeout=600)
        except urllib.error.HTTPError as exc:
            upstream = exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            self._send_json(
                HTTPStatus.BAD_GATEWAY,
                {"error": f"Ollama unreachable at {OLLAMA_URL}: {exc}"},
            )
            return

        try:
            self.send_response(upstream.status)
            content_type = upstream.headers.get("Content-Type", "")
            is_stream = "ndjson" in content_type or "text/event-stream" in content_type
            for header, value in upstream.headers.items():
                if header.lower() not in _HOP_BY_HOP_HEADERS:
                    self.send_header(header, value)
            if is_stream:
                self.send_header("Cache-Control", "no-cache")
                self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            if is_stream and ("ndjson" in content_type or "text/event-stream" in content_type):
                buffer = b""
                while True:
                    chunk = upstream.read(512)
                    if not chunk:
                        if buffer:
                            self.wfile.write(buffer)
                            self.wfile.flush()
                        break
                    buffer += chunk
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        self.wfile.write(line + b"\n")
                        self.wfile.flush()
            else:
                while True:
                    chunk = upstream.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
        except BrokenPipeError:
            pass
        finally:
            upstream.close()

    def _serve_static(self) -> None:
        rel = self.path.split("?", 1)[0]
        if rel in ("", "/"):
            rel = "/index.html"
        target = (CONSOLE_DIR / rel.lstrip("/")).resolve()
        if not str(target).startswith(str(CONSOLE_DIR.resolve())):
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        content = target.read_bytes()
        mime, _ = mimetypes.guess_type(str(target))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime or "application/octet-stream")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:
        if self.path == "/api/runtime":
            self._send_json(HTTPStatus.OK, runtime_status())
            return
        if self.path.startswith(OLLAMA_PROXY_PREFIX):
            self._proxy_to_ollama("GET")
            return
        self._serve_static()

    def do_POST(self) -> None:
        if self.path.startswith(OLLAMA_PROXY_PREFIX):
            self._proxy_to_ollama("POST")
            return
        if self.path == "/api/runtime/gpu":
            try:
                body = self._read_json_body()
            except ValueError as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
                return
            enabled = bool(body.get("enabled"))
            result = set_gpu(enabled)
            status = HTTPStatus.OK if result.get("ok") else HTTPStatus.BAD_REQUEST
            self._send_json(status, result)
            return
        self.send_error(HTTPStatus.NOT_FOUND)


def main() -> None:
    if not CONSOLE_DIR.is_dir():
        print(f"error: runner console not found at {CONSOLE_DIR}", file=sys.stderr)
        sys.exit(1)
    if not OLLAMA_COMPOSE.is_file():
        print(f"error: missing {OLLAMA_COMPOSE}", file=sys.stderr)
        sys.exit(1)

    status = runtime_status()
    ollama_state = "online" if status["ollama_online"] else "not responding"
    gpu_line = "enabled" if status["gpu_enabled"] else "disabled"
    if status["gpu_available"]:
        gpu_line += " (NVIDIA available)"
    else:
        gpu_line += " (NVIDIA not detected for Docker)"

    print(f"==> AI Model Runner console on http://{DEFAULT_HOST}:{DEFAULT_PORT}")
    print(f"    Ollama API: {OLLAMA_URL} ({ollama_state})")
    print(f"    GPU mode: {gpu_line}")
    print("    Gateway dashboard: http://localhost:8090/dashboard")
    print("    Press Ctrl+C to stop")
    print()

    server = ThreadingHTTPServer((DEFAULT_HOST, DEFAULT_PORT), ConsoleHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
