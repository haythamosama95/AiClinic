---
description: Plan an AI platform delivery slice whose spec.md already exists, filling the Spec Kit plan template and binding each consumed contract to an existing module. Pass the slice id or spec path as the argument.
---

# AI Platform — Plan a Slice

The spec is authoritative. **The plan may not introduce any requirement, file, or component the spec
does not name.** You are choosing how to satisfy an already-written spec, not extending it.

**Input:** the slice's `specs/<NNN>-<name>/spec.md`. Resolve it from the current branch or the slice
id given as `$ARGUMENTS`. If neither identifies exactly one spec directory, ask; do nothing else.

## User Input

```text
$ARGUMENTS
```

The first argument should be the slice id (e.g. `A1`, `D6`). If empty, resolve from the current branch
or ask.

## Sources — read exactly these

1. The slice's `spec.md` — whole file, including its `## Slice Contract` block.
2. `docs/architecture/17b-ai-platform-delivery-plan.md` — the slice's §3 row, §3.10, and §6.
3. `docs/architecture/17-ai-platform.md` — **only** the sections in the spec's **Implements**.
4. The existing modules named in the spec's **Consumes**.
5. `.specify/templates/plan-template.md` and `.specify/memory/constitution.md`.

Needing any other source is stop condition 1.

## Repository layout

The Cloudflare Worker, its D1 migrations, its prompt artifacts, and its tests live in
**`ai-platform/`** at the repository root, alongside `frontend/` and `backend/`. The plan template's
path conventions predate it; extend the source tree rather than forcing Worker code into
`backend/`.

## Output — the Spec Kit plan template, filled this way

| Template section | Fill with |
| --- | --- |
| Summary | The slice's purpose in two sentences, taken from the spec, plus its position in the delivery sequence |
| Technical Context | Concrete values only. Every field must be answerable from the spec or the cited architecture. **Never write `NEEDS CLARIFICATION`** — an unanswerable field is stop condition 1 |
| Constitution Check | Every box must be checked before proceeding. For gateway slices, record the §14 acknowledgement: the Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. An uncheckable box is an escalation, not a Complexity Tracking row |
| Project Structure → Documentation | List only the artifacts this slice actually produces, then **write every one you list**. `data-model.md` only when the slice defines D1 entities; `contracts/` whenever a **Freezes** entry has a wire shape — a table, a payload, a token, an event, an error taxonomy — because a later slice's **Consumes** must bind to a frozen artifact, not to prose; `quickstart.md` only when a human must run something to verify it. **Never `research.md`** — the research is `17-ai-platform.md`, and redoing it is how architecture drift starts |
| Project Structure → Source Code | The real tree for this slice, including `ai-platform/` where applicable. Delete unused branches |
| **`## Consumes Binding`** *(added)* | One row per **Consumes** entry, naming the existing module, file, or type it binds to. An entry with no existing implementation is stop condition 2 |
| **`## Components Touched`** *(added)* | The §4 components of `17-ai-platform.md` this slice modifies. More than one requires an explicit written reason here |
| **`## Files`** *(added)* | Every file created or modified, each traced to an `FR-###` from the spec |
| **`## Test Layout`** *(added)* | Where each named test from the spec's Test plan will live, using the layers in §13.5 |
| **`## Sequencing`** *(added)* | The order in which tests and implementation land — tests first or alongside, never after |
| Complexity Tracking | Only for a genuine constitution violation. Not a place to park unresolved questions |

## Rules

- **The phase is not done until every artifact named in Project Structure → Documentation exists on
  disk.** Naming one and not writing it leaves a later slice binding to a file that is not there.
- Every file in the plan traces to a spec requirement. An untraced file is out of scope.
- Do not choose a library, pattern, or abstraction the spec or the cited architecture does not name.
  One implementation needs no interface (D-15).
- Do not add a configuration surface, a feature flag, or an extension point nobody asked for (R-20).
- Do not modify anything in **Consumes**. A later slice may extend a frozen contract, never rewrite
  it (delivery plan §2.3).
- Preserve the platform's I/O budgets: one Quota Durable Object round trip and one D1 insert in the
  guard, one R2 object per request (§6.1, §7.5, §13.6).

## Stop conditions

Delivery plan §6.3. If any is true, output **nothing but** an `## ESCALATION` block. Do not resolve
it yourself, do not guess, do not proceed partially, do not substitute `NEEDS CLARIFICATION`.

1. The plan needs something the spec omitted, or a Technical Context field cannot be answered.
2. A **Consumes** entry has no existing implementation, or satisfying the spec would require changing one.
3. A named test from the spec cannot be placed in a test layer.
4. A Constitution Check box cannot be ticked.
5. The plan touches more than one §4 component without a reason, or clearly implies more than ~25 tasks.

```markdown
## ESCALATION

**Stop condition:** 1 — plan needs something the spec omitted
**Slice:** C5
**Question:** The spec names no behaviour for a journal insert that fails before the stream opens.
**Should be answered by:** the spec, regenerated from §4.3.11 and §6.1 stage 9
**Blocked until:** spec.md is amended
```
