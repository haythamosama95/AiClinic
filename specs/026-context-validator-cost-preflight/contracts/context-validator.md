# Contract: Context validator stage and cost pre-flight (C2)

**Frozen by:** Slice C2 — Context validator stage and cost pre-flight
**Implements:** §4.3.5, §5.2, §4.3.3, §6.1 stages 6–7, §13.6.2 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (D1, J2, B4, D3) **consume** this artifact; they extend, never rewrite
the `ValidateResult` union, the `context_required` wire payload shape, the `PreflightResult` union,
the §13.6.2 estimator formula, or the stage-7 rejection predicates.

**Source of truth in code:** `ai-platform/src/context/validator.ts` (`ValidateResult`,
`validateContext`, `buildContextRequiredResponse`, conversational exports); `ai-platform/src/context/preflight.ts`
(`PreflightResult`, `TOKENS_PER_BYTE_DIVISOR`, `ESTIMATE_SAFETY_FACTOR`, `estimateInputTokens`,
`runCostPreflight`); A5 `publishedShapeForKey` from `ai-platform/src/context/index.ts`.

**Traces to:** FR-001–FR-009; spec **Freezes** entries; A5 context-key shapes
(`specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`); C1 resolved manifest
(`specs/025-capability-resolver-discovery/contracts/capability-registry.md`); B3 request principal
(`specs/023-guard-stages/contracts/request-principal.md`); A2 error taxonomy (`ai-platform/src/errors.ts`).

**Review extension (C2-R):** H2 merged conversational validation into `validator.ts` (architecture
§4.3.5 / §5.4); fail-closed Economics / Context-requirements typing at A4 load; platform vs client
fault split for declared-key vocabulary defects; prompt-artifact bytes in the §13.6.2 estimator;
frozen output payloads. Stages 6–7 remain unwired in `worker.ts` (consumption deferred to D1/B4/D3
per §10).

---

## 1. Overview

C2 owns the guard's **stage-6 context validator** and **stage-7 cost pre-flight**. After B3 has
established an immutable request principal and C1 has returned a resolved, frozen capability
manifest, `validateContext()` enforces the manifest's Context Contract — required keys present,
shapes conforming, per-key sizes within bounds, org/branch consistent with token claims, undeclared
keys dropped — and `runCostPreflight()` estimates input tokens with the §13.6.2 byte formula and
rejects oversized requests before any egress.

Both stages are CPU-only and perform no I/O. They emit taxonomy codes only; HTTP status mapping is
owned by A2/A6 and is not modified by C2.

H2 extends the same module for `interaction_mode: conversational` (transcript shape, budgets,
permitted-key allowlist). That extension is recorded here so D1/J2/B4 switch on the full
`ValidateResult` union.

---

## 2. ValidateResult

`validateContext(manifest, suppliedContext, principal, conversational?)` returns a discriminated union:

| Branch | Shape | Meaning |
| --- | --- | --- |
| Success | `{ ok: true, filteredContext: Record<string, unknown>, validatedTranscript?: Transcript }` | All checks passed; only manifest-declared (or permitted) keys that were supplied are retained. `filteredContext` is a deep-frozen copy. |
| Missing keys | `{ ok: false, code: "context_required", missingKeys: string[], shapes: Record<string, KeyShape>, manifestVersion: string, manifestCapabilityId: string }` | One or more manifest-declared **required** keys are absent from `suppliedContext`. Result object is frozen. |
| Invalid context | `{ ok: false; code: "context_invalid" }` | Tenant mismatch, client-remediable shape/field violation, or per-key oversize. |
| Conversation budget | `{ ok: false; code: "conversation_budget_exhausted" }` | Conversational transcript exceeds `maxHistoryTurns` or `maxContextRoundsPerTurn` (H2 / §4.3.5). |
| Platform defect | `{ ok: false; code: "internal_error" }` | Manifest declared a key that fails A5 `validateKey` (unpublished / malformed / storage-named), or a Context-requirements field is malformed at runtime despite load checks. |

Stage 6 for `single_shot` emits `context_required`, `context_invalid`, or `internal_error`. The
conversational path (H2) may also emit `conversation_budget_exhausted`.

`KeyShape` is the A5 published-shape type (`{ key: string, fields: KeyShapeField[] }`); see
`specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`.

Optional fourth argument:

