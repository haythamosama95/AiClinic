---
name: abo-plan
description: Plan an ABO delivery slice whose spec.md already exists, filling the Spec Kit plan template and binding consumed contracts. Use when the user asks to plan an ABO slice or run abo-plan.
disable-model-invocation: true
---

# ABO — Plan a Slice

The spec is authoritative. **The plan may not introduce requirements, files, or components the spec
does not name.**

**Input:** `specs/<NNN>-<name>/spec.md` from the current branch or slice id in `$ARGUMENTS`.

## Subagent models

Stage owner under `/abo-workflow`: **Grok 4.7 High** (`model: "grok-4.7-high"`). `## ESCALATION` →
**Kimi K3 High** (`model: "kimi-k3-high"`).

## Prerequisites

```bash
.specify/scripts/bash/abo-paths.sh --json --paths-only
```

If `FEATURE_SPEC` is missing, stop — run `/abo-specify`.

```bash
SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR" .specify/scripts/bash/setup-plan.sh --json
```

Fill the copied `plan.md` in place.

## Sources

1. `spec.md` including `## Slice Contract` and `## Clarifications`.
2. `docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` — slice row, §3.11–§3.12, §5.
3. ABO architecture parts in **Implements**; AP-ARCH sections when cited there.
4. Modules in **Consumes**.
5. `.specify/templates/plan-template.md`, `.specify/memory/constitution.md`.

## Repository layout

Slices may touch any of:

- `ai-platform/` — Cloudflare Worker gateway (platform bands M–P).
- `ai-billing-orchestrator/` — vendor billing Worker + D1 (bands Q–R).
- `backend/` — Supabase migrations, RPCs, pgTAP (band S).
- `frontend/` — Flutter (band T).
- `packages/` — shared libraries (e.g. `packages/ed25519-jws/`).

Extend the plan template's source tree with real paths; do not force ABO code into `backend/`.

## Output — plan template

Same added sections as `ai-platform-plan`: **Consumes Binding**, **Components Touched**, **Files**,
**Test Layout**, **Sequencing**.

| Documentation | Rules |
| --- | --- |
| `quickstart.md` | **Always** — use `.specify/templates/abo-quickstart-template.md`; slice-only scope |
| `data-model.md` | When the slice defines D1 or Supabase entities |
| `contracts/` | When **Freezes** has a wire shape consumed cross-deployable |
| `research.md` | **Never** — architecture corpus is the research |

**Test Layout** covers **§3.12 floor tests only**. Add **`## Band verification`** stating the
band's §3.x.1 matrix is implemented by `/abo-verify` after all slices in the band land — not in this
plan's Files section.

## Constitution

For `ai-billing-orchestrator/`: vendor control plane only; no clinic business data; no write path into
Supabase. For gateway slices: additive, non-primary Worker per constitution Operating Constraints.

## Rules

- Every documentation artifact named in Project Structure must exist before the phase is done
  (`quickstart.md` filled during implement Documentation).
- Preserve AP I/O budgets when touching `ai-platform/`.
- Never modify **Consumes** contracts (delivery plan §2.3).

## Stop conditions

Delivery plan §5.2. Output only `## ESCALATION` when the plan needs something the spec omitted, a
**Consumes** binding is missing, §3.12 tests cannot be placed, constitution boxes cannot be checked,
or the plan implies >~25 tasks.
