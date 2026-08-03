# Implementation Plan: Capability registry, resolver stage, and discovery endpoint (C1)

**Branch**: `ai/025-c1-capability-resolver-discovery` | **Date**: 2026-08-01 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/025-capability-resolver-discovery/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

C1 builds the pipeline's stage-5 capability resolver and the §5.5 capability-discovery surface: a registry-backed lookup that turns `capability id + requested version` into exactly one immutable manifest honouring the client's pin, distinguishing `capability_unknown` / `capability_retired` / `capability_disabled`, and a discovery read that returns the active, granted manifests for an installation/plan, cacheable and revalidated by version or etag. It sits immediately after A4 (froze the manifest schema/loader) and B3 (froze the immutable `Principal` and the in-isolate config-cache surface); it is the unlock for parallel work in bands D and E, which both need a resolved manifest (`17b-ai-platform-delivery-plan.md` §3.4).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), `target: ES2022`, strict, `@cloudflare/workers-types` — matching A4/B3.

**Primary Dependencies**: the platform's existing `ai-platform/src/manifest/` (A4 — `load`, `Manifest`, `hashManifest`, `MANIFEST_FIELD_GROUPS`), `ai-platform/src/config-cache/` (A5 — `ConfigCache`, `loadConfig`, `D1Reader`, `ConfigCacheMissError`, `ConfigEntityKind`), `ai-platform/src/identity/` (B3 — `Principal`), and `ai-platform/src/errors.ts` (A2 — `TaxonomyCode`, `liveHttpStatusForCode`). No new dependency is introduced — the registry is a `Map`, the etag reuses A4's `hashManifest`, and adding a schema-validation or HTTP-framework library would be a mechanism no cited section names (R-20).

**Storage**: Reads only — kill-switch rows (`loadConfig("kill_switches", …)`), entitlement rows (`loadConfig("entitlements", …)`), and grant rows (`loadConfig("grants", …)`), all from the platform D1 frozen by A5's migration `20260731120000_platform_schema.sql`, through A5's in-isolate config cache (§6.1 stage 5 — bundled artifacts for the manifest; config cache for flags). C1 defines **no** D1 entity and runs **no** migration (spec `### Key Entities`: "Not applicable for D1"). The capability registry itself is bundled manifests loaded at build time via A4's `load()` (§6.1 stage 5 "Bundled artifacts"); the first real manifest ships with D1 (Open Decision 1), so the shipped registry is empty until then and is proven by inline fixtures, exactly as A4 shipped a loader with no manifests.

**Testing**: `npx vitest run` for pure-unit cases via `vitest.config.ts` (in-memory registry + fixture manifests + injected `ConfigCache`); `npx vitest run --config vitest.workers.config.ts` for the three cases that read kill-switch / entitlement / grant rows against the real Miniflare D1 binding B2/B3 already wired (`d1Databases: ["DB"]`, seeded from the A5 migration). Spy scaffolding is A5's `ReaderSpy` shape, reused where an absence is asserted.

**Target Platform**: the `ai-platform/` Cloudflare Worker at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). No Worker request fetch is exercised by this slice — `resolve()` and `discover()` are stage/ surface functions tested directly, mirroring how B3 tested the guard functions without wiring `worker.ts`.

**Project Type**: Additive, non-primary AI gateway component (§14 acknowledgement) — contract + stage logic only, no domain logic, no business data, no write path into Supabase, always optional.

**Performance Goals**: Stage 5 completes from the bundled registry and the warm config cache with no D1 read (§6.1 stage 5; spec Edge Cases "no D1 read on a warm isolate"). The cold-isolate single-D1-read invariant is A5's, already pinned by A5's `T-A5-17`; C1 does not re-prove it.

**Constraints**: A manifest is immutable per version and the manifest handed downstream or to a discovery caller must not be mutable by that caller (§5.1) — the manifest is returned as A4's already-`Proxy`-frozen `Manifest`, re-frozen at the registry boundary. Only an exact requested version resolves; the resolver honours the pin rather than picking a "compatible" version (§4.3.4). A guard rejection at stage 5 produces no `ai_request` row (§7.5, §6.2) — that invariant is C3's and is consumed here, not re-built. No per-request server-side state (§4.4, §9.7). No deprecation overlap window or successor announcement — that is J1; C1 recognises `deprecated` and still *serves* it (resolve), but discovery returns `active`-lifecycle manifests (§5.5 "active manifests"; the spec test "only granted and active manifests returned"). No second Quota DO round trip and no R2 object — C1 performs neither.

