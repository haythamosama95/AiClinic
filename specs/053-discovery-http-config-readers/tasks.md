# Tasks: Discovery HTTP route and production config-cache readers (I2)

**Input**: Design documents from `specs/053-discovery-http-config-readers/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — spec Key Entities is "Not applicable" (A5 froze the D1 logical model; Clarification Q1 realises already-named `kill_switch`). `contracts/discovery-http.md` is already frozen on disk (written during the plan phase per DP-4; `AVAILABLE_DOCS` includes `contracts/`). `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T14) is covered by its own task, written to fail before the discovery handler, worker route, kill_switch migration, and `createD1ConfigReader` kill_switches SELECT exist. Layer is **Workers integration** (delivery plan §3.12.9 row I2; §13.5 Pipeline / Workers integration via Miniflare). Two files per Clarification Q3: `ai-platform/test/discovery-http.test.ts` (T1–T5) and `ai-platform/test/config-readers.test.ts` (T6–T14). Permanent suites join CI via both Vitest harness configs (delivery plan §3.10).

**Organization**: One user story (US1, P1) — I2 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — the workers-pool include / Node-pool exclude pair must land before any named Worker test. No Foundational or Polish phase — prerequisites are already-merged Needs (A5, C1) in the plan's Consumes Binding.

**Task count**: 21 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by I2*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by I2*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/053-discovery-http-config-readers/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). I2 adds `src/discovery/`, routes `GET /v1/capabilities` in `worker.ts`, completes `createD1ConfigReader` kill_switches SELECT, adds one forward-only D1 `kill_switch` migration + schema snapshot, and does not edit consumed frozen contracts (A5 `config-cache.md`; C1 `capability-registry.md`).

---

## Phase 1: Setup (Test harness)

**Purpose**: Route the two new Workers integration test files so Miniflare-D1 cases do not cross-contaminate the default Node pool (plan → Testing / Files; B2/C1/J4 precedent). Both config edits must land before any named Worker test is written.

- [X] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/discovery-http.test.ts"` and `"test/config-readers.test.ts"` to `include`. Modify `ai-platform/vitest.config.ts` — add both files to `exclude`, so the workers-pool-only cases do not double-run in the default Node pool (plan → Files). No FR — harness; required by T1–T14. Prepares the Phase 2 Worker substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.9 row I2; Workers integration). Per Clarification Q3, T1–T5 live in `ai-platform/test/discovery-http.test.ts` and T6–T14 in `ai-platform/test/config-readers.test.ts`. Per Clarification Q4, T6–T12 and T14 use direct Miniflare D1 + `createD1ConfigReader` / `loadConfig` (discovery HTTP does not consult every kind). Per Clarification Q5, T13 spies / wraps `D1Reader.read` around `createD1ConfigReader`. Until the discovery handler, worker route, kill_switch migration, and kill_switches SELECT exist, imports/assertions fail — the intended red state.

### Discovery HTTP — `ai-platform/test/discovery-http.test.ts`

