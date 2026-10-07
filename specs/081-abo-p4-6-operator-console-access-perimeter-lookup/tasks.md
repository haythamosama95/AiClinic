# Tasks: Operator console: Access perimeter, lookup, views and class-H ABO actions

**Input**: Design documents from `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.5 (no frozen contract; later payment stays `paid_late` in the existing sweep) and P3.6 (`inspectCoverage`, `suspend`, `resume`). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/`. Those plan artifacts are already written. They are not implement tasks. `research.md` is not a task: Spikes is none, so the plan phase did not write it. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id, written to fail before `abo/src/ops/index.ts` and `recordOperatorAction` exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 15. Size M is 20–32 (rule S3). The count is one task per E2E id (7), one task per Files unit that is not already one of those tests and was not written in the plan phase (the Access fixture, the vitest include, and 4 production files), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §6.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/src/vendor/entrypoint.ts` — wiring exception (rules S3, S7, S10): add and freeze class-H `recordOperatorAction` on the existing `VendorEntrypoint`. Leave `inspectCoverage`, `suspend`, `resume`, `listGrants`, `listIssuerKeys`, `listServiceKeys`, and `listOperatorCredentials` unchanged
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed (`verifyAccessJwt`, `subscriptionRef`, `humanRef`, `canonicalize`, `sha256Hex`, `CHANNEL_VERSIONS`) and not modified. The ABO worker does not grow a second Access checker
- **Spec Kit artifacts**: `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/`
- Leave `abo/src/work/runner.ts`, `abo/src/work/sweep.ts`, `abo/src/work/grant.ts`, `abo/src/clinic-api/version.ts`, `abo/test/system/harness.ts`, `abo/wrangler.toml`, `data-model.md`, and `contracts/record-operator-action.md` unchanged. `opsFetch` stays in the harness. No `TEST_CLOCK` var is added to production or staging. No second worker, no stub, and no new wrangler binding

---

## 3. Setup

**Purpose**: Sequencing step 1, before the failing tests. The vitest include and the Access JWT fixture are the scaffold those tests need. The `abo/` Worker already exists.

### 3.1 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — vitest include

**Independent Test**: E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07 in harness H-XW.

- [X] T001 [US1] Add the ops test include in `abo/vitest.cross-worker.config.ts` — produces the H-XW include for this unit, FR-001, E2E-P4.6-01. Depends on nothing. Add `test/system/ops.cross-worker.test.ts` to `test.include`. The unit command still names only that file. Leave `TEST_CLOCK` off production and staging wrangler envs. Leave `abo/test/system/hxw-access-fixture.ts` unchanged in this task.

**Checkpoint**: The include lists `test/system/ops.cross-worker.test.ts`. That file does not exist yet.

### 3.2 User Story 2 - Retry parked work and cancel an open checkout (Priority: P2) — Access JWT fixture

**Independent Test**: E2E-P4.6-04 and E2E-P4.6-05 in harness H-XW.

- [X] T002 [US2] Teach `mintHxwVendorAccessJwt` in `abo/test/system/hxw-access-fixture.ts` to set `jti` and accept an issuer override — produces the Access JWT the ops tests mint, FR-001, FR-007, E2E-P4.6-01, E2E-P4.6-04. Depends on nothing. Put `jti` on the payload (a UUID when the caller omits it). Accept an optional `iss` override for the bad-issuer case. Default `iss` stays `https://access.test`. `verifyAccessJwt` ignores the extra `jti` claim, so earlier suites that mint with this helper still verify. Leave `abo/vitest.cross-worker.config.ts` unchanged in this task.

**Checkpoint**: Minted vendor Access JWTs carry `jti`. `abo/test/system/ops.cross-worker.test.ts` does not exist yet.

---

## 4. Tests