**Scale/Scope**: One §4 component (§4.3.4 capability resolver — the discovery surface of §5.5 is a contract realisation of the same component, not a second §4 component), one module directory, one test file, one contract artifact, one quickstart. ~10–12 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — C1 is a
      registry/resolve stage shared by every clinic; it introduces no enterprise-specific concept.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — C1 adds a `Map`-backed registry, a resolve
      function, and a discovery read; no new service, queue, or orchestration.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — C1 lives
      wholly in `ai-platform/` and touches neither `frontend/` nor `backend/`.
- [ ] (intentionally unchecked — see note) Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — N/A: C1 defines no stored
      domain data, no writes, no RLS, no RPC. This row concerns the Supabase/PostgreSQL layer and
      does not apply to a gateway resolution slice. Per the §14 acknowledgement registered for the
      gateway, the Worker is an additive, non-primary component with **no domain logic, no business
      data, and no write path into Supabase**; if it vanishes, no business rule is lost.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — C1 consumes the already-authenticated, immutable
      `Principal` from B3 (§4.3.2) and scopes discovery to the principal's installation via the
      config-cache entitlement/grant rows; it performs no authentication and writes nothing to
      audit (the journal is C3). A stage-5 rejection is a guard rejection and is not journaled
      (§7.5).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — C1 is strictly
      additive; a killed capability degrades to `capability_disabled` (503, a
      temporary-unavailable state) and a retired capability to `capability_retired` so the client
      can prompt for an update; the gateway's unavailability never blocks clinical work, which
      continues without AI affordances (§14 "V"; A11). Hard-locking never occurs here.

The one unchecked box is the Supabase/PostgreSQL row that is structurally inapplicable to a read-only gateway resolution slice. It is not a constitution violation; it is recorded here rather than silently dropped, per the §14 acknowledgement that the gateway is non-primary, additive, and holds no domain truth.

## Project Structure

### Documentation (this feature)

```text
specs/025-capability-resolver-discovery/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify output (authoritative)
├── contracts/
│   └── capability-registry.md  # Frozen: ResolveResult + DiscoveryResult + registry key format + immutability
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — C1 defines no D1 entity (spec `### Key Entities`: "Not applicable for D1"). The registry is bundled manifests, not a D1 table; the config-cache reads go through A5's frozen surface.

`research.md` is **never** produced on this platform — the research is `docs/architecture/17-ai-platform.md`; redoing it is how architecture drift starts.

