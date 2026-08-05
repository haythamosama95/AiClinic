# Contract: Transcript validation, budgets, and allowlist (H2)

**Frozen by:** Slice H2 — Transcript validation, conversation budgets, and composer rendering
**Implements:** §4.3.5, §6.7.1, §6.7.3 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (H3, H4) **consume** this artifact; they may extend enforcement
sites but may not rewrite evaluation order, breach codes, or the allowlist-drop rule (delivery plan
§2.3).

**Source of truth in code:** `ai-platform/src/context/validator.ts` (conversational stage-6 path);
`ai-platform/src/context/preflight.ts` (unchanged stage-7; transcript included in serialized input).

**Traces to:** spec **Freezes** (transcript validation at the context validator; `context_invalid`
as shape/order rejection; whole-transcript accept-or-reject; shape before budgets;
`conversation_budget_exhausted`; permitted-key allowlist; per-turn cost via existing pre-flight);
FR-001, FR-007–FR-013, FR-019.

**Extends (does not rewrite):**
- C2 `ValidateResult` / stage-6–7 contracts — `single_shot` required/optional behaviour, estimator
  formula, and stage-7 predicates remain intact; conversational legs gain transcript checks and a
  `conversation_budget_exhausted` failure branch.
- H1 conversational Interaction fields and `permittedKeySet` — H2 enforces them at runtime; it does
  not redefine field keys or defaults.

---

## 1. Overview

For `interactionMode: "conversational"`, stage 6 validates the supplied transcript against the
closed wire shape (`transcript-wire.md`), then counts conversation budgets from that transcript
alone, and enforces the manifest's permitted key set as an allowlist. Stage 7 continues to price the
whole request — including the transcript — with no new cost mechanism.

---

## 2. Evaluation order (shape before budgets)

| Step | Check | Failure |
| --- | --- | --- |
| 1 | Transcript shape and `turn_ordinal` ordering (whole array); `context_requested.requests` elements via H1 `validateContextRequest` | `context_invalid` — stop; do not count budgets |
| 2 | Permitted-key allowlist (ordinary context + keys inside each `context_resolved.context`) | Drop unknown keys; do **not** reject |
| 3 | Published-shape (`validatePayload`) and per-value size (bounded by `Interaction.transcriptSizeLimit`) for permitted ordinary context and `context_resolved` values | `context_invalid` |
| 4 | Max history turns (count of turns in the supplied transcript) | `conversation_budget_exhausted` |
| 5 | Max context rounds per turn (consecutive `context_requested` turns at the transcript tail) | `conversation_budget_exhausted` |
| 6 | `Interaction.transcriptSizeLimit` over the serialized validated transcript | `conversation_budget_exhausted` |
| 7 | Existing stage-7 cost pre-flight over the serialized whole request (transcript included via `serializePreflightInput`) | `request_too_large` |

A malformed or out-of-order transcript MUST fail with `context_invalid` and MUST NOT emit a budget
code (FR-007). A well-formed transcript that is merely too long is never `context_invalid`
(FR-008). An omitted `transcript` field on a conversational leg is `context_invalid`; an explicit
empty array is a valid first leg. Non-numeric Interaction budget / size fields fail closed as
`conversation_budget_exhausted`.

---

## 3. Extended ValidateResult (conversational)

Stage 6 for conversational legs returns a discriminated union that **extends** C2's
`ValidateResult`:

| Branch | Shape | Meaning |
| --- | --- | --- |
| Success | `{ ok: true, filteredContext: Record<string, unknown>, … }` | Shape and budgets passed; filtered context retains only permitted keys (unknown keys dropped). May also surface the validated transcript for the composer. |
| Invalid shape/order | `{ ok: false, code: "context_invalid" }` | Malformed turn, unknown kind, or ordering violation (same code as C2 shape/tenant failures). |
| Budget breach | `{ ok: false, code: "conversation_budget_exhausted" }` | Max history turns or max context rounds breached. |

`single_shot` continues to emit only C2's `context_required` / `context_invalid` from
`validateContext` — H2 does not introduce budget codes on that path.

---

## 4. Budget counters (submitted transcript alone)

| Bound | Source (H1 manifest) | Counted as | Breach code |
| --- | --- | --- | --- |
| Max history turns | `Interaction.maxHistoryTurns` | Number of turns in the supplied `transcript` array | `conversation_budget_exhausted` |
| Max context rounds per turn | `Interaction.maxContextRoundsPerTurn` | Consecutive `context_requested` turns at the **tail** of the supplied transcript | `conversation_budget_exhausted` |
| Transcript size limit | `Interaction.transcriptSizeLimit` | UTF-8 byte length of the JSON-serialized validated transcript | `conversation_budget_exhausted` |
| Per-turn cost ceiling | Economics / existing pre-flight | Existing `runCostPreflight(manifest, serializePreflightInput({…, transcript}))` where `serializedInput` includes the transcript | `request_too_large` |

No platform-held conversation counter is consulted. No running conversation total. No §9.14
pre-flight reservation (FR-012; delivery plan §6.4).

---

## 5. Permitted-key allowlist

For conversational capabilities, the manifest's `permittedKeySet` is an allowlist at the validator:

- A key the manifest does not permit MUST NOT enter a prompt, even if the model requested it and the
  client supplied it.
- Unknown keys are **dropped**, not forwarded and not a rejection — including keys inside a
  `context_resolved` turn's `context` object (FR-011).
- This drop rule MUST NOT be used to silently discard a malformed turn (see `transcript-wire.md` §6).
- After the allowlist drop, remaining permitted values (ordinary supplied context and
  `context_resolved` payloads) MUST pass A5 `validatePayload` shape checks and a per-value byte
  size bound of `Interaction.transcriptSizeLimit` (§6.7.1 "shaped exactly as an ordinary context
  payload"; §4.3.5 sizes within bounds).

---

## 6. Trimmed transcript (R-22)

A client-trimmed transcript with `turn_ordinal` gaps that resets the round counter is **accepted**
for budget counting rather than rejected as integrity failure. Containment remains per-leg
authentication, rate limiting, cost check, and admission (FR-013; §6.7.3).

**Tenant check (C2 divergence):** The conversational path does **not** apply C2's
`suppliedContext.org` / `suppliedContext.branch` principal match. §4.3.5 does not name that check
for conversational capabilities; containment remains per-leg authn/admission and client-side RLS on
resolution. Documented here so the divergence from C2's frozen single-shot behaviour is explicit.

---

## 7. Prohibitions

- No conversation session store, no new pipeline stage, no per-request Durable Object or session
  object (FR-019).
- No second cost mechanism and no change to the §13.6.2 estimator.
- No rewrite of C2's `single_shot` required-key / `context_required` behaviour.

---

## 8. Out of scope of this contract

- Composer prior-turn rendering and dual output shapes — see `conversational-composition.md`.
- Writing `conversation_id` / `turn_ordinal` to the journal; client transcript ownership — H3.
- Stage-integration proofs that the request handler includes the transcript in pre-flight
  serialization and that `request_too_large` / `conversation_budget_exhausted` abort before egress —
  deferred until conversational pipeline wiring lands (H3 / request handler). H2 freezes
  `serializePreflightInput` as the seam those tests will call.
