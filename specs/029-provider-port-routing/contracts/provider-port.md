# Provider port, classification, and fake adapter (D2)

Frozen provider-port contract: the typed adapter boundary, the exhaustive
retryable-versus-terminal classification over A2's taxonomy (carried on A3's
canonical error), and the deterministic fake adapter's scripted outcomes. Later
slices **D3** (invocation), **D4** (stream broker), **D5/D7** (real adapters),
and **CP3** **consume** this artifact — they implement against the port and must
not move retry, fallback, or logging policy into an adapter.

**Source of truth in code (this slice):** `ai-platform/src/provider/port.ts`,
`ai-platform/src/provider/classify.ts`, `ai-platform/src/provider/fake.ts`.

**Traces to:** spec Freezes (provider port, classification, deterministic fake);
FR-001–FR-006; architecture §4.3.8, §13.5.

---

## 1. Overview

One adapter per provider translates the **canonical inference request** (A3) to
that provider's wire format and normalizes responses, streaming chunks, usage
counters, and errors back into the canonical form and the shared error taxonomy.
Adapters own authentication, request/response mapping, stream-chunk
normalization, provider-specific structured-output mechanics, timeouts, and
**classification of every failure as retryable or terminal**. Adapters own
nothing else — no retry decisions, no fallback decisions, no logging policy
(§4.3.8).

D2 freezes the port and a deterministic fake behind it. Real wire mapping and
secret-store credential wiring are D5/D7.

---

## 2. Provider port surface

**Module:** `ai-platform/src/provider/port.ts`

| Element | Role |
| --- | --- |
| `ProviderPort` | Typed boundary every adapter implements |
| `invoke` | **Async** — `invoke(request, options?): Promise<ProviderInvokeResult>` so adapters can await provider I/O without busy-spinning the isolate event loop |
| Invoke input | `CanonicalRequest` (A3). Deadline remains on the request (`CanonicalRequest.deadline`). Port-named options are `ProviderInvokeOptions` |
| `ProviderInvokeOptions` | `{ signal?: AbortSignal }` — caller cancellation combined with adapter-owned timeout abort on the in-flight fetch |
| Invoke success | `{ kind: "success"; result: CanonicalResult; chunks: readonly CanonicalStreamChunk[] }` — ordered chunk sequence ending with exactly one terminal chunk (A3 invariant; callers/adapters assert via `assertExactlyOneTerminal`) |
| Invoke truncation | `{ kind: "truncation"; result: CanonicalResult; chunks: readonly CanonicalStreamChunk[] }` — same chunk invariant as success |
| Invoke failure | `{ kind: "error" \| "malformed"; error: CanonicalError; chunks?: readonly CanonicalStreamChunk[] }` — taxonomy code, retryability, provider-native diagnostics, and consumed-budget flag (A3). **`chunks` is optional**: when present, it carries partial stream observed before the failure (allowed extension for D3 regenerating detection). Omitting `chunks` remains valid. Optional error/malformed chunks do **not** change the meaning of required success/truncation `chunks` (still exactly one terminal) |

### 2.1 Ownership

Adapters **MUST** own:

- Authentication to the provider
- Request/response mapping
- Stream chunk normalization
- Provider-specific structured-output mechanics
- Timeouts
- Classification of every failure as retryable or terminal

Adapters **MUST NOT** own:

- Retry decisions
- Fallback decisions
- Logging policy (no logger/journal sinks on adapter constructors)

### 2.2 Export-surface prohibition (T18)

Every module under `ai-platform/src/provider/` (port, fake, classify, deepseek,
gemini, wiring) MUST expose no retry API, no fallback API, and no logging-policy
sinks (`LoggerSink` / `JournalSink`). The prohibition covers module exports **and**
class prototype / interface member names (not only `Object.keys` on the module
namespace). Classification is the only failure-policy signal on the port.
Bounded retry and fallback are D3.

---

## 3. Retryable-versus-terminal classification

**Module:** `ai-platform/src/provider/classify.ts`

The classification contract is **exhaustive** over A2's closed `TaxonomyCode`
set: every code has exactly one adapter classification — `retryable` or
`terminal` — and that classification is carried on the canonical error's
`retryability` boolean (A3).

| Rule | Detail |
| --- | --- |
| Source set | `TaxonomyCode` from `ai-platform/src/errors.ts` — no code may be added, removed, or renamed. Exhaustiveness tests MUST enumerate `ALL_TAXONOMY_CODES` exported from that module (never a hand-copied list) and MUST pin several literal code→class pairs |
| Mapping | Each code maps to exactly one of `retryable` / `terminal` for adapter purposes |
| Carry field | `CanonicalError["retryability"]` (boolean) |
| Alignment | Derived from A2's taxonomy `retryable` column via the same retry-safety rule A2 already freezes (`isRetrySafe`): codes whose taxonomy retryability is `"No"` or `"—"` are terminal; all others are retryable |
| Unclassified | An unclassified failure is a contract violation — not a new taxonomy code |

D3 retries only adapter-classified retryable failures. Exhausting a chain and
surfacing `provider_unavailable` is D3, not D2.

---

## 4. Deterministic fake adapter

**Module:** `ai-platform/src/provider/fake.ts`

A test double behind the same `ProviderPort`. Constructor takes an **ordered
queue of scripted outcomes**; each invoke consumes the next outcome
(Clarification Q2).

### 4.1 Scripted outcomes

| Outcome | Port result |
| --- | --- |
| `success` | Canonical result (success) plus a minimal valid `chunks` sequence with exactly one terminal |
| `retryable:<TaxonomyCode>` | Canonical error with `retryability: true` for a retryable class; invalid codes are classified `internal_error` |
| `terminal:<TaxonomyCode>` | Canonical error with `retryability: false` for a terminal class; invalid codes are classified `internal_error` |
| `truncation` | Truncated response outcome plus `chunks` (fixture behaviour — not a new taxonomy code) |
| `malformed` | Malformed response outcome normalized through the port (fixture behaviour — not a new taxonomy code) |
| Empty queue / unrecognized | Classified `{ kind: "error"; error: CanonicalError }` with `internal_error` — never a bare throw |

### 4.2 Credentials (T21)

Provider credentials come from the platform's secret store, are never logged, and
are never present in the journal (§4.3.8). The fake has no real credentials.
Returned canonical records and any fake-emitted diagnostics MUST carry **no
credential fields**. Real secret-store wiring is D5.

---

## 5. Consumers

| Slice | Binding |
| --- | --- |
| **D3** | Invokes adapters through the port (async + `ProviderInvokeOptions.signal`); retries only classified-retryable failures; falls back along the candidate chain; may relay optional error/malformed `chunks` for regenerating detection |
| **D4** | Relays normalized stream chunks produced at the adapter boundary |
| **D5 / D7** | Implement real adapters against this port; replace the fake for fixture suites |
| **CP3** | Walking skeleton runs against the fake |

Later slices MUST **consume** this artifact. They may add real adapters behind the
port; they must not rewrite the ownership boundary, the classification contract,
or the fake's role as the deterministic double for pipeline suites.

---

## 6. Verification

| Test | Asserts |
| --- | --- |
| T1 | Fake success through the port |
| T2 | One case per retryable failure class |
| T3 | One case per terminal failure class |
| T4 | Truncation outcome |
| T5 | Malformed outcome |
| T6 | Classification exhaustive over the taxonomy |
| T18 | No retry/fallback API on port/fake export surface |
| T21 | Credentials absent from fake/port emissions |
