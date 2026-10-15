"""Live stderr progress: status header and pass/fail counts."""

from __future__ import annotations

import json
import os
import re
import sys
from collections import deque
from pathlib import Path
import threading
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Callable, Literal, Optional, Sequence, TextIO

if TYPE_CHECKING:
    from harness.campaign_logging import CampaignLogSession

_Phase = Literal["starting", "running", "between", "done"]

_STEP_HEADER = re.compile(r"^==\s*\[(\d+)\]\s+(.+?)\s*==\s*$")
_SEQUENCE_STEP = re.compile(r"^==\s+(?!\[\d+\])(.+?)\s*==\s*$")
_VITEST_PASS = re.compile(r"^\s*(?:✓|✔)\s+(.+?)\s*$")
_VITEST_FAIL = re.compile(r"^\s*(?:×|✗|x)\s+(.+?)\s*$", re.IGNORECASE)
_VITEST_FAIL_FILE = re.compile(
    r"^\s*FAIL\s+(\S+\.test\.\S+)\s*>\s*(.+?)\s*$",
    re.IGNORECASE,
)
_NODE_PASS = re.compile(r"^\s*✔\s+(.+?)\s*$")
_NODE_FAIL = re.compile(r"^\s*✖\s+(.+?)\s*$")
_NODE_TAP_OK = re.compile(r"^ok \d+(?:\s+-\s+(.+))?\s*$")
_NODE_TAP_NOT_OK = re.compile(r"^not ok \d+(?:\s+-\s+(.+))?\s*$")
_TAP_DIAGNOSTIC_SKIP = re.compile(
    r"^(Binding|Mode|env\.\w+|Your Worker has access|Service bindings)",
)
_FATAL_WORKERD = re.compile(
    r"(Fatal uncaught kj::Exception|MiniflareCoreError \[ERR_RUNTIME_FAILURE\])"
)
# ``info: uncaught exception`` is routine workerd logging during expected test throws.
_WORKERD_UNCAUGHT = re.compile(
    r"workerd/.*:\s*(?:error|warn):\s*uncaught exception",
    re.IGNORECASE,
)
_LABEL = re.compile(r"^\[([^/]+)/([^\]]+)\]\s*$")
_ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
_VITEST_DURATION_MS = re.compile(r"(\d+(?:\.\d+)?)\s*ms")


def _strip_ansi(text: str) -> str:
    return _ANSI_ESCAPE.sub("", text)


def _node_tap_progress_label(stripped: str) -> str | None:
    """Short label from node --test TAP ``#`` diagnostics (wrangler bootstrap, etc.)."""
    if not stripped.startswith("# ") or stripped.startswith("# Subtest:"):
        return None
    body = stripped[2:].strip()
    if not body or len(body) > 200 or _TAP_DIAGNOSTIC_SKIP.match(body):
        return None
    if "Starting local server" in body or body.startswith("⎔"):
        return body[:100]
    if body.startswith("***") or body.startswith("Using secrets"):
        return body[:120]
    if _FATAL_WORKERD.search(body) or "failed:" in body or body.startswith("Fatal"):
        return body[:160]
    if "MiniflareCoreError" in body or "ERR_RUNTIME_FAILURE" in body:
        return body[:160]
    return None


def _parse_vitest_duration_seconds(raw: str) -> float | None:
    matches = list(_VITEST_DURATION_MS.finditer(raw))
    if not matches:
        return None
    return float(matches[-1].group(1)) / 1000.0

if TYPE_CHECKING:
    from rich.console import Console
    from rich.live import Live


def _format_elapsed(seconds: float) -> str:
    total = int(max(0.0, seconds))
    minutes, secs = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def _rich_available() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    try:
        import rich  # noqa: F401
    except ImportError:
        return False
    return True


_RICH_WARNED = False


def warn_if_rich_missing_for_tty() -> None:
    """One-line hint when stderr is a TTY but Rich is not on sys.executable."""
    global _RICH_WARNED
    if _RICH_WARNED or os.environ.get("NO_COLOR"):
        return
    if not sys.stderr.isatty() or _rich_available():
        return
    _RICH_WARNED = True
    req = Path(__file__).resolve().parent.parent / "requirements.txt"
    sys.stderr.write(
        f"note: Rich is not installed for {sys.executable}; using plain live UI.\n"
        f"Install: {sys.executable} -m pip install --user -r {req}\n\n"
    )
    sys.stderr.flush()


@dataclass
class _FailureTree:
    children: dict[str, _FailureTree] = field(default_factory=dict)
    failures: list[str] = field(default_factory=list)

    def insert(self, path: tuple[str, ...], test_name: str) -> None:
        if not path:
            self.failures.append(test_name)
            return
        child = self.children.setdefault(path[0], _FailureTree())
        child.insert(path[1:], test_name)

    def is_empty(self) -> bool:
        return not self.failures and not self.children


def _parse_status_label(label: str) -> tuple[str, str]:
    stripped = label.strip()
    match = _LABEL.match(stripped)
    if match:
        return match.group(1), match.group(2)
    return stripped, ""


def _failure_path_and_leaf(
    nested: tuple[str, ...], test_name: str
) -> tuple[tuple[str, ...], str]:
    """Split ``Group label: detail`` into a tree branch and leaf (backend SQL steps)."""
    if ": " in test_name:
        group, leaf = test_name.split(": ", 1)
        group = group.strip()
        leaf = leaf.strip()
        if group and leaf:
            return nested + (group,), leaf
    return nested, test_name


def _render_failure_tree_plain(tree: _FailureTree) -> list[str]:
    lines: list[str] = []

    def walk(node: _FailureTree, prefix: str) -> None:
        child_keys = sorted(node.children.keys())
        failure_items = list(node.failures)
        entries: list[tuple[str, str]] = [(k, "child") for k in child_keys]
        entries.extend((name, "fail") for name in failure_items)
        for index, (name, kind) in enumerate(entries):
            last = index == len(entries) - 1
            branch = "└─ " if last else "├─ "
            lines.append(f"{prefix}{branch}{name}")
            if kind == "child":
                extension = "   " if last else "│  "
                walk(node.children[name], prefix + extension)

    walk(tree, "")
    return lines


def _populate_rich_tree(branch: Any, node: _FailureTree) -> None:
    from rich.tree import Tree

    assert isinstance(branch, Tree)
    for key in sorted(node.children.keys()):
        child = branch.add(f"[bold cyan]{key}[/]")
        _populate_rich_tree(child, node.children[key])
    for fail in node.failures:
        branch.add(f"[red]✗[/] [bright_white]{fail}[/]")


def _build_failure_rich_tree(tree: _FailureTree) -> Any:
    from rich import box
    from rich.panel import Panel
    from rich.tree import Tree

    inner = Tree(
        "[dim]Grouped by suite[/]",
        guide_style="bright_black",
        hide_root=True,
    )
    for key in sorted(tree.children.keys()):
        branch = inner.add(f"[bold orange1]{key}[/]")
        _populate_rich_tree(branch, tree.children[key])
    for fail in tree.failures:
        inner.add(f"[red]✗[/] [bright_white]{fail}[/]")

    return Panel(
        inner,
        title="[bold red]Failures[/]",
        subtitle="[dim]only failing cases are listed[/]",
        border_style="red",
        box=box.ROUNDED,
        padding=(0, 1),
    )


