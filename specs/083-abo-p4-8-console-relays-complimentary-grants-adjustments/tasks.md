# Tasks: Console relays: complimentary grants, adjustments, voids, suspension, deletion and the transfer saga

**Input**: Design documents from `specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.7 (none; that unit row states no Outputs / freezes line) and P3.8 (none; that unit row states no Outputs / freezes line). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`. That plan artifact is already written. It is not an implement task. `research.md` is not a task: Spikes is none, so the plan phase did not write it. `contracts/` is not a task: Freezes has no wire shape. `quickstart.md` is written in Documentation after verification.

**Organization**: Two user stories, as the spec partitions them (`[US1]`, `[US2]`). Tests are one task per E2E id, written to fail before the relays exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 16. Size M is 20–32 (rule S3). The count is one task per E2E id (8), the vitest include (1), the Sequencing step 2 `PLATFORM` method lists on `abo/src/ops/index.ts` and `abo/src/worker.ts` (2), the User Story 1 relays in `abo/src/ops/index.ts` (1), the transfer saga in that same file (1), the minute `scheduled()` call in `abo/src/worker.ts` (1), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §6.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/src/vendor/entrypoint.ts` — consumed and not modified. `VendorEntrypoint` stays unchanged
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed (`canonicalize`, `sha256Hex`) and not modified
- **Spec Kit artifacts**: `specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/`
- No new table and no migration. `grant_request`, `grant_outcome`, `operator_action`, and `work` already exist. `transfer_step` is a `work.kind`. Leave `abo/test/system/harness.ts` unchanged. `opsFetch` and `billingFetch` stay there. No new worker, hostname, or scheduler. These relays do not call `recordOperatorAction`

---

## 3. Setup

**Purpose**: Sequencing step 1, before the failing tests. The vitest include is the scaffold those tests need. The `abo/` Worker already exists.

### 3.1 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — vitest include

**Independent Test**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 in harness H-XW.

- [ ] T001 [US1] Add the console-relays test include in `abo/vitest.cross-worker.config.ts` — produces the H-XW include for this unit, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-04, E2E-P4.8-05, E2E-P4.8-06, E2E-P4.8-07, E2E-P4.8-08. Depends on nothing. Add `test/system/console-relays.cross-worker.test.ts` to the H-XW `include` list. The unit command still names only that file. Leave `abo/test/system/console-relays.cross-worker.test.ts` uncreated in this task.

**Checkpoint**: The include lists `test/system/console-relays.cross-worker.test.ts`. That file does not exist yet.

---

## 4. Tests

**Purpose**: Sequencing step 1 continued. One failing test per E2E id, all in `abo/test/system/console-relays.cross-worker.test.ts`. Titles are prefixed with the E2E id. Harness H-XW runs the real platform worker from source. Entry is `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`, except where a row also names `billingFetch`, `scheduled()`, or a direct `VendorEntrypoint` call. No scenario sleeps more than 2 s (rule V4). Saga retries advance with `runScheduled`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/console-relays.cross-worker.test.ts
```

### 4.1 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — tests (part 1)

**Independent Test**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 in harness H-XW.

- [ ] T002 [US1] Add the failing test `E2E-P4.8-01` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-001, FR-010, FR-011, E2E-P4.8-01. Depends on T001. Create the file and the shared setup. `opsFetch` submits a complimentary grant with `duration` `{unit: "day", count: 14}` on `POST /ops/orgs/:orgId/complimentary-grant`, then the same session submits one term adjustment on that route with `kind` `term_adjustment`. The 14-day extension is applied. AL-11 is a `platform_alert` row on `PLATFORM_DB`. `operator_action` and `grant_request` share the action id (`source_ref`, and `grant_id` is the comp form: SHA-256 hex over `"grant:comp:"` ‖ the operator action id). The adjustment is applied. The command fails because that route is absent from `abo/src/ops/index.ts`.

- [ ] T003 [US1] Add the failing test `E2E-P4.8-02` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-002, FR-010, FR-011, E2E-P4.8-02. Depends on T002 (same file). `opsFetch` submits a complimentary grant with day count 365, then the same route with `ceiling_override` and `ceiling_override_operation`. The first result is `rejected` with code `exceeds_ceiling`. The second result is applied. AL-12 is a `platform_alert` row on `PLATFORM_DB`. The command fails because that route is absent from `abo/src/ops/index.ts`.

