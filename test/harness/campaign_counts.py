"""Test-case counts for campaign --list (static analysis; may lag refactors)."""

from __future__ import annotations

import importlib.util
import os
import re
import sys
from functools import lru_cache
from pathlib import Path

from harness.common import REPO_ROOT

_VITEST_CASE = re.compile(r"^\s*(?:it|test)\s*\(", re.MULTILINE)
_DART_CASE = re.compile(r"^\s*(?:test|testWidgets)\s*\(", re.MULTILINE)
_NODE_CASE = re.compile(r"^\s*test\s*\(", re.MULTILINE)

# ai-platform vitest.config.ts excludes (Node pool only).
_AI_PLATFORM_UNIT_EXCLUDED_NAMES = {
    "control.test.ts",
    "identity.test.ts",
    "entitlement.test.ts",
    "rate-limit.test.ts",
    "quota-do.test.ts",
    "admission-credit.test.ts",
    "capability.test.ts",
    "journal.test.ts",
    "support-lookup.test.ts",
    "support-purge.test.ts",
    "pipeline.test.ts",
    "retention.test.ts",
    "rollup-reconciliation.test.ts",
    "journal-dashboards.test.ts",
    "soft-threshold-routing.test.ts",
    "conversational-journaling.test.ts",
    "capability-deprecation.test.ts",
    "cohort-activate-promote.test.ts",
    "routing-policy-canary.test.ts",
    "routing-policy-document-wiring.test.ts",
    "routing-policy-rollback-generation.test.ts",
    "token-contract-control.test.ts",
    "discovery-http.test.ts",
    "config-readers.test.ts",
    "worker-request-orchestrator.test.ts",
    "entitle-grant.test.ts",
    "plan-catalogue.test.ts",
    "quota-inspect.test.ts",
    "period-close.test.ts",
    "price-list-activation.test.ts",
    "vendor-entrypoint.test.ts",
}

_AI_PLATFORM_WORKERS_INCLUDES = [
    "test/vendor-entrypoint.test.ts",
    "test/identity.test.ts",
    "test/entitlement.test.ts",
    "test/rate-limit.test.ts",
    "test/quota-do.test.ts",
    "test/admission-credit.test.ts",
    "test/capability.test.ts",
    "test/journal.test.ts",
    "test/support-lookup.test.ts",
    "test/support-purge.test.ts",
    "test/retention.test.ts",
    "test/rollup-reconciliation.test.ts",
    "test/journal-dashboards.test.ts",
    "test/soft-threshold-routing.test.ts",
    "test/conversational-journaling.test.ts",
    "test/pipeline.test.ts",
    "test/capability-deprecation.test.ts",
    "test/cohort-activate-promote.test.ts",
    "test/routing-policy-canary.test.ts",
    "test/routing-policy-document-wiring.test.ts",
    "test/routing-policy-rollback-generation.test.ts",
    "test/token-contract-control.test.ts",
    "test/discovery-http.test.ts",
    "test/config-readers.test.ts",
    "test/load/load-and-cost.test.ts",
    "test/worker-request-orchestrator.test.ts",
    "test/plan-catalogue.test.ts",
    "test/quota-inspect.test.ts",
    "test/usage-summary.test.ts",
]

_ABO_CROSS_WORKER_FILES = [
    "test/system/checkout.cross-worker.test.ts",
    "test/system/coverage-view.cross-worker.test.ts",
    "test/system/grant.cross-worker.test.ts",
    "test/system/hp-actions.cross-worker.test.ts",
    "test/system/ops.cross-worker.test.ts",
    "test/system/reconciliation.cross-worker.test.ts",
    "test/system/sweeps.cross-worker.test.ts",
    "test/system/console-relays.cross-worker.test.ts",
    "test/system/configuration-relays.cross-worker.test.ts",
    "test/system/digest-watch-rebuild.cross-worker.test.ts",
]


def _count_vitest(paths: list[Path]) -> int:
    total = 0
    for path in paths:
        if not path.is_file():
            continue
        total += len(_VITEST_CASE.findall(path.read_text(encoding="utf-8")))
    return total


def _count_dart(paths: list[Path]) -> int:
    total = 0
    for path in paths:
        if not path.is_file():
            continue
        total += len(_DART_CASE.findall(path.read_text(encoding="utf-8")))
    return total


def _count_node(paths: list[Path]) -> int:
    total = 0
    for path in paths:
        if not path.is_file():
            continue
        total += len(_NODE_CASE.findall(path.read_text(encoding="utf-8")))
    return total


def _ai_platform_root() -> Path:
    return REPO_ROOT / "ai-platform"


def _ai_platform_unit_files() -> list[Path]:
    root = _ai_platform_root()
    test_root = root / "test"
    paths: list[Path] = []
    for path in test_root.rglob("*.test.ts"):
        rel = path.relative_to(root).as_posix()
        if rel.startswith("test/e2e/"):
            continue
        if rel.startswith("test/eval/"):
            continue
        if rel.startswith("test/system/"):
            continue
        if rel.startswith("test/version-matrix/"):
            continue
        if rel == "test/load/load-and-cost.test.ts":
            continue
        if path.name in _AI_PLATFORM_UNIT_EXCLUDED_NAMES:
            continue
        paths.append(path)
    return sorted(paths)


