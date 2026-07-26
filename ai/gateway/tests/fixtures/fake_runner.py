"""Scriptable fake runner for lifecycle transitions and chat completions in tests."""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

import httpx


class PollOutcome(str, Enum):
    OK = "ok"
    LOADING = "loading"
    ERROR = "error"
    TIMEOUT = "timeout"


class ChatScriptMode(str, Enum):
    VALID_CREATE = "valid_create"
    VALID_RESCHEDULE = "valid_reschedule"
    VALID_CANCEL = "valid_cancel"
    VALID_UPDATE_STATUS = "valid_update_status"
    INVALID_JSON = "invalid_json"
    SEMANTIC_VIOLATION = "semantic_violation"
    OFF_CATALOG = "off_catalog"
    CUSTOM = "custom"


class ChatFailureMode(str, Enum):
    """Injected runner failures for resilience contract tests."""

    CONNECTION_REFUSED = "connection_refused"
    HTTP_5XX = "http_5xx"
    NETWORK_ERROR = "network_error"


@dataclass
class LoadedModelInfo:
    name: str
    digest: str
    context_tokens: int = 8192
    features: list[str] = field(default_factory=list)


@dataclass
class ChatScript:
    """One scripted chat completion (non-streaming or streaming)."""

    stream: bool = False
    mode: ChatScriptMode = ChatScriptMode.VALID_CREATE
    custom: dict[str, Any] | None = None
    chunk_size: int = 8
    summary_prefix: str | None = None
    first_token_delay_s: float = 0.0
    inter_token_delay_s: float = 0.0
    total_delay_s: float = 0.0
    failure: ChatFailureMode | None = None
    http_status: int = 500
    token_sequence: list[str] | None = None


def _default_create_envelope(*, context: dict[str, Any] | None = None) -> dict[str, Any]:
    ctx = context or {}
    now = ctx.get("now", "2026-07-18T12:00:00+03:00")
    date_str = str(now)[:10]
    if "T" in str(now):
        from datetime import datetime, timedelta

        today = datetime.fromisoformat(str(now).replace("Z", "+00:00")).date()
        tomorrow = today + timedelta(days=1)
        date_str = tomorrow.isoformat()
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": "create_appointment",
        "confidence": 0.92,
        "display_summary": "Book Ahmed with Dr Ali tomorrow at 5:00 PM",
        "params": {
            "patient_name": "Ahmed",
            "doctor_name": "Dr Ali",
            "date": date_str,
            "time": "17:00",
            "type": "planned",
        },
        "requires_resolution": {
            "patient_id": "lookup_required",
            "doctor_id": "lookup_required",
        },
        "warnings": [],
        "needs_clarification": False,
    }


def _default_reschedule_envelope(*, context: dict[str, Any] | None = None) -> dict[str, Any]:
    ctx = context or {}
    now = ctx.get("now", "2026-07-18T12:00:00+03:00")
    from datetime import datetime, timedelta

    today = datetime.fromisoformat(str(now).replace("Z", "+00:00")).date()
    new_date = (today + timedelta(days=2)).isoformat()
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": "reschedule_appointment",
        "confidence": 0.88,
        "display_summary": "Reschedule Ahmed tomorrow 5pm to next week",
        "params": {
            "appointment_ref": "Ahmed tomorrow 5pm",
            "new_date": new_date,
            "new_time": "10:00",
        },
        "requires_resolution": {
            "appointment_id": "lookup_required",
            "patient_id": "lookup_required",
            "doctor_id": "lookup_required",
        },
        "warnings": [],
        "needs_clarification": False,
    }


def _default_cancel_envelope() -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": "cancel_appointment",
        "confidence": 0.9,
        "display_summary": "Cancel Ahmed tomorrow 5pm",
        "params": {"appointment_ref": "Ahmed tomorrow 5pm"},
        "requires_resolution": {"appointment_id": "lookup_required"},
        "warnings": [],
        "needs_clarification": False,
    }


