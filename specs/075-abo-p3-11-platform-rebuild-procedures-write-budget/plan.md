# Implementation Plan: Platform rebuild procedures and the write budget

**Branch**: `ai/075-abo-p3-11-platform-rebuild-procedures-write-budget` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.11 adds three class-H methods on `VendorEntrypoint`: rebuild one clinic's DO from the last `coverage_event` and later ledger, void, hold, release, suspension, and transfer events plus `usage_event`; rebuild `grant_ledger` and `grant_void` from R2 `grant-ledger/`; and emit one fresh snapshot `coverage_event` per installation so `coverage_mirror` updates. It is phase P3, size M, **Depends** P3.10, in parallel with P4.x. The same unit measures the live `POST /v1/requests` path: 100 concurrent requests across exhaustion, one exhaustion, overshoot ≤ `w_max − 1`, and ≤ 2 `hot` row writes per request.

## Technical Context

**Language/Version**: TypeScript ESM in `ai-platform`. The worker entry stays `ai-platform/src/worker.ts`. `VendorEntrypoint` stays the `WorkerEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`. `GatewayObject` stays the durable object.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. Class-H methods use the existing `invokeClassH` path (`verifyHpAccess` on `access_jwt`, vendor-channel `negotiate`). No passkey assertion. Tests use `vendorCall`, `coverClinic`, and `newClinic` from `ai-platform/test/system/harness.ts`.

**Storage**: Existing D1 tables `coverage_event`, `coverage_mirror`, `grant_ledger`, `grant_void`, `usage_event`, and `platform_alert`. Existing R2 keys `grant-ledger/<grant_id>.ndjson` and `grant-ledger/<grant_id>.void.ndjson`. Existing DO tables `hot`, `term`, `grant`, and `outbox`. No new table, column, index, migration, route, cron, alarm, or RPC.

**Testing**: H-AP for E2E-P3.11-01 through E2E-P3.11-04 in `ai-platform/test/system/platform-rebuild.system.test.ts`. H-AP load suite for E2E-P3.11-05 in `ai-platform/test/load/write-budget.load.test.ts`. Both run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the three methods and the write measurement exist. Time moves with the existing test clock (rule V4). No local scenario sleeps more than 2 s. The platform alert is a `platform_alert` row (rule V6). No new CI job (rule V7).

**Target Platform**: The existing `ai-platform` worker. Live entries are `vendorCall` on `VendorEntrypoint` (`env.VENDOR` in `ai-platform/test/system/harness.ts`) for `rebuildClinicDo`, `rebuildGrantLedger`, and `refreshCoverageSnapshot`, and `SELF.fetch` `POST /v1/requests` on `ai-platform/src/worker.ts` for the load.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: The load observes one exhaustion, overshoot ≤ `w_max − 1`, and ≤ 2 `hot` row writes per AI request (FR-005, FR-006, R-7). `w_max` is the published capability quota weight the existing admission tests call `W_MAX`.

**Constraints**: The D1 rebuild stays a separate class-H method from the snapshot refresh. 05 §5.3 runs the ledger rebuild first, then the snapshot method once per installation. The product path does not delete `grant_ledger` or `grant_void` (append-only triggers stay). Time Travel within 30 days is the operator restore in 05 §5.3; this unit does not call a Time Travel API. The DO schema stays the §3.2 `hot` row (research.md). Do not implement ABO rebuild (P4.11), backend projection rebuild (P5.2), the NFR-08 allowance check (P8.1), outage overshoot (P3.9), the 03 §6.7 events bullet (P3.3), or the 03 §6.7 alarm bullet (P3.5).

