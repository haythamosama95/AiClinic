"""Run picked campaigns with queue panel + standard live progress."""

from __future__ import annotations

import sys
import threading
from collections.abc import Callable, Sequence

from pathlib import Path

from harness.batch_queue_display import (
    BatchQueueState,
    batch_queue_from_picked,
    campaign_progress_finished,
    resume_campaign_is_complete,
    set_campaign_finished_count,
    set_campaign_resume_baseline,
)
from harness.campaign_selection import minimal_run_picks
from harness.campaign_config import governor_config_area, load_campaign_config
from harness.common import ensure_campaign_sigint_handler, governor_run_root, new_run_id
from harness.campaign_resume import (
    prior_results_from_summary,
    summary_stats,
    summary_test_counts,
    sync_queue_campaign_progress,
)
from harness.test_result_stats import reconcile_total
from harness.governor_console_log import attach_governor_console_log, governor_console_log_line
from harness.governor_run_manifest import (
    manifest_path,
    load_run_manifest,
    sync_manifest_from_disk,
    update_manifest_campaign,
    write_run_manifest,
)
from harness.common import governor_campaign_log_dir
from harness.live_progress import CampaignProgressDisplay
from harness.curses_campaign_ui import build_status_forest


def _prefetch_queue_totals_async(
    queue: BatchQueueState,
    count_keys: list[tuple[str, str]],
    display: CampaignProgressDisplay,
) -> None:
    """Fill queue totals after the live UI is up (static counts only; no subprocess)."""

    def work() -> None:
        from harness.campaign_counts import static_test_count

        for area, sub_id in count_keys:
            queue.test_total_by_key[(area, sub_id)] = static_test_count(area, sub_id)
        display.tick()

    threading.Thread(target=work, name="queue-test-totals", daemon=True).start()


def run_batch_with_dashboard(
    picked: Sequence[tuple[str, str]],
    area_subcampaigns: dict[str, list[str]],
    run_one: Callable[
        [str, str, BatchQueueState, CampaignProgressDisplay, bool, Path],
        int,
    ],
    *,
    run_root: Path | None = None,
    resume: bool = False,
) -> int:
    """Run each pair; one live UI updates in place for the whole batch."""
    if not picked:
        return 0

    ensure_campaign_sigint_handler()

    picked = minimal_run_picks(list(picked))
    if not picked:
        return 0

    if run_root is None:
        run_root = governor_run_root(new_run_id())
    run_root = run_root.resolve()
    run_root.mkdir(parents=True, exist_ok=True)

    previous_continued: list[str] | None = None
    if resume and manifest_path(run_root).is_file():
        previous_continued = load_run_manifest(run_root).get("continued_at", [])

    plan_path = write_run_manifest(
        run_root,
        picked,
        resumed_from=run_root if resume else None,
        previous_continued_at=previous_continued,
    )

    last_index = len(picked) - 1
    exit_code = 0
    interrupted = False
    with attach_governor_console_log(
        run_root,
        meta={
            "resume": resume,
            "picked": [f"{a}/{s}" for a, s in picked],
            "manifest": str(plan_path),
        },
    ):
        forest = build_status_forest(list(picked), area_subcampaigns)
        count_keys: list[tuple[str, str]] = []
        for root in forest:
            for node in root.flattened():
                if node.runnable:
                    count_keys.append((node.area, node.sub_id))
        queue = batch_queue_from_picked(
            picked,
            area_subcampaigns,
            resume_display=resume,
        )

        if resume:
            from harness.campaign_counts import static_test_count

            for area, sub_id in picked:
                key = (area, sub_id)
                log_dir = governor_campaign_log_dir(run_root, area, sub_id)
                passed, failed, _completed = summary_test_counts(log_dir)
                stats = summary_stats(log_dir)
                total = queue.test_total_by_key.get(key)
                if total is None:
                    total = static_test_count(area, sub_id)
                queue.test_total_by_key[key] = reconcile_total(total, stats)
                set_campaign_resume_baseline(queue, area, sub_id, passed, failed)
                if resume_campaign_is_complete(queue, area, sub_id):
                    queue.status_by_key[key] = "finished"
                    sync_queue_campaign_progress(
                        queue, area, sub_id, log_dir, exit_code=0
                    )
                    continue

        first_to_run: tuple[str, str] | None = None
        for area, sub_id in picked:
            if not resume or not resume_campaign_is_complete(queue, area, sub_id):
                first_to_run = (area, sub_id)
                break
        if first_to_run is None:
            first_to_run = picked[0]

        first_area, first_sub = first_to_run
        first_config = load_campaign_config(first_area, first_sub)
        display = CampaignProgressDisplay(
            f"[{first_area}/{first_sub}]",
            batch_queue=queue,
            campaign_config=first_config,
            config_area=governor_config_area(first_area),
            run_log_root=run_root,
            run_manifest_path=plan_path,
        )
        from harness.common import campaign_interactive_ui_enabled

        display.begin(
            clear_screen=campaign_interactive_ui_enabled() and sys.stderr.isatty()
        )
        _prefetch_queue_totals_async(queue, count_keys, display)

        try:
            if resume:
                first_log = governor_campaign_log_dir(run_root, first_area, first_sub)
                prior_passed, prior_failed, prior_failures = prior_results_from_summary(
                    first_log
                )
                display.seed_prior_results(
                    prior_passed,
                    prior_failed,
                    failure_names=prior_failures,
                )
                display.bind_campaign_log_dir(first_log)
                display.pull_stats_from_summary()

            try:
                exit_code = _run_dashboard_campaigns(
                    picked,
                    resume,
                    run_root,
                    queue,
                    display,
                    run_one,
                    last_index=last_index,
                )
            except SystemExit as exc:
                if exc.code != 130:
                    raise
                interrupted = True
                exit_code = 130
            except KeyboardInterrupt:
                interrupted = True
                exit_code = 130
        finally:
            display.finish(final=True, interrupted=interrupted)

    sync_manifest_from_disk(run_root)

    if interrupted or exit_code == 130:
        try:
            from harness.local_dev_ports import release_stale_fullstack_dev_ports

            release_stale_fullstack_dev_ports()
        except Exception:
            pass
        msg = "\nInterrupted.\n"
        sys.stderr.write(msg)
        governor_console_log_line(msg)
    elif exit_code == 0:
        msg = "\nAll campaigns finished.\n"
        sys.stderr.write(msg)
        governor_console_log_line(msg)
    else:
        msg = "\nFinished with failures.\n"
        sys.stderr.write(msg)
        governor_console_log_line(msg)
    sys.stderr.flush()
    return exit_code


