---
name: abo-clarify
description: >-
  Clarify the ABO delivery unit on the current branch, recording implementation
  choices in the spec's Clarifications section and escalating design gaps. Use
  when the user asks to clarify an ABO unit after specify, or run abo-clarify
  on an ai/ branch. Never commit.
disable-model-invocation: true
---

# ABO — Clarify a Unit

The design and the spec are authoritative. This phase resolves nothing that belongs to the design.
It records implementation choices the design left open, so the plan does not invent them silently.

The leaf is a **unit** (`P1.1`). One unit is one Spec Kit feature (rule S2).

**Input:** none. Runs after `/abo-specify`, on the spec it just wrote. Do not create a spec, and do not commit, amend, or push.

## Relationship to Spec Kit

Same slot as `/speckit-clarify`: after `/abo-specify`, before `/abo-plan`. Phase order:
`/abo-specify` → `/abo-clarify` → `/abo-plan` → `/abo-tasks` → `/abo-implement`.

`/speckit-clarify` rewrites Functional Requirements, Success Criteria, and Edge Cases to absorb each
answer. Here the body stays a transcription of the design docs, and the answer is one tagged,
non-normative bullet. A gap in the design is a stop, never a guessed answer.

## Branch and feature directory

`.specify/feature.json` outranks branch lookup. Resolve the current `ai/<NNN>-abo-…` branch to the
single `specs/<NNN>-*` directory and pass it explicitly. Never call `check-prerequisites.sh`
without `SPECIFY_FEATURE_DIRECTORY`.

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-…" \
  .specify/scripts/bash/check-prerequisites.sh --json --paths-only
```

Parse `FEATURE_DIR` and `FEATURE_SPEC` from the JSON. If that branch is not exactly one
`specs/<NNN>-*` directory, ask and stop. If `FEATURE_SPEC` is missing, tell the user to run
`/abo-specify` first. If `plan.md` already exists, stop — clarify runs before plan.

## Sources — read exactly these

If the prompt says to continue after a resolver amendment, read that amendment and continue. Do not re-read Read spans already accepted.

1. `FEATURE_SPEC` — whole file, including `## Unit Contract`.
2. `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` — sections 2 and 3 (rules
   S1–S12, harnesses V1–V8), this unit's section in section 4, and section 6 only for an open
   question named in **Open questions relied on**.
3. Design docs in `docs/architecture/ai-billing-orchestration/`, only the spans **Implements** cites.
   `00`–`05` are `00-abo-requirements-seed.md`, `01-abo-design-decisions.md`,
   `02-abo-architecture-and-threat-model.md`, `03-abo-data-model-and-lifecycle.md`,
   `04-abo-contracts.md`, `05-abo-operations-and-traceability.md`. Read the files. Do not use
   `git show`. A bounded citation ("first paragraph", "row T-1") ends at that span.
4. `.specify/memory/constitution.md`.

A **Do not read** section is a stop, not a lookup. Needing any other source means the question is a
design gap.

## Classify

Classify before asking. The class decides the destination.

| Kind | Test | Destination |
| --- | --- | --- |
| **Implementation choice** | Design is complete; two or more compliant implementations exist; the spec does not need to pick | `## Clarifications` in spec.md, tagged, non-normative |
| **Design gap** | No compliant implementation exists until a value, contract, or behaviour is decided; or the answer would change a cited section | `## ESCALATION`, stop |

If you cannot tell, it is a gap.

Implementation choices may only be: test construction (fixture shape, how a harness asserts an
absence), code organisation inside the unit's Codebase (module split, file names, inlined helper),
local mechanics the contract does not fix (iteration order, in-function lookup structure,
error-message wording no contract fixes), verification mechanics (how the named harness is invoked,
what `quickstart.md` demonstrates).

