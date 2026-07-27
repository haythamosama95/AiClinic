"""OpenAI-compatible runner client for health polling and grammar-constrained generation."""

from __future__ import annotations

import json
import time
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any

import httpx
import jsonschema
from ai_common.verbose_logging import (
    dump_json_for_log,
    get_logger,
    health_poll_verbose_enabled,
    log_request_v2,
    log_response_v2,
)

from gateway.routing.lifecycle import PollOutcome
from gateway.routing.registry import LoadedModel

POLL_TIMEOUT_S = 2.0
GENERATION_TIMEOUT_S = 45.0

vlog = get_logger(__name__)


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


@dataclass(frozen=True)
class StreamDelta:
    """One decoded content delta from a runner streaming chat completion."""

    content: str


@dataclass
class GrammarStreamSession:
    """Accumulates a grammar-constrained streaming chat completion."""

    model: str
    digest: str
    content: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_seconds: float = 0.0
    first_token_seconds: float | None = None

    def feed(self, delta: str) -> None:
        if delta:
            self.content += delta

    def parsed_json(self) -> dict[str, Any]:
        """Parse the buffered model output as a JSON object."""
        return _extract_json_content(self.content)

    def parsed_json_matching_schema(self, format_schema: dict[str, Any]) -> dict[str, Any]:
        """Return the last JSON object in the buffer that matches ``format_schema``."""
        parsed = _extract_json_matching_schema(self.content, format_schema)
        if parsed is None:
            raise ValueError("no JSON object matching schema found in model content")
        return parsed

    def to_generation_result(self, *, format_schema: dict[str, Any] | None = None) -> GenerationResult:
        parsed = (
            self.parsed_json_matching_schema(format_schema)
            if format_schema is not None
            else self.parsed_json()
        )
        return GenerationResult(
            parsed=parsed,
            model=self.model,
            digest=self.digest,
            prompt_tokens=self.prompt_tokens,
            completion_tokens=self.completion_tokens,
            total_seconds=self.total_seconds,
            first_token_seconds=self.first_token_seconds,
        )


async def poll_runner(
    base_url: str,
    *,
    timeout_s: float = POLL_TIMEOUT_S,
    client: httpx.AsyncClient | None = None,
    preferred_models: list[str] | None = None,
) -> PollResult:
    """Poll a runner via GET /v1/models (and optional GET /health).

    When ``preferred_models`` is set, the first listed model present in the
    runner catalog is treated as loaded; otherwise the first catalog entry is used.

    Bounded timeout (default ≤2 s). Returns ok/loading/error/timeout outcomes.
    """
    poll_verbose = health_poll_verbose_enabled()
    if poll_verbose:
        vlog.v0("Polling runner health endpoint", base_url=base_url)
    url = base_url.rstrip("/") + "/v1/models"
    started = time.perf_counter()

    owns_client = client is None
    http = client or httpx.AsyncClient()

    try:
        response = await http.get(url, timeout=timeout_s)
        latency_ms = (time.perf_counter() - started) * 1000.0

        if response.status_code != 200:
            if poll_verbose:
                vlog.v0(
                    "Runner health poll returned error status",
                    http_status=response.status_code,
                    latency_ms=latency_ms,
                )
            return PollResult(outcome=PollOutcome.ERROR, latency_ms=latency_ms)

        payload = response.json()
        if poll_verbose:
            log_response_v2(
                vlog,
                "Runner health poll",
                payload,
                base_url=base_url,
            )
        models = payload.get("data") if isinstance(payload, dict) else None
        if not models:
            if poll_verbose:
                vlog.v1("Runner is loading; no models available yet", latency_ms=latency_ms)
            return PollResult(outcome=PollOutcome.LOADING, latency_ms=latency_ms)

        chosen: dict[str, Any] | None = None
        if preferred_models:
            preferred = set(preferred_models)
            for item in models:
                if isinstance(item, dict) and item.get("id") in preferred:
                    chosen = item
                    break
        if chosen is None:
            first = models[0]
            chosen = first if isinstance(first, dict) else None
        if chosen is None or not chosen.get("id"):
            if poll_verbose:
                vlog.v1("Runner catalog has no usable model", latency_ms=latency_ms)
            return PollResult(outcome=PollOutcome.LOADING, latency_ms=latency_ms)

        digest = chosen.get("digest") or ""
        context = chosen.get("context_length")
        loaded = LoadedModel(
            name=str(chosen["id"]),
            digest=str(digest),
            context_tokens=int(context) if context is not None else None,
        )
        if poll_verbose:
            vlog.v1(
                "Runner health poll succeeded",
                model=loaded.name,
                latency_ms=latency_ms,
            )
        return PollResult(
            outcome=PollOutcome.OK,
            latency_ms=latency_ms,
            loaded_model=loaded,
        )
    except httpx.TimeoutException:
        latency_ms = (time.perf_counter() - started) * 1000.0
        if poll_verbose:
            vlog.v0("Runner health poll timed out", latency_ms=latency_ms)
        return PollResult(outcome=PollOutcome.TIMEOUT, latency_ms=latency_ms)
    except httpx.HTTPError:
        latency_ms = (time.perf_counter() - started) * 1000.0
        if poll_verbose:
            vlog.v0("Runner health poll HTTP error", latency_ms=latency_ms)
        return PollResult(outcome=PollOutcome.ERROR, latency_ms=latency_ms)
    finally:
        if owns_client:
            await http.aclose()


