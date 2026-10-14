"""Shared test campaign harness utilities."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import signal
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Iterator, Literal, Optional, Sequence

StepKind = Literal["sql", "shell", "node", "psql"]


def find_repo_root(start: Path) -> Path:
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return candidate
    return current.resolve()


REPO_ROOT = find_repo_root(Path(__file__).resolve().parent)

# When a subcampaign is omitted, run this id if present for the area.
AREA_DEFAULT_SUBCAMPAIGN: dict[str, str] = {
    "frontend": "all",
    "backend": "all",
    "ai-platform": "npm-test",
    "abo": "system",
    "e2e-fullstack": "all-ci",
    "vendor-contracts": "all",
    "ops-launch": "launch-check",
}


def default_subcampaign(area: str, subcampaigns: dict[str, object]) -> str | None:
    preferred = AREA_DEFAULT_SUBCAMPAIGN.get(area)
    if preferred and preferred in subcampaigns:
        return preferred
    if "all" in subcampaigns:
        return "all"
    names = sorted(subcampaigns.keys())
    return names[0] if names else None


def _subprocess_env() -> dict[str, str]:
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    if os.environ.get("AICLINIC_LIVE_PROGRESS") == "1":
        env["AICLINIC_LIVE_PROGRESS"] = "1"
    return env


def live_progress_child_enabled() -> bool:
    return os.environ.get("AICLINIC_LIVE_PROGRESS") == "1"


def campaign_interactive_ui_enabled() -> bool:
    """Rich / in-place batch dashboard (off in CI log streams)."""
    if os.environ.get("AICLINIC_PLAIN_CAMPAIGN_LOG", "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    ):
        return False
    if os.environ.get("GITHUB_ACTIONS", "").strip().lower() == "true":
        return False
    if os.environ.get("CI", "").strip().lower() in ("1", "true", "yes"):
        return False
    return True


def _subprocess_env_for_child(
    *,
    campaign_log_dir: Path | None = None,
    governor_run_id: str | None = None,
    governor_resume: bool = False,
    exclude_tests_file: Path | None = None,
) -> dict[str, str]:
    from harness.campaign_resume import (
        CAMPAIGN_RESUME_ENV,
        EXCLUDE_TESTS_FILE_ENV,
    )
    env = _subprocess_env()
    env["AICLINIC_LIVE_PROGRESS"] = "1"
    if campaign_log_dir is not None:
        env[CAMPAIGN_LOG_DIR_ENV] = str(campaign_log_dir.resolve())
    if governor_run_id:
        env[GOVERNOR_RUN_ID_ENV] = governor_run_id
    if governor_resume:
        env[CAMPAIGN_RESUME_ENV] = "1"
    if exclude_tests_file is not None:
        env[EXCLUDE_TESTS_FILE_ENV] = str(exclude_tests_file.resolve())
    from harness.governor_console_log import GOVERNOR_CONSOLE_LOG_ENV

    console_log = os.environ.get(GOVERNOR_CONSOLE_LOG_ENV)
    if console_log:
        env[GOVERNOR_CONSOLE_LOG_ENV] = console_log
    return env


def test_results_root() -> Path:
    return REPO_ROOT / "test-results"


CAMPAIGN_LOG_DIR_ENV = "AICLINIC_CAMPAIGN_LOG_DIR"
GOVERNOR_RUN_ID_ENV = "AICLINIC_TEST_RUN_ID"


def campaign_log_dir(area: str, subcampaign: str, run_id: str) -> Path:
    return test_results_root() / area / subcampaign / run_id


def governor_run_root(run_id: str) -> Path:
    """Root directory for one governor invocation (batch or single)."""
    return test_results_root() / "governor" / run_id


def governor_campaign_log_dir(run_root: Path, area: str, subcampaign: str) -> Path:
    """Per-campaign logs under a governor run: ``<run_root>/<area>/<subcampaign>/``."""
    return run_root / area / subcampaign


def resolve_campaign_log_dir(area: str, subcampaign: str, run_id: str) -> Path:
    """Honor ``AICLINIC_CAMPAIGN_LOG_DIR`` when the governor sets it for child scripts."""
    override = os.environ.get(CAMPAIGN_LOG_DIR_ENV)
    if override:
        return Path(override).resolve()
    return campaign_log_dir(area, subcampaign, run_id)


def resolve_governor_run_id(fallback: str | None = None) -> str:
    return os.environ.get(GOVERNOR_RUN_ID_ENV) or fallback or new_run_id()


def new_run_id() -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{stamp}-{uuid.uuid4().hex[:8]}"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _format_elapsed(seconds: float) -> str:
    total = int(max(0.0, seconds))
    minutes, secs = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def _subprocess_test_label(cmd: Sequence[str]) -> str:
    if not cmd:
        return "command"
    base = Path(cmd[0]).name
    if len(cmd) > 1:
        return f"{base} {' '.join(cmd[1:3])}".strip()
    return base


def _emit_resume_status(message: str) -> None:
    from harness.governor_console_log import governor_console_log_line

    line = f"CAMPAIGN_STATUS: {message}\n"
    governor_console_log_line(line)
    if live_progress_child_enabled():
        sys.stdout.write(line)
        sys.stdout.flush()


def plan_vitest_execution_batches(
    cmd: list[str],
    cwd: Path,
    exclude: set[str],
    *,
    area: str | None,
    subcampaign: str | None,
    status: Callable[[str], None] | None = None,
) -> tuple[Literal["skip", "run"], list[list[str]]]:
    """Map a vitest run argv to one or more filtered invocations (or skip if all excluded)."""
    from harness.vitest_resume import _is_vitest_run_cmd, plan_vitest_resume_commands

    def notify(message: str) -> None:
        _emit_resume_status(message)
        if status is not None:
            status(message)

    if not exclude:
        return "run", [cmd]
    if not _is_vitest_run_cmd(cmd):
        return "run", [cmd]
    notify("Discovering remaining tests…")
    plan = plan_vitest_resume_commands(
        cmd,
        cwd,
        exclude,
        area=area,
        subcampaign=subcampaign,
        on_status=notify,
    )
    if plan is None:
        return "run", [cmd]
    if plan.skip_entirely:
        return "skip", []
    return "run", plan.commands


def _subprocess_popen_kwargs() -> dict[str, object]:
    """
    New session only for a top-level harness child (e.g. governor → area script).

    Nested runners (area script → vitest/node) must stay in the same process
    group so ``killpg`` from the governor tears down workerd/wrangler too.
    """
    if sys.platform == "win32":
        return {}
    if live_progress_child_enabled():
        return {}
    return {"start_new_session": True}


def _process_group_id(proc: subprocess.Popen[str]) -> int | None:
    try:
        return os.getpgid(proc.pid)
    except (ProcessLookupError, PermissionError, OSError):
        return None


def _child_pids(parent_pid: int) -> list[int]:
    if sys.platform == "win32":
        return []
    children: list[int] = []
    proc_root = Path("/proc")
    try:
        entries = proc_root.iterdir()
    except OSError:
        return children
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / "stat").read_text(encoding="utf-8")
            ppid = int(stat.split()[3])
        except (OSError, ValueError, IndexError):
            continue
        if ppid == parent_pid:
            children.append(int(entry.name))
    return children


def _signal_process_tree(pid: int, sig: int) -> None:
    for child in _child_pids(pid):
        _signal_process_tree(child, sig)
    try:
        os.kill(pid, sig)
    except (ProcessLookupError, PermissionError, OSError):
        pass


def _release_fullstack_ports_after_interrupt() -> None:
    try:
        from harness.local_dev_ports import release_stale_fullstack_dev_ports

        release_stale_fullstack_dev_ports()
    except Exception:
        pass


_MONITORED_PROCS: list[subprocess.Popen[str]] = []
_MONITORED_PROCS_LOCK = threading.Lock()
_CAMPAIGN_SIGINT_INSTALLED = False
_SIGINT_PRESS_COUNT = 0


def _campaign_sigint_handler(_signum: int, _frame: object) -> None:
    """Terminate every registered harness child; second press forces exit."""
    global _SIGINT_PRESS_COUNT
    _SIGINT_PRESS_COUNT += 1
    with _MONITORED_PROCS_LOCK:
        targets = list(_MONITORED_PROCS)
    for proc in reversed(targets):
        try:
            _terminate_process(proc)
        except Exception:
            pass
    _release_fullstack_ports_after_interrupt()
    if _SIGINT_PRESS_COUNT >= 2:
        os._exit(130)
    raise KeyboardInterrupt


def ensure_campaign_sigint_handler() -> None:
    global _CAMPAIGN_SIGINT_INSTALLED
    if _CAMPAIGN_SIGINT_INSTALLED or sys.platform == "win32":
        return
    signal.signal(signal.SIGINT, _campaign_sigint_handler)
    _CAMPAIGN_SIGINT_INSTALLED = True


@contextlib.contextmanager
def _monitored_subprocess(proc: subprocess.Popen[str]) -> Iterator[None]:
    ensure_campaign_sigint_handler()
    with _MONITORED_PROCS_LOCK:
        _MONITORED_PROCS.append(proc)
    try:
        yield
    finally:
        with _MONITORED_PROCS_LOCK:
            try:
                _MONITORED_PROCS.remove(proc)
            except ValueError:
                pass


def _terminate_process(proc: subprocess.Popen[str]) -> None:
    """Stop a child process and its descendants (vitest, workerd, etc.)."""
    if proc.poll() is not None:
        return
    try:
        _signal_process_tree(proc.pid, signal.SIGINT)
    except (ProcessLookupError, PermissionError, OSError):
        pass
    pgid = _process_group_id(proc)
    if pgid is not None:
        try:
            os.killpg(pgid, signal.SIGINT)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    else:
        try:
            proc.send_signal(signal.SIGINT)
        except ProcessLookupError:
            return
    try:
        proc.wait(timeout=5)
        return
    except (ProcessLookupError, subprocess.TimeoutExpired):
        pass
    try:
        _signal_process_tree(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        pass
    if pgid is not None:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    try:
        proc.kill()
        proc.wait(timeout=5)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        pass


def _ensure_process_terminated(
    proc: subprocess.Popen[str], *, timeout: float = 20.0
) -> None:
    """Block until ``proc`` exits or force-kill the process group."""
    if proc.poll() is not None:
        return
    deadline = time.monotonic() + timeout
    while proc.poll() is None and time.monotonic() < deadline:
        time.sleep(0.1)
    if proc.poll() is not None:
        return
    _terminate_process(proc)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def _run_monitored_child_process(
    proc: subprocess.Popen[str],
    parser: object,
    session: object,
    *,
    stall_guard: object,
    crash_guard: object,
    progress: object | None = None,
    forward_stdout: bool = False,
    poll_interval: float = 0.25,
) -> tuple[int, bool]:
    """Pump stdout on a thread; abort on stall/crash; return (exit_code, harness_killed)."""
    from harness.live_progress import pump_process_output

    assert proc.stdout is not None
    reader = threading.Thread(
        target=pump_process_output,
        args=(proc.stdout, parser, session),
        kwargs={"forward_stdout": forward_stdout, "proc": proc},
        daemon=True,
    )
    reader.start()
    harness_killed = False
    exit_code = 0
    try:
        with _monitored_subprocess(proc):
            while proc.poll() is None:
                if progress is not None:
                    progress.tick(subprocess_alive=True)
                if crash_guard.should_abort() or stall_guard.should_abort():
                    if crash_guard.should_abort():
                        abort_error = crash_guard.abort_error()
                        crash_guard.mark_aborted()
                    else:
                        abort_error = stall_guard.abort_error()
                    _log_harness_runner_test_failure(
                        session,
                        name=stall_guard.failure_test_name(),
                        error=abort_error,
                        progress=progress,
                        forward_stdout=forward_stdout,
                    )
                    stall_guard.mark_aborted()
                    _terminate_process(proc)
                    _ensure_process_terminated(proc)
                    harness_killed = True
                    exit_code = 1
                    break
                time.sleep(poll_interval)
            if not harness_killed:
                if progress is not None:
                    progress.tick(subprocess_alive=False)
                reader.join(timeout=30)
                exit_code = proc.returncode if proc.returncode is not None else 1
                dangling: str | None = None
                if progress is not None:
                    dangling = progress.record_dangling_failure_on_exit(exit_code)
                else:
                    dangling = stall_guard.dangling_failure_on_exit(exit_code)
                if dangling is not None:
                    _log_harness_runner_test_failure(
                        session,
                        name=dangling,
                        error=(
                            f"runner exited with code {exit_code} "
                            "before reporting a result"
                        ),
                        progress=progress,
                        forward_stdout=forward_stdout,
                    )
            else:
                reader.join(timeout=5)
                exit_code = max(exit_code, proc.returncode or 1)
    except KeyboardInterrupt:
        from harness.campaign_logging import CampaignLogSession

        if isinstance(session, CampaignLogSession):
            session.abort_current_test()
        _terminate_process(proc)
        _ensure_process_terminated(proc)
        _release_fullstack_ports_after_interrupt()
        reader.join(timeout=5)
        raise
    return exit_code, harness_killed


def run_subprocess(cmd: Sequence[str], cwd: Path, log_dir: Path) -> int:
    """Run a command; capture output in ``tests/`` and write ``summary.json``."""
    from harness.campaign_logging import CampaignLogSession

    log_dir.mkdir(parents=True, exist_ok=True)
    started_at = utc_now_iso()
    start_mono = time.monotonic()
    session = CampaignLogSession(log_dir)
    label = _subprocess_test_label(cmd)
    session.start_test(label)
    session.append_output(f"$ {' '.join(cmd)}\n")
    from harness.governor_console_log import governor_console_output_path

    transcript_path = governor_console_output_path(log_dir)
    transcript_path.parent.mkdir(parents=True, exist_ok=True)
    transcript = transcript_path.open("a", encoding="utf-8")

    live = live_progress_child_enabled()
    try:
        proc = subprocess.Popen(
            list(cmd),
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=_subprocess_env(),
            **_subprocess_popen_kwargs(),
        )
    except Exception:
        transcript.close()
        raise
    assert proc.stdout is not None
    from harness.live_progress import should_forward_progress_stdout_line

    try:
        for line in proc.stdout:
            session.append_line(line)
            transcript.write(line)
            transcript.flush()
            if live and should_forward_progress_stdout_line(line):
                sys.stdout.write(line)
                sys.stdout.flush()
        exit_code = proc.wait()
    except KeyboardInterrupt:
        _terminate_process(proc)
        transcript.close()
        session.abort_current_test()
        session.write_summary(
            command=list(cmd),
            cwd=str(cwd.resolve()),
            started_at=started_at,
            exit_code=130,
            interrupted=True,
            elapsed_seconds=round(time.monotonic() - start_mono, 3),
        )
        raise SystemExit(130) from None
    finally:
        if not transcript.closed:
            transcript.close()

    status = "PASS" if exit_code == 0 else "FAIL"
    session.end_test(label, status=status)
    session.write_summary(
        command=list(cmd),
        cwd=str(cwd.resolve()),
        started_at=started_at,
        exit_code=exit_code,
        elapsed_seconds=round(time.monotonic() - start_mono, 3),
    )
    return exit_code


def _log_harness_runner_test_failure(
    session: object,
    *,
    name: str,
    error: str,
    progress: object | None,
    forward_stdout: bool,
) -> None:
    from harness.campaign_logging import CampaignLogSession
    from harness.live_progress import (
        CampaignProgressDisplay,
        synthetic_vitest_fail_line,
    )

    if isinstance(progress, CampaignProgressDisplay):
        progress.record_stall_failure(name, error)
    if isinstance(session, CampaignLogSession):
        session.start_test(name)
        session.append_line(f"harness: {error}\n")
        session.end_test(name, status="FAIL", error=error)
    from harness.governor_console_log import (
        governor_console_log_line,
        governor_console_output_path,
    )

    output_path = governor_console_output_path(
        getattr(session, "log_dir", Path.cwd())
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("a", encoding="utf-8") as handle:
        handle.write(synthetic_vitest_fail_line(name))
        handle.write(f"harness: {error}\n")
    if forward_stdout:
        sys.stdout.write(synthetic_vitest_fail_line(name))
        sys.stdout.flush()


def run_subprocess_with_live_status(
    cmd: Sequence[str],
    cwd: Path,
    log_dir: Path,
    *,
    status_label: str,
    poll_interval: float = 0.25,
    display: object | None = None,
    batch_queue: object | None = None,
    campaign_config: dict | None = None,
    config_area: str | None = None,
    final_finish: bool = True,
    governor_run_id: str | None = None,
    governor_resume: bool = False,
    exclude_tests_file: Path | None = None,
) -> int:
    """Run a command with live current-test line and finished-test table on stderr."""
    ensure_campaign_sigint_handler()
    from harness.campaign_logging import CampaignLogSession
    from harness.campaign_resume import (
        exclude_tests_from_environ,
        prior_passed_counts,
        prior_results_from_summary,
        read_exclude_tests_file,
    )
    from harness.live_progress import (
        CampaignProgressDisplay,
        CrashInspectParser,
        NoOpCampaignProgressDisplay,
        RunnerCrashGuard,
        RunnerStallGuard,
        StallTrackingDisplay,
        TouchProgressParser,
        _parse_status_label,
        parser_for_command,
    )
    log_dir.mkdir(parents=True, exist_ok=True)
    started_at = utc_now_iso()
    start_mono = time.monotonic()
    session = CampaignLogSession(log_dir, resume=governor_resume)
    exclude = (
        read_exclude_tests_file(exclude_tests_file)
        if exclude_tests_file is not None
        else exclude_tests_from_environ()
    )
    campaign_name, sub_name = _parse_status_label(status_label.strip())
    effective_area = config_area or campaign_name
    effective_sub = sub_name or campaign_name
    cmd_list = list(cmd)

    delegate_ui = live_progress_child_enabled() and not isinstance(
        display, CampaignProgressDisplay
    )
    forward_stdout = delegate_ui

    prior_passed, prior_failed, prior_failures = (
        prior_results_from_summary(log_dir) if governor_resume else (0, 0, [])
    )
    if isinstance(display, CampaignProgressDisplay):
        progress = display
        progress.prepare_run(
            status_label,
            log_dir,
            batch_queue=batch_queue,
            campaign_config=campaign_config,
            config_area=config_area,
        )
        if governor_resume:
            progress.seed_prior_results(
                prior_passed,
                prior_failed,
                failure_names=prior_failures,
            )
        progress.begin(clear_screen=False)
        parser_target = progress
    elif delegate_ui:
        progress = None
        parser_target = NoOpCampaignProgressDisplay()
    else:
        run_log_root = (
            governor_run_root(governor_run_id) if governor_run_id else None
        )
        progress = CampaignProgressDisplay(
            status_label,
            log_dir=log_dir,
            batch_queue=batch_queue,
            campaign_config=campaign_config,
            config_area=config_area,
            run_log_root=run_log_root,
        )
        progress.prepare_run(
            status_label,
            log_dir,
            batch_queue=batch_queue,
            campaign_config=campaign_config,
            config_area=config_area,
        )
        if governor_resume:
            progress.seed_prior_results(
                prior_passed,
                prior_failed,
                failure_names=prior_failures,
            )
        progress.begin(clear_screen=sys.stderr.isatty())
        parser_target = progress

    def _resume_status(message: str) -> None:
        if progress is not None:
            progress.set_current(message)

    outcome, cmd_batches = plan_vitest_execution_batches(
        cmd_list,
        cwd,
        exclude,
        area=effective_area,
        subcampaign=effective_sub,
        status=_resume_status,
    )
    if outcome == "skip":
        session.write_summary(
            command=cmd_list,
            cwd=str(cwd.resolve()),
            started_at=started_at,
            finished_at=utc_now_iso(),
            elapsed_seconds=round(time.monotonic() - start_mono, 3),
            exit_code=0,
            status_label=status_label,
            passed=prior_passed,
            failed=prior_failed,
            resumed=governor_resume,
        )
        if progress is not None:
            progress.finish(interrupted=False, final=final_finish)
        return 0

    session._summary_fields = {
        "command": cmd_list,
        "cwd": str(cwd.resolve()),
        "started_at": started_at,
        "status_label": status_label,
    }

    interrupted = False
    harness_error = False
    exit_code = 0
    child_env = _subprocess_env_for_child(
        campaign_log_dir=log_dir,
        governor_run_id=governor_run_id,
        governor_resume=governor_resume,
        exclude_tests_file=exclude_tests_file,
    )
    try:
        for batch_index, batch_cmd in enumerate(cmd_batches):
            if batch_index > 0:
                if progress is not None:
                    progress.set_current(
                        f"Running filtered batch {batch_index + 1}/{len(cmd_batches)}…"
                    )
                _emit_resume_status(
                    f"Running filtered batch {batch_index + 1}/{len(cmd_batches)}…"
                )
            stall_guard = RunnerStallGuard(
                campaign_config,
                subcampaign=effective_sub or "campaign",
            )
            crash_guard = RunnerCrashGuard(stall_guard)
            stall_parser_target = StallTrackingDisplay(parser_target, stall_guard)
            parser = CrashInspectParser(
                TouchProgressParser(
                    parser_for_command(
                        batch_cmd,
                        stall_parser_target,
                        log_session=session,
                        exclude_tests=exclude,
                    ),
                    stall_guard,
                ),
                crash_guard,
            )
            proc = subprocess.Popen(
                batch_cmd,
                cwd=str(cwd),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env=child_env,
                **_subprocess_popen_kwargs(),
            )
            try:
                batch_code, _stall_killed = _run_monitored_child_process(
                    proc,
                    parser,
                    session,
                    stall_guard=stall_guard,
                    crash_guard=crash_guard,
                    progress=progress,
                    forward_stdout=forward_stdout,
                    poll_interval=poll_interval,
                )
            except KeyboardInterrupt:
                interrupted = True
                exit_code = 130
                session.abort_current_test()
                break
            except Exception:
                harness_error = True
                raise
            exit_code = max(exit_code, batch_code)
            if batch_code != 0 and not (
                governor_resume and len(cmd_batches) > 1
            ):
                break
    except Exception:
        harness_error = True
        raise
    finally:
        if progress is not None:
            progress.finish(
                interrupted=interrupted or harness_error,
                final=final_finish or harness_error or interrupted,
            )

    if progress is not None:
        passed, failed = progress.passed, progress.failed
    else:
        passed, failed = session.deduped_pass_fail_counts()
        if passed == 0 and failed == 0 and governor_resume:
            passed, failed = prior_passed, prior_failed
    session.write_summary(
        command=cmd_list,
        cwd=str(cwd.resolve()),
        started_at=started_at,
        finished_at=utc_now_iso(),
        elapsed_seconds=round(time.monotonic() - start_mono, 3),
        exit_code=exit_code if not interrupted else 130,
        status_label=status_label,
        passed=passed,
        failed=failed,
        resumed=governor_resume,
        interrupted=interrupted,
        output_file="output.log",
    )
    _maybe_reconcile_vitest_summary(
        log_dir,
        cmd_list,
        cwd=cwd,
        area=config_area or effective_area,
        subcampaign=effective_sub,
        campaign_config=campaign_config,
    )
    if interrupted:
        raise SystemExit(130)
    return exit_code


def run_subprocess_sequence(
    steps: Sequence[tuple[str, Sequence[str]]],
    cwd: Path,
    log_dir: Path,
    *,
    status_label: str | None = None,
    campaign_config: dict | None = None,
    config_area: str | None = None,
    continue_on_step_failure: bool = False,
) -> int:
    """Run commands in order; one log per step under ``tests/``; write ``summary.json``."""
    from harness.campaign_logging import CampaignLogSession
    from harness.live_progress import (
        CampaignProgressDisplay,
        CrashInspectParser,
        NoOpCampaignProgressDisplay,
        RunnerCrashGuard,
        RunnerStallGuard,
        StallTrackingDisplay,
        TouchProgressParser,
        _parse_status_label,
        parser_for_command,
    )

    log_dir.mkdir(parents=True, exist_ok=True)
    started_at = utc_now_iso()
    start_mono = time.monotonic()
    from harness.campaign_resume import campaign_resume_enabled

    session = CampaignLogSession(log_dir, resume=campaign_resume_enabled())
    step_records: list[dict[str, object]] = []
    overall = 0

    live = live_progress_child_enabled()
    use_display = (
        status_label is not None and sys.stderr.isatty() and not live
    )
    progress: CampaignProgressDisplay | None = None
    if use_display:
        progress = CampaignProgressDisplay(
            status_label,
            log_dir=log_dir,
            campaign_config=campaign_config,
            config_area=config_area,
        )
        progress.begin()
    parser_display: CampaignProgressDisplay | NoOpCampaignProgressDisplay | None = (
        progress if progress is not None else (NoOpCampaignProgressDisplay() if live else None)
    )

    from harness.campaign_resume import campaign_resume_enabled, exclude_tests_from_environ

    exclude_set = exclude_tests_from_environ() if campaign_resume_enabled() else set()
    exclude_for_parser = exclude_set if exclude_set else None
    campaign_name, sub_name = (
        _parse_status_label(status_label.strip())
        if status_label
        else (None, None)
    )
    effective_area = config_area or campaign_name
    effective_sub = sub_name or campaign_name

    interrupted = False
    try:
        for step_name, cmd in steps:
            if step_name in exclude_set:
                if progress is not None:
                    progress.add_finished(step_name, "PASS")
                session.end_test(
                    step_name,
                    status="PASS",
                    skipped=True,
                    resumed=True,
                )
                step_records.append(
                    {
                        "name": step_name,
                        "command": list(cmd),
                        "status": "PASS",
                        "resumed": True,
                        "exit_code": 0,
                    }
                )
                continue
            banner = f"== {step_name} ==\n"
            if live or use_display:
                sys.stdout.write(banner)
                sys.stdout.flush()
            if progress is not None:
                progress.set_nested_subcampaign(step_name)
            session.start_test(step_name)
            step_started = utc_now_iso()
            step_mono = time.monotonic()
            outcome, cmd_batches = plan_vitest_execution_batches(
                list(cmd),
                cwd,
                exclude_set,
                area=effective_area,
                subcampaign=effective_sub or step_name,
            )
            if outcome == "skip":
                if progress is not None:
                    progress.add_finished(step_name, "PASS")
                session.end_test(
                    step_name,
                    status="PASS",
                    skipped=True,
                    resumed=True,
                )
                step_records.append(
                    {
                        "name": step_name,
                        "command": list(cmd),
                        "status": "PASS",
                        "resumed": True,
                        "exit_code": 0,
                    }
                )
                continue

            step_exit = 0
            for batch_index, batch_cmd in enumerate(cmd_batches):
                batch_banner = banner
                if len(cmd_batches) > 1:
                    batch_banner = (
                        f"{banner}$ ({batch_index + 1}/{len(cmd_batches)}) "
                        f"{' '.join(batch_cmd)}\n\n"
                    )
                else:
                    batch_banner = banner + f"$ {' '.join(batch_cmd)}\n\n"
                if batch_index == 0:
                    session.append_output(batch_banner)
                else:
                    session.append_output(batch_banner)
                proc = subprocess.Popen(
                    batch_cmd,
                    cwd=str(cwd),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    env=_subprocess_env_for_child()
                    if (use_display or live)
                    else _subprocess_env(),
                    **_subprocess_popen_kwargs(),
                )
                assert proc.stdout is not None

                if parser_display is not None:
                    from harness.campaign_config import nested_subcampaign_config

                    step_config = campaign_config
                    if config_area:
                        step_config = (
                            nested_subcampaign_config(config_area, step_name)
                            or campaign_config
                        )
                    stall_guard = RunnerStallGuard(
                        step_config,
                        subcampaign=effective_sub or step_name,
                    )
                    crash_guard = RunnerCrashGuard(stall_guard)
                    stall_parser_target = StallTrackingDisplay(
                        parser_display, stall_guard
                    )
                    parser = CrashInspectParser(
                        TouchProgressParser(
                            parser_for_command(
                                batch_cmd,
                                stall_parser_target,
                                log_session=session,
                                exclude_tests=exclude_for_parser,
                            ),
                            stall_guard,
                        ),
                        crash_guard,
                    )
                    sequence_progress = (
                        progress if isinstance(progress, CampaignProgressDisplay) else None
                    )
                    try:
                        batch_exit, _ = _run_monitored_child_process(
                            proc,
                            parser,
                            session,
                            stall_guard=stall_guard,
                            crash_guard=crash_guard,
                            progress=sequence_progress,
                            forward_stdout=live,
                        )
                    except KeyboardInterrupt:
                        interrupted = True
                        overall = 130
                        session.abort_current_test()
                        break
                else:
                    try:
                        from harness.governor_console_log import (
                            governor_console_output_path,
                        )

                        transcript_path = governor_console_output_path(log_dir)
                        transcript_path.parent.mkdir(parents=True, exist_ok=True)
                        transcript = transcript_path.open("a", encoding="utf-8")
                        for line in proc.stdout:
                            session.append_line(line)
                            transcript.write(line)
                            transcript.flush()
                        batch_exit = proc.wait()
                    except KeyboardInterrupt:
                        interrupted = True
                        overall = 130
                        _terminate_process(proc)
                        session.abort_current_test()
                        break
                    finally:
                        if "transcript" in locals() and not transcript.closed:
                            transcript.close()
                step_exit = max(step_exit, batch_exit)
                if batch_exit != 0 and not (
                    campaign_resume_enabled() and len(cmd_batches) > 1
                ):
                    break

            if interrupted:
                break

            exit_code = step_exit
            status = "PASS" if exit_code == 0 else "FAIL"
            session.end_test(step_name, status=status)
            step_records.append(
                {
                    "name": step_name,
                    "command": list(cmd),
                    "started_at": step_started,
                    "finished_at": utc_now_iso(),
                    "elapsed_seconds": round(time.monotonic() - step_mono, 3),
                    "exit_code": exit_code,
                    "status": status,
                }
            )
            overall = max(overall, exit_code)
            if (
                exit_code != 0
                and not campaign_resume_enabled()
                and not continue_on_step_failure
            ):
                break
    finally:
        if progress is not None:
            progress.finish(interrupted=interrupted)

    session.write_summary(
        cwd=str(cwd.resolve()),
        started_at=started_at,
        elapsed_seconds=round(time.monotonic() - start_mono, 3),
        exit_code=overall if not interrupted else 130,
        interrupted=interrupted,
        steps=step_records,
    )
    _maybe_reconcile_vitest_summary(
        log_dir,
        [],
        cwd=cwd,
        area=config_area or campaign_name,
        subcampaign=effective_sub or sub_name,
        campaign_config=campaign_config,
    )
    if interrupted:
        raise SystemExit(130)
    return overall


def _maybe_reconcile_vitest_summary(
    log_dir: Path,
    cmd: list[str],
    *,
    cwd: Path,
    area: str | None,
    subcampaign: str | None,
    campaign_config: dict | None,
) -> None:
    from harness.campaign_vitest_reconcile import (
        reconcile_vitest_summary_log,
        should_reconcile_vitest_campaign,
    )

    if not area or not subcampaign:
        return
    if not should_reconcile_vitest_campaign(
        cmd,
        area=area,
        subcampaign=subcampaign,
        campaign_config=campaign_config,
    ):
        return
    reconcile_vitest_summary_log(
        log_dir,
        area=area,
        subcampaign=subcampaign,
        cwd=cwd,
    )


def make_arg_parser(
    area: str,
    subcampaigns: dict[str, object],
    *,
    description: str | None = None,
) -> argparse.ArgumentParser:
    names = sorted(subcampaigns.keys())
    parser = argparse.ArgumentParser(
        prog=f"{area} run_campaigns",
        description=description or f"Run {area} test campaigns.",
    )
    parser.add_argument(
        "subcampaign",
        nargs="?",
        choices=names,
        help="Campaign to run (default: area default, usually 'all').",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available subcampaigns and exit.",
    )
    return parser


def resolve_subcampaign(
    args: argparse.Namespace,
    subcampaigns: dict[str, object],
    area: str | None = None,
) -> str | None:
    if args.list:
        from harness.campaign_catalog import list_subcampaign_ids

        list_subcampaign_ids(area or "unknown", sorted(subcampaigns.keys()))
        return None
    if args.subcampaign:
        return args.subcampaign
    if area:
        return default_subcampaign(area, subcampaigns)
    names = sorted(subcampaigns.keys())
    return names[0] if names else None


def ensure_harness_import() -> None:
    """Allow `from harness.common import ...` when invoked as a script under repo."""
    test_pkg = REPO_ROOT / "test"
    path = str(test_pkg)
    if path not in sys.path:
        sys.path.insert(0, path)


# --- Backend SQL/shell campaign helpers (used by backend/tests/run_campaigns.py) ---


@dataclass
class TestStep:
    name: str
    kind: StepKind
    target: str
    skip_if_missing: bool = False


@dataclass
class StepResult:
    name: str
    kind: str
    passed: bool
    skipped: bool = False
    error: Optional[str] = None


@dataclass
class CampaignMeta:
    subcampaign: str
    run_id: str
    started_at: str
    finished_at: Optional[str] = None
    repo_root: str = ""
    results: list[StepResult] = field(default_factory=list)
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    exit_code: Optional[int] = None


def load_backend_local_env(repo_root: Path = REPO_ROOT) -> None:
    env_path = repo_root / "backend" / "local" / ".env"
    if not env_path.is_file():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        os.environ[key] = value


def db_port() -> str:
    return os.environ.get("SUPABASE_DB_PORT", "54322")


def db_password() -> str:
    return os.environ.get("POSTGRES_PASSWORD", "postgres")


def _psql_base_env() -> dict[str, str]:
    env = os.environ.copy()
    env["PGPASSWORD"] = db_password()
    return env


class TestHarness:
    def __init__(
        self,
        repo_root: Path,
        tests_dir: Path,
        subcampaign: str,
        run_id: str,
        area: str = "backend",
        *,
        live_label: str | None = None,
    ) -> None:
        self.repo_root = repo_root
        self.tests_dir = tests_dir
        self.subcampaign = subcampaign
        self.run_id = run_id
        self.area = area
        self.log_dir = resolve_campaign_log_dir(area, subcampaign, run_id)
        self._live_label = live_label
        self._live_display = None
        self.log_dir.mkdir(parents=True, exist_ok=True)
        from harness.campaign_logging import CampaignLogSession

        from harness.campaign_resume import campaign_resume_enabled

        self._log_session = CampaignLogSession(
            self.log_dir, resume=campaign_resume_enabled()
        )
        self.meta_path = self.log_dir / "summary.json"
        self.meta = CampaignMeta(
            subcampaign=subcampaign,
            run_id=run_id,
            started_at=utc_now_iso(),
            repo_root=str(repo_root),
        )

    def _write(self, text: str) -> None:
        self._log_session.append_output(text)

    def _run_psql_file(self, sql_path: Path) -> tuple[bool, Optional[str]]:
        cmd = [
            "psql",
            "-h",
            "127.0.0.1",
            "-p",
            db_port(),
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
            "-f",
            str(sql_path),
        ]
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=_psql_base_env(),
        )
        if proc.stdout:
            self._write(proc.stdout)
        if proc.stderr:
            self._write(proc.stderr)
        if proc.returncode == 0:
            return True, None
        err = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        return False, err

    def _run_psql_sql(self, sql: str) -> tuple[bool, Optional[str]]:
        cmd = [
            "psql",
            "-h",
            "127.0.0.1",
            "-p",
            db_port(),
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
            "-c",
            sql,
        ]
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=_psql_base_env(),
        )
        if proc.stdout:
            self._write(proc.stdout)
        if proc.stderr:
            self._write(proc.stderr)
        if proc.returncode == 0:
            return True, None
        err = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        return False, err

    def _run_shell(self, script_path: Path) -> tuple[bool, Optional[str]]:
        proc = subprocess.run(
            ["bash", str(script_path)],
            cwd=str(self.tests_dir),
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        )
        if proc.stdout:
            self._write(proc.stdout)
        if proc.stderr:
            self._write(proc.stderr)
        if proc.returncode == 0:
            return True, None
        err = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        return False, err

    def _run_node(self, script_path: Path) -> tuple[bool, Optional[str]]:
        proc = subprocess.run(
            ["node", str(script_path)],
            cwd=str(self.tests_dir),
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        )
        if proc.stdout:
            self._write(proc.stdout)
        if proc.stderr:
            self._write(proc.stderr)
        if proc.returncode == 0:
            return True, None
        err = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        return False, err

    def _live(self):
        if self._live_display is None and self._live_label:
            from harness.live_progress import CampaignProgressDisplay

            self._live_display = CampaignProgressDisplay(
                self._live_label, log_dir=self.log_dir
            )
            self._live_display.begin()
        return self._live_display

    def run_step(self, step: TestStep, index: int) -> StepResult:
        from harness.campaign_resume import exclude_tests_from_environ

        if step.name in exclude_tests_from_environ():
            header = f"== [{index}] {step.name} ==\n"
            self._write(header)
            print(header, end="", flush=True)
            msg = "   SKIP (resumed)\n"
            self._write(msg)
            print(msg, end="", flush=True)
            live = self._live()
            if live is not None:
                live.add_finished(step.name, "SKIP")
            self._log_session.end_test(
                step.name, status="PASS", skipped=True, resumed=True
            )
            return StepResult(
                name=step.name, kind=step.kind, passed=True, skipped=True
            )
        self._log_session.start_test(step.name)
        header = f"== [{index}] {step.name} ==\n"
        self._write(header)
        print(header, end="", flush=True)
        live = self._live()
        if live is not None:
            live.set_current(step.name)

        if step.kind in ("sql", "shell", "node"):
            path = self.tests_dir / step.target
            if not path.is_file():
                if step.skip_if_missing:
                    msg = "   SKIP (missing {0})\n".format(step.target)
                    self._write(msg)
                    print(msg, end="", flush=True)
                    if live is not None:
                        live.add_finished(step.name, "SKIP")
                    self._log_session.end_test(
                        step.name, status="SKIP", skipped=True
                    )
                    return StepResult(
                        name=step.name, kind=step.kind, passed=True, skipped=True
                    )
                err = f"missing file: {path}"
                self._write(f"   FAIL {err}\n")
                print("   FAIL", flush=True)
                self._log_session.end_test(
                    step.name, status="FAIL", error=err
                )
                return StepResult(
                    name=step.name, kind=step.kind, passed=False, error=err
                )
            if step.kind == "sql":
                ok, err = self._run_psql_file(path)
            elif step.kind == "shell":
                ok, err = self._run_shell(path)
            else:
                ok, err = self._run_node(path)
        elif step.kind == "psql":
            ok, err = self._run_psql_sql(step.target)
        else:
            ok, err = False, f"unknown step kind: {step.kind}"

        if ok:
            self._write("   PASS\n")
            print("   PASS", flush=True)
            if live is not None:
                live.add_finished(step.name, "PASS")
            self._log_session.end_test(step.name, status="PASS")
            return StepResult(name=step.name, kind=step.kind, passed=True)
        self._write("   FAIL\n")
        print("   FAIL", flush=True)
        if live is not None:
            live.add_finished(step.name, "FAIL")
        self._log_session.end_test(step.name, status="FAIL", error=err)
        return StepResult(name=step.name, kind=step.kind, passed=False, error=err)

    def run_steps(self, steps: Iterable[TestStep]) -> int:
        index = 0
        for step in steps:
            index += 1
            result = self.run_step(step, index)
            self.meta.results.append(result)
            if result.skipped:
                self.meta.skipped += 1
            elif result.passed:
                self.meta.passed += 1
            else:
                self.meta.failed += 1

        self.meta.finished_at = utc_now_iso()
        self.meta.exit_code = 0 if self.meta.failed == 0 else 1
        self._flush_meta()
        live = self._live()
        if live is not None:
            live.finish()
        return self.meta.exit_code or 0

    def _flush_meta(self) -> None:
        results = [asdict(r) for r in self.meta.results]
        self._log_session.write_summary(
            area=self.area,
            subcampaign=self.meta.subcampaign,
            run_id=self.meta.run_id,
            repo_root=self.meta.repo_root,
            exit_code=self.meta.exit_code,
            passed=self.meta.passed,
            failed=self.meta.failed,
            skipped=self.meta.skipped,
            results=results,
        )


def catalog_sql_steps(catalog_dir: Path) -> list[TestStep]:
    steps: list[TestStep] = []
    smoke = catalog_dir / "harness-smoke.sql"
    if smoke.is_file():
        steps.append(
            TestStep("catalog SQL: harness-smoke.sql", "sql", f"catalog/{smoke.name}")
        )
    for path in sorted(catalog_dir.glob("stage-*.sql")):
        rel = f"catalog/{path.name}"
        steps.append(TestStep(f"catalog SQL: {path.name}", "sql", rel))
    return steps


def sql_steps(
    label: str, filenames: Iterable[str], skip_if_missing: bool = False
) -> list[TestStep]:
    return [
        TestStep(f"{label}: {name}", "sql", name, skip_if_missing=skip_if_missing)
        for name in filenames
    ]


RunFn = Callable[[str], int]


def run_campaign_script(
    area: str,
    subcampaigns: dict[str, RunFn],
    argv: Sequence[str] | None = None,
) -> int:
    """Shared main() helper for area run_campaigns.py scripts."""
    ensure_harness_import()
    parser = make_arg_parser(area, subcampaigns)
    args = parser.parse_args(list(argv) if argv is not None else None)
    chosen = resolve_subcampaign(args, subcampaigns, area=area)
    if chosen is None:
        return 0
    return subcampaigns[chosen](chosen)
