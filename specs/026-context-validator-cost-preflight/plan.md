# Implementation Plan: Context validator stage and cost pre-flight (C2)

**Branch**: `ai/026-c2-context-validator-cost-preflight` | **Date**: 2026-08-01 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/026-context-validator-cost-preflight/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. The AI platform variant adds four sections (`## Consumes Binding`, `## Components Touched`, `## Files`, `## Test Layout`, `## Sequencing`) for the delivery plan's contract model, and never produces `research.md`.

## Summary

C2 makes the guard's stage-6 context validator and stage-7 cost pre-flight real: it takes a resolved, immutable capability manifest and a client-supplied context payload, drops every key the manifest did not declare, enforces each remaining key's published shape and per-key max size, cross-checks the supplied org/branch against the verified token claims, and rejects with a typed `context_required` / `context_invalid` payload before a cost pre-flight estimates the request's input tokens (the §13.6.2 byte formula) and rejects with `request_too_large` when the estimate plus `maxOutputTokens` exceeds the token-denominated `perRequestCostCeiling`, or the estimate alone exceeds `maxInputTokens`, before any egress. The slice sits in band C, after A5+ C1 froze the manifest and the context-key vocabulary and before D1 (composer) and B4/D3 (admission, invocation) consume its frozen outputs (delivery plan §3.4, row C2).

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime); `@cloudflare/workers-types` ^4.20250730.0; vitest ~3.2.4 with `@cloudflare/vitest-pool-workers` 0.8.71.

**Primary Dependencies**: `ai-platform/src/manifest` (A4 — `Manifest`, `ContextRequirementEntry`, `EconomicsGroup`), `ai-platform/src/context` (A5 — `KeyShape`, `validateKey`, `validatePayload`, `PUBLISHED_KEY_SHAPES`), `ai-platform/src/capability` (C1 — `ResolveResult`), `ai-platform/src/identity` (B3 — `Principal`), `ai-platform/src/errors` (A2 — `TaxonomyCode`, `buildErrorBody`, `ErrorBody`, `liveHttpStatusForCode`). No new dependency is introduced.

**Storage**: N/A — stages 6–7 are CPU-only (§6.1); C2 performs no D1, Durable Object, R2, or provider I/O and holds no per-request server-side state (§4.4, §9.7).

**Testing**: vitest unit (spy) tests in `ai-platform/test/context-validator.test.ts`, exercising the validator and pre-flight in isolation with a manifest fixture and a supplied payload; spy assertions verify call counts/absences per §3.10. No `vitest.workers.config.ts` cases are needed (C2 does no D1 I/O) — all 15 named tests run under `vitest.config.ts`.

**Target Platform**: Cloudflare Workers (the `ai-platform/` gateway); no Flutter, no Supabase, no live endpoint exposed by this slice (`worker.ts` unchanged, mirroring B3/C1).

**Project Type**: Additive, non-primary Worker module — one §4 component (§4.3.5) plus the §4.3.3 cost-ceiling check. Per the §14 acknowledgement: no domain logic, no business data, no write path into Supabase, always optional.

**Performance Goals**: CPU-only, microseconds — the cheapest rejections in the guard (§6.1 stages 6–7; §4.3.3 "Rejecting an oversized request before egress is the cheapest possible protection"). No I/O budget is consumed.

**Constraints**: Stages 6–7 emit only `context_required` / `context_invalid` / `request_too_large` (§6.1, §5.4 — closed set). The estimator is the fixed `ceil(utf8Bytes/4)*1.15` (§13.6.2) — no tokenizer, no provider price. `perRequestCostCeiling` is token-denominated (§5.1, A6). No per-request state (§4.4, §9.7). No guard rejection journaled (§6.2). No mechanism from §9.14 (R-20).

