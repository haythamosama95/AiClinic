"""Link check. Usage: python3 -I check_links.py [data-journey-dir]"""
import importlib.util
import re
import sys
from pathlib import Path
from urllib.parse import unquote

_spec = importlib.util.spec_from_file_location("_common", Path(__file__).resolve().parent / "_common.py")
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)

EXTERNAL = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|//)", re.I)


def check_file(path, root, problems, cache):
    text = C.read(path)
    rel = path.relative_to(root)
    for n, line, fence in C.iter_lines(text):
        if fence is not None:
            continue
        line = re.sub(r"`[^`]*`", "", line)
        for _t, target in C.LINK_RE.findall(line):
            if not target or EXTERNAL.match(target):
                continue
            file_part, _, frag = target.partition("#")
            dest = path if not file_part else (path.parent / unquote(file_part))
            try:
                dest = dest.resolve()
            except OSError:
                dest = None
            if dest is None or not dest.exists():
                problems.append("%s:%d: broken link target '%s'" % (rel, n, target))
                continue
            if frag and dest.is_file() and dest.suffix == ".md":
                if dest not in cache:
                    cache[dest] = C.anchors(C.read(dest))
                if unquote(frag).lower() not in cache[dest]:
                    problems.append("%s:%d: anchor '#%s' not found in %s" % (rel, n, frag, dest.name))


def check_nav(chapters, root, problems):
    for i, ch in enumerate(chapters):
        lines = C.read(ch).splitlines()
        if len(lines) < 2 or not lines[1].strip():
            problems.append("%s:2: second line must be the Previous | Next line" % ch.name)
            continue
        nav = lines[1]
        links = C.LINK_RE.findall(nav)
        want = {"previous": chapters[i - 1].name if i > 0 else None,
                "next": chapters[i + 1].name if i + 1 < len(chapters) else None}
        for key, label in (("previous", r"prev"), ("next", r"next")):
            if not re.search(label, nav, re.I):
                problems.append("%s:2: no '%s' entry on the navigation line" % (ch.name, key.capitalize()))
                continue
            mine = [t for txt, t in links if re.search(label, txt, re.I)]
            if not mine:
                if want[key] is not None:
                    problems.append("%s:2: '%s' has no link" % (ch.name, key.capitalize()))
                continue
            got = Path(mine[0].split("#")[0]).name
            if want[key] is not None and got != want[key]:
                problems.append("%s:2: '%s' link goes to %s but reading order says %s"
                                % (ch.name, key.capitalize(), got, want[key]))


def main():
    root = C.get_root(sys.argv)
    problems, cache = [], {}
    chapters = C.chapter_files(root)
    files = list(chapters) + C.reference_files(root)
    for name in ("00-index.md", "GLOSSARY.md", "METAPHORS.md"):
        if (root / name).is_file():
            files.append(root / name)
    for f in files:
        check_file(f, root, problems, cache)
    check_nav(chapters, root, problems)
    return C.finish(problems, "check_links")


if __name__ == "__main__":
    sys.exit(main())
