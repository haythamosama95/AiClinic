# Tasks: Plan catalogue and credit-denominated entitlement (G1)

**Input**: Design documents from `specs/056-plan-catalogue/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` and `contracts/` (`plan-catalogue.md`, `credit-price.md`) are already frozen on disk (written during the plan phase). `AVAILABLE_DOCS`: `data-model.md`, `contracts/`. `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (thirteen cases) is covered by its own task, written to fail before the migration, catalogue handlers, entitle extension, and cache kind exist. Layers are **SQL / migration** (`migrations.test.ts`) and **Workers integration** (`plan-catalogue.test.ts`) (delivery plan §3.12.10 row G1; §13.5). Spy cases (the four `config_cache_*` call-count / absence asserts) each have their own task. Permanent suite joins CI (delivery plan §3.11).

**Organization**: One user story (US1, P1) — G1 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — plan Files names `vitest.workers.config.ts` and `vitest.config.ts` so `plan-catalogue.test.ts` joins the workers pool and is excluded from the Node pool. No Foundational or Polish phase — prerequisites are already-merged Needs (A5, B2) in the plan's Consumes Binding.

**Task count**: 24 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by G1*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by G1*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/056-plan-catalogue/`
- Catalogue CRUD lands under `ai-platform/src/control/plan.ts` beside `token-contract.ts` / `kill-switch.ts`; assignment extends I4 `entitle.ts`; cache kind `"plans"` extends A5 `ai-platform/src/config-cache/index.ts`. Consumed B2 lifecycle/auth and A5 cache mechanics stay unmodified aside from the listed extensions (delivery plan §2.3).

---

## Phase 1: Setup (Test harness)

**Purpose**: Plan Files names `ai-platform/vitest.workers.config.ts` and `ai-platform/vitest.config.ts` so this slice's workers integration file joins the workers pool and is excluded from the Node pool before or alongside the Tests phase (J1 harness pair).

- [X] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/plan-catalogue.test.ts"` to `include`. Modify `ai-platform/vitest.config.ts` — add `"test/plan-catalogue.test.ts"` to `exclude`, so the workers-pool-only cases do not double-run in the default Node pool (plan → Files). No FR — harness; required by every named integration test. Prepares the Phase 2 workers substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.10 row G1). Two SQL / migration cases live in the existing A5 harness `ai-platform/test/migrations.test.ts`. Eleven Workers integration cases (CRUD, assignment, override, non-operator, four cache spies) live in `ai-platform/test/plan-catalogue.test.ts`. Until the G1 migration, handlers, and `"plans"` kind exist, assertions fail — the intended red state. SQL file vs workers file are `[P]`; within each file, append sequentially.

- [X] T002 [P] [US1] Add named test `migrations_apply_cleanly_empty_database` to `ai-platform/test/migrations.test.ts` using the existing A5 `applyMigrations` harness: forward-only migrations apply cleanly to an empty database and the resulting schema includes `plan`, `credit_price`, and `entitlement.credit_budget` (Delivery Plan §3.12.10 G1 *Catalogue*; FR-007). Fails red until `ai-platform/migrations/20260911120000_plan_catalogue.sql` exists. Do not rewrite A5's existing apply/snapshot describes. **Satisfies**: FR-007 / SC-001. **Proves**: `migrations_apply_cleanly_empty_database`.

- [X] T003 [US1] Add named test `schema_snapshot_matches` to `ai-platform/test/migrations.test.ts`: after migration the schema snapshot matches and includes `plan`, `credit_price`, and the `entitlement` monthly credit-budget column (`credit_budget`) (and `max_cost_class`) (Delivery Plan §3.12.10 G1 *Catalogue*; §7.3; A15). Fails red until `ai-platform/schema.snap.sql` is updated. **Satisfies**: FR-007–FR-011 / SC-001. **Proves**: `schema_snapshot_matches`.

