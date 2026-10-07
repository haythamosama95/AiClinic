# Tasks: Console relays: platform configuration, registries and bootstrap

**Input**: Design documents from `specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.7 (none; that unit row states no Outputs / freezes line) and P3.10 (none; that unit row states no Outputs / freezes line). Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is not a task: Spikes is none, so the plan phase did not write it. `data-model.md` is not a task: this unit defines no entities. `contracts/` is not a task: Freezes has no wire shape. `quickstart.md` is written in Documentation after verification.

**Organization**: Two user stories, as the spec partitions them (`[US1]`, `[US2]`). Tests are one task per E2E id, written to fail before the relays exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 18. Size M is 20–32 (rule S3). The count is the vitest include (1), one task per E2E id (7), Sequencing step 2 on `abo/src/ops/index.ts` (1), Sequencing steps 3–9 as one route group each in that same file (7), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §6.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/src/worker.ts` — consumed and not modified. `VendorEntrypoint` stays unchanged. `ai-platform/scripts/bootstrap-routing-policy.sh` stays until P7.1
- **ABO**: `abo/` — the Files paths in `plan.md`. No change to `abo/src/worker.ts`. `handleOps` there already delegates `/ops/*`
- **Shared package**: `packages/vendor-contracts/` — consumed (`createSoftwareAuthenticator`, `createAboGrantSigner`, `createIssuer`) and not modified
- **Spec Kit artifacts**: `specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/`
- No new table and no migration. `operator_action` already exists. Leave `abo/test/system/harness.ts` unchanged. `opsFetch` stays there. No new worker, hostname, or route family. These relays do not call `recordOperatorAction`. No test-only secret setter

---

## 3. Setup

**Purpose**: Sequencing step 1, before the failing tests. The vitest include is the scaffold those tests need. The `abo/` Worker already exists.

### 3.1 User Story 1 - Registries and bootstrap (Priority: P1) — vitest include

**Independent Test**: E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 in harness H-XW.

- [X] T001 [US1] Add the configuration-relays test include in `abo/vitest.cross-worker.config.ts` — produces the H-XW include for this unit, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.9-01, E2E-P4.9-02, E2E-P4.9-03, E2E-P4.9-04, E2E-P4.9-05, E2E-P4.9-06, E2E-P4.9-07. Depends on nothing. Add `test/system/configuration-relays.cross-worker.test.ts` to the H-XW `include` list. The unit command still names only that file. Leave `abo/test/system/configuration-relays.cross-worker.test.ts` uncreated in this task. Leave `abo/src/ops/index.ts` unchanged.

**Checkpoint**: The include lists `test/system/configuration-relays.cross-worker.test.ts`. That file does not exist yet.

---

## 4. Tests