STALL_GRACE_SECONDS = 15.0
POST_CRASH_GRACE_SECONDS = 8.0
_CRASH_IMMEDIATE_SETTLE_SECONDS = 0.75
_TRACE_BACK_START = re.compile(r"^Traceback \(most recent call last\):")
_DART_UNHANDLED = re.compile(r"^Unhandled exception:")
_FLUTTER_TEST_EXCEPTION = re.compile(
    r"EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|══╡.*EXCEPTION.*╞═"
)
_NODE_UNHANDLED_REJECTION = re.compile(
    r"UnhandledPromiseRejection|Unhandled 'error'|Unhandled 'rejection'"
)
_VITEST_UNHANDLED = re.compile(
    r"Unhandled Errors|Vitest caught \d+ unhandled|Error: Hook timed out"
)

_STALL_PLACEHOLDER_CURRENTS = frozenset(
    {
        "(starting…)",
        "Collecting tests…",
        "Starting worker runtime…",
        "running…",
    }
)


def progress_stall_limit_seconds(config: dict[str, Any] | None) -> float | None:
    """Per-test timeout used to detect a hung runner (vitest / node --test)."""
    if not config:
        return None
    kind = config.get("kind")
    if kind == "vitest":
        return int(config.get("test_timeout_ms", 120_000)) / 1000.0
    if kind == "node-test":
        timeout = config.get("test_timeout_ms")
        if timeout is None:
            return 180.0
        return int(timeout) / 1000.0
    return None


def runner_stall_failure_name(current: str, subcampaign: str) -> str:
    if (
        not current
        or current in _STALL_PLACEHOLDER_CURRENTS
        or current.startswith("Running filtered batch")
    ):
        return f"{subcampaign}: runner stalled (no progress)"
    return current


def runner_stall_abort_error(limit_seconds: float) -> str:
    limit = int(limit_seconds)
    grace = int(STALL_GRACE_SECONDS)
    return (
        f"harness stalled: no runner output for >{limit}s "
        f"(test timeout + {grace}s grace)"
    )


def synthetic_vitest_fail_line(name: str) -> str:
    """Vitest-style fail line so the governor UI counts a stall as a failure."""
    return f"× {name} 0ms\n"


def runner_stdout_advances_stall_clock(stripped: str) -> bool:
    """Stdout that reflects real runner progress (not workerd log spam)."""
    if not stripped:
        return False
    if stripped.startswith("workerd/"):
        return False
    if stripped.startswith(("stdout |", "stderr |")):
        return False
    if _VITEST_PASS.match(stripped) or _VITEST_FAIL.match(stripped):
        return True
    if _VITEST_FAIL_FILE.match(stripped):
        return True
    if _STEP_HEADER.match(stripped) or _SEQUENCE_STEP.match(stripped):
        return True
    if stripped.startswith("RUN  v") or "[vpw:" in stripped:
        return True
    if stripped.startswith(("Test Files", "Tests ", " FAIL ", "× ", "✓ ", "✔ ")):
        return True
    if " > " in stripped and ".test." in stripped and not stripped.startswith("{"):
        return True
    return False


def line_indicates_uncaught_runner_crash(stripped: str) -> tuple[bool, str]:
    """
    True when a line likely signals an unhandled crash (not a normal assertion).

    Avoids matching arbitrary log text that mentions "exception".
    """
    if not stripped or stripped.startswith(("✓", "✔", "×", "✗", "x ")):
        return False, ""
    if "[vitest-worker]" in stripped and "Timeout" in stripped:
        return True, stripped[:160]
    if _FATAL_WORKERD.search(stripped) or _WORKERD_UNCAUGHT.search(stripped):
        return True, stripped[:160]
    if _TRACE_BACK_START.match(stripped):
        return True, stripped[:160]
    if _DART_UNHANDLED.match(stripped):
        return True, stripped[:160]
    if _FLUTTER_TEST_EXCEPTION.search(stripped):
        return True, stripped[:160]
    if _NODE_UNHANDLED_REJECTION.search(stripped):
        return True, stripped[:160]
    if _VITEST_UNHANDLED.search(stripped):
        return True, stripped[:160]
    if stripped.startswith("Failed assertion:"):
        return True, stripped[:160]
    return False, ""


def runner_crash_abort_error(snippet: str, grace_seconds: float) -> str:
    grace = int(grace_seconds)
    return (
        f"harness aborted: runner error without a test result "
        f"({snippet!r}; waited {grace}s for completion)"
    )


class RunnerCrashGuard:
    """Abort when the runner prints an unhandled crash but never finishes the test."""

    def __init__(
        self,
        stall_guard: RunnerStallGuard,
        *,
        grace_seconds: float = POST_CRASH_GRACE_SECONDS,
        immediate_settle_seconds: float = _CRASH_IMMEDIATE_SETTLE_SECONDS,
    ) -> None:
        self._stall = stall_guard
        self._grace = grace_seconds
        self._immediate_settle = immediate_settle_seconds
        self._fatal_at: float | None = None
        self._snippet = ""
        self._immediate = False
        self._aborted = False

    def inspect_line(self, line: str) -> None:
        stripped = _strip_ansi(line.strip())
        if not stripped:
            return
        if stripped.startswith("{") or stripped.startswith("["):
            try:
                payload = json.loads(stripped)
            except json.JSONDecodeError:
                payload = None
            if isinstance(payload, dict):
                if payload.get("type") == "print":
                    return
                if payload.get("type") == "error":
                    # Flutter attributes normal assertion failures to a testID.
                    if payload.get("testID") is not None:
                        return
                    err = (payload.get("error") or "flutter test error").strip()
                    self._mark_fatal(err[:160], immediate=False)
                    return
            if isinstance(payload, list):
                for item in payload:
                    if not isinstance(item, dict) or item.get("type") != "error":
                        continue
                    if item.get("testID") is not None:
                        continue
                    err = (item.get("error") or "flutter test error").strip()
                    self._mark_fatal(err[:160], immediate=False)
                return
        immediate, snippet = line_indicates_uncaught_runner_crash(stripped)
        if immediate:
            self._mark_fatal(snippet, immediate=True)

    def _mark_fatal(self, snippet: str, *, immediate: bool) -> None:
        self._fatal_at = time.monotonic()
        self._snippet = snippet or "runner error"
        self._immediate = immediate or self._immediate

    def should_abort(self) -> bool:
        if self._aborted or self._fatal_at is None:
            return False
        if self._stall._phase != "running":
            return False
        elapsed = time.monotonic() - self._fatal_at
        limit = self._immediate_settle if self._immediate else self._grace
        return elapsed >= limit

    def mark_aborted(self) -> None:
        self._aborted = True

    def abort_error(self) -> str:
        limit = self._immediate_settle if self._immediate else self._grace
        return runner_crash_abort_error(self._snippet, limit)

    def clear_fatal(self) -> None:
        """Clear a pending crash after the runner reports a normal test result."""
        self._fatal_at = None
        self._snippet = ""
        self._immediate = False


class RunnerStallGuard:
    """Tracks runner output gaps and names the in-flight test for stall abort."""

    def __init__(
        self,
        config: dict[str, Any] | None,
        *,
        subcampaign: str = "campaign",
        grace_seconds: float = STALL_GRACE_SECONDS,
    ) -> None:
        self._limit = progress_stall_limit_seconds(config)
        self._grace = grace_seconds
        self._subcampaign = subcampaign
        now = time.monotonic()
        self._last_progress_at = now
        self._current = "(starting…)"
        self._phase: _Phase = "starting"
        self._status_by_test: dict[str, str] = {}
        self._aborted = False

    def touch(self) -> None:
        self._last_progress_at = time.monotonic()

    def set_current(self, name: str) -> None:
        self.touch()
        self._current = name
        self._phase = "running"

    def note_finished(self, name: str, status: str) -> None:
        self.touch()
        if status in ("PASS", "FAIL"):
            self._status_by_test[name] = status
        self._current = name
        self._phase = "between" if status == "FAIL" else "running"

    def should_abort(self) -> bool:
        if self._aborted or self._limit is None:
            return False
        return (time.monotonic() - self._last_progress_at) > self._limit + self._grace

    def mark_aborted(self) -> None:
        self._aborted = True

    def failure_test_name(self) -> str:
        return runner_stall_failure_name(self._current, self._subcampaign)

    def abort_error(self) -> str:
        assert self._limit is not None
        return runner_stall_abort_error(self._limit)

    def dangling_failure_on_exit(self, exit_code: int) -> str | None:
        if exit_code == 0 or self._phase != "running":
            return None
        name = self.failure_test_name()
        if name in self._status_by_test:
            return None
        return name


