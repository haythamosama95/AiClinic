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
measured `provider_ms`, and **classification of every failure as retryable or
terminal**. Adapters own nothing else — no retry decisions, no fallback
decisions, no logging policy (§4.3.8).

D2 froze the port (async `invoke`, required `chunks`, caller `signal`, no
adapter logger/journal sinks), the exhaustive classification contract, and the
deterministic fake. D5 freezes the **first real** adapter — DeepSeek —
proven by recorded fixtures with credentials from the platform secret store.

---

## 2. DeepSeek adapter behind the provider port

**Module:** `ai-platform/src/provider/deepseek.ts`

| Element | Role |
| --- | --- |
| `DeepSeekAdapter` | Implements D2 `ProviderPort`; the only real provider adapter added by D5 |
| Provider identity | `provider_id` value for this adapter is `deepseek` (architecture names DeepSeek as a remote provider target; Clarification Q1) |
| Invoke | **Async** — `invoke(request, options?): Promise<ProviderInvokeResult>` (D2 port repair; no busy-wait) |
| Invoke input | `CanonicalRequest` (A3) via `ProviderPort.invoke`; `ProviderInvokeOptions.signal` for caller cancellation combined with adapter-owned timeout abort |
| Invoke success | `{ kind: "success"; result: CanonicalResult; chunks: … }` — ordered `CanonicalStreamChunk` sequence ending with exactly one terminal chunk (A3 / D2) |
| Invoke truncation | `{ kind: "truncation"; result: CanonicalResult; chunks: … }` — same chunk invariant |
| Invoke failure | `{ kind: "error" \| "malformed"; error: CanonicalError; chunks?: … }` — taxonomy code, D2 `retryability`, provider-native diagnostics, and consumed-budget flag — no new taxonomy codes |
| Transport | Injectable transport/fetch port; fixture suite feeds recorded request/response (or stream) pairs and asserts the outbound wire golden (Clarification Q3) |
| Credentials | Injectable secret-store binding; production wires the platform secrets binding (§4.4; §13.4). Credentials are never taken from config files or request input. No logger/journal sinks on the constructor (D2 repair) |

### 2.1 Ownership (unchanged from §4.3.8 / D2)

Adapters **MUST** own:

- Authentication to the provider (Authorization / API key from the secret store)
- Request/response mapping (canonical ↔ DeepSeek wire)
- Stream chunk normalization onto port `chunks`
- Provider-specific structured-output wire mechanics (pipeline `structured` /
  `structured_atomic` modes remain D6)
- Timeouts / deadline enforcement on the outbound call (abort the in-flight fetch)
- Measured `provider_ms` around the outbound transport call
- Classification of every failure as retryable or terminal via D2
  `classifyFailure` / `setRetryabilityFromClassification`

Adapters **MUST NOT** own:

- Retry decisions
- Fallback decisions
- Logging policy (no logger/journal sinks)

### 2.2 Export-surface prohibition (T9 / T10)

The DeepSeek adapter export surface MUST expose no retry API, no fallback API,
and no logger/journal sink options. Classification is the only failure-policy
signal. Bounded retry and fallback remain D3; journaling remains C3.

### 2.3 Coexistence with the fake (Consumes D2)

Pipeline tests continue to use `FakeAdapter`. D5's fixture suite exercises
`DeepSeekAdapter` only. This slice does not delete, redefine, or replace the
fake's scripted outcomes.

### 2.4 Exactly one provider (FR-009)

This module is the DeepSeek adapter only. A second provider MUST NOT be folded
into this module; D7 owns the second adapter.

### 2.5 Deadline interpretation (adapter only — Deviation 5)

