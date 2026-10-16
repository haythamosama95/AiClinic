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

**Capability-eval clause (FR-010 / T12 / SC-005):** Unblocked by F1 presence
(`specs/039-eval-suite-harness/`, `ai-platform/test/eval/`). Live-smoke already
targets `gemini-1.5-flash`. Golden-eval inclusion of Gemini in the candidate
set remains the permanent proof path for the CP4 eval half. Architecture is
not amended.

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
| Invoke | **Async** — `invoke(request, options?): Promise<ProviderInvokeResult>` (D2 port repair; no busy-wait) |
| Invoke input | `CanonicalRequest` (A3) via `ProviderPort.invoke`; `ProviderInvokeOptions.signal` for caller cancellation combined with adapter-owned timeout abort |
| Invoke success | `{ kind: "success"; result: CanonicalResult; chunks: … }` — ordered `CanonicalStreamChunk` sequence ending with exactly one terminal chunk (A3 / D2) |
| Invoke truncation | `{ kind: "truncation"; result: CanonicalResult; chunks: … }` — same chunk invariant |
| Invoke failure | `{ kind: "error" \| "malformed"; error: CanonicalError; chunks?: … }` — taxonomy code, D2 `retryability`, provider-native diagnostics, and consumed-budget flag — no new taxonomy codes |
| Transport | Injectable transport/fetch port; fixture suite feeds recorded request/response (or stream) pairs and asserts the outbound wire golden (duplicate D5 inject pattern; Clarification Q6 — do not modify `deepseek.ts`) |
| Credentials | Injectable secret-store binding; production wires the platform secrets binding (§4.4; §13.4). Credentials are never taken from config files or request input. No logger/journal sinks on the constructor (D2 repair) |

### 2.1 Ownership (unchanged from §4.3.8 / D2 / D5)

Adapters **MUST** own:

- Authentication to the provider (API key from the secret store)
- Request/response mapping (canonical ↔ Gemini wire)
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

The Gemini adapter export surface MUST expose no retry API, no fallback API,
and no logger/journal sink options. Classification is the only failure-policy
signal. Bounded retry and fallback remain D3; journaling remains C3.

### 2.3 Coexistence with DeepSeek and the fake (Consumes D5 / D2)

D5's `DeepSeekAdapter` and D2's `FakeAdapter` remain unchanged. D7 adds
`GeminiAdapter` as a separate module. This slice does not delete, redefine, or
fold providers into one module (§4.3.8; FR-004).

### 2.4 Exactly one second provider (FR-004)

This module is the Gemini adapter only. A third provider MUST NOT be folded
into this module; further providers are out of scope for D7.

### 2.5 Deadline interpretation (adapter only)

