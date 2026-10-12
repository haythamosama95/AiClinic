"""Tests for fullstack dev port cleanup."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

from harness.local_dev_ports import (
    _is_stale_fullstack_dev_process,
    pids_listening_on_tcp_port,
    release_stale_fullstack_dev_ports,
    reset_fullstack_wrangler_persist,
)


def test_pids_listening_on_tcp_port_parses_ss() -> None:
    ss_out = (
        "State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess\n"
        'LISTEN 0      4096   127.0.0.1:8787      0.0.0.0:*    users:(("workerd",pid=1504433,fd=12))\n'
    )
    with patch("harness.local_dev_ports.subprocess.run") as run:
        run.return_value.returncode = 0
        run.return_value.stdout = ss_out
        assert pids_listening_on_tcp_port(8787) == [1504433]


def test_is_stale_fullstack_dev_process_workerd() -> None:
    repo = Path("/home/dev/AiClinic")
    with patch("harness.local_dev_ports._proc_comm", return_value="workerd"):
        with patch("harness.local_dev_ports._proc_cmdline", return_value=""):
            assert _is_stale_fullstack_dev_process(99, repo)


def test_is_stale_fullstack_dev_process_rejects_unrelated() -> None:
    repo = Path("/home/dev/AiClinic")
    with patch("harness.local_dev_ports._proc_comm", return_value="postgres"):
        with patch(
            "harness.local_dev_ports._proc_cmdline",
            return_value="postgres -D /var/lib/postgresql",
        ):
            assert not _is_stale_fullstack_dev_process(99, repo)


def test_reset_fullstack_wrangler_persist_removes_entire_tree(tmp_path: Path) -> None:
    wrangler = tmp_path / "e2e" / "fullstack" / ".wrangler"
    (wrangler / "platform" / "v3").mkdir(parents=True)
    (wrangler / "state" / "v3").mkdir(parents=True)
    (wrangler / "tmp").mkdir(parents=True)

    removed = reset_fullstack_wrangler_persist(repo_root=tmp_path)

    assert removed == [wrangler]
    assert not wrangler.exists()


def test_release_stale_fullstack_dev_ports_terminates_matching_pids() -> None:
    repo = Path("/home/dev/AiClinic")
    with patch(
        "harness.local_dev_ports.pids_listening_on_tcp_port",
        side_effect=[[1504433], [], [], [], [], []],
    ):
        with patch(
            "harness.local_dev_ports._is_stale_fullstack_dev_process",
            return_value=True,
        ):
            with patch("harness.local_dev_ports._terminate_pid", return_value=True) as term:
                released = release_stale_fullstack_dev_ports(
                    ports=(8787,),
                    repo_root=repo,
                )
    assert released == [1504433]
    term.assert_called_once_with(1504433)
