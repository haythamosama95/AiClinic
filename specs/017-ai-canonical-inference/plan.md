# Implementation Plan: Canonical inference representation (slice A3)

**Branch**: `ai/017-a3-canonical-inference-representation` | **Date**: 2026-07-30 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `/specs/017-ai-canonical-inference/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

A3 freezes the four canonical, provider-neutral inference elements of §5.3 (request, stream chunk, result, error) as typed code inside the Cloudflare Worker, plus a contract test that fails if any upstream field name is provider-shaped (§5.3, §9.10). It sits immediately after A1 in delivery band A because every later inference-path slice (D2 composer, D3 provider port, D6 stream broker, D9 validator) consumes these types, so freezing them as code before those slices start constrains a weak implementer against provider-shaped drift (delivery plan §3.2 row A3, Needs = A1; DP-4).

## Technical Context

**Language/Version**: TypeScript 5.9 on Node.js 22+ (repository `.nvmrc`), targeting the Cloudflare Workers runtime (`@cloudflare/workers-types`).

**Primary Dependencies**: `vitest` ~3.2.4 with `@cloudflare/vitest-pool-workers` for the contract suite; `typescript` for type-level enforcement. No new production dependency is introduced — the canonical elements are plain typed data and a thin owned JSON codec.

**Storage**: N/A. A3 defines in-memory/wire representation types only; it writes no D1 rows, no R2 objects, and no Durable Object state (spec § Key Entities; delivery plan §3.2 row A3).

**Testing**: Contract layer of §13.5 — `npm test` from `ai-platform/` runs `vitest run`, joining the A1 and A2 suites already in `ai-platform/test/`. A regression in any prior slice's suite is a hard fail (delivery plan §3.10).

**Target Platform**: Cloudflare Worker (`ai-platform/`), deployed to the dev/staging/production environments A1 provisioned. A3 adds no binding and no deployable behaviour.

**Project Type**: Additive, non-primary gateway component — one serverless Worker, synchronous, no queues, no per-request state (§14; constitution principle I).

**Performance Goals**: None for this slice. It is types and a codec; runtime cost is not on any hot path A3 introduces.

**Constraints**: Desktop-first constitution principle I is preserved by the slice's purpose (stable core lets prompts/providers/models change without a client release, §1.1). No mechanism from §9.14 is added (R-20). The canonical types name no prompt text, provider name, or model identifier (R-12). The platform's I/O budgets are untouched — A3 performs zero D1 inserts, zero R2 puts, and zero Durable Object round trips, so §6.1/§7.5/§13.6 limits are trivially preserved.

**Scale/Scope**: One new source module, one new test file, plus this directory's `quickstart.md` and a `contracts/` artifact documenting the frozen shapes. The slice holds the four §5.3 elements, the four chunk kinds, and one guard invariant; it is well within the 25-task sizing guidance.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

**§14 acknowledgement for gateway slices:** the Cloudflare Worker is an additive, non-primary component introduced in architecture §14 — it holds no domain logic, no business data, and no write path into Supabase, and it is always optional (AI is additive per A11). Slice A3 adds only the canonical representation types and their contract test inside that boundary; it touches no clinical data, no Supabase path, and no client code, so the §14 boundary is preserved.

## Project Structure

### Documentation (this feature)

```text
specs/017-ai-canonical-inference/
├── spec.md                 # /ai-platform-specify output (authoritative)
├── plan.md                 # This file (/ai-platform-plan output)
├── contracts/
│   └── canonical-shapes.md # Frozen wire shapes of the four §5.3 elements, for later slices' Consumes review
└── quickstart.md           # Written during the implement phase's Documentation task (per the ai-platform-quickstart-template)
```

No `data-model.md` — A3 defines no D1 entities (spec § Key Entities). No `research.md` — the research is `17-ai-platform.md` §5.3 and §9.10; redoing it is architecture drift (delivery plan preamble). No `tasks.md` here — produced by `/ai-platform-tasks`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── worker.ts           # A1 — unchanged; A3 adds no request path
│   ├── reference.ts        # A2 — consumed, not modified
│   ├── trace.ts            # A2 — consumed, not modified
│   ├── errors.ts           # A2 — canonical error's taxonomy code binds to its TaxonomyCode type, not modified
│   └── contracts/
│       └── canonical.ts    # A3 — field-name manifest, four canonical element types derived from it, owned JSON codec
└── test/
    ├── env-deploys.test.ts # A1
    ├── health.test.ts      # A1
    ├── error-body.test.ts  # A2
    ├── taxonomy.test.ts    # A2
    ├── log-redaction.test.ts # A2
    ├── reference.test.ts   # A2
    ├── trace.test.ts       # A2
    └── canonical.test.ts   # A3 — T-A3-01..07 contract suite
```

