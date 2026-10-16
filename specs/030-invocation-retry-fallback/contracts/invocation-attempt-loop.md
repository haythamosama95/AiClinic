# Invocation attempt loop, selection reasons, and regenerating (D3)

Frozen platform-internal attempt-loop contract: walking the D2 candidate chain through the
provider port with bounded jittered retries, attempt-level `selection_reason` values, exhausted-chain
`provider_unavailable`, the no-splice regenerating rule, and the per-attempt journal feed. Later
slices **D4** (stream broker), **D5/D7** (real adapters behind the same port), **D6** (bounded
repair / `repair_retry`), and **CP3** **consume** this artifact — they must not move retry or
fallback into an adapter, invent targets outside the given chain, splice providers' text, or emit
`repair_retry` from this loop.

**Source of truth in code (this slice):** `ai-platform/src/invocation/index.ts`.

**Traces to:** spec Freezes (attempt loop; fallback walk and selection reasons; exhausted-chain
outcome; no-splice regenerating rule; per-attempt journal feed); FR-001–FR-011; architecture
§4.3.7, §8.6, §6.6.

---

## 1. Overview

Given the router's ordered candidate chain (D2), the gateway walks targets in order and invokes each
through the provider port. Per-target retries are bounded by that target's `max_attempts`, each
attempt is raced against the entry's `timeout_ms`, backoff is exponential+jitter capped at
`BACKOFF_CAP_MS` (and truncated to the request deadline), and a retry occurs only when the adapter
classifies the failure as retryable. After retryable exhaustion (including when the exhausting
failure is timeout-classified), the loop falls back to the next chain entry. When every candidate
is exhausted under retryable failure — or the chain is empty — the request fails with
`provider_unavailable`. If partial streamed text was already produced for a failed target
(relayed `text_delta` chunks), fallback emits an explicit `regenerating` signal, discards that
text, and never splices two providers' output (§4.3.7; §8.6; §6.6).

Adapters own classification only. This module owns retry, fallback, attempt journaling feed, and the
regenerating decision — never the reverse (D2 Freezes; §4.3.8).

---

## 2. Attempt loop

**Module:** `ai-platform/src/invocation/index.ts`

| Rule | Detail |
| --- | --- |
| Input chain | Ordered `routing_decision.chain[]` from D2 — `{ ordinal, provider_id, model_id, max_attempts, timeout_ms }[]`. Walked in order; never rebuilt, reordered, widened, or history-filtered (§4.3.7; FR-007, FR-008) |
| Invoke path | Each attempt calls the async provider port for that target's `provider_id` with the same `requestId` / `idempotencyKey` (no new user-initiated request) (§6.6; FR-009) |
| Retry bound | At most `max_attempts` invokes of a given chain entry (FR-001, FR-010). `max_attempts = 1` means one invoke and no inter-retry sleep |
| Retry eligibility | Only adapter-classified **retryable** failures (`CanonicalError.retryability === true` / D2 classification). Terminal failures are not retried and do not continue the fallback walk (FR-002, FR-003) |
| Backoff | Between same-target retries: exponential + jitter, capped at `BACKOFF_CAP_MS` (10_000). Sleeps are truncated to the remaining request `deadline` budget (`CanonicalRequest.deadline` as relative ms from walk start; null = no truncation). No sleep on a target's final attempt (FR-002; Clarification Q3) |
| Per-attempt timeout | Each chain entry's `timeout_ms` is enforced by racing `port.invoke` against that bound and passing `AbortSignal` via `ProviderInvokeOptions`. A timed-out attempt is classified taxonomy `timeout` (retryable) (FR-004) |
| Exhausted chain | When every chain entry has failed retryably to its bound, **or the chain is empty**, fail with taxonomy code `provider_unavailable` (FR-005). Empty chain journals zero attempts |
| Unmapped invoke kind | An unexpected `ProviderInvokeResult.kind` is recorded as a classified `internal_error` attempt — never a bare throw across the module boundary |
| Speculative parallelism | `max_parallel_attempts > 1` / `selection_reason = speculative` are out of scope for this slice; the frozen walk is sequential |

### 2.1 Injectable dependencies (implementation surface, not new architecture)

| Dependency | Role |
| --- | --- |
| Port resolver | Maps `provider_id` → `ProviderPort` (D2). Does not modify the port |
| Event / attempt sink | Collects attempt records and stream signals for journaling / later stream wiring (Clarification Q4). The loop wraps the sink in a **run-scoped observing object**; it never mutates the caller-owned sink |
| Sleeper / delay | Recording delay function for jittered backoff (Clarification Q3) |
| RNG | Injectable `() => number` for jitter (defaults to `Math.random`); enables proving delay ≠ pure exponential (Clarification Q3 amended) |

**Not an injectable:** `providerHistoryStore` / circuit-breaker / shared provider-health state — forbidden by §9.14 / FR-008 and **removed** from the input surface. Non-consultation is proven by a spy that the module never receives (T11).

Production later wires the sink to C3's journal writer and D4's stream path. This slice does **not**
change C3's write-path contract or D2's port/fake modules.

---

## 3. Attempt-level `selection_reason`

Recorded on each journaled attempt (why *that* attempt was tried). Distinct from the request-level
`routing_decision` frozen by D2 (§4.3.7).

| Value | When set by D3 |
| --- | --- |
| `primary` | First target in the chain, first attempt on that target |
| `fallback_after_retryable_error` | First attempt on a subsequent target after prior target's **exhausting (final) failure** was a non-timeout retryable failure |
| `fallback_after_timeout` | First attempt on a subsequent target after prior target's **exhausting (final) failure** was timeout-classified — including mixed scripts where earlier attempts on that target were non-timeout then the last was timeout (§8.6) |
| `speculative` | Named in §4.3.7; **not emitted** by this slice (parallel walk out of scope) |
| `repair_retry` | Named in §4.3.7; **reserved for D6**; D3 must never emit it (FR-011; T13) |

