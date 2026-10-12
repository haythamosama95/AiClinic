"""Tests for campaign runner config loading and CLI application."""

from harness.campaign_config import (
    apply_flutter_args,
    apply_node_test_args,
    apply_vitest_args,
    config_display_lines,
    load_campaign_config,
)


def test_load_frontend_unit_config() -> None:
    config = load_campaign_config("frontend", "unit")
    assert config is not None
    assert config["kind"] == "flutter"
    assert config["parallel_tests"] == 15
    assert config["coverage"] is True


def test_boundary_subset_falls_back_to_boundary() -> None:
    config = load_campaign_config("frontend", "boundary-auth")
    assert config is not None
    assert config["parallel_tests"] == 1


def test_apply_flutter_coverage_and_parallelism() -> None:
    cmd = apply_flutter_args(
        ["flutter", "test", "foo_test.dart", "--machine"],
        {"kind": "flutter", "parallel_tests": 4, "coverage": True},
    )
    assert "--concurrency" in cmd
    assert cmd[cmd.index("--concurrency") + 1] == "4"
    assert "--coverage" in cmd


def test_apply_vitest_no_parallel_and_timeout() -> None:
    cmd = apply_vitest_args(
        ["npx", "vitest", "run"],
        {"kind": "vitest", "file_parallelism": False, "test_timeout_ms": 120000, "shard": None},
    )
    assert "--no-file-parallelism" in cmd
    assert "--reporter" in cmd
    assert cmd[cmd.index("--reporter") + 1] == "verbose"
    assert "--testTimeout" in cmd
    assert cmd[cmd.index("--testTimeout") + 1] == "120000"


def test_config_display_lines_vitest() -> None:
    lines = config_display_lines(
        {
            "kind": "vitest",
            "file_parallelism": False,
            "test_timeout_ms": 120000,
            "shard": None,
        }
    )
    assert ("File parallelism", "off") in lines
    assert ("Shard", "off") in lines


def test_apply_node_test_shard() -> None:
    cmd = apply_node_test_args(
        ["node", "--import", "tsx", "--test", "a.mjs"],
        {"kind": "node-test", "test_concurrency": 2, "test_timeout_ms": 60000, "shard": "1/2"},
    )
    assert "--test-concurrency=2" in cmd
    assert "--test-timeout=60000" in cmd
    assert "--test-shard=1/2" in cmd


def test_apply_node_test_default_timeout_when_unset() -> None:
    cmd = apply_node_test_args(
        ["node", "--test", "a.mjs"],
        {"kind": "node-test"},
    )
    assert "--test-timeout=180000" in cmd
