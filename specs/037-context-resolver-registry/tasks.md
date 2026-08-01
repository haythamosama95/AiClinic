# Tasks: Context Resolver registry, first context RPC, and client contract test (E3)

**Input**: Design documents from `specs/037-context-resolver-registry/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — E3 defines no entities (spec Key Entities: not applicable). `contracts/` Freezes artifacts are named in the plan Files section and written/confirmed in Phase 4 (Documentation). `quickstart.md` is written in Phase 4.

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (E3-T01–E3-T10) is a task. Layer is **Flutter unit + SQL / RLS + contract** (delivery plan §3.11.5 row E3; DP-3). Flutter cases live under `frontend/test/unit/core/ai/` and run via `flutter test` against injectable fakes (Clarification Q2–Q3 patterns; no live Worker). SQL/RLS cases live in `backend/tests/context_provider_rpc.sql` and run via `psql` / the AI-platform trust runner. Written to fail before the Resolver library and context RPC exist.

**Organization**: One user story (US1, P1) — E3 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — test substrates (`fakes.dart` extension; new test files) land in the Tests phase; library/RPC Files units land in Implementation. No Foundational or Polish phase — prerequisites are already-merged Needs (E2, C1) plus A5 via §5.2 / C1 in the plan's Consumes Binding.

**Task count**: 19 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`, `frontend/tool/`
- **Supabase backend**: `backend/supabase/migrations/`, `backend/tests/`
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by E3* (Consumes A5 shape + C1 discovery only)
- **Spec Kit artifacts**: `specs/037-context-resolver-registry/`
- E3 Resolver modules are siblings of the E2 SDK under `frontend/lib/core/ai/` (Clarification Q4). Tests and fakes live under `frontend/test/unit/core/ai/`. First context provider RPC is an ordinary clinic read under `backend/`. No `ai-platform/` path is modified.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: Cover every named test in the spec's `### Test plan` (§3.11.5 row E3). Flutter unit cases share `frontend/test/unit/core/ai/context_resolver_test.dart` (E3-T01–E3-T04). SQL/RLS cases share `backend/tests/context_provider_rpc.sql` (E3-T05–E3-T08). Contract cases share `frontend/test/unit/core/ai/context_contract_test.dart` (E3-T09–E3-T10). T001 also extends `frontend/test/unit/core/ai/fakes.dart` (plan Files test-support row — substrate, not repeated in Implementation). Until `frontend/lib/core/ai/context_*.dart` and the context RPC migration exist, imports / RPC calls fail — the intended red state. Order follows plan Sequencing themes (Resolver unit → RPC SQL → contract).

