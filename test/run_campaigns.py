#!/usr/bin/env python3
"""Root test campaign governor — delegates to per-area run_campaigns.py scripts."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from harness.campaign_catalog import CATALOG, print_full_table  # noqa: E402
from harness.interactive_campaign_picker import pick_campaigns  # noqa: E402
from harness.batch_queue_display import BatchQueueState  # noqa: E402
from harness.interactive_run_dashboard import run_batch_with_dashboard  # noqa: E402
from harness.campaign_config import (  # noqa: E402
    governor_config_area,
    load_campaign_config,
)
from harness.common import (  # noqa: E402
    AREA_DEFAULT_SUBCAMPAIGN,
    ensure_campaign_sigint_handler,
    governor_campaign_log_dir,
    governor_run_root,
    new_run_id,
    run_subprocess_with_live_status,
)
from harness.governor_run_manifest import (  # noqa: E402
    load_run_manifest,
    picked_from_manifest,
    resolve_governor_run_dir,
)
from harness.campaign_resume import sync_resume_state  # noqa: E402
from harness.governor_run_stats import generate_governor_run_stats  # noqa: E402

AREA_SCRIPTS: dict[str, Path] = {
    "frontend": REPO_ROOT / "frontend" / "tool" / "run_campaigns.py",
    "backend": REPO_ROOT / "backend" / "tests" / "run_campaigns.py",
    "ai-platform": REPO_ROOT / "ai-platform" / "run_campaigns.py",
    "abo": REPO_ROOT / "abo" / "run_campaigns.py",
    "e2e-fullstack": REPO_ROOT / "e2e" / "fullstack" / "run_campaigns.py",
    "vendor-contracts": REPO_ROOT / "packages" / "vendor-contracts" / "run_campaigns.py",
    "ops-launch": REPO_ROOT / "ops" / "launch" / "run_campaigns.py",
}


def area_subcampaign_map() -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for area in sorted(AREA_SCRIPTS.keys()):
        entry = CATALOG.get(area)
        if entry:
            out[area] = sorted(entry.subcampaigns.keys())
        else:
            out[area] = ["all"]
    return out


def _interactive_pick_campaigns() -> list[tuple[str, str]]:
    area_subs = area_subcampaign_map()
    if not any(area_subs.values()):
        print("error: no campaigns available", file=sys.stderr)
        return []
    return pick_campaigns(area_subs)


def default_campaigns_picked() -> list[tuple[str, str]]:
    """One subcampaign per area: each area's default rollup (e.g. backend ``all``)."""
    area_subs = area_subcampaign_map()
    picked: list[tuple[str, str]] = []
    for area in sorted(AREA_SCRIPTS.keys()):
        preferred = AREA_DEFAULT_SUBCAMPAIGN.get(area, "all")
        subs = area_subs.get(area, [])
        if preferred in subs:
            sub_id = preferred
        elif "all" in subs:
            sub_id = "all"
        elif subs:
            sub_id = subs[0]
        else:
            continue
        picked.append((area, sub_id))
    return picked


def _run_area(
    area: str,
    script: Path,
    subcampaign: str | None,
    *,
    batch_queue: BatchQueueState | None = None,
    display: object | None = None,
    final_finish: bool = True,
    run_root: Path | None = None,
    governor_run_id: str | None = None,
    governor_resume: bool = False,
) -> int:
    if not script.is_file():
        print(f"error: missing campaign script for {area}: {script}", file=sys.stderr)
        return 2

    effective = subcampaign or AREA_DEFAULT_SUBCAMPAIGN.get(area, "all")
    if run_root is None:
        governor_run_id = governor_run_id or new_run_id()
        run_root = governor_run_root(governor_run_id)
    elif governor_run_id is None:
        governor_run_id = run_root.name
    run_root.mkdir(parents=True, exist_ok=True)
    log_dir = governor_campaign_log_dir(run_root, area, effective)
    cmd = [sys.executable, "-u", str(script), effective]

    label = f"[{area}/{effective}]"
    config_area = governor_config_area(area)
    campaign_config = load_campaign_config(area, effective)
    exclude_file = None
    if governor_resume:
        from harness.campaign_resume import (
            exclude_tests_for_campaign,
            write_campaign_exclude_file,
        )

        exclude = exclude_tests_for_campaign(run_root, area, effective, log_dir)
        if exclude:
            exclude_file = write_campaign_exclude_file(log_dir, exclude)

    from contextlib import nullcontext

    from harness.governor_console_log import attach_governor_console_log

    log_ctx = (
        attach_governor_console_log(
            run_root,
            meta={
                "area": area,
                "subcampaign": effective,
                "resume": governor_resume,
            },
        )
        if batch_queue is None
        else nullcontext()
    )
    with log_ctx:
        code = run_subprocess_with_live_status(
            cmd,
            REPO_ROOT,
            log_dir,
            status_label=label,
            batch_queue=batch_queue,
            campaign_config=campaign_config,
            config_area=config_area,
            display=display,
            final_finish=final_finish,
            governor_run_id=governor_run_id,
            governor_resume=governor_resume,
            exclude_tests_file=exclude_file,
        )
    if batch_queue is None:
        generate_governor_run_stats(run_root)
    return code


