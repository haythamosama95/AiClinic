# Tasks: Token contract rotation with overlapping acceptance (J4)

**Input**: Design documents from `specs/051-token-contract-rotation/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` and `contracts/token-contract-rotation.md` are already frozen on disk (written during the plan phase per DP-4; `AVAILABLE_DOCS` includes both). `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T-J4-01 .. T-J4-10) is covered by its own task, written to fail before the accepted-`ver` check, control writers, and clinic mint assertions exist. Layers are **Unit + SQL** (delivery plan §3.11.8 row J4; §13.5): Node-pool Unit in `ai-platform/test/token-contract-rotation.test.ts`; workers-pool D1 SQL in `ai-platform/test/token-contract-control.test.ts`; clinic Contract SQL in `backend/tests/ai_token_contract_rotation.sql`. Permanent suites join CI via both Vitest harness configs and `backend/tests/run_ai_platform_trust_tests.sh` (delivery plan §3.10).

**Organization**: One user story (US1, P1) — J4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — the workers-pool include / Node-pool include+exclude pair must land before any named Worker test. No Foundational or Polish phase — prerequisites are already-merged Needs (B1, B3) in the plan's Consumes Binding.

**Task count**: 18 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by J4*
- **Supabase backend**: `backend/supabase/migrations/` (*unchanged — B1 issuer already reads `ai.aat.ver`*), `backend/tests/`
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/051-token-contract-rotation/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). J4 extends B3 `src/identity/`, A5 `src/config-cache/`, and B2 `src/control/` in place, adds one forward-only D1 `token_contract` migration, and does not edit consumed frozen contracts (`aat-token.md`, `token-verifier.md`, `control-plane.md`, A5 `config-cache.md` / `data-model.md`).

---

## Phase 1: Setup (Test harness)

**Purpose**: Route the new Unit and workers-pool test files so Node-pool and Miniflare-D1 cases do not cross-contaminate (plan → Testing / Files; B2/C1/J1 precedent). Both config edits must land before any named Worker test is written.

- [x] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/token-contract-control.test.ts"` to `include`. Modify `ai-platform/vitest.config.ts` — ensure `"test/token-contract-rotation.test.ts"` is covered by the Node-pool `include` and add `"test/token-contract-control.test.ts"` to `exclude`, so the workers-pool-only D1 cases do not double-run in the default Node pool (plan → Files). No FR — harness; required by T-J4-01 .. T-J4-07 and the platform half of T-J4-10. Prepares the Phase 2 Worker substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.8 row J4; Unit + SQL). Unit cases (T-J4-01..03, T-J4-07, Unit half of T-J4-10) live in `ai-platform/test/token-contract-rotation.test.ts` under `vitest.config.ts`. D1 SQL cases (T-J4-04..06, SQL half of T-J4-10) live in `ai-platform/test/token-contract-control.test.ts` under `vitest.workers.config.ts`. Clinic SQL cases (T-J4-08..09, clinic half of T-J4-10) live in `backend/tests/ai_token_contract_rotation.sql`. Until migration, config-cache kind, identity check, and control handlers exist, Worker imports/assertions fail — the intended red state. Clinic cases fail until they assert against an advanced `ai.aat.ver` mint path (issuer itself is B1; J4 does not rewrite it).

### Unit — `ai-platform/test/token-contract-rotation.test.ts`

- [ ] T002 [US1] Create `ai-platform/test/token-contract-rotation.test.ts` with the Node-pool substrate and named test `T-J4-01 both_ver_values_verify_during_rotation_window`: seed / stub the accepted-`ver` set with two members; present AATs carrying each participating `ver` to the verifier; both verify (FR-001, FR-002 / SC-001; §5.7; §5.6). Fails red until the accepted-`ver` check via config cache exists. **Satisfies**: FR-001, FR-002 / SC-001. **Proves**: T-J4-01.
- [ ] T003 [US1] Add named test `T-J4-02 retired_ver_refused_as_unauthenticated` to `ai-platform/test/token-contract-rotation.test.ts`: after the prior `ver` is no longer in the accepted set, a token carrying it → `{ ok: false, code: "unauthenticated" }`; assert no new taxonomy code is emitted (FR-010 / SC-002; §5.6; §5.7). Fails red until retired-`ver` refusal reuses existing `unauthenticated`. **Satisfies**: FR-010 / SC-002. **Proves**: T-J4-02.
- [ ] T004 [US1] Add named test `T-J4-03 unknown_ver_refused_as_unauthenticated` to `ai-platform/test/token-contract-rotation.test.ts`: a never-accepted `ver` → same `unauthenticated` path as T-J4-02 (FR-010 / SC-002; §5.6 accepting side). Fails red until set-membership refusal (not a retired-versus-unknown distinction) exists. **Satisfies**: FR-010 / SC-002. **Proves**: T-J4-03.
- [ ] T005 [US1] Add named spy test `T-J4-07 request_path_never_writes_token_contract` to `ai-platform/test/token-contract-rotation.test.ts`: identity / request-path verification performs no `token_contract` write; nothing auto-retires a `ver` (no `retire_after` / TTL clock trip) (FR-004, FR-005 / SC-005; §5.7; §7.3). Fails red until the non-writer invariant is assertable on the verify path. **Satisfies**: FR-004, FR-005 / SC-005. **Proves**: T-J4-07.