- [X] T002 [US1] Create `ai-platform/test/discovery-http.test.ts` with the Workers integration substrate (Miniflare D1 + Worker fetch; enroll / seed entitlements+grants+manifests as needed for discovery) and named test `T1 discovery_http_granted_active_manifests`: enrolled installation with valid AAT `GET /v1/capabilities` (no capability id) receives only granted effective-`active`/`deprecated` manifests (FR-001, FR-004, FR-006 / SC-001; §5.5; C1 Freezes). Fails red until the discovery handler and worker route exist. **Satisfies**: FR-001, FR-004, FR-006 / SC-001. **Proves**: T1.
- [X] T003 [US1] Add named test `T2 discovery_http_etag_not_modified` to `ai-platform/test/discovery-http.test.ts`: matching `If-None-Match` → not-modified (304); response carries `Cache-Control: private, must-revalidate` (FR-003 / SC-002; §5.5). Fails red until conditional revalidation is mounted via C1 `buildDiscoveryResponse`. **Satisfies**: FR-003 / SC-002. **Proves**: T2.
- [X] T004 [US1] Add named test `T3 discovery_http_changed_manifest_changes_etag` to `ai-platform/test/discovery-http.test.ts`: changed granted manifest set → different response `ETag` (FR-003 / SC-002; §5.5). Fails red until live discovery returns C1 etags. **Satisfies**: FR-003 / SC-002. **Proves**: T3.
- [X] T005 [US1] Add named test `T4 discovery_http_ineligible_plan_capability_absent` to `ai-platform/test/discovery-http.test.ts`: entitlement-gated capability absent for ineligible plan — not an error code on this surface (FR-004 / SC-001; §4.3.4; §5.5; C1 Freezes). Fails red until HTTP discovery invokes C1 `discover()`. **Satisfies**: FR-004 / SC-001. **Proves**: T4.
- [X] T006 [US1] Add named test `T5 discovery_http_unauthenticated` to `ai-platform/test/discovery-http.test.ts`: missing/invalid AAT → taxonomy `unauthenticated`; no manifest body (FR-002, FR-005 / SC-003; §5.5; §4.3.2). Fails red until the handler verifies Bearer AAT with the same verifier as submit. **Satisfies**: FR-002, FR-005 / SC-003. **Proves**: T5.

### Config readers — `ai-platform/test/config-readers.test.ts`

- [X] T007 [P] [US1] Create `ai-platform/test/config-readers.test.ts` with the workers-pool substrate (`beforeAll` applies platform migrations including the I2 `kill_switch` migration to `env.DB`; direct Miniflare D1 + `createD1ConfigReader` / `loadConfig` per Clarification Q4) and named test `T6 config_reader_presence_installation`: present installation row served through the production D1 config reader (FR-007 / SC-004; §4.3.2). Fails red until the production reader path is assertable for installations. **Satisfies**: FR-007 / SC-004. **Proves**: T6.
- [X] T008 [US1] Add named test `T7 config_reader_presence_keys` to `ai-platform/test/config-readers.test.ts`: present installation keys served through the production D1 config reader (FR-007 / SC-004; §4.3.2). Fails red until keys presence is assertable. **Satisfies**: FR-007 / SC-004. **Proves**: T7.
- [X] T009 [US1] Add named test `T8 config_reader_presence_entitlements` to `ai-platform/test/config-readers.test.ts`: present entitlement served through the production D1 config reader (FR-007 / SC-004; §4.3.2). Fails red until entitlements presence is assertable. **Satisfies**: FR-007 / SC-004. **Proves**: T8.
- [X] T010 [US1] Add named test `T9 config_reader_presence_grants_lifecycle_overlay` to `ai-platform/test/config-readers.test.ts`: present grants / lifecycle overlay served through the production D1 config reader (FR-007 / SC-004; §4.3.2; Done when). Fails red until grants presence is assertable. **Satisfies**: FR-007 / SC-004. **Proves**: T9.
- [X] T011 [US1] Add named test `T10 config_reader_presence_kill_switches` to `ai-platform/test/config-readers.test.ts`: present kill_switch row served through the production D1 config reader (FR-007 / SC-004; §4.3.2). Fails red until the additive `kill_switch` table and SELECT exist. **Satisfies**: FR-007 / SC-004. **Proves**: T10.
- [X] T012 [US1] Add named test `T11 config_reader_presence_active_routing_policy` to `ai-platform/test/config-readers.test.ts`: present active routing policy served through the production D1 config reader (FR-007 / SC-004; §4.3.2). Fails red until routing-policy presence is assertable. **Satisfies**: FR-007 / SC-004. **Proves**: T11.
- [X] T013 [US1] Add named test `T12 config_reader_presence_token_contract` to `ai-platform/test/config-readers.test.ts`: present global `token_contract` accepted-`ver` set served through the production D1 config reader (FR-007 / SC-004; §4.3.2; §13.4). Fails red until token_contract presence is assertable. **Satisfies**: FR-007 / SC-004. **Proves**: T12.
- [X] T014 [US1] Add named spy test `T13 config_reader_cold_isolate_single_d1_read_pattern` to `ai-platform/test/config-readers.test.ts`: spy/wrapper on `D1Reader.read` around `createD1ConfigReader` (Clarification Q5); cold isolate with empty in-isolate map performs A5's single same-region D1 read pattern on first config load (FR-008 / SC-005; §4.3.2; A5 Freezes). Fails red until the single-read pattern is assertable via spy call count. **Satisfies**: FR-008 / SC-005. **Proves**: T13.
- [X] T015 [US1] Add named test `T14 config_reader_miss_typed_failure_not_silent_admit` to `ai-platform/test/config-readers.test.ts`: a miss for a required request-path kind → typed `ConfigCacheMissError`, not an empty grant set that silently admits (FR-009 / SC-005; Done when; §4.3.2). Fails red until typed-miss behaviour is assertable through the production reader. **Satisfies**: FR-009 / SC-005. **Proves**: T14.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Vitest test entries, harness config, or Documentation. Migration + `schema.snap.sql` are one FR-007 schema unit (A5/J4 precedent: snapshot reflects post-migration shape). Vitest entry Files-section rows (`discovery-http.test.ts`, `config-readers.test.ts`) are produced by Phase 2; vitest config pair by Phase 1. `contracts/discovery-http.md` is already frozen — no task recreates it. Consumed modules (`capability/`, `identity/`, `errors.ts`) are imported, not rewritten (delivery plan §2.3). Order follows plan Sequencing: migration → kill_switches SELECT → discovery handler → worker route.

