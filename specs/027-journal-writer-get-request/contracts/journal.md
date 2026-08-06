# Contract: Journal writer, post-response detail, and get-request endpoint (C3)

**Frozen by:** Slice C3 — Journal writer, post-response detail, and get-request endpoint
**Implements:** §4.3.11, §6.1 stages 9/15/16, §6.3, §7.4, §7.4.1, §7.6, §5.5 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices (D3, D4, D6, F3) and the client-facing read path **consume** this
artifact; they extend, never rewrite the R2 envelope layout, the get-request response shape's
existing Completed/Failed/Cancelled success meanings, or the journal write-path timings and row
shapes. Additive branches and fields (auth, AwaitingContext, pending, Completed-without-result,
`routing_tier`, H3 helpers) are allowed under delivery plan §2.3.

**Source of truth in code:** `ai-platform/src/journal/index.ts` (exported types and functions listed
in §6).

**Traces to:** spec **Freezes** entries; FR-001–FR-012; A5 D1 schema
(`specs/019-ai-context-keys-d1-config/data-model.md`); A2 error taxonomy and request reference
(`ai-platform/src/errors.ts`, `ai-platform/src/reference.ts`); A3 `CanonicalResult`
(`specs/017-ai-canonical-inference/contracts/canonical-shapes.md`); A4/C1 resolved manifest
(`specs/018-ai-capability-manifest/contracts/manifest-schema.md`,
`specs/025-capability-resolver-discovery/contracts/capability-registry.md`); B3 request principal
(`specs/023-guard-stages/contracts/request-principal.md`); C2 filtered context
(`specs/026-context-validator-cost-preflight/contracts/context-validator.md`).

---

## 1. Overview

C3 owns the platform journal: the durable `ai_request` row created synchronously at stage 9 before
any inference work, every §6.3 state transition stamped on that row, the terminal-state update at
stage 15, and the post-response detail written at stage 16 (per-attempt `ai_attempt` rows, exactly one
`usage_event` row, and exactly one R2 payload envelope). A guard rejection produces no journal row
(rejection counting is owned by rate-limit/admission — see §4.1). The get-request endpoint is an
authenticated, installation-scoped read: it resolves a request reference to journaled state and, for
a completed request with a readable envelope, the validated result from the envelope.

This contract freezes three wire shapes downstream slices bind to:

1. **R2 payload envelope** — one JSON object per request at `request/{id}/envelope`.
2. **Get-request response** — `{ state, terminal_error_code?, result?, pending? }` returned by
   `GET /v1/requests/{reference}` (auth and branch table in §3).
3. **Journal write-path** — stage-9 row insert, §6.3 transition stamping, stage-15 terminal update,
   and stage-16 detail writes.

---

## 2. R2 payload envelope

### 2.1 Object key and format

| Property | Value |
| --- | --- |
| **Key** | `request/{request_id}/envelope` — `{request_id}` is the `ai_request.request_id` (ULID, A2). |
| **Content-Type** | `application/json` |
| **Cardinality** | Exactly **one** object per request. No second R2 object per request (§7.4.1). |

The `ai_request.payload_pointer` column stores this key after stage 16 completes successfully.

### 2.2 Document shape

The envelope is a single JSON object with exactly four top-level sections. No other top-level keys
are permitted on the wire.

```json
{
  "context": { },
  "prompt": { },
  "attempts": [ ],
  "result": { }
}
```

| Section | Type | Source slice | Contents |
| --- | --- | --- | --- |
| `context` | `Record<string, unknown>` | C2 | The filtered, declaration-conformant context payload — only manifest-declared keys that were supplied. C3 stores; C2 validates. |
| `prompt` | `unknown` | D1 | The composed, provider-bound prompt artifact. C3 stores; D1 composes. |
| `attempts` | `unknown[]` | D3/D4 | One element per provider attempt: the raw provider response body on success, or the error body on failure. C3 stores; D3/D4 produce. |
| `result` | `CanonicalResult` | D6 | The validated terminal payload. Field names are the A3 manifest (`specs/017-ai-canonical-inference/contracts/canonical-shapes.md` §4). C3 stores; D6 validates. |

