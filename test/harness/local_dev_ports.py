"""Release stale local wrangler/workerd ports used by e2e fullstack stacks."""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Sequence

from harness.common import REPO_ROOT

FULLSTACK_WRANGLER_DIR = "e2e/fullstack/.wrangler"

# Default Cloudflare local dev ports for e2e/fullstack (platform, ABO, paymob, harness).
FULLSTACK_DEV_PORTS: tuple[int, ...] = (8787, 8788, 8789, 8790, 9230, 9231)

_PID_RE = re.compile(r"pid=(\d+)")


def _proc_comm(pid: int) -> str:
    try:
        return Path(f"/proc/{pid}/comm").read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _proc_cmdline(pid: int) -> str:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return ""
    return raw.replace(b"\0", b" ").decode("utf-8", errors="replace")


def _is_stale_fullstack_dev_process(pid: int, repo_root: Path) -> bool:
    if pid <= 1 or pid == os.getpid():
        return False
    comm = _proc_comm(pid)
    cmd = _proc_cmdline(pid)
    if comm == "workerd":
        return True
    if "wrangler" in cmd:
        return True
    repo = str(repo_root)
    if comm == "node" and repo in cmd and (
        "wrangler" in cmd or "e2e/fullstack" in cmd or "workerd" in cmd
    ):
        return True
    return False


def pids_listening_on_tcp_port(port: int, host: str = "127.0.0.1") -> list[int]:
    """Return PIDs bound to ``host:port`` from ``ss -tlnp`` (Linux)."""
    try:
        result = subprocess.run(
            ["ss", "-tlnp"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return []
    if result.returncode != 0:
        return []
    needles = (f"{host}:{port}", f"0.0.0.0:{port}", f"*:{port}", f"[::]:{port}")
    pids: list[int] = []
    for line in result.stdout.splitlines():
        if not any(needle in line for needle in needles):
            continue
        for match in _PID_RE.finditer(line):
            try:
                pids.append(int(match.group(1)))
            except ValueError:
                continue
    return sorted(set(pids))


def _terminate_pid(pid: int, *, grace_seconds: float = 5.0) -> bool:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return False
    except PermissionError:
        return False
    deadline = time.monotonic() + grace_seconds
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return True


def release_stale_fullstack_dev_ports(
    *,
    ports: Sequence[int] = FULLSTACK_DEV_PORTS,
    repo_root: Path = REPO_ROOT,
    host: str = "127.0.0.1",
) -> list[int]:
    """
    Stop leftover workerd/wrangler listeners on the fullstack dev ports.

    Used before e2e stack tests (including governor ``--continue``) when a prior
    run was interrupted and ``after()`` hooks did not tear workers down.
    """
    released: list[int] = []
    for port in ports:
        for pid in pids_listening_on_tcp_port(port, host=host):
            if pid in released:
                continue
            if not _is_stale_fullstack_dev_process(pid, repo_root):
                continue
            if _terminate_pid(pid):
                released.append(pid)
                print(
                    f"Released stale fullstack dev port {port} (pid {pid}, {_proc_comm(pid)})",
                    file=sys.stderr,
                )
    return released


def reset_fullstack_wrangler_persist(
    *,
    repo_root: Path = REPO_ROOT,
) -> list[Path]:
    """
    Remove ``e2e/fullstack/.wrangler`` entirely.

    Abrupt workerd shutdown leaves SQLite under ``platform/``, ``d1-seed/``,
    default ``state/``, ``tmp/``, etc. Partial deletes leave schema mismatches
    (``_cf_ALARM`` errors). Platform D1 migrations must use ``d1-seed/`` only;
    see ``e2e/fullstack/test/wrangler-persist.mjs``.
    """
    wrangler_root = repo_root / FULLSTACK_WRANGLER_DIR
    if not wrangler_root.exists():
        return []
    shutil.rmtree(wrangler_root, ignore_errors=True)
    print(
        f"Reset fullstack wrangler persist: {wrangler_root.relative_to(repo_root)}",
        file=sys.stderr,
    )
    return [wrangler_root]


def prepare_fullstack_e2e_stack(
    *,
    repo_root: Path = REPO_ROOT,
) -> tuple[list[int], list[Path]]:
    """Release stale dev ports, then reset wrangler persist before stack tests."""
    released = release_stale_fullstack_dev_ports(repo_root=repo_root)
    if released:
        time.sleep(0.25)
    removed = reset_fullstack_wrangler_persist(repo_root=repo_root)
    return released, removed


def main() -> int:
    prepare_fullstack_e2e_stack()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
