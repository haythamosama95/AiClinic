"""Shared curses theme and campaign tree helpers."""

from __future__ import annotations

import curses
from dataclasses import dataclass
from typing import Literal

from harness.campaign_tree import _children, root_subcampaign_ids

SelectionState = Literal["none", "partial", "all"]
RunStatus = Literal["waiting", "running", "finished", "failed"]


class Theme:
    """Color pairs for campaign TUI (call ``apply`` once per session)."""

    HEADER = 1
    ACCENT = 2
    SUCCESS = 3
    WARNING = 4
    DANGER = 5
    MUTED = 6
    BORDER = 7
    SELECTED = 8
    RUNNING = 9

    @classmethod
    def apply(cls) -> None:
        if not curses.has_colors():
            return
        curses.start_color()
        try:
            curses.use_default_colors()
        except curses.error:
            pass
        curses.init_pair(cls.HEADER, curses.COLOR_CYAN, -1)
        curses.init_pair(cls.ACCENT, curses.COLOR_MAGENTA, -1)
        curses.init_pair(cls.SUCCESS, curses.COLOR_GREEN, -1)
        curses.init_pair(cls.WARNING, curses.COLOR_YELLOW, -1)
        curses.init_pair(cls.DANGER, curses.COLOR_RED, -1)
        curses.init_pair(cls.MUTED, curses.COLOR_WHITE, -1)
        curses.init_pair(cls.BORDER, curses.COLOR_BLUE, -1)
        curses.init_pair(cls.SELECTED, curses.COLOR_CYAN, -1)
        curses.init_pair(cls.RUNNING, curses.COLOR_YELLOW, -1)

    @classmethod
    def attr(cls, pair: int, *, bold: bool = False) -> int:
        bits = curses.color_pair(pair)
        if bold:
            bits |= curses.A_BOLD
        return bits


@dataclass(frozen=True)
class TreeLine:
    area: str
    sub_id: str
    depth: int
    has_children: bool
    expanded: bool
    prefix: str


def _sub_ids(area: str, area_subcampaigns: dict[str, list[str]]) -> set[str]:
    return set(area_subcampaigns.get(area, []))


def _subtree(area: str, node: str, ids: set[str]) -> list[str]:
    out = [node]
    for child in _children(area, node, ids):
        out.extend(_subtree(area, child, ids))
    return out


def selection_state(
    selected: set[tuple[str, str]],
    area: str,
    sub_ids: list[str],
) -> SelectionState:
    if not sub_ids:
        return "none"
    hits = sum(1 for s in sub_ids if (area, s) in selected)
    if hits == 0:
        return "none"
    if hits == len(sub_ids):
        return "all"
    return "partial"


def check_char(state: SelectionState) -> str:
    if state == "all":
        return "✓"
    if state == "partial":
        return "◐"
    return "·"


def visible_tree_lines(
    area: str,
    area_subcampaigns: dict[str, list[str]],
    expanded: set[str],
) -> list[TreeLine]:
    ids = _sub_ids(area, area_subcampaigns)
    roots = root_subcampaign_ids(area, sorted(ids))
    lines: list[TreeLine] = []

    def walk(node: str, depth: int, anc_continues: list[bool]) -> None:
        children = _children(area, node, ids)
        has_children = bool(children)
        is_expanded = node in expanded
        if depth == 0:
            prefix = ""
        else:
            prefix = ""
            for cont in anc_continues[:-1]:
                prefix += "│  " if cont else "   "
            prefix += "└─ " if not anc_continues[-1] else "├─ "
        lines.append(
            TreeLine(
                area=area,
                sub_id=node,
                depth=depth,
                has_children=has_children,
                expanded=is_expanded,
                prefix=prefix,
            )
        )
        if has_children and is_expanded:
            for index, child in enumerate(children):
                walk(
                    child,
                    depth + 1,
                    anc_continues + [index < len(children) - 1],
                )

    for index, root in enumerate(roots):
        walk(root, 0, [index < len(roots) - 1])

    return lines


def _acs_hline(stdscr: curses.window, y: int, x: int, length: int, attr: int) -> None:
    if length <= 0:
        return
    ch = curses.ACS_HLINE
    for offset in range(length):
        stdscr.addch(y, x + offset, ch, attr)


def _acs_vline(stdscr: curses.window, x: int, y: int, length: int, attr: int) -> None:
    if length <= 0:
        return
    ch = curses.ACS_VLINE
    for offset in range(length):
        stdscr.addch(y + offset, x, ch, attr)


