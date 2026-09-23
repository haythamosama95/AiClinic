# Tasks: Catalogue price/display/`grace_days`, `credit_price` withdrawal, plan-delete fix (M1)

**Input**: Design documents from `specs/061-catalogue-grace-days/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is the ABO architecture corpus and AP-ARCH A17). `data-model.md` and `quickstart.md` are already on disk from the plan phase (`AVAILABLE_DOCS`: `data-model.md`, `quickstart.md`). `contracts/` is **not** produced (FR-017 / P2 owns `GET /v1/plans`). `quickstart.md` is finalized in Phase 5 (Documentation) after the suite is green.

**Tests**: Tests are mandatory (Delivery Plan §3.11; DP-3). Every named §3.12.1 floor case for row **M1** (spec `### Test plan` / Delivery Plan §3.12.1 M1 Required cases) is its own task, written to fail before the migration, credit-price withdrawal, and plan CRUD/delete fix exist. Layer is **SQL / migration + integration**. The grep absence of `credit_price` / `CreditPriceActivatePayload` / `credit-price` is a spy case and has its own task. **Band matrix rows (M1-V*, M-E*, M-X*) are excluded** — `/abo-verify` only. Permanent suite joins CI (§3.11).

**Organization**: One user story (US1, P1) — M1 is one slice, one story (ABO specify override; plan). No cross-story parallelism section. **No Setup phase** — plan Files leaves `vitest.workers.config.ts` / `vitest.config.ts` unchanged (no new test file). No Foundational or Polish phase — prerequisites are already-merged Needs (G1) in the plan's Consumes Binding.

