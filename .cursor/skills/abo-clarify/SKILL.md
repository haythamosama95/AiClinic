---
name: abo-clarify
description: >-
  Record implementation choices in spec Clarifications; escalate design gaps.
  After specify, before plan. Never commit.
disable-model-invocation: true
---

# ABO — Clarify

Design + spec are authoritative. Record choices the design left open; never resolve design gaps here.

**Input:** none (runs on current `ai/<NNN>-abo-…` after specify). No commit/branch/spec creation.

Unlike `/speckit-clarify`, do not rewrite FR/SC/Edge Cases — one tagged bullet under `## Clarifications` per answer.

## Paths

Resolve one `specs/<NNN>-abo-…` from the current branch. Pass it explicitly (do not trust `.specify/feature.json` for directory choice):

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-…" \
  .specify/scripts/bash/check-prerequisites.sh --json --paths-only
```

Not exactly one feature dir → ask and stop. No `FEATURE_SPEC` → run specify. `plan.md` exists → stop (clarify is before plan).

**After resolver:** read amendment; continue; do not re-read accepted spans.

## Sources (only these)

1. `FEATURE_SPEC` (whole file, including `## Unit Contract`).
2. `06-abo-delivery-plan.md`: §2–3 (S1–S12, V1–V8); this unit in §4; §6 only for **Open questions relied on**.
3. Design `00`–`05` under `docs/architecture/ai-billing-orchestration/` — only spans **Implements** cites (same file list as specify). On disk; no `git show`.
4. `.specify/memory/constitution.md`.

**Do not read** → design gap. Any other source → gap.

## Classify

| Kind | Test | Action |
| --- | --- | --- |
| **Implementation choice** | Design complete; ≥2 compliant options; spec need not pick | `## Clarifications` bullet `[implementation choice — no §citation]` |
| **Design gap** | Value/contract/behaviour undecided; answer would change a cited section | `## ESCALATION` |

If unsure → gap.

**Choices allowed:** test/harness construction, in-codebase file layout, local mechanics contracts don't fix, verification/quickstart mechanics.

**Always gap:** field/table/column names, codes, headers, token shapes, thresholds, timeouts, limits, retries, defaults; unnamed failure branches; anything a later **Consumes** would bind to.

Spikes → `research.md` in plan (S6), not here. §6 defaults already in **Open questions relied on** are not questions.

## Questioning

Orchestrator says not to ask user → write each choice as your recommendation immediately; gaps still escalate.

Otherwise ≤5 questions, one per message, no queue reveal. Only what changes plan, layout, or test construction. None open → `No open implementation choices — the spec is sufficient to plan.` and stop.

Every question includes a **Recommendation** (compliance, simplicity, testability, match **Consumes** patterns). No recommendable answer → gap.

Format: `**Q<n> of <total>** — question`; classification; recommendation (+ option table when A/B apply, else single proposed answer); `Reply with letter, yes, or ≤5 words.`

User may reply with option letter, `yes`, or ≤5 words. Ambiguous → ask once (free). Reclassify to gap → escalation, keep written bullets. Stop on "done" / "good" / "proceed".

## Writing answers

After each accepted answer, one edit to `spec.md`:

- `## Clarifications` immediately after `## Unit Contract`
- `### Session YYYY-MM-DD`
- `- Q: … → A: … \`[implementation choice — no §citation]\``

Do not edit Unit Contract, FR/SC, Requirements, Test plan, Edge Cases, stories, or other sections. No new files (`plan.md`, `research.md`, …). Answer needing those → gap.

## Downstream

Clarifications are not requirements. Plan may cite them in Files/Test Layout; never promote to FR or **Consumes** freeze.

## Report

Questions answered, path, reclassified items, left to plan. Next: `/abo-plan`.

## Stop conditions

Only `## ESCALATION` if any fires. No partial writes.

| # | Trigger |
| --- | --- |
| 1 | Design gap |
| 2 | Answer changes **Consumes** or freezes a later contract |
| 3 | Spec contradicts citations or lacks citation |
| 4 | No `## Unit Contract` |

User-reclassified gaps go in the escalation block; existing clarification bullets stay.

```markdown
## ESCALATION

**Stop condition:** 1 — design gap
**Unit:** P1.1
**Question:** …
**Should be answered by:** …
**Blocked until:** the design document or the delivery plan is amended
```