def _default_update_status_envelope() -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": "update_appointment_status",
        "confidence": 0.87,
        "display_summary": "Mark Ahmed tomorrow 5pm as arrived",
        "params": {"appointment_ref": "Ahmed tomorrow 5pm", "status": "arrived"},
        "requires_resolution": {"appointment_id": "lookup_required"},
        "warnings": [],
        "needs_clarification": False,
    }


def _semantic_violation_envelope() -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": "create_appointment",
        "confidence": 0.8,
        "display_summary": "Book someone with someone",
        "params": {
            "patient_name": "Ahmed",
            "doctor_name": "Dr Ali",
            "date": "2020-01-01",
            "time": "17:00",
            "type": "planned",
        },
        "requires_resolution": {
            "patient_id": "lookup_required",
            "doctor_id": "lookup_required",
        },
        "warnings": [],
        "needs_clarification": False,
    }


def _off_catalog_envelope() -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": "admin_delete_user",
        "confidence": 0.99,
        "display_summary": "Delete user",
        "params": {},
        "requires_resolution": {},
        "warnings": [],
        "needs_clarification": False,
    }


def envelope_for_mode(
    mode: ChatScriptMode,
    *,
    context: dict[str, Any] | None = None,
    custom: dict[str, Any] | None = None,
) -> dict[str, Any] | str:
    if mode == ChatScriptMode.CUSTOM and custom is not None:
        return custom
    if mode == ChatScriptMode.VALID_CREATE:
        return _default_create_envelope(context=context)
    if mode == ChatScriptMode.VALID_RESCHEDULE:
        return _default_reschedule_envelope(context=context)
    if mode == ChatScriptMode.VALID_CANCEL:
        return _default_cancel_envelope()
    if mode == ChatScriptMode.VALID_UPDATE_STATUS:
        return _default_update_status_envelope()
    if mode == ChatScriptMode.SEMANTIC_VIOLATION:
        return _semantic_violation_envelope()
    if mode == ChatScriptMode.OFF_CATALOG:
        return _off_catalog_envelope()
    if mode == ChatScriptMode.INVALID_JSON:
        return "not valid json {"
    raise ValueError(f"unsupported chat script mode: {mode}")


