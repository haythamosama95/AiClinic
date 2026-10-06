# Tasks: Transfer, deletion with coverage left, and ledger retention

**Input**: Design documents from `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged unit in **Consumes Binding**: P3.7 (void, release, and listing methods; the tombstone rule). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`. There is no `research.md` and no `contracts/`. `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id in the spec Test plan, written to fail before transfer, deletion, lineage, and purge retention exist. Test Layout also names three existing purge assertions; those are one task per file, after the purge change, in Sequencing step 23. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing.

**Task count**: 27. Size L is 32–40 (rule S3). The count is eight E2E tasks (Sequencing steps 1–8), fourteen implementation tasks (steps 9–22), three assertion-update tasks (step 23, one file each), one verification task (the unit harness), and `quickstart.md`. It is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the Files paths in `plan.md`
- **ABO**: `abo/` — this unit does not change it. The harness does not start an ABO worker. The saga driver stays in P4.8.
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified
- **Spec Kit artifacts**: `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/`
- `data-model.md` stays a plan-phase artifact. Do not edit earlier migrations. Do not add a DO column. The live-org unique index already allows `held_for_transfer`. Do not rewrite `voidForReversalRPC`, `voidGrantRPC`, `releaseHeld`, `releaseHeldRPC`, `listGrantsForVoid`, or the tombstone write (rule S7). `ai-platform/src/control/lifecycle.ts` `handleDelete` stays the `/control` path until P3.10. `ai-platform/src/control/support-purge.ts` stays the HTTP caller of `purgeByInstallationId`. Projection handling of `(binding_epoch, clinic_seq)` stays in P5.2. Do not add a cron. Do not modify `packages/vendor-contracts`.

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/transfer-deletion.system.test.ts`. The unit command is that file only, under `vitest.workers.config.ts`. `coverClinic()` remains the paid-grant helper. HP calls use `coverClinicSigner()` the way a complimentary grant does. `actor_email` is `VENDOR_OPERATOR_EMAIL`. For `beginTransfer`, `operation.op` is `beginTransfer` and `operation.params` is `{contract_version, access_jwt, org_id, from_installation_id, reason}`. For `deleteInstallation`, `operation.op` is `deleteInstallation` and `operation.params` is `{contract_version, access_jwt, org_id, reason}`. `transferOut` and `transferIn` send `contract_version` and `transfer_id` only, over `env.VENDOR`. After `coverClinic()`, do not move the clock backward of the credential's `activates_at`. `mintAat` is reminted after any `setTestClock` that passes its `exp`. No `sleep` over 2 s. No ABO worker is constructed. `runDurableObjectAlarm` runs before a D1 assertion that the DO outbox ships (`grant_ledger`, `coverage_event`). A successful `beginTransfer` is `ok`, `code` empty, `receipt` absent, and `detail` is the JSON text of the `transfer` row (`package` null, `transfer_id` present). A successful `deleteInstallation` is `ok`, `code` empty, `receipt` absent, and `detail` is the JSON text of `{installation, tenant_binding}`. `transferOut` and `transferIn` are `applied` or `already_applied` with `detail` the JSON text of the package and `receipt` the transfer receipt (`transfer_id` as the id member, `installation_id` the installation that step wrote, `envelope_sha256` the SHA-256 of the RFC 8785 canonical package, `ledger_seq` the `clinic_seq` of the `transfer` coverage event that step wrote, `term_ids` the terms that step ended or created). The four `VendorMethod` names stay until T010.

### 3.1 User Story 1 - Move a clinic's coverage to a new installation (Priority: P1)

**Independent Test**: E2E-P3.8-01, E2E-P3.8-02, and E2E-P3.8-03 in harness H-AP.

