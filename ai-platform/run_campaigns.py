#!/usr/bin/env python3
"""AI Platform test campaign orchestrator."""

from __future__ import annotations

import json
import sys
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent
REPO_ROOT = PKG_ROOT.parent
sys.path.insert(0, str(REPO_ROOT / "test"))

from harness.campaign_config import apply_campaign_args, load_campaign_config  # noqa: E402
from harness.common import (  # noqa: E402
    new_run_id,
    resolve_campaign_log_dir,
    run_campaign_script,
    run_subprocess_sequence,
    run_subprocess_with_live_status,
)

AREA = "ai-platform"


def _log_dir(subcampaign: str) -> Path:
    return resolve_campaign_log_dir(AREA, subcampaign, new_run_id())


def _status_label(subcampaign: str) -> str:
    return f"[{AREA}/{subcampaign}]"


def _prepare(subcampaign: str, cmd: list[str]) -> tuple[list[str], dict | None]:
    config = load_campaign_config(AREA, subcampaign)
    return apply_campaign_args(cmd, config), config


def _run(subcampaign: str, cmd: list[str]) -> int:
    prepared, config = _prepare(subcampaign, cmd)
    log_dir = _log_dir(subcampaign)
    raw_report = log_dir / ".vitest-report-raw.json"
    prepared = _with_json_reporter(prepared, raw_report)
    result = run_subprocess_with_live_status(
        prepared,
        PKG_ROOT,
        log_dir,
        status_label=_status_label(subcampaign),
        campaign_config=config,
        config_area=AREA,
    )
    _write_normalized_report(raw_report, log_dir / "vitest-report.json")
    return result


def _run_steps(
    subcampaign: str,
    steps: list[tuple[str, list[str]]],
    *,
    continue_on_step_failure: bool = False,
) -> int:
    config = load_campaign_config(AREA, subcampaign)
    log_dir = _log_dir(subcampaign)
    prepared = [
        (name, _with_json_reporter(apply_campaign_args(list(cmd), config), log_dir / f".vitest-report-{name}.json"))
        for name, cmd in steps
    ]
    result = run_subprocess_sequence(
        prepared,
        PKG_ROOT,
        log_dir,
        status_label=_status_label(subcampaign),
        campaign_config=config,
        config_area=AREA,
        continue_on_step_failure=continue_on_step_failure,
    )
    _merge_step_reports(log_dir, [name for name, _ in steps])
    return result


def _with_json_reporter(cmd: list[str], report_path: Path) -> list[str]:
    """Keep Vitest's normal console reporter and capture machine-readable results."""
    return [
        *cmd,
        "--reporter=default",
        "--reporter=json",
        f"--outputFile.json={report_path}",
    ]


def _report_tests(payload: object) -> list[dict]:
    """Normalize Vitest 3 JSON reporter output into stable per-case diagnostics."""
    if not isinstance(payload, dict):
        return []
    normalized: list[dict] = []
    for file_result in payload.get("testResults", []):
        if not isinstance(file_result, dict):
            continue
        file_name = file_result.get("name") or file_result.get("file") or ""
        for case in file_result.get("assertionResults", []):
            if not isinstance(case, dict):
                continue
            status = case.get("status", "unknown")
            if status != "failed":
                continue
            titles = case.get("ancestorTitles", [])
            name = " > ".join([*(str(title) for title in titles), str(case.get("title", ""))]).strip(" >")
            messages = case.get("failureMessages") or case.get("failureMessage") or []
            if isinstance(messages, str):
                messages = [messages]
            error = "\n\n".join(str(message) for message in messages if message)
            stack = next((line for line in error.splitlines() if line.startswith("    at ") or line.startswith("at ")), None)
            entry = {
                "name": name or str(case.get("fullName") or file_name),
                "file": file_name,
                "status": status,
                "error": error,
            }
            if stack:
                entry["stack"] = error[error.find(stack):]
            for key in ("expected", "actual"):
                if key in case:
                    entry[key] = case[key]
            normalized.append(entry)
    return normalized


