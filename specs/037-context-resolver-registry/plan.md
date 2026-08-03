# Implementation Plan: Context Resolver registry, first context RPC, and client contract test (E3)

**Branch**: `ai/037-e3-context-resolver-registry` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/037-context-resolver-registry/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

E3 lands the Flutter **Context Resolver** as the §4.1 generic key→resolver registry (key list in, assembled payload or typed failure out; never a capability id; screen-scoped instance cache), the clinic **first context provider** ordinary read RPC returning the A5-published `visit.chief_complaint@v1` shape under caller RLS with no AI knowledge, and the Flutter **client contract suite** that asserts every declared key of every active capability is resolvable (§13.5). It sits in Band E after E2 / C1 (`Needs: E2, C1`) and freezes the Context Contract’s verified client/clinic half before E4’s first surface.

## Technical Context

**Language/Version**: Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`) for the Resolver and Flutter contract suite; PostgreSQL / Supabase SQL for the first context provider RPC (matching existing `public` INVOKER → `auth_internal` SECURITY DEFINER clinic RPCs).

**Primary Dependencies**: Flutter desktop client under `frontend/`; E2 AI Client SDK siblings under `frontend/lib/core/ai/` (Consumes — not modified); C1 discovery wire shape (`DiscoveryResult` / `{ manifests }` body + `ETag`) for the contract suite’s manifest fetch (Consumes — not modified); A5 first-key shape `visit.chief_complaint@v1` / `VISIT_CHIEF_COMPLAINT_V1_SHAPE` (`ai-platform/src/context/index.ts`; frozen artifact `specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`). Clinic data from existing `visit_clinical_notes` (complaint ≤ 10000) under existing visit RLS. Injectable Supabase-read / manifest-source ports for Flutter unit and contract tests (Clarification Q1–Q3 patterns). No Worker source changes, no new pub packages, no schema-validation library (R-20).

**Storage**: No D1 entities (spec Key Entities: not applicable). Clinic: ordinary read over existing visit clinical-notes rows — no new clinic tables, no AI-shaped columns, no prompts/providers/quotas/AI request state (§4.2 Boundary note). Resolver cache is ephemeral instance state on one Resolver per screen, discarded on dispose (Clarification Q1; FR-005).

**Testing**: Flutter unit + SQL / RLS + contract (delivery plan §3.11.5 row E3; §13.5 Client contract tests). Named cases E3-T01–E3-T10 via `flutter test` (Resolver unit + contract suite) and `psql` SQL/RLS scripts (RPC shape + RLS denial + no AI parameter + A5 shape match), joined to CI permanently (delivery plan §3.10). Contract suite feeds C1-shaped active manifests through an injectable manifest source; E3-T10 uses a synthetic/fixture manifest declaring an unregistered key (Clarification Q3). No live Worker required for the Flutter suite (mirrors E2 injectable-port precedent).

**Target Platform**: Flutter Windows desktop client (`frontend/`) and local/clinic Supabase PostgreSQL (`backend/`). AI remains optional and additive; this slice adds no gateway stage.

**Project Type**: Dual-layer slice — Flutter Context Resolver under `frontend/lib/core/ai/` (Clarification Q4) plus one ordinary clinic context-provider RPC under `backend/supabase/migrations/` / `backend/tests/`. Not a Worker slice (`ai-platform/` unchanged).

**Performance Goals**: None beyond ordinary client assembly and one clinic read RPC. E3 adds no Quota DO round trip, no D1 insert, and no R2 object; platform I/O budgets (§6.1, §7.5, §13.6) remain untouched.

**Constraints**: Generic registry only — key list in, payload or typed failure out; no capability id and no capability branching (FR-002, FR-003). Must not decide which keys are needed, send unrequested/invented data, or bypass RLS via a privileged path (FR-004). Cache lifetime ≤ screen; discarded on dispose (FR-005; Clarification Q1). Keys follow `domain.concept@vN`; first RPC returns A5-published shape under caller RLS with no AI-specific parameter or AI platform knowledge (FR-006–FR-010). Contract suite fails on coverage gaps (FR-011, FR-012). No prompt/provider/model identifiers in Flutter (FR-013; R-12 / E1). Closed static registration map in one module (Clarification Q2).

**Scale/Scope**: Two §4 components with an explicit reason (see Components Touched): §4.1 Context Resolver and §4.2 Context provider RPCs. ~six Dart library/test files under `frontend/lib|test/.../ai/`, one migration, one SQL test suite (+ runner wiring), two contract artifacts, one quickstart. Thirteen FRs. Ten named tests. Roughly 18–22 tasks — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — context
      assembled on the desktop client from ordinary clinic reads under existing branch-scoped
      RLS; no clinic-operated AI infrastructure (§4.1; §4.2; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one Flutter registry module family and one
      ordinary Supabase read RPC; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — Resolver
      and contract suite in `frontend/`; context provider RPC in `backend/`; `ai-platform/`
      unchanged. Gateway remains the additive, non-primary §14 component (no domain logic, no
      business data, no write path into Supabase); this slice does not add or change Worker code,
      so the §14 acknowledgement is recorded as inherited boundary, not as a gateway change.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — first context RPC is an
      ordinary read under caller session/RLS; Resolver must not use a privileged path (FR-004,
      FR-008).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — resolution under caller permissions; out-of-scope
      rows denied by RLS (E3-T06); soft-delete and clinic audit unchanged; no AI request state in
      clinic DB (§4.2 Boundary note).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — Resolver/RPC are
      context assembly only; provisional/degraded UX is E4 (Out of Scope); no auto-commit; platform
      unavailability does not block clinical reads of the same ordinary data.

## Project Structure

### Documentation (this feature)

```text
specs/037-context-resolver-registry/
├── plan.md                         # This file
├── spec.md                         # /ai-platform-specify + /ai-platform-clarify output (authoritative)
├── contracts/
│   ├── context-resolver.md         # Frozen: key-list API, assembled payload, typed unknown-key failure
│   └── context-provider-rpc.md     # Frozen: first ordinary read RPC for visit.chief_complaint@v1
└── quickstart.md                   # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — E3 defines no D1 (or other) entities (spec Key Entities: "Not applicable").