def _extract_json_content(content: str) -> dict[str, Any]:
    """Parse model content, tolerating an optional leading summary prefix."""
    parsed = _extract_json_matching_schema(content, schema=None)
    if parsed is None:
        raise ValueError("no JSON object found in model content")
    return parsed


def _iter_json_object_candidates(text: str) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    start = 0
    while start < len(text):
        brace = text.find("{", start)
        if brace == -1:
            break
        depth = 0
        for index in range(brace, len(text)):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    fragment = text[brace : index + 1]
                    try:
                        parsed = json.loads(fragment)
                    except json.JSONDecodeError:
                        start = brace + 1
                        break
                    if isinstance(parsed, dict):
                        candidates.append(parsed)
                    start = index + 1
                    break
        else:
            break
    return candidates


def _extract_json_matching_schema(
    content: str,
    schema: dict[str, Any] | None,
) -> dict[str, Any] | None:
    """Return the last JSON object in ``content`` that validates against ``schema``."""
    text = content.strip()
    if not text:
        return None

    if schema is None:
        try:
            parsed = json.loads(text)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass

    candidates = _iter_json_object_candidates(text)
    if not candidates:
        return None

    if schema is None:
        return candidates[-1]

    for candidate in reversed(candidates):
        try:
            jsonschema.validate(candidate, schema)
        except jsonschema.ValidationError:
            continue
        return candidate
    return None


def _ollama_root(base_url: str) -> str:
    """Strip OpenAI-compatible /v1 suffix to reach the Ollama root."""
    root = base_url.rstrip("/")
    if root.endswith("/v1"):
        return root[:-3]
    return root


def _ollama_chat_url(base_url: str) -> str:
    return _ollama_root(base_url).rstrip("/") + "/api/chat"


def _grammar_chat_body(
    *,
    model: str,
    messages: list[dict[str, str]],
    format_schema: dict[str, Any],
    stream: bool,
) -> dict[str, Any]:
    """Ollama native chat body — ``think: false`` for reliable JSON schema output."""
    return {
        "model": model,
        "messages": messages,
        "stream": stream,
        "format": format_schema,
        "think": False,
    }


def _content_from_ollama_chat_payload(payload: dict[str, Any]) -> str:
    message = payload.get("message")
    if isinstance(message, dict):
        content = message.get("content")
        if content:
            return str(content)
    return ""


def _usage_from_ollama_chat_payload(payload: dict[str, Any]) -> tuple[int, int]:
    return (
        int(payload.get("prompt_eval_count") or 0),
        int(payload.get("eval_count") or 0),
    )


async def _iter_ollama_ndjson(
    response: httpx.Response,
) -> AsyncIterator[dict[str, Any]]:
    """Parse newline-delimited JSON from Ollama ``/api/chat`` streaming."""
    async for line in response.aiter_lines():
        stripped = line.strip()
        if not stripped:
            continue
        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            yield payload