def _write_normalized_report(raw_path: Path, report_path: Path) -> None:
    tests: list[dict] = []
    if raw_path.is_file():
        try:
            tests = _report_tests(json.loads(raw_path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            pass
        raw_path.unlink(missing_ok=True)
    report_path.write_text(json.dumps({"tests": tests}, indent=2) + "\n", encoding="utf-8")


def _merge_step_reports(log_dir: Path, step_names: list[str]) -> None:
    tests: list[dict] = []
    for step in step_names:
        raw_path = log_dir / f".vitest-report-{step}.json"
        if raw_path.is_file():
            try:
                tests.extend(_report_tests(json.loads(raw_path.read_text(encoding="utf-8"))))
            except (OSError, json.JSONDecodeError):
                pass
            raw_path.unlink(missing_ok=True)
    (log_dir / "vitest-report.json").write_text(json.dumps({"tests": tests}, indent=2) + "\n", encoding="utf-8")


def _eval_files() -> list[str]:
    return sorted(str(p.relative_to(PKG_ROOT)) for p in (PKG_ROOT / "test/eval").glob("*.test.ts"))


def run_manifests(_: str) -> int:
    return _run(
        "manifests",
        [
            "npx",
            "vitest",
            "run",
            "test/manifest-registry-gate.test.ts",
            "test/prompt-registry-gate.test.ts",
        ],
    )


def run_unit(_: str) -> int:
    return _run("unit", ["npx", "vitest", "run"])


def run_unit_shard(subcampaign: str) -> int:
    shard = int(subcampaign[-1])
    return _run(subcampaign, ["npx", "vitest", "run", f"--shard={shard}/2"])


def run_workers(_: str) -> int:
    return _run(
        "workers",
        ["npx", "vitest", "run", "--config", "vitest.workers.config.ts"],
    )


def run_npm_test(_: str) -> int:
    return _run_steps(
        "npm-test",
        [
            (
                "verify-manifests",
                [
                    "npx",
                    "vitest",
                    "run",
                    "test/manifest-registry-gate.test.ts",
                    "test/prompt-registry-gate.test.ts",
                ],
            ),
            ("unit", ["npx", "vitest", "run"]),
            ("workers", ["npx", "vitest", "run", "--config", "vitest.workers.config.ts"]),
        ],
        continue_on_step_failure=True,
    )


def run_load(_: str) -> int:
    return _run(
        "load",
        [
            "npx",
            "vitest",
            "run",
            "--config",
            "vitest.workers.config.ts",
            "test/load/load-and-cost.test.ts",
        ],
    )


def run_e2e(_: str) -> int:
    return _run("e2e", ["npx", "vitest", "run", "--config", "vitest.e2e.config.ts"])


def run_eval(_: str) -> int:
    return _run(
        "eval",
        [
            "npx",
            "vitest",
            "run",
            "test/eval/golden.test.ts",
            "test/eval/conversation.test.ts",
            "test/eval/prohibitions.test.ts",
        ],
    )


def run_eval_all(_: str) -> int:
    files = _eval_files()
    if not files:
        print("error: no test/eval/*.test.ts files found", file=sys.stderr)
        return 1
    return _run("eval-all", ["npx", "vitest", "run", *files])


def run_version_matrix_channels(_: str) -> int:
    return _run(
        "version-matrix-channels",
        ["npx", "vitest", "run", "--config", "vitest.version-matrix.config.ts"],
    )


def run_version_matrix_do(_: str) -> int:
    return _run(
        "version-matrix-do",
        ["npx", "vitest", "run", "--config", "vitest.version-matrix-do.config.ts"],
    )


def run_version_matrix(_: str) -> int:
    return _run_steps(
        "version-matrix",
        [
            (
                "version-matrix-channels",
                ["npx", "vitest", "run", "--config", "vitest.version-matrix.config.ts"],
            ),
            (
                "version-matrix-do",
                ["npx", "vitest", "run", "--config", "vitest.version-matrix-do.config.ts"],
            ),
        ],
    )


SUBCAMPAIGNS = {
    "manifests": run_manifests,
    "unit": run_unit,
    "unit-1": run_unit_shard,
    "unit-2": run_unit_shard,
    "workers": run_workers,
    "npm-test": run_npm_test,
    "load": run_load,
    "e2e": run_e2e,
    "eval": run_eval,
    "eval-all": run_eval_all,
    "version-matrix": run_version_matrix,
    "version-matrix-channels": run_version_matrix_channels,
    "version-matrix-do": run_version_matrix_do,
}


def main() -> int:
    return run_campaign_script(AREA, SUBCAMPAIGNS)


if __name__ == "__main__":
    raise SystemExit(main())
