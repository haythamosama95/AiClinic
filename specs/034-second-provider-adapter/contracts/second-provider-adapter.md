# Second provider adapter — Gemini (D7)

Frozen contracts for the second real provider adapter behind the D2 provider
port: Gemini wire mapping and normalization duties, the recorded-fixture
adapter suite shape mirrored from D5, the secret-store credential path, and
registration as a low-priority fallback by routing-policy data alone. Later
slices **F1** (capability-eval half of CP4) and **F5** (load/cost) **consume**
this artifact — they must not rewrite this adapter's duties or move retry,
fallback, or logging policy into either adapter.

**Source of truth in code (this slice):**
`ai-platform/src/provider/gemini.ts`, proven by
`ai-platform/test/gemini-adapter.test.ts` against
`ai-platform/test/fixtures/gemini/`, with policy registration in
`ai-platform/control/routing-policy/platform-default/1.json` and thin wiring in
`ai-platform/src/provider/wiring.ts` (T13 / T14).

**Traces to:** spec Freezes (second real provider adapter; provider-independence
proof for a second real target — adapter / fixture / policy half); FR-001–FR-009,
FR-011, FR-012; architecture §4.3.8, §13.5; delivery plan §3.5 row D7,
§3.11.4 row D7.

**Deferred (`blocked_on_F1`):** FR-010, T12, SC-005, and the capability-eval
clause of Done when are **not** frozen or implemented here. They land with F1.

---

## 1. Overview

One adapter per provider translates the **canonical inference request** (A3)
to that provider's wire format and normalizes responses, streaming chunks,
usage counters, and errors back into the canonical form and the shared error
taxonomy. Adapters own authentication, request/response mapping, stream-chunk
normalization, provider-specific structured-output wire mechanics, timeouts,
and **classification of every failure as retryable or terminal**. Adapters own
nothing else — no retry decisions, no fallback decisions, no logging policy
(§4.3.8).

D5 froze the first real adapter (DeepSeek) and the recorded-fixture suite
shape. D7 freezes the **second real** adapter — Gemini — proven by the same
suite shape, registered as a low-priority fallback by routing-policy data
alone, with no inference-pipeline change.

---

## 2. Gemini adapter behind the provider port

**Module:** `ai-platform/src/provider/gemini.ts`

