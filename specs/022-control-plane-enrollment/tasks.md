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
  identity and transitions lifecycle status; the row purge itself is out of scope (F3, plan → Out of
  Scope). **Proves**: FR-008 (delete); **satisfies**: SC-002.
- [X] T008 [US1] Add `non_operator_credentials_rejected` (T-B2-06) to
  `ai-platform/test/control.test.ts` — with `OperatorAuth` returning `null`, each of the five
  mutations produces no D1 row write (read-back counts unchanged) and a terminal rejection. Emits no
  §5.4 code (spec → Edge Cases). **Proves**: FR-001, FR-009; **satisfies**: SC-003.
- [X] T009 [US1] Add `duplicate_enrollment_deterministic` (T-B2-07) to
  `ai-platform/test/control.test.ts` — a second enroll for an existing `installation`/`org_id` leaves
  D1 row counts unchanged and returns a terminal non-2xx rejection; both sides asserted per
  Clarification Q4. **Proves**: FR-004 (one-time), FR-010; **satisfies**: SC-004.

**Checkpoint**: all seven tests red, failing for the right reason (handlers / routes absent), not for a
harness reason.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: One task per implementation unit in `plan.md` → Files. Handlers and route wiring are the
only code B2 adds; no migration, no binding, no `wrangler.toml` change (plan → Files note).

- [ ] T010 [US1] Create `ai-platform/src/control/index.ts` — define the `OperatorAuth` port (a
  single-method seam resolving an operator principal or rejecting; Clarification Q2) and the
  **enroll** handler that transactionally writes `installation` + `installation_key` + `entitlement`
  (status `pending`, plan from payload, zeroed economics, closed empty period per §8.1 amendment,
  §7.3 status enum) + `control_audit` (operator identity, `action = enroll`), and returns the gateway
  origin. Rejects a duplicate `org_id`/`installation` with no row write (FR-010). The same handler
  branch serves T-B2-01 and T-B2-07. **Satisfies**: FR-001, FR-004, FR-005, FR-006, FR-010; **proved
  by**: T-B2-01, T-B2-07.
- [ ] T011 [US1] Add the **rotate** handler to `ai-platform/src/control/index.ts` — adds a new
  `installation_key` row with a new `kid` without removing the previous one (overlap intact, §8.1),
  and writes `control_audit` (operator identity, `action = rotate`). Verifying both keys is the
  guard's concern (B3) and is not implemented here (plan → Out of Scope). **Satisfies**: FR-007; **proved
  by**: T-B2-04.
- [ ] T012 [US1] Add the **suspend**, **resume**, and **delete** handlers to
  `ai-platform/src/control/index.ts` — each writes its `control_audit` row carrying the operator
  identity and transitions `installation.status` (suspend → `suspended`, resume → prior active status,
  delete → lifecycle-terminal status, not a row purge — the installation-by-`installation_id` purge is
  F3 per plan → Out of Scope). **Satisfies**: FR-008; **proved by**: T-B2-02, T-B2-03, T-B2-05.
- [ ] T013 [US1] Add the non-operator rejection path to `ai-platform/src/control/index.ts` — every
  handler consults `OperatorAuth` first and on `null` writes no row and returns a terminal rejection
  (no §5.4 code; spec → Edge Cases). **Satisfies**: FR-001, FR-009; **proved by**: T-B2-06.
- [ ] T014 [US1] Modify `ai-platform/src/worker.ts` — add `/control` route dispatch with
  operator-auth gating that routes to the handlers (Clarification Q1); the client-facing
  `/v1/requests` and `/health` routes are unchanged. A1's `assertRequiredBindings` is untouched.
  **Satisfies**: FR-001, FR-002; **proved by**: T-B2-01 (end-to-end route → handler → D1) and T-B2-06
  (route-level rejection).

**Checkpoint**: T-B2-01…07 green (run `npx vitest run --config vitest.workers.config.ts
test/control.test.ts`).

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the
latest.