**Structure Decision**: A3 lives entirely under `ai-platform/`, the gateway directory at the repository root, consistent with delivery plan §7.1 (the gateway is a sibling of `frontend/` and `backend/`, not a subdirectory of `backend/`). The new `ai-platform/src/contracts/` subdirectory groups frozen contract types; later slices (D2, D3, D6, D9) import from it. No existing file under `ai-platform/src/` is modified — the consuming exercises happen in `canonical.test.ts`, which imports the new module alongside A2's `errors.ts` (whose `TaxonomyCode` type the canonical error field references) without altering either.

## Consumes Binding

| Consumes entry (spec) | Existing module / file / type it binds to |
| --- | --- |
| A1's Worker skeleton and environment bindings (§13.4, §1.4) | `ai-platform/src/worker.ts`, `ai-platform/wrangler.toml`, `ai-platform/package.json`, and the `Env` interface A1 declared. A3 adds no binding and no env entry; it adds `ai-platform/src/contracts/canonical.ts` and `ai-platform/test/canonical.test.ts` only. |
| A2's error taxonomy (§5.4) | `ai-platform/src/errors.ts` — `export type TaxonomyCode` (the closed 18-code set) and `isTaxonomyCode`. The canonical error element's `taxonomy code` field is typed as A2's `TaxonomyCode`; an unrecognised value is rejected via `classifyErrorCode`'s fallback to `internal_error` (spec § Edge Cases, FR-007). A3 reads the type and does not redefine the set. |

Both bindings resolve to implementations already on `ai/master`. No frozen contract is changed (delivery plan §2.3).

## Components Touched

