# Tasks: Console passkey ceremony and ABO-side HP actions

**Input**: Design documents from `specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.6 (class-H `recordOperatorAction` on `VendorEntrypoint`) and P3.1 (`listOperatorCredentials`, method dispatch, class table, auth refusal codes, credential lifecycle, alert body format, `platform_alert`). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`. That plan artifact is already written. It is not an implement task. `research.md` is not a task: Spikes is none, so the plan phase did not write it. `contracts/` is not a task: Freezes has no wire shape. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id, written to fail before the HP routes exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 14. Size M is 20–32 (rule S3). The count is one task per E2E id (7), one task per Files unit that is not already one of those tests and was not written in the plan phase (the vitest include and 4 production files), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §6.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/src/vendor/entrypoint.ts` — consumed and not modified. `listOperatorCredentials` and `recordOperatorAction` stay as P3.1 and P4.6 froze them
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed (`validateOperation`, `operationChallenge`, `verifyAssertion`, `canonicalize`, `sha256Hex`, and the testkit `createSoftwareAuthenticator`) and not modified
- **Spec Kit artifacts**: `specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/`
- Leave `abo/src/worker.ts`, `abo/test/system/harness.ts`, `abo/wrangler.toml`, and `data-model.md` unchanged. The worker fetch already delegates `OPS_HOST` + `/ops/*`. `opsFetch` stays in the harness. `handleOps` in `abo/src/ops/index.ts` gains the HP routes and keeps the existing console routes

---

## 3. Setup

**Purpose**: Sequencing step 1, before the failing tests. The vitest include is the scaffold those tests need. The `abo/` Worker already exists.

### 3.1 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — vitest include

**Independent Test**: E2E-P4.7-03 and E2E-P4.7-07 in harness H-XW.

- [X] T001 [US1] Add the HP-actions test include in `abo/vitest.cross-worker.config.ts` — produces the H-XW include for this unit, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, E2E-P4.7-04, E2E-P4.7-05, E2E-P4.7-06, E2E-P4.7-07. Depends on nothing. Add `test/system/hp-actions.cross-worker.test.ts` to the H-XW `include` list. The unit command still names only that file. Leave `abo/test/system/hp-actions.cross-worker.test.ts` uncreated in this task.

**Checkpoint**: The include lists `test/system/hp-actions.cross-worker.test.ts`. That file does not exist yet.

---

## 4. Tests

**Purpose**: Sequencing step 1 continued. One failing test per E2E id, all in `abo/test/system/hp-actions.cross-worker.test.ts`. There is no eighth E2E id. Reinstate has no E2E id. The harness builds the operation object and the challenge with the package and signs with `createSoftwareAuthenticator` using a credential `listOperatorCredentials` lists as active. Entry is `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`. No scenario sleeps more than 2 s (rule V4). Time moves with the ABO test clock.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/hp-actions.cross-worker.test.ts
```

### 4.1 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — tests

**Independent Test**: E2E-P4.7-03 and E2E-P4.7-07 in harness H-XW.

- [X] T002 [US1] Add the failing test `E2E-P4.7-03` in `abo/test/system/hp-actions.cross-worker.test.ts` — red test, FR-001, FR-002, FR-003, E2E-P4.7-03. Depends on T001. Create the file and the shared setup. Three `opsFetch` HP calls on `POST /ops/offers/:offerId/publish`. The operation is `{op, params, actor_email, issued_at, nonce, contract_version}` with `op` `publish_offer` and `params` the action input without the assertion. The challenge is base64url(SHA-256(canonical operation object)). One call omits `assertion` and is rejected with `assertion_required`. One call’s operation does not match the challenge and is refused; the spec names no separate code for that mismatch. One call’s `issued_at` is more than 5 minutes before the ABO test clock and is rejected with `assertion_expired`. Each refusal inserts `operator_action` and does not call `recordOperatorAction`. The command fails because those HP routes are absent from `abo/src/ops/index.ts`.

- [X] T003 [US1] Add the failing test `E2E-P4.7-07` in `abo/test/system/hp-actions.cross-worker.test.ts` — red test, FR-002, FR-004, E2E-P4.7-07. Depends on T002 (same file). Revoke the credential with `revokeOperatorCredential` on the real `VendorEntrypoint`, then `opsFetch` an HP action. The next check calls `listOperatorCredentials` again. The id is absent from that active-only `{credential_id, public_key_cose, alg}` list, so the action is rejected with `credential_not_active`. The command fails because those HP routes are absent from `abo/src/ops/index.ts`.

**Checkpoint**: E2E-P4.7-03 and E2E-P4.7-07 exist and fail.

### 4.2 User Story 2 - Publish and retire an offer (Priority: P2) — tests

**Independent Test**: E2E-P4.7-01 and E2E-P4.7-02 in harness H-XW.

- [X] T004 [US2] Add the failing test `E2E-P4.7-01` in `abo/test/system/hp-actions.cross-worker.test.ts` — red test, FR-005, FR-007, FR-011, E2E-P4.7-01. Depends on T003 (same file). `opsFetch` publishes offer v2 at a new price with a passkey. `billingFetch` `GET /v1/offers` shows v2. An open v1 checkout is still charged and granted at v1. Past prices remain in `offer_version`. The command fails because those HP routes are absent from `abo/src/ops/index.ts`.

- [X] T005 [US2] Add the failing test `E2E-P4.7-02` in `abo/test/system/hp-actions.cross-worker.test.ts` — red test, FR-006, FR-007, FR-011, E2E-P4.7-02. Depends on T004 (same file). `opsFetch` retires the offer with a passkey. `billingFetch` `GET /v1/offers` no longer shows it. `billingFetch` `POST /v1/checkouts` on it returns `offer_unavailable`. Existing platform terms on the real platform worker are unchanged. The command fails because those HP routes are absent from `abo/src/ops/index.ts`.

**Checkpoint**: E2E-P4.7-01 and E2E-P4.7-02 exist and fail. E2E-P4.7-03 and E2E-P4.7-07 still fail.

### 4.3 User Story 3 - Release, chargeback, and erasure (Priority: P3) — tests

**Independent Test**: E2E-P4.7-04, E2E-P4.7-05, and E2E-P4.7-06 in harness H-XW. Earlier suites stay green, and E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, and E2E-P4.7-07 still pass.

- [X] T006 [US3] Add the failing test `E2E-P4.7-04` in `abo/test/system/hp-actions.cross-worker.test.ts` — red test, FR-008, FR-011, E2E-P4.7-04. Depends on T005 (same file). `opsFetch` releases a withheld payment with a passkey, then the harness runs `runDueGrantWork` until the grant is applied. A second `opsFetch` releases a withheld payment that existing reversal rows already treat as fully reversed (`is_full`). That call is refused, appends no `payment_release`, and starts no grant. The spec names no refusal code for that release. The command fails because those HP routes are absent from `abo/src/ops/index.ts`.

- [X] T007 [US3] Add the failing test `E2E-P4.7-05` in `abo/test/system/hp-actions.cross-worker.test.ts` — red test, FR-009, FR-011, E2E-P4.7-05. Depends on T006 (same file). The test completes a real H-XW purchase so the payment funds the current term. `opsFetch` records the manual chargeback (`source=operator`, `detected_via=manual`). The P4.5 effect pipeline on the real platform worker voids, reverses the term, holds queued, and fires AL-06. The command fails because those HP routes are absent from `abo/src/ops/index.ts`.

- [X] T008 [US3] Add the failing test `E2E-P4.7-06` in `abo/test/system/hp-actions.cross-worker.test.ts` — red test, FR-010, FR-011, E2E-P4.7-06. Depends on T007 (same file). `opsFetch` erases the tenant’s contact data with a passkey. `name`, `email`, and `phone` are blank on every version, `erased_at` is set, that tenant’s raw R2 bodies are deleted, D1 hashes and the `ledger/` export stay, and `billingFetch` `POST /v1/checkouts` returns `billing_contact_required`. The command fails because those HP routes are absent from `abo/src/ops/index.ts`.

**Checkpoint**: E2E-P4.7-04, E2E-P4.7-05, and E2E-P4.7-06 exist and fail. E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, and E2E-P4.7-07 still fail.

---

## 5. Implementation

**Purpose**: Sequencing steps 2–7. Starts after T002–T008 exist and those E2E tests fail. Inside `abo/src/ops/index.ts`, do the work in Sequencing order: HP verification, then the catalogue action, then release, then manual chargeback, then erasure. `abo/src/clinic-api/checkouts.ts` and `abo/src/work/grant.ts` follow that module. Within a subphase the tasks run in id order.

### 5.1 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — assertion_used and payment_release

**Independent Test**: E2E-P4.7-03 and E2E-P4.7-07 in harness H-XW.

- [X] T009 [US1] Add `abo/migrations/0007_hp_actions.sql` — produces append-only `assertion_used` and `payment_release`, FR-002, FR-008, E2E-P4.7-03, E2E-P4.7-04, E2E-P4.7-07. Depends on T008. `assertion_used` has primary key `challenge_sha256`. `payment_release` has primary key `payment_id` plus `operator_action_id` and `at`. Both abort update and delete. Leave `data-model.md` unchanged. Leave `abo/src/ops/index.ts` without the HP routes in this task. The harness applies this file before the HP-actions tests.

**Checkpoint**: E2E-P4.7-03 and E2E-P4.7-07 can store a spent challenge hash. E2E-P4.7-04 can store `payment_release`. The HP-actions tests still fail until the routes exist.

### 5.2 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — HP routes

**Independent Test**: E2E-P4.7-03 and E2E-P4.7-07 in harness H-XW.

- [X] T010 [US1] Add HP verification and the HP actions in `abo/src/ops/index.ts` — produces the ceremony check and the six routes, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, E2E-P4.7-04, E2E-P4.7-05, E2E-P4.7-06, E2E-P4.7-07. Depends on T009. Keep the existing console routes. In this task, in order: verification, catalogue, release, manual chargeback, erasure. Leave `abo/src/clinic-api/checkouts.ts` and `abo/src/work/grant.ts` unchanged in this task. Every new route runs the existing `verifyOpsAccess` first. A missing, expired, or wrong-`aud` Access JWT is `unauthenticated` and writes nothing. Routes: `POST /ops/offers/:offerId/publish`, `POST /ops/offers/:offerId/retire`, `POST /ops/offers/:offerId/reinstate`, `POST /ops/payments/:paymentId/release`, `POST /ops/payments/:paymentId/chargeback`, `POST /ops/orgs/:orgId/erase-contact`. `operator_action.action` and the operation `op` are `publish_offer`, `retire_offer`, `reinstate_offer`, `release_payment`, `manual_chargeback`, or `erase_contact`. `subject` is the offer id, payment id, or org id in the path. Bootstrap `registerOperatorCredential` is not an ABO route. The request carries `operation` and `assertion`. The operation is `{op, params, actor_email, issued_at, nonce, contract_version}`. `params` is the action input without the assertion. `validateOperation` and `operationChallenge` come from the package. `actor_email` must equal the Access JWT email (`actor_email_mismatch`). `issued_at` more than 5 minutes from `clockNowMs` is `assertion_expired`. A class HP call that omits `assertion` is `assertion_required`. These refusals insert `operator_action` and do not call `recordOperatorAction`. The challenge hash is `sha256Hex(canonicalize(operation))`. If `assertion_used` already holds it, the call is `assertion_used` and the HP write does not run. On acceptance the hash is inserted before the HP write. Each verification calls `listOperatorCredentials` once and looks up `credential_id` in that active-only array. An absent id is `credential_not_active`, including a still-pending row, a revoked row, and an unknown id. `credential_revoked` stays the platform's code when its own credential read sees `status` `revoked`. This unit does not add a platform method. `verifyAssertion` uses the matching `public_key_cose` and `alg`, `rpId` `OPS_HOST`, and origin `https://` plus `OPS_HOST`. An assertion over a different operation fails that check, is refused, and `operator_action` records the result. The spec names no separate code for that mismatch. `rpId` is the console hostname. `type` is `webauthn.get`. User presence and user verification are both set. The algorithm is ES256 or EdDSA. Publish, retire, and reinstate share one handler. Publish inserts `offer_version` at the new price with `assertion_sha256` set to the challenge hash, inserts `offer_event` kind `published`, and stores the terms text at the new `terms_version.text_r2_key`. Retire inserts `offer_event` kind `retired`. Reinstate inserts `offer_event` kind `reinstated`. Past `offer_version` rows stay. An open checkout keeps its snapshot. After `operator_action` commits, the handler calls `recordPlatformOperatorAction` via `env.PLATFORM.recordOperatorAction` with `contract_version`, `access_jwt`, and `action`, `subject`, and `action_id` copied from that row. That call inserts one `control_audit` row and leaves every other platform table unchanged. It is not called on refusal. `release_payment` requires a withheld payment. If existing reversal rows already treat it as fully reversed (`is_full`), the call is refused, `operator_action` records the result, and there is no `payment_release` and no grant work. Otherwise the handler appends `payment_release` (`payment_id`, `operator_action_id`, `at`) and inserts the same `work` row the paid path inserts (`kind` `grant`, dedupe `grant:${paymentId}`). A withheld payment row is not updated. `manual_chargeback` inserts `reversal` with `source` `operator`, `detected_via` `manual`, `kind` `chargeback`, amount and cumulative equal to the payment amount, `is_full` true, `recorded_by` the Access email, and `evidence_sha256` the challenge hash. The dedupe key and reversal id use the existing `reversalDedupeKey` and `reversalIdFromDedupeKey` with that payment's parent transaction. `effect` comes from `determineReversalEffect`. The handler raises AL-06 through `raiseAlert`, then `insertReverseWorkRow` and `processReverseWork` so the existing pipeline voids on the real platform worker, reverses the current term, and holds queued. `operator_action` is committed before `recordOperatorAction`. `erase_contact` blanks `name`, `email`, and `phone` on every `billing_contact` version of that `org_id`, sets `erased_at` and `erased_by`, deletes that tenant's raw R2 bodies, and leaves the hash columns and `ledger/` objects. `operator_action` is committed before `recordOperatorAction`.

**Checkpoint**: E2E-P4.7-03 and E2E-P4.7-07 are refused by HP verification. Catalogue, release, chargeback, and erasure write through `handleOps`. E2E-P4.7-02 still needs the sellable check. E2E-P4.7-04 still needs grant-work eligibility.

### 5.3 User Story 2 - Publish and retire an offer (Priority: P2) — sellable offer

**Independent Test**: E2E-P4.7-01 and E2E-P4.7-02 in harness H-XW.

- [X] T011 [US2] Teach `sellableOfferVersion` in `abo/src/clinic-api/checkouts.ts` to follow the latest `offer_event` — produces `offer_unavailable` for a retired offer, FR-006, E2E-P4.7-02. Depends on T010. Return null when the latest `offer_event` for the offer is not `published`, so checkout keeps returning `offer_unavailable`. When the latest event is `published`, return the latest published version. Leave `abo/src/ops/index.ts` unchanged in this task. Leave `abo/src/work/grant.ts` unchanged in this task.

**Checkpoint**: E2E-P4.7-02’s checkout on a retired offer is `offer_unavailable`. E2E-P4.7-01’s open v1 checkout still uses its snapshot.

### 5.4 User Story 3 - Release, chargeback, and erasure (Priority: P3) — grant after release

**Independent Test**: E2E-P4.7-04, E2E-P4.7-05, and E2E-P4.7-06 in harness H-XW. Earlier suites stay green, and E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, and E2E-P4.7-07 still pass.

- [X] T012 [US3] Run the existing grant work when `payment_release` exists in `abo/src/work/grant.ts` — produces the applied grant for a withheld release, FR-008, E2E-P4.7-04. Depends on T010. `runDueGrantWork` and the payment’s `grant:${paymentId}` row also run when a `payment_release` row exists for that payment. Disposition `grant` stays the paid path’s gate. A withheld payment is not updated. Leave `abo/src/ops/index.ts` unchanged in this task. Leave `abo/src/clinic-api/checkouts.ts` unchanged in this task.

**Checkpoint**: E2E-P4.7-04’s withheld release can apply the grant. The fully reversed release still writes no `payment_release` and starts no grant.

---

## 6. Verification

**Purpose**: After T010, T011, and T012, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command.

### 6.1 Unit harness

**Independent Test**: E2E-P4.7-04, E2E-P4.7-05, and E2E-P4.7-06 in harness H-XW. Earlier suites stay green, and E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, and E2E-P4.7-07 still pass.

- [ ] T013 [US3] Run `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/hp-actions.cross-worker.test.ts` from `abo/` until E2E-P4.7-01 through E2E-P4.7-07 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, E2E-P4.7-04, E2E-P4.7-05, E2E-P4.7-06, E2E-P4.7-07. Depends on T009, T010, T011, and T012 (and therefore on T001–T008). This task may edit only files under `abo/test/`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/hp-actions.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.7-01 through E2E-P4.7-07 pass.

---

## 7. Documentation

**Purpose**: After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 7.1 Quickstart

- [ ] T014 [US3] Create `specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, E2E-P4.7-04, E2E-P4.7-05, E2E-P4.7-06, E2E-P4.7-07. Depends on T013. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps; the harness observes every scenario.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/hp-actions.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.7-01 | `opsFetch` publish → `handleOps` catalogue action → `offer_event` / `offer_version` / terms R2 / `operator_action` / `recordOperatorAction`. Outcome: `billingFetch` `GET /v1/offers` (`listOffers`) and the open v1 checkout’s existing charge and grant |
| E2E-P4.7-02 | `opsFetch` retire → `handleOps` catalogue action. Outcome: `billingFetch` `GET /v1/offers` and `POST /v1/checkouts` (`sellableOfferVersion`), and existing platform terms on the real platform worker |
| E2E-P4.7-03 | `opsFetch` three HP calls → `handleOps` verification → `operator_action`. One call omits `assertion`. One call’s operation does not match the challenge. The test clock places one `issued_at` more than 5 minutes in the past |
| E2E-P4.7-04 | `opsFetch` release → `handleOps` → `payment_release` and grant `work` → `runDueGrantWork`. The refusal case uses a withheld payment whose reversal rows are already fully reversed |
| E2E-P4.7-05 | A real H-XW purchase so the payment funds the current term. `opsFetch` chargeback → `handleOps` → `reversal` → `determineReversalEffect`, `raiseAlert`, `insertReverseWorkRow`, `processReverseWork` → platform `voidForReversal` |
| E2E-P4.7-06 | `opsFetch` erase → `handleOps` → `billing_contact` and R2 evidence keys. Outcome: D1 hashes, `ledger/` export, then `billingFetch` `POST /v1/checkouts` |
| E2E-P4.7-07 | Platform `revokeOperatorCredential` on the real `VendorEntrypoint`, then `opsFetch` HP → `handleOps` calls `listOperatorCredentials` again |

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (Phase 3)**: T001 writes `abo/vitest.cross-worker.config.ts` before T002 creates `abo/test/system/hp-actions.cross-worker.test.ts`.
- **Tests (Phase 4)**: T002 through T008 stay in id order in `abo/test/system/hp-actions.cross-worker.test.ts`. User Story 1 tests are T002–T003. User Story 2 tests are T004–T005. User Story 3 tests are T006–T008. They fail because the HP routes are absent from `abo/src/ops/index.ts`.
- **Implementation (Phase 5)**: Starts after T008. The migration (T009) finishes before `abo/src/ops/index.ts` inserts `assertion_used` or `payment_release`. That module (T010) finishes before the sellable check (T011) and grant-work eligibility (T012). Inside T010 the order is HP verification, catalogue, release, manual chargeback, then erasure.
- **Verification (Phase 6)**: Depends on T009, T010, T011, and T012. Runs only the command in §6.1.
- **Documentation (Phase 7)**: Depends on T013 being green.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: The vitest include is T001, before the tests. Tests T002 and T003. The migration is T009. HP verification is the first work inside T010. E2E-P4.7-03 and E2E-P4.7-07.
- **User Story 2 (P2)**: Tests T004 and T005 after T003, in that id order, in the same file. The catalogue action is inside T010, after verification. The sellable check is T011, after T010. E2E-P4.7-01 and E2E-P4.7-02.
- **User Story 3 (P3)**: Tests T006, T007, and T008 after T005. Release, manual chargeback, and erasure are inside T010, after the catalogue action. Grant-work eligibility is T012, after T010. E2E-P4.7-04, E2E-P4.7-05, and E2E-P4.7-06, with E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, and E2E-P4.7-07 still passing once T013 is green.

### 8.3 Within Each Phase

- T001 writes only `abo/vitest.cross-worker.config.ts`.
- T002 creates `abo/test/system/hp-actions.cross-worker.test.ts` after T001. T003 through T008 all write that same file, in that id order.
- T009 writes only `abo/migrations/0007_hp_actions.sql` after T008, and does not add the HP routes.
- T010 writes only `abo/src/ops/index.ts` after T009, and does not write `abo/src/clinic-api/checkouts.ts` or `abo/src/work/grant.ts`.
- T011 writes only `abo/src/clinic-api/checkouts.ts` after T010.
- T012 writes only `abo/src/work/grant.ts` after T010.
- T013 runs after T011 and T012 and may edit only `abo/test/`.
- T014 writes only `specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/quickstart.md` after T013 is green.

---

## 9. Implementation Waves

### 9.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — vitest include` — paths: `abo/vitest.cross-worker.config.ts`

### 9.2 Wave 2

- T002–T003 [US1] — subphase: `### 4.1 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — tests` — paths: `abo/test/system/hp-actions.cross-worker.test.ts`

### 9.3 Wave 3

- T004–T005 [US2] — subphase: `### 4.2 User Story 2 - Publish and retire an offer (Priority: P2) — tests` — paths: `abo/test/system/hp-actions.cross-worker.test.ts`

### 9.4 Wave 4

- T006–T008 [US3] — subphase: `### 4.3 User Story 3 - Release, chargeback, and erasure (Priority: P3) — tests` — paths: `abo/test/system/hp-actions.cross-worker.test.ts`

### 9.5 Wave 5

- T009 [US1] — subphase: `### 5.1 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — assertion_used and payment_release` — paths: `abo/migrations/0007_hp_actions.sql`

### 9.6 Wave 6

- T010 [US1] — subphase: `### 5.2 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1) — HP routes` — paths: `abo/src/ops/index.ts`

### 9.7 Wave 7

- T011 [US2] — subphase: `### 5.3 User Story 2 - Publish and retire an offer (Priority: P2) — sellable offer` — paths: `abo/src/clinic-api/checkouts.ts`
- T012 [US3] — subphase: `### 5.4 User Story 3 - Release, chargeback, and erasure (Priority: P3) — grant after release` — paths: `abo/src/work/grant.ts`

### 9.8 Wave 8

- T013 [US3] — subphase: `### 6.1 Unit harness` — paths: `abo/test/`

### 9.9 Wave 9

- T014 [US3] — subphase: `### 7.1 Quickstart` — paths: `specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/quickstart.md`
