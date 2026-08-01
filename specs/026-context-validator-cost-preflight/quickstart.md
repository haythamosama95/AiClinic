# Quickstart: Context validator stage and cost pre-flight (C2)

C2 adds the guard's stage-6 context validator and stage-7 cost pre-flight to the AI gateway: after
C1 resolves an immutable capability manifest, C2 validates the client-supplied context payload
against the manifest's Context Contract, drops undeclared keys, and runs a token-denominated
pre-flight that rejects oversized requests before any egress to a provider or composer.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

C2 implements the **C2** row in
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md)
§3.4, covering architecture sections **§4.3.5** (context validator), **§5.2** (context-key shapes
and minimization), **§4.3.3** (cost-ceiling check), **§6.1 stages 6–7** (pipeline stages), and
**§13.6.2** (byte-based input-token estimator). Full detail lives in
[`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md).

- **What the spec delivered** ([`spec.md`](./spec.md)): stage-6 validation that enforces required
  keys, declared shapes, per-key max size, and org/branch consistency against token claims; drops
  undeclared keys rather than forwarding them; emits `context_required` (422) with the missing-key
  manifest when a required key is absent; emits `context_invalid` (422) on shape, size, or
  tenant-consistency violations; stage-7 cost pre-flight that estimates input tokens via the
  §13.6.2 formula and rejects with `request_too_large` (413) when
  `estimatedInputTokens + maxOutputTokens` exceeds the token-denominated `perRequestCostCeiling` or
  when `estimatedInputTokens` alone exceeds `maxInputTokens`; zero egress on pre-flight rejection.
- **What the plan scoped** ([`plan.md`](./plan.md)): two new modules under `ai-platform/src/context/`
  — `validator.ts` (stage-6 `validateContext()` + `buildContextRequiredResponse()`) and
  `preflight.ts` (stage-7 `estimateInputTokens()` + `runCostPreflight()`); one test file with 15
  named test suites (`T-C2-01` … `T-C2-15`); one frozen contract artifact; no `worker.ts` wiring
  (functions tested directly, mirroring B3/C1); CPU-only — no D1, Durable Object, R2, or provider
  I/O.

## 2. What was implemented

- **`validateContext()`** (`src/context/validator.ts`) — stage-6 validator: checks required keys,
  shape conformance, per-key max size, and org/branch consistency; drops undeclared keys; returns a
  filtered context payload on success or a typed rejection (`context_required` /
  `context_invalid`).
- **`buildContextRequiredResponse()`** (`src/context/validator.ts`) — `context_required` wire
  builder: calls A2's `buildErrorBody` for the four common fields and attaches the frozen
  snake_case missing-key manifest (`missing_keys`, `shapes`, `manifest_version`,
  `manifest_capability_id`).
- **`estimateInputTokens()`** (`src/context/preflight.ts`) — stage-7 byte estimator: deterministic
  `ceil(utf8ByteLength(serialized input) / 4) * 1.15` per §13.6.2.
- **`runCostPreflight()`** (`src/context/preflight.ts`) — stage-7 two-predicate pre-flight:
  rejects when `estimatedInputTokens + maxOutputTokens > perRequestCostCeiling` or when
  `estimatedInputTokens > maxInputTokens`; emits `request_too_large` on breach.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/context/validator.ts` | stage-6 validator |
| `ai-platform/src/context/preflight.ts` | stage-7 pre-flight |
| `ai-platform/test/context-validator.test.ts` | 15 named `T-C2-*` tests |
| `specs/026-context-validator-cost-preflight/contracts/context-validator.md` | frozen wire shapes |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/context-validator.test.ts
```

Expected: **19 passing tests** (15 named test suites with parameterised cases) for this slice only.
Tests are green: **19 passed**. Do **not** run `npm test` for the full platform suite.

| Test id | Describe name |
| --- | --- |
| T-C2-01 | `validator_accepts_complete_valid_context` |
| T-C2-02 | `validator_rejects_each_missing_required_key` |
| T-C2-03 | `validator_rejects_multiple_missing_required_keys` |
| T-C2-04 | `validator_rejects_each_shape_violation` |
| T-C2-05 | `validator_rejects_oversize_key` |
| T-C2-06 | `validator_drops_undeclared_key_spy` |
| T-C2-07 | `validator_rejects_org_mismatch` |
| T-C2-08 | `validator_rejects_branch_mismatch` |
| T-C2-09 | `validator_passes_absent_optional_key` |
| T-C2-10 | `preflight_passes_under_ceiling` |
| T-C2-11 | `preflight_rejects_over_ceiling` |
| T-C2-12 | `preflight_estimate_includes_max_output_tokens` |
| T-C2-13 | `preflight_no_egress_on_rejection_spy` |
| T-C2-14 | `preflight_estimator_is_deterministic_bytes` |
| T-C2-15 | `preflight_rejects_over_max_input_tokens` |

## 5. Inspect the changes

Grep for the stage-6 taxonomy codes in the validator module:

```bash
cd ai-platform
grep -n 'context_required\|context_invalid' src/context/validator.ts
```

Grep for the stage-7 estimator and rejection code in the pre-flight module:

```bash
grep -n 'estimateInputTokens\|request_too_large' src/context/preflight.ts
```

Read the frozen contract artifact:

```bash
cat ../specs/026-context-validator-cost-preflight/contracts/context-validator.md
```

Confirm the `ValidateResult` discriminated union, `FilteredContext` shape,
`ContextRequiredResponse` wire payload, `PreflightResult` type, and the §13.6.2 estimator formula
match what `validateContext()` and `runCostPreflight()` export.
