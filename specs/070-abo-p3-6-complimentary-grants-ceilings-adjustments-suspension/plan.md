# Implementation Plan: Complimentary grants, ceilings, term adjustments and suspension

**Branch**: `ai/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.6 lets an operator grant a complimentary term inside the ceiling policy, adjust the active term, and suspend or inspect a clinic. It is phase P3, size M, **Depends** P3.5, in parallel with P3.9 and P4.x.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. `validateGrantEnvelope` already accepts `complimentary`, `term_adjustment`, `day` duration, and a `ceiling_override` key when `evidence.approvals` has at least two elements. Dates use the existing `addDuration` in `ai-platform/src/coverage/calendar.ts`. HP checks use the existing `verifyHpAccess` and `runHpAssertionChecks` in `ai-platform/src/vendor/entrypoint.ts`. Tests use `coverClinic`, `vendorCall`, `setTestClock`, `runDurableObjectAlarm`, `mintAat`, `getCapabilities`, and `invoke` from `ai-platform/test/system/harness.ts`. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`.

**Storage**: New D1 table `ceiling_policy` (03 §3.2). Existing per-clinic DO SQLite tables `hot`, `term`, `grant`, and `outbox`. Existing D1 `grant_ledger`, `coverage_event`, `coverage_mirror`, `plan_version`, `assertion_used`, and `platform_alert`. `hot.suspended` is already on the row. No new column on `grant_ledger`. The window sum reads DO `grant` rows, which store `applied_at`, `kind`, `source_kind`, and the envelope (`duration`, `adjustment.extend_days`, `allowance_credits`). `grant_ledger` is the shipped mirror and does not store those day or allowance figures.

**Testing**: H-AP. E2E-P3.6-01 through E2E-P3.6-09 live in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the complimentary path exists. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on `npm test` and `npm run test:e2e` (rule S2). Time moves with `setTestClock` and `runDurableObjectAlarm` (rule V4). No local scenario sleeps more than 2 s. The harness does not start an ABO worker. Alerts are the captured `send_email` bodies from `getCapturedVendorEmails` (rule V6).

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Live entries are `VendorEntrypoint` methods over the H-AP self service binding (`vendorCall` / `env.VENDOR`) and `SELF.fetch` `GET /v1/capabilities` and `POST /v1/requests`. Paid setup is the existing `coverClinic()` grant. Production wrangler has no clock control.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). Ceiling checks and grant application run inside the DO's existing `blockConcurrencyWhile`. No separate throughput target. The write budget stays in P3.11.

**Constraints**: Do not modify `packages/vendor-contracts`. Do not rewrite snapshot states `grace` / `lapsed` or reasons `expired` / `grace_exhausted` (rule S7). Do not change `coverClinic()`'s paid envelope. Do not add a void path (P3.7), a console relay (P4.8), or a kill-switch change (P3.10). Entitlement, plan, and invoice tables and `/control/*` stay until P3.10. The existing DO kind `inspect` stays the quota inspect. Complimentary `month` counts as `count × 31` days toward both day ceilings (03 §3.2); `ends_at` still uses `addDuration`. A queued complimentary term has no `calendar_start` at validation. Paid AL-11 email bodies stay the object E2E-P3.3-08 already asserts, without an `attention` field.

