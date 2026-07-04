"""Reloadable role → ai.access map."""

from __future__ import annotations

import logging
import signal
import threading
from pathlib import Path
from typing import Any

import yaml

from gateway.config.settings import RoleAiAccessMap

logger = logging.getLogger(__name__)


class RoleMapStore:
    """Thread-safe, atomically reloadable role → ai.access map."""

    def __init__(self, initial: dict[str, bool] | None = None) -> None:
        self._lock = threading.RLock()
        self._map: RoleAiAccessMap = RoleAiAccessMap.from_mapping(initial)

    def has_ai_access(self, staff_role: str) -> bool:
        with self._lock:
            return bool(self._map.get(staff_role, False))

    def snapshot(self) -> dict[str, bool]:
        with self._lock:
            return dict(self._map)

    def reload(self, mapping: dict[str, bool]) -> None:
        """Atomically replace the role map (merges with defaults)."""
        new_map = RoleAiAccessMap.from_mapping(mapping)
        with self._lock:
            self._map = new_map
        logger.info("Role map reloaded", extra={"roles": list(new_map.keys())})

    def reload_from_file(self, path: Path) -> None:
        if not path.is_file():
            logger.warning("Role map file not found: %s", path)
            return
        with path.open(encoding="utf-8") as fh:
            raw = yaml.safe_load(fh) or {}
        if not isinstance(raw, dict):
            logger.warning("Role map file %s is not a mapping", path)
            return
        normalized = {str(k): bool(v) for k, v in raw.items()}
        self.reload(normalized)


class RoleMapReloader:
    """Background periodic re-read and optional SIGHUP reload for the role map."""

    def __init__(
        self,
        store: RoleMapStore,
        *,
        file_path: Path | None = None,
        interval_s: int = 60,
    ) -> None:
        self._store = store
        self._file_path = file_path
        self._interval_s = interval_s
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._previous_handler: Any = None

    def start(self) -> None:
        if self._file_path is not None:
            self._store.reload_from_file(self._file_path)
        self._thread = threading.Thread(target=self._loop, name="role-map-reloader", daemon=True)
        self._thread.start()
        try:
            self._previous_handler = signal.getsignal(signal.SIGHUP)

            def _on_sighup(signum: int, frame: Any) -> None:
                if self._file_path is not None:
                    self._store.reload_from_file(self._file_path)
                if callable(self._previous_handler):
                    self._previous_handler(signum, frame)

            signal.signal(signal.SIGHUP, _on_sighup)
        except (AttributeError, ValueError, OSError):
            # SIGHUP unavailable on some platforms (e.g. Windows)
            pass

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2.0)
            self._thread = None

    def _loop(self) -> None:
        while not self._stop.wait(self._interval_s):
            if self._file_path is not None:
                self._store.reload_from_file(self._file_path)