```typescript
conversational?: { transcript: unknown; legTurnOrdinal: number }
```

Required when `manifest.interactionMode === "conversational"`; omitted for `single_shot`.

---

## 3. Context validator behaviour (stage 6)

### 3.1 Evaluation order

`validateContext()` applies checks in this order; the first failure short-circuits:

| Step | Check | Outcome on failure |
| --- | --- | --- |
| 1 | Required-key presence | `context_required` with the full set of missing required keys. |
| 2 | Tenant consistency | `context_invalid`. |
| 3 | Per-key shape and size (for each supplied declared key) | `context_invalid` or `internal_error` (see §3.4). |
| 4 | Filtered-context assembly | `{ ok: true, filteredContext }` (frozen copy). |

### 3.2 Required-key presence

For each entry in `manifest["Context requirements"]` where `required === true`, the validator
checks `Object.prototype.hasOwnProperty.call(suppliedContext, key)`. Absent keys are accumulated
into `missingKeys`. When `missingKeys` is non-empty, the function returns immediately with
`code: "context_required"` — shape, size, and tenant checks are not run.

`manifestVersion` is `String(manifest.Identity.version)` and `manifestCapabilityId` is
`String(manifest.Identity.capabilityId)`. Together they identify the capability the stale client
must refresh (§8.4).

A4 `load()` type-checks each entry: `required` MUST be a boolean and `maxSize` MUST be a finite
number; each `key` MUST pass A5 `validateKey`. Malformed entries fail the build rather than
silently disabling bounds.

### 3.3 Tenant consistency

After all required keys are present, the validator compares:

| Supplied context field | Principal field |
| --- | --- |
| `suppliedContext.org` | `principal.organizationId` |
| `suppliedContext.branch` | `principal.branchId` |

A mismatch on either field — including **absence** of `org`/`branch` — returns
`{ ok: false, code: "context_invalid" }`. This is a tenant-consistency failure, not a shape
failure (§5.2 Authorization, §5.6).

### 3.4 Shape conformance

For each entry in `manifest["Context requirements"]` whose key is present in `suppliedContext`,
the validator calls A5's `validatePayload(key, value)`:

| `validatePayload` outcome | Validator outcome |
| --- | --- |
| `ok` | Continue. |
| `unknown_shape` | Continue (not a rejection — A5 owns shape publication). |
| Client field violation (`type`, `cardinality`, `units`, `missing_field`, …) | `context_invalid`. |
| Platform key defect (`unknown_version`, `unknown_key`, `malformed_key`, `storage_named_key`) | `internal_error` (platform defect; §5.4). Load-time `validateKey` should already have rejected such declared keys. |

### 3.5 Per-key max size

For each supplied declared key, the validator measures the UTF-8 byte length of
`JSON.stringify(value)` and compares it against the manifest entry's `maxSize` with `>`.
Equality passes. Exceeding the bound returns `context_invalid`. A non-finite `maxSize` at
runtime returns `internal_error` (defence in depth; load already rejects).

### 3.6 Minimization (undeclared keys dropped)

On success, `filteredContext` contains **only** keys declared in `manifest["Context requirements"]`
that are also present in `suppliedContext`. Any key not declared by the manifest is dropped and is
provably absent from the payload handed to the composer (§4.3.5, §5.2 Minimization). Nested values
are deep-cloned then deep-frozen so callers and downstream stages cannot mutate through aliases.

Optional keys that are absent from `suppliedContext` are not added to `filteredContext` and do not
cause rejection (§5.1 Context requirements).

### 3.7 Published shapes (single source)

Missing-key `shapes` are looked up via A5's exported `publishedShapeForKey(key)` — there is no
duplicate shape map in `validator.ts`. Keys without a published shape are omitted from `shapes`,
not synthesised. **Note (A5 vocabulary gap):** today only `visit.chief_complaint@v1` has a published
shape, and typical required keys (`patient.demographics@v1`, `visit.vitals@v1`) do not — so
`shapes` is often `{}` for real `context_required` payloads until A5 publishes more shapes. J2
must not assume shapes are always populated.

---

## 4. context_required wire payload