- [X] T004 [P] [US1] Create `ai-platform/test/plan-catalogue.test.ts` with the Workers integration substrate (Miniflare D1 + operator auth / `SELF.fetch` — same pattern as B2 `control.test.ts` and I4 `entitle-grant.test.ts`; `beforeAll` applies A5 + G1 migrations) and named test `plan_create_audit`: operator create-plan writes a `plan` row and a `control_audit` row carrying the operator identity (`action = plan_create`) (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5; §7.3). Fails red until `handlePlanCreate` and dispatch wiring exist. **Satisfies**: FR-005, FR-008, FR-013 / SC-002. **Proves**: `plan_create_audit`.

- [X] T005 [US1] Add named test `plan_update_audit` to `ai-platform/test/plan-catalogue.test.ts`: operator update-plan changes the `plan` row and journals `control_audit` carrying the operator identity (`action = plan_update`) (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5; §7.3). Fails red until `handlePlanUpdate` exists. **Satisfies**: FR-005, FR-013 / SC-002. **Proves**: `plan_update_audit`.

- [X] T006 [US1] Add named test `plan_delete_audit` to `ai-platform/test/plan-catalogue.test.ts`: operator delete-plan journals `control_audit` carrying the operator identity (`action = plan_delete`) and retains the `plan` row (full history, §7.3) (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5). Fails red until `handlePlanDelete` exists. **Satisfies**: FR-005, FR-013 / SC-002. **Proves**: `plan_delete_audit`.

- [X] T007 [US1] Add named test `plan_crud_non_operator_rejected` to `ai-platform/test/plan-catalogue.test.ts`: non-operator credentials are rejected on every plan CRUD mutation (create, update, delete); no `plan` or `control_audit` row is written; B2 `401 unauthorized` (no new diagnostic code) (Delivery Plan §3.12.10 G1 *Catalogue*; §4.5). Fails red until routes are operator-gated. **Satisfies**: FR-001, FR-006 / SC-002. **Proves**: `plan_crud_non_operator_rejected`.

- [X] T008 [US1] Add named test `assign_plan_populates_economics_one_audited_mutation` to `ai-platform/test/plan-catalogue.test.ts`: given operator credentials, a catalogue `plan`, and an enrolled installation whose `entitlement` is `pending`, assigning that plan populates monthly credit budget, request-count guard, `max_cost_class`, soft threshold, and capability set from the plan in one mutation, status becomes `active`, and `control_audit` carries the operator identity (Delivery Plan §3.12.10 G1 *Assignment*; A15; §4.5; §7.3). Fails red until `handleEntitle` reads the catalogue. **Satisfies**: FR-011, FR-014, FR-015 / SC-003. **Proves**: `assign_plan_populates_economics_one_audited_mutation`.

- [X] T009 [US1] Add named test `per_installation_override_recorded_as_such` to `ai-platform/test/plan-catalogue.test.ts`: an explicit per-installation override of a plan value is journaled as that override (`control_audit.action = override`), distinct from plan assignment (`entitle`) (Delivery Plan §3.12.10 G1 *Assignment*; §4.5; FR-016). Fails red until `handleOverride` exists. **Satisfies**: FR-016 / SC-004. **Proves**: `per_installation_override_recorded_as_such`.

- [X] T010 [US1] Add named test `assignment_non_operator_rejected` to `ai-platform/test/plan-catalogue.test.ts`: non-operator credentials are rejected on assign-plan and on override; no entitlement or audit write; B2 `401 unauthorized` (Delivery Plan §3.12.10 G1; §4.5). Fails red until entitle/override routes are operator-gated. **Satisfies**: FR-001, FR-006 / SC-002. **Proves**: `assignment_non_operator_rejected`.

- [X] T011 [US1] Add named spy test `config_cache_plan_cold_one_d1_read` to `ai-platform/test/plan-catalogue.test.ts`: serving a plan from a cold isolate via `loadConfig(..., "plans", ...)` performs exactly one `D1Reader.read` (A5 spy substrate `makeReader` / `readCount` from `ai-platform/test/config-cache.test.ts`; do not modify that file) (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2). Fails red until kind `"plans"` exists. **Satisfies**: FR-017 / SC-005. **Proves**: `config_cache_plan_cold_one_d1_read`.