**Purpose**: Sequencing step 1 continued. One failing test per E2E id, all in `abo/test/system/configuration-relays.cross-worker.test.ts`. Titles are prefixed with the E2E id. Harness H-XW runs the real platform worker from source. Entry is `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`. AI-token, routing, and kill-switch outcomes are `POST /v1/requests` on the real platform worker (`PLATFORM_HTTP`). No scenario sleeps (rule V4). Credential activation and the config-cache TTL advance with `setClock`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/configuration-relays.cross-worker.test.ts
```

### 4.1 User Story 1 - Registries and bootstrap (Priority: P1) — tests

**Independent Test**: E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 in harness H-XW.

- [X] T002 [US1] Add the failing test `E2E-P4.9-01` in `abo/test/system/configuration-relays.cross-worker.test.ts` — red test, FR-001, FR-002, FR-011, E2E-P4.9-01. Depends on T001. Create the file and the shared setup. Use `createSoftwareAuthenticator` from `vendor-contracts/testkit`. The first `opsFetch` `POST /ops/operator-credentials` sends `attest()` and no approving assertion → `handleOps` → `PLATFORM.registerOperatorCredential`. The first call raises AL-13 bootstrap: a `platform_alert` row whose `alert_key` is `AL-13:` ‖ credential id ‖ `:bootstrap` (the key ends in `:bootstrap` and the code is `AL-13`). `setClock` then moves the platform test clock 24 hours so that credential is active. The second `opsFetch` sends a new attestation plus `assert()` from the first credential → the same method. The new `operator_credential` row is `pending` and `activates_at` is 24 hours ahead. The same session `opsFetch` revoke → `PLATFORM.revokeOperatorCredential` and the revoke returns the platform `ok`. One `operator_action` per call, actor the Access email. The harness does not sleep. The command fails because those routes are absent from `abo/src/ops/index.ts`.

- [X] T003 [US1] Add the failing test `E2E-P4.9-03` in `abo/test/system/configuration-relays.cross-worker.test.ts` — red test, FR-003, FR-011, E2E-P4.9-03. Depends on T002 (same file). `opsFetch` `POST /ops/issuer-keys` registers the drill `kid` with `createIssuer` → `PLATFORM.registerIssuerKey`. A token is `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker and is accepted. `opsFetch` revoke → `PLATFORM.revokeIssuerKey`. `setClock` advances the platform test clock by the harness `CONFIG_CACHE_TTL_MS` (`100`, within ≤ 30 s). The same request again is rejected. The same session `opsFetch` retire on a different `kid` from the drill `kid` → `PLATFORM.retireIssuerKey`. `operator_action` records register, revoke, and retire. The harness does not sleep. The command fails because those routes are absent from `abo/src/ops/index.ts`.

- [X] T004 [US1] Add the failing test `E2E-P4.9-04` in `abo/test/system/configuration-relays.cross-worker.test.ts` — red test, FR-004, FR-011, E2E-P4.9-04. Depends on T003 (same file). `opsFetch` `POST /ops/service-keys` → `PLATFORM.registerServiceKey`. The key pair is `createAboGrantSigner()`. There is no new binding and no route that sets a secret. The switch reuses the way `runScheduled` already calls `abo/src/worker.ts`: `fetch` and `scheduled` receive the harness env with `ABO_GRANT_KEY` set to the JSON of the key just registered (`kid`, `pkcs8`, `public_key`). Before each of those starts, the test deletes the `signing_key_gate` row so `fetch` runs `maybeRefreshSigningKeyCheck`. The paid grant is the existing minute cron `* * * * *` on that env, which runs `runDueGrantWork`, and that grant is accepted after the switch. The old `kid` is the harness `ABO_GRANT_KEY` kid. `opsFetch` revoke of that previous harness kid → `PLATFORM.revokeServiceKey`. A further `fetch` with the new key leaves the ABO `alert` row for AL-23 inactive. `operator_action` records register and revoke. The command fails because those routes are absent from `abo/src/ops/index.ts`.

**Checkpoint**: E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 exist and fail.

### 4.2 User Story 2 - Configuration relays and support lookup (Priority: P2) — tests

**Independent Test**: E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 in harness H-XW. Earlier suites stay green, and E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 still pass.

- [X] T005 [US2] Add the failing test `E2E-P4.9-02` in `abo/test/system/configuration-relays.cross-worker.test.ts` — red test, FR-005, FR-006, FR-011, E2E-P4.9-02. Depends on T004 (same file). `opsFetch` `POST /ops/plan-versions` → `PLATFORM.publishPlanVersion`. The paid grant on that version is the existing `runDueGrantWork` / `PLATFORM.grant` path, and that grant is accepted. The same session `opsFetch` `POST /ops/ceiling-policy` → `PLATFORM.setCeilingPolicy`, and `opsFetch` `POST /ops/plan-versions/retire` → `PLATFORM.retirePlanVersion`. The named assertion is the accepted paid grant. `operator_action` records publish, ceiling, and retire. Inputs are fixture data the platform methods already accept. The command fails because those routes are absent from `abo/src/ops/index.ts`.