`buildContextRequiredResponse(result, requestReference, traceId)` produces the HTTP 422 body for
`context_required`. It calls A2's `buildErrorBody({ code: "context_required", requestReference,
traceId })` for the four common fields, then attaches the C2-frozen missing-key manifest in
snake_case. The returned object is deep-frozen; `missing_keys` and `shapes` are copies, not shared
references with `ValidateResult`.

```typescript
{
  code: "context_required";
  request_reference: string;
  trace_id: string;
  retry_safe: boolean;          // true — A2 taxonomy: "Yes, after resolving"
  missing_keys: string[];
  shapes: Record<string, KeyShape>;
  manifest_version: string;
  manifest_capability_id: string;
}
```

| Field | Source |
| --- | --- |
| `code`, `request_reference`, `trace_id`, `retry_safe` | A2 `buildErrorBody` (four common fields). |
| `missing_keys` | Copy of `result.missingKeys` (camelCase in `ValidateResult`, snake_case on the wire). |
| `shapes` | Copy of `result.shapes` — one `KeyShape` per missing key that has a platform-published shape. |
| `manifest_version` | `result.manifestVersion`. |
| `manifest_capability_id` | `result.manifestCapabilityId`. |

HTTP status for `context_required` is **422** (A2 taxonomy; C2 does not map statuses). Slice J2
later wires client self-healing behaviour against this payload; C2 freezes the payload only.

---

## 5. PreflightResult

`runCostPreflight(manifest, serializedInput, promptArtifactByteLength?)` returns a discriminated union:

| Branch | Shape | Meaning |
| --- | --- | --- |
| Pass | `{ ok: true }` | Both stage-7 predicates hold. |
| Reject | `{ ok: false, code: "request_too_large" }` | Either predicate failed, Economics were non-finite, or `promptArtifactByteLength` was invalid. |

No other failure codes are emitted by `runCostPreflight()`. Stage 7 emits only `request_too_large`
(§6.1). HTTP status is **413** (A2 taxonomy; C2 does not map statuses).

---

## 6. Token estimation (§13.6.2)

### 6.1 Platform constants

| Constant | Value | Role |
| --- | --- | --- |
| `TOKENS_PER_BYTE_DIVISOR` | `4` | Conventional bytes-per-token ratio. |
| `ESTIMATE_SAFETY_FACTOR` | `1.15` | Conservative safety margin. |

Both are platform constants — not manifest fields and not per-provider values.

### 6.2 Estimator formula

`estimateInputTokens(serializedInput, promptArtifactByteLength = 0)` computes:

```
utf8ByteLength = TextEncoder().encode(serializedInput).byteLength + promptArtifactByteLength
estimatedInputTokens = ceil(utf8ByteLength / TOKENS_PER_BYTE_DIVISOR) * ESTIMATE_SAFETY_FACTOR
```

`promptArtifactByteLength` is the known UTF-8 byte length of prompt artifacts bound to the
capability (system instruction, rule fragments, templates — §13.6.2). Callers (D1/D3) supply it;
default `0` preserves prior single-argument call sites.

The estimate is deterministic, provider-independent, and CPU-only. It is never billed; exact
accounting is stage 15 (§13.6.2).

---

## 7. Cost pre-flight behaviour (stage 7)

### 7.1 Economics inputs

`runCostPreflight()` reads from `manifest.Economics`:

| Field | Use |
| --- | --- |
| `maxOutputTokens` | Added to the input estimate for the ceiling comparison. |
| `maxInputTokens` | Secondary bound on the input estimate alone. |
| `perRequestCostCeiling` | Token-denominated per-request budget (§5.1). |

A4 `load()` requires each Economics field to be a finite number. At runtime, non-finite values
fail closed as `request_too_large` (defence in depth).

### 7.2 Rejection predicates

Let `estimatedInputTokens = estimateInputTokens(serializedInput, promptArtifactByteLength)`. The
pre-flight **passes** when **both** predicates hold:

```
estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling
estimatedInputTokens ≤ maxInputTokens
```

The pre-flight **rejects** with `request_too_large` when **either** predicate fails (`>`), when
Economics are non-finite, or when `promptArtifactByteLength` is non-finite or negative.

The comparison is in tokens throughout. C2 applies no token→cost conversion and holds no provider
price (§13.6.2). Currency appears only in the post-response `usage_event` ledger.

### 7.3 No egress on rejection

A pre-flight rejection must occur before the composer (stage 10) or provider invocation (stage 11).
No egress occurs when `runCostPreflight()` returns `{ ok: false }` (§4.3.3, §6.1 stage 7).
Pipeline wiring into `worker.ts` is deferred to consuming slices (see §10); unit spies prove the
module-level no-egress property.

---

## 8. HTTP status mapping (consumed, not owned)

C2 emits taxonomy codes only. A2 assigns HTTP statuses; C2 does not modify them:

| Code | HTTP status | `retry_safe` (via `buildErrorBody`) |
| --- | --- | --- |
| `context_required` | 422 | `true` |
| `context_invalid` | 422 | `false` |
| `conversation_budget_exhausted` | (A2) | (A2) |
| `request_too_large` | 413 | `false` |
| `internal_error` | 500 | `true` (platform defect; retry-safe per §5.4) |

---

## 9. Export surface

### 9.1 `ai-platform/src/context/validator.ts`

| Export | Role |
| --- | --- |
| `ValidateResult` | Discriminated union for stage-6 outcomes (incl. H2 / platform-defect branches). |
| `TranscriptTurn`, `Transcript`, `ConversationalValidateOptions` | H2 conversational types. |
| `validateContext(manifest, suppliedContext, principal, conversational?)` | Stage-6 context validator. |
| `buildContextRequiredResponse(result, requestReference, traceId)` | Frozen HTTP 422 body builder for `context_required`. |

### 9.2 `ai-platform/src/context/preflight.ts`

| Export | Role |
| --- | --- |
| `TOKENS_PER_BYTE_DIVISOR` | Platform constant (`4`). |
| `ESTIMATE_SAFETY_FACTOR` | Platform constant (`1.15`). |
| `estimateInputTokens(serializedInput, promptArtifactByteLength?)` | §13.6.2 byte-based token estimator. |
| `PreflightResult` | Discriminated union for stage-7 outcomes. |
| `runCostPreflight(manifest, serializedInput, promptArtifactByteLength?)` | Stage-7 cost pre-flight. |

`buildShapesForMissingKeys` remains internal to `validator.ts`. Shape lookup uses A5
`publishedShapeForKey`.

---

## 10. Consumers

| Slice / stage | What it reads |
| --- | --- |
| **Prompt composer (D1)** | `ValidateResult.filteredContext` — manifest-declared keys only, no undeclared keys; supplies `promptArtifactByteLength` into stage 7 when wired. |
| **Client self-healing (J2)** | `context_required` wire payload — `missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id` (shapes may be empty until A5 publishes more). |
| **Admission (B4)** | Pre-flight pass — only requests that returned `{ ok: true }` from `runCostPreflight()` proceed to stage 8. |
| **Invocation (D3)** | Pre-flight pass — provider egress occurs only after stage 7 passes. |
| **Protocol adapter (A6)** | Taxonomy codes from `ValidateResult.code` and `PreflightResult.code` — maps to HTTP statuses; does not build the `context_required` body (C2 owns that). |

C2 does **not** wire stages 6–7 into `worker.ts`; consumption is deferred to the slices above.

---

## 11. Out of scope for this contract

| Behaviour | Owner | Reason |
| --- | --- | --- |
| Context-key vocabulary and `validatePayload()` | A5 | Platform-published shapes; C2 orchestrates, does not redefine. Publishing shapes for required keys is an A5 gap, not a C2 defect. |
| Resolved manifest immutability | C1 | C2 reads `ResolveResult.manifest` as read-only. |
| Request principal construction | B3 | C2 reads `principal.organizationId` and `principal.branchId`; does not verify the token. |
| HTTP status mapping and SSE framing | A6 | C2 emits codes; A6 maps to statuses. Ingress-too-large gate (stage 1) remains A6's. |
| Per-installation Quota DO admission | B4 | Stage 8; distinct from the local token-ceiling pre-flight. |
| Provider invocation and egress | D3 | Stage 11; preceded by stage 7. |
| Prompt composition | D1 | Consumes `filteredContext`; does not validate it. Supplies artifact byte length when calling pre-flight. |
| Journal rows for guard rejections | C3 | Stages 6–7 rejections produce no journal row (§6.2). |
| Client `context_required` self-healing behaviour | J2 | C2 freezes the payload; J2 wires the refresh-and-resubmit-once behaviour. |
| Conversational transcript validation (original C2 scope) | H2 | H2 extended `validator.ts` in place; behaviour is architecture-aligned and documented in §2 / §9.1 above. |