class StallTrackingDisplay:
    """Forwards parser updates to a display and a ``RunnerStallGuard``."""

    def __init__(self, target: object, guard: RunnerStallGuard) -> None:
        self._target = target
        self._guard = guard

    def set_nested_subcampaign(self, segment: str) -> None:
        setter = getattr(self._target, "set_nested_subcampaign", None)
        if callable(setter):
            setter(segment)

    def set_current(self, name: str) -> None:
        self._guard.set_current(name)
        setter = getattr(self._target, "set_current", None)
        if callable(setter):
            setter(name)

    def add_finished(
        self,
        name: str,
        status: str,
        *,
        duration_seconds: float | None = None,
    ) -> None:
        self._guard.note_finished(name, status)
        setter = getattr(self._target, "add_finished", None)
        if callable(setter):
            setter(name, status, duration_seconds=duration_seconds)

    def set_campaign_config(self, config: dict[str, Any] | None) -> None:
        setter = getattr(self._target, "set_campaign_config", None)
        if callable(setter):
            setter(config)


class NoOpCampaignProgressDisplay:
    """Parser sink when the parent governor owns the live UI."""

    def set_nested_subcampaign(self, segment: str) -> None:
        pass

    def set_current(self, name: str) -> None:
        pass

    def add_finished(
        self,
        name: str,
        status: str,
        *,
        duration_seconds: float | None = None,
    ) -> None:
        pass