**Scale/Scope**: Size M (rule S3: 2–3 user stories, one codebase). Two user stories and five E2E ids. Implied task count is 17. That is the sequencing below and is not padded (rule S3, plan skill).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Research is the R-7 spike in `research.md`. The spec defines no entities, so there is no `data-model.md`. **Freezes** is none, so there is no `contracts/`. No clinic write and no second service. The same boxes hold after the design below.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One clinic's DO and `grant_ledger` are rebuilt after loss, and a live AI request stays inside the write budget (spec §4.1, 02 §7 principle I). The unit adds no second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. The three methods are class H on `VendorEntrypoint`. No new route, cron, alarm, queue, or service (02 §7 principle I and the workflow-automation row).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 and the clinic DO only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 append-only triggers and the DO's serialized writer. Clinic RPCs, RLS, and triggers stay as they are. `grant_ledger` and `grant_void` stay append-only.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Each class-H method takes `access_jwt` through `invokeClassH` (02 §3.3, 02 §7 principle IV). A mirror mismatch writes `platform_alert`. The product path does not delete ledger rows.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). The load uses the existing `POST /v1/requests` path. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/
├── plan.md
├── research.md
├── spec.md
├── quickstart.md              # implement writes this after verification; outline below
└── tasks.md                   # /abo-tasks, not this phase
```

`research.md` is the R-7 spike (already written). No `data-model.md` (spec §3.2 defines no entities). No `contracts/` (**Freezes** is none).

#### quickstart.md outline

Implement writes `quickstart.md` after both commands below are green. Sections:

1. What was implemented — `rebuildClinicDo`, `rebuildGrantLedger`, and `refreshCoverageSnapshot` on `VendorEntrypoint`, and the write-budget measurement on `POST /v1/requests`.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness commands for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/platform-rebuild.system.test.ts
```

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/load/write-budget.load.test.ts
```

`npm test`, `npm run test:load`, and other packages stay out of these commands (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.11-01 | `vendorCall("rebuildClinicDo")` → `VendorEntrypoint.rebuildClinicDo` → `src/quota-do/coverage.ts` load of the last `coverage_event`, later `grant_ledger` / `grant_void` / hold events, and `usage_event` → DO `term` and `hot`. |
| E2E-P3.11-02 | `vendorCall("rebuildClinicDo")` → the same rebuild → compare with `coverage_mirror` → `src/alert/index.ts` insert into `platform_alert`. |
| E2E-P3.11-03 | `vendorCall("rebuildGrantLedger")` → `src/quota-do/coverage.ts` list of R2 `grant-ledger/` → `INSERT OR IGNORE` into `grant_ledger` and `grant_void`. |
| E2E-P3.11-04 | `vendorCall("refreshCoverageSnapshot")` → DO outbox `coverage_event` → existing ship into D1 `coverage_event` and `coverage_mirror`. |
| E2E-P3.11-05 | `SELF.fetch` `POST /v1/requests` → `worker.ts` admission and credit on `GatewayObject` → `admitOnHotRow` / `settleReservationOnHot` in `src/quota-do/index.ts`. The test reads the in-memory write counts from inside `runInDurableObject`. |

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── alert/
│   │   └── index.ts
│   ├── quota-do/
│   │   ├── coverage.ts
│   │   └── index.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   └── worker.ts
└── test/
    ├── load/
    │   └── write-budget.load.test.ts
    └── system/
        ├── harness.ts
        └── platform-rebuild.system.test.ts
```

**Structure Decision**: Source stays the existing Worker. The three class-H methods are added on `VendorEntrypoint` and call functions in `src/quota-do/coverage.ts`. The mismatch alert is an insert in `src/alert/index.ts`. The write measurement stays inside `admitOnHotRow` and `settleReservationOnHot`. No new module and no new wrangler binding.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| P3.10 | None. |

## Files

| File | FR |
| --- | --- |
| `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/research.md` | FR-006 |
| `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/quickstart.md` (implement, after verification) | FR-001 through FR-006 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-003, FR-004 |
| `ai-platform/src/quota-do/coverage.ts` | FR-001, FR-002, FR-003, FR-004 |
| `ai-platform/src/alert/index.ts` | FR-002 |
| `ai-platform/src/quota-do/index.ts` | FR-006 |
| `ai-platform/src/worker.ts` | FR-006 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-003, FR-004 |
| `ai-platform/test/system/platform-rebuild.system.test.ts` | FR-001, FR-002, FR-003, FR-004 |
| `ai-platform/test/load/write-budget.load.test.ts` | FR-005, FR-006 |

`packages/vendor-contracts/**` stays. No migration file. `ai-platform/package.json` script `test:load` stays pointed at `test/load/load-and-cost.test.ts`.

## Test Layout

Titles start with the E2E id (rule V3). E2E-P3.11-01 through E2E-P3.11-04 are in `ai-platform/test/system/platform-rebuild.system.test.ts` under H-AP (`vitest.workers.config.ts`). E2E-P3.11-05 is in `ai-platform/test/load/write-budget.load.test.ts` under the same workers config (the H-AP load suite). Each test calls the entry point below and fails while the behavior it names is absent. Class-H calls use `vendorCall(method, args, { accessJwt })` with the harness Access JWT. No assertion object. No `sleep` over 2 s.

A class-H success is the existing result envelope: `result` `ok`, `code` empty, `receipt` absent, `detail` the JSON text named below. `invokeClassH` already returns `unauthenticated` when the access JWT is missing. These tests always send the harness JWT.