D5 treats A3 `CanonicalRequest.deadline` as a **remaining-duration budget in
milliseconds** (min'd with adapter `timeoutMs`), matching existing fixtures —
not an absolute epoch timestamp. This is adapter interpretation only;
architecture / A3 field prose is not amended.

### 2.6 Buffered fixture transport (Deviation 4)

The injectable fixture transport models the **full response body as one
string**; the adapter parses SSE **post-hoc** after the body is complete.
Incremental byte delivery is **out of scope** for this slice's harness — true
byte-streaming remains a future transport concern. Normalized chunks still
land on the port `chunks` array.

---

## 3. Recorded-fixture adapter suite shape

Permanent proof is **recorded fixtures**, not live provider egress (delivery
plan §3.5 Done when; §3.11.4 D5; DP-3). D7 MUST pass the same suite shape
against its second provider.

| Case | Named test | Asserts |
| --- | --- | --- |
| Request-mapping golden | T1 `request_mapping_golden` | Canonical request → DeepSeek wire request matches recorded outbound golden; stream requests include `stream_options.include_usage` |
| Stream normalization | T2 `stream_normalization` | Provider stream → port `chunks`; content/order/assembly; exactly one empty `text_delta` terminal (`assertExactlyOneTerminal`) |
| Usage extraction | T3 `usage_extraction` | Provider usage → canonical counters; `prompt_cache_hit_tokens` → `cached`; absent usage → zero-filled + `provider_note` `{ note: "usage_absent" }` |
| Error class → taxonomy | T4 `provider_error_class_mapped_to_taxonomy` | One subcase per mapped DeepSeek wire error class → exactly one existing `TaxonomyCode` with D2 retryable/terminal classification |
| Malformed response | T5 `malformed_response` | Malformed JSON **or** malformed SSE data line → port `malformed` / classified failure; not an unclassified throw; not silent skip-success |
| Truncated response | T6 `truncated_response` | `finish_reason: length` **or** SSE cut without `[DONE]` / `finish_reason` → port `truncation`; no new taxonomy code |
| Timeout | T7 `timeout` | Adapter-owned deadline exceeded → taxonomy `timeout` with D2 retryability; outbound abort signal fired |
| Credentials absent | T8 `credentials_absent_from_logs_and_journal` | Spy: secret absent from returned canonical errors and captured wire artifacts; missing key → `consumedBudget: false` |
| No retry/fallback API | T9 `adapter_owns_no_retry_or_fallback` | Export / options surface: classification only |
| No logging policy | T10 `adapter_owns_no_logging_policy` | No logger/journal sinks; T8 still holds |
| Secret store only | T11 `credentials_from_secret_store_only` | Credentials obtained from secret-store binding only; wire `Authorization` carries the store secret |

### 3.1 DeepSeek wire error classes (T4 floor)

T4 expands to **one named subcase per class** the adapter maps. The closed set
of DeepSeek wire error classes for this adapter is:

| Wire error class | Typical DeepSeek / HTTP signal | Maps to `TaxonomyCode` | Notes |
| --- | --- | --- | --- |
| `auth_rejected` | HTTP 401 / 403 from provider | `provider_rejected` | Terminal under D2 classification |
| `rate_limited` | HTTP 429 | `rate_limited` | Retryable under D2 classification |
| `provider_server_error` | HTTP 5xx | `internal_error` | Retryable under D2; exhausting the chain and emitting `provider_unavailable` remains D3 |
| `content_filtered` | Structured `type`/`code` or explicit content-policy phrases; **or** `finish_reason: content_filter` | `provider_rejected` | Terminal. HTTP status **wins** over free-text `"safety"` substrings; bare `"safety"` alone MUST NOT override a retryable status |

No taxonomy code may be added, removed, or renamed. Unclassified provider
failures MUST NOT escape as throws; they normalize through the port into a
classified canonical error using an existing code (malformed path → typically
`malformed` / `internal_error` as the port-normalized failure form, consistent
with D2 fake malformed behaviour). Transport throw/reject is contained at
`invoke` and classified — never rethrown across the module boundary.

### 3.2 Stream chunk semantics

| Rule | Detail |
| --- | --- |
| Terminal count | Exactly one terminal chunk per successful/truncated stream (`assertExactlyOneTerminal`) |
| Terminal payload | Terminal MUST NOT re-emit assembled text — empty `text_delta` terminal marker |
| Non-terminal deltas | Carry content; consumers that relay deltas must not see duplicated full text |
| Carrier | Port-required `chunks` array (D2 repair) — not a module-local extension type |

### 3.3 SSE failure classification

| Wire condition | Port outcome |
| --- | --- |
| Malformed SSE data line (JSON parse failure) | `malformed` / classified failure — **not** silent skip-success |
| Stream cut without `[DONE]` and without `finish_reason` | `truncation` (no new taxonomy code) |
| Mid-stream provider `error` frame | Classified error (not success with partial content) |

### 3.4 Finish-reason mapping

| DeepSeek `finish_reason` | Outcome |
| --- | --- |
| `content_filter` | Terminal `provider_rejected` |
| `insufficient_system_resource` | `internal_error` (retryable) |
| `length` | Port `truncation` |
| else (e.g. `stop`) | Success / stop |

### 3.5 Usage and timing

| Rule | Detail |
| --- | --- |
| Stream wire | Streaming requests MUST set `stream_options.include_usage` |
| Cache hits | Map DeepSeek `prompt_cache_hit_tokens` → canonical `cached` |
| Absent usage | Emit `provider_note` `{ note: "usage_absent" }` with zero-filled counters (distinguish from genuine zeros) |
| Timing | Adapter measures `provider_ms` around the outbound transport call — MUST NOT fabricate all-zeros without measurement |

### 3.6 Missing credentials

Absent secret MAY classify as taxonomy `provider_rejected`, but
`consumedBudget` MUST be `false` (provider never reached).

---

## 4. Secret-store credential path

Provider credentials come from the platform's secret store and must not appear
in returned canonical errors or captured wire artifacts (§4.3.8; §4.4; §13.4).

| Rule | Detail |
| --- | --- |
| Source | Injectable secret-store binding (Clarification Q4). Production wires the Worker secrets binding for the DeepSeek API key — binding name `DEEPSEEK_API_KEY` |
| Not a source | Config files, `vars` in `wrangler.toml`, request body/headers from the clinic client, hard-coded literals in source |
| Returned errors / wire | Credential material MUST NOT appear in any `CanonicalError` payload or captured outbound wire artifact under test (T8, T10, T11) |
| Missing key | Taxonomy may be `provider_rejected`; `consumedBudget: false` (T8) |
| Spy harness | Fake secret-store binding (Clarification Q4 amended); assert the secret was read from the store, Authorization uses that value, and the secret never appears in returned errors / wire captures. No adapter logger/journal sinks |

D2 asserted credential absence on the fake. D5 freezes the **real** binding and
the spy on returned errors and wire artifacts.

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
| T1 | Request-mapping golden against recorded outbound wire (`include_usage` on stream) |
| T2 | Stream chunks on port `chunks`; empty terminal; content/order/assembly |
| T3 | Usage counters / `cached` / `usage_absent`; measured `provider_ms` |
| T4 | One case per §3.1 wire error class → taxonomy + D2 retryability (status wins) |
| T5 | Malformed JSON/SSE → classified/normalized failure |
| T6 | Truncated `length` / stream-cut → port `truncation`, no new code |
| T7 | Timeout → taxonomy `timeout` with D2 retryability; abort fired |
| T8 | Credentials absent from returned errors / wire; missing key → `consumedBudget: false` |
| T9 | No retry/fallback API on adapter export / options surface |
| T10 | No logger/journal sinks (spy; T8 still holds) |
| T11 | Credentials from secret store only; Authorization uses store secret |
