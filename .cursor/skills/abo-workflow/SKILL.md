---
name: abo-workflow
description: Execute the ABO introduction workflow — Spec Kit per slice (specify through implement), parallelize unblocked bands and slices, then abo-verify for band matrices. Use when the user runs the full ABO workflow for a slice or band.
disable-model-invocation: true
---

# ABO Specification Workflow

## Input

- **Slice id** (e.g. `M1`, `N2`, `Q3`) and/or **band** (e.g. `M`, `N`) in `$ARGUMENTS`.
- If the user names only a band, run the band's slices in delivery-plan order, parallelizing where
  allowed.

```text
$ARGUMENTS
```

## Objective

1. **Per slice:** Spec Kit pipeline — specify → clarify → plan → tasks → implement-all-tasks.
2. **Per band:** after all slices in the band have completed implement-all-tasks, run
   `/abo-verify <Band>` (direct — no Spec Kit).
3. **Across bands:** maximize parallelism per §3.1 spine without violating `Needs`.

## Subagent models

- **Default — every subagent assignment:** Grok 4.7 High — `subagent_type: "generalPurpose"`,
  `model: "grok-4.7-high"`. Stages, slice pipelines, clarify answers, implement phases, verify
  batches, and review stages all use this model.
- **Escalations only:** Kimi K3 High — `subagent_type: "generalPurpose"`, `model: "kimi-k3-high"`.
  Use when any stage outputs `## ESCALATION`, when resolving plan/spec/delivery-plan conflicts, or
  when architecture meaning must be decided before continuing.

Do **not** use Grok to invent past an escalation. After Kimi resolves (or the user amends
architecture), re-run the failed stage with Grok. Stop only if Kimi cannot resolve after a
reasonable attempt.

## Band dependency spine (from delivery plan §3.1)

```text
M ─┬─► P ─► Q ─► R ─► S ─► T ─► U
   │
N ─┘ (parallel to M; N required before O)
M + N ─► O ─► (R needs O + Q)
P ─► Q, S
Q + S ─► T
```

**Parallelize aggressively:**

| When unblocked | May run in parallel |
| --- | --- |
| Start of introduction | Band **M** and band **N** (whole bands or individual slices) |
| After **M1** | **M2** and **M3** (M3 needs M1 only) |
| After prerequisites | Any two slices whose `Needs` are both satisfied and whose files do not conflict |
| Verification | `/abo-verify M` and `/abo-verify N` after respective bands' slices are implemented |
| Within a slice | `[P]` tasks and phases per `abo-implement-all-tasks` |

Assign **each slice's Spec Kit pipeline** to a dedicated **Grok 4.7 High** subagent when multiple
slices are unblocked (`model: "grok-4.7-high"`). Each subagent runs stages **in order** for its
slice. Do not parallelize clarify before specify completes on the same slice.

## Per-slice pipeline (strict order within the slice)

### Stage 1 — Specify

Assign **Grok 4.7 High** to run `/abo-specify @<slice-id>` — `.cursor/skills/abo-specify/SKILL.md`

### Stage 2 — Clarify

Assign **Grok 4.7 High** to run `/abo-clarify @<slice-id>` — one Grok subagent per clarification
question if batching.

### Stage 3 — Plan

Assign **Grok 4.7 High** to run `/abo-plan @<slice-id>`

### Stage 4 — Tasks

Assign **Grok 4.7 High** to run `/abo-tasks @<slice-id>` — if over 25 tasks, escalate; do not merge
unrelated tasks to fit.

### Stage 5 — Implement

`/abo-implement-all-tasks <specs-path>` — assign each phase to **Grok 4.7 High**; parallelize `[P]`
work inside phases.

### Stage 6 — Band verify (not Spec Kit)

When **every slice in the band** has finished Stage 5, run:

`/abo-verify <Band-letter>` — orchestrate with **Grok 4.7 High** subagents per **Subagent models**.

Parallelize verification **unit** and **x-e2e** rows; run **e2e-seq** serially. Multiple bands may
verify in parallel (each band orchestration on Grok 4.7 High) if stacks do not conflict.

For **CP-ABO-3**, after bands through R/S/T prerequisites: `/abo-verify chain`.

## Escalation handling

When any stage reports `## ESCALATION`:

1. Spawn a **Kimi K3 High** subagent (`model: "kimi-k3-high"`) to resolve if the fix is
   spec/plan/delivery-plan scoped and the user has authorized edits; otherwise stop for human
   architecture amendment.
2. After escalation is resolved, **re-run the failed stage** on **Grok 4.7 High**.
3. Proceed only when that stage completes without a new escalation.

Task-count escalation during **Tasks**: do not combine tasks — escalate as mis-scoped slice (Kimi
handles the escalation; do not merge tasks to fit the cap).

Stop the workflow only if Kimi cannot resolve the escalation after a reasonable attempt.

## Success criteria

For a **slice:**

1. `spec.md`, `plan.md`, `tasks.md` exist and slice-floor Verification is green.
2. `quickstart.md` exists per template.

For a **band:**

3. All slices implemented.
4. `/abo-verify` has all layers in the band table green and §8 columns updated.

## What this workflow does not do

- It does not replace review resolution — use `/abo-resolve-review` after human review docs exist.
- It does not implement band matrix rows inside Spec Kit tasks — that is always `/abo-verify`.
