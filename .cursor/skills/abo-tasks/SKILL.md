---
name: abo-tasks
description: Task out an ABO delivery slice (spec + plan), one task per §3.12 floor test plus implementation, capped at 25. Band verification matrix rows are excluded — use abo-verify. Use when the user runs abo-tasks.
disable-model-invocation: true
---

# ABO — Task Out a Slice

The spec and plan are authoritative. **Tasks add nothing.**

**Input:** `specs/<NNN>-<name>/` with `spec.md` and `plan.md`. If `plan.md` is missing, stop.

## Subagent models

Stage owner under `/abo-workflow`: **Grok 4.7 High** (`model: "grok-4.7-high"`). `## ESCALATION` →
**Kimi K3 High** (`model: "kimi-k3-high"`).

## Prerequisites

```bash
.specify/scripts/bash/abo-paths.sh --json
```

```bash
SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR" .specify/scripts/bash/setup-tasks.sh --json
```

## Sources

1. `spec.md` and `plan.md` (Clarifications are non-normative).
2. `docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` §3.12 and §5.
3. Tasks template from `setup-tasks.sh`.
4. `.specify/templates/abo-quickstart-template.md`.

Do not read the full architecture at this phase.

## Critical split — slice tasks vs band verification

| Work | Spec Kit (`tasks.md`) | `/abo-verify` |
| --- | --- | --- |
| §3.12 per-slice test floor | **Yes** — one task per named floor case in the spec Test plan | No |
| Band matrix §3.2.1–§3.10.1 (`M1-V1`, `Q-E3`, `T-X4`, …) | **No** — never task these | **Yes** — implement directly, parallelized |
| Master chain §3.13 (`MC-01`…) | No | `/abo-verify --chain` or band `x-e2e` rows as documented |

If `tasks.md` would include a row from a band verification table, **stop** — that is a process
violation, not an over-cap slice.

## Overrides

Same as ai-platform-tasks: mandatory tests, one story, no Foundational/Polish, 25-task cap — but the
**Tests** phase includes **only §3.12 floor cases**, not band `-V`/`-E`/`-X` ids.

## Phases

1. **Setup** — only if the plan requires scaffold files first.
2. **Tests** — one `[P]` task per §3.12 floor case where files differ; red-first.
3. **Implementation** — one task per plan **Files** unit; **`[P]` wherever files do not overlap**.
4. **Verification** — **slice floor only**: run the tests from phase 2 plus prior-slice suites per
   §3.11 (checkpoints need all prior suites green). **Do not** implement band matrix rows here.
5. **Documentation** — `quickstart.md` via `abo-quickstart-template.md`; other plan docs `[P]` per file.

**Parallel opportunities:** In Dependencies & Execution Order, list every `[P]` batch explicitly.
Default assumption: maximize parallel test authoring and parallel implementation tasks unless a
shared file or migration ordering forbids it.

## Rules

- Hard cap 25 tasks. Over-cap → escalation (mis-scoped slice), never drop floor tests.
- Every spy case in §3.12 floor is its own task.

## Stop conditions

1. A task is not named by spec or plan.
2. A §3.12 floor test has no implementation unit.
3. Task count > 25.
4. A band verification id appears in the task list.
