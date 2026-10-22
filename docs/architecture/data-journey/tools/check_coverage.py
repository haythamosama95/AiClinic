"""Coverage check. Usage: python3 -I check_coverage.py [data-journey-dir]"""
import importlib.util
import re
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location("_common", Path(__file__).resolve().parent / "_common.py")
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)

ID_RE = re.compile(r"^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$")
METHOD_RE = re.compile(r"^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+", re.I)


def norm(s):
    return re.sub(r"\s+", " ", s.replace("`", "")).strip().lower()


def candidates(name):
    n = norm(name)
    out = {n}
    out.add(METHOD_RE.sub("", n))
    return [c for c in out if c]


def present(cands, text):
    for c in cands:
        if re.search(r"(?<![\w])" + re.escape(c) + r"(?![\w])", text):
            return True
    return False


def main():
    root = C.get_root(sys.argv)
    problems = []
    inv = root / "INVENTORY.md"
    if not inv.is_file():
        return C.finish(problems, "check_coverage (no INVENTORY.md; nothing to check)")
    group_text, ref_text = {}, ""
    for ch in C.chapter_files(root):
        t = C.read(ch)
        gs = C.groups_of(t)
        if not gs:
            problems.append("%s: no '<!-- group: Gxx -->' comment in the first 10 lines" % ch.name)
        for g in gs:
            group_text[g] = group_text.get(g, "") + "\n" + norm(t)
    for rf in C.reference_files(root):
        ref_text += "\n" + norm(C.read(rf))
    for n, cells in C.table_rows(C.read(inv)):
        if len(cells) < 5 or not ID_RE.match(cells[0].replace("`", "")):
            continue
        iid, item, groups = cells[0].replace("`", ""), cells[1], re.findall(r"G\d+", cells[4], re.I)
        if not item.strip():
            continue
        if not groups:
            problems.append("INVENTORY.md:%d: %s '%s': no assigned group" % (n, iid, item))
            continue
        cands = candidates(item)
        if present(cands, ref_text):
            continue
        if not any(present(cands, group_text.get(g.upper(), "")) for g in groups):
            problems.append("INVENTORY.md:%d: %s '%s' not found in any chapter of group(s) %s or in reference/"
                            % (n, iid, item, ",".join(g.upper() for g in groups)))
    return C.finish(problems, "check_coverage")


if __name__ == "__main__":
    sys.exit(main())
