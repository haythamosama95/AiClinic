"""Build Vitest CLI commands that skip cases which already have a result."""

from __future__ import annotations

import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from harness.campaign_config import apply_campaign_args, load_campaign_config
from harness.vitest_labels import vitest_exclude_label_set, vitest_list_line_label

# Vitest can appear hung during collection with huge name patterns.
_MAX_LEAVES_PER_INVOCATION = 24
_MAX_PATTERN_CHARS = 8_000


def _is_vitest_run_cmd(cmd: list[str]) -> bool:
    joined = " ".join(cmd)
    return "vitest" in joined and " list" not in joined


def _vitest_list_args_from_run_cmd(cmd: list[str]) -> list[str]:
    """Argv tail for ``vitest list`` / ``vitest run`` (same file/config scope as run)."""
    args: list[str] = []
    skip_next = False
    for part in cmd:
        if skip_next:
            skip_next = False
            continue
        if part in ("npx", "vitest", "run", "list", "bunx"):
            continue
        if part == "--":
            continue
        if part in ("-t", "--testNamePattern", "--shard", "--reporter"):
            skip_next = True
            continue
        if str(part).startswith("--testNamePattern="):
            continue
        if str(part).startswith("--reporter="):
            continue
        args.append(part)
    return args


def _run_vitest_list(
    list_args: list[str],
    cwd: Path,
    config: dict | None,
) -> str | None:
    list_cmd = apply_campaign_args(["npx", "vitest", "list", *list_args], config)
    from subprocess import run as subprocess_run

    try:
        result = subprocess_run(
            list_cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=600,
            check=False,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def _chunk_leaves(leaves: list[str]) -> list[list[str]]:
    chunks: list[list[str]] = []
    current: list[str] = []
    current_len = 0
    for leaf in leaves:
        piece = re.escape(leaf)
        extra = len(piece) + (1 if current else 0)
        if current and (
            len(current) >= _MAX_LEAVES_PER_INVOCATION
            or current_len + extra > _MAX_PATTERN_CHARS
        ):
            chunks.append(current)
            current = []
            current_len = 0
        current.append(leaf)
        current_len += extra
    if current:
        chunks.append(current)
    return chunks


def _run_argv_for_scope(
    list_args: list[str],
    config: dict | None,
    file_path: str,
    leaves: list[str],
) -> list[str]:
    pattern = "|".join(re.escape(leaf) for leaf in leaves)
    base = apply_campaign_args(["npx", "vitest", "run", *list_args], config)
    out = list(base)
    if file_path and file_path not in out:
        out.append(file_path)
    out.extend(["-t", pattern])
    return out


@dataclass(frozen=True)
class VitestResumePlan:
    """One or more ``vitest run`` commands that cover only non-excluded cases."""

    commands: list[list[str]]

    @property
    def skip_entirely(self) -> bool:
        return not self.commands


def plan_vitest_resume_commands(
    cmd: list[str],
    cwd: Path,
    exclude: set[str],
    *,
    area: str | None = None,
    subcampaign: str | None = None,
    on_status: Callable[[str], None] | None = None,
) -> VitestResumePlan | None:
    """
    Return filtered vitest command(s), or ``None`` when resume filtering does not apply.

    ``VitestResumePlan.skip_entirely`` is true when every case is already excluded.
    """
    if not exclude or not _is_vitest_run_cmd(cmd):
        return None

    if on_status is not None:
        on_status("Discovering remaining tests…")

    exclude_match = vitest_exclude_label_set(exclude)

    list_args = _vitest_list_args_from_run_cmd(cmd)
    config = None
    if area and subcampaign:
        config = load_campaign_config(area, subcampaign)

    stdout = _run_vitest_list(list_args, cwd, config)
    if stdout is None:
        # Preserve the exclusion guarantee if Vitest discovery is unavailable.
        # The regex filter is less precise than list-based planning but keeps
        # any matching case out of execution.
        pattern = "(?!(?:.*(?:" + "|".join(
            re.escape(name) for name in sorted(exclude_match)
        ) + "))).*"
        fallback = list(cmd)
        fallback.extend(["-t", pattern])
        return VitestResumePlan(commands=[fallback])

    remaining: list[str] = []
    for line in stdout.splitlines():
        label = vitest_list_line_label(line)
        if label is None:
            continue
        if label in exclude_match:
            continue
        remaining.append(label)

    if not remaining:
        return VitestResumePlan(commands=[])

    by_file: dict[str, list[str]] = defaultdict(list)
    for label in remaining:
        parts = [part.strip() for part in label.split(" > ") if part.strip()]
        if not parts:
            continue
        file_path = parts[0]
        by_file[file_path].append(parts[-1])

    if not by_file:
        return VitestResumePlan(commands=[list(cmd)])

    commands: list[list[str]] = []
    for file_path in sorted(by_file):
        for leaf_chunk in _chunk_leaves(by_file[file_path]):
            commands.append(
                _run_argv_for_scope(list_args, config, file_path, leaf_chunk)
            )

    return VitestResumePlan(commands=commands)


def filter_vitest_run_command(
    cmd: list[str],
    cwd: Path,
    exclude: set[str],
    *,
    area: str | None = None,
    subcampaign: str | None = None,
) -> list[str] | None:
    """Return a single filtered ``vitest run`` argv, or ``None`` if all cases excluded."""
    plan = plan_vitest_resume_commands(
        cmd,
        cwd,
        exclude,
        area=area,
        subcampaign=subcampaign,
    )
    if plan is None:
        return list(cmd)
    if plan.skip_entirely:
        return None
    if len(plan.commands) == 1:
        return plan.commands[0]
    return plan.commands[0]
