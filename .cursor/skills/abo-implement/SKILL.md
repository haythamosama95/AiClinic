---
name: abo-implement
description: >-
  Execute a task range from tasks.md; red tests then code; unit harness per
  range. Workflow passes T00x–T00y. Never commit.
disable-model-invocation: true
---

# ABO — Implement

Spec, plan, `tasks.md` are authoritative. **Implementation adds nothing.** No design docs (gap → stop 1).

**Input:** `$ARGUMENTS` = unit id (`P1.1`) + optional selector: phase number/range/name (`tests`, `implementation`, `verification`, `documentation`) or task range (`T003-T006`). Empty unit id → resolve via paths. No `tasks.md` → run tasks.

Workflow invokes with **task range only** (one subphase bullet).

## Paths

Resolve `specs/<NNN>-*` from unit id or branch (not from `.specify/feature.json` alone):

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-…" \
  .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
```

Parse `FEATURE_DIR`, `AVAILABLE_DOCS`. Read only docs `AVAILABLE_DOCS` lists. Mismatched unit vs `FEATURE_DIR` → stop and report both.

**After resolver:** read amendment; continue.

## Sources (only these)

1. `tasks.md` — order and scope.
2. `plan.md` — Files, Test Layout, Sequencing, Consumes Binding.
3. `spec.md` — Requirements, Test plan, Out of Scope.
4. `06-abo-delivery-plan.md` §2–3: S7, S8, S9.
5. `contracts/`, `data-model.md`, `research.md` if `AVAILABLE_DOCS`; plus Consumes modules.

## Scope

Run only the requested range. Subsections ≤5 tasks belong to their parent phase.

- Empty selector (non-workflow): list phases with ids and `[ ]`/`[X]`, name next unstarted, ask — or `## ESCALATION` if prompt forbids asking.
- Stop at end of in-scope phase; don't spill into the next.
- Out-of-scope: no files, no `[X]`. Range ≠ whole phase.

Examples: `P4.2 phase 2` = phase 2 only; `P4.2 2-3` = phases 2–3; `P3.1 T003-T006` = those tasks only.

### Preconditions

- Dependencies in **Dependencies & Execution Order**: earlier phases `[X]` with files on disk (`[X]` but missing file → stop 5).
- Implementation in scope → Tests phase already `[X]` on disk; no harness before edits; no back-filling tests in an implementation-only run.

## Execution

1. State in-scope task ids.
2. Consumes Binding code present (missing → stop 2).
3. Execute `tasks.md` order; one phase at a time; `[P]` tasks together only if different files.
4. **Tests in range:** after last in-scope test task, run unit harness from Test Layout **once** — new tests fail on assertion (file loads), not missing imports. Report that run.
5. Implement only **Files** paths for in-scope tasks.
6. `[X]` after file on disk; test tasks `[X]` after red run.
7. **Verification** (if in scope): same harness; no earlier suites; don't edit prior units' tests.
8. **Documentation** (if in scope): `quickstart.md` last, after harness green — content per plan **Quickstart** in `abo-plan/SKILL.md`.
9. Report: completed ids, red/fail state, left in scope, next runnable phase.

No `npm ci`/`install` if `node_modules` present. Multi-story range = one pass in task order.

## Prohibitions (spec Out of Scope + S7–S9)

- No Consumes rewrite (S7); later units extend, not rewrite.
- No module unreachable from live entry (S8): route, VendorEntrypoint, `scheduled()`, DO alarm, RPC, pg_cron, Flutter in real shell — except P2.2 / package P2.1 Node+workerd vectors.
- No removing S9 transitional paths owned by later units.
- No libraries/patterns/flags/abstractions plan doesn't name.
- No weaken/skip tests. No later unit's work. No commit.

Violation needed to complete task → stop 1.

## Stop conditions

Only `## ESCALATION`. On stop: remove/revert files this run added that no `[X]` task names.

| # | Trigger |
| --- | --- |
| 1 | Task needs more than spec/plan; prohibition conflict |
| 2 | Consumes missing or would change |
| 3 | Test can't pass without changing spec behaviour |
| 4 | Work beyond task list (extra files/codebase) |
| 5 | `tasks.md` vs tree mismatch |

```markdown
## ESCALATION

**Stop condition:** 1 — task needs something the plan omitted
**Unit:** P1.1
**Task:** T007
**Question:** …
**Should be answered by:** plan.md Files, or spec.md FR-001
**Blocked until:** the plan is amended
```
