# Implementation Plan: Capability manifest schema and loader (A4)

**Branch**: `ai/018-a4-capability-manifest` | **Date**: 2026-07-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/018-ai-capability-manifest/spec.md`

## Summary

A4 freezes the platform's declaration of an AI feature: a schema that covers all ten
field groups of §5.1 and a loader that turns a JSON manifest into a typed, immutable
`Manifest` object, plus a published-version hash registry so an in-place edit to a
published version fails CI. It sits in band A because nothing in it handles a real
request — it exists so that every later stage (resolver, validator, composer, router,
journal) is constrained by a frozen contract rather than by prose (delivery plan §3.2,
row A4). It needs only A3 (canonical types, which it does not redefine) and must land
before A5 (context-key vocabulary) and C1 (the capability resolver).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), Node ≥22 for the toolchain.

**Primary Dependencies**: `vitest` ~3.2 (contract test runner, already present from A1–A3), `@cloudflare/workers-types`. No new dependency is introduced — the manifest schema is hand-rolled TS narrowing, mirroring A3's `CANONICAL_FIELD_MANIFEST` pattern (no schema-validation library is named by §5.1/§5.7, and adding one would be a mechanism the spec does not name — R-20).

**Storage**: None. A4 defines no D1, R2, or DO entity and writes nothing to any store (spec §Key Entities: "A4 defines no stored domain data"). D1 schema/migrations are A6.

**Testing**: `npx vitest run` contract + build tests in `ai-platform/test/manifest.test.ts`, run in CI on every change (§13.5 Contract tests row). The CI gate *is* the "build fails" mechanism in the spec's Done-when and §3.11.1 row A4 — a manifest that fails to load, a malformed group, or a published-version hash mismatch fails the contract test and therefore fails CI.

**Target Platform**: The `ai-platform/` Cloudflare Worker at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). No Worker request path is exercised by this slice.

**Project Type**: Additive, non-primary AI gateway component (§14 acknowledgement) — contract surface only, no domain logic, no business data, no write path into Supabase.

**Performance Goals**: Not applicable — A4 is a build-time contract slice with no request path and no latency budget.

**Constraints**: A manifest is data, not code, and never names a provider or a model (§5.1). `interaction_mode` is the only shape switch and defaults to `single_shot`. The manifest is immutable per version; an in-place edit to a published version is a new version, never a mutation (§5.7). Hand-rolled TS narrowing, schema-as-data, internal validator — matching A3 (fewest moving parts, R-20/D-15).

**Scale/Scope**: One §4 component (§4.3.4, contract surface only), one module, one test file, one contract artifact, one quickstart. ~8–10 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — A4 is a contract surface shared by every clinic; it introduces no enterprise-specific concept.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — A4 adds a typed schema and a build-time hash check; no new service, queue, or orchestration.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — A4 lives wholly in `ai-platform/` and touches neither `frontend/` nor `backend/`.
- [ ] (intentionally unchecked — see note) Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — N/A: A4 defines no stored domain data, no writes, no RLS, no RPC. This row concerns the Supabase/PostgreSQL layer and does not apply to a gateway contract slice. Per the §14 acknowledgement registered for band A (delivery plan §7), the Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase.
- [ ] (intentionally unchecked — see note) Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — N/A: A4 has no request path, no authn/authz surface (B4/B8), no tenant scoping, and no records to soft-delete. Those land in band B and C. A4 is build-time contract surface only.
- [ ] (intentionally unchecked — see note) AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — N/A: A4 declares the `acceptance_mode` *value* (a string on the manifest) but performs no AI action, has no backend access, and has no runtime to degrade. Acceptance *behaviour* is F2; the manifest just carries the field (§5.1 Governance row).

The three unchecked boxes are the Supabase/PostgreSQL/acceptance-runtime rows that are structurally inapplicable to a build-time, data-only contract slice in the additive gateway. They are not constitution violations; they are recorded here rather than silently dropped, per the §14 acknowledgement that the gateway is non-primary, additive, and holds no domain truth.

## Project Structure

### Documentation (this feature)

```text
specs/018-ai-capability-manifest/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify output (already present)
├── quickstart.md        # Written after implementation + verification (this slice's review surface)
├── contracts/
│   └── manifest-schema.md   # The frozen manifest payload shape (Freezes → wire shape)
└── tasks.md             # /ai-platform-tasks output (NOT created here)
```

`data-model.md` is omitted — A4 defines no D1 entity (spec §Key Entities). `research.md` is never produced on this platform; the research is `docs/architecture/17-ai-platform.md` (delivery plan §6, plan-phase protocol).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── contracts/
│   │   └── canonical.ts      # A3 — consumed, unchanged
│   └── manifest/
│       └── index.ts          # NEW — Manifest type, load(), registry/hash helpers; validator internal
└── test/
    └── manifest.test.ts      # NEW — T-A4-* contract + build tests (inline fixture builders)
```