`contracts/` is produced because three **Freezes** entries have wire shapes a later slice's **Consumes** must bind to (C2 consumes the resolved manifest for context validation; D1 consumes it for prompt composition; E3 fetches discovery and runs its contract test against live manifests). The plan names the artifact; the implement phase writes it.

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — C1 row of the delivery plan (§3.4) and the §4.3.4 / §5.1 / §6.1-stage-5 / §5.5 / §5.2 sections; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — the `src/capability/` module: the registry, `resolve()`, `discover()`, the etag/revalidation helper.
- **§3 Files to review** — this slice's `ai-platform/src/capability/index.ts` and `ai-platform/test/capability.test.ts`.
- **§5 Run the automated suite** — `npx vitest run test/capability.test.ts` (unit cases) and `npx vitest run --config vitest.workers.config.ts test/capability.test.ts` (the three integration cases), slice-only.
- **§6 Inspect the changes** — grep for the three resolver error codes, read the frozen `contracts/capability-registry.md` artifact.
- No §7 — CI is the only verification path (C1 exposes no user-facing behaviour beyond the suite; `worker.ts` is not modified, so there is no live endpoint to `curl`).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── capability/        # NEW (this slice — FR-001..FR-014)
│   │   └── index.ts       # CapabilityRegistry, resolve(), discover(), buildDiscoveryResponse(), etag
│   ├── manifest/          # UNCHANGED (consumed from A4 — load, Manifest, hashManifest)
│   ├── config-cache/      # UNCHANGED (consumed from A5 — loadConfig, ConfigCache, D1Reader)
│   ├── identity/          # UNCHANGED (consumed from B3 — Principal)
│   ├── errors.ts          # UNCHANGED (consumed from A2 — TaxonomyCode, liveHttpStatusForCode)
│   └── worker.ts          # UNCHANGED — no route wired by this slice (see Components Touched)
├── test/
│   └── capability.test.ts # NEW — T-C1-* unit + integration tests (inline fixture manifests)
├── vitest.config.ts       # MODIFIED — include test/capability.test.ts (unit cases)
└── vitest.workers.config.ts  # MODIFIED — include the three integration cases (real D1)
```

`worker.ts` is unchanged because C1 freezes the resolver and discovery contracts in code but does not wire them into the request pipeline — matching B3's precedent (the guard functions exist; their pipeline wiring is a later orchestrator slice). C1's tests exercise `resolve()` and `discover()` directly via their exported functions, mirroring how B3 tested `evaluateEntitlement` without a Worker fetch. The discovery route attachment (a `GET` against the §5.5 surface) belongs to the same later pipeline-orchestrator slice that wires the guard stages. This keeps C1 to exactly one §4 component (§4.3.4) and avoids reworking §4.3.1 (the adapter owns the submit stream).

**Structure Decision**: One module directory `ai-platform/src/capability/` exporting `resolve()` and `discover()` (Clarification Q1), the established `ai-platform/src/<concern>/index.ts` pattern (A4 `src/manifest/`, B3 `src/identity/` + `src/entitlement/` + `src/rate-limit/`). Inline manifest fixtures in the test file reuse A4's valid-manifest factory shape — no separate fixture directory, no shipped capability (Open Decision 1 is blocked to D1, delivery plan §7), no live binding.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How C1 binds to it |
| --- | --- | --- |
| **A4** — capability manifest schema, loader, immutability, `interaction_mode` default (§5.1) | `ai-platform/src/manifest/index.ts` — `load(json)`, `Manifest` type, `hashManifest(json)`, `MANIFEST_FIELD_GROUPS`. Frozen artifact: `specs/018-ai-capability-manifest/contracts/manifest-schema.md`. | C1 imports `load` and the `Manifest` type. The registry stores `Manifest` objects produced by `load()`; `resolve()` returns the same `Manifest` A4 already freezes with a `Proxy` (so the "manifest handed downstream cannot be mutated" rule is inherited, not re-implemented). The never-names-provider/model rule (FR-009) is enforced by A4's `load()` at registry-build time; C1 adds no separate check. A4's contract is read, not modified (delivery plan §2.3). |
| **B3** — immutable request `Principal` produced by identity (§4.3.2) | `ai-platform/src/identity/index.ts` — `Principal` interface. Frozen artifact: `specs/023-guard-stages/contracts/request-principal.md` (§5 names C1 as a consumer of `installationId`, `scopes`). | C1's `resolve()` and `discover()` take the `Principal` as a read-only argument and read `principal.installationId` for installation-scoped grant filtering. C1 never mutates the principal and adds no field to it (the no-rework rule). |
| **B3 / A5** — in-isolate config-cache surface for kill-switch scopes and entitlement (§4.3.4, §6.1 stage 5) | `ai-platform/src/config-cache/index.ts` — `ConfigCache`, `loadConfig(cache, reader, kind, key)`, `D1Reader`, `ConfigCacheMissError`, `ConfigEntityKind` (`"kill_switches"`, `"entitlements"`, `"grants"`). Frozen artifact: `specs/019-ai-context-keys-d1-config/contracts/config-cache.md`. | C1 calls `loadConfig("kill_switches", …)` for the four kill-switch scopes at resolve time (FR-005) and `loadConfig("entitlements", …)` / `loadConfig("grants", …)` to filter discovery (FR-002, FR-012). It consumes the **surface**; it does **not** import or call B3's `evaluateEntitlement` (that function also runs AI-enablement / plan-tier / grant checks, which are stage-3 entitlement concerns, not stage-5 resolve — pulling them in would be rework and would cross stages). The warm-isolate no-D1-read invariant is A5/B3's and is not re-proven by C1. |
| **A6** — protocol adapter's parsing of the version-pin header and normative HTTP-status mapping (§5.4) | `ai-platform/src/adapter.ts` — `AdapterStreamContext.headers.capabilityVersion`. `ai-platform/src/errors.ts` — `liveHttpStatusForCode`. | C1 emits the three taxonomy codes (`capability_unknown`, `capability_retired`, `capability_disabled`); it does not re-implement their HTTP translation, which stays the adapter's (A6 / A2 `liveHttpStatusForCode`). C1 is agnostic to the header-parse shape — it receives the requested version as a string argument. No adapter file is modified. |

No consumed entry lacks an implementation. None is modified (delivery plan §2.3).

## Components Touched

| §4 component | What C1 changes | Behaviour added? |
| --- | --- | --- |
| §4.3.4 Capability resolver | **Created** — the registry-backed `resolve()` (stage 5) and the `discover()` read of §5.5. Resolves `(capability id, version)` → immutable `Manifest`; honours the version pin; distinguishes `capability_unknown` / `capability_retired` / `capability_disabled`; serves `deprecated`; filters discovery to active + granted; etag/version revalidation. | Yes — this is C1's primary component. The kill-switch *evaluation logic* B3 built in `src/entitlement/` is a library function whose stage assignment B3 deliberately left unwired (`worker.ts` unchanged); C1's resolver is where §4.3.4 places kill-switch enforcement ("here — the earliest point where a capability is identified and the last point before any real work happens") and where §6.1 stage 5 places the `capability_disabled` code. C1 reads kill switches from the consumed config-cache surface; it does not rewrite B3's `evaluateEntitlement`. |
| §4.3.1, §4.3.5–§4.3.11, §4.4, §4.5 | **Not touched** | Consumed unchanged (A6 adapter parses the version header; C3 owns the journal and the no-row-on-guard-rejection invariant) or out of scope (C2 context validator, D1 prompt composer). |

C1 touches exactly one §4 component. No written reason for touching a second component is needed because no second component is touched.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/capability/index.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014 — `CapabilityRegistry` (the `${capabilityId}@${version}` → immutable `Manifest` map built from bundled manifests via A4 `load()`), `resolve(principal, capabilityId, version, cache, reader)` returning `{ok, manifest}` or `{ok:false, code}`, `discover(principal, cache, reader)` returning the active+granted `Manifest[]` plus an etag, `buildDiscoveryResponse(request, manifestList, etag)` returning a `200` or `304`, and the etag helper (hash over the granted+active manifest set, reusing A4 `hashManifest` for stability). |
| `ai-platform/test/capability.test.ts` | Created | SC-001, SC-002, SC-003, SC-004, SC-005, SC-006 (all ten named tests from the spec's `### Test plan`, named `T-C1-01` .. `T-C1-10` per the A-series test-naming convention) |
| `ai-platform/vitest.config.ts` | Modified | — `include` adds `test/capability.test.ts` for the seven unit cases. |
| `ai-platform/vitest.workers.config.ts` | Modified | — `include` adds the three integration cases that read kill-switch / entitlement / grant rows against the real Miniflare D1 binding (B2/B3 harness: `d1Databases: ["DB"]`, seeded from the A5 migration). |
| `specs/025-capability-resolver-discovery/contracts/capability-registry.md` | Created | (freezes the `ResolveResult` discriminated union, the `DiscoveryResult` shape + etag semantics, the `${capabilityId}@${version}` registry key format, and the resolved-manifest immutability guarantee, from FR-001/FR-008/FR-013) so C2/D1/E3 consume a contract, not prose. |
| `specs/025-capability-resolver-discovery/quickstart.md` | Created | — written during the implement-phase Documentation task (sections named in Project Structure → Documentation). Not traced to an FR (template-mandated review surface). |