- [ ] T004 [US1] Add the failing test `E2E-P4.8-03` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-003, FR-010, E2E-P4.8-03. Depends on T003 (same file). `opsFetch` submits a trial complimentary grant. The trial `day` count is fixture data inside the current ceiling, not a product default. Then `billingFetch` `POST /v1/checkouts` and the existing paid-grant path (`runDueGrantWork` / the paid `grant` work row) on the real platform worker. The paid term queues after the trial. The command fails because the complimentary-grant route is absent from `abo/src/ops/index.ts`.

- [ ] T005 [US1] Add the failing test `E2E-P4.8-06` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-007, FR-010, E2E-P4.8-06. Depends on T004 (same file). `env.PLATFORM.revokeOperatorCredential` on the real platform worker (credential Y revokes X). Then `opsFetch` `POST /ops/grants/list-for-void` with the fixture window `{applied_from, applied_to}` of inclusive UTC ISO-8601 timestamps that cover the grants under test, then `opsFetch` `POST /ops/grants/:grantId/void` for each returned `grant_id`. Those listed grants end `voided`. The command fails because those routes are absent from `abo/src/ops/index.ts`.

- [ ] T006 [US1] Add the failing test `E2E-P4.8-07` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-008, FR-010, E2E-P4.8-07. Depends on T005 (same file). `opsFetch` `POST /ops/orgs/:orgId/suspend`. The refusal is `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker, the same call shape as `platformHttpInvoke` in `abo/test/system/grant.cross-worker.test.ts`. After suspend the admission outcome is `suspended`. Then `opsFetch` `POST /ops/orgs/:orgId/resume` and the same platform request again. After resume that refusal is gone. The command fails because those routes are absent from `abo/src/ops/index.ts`.

**Checkpoint**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, and E2E-P4.8-07 exist and fail.

### 4.2 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — tests (part 2)

**Independent Test**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 in harness H-XW.

- [ ] T007 [US1] Add the failing test `E2E-P4.8-08` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-009, E2E-P4.8-08. Depends on T006 (same file). `opsFetch` `POST /ops/orgs/:orgId/complimentary-grant` with `assertion` omitted. The platform rejects the call. The test does not expect a new ABO refusal code. The command fails because that route is absent from `abo/src/ops/index.ts`.

**Checkpoint**: E2E-P4.8-08 exists and fails. E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, and E2E-P4.8-07 still fail.

### 4.3 User Story 2 - Deletion and the transfer saga (Priority: P2) — tests

**Independent Test**: E2E-P4.8-04 and E2E-P4.8-05 in harness H-XW. Earlier suites stay green, and E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 still pass.

- [ ] T008 [US2] Add the failing test `E2E-P4.8-04` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-004, FR-005, FR-010, FR-011, E2E-P4.8-04. Depends on T007 (same file). The fixture binding starts at epoch 1 with coverage to move. `opsFetch` `POST /ops/orgs/:orgId/begin-transfer` inserts one `transfer_step` work row. `runScheduled("* * * * *")` drives that row. The first run leaves `last_error` `awaiting_transfer_out` and the row `open`. Later runs reach `applied` or `already_applied` for both `transferOut` and `transferIn`. `opsFetch` `GET /ops/clinics/:orgId` shows `binding_epoch` 2. One `grant_request` per package element, `source_kind` `transfer`. The command fails because begin-transfer and the saga driver are absent.

- [ ] T009 [US2] Add the failing test `E2E-P4.8-05` in `abo/test/system/console-relays.cross-worker.test.ts` — red test, FR-006, FR-004, FR-010, E2E-P4.8-05. Depends on T008 (same file). `opsFetch` `POST /ops/orgs/:orgId/delete-installation`. Platform `detail` shows the binding `held_for_transfer`. Then `opsFetch` `beginTransfer` with `from_installation_id` of that held binding, and the same `scheduled()` driver. The transfer runs from that held binding. The command fails because delete-installation, begin-transfer, and the saga driver are absent.

**Checkpoint**: E2E-P4.8-04 and E2E-P4.8-05 exist and fail. E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 still fail.

---

## 5. Implementation

**Purpose**: Sequencing steps 2–6. Starts after T002–T009 exist and those E2E tests fail. Step 7 needs no separate task: E2E-P4.8-08 is the complimentary-grant relay with `assertion` omitted. Within a subphase the tasks run in id order.

### 5.1 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — OpsEnv PLATFORM methods

**Independent Test**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 in harness H-XW.

- [ ] T010 [US1] Add the relay methods on `PLATFORM` in `OpsEnv` in `abo/src/ops/index.ts` — produces the method types, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-04, E2E-P4.8-05, E2E-P4.8-06, E2E-P4.8-07, E2E-P4.8-08. Depends on T009. Add `grant`, `beginTransfer`, `transferOut`, `transferIn`, `releaseHeld`, `voidGrant`, `listGrantsForVoid`, `suspend`, `resume`, and `deleteInstallation`. Leave `getCoverage` as it already is. Add no route in this task. Leave `abo/src/worker.ts` unchanged in this task.

**Checkpoint**: `OpsEnv` lists those methods. E2E-P4.8-01 through E2E-P4.8-08 still fail.

### 5.2 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — worker Env PLATFORM methods

**Independent Test**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 in harness H-XW.

- [ ] T011 [US1] Add the same relay methods on `PLATFORM` in the worker `Env` in `abo/src/worker.ts` — produces the method types, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-04, E2E-P4.8-05, E2E-P4.8-06, E2E-P4.8-07, E2E-P4.8-08. Depends on T009. Add `grant`, `beginTransfer`, `transferOut`, `transferIn`, `releaseHeld`, `voidGrant`, `listGrantsForVoid`, `suspend`, `resume`, and `deleteInstallation`. Leave the minute `scheduled()` branch unchanged in this task. Leave `abo/src/ops/index.ts` unchanged in this task.

**Checkpoint**: The worker `Env` lists those methods. `scheduled()` does not call `runDueTransferSteps` yet. E2E-P4.8-01 through E2E-P4.8-08 still fail.

### 5.3 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — console relays

**Independent Test**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 in harness H-XW.

- [ ] T012 [US1] Add the User Story 1 relays in `abo/src/ops/index.ts` — produces complimentary grant, term adjustment, ceiling override, suspend, resume, list-for-void, void, and release-held, FR-001, FR-002, FR-003, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, E2E-P4.8-08. Depends on T010. Leave `abo/src/worker.ts` unchanged in this task. Leave delete-installation, begin-transfer, `runDueTransferSteps`, and `binding_epoch` for T013. Every new route runs the existing `verifyOpsAccess` first. The verified Access JWT is the `access_jwt` forwarded to the platform. These routes do not use the ABO-side HP verifier and do not call `recordOperatorAction`. The body carries `action_id`. The handler inserts one `operator_action` with that id, the Access email as `actor_email`, and the platform result. A second insert of the same `action_id` does not run. `subject` is the org id or grant id in the path. `listGrantsForVoid` uses `credential_id` as `subject`. `grant_request` and `grant_outcome` inserts also write `fact_log` the same way `abo/src/work/grant.ts` already does for those tables. Leave `abo/src/work/grant.ts` unchanged. In this task, in order: the complimentary-grant route, then `ceiling_override` on that route, then suspend, resume, list, void, and release-held. `POST /ops/orgs/:orgId/complimentary-grant` calls `PLATFORM.grant` and forwards `envelope`, `operation`, `assertion`, `signer_credential_id`, and, when present, `ceiling_override_operation`. A missing `assertion` is still forwarded. The platform's existing rejection is the result. No new refusal code. The handler still writes `operator_action`. The envelope's `grant_id` is SHA-256 hex over `"grant:comp:"` ‖ `action_id`. `source.kind` is `complimentary`. `source.ref` is `action_id`. `kind` `term` is the complimentary grant, including the 14-day extension `duration` `{unit: "day", count: 14}`, the 365-day grant `duration` `{unit: "day", count: 365}`, and a trial whose `day` count the fixture chooses. `kind` `term_adjustment` is the adjustment, with `adjustment` on the envelope. Both write `grant_request` with `source_kind` `complimentary`, `source_ref` the action id, the canonical envelope, `envelope_sha256`, and `assertion`. `grant_outcome` records the platform `result`, the platform `receipt` when present, `term_ids`, and `at`. `abo_kid` and `abo_signature` stay null. The console response returns the platform result, including `code` when the result is `rejected`. The 365-day grant's first response is the platform's `exceeds_ceiling`. The second request puts the second passkey on `envelope.ceiling_override` and forwards `ceiling_override_operation`. `POST /ops/orgs/:orgId/suspend` and `POST /ops/orgs/:orgId/resume` forward `org_id` and `reason` with `access_jwt` and no assertion. `POST /ops/grants/list-for-void` forwards `credential_id` and `window` as `{applied_from, applied_to}`. `POST /ops/grants/:grantId/void` and `POST /ops/grants/:grantId/release-held` are one function. The path chooses `voidGrant` or `releaseHeld`. Both forward `grant_id`, `reason`, `operation`, `assertion`, and `signer_credential_id`. E2E-P4.8-06 enters that function through `void`. The clinic purchase in E2E-P4.8-03 stays on the existing `POST /v1/checkouts` and paid-grant path.

**Checkpoint**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 are covered by these routes. E2E-P4.8-04 and E2E-P4.8-05 still fail.

### 5.4 User Story 2 - Deletion and the transfer saga (Priority: P2) — transfer saga

**Independent Test**: E2E-P4.8-04 and E2E-P4.8-05 in harness H-XW. Earlier suites stay green, and E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 still pass.

- [ ] T013 [US2] Add delete, begin-transfer, `runDueTransferSteps`, and `binding_epoch` in `abo/src/ops/index.ts` — produces the held-binding delete and the transfer saga, FR-004, FR-005, FR-006, FR-010, E2E-P4.8-04, E2E-P4.8-05. Depends on T012. Leave `abo/src/worker.ts` unchanged in this task. `POST /ops/orgs/:orgId/delete-installation` calls `PLATFORM.deleteInstallation` and forwards `org_id`, `reason`, and the HP assertion fields. The console response includes the platform `detail`. `POST /ops/orgs/:orgId/begin-transfer` calls `PLATFORM.beginTransfer` and forwards `org_id`, `from_installation_id`, `reason`, and the HP assertion fields. Both write one `operator_action` the same way T012 does, and do not call `recordOperatorAction`. On `beginTransfer` `ok`, read `transfer_id` from the platform `detail`. Insert one `work` row: `kind` `transfer_step`, `subject_id` and the dedupe key `transfer_step:` ‖ `transfer_id`, `state` `open`, `next_attempt_at` null. If that dedupe key already exists, do not insert another row. `runDueTransferSteps` takes each open `transfer_step` row whose `next_attempt_at` is null or already due, with the existing lease update. It does not change `next_attempt_at` and it does not insert another row. When that row has not yet seen `transferOut` `applied` or `already_applied`, call `transferIn` once. `transient` with `detail` `awaiting_transfer_out` is stored on `last_error`. The lease is cleared and the row stays `open`. That run does not call `transferOut`. A later run calls `transferOut`. `applied` or `already_applied` writes one `grant_request` per element of the package JSON array in `detail`, when `detail` is that array. `n` is that element's 0-based index, written as decimal digits with no leading zeros. `grant_id` is SHA-256 hex over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. `source_kind` is `transfer`, `source_ref` is `transfer_id`, `assertion` is null, and `org_id` is the transfer's org. An `n` whose `grant_id` already exists is skipped. An empty array writes none. Those inserts write `fact_log` the same way `abo/src/work/grant.ts` already does. The run then calls `transferIn`. A `transient` `transferIn` after that stores `last_error`, clears the lease, and leaves the row `open`. When `transferIn` is `applied` or `already_applied`, the row is `done` and the lease is cleared. `GET /ops/clinics/:orgId` includes `binding_epoch` from `getCoverage` `detail.snapshot.binding_epoch`.

**Checkpoint**: `runDueTransferSteps` exists. The minute cron does not call it yet, so E2E-P4.8-04 and E2E-P4.8-05 still fail until T014. E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 stay covered by T012.

### 5.5 User Story 2 - Deletion and the transfer saga (Priority: P2) — minute cron

**Independent Test**: E2E-P4.8-04 and E2E-P4.8-05 in harness H-XW. Earlier suites stay green, and E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 still pass.

- [ ] T014 [US2] Call `runDueTransferSteps` from the minute `scheduled()` branch in `abo/src/worker.ts` — produces the cron drive for `transfer_step`, FR-004, FR-005, E2E-P4.8-04, E2E-P4.8-05. Depends on T011 and T013. The existing `* * * * *` branch calls `runDueTransferSteps`. Leave `abo/src/ops/index.ts` unchanged in this task. A `transient` result waits for the next minute `scheduled()` run. This task does not add a retry schedule and does not change `next_attempt_at`.

**Checkpoint**: E2E-P4.8-04 and E2E-P4.8-05 can run through `scheduled()` until both sides are applied. E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 stay covered by T012.

---

## 6. Verification

**Purpose**: After T012, T013, and T014, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command.

### 6.1 Unit harness

**Independent Test**: E2E-P4.8-04 and E2E-P4.8-05 in harness H-XW. Earlier suites stay green, and E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 still pass.

- [ ] T015 [US2] Run `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/console-relays.cross-worker.test.ts` from `abo/` until E2E-P4.8-01 through E2E-P4.8-08 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-04, E2E-P4.8-05, E2E-P4.8-06, E2E-P4.8-07, E2E-P4.8-08. Depends on T012, T013, and T014 (and therefore on T001–T011). This task may edit only files under `abo/test/`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/console-relays.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.8-01 through E2E-P4.8-08 pass.

---

## 7. Documentation

**Purpose**: After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 7.1 Quickstart

- [ ] T016 [US2] Create `specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-04, E2E-P4.8-05, E2E-P4.8-06, E2E-P4.8-07, E2E-P4.8-08. Depends on T015. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps; the harness observes every scenario.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/console-relays.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.8-01 | `opsFetch` complimentary grant (`duration` day 14) → `handleOps` → `PLATFORM.grant`. Same session: `opsFetch` term adjustment → the same route with `kind` `term_adjustment`. 14-day extension applied. AL-11 is a `platform_alert` row on `PLATFORM_DB`. `operator_action` and `grant_request` share the action id |
| E2E-P4.8-02 | `opsFetch` complimentary grant, day count 365, then the same route with `ceiling_override` and `ceiling_override_operation` → `PLATFORM.grant`. First result `rejected`, code `exceeds_ceiling`. Second result applied. AL-12 is a `platform_alert` row |
| E2E-P4.8-03 | `opsFetch` trial complimentary grant → `PLATFORM.grant`. Then `billingFetch` `POST /v1/checkouts` and the existing paid-grant path (`runDueGrantWork` / the paid `grant` work row) on the real platform worker. The paid term queues after the trial |
| E2E-P4.8-04 | Fixture binding starts at epoch 1. `opsFetch` `beginTransfer` → `handleOps` inserts one `transfer_step` row. `runScheduled("* * * * *")` → `runDueTransferSteps` → `PLATFORM.transferIn` then, on the later run, `PLATFORM.transferOut` and `PLATFORM.transferIn`. Clinic page: `opsFetch` `GET /ops/clinics/:orgId` shows `binding_epoch` 2. One `grant_request` per package element, `source_kind` `transfer` |
| E2E-P4.8-05 | `opsFetch` `deleteInstallation` → `PLATFORM.deleteInstallation`. Then `opsFetch` `beginTransfer` with `from_installation_id` of that held binding, and the same `scheduled()` driver. Platform `detail` shows the binding `held_for_transfer`. The transfer runs from that binding |
| E2E-P4.8-06 | `env.PLATFORM.revokeOperatorCredential` on the real platform worker (credential Y revokes X). Then `opsFetch` `list-for-void` with the fixture window, then `opsFetch` `void` for each returned `grant_id` → `PLATFORM.voidGrant`. Listed grants end `voided` |
| E2E-P4.8-07 | `opsFetch` suspend → `PLATFORM.suspend`. Refusal: `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker. Then `opsFetch` resume → `PLATFORM.resume`, and the same platform request again. After suspend the admission outcome is `suspended`. After resume that refusal is gone |
| E2E-P4.8-08 | `opsFetch` complimentary grant with `assertion` omitted → `handleOps` → `PLATFORM.grant`. The platform rejects the call. The test does not expect a new ABO refusal code |

**Checkpoint**: `quickstart.md` names the files, the harness command, and the eight chains.

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (§3)**: No dependencies. Starts immediately.
- **Tests (§4)**: Depend on the vitest include. One failing test per E2E id, User Story 1 then User Story 2, in the id order inside each story: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, E2E-P4.8-08, then E2E-P4.8-04, E2E-P4.8-05. All of them fail before any relay is implemented.
- **Implementation (§5)**: Depends on those failing tests. Sequencing step 2 extends `PLATFORM` on `OpsEnv` and on the worker `Env`. User Story 1 relays follow the `OpsEnv` methods. Delete, begin-transfer, `runDueTransferSteps`, and `binding_epoch` follow those relays in `abo/src/ops/index.ts`. The minute `scheduled()` call follows that function and the worker `Env` methods.
- **Verification (§6)**: Depends on the relays, the saga, and the cron call. The harness is the command in §6.1.
- **Documentation (§7)**: Depends on that harness being green. `quickstart.md` is the only doc task.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: Complimentary grant, term adjustment, ceiling override, suspend, resume, list-for-void, void, release-held, and the assertion-less forward. Tested by E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08. No dependency on User Story 2.
- **User Story 2 (P2)**: Delete with time left, begin-transfer, the `transfer_step` saga, and epoch 2 on the clinic page. Tested by E2E-P4.8-04 and E2E-P4.8-05. Follows User Story 1 in `abo/src/ops/index.ts` because that file already holds the relays. The saga does not rewrite those relays.

### 8.3 Within Each Phase

- T001 writes only `abo/vitest.cross-worker.config.ts`.
- T002 creates `abo/test/system/console-relays.cross-worker.test.ts` after T001. T003 through T009 all write that same file, in that id order.
- T010 writes only the `OpsEnv` method list in `abo/src/ops/index.ts` after T009, and does not add routes. T011 writes only the worker `Env` method list in `abo/src/worker.ts` after T009, and does not change `scheduled()`. Sequencing step 2 does not order T010 before T011.
- T012 writes the User Story 1 routes in `abo/src/ops/index.ts` after T010, and does not write `abo/src/worker.ts`.
- T013 writes delete, begin-transfer, `runDueTransferSteps`, and `binding_epoch` in `abo/src/ops/index.ts` after T012, and does not write `abo/src/worker.ts`.
- T014 writes only the minute `scheduled()` call in `abo/src/worker.ts` after T011 and T013.
- T015 runs after T012, T013, and T014 and may edit only `abo/test/`.
- T016 writes only `specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/quickstart.md` after T015 is green.

---

## 9. Implementation Waves

### 9.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — vitest include` — paths: `abo/vitest.cross-worker.config.ts`