**Structure Decision**: The manifest module is a single directory `ai-platform/src/manifest/` exporting `load()` and the `Manifest` type with the validator kept internal, per Clarification Q3. The published-version mechanism (content hash + registry check) lives in the same module as exported helpers (`hashManifest`, `verifyPublishedRegistry`), since the "in-place edit fails the build" gate is exercised by the contract test suite (§13.5), which is the CI build gate for this slice. Manifest JSON fixtures are built inline in the test file, matching A3's inline `chunkFixture` / `model` fixture pattern — no shipped capability is added (the first capability is Open Decision 1 and blocked to A5/D1, delivery plan §7).

## Consumes Binding

| **Consumes** entry | Existing module / file bound to | How A4 binds to it |
| --- | --- | --- |
| A3 — canonical inference representation (§5.3) | `ai-platform/src/contracts/canonical.ts` (`CanonicalRequest`, `CanonicalResult`, `CanonicalStreamChunk`, `CanonicalError`, `assertNoProviderShapedFieldNames`) | A4 does **not** import or redefine A3's canonical types. The manifest's Output group carries an `output schema ref` (opaque string) and its Prompt-binding group carries `artifact refs` (opaque strings); A4 treats these as string references and adds no canonical-field definition. The "manifest never names a provider or a model" rule (FR-008, §5.1) is the manifest-side analogue of A3's `assertNoProviderShapedFieldNames`; A4 does not call A3's guard — it enforces its own equivalently-named rule on the manifest's Routing group. A3's contract is read, not modified (delivery plan §2.3). |

## Components Touched

| §4 component | What A4 changes | Behaviour added? |
| --- | --- | --- |
| §4.3.4 Capability resolver | Only its **data/contract surface**: the immutable manifest schema and loader that the capability registry (C1) will resolve against. | No. A4 adds the manifest payload + loader + published-version hash check. The resolver **behaviour** — `capability id + requested version` → manifest, version-pin honour, entitlement gating, `capability_unknown` / `capability_retired` / `capability_disabled` distinguishing, kill-switch enforcement — is slice C1 (and B8/A7 for gating) and is explicitly Out of Scope. |

A4 touches exactly one §4 component's contract surface and adds no behaviour to it. No written reason for touching a second component is needed because no second component is touched.

## Files

| Path | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/manifest/index.ts` | Created | FR-001, FR-002, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 (schema, default, conversational rejection, data-not-code, never-names-provider/model, Output/Governance field groups); plus the published-version hash mechanism for FR-002/FR-004 |
| `ai-platform/test/manifest.test.ts` | Created | SC-001, SC-002, SC-003, SC-004, SC-005, SC-006 (all named tests from the spec's Test plan, named `T-A4-01` .. `T-A4-NN` per the A3 test-naming convention) |

No `ai-platform/` capacity manifests or `wrangler.toml` bindings are added — A4 defines no binding and stores nothing (FR-001..010 are schema/loader rules; no FR names a binding or store).

## Test Layout

All named tests from the spec's `### Test plan` live in `ai-platform/test/manifest.test.ts`, in the **Contract tests** layer (§13.5, row "Contract tests … CI, on every change"). The §3.11.1 row A4 layer is "Contract + build", which the §13.5 table realises as the Contract-test layer running in CI. Inline fixture builders (a valid manifest factory plus per-group mutation helpers) supply the inputs, matching A3's inline fixture pattern — no separate fixture directory, no real provider, no live binding.

