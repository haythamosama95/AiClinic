"""Scriptable fake runner for driving lifecycle transitions in tests."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class PollOutcome(str, Enum):
    OK = "ok"
    LOADING = "loading"
    ERROR = "error"
    TIMEOUT = "timeout"


@dataclass
class LoadedModelInfo:
    name: str
    digest: str
    context_tokens: int = 8192
    features: list[str] = field(default_factory=list)


@dataclass
class FakeRunner:
    """In-memory fake runner whose poll responses are scripted on demand."""

    runner_id: str = "fake-runner-1"
    base_url: str = "http://127.0.0.1:19999"
    _outcomes: list[tuple[PollOutcome, float | None, LoadedModelInfo | None]] = field(
        default_factory=list
    )
    _call_index: int = 0

    def script(self, *outcomes: tuple[PollOutcome, float | None, LoadedModelInfo | None]) -> None:
        """Queue poll outcomes: ok(latency, model) / loading / error / timeout."""
        self._outcomes.extend(outcomes)
        self._call_index = 0

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

    def reset(self) -> None:
        self._outcomes.clear()
        self._call_index = 0
