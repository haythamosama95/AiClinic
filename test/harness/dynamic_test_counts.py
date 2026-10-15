"""Discover per-subcampaign test totals when the governor starts (no test execution)."""

from __future__ import annotations

import importlib.util
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Callable

from harness.common import REPO_ROOT
from harness.vitest_list_count import count_vitest_list, list_vitest_labels

_DEFAULT_WARM_WORKERS = max(2, min(8, (os.cpu_count() or 4)))

_NODE_CASE = re.compile(r"^\s*test\s*\(", re.MULTILINE)
_DART_CASE = re.compile(r"^\s*(?:test|testWidgets)\s*\(", re.MULTILINE)

_COUNT_CACHE: dict[tuple[str, str], int | None] = {}

DiscoverFn = Callable[[str], int | None]


def clear_test_count_cache() -> None:
    _COUNT_CACHE.clear()


def _sum_vitest_specs(
    root: Path,
    specs: list[list[str]],
    *,
    area: str,
    subcampaign: str,
) -> int | None:
    if not specs:
        return 0

    def _one(list_args: list[str]) -> int | None:
        return count_vitest_list(
            root, list_args, area=area, subcampaign=subcampaign
        )

    if len(specs) == 1:
        return _one(specs[0])

    workers = min(_DEFAULT_WARM_WORKERS, len(specs))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        parts = list(pool.map(_one, specs))
    if any(part is None for part in parts):
        return None
    return sum(parts)


def _sum_parallel_counts(parts: list[int | None]) -> int | None:
    if any(part is None for part in parts):
        return None
    return sum(parts)


def _count_node_sources(cwd: Path, relative_paths: list[str]) -> int | None:
    total = 0
    for rel in relative_paths:
        path = cwd / rel
        if not path.is_file():
            continue
        total += len(_NODE_CASE.findall(path.read_text(encoding="utf-8")))
    return total


