# First real provider adapter — DeepSeek (D5)

Frozen contracts for the first real provider adapter behind the D2 provider
port: DeepSeek wire mapping and normalization duties, the recorded-fixture
adapter suite shape, and the secret-store credential path. Later slices
**D7** (second provider), **F1** (evals against a real adapter), and **CP4**
**consume** this artifact — they must not rewrite this adapter's duties or
move retry, fallback, or logging policy into either adapter.

**Source of truth in code (this slice):**
`ai-platform/src/provider/deepseek.ts`, proven by
`ai-platform/test/deepseek-adapter.test.ts` against
`ai-platform/test/fixtures/deepseek/`.

**Traces to:** spec Freezes (first real provider adapter; recorded-fixture
suite; secret-store credential path); FR-001–FR-009; architecture §4.3.8;
delivery plan §3.5 row D5, §3.11.4 row D5.

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

D2 froze the port, the exhaustive classification contract, and the
deterministic fake. D5 freezes the **first real** adapter — DeepSeek —
proven by recorded fixtures with credentials from the platform secret store.

---

## 2. DeepSeek adapter behind the provider port

**Module:** `ai-platform/src/provider/deepseek.ts`

| Element | Role |
| --- | --- |
| `DeepSeekAdapter` | Implements D2 `ProviderPort`; the only real provider adapter added by D5 |
| Provider identity | `provider_id` value for this adapter is `deepseek` (architecture names DeepSeek as a remote provider target; Clarification Q1) |
| Invoke input | `CanonicalRequest` (A3) via `ProviderPort.invoke` |
| Invoke success | `CanonicalResult` and, when a stream fixture/path is exercised, an ordered sequence of `CanonicalStreamChunk` ending with exactly one terminal chunk (A3 invariant; D2 frozen port) |
| Invoke failure | `CanonicalError` with taxonomy code, D2 `retryability`, provider-native diagnostics, and consumed-budget flag — no new taxonomy codes |
| Transport | Injectable transport/fetch port; fixture suite feeds recorded request/response (or stream) pairs and asserts the outbound wire golden (Clarification Q3) |
| Credentials | Injectable secret-store binding; production wires the platform secrets binding (§4.4; §13.4). Credentials are never taken from config files or request input |

### 2.1 Ownership (unchanged from §4.3.8 / D2)

Adapters **MUST** own:

- Authentication to the provider (Authorization / API key from the secret store)
- Request/response mapping (canonical ↔ DeepSeek wire)
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

The DeepSeek adapter export surface MUST expose no retry API and no fallback
API. Classification is the only failure-policy signal. Bounded retry and
fallback remain D3.

### 2.3 Coexistence with the fake (Consumes D2)

Pipeline tests continue to use `FakeAdapter`. D5's fixture suite exercises
`DeepSeekAdapter` only. This slice does not delete, redefine, or replace the
fake's scripted outcomes.

### 2.4 Exactly one provider (FR-009)

This module is the DeepSeek adapter only. A second provider MUST NOT be folded
into this module; D7 owns the second adapter.

---

## 3. Recorded-fixture adapter suite shape

Permanent proof is **recorded fixtures**, not live provider egress (delivery
plan §3.5 Done when; §3.11.4 D5; DP-3). D7 MUST pass the same suite shape
against its second provider.

| Case | Named test | Asserts |
| --- | --- | --- |
| Request-mapping golden | T1 `request_mapping_golden` | Canonical request → DeepSeek wire request matches recorded outbound golden |
| Stream normalization | T2 `stream_normalization` | Provider stream chunks → `CanonicalStreamChunk` only; no provider-shaped fields at the port/adapter boundary |
| Usage extraction | T3 `usage_extraction` | Provider usage → canonical usage counters |
| Error class → taxonomy | T4 `provider_error_class_mapped_to_taxonomy` | One subcase per mapped DeepSeek wire error class → exactly one existing `TaxonomyCode` with D2 retryable/terminal classification |
| Malformed response | T5 `malformed_response` | Malformed recorded body → classified/normalized failure; not an unclassified throw |
| Truncated response | T6 `truncated_response` | Truncated recorded body → port-normalized outcome; no new taxonomy code |
| Timeout | T7 `timeout` | Adapter-owned deadline exceeded → taxonomy `timeout` with D2 retryability |
| Credentials absent | T8 `credentials_absent_from_logs_and_journal` | Spy: secret absent from every emitted log and journal record |
| No retry/fallback API | T9 `adapter_owns_no_retry_or_fallback` | Export surface: classification only |
| No logging policy | T10 `adapter_owns_no_logging_policy` | Adapter does not own logging policy; T8 still holds |
| Secret store only | T11 `credentials_from_secret_store_only` | Credentials obtained from secret-store binding only |

