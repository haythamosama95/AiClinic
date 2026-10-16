"""Single source of truth for live governor UI: ``summary.json`` on disk."""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from harness.test_result_stats import CampaignTestStats, reconcile_total

if TYPE_CHECKING:
    from harness.batch_queue_display import BatchQueueState
    from harness.live_progress import CampaignProgressDisplay


def governor_campaign_stats_log_dir(
    run_log_root: Path | None,
    area: str,
    subcampaign: str,
    fallback_log_dir: Path | None = None,
) -> Path | None:
    """Per-campaign log dir under a governor run (where ``summary.json`` lives)."""
    if run_log_root is not None:
        from harness.common import governor_campaign_log_dir

        return governor_campaign_log_dir(run_log_root, area, subcampaign)
    if fallback_log_dir is not None:
        return fallback_log_dir.resolve()
    return None


def load_campaign_stats(log_dir: Path) -> CampaignTestStats:
    from harness.campaign_resume import summary_stats

    return summary_stats(log_dir)


def apply_campaign_stats(
    stats: CampaignTestStats,
    area: str,
    subcampaign: str,
    *,
    batch_queue: BatchQueueState | None = None,
    total: int | None = None,
    adjust_total: bool = True,
) -> int:
    """Write deduped pass/fail into queue state; return ``finished`` (attempted) count."""
    from harness.batch_queue_display import (
        campaign_progress_finished,
        set_campaign_finished_count,
        set_campaign_pass_fail_counts,
    )

    key = (area, subcampaign)
    if (
        adjust_total
        and batch_queue is not None
        and key in batch_queue.test_total_by_key
    ):
        discovered = batch_queue.test_total_by_key[key]
        total = reconcile_total(discovered, stats)
        batch_queue.test_total_by_key[key] = total
    elif total is None and batch_queue is not None:
        total = batch_queue.test_total_by_key.get(key)

    set_campaign_pass_fail_counts(
        batch_queue, area, subcampaign, stats.passed, stats.failed
    )
    if batch_queue is None:
        # Standalone area/subcampaign runs do not have the batch queue used by
        # --full-area and --interactive. Their live progress is still the
        # number of recorded outcomes.
        finished = max(0, stats.passed) + max(0, stats.failed)
    else:
        finished = campaign_progress_finished(
            batch_queue,
            area,
            subcampaign,
            passed=stats.passed,
            failed=stats.failed,
        )
    set_campaign_finished_count(batch_queue, area, subcampaign, finished)
    return finished


def refresh_live_campaign_stats(
    log_dir: Path,
    area: str,
    subcampaign: str,
    *,
    batch_queue: BatchQueueState | None = None,
    display: CampaignProgressDisplay | None = None,
) -> CampaignTestStats:
    """Reload ``summary.json`` and push counts to queue + progress display."""
    stats = load_campaign_stats(log_dir)
    apply_campaign_stats(stats, area, subcampaign, batch_queue=batch_queue)
    if display is not None:
        display.apply_disk_stats(stats.passed, stats.failed)
    return stats
