"""Terminal UI to pick test campaigns (areas + expandable tree)."""

from __future__ import annotations

import curses
import sys
from typing import Literal

from harness.curses_campaign_ui import (
    Theme,
    TreeLine,
    check_char,
    draw_panel_border,
    selection_state,
    visible_tree_lines,
)
from harness.campaign_selection import sub_ids as _sub_ids, toggle_area as _toggle_area, toggle_subtree as _toggle_sub

AREA_COL_WIDTH = 24
FocusPane = Literal["left", "right"]


def _area_check(area: str, selected: set[tuple[str, str]], area_subcampaigns: dict[str, list[str]]) -> str:
    return check_char(selection_state(selected, area, sorted(_sub_ids(area, area_subcampaigns))))


def _draw_picker(
    stdscr: curses.window,
    areas: list[str],
    area_index: int,
    focus: FocusPane,
    tree_lines: list[TreeLine],
    tree_index: int,
    tree_scroll: int,
    selected: set[tuple[str, str]],
    area_subcampaigns: dict[str, list[str]],
    active_area: str,
) -> int:
    height, width = stdscr.getmaxyx()
    if height < 8 or width < 40:
        stdscr.erase()
        stdscr.refresh()
        return tree_scroll

    stdscr.erase()
    help_attr = Theme.attr(Theme.MUTED)
    stdscr.addnstr(
        0,
        1,
        "↑↓ move   → expand / panel   ← collapse / panel   Space select   Enter run   Esc quit",
        width - 2,
        help_attr,
    )

    top = 2
    bottom = height - 2
    panel_h = bottom - top
    left_w = min(AREA_COL_WIDTH, max(16, width // 3))
    right_x = left_w + 1
    right_w = width - right_x

    draw_panel_border(stdscr, top, 0, panel_h, left_w, "Areas", focused=focus == "left")
    draw_panel_border(
        stdscr,
        top,
        right_x,
        panel_h,
        right_w,
        f"Subcampaigns · {active_area}",
        focused=focus == "right",
    )

    list_top = top + 1
    list_bottom = bottom - 1
    list_h = list_bottom - list_top

    for row in range(list_h):
        idx = row
        if idx >= len(areas):
            break
        area = areas[idx]
        mark = _area_check(area, selected, area_subcampaigns)
        label = f" {mark} {area}"
        attr = Theme.attr(Theme.ACCENT) if area == active_area else Theme.attr(Theme.MUTED)
        if focus == "left" and idx == area_index:
            attr |= curses.A_REVERSE
        stdscr.addnstr(list_top + row, 2, label, left_w - 4, attr)

    if tree_lines and list_h > 0:
        tree_index = max(0, min(tree_index, len(tree_lines) - 1))
        if tree_index < tree_scroll:
            tree_scroll = tree_index
        elif tree_index >= tree_scroll + list_h:
            tree_scroll = tree_index - list_h + 1

        for row in range(list_h):
            line_i = tree_scroll + row
            if line_i >= len(tree_lines):
                break
            line = tree_lines[line_i]
            ids = _sub_ids(line.area, area_subcampaigns)
            from harness.campaign_selection import subtree as _subtree

            mark = check_char(
                selection_state(selected, line.area, _subtree(line.area, line.sub_id, ids))
            )
            twist = "▾" if line.expanded else "▸" if line.has_children else " "
            label = f" {line.prefix}{twist}{mark} {line.sub_id}"
            attr = Theme.attr(Theme.SELECTED) if (line.area, line.sub_id) in selected else 0
            if focus == "right" and line_i == tree_index:
                attr |= curses.A_REVERSE
            stdscr.addnstr(list_top + row, right_x + 2, label, right_w - 4, attr)

    footer = f"  {len(selected)} subcampaign(s) selected"
    stdscr.addnstr(height - 1, 0, footer, width - 1, Theme.attr(Theme.HEADER, bold=True))
    stdscr.refresh()
    return tree_scroll


def _picker_main(
    stdscr: curses.window,
    area_subcampaigns: dict[str, list[str]],
) -> list[tuple[str, str]]:
    curses.curs_set(0)
    stdscr.keypad(True)
    Theme.apply()

    areas = sorted(area_subcampaigns.keys())
    area_index = 0
    focus: FocusPane = "left"
    expanded_by_area: dict[str, set[str]] = {a: set() for a in areas}
    tree_index = 0
    tree_scroll = 0
    selected: set[tuple[str, str]] = set()

    while True:
        active_area = areas[area_index]
        tree_lines = visible_tree_lines(
            active_area,
            area_subcampaigns,
            expanded_by_area[active_area],
        )
        if tree_lines and tree_index >= len(tree_lines):
            tree_index = len(tree_lines) - 1
        tree_scroll = _draw_picker(
            stdscr,
            areas,
            area_index,
            focus,
            tree_lines,
            tree_index,
            tree_scroll,
            selected,
            area_subcampaigns,
            active_area,
        )

        try:
            key = stdscr.getch()
        except curses.error:
            continue

        if key in (curses.KEY_UP, ord("k")):
            if focus == "left":
                area_index = (area_index - 1) % len(areas)
                tree_index = 0
                tree_scroll = 0
            elif tree_lines:
                tree_index = (tree_index - 1) % len(tree_lines)
        elif key in (curses.KEY_DOWN, ord("j")):
            if focus == "left":
                area_index = (area_index + 1) % len(areas)
                tree_index = 0
                tree_scroll = 0
            elif tree_lines:
                tree_index = (tree_index + 1) % len(tree_lines)
        elif key in (curses.KEY_RIGHT, ord("l")):
            if focus == "left":
                focus = "right"
            elif tree_lines:
                line = tree_lines[tree_index]
                if line.has_children:
                    expanded_by_area[active_area].add(line.sub_id)
        elif key in (curses.KEY_LEFT, ord("h")):
            if focus == "right" and tree_lines:
                line = tree_lines[tree_index]
                if line.expanded:
                    expanded_by_area[active_area].discard(line.sub_id)
                else:
                    focus = "left"
            elif focus == "right":
                focus = "left"
        elif key == ord(" "):
            if focus == "left":
                _toggle_area(areas[area_index], selected, area_subcampaigns)
            elif tree_lines:
                line = tree_lines[tree_index]
                _toggle_sub(line.area, line.sub_id, selected, area_subcampaigns)
        elif key in (curses.KEY_ENTER, 10, 13):
            return sorted(selected)
        elif key in (27, ord("q"), ord("Q")):
            return []


def pick_campaigns(area_subcampaigns: dict[str, list[str]]) -> list[tuple[str, str]]:
    """Multi-select picker; returns (area, subcampaign) pairs to run."""
    if not area_subcampaigns:
        return []
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("error: interactive picker requires a TTY", file=sys.stderr)
        return []
    try:
        return curses.wrapper(_picker_main, area_subcampaigns)
    except curses.error as exc:
        print(f"error: terminal UI failed: {exc}", file=sys.stderr)
        return []