Same-target retries keep the selection reason of the attempt that opened that target walk (they do
not re-label mid-target retries as fallback). Only advancing to a new chain entry introduces
`fallback_after_*`. The timeout-vs-retryable fallback reason keys off the prior target's
**last** failure only — not "timeout-only" for the whole target walk.

---

## 4. Exhausted-chain outcome

| Outcome | Condition |
| --- | --- |
| `provider_unavailable` | Every candidate target failed retryably up to its `max_attempts`, or the chain has no targets |

Uses the existing A2 taxonomy entry (`ai-platform/src/errors.ts`). D3 does not alter its HTTP status,
retryability, or quota flag. Terminal adapter errors fail the request with **that** terminal code —
not `provider_unavailable` (FR-003 vs FR-005).

---

## 5. Regenerating and no-splice

| Rule | Detail |
| --- | --- |
| Trigger | Fallback to a new chain entry **after** the failed target had already produced streamed text — detected when the loop relays `text_delta` chunks to the observing sink (including optional `chunks` on `error` / `malformed` results; see D2 `provider-port.md` §2) |
| Detection | Partial text is observed via a **local** sink wrapper scoped to the run; the caller-owned `InvocationSink` is never mutated in place |
| Signal | Emit an explicit `regenerating` event on the sink **before** the fallback target's output is considered (exactly once per such advance) |
| Discard | Discard the earlier provider's partial text; it must not appear in the final assembled text for the request |
| No splice | Never concatenate or interleave text from two providers (§8.6; FR-006) |
| Non-trigger | Fallback with no prior partial text, or a terminal failure after partial text (no fallback), must **not** emit `regenerating` |

Stream *relay*, heartbeats, and incremental guards remain D4. D3 owns the regenerating decision and
discard-on-fallback rule. The sink event is the frozen shape for later D4 wiring; this slice does not
amend A6's SSE framing contract.

### 5.1 Test-only streaming harness (Clarification Q2)

T6 drives a **test-only** port double/harness that yields partial `text_delta` chunks (including on
error results via optional `chunks`) then a retryable error. D2's production `FakeAdapter` scripted
outcome set is **unchanged** for success/truncation/malformed/error kinds; optional error `chunks`
are an allowed port extension. The harness lives with the invocation suite and is not a new
production adapter.

---

## 6. Per-attempt journal feed

Each provider invoke produces exactly one attempt record for the sink (FR-002; T4). D3 adds no D1
columns and does not call C3's writer.

| Field | Contents |
| --- | --- |
| `attempt_no` | 1-based ordinal within the request |
| `provider_id`, `model_id` | From the chain entry being invoked |
| `selection_reason` | Per §3 |
| `outcome` | `success` \| `truncation` \| `retryable_failure` \| `terminal_failure` \| `timeout` |
| `error_code` | Taxonomy code when the attempt failed; absent on `success` / `truncation` |
| `request_id` | Same request across internal retries (FR-009; T12) |
| `idempotency_key` | **Required** — same key across internal retries; asserted on the feed (not only on input) (FR-009; T12) |
| `latency_ms`, `tokens_in`, `tokens_out`, `cost`, `provider_request_id` | Optional; carried when the port returns usage/timing on success or truncation |

`truncation` is distinct from `success` in the feed so C3 can distinguish length-truncated
completions. Optional usage/timing fields feed C3's existing `AttemptInput` / envelope `attempts[]`
when production wiring lands; they are not new Freezes beyond that hand-off. `selection_reason`
travels on this feed; persisting it into a D1 column is outside this slice (spec: no new D1
columns; C3 write-path unchanged).

---

## 7. Consumers

| Slice | Binding |
| --- | --- |
| **D4** | Relays chunks; observes `regenerating` and discard-on-fallback when wiring the sink to the stream |
| **D5 / D7** | Real adapters behind the unchanged D2 port; this loop retries only their classifications |
| **D6** | May emit `repair_retry` on its own bounded re-ask path — not through this sequential fallback walk |
| **CP3** | Walking skeleton runs this loop against the D2 fake |

Later slices MUST **consume** this artifact. They may wire the sink to C3/D4; they must not rewrite
retry/fallback ownership, the selection_reason set D3 emits, the regenerating/no-splice rule, or the
exhausted-chain → `provider_unavailable` outcome.

---

## 8. Verification

| Test | Asserts |
| --- | --- |
| T1 | Retryable failure retried to cap then fallback |
| T2 | Terminal failure not retried; no fallback walk |
| T3 | Backoff delays not all identical; delay ≠ pure exponential (injectable RNG); delays ≤ `BACKOFF_CAP_MS`; sleeps truncated to remaining deadline |
| T4 | One journaled attempt per invoke; feed carries `idempotency_key` |
| T5 | Exhausted chain → `provider_unavailable` (incl. empty chain → zero attempts) |
| T6 | Partial stream then fallback → `regenerating` once before fallback output; earlier text discarded; no splice; no regenerating without prior partial |
| T7 | Per-target `max_attempts` / chain budget never exceeded (incl. `max_attempts = 1`) |
| T8 | Primary success; single attempt; `selection_reason = primary` |
| T9 | Timeout exhaustion (incl. mixed non-timeout then timeout) → `fallback_after_timeout` |
| T10 | Fallback walks only the given chain |
| T11 | No provider-history / circuit-breaker consultation (spy; store not on input surface) |
| T12 | Internal retries keep the same `request_id` and `idempotency_key` on the attempt feed |
| T13 | `repair_retry` never recorded |
