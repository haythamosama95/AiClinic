# Feature Specification: Second provider adapter

**Feature Branch**: `ai/034-d7-second-provider-adapter`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `D7` — "Second provider adapter" (delivery plan §3.5, band D).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.5, row D7):

> §4.3.8, §13.5

### Freezes

Contracts this slice establishes for the first time:

- The **second real provider adapter** behind the same D2 provider port already used by D5: one adapter for one additional real provider that translates the canonical inference request to that provider's wire format and normalizes responses, streaming chunks, usage counters, and errors back into the canonical form and the shared error taxonomy; it owns authentication to the provider, request/response mapping, stream chunk normalization, provider-specific structured-output mechanics, timeouts, and classification of every failure as retryable or terminal, and owns nothing else — no retry decisions, no fallback decisions, no logging policy (§4.3.8). Later slices may register further providers the same way; they must not rewrite this adapter's duties or move retry/fallback/logging into adapters.
- The **provider-independence proof for a second real target**: the second provider passes the same recorded-fixture suite shape frozen by D5, and is registered as a low-priority fallback target by a routing-policy data edit alone, with no pipeline change (delivery plan §3.5 Done when; §3.11.4 row D7; §4.3.8 adapter boundary; §13.5 Provider adapter tests). The capability-eval half of that proof — the second provider passing the golden capability evals frozen by F1 — is tracked under FR-010 / T12 / SC-005 (see *Capability-eval clause* below). Checkpoint CP4 rests on both halves and is therefore reached by D7 **plus** F1, not by D7 alone (delivery plan §3.5 "D7 plus F1 satisfy CP4"; §5).

### Consumes

Contracts frozen by earlier slices that this slice binds to. Every entry below has an existing implementation on disk. Changing any of these is out of scope by definition:

- **From D5 (first real provider adapter)**: the **first real provider adapter**, the **recorded-fixture adapter suite shape** (request-mapping golden; stream normalization with empty terminal; usage extraction including `cached` / `usage_absent`; one case per provider error class mapped to the taxonomy; malformed JSON/SSE; truncated finish / stream-cut; timeout with abort; credentials absent from returned errors / wire; missing key → `consumedBudget: false`), and the **secret-store credential path** for a real provider (§4.3.8 Freezes in D5; delivery plan §3.11.4 row D5). D7 applies that same suite shape to the second provider and does not rewrite D5's adapter, suite contract, or secret-store binding rules.
- **From D5 / D2 (via D5 Consumes)**: the **provider port contract** — canonical request in; canonical stream chunks, result, or classified error out; adapters own mapping, normalization, timeouts, and retryable/terminal classification; adapters own no retry, fallback, or logging policy; the classification contract is exhaustive over the error taxonomy (§4.3.8 Freezes in D2 / Consumes in D5). D7 implements a second real adapter against this port and does not redefine the port, the taxonomy, or retryability.
- **From D5 / D2 (via D5 Consumes)**: the **routing-policy-as-data contract** — versioned policy yields an ordered candidate chain; selection is stateless; the selection reason is recorded; the outgoing-connection cap of six bounds speculative parallelism (§4.3.7, §4.3.8 Freezes in D2). D7 registers the second provider as a low-priority fallback target by editing policy data only and must not alter router selection logic, the cap, or policy schema meaning.
- **From D5 / D2 / A3 (via D5 Consumes)**: the canonical request, stream chunk, result, and error types — including taxonomy code, retryability, and provider-native diagnostics — that the adapter must emit; nothing upstream of adapters may contain a provider-shaped field (§5.3 via D2/D5).
- **From F1 (eval suite harness and first capability eval)**: the **capability eval harness** — golden cases run per capability in CI against fixtures; scheduled live smoke against pinned model versions (§13.5 Capability evals (A9); delivery plan §3.7 row F1; `specs/039-eval-suite-harness/`, `ai-platform/test/eval/`). D7 neither authors nor redefines the harness, its scoring, or its smoke schedule.

### Capability-eval clause (FR-010 / T12 / SC-005)

F1 has landed. The capability-eval clause is **unblocked by F1 presence**. Live-smoke already targets `gemini-1.5-flash`. Golden-eval inclusion of Gemini in the candidate set remains the permanent proof path for FR-010 / T12 / SC-005 and the CP4 eval half. Live-smoke coverage alone does not substitute for that permanent path. Architecture is not amended.

This slice's implementable adapter / fixture / policy scope does not invent a substitute harness:

