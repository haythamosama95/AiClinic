# Implementation Plan: Term boundaries, grace and renewal

**Branch**: `ai/069-abo-p3-5-term-boundaries-grace-renewal` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/069-abo-p3-5-term-boundaries-grace-renewal/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.5 runs the per-clinic boundary loop on the DO alarm and on admission, so a queued renewal starts at the old end date, an unpaid end date enters grace and then lapses, and a later grant either continues from that end date or starts at payment. It is phase P3, size M, **Depends** P3.4, in parallel with P4.2 and P4.3.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. Dates use the existing `addDuration` in `ai-platform/src/coverage/calendar.ts`. Tests use the existing H-AP helpers `coverClinic`, `vendorCall`, `setTestClock`, and `runDurableObjectAlarm` / `runInDurableObject` from `cloudflare:test`. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`.

**Storage**: The existing per-clinic DO SQLite tables `hot`, `term`, `grant`, and `outbox`. No new table and no new column. `term.grace_ends_at` and `hot.grace_base_used` are already on the row and are written when grace starts. `term.grace_cap` stays the rule text `proportional`. D1 `coverage_event` and `coverage_mirror` stay. `coverage_mirror.hard_stop_at` is filled from the snapshot this unit already ships. The existing `DB`, `R2`, and `DO` bindings stay.

**Testing**: H-AP. E2E-P3.5-01 through E2E-P3.5-08 live in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the boundary loop exists. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on `npm test` and `npm run test:e2e` (rule S2). Time moves with `setTestClock` and `runDurableObjectAlarm` (rule V4). No local scenario sleeps more than 2 s. The harness does not start an ABO worker.

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Clinic calls are `SELF.fetch` `POST /v1/requests`. Paid setup is `VendorEntrypoint.grant` over the H-AP self service binding (`coverClinic()` / `vendorCall`). The alarm is `GatewayObject.alarm()` in `ai-platform/src/worker.ts`. Staging scale is the existing `DURATION_SCALE` binding (`staging` maps 1 month to 30 minutes and 1 day to 1 minute). Production wrangler has no clock control.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). The boundary loop runs inside the DO's existing `blockConcurrencyWhile` on admission and on the alarm. No separate throughput target. The write budget stays in P3.11.

**Constraints**: Do not modify `packages/vendor-contracts`. Do not rewrite the consumed admission answer or the clinic denial codes (rule S7). Do not edit `VendorEntrypoint.grant` or `coverClinic()`. Do not implement reversal ends (P3.7) or fallback reads of `hard_stop_at` (P3.9). Entitlement tables and `/control/*` stay until P3.10. `term.grace_cap` is not overwritten with the numeric ceiling. The boundary compares stored instants to `clockNowIso`, not to the alarm's scheduled timestamp. `setAlarm` runs only when the next instant differs from `hot.next_alarm_at`.

**Scale/Scope**: Size M (rule S3, 20–32 tasks, 2 user stories, 8 E2E ids, 10 functional requirements). Implied task count is 20.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: DO SQLite and D1 on the existing AI Platform worker. No clinic write and no second service. The same boxes hold after those artifacts.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One clinic's paid term ends, enters grace, or accepts a renewal on that clinic's own calendar (spec §4.1, 02 §7 principle I). The allowance and the grace cap are that term's. No second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. The next boundary is a DO alarm, and a missed alarm is applied on the next admission (02 §7 principle I). No Kubernetes and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 and DO SQLite only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 unique keys and the DO's serialized writer. Boundary steps run inside `blockConcurrencyWhile`. `coverage_event` keeps `INSERT OR IGNORE` on event id. `coverage_mirror` is replaced only by a higher `(binding_epoch, clinic_seq)`. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `POST /v1/requests` still requires the issuer token (spec §4.1). A renewal still enters through the consumed `grant` method. A lapsed admission returns the existing `coverage_lapsed` denial. No hard delete of ledger or event rows.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). Grace and lapse refuse or allow the AI request inline. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/069-abo-p3-5-term-boundaries-grace-renewal/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   └── coverage-snapshot-grace-lapse.md
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). `data-model.md` records the entities in spec §3.2. `contracts/` freezes clinic states `grace` / `lapsed` and reasons `expired` / `grace_exhausted` on the snapshot.

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — the boundary loop on the alarm and on admission, grace and lapse, renewal during grace and after lapse, scaled windows, and mirror `hard_stop_at`.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/term-boundaries-grace-renewal.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.5-01 | `coverClinic()` → `vendorCall` `grant` while T1 is active → `setTestClock` to T1 `ends_at` → `runDurableObjectAlarm` → `GatewayObject.alarm` → `applyDueBoundaries` → successor `term` row |
| E2E-P3.5-02 | `coverClinic()` once → `setTestClock` to `ends_at` → `runDurableObjectAlarm` → `POST /v1/requests` → `admissionRPC` step 3 then step 5 → `setTestClock` to `grace_ends_at` → `runDurableObjectAlarm` → `POST /v1/requests` → `coverage_lapsed` |
| E2E-P3.5-03 | `coverClinic()` → boundary into grace → `POST /v1/requests` until the grace allowance is taken → next `POST` → `coverage_lapsed` reason `grace_exhausted` |
| E2E-P3.5-04 | `coverClinic()` into grace → `setTestClock` to day 3 → `coverClinic()` → `applyGrantRPC` grace branch → new `term.calendar_start` |
| E2E-P3.5-05 | `coverClinic()` → clock through grace to lapse → `setTestClock` two months later → `coverClinic()` → `applyGrantRPC` no-coverage branch |
| E2E-P3.5-06 | `setTestClock` past `grace_ends_at` with no `runDurableObjectAlarm` → `POST /v1/requests` → `admissionRPC` step 3 → `coverage_lapsed` |
| E2E-P3.5-07 | `DURATION_SCALE=staging` on the worker binding → `coverClinic()` → `setTestClock` to the scaled `ends_at` and `grace_ends_at` → `runDurableObjectAlarm` and `POST /v1/requests` |
| E2E-P3.5-08 | `runDurableObjectAlarm` on activate, end, and grace start → D1 `coverage_event` → `coverage_mirror.hard_stop_at` |

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── coverage/
│   │   └── calendar.ts
│   ├── quota-do/
│   │   ├── coverage.ts
│   │   └── index.ts
│   └── worker.ts
└── test/
    └── system/
        ├── harness.ts
        └── term-boundaries-grace-renewal.system.test.ts
```

**Structure Decision**: Source stays the existing Worker. The boundary loop lives in `src/quota-do/coverage.ts` and is called from admission step 3 in `src/quota-do/index.ts` and from the start of the existing alarm ship. `src/coverage/calendar.ts` stays as P3.3 left it; grace days and successor end dates call `addDuration`. `coverClinic()` stays in `test/system/harness.ts`. No new source file.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Admission answer (reservation, `term_id`, snapshot, band) | `admitOnHotRow` in `ai-platform/src/quota-do/index.ts` returns the admitted object. `runAdmission` / `mapDoOutcome` in `ai-platform/src/admission/index.ts` map it. Frozen contract: `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/admission-answer.md`. This unit does not add or rename those fields. Grace admission still returns that object with the grace term's `term_id`. |
| Clinic denial codes of 04 §4.2 | `coverage_lapsed` with `coverage_reason`, mapped in `ai-platform/src/admission/index.ts` and written on the HTTP body by `ai-platform/src/errors.ts`. Frozen contract: `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/clinic-denial-codes.md`. `coverageLapseReason` already returns `expired` and `grace_exhausted` when the last ended term has those `end_reason` values. This unit does not add a denial code. |
| CP-B | Checkpoint after P3.4: a paid grant over `VendorEntrypoint.grant` (`coverClinic()` in `ai-platform/test/system/harness.ts`) then an issuer token completes `POST /v1/requests`. This unit calls that helper and does not change it. |

## Files

| File | FR |
| --- | --- |
| `specs/069-abo-p3-5-term-boundaries-grace-renewal/data-model.md` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-010 |
| `specs/069-abo-p3-5-term-boundaries-grace-renewal/contracts/coverage-snapshot-grace-lapse.md` | FR-003, FR-004, FR-005, FR-010 |
| `specs/069-abo-p3-5-term-boundaries-grace-renewal/quickstart.md` (implement, after verification) | FR-001 through FR-010 |
| `ai-platform/src/quota-do/coverage.ts` | FR-001, FR-002, FR-003, FR-004, FR-006, FR-007, FR-009, FR-010 |
| `ai-platform/src/quota-do/index.ts` | FR-001, FR-003, FR-004, FR-005, FR-008 |
| `ai-platform/src/worker.ts` | FR-001, FR-008, FR-009 |
| `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` | FR-001 through FR-010 |

`src/coverage/calendar.ts`, `src/vendor/entrypoint.ts`, `src/admission/index.ts`, `src/errors.ts`, `test/system/harness.ts`, and `packages/vendor-contracts/**` stay as they are. `grant_void` is not added (reversals are P3.7). The existing outbox kinds `coverage_event`, `grant_ledger`, `usage_adjustment`, and `alert` stay. Fallback reads of `hard_stop_at` stay in P3.9.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` under H-AP (`vitest.workers.config.ts`). Each test calls the entry point below and fails while the boundary transition it names is absent. `coverClinic()` is the paid-grant helper in `test/system/harness.ts`. It already sends `grace: { days: 7, cap_rule: "proportional" }` and calls `vendorCall` `grant`, then `runDurableObjectAlarm`. `test/system/harness.ts` and `coverClinic()` stay unchanged.

Each test's first `coverClinic()` registers the harness operator. `bootstrapHarnessOperatorCredential` calls `setTestClock(activates_at)`, and `activates_at` is the clock at registration plus 24 hours. The grant's `nowIso` is that `activates_at`. Before that first `coverClinic()`, the test sets the clock to the worked grant instant minus 24 hours, so `activates_at` and `nowIso` are the worked instant in the table below (1 Mar 10:00, 1 Feb 10:00, 1 May 14:00, and the staging start). A later `setTestClock` in the same test is the instant named in the scenario. The credential already exists, so bootstrap does not move the clock again. `mintAat` sets `exp` to the harness clock plus 300 seconds. After any `setTestClock` that passes that expiry, the test calls `mintAat` again and sends the new token on `POST /v1/requests`. A 401 from the previous token is not a coverage result. Term and `hot` rows are read with `runInDurableObject`, the same way `admission-settlement.system.test.ts` reads them. No `sleep` over 2 s. No ABO worker is constructed.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.5-01 | H-AP | Title `E2E-P3.5-01 A9 renewal paid five days early queues and activates at the old end`. Clock at 1 Mar 10:00, `coverClinic()` once. Clock at 27 Mar, `coverClinic()` again. T2 is `queued`. T1 `allowance` and `used` are unchanged. Clock at 1 Apr 10:00, `runDurableObjectAlarm`. T1 is `ended` with `end_reason` `expired`. T2 is `active` with `starts_at` and `calendar_start` 1 Apr 10:00, `ends_at` 1 May 10:00, and a full allowance. |
| E2E-P3.5-02 | H-AP | Title `E2E-P3.5-02 A10 unpaid end enters grace then lapses as expired`. `coverClinic()` once. Clock at `ends_at`, `runDurableObjectAlarm`. State is grace. `POST /v1/requests` inside the grace cap is admitted and `usage_event.term_id` is that same term. Clock at `grace_ends_at`, `runDurableObjectAlarm`, then `POST /v1/requests` is 403 `coverage_lapsed` with `coverage_reason` `expired`. The test file does not start an ABO worker. |
| E2E-P3.5-03 | H-AP | Title `E2E-P3.5-03 The reservation that takes the last grace credit ends grace_exhausted`. `coverClinic()`, then the boundary loop into grace. `POST /v1/requests` until a reservation takes the last of the grace allowance. That term is `ended` with `end_reason` `grace_exhausted`. The next `POST` is 403 `coverage_lapsed` with `coverage_reason` `grace_exhausted`. |
| E2E-P3.5-04 | H-AP | Title `E2E-P3.5-04 A grant on day three of grace keeps the old calendar`. T1 `ends_at` is 1 Mar 10:00 and the clinic is in grace. Clock at 4 Mar, `coverClinic()`. The new term is `active` with `calendar_start` 1 Mar 10:00 and `ends_at` 1 Apr 10:00. T1 is `ended` with `end_reason` `renewed` and `used_final` still holding the grace usage. |
| E2E-P3.5-05 | H-AP | Title `E2E-P3.5-05 A11 a lapsed clinic paid two months later starts now`. T1 ends 1 Mar 10:00, grace runs to 8 Mar 10:00, clinic is `lapsed`. Clock at 1 May 14:00, `coverClinic()`. The new term is `active` from 1 May 14:00 to 1 Jun 14:00. |
| E2E-P3.5-06 | H-AP | Title `E2E-P3.5-06 A skipped alarm is applied by the next admission`. Clock moves past `grace_ends_at` with no `runDurableObjectAlarm`. The next `POST /v1/requests` is 403 `coverage_lapsed` with `coverage_reason` `expired`. |
| E2E-P3.5-07 | H-AP | Title `E2E-P3.5-07 Staging DURATION_SCALE compresses the month and the grace window`. Set `DURATION_SCALE` to `staging` on the worker binding the way `paid-grant-coverage.system.test.ts` does, and restore it afterwards. A monthly term's `ends_at` is 30 minutes after `calendar_start`. After the end boundary, `grace_ends_at` is 7 minutes after `ends_at`. `runDurableObjectAlarm` and `POST /v1/requests` see those instants. |
| E2E-P3.5-08 | H-AP | Title `E2E-P3.5-08 Activate, end, and grace start ship events and hard_stop_at`. After `runDurableObjectAlarm` on a grant that activates, on an end with a successor, and on a grace start, `coverage_event` has `term_activated`, `term_ended`, and `grace_started`. `coverage_mirror.hard_stop_at` equals `ends_at` while active and `grace_ends_at` while in grace. |

## Sequencing

Tests are written and observed failing before the boundary loop applies these transitions. Each step is one task. The implied count is 20, inside size M (20–32).

1. Add `test/system/term-boundaries-grace-renewal.system.test.ts` with E2E-P3.5-01. Run the unit command. It fails because the alarm at T1 `ends_at` does not end T1 `expired` and activate T2 from that instant.
2. Add E2E-P3.5-02. The run fails because an unpaid `ends_at` does not enter grace, and `grace_ends_at` does not lapse with `coverage_lapsed` reason `expired`.
3. Add E2E-P3.5-03. The run fails because taking the last grace credit does not end the term `grace_exhausted`.
4. Add E2E-P3.5-04. The run fails because a second `coverClinic()` during grace does not leave T1's grace usage on T1 with the new `calendar_start` at T1 `ends_at`.
5. Add E2E-P3.5-05. The run fails because a grant after lapse does not open a term from the payment instant.
6. Add E2E-P3.5-06. The run fails because a `POST` after a skipped alarm still treats the clinic as inside grace.
7. Add E2E-P3.5-07. The run fails because the staging scale does not place the monthly end at 30 minutes and grace at 7 minutes.
8. Add E2E-P3.5-08. The run fails because `grace_started` is absent and `coverage_mirror.hard_stop_at` is null.
9. Add `applyDueBoundaries` in `src/quota-do/coverage.ts`. Call it from admission step 3 in place of the P3.5 no-op, inside the existing `blockConcurrencyWhile`, before the refusal order. When the active term's `ends_at` is due and a `queued` term exists, end the active term `expired` and activate the successor with `starts_at` and `calendar_start` equal to that `ends_at`, `ends_at` from `addDuration`, and `hot.used` reset to 0. Emit `term_ended` then `term_activated` through the existing `coverage_event` outbox. Repeat until no transition applies. The alarm path still skips this, so E2E-P3.5-01 still fails when only the alarm runs.
10. Call `applyDueBoundaries` at the start of `shipCoverageOutboxAlarm`, before outbox rows are read, then ship as today. `GatewayObject.alarm` already calls that function, so one `runDurableObjectAlarm` both applies the boundary and ships the events. `setAlarm` is still unchanged.
11. When `ends_at` is due and no `queued` term exists, set the term `state` to `grace`, set `grace_ends_at` to `addDuration(ends_at, "day", grace_days, scale)`, set `hot.grace_base_used` to `hot.used`, and emit `grace_started`. Leave `term.grace_cap` as `proportional`. The numeric ceiling is `ceil(allowance × grace_days ÷ unscaled term days)` and the grace allowance is `min(allowance − grace_base_used, ceiling)`, fixed at this moment. A later admission inside that allowance reserves against this same `term_id`. An `exhausted` term does not enter grace.
12. When the grace term's `grace_ends_at` is due, set it `ended` / `expired`, clear `hot.active_term_id`, and let step 4 return the existing `coverage_lapsed` outcome with reason `expired`. The same loop lapses immediately if the clock is already past both `ends_at` and `grace_ends_at`.
13. In `admitOnHotRow`, after a grace reservation, if `used + reserved − grace_base_used` reaches the grace allowance from step 11, end that term `grace_exhausted` in the same admission, clear `hot.active_term_id`, and emit `term_ended`. The next admission returns `coverage_lapsed` with reason `grace_exhausted`.
14. `buildCoverageSnapshot` sets `state` `grace` with `reason` `none` and the grace term in `term` while grace is running, and `state` `lapsed` with `reason` `expired` or `grace_exhausted` and `term` null after those ends. `mirrorFromSnapshot` writes `hard_stop_at` from `term.ends_at` when `state` is `active` and from `term.grace_ends_at` when `state` is `grace`. A lapsed replace keeps the `hard_stop_at` already stored on that mirror row.
15. `computeNextAlarmAt` takes the grace term's `grace_ends_at` as well as the active term's `ends_at`, and the pending-outbox instant when the outbox is non-empty. `syncAlarm` calls `setAlarm` only when that instant differs from `hot.next_alarm_at`. Drop the `immediate` bypass that calls `setAlarm` when the instant is unchanged.
16. On the existing grace branch of `applyGrantRPC`, set the grace term's `used_final` to `hot.used` and set `hot.grace_base_used` to 0 before `hot.used` resets to 0. Leave `calendar_start` and `starts_at` at the grace term's `ends_at`, and leave the no-coverage branch that starts a term at `nowIso`.
17. In `GatewayObject.fetch`, set admission `durationScale` from `env.DURATION_SCALE === "staging"` before `admissionRPC`. Pass that same scale into `shipCoverageOutboxAlarm` from `alarm()`. Do not edit `durationScaleFromEnv` or `VendorEntrypoint.grant`.
18. Re-run the unit command and confirm E2E-P3.5-01 through E2E-P3.5-08 pass together. This step may edit `test/system/term-boundaries-grace-renewal.system.test.ts` only for the 24-hour pre-clock before each test's first `coverClinic()` and for reminting the AAT after a later `setTestClock`, as Test Layout states. It does not edit `test/system/harness.ts` or `coverClinic()`.
19. Run `cd ai-platform && npm test && npm run test:e2e`. Earlier suites stay green (rule S2). Change an assertion only when this unit's boundary made that older expectation wrong.
20. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
