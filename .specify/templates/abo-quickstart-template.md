# Quickstart: <slice title> (<slice id>)

<Two or three sentences: what this slice adds across the ABO introduction. Do not catalogue prior
slices — context belongs in `spec.md` / `plan.md`, not here.>

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Slice-floor regression (§3.12)
belongs in the implement Verification task; the band verification matrix (§3.2.1–§3.10.1) is
implemented via `/abo-verify`, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

<Brief paragraph or a few bullets — in simple words:>

- Which **delivery-plan row** this slice implements — cite
  [`../../docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md`](../../docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md)
  and the **Implements** sections from `spec.md` (ABO `architecture/*.md` parts and, when named,
  AP-ARCH amendments in
  [`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)).
- What the **spec** (`spec.md`) was aiming to deliver.
- What the **plan** (`plan.md`) scoped for implementation.

Keep this slice-focused — what *this* slice implements, not a catalogue of prior slices.

## 2. What was implemented

- <Deliverable 1 — module, contract, endpoint, migration, RPC, Flutter flow, etc.>
- <Deliverable 2>
- <Link to `spec.md` for full requirements and `plan.md` for file-level traceability.>

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/<file>.ts` or `ai-billing-orchestrator/src/<file>.ts` or `backend/...` or `frontend/lib/...` | <What this file does> |
| `<test path>` | <Which named §3.12 floor tests live here> |

## 4. Prerequisites

<Omit when slice-only test commands are sufficient. Otherwise list stack pieces this slice needs
(e.g. local Supabase, `wrangler dev`, Flutter SDK). Do not point at prior slices' test files here.>

## 5. Run the automated suite

From the repository root — **slice-only** commands for the codebase this slice touched:

```bash
# Example — replace with the plan's Test Layout paths
cd ai-platform && npx vitest run test/<file>.test.ts
# cd ai-billing-orchestrator && npx vitest run test/<file>.test.ts
# bash backend/tests/<script>.sh
# cd frontend && flutter test test/<file>_test.dart
```

Expected: **<N> passing tests** for this slice only. Do not run full multi-deployable suites or band
`e2e-seq` / `x-e2e` chains here — those are `/abo-verify`.

## 6. Inspect the changes

<Concrete commands or paths so a reviewer can see what this slice landed — scoped to this slice's
files only.>

## 7. Manual validation

<Omit when CI is the only verification path. Otherwise: deploy steps, `curl` examples, viewer smoke,
etc., only for behaviour this slice exposes beyond the slice-floor suite.>
