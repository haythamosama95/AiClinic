---
name: ai-platform-specify
description: Writes spec.md for one AI platform delivery slice (A1, D6, H3, …) by transcribing docs/architecture/17-ai-platform.md into the Spec Kit spec template, without inventing architecture. Use when the user names an AI platform slice id and asks to specify it or drive speckit.specify on it.
---

# AI Platform — Specify a Slice

You are **transcribing an already-decided architecture** into a feature spec. You are not designing.
Every requirement must be traceable to a cited section. If it cannot be traced, you stop.

**Input:** the slice id (`A1`, `B7`, `D6`, `H3`, `J2`, …). If the user did not give one, ask for it
and do nothing else.

## Branch

Before anything else, branch from `ai/master` with the `ai/` prefix (e.g. `ai/017-a1-worker-skeleton`).

```bash
git fetch origin ai/master
git checkout ai/master
git checkout -b ai/<branch-name>
```

## Sources — read exactly these

1. `docs/architecture/17b-ai-platform-delivery-plan.md` — whole file.
2. `docs/architecture/17-ai-platform.md` — **only** the sections named in the slice's `Canonical`
   cell in §3 of the delivery plan.
3. `docs/architecture/17-ai-platform.md` §15 Open Decisions — only if the slice depends on one.
4. `.specify/templates/spec-template.md` and `.specify/memory/constitution.md`.

Do not read other sections of `17-ai-platform.md`. Do not read other architecture docs. Needing one
is a stop condition, not a reason to read it.

## Scope

Find the slice's row in §3 of the delivery plan. Its `Slice`, `Canonical`, `Needs`, and `Done when`
cells are the entire scope. The slice's row in §3.11 is the minimum test set. Nothing outside those
two rows is in scope.

## Output — the Spec Kit template, filled this way

Keep every mandatory section of `.specify/templates/spec-template.md`. Two sections are added. Fill
them as follows.

| Template section | Fill with |
| --- | --- |
| Header block | `**Input**` is the slice id and its `Slice` cell, not a prose description |
| **`## Slice Contract`** *(added, immediately after the header)* | Four subsections: **Implements** — the `Canonical` cell copied verbatim; **Freezes** — contracts this slice establishes for the first time; **Consumes** — contracts frozen by the slices in `Needs`, changing any is out of scope by definition; **Open decisions relied on** — any §15 decision whose recommended default is assumed |
| `## User Scenarios & Testing` | **Exactly one** user story, titled with the slice name. "Why this priority" states why the slice sits where it does, from its `Needs`. "Independent Test" is the slice's `Done when` cell. Acceptance Scenarios are Given/When/Then, one per case in the slice's §3.11 row. Add a `### Test plan` subsection listing every named test with its layer from §13.5 |
| `### Edge Cases` | Replace the template's placeholder questions with this slice's real ones: every error code it can emit, every boundary it enforces, every failure branch |
| `## Requirements` | `FR-###`, each a restatement of a cited sentence, each ending with its section reference, e.g. `(§4.3.11)` |
| `### Key Entities` | Only if the slice defines D1 entities or contract types. Otherwise write `Not applicable — this slice defines no entities.` |
| `## Constitution Alignment` | Layer Placement must name which of `ai-platform/` (Cloudflare Worker), `backend/` (Supabase), and `frontend/` (Flutter) this slice touches. Where the slice is part of the gateway, cite the §14 acknowledgement that it is a non-primary, additive component |
| **`## Out of Scope`** *(added, before Assumptions)* | Explicit exclusions: neighbouring slices this one touches, plus the prohibitions listed below |
| `## Success Criteria` | `SC-###` derived from the `Done when` cell, stated measurably |
| `## Assumptions` | As the template intends |

## Overrides to the template

The template predates the delivery plan. Where they conflict, the delivery plan wins:

- **One slice is one user story.** Do not decompose a slice into P1/P2/P3. Label the single story P1
  and add no others.
- **Drop MVP, deploy, and demo language.** Nothing ships until the whole product does (DP-1). "Independently
  testable" means provable by an automated test, not demonstrable to a user (DP-3).
- **Tests are never optional.** The template's optional-tests note does not apply to this platform.
- A slice with no user-facing behaviour (most of bands A–D) still writes one story, from the
  perspective of the operator, the reviewer, or the calling component.

## Rules

- A requirement restates the architecture. If it needs original prose to justify it, delete it or stop.
- Never invent field names, table names, error codes, thresholds, timeouts, limits, or defaults. Use
  the cited ones. An unspecified value is a stop condition — never write `[NEEDS CLARIFICATION]`.
- Never add error handling, retries, caching, abstraction, or configurability the cited sections do
  not name (R-20).
- Never pull work forward from a later slice.
- Every acceptance criterion is a named test case. Untestable criteria are a stop condition.
- Coverage is behavioural (delivery plan §3.10): the happy path of every requirement, **every error
  code the slice can emit**, every branch, every inherited prohibition, every named boundary.

## Prohibitions to copy into Out of Scope

Delivery plan §6.4:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Stop conditions

Delivery plan §6.3. If any is true, output **nothing but** an `## ESCALATION` block. Do not resolve
it yourself, do not guess, do not proceed partially, do not substitute `[NEEDS CLARIFICATION]`.

1. A requirement cannot be traced to a cited section or a §15 recommended default.
2. The slice appears to require changing something listed in `Consumes`.
3. An acceptance criterion cannot be expressed as a test case.
4. The slice looks likely to exceed ~25 tasks or to touch more than one §4 component.

```markdown
## ESCALATION

**Stop condition:** 1 — untraceable requirement
**Slice:** A2
**Question:** What is the required length and alphabet of the request reference?
**Should be answered by:** §5.4 or §13.2 of docs/architecture/17-ai-platform.md
**Blocked until:** the architecture document is amended
```