Every code/contract file traces to an `FR-###`. No file is created for an unstated requirement. `worker.ts` and the consumed modules (`manifest/`, `config-cache/`, `identity/`, `errors.ts`, `adapter.ts`) are unchanged.

## Test Layout

The spec's `### Test plan` names ten tests at the §13.5 layers "Pipeline tests" and "Contract tests" (the §3.11.3 row C1 layer "Unit + integration" realised as those two §13.5 rows). Per Clarification Q1 all ten live in one file `ai-platform/test/capability.test.ts`. The split between the two vitest configs mirrors B3: pure resolve / etag / immutability cases that need no D1 run under `vitest.config.ts` against an in-memory registry + `ConfigCache` seeded in-test; the three cases that read kill-switch / entitlement / grant rows run under `vitest.workers.config.ts` against the real Miniflare D1 seeded from the A5 migration.

| Spec Test plan name | Test id | §13.5 layer | Config | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `resolver_exact_pin_resolves` | T-C1-01 | Pipeline tests | `vitest.config.ts` | FR-001, FR-008 / SC-001 — fixture manifest registered at `clinic.test@1.0.0`; `resolve()` with that exact version returns one immutable `Manifest`; a different requested version does not satisfy the pin (returns `capability_unknown`). |
| `resolver_unknown_capability` | T-C1-02 | Pipeline tests | `vitest.config.ts` | FR-003, FR-010 / SC-002 — `resolve()` for a capability id not in the registry returns `{ok:false, code:"capability_unknown"}`. |
| `resolver_retired_rejected` | T-C1-03 | Pipeline tests | `vitest.config.ts` | FR-004, FR-010 / SC-002 — a fixture manifest with `Identity.lifecycleState:"retired"` returns `{ok:false, code:"capability_retired"}`. |
| `resolver_killed_capability_disabled` | T-C1-04 | Pipeline tests | `vitest.workers.config.ts` | FR-005, FR-006, FR-010 / SC-002 — a seeded active `kill_switches` row for one of the four scopes (global / `capability:<id>` / `installation:<id>` / provider) makes `resolve()` return `{ok:false, code:"capability_disabled"}`, read through `loadConfig("kill_switches", …)` against real D1. |
| `resolver_deprecated_serves` | T-C1-05 | Pipeline tests | `vitest.config.ts` | FR-007 / SC-003 — a fixture manifest with `lifecycleState:"deprecated"` is **not** rejected; `resolve()` returns its `Manifest`. |
| `resolver_manifest_immutable` | T-C1-06 | Contract tests | `vitest.config.ts` | FR-008 / SC-004 — the `Manifest` returned by `resolve()` cannot be mutated by the caller (the A4 `Proxy` freeze holds; a write no-ops and a subsequent reader sees the original fields). |
| `discovery_only_granted_active` | T-C1-07 | Pipeline tests | `vitest.workers.config.ts` | FR-011, FR-012 / SC-005 — discovery for a principal seeded with an `entitlements.allowed_capabilities` list and `grants` rows returns only the granted, `active`-lifecycle manifests; a `retired`/`deprecated` one and an un-granted one are absent. |
| `discovery_etag_not_modified` | T-C1-08 | Contract tests | `vitest.config.ts` | FR-013 / SC-006 — `buildDiscoveryResponse()` with an `If-None-Match` equal to the computed etag returns `304`; the manifest list is not re-serialised. |
| `discovery_etag_changes` | T-C1-09 | Contract tests | `vitest.config.ts` | FR-013 / SC-006 — changing one fixture manifest in the granted+active set changes the computed etag (reusing A4 `hashManifest` over the set). |
| `discovery_entitlement_gated_absent` | T-C1-10 | Pipeline tests | `vitest.workers.config.ts` | FR-002, FR-012 / SC-005 — a capability whose manifest `Access.minimumPlanTier` exceeds the seeded `entitlements.plan` (or which has no grant row) is absent from the discovery result for that installation. |