**Task count**: 21 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by M1*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by M1*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/061-catalogue-grace-days/`
- M1 extends G1 `plan.ts` / `PlanPayload` / `plan-catalogue.test.ts` and the A5/G1 migrations harness; withdraws `credit-price.ts` and strips `period-close` `credit_price` reads. No `ai-billing-orchestrator/`, `frontend/`, or `backend/` change. Consumed G1 contract files are not rewritten (delivery plan §2.3).

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per §3.12.1 M1 floor case (Migration / Code / Bug fix). Migration cases live in `ai-platform/test/migrations.test.ts`. Code + Bug fix cases live in `ai-platform/test/plan-catalogue.test.ts`, except the withdrawn activate → 404 case which lives in the adjusted `ai-platform/test/price-list-activation.test.ts` (plan Test Layout). Until the M1 migration, withdrawal, and plan CRUD/delete fix exist, assertions fail — the intended red state. The three suite files are `[P]` relative to each other; within each file, append sequentially.

- [X] T001 [P] [US1] Add named test `m1_migration_applies_empty_database_snapshot_pinned` to `ai-platform/test/migrations.test.ts` using the existing A5/G1 `applyMigrations` harness: the M1 forward-only migration applies cleanly to an empty database and the pinned schema snapshot includes `grace_days INTEGER NOT NULL DEFAULT 7` on `plan` and does not include `credit_price` (Delivery Plan §3.12.1 M1 *Migration*; Acceptance Scenario 1). Fails red until `ai-platform/migrations/20260923120000_catalogue_grace_days.sql` and the updated `schema.snap.sql` exist. Do not rewrite A5/G1 existing apply/snapshot describes beyond extending asserts for M1 — the G1-era `credit_price` presence asserts (`G1_CATALOGUE_TABLES`; the `schema_snapshot_matches` `CREATE TABLE credit_price` expectation) are retired by the A17 withdrawal and adjusted under T019, not here. **Satisfies**: FR-001–FR-004 / SC-001. **Proves**: `m1_migration_applies_empty_database_snapshot_pinned`.

- [X] T002 [US1] Add named test `m1_migration_applies_over_existing_catalogue` to `ai-platform/test/migrations.test.ts`: given the existing pre-A17 catalogue (seeded `plan` rows and existing `credit_price` rows), the M1 forward-only migration applies cleanly; existing `plan` rows are preserved with `grace_days` defaulted; `credit_price` is absent from the pinned snapshot; no down migration (Delivery Plan §3.12.1 M1 *Migration*; Acceptance Scenario 2). Fails red until the M1 migration applies over that catalogue. **Satisfies**: FR-002, FR-004 / SC-001. **Proves**: `m1_migration_applies_over_existing_catalogue`.

- [X] T003 [P] [US1] Add named spy test `m1_no_credit_price_reference_in_src` to `ai-platform/test/plan-catalogue.test.ts`: a grep over `ai-platform/src/` finds zero matches for `credit_price`, `CreditPriceActivatePayload`, and `credit-price`; `src/control/credit-price.ts` is absent (Delivery Plan §3.12.1 M1 *Code*; Acceptance Scenario 3). Spy — absence is separate from the activate-404 outcome. Fails red until the module, type, route, and period-close reads are withdrawn. **Satisfies**: FR-005 / SC-002. **Proves**: `m1_no_credit_price_reference_in_src`.

- [X] T004 [P] [US1] Adjust `ai-platform/test/price-list-activation.test.ts` — withdraw G4 activate happy-path writes that require the `credit_price` table; add named test `m1_credit_price_activate_returns_404`: `POST /control/credit-price/activate` returns 404 because the route is unregistered; no `credit_price` table dependency (Delivery Plan §3.12.1 M1 *Code*; Acceptance Scenario 4; plan Files). Fails red until the route is unregistered. **Satisfies**: FR-005, FR-006 / SC-005. **Proves**: `m1_credit_price_activate_returns_404`.

- [X] T005 [US1] Add named test `m1_plan_crud_a17_fields_round_trip_audited` to `ai-platform/test/plan-catalogue.test.ts`: with valid operator credentials, plan create/update carrying `price_cents` / `currency` / `display_name` / `description` / `grace_days` round-trips those fields exactly and writes the usual `control_audit` row (`plan_create` / `plan_update`); omitting `grace_days` on create stores `7`; explicit `grace_days = 0` is stored as `0`; invalid payloads (negative `grace_days`, negative or non-integer `price_cents`, empty `currency`, empty `display_name`) return `400` `invalid_payload` with no row and no audit; update of only A17 fields leaves G1 economics columns unchanged and writes `plan_update` audit (Delivery Plan §3.12.1 M1 *Code*; Acceptance Scenario 5; plan Test Layout). Fails red until `PlanPayload` and `plan.ts` accept/persist/validate A17 fields. **Satisfies**: FR-009–FR-012 / SC-003. **Proves**: `m1_plan_crud_a17_fields_round_trip_audited`.

- [X] T006 [US1] Add named test `m1_plan_crud_non_operator_rejected` to `ai-platform/test/plan-catalogue.test.ts`: credentials that are not a valid operator credential are rejected on plan create, update, and delete with `401` `{"error":"unauthorized"}`; no catalogue or audit row is written (Delivery Plan §3.12.1 M1 *Code*; Acceptance Scenario 6). Fails red until routes remain operator-gated via B2 `requireOperator`. **Satisfies**: FR-016 / SC-005. **Proves**: `m1_plan_crud_non_operator_rejected`.

- [X] T007 [US1] Add named test `m1_plan_delete_removes_row_and_audits` to `ai-platform/test/plan-catalogue.test.ts`: with valid operator credentials and an existing plan, `POST /control/plans/{name}/delete` removes the `plan` row and writes a `plan_delete` `control_audit` row; delete still succeeds when `entitlement.plan` / `invoice.plan` reference the name (referencing rows untouched — no FK) (Delivery Plan §3.12.1 M1 *Bug fix*; Acceptance Scenario 7; FR-015). Fails red until `handlePlanDelete` issues `DELETE FROM plan` in the same batch as the audit. **Satisfies**: FR-013, FR-015 / SC-004. **Proves**: `m1_plan_delete_removes_row_and_audits`.

- [X] T008 [US1] Add named test `m1_plan_delete_unknown_returns_404` to `ai-platform/test/plan-catalogue.test.ts`: with valid operator credentials and an unknown plan name, `POST /control/plans/{name}/delete` returns `404` `plan_not_found` and writes no audit row (Delivery Plan §3.12.1 M1 *Bug fix*; Acceptance Scenario 8). Fails red until unknown-name handling is preserved alongside the real delete. **Satisfies**: FR-014 / SC-004. **Proves**: `m1_plan_delete_unknown_returns_404`.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Tests (Phase 1) or Documentation. Order follows plan Sequencing (migration → snapshot → credit-price withdrawal → plan CRUD A17 → plan delete fix → G4 period-close fallout → G1 suite fallout). Test-file Files rows `migrations.test.ts`, `plan-catalogue.test.ts`, and `price-list-activation.test.ts` are produced by Phase 1. `data-model.md` / plan-phase `quickstart.md` stub are not recreated here. Consumed G1 assign/enroll/cache and B2 auth stay unmodified aside from the listed extensions (delivery plan §2.3). Do not implement `GET /v1/plans`, period-close repricing, `purchase_proof`, or invoice reshape (FR-017).

- [X] T009 [P] [US1] Create `ai-platform/migrations/20260923120000_catalogue_grace_days.sql` — forward-only `ALTER TABLE plan ADD` `price_cents`, `currency`, `display_name`, `description`, and `grace_days INTEGER NOT NULL DEFAULT 7`; `DROP TABLE credit_price`; no down migration. Non-grace A17 columns use SQLite-required backfill defaults on ALTER so the migration applies over an existing catalogue (FR-004); create/update validation still rejects empty/invalid values (FR-011). **Satisfies**: FR-001, FR-002, FR-004. **Proved by**: `m1_migration_applies_empty_database_snapshot_pinned`, `m1_migration_applies_over_existing_catalogue`.

- [X] T010 [US1] Modify `ai-platform/schema.snap.sql` so the snapshot pins A17 `plan` columns including `grace_days … DEFAULT 7` and shows `credit_price` absent (FR-003; A5 snapshot discipline). Depends on T009. **Satisfies**: FR-003 / SC-001. **Proved by**: `m1_migration_applies_empty_database_snapshot_pinned`, `m1_migration_applies_over_existing_catalogue`.

- [X] T011 [P] [US1] Modify `ai-platform/src/control/types.ts` — extend `PlanPayload` with A17 fields (`price_cents`, `currency`, `display_name`, `description`, `grace_days`); remove `CreditPriceActivatePayload`. Do not rewrite G1 economics payload fields. **Satisfies**: FR-005, FR-009. **Proved by**: `m1_no_credit_price_reference_in_src`, `m1_plan_crud_a17_fields_round_trip_audited`.

- [X] T012 [US1] Modify `ai-platform/src/control/plan.ts` — accept/persist A17 fields on create/update with `control_audit`; omit `grace_days` → schema default `7`; explicit `0` stored; invalid A17 payloads → `400` `invalid_payload` with no writes; update-only A17 leaves G1 economics unchanged; fix `handlePlanDelete` to `DELETE FROM plan` in the same batch as `plan_delete` audit; unknown plan → `404` `plan_not_found` with no audit; non-operator → `401` with no writes (B2 `requireOperator` / batch helpers — Consumes, do not rewrite). Depends on T011 (and T009 for columns). **Satisfies**: FR-009–FR-016. **Proved by**: `m1_plan_crud_a17_fields_round_trip_audited`, `m1_plan_crud_non_operator_rejected`, `m1_plan_delete_removes_row_and_audits`, `m1_plan_delete_unknown_returns_404`.

- [X] T013 [P] [US1] Delete `ai-platform/src/control/credit-price.ts` (module gone; activate path withdrawn) (FR-005, FR-006). **Satisfies**: FR-005, FR-006. **Proved by**: `m1_no_credit_price_reference_in_src`, `m1_credit_price_activate_returns_404`.

- [X] T014 [US1] Modify `ai-platform/src/control/index.ts` — remove credit-price route registration and export so `POST /control/credit-price/activate` is unregistered (404). Depends on T013. Do not alter plan route paths except as needed for existing plan CRUD dispatch. **Satisfies**: FR-005, FR-006. **Proved by**: `m1_credit_price_activate_returns_404`, `m1_no_credit_price_reference_in_src`.

- [ ] T015 [P] [US1] Modify `ai-platform/src/period-close/index.ts` — remove `credit_price` reads / `resolveCreditPrice`; issue no invoices until M2 (spec Assumptions; FR-017). Do not implement purchase-proof pricing. **Satisfies**: FR-005, FR-017. **Proved by**: `m1_no_credit_price_reference_in_src`.

- [X] T016 [US1] Modify `ai-platform/test/period-close.test.ts` — remove `credit_price` fixtures; stop asserting G-era credits×price invoices (M2 owns repricing). Depends on T015. Do not add M2 purchase-proof cases. **Satisfies**: FR-005, FR-017. **Proved by**: prior G4 suite remaining green under Verification once fallout is applied; `m1_no_credit_price_reference_in_src`.

- [X] T019 [P] [US1] Modify `ai-platform/test/migrations.test.ts` — G1 suite fallout for the A17 withdrawal: remove `"credit_price"` from `G1_CATALOGUE_TABLES` (a post-M1 empty-database apply no longer creates the dropped table) and change the G1 `schema_snapshot_matches` `expect(expectedDdl).toMatch(/CREATE TABLE\s+credit_price\b/i)` presence expectation into an absence expectation (`not.toMatch`, mirroring the M1 cases). Do not otherwise rewrite A5/G1 describes; G1 economics-column asserts (`credit_budget`, `max_cost_class`) stay. Depends on T009, T010. **Satisfies**: FR-002, FR-003 / SC-001. **Proved by**: `migrations_apply_cleanly_empty_database` and `schema_snapshot_matches` green under T017.

- [X] T020 [US1] Modify `ai-platform/test/plan-catalogue.test.ts` harness — import `../migrations/20260923120000_catalogue_grace_days.sql?raw` and apply it in `beforeAll` after `planCatalogueSql` so every case in the file (G1-era and M1 floor) runs against the post-M1 schema. Leave the inline `invoiceMigrationSql` application inside `m1_plan_delete_removes_row_and_audits` as-is (moving it into `beforeAll` would double-create `invoice`). Depends on T009. **Satisfies**: FR-001, FR-004 — harness enablement for the §3.12.1 M1 Code / Bug fix floor. **Proved by**: T005–T008 floor cases able to see the A17 columns; suite green under T017.

- [X] T021 [US1] Modify `ai-platform/test/plan-catalogue.test.ts` G1 fixtures/asserts — (a) extend `DEFAULT_PLAN_PAYLOAD` with valid A17 fields (`price_cents`, `currency`, `display_name`, `description`; `grace_days` optional) so G1-era `plan_create_audit` / `plan_update` cases pass FR-011 validation instead of 400ing; (b) `seedCataloguePlan`'s raw INSERT needs no A17 columns — the migration's SQLite backfill defaults cover raw INSERTs — adjust only if a NOT NULL A17 column lacks a usable default; (c) update `plan_delete_audit` to assert the `plan` row is removed (FR-013) while keeping the `plan_delete` audit assertion — the G-era "retains the plan row" assert pinned the audit-only delete bug M1 fixes. Depends on T020 and T012. **Satisfies**: FR-011, FR-013 / SC-003, SC-004. **Proved by**: G1-era describes green under T017 alongside the M1 floor cases.

---

## Phase 3: Verification

**Purpose**: Delivery Plan §3.11 — slice floor green plus every prior suite green (checkpoints need all prior suites green). **Do not** implement band matrix rows (M1-V*, M-E*, M-X*) here.

- [ ] T017 [US1] From `ai-platform/`, run this slice's SQL suite — `npx vitest run test/migrations.test.ts` (named cases `m1_migration_applies_empty_database_snapshot_pinned`, `m1_migration_applies_over_existing_catalogue`). Run this slice's Workers suite — `npx vitest run --config vitest.workers.config.ts test/plan-catalogue.test.ts` (named cases `m1_no_credit_price_reference_in_src` … `m1_plan_delete_unknown_returns_404`) and `npx vitest run --config vitest.workers.config.ts test/price-list-activation.test.ts` (`m1_credit_price_activate_returns_404`). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including adjusted `period-close.test.ts`). Confirm M1's eight named floor cases are green and every prior suite stays green. Confirm `grep` over `ai-platform/src/` is clean for `credit_price` / `CreditPriceActivatePayload` / `credit-price`. Confirm G1 contract files / entitle / enroll / config-cache kind untouched; no `GET /v1/plans`; no ABO plan/price table; no clinic Postgres write; request path never sees a price (Delivery Plan §5.3 / FR-017). No new test is added here — this is the §3.11 checkpoint gate. **Satisfies**: the §3.11 checkpoint rule (eight named floor cases + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. Finalize `specs/061-catalogue-grace-days/quickstart.md` per `.specify/templates/abo-quickstart-template.md` after the suite is green. `data-model.md` was frozen during the plan phase — no separate task. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T018 [US1] Finalize `specs/061-catalogue-grace-days/quickstart.md` from `.specify/templates/abo-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — Delivery Plan §3.2 row M1; Implements A17 items 1–2, A15 item 4; ABO §4.1.6 / §4.2 / §5.10 (columns only); what the spec delivered; what the plan scoped. **§2 What was implemented** — A17 plan columns migration; `credit_price` drop + control withdrawal; plan CRUD carrying A17 fields; plan-delete fix; period-close stripped of `credit_price` reads (temporary until M2). **§3 Files to review** — only this slice's migration, plan/types/index/period-close changes, deleted credit-price module, this slice's test files, schema snapshot (no prior-slice files). **§4 Prerequisites** — Node/workers pool; `OPERATOR_*` bindings for `SELF.fetch` control e2e (same as G1/B2). **§5 Run the automated suite** — slice-only vitest commands from Test Layout; no full-suite `npm test`, no band e2e/x-e2e. **§6 Inspect the changes** — open migration + `plan.ts` delete batch; grep `credit_price` over `src/` (expect zero); confirm G1 economics columns untouched. **No §7 Manual validation** — CI / floor suite is the verification path (plan). Renumber remaining sections sequentially with no gaps. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T008)** — no Setup prerequisite. T001 / T003 / T004 are `[P]` relative to each other (three different files). T002 appends after T001 (same `migrations.test.ts`). T005–T008 append sequentially after T003 (same `plan-catalogue.test.ts`). Written to fail before migration / withdrawal / plan CRUD/delete fix exist.
- **Implementation (T009–T016, T019–T021)** — after tests exist (red). Order follows plan Sequencing: migration (T009) → snapshot (T010) → types (T011) + credit-price delete (T013) + period-close strip (T015) in parallel where files differ → plan CRUD/delete (T012) → index unregister (T014) → period-close test fallout (T016) → G1 suite fallout (T019–T021).
- **Verification (T017)** — depends on T001–T021; runs this slice's floor suites plus every prior suite per §3.11.
- **Documentation (T018)** — depends on T017 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: migration (T009) → snapshot (T010) → credit-price withdrawal (T011 type removal + T013 delete + T014 unregister + T015 period-close) → plan CRUD A17 + delete fix (T012) → G4 period-close test fallout (T016) → G1 suite fallout (T019 migrations asserts; T020 plan-catalogue harness; T021 fixtures + delete assert); Documentation last.
- Test-file Files-section rows are produced by Phase 1. Remaining Files units are T009–T016, the G1 fallout tasks T019–T021 (same two test files, withdrawal/delete-fix fallout only), plus T018 (`quickstart.md`). Consumed G1/B2 modules remain unchanged aside from listed extensions.