def draw_panel_border(
    stdscr: curses.window,
    y0: int,
    x0: int,
    height: int,
    width: int,
    title: str,
    *,
    focused: bool,
) -> None:
    if height < 2 or width < 4:
        return
    y1 = y0 + height - 1
    x1 = x0 + width - 1
    border_attr = Theme.attr(Theme.BORDER, bold=focused)
    title_attr = Theme.attr(Theme.HEADER if focused else Theme.MUTED, bold=True)
    stdscr.addch(y0, x0, curses.ACS_ULCORNER, border_attr)
    stdscr.addch(y0, x1, curses.ACS_URCORNER, border_attr)
    stdscr.addch(y1, x0, curses.ACS_LLCORNER, border_attr)
    stdscr.addch(y1, x1, curses.ACS_LRCORNER, border_attr)
    _acs_hline(stdscr, y0, x0 + 1, width - 2, border_attr)
    _acs_hline(stdscr, y1, x0 + 1, width - 2, border_attr)
    _acs_vline(stdscr, x0, y0 + 1, height - 2, border_attr)
    _acs_vline(stdscr, x1, y0 + 1, height - 2, border_attr)
    label = f" {title} "
    tx = x0 + max(1, (width - len(label)) // 2)
    stdscr.addnstr(y0, tx, label, width - 2, title_attr)


def aggregate_run_status(children: list[RunStatus]) -> RunStatus:
    if not children:
        return "waiting"
    if any(s == "running" for s in children):
        return "running"
    if any(s == "failed" for s in children):
        return "failed"
    if all(s == "finished" for s in children):
        return "finished"
    if any(s == "finished" for s in children):
        return "running"
    return "waiting"


def status_glyph(status: RunStatus) -> str:
    return {
        "waiting": "○",
        "running": "◉",
        "finished": "✓",
        "failed": "✗",
    }[status]


def status_color_pair(status: RunStatus) -> int:
    if status == "waiting":
        return Theme.MUTED
    if status == "running":
        return Theme.RUNNING
    if status == "finished":
        return Theme.SUCCESS
    return Theme.DANGER


@dataclass
class StatusTreeNode:
    area: str
    sub_id: str
    depth: int
    prefix: str
    runnable: bool
    children: list[StatusTreeNode]

    def flattened(self) -> list[StatusTreeNode]:
        out: list[StatusTreeNode] = [self]
        for child in self.children:
            out.extend(child.flattened())
        return out


def build_status_forest(
    picked: list[tuple[str, str]],
    area_subcampaigns: dict[str, list[str]],
) -> list[StatusTreeNode]:
    picked_set = set(picked)
    by_area: dict[str, set[str]] = {}
    for area, sub_id in picked_set:
        by_area.setdefault(area, set()).add(sub_id)

    def include_node(area: str, node: str) -> bool:
        ids = _sub_ids(area, area_subcampaigns)
        return any((area, s) in picked_set for s in _subtree(area, node, ids))

    def build_subtree(area: str, node: str, depth: int, anc_continues: list[bool]) -> StatusTreeNode | None:
        ids = _sub_ids(area, area_subcampaigns)
        if not include_node(area, node):
            return None
        children_ids = _children(area, node, ids)
        child_nodes: list[StatusTreeNode] = []
        for index, child in enumerate(children_ids):
            built = build_subtree(
                area,
                child,
                depth + 1,
                anc_continues + [index < len(children_ids) - 1],
            )
            if built is not None:
                child_nodes.append(built)
        if depth == 0:
            prefix = ""
        else:
            prefix = ""
            for cont in anc_continues[:-1]:
                prefix += "│  " if cont else "   "
            prefix += "└─ " if not anc_continues[-1] else "├─ "
        return StatusTreeNode(
            area=area,
            sub_id=node,
            depth=depth,
            prefix=prefix,
            runnable=(area, node) in picked_set,
            children=child_nodes,
        )

    forest: list[StatusTreeNode] = []
    for area in sorted(by_area.keys()):
        ids = _sub_ids(area, area_subcampaigns)
        roots = root_subcampaign_ids(area, sorted(ids))
        for index, root in enumerate(roots):
            node = build_subtree(area, root, 0, [index < len(roots) - 1])
            if node is not None:
                forest.append(node)
    return forest


def node_run_status(
    node: StatusTreeNode,
    status_by_key: dict[tuple[str, str], RunStatus],
) -> RunStatus:
    if node.runnable:
        return status_by_key.get((node.area, node.sub_id), "waiting")
    child_statuses = [node_run_status(c, status_by_key) for c in node.children]
    return aggregate_run_status(child_statuses)
