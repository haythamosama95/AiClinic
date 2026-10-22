"""Term-first lint. Usage: python3 -I lint_terms.py [data-journey-dir]"""
import importlib.util
import re
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location("_common", Path(__file__).resolve().parent / "_common.py")
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)

BOX_RE = re.compile(r"words\s+you.{0,3}ll\s+meet\s+here", re.I)


def clean(s):
    return re.sub(r"[`*]", "", s).strip()


def load_glossary(root, chapters, problems):
    by_num = {}
    for i, p in enumerate(chapters):
        m = re.match(r"(\d+)-", p.name)
        if m:
            by_num.setdefault(int(m.group(1)), p.name)
    pos = {p.name: i for i, p in enumerate(chapters)}
    terms = []
    for n, cells in C.table_rows(C.read(root / "GLOSSARY.md")):
        if len(cells) < 3 or cells[0].lower().strip("* ") == "term":
            continue
        term = clean(cells[0])
        if not term:
            continue
        variants = {term}
        for v in re.split(r"[;,]", cells[1] if len(cells) > 1 else ""):
            v = clean(v)
            if v and v not in "-—–":
                variants.add(v)
        home = cells[2]
        fname = None
        m = C.LINK_RE.search(home)
        if m:
            fname = Path(m.group(2).split("#")[0]).name
        else:
            m = re.search(r"\d{2,3}-[\w\-]+(?:\.md)?", home)
            if m:
                fname = m.group(0) if m.group(0).endswith(".md") else m.group(0) + ".md"
            else:
                m = re.search(r"\b(\d{1,3})\b", home)
                if m:
                    fname = by_num.get(int(m.group(1)))
        if not fname or not (root / fname).is_file():
            problems.append("GLOSSARY.md:%d: term '%s': home chapter not resolvable from '%s'" % (n, term, home))
            continue
        if fname not in pos:
            continue  # home is not a narrative chapter (e.g. reference file): no ordering constraint
        terms.append((term, variants, fname, pos[fname]))
    return terms


def split_box(text):
    """Return (body_lines [(n,line)], box_text)."""
    body, box, in_box, level = [], [], False, 0
    for n, line, fence in C.iter_lines(text):
        if fence is None:
            m = C.HEADING_RE.match(line)
            if m:
                if in_box and len(m.group(1)) <= level:
                    in_box = False
                if BOX_RE.search(m.group(2)):
                    in_box, level = True, len(m.group(1))
                    continue
        if in_box:
            box.append(line)
        elif fence is None or fence not in ("",):
            body.append((n, line))
        else:
            body.append((n, line))
    return body, "\n".join(box)


def main():
    root = C.get_root(sys.argv)
    chapters = C.chapter_files(root)
    problems = []
    terms = load_glossary(root, chapters, problems)
    for i, ch in enumerate(chapters):
        text = C.read(ch)
        body, box = split_box(text)
        linked = {Path(t.split("#")[0]).name for _x, t in C.LINK_RE.findall(text)}
        box_l = box.lower()
        for term, variants, home, hpos in terms:
            if hpos <= i:
                continue
            if home in linked:
                continue
            pats = [re.compile(r"(?<!\w)" + re.escape(v) + r"(?!\w)", re.I) for v in variants]
            if any(p.search(box) for p in pats):
                continue
            for n, line in body:
                if n <= 2:
                    continue  # title and Previous/Next line
                stripped = re.sub(r"\]\([^)]*\)", "]", line)
                if any(p.search(stripped) for p in pats):
                    problems.append("%s:%d: term '%s' used before its home chapter %s (no link, not in 'Words you'll meet here')"
                                    % (ch.name, n, term, home))
                    break
    return C.finish(problems, "lint_terms")


if __name__ == "__main__":
    sys.exit(main())
