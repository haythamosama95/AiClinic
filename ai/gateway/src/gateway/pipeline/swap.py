"""Auto-trigger model swap when no READY runner advertises the required capability."""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass

import httpx
import structlog

from gateway.api.errors import ErrorCode, GatewayError
from gateway.config.settings import GatewayConfig, ModelDef
from gateway.obs.metrics import record_ai_model_swap
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import RunnerRegistry, RunnerRegistryEntry

logger = structlog.get_logger("gateway.pipeline.swap")

_ROUTABLE = frozenset({RunnerStatus.READY, RunnerStatus.DEGRADED})


@dataclass(frozen=True)
class SwapCandidate:
    """A runner that can serve a capability after loading the required model."""

    entry: RunnerRegistryEntry
    model: ModelDef


def _capability_match(entry: RunnerRegistryEntry, required: list[str]) -> bool:
    if not required:
        return True
    return all(cap in entry.declared_capabilities for cap in required)


def _model_loaded(entry: RunnerRegistryEntry, model: ModelDef) -> bool:
    loaded = entry.loaded_model
    if loaded is None:
        return False
    return loaded.name == model.name and loaded.digest == model.digest


def find_swap_candidate(
    entries: list[RunnerRegistryEntry],
    *,
    required_capabilities: list[str],
) -> SwapCandidate | None:
    """Return the least-busy runner that can load a model providing the capability."""
    candidates: list[tuple[RunnerRegistryEntry, ModelDef]] = []
    for entry in entries:
        if entry.status == RunnerStatus.UNREACHABLE:
            continue
        if entry.status in _ROUTABLE and _capability_match(entry, required_capabilities):
            continue
        for model in entry.declared_models:
            if not all(cap in model.capabilities for cap in required_capabilities):
                continue
            if _model_loaded(entry, model):
                continue
            candidates.append((entry, model))

    if not candidates:
        return None

    candidates.sort(key=lambda pair: (pair[0].in_flight, pair[0].id))
    entry, model = candidates[0]
    return SwapCandidate(entry=entry, model=model)


def _pick_least_busy(entries: list[RunnerRegistryEntry]) -> RunnerRegistryEntry:
    min_in_flight = min(entry.in_flight for entry in entries)
    least_busy = [entry for entry in entries if entry.in_flight == min_in_flight]
    least_busy.sort(key=lambda entry: entry.id)
    return least_busy[0]


def find_ready_runner(
    entries: list[RunnerRegistryEntry],
    *,
    required_capabilities: list[str],
) -> RunnerRegistryEntry | None:
    """Return a READY/DEGRADED runner that already advertises the capability."""
    routable = [
        entry
        for entry in entries
        if entry.status in _ROUTABLE and _capability_match(entry, required_capabilities)
    ]
    if not routable:
        return None
    return _pick_least_busy(routable)


def _ollama_root(base_url: str) -> str:
    """Strip OpenAI-compatible /v1 suffix to reach the Ollama root."""
    root = base_url.rstrip("/")
    if root.endswith("/v1"):
        return root[:-3]
    return root


async def emit_model_swap(
    base_url: str,
    model_name: str,
    *,
    client: httpx.AsyncClient | None = None,
    timeout_s: float = 30.0,
) -> None:
    """Trigger an Ollama model load via POST /api/load."""
    url = _ollama_root(base_url).rstrip("/") + "/api/load"

    owns_client = client is None
    http = client or httpx.AsyncClient()
    try:
        response = await http.post(
            url,
            json={"name": model_name},
            timeout=timeout_s,
        )
        if response.status_code >= 400:
            raise httpx.HTTPStatusError(
                f"model load returned {response.status_code}",
                request=response.request,
                response=response,
            )
    finally:
        if owns_client:
            await http.aclose()


async def wait_for_runner_ready(
    registry: RunnerRegistry,
    runner_id: str,
    *,
    timeout_s: float,
    poll_interval_s: float = 0.25,
    client: httpx.AsyncClient | None = None,
) -> RunnerRegistryEntry | None:
    """Poll the registry and runner until READY or the timeout elapses."""
    from gateway.runners.openai_client import poll_runner
    from gateway.routing.lifecycle import PollOutcome

    deadline = time.monotonic() + timeout_s
    owns_client = client is None
    http = client or httpx.AsyncClient()
    try:
        while time.monotonic() < deadline:
            entry = registry.get(runner_id)
            if entry is None:
                return None
            if entry.status == RunnerStatus.READY and entry.loaded_model is not None:
                return entry
            if entry.status == RunnerStatus.UNREACHABLE:
                return None

            preferred_models = [model.name for model in entry.declared_models]
            poll_result = await poll_runner(
                entry.base_url,
                client=http,
                preferred_models=preferred_models,
            )
            if poll_result.outcome == PollOutcome.OK and poll_result.loaded_model is not None:
                registry.update_entry(
                    runner_id,
                    status=RunnerStatus.READY,
                    loaded_model=poll_result.loaded_model,
                )
                return registry.get(runner_id)

            await asyncio.sleep(poll_interval_s)
    finally:
        if owns_client:
            await http.aclose()
    return registry.get(runner_id)


async def ensure_capable_runner(
    registry: RunnerRegistry,
    *,
    required_capabilities: list[str],
    config: GatewayConfig,
    client: httpx.AsyncClient | None = None,
    request_id: str | None = None,
) -> RunnerRegistryEntry:
    """Select a READY runner or auto-trigger a model swap; raise ai_no_capacity on failure."""
    entries = registry.snapshot()
    ready = find_ready_runner(entries, required_capabilities=required_capabilities)
    if ready is not None:
        return ready

    candidate = find_swap_candidate(entries, required_capabilities=required_capabilities)
    if candidate is None:
        raise GatewayError(
            ErrorCode.AI_NO_CAPACITY,
            "No runner available to serve the requested capability",
            request_id,
        )

    registry.update_entry(candidate.entry.id, status=RunnerStatus.STARTING)
    logger.info(
        "model_swap_triggered",
        runner_id=candidate.entry.id,
        model=candidate.model.name,
    )

    try:
        await emit_model_swap(
            candidate.entry.base_url,
            candidate.model.name,
            client=client,
        )
        ready_entry = await wait_for_runner_ready(
            registry,
            candidate.entry.id,
            timeout_s=float(config.model_swap_first_token_timeout_s),
            client=client,
        )
        if ready_entry is not None and ready_entry.status == RunnerStatus.READY:
            record_ai_model_swap(candidate.entry.id, "ok")
            return ready_entry
        record_ai_model_swap(candidate.entry.id, "timeout")
        raise GatewayError(
            ErrorCode.AI_NO_CAPACITY,
            "Model swap did not complete within the configured timeout",
            request_id,
        )
    except httpx.HTTPError as exc:
        record_ai_model_swap(candidate.entry.id, "error")
        logger.warning(
            "model_swap_failed",
            runner_id=candidate.entry.id,
            error=str(exc),
        )
        raise GatewayError(
            ErrorCode.AI_NO_CAPACITY,
            "Model swap failed",
            request_id,
        ) from exc
