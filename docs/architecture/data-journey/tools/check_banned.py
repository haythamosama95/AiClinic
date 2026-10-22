"""Banned-content check. Usage: python3 -I check_banned.py [data-journey-dir]
Suppress a false positive on one line by adding <!-- banned-ok --> to it."""
import importlib.util
import re
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location("_common", Path(__file__).resolve().parent / "_common.py")
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)

ALLOWED_FENCES = {"mermaid", "ascii", "text", "txt", "diagram"}
EXT = r"(?:dart|ts|tsx|js|mjs|cjs|py|sql|toml|ya?ml|sh|jsonc?|md|html|css|rs|go|kt|swift|lock|env|conf)"
PATH_RES = [
    re.compile(r"(?<![\w:/])(?:\.{0,2}/)?[\w.\-@]+(?:/[\w.\-@]+)+\." + EXT + r"(?![\w])"),
    re.compile(r"(?<![\w/.])(?:abo|ai-platform|backend|frontend|supabase|lib|src|docs|specs|migrations|test)/[\w.\-]+(?:/[\w.\-]+)*"),
    re.compile(r"(?<![\w/.\-])[\w\-]+\." + EXT + r"(?![\w/])"),
]
LINE_RES = [
    re.compile(r"[\w./\-]+\.\w+:\d+(?::\d+)?\b"),
    re.compile(r"\bL\d+(?:-L?\d+)?\b(?=\W|$)"),
    re.compile(r"\blines?\s+\d+(?:\s*[-\u2013]\s*\d+)?\b", re.I),
]
TEST_RE = re.compile(r"\b(?:tests?|testing|tested|unit[- ]tests?|test[- ]suite|spec[- ]files?|specs?\.?(?:ts|js|dart)|probes?|probing|test[- ]map)\b", re.I)
URL_RE = re.compile(r"https?://\S+")


def strip_link_urls(line):
    line = re.sub(r"\]\([^)]*\)", "]", line)
    return URL_RE.sub("", line)


def check(path, root, problems):
    rel = path.relative_to(root)
    text = C.read(path)
    prev = None
    for n, line, fence in C.iter_lines(text):
        if "banned-ok" in line:
            continue
        m = C.FENCE_RE.match(line)
        opening = fence is not None and prev is None and m
        prev = fence
        if opening:
            if fence not in ALLOWED_FENCES:
                problems.append("%s:%d: %s code fence (only mermaid/ascii/text diagram fences allowed)"
                                % (rel, n, "bare" if fence == "" else "'%s'" % fence))
            continue
        if fence is not None and m:
            continue
        probe = strip_link_urls(line)
        for r in PATH_RES:
            mm = r.search(probe)
            if mm:
                problems.append("%s:%d: file path or file name '%s'" % (rel, n, mm.group(0)))
                break
        for r in LINE_RES:
            mm = r.search(probe)
            if mm:
                problems.append("%s:%d: line reference '%s'" % (rel, n, mm.group(0)))
                break
        mm = TEST_RE.search(probe)
        if mm:
            problems.append("%s:%d: mention of tests/probes '%s'" % (rel, n, mm.group(0)))


def main():
    root = C.get_root(sys.argv)
    problems = []
    files = list(C.chapter_files(root)) + C.reference_files(root)
    for name in ("00-index.md", "GLOSSARY.md", "METAPHORS.md"):
        if (root / name).is_file():
            files.append(root / name)
    for f in files:
        check(f, root, problems)
    return C.finish(problems, "check_banned")


if __name__ == "__main__":
    sys.exit(main())
