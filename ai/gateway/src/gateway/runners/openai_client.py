"""OpenAI-compatible runner client for health polling and grammar-constrained generation."""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Any

import httpx

from gateway.routing.lifecycle import PollOutcome
from gateway.routing.registry import LoadedModel

POLL_TIMEOUT_S = 2.0
GENERATION_TIMEOUT_S = 45.0


@dataclass(frozen=True)
class PollResult:
    outcome: PollOutcome
    latency_ms: float | None = None
    loaded_model: LoadedModel | None = None


@dataclass(frozen=True)
class GenerationResult:
    parsed: dict[str, Any]
    model: str
    digest: str
    prompt_tokens: int
    completion_tokens: int
    total_seconds: float
    first_token_seconds: float | None = None


async def poll_runner(
    base_url: str,
    *,
    timeout_s: float = POLL_TIMEOUT_S,
    client: httpx.AsyncClient | None = None,
) -> PollResult:
    """Poll a runner via GET /v1/models (and optional GET /health).

    Bounded timeout (default ≤2 s). Returns ok/loading/error/timeout outcomes.
    """
    url = base_url.rstrip("/") + "/v1/models"
    started = time.perf_counter()

    owns_client = client is None
    http = client or httpx.AsyncClient()

    try:
        response = await http.get(url, timeout=timeout_s)
        latency_ms = (time.perf_counter() - started) * 1000.0

        if response.status_code != 200:
            return PollResult(outcome=PollOutcome.ERROR, latency_ms=latency_ms)

        payload = response.json()
        models = payload.get("data") if isinstance(payload, dict) else None
        if not models:
            return PollResult(outcome=PollOutcome.LOADING, latency_ms=latency_ms)

        first = models[0]
        if not isinstance(first, dict) or not first.get("id"):
            return PollResult(outcome=PollOutcome.LOADING, latency_ms=latency_ms)

        digest = first.get("digest") or ""
        context = first.get("context_length")
        loaded = LoadedModel(
            name=str(first["id"]),
            digest=str(digest),
            context_tokens=int(context) if context is not None else None,
        )
        return PollResult(
            outcome=PollOutcome.OK,
            latency_ms=latency_ms,
            loaded_model=loaded,
        )
    except httpx.TimeoutException:
        latency_ms = (time.perf_counter() - started) * 1000.0
        return PollResult(outcome=PollOutcome.TIMEOUT, latency_ms=latency_ms)
    except httpx.HTTPError:
        latency_ms = (time.perf_counter() - started) * 1000.0
        return PollResult(outcome=PollOutcome.ERROR, latency_ms=latency_ms)
    finally:
        if owns_client:
            await http.aclose()


def _extract_json_content(content: str) -> dict[str, Any]:
    """Parse model content, tolerating an optional leading summary prefix."""
    text = content.strip()
    if not text:
        raise ValueError("empty model content")

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("no JSON object found in model content")

    parsed = json.loads(text[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError("model JSON must be an object")
    return parsed


async def chat_completion_grammar(
    base_url: str,
    *,
    model: str,
    digest: str,
    messages: list[dict[str, str]],
    format_schema: dict[str, Any],
    timeout_s: float = GENERATION_TIMEOUT_S,
    client: httpx.AsyncClient | None = None,
) -> GenerationResult:
    """Grammar-constrained non-streaming chat completion via Ollama OpenAI API."""
    url = base_url.rstrip("/") + "/v1/chat/completions"
    started = time.perf_counter()

    owns_client = client is None
    http = client or httpx.AsyncClient()

    body = {
        "model": model,
        "messages": messages,
        "stream": False,
        "format": format_schema,
    }

    try:
        response = await http.post(url, json=body, timeout=timeout_s)
        total_seconds = time.perf_counter() - started

        if response.status_code != 200:
            raise httpx.HTTPStatusError(
                f"runner returned {response.status_code}",
                request=response.request,
                response=response,
            )

        payload = response.json()
        choices = payload.get("choices") if isinstance(payload, dict) else None
        if not choices or not isinstance(choices, list):
            raise ValueError("runner response missing choices")

        message = choices[0].get("message", {}) if isinstance(choices[0], dict) else {}
        content = message.get("content", "") if isinstance(message, dict) else ""
        parsed = _extract_json_content(str(content))

        usage = payload.get("usage", {}) if isinstance(payload, dict) else {}
        prompt_tokens = int(usage.get("prompt_tokens") or 0)
        completion_tokens = int(usage.get("completion_tokens") or 0)

        return GenerationResult(
            parsed=parsed,
            model=model,
            digest=digest,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_seconds=total_seconds,
            first_token_seconds=total_seconds,
        )
    finally:
        if owns_client:
            await http.aclose()