class CampaignProgressDisplay:
    """Status header and pass/fail counts on stderr."""

    def __init__(
        self,
        status_label: str,
        *,
        log_dir: Path | None = None,
        batch_queue: object | None = None,
        campaign_config: dict[str, Any] | None = None,
        config_area: str | None = None,
        run_log_root: Path | None = None,
        run_manifest_path: Path | None = None,
    ) -> None:
        self.campaign, self.subcampaign = _parse_status_label(status_label)
        self._batch_queue = batch_queue
        self._campaign_config = campaign_config
        self._config_area = config_area
        self._run_log_root = run_log_root.resolve() if run_log_root is not None else None
        if run_manifest_path is not None:
            self._run_manifest_path = run_manifest_path.resolve()
        elif self._run_log_root is not None:
            from harness.governor_run_manifest import RUN_MANIFEST_NAME

            self._run_manifest_path = self._run_log_root / RUN_MANIFEST_NAME
        else:
            self._run_manifest_path = None
        if self._run_log_root is not None:
            self._log_dir = self._run_log_root
        else:
            self._log_dir = log_dir.resolve() if log_dir is not None else None
        self._stats_log_dir = log_dir.resolve() if log_dir is not None else None
        self.current = "(starting…)"
        now = time.monotonic()
        self._current_started = now
        self._last_progress_at = now
        self._start = now
        self.passed = 0
        self.failed = 0
        self._session_passed_baseline = 0
        self._session_failed_baseline = 0
        self._show_resume_deltas = False
        self._status_by_test: dict[str, str] = {}
        self._nested: tuple[str, ...] = ()
        self._failures = _FailureTree()
        self._lines_drawn = 0
        self._lock = threading.RLock()
        from harness.common import campaign_interactive_ui_enabled

        self._interactive_ui = campaign_interactive_ui_enabled()
        self._tty = self._interactive_ui and sys.stderr.isatty()
        self._use_rich = self._tty and _rich_available()
        self._live: Live | None = None
        self._console: Console | None = None
        self._phase: _Phase = "starting"
        self._last_result: str | None = None
        self._subprocess_alive: bool | None = None
        self._poll_summary_on_tick = False
        self._render_error_logged = False
        self._ui_thread_id = threading.main_thread().ident
        self._ui_ops: deque[Callable[[], None]] = deque()
        self._ui_ops_lock = threading.Lock()

    def _schedule_ui(self, fn: Callable[[], None]) -> None:
        """Apply parser-driven UI mutations on the main poll thread (Rich Live)."""
        if threading.get_ident() == self._ui_thread_id:
            with self._lock:
                fn()
            self._sync_queue_counts()
            self._render_all()
        else:
            with self._ui_ops_lock:
                self._ui_ops.append(fn)

    def _flush_scheduled_ui(self) -> None:
        with self._ui_ops_lock:
            pending = list(self._ui_ops)
            self._ui_ops.clear()
        if pending:
            with self._lock:
                for fn in pending:
                    fn()
        self._sync_queue_counts()

    def _campaign_stats_log_dir(self) -> Path | None:
        from harness.campaign_live_stats import governor_campaign_stats_log_dir

        return governor_campaign_stats_log_dir(
            self._run_log_root,
            self.campaign,
            self.subcampaign,
            self._stats_log_dir,
        )

    def apply_disk_stats(self, passed: int, failed: int) -> None:
        """Take ``summary.json`` counts when they are at least as complete as memory.

        A stale summary (parent/child rewrite, or a flush that has not landed
        yet) must not snap the on-screen counters backwards while tests run.
        """
        with self._lock:
            passed = max(0, passed)
            failed = max(0, failed)
            if passed + failed >= self.passed + self.failed:
                self.passed = passed
                self.failed = failed
        self._sync_queue_counts()

    def _apply_outcome_delta(self, name: str, status: str) -> None:
        if status not in ("PASS", "FAIL"):
            return
        from harness.vitest_labels import normalize_vitest_case_label

        name = normalize_vitest_case_label(name)
        prior = self._status_by_test.get(name)
        if prior == status:
            return
        if status == "PASS":
            if prior is None:
                self.passed += 1
            elif prior == "FAIL":
                self.failed -= 1
                self.passed += 1
        else:
            if prior is None:
                self.failed += 1
            elif prior == "PASS":
                self.passed -= 1
                self.failed += 1
        self._status_by_test[name] = status

    def _sync_queue_counts(self) -> None:
        """Push in-memory pass/fail into the queue (does not read ``summary.json``)."""
        from harness.batch_queue_display import BatchQueueState
        from harness.campaign_live_stats import apply_campaign_stats
        from harness.test_result_stats import CampaignTestStats

        queue = self._batch_queue if isinstance(self._batch_queue, BatchQueueState) else None
        if queue is None:
            return
        stats = CampaignTestStats(self.passed, self.failed, ())
        apply_campaign_stats(
            stats,
            self.campaign,
            self.subcampaign,
            batch_queue=queue,
            adjust_total=False,
        )

    def bind_campaign_log_dir(self, log_dir: Path) -> None:
        """Point live refresh at ``<log_dir>/summary.json`` (governor per-campaign dir)."""
        self._stats_log_dir = log_dir.resolve()
        self._poll_summary_on_tick = True

    def pull_stats_from_summary(self) -> None:
        """Reload pass/fail from ``summary.json`` into the header and queue."""
        self._refresh_from_disk()

    def _refresh_from_disk(self) -> None:
        """Reload ``summary.json`` (child orchestrator is the writer during governor runs)."""
        from harness.batch_queue_display import BatchQueueState
        from harness.campaign_live_stats import refresh_live_campaign_stats

        log_dir = self._campaign_stats_log_dir()
        if log_dir is None or not (log_dir / "summary.json").is_file():
            return
        queue = self._batch_queue if isinstance(self._batch_queue, BatchQueueState) else None
        refresh_live_campaign_stats(
            log_dir,
            self.campaign,
            self.subcampaign,
            batch_queue=queue,
            display=self,
        )

    def seed_prior_results(
        self,
        passed: int,
        failed: int,
        *,
        failure_names: Sequence[str] | None = None,
        status_by_test: dict[str, str] | None = None,
        log_dir: Path | None = None,
    ) -> None:
        with self._lock:
            self.passed = max(0, passed)
            self.failed = max(0, failed)
            self._session_passed_baseline = self.passed
            self._session_failed_baseline = self.failed
            self._show_resume_deltas = True
            self._status_by_test = {}
            if status_by_test:
                from harness.vitest_labels import normalize_vitest_case_label

                for name, outcome in status_by_test.items():
                    if outcome in ("PASS", "FAIL"):
                        self._status_by_test[normalize_vitest_case_label(name)] = outcome
            elif failure_names:
                from harness.vitest_labels import normalize_vitest_case_label

                for name in failure_names:
                    if name:
                        self._status_by_test[normalize_vitest_case_label(name)] = "FAIL"
            if failure_names:
                self._failures = _FailureTree()
                for name in failure_names:
                    path, leaf = _failure_path_and_leaf(self._nested, name)
                    self._failures.insert(path, leaf)
        self._sync_queue_counts()
        self._render_all()

    def prepare_run(
        self,
        status_label: str,
        log_dir: Path | None,
        *,
        batch_queue: object | None = None,
        campaign_config: dict[str, Any] | None = None,
        config_area: str | None = None,
    ) -> None:
        """Reset per-campaign counters for the next subprocess in a batch."""
        with self._lock:
            self.campaign, self.subcampaign = _parse_status_label(status_label)
            if batch_queue is not None:
                self._batch_queue = batch_queue
            if config_area is not None:
                self._config_area = config_area
            if campaign_config is not None:
                self._campaign_config = campaign_config
            elif config_area is not None:
                from harness.campaign_config import load_campaign_config

                self._campaign_config = load_campaign_config(
                    config_area, self.subcampaign
                )
            if log_dir is not None:
                self._stats_log_dir = log_dir.resolve()
            if self._run_log_root is None:
                self._log_dir = self._stats_log_dir
            self._poll_summary_on_tick = self._stats_log_dir is not None
            self.current = "(starting…)"
            now = time.monotonic()
            self._current_started = now
            self._last_progress_at = now
            self._phase = "starting"
            self._last_result = None
            self.passed = 0
            self.failed = 0
            self._session_passed_baseline = 0
            self._session_failed_baseline = 0
            self._show_resume_deltas = False
            self._status_by_test = {}
            self._nested = ()
            from harness.batch_queue_display import BatchQueueState

            if isinstance(self._batch_queue, BatchQueueState):
                key = (self.campaign, self.subcampaign)
                qp = self._batch_queue.passed_by_key.get(key, 0)
                qf = self._batch_queue.failed_by_key.get(key, 0)
                if qp or qf:
                    self.passed = qp
                    self.failed = qf
        self._sync_queue_counts()
        self._render_all()

    def begin(self, *, clear_screen: bool = False) -> None:
        self._ui_thread_id = threading.get_ident()
        if clear_screen and self._tty:
            sys.stderr.write("\033[2J\033[H")
            sys.stderr.flush()
        if not self._use_rich:
            if self._tty:
                warn_if_rich_missing_for_tty()
            return
        if self._live is not None:
            return
        from rich.console import Console
        from rich.live import Live

        self._console = Console(stderr=True, highlight=False)
        # Alternate screen + home on every refresh repaints the whole terminal.
        # Cursor-up live regions leave the queue counters stuck once the
        # dashboard is taller than the window or any other write lands above it.
        self._live = Live(
            self._build_rich_renderable(),
            console=self._console,
            screen=True,
            refresh_per_second=8,
            auto_refresh=False,
            redirect_stdout=False,
            redirect_stderr=False,
            vertical_overflow="crop",
        )
        self._live.start()
        self._render_all()

    def set_nested_subcampaign(self, segment: str) -> None:
        name = segment.strip()
        if not name:
            return

        def work() -> None:
            self._nested = (name,)
            if self._config_area:
                from harness.campaign_config import nested_subcampaign_config

                cfg = nested_subcampaign_config(self._config_area, name)
                if cfg is not None:
                    self._campaign_config = cfg

        self._schedule_ui(work)

    def set_campaign_config(self, config: dict[str, Any] | None) -> None:
        def work() -> None:
            self._campaign_config = config

        self._schedule_ui(work)

    def set_current(self, name: str) -> None:
        def work() -> None:
            self.current = name
            self._phase = "running"
            self._last_result = None
            now = time.monotonic()
            self._current_started = now
            self._last_progress_at = now

        self._schedule_ui(work)

    def add_finished(
        self,
        name: str,
        status: str,
        *,
        duration_seconds: float | None = None,
    ) -> None:
        def work() -> None:
            if status in ("PASS", "FAIL"):
                self._apply_outcome_delta(name, status)
                if status == "FAIL":
                    path, leaf = _failure_path_and_leaf(self._nested, name)
                    self._failures.insert(path, leaf)
            self.current = name
            self._last_result = status
            now = time.monotonic()
            self._last_progress_at = now
            if duration_seconds is not None and duration_seconds >= 0:
                self._current_started = now - duration_seconds
            else:
                self._current_started = now
            if status == "PASS":
                self._phase = "running"
            elif status == "FAIL":
                self._phase = "between"

        self._schedule_ui(work)
        if not self._tty and status == "FAIL":
            path = "/".join(self._nested) if self._nested else self.subcampaign
            sys.stderr.write(f"FAIL [{path}] {name}\n")
            sys.stderr.flush()

    def tick(self, *, subprocess_alive: bool | None = None) -> None:
        self._flush_scheduled_ui()
        if subprocess_alive is not None:
            self._subprocess_alive = subprocess_alive
        if self._poll_summary_on_tick and (
            self._subprocess_alive or subprocess_alive is False
        ):
            self._refresh_from_disk()
        else:
            self._sync_queue_counts()
        with self._lock:
            self._render_all()

    def _restore_terminal(self) -> None:
        if not self._tty:
            return
        if self._lines_drawn:
            self._lines_drawn = 0
        sys.stderr.write("\033[?25h\033[0m\n")
        sys.stderr.flush()

    def finish(self, *, interrupted: bool = False, final: bool = True) -> None:
        self._flush_scheduled_ui()
        if final and not interrupted:
            self._refresh_from_disk()
        with self._lock:
            if not final and not interrupted:
                return
            self._phase = "done"
            if interrupted:
                self.current = "Interrupted"
            else:
                self.current = (
                    "Finished"
                    if self.failed == 0
                    else "Finished with failures"
                )
            final_renderable = None
            if self._live is not None:
                try:
                    final_renderable = self._build_rich_renderable()
                    if not interrupted:
                        self._live.update(final_renderable, refresh=True)
                except Exception:
                    final_renderable = None
                try:
                    self._live.stop()
                except Exception:
                    pass
                self._live = None
                if self._console is not None and final_renderable is not None:
                    # screen=True restores the main buffer on stop; print the
                    # last frame there so counts stay visible (including Ctrl+C).
                    try:
                        self._console.print(final_renderable)
                        self._console.print()
                    except Exception:
                        pass
                self._console = None
            else:
                self._render_all()
                if self._tty:
                    sys.stderr.write("\n")
                self._emit_log_footer_plain()
                if not self._tty and not interrupted:
                    sys.stderr.write("\n")
            if interrupted:
                self._restore_terminal()
            self._lines_drawn = 0
            sys.stderr.flush()

    def _log_dirs_for_footer(self) -> list[Path]:
        if self._run_log_root is not None:
            return [self._run_log_root]
        if self._log_dir is not None:
            return [self._log_dir]
        return []

    def _emit_log_footer_plain(self) -> None:
        for log_dir in self._log_dirs_for_footer():
            sys.stderr.write(f"Logs: {log_dir}\n")
            if self._run_log_root is None:
                summary = log_dir / "summary.json"
                tests_dir = log_dir / "tests"
                sys.stderr.write(f"Summary: {summary}\n")
                sys.stderr.write(f"Per-test: {tests_dir}/\n")

    def _progress_stall_limit_seconds(self) -> float | None:
        return progress_stall_limit_seconds(self._campaign_config)

    def _runner_stalled(self) -> bool:
        if self._phase not in ("running", "starting"):
            return False
        timeout = self._progress_stall_limit_seconds()
        if timeout is None:
            return False
        return (time.monotonic() - self._last_progress_at) > timeout + STALL_GRACE_SECONDS

    def record_stall_failure(self, name: str, error: str) -> None:
        del error  # logged by harness session; UI uses fail counts only
        self.add_finished(name, "FAIL")

    def record_dangling_failure_on_exit(self, exit_code: int) -> str | None:
        with self._lock:
            if exit_code == 0 or self._phase != "running":
                return None
            name = runner_stall_failure_name(self.current, self.subcampaign)
            if name in self._status_by_test:
                return None
        self.add_finished(name, "FAIL")
        return name

    def _case_elapsed_seconds(self) -> float:
        return max(0.0, time.monotonic() - self._current_started)

    def _activity_labels(self) -> tuple[str, str]:
        """Subcampaign bracket and test-case bracket for the status line."""
        if self._phase == "starting":
            return self._nested_subcampaign_label(), "starting…"
        if self._phase == "done":
            return self.subcampaign, self.current
        if self._runner_stalled():
            timeout = self._progress_stall_limit_seconds()
            limit = int(timeout) if timeout is not None else 120
            if self._subprocess_alive is False:
                return (
                    self._nested_subcampaign_label(),
                    "runner exited without a test result (see logs)",
                )
            return (
                self._nested_subcampaign_label(),
                f"long test or setup (>{limit}s, no vitest line yet)",
            )

        name = self.current
        if " > " in name and (".test." in name or ".spec." in name):
            parts = [part.strip() for part in name.split(" > ") if part.strip()]
            if len(parts) >= 2:
                return parts[-2], parts[-1]
        if ": " in name:
            group, leaf = name.split(": ", 1)
            group, leaf = group.strip(), leaf.strip()
            if group and leaf:
                return group, leaf
        if self._nested:
            return " / ".join(self._nested), name
        return self.subcampaign, name

    def _nested_subcampaign_label(self) -> str:
        if self._nested:
            return " / ".join(self._nested)
        return self.subcampaign

    def _append_bracketed_activity(self, target: Any, *, case_style: str) -> None:
        sub, case = self._activity_labels()
        target.append("[", style="bright_black")
        target.append(sub, style="bold magenta")
        target.append("] [", style="bright_black")
        target.append(case, style=case_style)
        target.append("]", style="bright_black")

    def _append_activity_line(self, activity: Any, *, case_style: str) -> None:
        """Second status row: timer + bracketed subcampaign / case."""
        case_elapsed = _format_elapsed(self._case_elapsed_seconds())
        if self._phase in ("running", "starting"):
            activity.append("▶ ", style="green")
            activity.append(case_elapsed, style="yellow")
            activity.append("  ", style="")
            self._append_bracketed_activity(activity, case_style=case_style)
        elif self._phase == "between":
            activity.append("✗ ", style="bold red")
            self._append_bracketed_activity(activity, case_style="bold red")
        elif self._phase == "done":
            icon = "✓ " if self.failed == 0 else "✗ "
            activity.append(icon, style="bold green" if self.failed == 0 else "bold red")
            self._append_bracketed_activity(activity, case_style="bold white")

    def _run_location_lines(self) -> list[str]:
        if self._run_log_root is None:
            return []
        return [f"Run directory: {self._run_log_root}"]

    def _build_run_location_rich(self) -> Any | None:
        if self._run_log_root is None:
            return None
        from rich.text import Text

        body = Text()
        body.append("Run directory: ", style="dim")
        body.append(str(self._run_log_root), style="cyan")
        return body

    def _plain_run_location_block(self) -> list[str]:
        return self._run_location_lines()

    def _queue_panel(self) -> Any | None:
        from harness.batch_queue_display import rich_queue_panel

        if self._batch_queue is None and not self._campaign_config:
            return None
        return rich_queue_panel(
            self._batch_queue,
            self._campaign_config,
            fallback_area=self.campaign,
            fallback_subcampaign=self.subcampaign,
            fallback_finished=self.passed + self.failed,
            run_directory=self._run_log_root,
        )

    def _queue_layout_size(self) -> int | None:
        """Rows needed for the campaign table (queue panel body, not terminal)."""
        from harness.batch_queue_display import BatchQueueState, flat_queue_rows
        from harness.campaign_config import config_display_lines

        queue = self._batch_queue if isinstance(self._batch_queue, BatchQueueState) else None
        if queue is None:
            return None
        rows = len(flat_queue_rows(queue))
        if rows == 0:
            return None
        overhead = 9
        if config_display_lines(self._campaign_config):
            overhead += 2
        if self._run_log_root is not None:
            overhead += 1
        return rows + overhead

    def _build_rich_renderable(self) -> Any:
        from rich import box
        from rich.console import Group
        from rich.panel import Panel
        from rich.text import Text

        total_elapsed = _format_elapsed(time.monotonic() - self._start)

        header = Text()
        header.append("  ", style="")
        header.append(self.campaign, style="bold cyan")
        header.append("  ", style="")
        header.append(self.subcampaign, style="bold magenta")
        header.append("  ⏱ ", style="dim")
        header.append(total_elapsed, style="bold yellow")

        activity = Text()
        activity.append("  ", style="")
        if self._phase == "starting":
            self._append_activity_line(activity, case_style="dim italic")
        elif self._phase == "done":
            self._append_activity_line(activity, case_style="bold white")
        elif self._phase == "between":
            self._append_activity_line(
                activity,
                case_style="bold red" if self._last_result == "FAIL" else "dim",
            )
        else:
            self._append_activity_line(activity, case_style="bold white")

        counts = Text()
        counts.append("  ✓ Passed ", style="dim")
        counts.append(str(self.passed), style="bold green")
        if self._show_resume_deltas:
            pass_delta = self.passed - self._session_passed_baseline
            if pass_delta > 0:
                counts.append(f" (+{pass_delta})", style="bold green")
        counts.append("    ✗ Failed ", style="dim")
        counts.append(
            str(self.failed),
            style="bold red" if self.failed else "dim bright_black",
        )
        if self._show_resume_deltas:
            fail_delta = self.failed - self._session_failed_baseline
            if fail_delta > 0:
                counts.append(f" (+{fail_delta})", style="bold red")
            elif fail_delta < 0:
                counts.append(f" ({fail_delta})", style="bold green")

        status_panel = Panel(
            Group(header, activity, counts),
            border_style="bright_blue",
            box=box.HEAVY,
            padding=(0, 1),
        )

        from rich.layout import Layout

        children: list[Layout] = []
        queue_panel = self._queue_panel()
        if queue_panel is not None:
            queue_size = self._queue_layout_size()
            term_h = self._console.size.height if self._console is not None else None
            reserved = 6
            if self._phase == "done" and self._build_log_footer_rich() is not None:
                reserved += 6
            if queue_size is not None and term_h is not None:
                max_queue = max(8, term_h - reserved - 1)
                children.append(Layout(queue_panel, size=min(queue_size, max_queue)))
            else:
                children.append(Layout(queue_panel, ratio=1))
        children.append(Layout(status_panel, size=6))
        if self._phase == "done":
            log_panel = self._build_log_footer_rich()
            if log_panel is not None:
                children.append(Layout(log_panel, size=6))
        if len(children) == 1:
            return children[0].renderable
        layout = Layout()
        layout.split_column(*children)
        return layout

    def _build_log_footer_rich(self) -> Any | None:
        log_dirs = self._log_dirs_for_footer()
        if not log_dirs:
            return None
        from rich import box
        from rich.panel import Panel
        from rich.text import Text

        body = Text()
        log_dir = log_dirs[0]
        body.append("Run directory\n", style="dim")
        body.append(f"{log_dir}\n", style="cyan")
        if self._run_log_root is None:
            summary = log_dir / "summary.json"
            tests_dir = log_dir / "tests"
            body.append("summary.json\n", style="dim")
            body.append(f"{summary}\n", style="cyan")
            body.append("tests/\n", style="dim")
            body.append(str(tests_dir), style="cyan")
        return Panel(
            body,
            title="[bold]Logs[/]",
            border_style="bright_black",
            box=box.ROUNDED,
            padding=(0, 1),
        )

    def _plain_activity_label(self, case_elapsed: str) -> str:
        sub, case = self._activity_labels()
        bracketed = f"[{sub}] [{case}]"
        if self._phase == "between":
            return f"✗ {bracketed}"
        if self._phase == "running" or self._phase == "starting":
            return f"▶ {case_elapsed} {bracketed}"
        if self._phase == "done":
            mark = "✓" if self.failed == 0 else "✗"
            return f"{mark} {bracketed}"
        return bracketed

    def _status_lines(self) -> list[str]:
        """Plain-text lines (tests and non-Rich fallback)."""
        total_elapsed = _format_elapsed(time.monotonic() - self._start)
        case_elapsed = _format_elapsed(self._case_elapsed_seconds())
        line1 = f"[{self.campaign}] [{self.subcampaign}] ⏱ {total_elapsed}"
        line2 = f"  {self._plain_activity_label(case_elapsed)}"
        pass_extra = ""
        fail_extra = ""
        if self._show_resume_deltas:
            pass_delta = self.passed - self._session_passed_baseline
            fail_delta = self.failed - self._session_failed_baseline
            if pass_delta > 0:
                pass_extra = f" (+{pass_delta})"
            if fail_delta > 0:
                fail_extra = f" (+{fail_delta})"
            elif fail_delta < 0:
                fail_extra = f" ({fail_delta})"
        line3 = f"Passed {self.passed}{pass_extra}  Failed {self.failed}{fail_extra}"
        progress_lines = [line1, line2, line3]
        lines: list[str] = []
        if self._batch_queue is not None or self._campaign_config:
            from harness.batch_queue_display import plain_queue_lines

            lines.extend(
                plain_queue_lines(
                    self._batch_queue,
                    self._campaign_config,
                    fallback_area=self.campaign,
                    fallback_subcampaign=self.subcampaign,
                    fallback_finished=self.passed + self.failed,
                    run_directory=self._run_log_root,
                )
            )
            lines.append("")
        lines.extend(progress_lines)
        return lines

    def _render_all(self) -> None:
        if not self._interactive_ui:
            return
        if self._use_rich and self._live is not None:
            try:
                self._live.update(self._build_rich_renderable(), refresh=True)
                return
            except Exception as exc:
                if not self._render_error_logged:
                    msg = f"live progress UI error: {exc}\n"
                    sys.stderr.write(msg)
                    from harness.governor_console_log import governor_console_log_line

                    governor_console_log_line(msg)
                    self._render_error_logged = True
                try:
                    self._live.stop()
                except Exception:
                    pass
                self._live = None
                self._console = None

        lines = self._status_lines()
        if self._tty:
            # Home + clear so every counter on screen is rewritten, including
            # rows above the previous cursor-up window.
            sys.stderr.write("\033[H\033[2J")
            sys.stderr.write("\n".join(lines))
            sys.stderr.write("\n")
            self._lines_drawn = len(lines)
        else:
            sys.stderr.write("\r\033[K" + lines[0] + "\n\033[K" + lines[1])
        sys.stderr.flush()