### 2.3 Invariants

- All four sections MUST be present in every envelope, even when an attempt array is empty or the
  request failed (the `result` section still carries the terminal validated payload or its failure
  representation as produced by D6).
- The envelope is written once, in stage 16, via a single R2 `PutObject`. No partial writes, no
  per-chunk objects, no separate objects per section (§7.4, §7.4.1).
- Envelope content is platform-internal diagnostic data. Retention and purge are F3's responsibility;
  C3 writes only.

---

## 3. Get-request response

### 3.1 Endpoint

| Property | Value |
| --- | --- |
| **Method / path** | `GET /v1/requests/{reference}` |
| **Authentication** | Requires `Authorization: Bearer <AAT>`. The Worker verifies the token via §5.6 / B3 `EnrolledKeyVerifier` before calling `getRequest`. Missing or invalid token → **401** with taxonomy code `unauthenticated`. |
| **Reference input** | Path segment `{reference}` normalised via A2 `normalizeRequestReference` before lookup. |
| **Lookup** | Exactly one indexed D1 `SELECT` on `ai_request.request_reference` using
  `idx_ai_request_request_reference`. No second D1 query and no table scan (§7.6). |
| **Installation scope** | Lookup is scoped to `principal.installationId` (passed into `getRequest` as `installationId`). A row whose `installation_id` does not match is treated the same as an unknown reference → **404**. |

Authentication is the Worker's responsibility: it verifies the AAT, extracts `principal.installationId`,
and feeds that id into `getRequest`. The journal module does not parse Authorization headers.

### 3.2 Response body shape

```typescript
type GetRequestResponseBody = {
  state: TransitionState;
  terminal_error_code?: TaxonomyCode; // present only when state === "Failed"
  result?: CanonicalResult;          // present only when state === "Completed" and the envelope result is available
  pending?: true;                    // present only for in-flight (non-terminal) states
};
```

`TransitionState` and `TaxonomyCode` are defined in §5.1 and A2 respectively.

Existing success shapes for `Completed` (with `result`), `Failed`, and `Cancelled` keep their
meanings; this section only adds branches and optional fields (delivery plan §2.3 — extend, do not
rewrite).

### 3.3 Response branches

| Journaled `state` / condition | HTTP status | Body fields | R2 read |
| --- | --- | --- | --- |
| `Completed` with non-null `payload_pointer`, readable envelope, valid JSON | 200 | `state`, `result` | One `GetObject` on `payload_pointer` only; parse envelope JSON; return the `result` section only. |
| `Completed` with missing/null `payload_pointer`, missing R2 object, or corrupt envelope JSON | 200 | `{ state: "Completed" }` — **no** `result` | `GetObject` only when `payload_pointer` is non-null; if the object is missing or JSON is corrupt, omit `result` (not 404). |
| `Failed` | 200 | `state`, `terminal_error_code` | **None** — no content / no `result` field (§5.5, §7.6). |
| `Cancelled` | 200 | `state` only | **None** (§5.5, §7.6). |
| `AwaitingContext` | 200 | `state` only | **None**. |
| In-flight (`Accepted` / `Composing` / `Invoking` / `Streaming` / `Validating` / `Repairing`) | 200 | `{ state, pending: true }` | **None**. |
| Unknown reference, or `installation_id` mismatch | 404 | A2 diagnostic envelope is **not** required for not-found; an empty 404 or minimal JSON body is acceptable. C3 does not emit a taxonomy code for not-found. |
| Missing / invalid `Authorization` | 401 | Taxonomy `unauthenticated` (Worker auth gate; never reaches `getRequest`). | **None**. |

**Pointer rule:** R2 `GetObject` runs **only** when `payload_pointer` is non-null. There is no
derived-key fallback (e.g. synthesising `request/{request_id}/envelope` when the pointer is NULL).

### 3.4 Distinction from F3