- [X] T001 [US1] Add the failing test `E2E-P3.8-01 A14 beginTransfer moves an active term and a queued term` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-001, FR-002, FR-003, E2E-P3.8-01. `coverClinic()` once, then a second paid grant so one term is `queued`. `beginTransfer` for that org and its active `from_installation_id`. `transferOut` then `transferIn`. The new installation's terms have the same `origin_grant_id`s. The active term's `allowance` is the old allowance minus `hot.used`. The queued term's `allowance` is unchanged. `getCoverage` on the old installation has state `transferred`. A later `vendorCall("grant")` aimed at the old installation is `rejected` with `code` `transferred_out`. A captured email is AL-11 for that `transfer_id`. `coverage_event` rows for the new installation carry `binding_epoch` 2. Do not add `beginTransfer`, `transferOut`, `transferIn`, or `deleteInstallation` to `VendorMethod`. Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/transfer-deletion.system.test.ts
```

The run fails because `beginTransfer` is not a method.

- [X] T002 [US1] Add the failing test `E2E-P3.8-02 a non-transfer grant during awaiting_transfer is transient and then queues behind the moved terms` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-004, E2E-P3.8-02. Depends on T001 (same file). After `beginTransfer`, before `transferIn`, a paid `vendorCall("grant")` is `transient` with `detail` `awaiting_transfer` and inserts no term. After `transferIn`, that grant is `applied` and `inspectCoverage` shows it queued after the moved terms. Do not add the four method names to `VendorMethod`. The unit command fails because a grant during `awaiting_transfer` is not `transient`.

- [X] T003 [US1] Add the failing test `E2E-P3.8-03 transfer steps retry as already_applied and transferIn before transferOut is transient` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-002, E2E-P3.8-03. Depends on T002 (same file). A second `transferOut` and a second `transferIn` with the same `transfer_id` are `already_applied` and return the original receipt. A `transferIn` called before `transferOut` is `transient` with `detail` `awaiting_transfer_out`. Term rows and `transfer.package` are unchanged by that early call. Do not add the four method names to `VendorMethod`. The unit command fails because a retry is not `already_applied` and an early `transferIn` is not `transient`.

**Checkpoint**: E2E-P3.8-01, E2E-P3.8-02, and E2E-P3.8-03 exist and fail.

### 3.2 User Story 2 - Delete an installation that may still have coverage (Priority: P2)

**Independent Test**: E2E-P3.8-04, E2E-P3.8-05, and E2E-P3.8-06 in harness H-AP.

- [X] T004 [US2] Add the failing test `E2E-P3.8-04 A24 delete with paid time left holds the binding` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-001, FR-005, E2E-P3.8-04. Depends on T003 (same file). `deleteInstallation` on a clinic with an active term. The binding is `held_for_transfer` and the installation is `deleted`. `SELF.fetch` `POST /v1/requests` is `coverage_lapsed` with `coverage_reason` `transfer_pending`. A paid `vendorCall("grant")` is `transient` with `detail` `transfer_pending`. An issuer token on a clinic `/v1/*` route inserts no second binding. One AL-18 email is captured. A second `deleteInstallation` does not capture another AL-18. `setTestClock` 24 hours ahead and `runScheduled("0 3 * * *")` capture a further AL-18. `beginTransfer` from that held `from_installation_id` is `ok`. Do not add the four method names to `VendorMethod`. The unit command fails because `deleteInstallation` is not a method.

- [X] T005 [US2] Add the failing test `E2E-P3.8-05 delete with no coverage retires the binding and the next token creates epoch 2` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-005, E2E-P3.8-05. Depends on T004 (same file). `deleteInstallation` when the clinic has no active, grace, queued, or held term. The binding is `retired`. The next issuer token for that org inserts a binding with `epoch` 2. Do not add the four method names to `VendorMethod`. The unit command fails because a delete with no coverage does not leave a retired binding whose next token is epoch 2.

- [X] T006 [US2] Add the failing test `E2E-P3.8-06 voiding the remaining grants of a held binding retires it` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-006, E2E-P3.8-06. Depends on T005 (same file). `deleteInstallation` with coverage left, then `voidGrant` for each not-ended term. The binding is `retired`. The next issuer token inserts `epoch` one greater than the held row. Do not add the four method names to `VendorMethod`. Do not change `voidGrantRPC`. The unit command fails because `voidGrant` of the remaining grants does not retire the held binding.

**Checkpoint**: E2E-P3.8-04, E2E-P3.8-05, and E2E-P3.8-06 exist and fail.

### 3.3 User Story 3 - Void a paid grant after transfer (Priority: P3)

**Independent Test**: E2E-P3.8-07 in harness H-AP.

- [X] T007 [US3] Add the failing test `E2E-P3.8-07 voidForReversal of a moved paid grant lands on the new installation` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-007, E2E-P3.8-07. Depends on T006 (same file). After `transferIn`, `voidForReversal` for that paid `grant_id` with `partial` false is `applied`. `inspectCoverage` on the new installation shows that term `ended` with `end_reason` `reversed`. The old installation's term stays `end_reason` `transferred`. Do not add the four method names to `VendorMethod`. Do not change `voidForReversalRPC` or the tombstone branch. The unit command fails because `voidForReversal` does not change the new installation's term.

**Checkpoint**: E2E-P3.8-07 exists and fails.

### 3.4 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4)

**Independent Test**: E2E-P3.8-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [X] T008 [US4] Add the failing test `E2E-P3.8-08 purge of a deleted installation keeps the ledger` in `ai-platform/test/system/transfer-deletion.system.test.ts` — red test, FR-008, E2E-P3.8-08. Depends on T007 (same file). `deleteInstallation` reaches `purgeByInstallationId`. Afterward the `installation` row is still present with `status` `deleted`. `grant_ledger`, `grant_void`, `coverage_event`, and `transfer` rows for that clinic are still present. `usage_event` rows whose `term_id` is a term that has not ended are still present. Do not add the four method names to `VendorMethod`. The unit command fails because purge still removes the installation row.

**Checkpoint**: E2E-P3.8-08 exists and fails.

---

## 4. Implementation

**Purpose**: Sequencing steps 9–23. Each step starts after T001–T008 exist and fail. Within a subphase the tasks run in id order. A successful `beginTransfer` or `deleteInstallation` is `ok` with empty `code` and no `receipt`. `transferOut` and `transferIn` return `applied` or `already_applied` with the transfer receipt. Do not modify `packages/vendor-contracts`. Do not change `voidForReversalRPC`, `voidGrantRPC`, `releaseHeld`, `releaseHeldRPC`, `listGrantsForVoid`, or the tombstone write.

### 4.1 User Story 1 - Move a clinic's coverage to a new installation (Priority: P1) (part 1)

**Independent Test**: E2E-P3.8-01, E2E-P3.8-02, and E2E-P3.8-03 in harness H-AP.

- [X] T009 [US1] Add `ai-platform/migrations/20261006150000_transfer.sql` — produces `transfer` and `transfer_step`, FR-001, FR-002, E2E-P3.8-01, E2E-P3.8-03. Depends on T008. Do not edit earlier migrations. `transfer` columns are `transfer_id` (ULID, primary key), `org_id`, `from_installation_id`, `to_installation_id`, `reason`, `assertion_sha256`, `package` (JSON, null until `transferOut`), and `created_at`. `transfer_step` columns are `transfer_id`, `step` (`transfer_out` or `transfer_in`), `receipt`, and `applied_at`, unique on (`transfer_id`, `step`). A step row is inserted only when that step returns `applied`.

- [X] T010 [US1] Add `beginTransfer`, `transferOut`, `transferIn`, and `deleteInstallation` to `VendorMethod` and `METHOD_CLASS` in `ai-platform/test/system/harness.ts` — produces the four call names, FR-001, FR-002, FR-005, E2E-P3.8-01, E2E-P3.8-04. Depends on T009. `beginTransfer` and `deleteInstallation` are `HP`. `transferOut` and `transferIn` are `M`. Extend `operationParamsMatch` for those two HP ops: `beginTransfer` params are `{contract_version, access_jwt, org_id, from_installation_id, reason}`; `deleteInstallation` params are `{contract_version, access_jwt, org_id, reason}`.

- [X] T011 [US1] Add `beginTransfer` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`, with the binding re-creation in `ai-platform/src/coverage/transfer.ts` — produces the authorised `transfer` row and the next binding, FR-001, E2E-P3.8-01. Depends on T010. Class HP, same assertion flow as `setCeilingPolicy`. If `transfer.assertion_sha256` already matches, return `ok` with that row's JSON and do not insert another row or create another binding. Otherwise verify the assertion, then in one batch retire the source binding, insert the new `installation` and the next `epoch` as `active`, and insert `transfer` with `package` null and `to_installation_id` set to the new installation. `from_installation_id` must be that org's `active` or `held_for_transfer` row, and the transfer is for that same org only. Open the new DO with `awaiting_transfer` set and `binding_epoch` equal to the new epoch. `detail` is the JSON text of the `transfer` row. `code` is empty and `receipt` is absent.

- [X] T012 [US1] Add DO kind `transfer_out` in `ai-platform/src/quota-do/coverage.ts`, dispatch it from `GatewayObject.fetch` in `ai-platform/src/worker.ts`, build the package in `ai-platform/src/coverage/transfer.ts`, and call it from `transferOut` in `ai-platform/src/vendor/entrypoint.ts` — produces the moved package and the `transferred` source, FR-002, FR-003, E2E-P3.8-01. Depends on T011. `transferOut` requires a `transfer` row. Read not-ended terms and build a JSON array ordered by `position`, one object per term: `{origin_grant_id, position, state, plan_snapshot, allowance, duration_unit, duration_count, grace_days, grace_cap, calendar_start, starts_at, ends_at, grace_ends_at}`. Queued and held objects copy the stored term. An active object's `allowance` is that term's `allowance` minus `hot.used`. A grace object's `allowance` is min(`allowance` − `grace_base_used`, `grace_cap`) − (`hot.used` − `grace_base_used`). Remaining days are the unelapsed time until the stored `ends_at` (active) or `grace_ends_at` (grace). End those terms with `end_reason` `transferred`, set `transferred_out_to` to `to_installation_id`, store the package, insert `transfer_step` `transfer_out` with the transfer receipt, and emit `coverage_event` `kind` `transfer`. `detail` is the JSON text of the package. `term_ids` are the terms that step ended. `buildCoverageSnapshot` returns state `transferred` when `transferred_out_to` is set. A grant whose DO has `transferred_out_to` set is `rejected` with `code` `transferred_out` and writes nothing.

- [X] T013 [US1] On a second `transferOut`, return `already_applied` from `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/src/coverage/transfer.ts`, and return early `transferIn` as `transient` — produces the retry and the early-step refusal, FR-002, E2E-P3.8-03. Depends on T012 (same files). A second `transferOut` for the same `transfer_id` is `already_applied` and returns the stored receipt without writing. `transferIn` when no `transfer_out` step exists is `transient` with `detail` `awaiting_transfer_out` and writes nothing.

**Checkpoint**: E2E-P3.8-01 and E2E-P3.8-03 still need `transferIn`. E2E-P3.8-02 still needs the `awaiting_transfer` grant refusal.

### 4.2 User Story 1 - Move a clinic's coverage to a new installation (Priority: P1) (part 2)

**Independent Test**: E2E-P3.8-01, E2E-P3.8-02, and E2E-P3.8-03 in harness H-AP.

- [ ] T014 [US1] Add DO kind `transfer_in` in `ai-platform/src/quota-do/coverage.ts`, dispatch it from `GatewayObject.fetch` in `ai-platform/src/worker.ts`, apply the package from `ai-platform/src/coverage/transfer.ts`, and raise AL-11 from `ai-platform/src/alert/index.ts` — produces the destination terms and one transfer alert, FR-002, FR-003, E2E-P3.8-01, E2E-P3.8-03. Depends on T013. Insert the package terms on the destination DO, `origin_grant_id` copied, new `term_id`s from `generateUlid`, `grant_id` SHA-256 of `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. Clear `awaiting_transfer`, emit `coverage_event` `kind` `transfer` with `binding_epoch` of the new binding, and insert `transfer_step` `transfer_in`. The receipt's `term_ids` are the terms that step created. The outbox ships `grant_ledger` rows with `source_kind` `transfer` and `installation_id` of the new installation. On `applied`, raise one AL-11 for that `transfer_id` through `src/alert/index.ts` (captured `send_email`, codes and ids only). A retry is `already_applied` and does not raise AL-11 again. `transferOut` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts` stays the source step from T012.

- [ ] T015 [US1] Until `transferIn` has applied, refuse a non-transfer `grant` whose binding's DO has `awaiting_transfer` set, in `ai-platform/src/quota-do/coverage.ts` and `ai-platform/src/vendor/entrypoint.ts` — produces `transient` `awaiting_transfer`, FR-004, E2E-P3.8-02. Depends on T014. The result is `transient` with `detail` `awaiting_transfer` and writes nothing. After `transferIn`, that grant applies and is queued after the moved terms.

**Checkpoint**: E2E-P3.8-01, E2E-P3.8-02, and E2E-P3.8-03 still need the unit command after T015. E2E-P3.8-04, E2E-P3.8-05, E2E-P3.8-06, E2E-P3.8-07, and E2E-P3.8-08 still fail.

### 4.3 User Story 2 - Delete an installation that may still have coverage (Priority: P2) (part 1)

**Independent Test**: E2E-P3.8-04, E2E-P3.8-05, and E2E-P3.8-06 in harness H-AP.

- [ ] T016 [US2] Add `deleteInstallation` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`, using `ai-platform/src/coverage/transfer.ts` — produces the held binding, FR-005, E2E-P3.8-04. Depends on T015. Class HP. Mark the installation `deleted` and then call `purgeByInstallationId`. With an active, grace, queued, or held term, the binding becomes `held_for_transfer`, the DO sets `transfer_pending`, and AL-18 is sent once through `ai-platform/src/alert/index.ts`. A repeat while the installation is already `deleted` and the binding is still in that status is `ok`, does not insert a binding, and does not send AL-18 again. `detail` is the JSON text of `{installation, tenant_binding}`. `code` is empty and `receipt` is absent. The no-coverage retire path is T018.

- [ ] T017 [US2] Refuse admission and block a new binding while `transfer_pending` or `held_for_transfer` is set, in `ai-platform/src/quota-do/index.ts`, `ai-platform/src/identity/index.ts`, `ai-platform/src/config-cache/index.ts`, and `ai-platform/src/vendor/entrypoint.ts` — produces the deletion refusals, FR-005, E2E-P3.8-04. Depends on T016. In `admitOnHotRow`, after boundaries, a set `transfer_pending` flag returns `coverage_lapsed` with `coverage_reason` `transfer_pending` and does not reserve. A paid `grant` for an org whose live binding is `held_for_transfer` is `transient` with `detail` `transfer_pending` and does not insert a binding. A complimentary `grant` for that same held installation still applies, so the running calendar can be compensated, and it does not create a binding. In `src/identity/index.ts` and the `tenant_bindings` reader in `src/config-cache/index.ts`, a `held_for_transfer` row is returned and no insert runs. A `deleted` installation whose binding is `held_for_transfer` is still admitted so the DO can refuse. Any other non-active installation stays `unauthenticated`.

- [ ] T018 [US2] Retire the binding when `deleteInstallation` finds no coverage left, in `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/src/identity/index.ts` — produces epoch `max(epoch) + 1`, FR-005, E2E-P3.8-05. Depends on T017. With no active, grace, queued, or held term, set the binding `retired`. The next token for that org, when no `active` or `held_for_transfer` row exists, inserts epoch `max(epoch) + 1` (2 for the E2E clinic).

- [ ] T019 [US2] After `voidGrantRPC` returns `applied`, retire a `held_for_transfer` binding that has no remaining term, in `ai-platform/src/vendor/entrypoint.ts` — produces the retired held binding, FR-006, E2E-P3.8-06. Depends on T018 (same file). If that installation's binding is `held_for_transfer` and the DO has no active, grace, queued, or held term, set the binding `retired`. Do not change `voidGrantRPC`.

**Checkpoint**: E2E-P3.8-04 still needs the daily AL-18. E2E-P3.8-05 and E2E-P3.8-06 still need the unit command after T019. E2E-P3.8-07 and E2E-P3.8-08 still fail.

### 4.4 User Story 3 - Void a paid grant after transfer (Priority: P3)

**Independent Test**: E2E-P3.8-07 in harness H-AP.

- [ ] T020 [US3] Choose the destination installation in `voidForReversal` in `ai-platform/src/vendor/entrypoint.ts` — produces the void on the moved term, FR-007, E2E-P3.8-07. Depends on T019. When choosing the DO, use the latest `grant_ledger` row by `applied_at` whose `grant_id` or `origin_grant_id` equals the paid `grant_id`, and call the existing `void_for_reversal` kind on that `installation_id` with the org's active binding epoch. Do not change `voidForReversalRPC` or the tombstone branch. `voidForReversal` stays class M.

**Checkpoint**: E2E-P3.8-07 still needs the unit command after T020. E2E-P3.8-08 still fails.

### 4.5 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4)

**Independent Test**: E2E-P3.8-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T021 [US4] Change `purgeByInstallationId` in `ai-platform/src/retention/index.ts` — produces ledger retention, FR-008, E2E-P3.8-08. Depends on T020. Update `installation.status` to `deleted` and do not delete that row, `entitlement`, `tenant_binding`, `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, or `transfer_step`. Do not delete or update DO storage. `usage_event` deletes stay, except rows whose `term_id` belongs to a DO term that has not ended. Keep the existing deletes of requests, attempts, rollups, counters, and capability grants.

**Checkpoint**: E2E-P3.8-08 still needs the unit command after T021. Earlier purge assertions still expect removed rows until T023–T025.

### 4.6 User Story 2 - Delete an installation that may still have coverage (Priority: P2) (part 2)

**Independent Test**: E2E-P3.8-04, E2E-P3.8-05, and E2E-P3.8-06 in harness H-AP.

- [ ] T022 [US2] On the existing cron `0 3 * * *`, send AL-18 again for each binding still `held_for_transfer`, in `ai-platform/src/worker.ts` and `ai-platform/src/alert/index.ts` — produces the daily alert, FR-005, E2E-P3.8-04. Depends on T021. Send only when that binding's last AL-18 send is at least 24 hours earlier. Do not add a cron. A binding that is no longer held is not sent.

**Checkpoint**: E2E-P3.8-01 through E2E-P3.8-08 are ready for the assertion updates and the unit command.

### 4.7 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4) — retention assertions

**Independent Test**: E2E-P3.8-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T023 [US4] Update purge assertions in `ai-platform/test/retention.test.ts` — produces kept-row expectations, FR-008, E2E-P3.8-08. Depends on T021. Expect the installation row kept with `status` `deleted`, and expect `entitlement` and `tenant_binding` kept. This is the same purge change as T024 and T025.

### 4.8 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4) — lifecycle assertions

**Independent Test**: E2E-P3.8-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T024 [US4] Update `SYS-2.4` in `ai-platform/test/system/lifecycle-interplay.system.test.ts` — produces kept-row expectations, FR-008, E2E-P3.8-08. Depends on T021. Expect the installation row kept with `status` `deleted`, and expect `entitlement` and `tenant_binding` kept. Leave the `unauthenticated` assertion after purge.

### 4.9 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4) — stage-03 assertions

**Independent Test**: E2E-P3.8-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T025 [US4] Update purge assertions in `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` — produces kept-row expectations, FR-008, E2E-P3.8-08. Depends on T021. Expect the installation row kept with `status` `deleted`, and expect `entitlement` and `tenant_binding` kept.

**Checkpoint**: Earlier purge assertions match the retained rows. The unit file is ready for the harness command.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2). This task does not name that run. Sequencing step 24's path check is this command: the only vitest path is the unit file, and `ai-platform/src/coverage/transfer.ts` is reached from `beginTransfer`, `transferOut`, `transferIn`, and `deleteInstallation`.

### 5.1 Unit harness

- [ ] T026 Run harness H-AP for this unit and confirm E2E-P3.8-01 through E2E-P3.8-08 pass together — produces the green run, FR-001 through FR-008, E2E-P3.8-01 through E2E-P3.8-08. Depends on T009 through T025 (and therefore on T001–T008). This task may edit only `ai-platform/test/system/transfer-deletion.system.test.ts`. `packages/vendor-contracts/**` stays unchanged. `voidForReversalRPC`, `voidGrantRPC`, `releaseHeld`, `releaseHeldRPC`, `listGrantsForVoid`, and the tombstone write stay unchanged. SC-002 is the review's run of earlier suites, not this command.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/transfer-deletion.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T026 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` stays a plan-phase artifact. No other doc task.

### 6.1 Quickstart

- [ ] T027 Create `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-008, E2E-P3.8-01 through E2E-P3.8-08. Depends on T026. Sections: (1) what was implemented — `beginTransfer`, `transferOut`, `transferIn`, `deleteInstallation`, transfer lineage on the existing void call, and purge retention; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) harness command for this unit's tests only — the command below; (4) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/transfer-deletion.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.8-01 | `coverClinic()` → queued paid `vendorCall("grant")` → `vendorCall("beginTransfer")` → `vendorCall("transferOut")` → `vendorCall("transferIn")` on `VendorEntrypoint` → `src/coverage/transfer.ts` → DO `transfer_out` / `transfer_in` → `getCoverage` on the old installation → `vendorCall("grant")` on the old installation → `coverage_event.binding_epoch` and captured AL-11 |
| E2E-P3.8-02 | `beginTransfer` so the new DO is `awaiting_transfer` → `vendorCall("grant")` → `vendorCall("transferIn")` → `vendorCall("grant")` again → `inspectCoverage` on the new installation |
| E2E-P3.8-03 | `vendorCall("transferOut")` and `vendorCall("transferIn")` retried with the same `transfer_id`; `vendorCall("transferIn")` before `transferOut` |
| E2E-P3.8-04 | `vendorCall("deleteInstallation")` → `SELF.fetch` `POST /v1/requests` → `vendorCall("grant")` → issuer token on a clinic `/v1/*` route → captured AL-18 → `setTestClock` plus one day → `runScheduled("0 3 * * *")` → `vendorCall("beginTransfer")` from the held binding |
| E2E-P3.8-05 | `vendorCall("deleteInstallation")` with no coverage → issuer token on a clinic `/v1/*` route → `tenant_binding.epoch` |
| E2E-P3.8-06 | `vendorCall("deleteInstallation")` with coverage → `vendorCall("voidGrant")` for the remaining grants → issuer token on a clinic `/v1/*` route |
| E2E-P3.8-07 | Transfer a paid grant → `vendorCall("voidForReversal")` → `inspectCoverage` on the new installation |
| E2E-P3.8-08 | `vendorCall("deleteInstallation")` → `purgeByInstallationId` → D1 counts for `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, `installation`, and unended-term `usage_event` |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests**: T001 through T008, in Sequencing steps 1–8. No Setup phase.
- **Implementation**: T009 through T025, after those tests exist and fail. T009 through T022 are Sequencing steps 9–22. T023 through T025 are Sequencing step 23, after T021 has stopped the deletes.
- **Verification**: T026, after T009 through T025.
- **Documentation**: T027, after T026 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001–T003, then T009–T015. `beginTransfer`, `transferOut`, and `transferIn` are the path User Stories 2, 3, and 4 call.
- **User Story 2 (P2)**: T004–T006 after the User Story 1 tests, because they share `ai-platform/test/system/transfer-deletion.system.test.ts`. Implementation T016–T019 and T022 starts after T015. T022 waits until T021 because Sequencing places the daily AL-18 after purge retention.
- **User Story 3 (P3)**: T007 after T006 (same test file). T020 starts after T019 and uses the moved `grant_ledger` row from User Story 1. It does not change `voidForReversalRPC`.
- **User Story 4 (P4)**: T008 after T007 (same test file). T021 starts after T020. T023, T024, and T025 start after T021 and edit three different existing test files.

### 7.3 Parallel Opportunities

- T001–T008 are not marked `[P]`. They all write `ai-platform/test/system/transfer-deletion.system.test.ts`.
- T009 writes only `ai-platform/migrations/20261006150000_transfer.sql`. T010 writes only `ai-platform/test/system/harness.ts`. T011 through T013 share `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/src/coverage/transfer.ts`. T012 also writes `ai-platform/src/quota-do/coverage.ts` and `ai-platform/src/worker.ts`. They stay in id order.
- T014 and T015 share `ai-platform/src/quota-do/coverage.ts` and `ai-platform/src/vendor/entrypoint.ts`. T014 also writes `ai-platform/src/worker.ts`, `ai-platform/src/coverage/transfer.ts`, and `ai-platform/src/alert/index.ts`. They stay in id order.
- T016 through T019 share `ai-platform/src/vendor/entrypoint.ts`. T016 also writes `ai-platform/src/coverage/transfer.ts` and `ai-platform/src/alert/index.ts`. T017 also writes `ai-platform/src/quota-do/index.ts`, `ai-platform/src/identity/index.ts`, and `ai-platform/src/config-cache/index.ts`. T018 also writes `ai-platform/src/identity/index.ts`. They stay in id order.
- T020 writes `ai-platform/src/vendor/entrypoint.ts` only after T019. T021 writes `ai-platform/src/retention/index.ts` only after T020. T022 writes `ai-platform/src/worker.ts` and `ai-platform/src/alert/index.ts` only after T021.
- T023, T024, and T025 each write one existing test file. Sequencing step 23 names them together, after T021, with no order among the three files.
- T026 and T027 are single tasks. T027 waits until T026 is green.

---

## 8. Implementation Waves

### Wave 1

- T001–T003 [US1] — subphase: `### 3.1 User Story 1 - Move a clinic's coverage to a new installation (Priority: P1)` — paths: `ai-platform/test/system/transfer-deletion.system.test.ts`

### Wave 2

- T004–T006 [US2] — subphase: `### 3.2 User Story 2 - Delete an installation that may still have coverage (Priority: P2)` — paths: `ai-platform/test/system/transfer-deletion.system.test.ts`

### Wave 3

- T007 [US3] — subphase: `### 3.3 User Story 3 - Void a paid grant after transfer (Priority: P3)` — paths: `ai-platform/test/system/transfer-deletion.system.test.ts`

### Wave 4

- T008 [US4] — subphase: `### 3.4 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4)` — paths: `ai-platform/test/system/transfer-deletion.system.test.ts`

### Wave 5

- T009–T013 [US1] — subphase: `### 4.1 User Story 1 - Move a clinic's coverage to a new installation (Priority: P1) (part 1)` — paths: `ai-platform/migrations/20261006150000_transfer.sql`, `ai-platform/test/system/harness.ts`, `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/coverage/transfer.ts`, `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/worker.ts`

### Wave 6

- T014–T015 [US1] — subphase: `### 4.2 User Story 1 - Move a clinic's coverage to a new installation (Priority: P1) (part 2)` — paths: `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/worker.ts`, `ai-platform/src/coverage/transfer.ts`, `ai-platform/src/alert/index.ts`, `ai-platform/src/vendor/entrypoint.ts`

### Wave 7

- T016–T019 [US2] — subphase: `### 4.3 User Story 2 - Delete an installation that may still have coverage (Priority: P2) (part 1)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/coverage/transfer.ts`, `ai-platform/src/alert/index.ts`, `ai-platform/src/quota-do/index.ts`, `ai-platform/src/identity/index.ts`, `ai-platform/src/config-cache/index.ts`

### Wave 8

- T020 [US3] — subphase: `### 4.4 User Story 3 - Void a paid grant after transfer (Priority: P3)` — paths: `ai-platform/src/vendor/entrypoint.ts`

### Wave 9

- T021 [US4] — subphase: `### 4.5 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4)` — paths: `ai-platform/src/retention/index.ts`

### Wave 10

- T022 [US2] — subphase: `### 4.6 User Story 2 - Delete an installation that may still have coverage (Priority: P2) (part 2)` — paths: `ai-platform/src/worker.ts`, `ai-platform/src/alert/index.ts`

### Wave 11

- T023 [US4] — subphase: `### 4.7 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4) — retention assertions` — paths: `ai-platform/test/retention.test.ts`
- T024 [US4] — subphase: `### 4.8 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4) — lifecycle assertions` — paths: `ai-platform/test/system/lifecycle-interplay.system.test.ts`
- T025 [US4] — subphase: `### 4.9 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4) — stage-03 assertions` — paths: `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts`

### Wave 12

- T026 — subphase: `### 5.1 Unit harness` — paths: `ai-platform/test/system/transfer-deletion.system.test.ts`

### Wave 13

- T027 — subphase: `### 6.1 Quickstart` — paths: `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/quickstart.md`
