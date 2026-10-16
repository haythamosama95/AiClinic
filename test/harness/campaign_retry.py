"""One filtered retry pass for non-timeout campaign test failures."""

from __future__ import annotations

import json
import re
import shutil
import tempfile
from pathlib import Path
from typing import Any

from harness.test_result_stats import dedupe_test_entries, stats_from_tests_list

_TIMEOUT_RE = re.compile(
    r"\b(?:timed?\s*out|timeout|exceeded\s+\d+\s*ms|stalled|deadline)\b", re.I
)


def _is_timeout(entry: dict[str, Any], log_dir: Path) -> bool:
    details = str(entry.get("error") or "")
    rel = entry.get("log_file")
    if isinstance(rel, str):
        path = log_dir / rel
        try:
            details += "\n" + path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            pass
    return bool(_TIMEOUT_RE.search(details))


def retry_candidates(log_dir: Path) -> list[dict[str, Any]]:
    """Return latest failed rows with logs that do not indicate a timeout."""
    try:
        payload = json.loads((log_dir / "summary.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    tests = payload.get("tests", [])
    if not isinstance(tests, list):
        return []
    return [
        entry
        for entry in dedupe_test_entries(tests).values()
        if entry.get("status") == "FAIL" and not _is_timeout(entry, log_dir)
    ]


def filtered_retry_command(
    cmd: list[str], kind: str, candidates: list[dict[str, Any]]
) -> list[str] | None:
    """Add the runner's name filter for the failed cases, if supported."""
    names = [entry.get("name") for entry in candidates]
    names = [name for name in names if isinstance(name, str) and name]
    if not names:
        return None
    pattern = "(?:" + "|".join(re.escape(name) for name in names) + ")"
    out = list(cmd)
    if kind == "vitest" and any("vitest" in arg for arg in out):
        out.extend(["--testNamePattern", pattern])
    elif kind == "node-test" and any(Path(arg).name == "node" for arg in out[:1]):
        out.append(f"--test-name-pattern={pattern}")
    elif kind == "flutter" and any(Path(arg).name == "flutter" for arg in out):
        out.append(f"--plain-name={pattern}")
    else:
        return None
    return out


def merge_retry_passes(original_dir: Path, retry_dir: Path) -> int | None:
    """Replace only original failures that passed on retry; return failures left."""
    original_path = original_dir / "summary.json"
    retry_path = retry_dir / "summary.json"
    try:
        original = json.loads(original_path.read_text(encoding="utf-8"))
        retry = json.loads(retry_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    originals = original.get("tests", [])
    retried = retry.get("tests", [])
    if not isinstance(originals, list) or not isinstance(retried, list):
        return None
    retry_by_key = dedupe_test_entries(retried)
    original_by_key = dedupe_test_entries(originals)
    for key, failed in list(original_by_key.items()):
        if failed.get("status") != "FAIL":
            continue
        passed = retry_by_key.get(key)
        if not passed or passed.get("status") != "PASS":
            continue
        old_log = failed.get("log_file")
        new_log = passed.get("log_file")
        if isinstance(old_log, str) and isinstance(new_log, str):
            try:
                old_path = original_dir / old_log
                new_path = retry_dir / new_log
                old_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(new_path, old_path)
            except OSError:
                continue
        replacement = dict(passed)
        replacement["log_file"] = old_log
        replacement["retry_passed"] = True
        for index, row in enumerate(originals):
            if not isinstance(row, dict):
                continue
            row_key = row.get("identity") or row.get("name")
            if row_key == key:
                originals[index] = replacement
                break
    stats = stats_from_tests_list(originals)
    original["tests"] = originals
    original["passed"] = stats.passed
    original["failed"] = stats.failed
    original_path.write_text(json.dumps(original, indent=2) + "\n", encoding="utf-8")
    return stats.failed


def temporary_retry_dir(parent: Path) -> Path:
    return Path(tempfile.mkdtemp(prefix=".retry-", dir=parent))