- [X] T012 [US1] Add named spy test `config_cache_plan_warm_zero_io` to `ai-platform/test/plan-catalogue.test.ts`: serving a plan from a warm isolate whose config cache is populated performs zero I/O (`readCount === 0`) (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2). Spy — absence of I/O is separate from T011's cold call-count. **Satisfies**: FR-017 / SC-005. **Proves**: `config_cache_plan_warm_zero_io`.

- [X] T013 [US1] Add named spy test `config_cache_entitlement_cold_one_d1_read` to `ai-platform/test/plan-catalogue.test.ts`: serving an entitlement (including the monthly credit-budget column `credit_budget`) from a cold isolate performs exactly one D1 read (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2; A15). Fails red until loaded entitlement rows include `credit_budget`. **Satisfies**: FR-010, FR-017 / SC-005. **Proves**: `config_cache_entitlement_cold_one_d1_read`.

- [X] T014 [US1] Add named spy test `config_cache_entitlement_warm_zero_io` to `ai-platform/test/plan-catalogue.test.ts`: serving an entitlement from a warm isolate performs zero I/O (Delivery Plan §3.12.10 G1 *Cache*; §4.3.2). Spy — absence of I/O is separate from T013's cold call-count. **Satisfies**: FR-017 / SC-005. **Proves**: `config_cache_entitlement_warm_zero_io`.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Setup (T001), Tests (Phase 2), or Documentation. Order follows plan Sequencing (migration → snapshot → config-cache kind → types → plan CRUD → entitle/override → dispatch → I4 seed). Consumed B2 lifecycle/auth and A5 cache mechanics are extended or imported, not rewritten (delivery plan §2.3). Do not touch `ai-platform/src/pricing/`, B4 `EntitlementSnapshot` / Quota DO, or `lifecycle.ts` enroll.

- [X] T015 [P] [US1] Create `ai-platform/migrations/20260911120000_plan_catalogue.sql` — forward-only additive `CREATE TABLE plan` (name, monthly credit budget, request-count guard, `max_cost_class`, soft threshold, capability set, status), `CREATE TABLE credit_price` (version, price per credit, currency, `active_from`, `activated_by`), `ALTER TABLE entitlement ADD COLUMN credit_budget INTEGER NOT NULL DEFAULT 0`, `ALTER TABLE entitlement ADD COLUMN max_cost_class TEXT NOT NULL DEFAULT ''`. No FK from `entitlement.plan` to `plan.name`. Do not activate `credit_price` rows. **Satisfies**: FR-007–FR-011. **Proved by**: `migrations_apply_cleanly_empty_database`, `schema_snapshot_matches`.

- [X] T016 [US1] Modify `ai-platform/schema.snap.sql` so the snapshot matches the post-migration schema and includes `plan`, `credit_price`, and the entitlement `credit_budget` (and `max_cost_class`) columns (FR-007; A5 snapshot discipline). Depends on T015. **Satisfies**: FR-007. **Proved by**: `schema_snapshot_matches`.

- [X] T017 [P] [US1] Modify `ai-platform/src/config-cache/index.ts` — extend `ConfigEntityKind` with `"plans"` (same forward-only pattern as `"token_contracts"`); add a `createD1ConfigReader` branch `SELECT * FROM plan WHERE name = ?` for `plans:{name}`. Do not rewrite TTL, miss semantics (`ConfigCacheMissError`), ownership, or existing kinds. Do not cache `credit_price`. Do not edit A5 `specs/019-ai-context-keys-d1-config/contracts/config-cache.md`. **Satisfies**: FR-017, FR-018. **Proved by**: `config_cache_plan_cold_one_d1_read`, `config_cache_plan_warm_zero_io`, `config_cache_entitlement_cold_one_d1_read`, `config_cache_entitlement_warm_zero_io`.

- [X] T018 [P] [US1] Modify `ai-platform/src/control/types.ts` — add `PlanPayload` / `OverridePayload` (and related) only. Plan payload: name, monthly credit budget, request-count guard, `max_cost_class`, soft threshold, capability set, status. Override payload: quota, budget (`credit_budget` and/or token/cost), period bounds, or soft threshold. Do not alter B2 lifecycle or I4 `EntitlePayload` grant fields. **Satisfies**: FR-008, FR-015, FR-016. **Proved by**: `plan_create_audit`, `assign_plan_populates_economics_one_audited_mutation`, `per_installation_override_recorded_as_such`.