**Purpose**: Sequencing step 1 continued. One failing test per E2E id, all in `abo/test/system/ops.cross-worker.test.ts`. There is no eighth E2E id. Shared setup uses the existing H-XW helpers (`setupCrossWorkerHarness`, `opsFetch`, `mintVendorAccessJwt`, `platformCall`, `setClock`, `runScheduled`). E2E-P4.6-04 calls `runDueGrantWork` from `abo/src/work/grant.ts`. E2E-P4.6-05 uses the Paymob stub already bound in the H-XW config. No scenario sleeps more than 2 s (rule V4). Time moves with `setClock`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/ops.cross-worker.test.ts
```

### 4.1 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — tests

**Independent Test**: E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07 in harness H-XW.

- [X] T003 [US1] Add the failing test `E2E-P4.6-01` in `abo/test/system/ops.cross-worker.test.ts` — red test, FR-001, E2E-P4.6-01. Depends on T001 and T002. Create the file and the shared setup. Entry: `opsFetch` → `SELF.fetch` on `OPS_ORIGIN` + `/ops/*` with no `Cf-Access-Jwt-Assertion`, an expired JWT, a wrong `aud`, and a wrong `iss`. Then `platformCall("recordOperatorAction", …)` with no JWT, an expired JWT, and a wrong `aud`. Each ops-host request is HTTP 401 `unauthenticated` and inserts no `operator_action`. Issuer is checked by the same `verifyAccessJwt` call. Each entrypoint call is `rejected` / `unauthenticated` and inserts no `control_audit` row. Advance expiry only with `setClock`. The command fails because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.

- [X] T004 [US1] Add the failing test `E2E-P4.6-02` in `abo/test/system/ops.cross-worker.test.ts` — red test, FR-002, FR-003, FR-004, FR-008, E2E-P4.6-02. Depends on T003 (same file). Entry: `opsFetch` `GET /ops/lookup?q=` with `AIC-…`, then `GET /ops/clinics/:orgId`, then the same session’s `GET /ops/parked`, `/ops/findings`, `/ops/grants`, `/ops/payout-imports`, and `/ops/registries`. The clinic page shows `inspectCoverage` terms and the ABO checkouts and payments, plus events, reversals, grant requests and receipts, operator actions, findings, and alerts. Response header `Abo-Contract-Version` is `1` and the body `contract_version` is `1`. `payout_imports` is `[]`. The command fails because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.

- [X] T005 [US1] Add the failing test `E2E-P4.6-03` in `abo/test/system/ops.cross-worker.test.ts` — red test, FR-002, E2E-P4.6-03. Depends on T004 (same file). Entry: `opsFetch` `GET /ops/lookup?q=` by billing email, `PAY-`, `org_id`, `CK-`, and `GR-`. Each lookup returns the same `org_id` as the `AIC-…` lookup. The command fails because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.

- [X] T006 [US1] Add the failing test `E2E-P4.6-07` in `abo/test/system/ops.cross-worker.test.ts` — red test, FR-003, E2E-P4.6-07. Depends on T005 (same file). Entry: `opsFetch` `GET /ops/clinics/:orgId` relay to `PLATFORM.inspectCoverage`, then `platformCall("inspectCoverage")` with no `access_jwt`. The relay sends the operator JWT as `access_jwt`. The frozen call returns `ok` and `detail` JSON `{ terms, grants, reservations }`. The result does not echo `email`. `control_audit` count is unchanged and no other actor-email row is inserted. A missing Access JWT is `rejected` / `unauthenticated` and still writes nothing. The clinic page shows those terms, grants, and reservations. The command fails because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.

**Checkpoint**: E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07 exist and fail.

### 4.2 User Story 2 - Retry parked work and cancel an open checkout (Priority: P2) — tests

**Independent Test**: E2E-P4.6-04 and E2E-P4.6-05 in harness H-XW.

- [X] T007 [US2] Add the failing test `E2E-P4.6-04` in `abo/test/system/ops.cross-worker.test.ts` — red test, FR-005, FR-007, E2E-P4.6-04. Depends on T006 (same file). Entry: `opsFetch` `GET /ops/parked`, then `POST /ops/parked/:workId/retry`, then `runDueGrantWork`. `platformCall("recordOperatorAction")` again with the same `action_id`. The harness inserts one parked `grant` work row. Retry moves it to `open`. The retry route does not apply the grant. After `runDueGrantWork` the grant is `applied`. One `operator_action` row stores `actor_email` and `access_jti`. One `control_audit` row stores that email as `actor` and `operator_id`, `action` `Retry parked work`, `target` the `action_id`, and `assertion_sha256` null. The repeated `action_id` is `ok` and does not insert a second row. The command fails because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.

- [X] T008 [US2] Add the failing test `E2E-P4.6-05` in `abo/test/system/ops.cross-worker.test.ts` — red test, FR-006, FR-007, E2E-P4.6-05. Depends on T007 (same file). Entry: `opsFetch` `POST /ops/checkouts/:checkoutId/cancel` on an open checkout opened through the existing clinic checkout API, then the existing sweep for a later payment. `platformCall("recordOperatorAction")` again with the same `action_id`. The checkout becomes `cancelled`. The later payment becomes `paid_late`. `operator_action` stores the actor email and `access_jti`. `control_audit` stores the Access email. The repeated `action_id` inserts no second row. The cancel route’s only platform method is `recordOperatorAction`. Leave `abo/src/work/sweep.ts` and `abo/src/work/runner.ts` unchanged. The command fails because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.

**Checkpoint**: E2E-P4.6-04 and E2E-P4.6-05 exist and fail. E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07 still fail.

### 4.3 User Story 3 - Reload the console when the contract version is stale (Priority: P3) — tests

**Independent Test**: E2E-P4.6-06 in harness H-XW. Earlier suites stay green, and E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07 still pass.

- [X] T009 [US3] Add the failing test `E2E-P4.6-06` in `abo/test/system/ops.cross-worker.test.ts` — red test, FR-008, E2E-P4.6-06. Depends on T008 (same file). Entry: `opsFetch` `POST /ops/checkouts/:checkoutId/cancel` with a stale `Abo-Contract-Version`, and with the header missing. Both responses are HTTP 400 `contract_version_unsupported` with `reload: true`, before authentication and before any write. The checkout stays `open`. No `operator_action` row is inserted. The command fails because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.

**Checkpoint**: E2E-P4.6-06 exists and fails. E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07 still fail.

---

## 5. Implementation

**Purpose**: Sequencing step 2. Starts after T003–T009 exist and those E2E tests fail. Freeze `recordOperatorAction` before `abo/src/ops/index.ts` calls it (rule S7). The migration finishes before that module inserts `operator_action`. `worker.ts` delegates only after the module exists. Within a subphase the tasks run in id order.

### 5.1 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — recordOperatorAction

**Independent Test**: E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07 in harness H-XW.

- [X] T010 [US1] Add class-H `recordOperatorAction` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts` — produces the frozen method, FR-001, FR-007, E2E-P4.6-01, E2E-P4.6-04, E2E-P4.6-05. Depends on T009. Add `recordOperatorAction: "H"` to `METHOD_CLASS`. That adds one method row. The P3.1 rows stay. Implement the method as `contracts/record-operator-action.md` already specifies. Use the existing `verifyHpAccess` and `writeEntrypointAudit`. Leave `inspectCoverage` unchanged. Leave `abo/src/ops/index.ts` uncreated in this task. Leave `contracts/record-operator-action.md` unchanged.

**Checkpoint**: E2E-P4.6-01’s entrypoint rejection, and the `control_audit` rows in E2E-P4.6-04 and E2E-P4.6-05, have a frozen method. The ops tests still fail until the ABO module exists.

### 5.2 User Story 2 - Retry parked work and cancel an open checkout (Priority: P2) — operator_action migration

**Independent Test**: E2E-P4.6-04 and E2E-P4.6-05 in harness H-XW.

- [X] T011 [US2] Add `abo/migrations/0006_operator_action.sql` — produces append-only `operator_action`, FR-007, E2E-P4.6-04, E2E-P4.6-05. Depends on T010. Columns, the append-only trigger, and constraints are those already written in `data-model.md` for the FR-007 fields `action_id`, `actor_email`, `access_jti`, `action`, `subject`, `params_sha256`, `assertion_sha256`, and `result`. This unit adds no platform migration and does not write PostgreSQL. Leave `data-model.md` unchanged. Leave `abo/src/ops/index.ts` uncreated in this task. The harness applies this file before the ops tests.

**Checkpoint**: E2E-P4.6-04 and E2E-P4.6-05 can store `operator_action`. The ops tests still fail until the console module exists.

### 5.3 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — ops console module

**Independent Test**: E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07 in harness H-XW.

- [X] T012 [US1] Create `abo/src/ops/index.ts` — produces lookup, the clinic page, the global views, retry, and cancel, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, E2E-P4.6-04, E2E-P4.6-05, E2E-P4.6-07. Depends on T010 and T011. Every route below is reached from the test layout. The Access JWT is the `Cf-Access-Jwt-Assertion` header. After the version gate, a missing header, a token `verifyAccessJwt` rejects, or a verified payload whose `jti` is not a non-empty string is HTTP 401 `{ code: "unauthenticated", message: "unauthenticated", contract_version }` and writes nothing. `nowSeconds` comes from the ABO clock. Certs are `{ issuer: "https://" + ACCESS_TEAM_DOMAIN, keys }` from `GET https://{ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`. The checker is `verifyAccessJwt` with `aud` `ACCESS_AUD`. Success responses use the existing clinic JSON helper: `contract_version` in the body and `Abo-Contract-Version` on the response. Current console version is 1. `GET /ops/lookup?q=` returns one clinic: `AIC-…` matches `subscriptionRef(org_id)` over distinct `org_id` values in `billing_contact`, `checkout`, and `coverage_view`; `org_id` matches that id; billing email matches `billing_contact.email` on the highest `version` for that org; `CK-` matches `checkout.reference`; `PAY-` matches `payment.reference`; `GR-` matches `humanRef("GR", grant_request.grant_id)`. The body is `{ contract_version, org_id }`. `GET /ops/clinics/:orgId` calls `PLATFORM.inspectCoverage({ contract_version, access_jwt, org_id })` and shows `detail` JSON `terms`, `grants`, and `reservations`. It does not add a suspension field and does not call `suspend`. It also shows that org’s checkouts with `checkout_event`, payments with `classification` and `disposition`, reversals, grant requests with `grant_outcome` and `receipt`, `operator_action` rows whose `subject` is that `org_id` or a `checkout_id` / `work_id` of that org, `finding` rows for that org, and `alert` rows with `active = 1` whose `alert_key` contains that `org_id` or one of its checkout or payment ids. `GET /ops/parked` lists `work` rows with `state = 'parked'`. `GET /ops/findings` lists every `finding` row. `GET /ops/grants` calls `listGrants({ contract_version })` once and groups that array by `source_kind` and by `operator_credential_id`. `GET /ops/payout-imports` returns `{ contract_version, payout_imports: [] }` and does not create or query `payout_import`. `GET /ops/registries` calls `listIssuerKeys`, `listServiceKeys`, and `listOperatorCredentials`, each with `contract_version` only, and returns the three `detail` arrays. `POST /ops/parked/:workId/retry` requires `kind = 'grant'` and `state = 'parked'`, sets `state = 'open'`, `lease_until` null, `last_error` null, and `next_attempt_at` null, then inserts `operator_action` (`action` `Retry parked work`, `subject` the `work_id`, `result` `open`, `assertion_sha256` null, `params_sha256` the hex SHA-256 of `canonicalize({ action, subject })`), then calls `PLATFORM.recordOperatorAction` with `access_jwt` and `action`, `subject`, and `action_id` copied from that row. The route does not apply the grant. `POST /ops/checkouts/:checkoutId/cancel` requires `checkout_status.state` `open`, sets it to `cancelled`, sets `last_event_at` from the ABO clock, inserts `checkout_event` (`kind` `cancelled`, `source` `operator`, `ref` the `action_id`, `actor` the email), does not update `checkout`, then does the same `operator_action` insert (`action` `Cancel an open checkout`, `subject` the `checkout_id`, `result` `cancelled`) and the same `recordOperatorAction` call. That call is this route’s only platform call. `actor_email` is the verified `email` claim. `access_jti` is the verified payload `jti`. The `operator_action` insert and its `fact_log` row are one D1 batch, and that batch commits before `recordOperatorAction`. Leave `abo/src/worker.ts`, `abo/src/work/grant.ts`, `abo/src/work/sweep.ts`, and `abo/src/work/runner.ts` unchanged in this task.

**Checkpoint**: E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, E2E-P4.6-04, E2E-P4.6-05, and E2E-P4.6-07 have their console module. E2E-P4.6-06 still depends on the version-gate change in `worker.ts`.

### 5.4 User Story 3 - Reload the console when the contract version is stale (Priority: P3) — version gate and ops dispatch

**Independent Test**: E2E-P4.6-06 in harness H-XW. Earlier suites stay green, and E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07 still pass.

- [X] T013 [US3] Delegate `/ops/*` from `abo/src/worker.ts` after the console version gate — produces ops-host dispatch and `reload: true`, FR-001, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, E2E-P4.6-01, E2E-P4.6-06. Depends on T012. `Env` gains `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, and `PLATFORM` methods `inspectCoverage`, `listGrants`, `listIssuerKeys`, `listServiceKeys`, `listOperatorCredentials`, and `recordOperatorAction`. `handleOps` still calls `checkContractVersion(request, "aboConsole")` before the ops module. On failure it returns that gate body with `reload: true` added, status 400, and the existing `Abo-Contract-Version` header. On success it calls `handleOps` from `abo/src/ops/index.ts`. Leave `abo/src/clinic-api/version.ts` unchanged. Leave `abo/src/ops/index.ts`’s route behavior unchanged in this task.

**Checkpoint**: E2E-P4.6-06 is refused at the version gate, and E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07 reach the ops module only after that gate.

---

## 6. Verification

**Purpose**: Sequencing step 3, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command.

### 6.1 Unit harness

**Independent Test**: E2E-P4.6-06 in harness H-XW. Earlier suites stay green, and E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07 still pass.

- [X] T014 [US3] Run `node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/ops.cross-worker.test.ts` from `abo/` until E2E-P4.6-01 through E2E-P4.6-07 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, E2E-P4.6-04, E2E-P4.6-05, E2E-P4.6-06, E2E-P4.6-07. Depends on T010, T011, T012, and T013 (and therefore on T001–T009). This task may edit only files under `abo/test/`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/ops.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.6-01 through E2E-P4.6-07 pass.

---

## 7. Documentation

**Purpose**: After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 7.1 Quickstart

- [X] T015 [US3] Create `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, E2E-P4.6-04, E2E-P4.6-05, E2E-P4.6-06, E2E-P4.6-07. Depends on T014. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps; the harness observes every scenario.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/ops.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.6-01 | `opsFetch` → `worker.ts` `handleOps` → `ops/index.ts` `verifyAccessJwt`; `platformCall` → `VendorEntrypoint.recordOperatorAction` → `verifyHpAccess` |
| E2E-P4.6-02 | `opsFetch` → `ops/index.ts` lookup and clinic page → `PLATFORM.inspectCoverage`; same session → parked, findings, `PLATFORM.listGrants`, payout imports, `PLATFORM.listIssuerKeys` / `listServiceKeys` / `listOperatorCredentials` |
| E2E-P4.6-03 | `opsFetch` → `ops/index.ts` lookup |
| E2E-P4.6-04 | `opsFetch` → `GET /ops/parked` → `POST` retry → `operator_action` → `PLATFORM.recordOperatorAction` → `work/grant.ts` `runDueGrantWork` |
| E2E-P4.6-05 | `opsFetch` → cancel → `operator_action` → `PLATFORM.recordOperatorAction`; later `worker.ts` `scheduled` → `work/sweep.ts` → `work/runner.ts` `paid_late` |
| E2E-P4.6-06 | `opsFetch` → `worker.ts` version gate (`reload: true`); `ops/index.ts` is not called |
| E2E-P4.6-07 | `opsFetch` → `ops/index.ts` → `PLATFORM.inspectCoverage`; `platformCall("inspectCoverage")` with no JWT |

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (Phase 3)**: T001 writes `abo/vitest.cross-worker.config.ts`. T002 writes `abo/test/system/hxw-access-fixture.ts`. Both finish before T003 creates `abo/test/system/ops.cross-worker.test.ts`.
- **Tests (Phase 4)**: T003 through T009 stay in id order in `abo/test/system/ops.cross-worker.test.ts`. User Story 1 tests are T003–T006. User Story 2 tests are T007–T008. User Story 3’s test is T009. They fail because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.
- **Implementation (Phase 5)**: Starts after T009. `recordOperatorAction` (T010) is frozen before the console module calls it. The migration (T011) finishes before that module inserts `operator_action`. The console module (T012) finishes before `worker.ts` (T013) delegates to it.
- **Verification (Phase 6)**: Depends on T010, T011, T012, and T013. Runs only the command in §6.1.
- **Documentation (Phase 7)**: Depends on T014 being green.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: The vitest include is T001, before the tests. Tests T003, T004, T005, and T006. Implementation T010 freezes `recordOperatorAction` for E2E-P4.6-01’s entrypoint rejection, and T012 serves lookup, the clinic page, the global views, and the `inspectCoverage` relay. E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07.
- **User Story 2 (P2)**: The Access JWT fixture is T002, before the tests. Tests T007 and T008 after T006, in that id order, in the same ops file. The migration is T011. Retry and cancel are T012, after T010 and T011. E2E-P4.6-04 and E2E-P4.6-05.
- **User Story 3 (P3)**: Test T009 after T008. The console version gate adds `reload: true` and dispatches `/ops/*` in T013, after T012. E2E-P4.6-06, with E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07 still passing once T014 is green.

### 8.3 Within Each Phase

- T001 writes only `abo/vitest.cross-worker.config.ts`. T002 writes only `abo/test/system/hxw-access-fixture.ts`. T003 creates `abo/test/system/ops.cross-worker.test.ts` after both.
- T003 through T009 all write `abo/test/system/ops.cross-worker.test.ts`, in that id order.
- T010 writes only `ai-platform/src/vendor/entrypoint.ts` after T009, and does not create `abo/src/ops/index.ts`.
- T011 writes only `abo/migrations/0006_operator_action.sql` after T010, and does not create `abo/src/ops/index.ts`.
- T012 writes only `abo/src/ops/index.ts` after T010 and T011, and does not write `abo/src/worker.ts`.
- T013 writes only `abo/src/worker.ts` after T012, and does not write `abo/src/clinic-api/version.ts`.
- T014 runs after T013 and may edit only `abo/test/`.
- T015 writes only `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/quickstart.md` after T014 is green.

---

## 9. Implementation Waves

### 9.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — vitest include` — paths: `abo/vitest.cross-worker.config.ts`
- T002 [US2] — subphase: `### 3.2 User Story 2 - Retry parked work and cancel an open checkout (Priority: P2) — Access JWT fixture` — paths: `abo/test/system/hxw-access-fixture.ts`

### 9.2 Wave 2

- T003–T006 [US1] — subphase: `### 4.1 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — tests` — paths: `abo/test/system/ops.cross-worker.test.ts`

### 9.3 Wave 3

- T007–T008 [US2] — subphase: `### 4.2 User Story 2 - Retry parked work and cancel an open checkout (Priority: P2) — tests` — paths: `abo/test/system/ops.cross-worker.test.ts`

### 9.4 Wave 4

- T009 [US3] — subphase: `### 4.3 User Story 3 - Reload the console when the contract version is stale (Priority: P3) — tests` — paths: `abo/test/system/ops.cross-worker.test.ts`

### 9.5 Wave 5

- T010 [US1] — subphase: `### 5.1 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — recordOperatorAction` — paths: `ai-platform/src/vendor/entrypoint.ts`

### 9.6 Wave 6

- T011 [US2] — subphase: `### 5.2 User Story 2 - Retry parked work and cancel an open checkout (Priority: P2) — operator_action migration` — paths: `abo/migrations/0006_operator_action.sql`

### 9.7 Wave 7

- T012 [US1] — subphase: `### 5.3 User Story 1 - Open the ops console and look up a clinic (Priority: P1) — ops console module` — paths: `abo/src/ops/index.ts`

### 9.8 Wave 8

- T013 [US3] — subphase: `### 5.4 User Story 3 - Reload the console when the contract version is stale (Priority: P3) — version gate and ops dispatch` — paths: `abo/src/worker.ts`

### 9.9 Wave 9

- T014 [US3] — subphase: `### 6.1 Unit harness` — paths: `abo/test/`

### 9.10 Wave 10

- T015 [US3] — subphase: `### 7.1 Quickstart` — paths: `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/quickstart.md`