- [X] T006 [US2] Add the failing test `E2E-P4.9-05` in `abo/test/system/configuration-relays.cross-worker.test.ts` — red test, FR-008, FR-009, FR-011, E2E-P4.9-05. Depends on T005 (same file). `opsFetch` publish → `PLATFORM.publishRoutingPolicy` with a document whose target `provider_id` is `fake` (the same shape as `fakePolicyDocument` in `abo/test/system/grant.cross-worker.test.ts`). `publishRoutingPolicy` inserts `published`, which is not served. `opsFetch` canary → `PLATFORM.canaryRoutingPolicy` for the fixture installation. `PLATFORM_HTTP` `POST /v1/requests` for that installation is routed to `provider_id` `fake`. Then `opsFetch` promote and `opsFetch` rollback. `operator_action` records publish, canary, promote, and rollback. That publish is the console seed that replaces `ai-platform/scripts/bootstrap-routing-policy.sh`. The script file stays. The command fails because those routes are absent from `abo/src/ops/index.ts`.

- [X] T007 [US2] Add the failing test `E2E-P4.9-06` in `abo/test/system/configuration-relays.cross-worker.test.ts` — red test, FR-007, FR-009, FR-011, E2E-P4.9-06. Depends on T006 (same file). `opsFetch` `POST /ops/kill-switches` → `PLATFORM.armKillSwitch` with `scope` `capability` and `target` `clinic.visit_summary`. The refusal is `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker. The capability answers `capability_disabled`. AL-19 is a `platform_alert` row. The same session then calls the six class-H routes: activate cohort, promote cohort, deprecate capability, retire capability, begin token-contract rotation, and retire token contract. Bodies are fixture arguments those methods already accept. The named assertions stay `capability_disabled` and AL-19. Each later call writes `operator_action`. The command fails because those routes are absent from `abo/src/ops/index.ts`.

- [X] T008 [US2] Add the failing test `E2E-P4.9-07` in `abo/test/system/configuration-relays.cross-worker.test.ts` — red test, FR-010, FR-011, E2E-P4.9-07. Depends on T007 (same file). `opsFetch` `GET /ops/support-lookup?reference=` looks up a request `reference` from a prior platform request → `handleOps` → `PLATFORM.supportLookup`. The response includes the envelope. `operator_action.actor_email` is the Access email. `supportLookup` is not modified. The command fails because that route is absent from `abo/src/ops/index.ts`.

**Checkpoint**: E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 exist and fail. E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 still fail.

---

## 5. Implementation

**Purpose**: Sequencing steps 2–9. Starts after T002–T008 exist and those E2E tests fail. Every new route runs the existing `verifyOpsAccess` first, then the shared forward from T009. These routes do not use the ABO-side HP verifier and do not call `recordOperatorAction`. The platform writes `control_audit` on the methods that already write it. This unit does not add that write to `supportLookup`. Method inputs are the body fields those `VendorEntrypoint` methods already read. The relay adds `access_jwt` and, on HP, the assertion fields. It does not invent defaults. No new refusal code. Leave `abo/src/worker.ts` unchanged. Within a subphase the tasks run in id order.

### 5.1 User Story 1 - Registries and bootstrap (Priority: P1) — shared forward

**Independent Test**: E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 in harness H-XW.

- [X] T009 [US1] Extend `PLATFORM` on `OpsEnv` and add the shared forward in `abo/src/ops/index.ts` — produces the method types and the forward that writes `operator_action` and returns the platform result, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.9-01, E2E-P4.9-02, E2E-P4.9-03, E2E-P4.9-04, E2E-P4.9-05, E2E-P4.9-06, E2E-P4.9-07. Depends on T008. `PLATFORM` gains `registerOperatorCredential`, `revokeOperatorCredential`, `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`, `registerServiceKey`, `revokeServiceKey`, `publishPlanVersion`, `retirePlanVersion`, `setCeilingPolicy`, `publishRoutingPolicy`, `canaryRoutingPolicy`, `promoteRoutingPolicy`, `rollbackRoutingPolicy`, `armKillSwitch`, `activateCohort`, `promoteCohort`, `deprecateCapability`, `retireCapability`, `beginTokenContractRotation`, `retireTokenContract`, and `supportLookup`. Do not add paid `grant`; the existing grant path already calls it. The verified Access JWT is the `access_jwt` forwarded to the platform, with `contract_version` from `CHANNEL_VERSIONS.vendorEntrypoint`. The body carries `action_id`. The forward inserts one `operator_action` through the existing `insertRelayOperatorAction`, with that id, the Access email as `actor_email`, and the platform `result`. A second insert of the same `action_id` does not run. `action` is the platform method name. `subject` is the credential id, `kid`, `(plan_id, version)`, or request reference in that call. HP bodies also carry `operation`, `assertion`, and `signer_credential_id`. Bootstrap `registerOperatorCredential` omits those three, and the forward still calls the platform method. The console response returns the platform result, including `code` and `detail` when present. Add no route in this task.

**Checkpoint**: `OpsEnv` lists those methods and the shared forward exists. E2E-P4.9-01 through E2E-P4.9-07 still fail.

### 5.2 User Story 1 - Registries and bootstrap (Priority: P1) — operator credentials

**Independent Test**: E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 in harness H-XW.

- [X] T010 [US1] Add operator-credential register and revoke in `abo/src/ops/index.ts` — produces the bootstrap and second-credential relays, FR-001, FR-002, FR-011, E2E-P4.9-01. Depends on T009. `POST /ops/operator-credentials` calls `PLATFORM.registerOperatorCredential`. Bootstrap omits `operation`, `assertion`, and `signer_credential_id`. The handler still calls the platform method. The body forwards `credential_id` and the WebAuthn attestation object. `POST /ops/operator-credentials/:credentialId/revoke` calls `PLATFORM.revokeOperatorCredential` and forwards the HP assertion fields. Both use the shared forward from T009. Leave issuer keys, service keys, plan versions, ceiling policy, routing, kill switches, cohort, capability lifecycle, token contract, and support lookup for later tasks.

**Checkpoint**: E2E-P4.9-01 is covered by these routes. E2E-P4.9-02 through E2E-P4.9-07 still fail.

### 5.3 User Story 2 - Configuration relays and support lookup (Priority: P2) — plan version and ceiling

**Independent Test**: E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 in harness H-XW. Earlier suites stay green, and E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 still pass.

- [ ] T011 [US2] Add plan publish, ceiling policy, and plan retire in `abo/src/ops/index.ts` — produces those HP relays, FR-005, FR-006, FR-011, E2E-P4.9-02. Depends on T010. `POST /ops/plan-versions` calls `PLATFORM.publishPlanVersion`. `POST /ops/ceiling-policy` calls `PLATFORM.setCeilingPolicy`. `POST /ops/plan-versions/retire` calls `PLATFORM.retirePlanVersion`. Each forwards the HP assertion fields and the body fields that method already reads: for publish, `plan_id`, `version`, `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, and `max_allowance_per_month`; for retire, `plan_id` and `version`; for ceiling, `per_grant_max_days`, `per_grant_max_allowance_months`, `window_days`, `window_max_days`, `window_max_allowance_months`, `max_paid_grace_days`, and `paid_cap_rule`. The paid grant stays on the existing grant path. Do not add a grant route. Leave the credential routes from T010 unchanged.