### 9.2 Wave 2

- T002–T006 [US1] — subphase: `### 4.1 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — tests (part 1)` — paths: `abo/test/system/console-relays.cross-worker.test.ts`

### 9.3 Wave 3

- T007 [US1] — subphase: `### 4.2 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — tests (part 2)` — paths: `abo/test/system/console-relays.cross-worker.test.ts`

### 9.4 Wave 4

- T008–T009 [US2] — subphase: `### 4.3 User Story 2 - Deletion and the transfer saga (Priority: P2) — tests` — paths: `abo/test/system/console-relays.cross-worker.test.ts`

### 9.5 Wave 5

- T010 [US1] — subphase: `### 5.1 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — OpsEnv PLATFORM methods` — paths: `abo/src/ops/index.ts`
- T011 [US1] — subphase: `### 5.2 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — worker Env PLATFORM methods` — paths: `abo/src/worker.ts`

### 9.6 Wave 6

- T012 [US1] — subphase: `### 5.3 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1) — console relays` — paths: `abo/src/ops/index.ts`

### 9.7 Wave 7

- T013 [US2] — subphase: `### 5.4 User Story 2 - Deletion and the transfer saga (Priority: P2) — transfer saga` — paths: `abo/src/ops/index.ts`

### 9.8 Wave 8

- T014 [US2] — subphase: `### 5.5 User Story 2 - Deletion and the transfer saga (Priority: P2) — minute cron` — paths: `abo/src/worker.ts`

### 9.9 Wave 9

- T015 [US2] — subphase: `### 6.1 Unit harness` — paths: `abo/test/`

### 9.10 Wave 10

- T016 [US2] — subphase: `### 7.1 Quickstart` — paths: `specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/quickstart.md`
