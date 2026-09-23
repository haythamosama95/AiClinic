---
name: abo-clarify
description: Clarify the ABO delivery slice on the current branch, recording implementation choices in the spec's Clarifications section and escalating architecture gaps. Use after abo-specify or when the user runs abo-clarify on an ai/ branch.
disable-model-invocation: true
---

# ABO — Clarify a Slice

The architecture is authoritative and the spec transcribes it. **This phase resolves nothing that
belongs to the architecture.** It records implementation choices the architecture left open.

| Kind | Test | Destination |
| --- | --- | --- |
| **Implementation choice** | Architecture is complete; multiple compliant implementations exist | `## Clarifications` in `spec.md`, tagged, non-normative |
| **Architecture gap** | No compliant implementation until architecture decides | `## ESCALATION`, stop |

If unsure, it is a gap. Escalate.

**Input:** none. Runs after `/abo-specify` on the current `ai/` branch. If `plan.md` exists, stop —
clarify runs before planning.

## Subagent models (when `/abo-workflow` batches clarify answers)

Each clarification question answered by a subagent: **Grok 4.7 High** (`model: "grok-4.7-high"`).
Architecture gaps (`## ESCALATION`): **Kimi K3 High** (`model: "kimi-k3-high"`) — the clarify phase
stops; Kimi does not rewrite the spec body.

## Prerequisites

```bash
.specify/scripts/bash/abo-paths.sh --json --paths-only
```

Never call `check-prerequisites.sh` directly on an `ai/` branch.

## Sources

1. `FEATURE_SPEC` — whole file, including `## Slice Contract`.
2. `docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` — slice §3 row, §3.12, §5.
3. ABO architecture parts in **Implements** only; AP-ARCH sections only when named in **Implements**.
4. `.specify/memory/constitution.md`.

## Scan

Candidate questions only from: test construction, code organisation, local mechanics, verification
mechanics for **§3.12 slice-floor tests only**. Band matrix scenarios (§3.x.1) are not clarified
here — `/abo-verify` implements them directly from the delivery plan.

Always gaps: field/table/error codes, thresholds, verification-order steps, anything a later slice
**Consumes** would bind to.

## Questioning loop

At most **5** questions, one per message, each with a **Recommendation**. Same format as
`ai-platform-clarify` (Qn of total, classification, options table, reply rules).

## Writing

After each answer, append to `## Clarifications` under `### Session YYYY-MM-DD` only. Never edit
`FR-###`, acceptance scenarios, §3.12 test plan, or Slice Contract.

## Report

Questions answered; gaps escalated; next: `/abo-plan`.

If no open choices: `No open implementation choices — the spec is sufficient to plan.`

## Stop conditions

Same as delivery plan §5.2 — collect all gaps in one `## ESCALATION` block.