- [X] T019 [US1] Create `ai-platform/src/control/plan.ts` — `handlePlanCreate` / `handlePlanUpdate` / `handlePlanDelete` as operator-authenticated control-plane mutations. Create/update write the `plan` row; delete journals and retains the row (full history). Journal `control_audit` with operator identity and actions `plan_create` / `plan_update` / `plan_delete`. Reject non-operator with B2 `401 unauthorized`; no catalogue or audit write. Use B2 `requireOperator` / `writeAudit` / `runControlBatch` helpers — Consumes, do not rewrite. Depends on T018. **Satisfies**: FR-001, FR-002, FR-005, FR-006, FR-008, FR-013. **Proved by**: `plan_create_audit`, `plan_update_audit`, `plan_delete_audit`, `plan_crud_non_operator_rejected`.

- [X] T020 [P] [US1] Modify `ai-platform/src/control/entitle.ts` — extend `handleEntitle` to `SELECT` the catalogue row (by enrolled `entitlement.plan`, or body `plan` then that name) and copy monthly credit budget, request-count guard, `max_cost_class`, soft threshold, and capability set onto the entitlement in the same D1 batch as I4's grant + audit writes; set `status = 'active'`. Add `handleOverride` on `POST /control/installations/{id}/override` with distinct `control_audit.action = override` and before/after pointer recording the change. Reject non-operator with B2 `401 unauthorized`; no entitlement or audit write. Do not reimplement I4 grant/revoke or self-heal. Do not debit `credit_budget`. Depends on T018 (payload types) and T015 (columns exist). **Satisfies**: FR-002, FR-005, FR-006, FR-011, FR-012, FR-014, FR-015, FR-016. **Proved by**: `assign_plan_populates_economics_one_audited_mutation`, `per_installation_override_recorded_as_such`, `assignment_non_operator_rejected`.

- [X] T021 [US1] Modify `ai-platform/src/control/index.ts` — extend `isControlRoute` / `dispatchControlRequest` for plan CRUD (`POST /control/plans/create`, `POST /control/plans/{name}/update`, `POST /control/plans/{name}/delete`) and override (`POST /control/installations/{id}/override`) without altering lifecycle, entitle, or other control routes (Consumes B2 barrel). Depends on T019 and T020. **Satisfies**: FR-001, FR-006. **Proved by**: `plan_create_audit`, `plan_crud_non_operator_rejected`, `assignment_non_operator_rejected`, `per_installation_override_recorded_as_such`.