def _run_dashboard_campaigns(
    picked: Sequence[tuple[str, str]],
    resume: bool,
    run_root: Path,
    queue: BatchQueueState,
    display: CampaignProgressDisplay,
    run_one: Callable[
        [str, str, BatchQueueState, CampaignProgressDisplay, bool, Path],
        int,
    ],
    *,
    last_index: int,
) -> int:
    exit_code = 0
    for index, (area, sub_id) in enumerate(picked):
        key = (area, sub_id)
        if resume and resume_campaign_is_complete(queue, area, sub_id):
            continue

        queue.status_by_key[key] = "running"
        log_dir = governor_campaign_log_dir(run_root, area, sub_id)
        display.bind_campaign_log_dir(log_dir)
        if resume:
            passed, failed, _completed = summary_test_counts(log_dir)
            set_campaign_finished_count(
                queue,
                area,
                sub_id,
                campaign_progress_finished(
                    queue, area, sub_id, passed=passed, failed=failed
                ),
            )
        else:
            set_campaign_finished_count(queue, area, sub_id, 0)
        update_manifest_campaign(run_root, area, sub_id, status="running", exit_code=None)
        display.tick()
        governor_console_log_line(
            f"CAMPAIGN START {area}/{sub_id} log_dir={log_dir.relative_to(run_root).as_posix()}"
        )
        try:
            code = run_one(area, sub_id, queue, display, index == last_index, run_root)
        except SystemExit as exc:
            if exc.code != 130:
                raise
            sync_queue_campaign_progress(
                queue, area, sub_id, log_dir, exit_code=130
            )
            update_manifest_campaign(
                run_root, area, sub_id, status="failed", exit_code=130
            )
            display.pull_stats_from_summary()
            raise
        sync_queue_campaign_progress(
            queue, area, sub_id, log_dir, exit_code=code
        )
        display.pull_stats_from_summary()
        status = "finished" if code == 0 else "failed"
        queue.status_by_key[key] = status
        update_manifest_campaign(run_root, area, sub_id, status=status, exit_code=code)
        summary_path = log_dir / "summary.json"
        try:
            import json

            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            passed = int(summary.get("passed", 0))
            failed = int(summary.get("failed", 0))
            elapsed = summary.get("elapsed_seconds", "unknown")
        except (OSError, ValueError, TypeError):
            passed, failed, elapsed = 0, 0, "unknown"
        governor_console_log_line(
            f"CAMPAIGN {status.upper()} {area}/{sub_id} exit_code={code} "
            f"passed={passed} failed={failed} elapsed_seconds={elapsed} "
            f"summary={summary_path.relative_to(run_root).as_posix()} "
            f"output={(log_dir / 'output.log').relative_to(run_root).as_posix()}"
        )
        display.tick()
        if code != 0:
            exit_code = code

    return exit_code
