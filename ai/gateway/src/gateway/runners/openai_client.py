"""OpenAI-compatible runner poll client for health and model discovery."""

from __future__ import annotations

import time
from dataclasses import dataclass

import httpx

from gateway.routing.lifecycle import PollOutcome
from gateway.routing.registry import LoadedModel

POLL_TIMEOUT_S = 2.0


@dataclass(frozen=True)
class PollResult:
    outcome: PollOutcome
    latency_ms: float | None = None
    loaded_model: LoadedModel | None = None


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
