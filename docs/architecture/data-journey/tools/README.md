# Data-journey check tools

Python standard library only. Run each from anywhere, with an optional
argument naming the data-journey folder (default: the parent of `tools/`):

    python3 -I tools/lint_terms.py [dir]
    python3 -I tools/check_coverage.py [dir]
    python3 -I tools/check_links.py [dir]
    python3 -I tools/check_banned.py [dir]

Each prints one line per problem and exits 1; a clean run prints "clean" and
exits 0. Missing or empty chapters, glossary, inventory or index are tolerated.

## Conventions

- Chapters are `NN-*.md` in the folder. Reading order is the order of links in
  `00-index.md`; chapters not linked there follow, sorted by name.
- Chapter layout: line 1 title, line 2 `[Previous: ...](a.md) | [Next: ...](b.md)`
  (first chapter may omit the Previous link, last may omit Next), and within
  the first 10 lines a group declaration: `<!-- group: G03 -->` (several:
  `<!-- group: G03, G09 -->`).
- "Words you'll meet here" is a heading containing that phrase; its section
  runs to the next heading of the same or higher level.

## lint_terms.py

Reads GLOSSARY.md rows `Term | Also written as | Home chapter | Definition`.
Home chapter may be a link, a number (`7`, `chapter 7`) or a file name.
"Also written as" is comma/semicolon separated. Matching is case-insensitive
on whole words. A term used in a chapter that comes before its home chapter is
reported unless that chapter (a) links to the home chapter file anywhere, or
(b) lists the term (or a variant) in its Words box. Title and nav lines are
ignored. Unresolvable home chapters are reported.

## check_coverage.py

Reads INVENTORY.md rows `ID | Item | Kind | Source area | Assigned group | Notes`
(IDs like `ABO-ROUTE-001`). Item name must appear (case-insensitive, whole
word, backticks ignored; a leading HTTP method is optional) in a chapter
declaring the assigned group (comma-separated groups: any one suffices), or in
any `reference/*.md`. Chapters without a group comment are reported.

## check_links.py

Checks relative links (files and `#anchors`, GitHub-style slugs) in chapters,
reference files, 00-index, GLOSSARY and METAPHORS, and that every chapter's
line 2 has Previous and Next links pointing at the neighbouring chapters.

## check_banned.py

Reports code fences other than `mermaid`/`ascii`/`text`/`txt`/`diagram`
(bare fences too), file paths and file names with code extensions,
`file:line` and "line N" references, and mentions of tests, specs files or
probes (whole words, so "latest"/"contest" pass). Add `<!-- banned-ok -->`
to a line to suppress a deliberate false positive.