def _run_batch(
    picked: list[tuple[str, str]],
    *,
    resume: bool = False,
    run_root: Path | None = None,
) -> int:
    if not picked:
        print("error: no campaigns available", file=sys.stderr)
        return 2
    area_subs = area_subcampaign_map()

    if resume and run_root is not None:
        sync_resume_state(run_root, picked)

    def _run_one(
        area: str,
        sub_id: str,
        queue: BatchQueueState,
        display: object,
        is_last: bool,
        batch_run_root: Path,
    ) -> int:
        return _run_area(
            area,
            AREA_SCRIPTS[area],
            sub_id,
            batch_queue=queue,
            display=display,
            final_finish=is_last,
            run_root=batch_run_root,
            governor_run_id=batch_run_root.name,
            governor_resume=resume,
        )

    if run_root is None:
        run_root = governor_run_root(new_run_id())
    code = run_batch_with_dashboard(
        picked,
        area_subs,
        _run_one,
        run_root=run_root,
        resume=resume,
    )
    generate_governor_run_stats(run_root)
    return code


def _handle_interrupt() -> int:
    """Best-effort message when Ctrl+C arrives outside subprocess handling."""
    try:
        sys.stderr.write("\nInterrupted.\n")
        sys.stderr.flush()
    except Exception:
        pass
    return 130


def main(argv: list[str] | None = None) -> int:
    ensure_campaign_sigint_handler()
    parser = argparse.ArgumentParser(
        description="Run AiClinic test campaigns by area.",
        usage="python3 test/run_campaigns.py [area|all] [subcampaign] [--list] [-i]",
    )
    parser.add_argument(
        "area",
        nargs="?",
        help=(
            "Test area to run, or ``all`` to run every area's default campaign "
            "(omit to only use --list)."
        ),
    )
    parser.add_argument(
        "subcampaign",
        nargs="?",
        help="Subcampaign name (passed to the area script).",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Tabular list of areas and subcampaigns with descriptions.",
    )
    parser.add_argument(
        "-i",
        "--interactive",
        action="store_true",
        help="Area list: → subcampaigns, Space selects subtree, Enter runs.",
    )
    parser.add_argument(
        "--continue",
        dest="continue_run",
        metavar="PATH",
        help=(
            "Resume a governor batch run: ``latest``, a directory under "
            "test-results/governor/, or a path to run.json. Skips campaigns that "
            "already finished successfully. A campaign that still has tests with "
            "no result runs only those tests; recorded passes and failures are not repeated."
        ),
    )
    parser.add_argument(
        "--stats",
        metavar="PATH",
        help=(
            "Show governor run stats (no tests). Uses existing stats.json when "
            "present; otherwise builds them once. PATH is ``latest``, a run "
            "directory, or run.json."
        ),
    )
    args = parser.parse_args(argv)

    if args.stats:
        if (
            args.area
            or args.subcampaign
            or args.interactive
            or args.list
            or args.continue_run
        ):
            print(
                "error: --stats cannot be combined with area, --list, "
                "--interactive, or --continue",
                file=sys.stderr,
            )
            return 2
        try:
            return generate_governor_run_stats(args.stats, refresh=False)
        except FileNotFoundError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2

    if args.continue_run:
        if args.area or args.subcampaign or args.interactive or args.list:
            print(
                "error: --continue cannot be combined with area, --list, or --interactive",
                file=sys.stderr,
            )
            return 2
        try:
            run_root = resolve_governor_run_dir(args.continue_run)
            picked = picked_from_manifest(load_run_manifest(run_root))
            if not picked:
                print(f"error: no campaigns in {run_root / 'run.json'}", file=sys.stderr)
                return 2
            return _run_batch(picked, resume=True, run_root=run_root)
        except FileNotFoundError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2

    if args.interactive:
        if args.area:
            print(
                "error: do not pass area/subcampaign with --interactive",
                file=sys.stderr,
            )
            return 2
        if args.list:
            print("error: --interactive cannot be combined with --list", file=sys.stderr)
            return 2
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            print("error: --interactive requires a TTY", file=sys.stderr)
            return 2
        picked = _interactive_pick_campaigns()
        if not picked:
            return 0
        return _run_batch(picked)

    if args.area == "all":
        if args.subcampaign:
            print(
                "error: do not pass a subcampaign with area 'all'",
                file=sys.stderr,
            )
            return 2
        if args.list:
            print("error: use --list without 'all'", file=sys.stderr)
            return 2
        return _run_batch(default_campaigns_picked())

    if args.list and not args.area:
        print_full_table()
        print()
        print("Run: python3 test/run_campaigns.py <area> <subcampaign>")
        print("     python3 test/run_campaigns.py all")
        print(
            "Logs: test-results/governor/<run_id>/run.json, console.log "
            "(full runner output + harness errors), "
            "<area>/<subcampaign>/tests/ + summary.json"
        )
        print("Resume: python3 test/run_campaigns.py --continue latest")
        print("     python3 test/run_campaigns.py --continue test-results/governor/<run_id>")
        print("Stats:  python3 test/run_campaigns.py --stats latest")
        return 0

    if args.area and args.list:
        script = AREA_SCRIPTS[args.area]
        if not script.is_file():
            print(f"error: missing campaign script: {script}", file=sys.stderr)
            return 2
        import subprocess

        return subprocess.run(
            [sys.executable, str(script), "--list"],
            cwd=str(REPO_ROOT),
        ).returncode

    if not args.area:
        parser.print_help()
        return 2

    if args.area not in AREA_SCRIPTS:
        print(f"error: unknown area: {args.area}", file=sys.stderr)
        return 2

    return _run_area(args.area, AREA_SCRIPTS[args.area], args.subcampaign)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(_handle_interrupt()) from None