def _ai_platform_workers_files() -> list[Path]:
    root = _ai_platform_root()
    paths: list[Path] = []
    for rel in _AI_PLATFORM_WORKERS_INCLUDES:
        paths.append(root / rel)
    paths.extend(sorted((root / "test/system").glob("*.system.test.ts")))
    return paths


def _backend_counts() -> dict[str, int]:
    module_path = REPO_ROOT / "backend" / "tests" / "run_campaigns.py"
    spec = importlib.util.spec_from_file_location("backend_run_campaigns", module_path)
    if spec is None or spec.loader is None:
        return {}
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.subcampaign_test_counts()


def _frontend_counts() -> dict[str, int]:
    frontend_root = REPO_ROOT / "frontend"
    tool_dir = frontend_root / "tool"
    if str(tool_dir) not in sys.path:
        sys.path.insert(0, str(tool_dir))
    from discover_tests import (  # noqa: PLC0415
        BOUNDARY_SUBSET_ROOTS,
        boundary_test_files,
        count_expected_tests,
        fullstack_test_files,
        unit_test_files,
        unit_test_shards,
    )

    counts: dict[str, int] = {}
    unit_files = unit_test_files(frontend_root)
    counts["unit"] = count_expected_tests(frontend_root, unit_files)
    for shard_number, shard_files in enumerate(
        unit_test_shards(frontend_root, shard_count=4), 1
    ):
        counts[f"unit-{shard_number}"] = count_expected_tests(
            frontend_root, shard_files
        )
    counts["boundary"] = count_expected_tests(
        frontend_root, boundary_test_files(frontend_root, None)
    )
    for sub_key in BOUNDARY_SUBSET_ROOTS:
        counts[f"boundary-{sub_key}"] = count_expected_tests(
            frontend_root, boundary_test_files(frontend_root, sub_key)
        )
    counts["fullstack"] = count_expected_tests(
        frontend_root, fullstack_test_files(frontend_root)
    )
    counts["all"] = counts["unit"] + counts["boundary"]
    return counts


def _ai_platform_counts() -> dict[str, int]:
    root = _ai_platform_root()
    manifests = [
        root / "test/manifest-registry-gate.test.ts",
        root / "test/prompt-registry-gate.test.ts",
    ]
    unit_files = _ai_platform_unit_files()
    worker_files = _ai_platform_workers_files()
    e2e_files = sorted((root / "test/e2e").glob("*.test.ts"))
    eval_ci = [
        root / "test/eval/golden.test.ts",
        root / "test/eval/conversation.test.ts",
        root / "test/eval/prohibitions.test.ts",
    ]
    eval_all = sorted((root / "test/eval").glob("*.test.ts"))
    vm_files = sorted((root / "test/version-matrix").glob("*.test.ts"))
    load_file = [root / "test/load/load-and-cost.test.ts"]

    m = _count_vitest(manifests)
    u = _count_vitest(unit_files)
    w = _count_vitest(worker_files)
    return {
        "manifests": m,
        "unit": u,
        "unit-1": (u + 1) // 2,
        "unit-2": u // 2,
        "workers": w,
        # Same scope as ``run_npm_test`` (unit pool then workers); manifest gates live in unit.
        "npm-test": u + w,
        "load": _count_vitest(load_file),
        "e2e": _count_vitest(e2e_files),
        "eval": _count_vitest(eval_ci),
        "eval-all": _count_vitest(eval_all),
        "version-matrix-channels": _count_vitest(
            [root / "test/version-matrix/channels.system.test.ts"]
        ),
        "version-matrix-do": _count_vitest(
            [root / "test/version-matrix/worker-do.system.test.ts"]
        ),
        "version-matrix": _count_vitest(vm_files),
    }


def _abo_counts() -> dict[str, int]:
    root = REPO_ROOT / "abo"
    system_files = sorted((root / "test/system").glob("*.system.test.ts"))
    cross_files = [root / rel for rel in _ABO_CROSS_WORKER_FILES]
    throw_file = [root / "test/system/checkout-throw.cross-worker.test.ts"]
    import_files = [root / "test/import-boundary/boundary.test.mjs"]
    vm_files = sorted((root / "test/version-matrix").glob("**/*.test.ts"))
    cross_main = _count_vitest(cross_files)
    throw = _count_vitest(throw_file)
    return {
        "system": _count_vitest(system_files),
        "cross-worker-main": cross_main,
        "platform-throw": throw,
        "cross-worker": cross_main + throw,
        "import-boundary": _count_node(import_files),
        "version-matrix": _count_vitest(vm_files),
    }