**Checkpoint**: E2E-P4.9-02 is covered by these routes. E2E-P4.9-01 stays covered by T010. E2E-P4.9-03 through E2E-P4.9-07 still fail.

### 5.4 User Story 1 - Registries and bootstrap (Priority: P1) — issuer keys

**Independent Test**: E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 in harness H-XW.

- [ ] T012 [US1] Add issuer-key register, revoke, and retire in `abo/src/ops/index.ts` — produces those HP relays, FR-003, FR-011, E2E-P4.9-03. Depends on T011. `POST /ops/issuer-keys` calls `PLATFORM.registerIssuerKey`. `POST /ops/issuer-keys/:kid/revoke` calls `PLATFORM.revokeIssuerKey`. `POST /ops/issuer-keys/:kid/retire` calls `PLATFORM.retireIssuerKey`. Register forwards `kid`, `public_key`, `not_before`, and `not_after`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key, forwarded as supplied. Revoke and retire forward `kid`. Each forwards the HP assertion fields. Leave the routes from T010 and T011 unchanged.

**Checkpoint**: E2E-P4.9-03 is covered by these routes. E2E-P4.9-01 and E2E-P4.9-02 stay covered. E2E-P4.9-04 through E2E-P4.9-07 still fail.

### 5.5 User Story 1 - Registries and bootstrap (Priority: P1) — service keys