`research.md` is **not** produced — the research is `docs/architecture/17-ai-platform.md`.

`contracts/` is produced because two **Freezes** entries have wire shapes later slices’ **Consumes** must bind to: the Resolver key-list → assembled payload API, and the first context provider RPC return shape. Screen-scoped cache lifetime and the client contract suite itself are behavioural / CI Freezes without new wire shapes beyond those two.

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — E3 row of the delivery plan (§3.6) and §4.1 / §5.2 / §4.2 / §13.5; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — Context Resolver registry + registration map; first `visit.chief_complaint@v1` context provider RPC; Flutter client contract suite.
- **§3 Files to review** — this slice’s `frontend/lib/core/ai/context_*.dart`, `frontend/test/unit/core/ai/context_*.dart`, the new backend migration, and `backend/tests/context_provider_rpc.sql` only.
- **§5 Run the automated suite** — slice-only `flutter test` against this slice’s test files and `psql -f backend/tests/context_provider_rpc.sql` (or the AI-platform trust runner extension); no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open the registration map, Resolver API, RPC migration, and frozen `contracts/` artifacts; confirm E1 guard still covers new Flutter AI paths.
- Manual validation omitted — CI / `flutter test` / SQL suite is the verification path (E3 exposes no user-visible surface; E4 does).

### Source Code (repository root)

