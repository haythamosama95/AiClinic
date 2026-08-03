# Feature Specification: Context validator stage and cost pre-flight

**Feature Branch**: `026-context-validator-cost-preflight`

**Created**: 2026-08-01

**Status**: Draft

**Input**: Slice `C2` — "Context validator stage and cost pre-flight" (delivery plan §3.4, band C).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.4, row C2):

> §4.3.5, §5.2, §4.3.3, §6.1 stages 6–7

### Freezes

Contracts this slice establishes for the first time:

- The **context validator stage output**: the filtered, declaration-conformant context payload that is handed forward to the composer. Its shape is "only the manifest-declared keys, each conforming to its published shape, with everything else dropped" (§4.3.5, §5.2 Minimization). Later slices (D1 composer) consume this filtered payload and may rely on it containing no undeclared keys.
- The **`context_required` rejection payload**: the missing-key manifest — the set of missing required keys, each with its declared shape, plus the manifest version (§4.3.5, §8.4). Slice J2 later wires the client self-healing *behaviour* against this payload; the payload itself is frozen here.
- The **cost pre-flight decision surface**: a single boolean per request — "does (estimated input tokens + the capability's declared `maxOutputTokens`) exceed the manifest's token-denominated `perRequestCostCeiling`, or does the estimate alone exceed `maxInputTokens`?" — computed in tokens with the §13.6.2 estimator and emitted before egress (§4.3.3, §6.1 stage 7, §13.6.2). Slice B4 admission consumes "no" from here; slice D3 invocation consumes only requests that passed.

### Consumes

Contracts frozen by the slices in `Needs` (A5, C1). Changing any of these is out of scope by definition:

- **From A5**: the context-key vocabulary (`domain.concept@vN`), the platform-published per-key shapes (field names, types, cardinality, units), the per-key max-size bound, and the config cache that serves keys/manifests from a warm isolate with no I/O (§5.2).
- **From A5 (D1 schema)**: nothing C2 writes — C2 performs no D1 I/O; stages 6–7 are CPU-only (§6.1).
- **From A2**: the error taxonomy as a closed set, including `context_required` (422, retryable after resolving, consumes no quota), `context_invalid` (422, not retryable, consumes no quota), and `request_too_large` (413, not retryable, consumes no quota) (§5.4).
- **From A3**: the canonical request representation that the filtered context is rendered into (§5.3).
- **From A4 / C1**: the immutable capability manifest, specifically its **Context requirements** field group (ordered list of context keys with `required`/`optional`, shape reference, max size, freshness hint) and its **Economics** field group (max input tokens, max output tokens, per-request cost ceiling, quota weight) (§5.1).
- **From A6**: the protocol adapter headers and the request principal established upstream (§4.3.1).
- **From B3**: the verified token claims — in particular `org` and `branch` — made immutable to later stages (§4.3.2, §5.6).

### Open decisions relied on

None. C2 reads only manifest fields and token claims that the architecture fully specifies; no §15 recommended default is assumed by this slice.

## Clarifications

### Session 2026-08-01

- Q: How should C2 freeze and produce the `context_required` missing-key manifest payload (which §8.4 requires to reach the client) given that A2's `ErrorBody` is a closed four-field shape and A6's adapter is frozen? → A: C2 owns a code-specific `context_required` HTTP 422 builder in a new C2 module, calling A2's `buildErrorBody` for the four common fields (`code`, `request_reference`, `trace_id`, `retry_safe`) and attaching a frozen snake_case missing-key manifest. A6's adapter is left untouched (its ingress-too-large gate and SSE framing remain its; only `context_required` carries extra fields). Manifest payload shape: `{ missing_keys: string[], shapes: Record<string, KeyShape>, manifest_version: string, manifest_capability_id: string }`, where `manifest_capability_id` + `manifest_version` together identify the capability the stale client must refresh. `[implementation choice — no §citation]`
- Q: How should C2 estimate input tokens for the cost pre-flight, and in what unit does the comparison against `perRequestCostCeiling` happen? → A: **Escalated as an architecture gap and resolved in the architecture, not in this slice.** §5.1, §6.1 stage 7, A6, and the new §13.6.2 now state: (a) `perRequestCostCeiling` is **token-denominated** — the maximum billable tokens per request — so the pre-flight compares tokens to tokens and no token→cost multiplier and no provider price ever enters the Worker; (b) the estimator is the fixed, deterministic, provider-independent formula `estimatedInputTokens = ceil(utf8ByteLength(serialized request input) / 4) * 1.15`, with the divisor and safety factor as platform constants; (c) the check is `estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling`, with the secondary bound `estimatedInputTokens ≤ maxInputTokens`. Money appears only in the post-response `usage_event` ledger, priced from provider-reported actuals. (§5.1, §6.1 stage 7, §13.6.2, A6)