**Scale/Scope**: Size M (rule S3, 20–32 tasks, 3 user stories, 9 E2E ids, 11 functional requirements). Implied task count is 23.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: D1 and DO SQLite on the existing AI Platform worker. No clinic write and no second service. The same boxes hold after those artifacts.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One operator grants one clinic complimentary days or months inside a per-grant and per-clinic 90-day ceiling, adjusts that clinic's active term, or suspends that clinic (spec §4.1, 02 §7 principle I). The unit adds no second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. Alerts leave through the existing `send_email` binding. The outbox ship stays the existing DO alarm (02 §7 principle I). No Kubernetes and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 and DO SQLite only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 unique keys and the DO's serialized writer. Grant, ceiling, suspend, resume, and inspect run inside `blockConcurrencyWhile`. `ceiling_policy.version` is the primary key. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Complimentary grants and `setCeilingPolicy` are class HP and carry an assertion (spec §4.1, 04 §1.3). `suspend`, `resume`, and `inspectCoverage` are class H and take `access_jwt`. A ceiling override needs a second assertion. `ceiling_policy` stores `set_by` and `assertion_sha256`. `control_audit` records the operator action. No hard delete of ledger or policy rows.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). A suspended clinic is refused inline. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── complimentary-and-adjustment-grant.md
│   ├── ceiling-policy.md
│   └── suspend-resume-inspect.md
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). `data-model.md` records the entities in spec §3.2. `contracts/` freezes the complimentary and adjustment grant results, `ceiling_policy` / `setCeilingPolicy`, and `suspend` / `resume` / `inspectCoverage`.

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — complimentary grants, ceiling policy and the 90-day window, ceiling override, term adjustment, suspend and resume, and inspectCoverage.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/complimentary-grants-ceilings.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.6-01 | `coverClinic()` → `vendorCall("grant")` complimentary 14-day HP → `applyGrantRPC` queues the term → `runDurableObjectAlarm` → `raiseAl11GrantFromOutbox` → `getCapturedVendorEmails` |
| E2E-P3.6-02 | `vendorCall("grant")` 365-day → DO ceiling check `exceeds_ceiling` → same grant with `ceiling_override` and a second assertion → `applied` + AL-12 → same assertion reused as the override → `rejected` |
| E2E-P3.6-03 | two `vendorCall("grant")` 31-day calls, then a 1-day grant → `exceeds_ceiling`; a second org's `term_adjustment` `extend_days` is inside the same day sum |
| E2E-P3.6-04 | `vendorCall("grant")` with `reason` omitted, then with `operator_email` omitted → `rejected` `bad_request` |
| E2E-P3.6-05 | `vendorCall("grant")` `term_adjustment` +7 days, then a negative `extend_days`, then `adjustment.plan` → `runDurableObjectAlarm` → `getCapabilities` |
| E2E-P3.6-06 | `vendorCall("suspend")` → `invoke` `POST /v1/requests` 403 `suspended` → `setTestClock` to `ends_at` → `runDurableObjectAlarm` still 403 `suspended` → `vendorCall("resume")` → `invoke` 200 |
| E2E-P3.6-07 | complimentary 14-day `vendorCall("grant")` on an uncovered org → paid `vendorCall("grant")` queues |
| E2E-P3.6-08 | `vendorCall("inspectCoverage")` with an Access JWT → DO terms, grants, reservations → same call without the JWT → `rejected` |
| E2E-P3.6-09 | `vendorCall("setCeilingPolicy")` twice with one assertion → `vendorCall("grant")` 30-day `day` → `applied` |

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261006130000_ceiling_policy.sql
├── src/
│   ├── alert/
│   │   └── index.ts
│   ├── quota-do/
│   │   └── coverage.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   └── worker.ts
└── test/
    └── system/
        ├── harness.ts
        └── complimentary-grants-ceilings.system.test.ts