- [X] T001 [US1] Add named test `resolver_key_list_assembles_payload` (E3-T01) in `frontend/test/unit/core/ai/context_resolver_test.dart`: extend substrate `frontend/test/unit/core/ai/fakes.dart` with a fake clinic-read port and an injectable C1-shaped active-manifest source returning `{ manifests }` (Clarification Q3; plan Files) — and import the Context Resolver under test from `frontend/lib/core/ai/`. Assert a registered key list resolves to an assembled payload conforming to each key's declared shape (§4.1; §5.2; §3.11.5 E3). Fails red until key-list assembly exists. **Satisfies**: FR-001, FR-002, FR-007 / SC-001. **Proves**: E3-T01.
- [X] T002 [US1] Add named test `resolver_unknown_key_typed_failure` (E3-T02) to `frontend/test/unit/core/ai/context_resolver_test.dart`: a key list that includes an unregistered key surfaces a typed failure and does not assemble a partial payload as success (§3.11.5 E3; §4.1 Must not: send unrequested data). **Satisfies**: FR-004 / SC-001. **Proves**: E3-T02.
- [X] T003 [US1] Add named test `resolver_api_exposes_no_capability_id` (E3-T03) to `frontend/test/unit/core/ai/context_resolver_test.dart`: the Resolver public API accepts no capability-id parameter and performs no capability-id branching — only a key list in, payload or typed failure out (§4.1; delivery plan §3.6 Done when; §3.11.5 E3). **Satisfies**: FR-003 / SC-002. **Proves**: E3-T03.
- [X] T004 [US1] Add named test `resolver_cache_screen_scoped_discarded_on_dispose` (E3-T04) to `frontend/test/unit/core/ai/context_resolver_test.dart`: cache is instance/screen-scoped; disposing the Resolver instance discards cached results so they do not outlive the screen (Clarification Q1; §4.1; §3.11.5 E3). **Satisfies**: FR-005 / SC-003. **Proves**: E3-T04.
- [X] T005 [P] [US1] Add named test `context_rpc_returns_declared_shape` (E3-T05) in `backend/tests/context_provider_rpc.sql`: create the SQL/RLS suite file; assert the first context provider RPC returns the `visit.chief_complaint@v1` declared shape (`visit_id`, `complaint`, optional `recorded_at`) for an authenticated caller with in-scope access (§4.2; §5.2; §3.11.5 E3). Fails red until the migration RPC exists. **Satisfies**: FR-008, FR-009 / SC-004. **Proves**: E3-T05.
- [X] T006 [US1] Add named test `context_rpc_rls_denies_out_of_scope` (E3-T06) to `backend/tests/context_provider_rpc.sql`: an authenticated caller without access to out-of-scope rows is RLS-denied — resolution stays under the caller's own permissions; no privileged bypass (§4.2; §5.2 Authorization; §3.11.5 E3). **Satisfies**: FR-008 / SC-004. **Proves**: E3-T06.
- [X] T007 [US1] Add named test `context_rpc_no_ai_specific_parameter` (E3-T07) to `backend/tests/context_provider_rpc.sql`: RPC signature/body has no AI-specific parameter and encodes no prompts, providers, quotas, or AI request state (§4.2 Boundary note; §3.11.5 E3). **Satisfies**: FR-010 / SC-004. **Proves**: E3-T07.
- [X] T008 [US1] Add named test `context_rpc_shape_matches_a5_published_key` (E3-T08) to `backend/tests/context_provider_rpc.sql`: returned shape matches A5 `VISIT_CHIEF_COMPLAINT_V1_SHAPE` (Consumes A5; §5.2; §3.11.5 E3). **Satisfies**: FR-009 / SC-004. **Proves**: E3-T08.
- [X] T009 [P] [US1] Add named test `contract_every_active_manifest_key_resolvable` (E3-T09) in `frontend/test/unit/core/ai/context_contract_test.dart`: create the client contract suite; feed C1-shaped active manifests through the injectable manifest source from T001's fakes; assert every declared context key of every active capability is resolvable by the Context Resolver (§13.5; §5.2 Discovery; §3.11.5 E3). Depends on T001 fakes substrate. Fails red until registration + Resolver cover declared keys. **Satisfies**: FR-011 / SC-005. **Proves**: E3-T09.
- [X] T010 [US1] Add named test `contract_manifest_unknown_key_fails_suite` (E3-T10) to `frontend/test/unit/core/ai/context_contract_test.dart`: inject a synthetic/fixture manifest that declares an unregistered context key (Clarification Q3); assert the contract suite fails (§13.5; §3.11.5 E3). **Satisfies**: FR-012 / SC-005. **Proves**: E3-T10.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as test substrates or Documentation: the three Dart library files under `frontend/lib/core/ai/`, the clinic RPC migration, and trust-runner CI wiring. `fakes.dart`, `context_resolver_test.dart`, `context_contract_test.dart`, and `context_provider_rpc.sql` are produced in Phase 1; `contracts/` and `quickstart.md` in Phase 4. Order follows plan Sequencing (port → registration → Resolver; migration parallel; CI wiring after SQL suite exists). Consumed modules (E2 SDK siblings, C1 discovery shape, A5 first-key shape, E1 guard) are bound as clients only — not modified (delivery plan §2.3).