| Element | Role |
| --- | --- |
| `GeminiAdapter` | Implements D2 `ProviderPort`; the only real provider adapter added by D7 |
| Provider identity | `provider_id` value for this adapter is `gemini` (Clarification Q1 — commercial remote provider distinct from D5's DeepSeek) |
| Invoke input | `CanonicalRequest` (A3) via `ProviderPort.invoke` |
| Invoke success | `CanonicalResult` and, when a stream fixture/path is exercised, an ordered sequence of `CanonicalStreamChunk` ending with exactly one terminal chunk (A3 invariant; D2 frozen port) |
| Invoke failure | `CanonicalError` with taxonomy code, D2 `retryability`, provider-native diagnostics, and consumed-budget flag — no new taxonomy codes |
| Transport | Injectable transport/fetch port; fixture suite feeds recorded request/response (or stream) pairs and asserts the outbound wire golden (duplicate D5 inject pattern; Clarification Q6 — do not modify `deepseek.ts`) |
| Credentials | Injectable secret-store binding; production wires the platform secrets binding (§4.4; §13.4). Credentials are never taken from config files or request input |

### 2.1 Ownership (unchanged from §4.3.8 / D2 / D5)

Adapters **MUST** own:

- Authentication to the provider (API key from the secret store)
- Request/response mapping (canonical ↔ Gemini wire)
- Stream chunk normalization
- Provider-specific structured-output wire mechanics (pipeline `structured` /
  `structured_atomic` modes remain D6)
- Timeouts / deadline enforcement on the outbound call
- Classification of every failure as retryable or terminal via D2
  `classifyFailure` / `setRetryabilityFromClassification`

Adapters **MUST NOT** own:

- Retry decisions
- Fallback decisions
- Logging policy

### 2.2 Export-surface prohibition (T9)

The Gemini adapter export surface MUST expose no retry API and no fallback
API. Classification is the only failure-policy signal. Bounded retry and
fallback remain D3.

### 2.3 Coexistence with DeepSeek and the fake (Consumes D5 / D2)

D5's `DeepSeekAdapter` and D2's `FakeAdapter` remain unchanged. D7 adds
`GeminiAdapter` as a separate module. This slice does not delete, redefine, or
fold providers into one module (§4.3.8; FR-004).

### 2.4 Exactly one second provider (FR-004)

This module is the Gemini adapter only. A third provider MUST NOT be folded
into this module; further providers are out of scope for D7.

---

## 3. Recorded-fixture adapter suite shape

Permanent proof is **recorded fixtures**, not live provider egress (delivery
plan §3.5 Done when adapter/fixture half; §3.11.4 D7 ← D5; DP-3). D7 MUST pass
the same suite shape D5 froze against its second provider.

| Case | Named test | Asserts |
| --- | --- | --- |
| Request-mapping golden | T1 `second_provider_request_mapping_golden` | Canonical request → Gemini wire request matches recorded outbound golden |
| Stream normalization | T2 `second_provider_stream_normalization` | Provider stream chunks → `CanonicalStreamChunk` only; no provider-shaped fields at the port/adapter boundary |
| Usage extraction | T3 `second_provider_usage_extraction` | Provider usage → canonical usage counters |
| Error class → taxonomy | T4 `second_provider_error_class_mapped_to_taxonomy` | One subcase per mapped Gemini wire error class → exactly one existing `TaxonomyCode` with D2 retryable/terminal classification |
| Malformed response | T5 `second_provider_malformed_response` | Malformed recorded body → classified/normalized failure; not an unclassified throw |
| Truncated response | T6 `second_provider_truncated_response` | Truncated recorded body → port-normalized outcome; no new taxonomy code |
| Timeout | T7 `second_provider_timeout` | Adapter-owned deadline exceeded → taxonomy `timeout` with D2 retryability |
| Credentials absent | T8 `second_provider_credentials_absent_from_logs_and_journal` | Spy: secret absent from every emitted log and journal record |
| No retry/fallback API | T9 `second_adapter_owns_no_retry_or_fallback` | Export surface: classification only |
| No logging policy | T10 `second_adapter_owns_no_logging_policy` | Adapter does not own logging policy; T8 still holds |
| Secret store only | T11 `second_provider_credentials_from_secret_store_only` | Credentials obtained from secret-store binding only |

### 3.1 Gemini wire error classes (T4 floor)

T4 expands to **one named subcase per class** the adapter maps. The closed set
of Gemini wire error classes for this adapter is:

| Wire error class | Typical Gemini / HTTP signal | Maps to `TaxonomyCode` | Notes |
| --- | --- | --- | --- |
| `auth_rejected` | HTTP 401 / 403 from provider | `provider_rejected` | Terminal under D2 classification |
| `rate_limited` | HTTP 429 | `rate_limited` | Retryable under D2 classification |
| `provider_server_error` | HTTP 5xx | `internal_error` | Retryable under D2; exhausting the chain and emitting `provider_unavailable` remains D3 |
| `content_filtered` | Provider safety / block (`blockReason` / SAFETY) | `provider_rejected` | Terminal under D2 classification |

No taxonomy code may be added, removed, or renamed. Unclassified provider
failures MUST NOT escape as throws; they normalize through the port into a
classified canonical error using an existing code (malformed path → typically
`internal_error` as the port-normalized failure form, consistent with D2 fake /
D5 malformed behaviour).

Fixture files live under `ai-platform/test/fixtures/gemini/` and are driven
through the injectable transport.

---

## 4. Secret-store credential path

Provider credentials come from the platform's secret store, are never logged,
and are never present in the journal (§4.3.8; §4.4; §13.4).

| Rule | Detail |
| --- | --- |
| Source | Injectable secret-store binding (duplicate D5 inject pattern). Production wires the Worker secrets binding for the Gemini API key — binding name `GEMINI_API_KEY` |
| Not a source | Config files, `vars` in `wrangler.toml`, request body/headers from the clinic client, hard-coded literals in source |
| Logs | Credential material MUST NOT appear in any log line the adapter causes to be emitted under test (T8, T10) |
| Journal | Credential material MUST NOT appear in any journalable record the adapter emits into recording sinks under test (T8) |
| Spy harness | Fake secret-store binding + recording logger + recording journal sinks; assert the secret was read from the store and never appears in collected emissions (T8, T11) |

D5 froze the real binding pattern for DeepSeek. D7 applies the same path to
Gemini with a distinct binding name and does not rewrite D5's secret-store
rules.

---

## 5. Provider-independence proof (adapter / policy half)

Checkpoint **CP4** requires D7 **plus** F1. This contract freezes only the
half D7 lands:

| Proof element | Mechanism | Named test |
| --- | --- | --- |
| Full D5 fixture suite against second provider | Recorded fixtures under `test/fixtures/gemini/` | T1–T11 |
| Added by routing-policy data edit with no pipeline diff | Versioned policy document lists `gemini` as a low-priority target; structural path allowlist permits only second-adapter + routing-policy data (+ provider wiring map); fails if invocation / retry-fallback / stream-broker / validator / journal modules must change | T13 |
| Fallback ordering honoured | Unchanged `selectCandidateChain` yields a chain placing `gemini` after higher-priority targets; selection reason recorded; identical inputs → identical chain | T14 |

### 5.1 Routing-policy data registration (FR-011, FR-012)

| Element | Detail |
| --- | --- |
| Document path | `ai-platform/control/routing-policy/platform-default/1.json` |
| Shape | D2 routing-policy document interpretation (`specs/029-provider-port-routing/contracts/routing-decision.md` §2) — unchanged schema meaning |
| Registration | At least one rule's `targets[]` lists a higher-priority target before `{ provider_id: "gemini", … }` so Gemini is a low-priority fallback |
| Router | `ai-platform/src/router/index.ts` is **not** modified |
| Pipeline | Invocation, retry/fallback, stream broker, validator, and journal modules are **not** modified |

### 5.2 Provider wiring map (T13 allowlist)

| Element | Detail |
| --- | --- |
| Module | `ai-platform/src/provider/wiring.ts` |
| Role | Thin `provider_id` → adapter construction map covering DeepSeek and Gemini |
| Boundary | Adapter-side registration only; must not alter D3/D4/D6/C3 pipeline modules |

### 5.3 Capability-eval half (deferred)

| Element | Status |
| --- | --- |
| T12 `capability_evals_pass_with_second_provider` | `blocked_on_F1` — not part of this contract's implementable surface |
| When F1 lands | Versioned routing-policy fixture listing Gemini as a low-priority candidate; F1 harness invoked **unchanged** (Clarification Q4, superseded in effect by the deferral — describes F1-time satisfaction, not D7 work) |

---

## 6. Consumers

| Slice | Binding |
| --- | --- |
| **F1** | Closes the capability-eval half of CP4; makes the second provider available to the harness by policy fixture with harness invoked unchanged; MUST NOT invent scoring or redefine this adapter |
| **F5** | Load and cost tests that need D7 |
| **CP4** | Provider independence checkpoint depends on D7 (this artifact) **plus** F1 |

Later slices MUST **consume** this artifact. They may add further adapters and
policy edits the same way; they must not rewrite this adapter's duties, move
retry/fallback/logging into adapters, or invent a substitute for the deferred
F1 eval half inside D7's surface.
