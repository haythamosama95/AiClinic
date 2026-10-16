"""Governor run console summary (``console.log`` under the run root).

Each fresh run starts a new compact log. ``--continue`` / resume appends a new
session header to the existing log. Raw subprocess output belongs in campaign
``output.log`` files.
"""

from __future__ import annotations

import os
import sys
import threading
import traceback
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

GOVERNOR_CONSOLE_LOG_ENV = "AICLINIC_GOVERNOR_CONSOLE_LOG"
_CONSOLE_LOG_NAME = "console.log"
_lock = threading.Lock()
_depth = 0
_exception_hooks_installed = False
_orig_sys_excepthook: Any = None
_orig_thread_excepthook: Any = None


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def governor_console_log_path(run_root: Path) -> Path:
    return run_root.resolve() / _CONSOLE_LOG_NAME


def governor_console_log_active() -> bool:
    return bool(os.environ.get(GOVERNOR_CONSOLE_LOG_ENV))


def governor_console_log_line(line: str) -> None:
    path = os.environ.get(GOVERNOR_CONSOLE_LOG_ENV)
    if not path:
        return
    text = line if line.endswith("\n") else f"{line}\n"
    with _lock:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text)


def governor_console_output_path(campaign_log_dir: Path) -> Path:
    """Full merged stdout/stderr transcript for one campaign."""
    return campaign_log_dir.resolve() / "output.log"


def governor_console_log_note(message: str) -> None:
    """Harness / UI messages that are not subprocess stdout."""
    governor_console_log_line(f"{message}\n")


def _install_governor_console_exception_hooks() -> None:
    global _exception_hooks_installed, _orig_sys_excepthook, _orig_thread_excepthook
    if _exception_hooks_installed:
        return
    _exception_hooks_installed = True
    _orig_sys_excepthook = sys.excepthook

    def _sys_excepthook(
        exc_type: type[BaseException],
        exc: BaseException,
        tb: object,
    ) -> None:
        if governor_console_log_active():
            governor_console_log_note(
                f"uncaught exception in main thread: {exc_type.__name__}: {exc}"
            )
            for line in traceback.format_exception(exc_type, exc, tb):
                governor_console_log_line(line)
        if _orig_sys_excepthook is not None:
            _orig_sys_excepthook(exc_type, exc, tb)

    sys.excepthook = _sys_excepthook

    if hasattr(threading, "excepthook"):
        _orig_thread_excepthook = threading.excepthook

        def _thread_excepthook(args: threading.ExceptHookArgs) -> None:
            if governor_console_log_active():
                governor_console_log_note(
                    "uncaught exception in thread "
                    f"{args.thread.name!r}: "
                    f"{args.exc_type.__name__}: {args.exc_value}"
                )
                for line in traceback.format_exception(
                    args.exc_type, args.exc_value, args.exc_traceback
                ):
                    governor_console_log_line(line)
            if _orig_thread_excepthook is not None:
                _orig_thread_excepthook(args)

        threading.excepthook = _thread_excepthook


@contextmanager
def attach_governor_console_log(
    run_root: Path,
    *,
    meta: dict[str, Any] | None = None,
) -> Iterator[Path]:
    """Enable ``governor_console_log_line`` for this process and descendants."""
    global _depth
    run_root = run_root.resolve()
    path = governor_console_log_path(run_root)
    run_root.mkdir(parents=True, exist_ok=True)

    with _lock:
        _depth += 1
        first = _depth == 1
        if first:
            os.environ[GOVERNOR_CONSOLE_LOG_ENV] = str(path)
            _install_governor_console_exception_hooks()
            header = f"\n{'=' * 72}\nGovernor campaign summary started {_utc_now()}\n"
            header += f"run_root: {run_root}\n"
            if meta:
                for key, value in meta.items():
                    header += f"{key}: {value}\n"
            header += f"{'=' * 72}\n"
            open_mode = "a" if meta and meta.get("resume") else "w"
            if open_mode == "w" and path.is_file() and path.stat().st_size > 0:
                # Nested attaches in one process must never truncate the active session.
                open_mode = "a"
            with path.open(open_mode, encoding="utf-8") as handle:
                handle.write(header)

    try:
        yield path
    finally:
        with _lock:
            _depth -= 1
            if _depth == 0:
                footer = f"{'=' * 72}\nGovernor campaign summary ended {_utc_now()}\n{'=' * 72}\n"
                with path.open("a", encoding="utf-8") as handle:
                    handle.write(footer)
                os.environ.pop(GOVERNOR_CONSOLE_LOG_ENV, None)