```text
frontend/
├── lib/
│   └── core/
│       └── ai/                                      # EXISTING E2 folder (Clarification Q4 — siblings)
│           ├── ai_client_sdk.dart                   # UNCHANGED — Consumes E2
│           ├── ports.dart                           # UNCHANGED — Consumes E2
│           ├── taxonomy.dart                        # UNCHANGED — Consumes E2
│           ├── sse_events.dart                      # UNCHANGED — Consumes E2
│           ├── context_resolver.dart                # NEW — key-list API, instance cache, typed failure
│           ├── context_registration.dart            # NEW — closed static map key → resolver fn
│           └── context_provider_port.dart           # NEW — injectable clinic-read port for resolvers
├── test/
│   └── unit/
│       └── core/
│           └── ai/
│               ├── fakes.dart                       # EXTEND — fake clinic-read + manifest source
│               ├── context_resolver_test.dart       # NEW — E3-T01..T04
│               └── context_contract_test.dart       # NEW — E3-T09..T10 (C1-shaped manifests; T10 fixture)
└── tool/
    └── architecture_guard/                          # UNCHANGED — Consumes E1 / R-12 (FR-013)

backend/
├── supabase/
│   └── migrations/
│       └── 20260802120000_context_provider_chief_complaint.sql  # NEW — ordinary read RPC
└── tests/
    ├── context_provider_rpc.sql                     # NEW — E3-T05..T08
    └── run_ai_platform_trust_tests.sh               # MODIFIED — append this slice’s SQL suite

# ai-platform/ — UNCHANGED (Consumes A5 shape + C1 discovery only; no rewrite)
```

**Structure Decision**: Resolver modules live as siblings of the E2 SDK under `frontend/lib/core/ai/` (Clarification Q4). Registration is one closed static map module (Clarification Q2). One Resolver instance per screen owns the cache as instance state (Clarification Q1). The first context provider is a thin ordinary clinic read RPC over existing `visit_clinical_notes` / visit RLS, returning the A5 wire shape — prefer reuse of existing storage and RLS rather than inventing a privileged AI path (§4.2; FR-009). Tests mirror E2’s injectable-fake layout. No `ai-platform/` path is modified.

## Consumes Binding

E3 has `Needs: E2, C1` (delivery plan §3.6). It also Consumes **A5 via §5.2 / C1** (context key vocabulary and first key shape). Changing any is out of scope (delivery plan §2.3).

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| **E2 — AI Client SDK** (§4.1 AI Client SDK; §5.5; §5.4) | `frontend/lib/core/ai/ai_client_sdk.dart`, `ports.dart`, `sse_events.dart`, `taxonomy.dart` (transport-only acquire AAT, submit, stream, cancel, last-N request references). E3 adds Context Resolver **siblings** under the same folder; it does not reinterpret transport, idempotency, SSE consumption, terminal-error retry, or embed those concerns into the Resolver. |
| **C1 — Capability registry, resolver stage, and discovery endpoint** (§4.3.4, §5.1, §5.5 discovery, §5.2 Discovery) | Frozen artifact `specs/025-capability-resolver-discovery/contracts/capability-registry.md`; implementation `ai-platform/src/capability/index.ts` (`discover`, `DiscoveryResult`, `buildDiscoveryResponse` — body `{ manifests }`, `ETag` header, active+granted filtering). E3’s client contract suite fetches active manifests in that wire shape via an injectable manifest source (fixtures representing the live active set in CI; Clarification Q3 for the unsatisfiable-key case) and asserts Resolver coverage of every declared context key. E3 does not redefine discovery, capability resolution, or manifest schema, and does not modify C1 modules. |
| **A5 via §5.2 / C1 — Context key vocabulary and first key shape** (§5.2; delivery plan §3.2 A5) | Frozen artifact `specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`; implementation `ai-platform/src/context/index.ts` — `VISIT_CHIEF_COMPLAINT_V1` (`visit.chief_complaint@v1`), `VISIT_CHIEF_COMPLAINT_V1_SHAPE` (`visit_id` uuid required; `complaint` string maxLength 10000; `recorded_at` optional iso8601), `validateKey` / `validatePayload`. E3’s first context provider RPC returns that shape and the contract/unit suites resolve declared keys against it; E3 does not rename keys, change shapes, or publish a new key version. |

No Consumes entry lacks an existing implementation. None is modified (delivery plan §2.3). Stop condition 2 is not triggered.

## Components Touched

Two §4 components, with explicit reason:

1. **§4.1 Context Resolver** — generic key→resolver registry, key-list API, screen-scoped cache, client contract suite placement (§13.5 Client contract tests run in the Flutter suite against the Resolver).
2. **§4.2 Context provider RPCs** — first ordinary clinic read RPC returning the A5-published first-key shape under caller RLS, with no AI-specific parameter or AI platform knowledge.