@dataclass
class FakeRunner:
    """In-memory fake runner whose poll and chat responses are scripted on demand."""

    runner_id: str = "fake-runner-1"
    base_url: str = "http://127.0.0.1:19999"
    _outcomes: list[tuple[PollOutcome, float | None, LoadedModelInfo | None]] = field(
        default_factory=list
    )
    _call_index: int = 0
    _chat_scripts: list[ChatScript] = field(default_factory=list)
    _chat_index: int = 0
    _chat_context: dict[str, Any] = field(default_factory=dict)
    chat_invocations: list[str] = field(default_factory=list)
    _models_in_ram_history: list[int] = field(default_factory=list)
    _swap_in_progress: bool = False

    def script(self, *outcomes: tuple[PollOutcome, float | None, LoadedModelInfo | None]) -> None:
        """Queue poll outcomes: ok(latency, model) / loading / error / timeout."""
        self._outcomes.extend(outcomes)
        self._call_index = 0

    def script_chat(
        self,
        mode: ChatScriptMode,
        *,
        custom: dict[str, Any] | None = None,
        context: dict[str, Any] | None = None,
        first_token_delay_s: float = 0.0,
        total_delay_s: float = 0.0,
        failure: ChatFailureMode | None = None,
        http_status: int = 500,
    ) -> None:
        """Queue chat completion outcomes for non-streaming generation tests."""
        if context is not None:
            self._chat_context = context
        self._chat_scripts.append(
            ChatScript(
                stream=False,
                mode=mode,
                custom=custom,
                first_token_delay_s=first_token_delay_s,
                total_delay_s=total_delay_s,
                failure=failure,
                http_status=http_status,
            )
        )

    def script_chat_stream(
        self,
        mode: ChatScriptMode,
        *,
        custom: dict[str, Any] | None = None,
        context: dict[str, Any] | None = None,
        chunk_size: int = 8,
        summary_prefix: str | None = None,
        first_token_delay_s: float = 0.0,
        inter_token_delay_s: float = 0.0,
        failure: ChatFailureMode | None = None,
        http_status: int = 500,
    ) -> None:
        """Queue streaming chat completion outcomes (OpenAI SSE chunks)."""
        if context is not None:
            self._chat_context = context
        self._chat_scripts.append(
            ChatScript(
                stream=True,
                mode=mode,
                custom=custom,
                chunk_size=chunk_size,
                summary_prefix=summary_prefix,
                first_token_delay_s=first_token_delay_s,
                inter_token_delay_s=inter_token_delay_s,
                failure=failure,
                http_status=http_status,
            )
        )

    def script_chat_failure(
        self,
        failure: ChatFailureMode,
        *,
        stream: bool = False,
        http_status: int = 500,
        first_token_delay_s: float = 0.0,
    ) -> None:
        """Queue a connection / 5xx / network failure for the next chat call."""
        self._chat_scripts.append(
            ChatScript(
                stream=stream,
                failure=failure,
                http_status=http_status,
                first_token_delay_s=first_token_delay_s,
            )
        )

    def script_chat_stream_tokens(
        self,
        tokens: list[str],
        *,
        first_token_delay_s: float = 0.0,
        inter_token_delay_s: float = 0.0,
        summary_prefix: str | None = None,
        failure: ChatFailureMode | None = None,
        http_status: int = 500,
    ) -> None:
        """Queue a custom streaming token sequence with optional delays."""
        self._chat_scripts.append(
            ChatScript(
                stream=True,
                token_sequence=list(tokens),
                summary_prefix=summary_prefix,
                first_token_delay_s=first_token_delay_s,
                inter_token_delay_s=inter_token_delay_s,
                failure=failure,
                http_status=http_status,
            )
        )

    def script_swap_window(
        self,
        *,
        starting_polls: int = 2,
        ready_model: LoadedModelInfo | None = None,
        ready_latency_ms: float = 50.0,
    ) -> None:
        """Queue STARTING (loading) polls then READY — simulates model swap."""
        self._swap_in_progress = True
        for _ in range(starting_polls):
            self.loading()
        model = ready_model or LoadedModelInfo(name="qwen3:4b", digest="sha256:swap-ready")
        self.ok(ready_latency_ms, model)

    def ok(self, latency_ms: float = 50.0, model: LoadedModelInfo | None = None) -> None:
        model = model or LoadedModelInfo(name="qwen3:4b", digest="sha256:abc123")
        self._outcomes.append((PollOutcome.OK, latency_ms, model))

    def loading(self) -> None:
        self._outcomes.append((PollOutcome.LOADING, None, None))

    def error(self) -> None:
        self._outcomes.append((PollOutcome.ERROR, None, None))

    def timeout(self) -> None:
        self._outcomes.append((PollOutcome.TIMEOUT, None, None))

    @property
    def models_in_ram_peak(self) -> int:
        """Peak concurrent models observed during scripted poll outcomes."""
        return max(self._models_in_ram_history, default=0)

    def poll(self) -> dict[str, Any]:
        """Return the next scripted poll outcome as a dict."""
        if self._call_index >= len(self._outcomes):
            return {"outcome": PollOutcome.ERROR.value}

        outcome, latency, model = self._outcomes[self._call_index]
        self._call_index += 1

        if outcome == PollOutcome.LOADING:
            self._models_in_ram_history.append(0)
        elif outcome == PollOutcome.OK and model is not None:
            self._models_in_ram_history.append(1)
            self._swap_in_progress = False

        result: dict[str, Any] = {"outcome": outcome.value}
        if latency is not None:
            result["latency_ms"] = latency
        if model is not None:
            result["model"] = {
                "name": model.name,
                "digest": model.digest,
                "context_tokens": model.context_tokens,
                "features": model.features,
            }
        return result

    def models_response(self) -> dict[str, Any]:
        """OpenAI-compatible /v1/models response for the current scripted state."""
        poll = self.poll()
        if poll["outcome"] == PollOutcome.OK.value and "model" in poll:
            m = poll["model"]
            return {
                "object": "list",
                "data": [
                    {
                        "id": m["name"],
                        "object": "model",
                        "digest": m["digest"],
                        "context_length": m.get("context_tokens"),
                    }
                ],
            }
        if poll["outcome"] == PollOutcome.LOADING.value:
            return {"object": "list", "data": []}
        raise RuntimeError(f"Fake runner error: {poll['outcome']}")

    def _next_chat_script(self) -> ChatScript:
        if self._chat_index >= len(self._chat_scripts):
            raise RuntimeError("no scripted chat completion remaining")
        script = self._chat_scripts[self._chat_index]
        self._chat_index += 1
        return script

    def _failure_exception(self, failure: ChatFailureMode) -> BaseException:
        if failure == ChatFailureMode.CONNECTION_REFUSED:
            return httpx.ConnectError("connection refused")
        if failure == ChatFailureMode.NETWORK_ERROR:
            return httpx.ReadError("simulated network error")
        return RuntimeError(f"unexpected failure mode: {failure}")

    def resolve_chat(
        self,
        *,
        stream: bool | None = None,
        apply_delays: bool = True,
        record_invocation: bool = True,
    ) -> httpx.Response | BaseException:
        """Build the next scripted chat response (or raise an injected failure)."""
        script = self._next_chat_script()
        if stream is not None and script.stream != stream:
            raise RuntimeError(
                f"script stream={script.stream!r} does not match requested stream={stream!r}"
            )

        if record_invocation:
            self.chat_invocations.append(self.runner_id)

        if apply_delays and script.first_token_delay_s > 0:
            time.sleep(script.first_token_delay_s)

        if script.failure == ChatFailureMode.CONNECTION_REFUSED:
            return self._failure_exception(ChatFailureMode.CONNECTION_REFUSED)
        if script.failure == ChatFailureMode.NETWORK_ERROR:
            return self._failure_exception(ChatFailureMode.NETWORK_ERROR)
        if script.failure == ChatFailureMode.HTTP_5XX:
            return httpx.Response(
                script.http_status,
                json={"error": {"message": "simulated runner failure"}},
            )

        if script.stream:
            return self._build_stream_response(script)

        if apply_delays and script.total_delay_s > 0:
            time.sleep(script.total_delay_s)

        body = envelope_for_mode(
            script.mode,
            context=self._chat_context,
            custom=script.custom,
        )
        content = body if isinstance(body, str) else json.dumps(body)
        return httpx.Response(
            200,
            json={
                "model": "fake",
                "message": {"role": "assistant", "content": content},
                "done": True,
                "prompt_eval_count": 120,
                "eval_count": 80,
            },
        )

    def _stream_lines_for_script(self, script: ChatScript) -> list[str]:
        if script.token_sequence is not None:
            return self._stream_lines_for_tokens(
                script.token_sequence,
                summary_prefix=script.summary_prefix,
                inter_token_delay_s=script.inter_token_delay_s,
            )
        body = envelope_for_mode(
            script.mode,
            context=self._chat_context,
            custom=script.custom,
        )
        content = body if isinstance(body, str) else json.dumps(body)
        return self.stream_lines_for_content(
            content,
            chunk_size=script.chunk_size,
            summary_prefix=script.summary_prefix,
            inter_token_delay_s=script.inter_token_delay_s,
        )

    def _build_stream_response(self, script: ChatScript) -> httpx.Response:
        lines = self._stream_lines_for_script(script)

        if script.failure == ChatFailureMode.HTTP_5XX:
            return httpx.Response(
                script.http_status,
                json={"error": {"message": "simulated mid-stream runner failure"}},
            )

        if script.failure == ChatFailureMode.NETWORK_ERROR and lines:
            def failing_stream():
                midpoint = max(1, len(lines) // 3)
                for index, line in enumerate(lines):
                    yield line.encode()
                    if index + 1 >= midpoint:
                        raise httpx.ReadError("simulated mid-stream network error")

            return httpx.Response(
                200,
                content=failing_stream(),
                headers={"Content-Type": "text/event-stream"},
            )

        return httpx.Response(
            200,
            content=b"".join(line.encode() for line in lines),
            headers={"Content-Type": "application/x-ndjson"},
        )

    def chat_completion_response(self) -> dict[str, Any]:
        """OpenAI-compatible /v1/chat/completions response for the next scripted mode."""
        response = self.resolve_chat(stream=False)
        if isinstance(response, BaseException):
            raise response
        return response.json()

    def chat_completion_stream_chunks(
        self,
        *,
        summary_prefix: str = "",
        chunk_size: int = 8,
    ) -> list[bytes]:
        """OpenAI-compatible SSE byte chunks for the next scripted streaming chat mode."""
        response = self.resolve_chat(stream=True)
        if isinstance(response, BaseException):
            raise response
        content = response.content
        if not isinstance(content, bytes):
            raise TypeError("streaming response content must be bytes for chunk splitting")
        return [content[i : i + chunk_size] for i in range(0, len(content), chunk_size)]

    @staticmethod
    def ollama_stream_line(content: str, *, done: bool = False) -> str:
        payload: dict[str, Any] = {
            "model": "fake",
            "message": {"role": "assistant", "content": content},
            "done": done,
        }
        if done:
            payload["prompt_eval_count"] = 120
            payload["eval_count"] = 80
        return json.dumps(payload) + "\n"

    @staticmethod
    def openai_stream_chunk(content: str, *, finish: bool = False) -> str:
        payload = {
            "id": "chatcmpl-fake",
            "object": "chat.completion.chunk",
            "choices": [
                {
                    "index": 0,
                    "delta": {} if finish else {"content": content},
                    "finish_reason": "stop" if finish else None,
                }
            ],
        }
        return f"data: {json.dumps(payload)}\n\n"

    @staticmethod
    def stream_lines_for_content(
        content: str,
        *,
        chunk_size: int = 8,
        summary_prefix: str | None = None,
        inter_token_delay_s: float = 0.0,
    ) -> list[str]:
        """Build Ollama-native NDJSON lines that assemble to ``content``."""
        full_text = f"{summary_prefix or ''}{content}"
        lines: list[str] = []
        for offset in range(0, len(full_text), chunk_size):
            if inter_token_delay_s > 0 and lines:
                time.sleep(inter_token_delay_s)
            lines.append(FakeRunner.ollama_stream_line(full_text[offset : offset + chunk_size]))
        lines.append(FakeRunner.ollama_stream_line("", done=True))
        return lines

    def _stream_lines_for_tokens(
        self,
        tokens: list[str],
        *,
        summary_prefix: str | None = None,
        inter_token_delay_s: float = 0.0,
    ) -> list[str]:
        lines: list[str] = []
        if summary_prefix:
            lines.append(FakeRunner.ollama_stream_line(summary_prefix))
        for index, token in enumerate(tokens):
            if inter_token_delay_s > 0 and index > 0:
                time.sleep(inter_token_delay_s)
            lines.append(FakeRunner.ollama_stream_line(token))
        lines.append(FakeRunner.ollama_stream_line("", done=True))
        return lines

    def chat_completion_stream_body(self) -> str:
        """OpenAI-compatible SSE body for the next scripted streaming mode."""
        response = self.resolve_chat(stream=True)
        if isinstance(response, BaseException):
            raise response
        return response.content.decode()

    def reset(self) -> None:
        self._outcomes.clear()
        self._call_index = 0
        self._chat_scripts.clear()
        self._chat_index = 0
        self._chat_context.clear()
        self.chat_invocations.clear()
        self._models_in_ram_history.clear()
        self._swap_in_progress = False