**Independent Test**: E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 in harness H-XW.

- [ ] T013 [US1] Add service-key register and revoke in `abo/src/ops/index.ts` — produces those HP relays, FR-004, FR-011, E2E-P4.9-04. Depends on T012. `POST /ops/service-keys` calls `PLATFORM.registerServiceKey`. `POST /ops/service-keys/:kid/revoke` calls `PLATFORM.revokeServiceKey`. Register forwards `kid`, `public_key`, `not_before`, and `not_after`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key, forwarded as supplied. Revoke forwards `kid`. Each forwards the HP assertion fields. Do not add a route or binding that sets `ABO_GRANT_KEY`. The secret switch stays a harness value on the existing worker `fetch` and `scheduled` handlers. Leave the routes from T010 through T012 unchanged.

**Checkpoint**: E2E-P4.9-04 is covered by these routes. E2E-P4.9-01, E2E-P4.9-02, and E2E-P4.9-03 stay covered. E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 still fail.

### 5.6 User Story 2 - Configuration relays and support lookup (Priority: P2) — routing policy

**Independent Test**: E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 in harness H-XW. Earlier suites stay green, and E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 still pass.

- [ ] T014 [US2] Add routing publish, canary, promote, and rollback in `abo/src/ops/index.ts` — produces those class-H relays, FR-008, FR-011, E2E-P4.9-05. Depends on T013. `POST /ops/routing-policy` calls `PLATFORM.publishRoutingPolicy`. `POST /ops/routing-policy/canary` calls `PLATFORM.canaryRoutingPolicy`. `POST /ops/routing-policy/promote` calls `PLATFORM.promoteRoutingPolicy`. `POST /ops/routing-policy/rollback` calls `PLATFORM.rollbackRoutingPolicy`. Each is class H: forward `access_jwt` and do not forward `operation`, `assertion`, or `signer_credential_id`. Forward the body fields those methods already read, including `document`, `policy_id`, and `installation_ids` when the call carries them. Do not delete or edit `ai-platform/scripts/bootstrap-routing-policy.sh`. Leave the routes from T010 through T013 unchanged.

**Checkpoint**: E2E-P4.9-05 is covered by these routes. E2E-P4.9-01 through E2E-P4.9-04 stay covered. E2E-P4.9-06 and E2E-P4.9-07 still fail.

### 5.7 User Story 2 - Configuration relays and support lookup (Priority: P2) — kill switch and class-H catalogue

**Independent Test**: E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 in harness H-XW. Earlier suites stay green, and E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 still pass.

