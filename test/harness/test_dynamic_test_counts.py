"""Tests for dynamic test count discovery."""

from __future__ import annotations

from harness.dynamic_test_counts import clear_test_count_cache, discover_test_count


def test_vendor_all_count_is_union_of_pool_names() -> None:
    from unittest.mock import patch

    from harness import dynamic_test_counts as mod

    clear_test_count_cache()

    def fake_labels(cwd, list_args, **kwargs):
        if list_args == ["--config", "vitest.config.ts"]:
            return {"shared", "node-only"}
        if list_args == ["--config", "vitest.workers.config.ts"]:
            return {"shared"}
        return set()

    with patch.object(mod, "list_vitest_labels", fake_labels):
        clear_test_count_cache()
        assert mod._vendor_count("all") == 2


def test_vitest_list_count_is_unique_labels() -> None:
    from harness.vitest_list_count import count_labels_in_vitest_list_output

    stdout = "\n".join(
        [
            "test/a.test.ts > suite > same case",
            "test/a.test.ts > suite > same case",
            "test/a.test.ts > suite > other case",
            "WARN something > ignored",
        ]
    )
    assert count_labels_in_vitest_list_output(stdout) == 2


def test_backend_all_count_is_distinct_step_names() -> None:
    import importlib.util

    from harness.common import REPO_ROOT

    clear_test_count_cache()
    module_path = REPO_ROOT / "backend" / "tests" / "run_campaigns.py"
    spec = importlib.util.spec_from_file_location("backend_run_campaigns", module_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    steps = module._all_steps()
    distinct = len({step.name for step in steps})
    assert distinct < len(steps)
    assert discover_test_count("backend", "all") == distinct


def test_backend_auth_rbac_count_is_positive() -> None:
    clear_test_count_cache()
    count = discover_test_count("backend", "auth-rbac")
    assert count is not None and count > 0


def test_vitest_list_count_mocked() -> None:
    from unittest.mock import patch

    from harness import dynamic_test_counts as mod

    clear_test_count_cache()

    def fake_vitest(cwd, list_args, **kwargs):
        if list_args == []:
            return 10
        if list_args == ["--config", "vitest.workers.config.ts"]:
            return 7
        if list_args and list_args[0].endswith("manifest-registry-gate.test.ts"):
            return 4
        return 0

    with patch.object(mod, "count_vitest_list", fake_vitest):
        clear_test_count_cache()
        assert mod._ai_platform_count("manifests") == 4
        clear_test_count_cache()
        assert mod._ai_platform_count("npm-test") == 17


def test_test_count_ignores_vitest_list_env(monkeypatch) -> None:
    from harness.campaign_counts import static_test_count, test_count as campaign_test_count

    monkeypatch.setenv("AICLINIC_VITEST_LIST_COUNTS", "1")
    assert campaign_test_count("abo", "system") == static_test_count("abo", "system")


def test_abo_cross_worker_labels_union() -> None:
    from unittest.mock import patch

    from harness import dynamic_test_counts as mod

    clear_test_count_cache()

    def fake_labels(cwd, list_args, **kwargs):
        if list_args == ["--config", "vitest.cross-worker.config.ts"]:
            return {"main-a", "main-b"}
        if list_args == ["--config", "vitest.platform-throw.config.ts"]:
            return {"throw-only"}
        return set()

    with patch.object(mod, "list_vitest_labels", fake_labels):
        clear_test_count_cache()
        labels = mod.list_vitest_labels_for_subcampaign("abo", "cross-worker")
        assert labels == {"main-a", "main-b", "throw-only"}
