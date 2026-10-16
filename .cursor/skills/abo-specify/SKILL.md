---
name: abo-specify
description: >-
  Transcribe one ABO unit from the delivery plan and design docs into spec.md.
  Use for abo-specify or when naming a unit id (P1.1, P4.2). Never commit.
disable-model-invocation: true
---

# ABO — Specify

Transcribe decided design into `spec.md`. Do not design. Untraceable requirements → `## ESCALATION`, never `[NEEDS CLARIFICATION]`.

**Input:** unit id in `$ARGUMENTS`. Empty → ask and stop. Refuse `a`/`b` split ids (splits happen at tasks, rule S3).

**Pipeline:** specify → clarify → plan → tasks → implement (`abo-workflow` orchestrates).

## Branch and directory

Rule S4: look up NNN in the delivery plan S4 table (`P1.1` = 061 … `P8.3` = 098). No `create-new-feature.sh`.

- **short-name:** unit title, kebab-case, drop a/an/the/and, ≤5 words (e.g. P4.2 → `checkout-paymob-intention`).
- **Directory:** `specs/<NNN>-abo-p<phase>-<n>-<short-name>/`
- **Branch:** `ai/<NNN>-abo-p<phase>-<n>-<short-name>` from `ai/abo-master`

If the orchestrator already created the branch, stay on it; do not `checkout -b` again. Otherwise:

```bash
git checkout ai/abo-master && git checkout -b ai/<NNN>-abo-…
mkdir -p specs/<NNN>-abo-…
cp .specify/templates/spec-template.md specs/<NNN>-abo-…/spec.md
```

Check stop conditions before occupying the number. No commit/push/amend. Leave `.cursor/skills/` untouched. Dirty tree stops the run except edits under `docs/architecture/ai-billing-orchestration/` and this unit's `specs/<NNN>-abo-…/`.

`specs/<NNN>-*` exists: empty template for this unit → reuse; filled spec for this unit → stop; other feature → stop 7.

Update `AGENTS.md` `<!-- SPECKIT START -->` … `<!-- SPECKIT END -->` with this feature's plan, spec, branch (S4).

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-…" \
  .specify/scripts/bash/check-prerequisites.sh --json --paths-only
```

Abort unless JSON resolves to this directory and exactly one `specs/<NNN>-*`. `.specify/feature.json` outranks branch lookup for that check only.

**After resolver:** read the amendment; continue; do not re-read accepted spans.

## Sources (only these)

1. `06-abo-delivery-plan.md`: §2–3; this unit in §4; its S4 row; §6 open questions its Read/Implements line names; from §5 only D1/D2 rows naming this unit.
2. `docs/architecture/ai-billing-orchestration/00`–`05` — only **Read** spans the unit row cites. Read files on disk; no `git show`. Bounded citations end at the span.
3. **Depends** units: **Outputs / freezes** line only.
4. `.specify/templates/spec-template.md`, `.specify/memory/constitution.md`.
5. **Code** paths only to name the S8 entry point and confirm a consumed contract exists.

**Do not read** on the unit row is a stop, not a lookup. No other units' Implements/E2E lists; no architecture files outside this list.

## Output (`spec.md`)

Keep mandatory template sections. Add `## Unit Contract` after the header; `## Out of Scope` before Assumptions. Drop MVP/deploy/demo language (nothing ships before P8, rule S2).

| Section | Content |
| --- | --- |
| Header | **Input:** unit id + title. **Feature Branch:** `ai/<NNN>-…` |
| `## Unit Contract` | **Implements** (Read cites + Implements bullets verbatim). **Freezes** (Outputs/freezes verbatim). **Consumes** (each Depends Outputs/freezes; `—` → `None.`). **Open questions relied on** (§6 defaults quoted or `None.`). **Spikes** (S6 spike + fallback or `None.`) |
| User stories | Rule S3 partition (below). Acceptance = that story's E2E ids as Given/When/Then from cited sections only |
| `### Test plan` | One row per E2E id: ID, Harness, Entry point (S8 live entry), Assertion (+ tags), Proves (`FR-###`), Story. P2.2 / package half of P2.1 may use Node/workerd vectors |
| `### Edge Cases` | Refusals/boundaries/failures E2E + Read name; delete template placeholders |
| Requirements | `FR-###`, cited sentences, e.g. `(04 §2.2)` |
| Key Entities | Types/tables this unit defines, or `Not applicable — this unit defines no entities.` |
| Constitution Alignment | **Codebase** cell + any wiring exception the row names (S3). `plan.md` re-runs `02 §7` (S12) |
| `## Out of Scope` | Unit Out of scope verbatim +: no Do-not-read material; no Consumes rewrite; no unreachable module (S8; except P2.2 / package P2.1); no S9 path owned by a later unit; no second codebase beyond **Codebase** |
| Success Criteria | Every test-plan id green in its harness; earlier suites stay green (S2). CP-A…CP-G in Outputs → SC for that checkpoint (S11) |
| Assumptions | §6 defaults relied on + S9 transitional paths named. Nothing else |

Test plan = S12 register: one failing test per row later (V3 title prefix). Copy every E2E id; add none.

### Story partition (S3)

S = 1–2, M = 2–3, L = 3–4 stories. One unit, one branch, one review.

- Each Implements bullet → candidate story; attach E2E ids to what they prove.
- Merge bullets sharing an entry point until count in range; keep every scenario.
- Split only when minimum story count needs it and scenarios use two entry points.
- Outside range → stop 4. P1 = story others depend on; regression-only line on last story.
- Voice: clinic member, admin, operator, or calling component as scenarios use.

## Rules

- Restate design only; unjustified prose → delete or stop.
- No invented names, codes, thresholds, timeouts, limits, defaults.
- No extra error handling, retries, caching, abstraction, configurability.
- No later unit's work. Coverage V5/V8: every E2E row; every refusal code introduced; every FM-# D1 assigns; owned version channels need accept + refuse-before-auth/write. Gap → stop; no new E2E ids.

## Stop conditions

Reply with **only** `## ESCALATION` (all that fired). No partial spec; no branch on escalation.

| # | Trigger |
| --- | --- |
| 1 | Requirement untraceable to Read or assumed §6 default |
| 2 | Would change **Consumes** |
| 3 | E2E has no live entry point or observable outcome |
| 4 | Stories outside S3 range, or wrong codebase |
| 5 | Read section missing, or answer only in **Do not read** |
| 6 | Coverage gap (V5/V8) |
| 7 | NNN belongs to another feature directory |

```markdown
## ESCALATION

**Stop condition:** 1 — untraceable requirement
**Unit:** P1.1
**Question:** …
**Should be answered by:** 01 §2 row T-1 (`docs/architecture/ai-billing-orchestration/01-abo-design-decisions.md`)
**Blocked until:** the design document or the delivery plan is amended
```