D7 treats A3 `CanonicalRequest.deadline` as a **remaining-duration budget in
milliseconds** (min'd with adapter `timeoutMs`), matching existing fixtures —
not an absolute epoch timestamp. This is adapter interpretation only;
architecture / A3 field prose is not amended. Same class of ruling as D5
contract §2.5.

### 2.6 Buffered fixture transport

The injectable fixture transport models the **full response body as one
string**; the adapter parses SSE **post-hoc** after the body is complete.
Incremental byte delivery is **out of scope** for this slice's harness — true
byte-streaming remains a future transport concern. Normalized chunks still
land on the port `chunks` array. Same class of ruling as D5 contract §2.6.

### 2.7 Wire mapping floor

The Gemini adapter maps at least the following canonical → wire fields (the
documented floor for this slice; fixtures pin the behaviour):

| Canonical | Gemini wire |
| --- | --- |
| `parts` with `role: "system"` | `systemInstruction.parts[].text` (joined) — not `contents[].role` |
| `parts` with `role: "data"` | `contents[].role: "user"` |
| `parts` with `role: "assistant"` | `contents[].role: "model"` |
| Consecutive same-role content parts | Merged into one `contents[]` entry (Gemini user/model alternation) |
| `samplingConstraints.top_k` | `generationConfig.topK` |
| `formatDirective` JSON + schema | `responseMimeType: "application/json"` and `responseSchema` when schema present |
| Non-empty `toolDeclarations` | `tools[].functionDeclarations` |

`allowedLanguages` is **still not mapped** — no Gemini `generationConfig`
equivalent is used for it in this adapter.

### 2.8 Model identity

The adapter pins `gemini-1.5-flash`, matching the platform-default routing
policy target's `model_id`. The port does **not** yet thread per-target
`model_id` into the adapter (same class of gap as D5). A policy edit of
`model_id` alone does **not** reconfigure the adapter until a later port
extension.

### 2.9 Wiring map hand-off

`ai-platform/src/provider/wiring.ts` `createProviderAdapter` is the thin
`provider_id` → adapter construction map **frozen by this slice**. Production
`portResolver` composition at the Worker / invocation boundary remains a
composition concern (D3 injects `portResolver`). Registration as a
low-priority fallback is proven at **router output + wiring constructibility**;
end-to-end `portResolver` join is **not** claimed by this slice's done-when
restatement.

---

## 3. Recorded-fixture adapter suite shape

Permanent proof is **recorded fixtures**, not live provider egress (delivery
plan §3.5 Done when adapter/fixture half; §3.11.4 D7 ← D5; DP-3). D7 MUST pass
the same suite shape D5 froze against its second provider.

| Case | Named test | Asserts |
| --- | --- | --- |
| Request-mapping golden | T1 `second_provider_request_mapping_golden` | Canonical request → Gemini wire request matches recorded outbound golden (incl. §2.7 floor fields exercised by fixtures) |
| Stream normalization | T2 `second_provider_stream_normalization` | Provider stream → port `chunks`; content/order/assembly; exactly one empty `text_delta` terminal (`assertExactlyOneTerminal`) |
| Usage extraction | T3 `second_provider_usage_extraction` | Provider usage → canonical counters; `cachedContentTokenCount` → `cached`; absent usage → zero-filled + `provider_note` `{ note: "usage_absent" }` |
| Error class → taxonomy | T4 `second_provider_error_class_mapped_to_taxonomy` | One subcase per mapped Gemini wire error class → exactly one existing `TaxonomyCode` with D2 retryable/terminal classification |
| Malformed response | T5 `second_provider_malformed_response` | Malformed JSON **or** malformed SSE data line → port `malformed` / classified failure; not an unclassified throw; not silent skip-success |
| Truncated response | T6 `second_provider_truncated_response` | `finishReason: MAX_TOKENS` **or** SSE cut without terminal finish → port `truncation`; no new taxonomy code |
| Timeout | T7 `second_provider_timeout` | Adapter-owned deadline exceeded → taxonomy `timeout` with D2 retryability; outbound abort signal fired |
| Credentials absent | T8 `second_provider_credentials_absent_from_logs_and_journal` | Spy: secret absent from returned canonical errors and captured wire artifacts; missing key → `consumedBudget: false` |
| No retry/fallback API | T9 `second_adapter_owns_no_retry_or_fallback` | Export / options surface: classification only |
| No logging policy | T10 `second_adapter_owns_no_logging_policy` | No logger/journal sinks; T8 still holds |
| Secret store only | T11 `second_provider_credentials_from_secret_store_only` | Credentials obtained from secret-store binding only; wire auth carries the store secret |

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
`malformed` / `internal_error` as the port-normalized failure form, consistent
with D2 fake / D5 malformed behaviour). Transport throw/reject is contained at
`invoke` and classified — never rethrown across the module boundary.

Fixture files live under `ai-platform/test/fixtures/gemini/` and are driven
through the injectable buffered transport.

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
| Stream cut without a terminal finish reason | `truncation` (no new taxonomy code) |
| Mid-stream provider `error` frame | Classified error (not success with partial content) |

### 3.4 Finish-reason mapping

| Gemini `finishReason` | Outcome |
| --- | --- |
| `SAFETY` / `BLOCKLIST` (and equivalent block signals) | Terminal `provider_rejected` |
| `MAX_TOKENS` | Port `truncation` |
| else (e.g. `STOP`) | Success / stop |

### 3.5 Usage and timing

| Rule | Detail |
| --- | --- |
| Cache hits | Map Gemini `cachedContentTokenCount` → canonical `cached` |
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
| Source | Injectable secret-store binding (duplicate D5 inject pattern). Production wires the Worker secrets binding for the Gemini API key — binding name `GEMINI_API_KEY` |
| Not a source | Config files, `vars` in `wrangler.toml`, request body/headers from the clinic client, hard-coded literals in source |
| Returned errors / wire | Credential material MUST NOT appear in any `CanonicalError` payload or captured outbound wire artifact under test (T8, T10, T11) |
| Missing key | Taxonomy may be `provider_rejected`; `consumedBudget: false` (T8) |
| Spy harness | Fake secret-store binding; assert the secret was read from the store, wire auth uses that value, and the secret never appears in returned errors / wire captures. No adapter logger/journal sinks |