This endpoint is the **client-facing** read path: journaled state plus validated result when
available. F3's operator-only support lookup returns the full trace and the whole envelope; it is a
separate surface and consumes the envelope layout frozen here without changing it.

---

## 4. Journal write-path contract

### 4.1 Guard rejection (stages 1–8)

A request rejected before stage 9 produces:

| Action | Count |
| --- | --- |
| `ai_request` INSERT | **0** |
| `platform_counter` increment | **1** (rejection counted, not journaled) |

There is no `Rejected` row in D1. The `Rejected` terminal state in §6.3 is represented by the
**absence** of a row (§6.2, §7.5).

**Ownership:** Guard-rejection counting (`platform_counter` increment) is owned by the rate-limit /
admission modules (B3/B4 live path). The journal module does **not** export
`recordGuardRejection` / `flushGuardRejectionCounters`. The invariant above is unchanged: 0
`ai_request` inserts, 1 `platform_counter` increment per rejection.

### 4.2 Stage 9 — `createRequestRow` (synchronous, pre-work)

**Timing:** Runs after the guard has passed and admission has succeeded (B4), and **before** any
inference work — specifically before prompt composition (stage 10) and provider invocation (stage 11).
A provider-call spy MUST observe the `ai_request` row already present (FR-001).

**Operation:** One synchronous D1 `INSERT` into `ai_request`.

#### 4.2.1 Row shape at insert

| Column | Source | Value at stage 9 |
| --- | --- | --- |
| `request_id` | Caller | ULID (A2) — primary identity. |
| `request_reference` | A6 | The reference carried in the `accepted` event (`XXXX-XXXX`, stored unchanged). |
| `installation_id` | B3 `Principal.installationId` | Required. |
| `actor_id` | B3 `Principal.actorId` | Required. |
| `branch_id` | B3 `Principal.branchId` | Nullable when not branch-scoped. |
| `capability_id` | C1 `Manifest.Identity.capabilityId` | Required. |
| `capability_version` | C1 `Manifest.Identity.version` | Required. |
| `prompt_artifact_hash` | C1 `Manifest["Prompt binding"].systemInstructionArtifactRef` | The manifest-pinned hash — known at stage 9, before D1 composes the prompt (§5.7). |
| `idempotency_key` | Caller | Client idempotency key. |
| `trace_id` | B3 / caller | Distributed trace identifier. |
| `state` | C3 | `"Accepted"` — initial §6.3 state. |
| `created_at` | C3 | ISO-8601 timestamp of insert. |
| `updated_at` | C3 | Same as `created_at` on insert. |
| `completed_at` | — | `NULL` |
| `terminal_error_code` | — | `NULL` |
| `payload_pointer` | — | `NULL` until stage 16. |
| `conversation_id` | Caller / H3 | `NULL` for `interactionMode: "single_shot"`; set when present on conversational legs. |
| `turn_ordinal` | Caller / H3 | `NULL` for `single_shot`; set when present on conversational legs. |
| `routing_tier` | `RequestRowInput.routingTier` | `"standard"` \| `"degraded"` \| `NULL` when omitted. Soft-threshold routing annotation; not required for single-shot stage-9 insert. |

#### 4.2.2 Failure behaviour

If the D1 `INSERT` fails, `createRequestRow` returns
`{ ok: false; code: "internal_error"; request_reference: string; trace_id: string }`
(built via A2 `buildErrorBody` / equivalent diagnostic fields). The request MUST fail
**before** the provider is called. This is the only taxonomy code C3's own stages emit to the client
(FR-001; stages 15 and 16 emit no client-facing error).

On success: `{ ok: true }`.

### 4.3 §6.3 transition stamping — `journalTransition`

Every non-terminal state change overwrites `ai_request.state` and stamps `ai_request.updated_at`.
There is **no** per-transition history table — the §6.3 amendment confirms the three milestone
timestamps (`created_at`, `updated_at`, `completed_at`) plus the deterministic §6.3 graph recover the
timeline (§8.9).

#### 4.3.1 Closed state set

