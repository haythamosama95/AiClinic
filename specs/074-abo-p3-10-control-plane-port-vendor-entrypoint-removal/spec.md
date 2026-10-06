# Feature Specification: Control-plane port to `VendorEntrypoint` and removal of `/control/*`

**Feature Branch**: `ai/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.10 — Control-plane port to `VendorEntrypoint` and removal of `/control/*`

## 1. Unit Contract

**Implements** — Read: 04 §1.3 (rows kill switch … token contract, supportLookup, and the "Removed" paragraph); 04 §6.1 rows `src/control/*` (all), support, `worker.ts` (`/control` dispatch, `Env`); 04 §6.3 rows drop_invoicing and the drop clauses of coverage_ledger; 04 §6.4; 04 §6.5; 02 §3.1 ("Removed" paragraph); 02 §1.4 (last paragraph).

- H methods for kill switches, routing policy (publish/canary/promote/rollback), cohort (plan membership from `plan_version`), capability lifecycle, token contract; `supportLookup` by reference, subscription ref and org; AL-19 on kill-switch changes. Delete the `/control/*` dispatch, auth, http, entitle, credit-price, the old plan CRUD, quota-inspect, period-close and invoice code; drop the `invoice`, `credit_price`, `plan` and `entitlement` tables; remove `OPERATOR_BEARER_TOKEN`/`OPERATOR_ID`. Final wrangler: `workers_dev=false`, `preview_urls=false`, crons (`0 5 1 * *` removed), vars. **Completes the harness migration (rule V2 step 4):** `operatorFetch` deleted; `test/e2e/harness/control.ts` and `env.ts` rewritten; suites deleted or rewritten per 04 §6.5; vitest configs without the bearer binding.

**Freezes** — None. The P3.10 unit row has no Outputs / freezes line.

**Consumes** — P3.8: None. The P3.8 unit row has no Outputs / freezes line. P3.9: the HTTP feed contract; `/v1/coverage` response; `feedConsumerHealth`.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Operate configuration and support lookup on `VendorEntrypoint` (Priority: P1)

An operator calls class-H methods on `VendorEntrypoint` for kill switches, routing policy (publish, canary, promote, rollback), cohort, capability lifecycle, and the token contract. Cohort plan membership comes from `plan_version`. `supportLookup` answers by reference, by subscription ref, and by org. A kill-switch change raises AL-19, and the audit actor is the Access email.

**Why this priority**: The later stories in this unit call these methods after `/control/*` is gone. This is the story they depend on.

**Independent Test**: E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, E2E-P3.10-05, and E2E-P3.10-06 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a routing policy, **When** the operator publishes it, then canaries it, then promotes it over `VendorEntrypoint`, **Then** traffic follows the promoted policy. (E2E-P3.10-02, port of SYS suite 4, 04 §1.3 routing-policy row)
2. **Given** a capability, **When** the operator turns the kill switch on over `VendorEntrypoint`, **Then** that capability answers `capability_disabled`, AL-19 is raised, and the audit actor is the Access email. [AL-19] (E2E-P3.10-03, 04 §1.3 kill-switch row, 04 §6.1 row `src/control/audit.ts`)
3. **Given** a capability version, **When** the operator deprecates it or retires it over `VendorEntrypoint`, **Then** discovery reflects that state. (E2E-P3.10-04, 04 §1.3 capability-lifecycle row)
4. **Given** the token contract, **When** the operator rotates it over `VendorEntrypoint`, **Then** version 2 is current. (E2E-P3.10-05, 04 §6.1 token-contract row)
5. **Given** a clinic, **When** `supportLookup` is called with that clinic's subscription ref, **Then** the result is that clinic's requests. **When** `supportLookup` is called by reference, **Then** the envelope is within retention. (E2E-P3.10-06, 04 §1.3 row `supportLookup`, 04 §6.1 row `src/support/index.ts`)

### 2.2 User Story 2 - Remove `/control/*` and boot without the bearer (Priority: P2)

The platform worker no longer dispatches `/control/*`. Every former `/control/*` path answers 404. The worker boots with `OPERATOR_BEARER_TOKEN` absent. `OPERATOR_ID` is removed. The `invoice`, `credit_price`, `plan`, and `entitlement` tables are dropped.

**Why this priority**: Story 1's methods are the replacement. This story removes the HTTP control plane those methods replace.

**Independent Test**: E2E-P3.10-01 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** the worker has no `OPERATOR_BEARER_TOKEN`, **When** it boots, **Then** it boots. **When** any former `/control/*` path is requested, **Then** the response is 404. [FR-91, P-07] (E2E-P3.10-01, 04 §1.3 Removed paragraph, 02 §3.1 Removed paragraph)

### 2.3 User Story 3 - Run retention and rollup without the monthly period close (Priority: P3)

The platform cron list keeps `0 3 * * *` and `0 4 * * *`, removes `0 5 1 * *`, and includes `*/5 * * * *`. `0 3 * * *` runs retention. `0 4 * * *` runs rollup keyed by `term_id`.

**Why this priority**: The schedule is the remaining live entry after the HTTP control plane is gone. It does not change the class-H methods.

**Independent Test**: E2E-P3.10-07 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** the platform wrangler crons, **When** the schedule is read, **Then** `0 5 1 * *` is gone. **When** `0 3 * * *` runs, **Then** retention runs. **When** `0 4 * * *` runs, **Then** rollup runs keyed by `term_id`. (E2E-P3.10-07, 04 §6.4 cron row)

### 2.4 User Story 4 - Finish the harness migration off the bearer (Priority: P4)

`operatorFetch` and `operatorFetchRaw` are deleted. `ai-platform/test/e2e/harness/control.ts` and `ai-platform/test/e2e/harness/env.ts` call `VendorEntrypoint` with test Access JWTs and test passkey assertions, and mint issuer tokens with a test issuer key. Suites in the 04 §6.5 Delete and Rewrite rows are deleted or rewritten. Both vitest configs drop the `OPERATOR_BEARER_TOKEN` binding. The rewritten SYS and e2e catalogue is green, and no bearer token appears in the test config.

**Why this priority**: The catalogue is the proof that Stories 1–3 hold together. It is the last story.

**Independent Test**: E2E-P3.10-08 in harness H-AP and the e2e catalogue. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** the rewritten SYS and e2e catalogue and the vitest configs, **When** that catalogue runs, **Then** it is green, and no bearer token appears anywhere in the test config. (E2E-P3.10-08, 04 §6.5, 06 §3 V2 step 4)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.10-01 | H-AP | `SELF.fetch` on `ai-platform/src/worker.ts` `fetch` for every pathname `isControlRoute` accepts in `ai-platform/src/control/index.ts` (POST, and GET where `isQuotaInspectRoute` is true). Worker boot with `OPERATOR_BEARER_TOKEN` absent from the binding. | Every former `/control/*` path → 404; the worker boots without `OPERATOR_BEARER_TOKEN`. [FR-91, P-07] | FR-007, FR-008 | User Story 2 |
| E2E-P3.10-02 | H-AP | `vendorCall` on `VendorEntrypoint` over the H-AP self service binding (`env.VENDOR` in `ai-platform/test/system/harness.ts`) for routing-policy publish, canary, and promote. Traffic is the port of `ai-platform/test/system/routing-policy-traffic.system.test.ts` (SYS suite 4). | Routing policy publish → canary → promote over the entrypoint; traffic follows (port of SYS suite 4). | FR-001, FR-002 | User Story 1 |
| E2E-P3.10-03 | H-AP | `vendorCall` on `VendorEntrypoint` (`env.VENDOR`) for the kill switch. The `capability_disabled` outcome is observed on the live clinic request path. AL-19 and the audit actor are read from `platform_alert` and `control_audit`. | Kill switch on a capability → `capability_disabled`; AL-19; audit actor = Access email. [AL-19] | FR-001, FR-003 | User Story 1 |
| E2E-P3.10-04 | H-AP | `vendorCall` on `VendorEntrypoint` (`env.VENDOR`) for capability deprecate and retire. Discovery is the existing discovery response. | Capability deprecate/retire over the entrypoint → discovery reflects it. | FR-001, FR-004 | User Story 1 |
| E2E-P3.10-05 | H-AP | `vendorCall` on `VendorEntrypoint` (`env.VENDOR`) for token-contract rotation. | Token-contract rotation over the entrypoint (ver 2 current). | FR-001, FR-005 | User Story 1 |
| E2E-P3.10-06 | H-AP | `vendorCall("supportLookup", …)` on `VendorEntrypoint` (`env.VENDOR`), once by subscription ref and once by reference. | `supportLookup` by subscription ref → that clinic's requests; by reference → envelope within retention. | FR-006 | User Story 1 |
| E2E-P3.10-07 | H-AP | `runScheduled("0 3 * * *")` and `runScheduled("0 4 * * *")` in `ai-platform/test/system/harness.ts`, which call `scheduled` on `ai-platform/src/worker.ts`. The cron list is `ai-platform/wrangler.toml` `[triggers].crons`. | Crons: `0 5 1 * *` gone; `0 3`/`0 4` run retention and rollup keyed by `term_id`. | FR-010, FR-011 | User Story 3 |
| E2E-P3.10-08 | H-AP + e2e catalog | The SYS catalogue under `ai-platform/test/system/` and the e2e catalogue under `ai-platform/test/e2e/`, after the 04 §6.5 Delete and Rewrite rows. Config is `ai-platform/vitest.e2e.config.ts` and `ai-platform/vitest.workers.config.ts`. | The full rewritten SYS and e2e catalogue is green, with no bearer token anywhere in the test config. | FR-009, FR-012 | User Story 4 |

### 2.6 Edge Cases

- Every former `/control/*` path answers 404, including the paths `isControlRoute` matches today: installation suspend, resume, delete, purge, and entitle; capability deprecate and retire; cohort activate and promote; routing-policy publish, canary, promote, and rollback; token-contract begin-rotation and retire; support lookup; quota inspect; kill-switch arm and disarm; plan create, update, and delete; credit-price activate; installation override. (04 §1.3 Removed paragraph, `ai-platform/src/control/index.ts`, E2E-P3.10-01)
- The worker boots when `OPERATOR_BEARER_TOKEN` is absent. [FR-91, P-07] (02 §3.1 Removed paragraph, E2E-P3.10-01)
- A kill switch on a capability answers `capability_disabled`, raises AL-19, and records the audit actor as the Access email. (E2E-P3.10-03, 04 §6.1 row `src/control/audit.ts`)
- `supportLookup` by reference returns the envelope within retention. Lookup is also by subscription reference and by `org_id`. (04 §1.3 row `supportLookup`, 04 §6.1 row `src/support/index.ts`, E2E-P3.10-06)
- Cohort plan membership is taken from `plan_version` instead of `entitlement`. (04 §6.1 row `src/control/cohort.ts`, Implements)
- Routing-policy rollback stays a class-H method, as today. The named traffic scenario is publish, then canary, then promote. (04 §1.3 routing-policy row, Implements, E2E-P3.10-02)
- After token-contract rotation, version 2 is current. (04 §6.1 token-contract row, E2E-P3.10-05)
- `0 5 1 * *` is absent. `0 3 * * *` runs retention and `0 4 * * *` runs rollup keyed by `term_id`. (04 §6.4, E2E-P3.10-07)
- `workers_dev = false` and `preview_urls = false`, so the Access-protected console has no bypass hostname on this worker. (02 §1.4 last paragraph, 04 §6.4)
- The test config contains no bearer token. (04 §6.5 Config row, E2E-P3.10-08)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `VendorEntrypoint` gains class-H methods for kill switches, routing policy (publish, canary, promote, rollback), cohort, capability lifecycle, and the token contract. Input, output, and idempotency stay as today (`src/control/index.ts` handlers for those actions). The logic in `src/control/kill-switch.ts`, `src/control/routing-policy.ts`, `src/control/token-contract.ts`, and `src/control/capability-lifecycle.ts` is kept and exposed as those class-H methods. Cohort plan membership comes from `plan_version` instead of `entitlement`. (04 §1.3 row "Kill switch, routing policy, cohort, capability lifecycle, token contract", 04 §6.1 rows for those files and `src/control/cohort.ts`, Implements, E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, E2E-P3.10-05)
- **FR-002**: Routing policy publish, then canary, then promote, runs over `VendorEntrypoint`. Traffic follows. This is the port of SYS suite 4 (`ai-platform/test/system/routing-policy-traffic.system.test.ts`). (04 §1.3 routing-policy actions, E2E-P3.10-02)
- **FR-003**: A kill switch on a capability answers `capability_disabled`, raises AL-19, and sets the audit actor to the Access email. `src/control/audit.ts` records the actor as the Access email and records `assertion_sha256`. (04 §6.1 row `src/control/audit.ts`, Implements, E2E-P3.10-03)
- **FR-004**: Capability deprecate and retire run over `VendorEntrypoint`. Discovery reflects the resulting state. (04 §1.3 capability-lifecycle actions, E2E-P3.10-04)
- **FR-005**: Token-contract rotation runs over `VendorEntrypoint`. Version 2 is current. `src/control/token-contract.ts` adds `ver = "2"`. (04 §6.1 token-contract row, E2E-P3.10-05)
- **FR-006**: `supportLookup` is class H. Its input includes a request `reference`. Lookup is also by subscription reference and by `org_id`. The lookup is the existing one in `ai-platform/src/support/index.ts`. By subscription ref the result is that clinic's requests. By reference the result is the envelope within retention. (04 §1.3 row `supportLookup`, 04 §6.1 row `src/support/index.ts`, Implements, E2E-P3.10-06)
- **FR-007**: The `/control/*` dispatch is removed from `ai-platform/src/worker.ts` `fetch`. Every former `/control/*` path answers 404. Deleted with that dispatch: `src/control/index.ts`, `src/control/auth.ts` (shared bearer), `src/control/http.ts`, `src/control/entitle.ts` (manual entitle and override), `src/control/credit-price.ts`, the old plan CRUD, quota-inspect HTTP, period-close code, and invoice code. Removed with the routes: `handleEntitle`, `handleOverride`, `handleEnroll`, `handleRotate`, `handleRevokeKey`, `handlePlanCreate`/`Update`/`Delete`, `handleCreditPriceActivate`. (04 §1.3 Removed paragraph, 04 §6.1 rows `src/worker.ts` `/control` dispatch and the `src/control/*` delete rows, Implements, E2E-P3.10-01) [FR-91]
- **FR-008**: The worker boots without `OPERATOR_BEARER_TOKEN`. `Env` drops `OPERATOR_BEARER_TOKEN`. `OPERATOR_ID` is removed. The 02 §3.1 Removed paragraph names that shared bearer (`ai-platform/src/control/auth.ts`, `src/worker.ts`). `src/control/lifecycle.ts` removes enroll, rotate, and revoke-key, and removes `INSTALLATION_KEY_TTL_DAYS`. `handleSuspend`, `handleResume`, and `handleDelete` are the entrypoint methods already on `VendorEntrypoint`; this unit removes their `/control/*` HTTP handlers. `src/control/plan.ts` no longer creates, updates, or deletes plans; `publishPlanVersion` and `retirePlanVersion` remain the HP entrypoint methods. `src/control/quota-inspect.ts` no longer serves the entitlement HTTP read; `inspectCoverage` remains the entrypoint method. `src/control/support-purge.ts` no longer serves HTTP purge; `deleteInstallation` remains the HP entrypoint method. `src/control/types.ts` follows the entrypoint methods. (02 §3.1 Removed paragraph, 04 §6.1 rows `worker.ts` `Env`, `src/control/auth.ts`, `src/control/lifecycle.ts`, `src/control/plan.ts`, `src/control/quota-inspect.ts`, `src/control/support-purge.ts`, `src/control/types.ts`, 04 §6.4 vars row, Implements, E2E-P3.10-01) [P-07, FR-91]
- **FR-009**: This unit drops `invoice`, `credit_price`, `plan`, and `entitlement`. The drop_invoicing content drops `invoice` and `credit_price`. The coverage_ledger drop clauses drop `plan`, `entitlement` (with `20260821130000_entitlement_installation_unique.sql`), and `grace_admission_queue`. 04 §6.3 file names are indicative. This unit creates its own migration files with fresh, increasing timestamps. (04 §6.3 rows drop_invoicing and the drop clauses of coverage_ledger, 06 §2 S7, Implements, E2E-P3.10-08)
- **FR-010**: Final `ai-platform/wrangler.toml` matches 04 §6.4. Crons keep `0 3 * * *` and `0 4 * * *`, remove `0 5 1 * *`, and include `*/5 * * * *`. The DO class line stays unchanged. Vars remove `OPERATOR_ID` and add `ISSUER_ID`, `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `WEBAUTHN_RP_ID`, `WEBAUTHN_ORIGIN`, and `HEARTBEAT_URL`. `DURATION_SCALE` is in staging only and absent in production. `CONFIG_CACHE_TTL_MS` stays for non-coverage configuration. Top level sets `workers_dev = false`, `preview_urls = false`, and `[observability] enabled = true`, plus a `send_email` binding with the verified destination, and secret `PLATFORM_SIGNING_KEY` in place of `OPERATOR_BEARER_TOKEN`. Rate-limit lines stay unchanged. `Env` drops `OPERATOR_BEARER_TOKEN` and adds the platform key, issuer id, Access and WebAuthn settings, `HEARTBEAT_URL`, the staging `DURATION_SCALE`, and the `send_email` binding. This worker sets `workers_dev = false` and `preview_urls = false`, so the Access-protected console has no bypass hostname on the platform. (04 §6.4, 04 §6.1 `worker.ts` `Env` clause, 02 §1.4 last paragraph, Implements)
- **FR-011**: `0 5 1 * *` is gone. `runScheduled("0 3 * * *")` runs retention. `runScheduled("0 4 * * *")` runs rollup keyed by `term_id`. (04 §6.4 cron row, E2E-P3.10-07)
- **FR-012**: Harness migration rule V2 step 4 is complete. `operatorFetch` and `operatorFetchRaw` in `ai-platform/test/system/harness.ts` are deleted. `ai-platform/test/e2e/harness/control.ts` and `ai-platform/test/e2e/harness/env.ts` are rewritten to call `VendorEntrypoint` with test Access JWTs and test passkey assertions, and to mint issuer tokens with a test issuer key. Suites in the 04 §6.5 Delete row are deleted: `period-close.test.ts`, `price-list-activation.test.ts`, `entitle-grant.test.ts`, `e2e/stage-03-enroll-validation.test.ts`, `e2e/stage-03-lifecycle-rotate.test.ts`, `e2e/stage-04-entitle-auth-period.test.ts`, `e2e/stage-04-entitle-quota-grants-validation.test.ts`. Suites in the 04 §6.5 Rewrite row are rewritten, including `control.test.ts` (becomes vendor-entrypoint), the `system/*` interplay tests, the `e2e/stage-*` tests that enroll or entitle through `/control/*`, and the e2e harness files named above. `ai-platform/vitest.e2e.config.ts` and `ai-platform/vitest.workers.config.ts` drop the `OPERATOR_BEARER_TOKEN` binding and bind the test issuer key, Access settings, and `DURATION_SCALE`. The full rewritten SYS and e2e catalogue is green, with no bearer token anywhere in the test config. (04 §6.5 Delete, Rewrite, and Config rows, 06 §3 V2 step 4, Implements, E2E-P3.10-08)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One clinic platform keeps operator configuration (routing policy, kill switch, cohort, capability lifecycle, token contract, and support lookup) on `VendorEntrypoint`. Former `/control/*` paths answer 404. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are `vendorCall` on `VendorEntrypoint` (`env.VENDOR` in `ai-platform/test/system/harness.ts`), `SELF.fetch` on `ai-platform/src/worker.ts` for former `/control/*` paths, and `runScheduled` for `0 3 * * *` and `0 4 * * *`. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: Class-H methods take `access_jwt`. Kill-switch audit actor is the Access email, and `control_audit` records `assertion_sha256`. `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID` are removed. `workers_dev = false` and `preview_urls = false`. Dropped platform D1 tables are `invoice`, `credit_price`, `plan`, and `entitlement`, plus the coverage_ledger drop clauses. (04 §1.3, 04 §6.1 audit row, 04 §6.3, 04 §6.4, 02 §3.1 Removed paragraph, 02 §1.4 last paragraph)
- **Failure Handling**: A former `/control/*` path answers 404. The worker boots with `OPERATOR_BEARER_TOKEN` absent. A kill switch on a capability answers `capability_disabled` and raises AL-19. `supportLookup` by reference returns the envelope within retention. (E2E-P3.10-01, E2E-P3.10-03, E2E-P3.10-06)