**Scale/Scope**: Clinic-scale (tens of requests/day/clinic, §13.6.1); the pre-flight protects against a single expensive request (§4.3.3). No enterprise scale assumption.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — the guard is the cheapest-rejection-first layer that keeps an abusive or oversized request nearly free to reject, which is what makes the platform affordable at clinic volumes (§6.1, §13.6.1). No enterprise scale assumption is introduced.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — C2 adds two pure CPU functions to one Worker; no new deployable, no queue, no store, no abstraction beyond the two named stages (R-20).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — C2 touches only `ai-platform/` (the Worker); no `frontend/`, no `backend/`, no Supabase access. The gateway is the §14-acknowledged additive, non-primary component with no domain logic, no business data, and no write path into Supabase.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — C2 performs no writes of any kind. The tenant-consistency check (org/branch match the token claims) is a read-only guard rejection, not a Supabase-side enforcement; it relies on B3's already-verified claims (§5.2 Authorization, §5.6).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — C2 consumes the immutable `Principal` (B3) and reads its `organizationId` / `branchId` for the tenant cross-check; it performs no authentication, holds no secrets, and writes no audit row. A guard rejection produces no journal row (§6.2); auditability of an admitted request is C3's.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — C2 is a rejection gate; it never reaches a provider, never produces AI content, and has no degraded mode of its own. When the guard rejects, AI is unreachable by design; clinic work continues without the AI affordance (§14 "V"; A11). The `context_required` payload enables the §8.4 self-healing handshake so a stale client recovers rather than failing hard.

The Supabase/PostgreSQL row is structurally inapplicable to a CPU-only guard slice — recorded here rather than silently dropped, per the §14 acknowledgement. No Constitution Check violation requires Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/026-context-validator-cost-preflight/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify output (authoritative)
├── contracts/
│   └── context-validator.md  # Frozen: stage-6 ValidateResult + filtered payload + context_required wire payload + stage-7 PreflightResult + the §13.6.2 estimator
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — C2 defines no D1 entity (spec `### Key Entities`: "Not applicable"). Stages 6–7 are CPU-only (§6.1) and introduce no stored data.

`research.md` is **never** produced on this platform — the research is `docs/architecture/17-ai-platform.md`; redoing it is how architecture drift starts.

`contracts/` is produced because the spec's **Freezes** entries have wire shapes later slices' **Consumes** bind to (D1 consumes the filtered context payload; J2 consumes the `context_required` missing-key manifest; B4/D3 consume the pre-flight decision). The plan names the artifact; the implement phase writes it.

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — C2 row of the delivery plan (§3.4) and the §4.3.5 / §5.2 / §4.3.3 / §6.1-stages-6-7 / §13.6.2 sections; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — the `src/context/validator.ts` stage-6 validator + `context_required` wire builder; the `src/context/preflight.ts` stage-7 byte estimator + two-predicate pre-flight.
- **§3 Files to review** — this slice's `ai-platform/src/context/validator.ts`, `ai-platform/src/context/preflight.ts`, `ai-platform/test/context-validator.test.ts`, and `contracts/context-validator.md`.
- **§4 Prerequisites** — omitted (no wrangler/D1 needed; all tests are unit under `vitest.config.ts`).
- **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/context-validator.test.ts`, slice-only.
- **§6 Inspect the changes** — grep for the three taxonomy codes, read the frozen `contracts/context-validator.md`, run a focused test file.
- No §7 — CI is the only verification path (C2 exposes no user-facing behaviour beyond the suite; `worker.ts` is not modified).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── context/
│   │   ├── index.ts           # UNCHANGED (consumed from A5 — KeyShape, validateKey, validatePayload, PUBLISHED_KEY_SHAPES)
│   │   ├── validator.ts       # NEW (this slice — FR-001..FR-006, FR-009): stage-6 validateContext() + buildContextRequiredResponse()
│   │   └── preflight.ts       # NEW (this slice — FR-007, FR-008): estimateInputTokens() + runCostPreflight()
│   ├── manifest/              # UNCHANGED (consumed from A4 — Manifest, ContextRequirementEntry, EconomicsGroup)
│   ├── capability/            # UNCHANGED (consumed from C1 — ResolveResult)
│   ├── identity/              # UNCHANGED (consumed from B3 — Principal)
│   ├── errors.ts              # UNCHANGED (consumed from A2 — buildErrorBody, TaxonomyCode, liveHttpStatusForCode)
│   └── worker.ts              # UNCHANGED — no route wired by this slice (see Components Touched)
├── test/
│   └── context-validator.test.ts  # NEW — T-C2-* unit (spy) tests (inline fixture manifests + supplies)
└── vitest.config.ts           # UNCHANGED — test/**/*.test.ts include already covers the new file; no exclude change needed (no workers-config case)
```