- [X] T011 [US1] Create `frontend/lib/core/ai/context_provider_port.dart` — injectable clinic-read port used by registered resolver functions (production: Supabase RPC; tests: in-memory fake from T001). Resolution stays under the caller's own Supabase session/RLS — no privileged path (FR-004, FR-008). **Satisfies**: FR-001, FR-008. **Proved by**: E3-T01, E3-T05–E3-T06 (and substrate for Resolver/contract suites).
- [X] T012 [US1] Create `frontend/lib/core/ai/context_registration.dart` — closed static map of context key → resolver function in one registration module (Clarification Q2); registers `visit.chief_complaint@v1` against the first context provider via the clinic-read port; keys follow `domain.concept@vN` (FR-006). Depends on T011. **Satisfies**: FR-001, FR-002, FR-006. **Proved by**: E3-T01, E3-T09.
- [X] T013 [US1] Create `frontend/lib/core/ai/context_resolver.dart` — Context Resolver (§4.1): `resolve(List<String> keys)` → assembled payload conforming to declared shapes, or typed failure for unknown keys; no capability-id parameter or branching; instance-state cache discarded with the instance (Clarification Q1); never invents data for unknown keys; never decides which keys are needed or sends unrequested data; no prompts, providers, or model identifiers (R-12 / FR-013). Depends on T012. **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-013. **Proved by**: E3-T01–E3-T04, E3-T09–E3-T10.
- [X] T014 [P] [US1] Create `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql` — ordinary `auth_internal` + `public` INVOKER read RPC returning `{ visit_id, complaint, recorded_at }` for `visit.chief_complaint@v1` under caller RLS over existing `visit_clinical_notes` / visit RLS; no AI-specific parameters; no prompts/providers/quotas/AI request state (§4.2 Boundary note). Prefer reuse of existing storage and RLS (FR-009). Parallel with the Flutter library chain (different layer). **Satisfies**: FR-008, FR-009, FR-010. **Proved by**: E3-T05–E3-T08.
- [X] T015 [US1] Modify `backend/tests/run_ai_platform_trust_tests.sh` — append `context_provider_rpc.sql` so the E3 SQL/RLS suite joins CI permanently (delivery plan §3.10). Depends on T005–T008 existing and T014 landed. **Satisfies**: the §3.10 permanent-suite rule for this slice's SQL cases (no new FR). **Proved by**: E3-T05–E3-T08 via the trust runner.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T016 [US1] From `frontend/`, run `flutter test test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart` (this slice's named cases E3-T01–E3-T04 and E3-T09–E3-T10). Confirm FR-013 / E1: new paths under `frontend/lib/core/ai/context_*.dart` still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). From `backend/`, run `bash backend/tests/run_ai_platform_trust_tests.sh` (includes this slice's `context_provider_rpc.sql` after T015). Then from `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Also keep the prior E2 Flutter suite green: `flutter test test/unit/core/ai/ai_client_sdk_test.dart`. Confirm E3's named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (E3-T01–E3-T10 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. Documentation artifacts the plan names: the two Freezes contracts (wire/behaviour for later Consumes) and `quickstart.md`. Written/confirmed after the suite is green. Contract files touch different paths from each other and from quickstart, so the two contract tasks are `[P]` relative to each other; quickstart may follow or run after contracts. No other documentation artifact is named for a separate task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T017 [P] [US1] Create (or confirm frozen content of) `specs/037-context-resolver-registry/contracts/context-resolver.md` — frozen key-list API: key list in → assembled payload or typed unknown-key failure; no capability-id parameter or branching; screen-scoped instance cache discarded on dispose; source-of-truth pointers to `context_resolver.dart` / `context_registration.dart`. Later slices (E4, H3, J2) consume this artifact, not prose (DP-4; delivery plan §2.3). **Satisfies**: Freezes — Context Resolver / generic key-list API / screen-scoped cache (plan Files).
- [ ] T018 [P] [US1] Create (or confirm frozen content of) `specs/037-context-resolver-registry/contracts/context-provider-rpc.md` — frozen first ordinary read RPC for `visit.chief_complaint@v1`: return shape binding to A5 `VISIT_CHIEF_COMPLAINT_V1_SHAPE`, caller-RLS posture, no AI-specific parameter / no AI platform knowledge; source-of-truth pointer to the migration. **Satisfies**: Freezes — first context provider RPC (plan Files).
- [ ] T019 [US1] Create `specs/037-context-resolver-registry/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.6 row E3; `17-ai-platform.md` §4.1 / §5.2 / §4.2 / §13.5; what the spec delivered; what the plan scoped. **§2 What was implemented** — Context Resolver registry + registration map; first `visit.chief_complaint@v1` context provider RPC; Flutter client contract suite. **§3 Files to review** — only this slice's `frontend/lib/core/ai/context_*.dart`, `frontend/test/unit/core/ai/context_*.dart` / fakes extension, the new backend migration, and `backend/tests/context_provider_rpc.sql` (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`flutter` / Dart SDK; local Supabase for SQL suite). **§5 Run the automated suite** — slice-only `flutter test test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart` and `psql -f backend/tests/context_provider_rpc.sql` (or the trust runner for this file only); no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open the registration map, Resolver API, RPC migration, and frozen `contracts/` artifacts; confirm E1 guard still covers new Flutter AI paths. **No §7 Manual validation** — CI / `flutter test` / SQL suite is the verification path (E3 exposes no user-visible surface; E4 does). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T010)** — none beyond existing `frontend/` / `backend/` and Consumes Binding modules available as contracts; written to fail before `context_*.dart` and the context RPC migration exist. T001 creates/extends the Flutter substrate (`fakes.dart` + `context_resolver_test.dart`). T002–T004 append to the same Resolver unit file. T005 creates the SQL suite; T006–T008 append. T009 creates the contract suite (after T001 fakes); T010 appends.
- **Implementation (T011–T015)** — after tests exist (red). T011 (`context_provider_port.dart`) first. T012 (`context_registration.dart`) after T011. T013 (`context_resolver.dart`) after T012 and turns E3-T01–E3-T04 and E3-T09–E3-T10 green. T014 (migration) is `[P]` with the Flutter chain (different layer) and turns E3-T05–E3-T08 green. T015 (trust runner) after T014 and the SQL test file exist.
- **Verification (T016)** — depends on T001–T015; runs this slice's Flutter + SQL suites plus E1 guard check plus every prior suite per §3.10.
- **Documentation (T017–T019)** — depends on T016 (artifacts/quickstart record a green suite). T017 and T018 are `[P]` relative to each other; T019 may follow either.

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: port (T011) → registration (T012) → Resolver (T013); migration (T014) parallel; CI wiring (T015); Documentation last.
- `fakes.dart` Files-section row is produced by T001 (test substrate); not repeated as an Implementation task. Remaining Files units: T011–T015 (library / migration / runner) and T017–T019 (contracts + quickstart).

### Parallel Opportunities

- Phase 1: T005 `[P]` (SQL suite, different file) can proceed in parallel with T001–T004. T009 `[P]` (contract suite, different file) can proceed after T001's fakes land, in parallel with T002–T008. Within each shared file, appends are sequential.
- Phase 2: T014 is `[P]` relative to T011–T013 (backend vs Flutter). T012/T013 are sequential after T011. T015 follows T014.
- Phase 4: T017 and T018 are `[P]`; T019 is a single follow-on task.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T005, T009, T014, T017, T018.
- Every named test E3-T01–E3-T10 from `spec.md` is its own task. No cases dropped. No unrelated tasks merged.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to Freezes / the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name. Clarifications Q1–Q4 guide how (one Resolver per screen; closed static registration map; synthetic unregistered-key fixture; siblings under `frontend/lib/core/ai/`), not what.
- No Polish phase and no Foundational phase — Needs are E2, C1 (already merged; Consumes Binding), plus A5 via §5.2 / C1.
- Consumed modules are imported/bound, not modified (delivery plan §2.3 — extend, never rewrite). No `ai-platform/` file is touched.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve R-12 / §6.4: no prompt text, provider name, or model identifier in the Flutter client; no privileged RLS bypass; no AI knowledge on the ordinary context RPC.