def _load_backend_run_campaigns():
    module_path = REPO_ROOT / "backend" / "tests" / "run_campaigns.py"
    spec = importlib.util.spec_from_file_location("backend_run_campaigns", module_path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _backend_count(subcampaign: str) -> int | None:
    module = _load_backend_run_campaigns()
    if module is None:
        return None
    if subcampaign == "all":
        # Repeated setup steps share one summary name (Reset ai_token_issuance
        # runs before each AI-trust file). The total is distinct step names.
        return len({step.name for step in module._all_steps()})
    counts = module.subcampaign_test_counts()
    return counts.get(subcampaign)


def _frontend_count(subcampaign: str) -> int | None:
    frontend_root = REPO_ROOT / "frontend"
    tool_dir = frontend_root / "tool"
    import sys

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

    if subcampaign == "unit":
        return count_expected_tests(frontend_root, unit_test_files(frontend_root))
    if subcampaign in {"unit-1", "unit-2"}:
        return count_expected_tests(
            frontend_root, unit_test_shards(frontend_root)[int(subcampaign[-1]) - 1]
        )
    if subcampaign == "boundary":
        return count_expected_tests(
            frontend_root, boundary_test_files(frontend_root, None)
        )
    if subcampaign.startswith("boundary-") and subcampaign != "boundary":
        key = subcampaign.removeprefix("boundary-")
        if key in BOUNDARY_SUBSET_ROOTS:
            return count_expected_tests(
                frontend_root, boundary_test_files(frontend_root, key)
            )
    if subcampaign == "fullstack":
        return count_expected_tests(frontend_root, fullstack_test_files(frontend_root))
    if subcampaign == "all":
        with ThreadPoolExecutor(max_workers=2) as pool:
            unit_future = pool.submit(_frontend_count, "unit")
            boundary_future = pool.submit(_frontend_count, "boundary")
            unit = unit_future.result()
            boundary = boundary_future.result()
        return _sum_parallel_counts([unit, boundary])
    return None


def _ai_platform_root() -> Path:
    return REPO_ROOT / "ai-platform"


def _ai_platform_vitest_specs() -> dict[str, list[list[str]]]:
    root = _ai_platform_root()
    manifests = [
        "test/manifest-registry-gate.test.ts",
        "test/prompt-registry-gate.test.ts",
    ]
    eval_all_files = [
        str(p.relative_to(root)) for p in sorted((root / "test/eval").glob("*.test.ts"))
    ]
    return {
        "manifests": [manifests],
        "unit": [[]],
        "workers": [["--config", "vitest.workers.config.ts"]],
        # ``npm-test`` runs manifests, then default unit pool, then workers pool; manifest
        # cases are already included in the unit ``vitest list`` scope (no double-count).
        "npm-test": [[], ["--config", "vitest.workers.config.ts"]],
        "load": [
            ["--config", "vitest.workers.config.ts", "test/load/load-and-cost.test.ts"]
        ],
        "e2e": [["--config", "vitest.e2e.config.ts"]],
        "eval": [
            [
                "test/eval/golden.test.ts",
                "test/eval/conversation.test.ts",
                "test/eval/prohibitions.test.ts",
            ]
        ],
        "eval-all": [eval_all_files] if eval_all_files else [[]],
        "version-matrix-channels": [
            ["--config", "vitest.version-matrix.config.ts"]
        ],
        "version-matrix-do": [
            ["--config", "vitest.version-matrix-do.config.ts"]
        ],
        "version-matrix": [
            ["--config", "vitest.version-matrix.config.ts"],
            ["--config", "vitest.version-matrix-do.config.ts"],
        ],
    }


def _ai_platform_count(subcampaign: str) -> int | None:
    root = _ai_platform_root()
    specs_map = _ai_platform_vitest_specs()
    if subcampaign == "npm-test":
        unit = _sum_vitest_specs(
            root,
            specs_map["unit"],
            area="ai-platform",
            subcampaign="unit",
        )
        workers = _sum_vitest_specs(
            root,
            specs_map["workers"],
            area="ai-platform",
            subcampaign="workers",
        )
        return _sum_parallel_counts([unit, workers])
    specs = specs_map.get(subcampaign)
    if specs is None:
        return None
    return _sum_vitest_specs(
        root, specs, area="ai-platform", subcampaign=subcampaign
    )


def _abo_root() -> Path:
    return REPO_ROOT / "abo"


def _abo_count(subcampaign: str) -> int | None:
    root = _abo_root()
    if subcampaign == "system":
        return count_vitest_list(
            root,
            ["--config", "vitest.workers.config.ts", "test/system"],
            area="abo",
            subcampaign=subcampaign,
        )
    if subcampaign == "cross-worker-main":
        return count_vitest_list(
            root,
            ["--config", "vitest.cross-worker.config.ts"],
            area="abo",
            subcampaign=subcampaign,
        )
    if subcampaign == "platform-throw":
        return count_vitest_list(
            root,
            ["--config", "vitest.platform-throw.config.ts"],
            area="abo",
            subcampaign=subcampaign,
        )
    if subcampaign == "cross-worker":
        with ThreadPoolExecutor(max_workers=2) as pool:
            main = pool.submit(
                count_vitest_list,
                root,
                ["--config", "vitest.cross-worker.config.ts"],
                area="abo",
                subcampaign="cross-worker-main",
            )
            throw = pool.submit(
                count_vitest_list,
                root,
                ["--config", "vitest.platform-throw.config.ts"],
                area="abo",
                subcampaign="platform-throw",
            )
        return _sum_parallel_counts([main.result(), throw.result()])
    if subcampaign == "import-boundary":
        return _count_node_sources(root, ["test/import-boundary/boundary.test.mjs"])
    if subcampaign == "version-matrix":
        return count_vitest_list(
            root,
            ["--config", "vitest.version-matrix.config.ts"],
            area="abo",
            subcampaign=subcampaign,
        )
    return None


def _e2e_root() -> Path:
    return REPO_ROOT / "e2e" / "fullstack"


def _e2e_files(pattern: str) -> list[str]:
    test_dir = _e2e_root() / "test"
    return [
        str(p.relative_to(_e2e_root()))
        for p in sorted(test_dir.glob(pattern))
    ]


def _e2e_count(subcampaign: str) -> int | None:
    root = _e2e_root()
    if subcampaign == "p5-1":
        return _count_node_sources(root, ["test/p5-1.test.mjs"])
    if subcampaign == "p5-2":
        return _count_node_sources(root, ["test/p5-2.test.mjs"])
    if subcampaign == "p5-core":
        with ThreadPoolExecutor(max_workers=2) as pool:
            a = pool.submit(_e2e_count, "p5-1")
            b = pool.submit(_e2e_count, "p5-2")
        return _sum_parallel_counts([a.result(), b.result()])
    if subcampaign == "p5-2b":
        return _count_node_sources(root, ["test/p5-2b.test.mjs"])
    if subcampaign == "p7-3":
        return _count_node_sources(root, _e2e_files("p7-3*.test.mjs"))
    if subcampaign == "p7-2":
        return _count_node_sources(root, _e2e_files("p7-2*.test.mjs"))
    if subcampaign == "all-ci":
        with ThreadPoolExecutor(max_workers=2) as pool:
            a = pool.submit(_e2e_count, "p5-1")
            b = pool.submit(_e2e_count, "p5-2")
        return _sum_parallel_counts([a.result(), b.result()])
    if subcampaign == "all-manual":
        files = [
            file
            for file in _e2e_files("*.test.mjs")
            if Path(file).name not in {"p5-1.test.mjs", "p5-2.test.mjs"}
        ]
        return _count_node_sources(root, files)
    return None


def _vendor_count(subcampaign: str) -> int | None:
    root = REPO_ROOT / "packages" / "vendor-contracts"
    if subcampaign == "node":
        return count_vitest_list(
            root, ["--config", "vitest.config.ts"], area="vendor-contracts", subcampaign=subcampaign
        )
    if subcampaign == "workers":
        return count_vitest_list(
            root,
            ["--config", "vitest.workers.config.ts"],
            area="vendor-contracts",
            subcampaign=subcampaign,
        )
    if subcampaign == "all":
        # Node and workers run the same case names (workers drops bundle-scan).
        # The summary stores one row per name, so the total is the union.
        with ThreadPoolExecutor(max_workers=2) as pool:
            node = pool.submit(
                list_vitest_labels,
                root,
                ["--config", "vitest.config.ts"],
                area="vendor-contracts",
                subcampaign="node",
            )
            workers = pool.submit(
                list_vitest_labels,
                root,
                ["--config", "vitest.workers.config.ts"],
                area="vendor-contracts",
                subcampaign="workers",
            )
            node_labels = node.result()
            workers_labels = workers.result()
        if node_labels is None or workers_labels is None:
            return None
        return len(node_labels | workers_labels)
    return None


def _ops_count(subcampaign: str) -> int | None:
    if subcampaign != "launch-check":
        return None
    launch_root = REPO_ROOT / "ops" / "launch"
    return _count_node_sources(launch_root, ["launch-check.test.mjs"])


_AREA_HANDLERS: dict[str, DiscoverFn] = {
    "backend": _backend_count,
    "frontend": _frontend_count,
    "ai-platform": _ai_platform_count,
    "abo": _abo_count,
    "e2e-fullstack": _e2e_count,
    "vendor-contracts": _vendor_count,
    "ops-launch": _ops_count,
}


def list_vitest_labels_for_subcampaign(area: str, subcampaign: str) -> set[str] | None:
    """Union of ``vitest list`` labels for one subcampaign (for resume reconcile)."""
    if area == "ai-platform":
        root = _ai_platform_root()
        specs_map = _ai_platform_vitest_specs()
        if subcampaign == "npm-test":
            labels: set[str] = set()
            for spec_key in ("unit", "workers"):
                for list_args in specs_map[spec_key]:
                    part = list_vitest_labels(
                        root,
                        list_args,
                        area="ai-platform",
                        subcampaign=spec_key,
                    )
                    if part is None:
                        return None
                    labels |= part
            return labels
        specs = specs_map.get(subcampaign)
        if specs is None:
            return None
        labels = set()
        for list_args in specs:
            part = list_vitest_labels(
                root,
                list_args,
                area="ai-platform",
                subcampaign=subcampaign,
            )
            if part is None:
                return None
            labels |= part
        return labels
    if area == "abo":
        root = _abo_root()
        if subcampaign == "system":
            return list_vitest_labels(
                root,
                ["--config", "vitest.workers.config.ts", "test/system"],
                area="abo",
                subcampaign=subcampaign,
            )
        if subcampaign == "cross-worker-main":
            return list_vitest_labels(
                root,
                ["--config", "vitest.cross-worker.config.ts"],
                area="abo",
                subcampaign=subcampaign,
            )
        if subcampaign == "platform-throw":
            return list_vitest_labels(
                root,
                ["--config", "vitest.platform-throw.config.ts"],
                area="abo",
                subcampaign=subcampaign,
            )
        if subcampaign == "cross-worker":
            with ThreadPoolExecutor(max_workers=2) as pool:
                main = pool.submit(
                    list_vitest_labels,
                    root,
                    ["--config", "vitest.cross-worker.config.ts"],
                    area="abo",
                    subcampaign="cross-worker-main",
                )
                throw = pool.submit(
                    list_vitest_labels,
                    root,
                    ["--config", "vitest.platform-throw.config.ts"],
                    area="abo",
                    subcampaign="platform-throw",
                )
                main_labels = main.result()
                throw_labels = throw.result()
            if main_labels is None or throw_labels is None:
                return None
            return main_labels | throw_labels
        if subcampaign == "version-matrix":
            return list_vitest_labels(
                root,
                ["--config", "vitest.version-matrix.config.ts"],
                area="abo",
                subcampaign=subcampaign,
            )
        return None
    if area == "vendor-contracts":
        root = REPO_ROOT / "packages" / "vendor-contracts"
        if subcampaign == "node":
            return list_vitest_labels(
                root,
                ["--config", "vitest.config.ts"],
                area="vendor-contracts",
                subcampaign=subcampaign,
            )
        if subcampaign == "workers":
            return list_vitest_labels(
                root,
                ["--config", "vitest.workers.config.ts"],
                area="vendor-contracts",
                subcampaign=subcampaign,
            )
        if subcampaign == "all":
            node = list_vitest_labels(
                root,
                ["--config", "vitest.config.ts"],
                area="vendor-contracts",
                subcampaign="node",
            )
            workers = list_vitest_labels(
                root,
                ["--config", "vitest.workers.config.ts"],
                area="vendor-contracts",
                subcampaign="workers",
            )
            if node is None or workers is None:
                return None
            return node | workers
        return None
    return None


def discover_test_count(area: str, subcampaign: str) -> int | None:
    """Discover runnable test-case count for one subcampaign (cached per process)."""
    key = (area, subcampaign)
    if key in _COUNT_CACHE:
        return _COUNT_CACHE[key]
    handler = _AREA_HANDLERS.get(area)
    if handler is None:
        _COUNT_CACHE[key] = None
        return None
    try:
        value = handler(subcampaign)
    except Exception:
        value = None
    _COUNT_CACHE[key] = value
    return value


def warm_test_counts(
    keys: list[tuple[str, str]],
    *,
    workers: int | None = None,
) -> dict[tuple[str, str], int | None]:
    """Prefetch static per-subcampaign totals (no subprocess)."""
    from harness.campaign_counts import static_test_count

    unique = list(dict.fromkeys(keys))
    if not unique:
        return {}
    areas = list(dict.fromkeys(area for area, _ in unique))
    pool_workers = workers if workers is not None else _DEFAULT_WARM_WORKERS
    pool_workers = min(max(pool_workers, 1), len(areas)) if areas else 1
    if pool_workers > 1 and len(areas) > 1:
        from harness.campaign_counts import counts_for_area

        with ThreadPoolExecutor(max_workers=pool_workers) as pool:
            list(pool.map(counts_for_area, areas))
    return {key: static_test_count(key[0], key[1]) for key in unique}


def warm_test_counts_for_forest(
    forest_nodes: list[tuple[str, str]],
) -> dict[tuple[str, str], int | None]:
    return warm_test_counts(forest_nodes)