### Session 2026-08-03 (C2 review resolution)

- Q: How do prompt-artifact bytes enter the §13.6.2 measured input? → A: `estimateInputTokens` / `runCostPreflight` take optional `promptArtifactByteLength` (default 0); total bytes = utf8(serializedInput) + artifact bytes. Aligns FR-007 with §13.6.2 without amending architecture prose.
- Q: How are H2 conversational outcomes reflected in the C2 contract? → A: Contract extension documents `conversation_budget_exhausted`, the optional fourth `validateContext` argument, and the H2 type exports — code already matched §4.3.5 / §5.4.
- Q: How are platform vocabulary defects vs client shape violations distinguished? → A: Load rejects unknown declared keys; runtime maps `validateKey` failures to `internal_error` and field/shape violations to `context_invalid`; `unknown_shape` still passes.
- Q: Recorded A5 shapes gap / unwired stages? → A: Required keys often lack published shapes so `shapes` may be `{}`; stages 6–7 remain unwired in `worker.ts` per contract §10.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Context validator stage and cost pre-flight (Priority: P1)

As the AI Gateway Worker, after the guard has authenticated the caller, resolved the capability manifest, and established an immutable request principal (B3, C1), I validate the client-supplied context payload against the resolved manifest's Context Contract — required keys present, shapes conforming, sizes within bounds, org/branch consistent with the token claims, undeclared keys dropped — and I run the cost pre-flight that rejects any request whose estimated input plus the capability's maximum output tokens exceed the manifest's per-request cost ceiling, before any egress to a provider. A request that fails either stage is rejected with a typed taxonomy code and never reaches the composer or a provider.

**Why this priority**: C2 sits where it does because its `Needs` (A5, C1) are the point at which the manifest and the context-key vocabulary are frozen and resolvable. The guard's "cheapest and most certain rejection first" ordering (§6.1) places context validation and the cost pre-flight at stages 6 and 7 — the last CPU-only checks before the one paid I/O of admission (stage 8) and all the latency of invocation (stage 11). C2 is what makes stages 6 and 7 real, and downstream slices D1 (composer) and B4/D3 (admission, invocation) consume its frozen outputs.

**Independent Test**: Provable by a unit (spy) suite, with no provider, no D1 I/O, and no network: drive the validator and the pre-flight with a resolved manifest fixture and a supplied context payload, and assert, per case, the emitted taxonomy code, the contents of the `context_required` payload, the absence of undeclared keys from the composer input, and that no egress occurs on a pre-flight rejection (§3.11.3, row C2; §3.10).

**Acceptance Scenarios**:

1. **Given** a resolved `single_shot` capability manifest and a complete, well-shaped, tenant-consistent context payload, **When** the context validator runs, **Then** validation passes and the filtered payload (declared keys only) is handed forward to the composer. *(happy path)*
2. **Given** a manifest declaring required keys `patient.demographics@v1` and `visit.vitals@v1`, **When** the supplied context omits `visit.vitals@v1`, **Then** the stage rejects with `context_required` (422) whose payload lists exactly the missing key `visit.vitals@v1`, its declared shape, and the manifest version. *(missing required key — one case per declared required key)*
3. **Given** a supplied context whose `visit.vitals@v1` value violates the key's declared shape (a wrong field type, wrong cardinality, wrong unit, or a missing required field), **When** the validator runs, **Then** the stage rejects with `context_invalid` (422). *(one case per shape-violation kind)*
4. **Given** a supplied context whose `visit.vitals@v1` payload exceeds the manifest's declared per-key max size for that key, **When** the validator runs, **Then** the stage rejects with `context_invalid` (422). *(oversize key)*
5. **Given** a supplied context that includes a key not declared by the manifest, **When** the validator runs, **Then** the undeclared key is dropped and is provably absent from the payload handed to the composer. *(undeclared key dropped, not forwarded — spy)*
6. **Given** a verified token whose `org`/`branch` claims do not match the org/branch in the supplied context, **When** the validator runs, **Then** the stage rejects with `context_invalid` (422). *(branch consistency — org mismatch and branch mismatch are separate cases)*
7. **Given** a manifest that declares an optional key, **When** the supplied context omits that optional key, **Then** validation passes. *(absent optional key)*
8. **Given** a manifest whose Economics declare a per-request cost ceiling, **When** (estimated input tokens + the manifest's max output tokens) is at or below that ceiling, **Then** the pre-flight passes. *(under ceiling)*
9. **Given** the same manifest, **When** (estimated input tokens + the manifest's max output tokens) exceeds the per-request cost ceiling, **Then** the pre-flight rejects with `request_too_large` (413). *(over ceiling)*
10. **Given** a request that the pre-flight rejects, **When** the pre-flight rejects it, **Then** no egress to a provider occurs (spy on the provider/composer entry: zero calls). *(no egress on pre-flight rejection)*

### Test plan

Layer for every named case is **Unit (spy)** per delivery plan §3.11.3 (row C2), exercising the validator and pre-flight in isolation with a manifest fixture and a supplied payload; the "spy" assertion style (asserting on the number or absence of calls) follows the coverage rule in §3.10 and corresponds to the **Pipeline tests** layer of the architecture's testing strategy (§13.5: "Stage ordering, guard rejection paths").

| # | Named test | Asserts |
| --- | --- | --- |
| T1 | `validator_accepts_complete_valid_context` | happy path passes; filtered payload handed forward (§4.3.5) |
| T2 (one per required key) | `validator_rejects_each_missing_required_key` | each missing required key → `context_required` payload listing exactly that key + its shape + manifest version (§4.3.5, §8.4) |
| T3 | `validator_rejects_multiple_missing_required_keys` | with several required keys missing, the payload lists exactly the full set of missing keys (§8.4) |
| T4 (one per kind) | `validator_rejects_each_shape_violation` | wrong type / wrong cardinality / wrong unit / missing required field → `context_invalid` (§5.2 Shape, §6.1 stage 6) |
| T5 | `validator_rejects_oversize_key` | payload exceeds the key's declared max size → `context_invalid` (§5.1 Context requirements, §6.1 stage 6) |
| T6 | `validator_drops_undeclared_key_spy` | an undeclared key is absent from the composer input (§4.3.5, §5.2 Minimization) |
| T7 | `validator_rejects_org_mismatch` | token `org` ≠ context org → `context_invalid` (§5.2 Authorization, §5.6, §6.1 stage 6) |
| T8 | `validator_rejects_branch_mismatch` | token `branch` ≠ context branch → `context_invalid` (§5.2 Authorization, §5.6, §6.1 stage 6) |
| T9 | `validator_passes_absent_optional_key` | an omitted optional key passes (§5.1 required/optional) |
| T10 | `preflight_passes_under_ceiling` | estimate + max output ≤ ceiling → passes (§4.3.3, §6.1 stage 7) |
| T11 | `preflight_rejects_over_ceiling` | estimate + max output > ceiling → `request_too_large` (§4.3.3, §6.1 stage 7) |
| T12 | `preflight_estimate_includes_max_output_tokens` | the estimate under test includes the manifest's declared max output tokens, not input alone (§5.1 Economics, §3.11.3) |
| T13 | `preflight_no_egress_on_rejection_spy` | a rejection results in zero composer/provider calls (§4.3.3 "before any egress", §3.10) |
| T14 | `preflight_estimator_is_deterministic_bytes` | the estimate equals `ceil(utf8Bytes/4)*1.15` for a fixed payload, is multi-byte-safe, and is recomputed identically across calls (§13.6.2) |
| T15 | `preflight_rejects_over_max_input_tokens` | estimate alone > `maxInputTokens` → `request_too_large` (§5.1 Economics, §6.1 stage 7) |

Coverage of every error code the slice can emit (§3.10 item 2): `context_required` (T2/T3), `context_invalid` (T4/T5/T7/T8), `request_too_large` (T11). Stages 6 and 7 emit no other codes (§6.1).

### Edge Cases

- **Error codes this slice can emit** (closed set, §5.4): `context_required`, `context_invalid`, `request_too_large`, plus H2's `conversation_budget_exhausted` on the conversational path and `internal_error` for platform vocabulary / malformed-manifest defects at runtime.
- **Multiple required keys missing at once**: the `context_required` payload must name the entire set of missing required keys (and each one's shape), not just the first encountered (§8.4 "missing keys + shapes").
- **Undeclared key that happens to match a declared key's name with a different version**: a key is identified by its full `domain.concept@vN` name; a same-concept different-version key is undeclared and is dropped (§5.2 Key format, Evolution). When the declared version is required and absent, the outcome is `context_required` listing that required key.
- **Branch consistency vs. shape**: an org/branch mismatch — including absent `org`/`branch` — is a tenant-consistency failure, not a shape failure, but it shares the stage's non-`context_required` code `context_invalid` by elimination from §6.1 stage 6's failure column; it is NOT reported as `forbidden_capability` (that is the entitlement stage's code, stage 3) and NOT as `request_too_large`.
- **Per-key max size vs. per-request cost ceiling**: an oversize *key* (exceeds the key's declared max size) is rejected at stage 6 as `context_invalid`; a request whose total estimated cost exceeds the *per-request* ceiling is rejected at stage 7 as `request_too_large`. Both are CPU-only and both must occur before egress, and stage 6 precedes stage 7 (§6.1). Exact equality on size and token bounds **passes** (`>` rejects).
- **Estimate is approximate**: the pre-flight uses an *estimated* input-token count plus the manifest's declared max output tokens; the estimate is a named control ("pre-flight estimation", §13.6) and is not a billed quantity. A request that passes the estimate but would exceed the ceiling at the provider is not rescued here — exact accounting is post-response (§4.3.3, §6.1 stage 15).
- **No per-request server-side state**: validation and pre-flight hold no state between requests; nothing about a rejected request is journaled (a guard rejection produces no journal row, §6.2; journalling is stage 9, C3).
- **A5 published-shapes gap**: until A5 publishes shapes for required keys, `context_required.shapes` is often empty even when missing keys are correctly listed — an A5 vocabulary gap, not a C2 wiring defect.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The context validator MUST enforce that every manifest-declared **required** context key is present in the supplied payload, and a missing required key MUST produce `context_required` carrying the missing-key manifest (the missing keys, each with its declared shape, and the manifest version), enabling the self-healing handshake in §8.4. (§4.3.5, §8.4)
- **FR-002**: The context validator MUST enforce that each supplied key conforms to its platform-published shape — field names, types, cardinality, and units — and that each supplied key is within its declared per-key max size; a violation MUST produce `context_invalid`. (§4.3.5, §5.2 Shape, §5.1 Context requirements)
- **FR-003**: The context validator MUST drop any key the manifest does not declare, rather than forward it; a prompt must never be able to receive data the capability did not declare, or the minimization property in §2.8 evaporates. (§4.3.5, §5.2 Minimization)
- **FR-004**: The context validator MUST verify that the supplied context is branch-consistent with the token's `org` and `branch` claims; an `org` or `branch` mismatch MUST be rejected with `context_invalid` (the context-validate stage's failure code that is not `context_required`, per the closed failure-code set of §6.1 stage 6). (§5.2 Authorization, §5.6, §6.1 stage 6)
- **FR-005**: An absent **optional** key (declared `optional` in the manifest's Context requirements) MUST pass validation. (§5.1 Context requirements)
- **FR-006**: The context-validate stage (stage 6) for `single_shot` MUST emit `context_required`, `context_invalid`, or `internal_error` (platform vocabulary / malformed-entry defects); the conversational path (H2 extension) MAY also emit `conversation_budget_exhausted`. The cost pre-flight stage (stage 7) MUST emit only `request_too_large`. Both stages are CPU-only and perform no I/O. (§6.1 stages 6–7, §5.4, §4.3.5 conversational)
- **FR-007**: The cost pre-flight MUST compute `estimatedInputTokens = ceil((utf8ByteLength(serialized request input) + promptArtifactByteLength) / 4) * 1.15` over the filtered context plus the caller's intent (and conversational transcript when supplied by the caller) **including** prompt-artifact bytes at their known length (§13.6.2), and MUST reject with `request_too_large` when `estimatedInputTokens + maxOutputTokens > perRequestCostCeiling` or when `estimatedInputTokens > maxInputTokens`, before any egress to a provider. The comparison is in tokens; C2 MUST NOT apply any token→cost conversion and MUST NOT hold any provider price. Non-finite Economics MUST fail closed as `request_too_large`. (§4.3.3, §6.1 stage 7, §5.1 Economics, §13.6.2)
- **FR-008**: When the pre-flight rejects a request, no egress occurs — the provider and composer entry must not be called. (§4.3.3 "Rejecting an oversized request before egress", §6.1 stage 7 precedes stage 11)
- **FR-009**: A guard rejection from stages 6 or 7 MUST NOT be journaled as a request; journalling occurs at stage 9 (C3), only after the guard passes. (§6.2, §6.1 stage 9)
- **FR-010**: A4 `load()` MUST type-check Economics fields as finite numbers and single-shot Context-requirements entries (`required` boolean, `maxSize` finite number, `key` in the A5 published vocabulary). `filteredContext` and the `context_required` wire body MUST be frozen copies.

### Key Entities *(include if feature involves data)*

Not applicable — this slice defines no D1 entities and no contract types. It consumes the manifest's Context-requirements and Economics field groups (§5.1) and the token's `org`/`branch` claims (§5.6), and produces a filtered context payload and a pre-flight decision, both in-memory and per-request.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Validation and the pre-flight are the cheapest possible rejections — CPU-only, no I/O, before any paid provider call (§6.1, §4.3.3). This is the guard's contribution to keeping an abusive or oversized request nearly free to reject, which is what makes the platform affordable at clinic volumes (tens of requests per day per clinic, §13.6.1). No enterprise-scale assumption is introduced.
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. C2 performs no Supabase or D1 access of any kind; stages 6–7 are CPU-only (§6.1).
- **Data Integrity & Security**: The validator enforces the Context Contract's minimization property (only declared keys forwarded, §4.3.5, §5.2) and a tenant-consistency check (org/branch match the token claims, §5.2 Authorization). It adds no stored data and introduces no audit fields; a guard rejection produces no journal row (§6.2). The frozen `context_required` payload carries no clinical data beyond the missing-key manifest (key names + shapes + manifest version).
- **Failure Handling**: This slice's "failure" is rejection of a malformed or oversized request, which is the intended behaviour, not a degradation. The slice holds no per-request state and performs no I/O that can fail; there is no retry, cache, or fallback to specify here. Quota exhaustion and provider unreachability are handled by later stages (B4, D3) and are out of scope.

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **C1 (capability resolver, discovery)**: C2 consumes the resolved, immutable manifest; it does not resolve capability ids, honour version pins, or serve discovery. (§4.3.4)
- **D1 (prompt composer)**: C2 produces the filtered context payload the composer consumes; it does not compose a prompt, render context as delimited typed data, or derive the output-format instruction. (§4.3.6)
- **B4 (admission)**: C2's pre-flight is a *local* cost-ceiling check against the manifest; it is not the per-installation Quota Durable Object budget/concurrency/replay/idempotency admission (stage 8). (§4.3.3, §6.1 stage 8)
- **D3 (invocation) / provider egress**: C2 precedes egress and makes no provider call. (§6.1 stage 11)
- **C3 (journal writer)**: C2 writes nothing; a guard rejection produces no journal row. (§6.2, §6.1 stage 9)
- **J2 (`context_required` self-healing behaviour)**: C2 emits the `context_required` rejection *payload*; the client-side refresh-and-resubmit-once *behaviour* is deferred to J2 under DP-5. (§8.4)
- **H2 (conversational transcript validation — original C2 exclusion)**: Conversational behaviour was later merged into `validator.ts` by H2 and is now documented on the C2 contract as an extension. C2's original `single_shot` scope remains the primary freeze; conversational codes and the fourth parameter are H2 extensions recorded for consumer accuracy. (§4.3.5 conversational paragraph, §6.7)
- **Worker pipeline wiring of stages 6–7**: Consumption in `worker.ts` is deferred to D1/B4/D3 (contract §10).

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20). C2 adds no health-check, no caching, no retry, no abstraction beyond the named stages.
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — not applicable to this Worker slice, but nothing it does pulls any such string into the client.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — C2 performs no DO and no R2 I/O.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — C2 writes no D1 rows at all.
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

C2 uses no tokenizer and no provider price table: the estimator is the byte-based formula fixed by §13.6.2, and the ceiling is token-denominated (§5.1), so the slice invents no threshold, timeout, or limit beyond the manifest values and the two §13.6.2 platform constants. Pricing actual usage in currency is the post-response `usage_event` ledger's job, not C2's.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every required-key-missing, shape-violation, oversize-key, and org/branch-mismatch case is provably rejected by an automated unit test, and a complete valid context is provably accepted — the full `Done when` validator clause, each branch a named test.
- **SC-002**: For every declared required key, a test proves a missing instance emits `context_required` whose payload lists exactly the missing key(s), each key's declared shape, and the manifest version.
- **SC-003**: A spy test proves an undeclared key is absent from the composer input — the minimization property is enforced, not merely asserted.
- **SC-004**: A test proves (estimated input tokens + `maxOutputTokens`) exceeding the token-denominated `perRequestCostCeiling` emits `request_too_large` with zero composer/provider calls — no egress on rejection — and a second test proves the estimator is the deterministic byte formula of §13.6.2 with no currency in the comparison.
- **SC-005**: The slice emits exactly the three taxonomy codes `context_required`, `context_invalid`, and `request_too_large`, and no others; one passing test exercises each code, satisfying the §3.10 item-2 coverage rule.

## Assumptions

- The capability manifest's Context-requirements field group (required/optional keys, shape references, per-key max size) and Economics field group (max output tokens, per-request cost ceiling) are frozen by A4/A5 and resolvable by C1 before C2 runs; C2 reads a fully-resolved, immutable manifest object.
- The verified token's `org` and `branch` claims are present and immutable to later stages, established by B3 (§4.3.2, §5.6); C2 reads them but does not verify the token.
- The context-key vocabulary and per-key published shapes are frozen by A5 (§5.2); C2 validates against them and does not add, rename, or version any key.
- The error taxonomy is frozen by A2 (§5.4); C2 consumes it and adds no code.
- Validation and pre-flight are CPU-only (§6.1 stages 6–7); the slice introduces no D1, DO, R2, or provider I/O, and no per-request server-side state.