- [ ] T015 [US2] Add the kill switch and the cohort, capability, and token-contract routes in `abo/src/ops/index.ts` — produces those class-H relays, FR-007, FR-009, FR-011, E2E-P4.9-06. Depends on T014. `POST /ops/kill-switches` calls `PLATFORM.armKillSwitch`. `POST /ops/cohorts/activate` calls `PLATFORM.activateCohort`. `POST /ops/cohorts/promote` calls `PLATFORM.promoteCohort`. `POST /ops/capabilities/deprecate` calls `PLATFORM.deprecateCapability`. `POST /ops/capabilities/retire` calls `PLATFORM.retireCapability`. `POST /ops/token-contracts/begin-rotation` calls `PLATFORM.beginTokenContractRotation`. `POST /ops/token-contracts/retire` calls `PLATFORM.retireTokenContract`. Each is class H: forward `access_jwt` and do not forward the HP assertion fields. Forward `scope` and `target` on the kill switch, and the cohort, capability, and token-contract fields those methods already read. Do not invent defaults. Leave the routes from T010 through T014 unchanged.

**Checkpoint**: E2E-P4.9-06 is covered by these routes. E2E-P4.9-01 through E2E-P4.9-05 stay covered. E2E-P4.9-07 still fails.

### 5.8 User Story 2 - Configuration relays and support lookup (Priority: P2) — support lookup

**Independent Test**: E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 in harness H-XW. Earlier suites stay green, and E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 still pass.

- [ ] T016 [US2] Add support lookup in `abo/src/ops/index.ts` — produces the class-H lookup relay, FR-010, FR-011, E2E-P4.9-07. Depends on T015. `GET /ops/support-lookup` calls `PLATFORM.supportLookup` with the request `reference`. It is class H: forward `access_jwt` and do not forward the HP assertion fields. The relay response includes the platform result. Do not modify `supportLookup` and do not add a `control_audit` write for it. `operator_action` still records the call with the Access email as actor. Leave the routes from T010 through T015 unchanged.

**Checkpoint**: E2E-P4.9-07 is covered by this route. E2E-P4.9-01 through E2E-P4.9-06 stay covered by T010 through T015.

---

## 6. Verification

**Purpose**: After T010 through T016, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command.

### 6.1 Unit harness

**Independent Test**: E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07 in harness H-XW. Earlier suites stay green, and E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04 still pass.

- [ ] T017 [US2] Run `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/configuration-relays.cross-worker.test.ts` from `abo/` until E2E-P4.9-01 through E2E-P4.9-07 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.9-01, E2E-P4.9-02, E2E-P4.9-03, E2E-P4.9-04, E2E-P4.9-05, E2E-P4.9-06, E2E-P4.9-07. Depends on T016 (and therefore on T001–T015). This task may edit only `abo/test/system/configuration-relays.cross-worker.test.ts`. It does not add an E2E id and does not change `abo/src/ops/index.ts`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/configuration-relays.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.9-01 through E2E-P4.9-07 pass.

---

## 7. Documentation

**Purpose**: After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 7.1 Quickstart

