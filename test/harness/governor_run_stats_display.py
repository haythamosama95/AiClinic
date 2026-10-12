"""Terminal report for governor run stats (Rich when available)."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from harness.governor_run_manifest import load_run_manifest, manifest_path


def format_elapsed(seconds: float | int | None) -> str:
    if seconds is None:
        return "—"
    total = max(0.0, float(seconds))
    if total < 60:
        return f"{total:.1f}s"
    minutes, sec = divmod(int(total), 60)
    if minutes < 60:
        return f"{minutes}m {sec}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes}m"


def _campaign_status(exit_code: int | None, has_summary: bool) -> tuple[str, str]:
    if exit_code is None and not has_summary:
        return "pending", "○"
    if exit_code is None:
        return "partial", "◐"
    if exit_code == 0:
        return "passed", "✓"
    return "failed", "✗"


def _status_style(status: str) -> str:
    return {
        "passed": "bold green",
        "failed": "bold red",
        "partial": "bold yellow",
        "pending": "dim",
    }.get(status, "")


def _progress_label(attempted: int, total: int | None) -> str:
    if total is None:
        return f"{attempted}/—"
    return f"{attempted}/{total}"


_PROGRESS_BAR_WIDTH = 10


def _mini_bar(attempted: int, total: int | None, width: int = _PROGRESS_BAR_WIDTH) -> str:
    if total is None or total <= 0:
        return " " * width
    ratio = min(1.0, attempted / total)
    filled = int(round(ratio * width))
    return "█" * filled + "░" * (width - filled)


def _progress_label_width(
    campaigns: list[dict[str, Any]],
    totals: dict[str, Any],
) -> int:
    width = len(_progress_label(0, None))
    for row in campaigns:
        attempted = int(row.get("attempted") or 0)
        total = row.get("total")
        if isinstance(total, int):
            width = max(width, len(_progress_label(attempted, total)))
        else:
            width = max(width, len(_progress_label(attempted, None)))
    t_attempted = int(totals.get("attempted") or 0)
    t_total = totals.get("total")
    if isinstance(t_total, int):
        width = max(width, len(_progress_label(t_attempted, t_total)))
    else:
        width = max(width, len(_progress_label(t_attempted, None)))
    return width


def _format_progress_field(
    attempted: int,
    total: int | None,
    *,
    label_width: int,
    bar_width: int = _PROGRESS_BAR_WIDTH,
) -> str:
    bar = _mini_bar(attempted, total, bar_width)
    label = _progress_label(attempted, total).rjust(label_width)
    return f"{bar} {label}"


def _rich_progress_cell(
    attempted: int,
    total: int | None,
    *,
    label_width: int,
    bar_style: str = "cyan",
    label_style: str = "bold white",
) -> Any:
    from rich.text import Text

    field = _format_progress_field(
        attempted, total, label_width=label_width
    )
    bar_part = field[:_PROGRESS_BAR_WIDTH]
    label_part = field[_PROGRESS_BAR_WIDTH + 1 :]
    cell = Text()
    cell.append(bar_part, style=bar_style)
    cell.append(" ", style="")
    cell.append(label_part, style=label_style)
    return cell


def _aggregate(campaigns: list[dict[str, Any]]) -> dict[str, Any]:
    passed = failed = attempted = 0
    total_known = 0
    total: int | None = 0
    elapsed = 0.0
    any_elapsed = False
    any_unknown_total = False
    exit_failures = 0
    for row in campaigns:
        passed += int(row.get("passed") or 0)
        failed += int(row.get("failed") or 0)
        attempted += int(row.get("attempted") or 0)
        t = row.get("total")
        if t is None:
            any_unknown_total = True
        else:
            total_known += int(t)
        sec = row.get("elapsed_seconds")
        if isinstance(sec, (int, float)):
            elapsed += float(sec)
            any_elapsed = True
        code = row.get("exit_code")
        if code not in (None, 0):
            exit_failures += 1
    if any_unknown_total:
        total = None
    else:
        total = total_known
    return {
        "passed": passed,
        "failed": failed,
        "attempted": attempted,
        "total": total,
        "elapsed_seconds": elapsed if any_elapsed else None,
        "failed_campaigns": exit_failures,
    }


def _run_header_meta(run_root: Path) -> dict[str, Any]:
    run_root = run_root.resolve()
    meta: dict[str, Any] = {"run_id": run_root.name, "run_root": str(run_root)}
    if manifest_path(run_root).is_file():
        try:
            doc = load_run_manifest(run_root)
            meta["started_at"] = doc.get("started_at")
            continued = doc.get("continued_at") or []
            if continued:
                meta["continued_runs"] = len(continued)
        except (ValueError, OSError):
            pass
    return meta


def _rich_available() -> bool:
    try:
        import rich  # noqa: F401

        return True
    except ImportError:
        return False


def print_governor_run_stats_report(
    run_root: Path,
    campaigns: list[dict[str, Any]],
    *,
    file: Any | None = None,
) -> None:
    """Render campaign stats to the terminal."""
    if not campaigns:
        return
    out = file if file is not None else sys.stderr
    meta = _run_header_meta(run_root)
    totals = _aggregate(campaigns)
    if _rich_available():
        _print_rich_report(run_root, meta, campaigns, totals, console_file=out)
    else:
        _print_plain_report(meta, campaigns, totals, out=out)
        if hasattr(out, "isatty") and out.isatty():
            print(
                "Tip: pip install -r test/requirements.txt for a Rich stats table.",
                file=out,
            )


def _print_rich_report(
    run_root: Path,
    meta: dict[str, Any],
    campaigns: list[dict[str, Any]],
    totals: dict[str, Any],
    *,
    console_file: Any,
) -> None:
    from rich import box
    from rich.console import Console, Group
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text

    console = Console(file=console_file, highlight=False, soft_wrap=True)

    header = Text()
    header.append("Run ", style="dim")
    header.append(meta.get("run_id", ""), style="bold cyan")
    if meta.get("started_at"):
        header.append("\nStarted ", style="dim")
        header.append(str(meta["started_at"]), style="white")
    if meta.get("continued_runs"):
        header.append("\nContinued ", style="dim")
        header.append(str(meta["continued_runs"]), style="bold magenta")
        header.append(" time(s)", style="dim")
    header.append("\n", style="")
    header.append(str(run_root), style="cyan")

    table = Table(
        box=box.ROUNDED,
        show_header=True,
        header_style="bold cyan",
        border_style="bright_blue",
        expand=True,
        padding=(0, 1),
    )
    table.add_column("Campaign", style="white", ratio=3, no_wrap=True)
    table.add_column("", width=2, justify="center")
    table.add_column("Pass", justify="right", style="green", width=6)
    table.add_column("Fail", justify="right", width=5)
    progress_label_w = _progress_label_width(campaigns, totals)
    progress_col_w = _PROGRESS_BAR_WIDTH + 1 + progress_label_w
    table.add_column("Progress", justify="left", width=progress_col_w, no_wrap=True)
    table.add_column("Time", justify="right", style="dim", width=8)
    table.add_column("Exit", justify="center", width=8)

    for row in campaigns:
        area = row.get("area", "")
        sub = row.get("subcampaign", "")
        name = f"{area} / {sub}"
        status, glyph = _campaign_status(
            row.get("exit_code"), bool(row.get("has_summary"))
        )
        passed = int(row.get("passed") or 0)
        failed = int(row.get("failed") or 0)
        attempted = int(row.get("attempted") or 0)
        total = row.get("total")

        fail_style = "bold red" if failed else "dim"
        progress = _rich_progress_cell(
            attempted,
            total if isinstance(total, int) else None,
            label_width=progress_label_w,
        )

        exit_label = "—" if row.get("exit_code") is None else str(row.get("exit_code"))
        exit_style = "green" if row.get("exit_code") == 0 else (
            "bold red" if row.get("exit_code") not in (None,) else "dim"
        )

        table.add_row(
            name,
            Text(glyph, style=_status_style(status)),
            str(passed),
            Text(str(failed), style=fail_style),
            progress,
            format_elapsed(row.get("elapsed_seconds")),
            Text(exit_label, style=exit_style),
        )

    t_passed = totals["passed"]
    t_failed = totals["failed"]
    t_attempted = totals["attempted"]
    t_total = totals["total"]
    total_progress = _rich_progress_cell(
        t_attempted,
        t_total if isinstance(t_total, int) else None,
        label_width=progress_label_w,
        bar_style="bold cyan",
    )
    table.add_section()
    table.add_row(
        Text("Total", style="bold"),
        "",
        Text(str(t_passed), style="bold green"),
        Text(str(t_failed), style="bold red" if t_failed else "dim"),
        total_progress,
        format_elapsed(totals.get("elapsed_seconds")),
        Text(
            "OK" if totals["failed_campaigns"] == 0 else f"{totals['failed_campaigns']} fail",
            style="bold green" if totals["failed_campaigns"] == 0 else "bold red",
        ),
    )

    parts: list[Any] = [
        Panel(header, title="[bold cyan]Governor run stats[/]", border_style="bright_blue", box=box.ROUNDED),
        Panel(table, border_style="cyan", box=box.ROUNDED, padding=(0, 0)),
    ]

    console.print(Group(*parts))
    console.print()


def _print_plain_report(
    meta: dict[str, Any],
    campaigns: list[dict[str, Any]],
    totals: dict[str, Any],
    *,
    out: Any,
) -> None:
    print(f"Governor run stats — {meta.get('run_id', '')}", file=out)
    print(f"  {meta.get('run_root', '')}", file=out)
    print(file=out)
    for row in campaigns:
        area = row.get("area", "")
        sub = row.get("subcampaign", "")
        status, glyph = _campaign_status(
            row.get("exit_code"), bool(row.get("has_summary"))
        )
        print(
            f"  {glyph} {area}/{sub}  "
            f"pass={row.get('passed')} fail={row.get('failed')}  "
            f"{_progress_label(int(row.get('attempted') or 0), row.get('total'))}  "
            f"time={format_elapsed(row.get('elapsed_seconds'))}  "
            f"exit={row.get('exit_code')}",
            file=out,
        )
    print(file=out)
    print(
        f"  Total: pass={totals['passed']} fail={totals['failed']}  "
        f"{_progress_label(totals['attempted'], totals['total'])}  "
        f"time={format_elapsed(totals.get('elapsed_seconds'))}",
        file=out,
    )
