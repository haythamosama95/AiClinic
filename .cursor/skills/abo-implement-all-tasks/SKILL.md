---
name: abo-implement-all-tasks
description: Implement every phase in an ABO spec's tasks.md, assigning each phase to a Grok 4.7 High subagent running abo-implement. Parallelize [P] tasks within phases. Escalations use Kimi K3 High. After the band's slices complete, run abo-verify for the band matrix.
disable-model-invocation: true
---

# ABO — Implement All Slice Tasks

## Input

Specification directory in `$ARGUMENTS`, or resolve via:

```bash
.specify/scripts/bash/abo-paths.sh --json --require-tasks --include-tasks
```

Read `.cursor/skills/abo-implement/SKILL.md` first.

## Objective

Complete every phase in `tasks.md` via `/abo-implement` per phase.

## Subagent models

- **Phase owners and `[P]` workers:** Grok 4.7 High — `subagent_type: "generalPurpose"`,
  `model: "grok-4.7-high"`.
- **`## ESCALATION` from a phase owner:** Kimi K3 High — `model: "kimi-k3-high"`. Re-run the phase
  on Grok after Kimi resolves.

## Parallelism rules (mandatory)

1. **Within a phase:** all tasks marked `[P]` that touch different files run **concurrently** (spawn
   parallel **Grok 4.7 High** subagents).
2. **Across phases:** stay sequential — do not start phase N+1 until phase N is validated.
3. **Across slices in the same band:** when delivery-plan `Needs` are satisfied, multiple slice
   branches may implement in parallel (e.g. `M3` after `M1` while `M2` proceeds; band `N` parallel to
   band `M`). The parent orchestrator (`/abo-workflow`) owns that scheduling — this skill is
   per-spec-directory.

Phase owner template:

```text
Specification directory: <path>
Phase: <N> (<name>)

Read and follow .cursor/skills/abo-implement/SKILL.md.
Run only this phase. Parallelize every [P] task in this phase across subagents.
Mark in-scope tasks [X] in tasks.md.
Report ESCALATION verbatim if blocked.
```

Use `subagent_type: "generalPurpose"`, `model: "grok-4.7-high"`.

## After each phase

1. Confirm every task in the phase is `[X]`.
2. Commit: `Phase <N> Implementation` (when the user/repo expects phase commits).

## After all phases

1. Run slice-floor Verification from `tasks.md` if not already green.
2. **Do not** implement band matrix tests here — hand off to `/abo-verify <Band>` once every slice
   in that band has merged or is ready on `ai/master`.

## Final validation (slice scope)

Run only the test commands named in the plan's Test Layout and Verification task — not the full band
`e2e-seq` / `x-e2e` matrix.