**Reason for two components:** Delivery plan §3.6 row E3 Done when and this slice’s Freezes jointly require (a) the Flutter registry, (b) the first ordinary clinic context RPC, and (c) the client contract suite that verifies coverage across them. Architecture places context *how* on the client (§4.1) and context *payload supply* on ordinary Supabase RPCs (§4.2); the Context Contract is a verified interface spanning both sides (§3.4.1, §13.5). Touching both is the minimal way to freeze what E3’s Canonical cell names; it is not scope creep into E2/E4/C2/H3.

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.1 Context Resolver | **Created** | This slice’s Flutter deliverable (§4.1 table; delivery plan §3.6). |
| §4.1 AI Client SDK | **Not touched** | Consumes E2 only |
| §4.1 AI Feature Surfaces | **Not touched** | E4 |
| §4.1 Conversation store | **Not touched** | H band |
| §4.2 Context provider RPCs | **Created (first RPC)** | Ordinary read for `visit.chief_complaint@v1` (§4.2; Done when) |
| §4.2 Installation keystore / AI token issuer / acceptance / availability | **Not touched** | B1 / F2 / E4 |
| §4.3.* gateway stages | **Not touched** | Out of scope; Consumes C1/A5 only |

Stop condition 5 (multi-component without reason) is not triggered — reason recorded above. Task count stays under ~25.

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `frontend/lib/core/ai/context_provider_port.dart` | FR-001, FR-008 | NEW — injectable clinic-read port used by registered resolver functions (production: Supabase RPC; tests: in-memory fake). |
| `frontend/lib/core/ai/context_registration.dart` | FR-001, FR-002, FR-006 | NEW — closed static map of context key → resolver function in one registration module (Clarification Q2); registers `visit.chief_complaint@v1` against the first context provider RPC. |
| `frontend/lib/core/ai/context_resolver.dart` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-013 | NEW — Context Resolver: `resolve(List<String> keys)` → assembled payload or typed failure; no capability-id parameter or branching; instance-state cache discarded with the instance (Clarification Q1); never invents data for unknown keys; no prompts/providers/models. |
| `frontend/test/unit/core/ai/fakes.dart` | FR-001–FR-012 (test support) | EXTEND — fake clinic-read port and injectable active-manifest source returning C1-shaped `{ manifests }` (Clarification Q3). |
| `frontend/test/unit/core/ai/context_resolver_test.dart` | FR-001–FR-007, FR-013; E3-T01–E3-T04 | NEW — Flutter unit suite for Resolver happy path, unknown-key typed failure, no capability id, screen-scoped cache discard. |
| `frontend/test/unit/core/ai/context_contract_test.dart` | FR-011, FR-012; E3-T09–E3-T10 | NEW — client contract suite: every declared key of every active manifest resolvable; synthetic unregistered-key manifest fails the suite (Clarification Q3). |
| `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql` | FR-008, FR-009, FR-010 | NEW — ordinary `auth_internal` + `public` read RPC returning `{ visit_id, complaint, recorded_at }` for `visit.chief_complaint@v1` under caller RLS; no AI-specific parameters; no prompts/providers/quotas/AI request state. |
| `backend/tests/context_provider_rpc.sql` | FR-008–FR-010; E3-T05–E3-T08 | NEW — SQL/RLS suite: declared shape, RLS out-of-scope denial, no AI-specific parameter, shape matches A5 published key. |
| `backend/tests/run_ai_platform_trust_tests.sh` | — (verification wiring) | MODIFIED — append `context_provider_rpc.sql` so the suite joins CI permanently (delivery plan §3.10). |
| `specs/037-context-resolver-registry/contracts/context-resolver.md` | Freezes — key-list API / payload | NEW — frozen wire/behaviour contract for later Consumes (E4, H3, J2). |
| `specs/037-context-resolver-registry/contracts/context-provider-rpc.md` | Freezes — first context RPC | NEW — frozen RPC return shape binding to A5. |
| `specs/037-context-resolver-registry/quickstart.md` | — | NEW — written during the implement-phase Documentation task (sections named in Project Structure → Documentation). |

Every file traces to an `FR-###` (or Freezes / deferred Documentation). No file is created for an unstated requirement. No Consumes module is rewritten. No `ai-platform/` file is touched.

