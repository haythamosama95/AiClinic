---
name: abo-plan
description: >-
  Fill plan.md for an ABO unit from spec.md; bind Consumes; optional spike
  artifacts. After clarify, before tasks. Never commit.
disable-model-invocation: true
---

# ABO — Plan

Spec is authoritative. Choose how to satisfy it — no new requirements, files, or components the spec does not name.

**Input:** unit id in `$ARGUMENTS`, or current `ai/<NNN>-abo-…`. Neither → one `specs/<NNN>-*` → ask and stop.

## Paths

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-…" \
  .specify/scripts/bash/check-prerequisites.sh --json --paths-only
```

No `FEATURE_SPEC` → specify first. Escalation → do not call `setup-plan.sh` or write `plan.md`.

**After resolver:** read amendment; continue; do not re-read accepted spans.

When stops clear:

```bash
SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR" .specify/scripts/bash/setup-plan.sh --json
```

Fresh template copy replaces a partial plan. Never run scripts without `SPECIFY_FEATURE_DIRECTORY`. No commit.

## Sources (only these)

1. `spec.md` (whole, including Unit Contract). `## Clarifications` = implementation choices: follow, never promote to FR or file trace.
2. Delivery plan: this unit §4; §2–3; §6 only for **Open questions relied on**.
3. Design docs — only **Implements** citations; plus `02 §7` for Constitution Check. On disk; no `git show`.
4. Existing **Consumes** modules.
5. `plan-template.md`, `constitution.md`.

Other source needed → stop 1. Unit **Do not read** → stop.

## Codebases

Per spec **Codebase** cell: `backend/`, `ai-platform/`, `abo/`, `packages/vendor-contracts/`, `frontend/`, `e2e/fullstack/`. Extend plan template tree; don't force Worker code into `backend/`. One codebase unless row names wiring exception (S3: P2.1 header, P5.1 H-FS, P7.1 viewer+scripts+docs).

## Output (`plan.md`)

Mandatory sections. Four sections after Project Structure, before Complexity Tracking. Delete unused tree branches. No `tasks.md`.

| Section | Content |
| --- | --- |
| Summary | Two sentences from spec + **Depends** / phase |
| Technical Context | Spec/cited design only; no `NEEDS CLARIFICATION` |
| Constitution Check | All boxes ticked via `02 §7` + constitution; uncheckable → stop 4, not Complexity Tracking |
| Project Structure → Documentation | Always `quickstart.md` (outline only — **Quickstart** below). `data-model.md` if spec defines entities. `contracts/` if **Freezes** has wire shape. `research.md` only per **Spikes** |
| Project Structure → Source Code | Real tree for **Codebase**; drop unused template branches |
| `## Consumes Binding` | Row per **Consumes** → existing module/file/type; missing → stop 2; `None.` if Depends `—` |
| `## Files` | Every create/modify path → `FR-###` |
| `## Test Layout` | Row per E2E id; harness from spec (H-PKG, H-AP, …); title prefix E2E id (V3); red before code |
| `## Sequencing` | Tests before implementation, observed failing |
| Complexity Tracking | Only constitution violations `02 §7` already records |

Phase not done until every artifact the plan says to create now exists on disk — except `quickstart.md` (implement after verification).

### Quickstart (canonical for tasks + implement)

Plan lists sections only; implement writes the file after harness green:

- what was implemented; files added/modified
- harness command for **this unit's tests only**
- entry point → module chain per E2E id (S8)
- no earlier-unit files, combined counts, or full-suite commands
- manual steps only if harness cannot see the behaviour

### Spikes (S6)

**Spikes** = `None` → no `research.md`.

Otherwise run spike here (one command; no `npm ci`/`install` if `node_modules` present; no subagents). `research.md` = outcome + named fallback. Fallback without approval → use it. Spec says stop (e.g. OQ-4 P5.1) or no fallback → stop 6.

## Rules

- `research.md`, `data-model.md`, `contracts/` written in this phase when required above.
- Every file → FR. No libraries/patterns/config the spec doesn't name. One implementation needs no interface.
- Don't modify **Consumes** (S7).
- Every new module reachable from Test Layout entry (S8).
- Implied task count in S3 band: S 12–20, M 20–32, L 32–40. >40 → stop 5 (split is tasks phase). Don't pad to minimum.

## Stop conditions

Only `## ESCALATION`; no partial `plan.md`.

| # | Trigger |
| --- | --- |
| 1 | Plan needs something spec omitted; unanswerable Technical Context |
| 2 | **Consumes** missing or would change |
| 3 | E2E can't be placed in named harness |
| 4 | Constitution box can't be ticked |
| 5 | >40 tasks implied or wrong codebase |
| 6 | Spike failed; spec says stop or no fallback |

```markdown
## ESCALATION

**Stop condition:** 1 — plan needs something the spec omitted
**Unit:** P4.2
**Question:** …
**Should be answered by:** spec.md
**Blocked until:** spec.md is amended
```