`worker.ts` is unchanged because C2 freezes the validator and pre-flight contracts in code but does not wire them into the request pipeline — matching B3's and C1's precedent (the guard functions exist; their pipeline wiring is a later orchestrator slice). C2's tests exercise `validateContext()` and `runCostPreflight()` directly via their exported functions, mirroring how B3 tested `evaluateEntitlement` and C1 tested `resolve()` without a Worker fetch. The pipeline-stage attachment belongs to the same later orchestrator slice that wires the guard stages. This keeps C2 to one §4 component (§4.3.5) plus the §4.3.3 cost-ceiling check, and avoids reworking §4.3.1 (the adapter owns the submit stream).

**Structure Decision**: Two new files under the existing `ai-platform/src/context/` directory — `validator.ts` (stage 6 + the `context_required` wire builder it alone emits) and `preflight.ts` (stage 7 + the §13.6.2 byte estimator). A5's `index.ts` holds the key vocabulary and `validatePayload()`; C2 imports from it rather than reworking it (delivery plan §2.3). The `context/` directory already exists from A5; extending it follows the one-dir-per-§4.3.x convention while keeping the two stages in separate files because they are independently testable and have distinct frozen contracts. Inline manifest fixtures in the test file reuse C1's `validManifest()` factory shape (from `test/capability.test.ts`) — no separate fixture directory, no shipped capability (Open Decision 1 is blocked to D1, delivery plan §7), no live binding.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How C2 binds to it |
| --- | --- | --- |
| **A5** — context-key vocabulary (`domain.concept@vN`), published per-key shapes, per-key max-size bound, config-cache surface (§5.2) | `ai-platform/src/context/index.ts` — `KeyShape`, `KeyShapeField`, `FieldCardinality`, `validateKey(key)`, `validatePayload(key, payload)`, `PUBLISHED_KEY_SHAPES`, `VISIT_CHIEF_COMPLAINT_V1_SHAPE`. Frozen artifact: `specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`. | C2's `validator.ts` imports `KeyShape`, `validatePayload`, and `PUBLISHED_KEY_SHAPES`. The stage-6 validator calls `validatePayload(key, value)` for each supplied key to enforce shape conformance (field names, types, cardinality, units — FR-002), and reads the manifest's per-key `maxSize` for the oversize check (FR-002). C2 does not rework A5's `validateKey()` or `validatePayload()`; it builds the stage-6 orchestration on top of them. The config cache is consumed only indirectly (C2 reads the resolved manifest's `Context requirements` from C1's `ResolveResult`, not the cache itself). |
| **A2** — error taxonomy as a closed set (§5.4); `buildErrorBody` for the four common fields | `ai-platform/src/errors.ts` — `TaxonomyCode` (includes `"context_required"`, `"context_invalid"`, `"request_too_large"`), `buildErrorBody(input: ErrorBodyInput): ErrorBody` with `ErrorBody = {code, request_reference, trace_id, retry_safe}`, `liveHttpStatusForCode(code)`. Frozen artifact: `specs/016-ai-diagnostic-envelope/contracts/` (no contract file; the spec's Clarification Q1 froze the body shape `{code, request_reference, trace_id, retry_safe}`). | C2's `validator.ts` emits the three taxonomy codes (`context_required`, `context_invalid` — FR-006); C2's `preflight.ts` emits `request_too_large` (FR-007). The `context_required` wire builder (Clarification Q1) calls `buildErrorBody({code:"context_required", requestReference, traceId})` for the four common fields, then attaches the frozen snake_case missing-key manifest (`missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id`). C2 adds no code to the taxonomy and changes no HTTP status; `liveHttpStatusForCode` stays A6's. A2's `errors.ts` is read, not modified. |
| **A3** — canonical inference representation (§5.3) | `ai-platform/src/contracts/canonical.ts` — `CanonicalRequest` type. Frozen artifact: `specs/017-ai-canonical-inference/contracts/canonical-shapes.md`. | C2 does not construct a `CanonicalRequest` (that is D1's stage-10 job); C2 produces the **filtered context payload** that D1's composer will later render into the canonical request. C2 imports the `CanonicalRequest` type only if the filtered-payload return type references it — otherwise it defines a local `FilteredContext` type. Test T6 (spy) verifies the filtered payload contains only declared keys; the composer is not called. |
| **A4 / C1** — immutable capability manifest, `Context requirements` field group, `Economics` field group (§5.1) | `ai-platform/src/manifest/index.ts` — `Manifest` type, `ContextRequirementEntry` (keys: `key`, `required`, `shapeRef`, `maxSize`, `freshnessHint`), `EconomicsGroup` (keys: `maxInputTokens`, `maxOutputTokens`, `perRequestCostCeiling`, `quotaWeight`). `ai-platform/src/capability/index.ts` — `ResolveResult = {ok:true, manifest:Manifest} | {ok:false, code}`. Frozen artifacts: `specs/018-ai-capability-manifest/contracts/manifest-schema.md` (A4), `specs/025-capability-resolver-discovery/contracts/capability-registry.md` (C1). | C2 receives the resolved `Manifest` from C1's `ResolveResult` (the `{ok:true, manifest}` branch) and reads its `"Context requirements"` array (FR-001, FR-002, FR-003, FR-005) and `Economics` group (FR-007). C2 treats the manifest as read-only for the lifetime of the request (C1's immutability guarantee); it does not mutate any field group. C1's `resolve()` is not called by C2 (the orchestrator calls it first and passes the manifest); C2's tests build a manifest fixture using A4's `load()` and the C1 `validManifest()` factory shape, then pass it directly to `validateContext()`. |
| **A6** — protocol adapter headers, request principal established upstream (§4.3.1) | `ai-platform/src/adapter.ts` — `AdapterStreamContext` (carries `requestReference`, `traceId`). `ai-platform/src/errors.ts` — `liveHttpStatusForCode`. Frozen artifact: `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md` (names C2 as the owner of "`request_too_large` at stage 7" and the per-capability/per-key size bounds). | C2 receives the `requestReference` and `traceId` (from A6's parsed headers / A2's generators) as arguments to the `context_required` wire builder, so the rejection body carries them (§5.4 "Every error response carries the request reference, the trace id, and whether a retry is safe"). C2 does not parse headers; it consumes the already-parsed values. A6's adapter is not modified — the ingress-too-large gate (stage 1) and SSE framing remain A6's; only the `context_required` body is built by C2 (Clarification Q1). |
| **B3** — verified token claims `org` / `branch`, immutable to later stages (§4.3.2, §5.6) | `ai-platform/src/identity/index.ts` — `Principal` interface (`organizationId`, `branchId` fields). Frozen artifact: `specs/023-guard-stages/contracts/request-principal.md` (§5 names C2 as the consumer of `organizationId`, `branchId`). | C2's `validateContext(manifest, suppliedContext, principal)` reads `principal.organizationId` and `principal.branchId` for the tenant cross-check (FR-004). C2 never mutates the principal and adds no field to it (the no-rework rule). The principal is a read-only argument. |

No consumed entry lacks an implementation. None is modified (delivery plan §2.3). A5's `src/context/index.ts` is imported from, not rewritten; A2's `errors.ts` is called, not modified; A6's `adapter.ts` is untouched (Clarification Q1 explicitly leaves it frozen).

## Components Touched

| §4 component | What C2 changes | Behaviour added? |
| --- | --- | --- |
| §4.3.5 Context validator | **Created** — the stage-6 `validateContext()` function and the `context_required` missing-key-manifest wire builder. Validates the client-supplied context payload against the resolved manifest's `Context requirements`: required keys present (else `context_required` carrying the missing-key manifest), shapes conform and per-key max size respected (else `context_invalid`), undeclared keys dropped, org/branch consistent with the token claims (else `context_invalid`), absent optional keys pass. The filtered, declaration-conformant payload is the output D1's composer consumes. | Yes — this is C2's primary component. The §4.3.5 conversational paragraph (permitted-key set, transcript budget) is explicitly out of scope (H2, spec `## Out of Scope`); C2 implements the `single_shot` validation only. |
| §4.3.3 Entitlement, quota, and rate control — the cost-ceiling check | **Extended** — the stage-7 cost pre-flight is the §4.3.3 "Cost ceiling" mechanism ("a local pre-flight check: estimated input tokens plus the capability's max output tokens against the capability's token budget"). C2 adds `estimateInputTokens()` (the §13.6.2 byte formula) and `runCostPreflight()` (the two predicates: `estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling` AND `estimatedInputTokens ≤ maxInputTokens`), emitting `request_too_large` on breach. | Yes — but this is the cost-ceiling mechanism §4.3.3 already names, not a new mechanism. The rate-limiting, quota-DO, and replay/idempotency mechanisms in §4.3.3 are untouched (B3/B4). Touching §4.3.3 is the reason recorded here: the spec's `Canonical` cell cites §4.3.3, and the cost pre-flight is its named "Cost ceiling" bullet. |

C2 touches two §4 components: §4.3.5 (primary — the validator) and §4.3.3 (the cost-ceiling check only). The reason is the spec's `Canonical` cell itself cites both (`§4.3.5, §5.2, §4.3.3, §6.1 stages 6–7`), and §4.3.3 names the cost pre-flight as one of its four mechanisms. C2 does not touch rate limiting, the Quota DO, replay/idempotency, admission (B4), or any other §4.3.3 mechanism — only the "Cost ceiling" bullet. This is within the one-component-group sizing guidance (delivery plan §2.5: "one component, or a small set of components that cannot be tested apart") because the validator and the pre-flight are the two stages the §3.4 row C2 `Done when` couples ("Required keys … enforced … and … estimated input tokens plus the capability's maximum output tokens are checked against its per-request ceiling before any egress").

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/context/validator.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-009 — `ValidateResult` discriminated union (`{ok:true, filteredContext} | {ok:false, code:"context_required", missingKeys, shapes, manifestVersion, manifestCapabilityId} | {ok:false, code:"context_invalid"}`); `validateContext(manifest, suppliedContext, principal): ValidateResult` (stage 6); `buildContextRequiredResponse(result, requestReference, traceId)` (the Clarification-Q1 wire builder, calling A2 `buildErrorBody` for the four common fields and attaching the frozen snake_case missing-key manifest `{missing_keys, shapes, manifest_version, manifest_capability_id}`). |
| `ai-platform/src/context/preflight.ts` | Created | FR-007, FR-008 — `TOKENS_PER_BYTE_DIVISOR = 4` and `ESTIMATE_SAFETY_FACTOR = 1.15` platform constants (§13.6.2); `estimateInputTokens(serializedInput: string): number` (`Math.ceil(utf8ByteLength / 4) * 1.15`); `runCostPreflight(manifest, serializedInput): PreflightResult` where `PreflightResult = {ok:true} | {ok:false, code:"request_too_large"}` — the two predicates `estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling` AND `estimatedInputTokens ≤ maxInputTokens` (§6.1 stage 7, §13.6.2). |
| `ai-platform/test/context-validator.test.ts` | Created | SC-001, SC-002, SC-003, SC-004, SC-005 — the 15 named tests from the spec's `### Test plan` (`T-C2-01` … `T-C2-15`), unit (spy), with spy assertions on composer/egress call counts for T6, T10, T13. |
| `specs/026-context-validator-cost-preflight/contracts/context-validator.md` | Created | (freezes the `ValidateResult` union + the filtered-context payload shape, the `context_required` wire payload `{code, request_reference, trace_id, retry_safe, missing_keys, shapes, manifest_version, manifest_capability_id}`, the `PreflightResult` union, and the §13.6.2 estimator with its two platform constants) from FR-001/FR-002/FR-003/FR-004/FR-005/FR-006/FR-007, so D1/J2/B4/D3 consume a contract, not prose. |
| `specs/026-context-validator-cost-preflight/quickstart.md` | Created | — written during the implement-phase Documentation task (sections named in Project Structure → Documentation). Not traced to an FR (template-mandated review surface). |

Every code/contract file traces to an `FR-###`. No file is created for an unstated requirement. `worker.ts` and the consumed modules (`context/index.ts`, `manifest/`, `capability/`, `identity/`, `errors.ts`, `adapter.ts`, `contracts/canonical.ts`) are unchanged.

## Test Layout

The spec's `### Test plan` names 15 tests at the §13.5 layer "Pipeline tests" (the §3.11.3 row C2 layer "Unit (spy)" realised as that §13.5 row: "Stage ordering, guard rejection paths"). All 15 run under `vitest.config.ts` — C2 does no D1, DO, R2, or provider I/O, so no `vitest.workers.config.ts` cases are needed (unlike C1, which needed the real D1 for kill-switch/entitlement reads). The test file is `ai-platform/test/context-validator.test.ts`. Spy assertions (T6, T10, T13) verify that a `nextStage()` sink (a `vi.fn()`) is called zero times on the rejection paths, per the §3.10 coverage rule.

| Spec Test plan name | Test id | §13.5 layer | Config | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `validator_accepts_complete_valid_context` | T-C2-01 | Pipeline tests | `vitest.config.ts` | FR-001, FR-002, FR-003, FR-006 / SC-001 — a complete, well-shaped, tenant-consistent supplied context passes; the returned `filteredContext` contains exactly the manifest-declared keys and is handed to a `nextStage` spy (called once). |
| `validator_rejects_each_missing_required_key` | T-C2-02 | Pipeline tests | `vitest.config.ts` | FR-001 / SC-002 — for a fixture manifest declaring two required keys (`patient.demographics@v1`, `visit.vitals@v1`), omitting each one in turn emits `context_required` whose payload lists exactly the missing key, its `KeyShape`, `manifest_version`, and `manifest_capability_id`. (Parameterised: one case per required key.) |
| `validator_rejects_multiple_missing_required_keys` | T-C2-03 | Pipeline tests | `vitest.config.ts` | FR-001 / SC-002 — with several required keys missing, the `context_required` payload lists the full set, not just the first. |
| `validator_rejects_each_shape_violation` | T-C2-04 | Pipeline tests | `vitest.config.ts` | FR-002 / SC-001 — for each shape-violation kind (wrong type, wrong cardinality, wrong unit, missing required field), the stage rejects with `context_invalid`. (Parameterised: one case per kind, A5's `validatePayload` returns the violation.) |
| `validator_rejects_oversize_key` | T-C2-05 | Pipeline tests | `vitest.config.ts` | FR-002 / SC-001 — a supplied key whose byte length exceeds the manifest's per-key `maxSize` rejects with `context_invalid`. |
| `validator_drops_undeclared_key_spy` | T-C2-06 | Pipeline tests | `vitest.config.ts` | FR-003 / SC-003 — a supplied key not in the manifest's `Context requirements` is absent from `filteredContext`; the undeclared key does not reach the `nextStage` spy's call argument. |
| `validator_rejects_org_mismatch` | T-C2-07 | Pipeline tests | `vitest.config.ts` | FR-004 / SC-001 — `principal.organizationId` ≠ the supplied context's org rejects with `context_invalid`. |
| `validator_rejects_branch_mismatch` | T-C2-08 | Pipeline tests | `vitest.config.ts` | FR-004 / SC-001 — `principal.branchId` ≠ the supplied context's branch rejects with `context_invalid`. |
| `validator_passes_absent_optional_key` | T-C2-09 | Pipeline tests | `vitest.config.ts` | FR-005 / SC-001 — a manifest-declared optional key omitted from the supplied context passes; the `filteredContext` omits it without rejection. |
| `preflight_passes_under_ceiling` | T-C2-10 | Pipeline tests | `vitest.config.ts` | FR-007 / SC-004 — `estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling` AND `estimatedInputTokens ≤ maxInputTokens` → `{ok:true}`. |
| `preflight_rejects_over_ceiling` | T-C2-11 | Pipeline tests | `vitest.config.ts` | FR-007 / SC-004 — `estimatedInputTokens + maxOutputTokens > perRequestCostCeiling` → `{ok:false, code:"request_too_large"}`. |
| `preflight_estimate_includes_max_output_tokens` | T-C2-12 | Pipeline tests | `vitest.config.ts` | FR-007 / SC-004 — the ceiling comparison under test uses `maxOutputTokens` from the manifest's `Economics`, not input alone; a fixture with `maxOutputTokens` set so that input-only would pass but input+output exceeds the ceiling rejects. |
| `preflight_no_egress_on_rejection_spy` | T-C2-13 | Pipeline tests | `vitest.config.ts` | FR-008 / SC-004 — a pre-flight rejection results in zero calls to the `nextStage` (composer/provider entry) spy. |
| `preflight_estimator_is_deterministic_bytes` | T-C2-14 | Pipeline tests | `vitest.config.ts` | FR-007 / SC-004 — `estimateInputTokens` equals `Math.ceil(utf8ByteLength(serializedInput) / 4) * 1.15` for a fixed ASCII payload, is multi-byte-safe (a 2-byte UTF-8 char counts as 2 bytes), and is recomputed identically across calls. |
| `preflight_rejects_over_max_input_tokens` | T-C2-15 | Pipeline tests | `vitest.config.ts` | FR-007 / SC-004 — `estimatedInputTokens > maxInputTokens` (with `+ maxOutputTokens ≤ perRequestCostCeiling` held) → `{ok:false, code:"request_too_large"}`. |

Coverage additions from §3.10: every error code the slice can emit is covered one-for-one — `context_required` (T-C2-02, T-C2-03), `context_invalid` (T-C2-04, T-C2-05, T-C2-07, T-C2-08), `request_too_large` (T-C2-11, T-C2-15). Every branch: the happy path (T-C2-01), each rejection branch, the absent-optional branch (T-C2-09), the undeclared-key-drop branch (T-C2-06). Every named boundary: per-key max size (T-C2-05), `perRequestCostCeiling` (T-C2-11), `maxInputTokens` (T-C2-15), the estimator's byte formula (T-C2-14). The no-egress-on-rejection prohibition (FR-008) is a spy assertion (T-C2-13). The no-journal-on-guard-rejection prohibition (FR-009) is consumed from C3's invariant and is not re-asserted (spec Edge Cases); C2 writes no D1 row, so there is nothing to spy on. Stages 6 and 7 emit no other codes (FR-006, §5.4 closed set — T-C2-01 through T-C2-15 exercise the union exhaustively).

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2; the test file plus the diff is the review artifact). Within this slice:

1. **Contract artifact** — `contracts/context-validator.md` is written first alongside the type definitions (it freezes the `ValidateResult` and `PreflightResult` unions, the `context_required` wire payload, and the estimator constants), so D1/J2/B4/D3 can bind during their own plan phase. The types are the contract; the functions follow.
2. **Stage 6 — validator happy path + filtered payload (FR-001, FR-002, FR-003, FR-005, FR-006)** — `T-C2-01`, `T-C2-09` first (the accept paths pin the `ValidateResult.ok` branch and the filtered-payload shape before any rejection is added), then `T-C2-06` (the undeclared-key-drop spy pins the minimization property, FR-003/SC-003). These exercise `validateContext()` against a fixture manifest built with A4's `load()` and the C1 `validManifest()` factory shape.
3. **Stage 6 — validator rejection paths (FR-001, FR-002, FR-004, FR-006)** — `T-C2-02`, `T-C2-03` (the `context_required` missing-key manifest, FR-001/SC-002), then `T-C2-04`, `T-C2-05` (the `context_invalid` shape/oversize paths, FR-002), then `T-C2-07`, `T-C2-08` (the org/branch mismatch paths, FR-004). The `buildContextRequiredResponse` wire builder is tested alongside T-C2-02/T-C2-03 — its missing-key manifest is the contract J2 consumes.
4. **Stage 7 — pre-flight estimator + predicates (FR-007, FR-008)** — `T-C2-14` first (the estimator is the §13.6.2 byte formula — pinning it before the predicates makes the boundary tests unambiguous), then `T-C2-10`, `T-C2-11`, `T-C2-12`, `T-C2-15` (the two predicates and their boundaries), then `T-C2-13` (the no-egress spy).
5. **Vitest config** — no edit needed: `test/context-validator.test.ts` is already covered by `vitest.config.ts`'s default `include: ["test/**/*.test.ts"]` and is not in the exclude list (only files that also run under `vitest.workers.config.ts` against real D1 are excluded from the unit config — C1's `capability.test.ts` is the precedent; C2 has no workers-config case).
6. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task, after the slice's tests pass.

Steps 2–4 interleave tests with implementation; no test is written after its implementation. The contract artifact (step 1) and the vitest config (step 5) are written alongside. The Documentation artifact (step 6) is written only after the suite is green — the plan names it here, the implement phase fills it in.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The one structurally-inapplicable Constitution box (Supabase/PostgreSQL protected writes) is recorded above as inapplicable to a CPU-only guard slice (per the §14 acknowledgement), not as a violation.