- **Landed by D7**: the second real provider adapter, its recorded-fixture suite (the full D5 case list against the second provider), secret-store credential handling, routing-policy registration as a low-priority fallback target with no pipeline diff, and fallback ordering (router output + wiring constructibility; end-to-end `portResolver` join is not claimed — see contract §2.9).
- **Proven with F1**: the capability-eval acceptance — FR-010, T12, SC-005, and the "capability evals" clause of the delivery plan's D7 `Done when` row — via golden evals with Gemini in the candidate set.

**Binding rule for the plan phase**: `## Consumes Binding` covers the adapter / port / policy / canonical entries above. F1 is present on disk; the capability-eval clause is tracked as unblocked permanent proof, not as a missing implementation (stop condition 2).

### Open decisions relied on

- **Open Decision 11** (local/on-LAN provider adapter): recommended default is not now. This slice assumes the second real adapter is a remote provider reached with credentials from the platform secret store, not an on-LAN OpenAI-compatible endpoint (§15 OD-11; §4.3.8).
- **Open Decision 5** (per-clinic model or provider preference): recommended default is no initially. This slice does not introduce a per-clinic preference surface; the second provider is selected as a low-priority fallback by routing-policy data alone (§15 OD-5; consistent with D2/D5).

## Clarifications

### Session 2026-08-02

- Q: Which commercial remote provider should the second real adapter target (distinct from D5’s DeepSeek)? → A: Gemini `[implementation choice — no §citation]`
- Q: Where should the second real adapter live under `ai-platform/src/`? → A: Under existing `src/provider/` (sibling to port, fake, and DeepSeek), e.g. `gemini.ts` + adapter-fixture tests `[implementation choice — no §citation]`
- Q: How should T13 (`added_by_routing_policy_edit_no_pipeline_diff`) prove the second provider is added without an inference-pipeline change? → A: Structural path allowlist: only second-adapter + routing-policy data (+ provider wiring map) may be required; fail if invocation / retry-fallback / stream-broker / validator / journal pipeline modules must change `[implementation choice — no §citation]`
- Q: How should T12 (`capability_evals_pass_with_second_provider`) make the second provider available to the F1 harness without redefining it? → A: Versioned routing-policy fixture listing the second provider as a low-priority candidate; invoke the F1 harness unchanged `[implementation choice — no §citation]` *(superseded in effect by the deferral below: this describes how T12 will be satisfied when F1 lands, not work this slice performs)*
- Q: F1 (capability eval harness) has no implementation on disk, so D7 cannot bind it as a hard `Consumes` entry. How should D7 proceed without inventing F1? → A: Split the slice's Done when — land the adapter, fixture suite, policy registration, and fallback ordering now against the D5/D2/A3 contracts that exist; defer the capability-eval acceptance (FR-010 / T12 / SC-005 / acceptance scenario 9) to F1 under a `blocked_on_F1` marker, with the binding contract stated in *Deferred consumption* so a later slice can bind it. CP4 remains gated on D7 **and** F1 `[escalation resolution 2026-08-02 — delivery plan §3.5, §3.7, §5]` *(superseded 2026-08-04: F1 has landed; see Session 2026-08-04 and *Capability-eval clause*)*
- Q: How should D7’s adapter-fixture suite obtain D5’s transport / secret-store / recording-sink injection shape without rewriting D5? → A: Reuse D5’s existing injection ports/helpers if already shared; otherwise duplicate the inject pattern in D7 tests without modifying D5’s adapter or suite contract `[implementation choice — no §citation]`

### Session 2026-08-04 (review resolution)

