# Contract: Context validator stage and cost pre-flight (C2)

**Frozen by:** Slice C2 — Context validator stage and cost pre-flight
**Implements:** §4.3.5, §5.2, §4.3.3, §6.1 stages 6–7, §13.6.2 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (D1, J2, B4, D3) **consume** this artifact; they extend, never rewrite
the `ValidateResult` union, the `context_required` wire payload shape, the `PreflightResult` union,
the §13.6.2 estimator formula, or the stage-7 rejection predicates.

**Source of truth in code:** `ai-platform/src/context/validator.ts` (`ValidateResult`,
`validateContext`, `buildContextRequiredResponse`); `ai-platform/src/context/preflight.ts`
(`PreflightResult`, `TOKENS_PER_BYTE_DIVISOR`, `ESTIMATE_SAFETY_FACTOR`, `estimateInputTokens`,
`runCostPreflight`).

**Traces to:** FR-001–FR-009; spec **Freezes** entries; A5 context-key shapes
(`specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`); C1 resolved manifest
(`specs/025-capability-resolver-discovery/contracts/capability-registry.md`); B3 request principal
(`specs/023-guard-stages/contracts/request-principal.md`); A2 error taxonomy (`ai-platform/src/errors.ts`).

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

---

## 2. ValidateResult

`validateContext(manifest, suppliedContext, principal)` returns a discriminated union:

| Branch | Shape | Meaning |
| --- | --- | --- |
| Success | `{ ok: true, filteredContext: Record<string, unknown> }` | All checks passed; only manifest-declared keys that were supplied are retained. |
| Missing keys | `{ ok: false, code: "context_required", missingKeys: string[], shapes: Record<string, KeyShape>, manifestVersion: string, manifestCapabilityId: string }` | One or more manifest-declared **required** keys are absent from `suppliedContext`. |
| Invalid context | `{ ok: false, code: "context_invalid" }` | Tenant mismatch, shape violation, or per-key oversize. |

No other failure codes are emitted by `validateContext()`. Stage 6 emits only `context_required` or
`context_invalid` (§6.1).

`KeyShape` is the A5 published-shape type (`{ key: string, fields: KeyShapeField[] }`); see
`specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`.

---

## 3. Context validator behaviour (stage 6)

### 3.1 Evaluation order

`validateContext()` applies checks in this order; the first failure short-circuits:

| Step | Check | Outcome on failure |
| --- | --- | --- |
| 1 | Required-key presence | `context_required` with the full set of missing required keys. |
| 2 | Tenant consistency | `context_invalid`. |
| 3 | Per-key shape and size (for each supplied declared key) | `context_invalid`. |
| 4 | Filtered-context assembly | `{ ok: true, filteredContext }`. |

### 3.2 Required-key presence

For each entry in `manifest["Context requirements"]` where `required === true`, the validator
checks `Object.prototype.hasOwnProperty.call(suppliedContext, key)`. Absent keys are accumulated
into `missingKeys`. When `missingKeys` is non-empty, the function returns immediately with
`code: "context_required"` — shape, size, and tenant checks are not run.

`manifestVersion` is `String(manifest.Identity.version)` and `manifestCapabilityId` is
`String(manifest.Identity.capabilityId)`. Together they identify the capability the stale client
must refresh (§8.4).

### 3.3 Tenant consistency

After all required keys are present, the validator compares:

| Supplied context field | Principal field |
| --- | --- |
| `suppliedContext.org` | `principal.organizationId` |
| `suppliedContext.branch` | `principal.branchId` |

A mismatch on either field returns `{ ok: false, code: "context_invalid" }`. This is a
tenant-consistency failure, not a shape failure (§5.2 Authorization, §5.6).

### 3.4 Shape conformance

For each entry in `manifest["Context requirements"]` whose key is present in `suppliedContext`,
the validator calls A5's `validatePayload(key, value)`. A shape violation returns
`context_invalid` when `!payloadResult.ok && payloadResult.code !== "unknown_shape"`.

The `unknown_shape` outcome is **not** a rejection at this stage — keys without a platform-published
shape pass the shape check (A5 owns shape publication; C2 orchestrates on top).

### 3.5 Per-key max size

For each supplied declared key, the validator measures the UTF-8 byte length of
`JSON.stringify(value)` and compares it against the manifest entry's `maxSize`. Exceeding the
bound returns `context_invalid`.

### 3.6 Minimization (undeclared keys dropped)

On success, `filteredContext` contains **only** keys declared in `manifest["Context requirements"]`
that are also present in `suppliedContext`. Any key not declared by the manifest is dropped and is
provably absent from the payload handed to the composer (§4.3.5, §5.2 Minimization).

Optional keys that are absent from `suppliedContext` are not added to `filteredContext` and do not
cause rejection (§5.1 Context requirements).

---

## 4. context_required wire payload