## 5. Out of Scope

- Viewer and `docs/testing/catalog` (→ P7.1); console UI (→ P4.9).
- No Do-not-read material. This unit row has no Do not read line.
- No rewrite of the HTTP feed contract, the `/v1/coverage` response, or `feedConsumerHealth` (P3.9 Outputs / freezes, rule S7).
- No module that no test-plan row reaches (rule S8). Class-H kill switch, routing policy, capability lifecycle, and token contract are reached by `vendorCall` (E2E-P3.10-02 through E2E-P3.10-05). Cohort is reached by the rewritten SYS and e2e catalogue (E2E-P3.10-08), which includes the existing cohort suites. `supportLookup` is reached by `vendorCall("supportLookup", …)` (E2E-P3.10-06). Removal of `/control/*` is reached by `SELF.fetch` (E2E-P3.10-01). Retention and rollup are reached by `runScheduled` (E2E-P3.10-07). The harness rewrite is reached by E2E-P3.10-08.
- No S9 path owned by a later unit. Viewer pages and `docs/testing/catalog` stage pages that describe `/control/*` stay until P7.1 (rule V2). Console relays of these methods stay until P4.9.
- No second codebase. The Codebase cell is `ai-platform`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.10-01, E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, E2E-P3.10-05, E2E-P3.10-06, and E2E-P3.10-07 pass in harness H-AP, and E2E-P3.10-08 passes in H-AP and the e2e catalogue.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 open question is named by this unit's Read or Implements lines.
- Rule S9: this unit removes the transitional entitlement, plan, and invoice tables and all `/control/*` routes. `invoice` and `credit_price` are dropped with them (Implements, 04 §6.3).
- Viewer and `docs/testing/catalog` pages that still describe `/control/*` stay until P7.1 (rule V2). Console UI stays until P4.9.
- 04 §6.3 migration file names are indicative. This unit creates its own migration files with fresh, increasing timestamps (rule S7).
