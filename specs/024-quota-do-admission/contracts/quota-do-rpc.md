# Contract: Quota Durable Object RPC wire shapes (B4)

**Frozen by:** Slice B4 — Quota Durable Object and admission stage
**Implements:** §4.3.3, §4.4, §6.1 stages 8 and 15, §6.6, §7.7, §9.17 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices (C3 journal writer, F4 soft-threshold routing) **consume** this artifact;
the no-rework rule applies (Delivery Plan §2.3). A later slice may **extend** (e.g. F4 routes on optional
`degraded` from the admission response) but may not **rewrite** the field set, discriminant
values, or transport shape below.

**Source of truth in code:** `ai-platform/src/quota-do/index.ts` (RPC handlers and ephemeral entry
types); `ai-platform/src/admission/index.ts` and `ai-platform/src/credit/index.ts` (callers);
`GatewayObject` dispatch in `ai-platform/src/worker.ts`.

**Traces to:** spec FR-001, FR-004–FR-010, FR-016; `## Slice Contract → Freezes` (admission RPC, credit
RPC, in-object ephemeral store).

---

## 1. Overview

The per-installation **Quota Durable Object** is the platform's only stateful side-car. One instance
per `installationId` holds the entitlement snapshot (read-only, supplied by the caller), period
counters, the in-flight count, and two ephemeral maps — the `jti` replay set and idempotency records
(§4.4; §7.7).

All interaction is over **two RPC kinds** on the same DO instance:

| RPC | Pipeline stage | Purpose |
| --- | --- | --- |
| `admission` | 8 | One round trip answers `jti` freshness, idempotency novelty, remaining budget, and concurrency headroom |
| `credit` | 15 | Settles actual token/cost usage (including partial usage on cancellation) and decrements in-flight |

There is no third DO round trip per request lifecycle (§7.5; FR-016). No pre-flight cost reservations
(FR-015).

---

## 2. Transport

Callers reach the installation-scoped instance via the A1 `DO → GatewayObject` binding unchanged:

```ts
const id = env.DO.idFromName(installationId);
const stub = env.DO.get(id);
const response = await stub.fetch("https://quota-do.internal/rpc", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(rpcBody),
});
```

The URL path is an internal convention; only the JSON body is normative. The handler dispatches on
the top-level `kind` discriminant (`"admission"` | `"credit"`).

`installationId` on both RPC bodies **must** match the DO-bound installation id. The first
successful admission binds `boundInstallationId` in DO storage; a later request whose
`installationId` does not match throws / returns a non-2xx that the callers surface as a client
error (`400` / `unknown_request` on credit). Callers always derive the stub with
`idFromName(installationId)` so the body id and the instance id stay aligned.

Optional injectable clock for ephemeral-sweep tests: the GatewayObject RPC body may carry
`now?: number` (epoch milliseconds). When present and finite, `admissionRPC` / `creditRPC` use it
instead of `Date.now()` for lazy sweep and expiry. Production callers omit `now`.

Responses use `Content-Type: application/json`. Non-2xx from `fetch` is a transport failure (the
stage-8 caller's fail-open grace path — §15 #3 — is **not** part of this wire contract; it lives in
`src/admission/`).

---

## 3. Plan-time constants

These values are frozen at plan time (R-20). They are **not** runtime configuration surfaces and are
**not** stored in the D1 `entitlement` row.

