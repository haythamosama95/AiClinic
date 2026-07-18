"""Runner selection: capability match → health filter → least-busy + round-robin."""

from __future__ import annotations

from typing import TYPE_CHECKING

import httpx

from gateway.config.settings import GatewayConfig
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import RunnerRegistry, RunnerRegistryEntry

if TYPE_CHECKING:
    pass

_HEALTH_PRIORITY: dict[RunnerStatus, int] = {
    RunnerStatus.READY: 0,
    RunnerStatus.DEGRADED: 1,
}

_ROUTABLE = frozenset({RunnerStatus.READY, RunnerStatus.DEGRADED})


def _capability_match(entry: RunnerRegistryEntry, required: list[str]) -> bool:
    if not required:
        return True
    return all(cap in entry.declared_capabilities for cap in required)


def _health_eligible(entry: RunnerRegistryEntry) -> bool:
    return entry.status in _ROUTABLE


class RunnerSelector:
    """Selects runners by capability, health, least-busy load, and round-robin ties.

    Clients cannot supply runner addresses; only logical capability requirements are
    accepted (FR-028).
    """

    def __init__(self) -> None:
        self._round_robin_counter = 0

    def select(
        self,
        entries: list[RunnerRegistryEntry],
        *,
        required_capabilities: list[str],
    ) -> RunnerRegistryEntry | None:
        """Return the best runner or ``None`` when no candidate qualifies."""
        capable = [
            entry
            for entry in entries
            if _capability_match(entry, required_capabilities)
        ]
        if not capable:
            return None

        healthy = [entry for entry in capable if _health_eligible(entry)]
        if not healthy:
            return None

        best_health = min(_HEALTH_PRIORITY[entry.status] for entry in healthy)
        preferred = [
            entry for entry in healthy if _HEALTH_PRIORITY[entry.status] == best_health
        ]

        min_in_flight = min(entry.in_flight for entry in preferred)
        least_busy = [entry for entry in preferred if entry.in_flight == min_in_flight]
        least_busy.sort(key=lambda entry: entry.id)

        chosen = least_busy[self._round_robin_counter % len(least_busy)]
        self._round_robin_counter += 1
        return chosen


class SelectorState:
    """Holds round-robin state across repeated selection calls."""

    def __init__(self) -> None:
        self._selector = RunnerSelector()


def select_runner(
    registry: RunnerRegistry,
    *,
    required_capabilities: list[str],
    round_robin_state: SelectorState,
) -> RunnerRegistryEntry | None:
    """Select the best runner from the live registry snapshot."""
    return round_robin_state._selector.select(
        registry.snapshot(),
        required_capabilities=required_capabilities,
    )


async def select_runner_with_swap(
    registry: RunnerRegistry,
    *,
    required_capabilities: list[str],
    round_robin_state: SelectorState,
    config: GatewayConfig,
    request_id: str,
    client: httpx.AsyncClient | None = None,
) -> RunnerRegistryEntry:
    """Select a runner, auto-triggering model swap when no READY match exists."""
    from gateway.pipeline.swap import ensure_capable_runner

    entry = select_runner(
        registry,
        required_capabilities=required_capabilities,
        round_robin_state=round_robin_state,
    )
    if entry is not None:
        return entry

    await ensure_capable_runner(
        registry,
        required_capabilities=required_capabilities,
        config=config,
        client=client,
        request_id=request_id,
    )

    entry = select_runner(
        registry,
        required_capabilities=required_capabilities,
        round_robin_state=round_robin_state,
    )
    if entry is not None:
        return entry

    ready = registry.snapshot()
    for candidate in ready:
        if candidate.status == RunnerStatus.READY:
            return candidate
    raise RuntimeError("ensure_capable_runner succeeded but no READY runner found")