# Backwards-compatible name for tests
_render_failure_tree = _render_failure_tree_plain


class ProgressParser(ABC):
    @abstractmethod
    def feed(self, line: str) -> None: ...


class TouchProgressParser(ProgressParser):
    def __init__(self, inner: ProgressParser, guard: RunnerStallGuard) -> None:
        self._inner = inner
        self._guard = guard

    def feed(self, line: str) -> None:
        stripped = _strip_ansi(line.strip())
        if runner_stdout_advances_stall_clock(stripped):
            self._guard.touch()
        self._inner.feed(line)


class CrashInspectParser(ProgressParser):
    """Feed crash detector before inner parsers (stall timer still advances)."""

    def __init__(self, inner: ProgressParser, crash_guard: RunnerCrashGuard) -> None:
        self._inner = inner
        self._crash = crash_guard

    def feed(self, line: str) -> None:
        stripped = _strip_ansi(line.strip())
        if '"type":"testDone"' in stripped:
            self._crash.clear_fatal()
        self._crash.inspect_line(line)
        self._inner.feed(line)


class SequenceStepParser(ProgressParser):
    """``== step-name ==`` banners from run_subprocess_sequence (not ``== [n]``)."""

    def __init__(
        self,
        display: CampaignProgressDisplay,
        log_session: Optional["CampaignLogSession"] = None,
    ) -> None:
        self.display = display
        self.log_session = log_session

    def feed(self, line: str) -> None:
        stripped = line.strip()
        if stripped.startswith("CAMPAIGN_STATUS:"):
            self.display.set_current(stripped.removeprefix("CAMPAIGN_STATUS:").strip())
            return
        match = _SEQUENCE_STEP.match(stripped)
        if match:
            self.display.set_nested_subcampaign(match.group(1))