| Constant | Value | Semantics |
| --- | --- | --- |
| `EPHEMERAL_HORIZON_MS` | `7_200_000` (2 hours) | Retention for in-object `jti` replay and idempotency entries (§7.7 `ephemeral` class — minutes to hours). New entries receive `expiresAt = now + EPHEMERAL_HORIZON_MS`. |
| `CONCURRENCY_LIMIT` | `16` | Per-installation in-flight ceiling. Not in the entitlement table; enforced only inside the Quota DO (§4.3.3). Admission rejects when `inFlight >= CONCURRENCY_LIMIT`. |
| `GRACE_ADMISSION_CAP` | `5` | Maximum admissions the stage-8 caller may serve without a successful DO round trip during Quota DO unavailability (Open Decision 3 / §15 #3). Consumed by `src/admission/`, not by the DO handler. |

---

## 4. Entitlement snapshot (wire payload)

Admission carries the entitlement snapshot the stage-8 caller loaded through A5's `loadConfig(cache,
reader, "entitlements", installationId)` seam (Clarification Q2). Field names and nesting match the
A5 `entitlements` cache kind; B4 does not redefine the D1 schema.

```ts
interface EntitlementSnapshot {
  plan: string;
  period_bounds: {
    period_start: string; // ISO-8601 instant
    period_end: string;   // ISO-8601 instant
  };
  request_quota: number;  // INTEGER — max requests in period
  token_cost_budget: {
    token_budget: number; // INTEGER — max tokens in period
    cost_budget: number;  // REAL — max cost in period
  };
  allowed_capabilities: string[]; // parsed from D1 `allowed_capabilities` TEXT
  soft_threshold: number;         // REAL — B4 may set `degraded` when crossed; F4 routes
  status: string;                 // e.g. `active`, `pending`, `suspended`
}
```

The Quota DO treats the snapshot as **read-only input** on each admission call. It updates its own
period counters from credits; it does not write back to D1 or the config cache.

---

## 5. RPC envelope

Every request body is a JSON object with a required `kind` discriminant:

```ts
type QuotaDoRequest = AdmissionRequest | CreditRequest;
```

Every response body is a JSON object whose shape is determined by `kind` and (for admission) `outcome`.

---

## 6. Admission RPC

### 6.1 Request (`kind: "admission"`)

| Field | Type | Required | Source |
| --- | --- | --- | --- |
| `kind` | `"admission"` | Yes | Literal discriminant |
| `jti` | `string` | Yes | B3 `Principal.jti` (B1 AAT claim) |
| `installationId` | `string` | Yes | B3 `Principal.installationId`; must match the DO-bound id (`idFromName`); first admission binds |
| `idempotencyKey` | `string` | Yes | A6-parsed `Idempotency-Key` header |
| `entitlement` | `EntitlementSnapshot` | Yes | A5 config cache `entitlements` kind |
| `requestReference` | `string` | Yes | A6 adapter `requestReference` — stored on a fresh admit for idempotent replay |

Example:

```json
{
  "kind": "admission",
  "jti": "f4000000-0000-4000-8000-000000000001",
  "installationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "idempotencyKey": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
  "requestReference": "AI-7X2K9M",
  "entitlement": {
    "plan": "standard",
    "period_bounds": {
      "period_start": "2026-08-01T00:00:00.000Z",
      "period_end": "2026-09-01T00:00:00.000Z"
    },
    "request_quota": 1000,
    "token_cost_budget": {
      "token_budget": 500000,
      "cost_budget": 50.0
    },
    "allowed_capabilities": ["ai.access"],
    "soft_threshold": 0.8,
    "status": "active"
  }
}
```

### 6.2 Response — discriminated `outcome`

The handler performs a lazy ephemeral sweep (evict entries with `expiresAt <= now`) before
answering (Clarification Q5). Evaluation order inside the atomic read-modify-write:

1. Repeat `jti` → `replay`
2. Repeat `idempotencyKey` → `idempotent` with `priorState`
3. Budget exhausted → `quota_exhausted`
4. `inFlight >= CONCURRENCY_LIMIT` → `concurrency_exhausted`
5. Otherwise → `admitted`

```ts
type AdmissionResponse =
  | AdmissionAdmitted
  | AdmissionReplay
  | AdmissionIdempotent
  | AdmissionQuotaExhausted
  | AdmissionConcurrencyExhausted;

interface AdmissionAdmitted {
  kind: "admission";
  outcome: "admitted";
  requestId: string; // UUID — correlates the stage-15 credit call
  /**
   * Optional contract extension: true when any period usage ratio
   * (requests / tokens / cost) has crossed `entitlement.soft_threshold`.
   * B4 computes and exposes the flag; F4 owns degraded-tier routing on it.
   */
  degraded?: boolean;
}

interface AdmissionReplay {
  kind: "admission";
  outcome: "replay";
}

interface AdmissionIdempotent {
  kind: "admission";
  outcome: "idempotent";
  priorState: IdempotencyPriorState;
}

interface AdmissionQuotaExhausted {
  kind: "admission";
  outcome: "quota_exhausted";
  /** ISO-8601 period end — matches §5.4 period-reset instant for `quota_exhausted`. */
  period_end: string;
}

interface AdmissionConcurrencyExhausted {
  kind: "admission";
  outcome: "concurrency_exhausted";
}
```

#### 6.2.1 `IdempotencyPriorState`

Carried on `idempotent` outcomes so callers and tests can prove "returns existing request state"
instead of starting a second inference (FR-005; §6.6).

| Field | Type | Semantics |
| --- | --- | --- |
| `requestReference` | `string` | The support/audit reference for the original request |
| `state` | `IdempotencyRequestState` | Terminal or in-progress state of the original request |
| `requestId` | `string` | The DO-issued id from the original admission — same value the credit RPC expects |

```ts
type IdempotencyRequestState =
  | "admitted"      // admitted, journal not yet terminal
  | "in_progress"   // journal row exists, inference running
  | "completed"
  | "failed"
  | "cancelled"
  | "awaiting_context"; // conversational leg only