## Test Layout

The spec’s Test plan names ten tests at layers **Flutter unit + SQL / RLS + contract** (delivery plan §3.11.5 row E3). Mapping to §13.5: Flutter unit cases exercise the Resolver; SQL/RLS cases exercise the clinic RPC; Client contract tests exercise coverage against fetched (C1-shaped) manifests. Tests join CI permanently (delivery plan §3.10).

| Test ID | Named test | Spec layer | Where it lives | Asserts |
| --- | --- | --- | --- | --- |
| E3-T01 | `resolver_key_list_assembles_payload` | Flutter unit | `context_resolver_test.dart` | Key list resolves to a payload conforming to declared shapes (§4.1; §5.2) |
| E3-T02 | `resolver_unknown_key_typed_failure` | Flutter unit | `context_resolver_test.dart` | Unknown key → typed failure; no partial success payload |
| E3-T03 | `resolver_api_exposes_no_capability_id` | Flutter unit | `context_resolver_test.dart` | Public API has no capability-id parameter and no capability branching |
| E3-T04 | `resolver_cache_screen_scoped_discarded_on_dispose` | Flutter unit | `context_resolver_test.dart` | Cache is instance/screen-scoped; discarded when the instance is disposed (Clarification Q1) |
| E3-T05 | `context_rpc_returns_declared_shape` | SQL / RLS | `context_provider_rpc.sql` | RPC returns `visit.chief_complaint@v1` declared shape |
| E3-T06 | `context_rpc_rls_denies_out_of_scope` | SQL / RLS | `context_provider_rpc.sql` | RLS denies out-of-scope rows |
| E3-T07 | `context_rpc_no_ai_specific_parameter` | SQL / RLS | `context_provider_rpc.sql` | RPC signature/body has no AI-specific parameter |
| E3-T08 | `context_rpc_shape_matches_a5_published_key` | SQL / RLS | `context_provider_rpc.sql` | Returned shape matches A5 `VISIT_CHIEF_COMPLAINT_V1_SHAPE` |
| E3-T09 | `contract_every_active_manifest_key_resolvable` | Contract (§13.5 Client contract tests) | `context_contract_test.dart` | Every declared key of every active (C1-shaped) manifest is resolvable |
| E3-T10 | `contract_manifest_unknown_key_fails_suite` | Contract (§13.5 Client contract tests) | `context_contract_test.dart` | Synthetic/fixture manifest with unregistered key fails the suite (Clarification Q3) |

Every named test places in a §13.5 / §3.11.5 layer — stop condition 3 not triggered. Coverage matches delivery plan §3.10 / spec Coverage paragraph (happy paths, unknown-key typed failure, RLS denial, no capability id, screen-scoped cache, ordinary RPC with no AI knowledge, contract fail-closed).

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this slice:

1. **Frozen contracts first** — write `contracts/context-resolver.md` and `contracts/context-provider-rpc.md` so later slices (E4, H3, J2) bind to artifacts, not prose (delivery plan DP-4).
2. **Clinic-read port + fakes** — land `context_provider_port.dart` and extend `fakes.dart` so Resolver unit tests can run without a network.
3. **Registration map + first key resolver (Clarification Q2; FR-001, FR-002, FR-006)** — land `context_registration.dart` registering `visit.chief_complaint@v1`.
4. **Resolver API + cache (FR-003–FR-005, FR-007; E3-T01–E3-T04)** — land `context_resolver.dart` with key-list API, typed unknown-key failure, instance cache; prove T01–T04 alongside (Clarification Q1).
5. **First context provider RPC (FR-008–FR-010; E3-T05–E3-T08)** — land the migration and `context_provider_rpc.sql`; prove shape, RLS denial, no AI parameter, A5 match.
6. **Client contract suite (FR-011, FR-012; E3-T09–E3-T10)** — land `context_contract_test.dart` with injectable C1-shaped active manifests; T10 uses synthetic unregistered-key fixture (Clarification Q3).
7. **CI wiring** — append SQL suite to `run_ai_platform_trust_tests.sh`; ensure Flutter tests join existing frontend CI.
8. **Documentation** — fill `quickstart.md` after implementation and verification (sections named above).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