class StepProgressParser(ProgressParser):
    """backend/tests harness: ``== [n] Name ==`` then ``PASS`` / ``FAIL``."""

    def __init__(
        self,
        display: CampaignProgressDisplay,
        log_session: Optional["CampaignLogSession"] = None,
    ) -> None:
        self.display = display
        self.log_session = log_session
        self._pending: str | None = None

    def feed(self, line: str) -> None:
        stripped = line.strip()
        match = _STEP_HEADER.match(stripped)
        if match:
            self._pending = match.group(2)
            if self.log_session is not None:
                self.log_session.start_test(self._pending)
            self.display.set_current(self._pending)
            return
        if self._pending and stripped == "PASS":
            self.display.add_finished(self._pending, "PASS")
            if self.log_session is not None:
                self.log_session.end_test(self._pending, status="PASS")
            self._pending = None
            return
        if self._pending and stripped == "FAIL":
            self.display.add_finished(self._pending, "FAIL")
            if self.log_session is not None:
                self.log_session.end_test(self._pending, status="FAIL")
            self._pending = None
            return
        if self._pending and stripped.startswith("SKIP"):
            self.display.add_finished(self._pending, "SKIP")
            if self.log_session is not None:
                self.log_session.end_test(
                    self._pending, status="SKIP", skipped=True
                )
            self._pending = None