| Spec Test plan name | Test id | Asserts (FR / SC) |
| --- | --- | --- |
| `manifest_loads_all_ten_groups` | T-A4-01 | FR-001 / SC-001 — a valid manifest declaring all ten §5.1 field groups loads and yields a typed `Manifest`. |
| `manifest_missing_or_malformed_group_<group>` (one per group: Identity, Access, Interaction, Input, Context requirements, Prompt binding, Output, Routing, Economics, Governance) | T-A4-02 .. T-A4-11 | FR-001/FR-003 / SC-002 — omitting or malformed-ing each group makes `load()` throw, naming the offending group. |
| `in_place_edit_of_published_version_fails_build` | T-A4-12 | FR-002/FR-004 / SC-003 — a registry entry whose on-disk manifest's content hash differs from the registry's is rejected by `verifyPublishedRegistry`; the prior hash still verifies. |
| `omitted_interaction_mode_defaults_to_single_shot` | T-A4-13 | FR-005 / SC-004 — a manifest with `interaction_mode` absent resolves to `single_shot`. |
| `conversational_fields_rejected_on_single_shot` | T-A4-14 | FR-006 / SC-005 — a `single_shot` manifest carrying any of max history turns / max context rounds per turn / transcript size limit is rejected. |
| `manifest_is_data_not_code` | T-A4-15 | FR-007 / SC-006 — the manifest contributes no executable pipeline/client entry point; reusing existing keys/policy/rules changes no pipeline wiring (asserted on the module's export surface). |
| `manifest_never_names_provider_or_model` | T-A4-16 | FR-008 / SC-006 — a manifest whose Routing group names a provider or a model identifier is rejected. |
| `interaction_mode_fixed_for_life_of_version` | T-A4-17 | FR-002 / SC-003 (companion) — a loaded `Manifest`'s `interaction_mode` is read-only at the type level and is not mutated by the loader; changing it is a new-version act (the in-place-edit test T-A4-12 covers the enforcement side). |

Coverage additions from §3.10 (every error path the slice can emit, every inherited prohibition, every named boundary) are the four contract-rule tests T-A4-14..T-A4-17 plus the ten per-group rejection tests T-A4-02..T-A4-11. A4 emits no §5.4 taxonomy code — its only failure mode is `load()` / `verifyPublishedRegistry` throwing — so there are no runtime error-code cases to cover (spec §Edge Cases).

## Sequencing

1. **`ai-platform/src/manifest/index.ts`** — define the ten-group schema as data (mirroring A3's `CANONICAL_FIELD_MANIFEST`), the `Manifest` type, internal `validate()`, `load(json)`, `hashManifest(json)`, and `verifyPublishedRegistry(entries, registry)`; the `interaction_mode` default and the conversational-only-field rejection live in `validate` (FR-005, FR-006); the never-names-provider/model check lives in `validate` over the Routing group (FR-008).
2. **`ai-platform/test/manifest.test.ts`** — write the valid-manifest inline factory and per-group mutation helpers first, then the named tests. Tests are written alongside / before the module's matching branches (the loader is exercised through them immediately); no test is written after its implementation. The contract-rule tests (T-A4-13..17) and the registry test (T-A4-12) are added once their counterparts in `index.ts` exist.
3. **Run `npx vitest run test/manifest.test.ts`** — all T-A4-* tests green; the prior band-A suites (`canonical.test.ts`, `taxonomy.test.ts`, `reference.test.ts`, `health.test.ts`, `env-deploys.test.ts`, `trace.test.ts`, `error-body.test.ts`, `log-redaction.test.ts`) remain green (checkpoint rule: every prior suite green, §3.10).
4. **`specs/018-ai-capability-manifest/contracts/manifest-schema.md`** — write the frozen manifest payload shape (the ten field groups, the `interaction_mode` default, the conversational-only rule, the never-names-provider/model rule, the published-version hash mechanism) so C1/C2/C5/C6/E7/H1/H5 bind to an artifact, not to prose.
5. **`specs/018-ai-capability-manifest/quickstart.md`** — fill from `.specify/templates/ai-platform-quickstart-template.md`: what was implemented, files to review (`index.ts`, `manifest.test.ts`), how to run the suite (`npx vitest run test/manifest.test.ts`), how to inspect the frozen schema and the contract artifact. No Manual validation section — CI is the only verification path (template: "Omit this section when CI is the only verification path").

Tests land alongside or before their implementation branches (step 1 and step 2 interleave); no test is written after its implementation. The Documentation artifacts (step 4, step 5) are written only after the suite is green — the plan names them here, the implement phase fills them in.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The three unchecked Constitution boxes are recorded above as structurally inapplicable to a build-time, data-only gateway slice (per the §14 acknowledgement), not as violations.