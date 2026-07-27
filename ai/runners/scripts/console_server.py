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
AI_ROOT = RUNNERS_ROOT.parent
AI_COMMON_SRC = AI_ROOT / "common" / "src"
for path in (AI_COMMON_SRC, AI_ROOT):
    path_str = str(path)
    if path_str not in sys.path:
        sys.path.insert(0, path_str)

from obs.verbose_logging import (  # noqa: E402
    configure_logging,
    get_logger,
    get_verbose_level,
    sanitized_json_body,
)

CONSOLE_DIR = RUNNERS_ROOT.parent / "runner-console"
OLLAMA_COMPOSE = SCRIPTS_DIR / "ollama_compose.sh"
DEFAULT_HOST = os.environ.get("RUNNER_CONSOLE_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.environ.get("RUNNER_CONSOLE_PORT", "11435"))
OLLAMA_URL = os.environ.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8090").rstrip("/")
OLLAMA_PROXY_PREFIX = "/api/runner"
GATEWAY_PROXY_PREFIX = "/api/gateway"
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

log = get_logger("console_server", component="runners")


def _run_script(*args: str, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    started = log.job_start(
        "Running Ollama compose script",
        command="ollama_compose",
        args=list(args),
        timeout_s=timeout,
    )
    log.v1("Invoking Ollama compose command", command="ollama_compose", args=list(args), timeout_s=timeout)
    try:
        result = subprocess.run(
            ["bash", str(OLLAMA_COMPOSE), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        log.v2(
            "Ollama compose script finished",
            returncode=result.returncode,
            stdout_len=len(result.stdout or ""),
            stderr_len=len(result.stderr or ""),
        )
        log.job_end(
            "Ollama compose script completed"
            if result.returncode == 0
            else "Ollama compose script failed",
            started_at=started,
            success=result.returncode == 0,
            returncode=result.returncode,
        )
        return result
    except subprocess.TimeoutExpired as exc:
        log.error("Ollama compose script timed out", command="ollama_compose", timeout_s=timeout)
        log.job_end(
            "Ollama compose script timed out",
            started_at=started,
            success=False,
            error="timeout",
        )
        raise exc


def _gpu_enabled() -> bool:
    log.v2("Checking whether GPU mode is enabled")
    result = _run_script("gpu-enabled", timeout=5)
    enabled = result.stdout.strip() == "1"
    log.v1("GPU mode preference resolved", enabled=enabled)
    return enabled


def _gpu_available() -> bool:
    log.v2("Checking NVIDIA GPU availability for Docker")
    result = _run_script("gpu-available", timeout=30)
    available = result.stdout.strip() == "yes"
    log.v1("NVIDIA GPU availability resolved", available=available)
    return available


def _ollama_ps() -> list[dict[str, Any]]:
    log.v2("Querying loaded Ollama models")
    result = _run_script("ps-json", timeout=15)
    raw = result.stdout.strip()
    if not raw:
        log.v1("No Ollama models are currently loaded")
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        log.error("Loaded model list returned invalid JSON")
        return []
    if isinstance(data, dict):
        rows = [data]
    elif isinstance(data, list):
        rows = [item for item in data if isinstance(item, dict)]
    else:
        rows = []
    log.v1(
        "Loaded Ollama models resolved",
        model_count=len(rows),
        models=[r.get("name") for r in rows],
    )
    log.v2("Loaded Ollama model details", rows=rows)
    return rows


def _ollama_online() -> bool:
    url = f"{OLLAMA_URL}/v1/models"
    log.v2("Probing Ollama API availability", url=url)
    try:
        with urllib.request.urlopen(url, timeout=3) as resp:
            online = resp.status == HTTPStatus.OK
            log.v1("Ollama API probe finished", online=online, status=resp.status)
            return online
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        log.v1("Ollama API probe failed", online=False, error=str(exc))
        return False


def _compose_status() -> dict[str, Any]:
    log.v2("Collecting Docker Compose status for Ollama")
    result = _run_script("status-json", timeout=15)
    raw = result.stdout.strip()
    if not raw:
        fallback = {
            "container_running": False,
            "ollama_reachable": False,
            "gpu_enabled": _gpu_enabled(),
            "gpu_available": _gpu_available(),
            "host_models": "unknown",
        }
        log.v1("Compose status unavailable, using fallback values", status=fallback)
        return fallback
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        log.error("Compose status returned invalid JSON")
        return {"error": "invalid status-json output"}
    if not isinstance(data, dict):
        log.error("Compose status returned unexpected shape")
        return {"error": "invalid status-json shape"}
    log.v1("Compose status resolved", status=data)
    return data


def _ollama_logs_tail(lines: int = 80) -> str:
    lines = max(10, min(lines, 500))
    log.v1("Fetching Ollama container logs", lines=lines)
    result = _run_script("logs-tail", str(lines), timeout=30)
    text = (result.stdout or result.stderr or "").strip()
    log.v2("Ollama container logs retrieved", char_count=len(text))
    return text


def server_config() -> dict[str, Any]:
    config = {
        "host": DEFAULT_HOST,
        "port": DEFAULT_PORT,
        "ollama_url": OLLAMA_URL,
        "gateway_url": GATEWAY_URL,
        "runner_proxy_prefix": OLLAMA_PROXY_PREFIX,
        "gateway_proxy_prefix": GATEWAY_PROXY_PREFIX,
    }
    log.v1("Runner console configuration resolved", config=config, verbose_level=get_verbose_level())
    return config


def runtime_status() -> dict[str, Any]:
    started = log.job_start("Collecting runner runtime status")
    ps_rows = _ollama_ps()
    processor = ps_rows[0].get("processor") if ps_rows else None
    loaded_model = ps_rows[0].get("name") if ps_rows else None
    gpu_on = _gpu_enabled()
    gpu_ready = _gpu_available()
    compose = _compose_status()
    status = {
        "ollama_online": _ollama_online(),
        "ollama_url": OLLAMA_URL,
        "gpu_enabled": gpu_on,
        "gpu_available": gpu_ready,
        "processor": processor,
        "loaded_model": loaded_model,
        "loaded_models": ps_rows,
        "compose": compose,
    }
    log.v1(
        "Runner runtime status assembled",
        ollama_online=status["ollama_online"],
        loaded_model=loaded_model,
        gpu_enabled=gpu_on,
        gpu_available=gpu_ready,
    )
    log.job_end("Runner runtime status collected", started_at=started, success=True)
    return status


def set_gpu(enabled: bool) -> dict[str, Any]:
    started = log.job_start("Changing Ollama GPU mode", enabled=enabled)
    if enabled and not _gpu_available():
        log.v1("GPU mode change rejected because NVIDIA is unavailable", reason="gpu_unavailable")
        result = {
            "ok": False,
            "error": (
                "NVIDIA GPU passthrough is not available. Install NVIDIA Container Toolkit "
                "and ensure nvidia-smi works."
            ),
        }
        log.job_end(
            "GPU mode change rejected",
            started_at=started,
            success=False,
            error=result["error"],
        )
        return result

    log.v1("Applying GPU mode preference", enabled=enabled)
    _run_script("set-gpu", "1" if enabled else "0", timeout=5)
    down = _run_script("down", timeout=60)
    log.v2("Stopped Ollama compose stack for GPU mode change", returncode=down.returncode)
    up = _run_script("up", timeout=120)
    if up.returncode != 0:
        error = (up.stderr or up.stdout or "Failed to restart Ollama").strip()
        log.error("Failed to restart Ollama after GPU mode change", error=error)
        result = {
            "ok": False,
            "error": error,
            "gpu_enabled": _gpu_enabled(),
        }
        log.job_end(
            "GPU mode change failed during Ollama restart",
            started_at=started,
            success=False,
            error=error,
        )
        return result

    for attempt in range(20):
        log.v2(
            "Waiting for Ollama to come back online after GPU mode change",
            attempt=attempt + 1,
            max_attempts=20,
        )
        if _ollama_online():
            log.v1("Ollama is online after GPU mode change", attempt=attempt + 1)
            break
        subprocess.run(["sleep", "0.5"], check=False)
    else:
        log.v1("Ollama did not come back online after GPU mode change", attempts=20)

    status = runtime_status()
    status["ok"] = True
    status["message"] = (
        "Ollama restarted with NVIDIA GPU enabled."
        if enabled
        else "Ollama restarted in CPU-only mode."
    )
    if down.stderr:
        status["restart_note"] = down.stderr.strip()
    log.job_end("GPU mode change completed", started_at=started, success=True, gpu_enabled=enabled)
    return status


class ConsoleHandler(BaseHTTPRequestHandler):
    server_version = "AiClinicRunnerConsole/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        message = fmt % args
        log.v0(
            "HTTP request received",
            client=self.client_address[0],
            message=message,
        )

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        if get_verbose_level() >= 2:
            log.v2(
                "Sending JSON response to client",
                path=self.path,
                status=status,
                body=sanitized_json_body(payload),
            )
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        log.v1("JSON response sent", status=status, path=self.path, body_keys=list(payload.keys()))

    def _read_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            log.v2("Request body is empty")
            return {}
        raw = self.rfile.read(length)
        log.v2("Request body read", byte_len=len(raw))
        try:
            data = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            log.error("Request body contains invalid JSON", error=str(exc))
            raise ValueError(f"Invalid JSON body: {exc}") from exc
        if not isinstance(data, dict):
            raise ValueError("JSON body must be an object")
        log.v1("Request body parsed", keys=list(data.keys()))
        if get_verbose_level() >= 2:
            log.v2(
                "Received JSON request body",
                path=self.path,
                body=sanitized_json_body(data),
            )
        return data

    def _proxy_to_ollama(self, method: str) -> None:
        started = log.job_start("Proxying request to Ollama", method=method, path=self.path)
        parsed = urllib.parse.urlparse(self.path)
        if not parsed.path.startswith(OLLAMA_PROXY_PREFIX):
            log.v1("Ollama proxy path not found", path=parsed.path)
            self.send_error(HTTPStatus.NOT_FOUND)
            log.job_end(
                "Ollama proxy request failed",
                started_at=started,
                success=False,
                error="not_found",
            )
            return

        upstream_path = parsed.path[len(OLLAMA_PROXY_PREFIX) :] or "/"
        if parsed.query:
            upstream_path = f"{upstream_path}?{parsed.query}"
        url = f"{OLLAMA_URL}{upstream_path}"
        log.v1("Forwarding request to Ollama upstream", method=method, url=url)

        body: bytes | None = None
        if method in {"POST", "PUT", "PATCH"}:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else None
            log.v1("Ollama proxy request body size", byte_len=len(body) if body else 0)
            if get_verbose_level() >= 2 and body:
                log.v2(
                    "Forwarding request body to Ollama",
                    method=method,
                    url=url,
                    body=sanitized_json_body(body),
                )

        req = urllib.request.Request(url, data=body, method=method)
        for header in ("Content-Type", "Accept"):
            if header in self.headers:
                req.add_header(header, self.headers[header])

        try:
            upstream = urllib.request.urlopen(req, timeout=600)
        except urllib.error.HTTPError as exc:
            upstream = exc
            log.v1("Ollama upstream returned HTTP error", status=exc.code)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            log.error("Ollama upstream is unreachable", url=url, error=str(exc))
            self._send_json(
                HTTPStatus.BAD_GATEWAY,
                {"error": f"Ollama unreachable at {OLLAMA_URL}: {exc}"},
            )
            log.job_end(
                "Ollama proxy request failed",
                started_at=started,
                success=False,
                error=str(exc),
            )
            return

        try:
            self.send_response(upstream.status)
            content_type = upstream.headers.get("Content-Type", "")
            is_stream = "ndjson" in content_type or "text/event-stream" in content_type
            log.v1(
                "Ollama upstream response received",
                status=upstream.status,
                content_type=content_type,
                streaming=is_stream,
            )
            for header, value in upstream.headers.items():
                if header.lower() not in _HOP_BY_HOP_HEADERS:
                    self.send_header(header, value)
            if is_stream:
                self.send_header("Cache-Control", "no-cache")
                self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            chunk_count = 0
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
                        chunk_count += 1
                        if get_verbose_level() >= 2:
                            log.v2(
                                "Streaming Ollama response line",
                                chunk_index=chunk_count,
                                body=sanitized_json_body(line),
                            )
            else:
                collected = bytearray()
                while True:
                    chunk = upstream.read(8192)
                    if not chunk:
                        break
                    if get_verbose_level() >= 2:
                        collected.extend(chunk)
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    chunk_count += 1
                if get_verbose_level() >= 2 and collected:
                    log.v2(
                        "Received response body from Ollama",
                        status=upstream.status,
                        url=url,
                        body=sanitized_json_body(bytes(collected)),
                    )
            log.v1("Ollama proxy response complete", chunks=chunk_count, status=upstream.status)
            log.job_end("Ollama proxy request completed", started_at=started, success=True, status=upstream.status)
        except BrokenPipeError:
            log.v1("Client disconnected during Ollama proxy", path=self.path)
            log.job_end(
                "Ollama proxy request interrupted",
                started_at=started,
                success=False,
                error="broken_pipe",
            )
        finally:
            upstream.close()

    def _proxy_to_gateway(self, method: str, upstream_path: str) -> None:
        started = log.job_start("Proxying request to gateway", method=method, path=upstream_path)
        url = f"{GATEWAY_URL}{upstream_path}"
        log.v1("Forwarding request to gateway upstream", method=method, url=url)

        body: bytes | None = None
        if method in {"POST", "PUT", "PATCH"}:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else None
            log.v1("Gateway proxy request body size", byte_len=len(body) if body else 0)
            if get_verbose_level() >= 2 and body:
                log.v2(
                    "Forwarding request body to gateway",
                    method=method,
                    url=url,
                    body=sanitized_json_body(body),
                )

        req = urllib.request.Request(url, data=body, method=method)
        for header in ("Content-Type", "Accept", "Authorization"):
            if header in self.headers:
                req.add_header(header, self.headers[header])

        try:
            upstream = urllib.request.urlopen(req, timeout=30)
        except urllib.error.HTTPError as exc:
            upstream = exc
            log.v1("Gateway upstream returned HTTP error", status=exc.code)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            log.error("Gateway upstream is unreachable", url=url, error=str(exc))
            self._send_json(
                HTTPStatus.BAD_GATEWAY,
                {"error": f"Gateway unreachable at {GATEWAY_URL}: {exc}"},
            )
            log.job_end(
                "Gateway proxy request failed",
                started_at=started,
                success=False,
                error=str(exc),
            )
            return

        try:
            payload = upstream.read()
            if get_verbose_level() >= 2:
                log.v2(
                    "Received response body from gateway",
                    status=upstream.status,
                    url=url,
                    body=sanitized_json_body(payload),
                )
            content_type = upstream.headers.get("Content-Type", "application/json")
            self.send_response(upstream.status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            log.v1(
                "Gateway proxy response complete",
                status=upstream.status,
                response_bytes=len(payload),
            )
            log.job_end("Gateway proxy request completed", started_at=started, success=True, status=upstream.status)
        except BrokenPipeError:
            log.v1("Client disconnected during gateway proxy", path=upstream_path)
            log.job_end(
                "Gateway proxy request interrupted",
                started_at=started,
                success=False,
                error="broken_pipe",
            )
        finally:
            upstream.close()

    def _proxy_to_gateway_raw(self, method: str, upstream_path: str) -> None:
        """Proxy to gateway preserving upstream content-type (e.g. Prometheus text)."""
        started = log.job_start(
            "Proxying raw request to gateway",
            method=method,
            path=upstream_path,
        )
        url = f"{GATEWAY_URL}{upstream_path}"
        log.v1("Forwarding raw request to gateway upstream", method=method, url=url)

        body: bytes | None = None
        if method in {"POST", "PUT", "PATCH"}:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else None
            if get_verbose_level() >= 2 and body:
                log.v2(
                    "Forwarding raw request body to gateway",
                    method=method,
                    url=url,
                    body=sanitized_json_body(body),
                )

        req = urllib.request.Request(url, data=body, method=method)
        for header in ("Content-Type", "Accept", "Authorization"):
            if header in self.headers:
                req.add_header(header, self.headers[header])

        try:
            upstream = urllib.request.urlopen(req, timeout=30)
        except urllib.error.HTTPError as exc:
            upstream = exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            log.error("Gateway raw upstream is unreachable", url=url, error=str(exc))
            self._send_json(
                HTTPStatus.BAD_GATEWAY,
                {"error": f"Gateway unreachable at {GATEWAY_URL}: {exc}"},
            )
            log.job_end(
                "Gateway raw proxy request failed",
                started_at=started,
                success=False,
                error=str(exc),
            )
            return

        try:
            payload = upstream.read()
            content_type = upstream.headers.get("Content-Type", "text/plain; charset=utf-8")
            if get_verbose_level() >= 2:
                if "json" in content_type.lower():
                    log.v2(
                        "Received raw JSON response from gateway",
                        status=upstream.status,
                        url=url,
                        body=sanitized_json_body(payload),
                    )
                else:
                    log.v2(
                        "Received non-JSON response from gateway",
                        status=upstream.status,
                        url=url,
                        response_bytes=len(payload),
                    )
            self.send_response(upstream.status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            log.v1(
                "Gateway raw proxy request completed",
                status=upstream.status,
                response_bytes=len(payload),
            )
            log.job_end(
                "Gateway raw proxy request completed",
                started_at=started,
                success=True,
                status=upstream.status,
            )
        except BrokenPipeError:
            log.job_end(
                "Gateway raw proxy request interrupted",
                started_at=started,
                success=False,
                error="broken_pipe",
            )
        finally:
            upstream.close()

    def _serve_static(self) -> None:
        rel = self.path.split("?", 1)[0]
        if rel in ("", "/"):
            rel = "/index.html"
        target = (CONSOLE_DIR / rel.lstrip("/")).resolve()
        log.v2("Resolving static file path", requested=rel, target=str(target))
        if not str(target).startswith(str(CONSOLE_DIR.resolve())):
            log.error("Static file access forbidden", path=rel)
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        if not target.is_file():
            log.v1("Static file not found", path=rel)
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        content = target.read_bytes()
        mime, _ = mimetypes.guess_type(str(target))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime or "application/octet-stream")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)
        log.v1("Static console asset served", path=rel, bytes=len(content), mime=mime)

    def _handle_runtime_post(self) -> None:
        started = log.job_start("Handling runtime control POST", path=self.path)
        try:
            body = self._read_json_body()
        except ValueError as exc:
            log.error("Runtime POST body is invalid", error=str(exc))
            self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            log.job_end(
                "Runtime control POST failed",
                started_at=started,
                success=False,
                error=str(exc),
            )
            return
        if "enabled" in body:
            enabled = bool(body.get("enabled"))
            log.v1("Runtime POST requests GPU mode change", enabled=enabled)
            result = set_gpu(enabled)
            status = HTTPStatus.OK if result.get("ok") else HTTPStatus.BAD_REQUEST
            self._send_json(status, result)
            log.job_end(
                "Runtime control POST completed",
                started_at=started,
                success=result.get("ok", False),
            )
            return
        log.v1("Runtime POST rejected due to invalid body", body_keys=list(body.keys()))
        self._send_json(
            HTTPStatus.BAD_REQUEST,
            {"ok": False, "error": "Expected JSON body with enabled: boolean"},
        )
        log.job_end(
            "Runtime control POST rejected",
            started_at=started,
            success=False,
            error="bad_request",
        )

    def do_GET(self) -> None:
        log.v0("Incoming GET request", method="GET", path=self.path)
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/runtime":
            self._send_json(HTTPStatus.OK, runtime_status())
            return
        if path == "/api/config":
            self._send_json(HTTPStatus.OK, server_config())
            return
        if path == "/api/compose/status":
            payload = _compose_status()
            payload["ollama_online"] = _ollama_online()
            payload["loaded_models"] = _ollama_ps()
            self._send_json(HTTPStatus.OK, payload)
            return
        if path == "/api/runtime/logs":
            query = urllib.parse.parse_qs(parsed.query)
            try:
                lines = int((query.get("lines") or ["80"])[0])
            except ValueError:
                lines = 80
            self._send_json(
                HTTPStatus.OK,
                {"lines": max(10, min(lines, 500)), "text": _ollama_logs_tail(lines)},
            )
            return
        if self.path == "/api/gateway/capabilities":
            self._proxy_to_gateway("GET", "/v1/capabilities")
            return
        if self.path == "/api/gateway/status":
            self._proxy_to_gateway("GET", "/v1/status")
            return
        if self.path == "/api/gateway/metrics":
            self._proxy_to_gateway_raw("GET", "/metrics")
            return
        if self.path.startswith(OLLAMA_PROXY_PREFIX):
            self._proxy_to_ollama("GET")
            return
        self._serve_static()

    def do_POST(self) -> None:
        log.v0("Incoming POST request", method="POST", path=self.path)
        if self.path.startswith(OLLAMA_PROXY_PREFIX):
            self._proxy_to_ollama("POST")
            return
        if self.path == "/api/gateway/auto-sign-in":
            self._proxy_to_gateway("POST", "/v1/dashboard/auto-sign-in")
            return
        if self.path in {"/api/runtime", "/api/runtime/gpu"}:
            self._handle_runtime_post()
            return
        log.v1("POST route not found", path=self.path)
        self.send_error(HTTPStatus.NOT_FOUND)


def main() -> None:
    configure_logging(
        component="runners",
        log_dir=os.environ.get("RUNNER_LOG_DIR", str(RUNNERS_ROOT / "logs")),
    )

    if not CONSOLE_DIR.is_dir():
        log.error("Runner console directory is missing", path=str(CONSOLE_DIR))
        print(f"error: runner console not found at {CONSOLE_DIR}", file=sys.stderr)
        sys.exit(1)
    if not OLLAMA_COMPOSE.is_file():
        log.error("Ollama compose script is missing", path=str(OLLAMA_COMPOSE))
        print(f"error: missing {OLLAMA_COMPOSE}", file=sys.stderr)
        sys.exit(1)

    started = log.job_start("Starting runner console server")
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
    print(f"    Gateway API: {GATEWAY_URL} (proxy /api/gateway/*)")
    print("    Gateway dashboard: http://localhost:8090/dashboard")
    print("    Press Ctrl+C to stop")
    print()

    log.v1(
        "Runner console server listening",
        host=DEFAULT_HOST,
        port=DEFAULT_PORT,
        ollama_url=OLLAMA_URL,
        gateway_url=GATEWAY_URL,
        verbose_level=get_verbose_level(),
    )

    server = ThreadingHTTPServer((DEFAULT_HOST, DEFAULT_PORT), ConsoleHandler)
    log.job_end("Runner console server startup completed", started_at=started, success=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.v0("Runner console shutdown requested", reason="keyboard_interrupt")
        print("\nStopped.")
    finally:
        server.server_close()
        log.v0("Runner console server stopped")


if __name__ == "__main__":
    main()