class FlutterMachineParser(ProgressParser):
    """Flutter ``--machine`` JSONL events."""

    def __init__(
        self,
        display: CampaignProgressDisplay,
        log_session: Optional["CampaignLogSession"] = None,
    ) -> None:
        self.display = display
        self.log_session = log_session
        self._active: dict[int, str] = {}
        self._ignored_ids: set[int] = set()
        self._pseudo: dict[int, str] = {}
        self._failed_pseudo: set[int] = set()
        self._suite_paths: dict[int, str] = {}

    def feed(self, line: str) -> None:
        stripped = line.strip()
        if stripped.startswith("CAMPAIGN_STATUS:"):
            # Tooling status (compile, etc.) — keep UI on real tests only.
            return
        if not stripped.startswith("{"):
            return
        try:
            event = json.loads(stripped)
        except json.JSONDecodeError:
            return
        if isinstance(event, list):
            for item in event:
                if isinstance(item, dict):
                    self._handle_event(item)
            return
        if isinstance(event, dict):
            self._handle_event(event)

    def _handle_event(self, event: dict) -> None:
        from harness.flutter_machine_labels import (
            flutter_pseudo_test_failure_label,
            flutter_test_label,
            is_flutter_hook_pseudo_test,
            is_loading_pseudo_test,
        )

        kind = event.get("type")
        if kind == "suite":
            suite = event.get("suite") or {}
            suite_id = suite.get("id")
            if suite_id is not None and suite.get("path"):
                self._suite_paths[int(suite_id)] = str(suite["path"])
            return
        if kind == "testStart":
            test = event.get("test") or {}
            test_id = test.get("id")
            if test_id is None:
                return
            tid = int(test_id)
            if is_loading_pseudo_test(test) or is_flutter_hook_pseudo_test(test):
                suite_id = test.get("suiteID")
                suite_path = (
                    self._suite_paths.get(int(suite_id)) if suite_id is not None else None
                )
                self._pseudo[tid] = flutter_pseudo_test_failure_label(test, suite_path)
                return
            label = flutter_test_label(test)
            if label is None:
                self._ignored_ids.add(tid)
                return
            self._active[tid] = label
            if self.log_session is not None:
                self.log_session.start_test(label)
            self.display.set_current(label)
        elif kind == "testDone":
            test_id = event.get("testID")
            if test_id is None:
                return
            tid = int(test_id)
            if tid in self._pseudo:
                label = self._pseudo.pop(tid)
                already_failed = tid in self._failed_pseudo
                self._failed_pseudo.discard(tid)
                result = event.get("result")
                if not already_failed and result not in (None, "success"):
                    self._record_failure(label, f"{label} finished with result {result}")
                return
            if event.get("hidden"):
                return
            if tid in self._ignored_ids:
                self._ignored_ids.discard(tid)
                return
            name = self._active.pop(tid, None)
            if name is None:
                return
            result = event.get("result")
            status = "PASS" if result == "success" else "FAIL"
            self.display.add_finished(name, status)
            if self.log_session is not None:
                self.log_session.end_test(name, status=status)
        elif kind == "error":
            test_id = event.get("testID")
            tid = int(test_id) if test_id is not None else None
            name: str | None = None
            if tid is not None and tid in self._pseudo:
                if tid in self._failed_pseudo:
                    return
                self._failed_pseudo.add(tid)
                name = self._pseudo[tid]
            elif tid is not None and tid in self._active:
                name = self._active.pop(tid, None)
            if name is None:
                name = self.display.current
                if name in ("(starting…)", "starting…", "Interrupted"):
                    name = "flutter test error"
            err = (event.get("error") or "flutter test error").strip()
            self._record_failure(name, err, stack_trace=event.get("stackTrace"))

    def _record_failure(
        self, name: str, err: str, *, stack_trace: object = None
    ) -> None:
        if self.log_session is not None:
            if not self.log_session.has_active():
                self.log_session.start_test(name)
            if stack_trace:
                self.log_session.append_line(str(stack_trace))
            self.log_session.append_line(err)
            self.log_session.end_test(name, status="FAIL", error=err)
        self.display.add_finished(name, "FAIL")


class VitestReporterParser(ProgressParser):
    """Vitest default reporter lines (✓ / ×)."""

    def __init__(
        self,
        display: CampaignProgressDisplay,
        log_session: Optional["CampaignLogSession"] = None,
        *,
        exclude_tests: set[str] | None = None,
    ) -> None:
        self.display = display
        self.log_session = log_session
        from harness.vitest_labels import vitest_exclude_label_set

        self._exclude = vitest_exclude_label_set(exclude_tests)

    def _finish_vitest(self, name: str, status: str, line: str) -> None:
        from harness.campaign_vitest_reconcile import is_harness_artifact_test_name
        from harness.vitest_labels import normalize_vitest_case_label

        label = normalize_vitest_case_label(name)
        if is_harness_artifact_test_name(label):
            return
        if label in self._exclude:
            return
        duration = _parse_vitest_duration_seconds(name) or _parse_vitest_duration_seconds(
            line
        )
        if self.log_session is not None:
            self.log_session.start_test(label)
            self.log_session.append_line(line)
            self.log_session.end_test(label, status=status)
        self.display.add_finished(
            label,
            status,
            duration_seconds=duration,
        )

    def feed(self, line: str) -> None:
        stripped = _strip_ansi(line.strip())
        if stripped.startswith("↓"):
            # Vitest skip: already recorded, or not in this filtered batch.
            return
        if "[vpw:info]" in stripped:
            self.display.set_current("Starting worker runtime…")
            return
        if stripped.startswith("RUN  v"):
            self.display.set_current("Collecting tests…")
            return
        pass_match = _VITEST_PASS.match(stripped)
        if pass_match:
            self._finish_vitest(pass_match.group(1), "PASS", line)
            return
        fail_match = _VITEST_FAIL.match(stripped)
        if fail_match:
            self._finish_vitest(fail_match.group(1), "FAIL", line)
            return
        fail_file = _VITEST_FAIL_FILE.match(stripped)
        if fail_file:
            name = f"{fail_file.group(1)} > {fail_file.group(2)}"
            self._finish_vitest(name, "FAIL", line)
            return
        # Vitest console capture lines are not test-case labels.
        if stripped.startswith(("stdout |", "stderr |")):
            return
        # Vitest verbose / workers: path > suite > case (no checkmark yet).
        if " > " in stripped and ".test." in stripped and not stripped.startswith("{"):
            from harness.vitest_labels import normalize_vitest_case_label

            label = normalize_vitest_case_label(stripped)
            if label not in self._exclude:
                self.display.set_current(label)


