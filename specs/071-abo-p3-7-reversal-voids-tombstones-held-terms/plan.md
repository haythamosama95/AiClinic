# Implementation Plan: Reversal voids, tombstones, held terms and operator voids

**Branch**: `ai/071-abo-p3-7-reversal-voids-tombstones-held-terms` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.7 voids a paid term for a reversal, holds and releases queued terms, and lets an operator void a complimentary grant or list grants for one credential. It is phase P3, size M, **Depends** P3.6, in parallel with P3.9 and P4.x.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. ABO checks reuse `verifyGrantSignature`, `canonicalize`, and `sha256Hex`. HP checks reuse `verifyHpAccess` and `runHpAssertionChecks` in `ai-platform/src/vendor/entrypoint.ts`. Receipts reuse the platform key already passed as `platformSigningKeyJson`. Tests use `coverClinic`, `vendorCall`, `mintAat`, `invoke`, `setTestClock`, `runDurableObjectAlarm`, and `inspectCoverage` from `ai-platform/test/system/harness.ts`. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`.

**Storage**: New D1 table `grant_void` (03 §3.2). Existing D1 `grant_ledger` (index `(operator_credential_id, applied_at)` already exists) and `coverage_event`. Existing R2 bucket, new object key `grant-ledger/<grant_id>.void.ndjson` only. Existing per-clinic DO SQLite tables `hot`, `term`, `grant`, and `outbox`. The DO also keeps the reversal and operator receipts it has already returned, so a replay on that installation does not apply twice. No new column on `grant_ledger`. Tombstone calls do not open a DO.

**Testing**: H-AP. E2E-P3.7-01 through E2E-P3.7-09 live in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the void path exists. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on `npm test` and `npm run test:e2e` (rule S2). Time moves with `setTestClock` and `runDurableObjectAlarm` (rule V4). No local scenario sleeps more than 2 s. The harness does not start an ABO worker. A clinic void's D1 row, R2 object, and coverage events are read after `runDurableObjectAlarm`. A tombstone is readable without that alarm.

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Live entries are `VendorEntrypoint` methods over the H-AP self service binding (`vendorCall` / `env.VENDOR`) and `SELF.fetch` `POST /v1/requests`. Paid setup is the existing `coverClinic()` grant. Production wrangler has no clock control.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). Void, release, and list run inside the DO's existing `blockConcurrencyWhile` when a `grant_ledger` row names an installation. Tombstone writes are one D1 insert and one R2 put. No separate throughput target. The write budget stays in P3.11.

**Constraints**: Do not modify `packages/vendor-contracts`. Do not rewrite complimentary or adjustment grant application, ceiling policy, or `suspend` / `resume` / `inspectCoverage` (rule S7). Do not change `coverClinic()`'s paid envelope. Do not follow `origin_grant_id` onto another installation (P3.8). Do not decide the ABO reversal effect, retry a transient void, or raise the ABO reversal alert (P4.5). A `partial` true call writes nothing and raises no platform alert. `/control/*` stays until P3.10. Revoking a credential, revoking Access sessions, and rotating a machine key are not methods this unit adds.

**Scale/Scope**: Size M (rule S3, 20–32 tasks, 3 user stories, 9 E2E ids, 10 functional requirements). Implied task count is 22.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: D1, R2, and DO SQLite on the existing AI Platform worker. No clinic write and no second service. The same boxes hold after those artifacts.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One clinic's paid term is voided when its payment is reversed, a held term can be released, and an operator can void a complimentary term or list grants made with one credential (spec §4.1, 02 §7 principle I). The unit adds no second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. Coverage events leave through the existing DO outbox and alarm (02 §7 principle I). No Kubernetes and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1, R2, and DO SQLite only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 append-only triggers and the DO's serialized writer. `voidForReversal`, `releaseHeld`, and `voidGrant` run inside `blockConcurrencyWhile` when they touch a clinic. `grant_void` is append-only. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `voidForReversal` is class M and ABO-signed (spec §4.1, 04 §1.3). `releaseHeld` and `voidGrant` are class HP and take `access_jwt` and `assertion`. `listGrantsForVoid` is class H and takes `access_jwt`. A bad ABO signature is rejected. `grant_void` is append-only. No hard delete of ledger or void rows.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). After `end_current`, a clinic request is refused inline. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── void-for-reversal.md
│   ├── release-held-and-void-grant.md
│   └── list-grants-for-void.md
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). `data-model.md` records the entities in spec §3.2. `contracts/` freezes `voidForReversal` and the tombstone rule, `releaseHeld` and `voidGrant`, and `listGrantsForVoid`.

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — `voidForReversal` (effects, tombstone, partial rejection, replay), `releaseHeld`, `voidGrant`, and `listGrantsForVoid`.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/reversal-voids-held-terms.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.7-01 | `coverClinic()` → second paid `vendorCall("grant")` → `vendorCall("voidForReversal")` for the active term → `voidForReversal` on `VendorEntrypoint` → DO `void_for_reversal` `end_current` → `inspectCoverage` → `invoke` `POST /v1/requests` |
| E2E-P3.7-02 | `coverClinic()` → queued paid `vendorCall("grant")` → `vendorCall("voidForReversal")` for the queued grant → DO `remove_queued` → `inspectCoverage` |
| E2E-P3.7-03 | `coverClinic()` → `setTestClock` to `ends_at` → `runDurableObjectAlarm` → `vendorCall("voidForReversal")` → DO effect `none` → `runDurableObjectAlarm` → `inspectCoverage` and D1 `grant_void` |
| E2E-P3.7-04 | `vendorCall("voidForReversal")` before any grant → D1 `grant_void` and R2 void object, no `coverage_event` → `vendorCall("grant")` with that id → `rejected` `voided` |
| E2E-P3.7-05 | `end_current` so two terms are `held` → `vendorCall("releaseHeld")` → DO `release_held` activates the first → `vendorCall("releaseHeld")` on the remaining held term re-queues it → `inspectCoverage` |
| E2E-P3.7-06 | complimentary `vendorCall("grant")` then a queued successor → `vendorCall("voidGrant")` → DO `void_grant` → `runDurableObjectAlarm` → `inspectCoverage`, D1 `grant_void`, R2 void object |
| E2E-P3.7-07 | paid grants on `grant_ledger` → `vendorCall("listGrantsForVoid")` |
| E2E-P3.7-08 | `vendorCall("voidForReversal")` → `runDurableObjectAlarm` → replay, conflict, bad signature, `partial` true, `partial` invalid, then the unconsumed `reversal_id` with `partial` false |
| E2E-P3.7-09 | `coverClinic()` → `vendorCall("voidForReversal")` `partial` false → `runDurableObjectAlarm` → D1 `grant_void`, R2 object, `coverage_event` |

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261006140000_grant_void.sql
├── src/
│   ├── quota-do/
│   │   └── coverage.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   └── worker.ts
└── test/
    └── system/
        ├── harness.ts
        └── reversal-voids-held-terms.system.test.ts
```

**Structure Decision**: Source stays the existing Worker. Term effects, the reversed snapshot, `held_count`, and the void receipt live in `src/quota-do/coverage.ts`. `VendorEntrypoint` in `src/vendor/entrypoint.ts` gains `voidForReversal`, `releaseHeld`, `voidGrant`, and `listGrantsForVoid`, and the grant path gains the step-5 tombstone check. `src/worker.ts` dispatches the new DO kinds. The alarm ship in `coverage.ts` writes `grant_void` and the R2 void object for a clinic void. A tombstone is written from the entrypoint because it has no installation. `test/system/harness.ts` adds the method names and an ABO signer for the void body. No new source file under `src/`.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Complimentary and adjustment grant semantics | `applyGrantRPC` and the complimentary / `term_adjustment` branch of `grant` in `ai-platform/src/vendor/entrypoint.ts`, with apply in `ai-platform/src/quota-do/coverage.ts`. Frozen contract: `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/complimentary-and-adjustment-grant.md`. This unit does not change those branches. `voidGrant` is a new method. |
| Ceiling policy | `setCeilingPolicy` and `readCurrentCeilingPolicy` in `ai-platform/src/vendor/entrypoint.ts`. Frozen contract: `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/ceiling-policy.md`. This unit does not change them. |
| `suspend` / `resume` / `inspectCoverage` | `suspend`, `resume`, and `inspectCoverage` on `VendorEntrypoint`, and `suspendResumeRPC` / `inspectCoverageRPC` in `ai-platform/src/quota-do/coverage.ts`. Frozen contract: `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/suspend-resume-inspect.md`. Tests read terms through the existing `inspectCoverage`. This unit does not change those methods. |

## Files

| File | FR |
| --- | --- |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/data-model.md` | FR-002, FR-003, FR-004, FR-005, FR-007, FR-008, FR-009 |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/contracts/void-for-reversal.md` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/contracts/release-held-and-void-grant.md` | FR-007, FR-008, FR-009 |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/contracts/list-grants-for-void.md` | FR-010 |
| `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/quickstart.md` (implement, after verification) | FR-001 through FR-010 |
| `ai-platform/migrations/20261006140000_grant_void.sql` | FR-005, FR-007 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 |
| `ai-platform/src/quota-do/coverage.ts` | FR-002, FR-003, FR-004, FR-007, FR-008, FR-009 |
| `ai-platform/src/worker.ts` | FR-002, FR-003, FR-004, FR-007, FR-008, FR-009 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-008, FR-009, FR-010 |
| `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` | FR-001 through FR-010 |

`src/quota-do/index.ts`, `src/admission/index.ts`, `src/coverage/calendar.ts`, and `packages/vendor-contracts/**` stay as they are. `coverClinic()` stays. Admission already refuses `coverage_lapsed` with `coverage_reason` `reversed` when the last ended term has `end_reason` `reversed`.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` under H-AP (`vitest.workers.config.ts`). Each test calls the entry point below and fails while the behavior it names is absent. `coverClinic()` remains the paid-grant helper. `harness.ts` adds `voidForReversal`, `releaseHeld`, `voidGrant`, and `listGrantsForVoid` to the `VendorMethod` union, and exports `signCoverAbo(body)` using the ABO key `coverClinic()` already registers. `coverClinic()`'s paid envelope and its grant call stay unchanged.

A `voidForReversal` call sends `contract_version`, `grant_id`, `reversal_id`, `reason`, `evidence_sha256`, `partial`, `abo_kid`, and `abo_signature`. `reversal_id` and `evidence_sha256` are 64 lowercase hex characters. `abo_signature` is `signCoverAbo` over `{contract_version, grant_id, reversal_id, reason, evidence_sha256, partial}` (no `abo_kid`, no `abo_signature`). `abo_kid` is the cover-clinic ABO kid. HP calls use `coverClinicSigner()` the way a complimentary grant does: `operation.op` is `releaseHeld` or `voidGrant`, and `operation.params` is `{contract_version, access_jwt, grant_id, reason}`. `actor_email` is `VENDOR_OPERATOR_EMAIL`. After `coverClinic()`, do not move the clock backward of the credential's `activates_at`. `mintAat` is reminted after any `setTestClock` that passes its `exp`. No `sleep` over 2 s. No ABO worker is constructed. `runDurableObjectAlarm` runs before a clinic void's D1, R2, or replay assertion. Tombstone assertions do not wait for an alarm.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.7-01 | H-AP | Title `E2E-P3.7-01 A15 void of the active term holds T2 and refuses coverage_lapsed reversed`. `coverClinic()` once, then a second paid grant so T2 is `queued`. `voidForReversal` for T1's `grant_id` with `partial` false is `applied`. `inspectCoverage` shows T1 `ended` with `end_reason` `reversed` and T2 `held`. `invoke` `POST /v1/requests` is `coverage_lapsed` with reason `reversed`. |
| E2E-P3.7-02 | H-AP | Title `E2E-P3.7-02 void of a queued term removes that term and leaves the active term`. `coverClinic()` plus a queued paid grant. `voidForReversal` for the queued grant removes that term (`ended`, `end_reason` `reversed`). The active term stays `active`. |
| E2E-P3.7-03 | H-AP | Title `E2E-P3.7-03 A17 void of an ended term is recorded only`. `coverClinic()`, advance to `ends_at`, `runDurableObjectAlarm`, so the term has ended `expired`. `voidForReversal` for that grant does not change `end_reason` or any other term. After `runDurableObjectAlarm`, a `grant_void` row exists for that `grant_id`. |
| E2E-P3.7-04 | H-AP | Title `E2E-P3.7-04 void before the grant stores a tombstone and the later grant is voided`. `voidForReversal` for a paid `grant_id` that has no `grant_ledger` row is `applied`. The receipt has `installation_id` and `org_id` `00000000-0000-0000-0000-000000000000`, `ledger_seq` 0, and `term_ids` `[]`. A `grant_void` row and `grant-ledger/<grant_id>.void.ndjson` exist. No `coverage_event` was inserted for that call. A later paid `vendorCall("grant")` with that `grant_id` is `rejected` with `code` `voided`. |
| E2E-P3.7-05 | H-AP | Title `E2E-P3.7-05 releaseHeld re-queues a held term and activates it when nothing is active`. Void the active grant while two terms are queued, so both become `held`. `releaseHeld` on the first held grant makes that term `active`. `releaseHeld` on the second makes that term `queued` at the end, and the first stays `active`. |
| E2E-P3.7-06 | H-AP | Title `E2E-P3.7-06 voidGrant ends an active complimentary term and activates the successor`. A complimentary grant is `active` and a later grant is `queued`. `voidGrant` ends the complimentary term with `end_reason` `voided` and the successor becomes `active`. After `runDurableObjectAlarm`, `grant_void.source` is `operator`, `evidence_sha256` is that call's assertion challenge, and `grant-ledger/<grant_id>.void.ndjson` exists. |
| E2E-P3.7-07 | H-AP | Title `E2E-P3.7-07 listGrantsForVoid lists that credential inside the window`. Two paid grants share `operator_credential_id` `cred-001`, which is not an active operator credential. `listGrantsForVoid` with that id and a window that covers both `applied_at` values is `ok`, `code` empty, envelope `receipt` absent, and `detail` is those rows ordered by `applied_at` then `grant_id`. A window that matches nothing is `ok` with `[]`. A missing bound, a non-timestamp, or `applied_from` greater than `applied_to` is `rejected` with `code` `window_invalid` and empty `detail`. |
| E2E-P3.7-08 | H-AP | Title `E2E-P3.7-08 reversal replay is already_applied, a changed body is conflict, and a rejected call does not consume reversal_id`. After an applied `partial` false void and `runDurableObjectAlarm`, the same `reversal_id`, `grant_id`, `reason`, `evidence_sha256`, and `partial` false is `already_applied` with the original receipt. Changing any one of those four is `conflict` and leaves the stored void unchanged. A bad ABO signature is `rejected` with `code` `bad_signature` and writes nothing. A new `reversal_id` with `partial` true is `rejected` with `code` `partial_void` and writes no row, no R2 object, and no coverage event. A missing or non-boolean `partial` is `rejected` with `code` `partial_invalid` and writes nothing. That unused `reversal_id` then applies with `partial` false. |
| E2E-P3.7-09 | H-AP | Title `E2E-P3.7-09 an applied void writes grant_void, the R2 object, and coverage events`. `coverClinic()`, then `voidForReversal` with `partial` false. After `runDurableObjectAlarm`, D1 has the `grant_void` row (`source` `reversal`, the call's `reason` and `evidence_sha256`), R2 `grant-ledger/<grant_id>.void.ndjson` is one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}`, a `coverage_event` exists, and the receipt's `installation_id` and `org_id` equal that `grant_ledger` row. |

## Sequencing

Tests are written and observed failing before reversal voids, tombstones, held release, and operator voids exist. Each step is one task. The implied count is 22, inside size M (20–32).

1. Add `test/system/reversal-voids-held-terms.system.test.ts` with E2E-P3.7-01. Run the unit command. It fails because `voidForReversal` is not a method, so T2 is not `held` and the clinic request is not `coverage_lapsed` with reason `reversed`.
2. Add E2E-P3.7-02. The run fails because a void of the queued grant does not remove that term.
3. Add E2E-P3.7-03. The run fails because a void of the ended grant is not recorded as `grant_void`.
4. Add E2E-P3.7-04. The run fails because the pre-grant void does not store a tombstone and the later grant is not `rejected` with `voided`.
5. Add E2E-P3.7-05. The run fails because `releaseHeld` is not a method.
6. Add E2E-P3.7-06. The run fails because `voidGrant` is not a method.
7. Add E2E-P3.7-07. The run fails because `listGrantsForVoid` is not a method.
8. Add E2E-P3.7-08. The run fails because a replay is not `already_applied` and `partial` true is not `partial_void`.
9. Add E2E-P3.7-09. The run fails because the applied void does not write the D1 row, the R2 object, and a coverage event.
10. Add `ai-platform/migrations/20261006140000_grant_void.sql`. Columns `grant_id` (primary key), `reason`, `source`, `evidence_sha256`, `at`. `source` is `reversal` or `operator`. Append-only triggers reject update and delete, matching `grant_ledger`.
11. Add `voidForReversal` on `VendorEntrypoint` (class M) and `signCoverAbo` in `test/system/harness.ts`. The signed body is `{contract_version, grant_id, reversal_id, reason, evidence_sha256, partial}`. Verify it with `verifyGrantSignature` and the same `service_key` rules as a paid grant. A bad signature is `rejected` with `bad_signature` and writes nothing. A missing or non-boolean `partial` is `rejected` with `partial_invalid` and empty `detail`, before the signature check, and writes nothing. This step does not apply a void yet.
12. When the signature is valid and a `grant_void` row already exists whose R2 receipt `reversal_id` matches, the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false returns `already_applied` and that receipt. Any difference in those four, including `partial` true, returns `conflict` and writes nothing. When no void is stored, `partial` true returns `rejected` with `partial_void` and empty `detail`, and writes no `grant_void` row, no R2 object, no coverage event, and no tombstone. The platform raises no alert for that rejection. A rejected call does not insert a row, so that `reversal_id` can still be applied with `partial` false.
13. When `partial` is false and no void is stored, and `grant_ledger` has no row for `grant_id`, write the tombstone in the entrypoint. The receipt uses `reversal_id`, nil UUID `00000000-0000-0000-0000-000000000000` for `installation_id` and `org_id`, `ledger_seq` 0, and `term_ids` `[]`. `envelope_sha256` is `sha256Hex` of the canonical signed body. `result` is `applied`. Insert `grant_void` with `source` `reversal` and the call's `reason` and `evidence_sha256`. Put R2 `grant-ledger/<grant_id>.void.ndjson` as one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}` plus a trailing newline. Do not insert `coverage_event` and do not call the DO.
14. On both the paid and complimentary `grant` paths, after the existing validation steps and before `callCoverageDo`, select `grant_void` by `grant_id`. A row means `rejected` with `code` `voided` and empty `detail`. Do not change ceiling checks or complimentary apply.
15. When `grant_ledger` has a row, call DO kind `void_for_reversal` on that row's `installation_id` only. Resolve the term with `origin_grant_id` or `grant_id` equal to the paid `grant_id`. Do not look at another installation. `active` or `grace` is `end_current`: that term becomes `ended` with `end_reason` `reversed` and no grace, and every `queued` term becomes `held`. `queued` or `held` is `remove_queued`: that term becomes `ended` with `end_reason` `reversed` and leaves the queue; other terms stay. `ended` or `exhausted` is `none`: the term row stays as it is. Dispatch the kind from `GatewayObject.fetch`.
16. In `buildCoverageSnapshot`, count `held` terms as `held_count`. `queued_count` stays the `queued` count. When no term is `active` or `grace` and the last ended term has `end_reason` `reversed`, set `state` and `reason` to `reversed`. Leave `expired`, `grace_exhausted`, and `exhausted` as they are. Admission already maps that `end_reason` to `coverage_lapsed` / `reversed`.
17. A clinic void emits coverage events through the existing outbox. `end_current` emits `term_ended`, then `term_held` for each held term, then `grant_voided`. `remove_queued` emits `term_ended`, then `grant_voided`. `none` emits `grant_voided` only. `ledger_seq` is the `clinic_seq` on `grant_voided`. The receipt's `installation_id` and `org_id` are the `grant_ledger` row's ids. `term_ids` contains the ended term for `end_current` and `remove_queued`, and is empty for `none`. The alarm ship writes the `grant_void` row and the R2 void object the same way it writes `grant_ledger`, using `INSERT OR IGNORE` and skipping the R2 put when the object already exists. The DO keeps the receipt by `reversal_id` and returns it on a same-installation replay. `signReceipt` gains a `reversal_id` form. The entrypoint returns that receipt as `applied`.
18. `releaseHeld` is class HP. `operationParamsMatch` expects `{contract_version, access_jwt, grant_id, reason}`. The held term for that `grant_id` becomes `queued` at the next position. If no term is `active`, it becomes `active` with `starts_at` and `calendar_start` set to now. If a term is `active`, it stays `queued`. Emit `term_released`, and `term_activated` when it activates. The receipt uses `grant_id` and the `term_released` event's `clinic_seq` as `ledger_seq`. The same assertion challenge returns that receipt as `already_applied` before `assertion_used` would reject the replay. `releaseHeld` does not write `grant_void`. Dispatch DO kind `release_held`.
19. `voidGrant` is class HP with the same params shape and the same challenge replay. It takes no `evidence_sha256` input. The term that has not ended becomes `ended` with `end_reason` `voided`. If it was `active`, the first `queued` term by `position` becomes `active` with `starts_at` and `calendar_start` set to now. `grant_void.source` is `operator` and `evidence_sha256` is the assertion challenge from `runHpAssertionChecks`. The R2 object and the receipt (`grant_id`, `ledger_seq` of `grant_voided`) ship the same way as a reversal void. Dispatch DO kind `void_grant`.
20. `listGrantsForVoid` is class H and uses the same Access JWT check as `inspectCoverage`. Both `window.applied_from` and `window.applied_to` are required. Each must be a UTC ISO-8601 string ending in `Z` that `Date.parse` accepts, and the parsed `applied_from` must be less than or equal to `applied_to`. Otherwise `rejected` with `window_invalid` and empty `detail`. On success, select `grant_ledger` where `operator_credential_id` equals `credential_id` and `applied_at` is inside the inclusive bounds, ordered by `applied_at` then `grant_id`. Return `ok` with `detail` the JSON array of `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, receipt, applied_at}`, each `receipt` parsed as the stored receipt object. `code` is empty and the envelope `receipt` is absent. An empty array is `ok`. Do not read `operator_credential.status`. Do not change `listGrants`.
21. Re-run the unit command and confirm E2E-P3.7-01 through E2E-P3.7-09 pass together. This step may edit only `test/system/reversal-voids-held-terms.system.test.ts`.
22. Run `cd ai-platform && npm test && npm run test:e2e`. Earlier suites stay green (rule S2). Change an assertion only when this unit's snapshot `held_count` or `reversed` state made that older expectation wrong. A clinic with no held terms still has `held_count` 0. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
