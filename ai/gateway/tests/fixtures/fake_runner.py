"""Scriptable fake runner for lifecycle transitions and chat completions in tests."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


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


@dataclass
class LoadedModelInfo:
    name: str
    digest: str
    context_tokens: int = 8192
    features: list[str] = field(default_factory=list)


def _default_create_envelope(*, context: dict[str, Any] | None = None) -> dict[str, Any]:
    ctx = context or {}
    now = ctx.get("now", "2026-07-18T12:00:00+03:00")
    date_str = str(now)[:10]
    if "T" in str(now):
        from datetime import date, datetime, timedelta

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
    _chat_modes: list[tuple[ChatScriptMode, dict[str, Any] | None]] = field(
        default_factory=list
    )
    _chat_index: int = 0
    _chat_context: dict[str, Any] = field(default_factory=dict)

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
    ) -> None:
        """Queue chat completion outcomes for non-streaming generation tests."""
        if context is not None:
            self._chat_context = context
        self._chat_modes.append((mode, custom))

    def ok(self, latency_ms: float = 50.0, model: LoadedModelInfo | None = None) -> None:
        model = model or LoadedModelInfo(name="qwen3:4b", digest="sha256:abc123")
        self._outcomes.append((PollOutcome.OK, latency_ms, model))

    def loading(self) -> None:
        self._outcomes.append((PollOutcome.LOADING, None, None))

    def error(self) -> None:
        self._outcomes.append((PollOutcome.ERROR, None, None))

    def timeout(self) -> None:
        self._outcomes.append((PollOutcome.TIMEOUT, None, None))

    def poll(self) -> dict[str, Any]:
        """Return the next scripted poll outcome as a dict."""
        if self._call_index >= len(self._outcomes):
            return {"outcome": PollOutcome.ERROR.value}

        outcome, latency, model = self._outcomes[self._call_index]
        self._call_index += 1

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

    def chat_completion_response(self) -> dict[str, Any]:
        """OpenAI-compatible /v1/chat/completions response for the next scripted mode."""
        if self._chat_index >= len(self._chat_modes):
            raise RuntimeError("no scripted chat completion remaining")

        mode, custom = self._chat_modes[self._chat_index]
        self._chat_index += 1
        body = envelope_for_mode(
            mode,
            context=self._chat_context,
            custom=custom,
        )
        content = body if isinstance(body, str) else json.dumps(body)
        return {
            "id": "chatcmpl-fake",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": content},
                    "finish_reason": "stop",
                }
            ],
            "usage": {"prompt_tokens": 120, "completion_tokens": 80, "total_tokens": 200},
        }

    def reset(self) -> None:
        self._outcomes.clear()
        self._call_index = 0
        self._chat_modes.clear()
        self._chat_index = 0
        self._chat_context.clear()