### Parallel Opportunities — explicit `[P]` batches

1. **Tests batch A (three files):** T001 `[P]` (`migrations.test.ts`), T003 `[P]` (`plan-catalogue.test.ts`), T004 `[P]` (`price-list-activation.test.ts`) — start together.
2. **Tests sequential within file:** T002 after T001; T005 → T006 → T007 → T008 after T003 (same `plan-catalogue.test.ts`).
3. **Implementation batch B (four files, after red tests):** T009 `[P]` (migration SQL), T011 `[P]` (`types.ts`), T013 `[P]` (delete `credit-price.ts`), T015 `[P]` (`period-close/index.ts`) — start together once Phase 1 exists.
4. **Implementation sequential:** T010 after T009 (snapshot); T012 after T011 and T009 (`plan.ts`); T014 after T013 (`index.ts`); T016 after T015 (`period-close.test.ts`).
5. **G1 fallout batch (after T009/T010; T021 also after T012):** T019 `[P]` (`migrations.test.ts`) runs parallel to T020 (`plan-catalogue.test.ts` harness) — different files; T021 appends after T020 (same file).
6. **Verification / Documentation:** T017 then T018 — no internal `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T001, T003, T004, T009, T011, T013, T015, T019.
- **G1 suite fallout is authorized A17 / delete-fix fallout, not a frozen-contract rewrite.** The G1-era asserts that pin `credit_price` presence (`G1_CATALOGUE_TABLES`; the `schema_snapshot_matches` `CREATE TABLE credit_price` expectation) and the audit-only delete (`plan_delete_audit` row retention) contradict FR-002 / FR-003 and FR-013 once M1 lands; T019–T021 adjust exactly those asserts plus the harness and fixtures they depend on. Frozen G1 contract files (`specs/056-plan-catalogue/contracts/*`) remain untouched (delivery plan §2.3).
- Every §3.12.1 M1 floor case from `spec.md` / Delivery Plan §3.12.1 is covered by its own task; the grep spy is separate from the activate-404 outcome. Edge-case asserts named under plan Test Layout for Code / Bug fix (omit/`0`/invalid/economics-unchanged; referenced-name delete) are folded into T005 and T007 — they are not separate Test plan IDs and are not band-matrix rows.
- **No band-matrix ids** (M1-V*, M-E*, M-X*, MC-*) appear in this task list — those belong to `/abo-verify`.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.11 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are G1 (Consumes Binding). No Setup — harness configs unchanged.
- Consumed modules are imported/bound, not rewritten (delivery plan §2.3 — extend, never rewrite). M1 does not absorb M2 / P2 / Band N.
- Tests land before or alongside their implementation, never after.
- Preserve Delivery Plan §5.3 / AP §6.4: no shared bearer; no ABO plan/price table; no clinic Postgres write; no money on the request path; no `GET /v1/plans` in this slice (FR-017).