D5 froze the real binding pattern for DeepSeek. D7 applies the same path to
Gemini with a distinct binding name and does not rewrite D5's secret-store
rules.

---

## 5. Provider-independence proof (adapter / policy half)

Checkpoint **CP4** requires D7 **plus** F1. This contract freezes the adapter /
fixture / policy half D7 lands; the capability-eval half is tracked in §5.3:

| Proof element | Mechanism | Named test |
| --- | --- | --- |
| Full D5 fixture suite against second provider | Recorded fixtures under `test/fixtures/gemini/` | T1–T11 |
| Added by routing-policy data edit with no pipeline diff | Versioned policy document lists `gemini` as a low-priority target; structural path allowlist permits only second-adapter + routing-policy data (+ provider wiring map); fails if invocation / retry-fallback / stream-broker / validator / journal modules must change | T13 |
| Fallback ordering honoured | Unchanged `selectCandidateChain` yields a chain placing `gemini` after higher-priority targets; selection reason recorded; identical inputs → identical chain. Proven at router output + wiring constructibility (§2.9); end-to-end `portResolver` join is not claimed here | T14 |

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
| Role | Thin `provider_id` → adapter construction map covering DeepSeek and Gemini (`createProviderAdapter`) |
| Boundary | Adapter-side registration only; must not alter D3/D4/D6/C3 pipeline modules |
| Hand-off | Frozen by this slice as constructibility (§2.9). Production `portResolver` composition remains a Worker / invocation composition concern (D3 injects `portResolver`) |

### 5.3 Capability-eval half (FR-010 / T12 / SC-005)

F1 has landed (`specs/039-eval-suite-harness/`, `ai-platform/test/eval/`). The
capability-eval clause is **unblocked by F1 presence**.

| Element | Status |
| --- | --- |
| Live smoke | Targets include `gemini-1.5-flash` (`ai-platform/test/eval/live-smoke.test.ts`) — live-smoke coverage for the second provider exists |
| Permanent proof | Golden-eval inclusion of Gemini in the candidate set remains the permanent proof path for FR-010 / T12 / SC-005 |
| CP4 eval half | Declared satisfied when golden evals include `gemini` in the candidate set; live-smoke alone does not substitute for that permanent path |
| Architecture | Not amended |

---

## 6. Consumers

| Slice | Binding |
| --- | --- |
| **F1** | Eval harness consumed for the CP4 capability-eval half; second provider available via policy / live-smoke targets; MUST NOT invent scoring or redefine this adapter |
| **F5** | Load and cost tests that need D7 |
| **CP4** | Provider independence checkpoint depends on D7 (this artifact) **plus** F1 capability-eval proof (§5.3) |

Later slices MUST **consume** this artifact. They may add further adapters and
policy edits the same way; they must not rewrite this adapter's duties or move
retry/fallback/logging into adapters.

---

## 7. Verification

| Test | Asserts |
| --- | --- |
| T1 | Request-mapping golden against recorded outbound wire (§2.7 floor) |
| T2 | Stream chunks on port `chunks`; empty terminal; content/order/assembly |
| T3 | Usage counters / `cached` / `usage_absent`; measured `provider_ms` |
| T4 | One case per §3.1 wire error class → taxonomy + D2 retryability |
| T5 | Malformed JSON/SSE → classified/normalized failure |
| T6 | Truncated `MAX_TOKENS` / stream-cut → port `truncation`, no new code |
| T7 | Timeout → taxonomy `timeout` with D2 retryability; abort fired |
| T8 | Credentials absent from returned errors / wire; missing key → `consumedBudget: false` |
| T9 | No retry/fallback API on adapter export / options surface |
| T10 | No logger/journal sinks (spy; T8 still holds) |
| T11 | Credentials from secret store only; wire auth uses store secret |
| T13 | Structural allowlist: adapter + policy data + wiring map only |
| T14 | Fallback ordering at router output; wiring constructible |
