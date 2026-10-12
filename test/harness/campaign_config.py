"""Per-campaign runner config files and CLI application."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Sequence

from harness.common import REPO_ROOT

CAMPAIGN_CONFIG_DIRS: dict[str, Path] = {
    "frontend": REPO_ROOT / "frontend" / "tool" / "campaigns",
    "ai-platform": REPO_ROOT / "ai-platform" / "campaigns",
    "abo": REPO_ROOT / "abo" / "campaigns",
    "e2e-fullstack": REPO_ROOT / "e2e" / "fullstack" / "campaigns",
    "vendor-contracts": REPO_ROOT / "packages" / "vendor-contracts" / "campaigns",
    "ops-launch": REPO_ROOT / "ops" / "launch" / "campaigns",
}


def governor_config_area(area: str) -> str | None:
    """Area id for nested campaign config (e.g. frontend ``all`` → unit/boundary)."""
    return area if area in CAMPAIGN_CONFIG_DIRS else None


_FRONTEND_BOUNDARY_PREFIX = "boundary"


def _config_candidates(area: str, subcampaign: str) -> list[str]:
    names = [subcampaign]
    if area == "frontend":
        if subcampaign == "all":
            return names
        if subcampaign.startswith(f"{_FRONTEND_BOUNDARY_PREFIX}-") or subcampaign == _FRONTEND_BOUNDARY_PREFIX:
            names.append(_FRONTEND_BOUNDARY_PREFIX)
        if subcampaign == "fullstack":
            names.append("fullstack")
    return names


def resolve_campaign_config_path(area: str, subcampaign: str) -> Path | None:
    root = CAMPAIGN_CONFIG_DIRS.get(area)
    if root is None:
        return None
    for name in _config_candidates(area, subcampaign):
        path = root / f"{name}.json"
        if path.is_file():
            return path
    return None


def load_campaign_config(area: str, subcampaign: str) -> dict[str, Any] | None:
    path = resolve_campaign_config_path(area, subcampaign)
    if path is None:
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def config_display_lines(config: dict[str, Any] | None) -> list[tuple[str, str]]:
    if not config:
        return []
    kind = config.get("kind")
    if kind == "flutter":
        coverage = config.get("coverage", True)
        return [
            ("Parallel tests", str(config.get("parallel_tests", 15))),
            ("Coverage", "on" if coverage else "off"),
        ]
    if kind == "vitest":
        fp = config.get("file_parallelism", False)
        shard = config.get("shard")
        return [
            ("File parallelism", "on" if fp else "off"),
            ("Test timeout", _format_timeout_ms(config.get("test_timeout_ms", 120_000))),
            ("Shard", str(shard) if shard else "off"),
        ]
    if kind == "node-test":
        concurrency = config.get("test_concurrency")
        shard = config.get("shard")
        timeout = config.get("test_timeout_ms")
        return [
            (
                "Test concurrency",
                str(concurrency) if concurrency is not None else "default",
            ),
            (
                "Test timeout",
                _format_timeout_ms(timeout) if timeout is not None else "default",
            ),
            ("Shard", str(shard) if shard else "off"),
        ]
    return []


def _format_timeout_ms(ms: int | float) -> str:
    seconds = int(ms) / 1000
    if seconds == int(seconds):
        return f"{int(seconds)}s"
    return f"{seconds}s"


def apply_flutter_args(cmd: list[str], config: dict[str, Any] | None) -> list[str]:
    if not config or config.get("kind") != "flutter":
        return cmd
    out = list(cmd)
    parallel = int(config.get("parallel_tests", 15))
    if "--concurrency" in out:
        idx = out.index("--concurrency")
        if idx + 1 < len(out):
            out[idx + 1] = str(parallel)
    else:
        out.extend(["--concurrency", str(parallel)])
    if config.get("coverage", True):
        if "--coverage" not in out:
            out.append("--coverage")
    else:
        out = [arg for arg in out if arg != "--coverage"]
    return out


def _ensure_vitest_verbose_reporter(cmd: list[str]) -> list[str]:
    if not any("vitest" in part for part in cmd):
        return cmd
    if any(arg == "--reporter" or str(arg).startswith("--reporter=") for arg in cmd):
        return cmd
    out = list(cmd)
    out.extend(["--reporter", "verbose"])
    return out


def apply_vitest_args(cmd: list[str], config: dict[str, Any] | None) -> list[str]:
    if not config or config.get("kind") != "vitest":
        return cmd
    out = list(cmd)
    _strip_vitest_config_flags(out)
    if config.get("file_parallelism", False):
        out.append("--file-parallelism")
    else:
        out.append("--no-file-parallelism")
    out = _ensure_vitest_verbose_reporter(out)
    timeout = int(config.get("test_timeout_ms", 120_000))
    out.extend(["--testTimeout", str(timeout)])
    shard = config.get("shard")
    if shard:
        out.extend(["--shard", str(shard)])
    return out


def apply_node_test_args(cmd: list[str], config: dict[str, Any] | None) -> list[str]:
    if not config or config.get("kind") != "node-test":
        return cmd
    out = list(cmd)
    _strip_node_test_config_flags(out)
    insert_at = 1 if out and out[0] == "node" else 0
    extras: list[str] = []
    concurrency = config.get("test_concurrency")
    if concurrency is not None:
        extras.append(f"--test-concurrency={int(concurrency)}")
    timeout = config.get("test_timeout_ms")
    if timeout is None:
        timeout = 180_000
    extras.append(f"--test-timeout={int(timeout)}")
    shard = config.get("shard")
    if shard:
        extras.append(f"--test-shard={shard}")
    for offset, flag in enumerate(extras):
        out.insert(insert_at + offset, flag)
    return out


def apply_campaign_args(cmd: Sequence[str], config: dict[str, Any] | None) -> list[str]:
    if not config:
        return _ensure_vitest_verbose_reporter(list(cmd))
    kind = config.get("kind")
    if kind == "flutter":
        return apply_flutter_args(list(cmd), config)
    if kind == "vitest":
        return apply_vitest_args(list(cmd), config)
    if kind == "node-test":
        return apply_node_test_args(list(cmd), config)
    return _ensure_vitest_verbose_reporter(list(cmd))


def _strip_vitest_config_flags(cmd: list[str]) -> None:
    drop_next = False
    filtered: list[str] = []
    for arg in cmd:
        if drop_next:
            drop_next = False
            continue
        if arg in ("--testTimeout", "--shard"):
            drop_next = True
            continue
        if arg in ("--file-parallelism", "--no-file-parallelism"):
            continue
        if arg in ("--reporter",):
            drop_next = True
            continue
        if str(arg).startswith("--reporter="):
            continue
        filtered.append(arg)
    cmd.clear()
    cmd.extend(filtered)


def _strip_node_test_config_flags(cmd: list[str]) -> None:
    cmd[:] = [
        arg
        for arg in cmd
        if not arg.startswith("--test-concurrency=")
        and not arg.startswith("--test-timeout=")
        and not arg.startswith("--test-shard=")
    ]


def nested_subcampaign_config(area: str, nested_step: str) -> dict[str, Any] | None:
    """Map sequence step names (e.g. frontend ``all`` → ``unit``) to config."""
    if area == "frontend" and nested_step in ("unit", "boundary", "fullstack"):
        return load_campaign_config(area, nested_step)
    return load_campaign_config(area, nested_step)