```typescript
type TransitionState =
  | "Accepted"
  | "Composing"
  | "Invoking"
  | "Streaming"
  | "Validating"
  | "Repairing"
  | "AwaitingContext"
  | "Completed"
  | "Failed"
  | "Cancelled";
```

`Rejected` is terminal in §6.3 but is never written to D1 (see §4.1). `Completed`, `Failed`,
`Cancelled`, and `AwaitingContext` are terminal and immutable once reached.

#### 4.3.2 `journalTransition(requestId, state, now, db)`

| `state` argument | D1 columns updated |
| --- | --- |
| Any non-terminal state | `state`, `updated_at` ← `now` |
| `Completed`, `Failed`, `Cancelled`, or `AwaitingContext` | `state`, `updated_at` ← `now`, `completed_at` ← `now` |

**Immutability:** The `UPDATE` is conditional on the row's current state being non-terminal
(`WHERE request_id = ? AND state NOT IN (<terminal immutable set>)`, or equivalent consultation of
`isJournalTransitionAllowed`). If the row is already terminal, the write is a no-op (row unchanged).

Terminal transitions MAY additionally set `terminal_error_code` when `state === "Failed"` — see
§4.4 (`recordTerminalState` is the stage-15 entry point for terminal updates).

### 4.4 Stage 15 — `recordTerminalState` (synchronous, terminal)

**Timing:** Runs when the pipeline reaches a terminal outcome, after the terminal SSE event is about
to be emitted (stage 14 precedes stage 16).

**Operation:** One D1 `UPDATE` on the existing `ai_request` row (the row is already durable from
stage 9), conditional on the row still being non-terminal (same immutability rule as §4.3.2). If the
row is already terminal, the writer is a **no-op**.

| Terminal `state` | Columns set |
| --- | --- |
| `Completed` | `state`, `updated_at`, `completed_at`; `terminal_error_code` remains `NULL`. |
| `Failed` | `state`, `updated_at`, `completed_at`, `terminal_error_code` ← taxonomy code from D3/D4/D6 (recorded, not generated by C3). **Requires** a taxonomy code — callers that omit it MUST be rejected (throw / typed failure); a `Failed` row MUST NOT be written with a NULL `terminal_error_code`. |
| `Cancelled` | `state`, `updated_at`, `completed_at`; `terminal_error_code` remains `NULL`. |
| `AwaitingContext` | `state`, `updated_at`, `completed_at`; `terminal_error_code` remains `NULL` (when reached via this entry point). |

**Failure behaviour:** Stage 15 MUST NOT emit an error to the client. The row update is to an
already-durable row (FR-004). A failed generation leaves the row present with the failure's terminal
state — the row is never deleted (FR-006).

