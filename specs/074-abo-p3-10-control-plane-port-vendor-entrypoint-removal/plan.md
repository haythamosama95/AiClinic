# Implementation Plan: Control-plane port to `VendorEntrypoint` and removal of `/control/*`

**Branch**: `ai/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.10 exposes kill switch, routing policy, cohort, capability lifecycle, token contract, and `supportLookup` as class-H methods on `VendorEntrypoint`, then removes `/control/*`, the shared bearer, and the transitional `invoice`, `credit_price`, `plan`, and `entitlement` tables. It is phase P3, size L, **Depends** P3.8 and P3.9, in parallel with P4.x.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. Class-H methods reuse `verifyHpAccess` (the Access JWT check `suspend` already uses) and `negotiate` on the vendor channel. Audit rows reuse `writeEntrypointAudit`. AL-19 reuses `raiseAl19FromOutbox` in `ai-platform/src/alert/index.ts`. `supportLookup` stays in `ai-platform/src/support/index.ts`. Subscription refs reuse `subscriptionRef` from `vendor-contracts`. Tests use `vendorCall`, `coverClinic`, `newClinic`, `mintAat`, `invoke`, `runScheduled`, and `setupVendorHarness` from `ai-platform/test/system/harness.ts`. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`.

**Storage**: D1 tables dropped by this unit: `invoice`, `credit_price`, `plan`, `entitlement`, and `grace_admission_queue` (already dropped in `20261006160000_fallback_admission_feed.sql`; this unit's migration repeats `DROP TABLE IF EXISTS`). Kept: `plan_version`, `token_contract` (version `2` is already inserted by `20261003130000_issuer_key_tenant_binding.sql`), `kill_switch`, `capability_grant`, `routing_policy`, `control_audit`, `platform_alert`, `coverage_mirror`, `tenant_binding`, `feed_consumer`. No new table. No clinic PostgreSQL change.

**Testing**: H-AP. E2E-P3.10-01 through E2E-P3.10-07 live in `ai-platform/test/system/control-plane-port.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the class-H methods and the `/control/*` removal exist. The unit command is that file only. E2E-P3.10-08 is the rewritten SYS catalogue (`test/system/`) and e2e catalogue (`test/e2e/`) after the 04 §6.5 Delete and Rewrite rows, plus both vitest configs. No new CI job (rule V7). Earlier platform suites stay on the existing `npm test` and `npm run test:e2e` jobs (rule S2). Time moves with the existing test clock and `runScheduled` (rule V4). No local scenario sleeps more than 2 s. AL-19 is a `platform_alert` row with code `AL-19` and the captured `send_email` body (rule V6). The harness does not start an ABO worker.

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Live entries are `vendorCall` on `VendorEntrypoint` (`env.VENDOR` in `ai-platform/test/system/harness.ts`), `SELF.fetch` on `ai-platform/src/worker.ts` `fetch` for former `/control/*` paths, `GET /v1/capabilities` for discovery, `POST /v1/requests` for `capability_disabled` and promoted-policy traffic, and `runScheduled` for `0 3 * * *` and `0 4 * * *`.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). No separate throughput target. The write budget stays in P3.11.

**Constraints**: Do not modify `packages/vendor-contracts`. Do not change `handleFeedCoverageRequest`, the `GET /v1/feed/coverage` route, `handleCoverageReadRequest`, the `GET /v1/coverage` route, or `feedConsumerHealth` (P3.9 freezes, rule S7). Do not change `publishPlanVersion`, `retirePlanVersion`, `inspectCoverage`, `suspend`, `resume`, or `deleteInstallation` result rules. Viewer and `docs/testing/catalog` stay until P7.1. Console relays stay until P4.9. `workers_dev = false` and `preview_urls = false` are already set; this unit does not turn them on.

**Scale/Scope**: Size L (rule S3: 3–4 user stories, one codebase). Four user stories and eight E2E ids. Implied task count is 30. That is under the L band and is not padded (rule S3, plan skill).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The spec defines no entities, so there is no `data-model.md`. **Freezes** is none, so there is no `contracts/`. No clinic write and no second service. The same boxes hold.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One clinic platform keeps operator configuration on `VendorEntrypoint`. Former `/control/*` paths answer 404 (spec §4.1, 02 §7 principle I). The unit adds no second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. Crons stay the existing list with `0 5 1 * *` removed (02 §7 principle I and the workflow-automation row). No Kubernetes and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 constraints and the DO's serialized writer. Clinic RPCs, RLS, and triggers stay as they are. Dropped tables are the pre-launch transitional platform tables named in 04 §6.3.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Class-H methods take `access_jwt` (spec §4.1, 02 §3.3, 04 §1.3). The kill-switch audit actor is the Access email, and `control_audit` records `assertion_sha256`. `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID` are removed. `workers_dev = false` and `preview_urls = false` stay set (02 §1.4).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). A kill switch refuses the clinic request inline with `capability_disabled`. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/
├── plan.md
├── spec.md
├── quickstart.md              # implement writes this after verification; outline below
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). No `data-model.md` (spec §3.2 defines no entities). No `contracts/` (**Freezes** is none).

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — class-H methods on `VendorEntrypoint`, `/control/*` removed, bearer and `OPERATOR_ID` removed, transitional tables dropped, crons without `0 5 1 * *`, harness off `operatorFetch`.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/control-plane-port.system.test.ts
```

E2E-P3.10-08, after that file is green, runs the rewritten catalogues only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system
cd ai-platform && npx vitest run --config vitest.e2e.config.ts test/e2e
```

`npm test` and other packages stay out of these commands (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.10-01 | `SELF.fetch` on `worker.ts` `fetch` for each former `isControlRoute` path → 404. Worker module loads with `OPERATOR_BEARER_TOKEN` absent from the vitest bindings. |
| E2E-P3.10-02 | `vendorCall("publishRoutingPolicy")` → `vendorCall("canaryRoutingPolicy")` → `vendorCall("promoteRoutingPolicy")` on `VendorEntrypoint` → `src/control/routing-policy.ts` → `POST /v1/requests` follows the promoted policy. |
| E2E-P3.10-03 | `vendorCall("armKillSwitch")` → `src/control/kill-switch.ts` → `writeEntrypointAudit` → `raiseAl19FromOutbox` → `POST /v1/requests` returns `capability_disabled`. |
| E2E-P3.10-04 | `vendorCall("deprecateCapability")` or `vendorCall("retireCapability")` → `src/control/capability-lifecycle.ts` → `GET /v1/capabilities`. |
| E2E-P3.10-05 | `vendorCall("beginTokenContractRotation")` → `src/control/token-contract.ts` → `token_contract` ver `2` current. |
| E2E-P3.10-06 | `vendorCall("supportLookup")` → `src/support/index.ts`, once by subscription ref and once by reference. |
| E2E-P3.10-07 | `ai-platform/wrangler.toml` `[triggers].crons` → `runScheduled("0 3 * * *")` → `runRetentionPurge`; `runScheduled("0 4 * * *")` → `runRollupAndReconciliation` keyed by `term_id`. |
| E2E-P3.10-08 | Rewritten `test/system/` and `test/e2e/` catalogues, `test/e2e/harness/control.ts`, `test/e2e/harness/env.ts`, `vitest.workers.config.ts`, `vitest.e2e.config.ts`. |

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   ├── 20261006170000_drop_invoicing.sql
│   └── 20261006170100_drop_plan_entitlement.sql
├── src/
│   ├── admission/
│   │   └── index.ts
│   ├── config-cache/
│   │   └── index.ts
│   ├── control/
│   │   ├── audit.ts
│   │   ├── capability-lifecycle.ts
│   │   ├── cohort.ts
│   │   ├── kill-switch.ts
│   │   ├── routing-policy.ts
│   │   ├── token-contract.ts
│   │   └── types.ts
│   ├── period-close/          # deleted
│   ├── support/
│   │   └── index.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   └── worker.ts
├── test/
│   ├── e2e/
│   │   └── harness/
│   │       ├── control.ts
│   │       └── env.ts
│   ├── system/
│   │   ├── control-plane-port.system.test.ts
│   │   └── harness.ts
│   ├── vendor-entrypoint.test.ts
│   ├── vitest.e2e.config.ts
│   └── vitest.workers.config.ts
└── wrangler.toml
```

`src/control/index.ts`, `auth.ts`, `http.ts`, `entitle.ts`, `credit-price.ts`, `lifecycle.ts`, `plan.ts`, `quota-inspect.ts`, and `support-purge.ts` are removed with the HTTP handlers. `publishPlanVersion`, `retirePlanVersion`, `inspectCoverage`, `suspend`, `resume`, and `deleteInstallation` stay on `VendorEntrypoint`.

**Structure Decision**: Source stays the existing Worker. New class-H methods are added on `VendorEntrypoint` and call the kept logic in `src/control/kill-switch.ts`, `routing-policy.ts`, `token-contract.ts`, `capability-lifecycle.ts`, and `cohort.ts`, plus `src/support/index.ts`. `worker.ts` `fetch` no longer dispatches `/control/*`. `GET /v1/feed/coverage` and `GET /v1/coverage` stay. No new module.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| P3.8 | None. |
| HTTP feed contract | `handleFeedCoverageRequest` in `ai-platform/src/worker.ts`, dispatched for `GET /v1/feed/coverage`. Page query, version check, and the `feed_consumer` upsert stay. This unit does not change that function or that route. |
| `/v1/coverage` response | `handleCoverageReadRequest` in `ai-platform/src/coverage-read/index.ts`, dispatched from `worker.ts` for `GET /v1/coverage`. This unit does not change that function or that route. |
| `feedConsumerHealth` | `VendorEntrypoint.feedConsumerHealth` in `ai-platform/src/vendor/entrypoint.ts` (class M). `detail` stays the JSON text of `{last_pull_at, last_cursor}` from `feed_consumer`. This unit does not change it. |

## Files

| File | FR |
| --- | --- |
| `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/quickstart.md` (implement, after verification) | FR-001 through FR-012 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006 |
| `ai-platform/src/control/routing-policy.ts` | FR-001, FR-002 |
| `ai-platform/src/control/kill-switch.ts` | FR-001, FR-003 |
| `ai-platform/src/control/audit.ts` | FR-003 |
| `ai-platform/src/control/capability-lifecycle.ts` | FR-001, FR-004 |
| `ai-platform/src/control/token-contract.ts` | FR-001, FR-005 |
| `ai-platform/src/control/cohort.ts` | FR-001 |
| `ai-platform/src/support/index.ts` | FR-006 |
| `ai-platform/src/control/types.ts` | FR-008 |
| `ai-platform/src/worker.ts` | FR-007, FR-008, FR-011 |
| `ai-platform/src/period-close/index.ts` (delete) | FR-007 |
| `ai-platform/src/control/index.ts` (delete) | FR-007 |
| `ai-platform/src/control/auth.ts` (delete) | FR-007, FR-008 |
| `ai-platform/src/control/http.ts` (delete) | FR-007 |
| `ai-platform/src/control/entitle.ts` (delete) | FR-007 |
| `ai-platform/src/control/credit-price.ts` (delete) | FR-007 |
| `ai-platform/src/control/lifecycle.ts` (delete) | FR-008 |
| `ai-platform/src/control/plan.ts` (delete) | FR-008 |
| `ai-platform/src/control/quota-inspect.ts` (delete) | FR-008 |
| `ai-platform/src/control/support-purge.ts` (delete) | FR-008 |
| `ai-platform/migrations/20261006170000_drop_invoicing.sql` | FR-009 |
| `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql` | FR-009 |
| `ai-platform/src/config-cache/index.ts` | FR-009 |
| `ai-platform/src/admission/index.ts` | FR-009 |
| `ai-platform/wrangler.toml` | FR-010, FR-011 |
| `ai-platform/test/system/control-plane-port.system.test.ts` | FR-001 through FR-008, FR-010, FR-011 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-012 |
| `ai-platform/test/e2e/harness/control.ts` | FR-012 |
| `ai-platform/test/e2e/harness/env.ts` | FR-012 |
| `ai-platform/test/vendor-entrypoint.test.ts` | FR-012 |
| `ai-platform/test/control.test.ts` (delete) | FR-012 |
| `ai-platform/vitest.workers.config.ts` | FR-012 |
| `ai-platform/vitest.e2e.config.ts` | FR-012 |
| `ai-platform/test/period-close.test.ts` (delete) | FR-012 |
| `ai-platform/test/price-list-activation.test.ts` (delete) | FR-012 |
| `ai-platform/test/entitle-grant.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-03-enroll-validation.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts` (delete) | FR-012 |
| `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts` (delete) | FR-012 |

`handleFeedCoverageRequest`, `handleCoverageReadRequest`, and `feedConsumerHealth` stay as they are. `packages/vendor-contracts/**` stays. `ai-platform-viewer/` and `docs/testing/catalog/` stay until P7.1.

The SYS and e2e files that still call `operatorFetch` or `/control/*`, and the workers-pool tests that still read `entitlement`, `plan`, `invoice`, or `credit_price`, are rewritten in the Sequencing steps for FR-012 and FR-009. They are not new modules. `ai-platform/test/plan-catalogue.test.ts` follows the mapping in Test Layout: one existing `publishPlanVersion` call and a `plan_version` read. The old plan CRUD, entitle, override, and config-cache plan and entitlement cases leave that file.

## Test Layout

Titles start with the E2E id (rule V3). E2E-P3.10-01 through E2E-P3.10-07 are in `ai-platform/test/system/control-plane-port.system.test.ts` under H-AP (`vitest.workers.config.ts`). Each test calls the entry point below and fails while the behavior it names is absent. Class-H calls use `vendorCall(method, args, { accessJwt })` with the harness Access JWT (`VENDOR_OPERATOR_EMAIL`). No assertion object. No `sleep` over 2 s. No ABO worker is constructed.

A class-H success is the existing `VendorResultEnvelope`: `result` `ok`, `code` empty, `receipt` absent, `detail` the JSON text of the object the handler returns today. A handler `reject` code becomes `result` `rejected` with that `code`. Idempotency stays the handler's current duplicate and illegal-transition rules.

`harness.ts` adds these names to the `VendorMethod` union: `publishRoutingPolicy`, `canaryRoutingPolicy`, `promoteRoutingPolicy`, `rollbackRoutingPolicy`, `armKillSwitch`, `disarmKillSwitch`, `deprecateCapability`, `retireCapability`, `activateCohort`, `promoteCohort`, `beginTokenContractRotation`, `retireTokenContract`, `supportLookup`. All are class H in `METHOD_CLASS`.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.10-01 | H-AP | Title `E2E-P3.10-01 former /control paths are 404 and the worker boots without the bearer`. `SELF.fetch` POST for one path of each pattern `isControlRoute` accepts: `/control/installations/{id}/suspend`, `resume`, `delete`, `purge`, `entitle`, `override`; `/control/capabilities/{id}/versions/{ver}/deprecate`, `retire`, `activate`, `promote`; `/control/routing-policies/publish`; `/control/routing-policies/{id}/versions/{ver}/canary`, `promote`, `rollback`; `/control/token-contract/begin-rotation`, `retire`; `/control/support/lookup`; `/control/kill-switches/arm`, `disarm`; `/control/plans/create`; `/control/plans/{id}/update`, `delete`; `/control/credit-price/activate`. GET `/control/installations/{id}/quota`. Every response is 404. The workers binding set for this run has no `OPERATOR_BEARER_TOKEN`, and the worker has already loaded. |
| E2E-P3.10-02 | H-AP | Title `E2E-P3.10-02 routing policy publish canary promote and traffic follows`. Port of SYS suite 4 (`routing-policy-traffic.system.test.ts`): `coverClinic` and `newClinic`, then `publishRoutingPolicy`, `canaryRoutingPolicy`, and `promoteRoutingPolicy` over `env.VENDOR`. The promoted version is `active`, the previous version is `superseded`, and `POST /v1/requests` is served with that promoted policy. |
| E2E-P3.10-03 | H-AP | Title `E2E-P3.10-03 kill switch answers capability_disabled and raises AL-19`. `armKillSwitch` for a capability. `POST /v1/requests` for that capability is `capability_disabled`. `platform_alert.code` is `AL-19`. `control_audit.actor` is the Access email. `control_audit.assertion_sha256` is stored (null when the call has no assertion). |
| E2E-P3.10-04 | H-AP | Title `E2E-P3.10-04 capability deprecate and retire show on discovery`. `deprecateCapability` and `retireCapability` over `env.VENDOR`. `GET /v1/capabilities` reflects `deprecated` and then `retired`. |
| E2E-P3.10-05 | H-AP | Title `E2E-P3.10-05 token-contract rotation leaves version 2 current`. `beginTokenContractRotation` over `env.VENDOR`. `token_contract` ver `2` has `retired_at` null. A repeat is the current-version success, not a conflict. |
| E2E-P3.10-06 | H-AP | Title `E2E-P3.10-06 supportLookup by subscription ref and by reference`. `supportLookup` with the clinic's `subscriptionRef` returns that clinic's requests. `supportLookup` with the request reference returns the envelope within retention. |
| E2E-P3.10-07 | H-AP | Title `E2E-P3.10-07 monthly period close is gone and 0 3 and 0 4 run retention and rollup`. `[triggers].crons` has `0 3 * * *`, `0 4 * * *`, and `*/5 * * * *`, and does not have `0 5 1 * *`. `runScheduled("0 3 * * *")` runs retention. `runScheduled("0 4 * * *")` runs rollup whose dimensions include `term_id`. |
| E2E-P3.10-08 | H-AP + e2e catalog | Title `E2E-P3.10-08 rewritten SYS and e2e catalogues are green without a bearer`. After the Delete and Rewrite rows, `test/system` under `vitest.workers.config.ts` and `test/e2e` under `vitest.e2e.config.ts` pass. Neither config contains `OPERATOR_BEARER_TOKEN`. `operatorFetch` and `operatorFetchRaw` are absent from `test/system/harness.ts`. |

**`plan-catalogue.test.ts`.** 04 §6.5 rewrites this file. It stays in the `vitest.workers.config.ts` `include` list. `publishPlanVersion` and `retirePlanVersion` result rules stay as they are. The mapping for this file is:

- Creating a catalogue row is one call to the existing `publishPlanVersion` on `env.VENDOR`, with the HP access JWT, passkey assertion, and arguments that method already accepts (the same publish `coverClinic` performs). The case reads that `plan_version` row and expects `status` `published` and the method's existing `ok` detail. The case does not call `coverClinic`.
- Updating a plan row, deleting a plan row, rejecting those HTTP handlers when the operator is missing, copying catalogue economics onto an entitlement, and recording a per-installation override are removed from this file. They are not calls to `publishPlanVersion`, `retirePlanVersion`, or any other `VendorEntrypoint` method. Former `/control/plans/create`, `/control/plans/{id}/update`, `/control/plans/{id}/delete`, entitle, and override responses stay the 404s in E2E-P3.10-01.
- Config-cache reads of `plans` and `entitlements` (cold one D1 read and warm zero I/O, including `credit_budget`) are removed from this file. They are not calls on `VendorEntrypoint`. Those reader cases return `"miss"` and do not query the dropped tables (Sequencing step 19).

The file no longer imports `src/control` HTTP handlers and no longer inserts or selects `plan`, `entitlement`, `invoice`, or `credit_price`. The other workers-pool files in Sequencing step 28 stay on that step: change a file only when it still inserts or selects those tables, and put its setup on `coverClinic` and `plan_version`.

## Sequencing

Tests are written and observed failing before the class-H methods, the route removal, and the table drops exist. Each step is one task. The implied count is 30.

1. Add `test/system/control-plane-port.system.test.ts` with E2E-P3.10-01. Run the unit command. It fails because former `/control/*` paths are not all 404.
2. Add E2E-P3.10-02. The run fails because `publishRoutingPolicy` is not a method.
3. Add E2E-P3.10-03. The run fails because `armKillSwitch` is not a method.
4. Add E2E-P3.10-04. The run fails because `deprecateCapability` is not a method.
5. Add E2E-P3.10-05. The run fails because `beginTokenContractRotation` is not a method.
6. Add E2E-P3.10-06. The run fails because `supportLookup` is not a method.
7. Add E2E-P3.10-07. The run fails because `[triggers].crons` still lists `0 5 1 * *`.
8. Add the thirteen class-H names to `METHOD_CLASS` in `src/vendor/entrypoint.ts` and to `VendorMethod` in `test/system/harness.ts`. Each method checks `access_jwt` with `verifyHpAccess` and negotiates the vendor channel. No assertion is required.
9. `publishRoutingPolicy`, `canaryRoutingPolicy`, `promoteRoutingPolicy`, and `rollbackRoutingPolicy` call the existing logic in `src/control/routing-policy.ts`. Input fields stay the handler bodies today (`document`, policy id, version, canary installation ids). Success `detail` is that handler's ok object. Illegal transitions stay rejected with the handler's current code. Drop the `Request` and bearer arguments from that module.
10. `armKillSwitch` and `disarmKillSwitch` call the existing logic in `src/control/kill-switch.ts` (`scope`, `target`). The actor passed into `writeEntrypointAudit` is the Access email. `assertion_sha256` is the column value (null on class H). On a kill-switch change, call `raiseAl19FromOutbox` so `platform_alert.code` is `AL-19` and the email body is that code plus ids. A live `POST /v1/requests` for an armed capability still returns `capability_disabled` through the existing capability check.
11. `deprecateCapability` and `retireCapability` call the existing logic in `src/control/capability-lifecycle.ts`. `GET /v1/capabilities` already reads the overlay those handlers write. Drop the `Request` and bearer arguments.
12. `beginTokenContractRotation` uses `src/control/token-contract.ts` to make ver `"2"` current (`retired_at` null). If ver `2` is already current, the result is `ok` and nothing else is inserted. `retireTokenContract` keeps today's retire rules. Drop the caller-supplied `ver` on the rotation method.
13. `supportLookup` is class H. `src/support/index.ts` still looks up by request reference and returns the envelope within retention. The same function also accepts a subscription ref (`subscriptionRef(org_id)` from `vendor-contracts`) and an `org_id`, and returns that clinic's requests via `tenant_binding.installation_id` and `ai_request.installation_id`. One of reference, subscription ref, or `org_id` is required.
14. In `src/control/cohort.ts`, replace the `entitlement` select with published `plan_version` rows (`plan_id`, `capabilities` where `status = 'published'`) for plan-scoped grants, and active `tenant_binding` rows whose `coverage_mirror.term_snapshot` capabilities include the capability for installation grants. `activateCohort` and `promoteCohort` call that logic. The actor stored as `changed_by` is the Access email.
15. Remove the `isControlRoute` branch from `worker.ts` `fetch`, and delete `src/control/index.ts`, `auth.ts`, `http.ts`, `entitle.ts`, and `credit-price.ts`. Kept modules stop importing `http.ts`. `audit.ts` keeps its id and timestamp helpers locally. Delete `src/period-close/index.ts` and the `cron === "0 5 1 * *"` branch in `scheduled`. `0 3 * * *` stays `runRetentionPurge`. `0 4 * * *` stays `runRollupAndReconciliation` (already grouped by `term_id`). The `*/5 * * * *` branch stays.
16. Delete `src/control/lifecycle.ts`, `plan.ts`, `quota-inspect.ts`, and `support-purge.ts`. `suspend`, `resume`, `deleteInstallation`, `publishPlanVersion`, `retirePlanVersion`, and `inspectCoverage` stay on `VendorEntrypoint` unchanged. `src/control/types.ts` keeps only the types the remaining control modules use.
17. `Env` in `worker.ts` drops `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID`. Boot does not read either binding. `assertRequiredBindings` stays DB, R2, and DO.
18. Add `ai-platform/migrations/20261006170000_drop_invoicing.sql` with `DROP TABLE IF EXISTS invoice` and `DROP TABLE IF EXISTS credit_price`. Add `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql` with `DROP TABLE IF EXISTS plan`, `DROP TABLE IF EXISTS entitlement`, and `DROP TABLE IF EXISTS grace_admission_queue`. Do not edit earlier migrations.
19. In `src/config-cache/index.ts`, the `plans` and `entitlements` reader cases return `"miss"` and do not query those tables. In `src/admission/index.ts`, delete `loadInstallationEntitlement` and use the snapshot object already built in the `??` branch. Do not change the fallback conditions, `fallback_admission` insert, or `GET /v1/feed/coverage`.
20. In `ai-platform/wrangler.toml`, remove `OPERATOR_ID` from development, staging, and production vars, and remove `0 5 1 * *` from `[triggers].crons`. Leave `workers_dev`, `preview_urls`, the DO class, rate limits, Access vars, `ISSUER_ID`, `PLATFORM_SIGNING_KEY`, `HEARTBEAT_URL`, `send_email`, and staging-only `DURATION_SCALE` as they are.
21. Delete `operatorFetch` and `operatorFetchRaw` from `test/system/harness.ts`. Point `publishPolicy`, `canary`, `promote`, and `rollback` at the new `vendorCall` methods.
22. Rewrite `test/e2e/harness/control.ts` and `test/e2e/harness/env.ts` so they call `VendorEntrypoint` with test Access JWTs and test passkey assertions, and mint issuer tokens with the test issuer key. Remove `OPERATOR_BEARER_TOKEN` from those files.
23. Delete `period-close.test.ts`, `price-list-activation.test.ts`, `entitle-grant.test.ts`, `e2e/stage-03-enroll-validation.test.ts`, `e2e/stage-03-lifecycle-rotate.test.ts`, `e2e/stage-04-entitle-auth-period.test.ts`, and `e2e/stage-04-entitle-quota-grants-validation.test.ts`. Remove the deleted workers-pool files from `vitest.workers.config.ts` `include`.
24. Replace `test/control.test.ts` with `test/vendor-entrypoint.test.ts` that calls the class-H methods on `env.VENDOR` and does not send a bearer. Point the workers `include` list at the new file. Drop cases that only asserted a deleted HTTP handler.
25. Rewrite the `test/system/*.system.test.ts` files that still call `operatorFetch` or `/control/*` so they use `vendorCall`, `coverClinic`, and `newClinic`. Leave `handleFeedCoverageRequest` and `GET /v1/coverage` assertions as they are.
26. Rewrite the `test/e2e/stage-*.test.ts` files that still enroll or entitle through `/control/*` the same way.
27. In `vitest.workers.config.ts` and `vitest.e2e.config.ts`, remove `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID`. Keep `ISSUER_ID` and the Access bindings. Add `DURATION_SCALE` = `"staging"`.
28. Update the remaining workers-pool tests that still `INSERT` or `SELECT` `entitlement`, `plan`, `invoice`, or `credit_price` so they do not touch those tables. Setup goes through `coverClinic` and `plan_version`. `test/plan-catalogue.test.ts` follows the Test Layout mapping for that file: one existing `publishPlanVersion` call and a `plan_version` read; plan update, plan delete, entitle economics, override, and config-cache plan and entitlement reads leave the file.
29. Run the unit command and confirm E2E-P3.10-01 through E2E-P3.10-07 pass.
30. Run the two catalogue commands in the quickstart outline (E2E-P3.10-08). Confirm both configs contain no `OPERATOR_BEARER_TOKEN`, and that `src/support/index.ts`, the kept `src/control/*` modules, and the new methods are reached from the entry points in Test Layout.

## Complexity Tracking

02 §7 records no constitution violation for this unit. Nothing is filled in here.