### D1 SQL — `ai-platform/test/token-contract-control.test.ts`

- [ ] T006 [P] [US1] Create `ai-platform/test/token-contract-control.test.ts` with the workers-pool substrate (`beforeAll` applies platform migrations including the J4 `token_contract` migration to `env.DB`; B2-style fake `OperatorAuth`) and named test `T-J4-04 accepted_set_is_one_when_stable_and_two_mid_rotation`: `WHERE retired_at IS NULL` count is exactly 1 when stable and 2 mid-rotation (FR-002, FR-003 / SC-003; §5.6; §5.7; §7.3). Fails red until the table, seed, and set-membership shape exist. **Satisfies**: FR-002, FR-003 / SC-003. **Proves**: T-J4-04.
- [ ] T007 [US1] Add named test `T-J4-05 begin_rotation_adds_ver_and_keeps_prior` to `ai-platform/test/token-contract-control.test.ts`: begin-rotation inserts the new `ver`, leaves the prior `ver` accepted, and writes `control_audit` with action `token_contract_begin_rotation` (FR-006, FR-008 / SC-004; §5.7; §4.5; §7.3). Fails red until the begin-rotation handler and audit write exist. **Satisfies**: FR-006, FR-008 / SC-004. **Proves**: T-J4-05.
- [ ] T008 [US1] Add named test `T-J4-06 retire_stamps_retired_at_and_returns_set_to_one` to `ai-platform/test/token-contract-control.test.ts`: retire stamps `retired_at` on the retired `ver`, accepted count → 1, and writes `control_audit` with action `token_contract_retire` (FR-007, FR-008 / SC-004; §5.7; §4.5; §7.3). Fails red until the retire handler and audit write exist. **Satisfies**: FR-007, FR-008 / SC-004. **Proves**: T-J4-06.

### Clinic SQL — `backend/tests/ai_token_contract_rotation.sql`

- [ ] T009 [P] [US1] Create `backend/tests/ai_token_contract_rotation.sql` with the clinic SQL substrate (B1 pattern: `BEGIN` … temp results … `DO $$` … `RAISE EXCEPTION` on failure) and named test `T-J4-08 new_contract_token_carries_every_claim`: advance `ai.aat.ver`, mint via the existing issuer, assert every §5.6 claim (`iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`), `alg: EdDSA` header, and deliberate omissions (FR-013, FR-016, FR-017 / SC-006; §5.6). Fails red until the case asserts claim-complete mint under the advanced setting. **Satisfies**: FR-013, FR-016, FR-017 / SC-006. **Proves**: T-J4-08.
- [ ] T010 [US1] Add named test `T-J4-09 issuer_mints_single_ver_from_ai_aat_ver` to `backend/tests/ai_token_contract_rotation.sql`: issuer reads `ver` from `ai.aat.ver` in `ai_internal.app_settings` and mints exactly one `ver` per token (no dual-mint); `scopes` remain RBAC-derived; platform does not write the setting (FR-011, FR-012, FR-014 / SC-007; §5.6 minting side). Fails red until the single-mint assertion exists. **Satisfies**: FR-011, FR-012, FR-014 / SC-007. **Proves**: T-J4-09.

### Cross-file — Unit + D1 SQL + clinic SQL

- [ ] T011 [US1] Add named test `T-J4-10 rotation_requires_no_re_enrollment` across the three suite files: Unit + workers halves in `ai-platform/test/token-contract-rotation.test.ts` and `ai-platform/test/token-contract-control.test.ts` assert the same enrolled `iss`+`kid` still verifies under both accepted `ver` values after begin-rotation; clinic half in `backend/tests/ai_token_contract_rotation.sql` asserts the same enrolled installation mints under the advanced `ai.aat.ver` without a re-enrollment step (FR-015 / SC-008; §5.6; §3.11.8 J4). Fails red until overlapping acceptance and clinic mint under advanced `ver` exist without re-enrollment. **Satisfies**: FR-015 / SC-008. **Proves**: T-J4-10.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Vitest/SQL test entries, harness config, or Documentation. Migration + `schema.snap.sql` are one FR-002..004 schema unit (A5/J1 precedent: snapshot reflects post-migration shape). Config-cache kind + identity accepted-`ver` check are one Sequencing step (plan → Sequencing §2; FR-001, FR-009, FR-010). Consumed B1/B3/B2/A5 modules are extended or imported, not rewritten (delivery plan §2.3). `data-model.md` and `contracts/token-contract-rotation.md` are already frozen — no task recreates them. Order follows plan Sequencing: migration → config-cache + identity → control → worker → clinic harness registration.

