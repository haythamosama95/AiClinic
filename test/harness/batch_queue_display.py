"""Campaign queue panel for batch runs (plain + Rich)."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any, NamedTuple

from harness.campaign_config import config_display_lines
from harness.curses_campaign_ui import (
    RunStatus,
    StatusTreeNode,
    build_status_forest,
    status_glyph,
)

if TYPE_CHECKING:
    from collections.abc import Sequence


@dataclass
class BatchQueueState:
    """Mutable queue snapshot read by live progress on each refresh."""

    forest: list[StatusTreeNode]
    status_by_key: dict[tuple[str, str], RunStatus]
    finished_by_key: dict[tuple[str, str], int]
    test_total_by_key: dict[tuple[str, str], int | None] = field(default_factory=dict)
    prior_finished_by_key: dict[tuple[str, str], int] = field(default_factory=dict)
    prior_remaining_by_key: dict[tuple[str, str], int | None] = field(
        default_factory=dict
    )
    passed_by_key: dict[tuple[str, str], int] = field(default_factory=dict)
    failed_by_key: dict[tuple[str, str], int] = field(default_factory=dict)
    resume_display: bool = False


def batch_queue_from_picked(
    picked: Sequence[tuple[str, str]],
    area_subcampaigns: dict[str, list[str]],
    *,
    test_totals: dict[tuple[str, str], int | None] | None = None,
    resume_display: bool = False,
) -> BatchQueueState:
    forest = build_status_forest(list(picked), area_subcampaigns)
    totals = dict(test_totals or {})
    return BatchQueueState(
        forest=forest,
        status_by_key={key: "waiting" for key in picked},
        finished_by_key={key: 0 for key in picked},
        test_total_by_key=totals,
        prior_finished_by_key={key: 0 for key in picked},
        prior_remaining_by_key={key: None for key in picked},
        passed_by_key={key: 0 for key in picked},
        failed_by_key={key: 0 for key in picked},
        resume_display=resume_display,
    )


def _subcampaign_test_total(
    state: BatchQueueState,
    area: str,
    sub_id: str,
) -> int | None:
    key = (area, sub_id)
    if key in state.test_total_by_key:
        return state.test_total_by_key[key]
    from harness.campaign_counts import test_count

    return test_count(area, sub_id)


def record_test_finished(
    state: BatchQueueState | None,
    area: str,
    sub_id: str,
) -> None:
    if state is None:
        return
    key = (area, sub_id)
    if key in state.finished_by_key:
        state.finished_by_key[key] += 1


def set_campaign_finished_count(
    state: BatchQueueState | None,
    area: str,
    sub_id: str,
    finished: int,
) -> None:
    if state is None:
        return
    key = (area, sub_id)
    if key in state.finished_by_key:
        state.finished_by_key[key] = max(0, finished)


def set_campaign_resume_baseline(
    state: BatchQueueState | None,
    area: str,
    sub_id: str,
    passed: int,
    failed: int,
) -> None:
    """Snapshot pass/fail from disk at the start of ``--continue``."""
    if state is None:
        return
    key = (area, sub_id)
    total = _subcampaign_test_total(state, area, sub_id)
    passed, failed = _cap_pass_fail(passed, failed, total)
    from harness.campaign_resume import progress_finished_count

    finished = progress_finished_count(passed, failed, resume=False)
    if total is not None:
        finished = min(finished, total)
    # Frozen at continue start: prior passes (skipped on resume), not pass+fail total.
    if key in state.prior_finished_by_key:
        state.prior_finished_by_key[key] = passed
    if key in state.prior_remaining_by_key:
        if total is None:
            state.prior_remaining_by_key[key] = None
        else:
            from harness.campaign_resume import work_remaining_count

            state.prior_remaining_by_key[key] = work_remaining_count(
                total, passed, failed, resume=True
            )
    set_campaign_pass_fail_counts(state, area, sub_id, passed, failed)
    set_campaign_finished_count(state, area, sub_id, finished)


def set_campaign_pass_fail_counts(
    state: BatchQueueState | None,
    area: str,
    sub_id: str,
    passed: int,
    failed: int,
) -> None:
    if state is None:
        return
    key = (area, sub_id)
    if key in state.passed_by_key:
        state.passed_by_key[key] = max(0, passed)
    if key in state.failed_by_key:
        state.failed_by_key[key] = max(0, failed)


def _cap_pass_fail(
    passed: int,
    failed: int,
    total: int | None,
) -> tuple[int, int]:
    passed = max(0, passed)
    failed = max(0, failed)
    if total is None:
        return passed, failed
    if passed + failed > total:
        overflow = passed + failed - total
        reduce_failed = min(failed, overflow)
        failed -= reduce_failed
        overflow -= reduce_failed
        passed = max(0, passed - overflow)
    return passed, failed


def campaign_progress_finished(
    state: BatchQueueState,
    area: str,
    sub_id: str,
    *,
    passed: int | None = None,
    failed: int | None = None,
) -> int:
    key = (area, sub_id)
    p = passed if passed is not None else state.passed_by_key.get(key, 0)
    f = failed if failed is not None else state.failed_by_key.get(key, 0)
    total = _subcampaign_test_total(state, area, sub_id)
    p, f = _cap_pass_fail(p, f, total)
    from harness.campaign_resume import progress_finished_count

    finished = progress_finished_count(p, f, resume=state.resume_display)
    if total is not None:
        finished = min(finished, total)
    return finished


def resume_campaign_is_complete(
    state: BatchQueueState,
    area: str,
    sub_id: str,
) -> bool:
    """True when continue has no test left without a pass or fail result."""
    left = campaign_tests_remaining(state, area, sub_id)
    if left is None:
        return False
    return left == 0


def campaign_tests_remaining(
    state: BatchQueueState,
    area: str,
    sub_id: str,
) -> int | None:
    key = (area, sub_id)
    total = _subcampaign_test_total(state, area, sub_id)
    passed = state.passed_by_key.get(key, 0)
    failed = state.failed_by_key.get(key, 0)
    if state.resume_display:
        return tests_left(total, passed, failed)
    from harness.campaign_resume import work_remaining_count

    return work_remaining_count(total, passed, failed, resume=False)


def _node_test_progress(
    node: StatusTreeNode,
    state: BatchQueueState,
) -> tuple[int, int | None]:
    if node.runnable:
        key = (node.area, node.sub_id)
        finished = state.finished_by_key.get(key, 0)
        return finished, _subcampaign_test_total(state, node.area, node.sub_id)

    finished = 0
    total = 0
    any_child = False
    total_known = True
    for child in node.children:
        any_child = True
        child_finished, child_total = _node_test_progress(child, state)
        finished += child_finished
        if child_total is None:
            total_known = False
        else:
            total += child_total
    if not any_child:
        return 0, _subcampaign_test_total(state, node.area, node.sub_id)
    return finished, total if total_known else None


def _normalize_finished_total(finished: int, total: int | None) -> tuple[int, str]:
    total_label = "—" if total is None else str(total)
    if total is not None and finished > total:
        finished = total
    return finished, total_label


def _coerce_queue_counts(
    finished: int,
    total: int | None,
    passed: int,
    failed: int,
    *,
    resume: bool,
) -> tuple[int, int, int, int]:
    from harness.campaign_resume import progress_finished_count

    passed, failed = _cap_pass_fail(passed, failed, total)
    derived = progress_finished_count(passed, failed, resume=resume)
    if passed > 0 or failed > 0:
        display_finished = derived
    elif finished > 0:
        display_finished = finished
    else:
        display_finished = 0
    display_finished, _ = _normalize_finished_total(display_finished, total)
    return display_finished, passed, failed, display_finished


def _queue_counts_body(
    finished: int,
    total: int | None,
    passed: int,
    failed: int,
    *,
    resume: bool = False,
) -> str:
    finished, passed, failed, _ = _coerce_queue_counts(
        finished, total, passed, failed, resume=resume
    )
    total_label = "—" if total is None else str(total)
    return f"[Pass {passed}| Fail {failed}] [{finished}/{total_label}]"


def format_queue_progress(
    finished: int,
    total: int | None,
    *,
    passed: int = 0,
    failed: int = 0,
    run_status: RunStatus | None = None,
    resume: bool = False,
) -> str:
    return _queue_counts_body(
        finished, total, passed, failed, resume=resume
    )


def campaign_has_continuation_snapshot(
    snapshot_ran: int,
    live_remaining: int | None,
) -> bool:
    """Show continuation stats when this run resumed with prior passes."""
    if snapshot_ran <= 0:
        return False
    if live_remaining is None:
        return True
    return True


def tests_left(total: int | None, passed: int, failed: int) -> int | None:
    """Tests with no recorded outcome. ``passed + failed + left == total``."""
    if total is None:
        return None
    return max(0, total - max(0, passed) - max(0, failed))


def resume_work_left(total: int | None, passed: int, failed: int = 0) -> int | None:
    """Tests still to execute on ``--continue`` (failures are retried)."""
    del failed
    if total is None:
        return None
    return max(0, total - max(0, passed))


def format_resume_queue_progress(
    snapshot_skip: int,
    live_remaining: int | None,
    finished: int,
    total: int | None,
    passed: int,
    failed: int,
    *,
    run_status: RunStatus | None = None,
) -> str:
    """Progress label for governor ``--continue`` (same counts as ``summary.json``)."""
    finished, passed, failed, _ = _coerce_queue_counts(
        finished, total, passed, failed, resume=True
    )
    total_label = "—" if total is None else str(total)
    body = f"[Pass {passed}| Fail {failed}] [{finished}/{total_label}]"
    if not campaign_has_continuation_snapshot(snapshot_skip, live_remaining):
        return body
    if run_status == "finished":
        left = 0
    else:
        left = resume_work_left(total, passed, failed)
    if left is None:
        return body
    return f"{body} [{left} Left]"


def _node_progress_counts(
    node: StatusTreeNode,
    state: BatchQueueState,
) -> tuple[int, int | None, int, int, int, int | None]:
    key = (node.area, node.sub_id)
    total = _subcampaign_test_total(state, node.area, node.sub_id)
    passed = state.passed_by_key.get(key, 0)
    failed = state.failed_by_key.get(key, 0)
    if node.runnable:
        finished = state.finished_by_key.get(key, 0)
        if passed > 0 or failed > 0:
            finished = campaign_progress_finished(state, node.area, node.sub_id)
    else:
        finished, total = _node_test_progress(node, state)
    snapshot_ran = state.prior_finished_by_key.get(key, 0)
    live_remaining = campaign_tests_remaining(state, node.area, node.sub_id)
    return finished, total, passed, failed, snapshot_ran, live_remaining


def _queue_name_column(node: StatusTreeNode) -> str:
    return f"{node.area} / {node.sub_id}"


class QueueTableRow(NamedTuple):
    status: RunStatus
    name: str
    passed: int
    failed: int
    finished: int
    total: int | None
    resume_left: int | None


def _queue_table_row(
    node: StatusTreeNode,
    state: BatchQueueState,
    status: RunStatus,
) -> QueueTableRow:
    finished, total, passed, failed, snapshot_ran, live_remaining = (
        _node_progress_counts(node, state)
    )
    finished, passed, failed, _ = _coerce_queue_counts(
        finished, total, passed, failed, resume=state.resume_display
    )
    resume_left: int | None = None
    if state.resume_display and campaign_has_continuation_snapshot(
        snapshot_ran, live_remaining
    ):
        if status == "finished":
            resume_left = 0
        else:
            resume_left = resume_work_left(total, passed, failed)
    return QueueTableRow(
        status=status,
        name=_queue_name_column(node),
        passed=passed,
        failed=failed,
        finished=finished,
        total=total,
        resume_left=resume_left,
    )


def _queue_table_rows(
    state: BatchQueueState | None,
    *,
    fallback_area: str | None = None,
    fallback_subcampaign: str | None = None,
    fallback_finished: int | None = None,
) -> list[QueueTableRow]:
    if state is not None:
        return [
            _queue_table_row(node, state, status)
            for node, status in flat_queue_rows(state)
        ]
    if fallback_area and fallback_subcampaign:
        from harness.campaign_counts import test_count

        finished = fallback_finished if fallback_finished is not None else 0
        total = test_count(fallback_area, fallback_subcampaign)
        return [
            QueueTableRow(
                status="running",
                name=f"{fallback_area} / {fallback_subcampaign}",
                passed=0,
                failed=0,
                finished=finished,
                total=total,
                resume_left=None,
            )
        ]
    return []


def _node_queue_progress_label(
    node: StatusTreeNode,
    state: BatchQueueState,
    status: RunStatus,
) -> str:
    finished, total, passed, failed, snapshot_ran, live_remaining = (
        _node_progress_counts(node, state)
    )
    if state.resume_display:
        label = format_resume_queue_progress(
            snapshot_ran,
            live_remaining,
            finished,
            total,
            passed,
            failed,
            run_status=status,
        )
        return " " + label
    return " " + format_queue_progress(
        finished, total, passed=passed, failed=failed, run_status=status
    )


def _done_progress_style(run_status: RunStatus) -> str:
    if run_status == "running":
        return "bold yellow"
    if run_status == "finished":
        return "bold green"
    if run_status == "failed":
        return "bold red"
    return "bold white"


def _rich_done_cell(row: QueueTableRow) -> Any:
    from rich.text import Text

    total_label = "—" if row.total is None else str(row.total)
    cell = Text()
    cell.append(str(row.finished), style=_done_progress_style(row.status))
    cell.append("/", style="dim")
    cell.append(total_label, style="dim cyan")
    return cell


def _rich_pass_cell(passed: int) -> Any:
    from rich.text import Text

    return Text(str(passed), style="bold green")


def _rich_fail_cell(failed: int) -> Any:
    from rich.text import Text

    style = "bold red" if failed else "dim bright_black"
    return Text(str(failed), style=style)


def _rich_left_cell(left: int | None) -> Any:
    from rich.text import Text

    if left is None:
        return Text("—", style="dim")
    return Text(str(left), style="bold magenta")


def _append_queue_progress_rich(
    text: Any,
    *,
    finished: int,
    total: int | None,
    passed: int,
    failed: int,
    run_status: RunStatus,
    resume_display: bool = False,
    snapshot_ran: int = 0,
    snapshot_remaining: int | None = None,
) -> None:
    """Colorized pass/fail and ran/total stats (Rich ``Text``)."""
    finished, passed, failed, _ = _coerce_queue_counts(
        finished, total, passed, failed, resume=resume_display
    )
    row = QueueTableRow(
        status=run_status,
        name="",
        passed=passed,
        failed=failed,
        finished=finished,
        total=total,
        resume_left=None,
    )
    text.append(" ")
    text.append("[", style="bright_black")
    text.append("Pass ", style="dim")
    text.append(_rich_pass_cell(passed))
    text.append("|", style="bright_black")
    text.append(" Fail ", style="dim")
    text.append(_rich_fail_cell(failed))
    text.append("]", style="bright_black")
    text.append(" [", style="bright_black")
    text.append(_rich_done_cell(row))
    text.append("]", style="bright_black")

    if resume_display and campaign_has_continuation_snapshot(
        snapshot_ran, snapshot_remaining
    ):
        left = tests_left(total, passed, failed)
        left_label = "—" if left is None else str(left)
        text.append(" [", style="bright_black")
        text.append(left_label, style="bold magenta")
        text.append(" Left", style="dim italic")
        text.append("]", style="bright_black")


def _rich_queue_table(
    rows: list[QueueTableRow],
    *,
    show_resume_left: bool = False,
) -> Any:
    from rich import box
    from rich.table import Table
    from rich.text import Text

    table = Table(
        box=box.SIMPLE_HEAD,
        show_header=True,
        header_style="bold cyan",
        expand=False,
        padding=(0, 1),
    )
    table.add_column("", width=2, justify="center", style="")
    table.add_column("Campaign", ratio=1, no_wrap=True)
    table.add_column("Pass", justify="right", style="dim")
    table.add_column("Fail", justify="right", style="dim")
    table.add_column("Done", justify="right")
    if show_resume_left:
        table.add_column("Left", justify="right", style="dim")

    for row in rows:
        glyph = status_glyph(row.status)
        status_cell = Text(glyph, style=_status_style_rich(row.status))
        name_cell = Text(row.name, style=_node_name_style_rich(row.status))
        cells: list[Any] = [
            status_cell,
            name_cell,
            _rich_pass_cell(row.passed),
            _rich_fail_cell(row.failed),
            _rich_done_cell(row),
        ]
        if show_resume_left:
            cells.append(_rich_left_cell(row.resume_left))
        table.add_row(*cells)
    return table


def _plain_queue_table_lines(
    rows: list[QueueTableRow],
    *,
    show_resume_left: bool = False,
) -> list[str]:
    if not rows:
        return [" (no campaigns selected)"]

    pass_w = max(len("Pass"), max(len(str(r.passed)) for r in rows))
    fail_w = max(len("Fail"), max(len(str(r.failed)) for r in rows))
    done_w = max(
        len("Done"),
        max(len(f"{r.finished}/{r.total if r.total is not None else '—'}") for r in rows),
    )
    name_w = max(len("Campaign"), max(len(r.name) for r in rows))
    left_w = 0
    if show_resume_left:
        left_w = max(
            len("Left"),
            max(
                len("—" if r.resume_left is None else str(r.resume_left))
                for r in rows
            ),
        )

    header_parts = [
        "  ",
        "Campaign".ljust(name_w),
        str("Pass").rjust(pass_w),
        str("Fail").rjust(fail_w),
        str("Done").rjust(done_w),
    ]
    if show_resume_left:
        header_parts.append(str("Left").rjust(left_w))
    lines = [" ".join(header_parts), " " + "─" * (len(header_parts[0]) + name_w + pass_w + fail_w + done_w + (left_w + 1 if show_resume_left else 0) + 3)]

    for row in rows:
        glyph = status_glyph(row.status)
        done = f"{row.finished}/{row.total if row.total is not None else '—'}"
        parts = [
            f" {glyph}",
            row.name.ljust(name_w),
            str(row.passed).rjust(pass_w),
            str(row.failed).rjust(fail_w),
            done.rjust(done_w),
        ]
        if show_resume_left:
            left = "—" if row.resume_left is None else str(row.resume_left)
            parts.append(left.rjust(left_w))
        lines.append(" ".join(parts))
    return lines


def _node_name_style_rich(status: RunStatus) -> str:
    if status == "running":
        return "bold yellow"
    if status == "finished":
        return "green"
    if status == "failed":
        return "bold red"
    if status == "waiting":
        return "bright_black"
    return ""


def flat_queue_rows(
    state: BatchQueueState,
) -> list[tuple[StatusTreeNode, RunStatus]]:
    """Only picked (runnable) campaigns — no parent rollup rows or tree prefixes."""
    flat: list[tuple[StatusTreeNode, RunStatus]] = []
    for root in state.forest:
        for node in root.flattened():
            if not node.runnable:
                continue
            key = (node.area, node.sub_id)
            flat.append((node, state.status_by_key.get(key, "waiting")))
    return flat


def _status_style_rich(status: RunStatus) -> str:
    if status == "waiting":
        return "bright_black"
    if status == "running":
        return "bold yellow"
    if status == "finished":
        return "bold green"
    return "bold red"


def _queue_body_lines(
    state: BatchQueueState | None,
    *,
    fallback_area: str | None = None,
    fallback_subcampaign: str | None = None,
    fallback_finished: int | None = None,
) -> list[str]:
    resume = bool(state and state.resume_display)
    rows = _queue_table_rows(
        state,
        fallback_area=fallback_area,
        fallback_subcampaign=fallback_subcampaign,
        fallback_finished=fallback_finished,
    )
    if rows:
        return _plain_queue_table_lines(rows, show_resume_left=resume)
    return [" (empty)"]


def _config_body_lines(campaign_config: dict[str, Any] | None) -> list[str]:
    pairs = config_display_lines(campaign_config)
    if not pairs:
        return [" (no config)"]
    lines: list[str] = []
    for label, value in pairs:
        lines.append(f" {label}: {value}")
    return lines


def _run_directory_line(run_directory: Path | str | None) -> str | None:
    if run_directory is None:
        return None
    return f"Run directory: {run_directory}"


def plain_queue_lines(
    state: BatchQueueState | None,
    campaign_config: dict[str, Any] | None = None,
    *,
    fallback_area: str | None = None,
    fallback_subcampaign: str | None = None,
    fallback_finished: int | None = None,
    run_directory: Path | str | None = None,
) -> list[str]:
    queue_lines = _queue_body_lines(
        state,
        fallback_area=fallback_area,
        fallback_subcampaign=fallback_subcampaign,
        fallback_finished=fallback_finished,
    )
    config_lines = _config_body_lines(campaign_config)
    show_config = bool(config_display_lines(campaign_config))
    min_left = max(len(" Queue "), max((len(line) for line in queue_lines), default=0), 12)
    min_right = (
        max(len(" Config "), max((len(line) for line in config_lines), default=0), 12)
        if show_config
        else 0
    )
    run_line = _run_directory_line(run_directory)
    if not show_config:
        inner_w = max(len(" Campaign queue "), min_left, 20)
        if run_line:
            inner_w = max(inner_w, len(run_line) + 2)
        rule = "─" * inner_w
        lines = [f"╭{rule}╮", f"│{' Campaign queue '.center(inner_w)}│"]
        if run_line:
            lines.append(f"│ {run_line.ljust(inner_w - 1)[: inner_w - 1]}│")
        for line in queue_lines:
            lines.append(f"│{line.ljust(inner_w)[:inner_w]}│")
        lines.append(f"╰{rule}╯")
        return lines

    inner_w = max(len(" Campaign queue "), min_left + min_right + 3, 20)
    while True:
        content_w = inner_w - 3
        left_w = (content_w * 2) // 3
        right_w = content_w - left_w
        if left_w >= min_left and right_w >= min_right:
            break
        inner_w += 1
    rule = "─" * inner_w
    title = " Campaign queue "
    lines = [f"╭{rule}╮", f"│{title.center(inner_w)}│"]
    if run_line:
        lines.append(f"│ {run_line.ljust(inner_w - 1)[: inner_w - 1]}│")
    height = max(len(queue_lines), len(config_lines))
    for index in range(height):
        left = queue_lines[index] if index < len(queue_lines) else ""
        right = config_lines[index] if index < len(config_lines) else ""
        row = f"{left.ljust(left_w)[:left_w]} │ {right.ljust(right_w)[:right_w]}"
        lines.append(f"│{row.ljust(inner_w)[:inner_w]}│")
    lines.append(f"╰{rule}╯")
    return lines


def _rich_queue_shell(body: Any, *, run_directory: Path | str | None) -> Any:
    from rich.console import Group
    from rich.text import Text

    run_line = _run_directory_line(run_directory)
    if run_line is None:
        return body
    return Group(Text(run_line, style="dim cyan"), body)


def rich_queue_panel(
    state: BatchQueueState | None,
    campaign_config: dict[str, Any] | None = None,
    *,
    fallback_area: str | None = None,
    fallback_subcampaign: str | None = None,
    fallback_finished: int | None = None,
    run_directory: Path | str | None = None,
) -> Any:
    from rich import box
    from rich.console import Group
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text

    rows = _queue_table_rows(
        state,
        fallback_area=fallback_area,
        fallback_subcampaign=fallback_subcampaign,
        fallback_finished=fallback_finished,
    )
    show_resume = bool(state and state.resume_display)
    if rows:
        queue_body = _rich_queue_table(rows, show_resume_left=show_resume)
    else:
        queue_body = Text("(empty)", style="dim")

    pairs = config_display_lines(campaign_config)
    if not pairs:
        return Panel(
            _rich_queue_shell(queue_body, run_directory=run_directory),
            title="[bold cyan]Campaign queue[/]",
            border_style="bright_blue",
            box=box.ROUNDED,
            padding=(0, 1),
        )

    config_body = Text()
    for index, (label, value) in enumerate(pairs):
        if index:
            config_body.append("\n")
        config_body.append(f"{label}\n", style="dim")
        config_body.append(value, style="bold white")

    grid = Table.grid(expand=True)
    grid.add_column(ratio=2)
    grid.add_column(ratio=1)
    grid.add_row(
        Group(Text("Queue", style="bold cyan"), queue_body),
        Group(Text("Config", style="bold cyan"), config_body),
    )
    return Panel(
        _rich_queue_shell(grid, run_directory=run_directory),
        title="[bold cyan]Campaign queue[/]",
        border_style="bright_blue",
        box=box.ROUNDED,
        padding=(0, 1),
    )
