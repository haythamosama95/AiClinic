"""Shared helpers for the data-journey check scripts (standard library only)."""
import re
import sys
from pathlib import Path

NON_CHAPTER = {"PLAN.md", "STATUS.md", "INVENTORY.md", "TEMPLATE.md",
               "METAPHORS.md", "GLOSSARY.md", "00-index.md", "README.md"}
CHAPTER_RE = re.compile(r"^\d{2,3}-.+\.md$")
LINK_RE = re.compile(r"(?<!!)\[([^\]]*)\]\(([^)\s]*)(?:\s+\"[^\"]*\")?\)")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
GROUP_RE = re.compile(r"<!--\s*group:\s*([^>]*?)-->", re.I)


def get_root(argv):
    if len(argv) > 1:
        return Path(argv[1]).resolve()
    return Path(__file__).resolve().parent.parent


def read(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def iter_lines(text):
    """Yield (lineno, line, fence) where fence is None outside fenced blocks,
    else the fence info string (lower-case, '' when bare). Fence delimiter
    lines are yielded too, with fence set."""
    marker = None
    info = ""
    for n, line in enumerate(text.splitlines(), 1):
        m = FENCE_RE.match(line)
        if marker is None:
            if m:
                marker = m.group(1)
                info = m.group(2).strip().split(" ")[0].lower() if m.group(2).strip() else ""
                yield n, line, info
                continue
            yield n, line, None
        else:
            if m and m.group(1)[0] == marker[0] and len(m.group(1)) >= len(marker) \
                    and not m.group(2).strip():
                marker = None
                yield n, line, info
                continue
            yield n, line, info


def chapter_files(root):
    """Chapters in reading order: links in 00-index.md first (in order),
    then any other NN-*.md files sorted by name."""
    root = Path(root)
    ordered, seen = [], set()
    for _t, target in LINK_RE.findall(read(root / "00-index.md")):
        target = target.split("#")[0]
        name = Path(target).name
        if "/" in target.strip("./") and not target.startswith("./"):
            continue
        if CHAPTER_RE.match(name) and name not in NON_CHAPTER and name not in seen \
                and (root / name).is_file():
            ordered.append(root / name)
            seen.add(name)
    if root.is_dir():
        for p in sorted(root.glob("*.md")):
            if CHAPTER_RE.match(p.name) and p.name not in NON_CHAPTER and p.name not in seen:
                ordered.append(p)
                seen.add(p.name)
    return ordered


def reference_files(root):
    d = Path(root) / "reference"
    return sorted(d.glob("*.md")) if d.is_dir() else []


def groups_of(text):
    head = "\n".join(text.splitlines()[:10])
    out = []
    for m in GROUP_RE.finditer(head):
        out += re.findall(r"G\d+", m.group(1), re.I)
    return [g.upper() for g in out]


def table_rows(text):
    """Yield (lineno, [cells]) for markdown table body rows (skips separators)."""
    for n, line, fence in iter_lines(text):
        if fence is not None:
            continue
        s = line.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c) or c == "" for c in cells):
            continue
        yield n, cells


def slug(heading):
    h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    h = re.sub(r"[`*_~]", "", h).strip().lower()
    h = re.sub(r"[^\w\- ]", "", h)
    return h.replace(" ", "-")


def anchors(text):
    seen, out = {}, set()
    for _n, line, fence in iter_lines(text):
        if fence is not None:
            continue
        m = HEADING_RE.match(line)
        if m:
            s = slug(m.group(2))
            k = seen.get(s, 0)
            out.add(s if k == 0 else "%s-%d" % (s, k))
            seen[s] = k + 1
    return out


def finish(problems, what):
    for p in problems:
        print(p)
    if problems:
        print("\n%s: %d problem(s)" % (what, len(problems)))
        return 1
    print("%s: clean" % what)
    return 0