class NodeTestParser(ProgressParser):
    """node --test TAP-like ✔ / ✖ lines."""

    def __init__(
        self,
        display: CampaignProgressDisplay,
        log_session: Optional["CampaignLogSession"] = None,
        *,
        exclude_tests: set[str] | None = None,
    ) -> None:
        from harness.vitest_labels import vitest_exclude_label_set

        self.display = display
        self.log_session = log_session
        self._exclude = vitest_exclude_label_set(exclude_tests)
        self._pending_subtest: str | None = None

    def feed(self, line: str) -> None:
        stripped = line.strip()
        # Vitest uses the same ✔ pass glyph; orchestrator parsers include both.
        if _VITEST_PASS.match(stripped) or _VITEST_FAIL.match(stripped):
            return
        if stripped.startswith("# Subtest:"):
            from harness.vitest_labels import normalize_vitest_case_label

            name = normalize_vitest_case_label(
                stripped.removeprefix("# Subtest:").strip()
            )
            if name in self._exclude:
                return
            if self.log_session is not None:
                self.log_session.start_test(name)
            self.display.set_current(name)
            self._pending_subtest = name
            return
        tap_ok = _NODE_TAP_OK.match(stripped)
        if tap_ok:
            from harness.vitest_labels import normalize_vitest_case_label

            raw = (tap_ok.group(1) or self._pending_subtest or "").strip()
            if raw:
                name = normalize_vitest_case_label(raw)
                if name not in self._exclude:
                    if self.log_session is not None:
                        self.log_session.append_line(line)
                        self.log_session.end_test(name, status="PASS")
                    self.display.add_finished(name, "PASS")
            self._pending_subtest = None
            return
        tap_fail = _NODE_TAP_NOT_OK.match(stripped)
        if tap_fail:
            from harness.vitest_labels import normalize_vitest_case_label

            raw = (tap_fail.group(1) or self._pending_subtest or "node test").strip()
            name = normalize_vitest_case_label(raw)
            if name not in self._exclude:
                if self.log_session is not None:
                    self.log_session.append_line(line)
                    self.log_session.end_test(name, status="FAIL")
                self.display.add_finished(name, "FAIL")
            self._pending_subtest = None
            return
        tap_label = _node_tap_progress_label(stripped)
        if tap_label is not None:
            phase = getattr(self.display, "_phase", None)
            if phase == "starting" and self._pending_subtest is None:
                self.display.set_current(tap_label)
            return
        pass_match = _NODE_PASS.match(stripped)
        if pass_match:
            from harness.vitest_labels import normalize_vitest_case_label

            name = normalize_vitest_case_label(pass_match.group(1))
            if name in self._exclude:
                return
            if self.log_session is not None:
                self.log_session.append_line(line)
                self.log_session.end_test(name, status="PASS")
            self.display.add_finished(name, "PASS")
            return
        fail_match = _NODE_FAIL.match(stripped)
        if fail_match:
            from harness.vitest_labels import normalize_vitest_case_label

            name = normalize_vitest_case_label(fail_match.group(1))
            if name in self._exclude:
                return
            if self.log_session is not None:
                self.log_session.append_line(line)
                self.log_session.end_test(name, status="FAIL")
            self.display.add_finished(name, "FAIL")


class CompositeProgressParser(ProgressParser):
    def __init__(self, parsers: list[ProgressParser]) -> None:
        self._parsers = parsers

    def feed(self, line: str) -> None:
        for parser in self._parsers:
            parser.feed(line)


def _cmd_is_area_campaign_orchestrator(cmd: list[str]) -> bool:
    """``run_campaigns.py`` for npm/node areas (not backend SQL harness)."""
    for part in cmd:
        if not part.endswith("run_campaigns.py"):
            continue
        normalized = part.replace("\\", "/")
        if "backend/tests/run_campaigns.py" in normalized:
            return False
        return True
    return False


def _cmd_includes_frontend_flutter_runner(cmd: list[str]) -> bool:
    joined = " ".join(cmd)
    if "run_unit_tests.py" in joined or "run_boundary_tests.py" in joined:
        return True
    for part in cmd:
        if not part.endswith("run_campaigns.py"):
            continue
        parent = Path(part).resolve().parent
        if parent.name == "tool" and parent.parent.name == "frontend":
            return True
    return False


def parser_for_command(
    cmd: list[str],
    display: CampaignProgressDisplay,
    log_session: Optional["CampaignLogSession"] = None,
    *,
    exclude_tests: set[str] | None = None,
) -> ProgressParser:
    exclude = exclude_tests or set()
    joined = " ".join(cmd)
    parsers: list[ProgressParser] = [SequenceStepParser(display, log_session)]

    if any("backend/tests/run_campaigns.py" in part.replace("\\", "/") for part in cmd):
        parsers.append(StepProgressParser(display, log_session))

    if _cmd_is_area_campaign_orchestrator(cmd):
        parsers.append(
            VitestReporterParser(display, log_session, exclude_tests=exclude)
        )
        parsers.append(NodeTestParser(display, log_session, exclude_tests=exclude))

    if _cmd_includes_frontend_flutter_runner(cmd):
        parsers.append(FlutterMachineParser(display, log_session))
    if "flutter" in joined and " test" in joined:
        parsers.append(FlutterMachineParser(display, log_session))
    if "vitest" in joined or "npm run test" in joined or "npx vitest" in joined:
        parsers.append(
            VitestReporterParser(display, log_session, exclude_tests=exclude)
        )
    if "node" in cmd and "--test" in cmd:
        parsers.append(NodeTestParser(display, log_session, exclude_tests=exclude))

    if not any(isinstance(p, StepProgressParser) for p in parsers):
        parsers.append(StepProgressParser(display, log_session))

    if len(parsers) == 1:
        return parsers[0]
    return CompositeProgressParser(parsers)


def should_forward_progress_stdout_line(line: str) -> bool:
    """Lines area scripts forward to the root governor stdout (for parsers only)."""
    stripped = line.strip()
    if not stripped:
        return False
    if stripped.startswith("{") or stripped.startswith("["):
        return True
    if _SEQUENCE_STEP.match(stripped) or _STEP_HEADER.match(stripped):
        return True
    if stripped in ("PASS", "FAIL") or stripped.startswith("SKIP"):
        return True
    if _VITEST_PASS.match(stripped) or _VITEST_FAIL.match(stripped):
        return True
    if _VITEST_FAIL_FILE.match(stripped):
        return True
    if _NODE_PASS.match(stripped) or _NODE_FAIL.match(stripped):
        return True
    if stripped.startswith("# Subtest:"):
        return True
    if _node_tap_progress_label(stripped) is not None:
        return True
    if stripped.startswith("RUN  v"):
        return True
    if "[vpw:info]" in stripped:
        return True
    if stripped.startswith("CAMPAIGN_STATUS:"):
        return True
    if stripped.startswith("▶") or stripped.startswith("ℹ"):
        return True
    if re.match(r"^(ok|not ok)\s+\d+", stripped):
        return True
    return False


def pump_process_output(
    proc_stdout: TextIO,
    parser: ProgressParser,
    log_session: Optional["CampaignLogSession"] = None,
    *,
    forward_stdout: bool = False,
    proc: object | None = None,
) -> None:
    from harness.governor_console_log import (
        governor_console_log_active,
        governor_console_log_line,
        governor_console_output_path,
    )

    transcript = None
    log_dir = getattr(log_session, "log_dir", None)
    if isinstance(log_dir, Path):
        transcript_path = governor_console_output_path(log_dir)
        transcript_path.parent.mkdir(parents=True, exist_ok=True)
        transcript = transcript_path.open("a", encoding="utf-8")

    try:
        for line in proc_stdout:
            if transcript is not None:
                transcript.write(line)
                transcript.flush()
            elif governor_console_log_active():
                # Standalone callers may not have a campaign directory/session.
                governor_console_log_line(line)
            try:
                parser.feed(line)
            except Exception as exc:
                msg = f"live progress parse error: {exc}\n"
                sys.stderr.write(msg)
                sys.stderr.flush()
                if transcript is not None:
                    transcript.write(msg)
                    transcript.flush()
                else:
                    governor_console_log_line(msg)
            if log_session is not None and log_session.has_active():
                log_session.append_line(line)
            if forward_stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
            if proc is not None:
                stripped = _strip_ansi(line.strip())
                if _FATAL_WORKERD.search(stripped):
                    from harness.common import (
                        _ensure_process_terminated,
                        _terminate_process,
                    )

                    _terminate_process(proc)
                    _ensure_process_terminated(proc)
                    break
    except (ValueError, OSError) as exc:
        # Expected when the parent terminates the child while this thread reads stdout.
        poll = getattr(proc, "poll", None)
        if callable(poll) and poll() is None:
            msg = f"harness stdout reader: {exc}\n"
            if transcript is not None:
                transcript.write(msg)
                transcript.flush()
            else:
                from harness.governor_console_log import governor_console_log_note

                governor_console_log_note(msg.rstrip())
    finally:
        if transcript is not None:
            transcript.close()
