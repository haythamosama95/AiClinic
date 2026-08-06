---
name: ai-platform-resolve-review
description: >-
  Resolve every comment in an AI platform slice review document: merge ai/master
  into the slice branch (real merge), fix findings in staged test-first passes,
  update Spec Kit docs, append a resolution record, commit, push, and
  squash-merge to ai/master.
  Use when the user invokes /ai-platform-resolve-review with a review file under
  docs/review/ai-platform-slices/, or asks to handle AI platform review comments.
disable-model-invocation: true
---

# AI Platform — Resolve Review Comments

Handle **every** finding in a slice review report. No comment is deferred, skipped,
or left for a later pass.

**Input:** path to the review document (e.g.
`docs/review/ai-platform-slices/B2-control-plane-enrollment.md`). Resolve from
`$ARGUMENTS` or an `@`-mention. If missing, ask and stop.

## User Input

```text
$ARGUMENTS
```

The first argument is the review file path.

## Key paths

| Document | Path |
| --- | --- |
| Delivery plan (slice table, canonical refs, needs) | `docs/architecture/ai-platform/03-ai-platform-delivery-plan.md` |
| Architecture (read **only** cited sections) | `docs/architecture/ai-platform/01-ai-platform.md` |
| Review index | `docs/review/ai-platform-slices/README.md` |

The user may say `delivery-hase.md`; that means `03-ai-platform-delivery-plan.md`.

---

## Workflow

Copy this checklist and track progress:

```text
Review resolution:
- [ ] 1. Parse slice id, branch, canonical sections from review file
- [ ] 2. Read delivery-plan row + architecture sections only
- [ ] 3. Checkout slice branch; merge ai/master into it (real merge, not squash)
- [ ] 4. Group all review comments into stages
- [ ] 5. For each stage: test first → fix → full suite → Spec Kit docs
- [ ] 6. Append resolution section to review file
- [ ] 7. Commit and push on slice branch
- [ ] 8. Squash-merge slice branch into ai/master; commit and push
```

---

### 1. Parse the review document

Read the review file header. Extract:

- **Slice id** — e.g. `B2` from `# Slice Review Report — B2: …`
- **Branch** — from `**Branch:** \`ai/…\``
- **Spec directory** — from `**Spec:** \`specs/…\``
- **Canonical sections** — from `**Canonical:**` (e.g. `§4.5, §8.1`)

Read every section: Executive Summary, Critical Issues, Bugs, Architectural
Deviations, Missing or Weak Tests, Recommended Improvements. Treat each numbered
item as a comment that **must** be resolved or escalated.

### 2. Scope from the delivery plan and architecture

**Do not read either document in full.**

1. In `03-ai-platform-delivery-plan.md`, locate the slice row in §3.2–§3.9
   (search for `| **<slice-id>** |`). Read only that row and its band intro
   paragraph (the `### 3.N Band …` section it sits under).
2. In `01-ai-platform.md`, read **only** the sections named in the review
   header's `Canonical:` field and the delivery-plan row's `Canonical` column.
   Use the Table of Contents or `^## N\.` / `^### N\.M` headings to jump
   directly to each § section.

These two reads define slice scope. Fixes must stay within them.

### 3. Sync the slice branch

Use a **real merge** of `origin/ai/master` into the slice branch — **not**
`merge --squash`. Squash-merging master into the slice branch does not advance
Git’s merge-base, so step 8’s later `merge --squash` of the slice into
`ai/master` re-applies master’s own history as conflicting add/add and content
changes. A merge commit updates the merge-base so step 8 only carries the review
delta.

```bash
git fetch origin ai/master
git checkout <branch-from-review>
git merge origin/ai/master -m "Merge ai/master into <branch-from-review>"
git push -u origin HEAD
```

If Git reports `Already up to date`, continue without an empty commit; still push
only if the branch needed `-u` setup or local commits were missing on origin.

If the merge conflicts, resolve them (prefer `origin/ai/master` for unrelated
files; keep slice-branch intent only where the conflict is in files this review
must change), finish the merge commit, then push.

Resolve the spec directory:

```bash
.specify/scripts/bash/ai-platform-paths.sh --json --paths-only
```

Confirm `FEATURE_DIR` matches the spec path in the review header.

### 4. Group comments into stages

Before writing any fix, read the **entire** review document and group every
numbered comment (across all sections) into **stages**.

**Grouping rule:** one stage = one or more comments that touch the same logic,
module, or files. A stage may span Critical Issues, Bugs, Missing Tests, and
Recommended Improvements when they share a root cause.

**Coverage rule:** every numbered item appears in exactly one stage. None are
deferred.

Name stages `<slice-id>-R<n>` (e.g. `B2-R1`, `B2-R2`).

For each stage, record:

- Review items covered (by section and number)
- Files / logic affected
- Whether production code, tests only, or Spec Kit docs change

### 5. Resolve each stage (test-first)

For **each stage**, in order:

#### 5a. Escalation gate (before any code)

If resolving a comment would require **changing** `01-ai-platform.md` — new
behaviour, amended contract meaning, new component, or contradiction with a cited
§ section — **stop immediately**. Output an `## ESCALATION` block (see below) and
do not proceed.

Allowed without escalation:

- Implementation fixes within slice scope
- Test additions or corrections
- Spec Kit doc updates (`spec.md`, `plan.md`, `tasks.md`, `contracts/`,
  `quickstart.md`) to reflect the fix
