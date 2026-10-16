---

description: "Task list for slice B2 — Control-plane enrollment and installation lifecycle"
---

# Tasks: Control-plane enrollment and installation lifecycle (B2)

**Input**: `specs/022-control-plane-enrollment/spec.md`, `specs/022-control-plane-enrollment/plan.md`

**Prerequisites**: plan.md (required), spec.md (required). A5
(`specs/019-ai-context-keys-d1-config/`) and its migration
`ai-platform/migrations/20260731120000_platform_schema.sql` are merged and bound, not modified
(plan → Consumes Binding).

**Tests**: Mandatory on this platform (delivery plan §3.10). Every named test in the spec's Test plan
is a task, written to fail before the code exists.

**Organization**: One slice = one user story = one `[US1]` label. No cross-story parallelism section.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: `US1` — the slice's single user story (spec → User Story 1)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/`
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`, and
  root configs `ai-platform/vitest*.config.ts`, `ai-platform/wrangler.toml`
- Paths below follow `plan.md` → Source Code; the Worker tree is authoritative for this slice

---

## Phase 1: Setup (Test harness)

**Purpose**: The real-Miniflare-D1 + fake-`OperatorAuth` harness the named tests run in (plan
Sequencing steps 1–2; Clarification Q3). Both files must exist before any named test is written.

- [X] T001 [US1] Create `ai-platform/vitest.workers.config.ts` — scoped
  `@cloudflare/vitest-pool-workers` pool with an ephemeral Miniflare `DB` D1 binding,
  `compatibilityDate` matching `ai-platform/wrangler.toml`, and `include: ["test/control.test.ts"]`.
  The shared `ai-platform/vitest.config.ts` (A1's default Node pool used by every prior suite) is not
  modified. (No FR — harness; required by SC-001…004 test harness.)
- [X] T002 [US1] Create `ai-platform/test/control.test.ts` skeleton — `beforeAll` that reads
  `ai-platform/migrations/20260731120000_platform_schema.sql` and applies it to `env.DB` (A5
  migration, unmodified), plus a fake `OperatorAuth` factory returning a fixed operator principal or
  `null` (Clarification Q3). No assertions yet; the named tests hang off this skeleton in Phase 2.
  (No FR — harness; required by SC-001…004.)

**Checkpoint**: harness green on an empty `it.skip` (config resolves, Miniflare D1 starts, migration
applies).

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (delivery plan §3.11.2 row B2 =
Integration layer). All assert real D1 rows via read-back queries; the fake `OperatorAuth` supplies
the principal or `null`. None is optional.

- [X] T003 [US1] Add `enroll_writes_all_four_tables` (T-B2-01) to
  `ai-platform/test/control.test.ts` — assert that enroll with operator credentials + org info +
  public key + plan writes exactly one row each in `installation`, `installation_key`,
  `entitlement` (status `pending`, zeroed economics, closed empty period per §8.1 amendment), and
  `control_audit` (`operator_id` = the fake principal, `action = enroll`), and the reply carries the
  gateway origin. **Proves**: FR-005, FR-006, the enroll half of FR-003, FR-004 (one-time, first
  enroll); **satisfies**: SC-001. Fails before `src/control/` exists.
- [X] T004 [US1] Add `lifecycle_suspend_audit` (T-B2-02) to
  `ai-platform/test/control.test.ts` — assert suspend writes `control_audit` with the operator
  identity and sets `installation.status = suspended`. **Proves**: FR-008 (suspend), the suspend half
  of FR-003; **satisfies**: SC-002.
- [X] T005 [US1] Add `lifecycle_resume_audit` (T-B2-03) to
  `ai-platform/test/control.test.ts` — assert resume writes `control_audit` with the operator identity
  and restores the prior active lifecycle status. **Proves**: FR-008 (resume); **satisfies**: SC-002.
- [X] T006 [US1] Add `lifecycle_rotate_audit` (T-B2-04) to
  `ai-platform/test/control.test.ts` — assert rotate adds a new `installation_key` row with a new
  `kid`, leaves the previous row present (overlap intact, §8.1), and writes `control_audit` with the
  operator identity. **Proves**: FR-007, the rotate half of FR-003; **satisfies**: SC-002.
- [X] T007 [US1] Add `lifecycle_delete_audit` (T-B2-05) to
  `ai-platform/test/control.test.ts` — assert delete writes `control_audit` with the operator
  identity and pins `installation.status === "deleted"` (row purge is F3). **Proves**: FR-008
  (delete); **satisfies**: SC-002.
- [X] T008 [US1] Add `non_operator_credentials_rejected` (T-B2-06) to
  `ai-platform/test/control.test.ts` — with `OperatorAuth` returning `null`, each of the five
  mutations produces no D1 row write and **`401` + `{error:"unauthorized"}`**. Emits no §5.4 code.
  **Proves**: FR-001, FR-009; **satisfies**: SC-003.
- [X] T009 [US1] Add `duplicate_enrollment_deterministic` (T-B2-07) to
  `ai-platform/test/control.test.ts` — a second enroll for an existing `installation`/`org_id` leaves
  D1 row counts unchanged and returns **`409` + `{error:"already_enrolled"}`** (Clarification Q4).
  **Proves**: FR-004 (one-time), FR-010; **satisfies**: SC-004.

**Checkpoint**: all seven tests red, failing for the right reason (handlers / routes absent), not for a
harness reason.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: One task per implementation unit in `plan.md` → Files. Handlers and route wiring are the
code B2 adds; A5 migration is not edited. Operator Env: `OPERATOR_BEARER_TOKEN` (secret) +
`OPERATOR_ID` (var).

- [X] T010 [US1] Create `ai-platform/src/control/` lifecycle path — `OperatorAuth` types,
  `createSecretOperatorAuth` in `auth.ts`, and **enroll** in `lifecycle.ts` that transactionally
  writes `installation` + `installation_key` + `entitlement` (`pending`, zeroed economics) +
  `control_audit` (journals configured operator id, never the bearer), with payload validation and
  UNIQUE → `already_enrolled` / `duplicate_kid` mapping. Rejects duplicate `org_id`/`installation`.
  Barrel exports via `index.ts`. **Satisfies**: FR-001, FR-004, FR-005, FR-006, FR-010, FR-011;
  **proved by**: T-B2-01, T-B2-07.
- [X] T011 [US1] Add the **rotate** handler to `ai-platform/src/control/lifecycle.ts` — new
  `installation_key` row without removing the previous; `409 duplicate_kid` on reuse; reject rotate
  on `deleted`. **Satisfies**: FR-007, FR-008 (FSM), FR-011; **proved by**: T-B2-04,
  `rotate_duplicate_kid`, `lifecycle_illegal_transitions`.
- [X] T012 [US1] Add **suspend**, **resume**, and **delete** to `lifecycle.ts` — FSM: `deleted`
  terminal; resume only from `suspended`; re-suspend → `409 illegal_lifecycle_transition`; journal
  only real transitions; delete pins `status === "deleted"`; entitlement row untouched.
  **Satisfies**: FR-008; **proved by**: T-B2-02, T-B2-03, T-B2-05, `lifecycle_illegal_transitions`,
  `suspend_resume_entitlement_unchanged`.
- [X] T013 [US1] Non-operator rejection — every handler consults `OperatorAuth` first; on `null`
  writes no row and returns `401 unauthorized`. **Satisfies**: FR-001, FR-009; **proved by**:
  T-B2-06.
- [X] T014 [US1] Modify `ai-platform/src/worker.ts` — `/control` dispatch with explicit
  `createSecretOperatorAuth({ bearerToken: OPERATOR_BEARER_TOKEN, operatorId: OPERATOR_ID })` passed
  to `dispatchControlRequest` (no default). **Satisfies**: FR-001, FR-002, FR-009; **proved by**:
  `control_route_end_to_end`, T-B2-06.

**Checkpoint**: T-B2-01…07 green (run `npx vitest run --config vitest.workers.config.ts
test/control.test.ts`).

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the
latest.

- [X] T015 [US1] Run `npx vitest run --config vitest.workers.config.ts test/control.test.ts` (this
  slice, 7 tests) and then `npx vitest run` (the default Node-pool config covering every prior
  band-A/band-B1 suite). Confirm every prior suite stays green. No new test is added here — this is
  the checkpoint gate, not extra work. **Satisfies**: the §3.10 checkpoint rule.

---

## Phase 5: Documentation

**Purpose**: Plan → Documentation. The quickstart and the frozen contract artifact are named in the
plan and must land before the slice closes; both are written after the suite is green.

- [X] T016 [US1] Create/update `specs/022-control-plane-enrollment/contracts/control-plane.md` —
  freeze `/control` surface, five lifecycle `control_audit.action` values, verifying
  `createSecretOperatorAuth` rule, §2.4 rejection table (incl. `invalid_payload`,
  `illegal_lifecycle_transition`, `duplicate_kid`, `storage_error`), FSM terminal rules, `pending`
  enroll entitlement, status enum, rotation overlap. **Satisfies**: Freeze obligation.
- [X] T017 [US1] Create/update `specs/022-control-plane-enrollment/quickstart.md` — architecture
  context, secret auth Env setup (`wrangler secret put OPERATOR_BEARER_TOKEN` + `OPERATOR_ID` var),
  sibling module layout, suite commands. No accept-any Bearer docs.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — T001 then T002 (T002 imports the config T001 defines, so
  not parallel). Blocks Phase 2.
- **Tests (Phase 2)**: depends on Setup. T003…T009 all touch `ai-platform/test/control.test.ts` and
  share the `beforeAll`/fake-`OperatorAuth` from T002 — **not** parallel; written in spec-Test-plan
  order so each later test can reuse enroll fixtures from T003. Block Phase 3.
- **Implementation (Phase 3)**: depends on Tests. T010 (enroll + port) first — it defines the
  `OperatorAuth` port and the enroll write path every other handler and the route both depend on.
  T011 (rotate), T012 (suspend/resume/delete) depend on T010's port; they touch the same file, so not
  parallel. T013 (rejection) touches the same handlers and depends on T010–T012. T014 (route) depends
  on T010–T013 (it dispatches to the handlers). Verified by T-B2-01…07 turning green at the Phase 3
  checkpoint.
- **Verification (Phase 4)**: depends on Implementation. T015 is the §3.10 gate.
- **Documentation (Phase 5)**: depends on Verification (T015 green). T016 and T017 are independent
  artifacts in different files and **may run in parallel** (`[P]` applies — different files, no
  dependency).

### Within the slice

- Tests are written and fail before their implementation unit (T010 proved by T003/T009 written
  first; T011 by T006; T012 by T004/T005/T007; T013 by T008; T014 by T003).
- The migration (`ai-platform/migrations/20260731120000_platform_schema.sql`) is applied in test
  setup, never edited — A5 owns it (plan → Consumes Binding).
- No new DO class or A5 migration edit. Operator Env bindings (`OPERATOR_BEARER_TOKEN`,
  `OPERATOR_ID`) are required for verifying auth (R-20 reconciled).

### Parallel Opportunities

- T016 ∥ T017 in Phase 5 (different files, no dependency) — the only `[P]` pair in the slice.
- Phase 2 tests are sequential because they share one file and a `beforeAll`; the `[P]` marker is not
  applied within Phase 2 or Phase 3.

---

## Notes

- `[P]` tasks = different files, no dependencies. The single parallel pair is T016/T017.
- The slice has one user story, `US1`; the multi-story phases and MVP/Foundational/Polish phases from
  the template are dropped (delivery plan overrides).
- Review-resolution completion evidence (in `test/control.test.ts`, no new task ids):
  `secret_operator_auth_verifies_credential`, `control_route_end_to_end`,
  `lifecycle_illegal_transitions` (5), `suspend_resume_entitlement_unchanged`,
  `duplicate_enrollment_same_org_different_installation`, `enroll_invalid_payload`,
  `rotate_duplicate_kid`, `enroll_invalid_json`, `invalid_route_rejected`, `installation_not_found`.
- A5 migration is not edited; `UNIQUE(org_id)` on `installation` is a known A5 follow-up.
- Operator Env: `OPERATOR_BEARER_TOKEN` (secret) + `OPERATOR_ID` (var). No accept-any Bearer.
- Delete only transitions lifecycle status and writes the audit row; row purge is F3.
- Commit after each task or logical group; stop at the Phase 4 checkpoint to validate the §3.10 rule
  (every prior suite green, not just the latest).