- [ ] T012 [US1] Create `ai-platform/migrations/20260803120000_token_contract.sql` — `CREATE TABLE token_contract (ver, added_at, retired_at, changed_by)` with **no** `retire_after` / TTL column; seed one accepted row `ver = '1'` (matches B1 default `ai.aat.ver`) so the stable set has exactly one member. Update `ai-platform/schema.snap.sql` so the snapshot matches the post-migration `token_contract` shape (FR-002, FR-003, FR-004; §7.3). **Satisfies**: FR-002, FR-003, FR-004. **Proved by**: T-J4-04 (and every case that seeds/reads the accepted set).
- [ ] T013 [US1] Modify `ai-platform/src/config-cache/index.ts` — extend `ConfigEntityKind` with `"token_contracts"` (forward-only; A5 contract file untouched). Modify `ai-platform/src/identity/index.ts` — after existing signature/audience/expiry/skew checks, `EnrolledKeyVerifier` loads the accepted set via `loadConfig(..., "token_contracts", …)`; accept every member; miss / retired / unknown → `{ ok: false, code: "unauthenticated" }`; no new taxonomy code; signature/audience/expiry/skew path unchanged (FR-001, FR-009, FR-010; plan → Sequencing §2). **Satisfies**: FR-001, FR-009, FR-010. **Proved by**: T-J4-01, T-J4-02, T-J4-03, T-J4-07.
- [ ] T014 [US1] Modify `ai-platform/src/control/index.ts` — `handleTokenContractBeginRotation` / `handleTokenContractRetire`; insert new `ver` while keeping prior; stamp `retired_at`; enforce at-most-two / return-to-one (FR-002); write `control_audit` with actions `token_contract_begin_rotation` / `token_contract_retire`; `dispatchControlRequest` routes (FR-005, FR-006, FR-007, FR-008). Does not redefine enroll / rotate / suspend / resume / delete or the `control_audit` row shape. Request path never writes `token_contract`. **Satisfies**: FR-005, FR-006, FR-007, FR-008. **Proved by**: T-J4-04, T-J4-05, T-J4-06, T-J4-07.
- [ ] T015 [US1] Modify `ai-platform/src/worker.ts` — dispatch new `/control/token-contract/...` paths to the control handlers (same `/control` boundary B2 froze; FR-008). **Satisfies**: FR-008. **Proved by**: T-J4-05, T-J4-06 (mutation path through the Worker control boundary).
- [ ] T016 [P] [US1] Modify `backend/tests/run_ai_platform_trust_tests.sh` — register `ai_token_contract_rotation.sql` in the trust suite so clinic SQL cases join CI permanently (plan → Files / Testing; delivery plan §3.10). No issuer rewrite; no new clinic migration. Depends on T009 (file to register exists). May run in parallel with T012–T015 (different file / layer). **Satisfies**: FR-011..FR-017 harness registration for T-J4-08 .. T-J4-10 clinic halves. **Proved by**: T-J4-08, T-J4-09, clinic half of T-J4-10 (when the trust suite runs them).

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T017 [US1] From `ai-platform/`, run this slice's Worker suites — `npx vitest run test/token-contract-rotation.test.ts` and `npx vitest run --config vitest.workers.config.ts test/token-contract-control.test.ts`. From the repo root, run this slice's clinic SQL via `bash backend/tests/run_ai_platform_trust_tests.sh` (includes the newly registered `ai_token_contract_rotation.sql`). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm J4's ten named cases (T-J4-01 .. T-J4-10) are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. The only error code this slice's `ver`-refusal path emits is existing `unauthenticated` (T-J4-02, T-J4-03); no new taxonomy code. Confirm inherited prohibitions hold: no auto-retire clock; no request-path `token_contract` write; no dual-mint; no re-enrollment; no second Quota DO / R2; no per-request server-side state; no §9.14 mechanism (§6.4). **Satisfies**: the §3.10 checkpoint rule (T-J4-01 .. T-J4-10 + prior suites). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. `data-model.md` and `contracts/token-contract-rotation.md` were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T018 [US1] Create `specs/051-token-contract-rotation/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.9 row J4; Implements §5.7, §5.6, §4.5, §7.3; what the spec delivered; what the plan scoped. **§2 What was implemented** — D1 `token_contract` migration + seed; begin-rotation / retire + `control_audit`; identity accepted-`ver` check via config cache; clinic SQL coverage for `ai.aat.ver` single mint; frozen `data-model.md` and `contracts/token-contract-rotation.md`. **§3 Files to review** — only this slice's migration, `src/identity/` / `src/control/` / `src/config-cache/` / `src/worker.ts` diffs, both Worker test files, clinic SQL file, trust-script registration, `data-model.md`, and the frozen contract (no prior-slice files). **§4 Prerequisites** — Miniflare D1 workers pool for control SQL tests; local Supabase for clinic SQL; one-time `npm install` in `ai-platform/`. **§5 Run the automated suite** — slice-only `npx vitest run test/token-contract-rotation.test.ts`, `npx vitest run --config vitest.workers.config.ts test/token-contract-control.test.ts`, and `psql -f backend/tests/ai_token_contract_rotation.sql` / trust-script entry for this file only (no full-suite `npm test`, no combined prior-slice counts). **§6 Inspect the changes** — grep `token_contract` / begin-rotation / retire; confirm no new taxonomy code; confirm issuer still reads `ai.aat.ver`. **§7 Manual validation** — omit; CI is the only verification path (plan). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — no dependencies; blocks the Worker Tests phase (workers include / Node exclude must be wired before any Worker test runs in the right pool).
- **Tests (T002–T011)** — depends on Setup for Worker files; every test is written against accepted-`ver` / control / mint behaviour that is absent or incomplete, so the files are red until the Implementation phase lands. T002–T005 append to `token-contract-rotation.test.ts` (sequential; T002 creates the substrate). T006–T008 append to `token-contract-control.test.ts` (T006 creates; `[P]` with T002). T009–T010 append to `ai_token_contract_rotation.sql` (T009 creates; `[P]` with T002/T006). T011 appends the no-re-enrollment halves to all three after their substrates exist.
- **Implementation (T012–T016)** — after tests exist (red). Order follows plan Sequencing: migration + snapshot (T012) → config-cache + identity (T013) → control begin-rotation / retire (T014) → worker routes (T015) → clinic trust-script registration (T016). Tests turn green in matching groups: T-J4-01/02/03/07 against seeded / spy cache with T013; T-J4-04/05/06 through the mutation path with T012–T015; T-J4-08/09/10 clinic halves with existing B1 issuer + T016 registration; T-J4-10 platform half with T013–T015.
- **Verification (T017)** — depends on T001–T016; runs this slice plus every prior slice per §3.10.
- **Documentation (T018)** — depends on T017 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: migration (T012) → config-cache + identity (T013) → control (T014) → worker (T015) → trust-script register (T016) → quickstart (T018).
- Vitest entry Files-section rows (`token-contract-rotation.test.ts`, `token-contract-control.test.ts`) and clinic SQL entry (`ai_token_contract_rotation.sql`) are produced by Phase 2; vitest config pair by Phase 1. Remaining Files units are T012–T016 plus T018 (`quickstart.md`). `data-model.md` and `contracts/token-contract-rotation.md` are already frozen — no task recreates them. `errors.ts` is unchanged (reuse existing `unauthenticated`).

### Parallel Opportunities

- Phase 1 (T001) is a single task — no internal parallelism.
- Phase 2: T006 `[P]` with T002 (different Worker test files). T009 `[P]` with T002/T006 (clinic SQL vs Worker files). T003–T005 append to the unit file — sequential, not `[P]`. T007–T008 append to the workers file — sequential. T010 appends to the clinic file — sequential after T009. T011 depends on all three substrates.
- Phase 3: T012 → T013 → T014 → T015 are sequential per plan Sequencing (migration before cache/identity reads; control before worker routes). T016 (trust-script registration) is `[P]` with T012–T015 after T009 exists (different file / layer — backend harness vs Worker impl).
- Phase 5 (T018) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Within each same-file test append chain there is no `[P]`.
- Every named test T-J4-01 .. T-J4-10 from `spec.md` is covered by its own task; no test is folded into another. T-J4-07 is a separate spy task (call absence), not merged into outcome assertions.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (B1, B3).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Combined related Files units only where the plan Sequencing or A5/J1 snapshot precedent requires them to land together: migration + `schema.snap.sql` (T012); config-cache kind + identity accepted-`ver` check (T013). Control and worker remain separate (J1 precedent).
- Preserve §6.4: no §9.14 mechanism; no timed auto-retire; no dual-mint; no re-enrollment as part of rotation; no second Quota DO / R2 object; no per-request server-side state; no new taxonomy code for retired/unknown `ver`; no Flutter AI surface; no rewrite of B1 keystore/issuer or B3 signature/audience/expiry/skew.