### 3.1 DeepSeek wire error classes (T4 floor)

T4 expands to **one named subcase per class** the adapter maps. The closed set
of DeepSeek wire error classes for this adapter is:

| Wire error class | Typical DeepSeek / HTTP signal | Maps to `TaxonomyCode` | Notes |
| --- | --- | --- | --- |
| `auth_rejected` | HTTP 401 / 403 from provider | `provider_rejected` | Terminal under D2 classification |
| `rate_limited` | HTTP 429 | `rate_limited` | Retryable under D2 classification |
| `provider_server_error` | HTTP 5xx | `internal_error` | Retryable under D2; exhausting the chain and emitting `provider_unavailable` remains D3 |
| `content_filtered` | Provider safety / content refusal body | `provider_rejected` | Terminal under D2 classification |

No taxonomy code may be added, removed, or renamed. Unclassified provider
failures MUST NOT escape as throws; they normalize through the port into a
classified canonical error using an existing code (malformed path → typically
`internal_error` as the port-normalized failure form, consistent with D2 fake
malformed behaviour).

Fixture files live under `ai-platform/test/fixtures/deepseek/` and are driven
through the injectable transport (Clarification Q3).

---

## 4. Secret-store credential path

Provider credentials come from the platform's secret store, are never logged,
and are never present in the journal (§4.3.8; §4.4; §13.4).

| Rule | Detail |
| --- | --- |
| Source | Injectable secret-store binding (Clarification Q4). Production wires the Worker secrets binding for the DeepSeek API key — binding name `DEEPSEEK_API_KEY` |
| Not a source | Config files, `vars` in `wrangler.toml`, request body/headers from the clinic client, hard-coded literals in source |
| Logs | Credential material MUST NOT appear in any log line the adapter causes to be emitted under test (T8, T10) |
| Journal | Credential material MUST NOT appear in any journalable record the adapter emits into recording sinks under test (T8) |
| Spy harness | Fake secret-store binding + recording logger + recording journal sinks (Clarification Q4); assert the secret was read from the store and never appears in collected emissions (T8, T11) |

D2 asserted credential absence on the fake. D5 freezes the **real** binding and
the spy on emitted logs and journal records.

---

## 5. Consumers

| Slice | Binding |
| --- | --- |
| **D7** | Implements a second real adapter against the same port; MUST pass this fixture suite shape against the second provider; MUST NOT rewrite DeepSeek adapter duties or move retry/fallback/logging into either adapter |
| **F1** | Runs capability evals against a real adapter; consumes this adapter as the first real target |
| **CP4** | Provider independence checkpoint depends on D5 + D7 + F1 |

Later slices MUST **consume** this artifact. They may add a second adapter and
register targets by routing-policy edit alone; they must not rewrite this
adapter's ownership boundary, fixture suite shape, or secret-store credential
path.

---

## 6. Verification

| Test | Asserts |
| --- | --- |
| T1 | Request-mapping golden against recorded outbound wire |
| T2 | Stream chunks normalized to canonical form |
| T3 | Usage counters extracted into canonical usage |
| T4 | One case per §3.1 wire error class → taxonomy + D2 retryability |
| T5 | Malformed → classified/normalized failure |
| T6 | Truncated → port-normalized outcome, no new code |
| T7 | Timeout → taxonomy `timeout` with D2 retryability |
| T8 | Credentials absent from logs and journal (spy) |
| T9 | No retry/fallback API on adapter export surface |
| T10 | Adapter owns no logging policy (spy; T8 still holds) |
| T11 | Credentials from secret store only (spy) |