- [X] T016 [US1] Create `ai-platform/migrations/20260807120000_kill_switch.sql` — additive `kill_switch` table per §7.3 (keys `global` / `{scope}:{target}`; Clarification Q1). Update `ai-platform/schema.snap.sql` so the snapshot includes `kill_switch` DDL after migration (FR-007). Not a new logical-model Freezes entry — realises the already-architecture-named entity so the production reader can SELECT a present row. **Satisfies**: FR-007. **Proved by**: T10 (and every case that seeds/reads kill switches).
- [X] T017 [US1] Modify `ai-platform/src/config-cache/index.ts` — replace the `kill_switches` stub miss in `createD1ConfigReader` with a SELECT against `kill_switch` (§7.3); leave `ConfigCache` / `loadConfig` / TTL / single-flight / other kind SELECTs unchanged (FR-007, FR-008, FR-009, FR-010; A5 Freezes; Clarification Q1). Miss remains typed `ConfigCacheMissError`, never a silent empty admit. Only volatile policy is D1 data through this reader. **Satisfies**: FR-007, FR-008, FR-009, FR-010. **Proved by**: T6–T14.
- [ ] T018 [US1] Create `ai-platform/src/discovery/index.ts` — HTTP handler: parse Bearer AAT → shared `ConfigCache` + `createD1ConfigReader` (Clarification Q2) → `EnrolledKeyVerifier.verify` → C1 `discover()` → `buildDiscoveryResponse`; unauthenticated → taxonomy `unauthenticated` body with no discovery body (FR-001..FR-006). Does not re-implement registry filtering or etag matching (C1 Consumes). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006. **Proved by**: T1–T5.
- [ ] T019 [US1] Modify `ai-platform/src/worker.ts` — route `GET /v1/capabilities` to the discovery handler (FR-001). Sibling of submit; does not touch `handleAdapterRequest` / §4.3.1. **Satisfies**: FR-001. **Proved by**: T1–T5 (HTTP path through the Worker fetch boundary).

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T020 [US1] From `ai-platform/`, run this slice's Workers suites — `npx vitest run --config vitest.workers.config.ts test/discovery-http.test.ts test/config-readers.test.ts`. Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm I2's fourteen named cases (T1–T14) are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions hold: no per-request server-side state; no second Quota DO / R2; no journal row for auth failure on this surface; no §9.14 mechanism (§6.4). **Satisfies**: the §3.10 checkpoint rule (T1–T14 + prior suites). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. `contracts/discovery-http.md` was already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T021 [US1] Create `specs/053-discovery-http-config-readers/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.10 row I2; Implements §5.5, §4.3.4, §4.3.2, §13.4; what the spec delivered; what the plan scoped. **§2 What was implemented** — `GET /v1/capabilities` handler; `createD1ConfigReader` kill_switches SELECT; `kill_switch` migration + schema snapshot; frozen `contracts/discovery-http.md`. **§3 Files to review** — only this slice's `src/discovery/`, `src/config-cache/` (reader branch), `src/worker.ts` route, migration, schema snapshot, both test files, and the frozen contract (no prior-slice files). **§4 Prerequisites** — omit when `npx vitest run --config vitest.workers.config.ts` against this slice's two test files is sufficient; otherwise note one-time `npm install` in `ai-platform/` and workers-pool Miniflare D1. **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/discovery-http.test.ts test/config-readers.test.ts` (14 named tests; no full-suite `npm test`, no combined prior-slice counts). **§6 Inspect the changes** — curl/grep for `/v1/capabilities`; read `contracts/discovery-http.md`; confirm kill_switches SELECT in `createD1ConfigReader`. **§7 Manual validation** — optional `curl` against a local Worker for `GET /v1/capabilities` with Bearer AAT and `If-None-Match` (this slice exposes live HTTP beyond CI; plan). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — no dependencies; blocks the Worker Tests phase (workers include / Node exclude must be wired before any Worker test runs in the right pool).
- **Tests (T002–T015)** — depends on Setup for Worker files; every test is written against discovery HTTP / production-reader behaviour that is absent or incomplete, so the files are red until the Implementation phase lands. T002–T006 append to `discovery-http.test.ts` (sequential; T002 creates the substrate). T007–T015 append to `config-readers.test.ts` (T007 creates; `[P]` with T002).
- **Implementation (T016–T019)** — after tests exist (red). Order follows plan Sequencing: migration + snapshot (T016) → kill_switches SELECT (T017) → discovery handler (T018) → worker route (T019). Tests turn green in matching groups: T6–T14 against T016–T017; T1–T5 against T018–T019 (with production reader available for shared cache/verify).
- **Verification (T020)** — depends on T001–T019; runs this slice plus every prior slice per §3.10.
- **Documentation (T021)** — depends on T020 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: migration (T016) → production reader (T017) → discovery handler (T018) → worker route (T019) → quickstart (T021).
- Vitest entry Files-section rows (`discovery-http.test.ts`, `config-readers.test.ts`) are produced by Phase 2; vitest config pair by Phase 1. Remaining Files units are T016–T019 plus T021 (`quickstart.md`). `contracts/discovery-http.md` is already frozen — no task recreates it. Consumed `capability/`, `identity/`, and `errors.ts` are unchanged aside from imports by the new handler.

### Parallel Opportunities

- Phase 1 (T001) is a single task — no internal parallelism.
- Phase 2: T007 `[P]` with T002 (different Worker test files). T003–T006 append to the discovery-http file — sequential, not `[P]`. T008–T015 append to the config-readers file — sequential after T007. T14 (spy) is its own task — not folded into presence or miss outcome asserts.
- Phase 3: T016 → T017 → T018 → T019 are sequential per plan Sequencing (migration before SELECT; reader before discovery handler shared cache; handler before worker route).
- Phase 5 (T021) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Within each same-file test append chain there is no `[P]`.
- Every named test T1–T14 from `spec.md` is covered by its own task; no test is folded into another. T13 is a separate spy task (call count), not merged into presence/outcome assertions.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (A5, C1).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Combined related Files units only where the plan Sequencing or A5/J4 snapshot precedent requires them to land together: migration + `schema.snap.sql` (T016). Discovery handler and worker remain separate (J4/C1 precedent).
- Preserve §6.4: no §9.14 mechanism; no second Quota DO / R2 object; no journal row for auth failure on this surface; no per-request server-side state; no rewrite of A5 cache mechanics or C1 `discover`/`resolve` library; no Flutter AI surface; no Supabase write.
