---
description: Clarify the AI platform delivery slice on the current branch, recording implementation choices in the spec's Clarifications section and escalating architecture gaps. Takes no argument.
---

# AI Platform — Clarify a Slice

The architecture is authoritative and the spec transcribes it. **This phase resolves nothing that
belongs to the architecture.** It records the implementation choices the architecture deliberately
left open, so the plan does not have to invent them silently.

Two kinds of unanswered question exist. You must classify every question before asking it, and the
classification decides where the answer goes:

| Kind | Test | Destination |
| --- | --- | --- |
| **Implementation choice** | The architecture is complete; two or more compliant implementations exist and the spec does not need to pick | `## Clarifications` in `spec.md`, tagged, non-normative |
| **Architecture gap** | No compliant implementation exists until a value, contract, or behaviour is decided; or the answer would change a `§` section | `## ESCALATION`, stop |

If you cannot tell which it is, it is a gap. Escalate.

**Input:** none. This phase runs directly after `/ai-platform-specify`, on the spec it just wrote.
Resolve the slice from the current `ai/` branch to its `specs/<NNN>-<name>/spec.md`. If the branch
does not identify exactly one spec directory, ask; do nothing else. If `plan.md` already exists, say
so and stop — clarification runs before planning.

## Relationship to Spec Kit

This is the AI platform variant of Spec Kit's `/speckit-clarify`, and it sits in the same slot: after
`/ai-platform-specify`, before `/ai-platform-plan`. It keeps that command's ambiguity taxonomy, its
five-question cap, its one-question-at-a-time loop, its recommendation format, and its
`## Clarifications` / `### Session YYYY-MM-DD` output shape.

It diverges in exactly two ways, both forced by the delivery plan:

- **`/speckit-clarify` rewrites the spec body** — Functional Requirements, Success Criteria, Data
  Model, Edge Cases — to absorb each answer. Here every requirement must stay traceable to a `§`
  section of `docs/architecture/ai-platform/01-ai-platform.md`, so the body is read-only and the answer is
  recorded as a tagged, non-normative bullet instead.
- **`/speckit-clarify` treats every ambiguity as answerable by the user.** Here an ambiguity in the
  architecture is stop condition 1 (delivery plan §6.3) and produces an `## ESCALATION`, never a
  guessed answer and never `[NEEDS CLARIFICATION]`.

Everything else about Spec Kit still applies: the same feature directory layout, the same
`.specify/` templates and scripts, the same constitution gate.

## Prerequisites

Run this from the repository root **once** and parse `FEATURE_DIR` and `FEATURE_SPEC` from the JSON:

```bash
.specify/scripts/bash/ai-platform-paths.sh --json --paths-only
```

That wraps Spec Kit's own `check-prerequisites.sh`, adding only the `ai/<NNN>-…` branch resolution
`.specify/feature.json` would otherwise override. Never call `check-prerequisites.sh` directly on an
`ai/` branch — it resolves the pinned non-AI feature instead of this slice.

If the script fails or `FEATURE_SPEC` does not exist, stop and instruct the user to run
`/ai-platform-specify` first — do not create a spec here.

## Sources — read exactly these

1. `FEATURE_SPEC` — whole file, including its `## Slice Contract` block.
2. `docs/architecture/ai-platform/03-ai-platform-delivery-plan.md` — the slice's §3 row, §3.11, and §6.
3. `docs/architecture/ai-platform/01-ai-platform.md` — **only** the sections in the spec's **Implements**, plus
   any §15 Open Decision named in **Open decisions relied on**.
4. `.specify/memory/constitution.md`.

Needing any other source means the question is an architecture gap. Escalate rather than read.

## Scan

Walk the spec once and collect candidate questions, each with the classification above. Only these
areas can yield an implementation choice:

- **Test construction** — fixture shape, fake versus real binding, how a spy asserts an absence,
  where a boundary case gets its input.
- **Code organisation** — module split, file naming, whether a helper is inlined, export surface
  within `ai-platform/src/`.
- **Local mechanics** — iteration order, data structure for an in-function lookup, error message
  wording that no contract fixes.
- **Verification mechanics** — how the suite is invoked, what `quickstart.md` demonstrates.

Everything else is a gap by default. In particular, these are **always** gaps, never choices:

- Any field name, table name, column type, error code, status code, header name, or token shape.
- Any threshold, timeout, limit, retry count, size bound, or default value.
- Any I/O count — Durable Object round trips, D1 inserts, R2 objects (§6.1, §7.5, §13.6).
- Any behaviour on a failure branch the spec does not name.
- Anything a later slice's **Consumes** would bind to. If the answer freezes a contract, it belongs in
  the architecture, not here.