def _e2e_counts() -> dict[str, int]:
    root = REPO_ROOT / "e2e" / "fullstack" / "test"

    def files_for(glob: str) -> list[Path]:
        return sorted(root.glob(glob))

    p51 = files_for("p5-1.test.mjs")
    p52 = files_for("p5-2.test.mjs")
    p52b = files_for("p5-2b.test.mjs")
    p73 = files_for("p7-3*.test.mjs")
    p72 = files_for("p7-2*.test.mjs")
    all_manual = files_for("*.test.mjs")
    return {
        "p5-1": _count_node(p51),
        "p5-2": _count_node(p52),
        "p5-core": _count_node(p51) + _count_node(p52),
        "p5-2b": _count_node(p52b),
        "p7-3": _count_node(p73),
        "p7-2": _count_node(p72),
        "all-ci": _count_node(p51) + _count_node(p52),
        "all-manual": _count_node(
            [
                path
                for path in all_manual
                if path.name not in {"p5-1.test.mjs", "p5-2.test.mjs"}
                and not path.name.startswith("p7-3-")
            ]
        ),
    }


def _vendor_contracts_counts() -> dict[str, int]:
    root = REPO_ROOT / "packages" / "vendor-contracts"
    files = sorted((root / "test").glob("*.test.ts"))
    # workers config excludes bundle-scan; every other name is shared.
    # ``all`` runs both pools, and the summary keeps one row per case name.
    workers_files = [path for path in files if path.name != "bundle-scan.test.ts"]
    node = _count_vitest(files)
    workers = _count_vitest(workers_files)
    return {"node": node, "workers": workers, "all": node}


def _ops_counts() -> dict[str, int]:
    path = REPO_ROOT / "ops" / "launch" / "launch-check.test.mjs"
    return {"launch-check": _count_node([path])}


_AREA_COUNT_LOADERS: dict[str, object] = {
    "frontend": _frontend_counts,
    "backend": _backend_counts,
    "ai-platform": _ai_platform_counts,
    "abo": _abo_counts,
    "e2e-fullstack": _e2e_counts,
    "vendor-contracts": _vendor_contracts_counts,
    "ops-launch": _ops_counts,
}


@lru_cache(maxsize=None)
def counts_for_area(area: str) -> dict[str, int]:
    """Counts for one area only (does not scan other areas)."""
    loader = _AREA_COUNT_LOADERS.get(area)
    if loader is None:
        return {}
    return loader()


def _vitest_list_counts_enabled() -> bool:
    """Opt-in: run ``vitest list`` per subcampaign (slow; accurate)."""
    flag = os.environ.get("AICLINIC_VITEST_LIST_COUNTS", "").strip().lower()
    return flag in ("1", "true", "yes")


def static_test_count(area: str, subcampaign: str) -> int | None:
    """Fast estimate from source analysis (default for governor UI and ``--list``)."""
    return counts_for_area(area).get(subcampaign)


def test_count(area: str, subcampaign: str) -> int | None:
    """Fast static estimate (never spawns ``vitest list``)."""
    count = static_test_count(area, subcampaign)
    if count is None:
        return None
    from harness.campaign_exclusions import excluded_test_cases

    return max(0, count - len(excluded_test_cases(area, subcampaign)))


def catalog_list_test_count(area: str, subcampaign: str) -> int | None:
    """``--list`` table: optional accurate ``vitest list`` when env is set."""
    from harness.campaign_exclusions import excluded_test_cases

    if _vitest_list_counts_enabled():
        from harness.dynamic_test_counts import discover_test_count

        count = discover_test_count(area, subcampaign)
    else:
        count = static_test_count(area, subcampaign)
    if count is None:
        return None
    return max(0, count - len(excluded_test_cases(area, subcampaign)))


def format_test_count(count: int | None) -> str:
    if count is None:
        return "—"
    return str(count)


# Default subcampaign whose test count is shown in the area title (not a sum of table rows).
AREA_ROLLUP_SUBCAMPAIGN: dict[str, str] = {
    "frontend": "all",
    "backend": "all",
    "ai-platform": "npm-test",
    "abo": "cross-worker",
    "e2e-fullstack": "all-ci",
    "vendor-contracts": "all",
    "ops-launch": "launch-check",
}


def area_rollup_subcampaign(area: str) -> str | None:
    return AREA_ROLLUP_SUBCAMPAIGN.get(area)


def area_rollup_test_count(area: str, subcampaign_ids: list[str]) -> int | None:
    """Tests in the default subcampaign for this area (title line), not a sum of all rows."""
    rollup = area_rollup_subcampaign(area)
    if rollup and rollup in subcampaign_ids:
        return test_count(area, rollup)
    return None


def area_root_tests_total(area: str, subcampaign_ids: list[str]) -> int:
    """Sum of Tests for top-level subcampaign rows in the tree (no indented children)."""
    from harness.campaign_tree import root_subcampaign_ids

    total = 0
    for sub_id in root_subcampaign_ids(area, subcampaign_ids):
        value = test_count(area, sub_id)
        if value is not None:
            total += value
    return total


def area_test_total(area: str, subcampaign_ids: list[str]) -> int:
    """Alias for area title line: root-level subcampaign test sum."""
    return area_root_tests_total(area, subcampaign_ids)