`buildContextRequiredResponse(result, requestReference, traceId)` produces the HTTP 422 body for
`context_required`. It calls A2's `buildErrorBody({ code: "context_required", requestReference,
traceId })` for the four common fields, then attaches the C2-frozen missing-key manifest in
snake_case:

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
| `missing_keys` | `result.missingKeys` (camelCase in `ValidateResult`, snake_case on the wire). |
| `shapes` | `result.shapes` — one `KeyShape` per missing key that has a platform-published shape. Keys without a published shape are omitted from `shapes`, not synthesised. |
| `manifest_version` | `result.manifestVersion`. |
| `manifest_capability_id` | `result.manifestCapabilityId`. |

HTTP status for `context_required` is **422** (A2 taxonomy; C2 does not map statuses). Slice J2
later wires client self-healing behaviour against this payload; C2 freezes the payload only.

---

## 5. PreflightResult

`runCostPreflight(manifest, serializedInput)` returns a discriminated union:

| Branch | Shape | Meaning |
| --- | --- | --- |
| Pass | `{ ok: true }` | Both stage-7 predicates hold. |
| Reject | `{ ok: false, code: "request_too_large" }` | Either predicate failed. |

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

`estimateInputTokens(serializedInput)` computes:

```
estimatedInputTokens = ceil(utf8ByteLength / TOKENS_PER_BYTE_DIVISOR) * ESTIMATE_SAFETY_FACTOR
```

where `utf8ByteLength = new TextEncoder().encode(serializedInput).byteLength` (multi-byte safe).

In shorthand: `ceil(utf8Bytes / 4) * 1.15`.

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

### 7.2 Rejection predicates

Let `estimatedInputTokens = estimateInputTokens(serializedInput)`. The pre-flight **passes** when
**both** predicates hold:

```
estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling
estimatedInputTokens ≤ maxInputTokens
```

The pre-flight **rejects** with `request_too_large` when **either** predicate fails:

```
estimatedInputTokens + maxOutputTokens > perRequestCostCeiling
estimatedInputTokens > maxInputTokens
```

The comparison is in tokens throughout. C2 applies no token→cost conversion and holds no provider
price (§13.6.2). Currency appears only in the post-response `usage_event` ledger.

### 7.3 No egress on rejection

A pre-flight rejection must occur before the composer (stage 10) or provider invocation (stage 11).
No egress occurs when `runCostPreflight()` returns `{ ok: false }` (§4.3.3, §6.1 stage 7).

---

## 8. HTTP status mapping (consumed, not owned)

C2 emits taxonomy codes only. A2 assigns HTTP statuses; C2 does not modify them:

| Code | HTTP status | `retry_safe` (via `buildErrorBody`) |
| --- | --- | --- |
| `context_required` | 422 | `true` |
| `context_invalid` | 422 | `false` |
| `request_too_large` | 413 | `false` |

---

## 9. Export surface

### 9.1 `ai-platform/src/context/validator.ts`

| Export | Role |
| --- | --- |
| `ValidateResult` | Discriminated union for stage-6 outcomes. |
| `validateContext(manifest, suppliedContext, principal)` | Stage-6 context validator. |
| `buildContextRequiredResponse(result, requestReference, traceId)` | HTTP 422 body builder for `context_required`. |

### 9.2 `ai-platform/src/context/preflight.ts`

| Export | Role |
| --- | --- |
| `TOKENS_PER_BYTE_DIVISOR` | Platform constant (`4`). |
| `ESTIMATE_SAFETY_FACTOR` | Platform constant (`1.15`). |
| `estimateInputTokens(serializedInput)` | §13.6.2 byte-based token estimator. |
| `PreflightResult` | Discriminated union for stage-7 outcomes. |
| `runCostPreflight(manifest, serializedInput)` | Stage-7 cost pre-flight. |

`PUBLISHED_SHAPES` and `buildShapesForMissingKeys` are internal to `validator.ts`; they are not
exported.

---

## 10. Consumers

| Slice / stage | What it reads |
| --- | --- |
| **Prompt composer (D1)** | `ValidateResult.filteredContext` — manifest-declared keys only, no undeclared keys. |
| **Client self-healing (J2)** | `context_required` wire payload — `missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id`. |
| **Admission (B4)** | Pre-flight pass — only requests that returned `{ ok: true }` from `runCostPreflight()` proceed to stage 8. |
| **Invocation (D3)** | Pre-flight pass — provider egress occurs only after stage 7 passes. |
| **Protocol adapter (A6)** | Taxonomy codes from `ValidateResult.code` and `PreflightResult.code` — maps to HTTP statuses; does not build the `context_required` body (C2 owns that). |

---

## 11. Out of scope for this contract

| Behaviour | Owner | Reason |
| --- | --- | --- |
| Context-key vocabulary and `validatePayload()` | A5 | Platform-published shapes; C2 orchestrates, does not redefine. |
| Resolved manifest immutability | C1 | C2 reads `ResolveResult.manifest` as read-only. |
| Request principal construction | B3 | C2 reads `principal.organizationId` and `principal.branchId`; does not verify the token. |
| HTTP status mapping and SSE framing | A6 | C2 emits codes; A6 maps to statuses. Ingress-too-large gate (stage 1) remains A6's. |
| Per-installation Quota DO admission | B4 | Stage 8; distinct from the local token-ceiling pre-flight. |
| Provider invocation and egress | D3 | Stage 11; preceded by stage 7. |
| Prompt composition | D1 | Consumes `filteredContext`; does not validate it. |
| Journal rows for guard rejections | C3 | Stages 6–7 rejections produce no journal row (§6.2). |
| Client `context_required` self-healing behaviour | J2 | C2 freezes the payload; J2 wires the refresh-and-resubmit-once behaviour. |
| Conversational transcript validation | H2 | `interaction_mode: conversational` manifests are not validated by C2. |