## Questioning loop

At most **5** questions, **one per message**. Never reveal queued questions in advance. Ask only
questions whose answer changes the plan, the file layout, or a test's construction — drop anything the
plan phase can decide without ambiguity.

**A question is never asked without a recommendation.** Before asking, decide which option you would
take and why, judged on: compliance with the cited sections, the fewest moving parts (R-20, D-15),
testability, and consistency with how the already-merged slices in **Consumes** did the same thing. A
question you cannot recommend an answer to is not an implementation choice — it is a gap. Escalate it.

Emit each question in exactly this shape, all five lines present:

```markdown
**Q<n> of <total>** — <the question>

**Classification:** implementation choice — the architecture permits either; no §citation fixes this.

**Recommendation: <Option letter or short answer>** — <one or two sentences of reasoning>

| Option | Description |
| --- | --- |
| A | … |
| B | … |

Reply with the option letter, `yes` to take the recommendation, or your own short answer (≤5 words).
```

For a question with no discrete options, drop the table and use
`**Recommendation:** <proposed answer> — <reasoning>`, then
`Reply with `yes` to take it, or your own short answer (≤5 words).`

Then:

- `yes`, `recommended`, or `ok` means the recommendation becomes the answer verbatim.
- Otherwise map the reply to an option or accept the short answer. If genuinely ambiguous, ask once
  for disambiguation — that does not consume a new question.
- **The user is the judge of the classification.** If the user says a question is really an
  architecture gap, abandon it, record nothing for it, and add it to the escalation block at the end.
- Stop early on "done", "good", "proceed", or when the remaining questions stop mattering.

## Writing

After each accepted answer, write immediately — one atomic overwrite of `spec.md` per answer.

- Ensure a `## Clarifications` section exists, placed immediately after `## Slice Contract`.
- Under it, a `### Session YYYY-MM-DD` subheading for today.
- One bullet per accepted answer, tagged:

  ```markdown
  - Q: <question> → A: <answer> `[implementation choice — no §citation]`
  ```

- Write **nothing else**. That is the whole edit.

## Prohibitions

The original Spec Kit clarify workflow rewrites the spec body. Here it must not. Never:

- add, edit, renumber, or delete an `FR-###` or an `SC-###`;
- touch `## Slice Contract`, `## Requirements`, `## Success Criteria`, `## Out of Scope`,
  `## Constitution Alignment`, `### Key Entities`, or the acceptance scenarios;
- add or remove a test from the `### Test plan`;
- add a bullet to `### Edge Cases`;
- write `[NEEDS CLARIFICATION]` anywhere;
- create `plan.md`, `research.md`, `data-model.md`, `contracts/`, or any new file.

An answer that would require one of the above is an architecture gap. Escalate it instead.

## Downstream contract

`## Clarifications` entries are **decided implementation choices, not requirements**. The plan may
follow them and may cite them in its Files or Test Layout sections. Nothing downstream may promote an
entry into a requirement, trace a file to one instead of to an `FR-###`, or treat one as a frozen
contract for a later slice's **Consumes**.

## Report

When the loop ends:

- Questions asked and answered, and the path written.
- Every question the user reclassified as a gap.
- What was deliberately left to the plan phase.
- Next command: `/ai-platform-plan`.

If no implementation choice is open, say `No open implementation choices — the spec is sufficient to
plan.` and stop. Do not manufacture questions to fill the quota.

## Stop conditions

Delivery plan §6.3. If any is true, output **nothing but** an `## ESCALATION` block. Do not resolve it
yourself, do not guess, do not proceed partially, do not substitute `[NEEDS CLARIFICATION]`.

1. A question is an architecture gap — an unspecified value, contract, field, code, threshold, or
   failure branch (see the always-gaps list).
2. Answering would change something in the spec's **Consumes**, or would freeze a contract a later
   slice binds to.
3. The spec contradicts its cited sections, or a requirement has no traceable `§` reference.
4. The spec has no `## Slice Contract` block — it was not produced by `/ai-platform-specify`.

Collect every gap found in one block; do not stop at the first.

```markdown
## ESCALATION

**Stop condition:** 1 — architecture gap
**Slice:** A2
**Question:** The spec names no maximum length for the request reference.
**Should be answered by:** §5.4 or §13.2 of docs/architecture/ai-platform/01-ai-platform.md
**Blocked until:** the architecture document is amended
```