```

On a fresh `admitted` outcome, the DO:

- Records `jti` in the replay set with `expiresAt`
- Records `idempotencyKey` → `{ priorState fields, expiresAt }`
- Increments `inFlight`
- Does **not** increment period usage counters (credit does that at stage 15)

#### 6.2.2 Stage-8 caller mapping

The admission stage caller (`src/admission/`) maps DO outcomes to pipeline results:

| `outcome` | Caller result | Taxonomy / notes |
| --- | --- | --- |
| `admitted` | Proceed; carry `requestId` (and optional `degraded`) to stage 15 / F4 | Soft-threshold flag is an allowed extension; F4 routes |
| `replay` | Reject | `unauthenticated` (§6.2 — replay is post-identity) |
| `idempotent` | Return `priorState`; no second inference | — |
| `quota_exhausted` | Reject; surface `period_end` as period reset | `quota_exhausted` (§5.4) |
| `concurrency_exhausted` | Reject | Maps to caller `quota_exhausted` (§6.1 / closed §5.4) — DO-internal outcome only |

---

## 7. Credit RPC

### 7.1 Request (`kind: "credit"`)

Settles actual usage at stage 15 (§6.1; FR-008). Exactly one credit call per admitted request.

| Field | Type | Required | Semantics |
| --- | --- | --- | --- |
| `kind` | `"credit"` | Yes | Literal discriminant |
| `installationId` | `string` | Yes | Must match the DO-bound installation id (else `unknown_request`) |
| `requestId` | `string` | Yes | `requestId` from the matching `admitted` admission response |
| `requestReference` | `string` | Yes | Echo of admission `requestReference` — correlation for tests and reconciliation |
| `usage` | `UsageActual` | Yes | Actual token and cost consumed |
| `partial` | `boolean` | Yes | `true` when the request was cancelled mid-stream; still credits consumed tokens/cost (§6.4) |

```ts
interface UsageActual {
  tokens: number; // non-negative integer — total tokens (input + output + cached)
  cost: number;   // non-negative real — platform-normalized cost units
}
```

Example:

```json
{
  "kind": "credit",
  "installationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "requestId": "b5000000-0000-4000-8000-000000000002",
  "requestReference": "AI-7X2K9M",
  "usage": { "tokens": 842, "cost": 0.0031 },
  "partial": false
}
```

### 7.2 Response

```ts
type CreditResponse = CreditAcknowledged | CreditUnknownRequest;

interface CreditAcknowledged {
  kind: "credit";
  ok: true;
  periodCounters: PeriodCounters; // post-credit snapshot — observable in DO unit tests
}