- [ ] T018 [US2] Create `specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, E2E-P4.9-01, E2E-P4.9-02, E2E-P4.9-03, E2E-P4.9-04, E2E-P4.9-05, E2E-P4.9-06, E2E-P4.9-07. Depends on T017. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps; the harness observes every scenario.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/configuration-relays.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.9-01 | `opsFetch` `POST /ops/operator-credentials` with attestation and no assertion → `handleOps` → `PLATFORM.registerOperatorCredential`. `setClock` +24 h. Second `opsFetch` with a new attestation and the first credential's assertion → the same method. Then `opsFetch` revoke → `PLATFORM.revokeOperatorCredential`. First call: `platform_alert.alert_key` ends in `:bootstrap` and code is `AL-13`. Second credential row is `pending` with `activates_at` 24 hours ahead. Revoke returns the platform `ok`. One `operator_action` per call, actor the Access email |
| E2E-P4.9-02 | `opsFetch` `POST /ops/plan-versions` → `PLATFORM.publishPlanVersion`. Paid grant on that version is the existing `runDueGrantWork` / `PLATFORM.grant` path. Same session: `opsFetch` `POST /ops/ceiling-policy` → `PLATFORM.setCeilingPolicy`, and `opsFetch` `POST /ops/plan-versions/retire` → `PLATFORM.retirePlanVersion`. The paid grant on the published version is accepted. `operator_action` records publish, ceiling, and retire |
| E2E-P4.9-03 | `opsFetch` `POST /ops/issuer-keys` → `PLATFORM.registerIssuerKey`. Token: `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker. `opsFetch` revoke → `PLATFORM.revokeIssuerKey`. `setClock` by `CONFIG_CACHE_TTL_MS`. The same request again. Same session: `opsFetch` retire on a different `kid` → `PLATFORM.retireIssuerKey`. Token accepted, then rejected after the clock advance. Retire is a different `kid`. `operator_action` records register, revoke, and retire |
| E2E-P4.9-04 | `opsFetch` `POST /ops/service-keys` → `PLATFORM.registerServiceKey`. Worker `fetch` and minute `scheduled` with `ABO_GRANT_KEY` set to that key → `maybeRefreshSigningKeyCheck` and `runDueGrantWork`. `opsFetch` revoke of the previous harness kid → `PLATFORM.revokeServiceKey`. A further `fetch` with the new key. The paid grant is accepted after the switch. After revoke, the further start leaves ABO `alert` for AL-23 inactive. `operator_action` records register and revoke |
| E2E-P4.9-05 | `opsFetch` publish → `PLATFORM.publishRoutingPolicy`. `opsFetch` canary → `PLATFORM.canaryRoutingPolicy`. `PLATFORM_HTTP` `POST /v1/requests`. Then `opsFetch` promote and `opsFetch` rollback. The request is routed to `provider_id` `fake`. `operator_action` records publish, canary, promote, and rollback |
| E2E-P4.9-06 | `opsFetch` `POST /ops/kill-switches` → `PLATFORM.armKillSwitch`. Refusal: `PLATFORM_HTTP` `POST /v1/requests`. Same session: the six class-H routes for cohort, capability lifecycle, and token contract. The capability answers `capability_disabled`. AL-19 is a `platform_alert` row. Each later call writes `operator_action` |
| E2E-P4.9-07 | `opsFetch` `GET /ops/support-lookup?reference=` → `handleOps` → `PLATFORM.supportLookup`. The response includes the envelope. `operator_action.actor_email` is the Access email |

**Checkpoint**: `quickstart.md` names the files, the harness command, and the seven chains.

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (§3)**: No dependencies. Starts immediately.
- **Tests (§4)**: Depend on the vitest include. One failing test per E2E id, User Story 1 then User Story 2: E2E-P4.9-01, E2E-P4.9-03, E2E-P4.9-04, then E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, E2E-P4.9-07. All of them fail before any relay is implemented.
- **Implementation (§5)**: Depends on those failing tests. Sequencing step 2 extends `PLATFORM` on `OpsEnv` and adds the shared forward in `abo/src/ops/index.ts`. Routes then follow Sequencing: operator credentials, plan publish with ceiling policy and plan retire, issuer keys, service keys, routing policy, the kill switch with cohort, capability lifecycle, and token contract, then support lookup.
- **Verification (§6)**: Depends on those routes. The harness is the command in §6.1.
- **Documentation (§7)**: Depends on that harness being green. `quickstart.md` is the only doc task.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: Operator-credential bootstrap, registration, and revocation, issuer-key register, retire, and revoke, and service-key register and revoke. Tested by E2E-P4.9-01, E2E-P4.9-03, and E2E-P4.9-04. The credential routes do not depend on User Story 2. Issuer and service-key routes follow the plan routes only because Sequencing writes them later in the same file.
- **User Story 2 (P2)**: Plan-version publish and retire, ceiling policy, routing policy, kill switch, cohort, capability lifecycle, token contract, and support lookup. Tested by E2E-P4.9-02, E2E-P4.9-05, E2E-P4.9-06, and E2E-P4.9-07. Plan routes follow the credential routes in `abo/src/ops/index.ts`. They do not rewrite those routes. Later User Story 1 key routes follow the plan routes the same way.