- [ ] T015 [US1] Run `npx vitest run --config vitest.workers.config.ts test/control.test.ts` (this
  slice, 7 tests) and then `npx vitest run` (the default Node-pool config covering every prior
  band-A/band-B1 suite). Confirm every prior suite stays green. No new test is added here — this is
  the checkpoint gate, not extra work. **Satisfies**: the §3.10 checkpoint rule.

---

## Phase 5: Documentation

**Purpose**: Plan → Documentation. The quickstart and the frozen contract artifact are named in the
plan and must land before the slice closes; both are written after the suite is green.

- [ ] T016 [US1] Create `specs/022-control-plane-enrollment/contracts/control-plane.md` — freeze the
  `/control` HTTP surface, the five `control_audit.action` lifecycle values (`enroll`, `rotate`,
  `suspend`, `resume`, `delete`), the operator-auth requirement, the `pending` enroll entitlement
  initial values (§8.1 amendment), the entitlement status enum `pending`/`active`/`suspended` (§7.3
  amendment, including the guard's "pending reads as no capability allowed → quota-exhaustion path"),
  and the rotation overlap invariant, so B3 (guard), J3 (control_audit activations), and F3
  (installation purge by lifecycle status) bind to an artifact, not prose (plan → Freezes → Consumes
  Binding). **Satisfies**: the Freeze live-wire-surface obligation; not traced to an FR (contract
  artifact).
- [ ] T017 [US1] Create `specs/022-control-plane-enrollment/quickstart.md` from
  `.specify/templates/ai-platform-quickstart-template.md` — sections **1. Architecture context**
  (§4.5 + §8.1; delivery plan §3.3 row B2; what the spec/plan scoped), **2. What was implemented**
  (the five lifecycle handlers, the `/control` route, the `OperatorAuth` port, the `pending`
  enrollment entitlement), **3. Files to review**
  (`ai-platform/src/control/index.ts`, `ai-platform/src/worker.ts` diff,
  `ai-platform/test/control.test.ts`, `ai-platform/vitest.workers.config.ts`,
  `specs/022-control-plane-enrollment/contracts/control-plane.md`), **4. Prerequisites** (kept:
  `--config vitest.workers.config.ts` flag + one-time `npm install`, since the slice's tests need the
  workers-pool Miniflare D1), **5. Run the automated suite**
  (`npx vitest run --config vitest.workers.config.ts test/control.test.ts`), **6. Inspect the changes**
  (read the handlers, grep `control_audit.action` cases, read the frozen entitlement initial-values
  contract). **No section 7** — CI is the only verification path (the control plane has no
  user-facing behaviour beyond the suite). **Slice-only scope explicit**: no prior-slice files in the
  review table, no combined test counts, no `npm test` for the full platform suite, no prior-slice
  regression commands. Not traced to an FR (template-mandated review surface).

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
- No new binding, secret, DO class, or `wrangler.toml` change is made anywhere in the slice.

### Parallel Opportunities

- T016 ∥ T017 in Phase 5 (different files, no dependency) — the only `[P]` pair in the slice.
- Phase 2 tests are sequential because they share one file and a `beforeAll`; the `[P]` marker is not
  applied within Phase 2 or Phase 3.

---

## Notes

- `[P]` tasks = different files, no dependencies. The single parallel pair is T016/T017.
- The slice has one user story, `US1`; the multi-story phases and MVP/Foundational/Polish phases from
  the template are dropped (delivery plan overrides).
- No task adds a migration, a binding, a retry, a cache, a configuration surface, or any §9.14
  mechanism — none is named by the spec or plan (R-20; spec → Out of Scope).
- The Row purge on delete is explicitly out of scope (F3) and is not a task here; delete only
  transitions lifecycle status and writes the audit row.
- Commit after each task or logical group; stop at the Phase 4 checkpoint to validate the §3.10 rule
  (every prior suite green, not just the latest).