- Q: What are terminal stream-chunk semantics? → A: Exactly one terminal chunk; terminal MUST NOT re-emit assembled text (empty `text_delta` terminal marker). Non-terminal deltas carry content `[clarifies A3 / D2 chunk invariant — same as D5]`
- Q: How are Gemini SSE wire failures classified? → A: Malformed SSE data lines → port `malformed` / classified failure (not silent skip-success). Stream cut without a terminal finish reason → port `truncation` (no new taxonomy code). Mid-stream provider `error` frames → classified error `[clarifies §4.3.8 / FR-005]`
- Q: How do Gemini finish reasons map? → A: `SAFETY` / `BLOCKLIST` → `provider_rejected` (terminal); `MAX_TOKENS` → truncation; else stop `[implementation choice — no §citation]`
- Q: Does a missing API key consume budget? → A: Taxonomy may remain `provider_rejected`, but `consumedBudget` MUST be `false` (provider never reached) `[clarifies A3 consumedBudget / §4.3.8]`
- Q: How is usage extracted? → A: Map `cachedContentTokenCount` → `cached`; absent usage emits `provider_note` `{ note: "usage_absent" }` with zero-filled counters; adapter measures `provider_ms` `[implementation choice — mirrors D5]`
- Q: Is fixture transport byte-streaming? → A: No — D7 fixture transport models the full response body as one string (post-hoc SSE parse); incremental delivery is out of scope for this slice's harness. Chunks still normalize to the port `chunks` array `[contract §2.6 — same class as D5 Deviation 4]`
- Q: Is A3 `deadline` an absolute timestamp? → A: D7 treats `deadline` as a remaining-duration budget in milliseconds (min with adapter `timeoutMs`), matching existing fixtures — not an absolute epoch. Architecture is not amended `[contract §2.5 — same class as D5 Deviation 5]`
- Q: What is the Gemini wire-mapping floor? → A: `system` → `systemInstruction`; `data` → `user`; `assistant` → `model`; consecutive same-role merge; `top_k` → `topK`; JSON schema → `responseSchema`; non-empty `toolDeclarations` → `tools.functionDeclarations`. `allowedLanguages` still not mapped `[contract §2.7]`
- Q: Does policy `model_id` reconfigure the adapter? → A: No — adapter pins `gemini-1.5-flash` matching platform-default policy; port does not yet thread per-target `model_id` (same class of gap as D5). Policy edit of `model_id` alone does not reconfigure until a later port extension `[contract §2.8]`
- Q: Does wiring.ts prove end-to-end fallback reachability? → A: `createProviderAdapter` is the thin map frozen by this slice; production `portResolver` composition remains a composition concern (D3 injects `portResolver`). Registration proven at router output + wiring constructibility; end-to-end join is not claimed `[contract §2.9]`
- Q: Is F1 still unimplemented? → A: No — F1 has landed (`specs/039-eval-suite-harness/`, `ai-platform/test/eval/`). Live-smoke targets `gemini-1.5-flash`. Golden-eval inclusion of Gemini remains the permanent proof path for FR-010 / T12 / SC-005 / CP4 eval half `[capability-eval clause update — no architecture change]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Second provider adapter (Priority: P1)

As the AI Gateway Worker, after the first real provider adapter (D5) exists, I add a second real provider behind the same provider port: I prove wire mapping (including `systemInstruction` and the documented wire-mapping floor), stream normalization (exactly one empty terminal), usage extraction, and error classification against the same recorded-fixture suite shape used for the first provider, including malformed JSON/SSE and truncated finish / stream-cut responses and timeout with abort, with credentials from the secret store absent from returned canonical errors and captured wire artifacts (`consumedBudget: false` when the key is missing). I register that provider as a low-priority fallback target by editing routing-policy data alone — with no change to the inference pipeline — so fallback ordering is honoured at router output. Capability evals with Gemini in the candidate set are proven through the F1 harness (*Capability-eval clause*).

**Why this priority**: D7 sits after D5 because D5 is the point at which one real adapter and the recorded-fixture bar exist — without it, a second provider would invent the fixture bar. The eval gate is F1's. D7 **plus** F1 is checkpoint **CP4**: provider independence proven by adapter and policy alone, with no pipeline change (delivery plan §3.5, §5).

**Independent Test**: A second provider passes the same fixture suite and is registered as a low-priority fallback target by routing policy alone, with no pipeline change (delivery plan §3.5 Done when; §3.11.4 row D7). The eval clause of that row is proven with F1 (golden evals with Gemini in the candidate set; live-smoke already covers `gemini-1.5-flash`).

**Acceptance Scenarios**:

1. **Given** a canonical inference request fixture and the second real provider adapter, **When** the adapter maps the request to the provider's wire format, **Then** the emitted wire request matches the recorded request-mapping golden for that fixture (including `system` → `systemInstruction` and the §2.7 wire-mapping floor). *(request-mapping golden — full D5 case list against the second provider)*
2. **Given** a recorded provider stream fixture for the second provider, **When** the adapter normalizes stream chunks onto the port `chunks` array, **Then** every chunk is canonical (no provider-shaped fields), non-terminal deltas carry content, and exactly one terminal chunk is an empty `text_delta` marker (assembled text is not re-emitted). *(stream normalization)*
3. **Given** a recorded second-provider response that reports usage (or omits it), **When** the adapter completes normalization, **Then** usage counters land in canonical form (`cachedContentTokenCount` → `cached`); absent usage yields zero-filled counters plus `provider_note` `{ note: "usage_absent" }`. *(usage extraction)*
4. **Given** a recorded second-provider failure for each provider error class the adapter must map, **When** the adapter classifies the failure, **Then** each class maps to exactly one taxonomy code with the D2 retryable-versus-terminal classification — one acceptance case per class. *(one case per provider error class mapped to the taxonomy)*
5. **Given** a recorded malformed second-provider response (non-stream JSON **or** malformed SSE data line), **When** the adapter handles it, **Then** the outcome is port `malformed` / a classified canonical error — not an unclassified throw and not silent skip-success. *(malformed response)*
6. **Given** a recorded truncated second-provider response (`finishReason: MAX_TOKENS` **or** SSE cut without a terminal finish), **When** the adapter handles it, **Then** the outcome is port `truncation` (or the port's required truncated form) without inventing a new taxonomy code. *(truncated response)*
7. **Given** a recorded or simulated second-provider deadline exceeded, **When** the adapter's owned timeout path fires (remaining-ms `deadline` min'd with `timeoutMs`; caller `signal` combined), **Then** the failure is classified into the taxonomy as the timeout class with the D2 retryability for that code, and the outbound fetch is aborted. *(timeout)*
8. **Given** the second adapter invoked with credentials loaded from the platform secret store (or with the secret missing), **When** it returns a canonical error or success, **Then** credentials are absent from every returned canonical error payload and captured wire artifact; missing credentials keep `consumedBudget: false`. *(credentials absent; missing-key budget flag)*
9. **Given** the F1 capability eval harness and golden cases for the first capability, **When** the suite runs with the second provider available as a candidate, **Then** the capability evals pass (golden cases against fixtures; the harness does not redefine scoring). Live-smoke already targets `gemini-1.5-flash`; golden-eval inclusion remains the permanent proof path. *(capability evals pass — proven with F1)*
10. **Given** the inference pipeline modules as they stood after D5/F1, **When** the second provider is added, **Then** the change set is the second adapter plus a routing-policy data edit — with no pipeline diff (no change to invocation, retry/fallback loop, stream broker, or other pipeline stages). *(the provider is added by a routing-policy edit with no pipeline diff)*
11. **Given** a versioned routing policy that lists the second provider as a low-priority fallback after higher-priority targets, **When** the router yields a candidate chain for identical capability/request inputs, **Then** the chain orders the second provider after those higher-priority targets and the selection reason is recorded — fallback ordering is honoured at router output + wiring constructibility without adapter-owned fallback decisions (end-to-end `portResolver` join is not claimed). *(fallback ordering honoured)*

### Test plan

Layer: Adapter fixtures + evals (delivery plan §3.11.4, row D7; §13.5 Provider adapter tests — recorded provider fixtures, including malformed and truncated responses; §13.5 Capability evals (A9)). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `second_provider_request_mapping_golden` | Adapter fixtures | Canonical request → second-provider wire format matches golden incl. wire-mapping floor (§3.11.4 D7 ← D5; §4.3.8; Done when) |
| T2 | `second_provider_stream_normalization` | Adapter fixtures | Provider stream → port `chunks`; exactly one empty terminal; content/order/assembly (§3.11.4 D7 ← D5; §4.3.8; Done when) |
| T3 | `second_provider_usage_extraction` | Adapter fixtures | Usage counters + `cached` mapping; absent usage → `usage_absent` note (§3.11.4 D7 ← D5; §4.3.8; Done when) |
| T4 | `second_provider_error_class_mapped_to_taxonomy` | Adapter fixtures | One case per second-provider error class mapped to the taxonomy with D2 retryable/terminal classification (§3.11.4 D7 ← D5; §4.3.8; §3.10 — suite expands to one named subcase per class under the D2 classification contract; no new taxonomy codes) |
| T5 | `second_provider_malformed_response` | Adapter fixtures | Malformed JSON or SSE → classified/normalized failure, not silent success (§3.11.4 D7 ← D5; §4.3.8; Done when) |
| T6 | `second_provider_truncated_response` | Adapter fixtures | `MAX_TOKENS` finish or stream cut → port `truncation` (§3.11.4 D7 ← D5; §4.3.8; Done when) |
| T7 | `second_provider_timeout` | Adapter fixtures | Adapter-owned timeout / deadline exceeded → taxonomy timeout; abort signal fired (§3.11.4 D7 ← D5; §4.3.8) |
| T8 | `second_provider_credentials_absent_from_logs_and_journal` | Adapter fixtures (spy) | Credentials from secret store; absent from returned canonical errors / wire artifacts; missing key → `consumedBudget: false` (§3.11.4 D7 ← D5; §4.3.8; Done when) |
| T9 | `second_adapter_owns_no_retry_or_fallback` | Adapter fixtures | Adapter surface exposes classification only — no retry or fallback decision API (§4.3.8; §3.10 inherited prohibition) |
| T10 | `second_adapter_owns_no_logging_policy` | Adapter fixtures (spy) | Adapter does not own logging policy / accepts no logger-journal sinks (D2 repair); T8 still holds (§4.3.8; §3.10) |
| T11 | `second_provider_credentials_from_secret_store_only` | Adapter fixtures (spy) | Authentication credentials are obtained from the platform secret store binding, not from config files or request input (§4.3.8) |
| T12 | `capability_evals_pass_with_second_provider` | Capability evals (A9) / CI | F1 golden capability evals pass with the second provider in the candidate set; live-smoke already covers `gemini-1.5-flash`; golden-eval inclusion is the permanent proof path (§3.11.4 D7; §13.5; delivery plan §3.5 Done when eval clause; unblocked by F1) |
| T13 | `added_by_routing_policy_edit_no_pipeline_diff` | Adapter fixtures + policy / structural | Second provider registered by routing-policy data edit; inference pipeline modules have no required diff (§3.11.4 D7; Done when; §4.3.8 adapter owns no fallback) |
| T14 | `fallback_ordering_honoured` | Unit (router + policy) | Policy listing the second provider as low-priority fallback yields an ordered chain that places it after higher-priority targets; selection reason recorded; identical inputs → identical chain (§3.11.4 D7; Consumes D2 routing-policy-as-data; contract §2.9) |

---

### Edge Cases

- **Error codes this slice can emit.** The second adapter does not invent taxonomy codes. It maps provider wire failures into the shared error taxonomy under the D2 classification contract (retryable versus terminal). The suite must include one case per provider error class the second adapter maps — the full D5 case list against the second provider (§3.11.4 D7 ← D5; §3.10). Exhausting a candidate chain and surfacing `provider_unavailable` remains D3.
- **Malformed response.** Malformed non-stream JSON **and** malformed SSE data lines → port `malformed` / classified failure — not an unclassified throw and not silent skip-success (§4.3.8; delivery plan §3.11.4 D5/D7).
- **Truncated response.** `finishReason: MAX_TOKENS` **and** SSE cut without a terminal finish → port `truncation`; no new taxonomy code (§3.11.4 D5/D7; Done when). Mid-stream provider `error` frames → classified error (not success with partial content).
- **Empty terminal delta.** Exactly one terminal chunk; terminal MUST NOT re-emit assembled text (empty `text_delta` marker). Non-terminal deltas carry content.
- **systemInstruction mapping.** Canonical `system` parts map to Gemini `systemInstruction`, not `contents[].role`. `data` → `user`; `assistant` → `model`; consecutive same-role parts merge. See contract §2.7.
- **Timeout / deadline.** Adapters own timeouts (§4.3.8). D7 treats A3 `deadline` as a remaining-duration budget in ms (min with adapter `timeoutMs`), matching fixtures — not an absolute epoch (adapter interpretation only; architecture unchanged — contract §2.5). Timeout aborts the outbound fetch via the combined caller/adapter signal.
- **Missing credentials.** Absent secret may classify as `provider_rejected`, but `consumedBudget` MUST be `false` (provider never reached).
- **Usage / timing.** Map `cachedContentTokenCount` → `cached`; absent usage → zero-filled counters + `provider_note` `{ note: "usage_absent" }`. Adapter measures `provider_ms` around the outbound transport call.
- **Buffered fixture transport.** Fixture harness models the full response body as one string (post-hoc SSE parse); incremental byte delivery is out of scope for this slice (contract §2.6).
- **Credentials.** Credentials come only from the platform secret store; they must not appear in returned canonical errors or captured wire artifacts (§4.3.8). T8/T11 spy those surfaces (no adapter logger/journal sinks).
- **Retry / fallback / logging policy.** The second adapter classifies only. Bounded retry, fallback, regenerating, and uniform logging policy remain outside the adapter (D3 / platform telemetry) (§4.3.8). Registration as a low-priority fallback is a routing-policy data concern, not an adapter decision. Wiring map hand-off: constructibility + router output; end-to-end `portResolver` join not claimed (contract §2.9).
- **Pipeline immutability.** Adding the second provider must not change the inference pipeline. A required change to invocation, retry/fallback loop, stream broker, validator, or journal writer to accommodate the second provider is a stop condition against Consumes / Done when (delivery plan §3.5 Done when; §3.11.4 D7).
- **Fallback ordering.** When policy lists the second provider after higher-priority targets, the ordered chain must honour that priority. The adapter must not reorder, skip, or self-promote (§4.3.8; Consumes D2).
- **Capability evals.** Evals are F1's harness (`specs/039-eval-suite-harness/`, `ai-platform/test/eval/`). D7 does not invent golden cases, scoring, or smoke schedules. Live-smoke already targets `gemini-1.5-flash`; golden-eval inclusion of Gemini in the candidate set remains the permanent proof path for FR-010 / T12 / SC-005 (§13.5; *Capability-eval clause*). Architecture is not amended.
- **Structured-output mechanics.** The second adapter may own provider-specific structured-output wire mechanics (§4.3.8), including JSON `responseSchema` and tool `functionDeclarations` per contract §2.7. Pipeline-level structured/`structured_atomic` streaming modes and validation/repair remain D6; this slice does not pull D6 forward. `allowedLanguages` is still not mapped.
- **Outgoing-connection cap of six.** Stated in §4.3.8 and frozen by D2 for routing parallelism. D7 does not raise or bypass the cap and does not add speculative fan-out in the adapter.
- **No per-request server-side state.** The adapter holds no per-request Durable Object or other server-side request state; an in-flight call exists only as the open provider connection plus journal rows owned elsewhere (§4.3.8 with §4.4 / §9.7 prohibitions inherited via delivery plan §6.4).
- **First adapter coexistence.** D5's first real adapter and the D2 fake remain unchanged. D7 adds a second real adapter; it does not delete, redefine, or fold providers into one module (§4.3.8 one adapter per provider; Consumes D5).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The second real provider adapter MUST translate the canonical inference request to that provider's wire format and normalize its responses, streaming chunks (exactly one empty-terminal marker on port `chunks`), usage counters, and errors back into the canonical form and the shared error taxonomy (§4.3.8).
- **FR-002**: The second adapter MUST own authentication to the provider, request/response mapping (including the wire-mapping floor in contract §2.7), stream chunk normalization, provider-specific structured-output mechanics, timeouts (remaining-ms `deadline` min'd with `timeoutMs`; caller `signal` combined), measured `provider_ms`, and classification of every failure as retryable or terminal (§4.3.8).
- **FR-003**: The second adapter MUST own nothing else — no retry decisions, no fallback decisions, no logging policy (no logger/journal sinks) — so those behaviours stay uniform across providers (§4.3.8; D2 repair).
- **FR-004**: There MUST be exactly one adapter per provider; this slice adds a second provider's adapter as a separate adapter and MUST NOT fold it into the first provider's adapter module (§4.3.8; Consumes D5).
- **FR-005**: Wire mapping, stream normalization, usage extraction (`cached` / `usage_absent`), and error classification for the second provider MUST pass against recorded fixtures, including malformed JSON/SSE and truncated (`MAX_TOKENS` / stream-cut) responses — the full D5 fixture case list against the second provider (§4.3.8; delivery plan §3.5 Done when; §3.11.4 D7 ← D5; §13.5 Provider adapter tests).
- **FR-006**: Every provider error class the second adapter maps MUST have exactly one fixture case that maps it into the shared error taxonomy under the D2 retryable-versus-terminal classification contract, without adding taxonomy codes (§4.3.8; delivery plan §3.11.4 D7 ← D5; Consumes D2/D5).
- **FR-007**: The second adapter MUST classify timeout / deadline-exceeded failures into the taxonomy's timeout class consistent with D2 classification and MUST abort the outbound fetch (§4.3.8; delivery plan §3.11.4 D7 ← D5).
- **FR-008**: Provider credentials for the second provider MUST come from the platform's secret store and MUST NOT appear in returned canonical error payloads or captured wire artifacts (§4.3.8). Missing credentials MAY use taxonomy `provider_rejected` but MUST set `consumedBudget: false`.
- **FR-009**: Credentials MUST be absent from every returned canonical error and captured wire artifact produced while exercising the second adapter (delivery plan §3.11.4 D7 ← D5; §4.3.8).
- **FR-010**: The second provider MUST pass the capability evals under the F1 harness (§13.5 Capability evals (A9); delivery plan §3.5 Done when; §3.11.4 D7). Unblocked by F1 presence (`specs/039-eval-suite-harness/`, `ai-platform/test/eval/`). Live-smoke already targets `gemini-1.5-flash`; golden-eval inclusion of Gemini in the candidate set is the permanent proof path for the CP4 eval half. Architecture is not amended.
- **FR-011**: The second provider MUST be registered as a low-priority fallback target by a routing-policy data edit alone, with no inference-pipeline change (§4.3.8 adapter owns no fallback; delivery plan §3.5 Done when; §3.11.4 D7; Consumes D2 routing-policy-as-data). Wiring constructibility via `createProviderAdapter` is frozen; end-to-end `portResolver` join is not claimed (contract §2.9).
- **FR-012**: When the routing policy lists the second provider as a low-priority fallback, the ordered candidate chain MUST honour that fallback ordering and record the selection reason (§3.11.4 D7; Consumes D2).

### Key Entities

Not applicable — this slice defines no entities. It implements a second real adapter against the provider port and related contracts already frozen by D2/D5 (and A3 via those slices), and consumes the F1 eval harness.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: A second provider behind the same port, registered by policy data alone, lets clinic-scale operations survive a primary-provider incident without a client release or pipeline rewrite — the independence claim CP4 guards (delivery plan §3.5, §5; §4.3.8). Fixture-based adapter tests and CI capability evals keep proof free of ad-hoc live-provider cost at clinic scale (§13.5; DP-3).
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker): a second provider adapter and routing-policy data registration. Capability-eval proof uses the landed F1 harness (golden-eval inclusion permanent path; live-smoke already covers `gemini-1.5-flash`). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. Provider credentials stay in the Worker's secret store; provider names and model identifiers must never enter the Flutter client (R-12).
- **Data Integrity & Security**: Credentials come from the secret-store binding and appear in no log or journal row (§4.3.8). The adapter does not write clinical data and does not open a write path into Supabase. Journal rows remain C3's concern; this slice only guarantees credential absence from any journalable record it emits into those sinks under test.
- **Failure Handling**: Adapter-classified retryable failures remain what D3 retries; terminal failures are not retried by the platform attempt loop (§4.3.8). When higher-priority targets fail, policy-ordered fallback reaches the second provider without adapter-owned fallback decisions. Malformed, truncated, and timeout fixtures prove classification without live egress. Provider unavailability of the whole chain remains D3 (`provider_unavailable`). AI remains additive: adapter or provider failure degrades AI features only; clinic workflows continue (A11 / §14).

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **D5 (first real provider adapter)**: D7 consumes the first adapter, fixture-suite shape, and secret-store path; it does not rewrite them or replace the first provider (§4.3.8 Freezes/Consumes from D5).
- **D2 (provider port, fake, routing policy)**: D7 consumes the port, classification contract, and routing-policy-as-data; it does not redefine them, replace the fake for pipeline tests, or change router selection logic or the outgoing-connection cap of six. Only a policy *data* edit registers the new target.
- **D3 (invocation with bounded retry and fallback)**: D7 classifies failures and relies on policy ordering; it does not retry, jitter, fall back inside the adapter, journal attempts as the attempt loop, emit `provider_unavailable`, or emit regenerating (§4.3.7, §8.6).
- **D4 (stream broker)**: D7 normalizes chunks at the adapter boundary; relaying to the client, heartbeats, incremental guards, and cancellation are D4 (§4.3.10).
- **D6 (response validator, repair, structured output modes)**: Adapter-owned provider-specific structured-output *wire* mechanics may exist here; schema/business/safety validation, bounded repair, and `structured` / `structured_atomic` broker modes are D6 (§4.3.9).
- **F1 (eval suite harness and first capability eval)**: the harness itself, its golden cases, its scoring, and its scheduled live smoke are F1's (§13.5; delivery plan §3.7 row F1; `specs/039-eval-suite-harness/`). F1 has landed; live-smoke already targets `gemini-1.5-flash`. The capability-eval acceptance for the second provider (FR-010 / T12 / SC-005) is proven through that harness — golden-eval inclusion of Gemini remains the permanent proof path. D7 must not invent a substitute eval system.
- **F5 (load and cost tests)**: Needs D7; load/cost assertions are F5, not this slice (delivery plan §3.7).
- **C3 (journal writer)**: D7 asserts credentials are absent from returned errors / wire artifacts under spy; writing `ai_attempt` / R2 envelopes is C3 (§4.3.11).
- **J3 (staged rollout / canary)**: Activating a routing-policy version for a named cohort, promotion, and rollback are J3. D7 registers the target in policy data and proves ordering; cohort canary activation is not this slice.
- **On-LAN / local provider adapter**: Deferred (Open Decision 11 / later band); not this slice.
- **Health-based provider routing / circuit breakers**: Deliberate deferrals under §9.14; not added because they look prudent (R-20).
- **A third or further provider**: Out of scope; this slice proves the second only.
- **End-to-end `portResolver` join / per-target `model_id` threading**: Composition of production `portResolver` from `createProviderAdapter`, and port threading of policy `model_id` into the adapter, are later concerns (contract §2.8–§2.9). Not claimed by this slice's done-when.

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — D7 is a Worker slice; provider identity stays in adapter internals and routing-policy data.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — D7 performs no Quota DO and no R2 I/O of its own.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An adapter-fixture suite against the second provider proves request-mapping golden (incl. wire-mapping floor), stream normalization (empty terminal), and usage extraction (`cached` / `usage_absent`) against recorded fixtures — the full D5 mapping/normalization/usage clause applied to the second provider (T1–T3; Done when; §3.11.4 D7).
- **SC-002**: The suite proves one case per second-provider error class mapped to the taxonomy under the D2 classification contract, plus malformed JSON/SSE, truncated (`MAX_TOKENS` / stream-cut), and timeout with abort (T4–T7; §3.11.4 D7 ← D5; Done when).
- **SC-003**: A spy proves credentials for the second provider come from the secret store and appear in no returned canonical error or captured wire artifact; missing key → `consumedBudget: false` (T8, T11; §4.3.8).
- **SC-004**: Tests prove the second adapter owns no retry or fallback decisions and no logging policy (T9–T10; §4.3.8; §3.10).
- **SC-005**: Capability evals under the F1 harness pass with the second provider available (T12; Done when; §13.5). Unblocked by F1 presence; live-smoke covers `gemini-1.5-flash`; golden-eval inclusion of Gemini in the candidate set is the permanent proof path for the CP4 eval half. Architecture is not amended.
- **SC-006**: The second provider is added by a routing-policy data edit with no inference-pipeline diff, and fallback ordering is honoured when the policy lists it as a low-priority fallback (T13–T14; Done when; §3.11.4 D7; contract §2.9).

## Assumptions

- The provider port and retryable-versus-terminal classification contract are frozen by D2 and consumed via D5; D7 implements a second adapter against them and does not amend them (§4.3.8 Freezes in D2/D5).
- The first real provider adapter, fixture-suite shape, and secret-store credential path are frozen by D5; D7 applies the same suite shape to a second provider and does not rewrite D5 (§4.3.8 Freezes in D5).
- The capability eval harness (golden cases in CI; scheduled live smoke against pinned models) is F1's contract (§13.5; delivery plan §3.7). F1 has landed (`specs/039-eval-suite-harness/`, `ai-platform/test/eval/`). Live-smoke already targets `gemini-1.5-flash`. Golden-eval inclusion of Gemini remains the permanent proof path for T12 / FR-010 / SC-005 and the CP4 eval half.
- The canonical inference types and shared error taxonomy are already frozen (A3/A2 via D2/D5); D7 maps into them and adds no code (§5.3 / §5.4 via Consumes).
- Which commercial remote provider is "second" is not named in §4.3.8 or the delivery plan row; the adapter duties, fixture suite, policy registration, and eval gate are fully specified without that product pick. Selecting among architecture-permitted remote providers distinct from D5's first provider is an implementation choice for the clarify stage, not a licence to invent port fields or taxonomy codes.
- Recorded fixtures (not live egress) are the permanent proof for this slice's adapter-fixture suite (delivery plan §3.11.4 D7 ← D5; §13.5 Provider adapter tests; DP-3). Capability evals follow F1's fixture/CI and scheduled-smoke split (§13.5).
- Secret-store bindings for provider credentials exist as part of the Worker environment model (A1 / §4.4 secrets binding); D7 wires the second real adapter to that binding pattern and does not invent a second credential store.
- Registering the second provider as a low-priority fallback is a versioned routing-policy *data* edit under the D2 contract; it is not a change to router code, pipeline stages, capability manifests, or the Flutter client (delivery plan §3.5 Done when; Consumes D2). Wiring map hand-off and model-identity pin are documented in contract §2.8–§2.9 without claiming architecture changes.
- The platform does not ship until the whole product does (DP-1); "independently testable" means provable by an automated fixture and eval suite, not demonstrable to a user (DP-3).
- Open Decision 11's default (no on-LAN adapter now) and Open Decision 5's default (no per-clinic preference initially) hold for this slice (§15).