def _delta_from_openai_chunk(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not choices or not isinstance(choices, list):
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    delta = first.get("delta", {})
    if not isinstance(delta, dict):
        return ""
    content = delta.get("content")
    return str(content) if content else ""


async def _iter_openai_sse_chunks(
    response: httpx.Response,
) -> AsyncIterator[dict[str, Any]]:
    """Parse OpenAI-compatible ``data:`` SSE lines from a runner response."""
    async for line in response.aiter_lines():
        stripped = line.strip()
        if not stripped or stripped.startswith(":"):
            continue
        if not stripped.startswith("data:"):
            continue
        data = stripped[5:].strip()
        if data == "[DONE]":
            return
        try:
            payload = json.loads(data)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            yield payload


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
    """Grammar-constrained non-streaming chat completion via Ollama native ``/api/chat``."""
    vlog.v0("Sending grammar-constrained chat completion", model=model)
    url = _ollama_chat_url(base_url)
    started = time.perf_counter()

    owns_client = client is None
    http = client or httpx.AsyncClient()

    body = _grammar_chat_body(
        model=model,
        messages=messages,
        format_schema=format_schema,
        stream=False,
    )
    log_request_v2(
        vlog,
        "Sending grammar-constrained chat completion",
        body,
        model=model,
        url=url,
    )

    try:
        response = await http.post(url, json=body, timeout=timeout_s)
        total_seconds = time.perf_counter() - started

        if response.status_code != 200:
            vlog.v0("Grammar chat completion returned HTTP error", status_code=response.status_code)
            raise httpx.HTTPStatusError(
                f"runner returned {response.status_code}",
                request=response.request,
                response=response,
            )

        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("runner response must be a JSON object")

        log_response_v2(
            vlog,
            "Runner chat completion",
            payload,
            model=model,
            url=url,
        )

        content = _content_from_ollama_chat_payload(payload)
        parsed = _extract_json_content(content)
        prompt_tokens, completion_tokens = _usage_from_ollama_chat_payload(payload)

        vlog.v1(
            "Grammar chat completion succeeded",
            model=model,
            total_seconds=total_seconds,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
        )
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


async def chat_completion_grammar_stream(
    base_url: str,
    *,
    model: str,
    digest: str,
    messages: list[dict[str, str]],
    format_schema: dict[str, Any],
    timeout_s: float = GENERATION_TIMEOUT_S,
    client: httpx.AsyncClient | None = None,
) -> AsyncIterator[tuple[StreamDelta, GrammarStreamSession]]:
    """Grammar-constrained streaming chat completion via Ollama native ``/api/chat``.

    Yields ``(delta, session)`` pairs where ``session`` accumulates the full
    buffered content. After iteration completes, call
    ``session.parsed_json_matching_schema(format_schema)`` for command tasks.
    """
    vlog.v0("Starting grammar-constrained streaming completion", model=model)
    url = _ollama_chat_url(base_url)
    started = time.perf_counter()
    first_token_at: float | None = None

    owns_client = client is None
    http = client or httpx.AsyncClient()

    body = _grammar_chat_body(
        model=model,
        messages=messages,
        format_schema=format_schema,
        stream=True,
    )
    log_request_v2(
        vlog,
        "Sending grammar-constrained streaming chat completion",
        body,
        model=model,
        url=url,
    )

    session = GrammarStreamSession(model=model, digest=digest)
    vlog.v1("Created grammar streaming session", model=model)

    try:
        async with http.stream("POST", url, json=body, timeout=timeout_s) as response:
            if response.status_code != 200:
                vlog.v0("Grammar streaming completion returned HTTP error", status_code=response.status_code)
                await response.aread()
                raise httpx.HTTPStatusError(
                    f"runner returned {response.status_code}",
                    request=response.request,
                    response=response,
                )

            async for chunk in _iter_ollama_ndjson(response):
                delta_text = _content_from_ollama_chat_payload(chunk)
                if delta_text and first_token_at is None:
                    first_token_at = time.perf_counter()
                    vlog.v2(
                        "Runner streaming chat completion first chunk received",
                        model=model,
                        body=dump_json_for_log(chunk),
                    )

                if chunk.get("done"):
                    prompt_tokens, completion_tokens = _usage_from_ollama_chat_payload(
                        chunk
                    )
                    session.prompt_tokens = prompt_tokens
                    session.completion_tokens = completion_tokens
                    vlog.v2(
                        "Runner streaming chat completion final chunk received",
                        model=model,
                        body=dump_json_for_log(chunk),
                    )

                if delta_text:
                    session.feed(delta_text)
                    yield StreamDelta(content=delta_text), session

        session.total_seconds = time.perf_counter() - started
        session.first_token_seconds = (
            (first_token_at - started) if first_token_at is not None else None
        )
        vlog.v1(
            "Grammar streaming completion finished",
            model=model,
            total_seconds=session.total_seconds,
            first_token_seconds=session.first_token_seconds,
        )
        log_response_v2(
            vlog,
            "Runner streaming chat completion assembled",
            {
                "model": session.model,
                "digest": session.digest,
                "content": session.content,
                "prompt_tokens": session.prompt_tokens,
                "completion_tokens": session.completion_tokens,
                "total_seconds": session.total_seconds,
                "first_token_seconds": session.first_token_seconds,
            },
            model=model,
        )
    finally:
        if owns_client:
            await http.aclose()