C3 does **not** invoke the Quota Durable Object credit call (B4's stage-15 responsibility). C3
updates the journal row only.

### 4.5 Stage 16 — `writePostResponseDetail` (post-response, `ctx.waitUntil`)

**Timing:** Scheduled via `ctx.waitUntil` **after** the terminal event has been emitted to the client
(stage 14 precedes stage 16). All stage-16 I/O is off the hot path.

**Failure behaviour:** Any R2 or D1 failure inside the continuation is swallowed after being logged
via `console.error` with at least the `request_id` (and trace id when available). The failure MUST
NOT change the terminal state already emitted and MUST NOT surface an error to the client (FR-009).

D1 `ai_attempt` + `usage_event` writes use `db.batch` so attempts-plus-ledger fail together. R2
`PutObject` and the subsequent `payload_pointer` update remain sequential relative to that batch.

**Accepted partial states:** Because R2 put and pointer update are not one atomic unit with the D1
batch, a partial outcome is possible and tolerated — notably an R2 object written without a
non-null `payload_pointer` if the pointer `UPDATE` fails after a successful put. Get-request treats
that as `Completed` without `result` (§3.3). No client-visible error is emitted.

#### 4.5.1 Writes performed (one continuation per request)

| # | Target | Count | Notes |
| --- | --- | --- | --- |
| 1 | `ai_attempt` INSERT | N | One row per provider attempt (N = 1–3 typical). Never one row per stream chunk (§7.5). |
| 2 | `usage_event` INSERT | **1** | Exactly one ledger row per request. `quota_weight` from `Manifest.Economics.quotaWeight`. |
| 3 | R2 `PutObject` | **1** | Key `request/{request_id}/envelope`; body is `buildEnvelope(input)` JSON (§2). |
| 4 | `ai_request` UPDATE | **1** | Sets `payload_pointer` to the envelope key. |

#### 4.5.2 `ai_attempt` row shape (per attempt)

| Column | Source |
| --- | --- |
| `attempt_id` | Generated ULID |
| `request_id` | Parent request |
| `attempt_no` | 1-based sequence |
| `provider` | From attempt metadata (D3) |
| `model` | From attempt metadata (D3) |
| `outcome` | Attempt outcome string |
| `latency_ms` | Measured latency |
| `tokens_in` | Input token count |
| `tokens_out` | Output token count |
| `cost` | Attempt cost |
| `provider_request_id` | Provider-assigned id, nullable |
| `error_code` | A2 taxonomy code on failure, nullable |

#### 4.5.3 `usage_event` row shape

| Column | Source |
| --- | --- |
| `usage_event_id` | Generated ULID |
| `installation_id` | B3 `Principal.installationId` |
| `period` | Current billing period key |
| `request_id` | Parent request |
| `quota_weight` | C1 `Manifest.Economics.quotaWeight` |
| `tokens` | Aggregated token count from attempts |
| `cost` | Aggregated cost from attempts |
| `recorded_at` | ISO-8601 timestamp |

#### 4.5.4 Input to `writePostResponseDetail`

```typescript
type AttemptInput = {
  attemptNo: number;
  provider: string;
  model: string;
  outcome: string;
  latencyMs: number;
  tokensIn: number;
  tokensOut: number;
  cost: number;
  providerRequestId?: string;
  errorCode?: TaxonomyCode;
  rawBody: unknown; // stored in envelope attempts[]
};

type PostResponseInput = {
  requestId: string;
  installationId: string;
  period: string;
  quotaWeight: number;
  totalTokens: number;
  totalCost: number;
  filteredContext: Record<string, unknown>; // C2 output → envelope context
  composedPrompt: unknown;                   // D1 output → envelope prompt
  attempts: AttemptInput[];
  validatedResult: CanonicalResult;          // D6 output → envelope result
  recordedAt: string;
};
```

`buildEnvelope(input: PostResponseInput): string` is an internal helper (not exported) that serialises
the four §2 sections to JSON.

---

## 5. Exported module surface

**File:** `ai-platform/src/journal/index.ts`

### 5.1 Types

| Type | Role |
| --- | --- |
| `TransitionState` | Closed §6.3 state union (§4.3.1). |
| `RequestRowInput` | Arguments for stage-9 insert (principal, manifest, reference, idempotency key, ids, optional conversation fields, optional `routingTier`: `"standard"` \| `"degraded"`). |
| `AttemptInput` | Per-attempt metadata for stage 16 (§4.5.4). |
| `PostResponseInput` | Full stage-16 payload (§4.5.4). |
| `Envelope` | Typed representation of the four envelope sections (internal to builder; shape matches §2). |
| `GetRequestResult` | Discriminated union returned by `getRequest` — see §5.2. |
| `ConversationLegRow` | H3 conversation-leg row shape returned by `listConversationLegs`. |

### 5.2 `getRequest` result union

```typescript
type InFlightState =
  | "Accepted"
  | "Composing"
  | "Invoking"
  | "Streaming"
  | "Validating"
  | "Repairing";

type GetRequestResult =
  | { found: true; state: "Completed"; result: CanonicalResult }
  | { found: true; state: "Completed" } // resultMissing — no result field
  | { found: true; state: "Failed"; terminalErrorCode: TaxonomyCode }
  | { found: true; state: "Cancelled" }
  | { found: true; state: "AwaitingContext" }
  | { found: true; state: InFlightState; pending: true }
  | { found: false };
```

The first `Completed` branch (with `result`) and the `Failed` / `Cancelled` / `found: false`
branches keep their existing meanings. `AwaitingContext`, `pending`, and `Completed` without
`result` are additive (delivery plan §2.3).

### 5.3 Functions

| Function | Stage | Returns |
| --- | --- | --- |
| `createRequestRow(input, db)` | 9 | `{ ok: true } \| { ok: false; code: "internal_error"; request_reference: string; trace_id: string }` |
| `journalTransition(requestId, state, now, db)` | §6.3 | `void` (no-op when row already terminal; throws or no-ops on D1 failure per implementation; stage 9 is the only client-visible failure) |
| `recordTerminalState(requestId, state, terminalErrorCode?, now, db)` | 15 | `void` — no-op when already terminal; **rejects/throws** if `state === "Failed"` and `terminalErrorCode` is omitted |
| `writePostResponseDetail(input, { db, r2, ctx })` | 16 | `void` — schedules continuation; returns immediately |
| `getRequest(reference, { db, r2, installationId })` | read | `GetRequestResult` — `installationId` scopes the lookup to that installation (mismatch → `{ found: false }`). Auth is the Worker's responsibility: verify AAT via §5.6 / B3 `EnrolledKeyVerifier`, then pass `principal.installationId`. |
| `listConversationLegs(…)` | H3 read | Conversation leg rows for a conversation (`ConversationLegRow[]`) |
| `canReachAwaitingContext(…)` | H3 / §6.3 | Whether a transition to `AwaitingContext` is allowed from the current state |
| `isJournalTerminalState(state)` | §6.3 | `true` when `state` is terminal/immutable |
| `isJournalTransitionAllowed(from, to)` | §6.3 | Transition legality helper (writers enforce immutability even if a caller skips this) |
| `JOURNAL_TERMINAL_IMMUTABLE_STATES` | §6.3 | Frozen list of terminal immutable states |

**Not on the journal surface:** `recordGuardRejection` / `flushGuardRejectionCounters` — live rejection
counting lives in the rate-limit / admission modules (§4.1).

No Durable Object I/O. No per-request server-side state object (§4.4, §9.7).

---

## 6. Prohibitions (delivery plan §6.4)

C3 and every consumer of this contract MUST NOT:

| Prohibition | Rationale |
| --- | --- |
| Write a second R2 object per request | §7.4.1 — metered footprint stays proportional to requests. |
| Journal a guard rejection as an `ai_request` row | §6.2, §7.5 — cheap-rejection path stays cheap. |
| Write one D1 row per stream chunk | §7.5 — chunks are relayed, not journaled individually. |
| Introduce per-request server-side state | §4.4, §9.7 — the D1 row is the durable record. |
| Surface stage-16 failures to the client | §6.1 stage 16 — terminal event already emitted. |
| Perform a second indexed D1 lookup on get-request | §7.6 — one query on `request_reference`. |
| Read R2 for `Failed`, `Cancelled`, `AwaitingContext`, or in-flight get-request | §7.6 / §3.3 — no content to return. |
| Derive envelope key when `payload_pointer` is NULL | §3.3 — GetObject only on a non-null pointer. |
| Invoke the Quota DO from C3 | B4 owns stage-15 credit; C3 updates the journal row only. |
| Export guard-rejection tally helpers from the journal module | §4.1 — counting is rate-limit / admission owned. |

---

## 7. Consumer binding summary

| Consumer slice | Binds to | Usage |
| --- | --- | --- |
| **D3** / **D4** | `attempts[]` section; `AttemptInput` | Supplies per-attempt raw bodies and attempt-row metadata for stage 16. |
| **D1** | `prompt` section | Supplies composed prompt stored in envelope. |
| **D6** | `result` section; `CanonicalResult` | Supplies validated terminal payload stored in envelope and returned on get-request for `Completed`. |
| **F3** | Full envelope layout; `payload_pointer` | Operator support lookup reads the whole envelope; retention purges use `request_id` keys. |
| **Client** (via `GET /v1/requests/{reference}`) | Get-request response shape (§3) | Polls terminal state and validated result after submit. |