- Contract **extension** per delivery plan §2.3 (new field, case, or test — not
  changed meaning)

Architectural Deviations that say "architecture wins" or require amending
`01-ai-platform.md` are escalation cases unless the review item can be fixed
purely in implementation without contradicting the architecture.

#### 5b. Write the test first

Before changing production code, add or rewrite the test that proves the review
comment is fixed. Follow delivery plan §3.10–§3.11 and the slice spec's test
plan.

- A missing-test comment → add the named case before the handler change.
- A bug comment → add a failing test that reproduces the bug, then fix.
- A recommended improvement that is in scope → encode it as a test assertion.

Do not weaken, skip, or delete tests to go green.

#### 5c. Implement the fix

Fix only what the stage requires. Stay within the slice's canonical sections and
the spec/plan scope. Do not pull work from other slices.

#### 5d. Run the full test suite

From `ai-platform/`:

```bash
npm test
```

All tests must pass before the stage is complete. A prior-slice regression is a
failure — fix it or escalate (stop condition 4 from `ai-platform-implement`).

#### 5e. Update Spec Kit docs

Modify `specs/<NNN>-<name>/` artifacts so they match the implementation:

- `spec.md` — acceptance criteria, edge cases, clarifications if behaviour changed
- `plan.md` — file references, test layout, sequencing notes
- `tasks.md` — only if task descriptions or completion evidence changed
- `contracts/` — only on allowed extension, never meaning change

Do **not** edit `01-ai-platform.md` or `03-ai-platform-delivery-plan.md`.

Repeat 5a–5e for every stage.

### 6. Append resolution to the review document

Append a new top-level section at the end of the review file (after any existing
resolution block, add `## N. Review Resolution` with the next number, or
`## 1. Review Resolution` if none exists):

```markdown
---

## N. Review Resolution

### N.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **<slice>-R1 — short title** | Critical #1; Bugs #2; … | `path/to/file.ts`; … |

### N.2 Test cases created first

For each stage, list the test(s) written **before** the fix:

- **<slice>-R1:** test file, case name/id, what it asserts, and why.

### N.3 Fix implemented

For each stage, describe what changed in production code, tests, and Spec Kit docs.
Note explicitly when no production-code change was needed.

### N.4 Verification

Report the full `ai-platform` suite result (file count, test count, pass/fail).
Name any test files added or modified.
```

Use the resolved example in
`docs/review/ai-platform-slices/A2-diagnostic-envelope.md` §1 as the style
reference.

### 7. Commit and push on the slice branch

Ensure the working tree is clean except for intentional changes. Commit
everything (code, Spec Kit docs, review resolution appendix):

```bash
git add -A
git commit -m "$(cat <<'EOF'
Handling review comments addressed in <review_file_name.md>

EOF
)"
git push origin HEAD
```

Replace `<review_file_name.md>` with the basename only (e.g.
`B2-control-plane-enrollment.md`).

### 8. Squash-merge into ai/master

```bash
git checkout ai/master
git merge --squash <branch-from-review>
git commit -m "$(cat <<'EOF'
Handling review comments addressed in <review_file_name.md>

EOF
)"
git push origin ai/master
```

Report: slice id, branch, stages completed, test count, commit hash on
`ai/master`.

---

## Escalation format

When a comment cannot be fixed without an architecture change, stop all work and
output **only**:

```markdown
## ESCALATION

**Review file:** docs/review/ai-platform-slices/B2-control-plane-enrollment.md
**Stage:** B2-R1
**Review item:** Critical Issues #1
**Conflict:** Fixing operator auth requires a new §4.5 verification scheme not
present in the current implementation or spec scope.
**Should be answered by:** architecture amendment to `01-ai-platform.md` §4.5,
or a revised review scope excluding this item.
**Blocked until:** human decision
```

Do not partially fix other stages after an escalation.

---

## Rules

- **No deferred comments.** "Recommended Improvements" are in scope unless they
  require architecture change (then escalate that item only if it blocks other
  work; otherwise implement what you can and escalate the rest).
- **Tests before fixes.** Never ship a production fix without its preceding test.
- **Full suite every stage.** Not slice-only tests.
- **Architecture is read-only.** Cite it for scope; never edit it in this skill.
- **Delivery plan is read-only.** Slice row is for scope only.
- **One commit message shape** on the resolution commit (step 7) and the
  `ai/master` squash merge (step 8). Step 3 uses the merge message above.
- **Real merge in step 3; squash only in step 8.** Never `merge --squash`
  `ai/master` into the slice branch — that breaks merge-base for step 8.
- **Push after every commit** — slice-branch sync (step 3, when a merge commit
  was created), resolution commit (step 7), and `ai/master` squash merge
  (step 8). Skip push only when step 3 was already up to date and tracking is
  set.
- **Do not create PRs** unless the user asks separately.

## Stop conditions

In addition to escalation, stop and report if:

1. The review file has no parseable slice id or branch.
2. The slice branch does not exist locally or on `origin`.
3. `specs/<NNN>-<name>/` cannot be resolved for the slice.
4. A fix would violate delivery plan §6.4 prohibitions (see
   `ai-platform-implement` skill).
5. The full test suite cannot be made green without changing architecture
   meaning.