- [X] T022 [US1] Modify `ai-platform/test/entitle-grant.test.ts` — seed a matching `plan` row so I4 entitle assertions stay green after assignment reads the catalogue. Do not rewrite I4 grant assertions. Depends on T015 (table) and T020 (catalogue read). **Satisfies**: FR-014, FR-015. **Proved by**: I4 entitle cases remaining green under Verification (and G1 `assign_plan_populates_economics_one_audited_mutation` as the catalogue-read behaviour).

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T023 [US1] From `ai-platform/`, run this slice's SQL suite — `npx vitest run test/migrations.test.ts` (named cases `migrations_apply_cleanly_empty_database`, `schema_snapshot_matches`). Run this slice's Workers suite — `npx vitest run --config vitest.workers.config.ts test/plan-catalogue.test.ts` (named cases `plan_create_audit` … `config_cache_entitlement_warm_zero_io`). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including I4 `entitle-grant.test.ts`). Confirm G1's thirteen named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: `lifecycle.ts` / enroll unchanged (FR-003, FR-004); A5 `contracts/config-cache.md` and B2 `contracts/control-plane.md` not rewritten; `ai-platform/src/pricing/` untouched (FR-020); no `credit_price` cache kind (FR-019); no overage, debit, `quota_exhausted`, period close, invoice, or usage gauge (FR-021); no B4 `EntitlementSnapshot` / Quota DO field changes; no §9.14 mechanism; no second Quota DO / R2; no per-request server-side state (delivery plan §6.4). **Satisfies**: the §3.10 checkpoint rule (thirteen named tests + prior suites). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts and `data-model.md` were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T024 [US1] Create `specs/056-plan-catalogue/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.13 row G1; `01-ai-platform.md` §4.5 / §7.3 / §4.3.2 / A15; what the spec delivered; what the plan scoped. **§2 What was implemented** — additive `plan` / `credit_price` / `credit_budget` (and `max_cost_class`) migration; operator plan CRUD; plan-based entitle assignment; per-installation override; config-cache kind `"plans"`. **§3 Files to review** — only this slice's migration, `src/control/plan.ts`, entitle extension, config-cache kind/reader, this slice's workers test file, and the schema snapshot (no prior-slice files). **§4 Prerequisites** — Node/workers pool; `OPERATOR_*` bindings when exercising `SELF.fetch` control e2e (same as B2). **§5 Run the automated suite** — slice-only `npx vitest run test/migrations.test.ts` and `npx vitest run --config vitest.workers.config.ts test/plan-catalogue.test.ts`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open migration + `plan.ts` + entitle copy-from-catalogue; grep `credit_budget` / `ConfigEntityKind` `"plans"`; confirm Consumes modules not rewritten. **No §7 Manual validation** — CI is the only verification path (plan). Renumber remaining sections sequentially with no gaps. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — none; can start immediately. Workers-pool include / Node-pool exclude for `plan-catalogue.test.ts`.
- **Tests (T002–T014)** — T002 `[P]` relative to T001 (Node-pool `migrations.test.ts` already exists). T003 appends after T002 (same file). T004 depends on T001 (workers include); T005–T014 append sequentially after T004 (same workers file). Written to fail before migration / handlers / `"plans"` kind exist.
- **Implementation (T015–T022)** — after tests exist (red). Order follows plan Sequencing: migration (T015) → snapshot (T016) → config-cache kind (T017) → types (T018) → plan CRUD (T019) → entitle/override (T020) → dispatch (T021) → I4 seed (T022).
- **Verification (T023)** — depends on T001–T022; runs this slice's SQL + workers suites plus every prior suite per §3.10.
- **Documentation (T024)** — depends on T023 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: migration (T015) → snapshot (T016) → config-cache kind (T017) → PlanPayload/OverridePayload (T018) → `plan.ts` CRUD (T019) → `handleEntitle` catalogue copy + `handleOverride` (T020) → control dispatch (T021) → I4 seed (T022); Documentation last.
- Test-file and harness Files-section rows are produced by Phase 1–2. Remaining Files units are T015–T022 plus T024 (`quickstart.md`). Consumed A5/B2 modules remain unchanged aside from listed extensions.

### Parallel Opportunities

- Phase 1 (T001) is a single harness-pair task — no internal parallelism.
- Phase 2: T002 is `[P]` relative to T001 and T004 (different file). T004 is `[P]` relative to T002–T003 (workers file vs SQL harness). Within each suite file, append sequentially (no `[P]`). Spy cases T011–T014 remain separate tasks from each other and from outcome asserts T008–T010.
- Phase 3: T015 is `[P]` relative to T017 and T018 (migration vs cache kind vs payload types — different files). T017 is `[P]` relative to T018–T020 (cache vs control). T020 is `[P]` relative to T019 (entitle.ts vs plan.ts — different files, both depend on T018). T016 depends on T015; T019 on T018; T021 on T019 and T020; T022 on T015 and T020.
- Phase 5 (T024) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T002, T004, T015, T017, T018, T020.
- Every named test from `spec.md` is covered by its own task; no test is folded into another. Spy cases `config_cache_plan_cold_one_d1_read`, `config_cache_plan_warm_zero_io`, `config_cache_entitlement_cold_one_d1_read`, and `config_cache_entitlement_warm_zero_io` are each a separate task (call-count / absence asserts).
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart / harness Setup. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are A5, B2 (Consumes Binding).
- Consumed modules are imported/bound, not rewritten (delivery plan §2.3 — extend, never rewrite). G1 does not absorb G2 debit, G3 gauge, or G4 invoice/activation (FR-021).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no second Quota DO or R2 object; no per-request server-side state; no Flutter catalogue UI (V4 later); request path never sees a price (FR-019).