```

**Structure Decision**: Source stays the existing Worker. Complimentary apply, the ceiling sum, term adjustment, the suspend flag, and the coverage inspect live in `src/quota-do/coverage.ts`. `VendorEntrypoint` in `src/vendor/entrypoint.ts` gains the complimentary `grant` branch and `setCeilingPolicy`, `suspend`, `resume`, and `inspectCoverage`. `src/worker.ts` dispatches the new DO kinds and the AL-12 and AL-19 alarm emails. `src/alert/index.ts` sends those two codes. `test/system/harness.ts` adds the method names and exports the cover-clinic signer. No new source file under `src/`.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Clinic states `grace` / `lapsed` and reasons `expired` / `grace_exhausted` in the snapshot | `buildCoverageSnapshot` and `lapsedSnapshotReason` in `ai-platform/src/quota-do/coverage.ts`. Frozen contract: `specs/069-abo-p3-5-term-boundaries-grace-renewal/contracts/coverage-snapshot-grace-lapse.md`. `suspend` and `resume` return that same snapshot object. This unit does not add or rename `state` or `reason`. |

## Files

| File | FR |
| --- | --- |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/data-model.md` | FR-003, FR-007, FR-008, FR-011 |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/complimentary-and-adjustment-grant.md` | FR-001, FR-002, FR-004, FR-005, FR-006, FR-007, FR-009 |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/ceiling-policy.md` | FR-003, FR-004, FR-005, FR-011 |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/suspend-resume-inspect.md` | FR-008, FR-010 |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/quickstart.md` (implement, after verification) | FR-001 through FR-011 |
| `ai-platform/migrations/20261006130000_ceiling_policy.sql` | FR-003, FR-011 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 |
| `ai-platform/src/quota-do/coverage.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008, FR-009, FR-010 |
| `ai-platform/src/worker.ts` | FR-002, FR-004, FR-008, FR-010 |
| `ai-platform/src/alert/index.ts` | FR-004, FR-008 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-003, FR-008, FR-010 |
| `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` | FR-001 through FR-011 |

`src/quota-do/index.ts`, `src/admission/index.ts`, `src/errors.ts`, `src/capability/index.ts`, `src/coverage/calendar.ts`, and `packages/vendor-contracts/**` stay as they are. `coverClinic()` stays. The existing DO kind `inspect` stays. `grant_void` is not added.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` under H-AP (`vitest.workers.config.ts`). Each test calls the entry point below and fails while the behavior it names is absent. `coverClinic()` remains the paid-grant helper. `harness.ts` adds `setCeilingPolicy`, `suspend`, `resume`, and `inspectCoverage` to the `VendorMethod` union, and exports `coverClinicSigner()` returning the `{ signerCredentialId, signerAuthenticator }` already stored by the cover-clinic bootstrap. `coverClinic()`'s paid envelope and its grant call stay unchanged.

A complimentary or adjustment `vendorCall("grant")` passes `accessJwt`, `signer_credential_id`, `operation`, and `assertion` from `coverClinicSigner()`, using `encodeVendorAssertion` the way `coverClinic()` signs `publishPlanVersion`. `operation.op` is `grant`. `operation.params` is `{ contract_version, access_jwt, envelope }`. `actor_email` is `VENDOR_OPERATOR_EMAIL`. The envelope `source` is `{ kind: "complimentary", ref, operator_email, reason }` with `operator_email` equal to that actor. `placement` is `queue`. `grace` is `{ days: 7, cap_rule: "proportional" }`. `evidence.approvals` is one stub `{ credential_id, assertion: "stub" }` unless `ceiling_override` is present, in which case the package requires two stubs. `allowance_credits` is the cover plan's `max_allowance_per_month` except where a row below says otherwise. After `coverClinic()`, do not move the clock backward of the credential's `activates_at`. `mintAat` is reminted after any `setTestClock` that passes its `exp`. No `sleep` over 2 s. No ABO worker is constructed.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.6-01 | H-AP | Title `E2E-P3.6-01 A20 14-day complimentary grant to a paying clinic queues after current coverage`. `coverClinic()` once. HP complimentary grant, unit `day`, count 14, with `operator_email` and `reason`. Result `applied`. The new `term` is `queued` and the paid term stays `active`. `runDurableObjectAlarm`. One captured email has `code` `AL-11`, `attention` true, and `operation.params.envelope.source` carrying that operator and reason. A second alarm does not send another AL-11 for that `grant_id`. |
| E2E-P3.6-02 | H-AP | Title `E2E-P3.6-02 A27 365-day complimentary grant is exceeds_ceiling unless a second assertion overrides it`. A 365-day complimentary grant is `rejected` with `code` `exceeds_ceiling`. The same envelope plus `ceiling_override` set to a second assertion, and two approval stubs, is `applied`, and the alarm email list contains one AL-12. A third call that puts the grant assertion in `ceiling_override` is `rejected`. |
| E2E-P3.6-03 | H-AP | Title `E2E-P3.6-03 90-day window accepts 31 plus 31 days and rejects a further day`. On one org, two 31-day complimentary grants are `applied`. A further 1-day grant is `rejected` with `exceeds_ceiling`. On a second org, a 31-day complimentary grant is `applied`, then `term_adjustment` `extend_days` 31 is `applied`, then a 1-day grant with `allowance_credits` 1 is `rejected` with `exceeds_ceiling`. |
| E2E-P3.6-04 | H-AP | Title `E2E-P3.6-04 Missing reason or operator_email is rejected`. One complimentary envelope omits `reason`. Another omits `operator_email`. Each result is `rejected` with `code` `bad_request`. |
| E2E-P3.6-05 | H-AP | Title `E2E-P3.6-05 term_adjustment moves ends_at later, rejects a shortening, and shows a plan change`. `coverClinic()` plus `newClinic()`. `extend_days` 7 makes `ends_at` seven days later. A negative `extend_days` is `rejected`. `publishPlanVersion` writes `live-monthly` version 2 with capabilities `["clinic.plan_changed"]`. The adjustment `plan` selects that version. After `runDurableObjectAlarm` and `clearConfigCache`, `getCapabilities` no longer lists `clinic.visit_summary`. |
| E2E-P3.6-06 | H-AP | Title `E2E-P3.6-06 Suspend returns 403 suspended before any other refusal and resume admits`. `setupPromotedFakePolicy`. `suspend` then `invoke` is 403 `suspended`. `setTestClock` to the active term's `ends_at` and `runDurableObjectAlarm`. The term has entered grace, and `invoke` is still 403 `suspended`. `resume`, then `invoke` is 200. The alarm emails include one AL-19 for suspend and one AL-19 for resume. |
| E2E-P3.6-07 | H-AP | Title `E2E-P3.6-07 A19 a 14-day trial then a paid grant queues the paid term`. No `coverClinic()` before the trial. Complimentary 14-day grant is `applied` and the term is `active` with `ends_at` 14 days after `calendar_start`. The following paid `vendorCall("grant")` is `applied` and that term is `queued`. The active term's interval does not overlap the queued term. |
| E2E-P3.6-08 | H-AP | Title `E2E-P3.6-08 inspectCoverage returns the ledger and rejects a missing Access JWT`. After `coverClinic()`, `inspectCoverage` with an Access JWT returns `ok` and `detail` JSON whose `terms`, `grants`, and `reservations` match the DO rows for that org. The same call with no `access_jwt` is `rejected`. |
| E2E-P3.6-09 | H-AP | Title `E2E-P3.6-09 Pilot grant of 30 days is accepted under the default policy`. `setCeilingPolicy` with the launch ceilings and one assertion returns `ok` and `detail.version` 2. The same assertion again returns `ok` with that same version and does not insert a row. A complimentary grant, unit `day`, count 30, is `applied`. |

## Sequencing

Tests are written and observed failing before complimentary grants, ceilings, adjustments, and suspension exist. Each step is one task. The implied count is 23, inside size M (20–32).

1. Add `test/system/complimentary-grants-ceilings.system.test.ts` with E2E-P3.6-01. Run the unit command. It fails because a complimentary grant is `rejected` with `unit_not_allowed` and no queued term or attention AL-11 is produced.
2. Add E2E-P3.6-02. The run fails because a 365-day grant is not `exceeds_ceiling` and a second assertion does not apply it.
3. Add E2E-P3.6-03. The run fails because the third day-grant is not `exceeds_ceiling` from a 62-day window.
4. Add E2E-P3.6-04. The run fails because a missing `reason` or `operator_email` is `unit_not_allowed`, not `bad_request`.
5. Add E2E-P3.6-05. The run fails because `extend_days` 7 does not move `ends_at` and `/v1/capabilities` still lists `clinic.visit_summary`.
6. Add E2E-P3.6-06. The run fails because `vendorCall("suspend")` is not a method, so the POST is not 403 `suspended`.
7. Add E2E-P3.6-07. The run fails because the trial grant is not `applied` and the paid term is not queued after it.
8. Add E2E-P3.6-08. The run fails because `inspectCoverage` is not a method.
9. Add E2E-P3.6-09. The run fails because `setCeilingPolicy` is not a method and a 30-day complimentary grant is not `applied`.
10. Add `ai-platform/migrations/20261006130000_ceiling_policy.sql` and `readCurrentCeilingPolicy` in `src/vendor/entrypoint.ts`. The migration creates the table and inserts version 1 with the launch numbers, `set_by` `''`, and `assertion_sha256` `''`. The reader returns the greatest `version`.
11. On the paid `grant` path, compare `grace.days` and `grace.cap_rule` to `max_paid_grace_days` and `paid_cap_rule` from that row. The launch row is 7 and `proportional`, so a paid grant that passes today still passes and `exceeds_plan_bound` still fires for the same illegal grace.
12. Add `setCeilingPolicy` on `VendorEntrypoint`. Class HP. On `ok`, insert the next version (2 after the seed), set `set_by` to the Access email and `assertion_sha256` to the assertion challenge hash, and return `detail` as the JSON row. When that challenge hash is already stored on a row, return `ok` with that row and do not insert. This lookup happens when `assertion_used` would otherwise reject the replay.
13. On `grant`, when `source.kind` is `complimentary` or the kind is `term_adjustment`, require the Access JWT and the HP assertion over `{ contract_version, access_jwt, envelope }`. A missing `operator_email` or `reason` on a non-paid source is `rejected` with `bad_request` and empty `detail`. `placement` `immediate` stays `placement_not_supported`. A paid source on `term_adjustment` is `rejected` with `bad_request`. Leave the paid `abo_kid` path as it is.
14. In `applyGrantRPC`, a complimentary `term` uses the envelope duration and source. It becomes `active` when no active, grace, or queued term exists, and `queued` otherwise. Idempotent replay by `grant_id` plus `envelope_sha256` returns the stored receipt before `assertion_used` rejects the replay. The AL-11 outbox body is the paid shape plus `attention: true`. `source_kind` and `kind` are stored from the envelope. A `day` count uses `addDuration` of exact days.
15. In that same apply transaction, load the current policy numbers from the request. A complimentary `day` contributes `count` days. A `month` contributes `count × 31` days. Per grant, days must be ≤ `per_grant_max_days` and `allowance_credits` must be ≤ `per_grant_max_allowance_months × plan.max_allowance_per_month`. The window is `window_days × 24` hours ending at this grant's `applied_at`. Sum earlier DO `grant` rows for this clinic whose `applied_at` is inside that span, plus this grant. Complimentary rows contribute their day figure and their `allowance_credits`. `term_adjustment` rows contribute `extend_days` and `add_allowance`. Days must be ≤ `window_max_days`. Credits must be ≤ `window_max_allowance_months ×` the grant's plan max. Otherwise the DO returns `exceeds_ceiling` and writes nothing. The entrypoint maps that to `rejected`.
16. When `ceiling_override` is present, verify a second assertion whose operation is `{ op: "ceiling_override", params: { contract_version, access_jwt, envelope } }` and whose envelope omits `ceiling_override`. The same challenge hash as the grant assertion, or a hash already in `assertion_used`, is `rejected` with `assertion_used`. A valid override skips the ceiling check, applies the grant, and writes an AL-12 outbox body `{ code: "AL-12", org_id, operation: { op: "grant", params: envelope } }` with `alert_key` `AL-12:<grant_id>`.
17. `term_adjustment` updates only the active term. `extend_days` greater than 0 sets `ends_at` to `addDuration(ends_at, "day", extend_days, scale)`. A value that would move `ends_at` earlier is `rejected` with `bad_request` and writes nothing. `add_allowance` adds to `allowance` when present. `plan` replaces `plan_snapshot` from the published `plan_version` row, including `capabilities`. Queued terms are not updated. Idempotent by `grant_id`: the same id returns the first receipt. The apply emits the existing `grant_applied` outbox event so the alarm's mirror write stores the new `term.capabilities`. AL-11 is raised with `attention: true`.
18. `suspend` and `resume` are class H. Each takes `access_jwt`, `org_id`, and `reason`. Suspend sets `hot.suspended` to 1. Resume sets it to 0. Both return `ok` with `detail` the JSON from `buildCoverageSnapshot`. A second call in the same target state returns `ok` and does not emit another alert. The first transition emits AL-19 with `alert_key` `AL-19:suspend:<org_id>` or `AL-19:resume:<org_id>`. Admission already refuses `suspended` before later refusal codes, and `applyDueBoundaries` already runs first, so the calendar still moves while the flag is set. Do not edit `src/quota-do/index.ts`.
19. `inspectCoverage` is class H. With an Access JWT it calls a new DO kind `inspect_coverage` and returns `ok` with `detail` JSON `{ terms, grants, reservations }` from the DO `term` rows, `grant` rows, and parsed `hot.reservations`. A missing Access JWT is `rejected` with `unauthenticated`. Do not change the existing DO kind `inspect`.
20. In `GatewayObject.fetch`, dispatch `suspend`, `resume`, and `inspect_coverage`. In `GatewayObject.alarm`, send AL-12 and AL-19 the way AL-11 is sent, through new raisers in `src/alert/index.ts`. Add the four method names and `coverClinicSigner()` in `test/system/harness.ts`.
21. Re-run the unit command and confirm E2E-P3.6-01 through E2E-P3.6-09 pass together. This step may edit only `test/system/complimentary-grants-ceilings.system.test.ts`.
22. Run `cd ai-platform && npm test && npm run test:e2e`. Earlier suites stay green (rule S2). Change an assertion only when this unit's grant or alert body made that older expectation wrong. The paid AL-11 body must stay without `attention`.
23. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