Coverage additions from §3.10: every error code the slice can emit is covered one-for-one — `capability_unknown` (T-C1-02), `capability_retired` (T-C1-03), `capability_disabled` (T-C1-04); the version-pin boundary (T-C1-01, the different-version half); the deprecation-vs-retirement branch (T-C1-05 vs T-C1-03); the no-`ai_request`-row-on-guard-rejection prohibition is C3's invariant and is consumed, not re-asserted, by C1 (spec Edge Cases). C1 emits **only** those three taxonomy codes — `forbidden_capability` / `installation_suspended` are B3's stage-3 codes and are out of scope here; an ineligible capability is filtered out of discovery (T-C1-10) rather than emitted as an error, per the spec Edge Cases.

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2; the test file plus the diff is the review artifact). Within this slice:

1. **Registry + resolve happy path (FR-001, FR-008, FR-009, FR-010)** — `T-C1-01`, `T-C1-05`, `T-C1-06` first (unit, in-memory registry, fixture manifests built with A4's factory shape). They pin the immutable-manifest contract and the deprecated-serves branch before any rejection path is added.
2. **Resolve rejection paths (FR-003, FR-004, FR-010)** — `T-C1-02`, `T-C1-03` next (unit): `capability_unknown` and `capability_retired` against the in-memory registry; then `T-C1-04` (integration) wires `loadConfig("kill_switches", …)` against the real D1 for `capability_disabled`.
3. **Discovery + etag (FR-011, FR-012, FR-013, FR-014)** — `T-C1-08`, `T-C1-09` (unit, etag over in-memory fixture set) first to fix the cache-revalidation contract; then `T-C1-07`, `T-C1-10` (integration) against the real D1 seeded with `entitlements` / `grants` rows to fix the granted + active + entitlement-gated filtering.
4. **Contract** — `contracts/capability-registry.md` is written alongside the module (it freezes what `resolve()` returns and what `discover()` emits), so C2/D1/E3 can bind during their own plan phase.
5. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task, after the slice's tests pass.

Tests land alongside or before their implementation branches (steps 1–3 interleave); no test is written after its implementation. The Documentation artifacts (steps 4–5) are written only after the suite is green — the plan names them here, the implement phase fills them in.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The one unchecked Constitution box is recorded above as structurally inapplicable to a read-only gateway resolution slice (per the §14 acknowledgement), not as a violation.