`harness.ts` adds `rebuildClinicDo`, `rebuildGrantLedger`, and `refreshCoverageSnapshot` to the `VendorMethod` union. All three are class H in `METHOD_CLASS`.

DO wipe in E2E-P3.11-01 and E2E-P3.11-02 uses `runInDurableObject` on that clinic's stub and deletes the DO `hot`, `term`, `grant`, and `outbox` rows. That is the loss. The method then loads an empty DO.

D1 truncation in E2E-P3.11-03 is the test's stand-in for an empty restored database. The test drops `grant_ledger_no_delete` and `grant_void_no_delete`, deletes the rows, and recreates those two triggers. The product method never deletes. It only inserts. The test waits until R2 already has `grant-ledger/<grant_id>.ndjson` for the grant under test (the existing grant ship writes that key).

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.11-01 | H-AP | Title `E2E-P3.11-01 FM-20 wiped DO rebuilds terms positions holds and usage and the compare is clean`. `newClinic` and `coverClinic` leave a clinic with terms, positions, holds, and settled usage, plus one admitted request that has not settled. Record the DO `term` rows and `hot.used`. Wipe that DO. `vendorCall("rebuildClinicDo", { installation_id })`. Afterward each `term` row matches the pre-loss `term_id`, `position`, `state`, hold, allowance, and used; `hot.used` matches; `hot.reservations` is `[]` and `hot.reserved` is 0. `detail` is `{"compare":"clean","installation_id":"<id>"}`. No `platform_alert` row with `alert_key` `do-rebuild:<id>`. |
| E2E-P3.11-02 | H-AP | Title `E2E-P3.11-02 a rebuild that diverges from the mirror alerts`. Same setup as E2E-P3.11-01. Before the wipe, change `coverage_mirror.state` for that installation so it cannot match the rebuilt DO. Wipe and `vendorCall("rebuildClinicDo")`. `platform_alert` has `alert_key` `do-rebuild:<installation_id>`, `code` `do_rebuild_mismatch`, `severity` `high`, `send_state` `unsent`. |
| E2E-P3.11-03 | H-AP | Title `E2E-P3.11-03 grant_ledger truncated rebuilds from R2 identical`. After the grant's R2 object exists, copy `grant_ledger` and `grant_void` for that clinic, truncate both tables as above, then `vendorCall("rebuildGrantLedger")`. Reloaded rows match the copy on `grant_id`, `origin_grant_id`, `org_id`, `installation_id`, `kind`, `source_kind`, `operator_credential_id`, `envelope_sha256`, `receipt`, and `applied_at`, and void rows match on `grant_id`, `reason`, `source`, `evidence_sha256`, and `at`. `detail` is `{"grant_ledger":<n>,"grant_void":<m>}` for the objects listed. |
| E2E-P3.11-04 | H-AP | Title `E2E-P3.11-04 snapshot refresh writes one coverage_event and updates the mirror`. Note the installation's `coverage_event` count and `coverage_mirror.clinic_seq`. `vendorCall("refreshCoverageSnapshot", { installation_id })`. Exactly one new `coverage_event` exists for that installation, `kind` `snapshot`, and `coverage_mirror` for that installation matches the new event's snapshot, `binding_epoch`, and `clinic_seq`. `detail` is `{"event_id":"<id>","installation_id":"<id>"}`. |
| E2E-P3.11-05 | H-AP load suite | Title `E2E-P3.11-05 A34 100 concurrent requests across exhaustion stay inside the write budget`. `coverClinic` with an allowance the 100 requests cross, and no queued successor. `Promise.all` of 100 `SELF.fetch` `POST /v1/requests`. Exactly one term ends `exhausted`. That term's usage beyond its allowance is ≤ `w_max − 1`. A later term is not charged. For every request, `hot` writes are ≤ 2. `term`, `grant`, and `outbox` writes are 0 on every request except the one that exhausts the term. Counts come from `total_changes()` inside admission and settlement, read back through `runInDurableObject`. |

## Sequencing

Tests are written and observed failing before the three methods and the write measurement exist. Each step is one task. The implied count is 17.

