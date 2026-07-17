"""In-memory runner registry with atomic reads and readiness derivation."""

from __future__ import annotations

import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone

from gateway.config.settings import GatewayConfig, ModelDef, RunnerConfig
from gateway.routing.lifecycle import RunnerStatus


@dataclass
class LoadedModel:
    name: str
    digest: str
    context_tokens: int | None = None
    features: list[str] = field(default_factory=list)


@dataclass
class RunnerRegistryEntry:
    id: str
    base_url: str
    status: RunnerStatus = RunnerStatus.UNKNOWN
    last_seen_at: datetime | None = None
    last_latency_ms: float | None = None
    avg_latency_ms: float | None = None
    consecutive_failures: int = 0
    loaded_model: LoadedModel | None = None
    declared_capabilities: list[str] = field(default_factory=list)
    declared_models: list[ModelDef] = field(default_factory=list)
    in_flight: int = 0


class RunnerRegistry:
    """Thread-safe in-memory registry of configured runners."""

    def __init__(self, config: GatewayConfig) -> None:
        self._lock = threading.Lock()
        self._entries: dict[str, RunnerRegistryEntry] = {}
        self._dynamic_ids: set[str] = set()
        self.reload_from_config(config)

    def reload_from_config(self, config: GatewayConfig) -> None:
        with self._lock:
            config_ids = {runner.id for runner in config.runners}
            next_entries: dict[str, RunnerRegistryEntry] = {}
            for runner in config.runners:
                existing = self._entries.get(runner.id)
                if existing is not None:
                    existing.base_url = runner.base_url
                    existing.declared_capabilities = list(runner.capabilities)
                    existing.declared_models = list(runner.models)
                    next_entries[runner.id] = existing
                else:
                    next_entries[runner.id] = _entry_from_config(runner)
            for runner_id, entry in self._entries.items():
                if runner_id in self._dynamic_ids and runner_id not in config_ids:
                    next_entries[runner_id] = entry
            self._entries = next_entries

    def register_runner(
        self,
        runner_id: str,
        base_url: str,
        capabilities: list[str],
        models: list[ModelDef] | None = None,
        *,
        dynamic: bool = True,
    ) -> None:
        """Register or update a runner (push mode)."""
        with self._lock:
            existing = self._entries.get(runner_id)
            if existing is not None:
                existing.base_url = base_url
                existing.declared_capabilities = list(capabilities)
                existing.declared_models = list(models or [])
            else:
                self._entries[runner_id] = RunnerRegistryEntry(
                    id=runner_id,
                    base_url=base_url,
                    declared_capabilities=list(capabilities),
                    declared_models=list(models or []),
                )
            if dynamic:
                self._dynamic_ids.add(runner_id)

    def apply_heartbeat(
        self,
        runner_id: str,
        status: RunnerStatus,
        loaded_model: LoadedModel | None = None,
    ) -> bool:
        """Apply a push heartbeat. Returns False when the runner is unknown."""
        with self._lock:
            entry = self._entries.get(runner_id)
            if entry is None:
                return False
            entry.status = status
            entry.last_seen_at = utc_now()
            entry.consecutive_failures = 0
            if loaded_model is not None:
                entry.loaded_model = loaded_model
            return True

    def snapshot(self) -> list[RunnerRegistryEntry]:
        with self._lock:
            return [_clone_entry(entry) for entry in self._entries.values()]

    def get(self, runner_id: str) -> RunnerRegistryEntry | None:
        with self._lock:
            entry = self._entries.get(runner_id)
            return _clone_entry(entry) if entry is not None else None

    def update_entry(self, runner_id: str, **changes: object) -> None:
        with self._lock:
            entry = self._entries.get(runner_id)
            if entry is None:
                return
            for key, value in changes.items():
                setattr(entry, key, value)

    @property
    def ready(self) -> bool:
        with self._lock:
            return any(entry.status == RunnerStatus.READY for entry in self._entries.values())

    def runner_ids(self) -> list[str]:
        with self._lock:
            return list(self._entries.keys())


def _entry_from_config(runner: RunnerConfig) -> RunnerRegistryEntry:
    return RunnerRegistryEntry(
        id=runner.id,
        base_url=runner.base_url,
        declared_capabilities=list(runner.capabilities),
        declared_models=list(runner.models),
    )


def _clone_entry(entry: RunnerRegistryEntry) -> RunnerRegistryEntry:
    loaded = entry.loaded_model
    cloned_model = None
    if loaded is not None:
        cloned_model = LoadedModel(
            name=loaded.name,
            digest=loaded.digest,
            context_tokens=loaded.context_tokens,
            features=list(loaded.features),
        )
    return RunnerRegistryEntry(
        id=entry.id,
        base_url=entry.base_url,
        status=entry.status,
        last_seen_at=entry.last_seen_at,
        last_latency_ms=entry.last_latency_ms,
        avg_latency_ms=entry.avg_latency_ms,
        consecutive_failures=entry.consecutive_failures,
        loaded_model=cloned_model,
        declared_capabilities=list(entry.declared_capabilities),
        declared_models=list(entry.declared_models),
        in_flight=entry.in_flight,
    )


def utc_now() -> datetime:
    return datetime.now(tz=timezone.utc)  # noqa: UP017