interface CreditUnknownRequest {
  kind: "credit";
  ok: false;
  code: "unknown_request"; // `requestId` not found or already credited
}
```

On `ok: true`, the DO:

- Adds `usage.tokens` / `usage.cost` to period counters (and increments request count by 1)
- Decrements `inFlight` (floored at 0)
- Removes the `requestId` from `admittedRequests` and records it in `creditedRequests` (both
  ephemeral-horizon bounded — see §9)
- Closes the matching idempotency record to `completed` (or `cancelled` when `partial: true`) so a
  repeat key returns the settled prior state

The `partial` flag does not change the arithmetic — it is carried for journaling and for the
idempotency close (`cancelled` vs `completed`). Partial and complete credits use the same counter
adjustment.

#### 7.2.1 `PeriodCounters`

```ts
interface PeriodCounters {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
  inFlight: number;
}
```

---

## 8. In-object ephemeral entry shape

Ephemeral records live inside the Quota DO only (§7.7; §9.17). They expire in place — no D1 table, no
`alarm()` handler (Clarification Q5). Every entry carries an `expiresAt` wall-clock (epoch
milliseconds).

### 8.1 Common envelope

```ts
interface EphemeralEntry {
  expiresAt: number; // epoch ms; set to now + EPHEMERAL_HORIZON_MS on insert
}
```

### 8.2 `jti` replay set

Keyed by `jti` string. Value is the envelope only — presence proves replay.

```ts
type JtiReplayEntry = EphemeralEntry;
```

### 8.3 Idempotency records

Keyed by `idempotencyKey` string. Value extends the envelope with the state returned on repeat.

```ts
interface IdempotencyEntry extends EphemeralEntry {
  requestReference: string;
  state: IdempotencyRequestState;
  requestId: string;
}
```

Lazy sweep: on each `admission` RPC, delete any `jti` or idempotency entry whose `expiresAt <= now`
before evaluating the new request (test `ephemeral_entries_expire_in_place`).

---

## 9. In-object durable fields (not RPC payload)

These are persisted in the DO's `ctx.storage` but are not sent on the wire. Documented so tests and
later slices know what the handlers own.

| Field | Type | Role |
| --- | --- | --- |
| `periodCounters` | `PeriodCounters` | Running totals for the current entitlement period |
| `periodBounds` | `{ period_start, period_end }` | Last entitlement period applied (rollover trigger) |
| `boundInstallationId` | `string` | Set on first admission; mismatch rejects later RPCs |
| `jtiReplay` | `Map<string, JtiReplayEntry>` | Seen `jti` values (ephemeral horizon) |
| `idempotency` | `Map<string, IdempotencyEntry>` | Idempotency key → prior state (ephemeral horizon) |
| `admittedRequests` | `Map<string, { requestReference, admittedAt }>` | In-flight `requestId` awaiting credit — **ephemeral-horizon bounded** (abandoned admissions are swept and decrement `inFlight`) |
| `creditedRequests` | `Map<string, { expiresAt }>` | `requestId` values already credited — **ephemeral-horizon bounded**, not a permanent set |

Period rollover: when an admission carries `entitlement.period_bounds` outside the stored period, the
DO resets usage counters (`requestsUsed` / `tokensUsed` / `costUsed`) before evaluating; `inFlight`
is carried across the rollover (exact rollover rules are implementation detail; counter reset is
observable in tests).

---

## 10. Consumers

| Slice / module | Binding |
| --- | --- |
| **B4 `src/admission/`** | Builds `AdmissionRequest`; maps `AdmissionResponse` to stage-8 outcomes; applies `GRACE_ADMISSION_CAP` on transport failure |
| **B4 `src/credit/`** | Builds `CreditRequest` with `requestId`, `requestReference`, `usage`, `partial` |
| **B4 `src/quota-do/`** | Implements handlers; owns ephemeral maps and `PeriodCounters` |
| **B4 `worker.ts`** | Dispatches `fetch` body `kind` (and optional `now`) to `admissionRPC` / `creditRPC`; `scheduled` runs `reconcileGraceUsage` + rejection flush |
| **C3 (journal writer)** | Consumes `requestId` / `requestReference` correlation; may further refine `IdempotencyRequestState` (e.g. `in_progress`, `failed`, `awaiting_context`). Credit already closes to `completed` / `cancelled` on settlement — C3 does not uniquely own state updates |
| **F4 (soft threshold)** | Reads optional `degraded` on `AdmissionAdmitted` (and may still derive remaining budget from `periodCounters` / `entitlement`) — routing owner; B4 only exposes the flag |

---

## 11. Out of scope for this contract

| Behaviour | Owner | Reason |
| --- | --- | --- |
| Fail-open grace and reconciliation wire shape | `src/admission/` | Open Decision 3 policy; uses `GRACE_ADMISSION_CAP` locally |
| HTTP / SSE error envelope | A6 adapter | B4 emits taxonomy codes at the stage layer |
| Entitlement D1 schema | A5 / B2 | Snapshot is consumed, not redefined |
| `platform_counter` rejection tally | B3 discipline | Same bucketing; no new counter shape |
| Pre-flight cost reservations | — | Explicitly forbidden (FR-015) |
| Third DO round trip | — | Forbidden (§7.5; FR-016) |

---

## 12. Verification

Contract behaviour is enforced by `ai-platform/test/quota-do.test.ts` (DO unit + concurrency) and
`ai-platform/test/admission-credit.test.ts` (integration spy):

| Test | Asserts |
| --- | --- |
| `admission_fresh_jti_accepted` | `outcome: "admitted"` + `requestId` |
| `admission_repeated_jti_rejected` | `outcome: "replay"` |
| `admission_new_idempotency_key_accepted` | `outcome: "admitted"` |
| `admission_repeat_idempotency_key_returns_prior_record` | `outcome: "idempotent"` + `priorState` |
| `admission_budget_exhaustion_rejected` | `outcome: "quota_exhausted"` |
| `admission_concurrency_ceiling_rejected` | `outcome: "concurrency_exhausted"` |
| `credit_adjusts_counters_with_actual_usage` | `CreditAcknowledged.periodCounters` delta |
| `credit_adjusts_counters_with_partial_usage` | Credit with `partial: true` |
| `parallel_admissions_exact_final_count` | Serialized `inFlight` / `requestsUsed` |
| `ephemeral_entries_expire_in_place` | Entries past `EPHEMERAL_HORIZON_MS` evicted on next admission |
| `admission_exactly_one_do_fetch_per_request` | One `fetch` per pipeline request |
| `admission_repeated_key_no_second_inference` | `idempotent` + no duplicate work |
| `grace_usage_reconciled_afterwards` | Credit after grace carries `requestId` / `requestReference` |
