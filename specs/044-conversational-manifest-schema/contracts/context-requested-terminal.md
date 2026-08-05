# Contract: `context_requested` terminal event and `AwaitingContext` (H1)

**Frozen by:** Slice H1 — Conversational manifest fields and context-request schema
**Implements:** §5.4 (absence), §5.5 rule 4, §6.3, §6.7.2, §6.7.4 of
`docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (H2, H3, E2) **consume** this artifact; they may extend payloads
carried by the event but may not rewrite the kind name, its terminal status, or its exclusion from
the §5.4 taxonomy (delivery plan §2.3).

**Source of truth in code:**

- `ai-platform/src/adapter.ts` — `context_requested` in the terminal event kind set; emission gated
  on `interactionMode === "conversational"`; `pushTerminalEvent` validates `context_request` via
  `validateContextRequest` (missing/malformed throws; no silent `[]` default).
- `ai-platform/src/journal/index.ts` — `AwaitingContext` as a terminal immutable §6.3 state;
  `canReachAwaitingContext` wired into `isJournalTransitionAllowed`, `journalTransition`, and
  `recordTerminalState` (optional `interactionMode`, default `single_shot`).
- `ai-platform/src/errors.ts` (A2, **CONSUMED unchanged**) — `context_requested` is not a
  `TaxonomyCode`. Unknown / non-taxonomy strings classify to `internal_error`; the error-body
  builder does **not** throw.

**Traces to:** spec **Freezes** (fourth terminal kind; not a taxonomy code; `AwaitingContext`
terminal immutable); FR-008, FR-009, FR-010, FR-011.

**Extends (does not rewrite):** `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md` (A6) —
A6 reserved `context_requested` for H1; the three existing terminal kinds and the
one-terminal-event invariant remain unchanged.

---

## 1. Terminal event kind `context_requested`

| Property | Value |
| --- | --- |
| Event type | `context_requested` |
| Role | Terminal SSE event — ends the stream |
| Mode | `conversational` capabilities only |
| Payload | Carries the keys (and arguments) the assistant needs — a conforming context request per `context-request-schema.md` |
| Emission validation | `pushTerminalEvent` requires `payload.context_request` and runs `validateContextRequest`; missing or malformed payloads throw — no silent `[]` default |
| Not an error | Must **not** appear in the §5.4 error taxonomy. A2 `errors.ts` is **unchanged**: forced string input of this literal classifies to `internal_error` (never throw from the error-body builder) |

A `single_shot` capability (including omitted/`default` mode) MUST never emit this kind. Clients that
only invoke `single_shot` capabilities therefore never observe it.

---

## 2. One-terminal-event invariant (unchanged)

Exactly one terminal event ends every stream:

- `completed` | `failed` | `cancelled` — all capabilities (A6)
- `context_requested` — conversational only (this freeze)

A conversational leg that ends in `context_requested` still emits **exactly one** terminal event.
Duplicate terminal emission remains forbidden under every path (A6 invariant extended, not rewritten).

---

## 3. Request state `AwaitingContext`

| Property | Value |
| --- | --- |
| State name | `AwaitingContext` |
| Graph | §6.3 — reachable from `Validating` when output is a valid context request |
| Reachability | `conversational` only — enforced by `canReachAwaitingContext` on allow-check and write path |
| Terminal | Yes — same class as `Completed`, `Failed`, `Cancelled`, `Rejected` |
| Immutable | No further state transition from `AwaitingContext` is allowed (SQL + helper) |
| Meaning | **That request is over.** Continuing the conversation is a **new** request with a **new** idempotency key, linked by `conversation_id` (H3 journaling). |

Naming it terminal (not a pause) is what keeps the platform free of in-flight conversation state
(§6.3; §6.7.4). `journalTransition` / `recordTerminalState` take optional `interactionMode`
(default `single_shot`) and refuse AwaitingContext writes for non-conversational mode.

---

## 4. What this freeze does not change

- No new §6.1 pipeline stage (stage 13 gains a second valid output shape later; stage 14 gains this
  fourth terminal kind — both parameterized by the manifest).
- No conversation table, no per-request Durable Object, no session store.
- No change to cancellation, idempotency, or the advisory rule.
- No new §5.4 taxonomy codes (`conversation_budget_exhausted` remains H2's runtime code, already
  present in A2's closed table for later use — H1 does not emit it).

---

## 5. Out of scope of this contract

- Validator acceptance of prose **or** context request as stage-13 output (H2).
- Client chat surface, transcript resupply, Resolver integration (H3).
- Stream-broker content relay changes beyond recognizing the terminal kind (D4 consumes A6 framing;
  H1's extension is the kind itself).