Slice A3 modifies **no §4 component of `17-ai-platform.md`**. It defines the §5.3 contract that §4.3.6 (composer), §4.3.8 (provider adapter), §4.3.10 (stream broker), and §4.3.9 (validator) will later consume. A3 is a contract-freezing slice (DP-4); touching a §4 component's behaviour belongs to bands C and D. This satisfies stop condition 5 by default — zero §4 components touched, with no written reason required beyond that statement.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/contracts/canonical.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `ai-platform/test/canonical.test.ts` | Created | FR-009 (guard), SC-001, SC-002, SC-003, SC-004, and the Test plan's T-A3-01..07 |
| `specs/017-ai-canonical-inference/contracts/canonical-shapes.md` | Created | Freezes (the four §5.3 wire shapes documented for later slices' Consumes) |
| `specs/017-ai-canonical-inference/quickstart.md` | Created | Documentation task — what A3 implemented, files to review, how to run the suite, how to inspect the frozen shapes |

No file outside the above is created or modified. In particular, `ai-platform/src/worker.ts`, `reference.ts`, `trace.ts`, and `errors.ts` are unchanged.

## Test Layout

All seven named tests from the spec's `### Test plan` live in the **Contract tests** layer of §13.5 ("Manifests, context key shapes, output schemas, and the error taxonomy are internally consistent and backward compatible... CI, on every change"). They run as plain `vitest` unit tests in `ai-platform/test/canonical.test.ts` — no Worker runtime, no D1/R2/DO access, since A3 has no I/O path.

| Test name | Layer (§13.5) | File | Binds to |
| --- | --- | --- | --- |
| `T-A3-01` round-trip canonical request | Contract | `ai-platform/test/canonical.test.ts` | `encodeCanonicalRequest` / `decodeCanonicalRequest` over the manifest-driven codec |
| `T-A3-02` round-trip canonical stream chunk | Contract | `ai-platform/test/canonical.test.ts` | `encodeCanonicalChunk` / `decodeCanonicalChunk` |
| `T-A3-03` round-trip canonical result | Contract | `ai-platform/test/canonical.test.ts` | `encodeCanonicalResult` / `decodeCanonicalResult` |
| `T-A3-04` round-trip canonical error | Contract | `ai-platform/test/canonical.test.ts` | `encodeCanonicalError` / `decodeCanonicalError` (taxonomy code validated against A2's `TaxonomyCode`) |
| `T-A3-05` provider-shaped field name rejected | Contract | `ai-platform/test/canonical.test.ts` | The guard reads the manifest keys and fails if any equals a known provider-shaped token (`messages`, `completion`, `n`, `frequency_penalty`, `top_p`, `logprobs`, …); codec encode/decode also reject a provider-shaped extra key on the value/wire — FR-009 / SC-002 |
| `T-A3-06` chunk kinds exhaustive | Contract | `ai-platform/test/canonical.test.ts` | Asserts the closed set is exactly `{text_delta, partial_structured, usage, provider_note}` and rejects any other kind — FR-005 / SC-003 |
| `T-A3-07` terminal flag exactly once per sequence | Contract | `ai-platform/test/canonical.test.ts` | Asserts zero-terminal and multiple-terminal sequences are rejected; exactly one terminal flag is required — FR-004 / SC-004 / §5.5 rule 4 |
| `T-A3-08` unknown keys rejected on decode | Contract | `ai-platform/test/canonical.test.ts` | Decode/encode reject unknown non-manifest keys fail-closed (no silent strip) on request, chunk, result, and error |
| `T-A3-09` typed field schema | Contract | `ai-platform/test/canonical.test.ts` | Decoded request/result/error expose typed field access; `CANONICAL_MESSAGE_ROLES` is the closed §5.3 role set |

`T-A3-05` is a spy-style assertion on an *absence*: it feeds a deliberately provider-shaped key into the manifest and proves the contract test rejects it, and additionally proves the codec rejects provider-shaped extras on the wire rather than stripping them — mirroring how §3.10 treats "the assertion is on the number or absence of calls". `T-A3-07`'s boundary inputs (zero-terminal, multiple-terminal) are constructed in-test from chunk sequences, since A3 has no runtime stream to observe.

## Sequencing

Tests are written first or alongside the module; no implementation lands before its test.

1. **`ai-platform/src/contracts/canonical.ts` skeleton + manifest.** The field-name manifest enumerating each canonical element's §5.3 keys is written first, with the `T-A3-05` guard test exercising it before the TS types are derived. (FR-002, FR-009)
2. **Types derived from the manifest.** The four canonical element interfaces use real per-field TypeScript types (not `ManifestRecord → unknown`), so adapters/composer can read fields without `as` casts. Field *names* stay the frozen §5.3 prose keys. (FR-001, FR-003..FR-007; T-A3-09)
3. **Chunk-kind closed set + terminal-flag invariant helpers.** `T-A3-06` and `T-A3-07` are written next to pin the closed kind set and the exactly-one-terminal rule. (FR-004, FR-005, SC-003, SC-004)
4. **Owned JSON codec.** The thin manifest-driven encoder/decoder is added, then `T-A3-01..04` exercise it as round-trip tests asserting §5.3 key names survive byte-for-byte with no extra keys. (FR-008, SC-001)
5. **Full suite green.** `npm test` from `ai-platform/` runs A1, A2, and A3 suites; A1/A2 regressions are hard fails. (delivery plan §3.10)
6. **Documentation task.** `specs/017-ai-canonical-inference/contracts/canonical-shapes.md` documents the four frozen shapes for later slices' Consumes, and `quickstart.md` is filled per the ai-platform-quickstart-template (files to review, suite invocation, focused inspection, no manual validation section since CI is the only verification path).

## Complexity Tracking

> Not filled — no Constitution Check box is violated. A3 is an additive, non-primary, contract-only slice inside the §14-bounded gateway; no complexity exception is being claimed.