1. Add `test/system/platform-rebuild.system.test.ts` with E2E-P3.11-01. Run the system command. It fails because `rebuildClinicDo` is not a method.
2. Add E2E-P3.11-02 to that file. The run fails because a divergent rebuild does not write `platform_alert`.
3. Add E2E-P3.11-03. The run fails because `rebuildGrantLedger` is not a method.
4. Add E2E-P3.11-04. The run fails because `refreshCoverageSnapshot` is not a method.
5. Add `test/load/write-budget.load.test.ts` with E2E-P3.11-05. Run the load command. It fails because per-request `hot` write counts are not recorded.
6. Add `rebuildClinicDo`, `rebuildGrantLedger`, and `refreshCoverageSnapshot` to `METHOD_CLASS` as `"H"` and to `VendorMethod`. Each method is `invokeClassH`. `rebuildClinicDo` and `refreshCoverageSnapshot` require `installation_id` and return `rejected` `missing_installation_id` when it is absent. An installation with no `coverage_event` returns `rejected` `not_found`.
7. In `buildCoverageSnapshot`, keep every key and value that function writes today. Add `terms`: one object per DO `term` row, `{term_id, position, state, end_reason, allowance, used, duration_unit, duration_count, starts_at, ends_at, grace_ends_at, held}`. `held` is true when `state` is `held`. `used` is `hot.used` for the active term and `used_final` otherwise. Do not put in-flight reservations on this object. `suspended`, `binding_epoch`, and `clinic_seq` stay the existing keys.
8. `rebuildClinicDo` deletes that clinic's DO `hot`, `term`, `grant`, and `outbox` rows, then loads the last `coverage_event` (highest `clinic_seq`) into `hot` and `term` from that snapshot, including `terms`. `hot.reservations` is `[]` and `hot.reserved` is 0. It does not write a new `coverage_event`.
9. Still in that method, apply rows with time after the snapshot `at`, in order: `grant_ledger` (`applied_at`), `grant_void` (`at`), then `coverage_event` kinds `term_held`, `term_released`, `suspension_changed`, and `transfer` (`clinic_seq` greater than the snapshot). Ledger and void application updates DO `term` and `hot` only. It does not insert another `grant_ledger` or `grant_void` row.
10. Re-apply `usage_event` rows for those `term_id`s with `recorded_at` after the snapshot `at`, including rows shipped from `usage_adjustment`. Add `quota_weight` to that term's used. A repeated `request_id` is applied once.
11. Compare the rebuilt DO with `coverage_mirror` (`state`, `suspended`, `binding_epoch`, `clinic_seq`, and the snapshot JSON). A match returns `ok` with `detail` `{"compare":"clean","installation_id":"<id>"}` and writes no alert. A mismatch calls a new export in `src/alert/index.ts` that inserts `platform_alert` (`alert_key` `do-rebuild:<installation_id>`, `code` `do_rebuild_mismatch`, `severity` `high`, `count` 1, `send_state` `unsent`) using the same column list as the existing alert insert. The method still returns `ok`; the alert is the compare outcome.
12. `rebuildGrantLedger` lists R2 prefix `grant-ledger/`. An object whose key ends in `.void.ndjson` inserts `grant_void` from that JSON (`grant_id`, `reason`, `source`, `evidence_sha256`, `at`). Any other object under that prefix inserts `grant_ledger` from that JSON (`grant_id`, `origin_grant_id`, `org_id`, `installation_id`, `kind`, `source_kind`, `operator_credential_id`, `envelope_sha256`, `receipt`, `applied_at`). Both inserts are `INSERT OR IGNORE`. `detail` is `{"grant_ledger":<n>,"grant_void":<m>}`. This method does not call `refreshCoverageSnapshot`.
13. `refreshCoverageSnapshot` asks that installation's DO to append one outbox `coverage_event` with `kind` `snapshot`, the current snapshot, and `clinic_seq` one higher, then runs the existing outbox ship so D1 `coverage_event` gains that row and `coverage_mirror` is replaced from it. One call, one installation. `detail` is `{"event_id":"<id>","installation_id":"<id>"}`.
14. In `admitOnHotRow` and `settleReservationOnHot`, read `total_changes()` before and after the writes. Count a write to `hot` as a `hot` write. Count a write to `term`, `grant`, or `outbox` as an event write. Keep the sums for that `request_id` in memory on the DO isolate (a module map in `src/quota-do/index.ts` that `runInDurableObject` can read). Do not add a column, a table, or an HTTP field. `worker.ts` does not copy the counts onto the `POST /v1/requests` response. `scheduleOutboxAlarmIfPending` stays outside the count.
15. Where an earlier test fails because `buildCoverageSnapshot` now includes `terms`, add `terms` to that expected object. Leave the previous keys and the admission, settlement, and feed behavior as they are.
16. Run the system command and confirm E2E-P3.11-01 through E2E-P3.11-04 pass.
17. Run the load command and confirm E2E-P3.11-05 passes, then write `quickstart.md` from the outline above.

## Complexity Tracking

02 §7 records no constitution violation for this unit. Nothing is filled in here.