Always a gap, never a choice: field name, table name, column type, error code, status, header, token
shape; any threshold, timeout, limit, retry count, or default; any behaviour on a failure branch the
spec does not name; anything a later unit's **Consumes** would bind to. If the answer freezes a
contract, it belongs in the design docs.

Rule S6 puts spikes in `research.md` during `/abo-plan`, not here. Do not ask the user to resolve a
spike the spec's **Spikes** subsection already assigns to the plan. A question whose answer is the
spike outcome is not an implementation choice. A section 6 default already quoted under **Open
questions relied on** is not a question; changing it is a gap.

## Questioning loop

If the prompt says not to ask the user, skip this loop. Write each implementation choice immediately as its recommendation. A design gap is still an escalation.

Otherwise at most **5** questions, **one per message**. Never reveal the queue. Ask only what would change the
plan, the file layout, or a test's construction. Do not manufacture questions. If none are open, say
`No open implementation choices — the spec is sufficient to plan.` and stop.

A question is never asked without a recommendation. Judge it by compliance with the cited sections,
fewest moving parts, testability, and consistency with how units in **Consumes** already did the
same thing. A question you cannot recommend an answer to is a gap.

```markdown
**Q<n> of <total>** — <the question>

**Classification:** implementation choice — the design permits either; no citation fixes this.

**Recommendation: <Option letter or short answer>** — <one or two sentences of reasoning>

| Option | Description |
| --- | --- |
| A | … |
| B | … |

Reply with the option letter, `yes` to take the recommendation, or your own short answer (≤5 words).
```

No discrete options: drop the table. Use `**Recommendation:** <proposed answer> — <reasoning>`, then
`Reply with `yes` to take it, or your own short answer (≤5 words).`

`yes` accepts the recommendation verbatim. Map any other reply to an option or take the short
answer. If it is ambiguous, ask once — that does not consume a question. The user may reclassify a
question as a gap; then record nothing for it and include it in the escalation block. Stop early on
"done", "good", or "proceed".

## Writing

After each accepted answer, one atomic edit of spec.md:

- `## Clarifications` immediately after `## Unit Contract`
- `### Session YYYY-MM-DD`
- one bullet:

```markdown
- Q: … → A: … `[implementation choice — no §citation]`
```

Write nothing else. Never edit FR/SC, Unit Contract, Requirements, Success Criteria, Out of Scope,
Constitution Alignment, Key Entities, acceptance scenarios, the Test plan, or Edge Cases. Never
write `[NEEDS CLARIFICATION]`. Never create `plan.md`, `research.md`, `data-model.md`, `contracts/`,
or any new file. An answer that needs one of those is a gap.

## Downstream

Clarifications are decided implementation choices, not requirements. The plan may follow them and
cite them in Files or Test Layout. Nothing downstream may promote one into an FR, trace a file to
one instead of an FR, or treat one as a freeze for a later unit's **Consumes**.

## Report

Questions asked and answered, and the path written. Questions the user reclassified. What was left
to the plan. Next command: `/abo-plan`.

## Stop conditions

If any stop condition is true, output nothing but one `## ESCALATION` block listing every condition
that fired. Do not guess, do not partial-write, do not use `[NEEDS CLARIFICATION]`.

1. The question is a design gap (unspecified value, contract, field, code, threshold, or failure branch).
2. Answering would change **Consumes**, or would freeze a contract a later unit binds to.
3. The spec contradicts its cited sections, or a requirement has no citation.
4. The spec has no `## Unit Contract` — it was not produced by `/abo-specify`.

Those four are gaps you find: the reply is only that block. A question the user reclassifies is
listed in the same block inside the report, and bullets already written stay.

```markdown
## ESCALATION

**Stop condition:** 1 — design gap
**Unit:** P1.1
**Question:** …
**Should be answered by:** 01 §2 row T-1 (`docs/architecture/ai-billing-orchestration/01-abo-design-decisions.md`)
**Blocked until:** the design document or the delivery plan is amended
```