### 8.3 Within Each Phase

- T001 writes only `abo/vitest.cross-worker.config.ts`.
- T002 creates `abo/test/system/configuration-relays.cross-worker.test.ts` after T001. T003 through T008 all write that same file, in that id order.
- T009 writes only the `OpsEnv` method list and the shared forward in `abo/src/ops/index.ts` after T008, and does not add routes.
- T010 writes only the operator-credential routes in `abo/src/ops/index.ts` after T009.
- T011 writes only the plan-version and ceiling routes in `abo/src/ops/index.ts` after T010.
- T012 writes only the issuer-key routes in `abo/src/ops/index.ts` after T011.
- T013 writes only the service-key routes in `abo/src/ops/index.ts` after T012.
- T014 writes only the routing-policy routes in `abo/src/ops/index.ts` after T013.
- T015 writes only the kill-switch, cohort, capability, and token-contract routes in `abo/src/ops/index.ts` after T014.
- T016 writes only the support-lookup route in `abo/src/ops/index.ts` after T015.
- T017 runs after T016 and may edit only `abo/test/system/configuration-relays.cross-worker.test.ts`.
- T018 writes only `specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/quickstart.md` after T017 is green.

---

## 9. Implementation Waves

### 9.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Registries and bootstrap (Priority: P1) — vitest include` — paths: `abo/vitest.cross-worker.config.ts`

### 9.2 Wave 2

- T002–T004 [US1] — subphase: `### 4.1 User Story 1 - Registries and bootstrap (Priority: P1) — tests` — paths: `abo/test/system/configuration-relays.cross-worker.test.ts`

### 9.3 Wave 3

- T005–T008 [US2] — subphase: `### 4.2 User Story 2 - Configuration relays and support lookup (Priority: P2) — tests` — paths: `abo/test/system/configuration-relays.cross-worker.test.ts`

### 9.4 Wave 4

- T009 [US1] — subphase: `### 5.1 User Story 1 - Registries and bootstrap (Priority: P1) — shared forward` — paths: `abo/src/ops/index.ts`

### 9.5 Wave 5

- T010 [US1] — subphase: `### 5.2 User Story 1 - Registries and bootstrap (Priority: P1) — operator credentials` — paths: `abo/src/ops/index.ts`

### 9.6 Wave 6

- T011 [US2] — subphase: `### 5.3 User Story 2 - Configuration relays and support lookup (Priority: P2) — plan version and ceiling` — paths: `abo/src/ops/index.ts`

### 9.7 Wave 7

- T012 [US1] — subphase: `### 5.4 User Story 1 - Registries and bootstrap (Priority: P1) — issuer keys` — paths: `abo/src/ops/index.ts`

### 9.8 Wave 8

- T013 [US1] — subphase: `### 5.5 User Story 1 - Registries and bootstrap (Priority: P1) — service keys` — paths: `abo/src/ops/index.ts`

### 9.9 Wave 9

- T014 [US2] — subphase: `### 5.6 User Story 2 - Configuration relays and support lookup (Priority: P2) — routing policy` — paths: `abo/src/ops/index.ts`

### 9.10 Wave 10

- T015 [US2] — subphase: `### 5.7 User Story 2 - Configuration relays and support lookup (Priority: P2) — kill switch and class-H catalogue` — paths: `abo/src/ops/index.ts`

### 9.11 Wave 11

- T016 [US2] — subphase: `### 5.8 User Story 2 - Configuration relays and support lookup (Priority: P2) — support lookup` — paths: `abo/src/ops/index.ts`

### 9.12 Wave 12

- T017 [US2] — subphase: `### 6.1 Unit harness` — paths: `abo/test/system/configuration-relays.cross-worker.test.ts`

### 9.13 Wave 13

- T018 [US2] — subphase: `### 7.1 Quickstart` — paths: `specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/quickstart.md`
