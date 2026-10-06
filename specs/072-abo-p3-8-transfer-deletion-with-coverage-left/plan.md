# Implementation Plan: Transfer, deletion with coverage left, and ledger retention

**Branch**: `ai/072-abo-p3-8-transfer-deletion-with-coverage-left` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.8 moves a clinic's remaining terms to a new installation, holds or retires the binding when that installation is deleted, and keeps the ledger when the installation is purged. It is phase P3, size L, **Depends** P3.7, in parallel with P3.9 (if not yet done) and P4.x.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. HP checks reuse `verifyHpAccess` and `runHpAssertionChecks`. Canonical package bytes reuse `canonicalize` and `sha256Hex`. Transfer receipts reuse `signCompactJws` and `receiptSigningBytes` with `PLATFORM_SIGNING_KEY`. `transfer_id` and new `term_id` values reuse `generateUlid` in `ai-platform/src/trace.ts`. Tests use `coverClinic`, `vendorCall`, `mintAat`, `invoke`, `setTestClock`, `runScheduled`, `runDurableObjectAlarm`, and `inspectCoverage` from `ai-platform/test/system/harness.ts`. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`.

**Storage**: New D1 tables `transfer` and `transfer_step` (03 §3.2). Existing `tenant_binding` (the live-org unique index already allows `held_for_transfer`), `installation` (`status` already accepts `deleted`), `grant_ledger`, `grant_void`, `coverage_event`, and `usage_event`. Existing per-clinic DO SQLite `hot` flags `awaiting_transfer`, `transfer_pending`, and `transferred_out_to`. No new DO column. `grant_ledger` stays append-only; a moved term is a new row with `source_kind` `transfer`.

**Testing**: H-AP. E2E-P3.8-01 through E2E-P3.8-08 live in `ai-platform/test/system/transfer-deletion.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the transfer path exists. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on `npm test` and `npm run test:e2e` (rule S2). Time moves with `setTestClock` and `runScheduled` (rule V4). No local scenario sleeps more than 2 s. AL-11 and AL-18 are the captured `send_email` binding (rule V6). The harness does not start an ABO worker.

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Live entries are `VendorEntrypoint` methods over the H-AP self service binding (`vendorCall` / `env.VENDOR`), `SELF.fetch` `POST /v1/requests` and other clinic `/v1/*` routes (`ai-platform/src/worker.ts`), and `purgeByInstallationId` (`ai-platform/src/retention/index.ts`) reached from `deleteInstallation`. Production wrangler has no clock control. The daily AL-18 repeat uses the existing cron `0 3 * * *`. No new cron.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). Transfer and delete run inside the DO's existing `blockConcurrencyWhile` when they touch a clinic. No separate throughput target. The write budget stays in P3.11.

**Constraints**: Do not modify `packages/vendor-contracts`. Do not rewrite `voidForReversalRPC`, `releaseHeld`, `releaseHeldRPC`, `listGrantsForVoid`, or the tombstone write (rule S7). The saga driver stays in P4.8. Projection handling of `(binding_epoch, clinic_seq)` stays in P5.2. `/control/*` routes stay until P3.10. `handleDelete` on the HTTP control route stays the transitional mark-deleted path those suites already call. `deleteInstallation` is the HP method this unit adds. No ABO worker in these tests.

**Scale/Scope**: Size L (rule S3: 3–4 user stories, one codebase). Four user stories and eight E2E ids. Implied task count is 24. That is under the L band and is not padded (rule S3, plan skill).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The Phase 1 artifact (`data-model.md`) stays on the vendor worker: D1 and DO SQLite on the existing AI Platform worker. No clinic write and no second service. The same boxes hold after that artifact.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One clinic's remaining coverage moves to a new installation, or is held when that installation is deleted with time left, and that clinic's ledger is kept (spec §4.1, 02 §7 principle I). The unit adds no second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. The transfer saga driver is out of scope (P4.8). This unit only records the authorisation and the two steps (02 §7 principle I and the workflow-automation row). No Kubernetes and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 and DO SQLite only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 constraints and the DO's serialized writer. `beginTransfer` retires the source binding and inserts the next epoch in one D1 batch. `grant_ledger`, `grant_void`, and `coverage_event` stay append-only. The live-org unique index stays. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `beginTransfer` and `deleteInstallation` are class HP and take `access_jwt` and `assertion` (spec §4.1, 04 §1.3). `transferOut` and `transferIn` are class M, take `transfer_id`, and require the authorised `transfer` row. An org has at most one binding that is `active` or `held_for_transfer`. Purge does not delete `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, or the installation row.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). After delete with coverage left, a clinic request is refused inline with `coverage_lapsed` and `transfer_pending`. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/072-abo-p3-8-transfer-deletion-with-coverage-left/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). No `contracts/` (the unit row has no Outputs / freezes line). `data-model.md` records the entities in spec §3.2.

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — `beginTransfer`, `transferOut`, `transferIn`, `deleteInstallation`, transfer lineage on the existing void call, and purge retention.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/transfer-deletion.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point to module chain per E2E id (rule S8):

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

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261006150000_transfer.sql
├── src/
│   ├── alert/
│   │   └── index.ts
│   ├── config-cache/
│   │   └── index.ts
│   ├── coverage/
│   │   └── transfer.ts
│   ├── identity/
│   │   └── index.ts
│   ├── quota-do/
│   │   ├── coverage.ts
│   │   └── index.ts
│   ├── retention/
│   │   └── index.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   └── worker.ts
└── test/
    ├── e2e/
    │   └── stage-03-revoke-delete-purge.test.ts
    ├── retention.test.ts
    └── system/
        ├── harness.ts
        ├── lifecycle-interplay.system.test.ts
        └── transfer-deletion.system.test.ts
```

**Structure Decision**: Source stays the existing Worker. `src/coverage/transfer.ts` is the module 04 §6.2 names for binding re-creation, the package, and the two steps. `VendorEntrypoint` gains `beginTransfer`, `transferOut`, `transferIn`, and `deleteInstallation`. DO kinds `transfer_out` and `transfer_in` are dispatched from `GatewayObject.fetch` in `src/worker.ts` and applied in `src/quota-do/coverage.ts`. Admission's `transfer_pending` refusal is in `src/quota-do/index.ts`. Token binding creation stays in `src/identity/index.ts`. Purge stays in `src/retention/index.ts`. The HTTP `handleDelete` and `handleInstallationPurge` routes stay until P3.10. No saga module.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Void methods | `voidForReversal` and `voidGrant` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`. Effects stay in `voidForReversalRPC` and `voidGrantRPC` in `ai-platform/src/quota-do/coverage.ts`. This unit does not change those RPC effects, result codes, or receipts. `voidForReversal` keeps class M, the same signed body, tombstone-when-no-ledger-row, and `partial` handling. The lineage this unit adds is the installation chosen before the existing RPC: the latest `grant_ledger` row whose `grant_id` or `origin_grant_id` is the paid `grant_id`. `voidGrant` keeps its term effect. After that RPC returns `applied`, this unit retires a `held_for_transfer` binding when that installation has no active, grace, queued, or held term. |
| Release method | `releaseHeld` on `VendorEntrypoint` and `releaseHeldRPC` in `ai-platform/src/quota-do/coverage.ts`. This unit does not change them. |
| Listing method | `listGrantsForVoid` on `VendorEntrypoint`. This unit does not change it. |
| Tombstone rule | The pre-grant branch of `voidForReversal` (no `grant_ledger` row: nil UUID receipt, `grant_void`, R2 void object, no DO call) and the `voided` check on `grant`. This unit does not change that branch. |

## Files

| File | FR |
| --- | --- |
| `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/data-model.md` | FR-001, FR-002, FR-003, FR-005, FR-008 |
| `specs/072-abo-p3-8-transfer-deletion-with-coverage-left/quickstart.md` (implement, after verification) | FR-001 through FR-008 |
| `ai-platform/migrations/20261006150000_transfer.sql` | FR-001, FR-002 |
| `ai-platform/src/coverage/transfer.ts` | FR-001, FR-002, FR-003, FR-005 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-004, FR-005, FR-006, FR-007 |
| `ai-platform/src/quota-do/coverage.ts` | FR-002, FR-003, FR-004, FR-005 |
| `ai-platform/src/quota-do/index.ts` | FR-003, FR-005 |
| `ai-platform/src/worker.ts` | FR-002, FR-005 |
| `ai-platform/src/identity/index.ts` | FR-005 |
| `ai-platform/src/config-cache/index.ts` | FR-005 |
| `ai-platform/src/alert/index.ts` | FR-003, FR-005 |
| `ai-platform/src/retention/index.ts` | FR-008 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-002, FR-005 |
| `ai-platform/test/system/transfer-deletion.system.test.ts` | FR-001 through FR-008 |
| `ai-platform/test/retention.test.ts` | FR-008 |
| `ai-platform/test/system/lifecycle-interplay.system.test.ts` | FR-008 |
| `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` | FR-008 |

`voidForReversalRPC`, `voidGrantRPC`, `releaseHeld`, `releaseHeldRPC`, `listGrantsForVoid`, and the tombstone write stay as they are. `packages/vendor-contracts/**` stays. `src/control/lifecycle.ts` `handleDelete` stays the `/control` path until P3.10. `src/control/support-purge.ts` stays the HTTP caller of `purgeByInstallationId`.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/transfer-deletion.system.test.ts` under H-AP (`vitest.workers.config.ts`). Each test calls the entry point below and fails while the behavior it names is absent. `coverClinic()` remains the paid-grant helper. `harness.ts` adds `beginTransfer`, `transferOut`, `transferIn`, and `deleteInstallation` to the `VendorMethod` union.

HP calls use `coverClinicSigner()` the way a complimentary grant does. `operation.op` is `beginTransfer` or `deleteInstallation`. For `beginTransfer`, `operation.params` is `{contract_version, access_jwt, org_id, from_installation_id, reason}`. For `deleteInstallation`, `operation.params` is `{contract_version, access_jwt, org_id, reason}`. `actor_email` is `VENDOR_OPERATOR_EMAIL`. `transferOut` and `transferIn` send `contract_version` and `transfer_id` only, over `env.VENDOR`. After `coverClinic()`, do not move the clock backward of the credential's `activates_at`. `mintAat` is reminted after any `setTestClock` that passes its `exp`. No `sleep` over 2 s. No ABO worker is constructed. `runDurableObjectAlarm` runs before a D1 assertion that the DO outbox ships (`grant_ledger`, `coverage_event`).

A successful `beginTransfer` is `ok`, `code` empty, `receipt` absent, and `detail` is the JSON text of the `transfer` row (`package` null, `transfer_id` present). A successful `deleteInstallation` is `ok`, `code` empty, `receipt` absent, and `detail` is the JSON text of `{installation, tenant_binding}`. `transferOut` and `transferIn` are `applied` or `already_applied` with `detail` the JSON text of the package and `receipt` the §1.6 transfer receipt.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.8-01 | H-AP | Title `E2E-P3.8-01 A14 beginTransfer moves an active term and a queued term`. `coverClinic()` once, then a second paid grant so one term is `queued`. `beginTransfer` for that org and its active `from_installation_id`. `transferOut` then `transferIn`. The new installation's terms have the same `origin_grant_id`s. The active term's `allowance` is the old allowance minus `hot.used`. The queued term's `allowance` is unchanged. `getCoverage` on the old installation has state `transferred`. A later `vendorCall("grant")` aimed at the old installation is `rejected` with `code` `transferred_out`. A captured email is AL-11 for that `transfer_id`. `coverage_event` rows for the new installation carry `binding_epoch` 2. |
| E2E-P3.8-02 | H-AP | Title `E2E-P3.8-02 a non-transfer grant during awaiting_transfer is transient and then queues behind the moved terms`. After `beginTransfer`, before `transferIn`, a paid `vendorCall("grant")` is `transient` with `detail` `awaiting_transfer` and inserts no term. After `transferIn`, that grant is `applied` and `inspectCoverage` shows it queued after the moved terms. |
| E2E-P3.8-03 | H-AP | Title `E2E-P3.8-03 transfer steps retry as already_applied and transferIn before transferOut is transient`. A second `transferOut` and a second `transferIn` with the same `transfer_id` are `already_applied` and return the original receipt. A `transferIn` called before `transferOut` is `transient` with `detail` `awaiting_transfer_out`. Term rows and `transfer.package` are unchanged by that early call. |
| E2E-P3.8-04 | H-AP | Title `E2E-P3.8-04 A24 delete with paid time left holds the binding`. `deleteInstallation` on a clinic with an active term. The binding is `held_for_transfer` and the installation is `deleted`. `SELF.fetch` `POST /v1/requests` is `coverage_lapsed` with `coverage_reason` `transfer_pending`. A paid `vendorCall("grant")` is `transient` with `detail` `transfer_pending`. An issuer token on a clinic `/v1/*` route inserts no second binding. One AL-18 email is captured. A second `deleteInstallation` does not capture another AL-18. `setTestClock` 24 hours ahead and `runScheduled("0 3 * * *")` capture a further AL-18. `beginTransfer` from that held `from_installation_id` is `ok`. |
| E2E-P3.8-05 | H-AP | Title `E2E-P3.8-05 delete with no coverage retires the binding and the next token creates epoch 2`. `deleteInstallation` when the clinic has no active, grace, queued, or held term. The binding is `retired`. The next issuer token for that org inserts a binding with `epoch` 2. |
| E2E-P3.8-06 | H-AP | Title `E2E-P3.8-06 voiding the remaining grants of a held binding retires it`. `deleteInstallation` with coverage left, then `voidGrant` for each not-ended term. The binding is `retired`. The next issuer token inserts `epoch` one greater than the held row. |
| E2E-P3.8-07 | H-AP | Title `E2E-P3.8-07 voidForReversal of a moved paid grant lands on the new installation`. After `transferIn`, `voidForReversal` for that paid `grant_id` with `partial` false is `applied`. `inspectCoverage` on the new installation shows that term `ended` with `end_reason` `reversed`. The old installation's term stays `end_reason` `transferred`. |
| E2E-P3.8-08 | H-AP | Title `E2E-P3.8-08 purge of a deleted installation keeps the ledger`. `deleteInstallation` reaches `purgeByInstallationId`. Afterward the `installation` row is still present with `status` `deleted`. `grant_ledger`, `grant_void`, `coverage_event`, and `transfer` rows for that clinic are still present. `usage_event` rows whose `term_id` is a term that has not ended are still present. |

Earlier purge assertions that expect the installation row, the entitlement row, or the tenant binding to be removed are updated in the same change that stops those deletes, so `npm test` and `npm run test:e2e` stay green (rule S2). `SYS-2.4` still expects the post-purge clinic call to be `unauthenticated`, which the `deleted` installation status already produces.

## Sequencing

Tests are written and observed failing before transfer, deletion, lineage, and purge retention exist. Each step is one task. The implied count is 24.

1. Add `test/system/transfer-deletion.system.test.ts` with E2E-P3.8-01. Run the unit command. It fails because `beginTransfer` is not a method.
2. Add E2E-P3.8-02. The run fails because a grant during `awaiting_transfer` is not `transient`.
3. Add E2E-P3.8-03. The run fails because a retry is not `already_applied` and an early `transferIn` is not `transient`.
4. Add E2E-P3.8-04. The run fails because `deleteInstallation` is not a method.
5. Add E2E-P3.8-05. The run fails because a delete with no coverage does not leave a retired binding whose next token is epoch 2.
6. Add E2E-P3.8-06. The run fails because `voidGrant` of the remaining grants does not retire the held binding.
7. Add E2E-P3.8-07. The run fails because `voidForReversal` does not change the new installation's term.
8. Add E2E-P3.8-08. The run fails because purge still removes the installation row.
9. Add `ai-platform/migrations/20261006150000_transfer.sql` with `transfer` and `transfer_step` as in `data-model.md`. Unique (`transfer_id`, `step`) on `transfer_step`. Do not edit earlier migrations.
10. Add the four method names to `VendorMethod` in `test/system/harness.ts` and to `METHOD_CLASS` (`beginTransfer` and `deleteInstallation` are `HP`, `transferOut` and `transferIn` are `M`). Extend `operationParamsMatch` for those two HP ops.
11. Add `beginTransfer` on `VendorEntrypoint`. Class HP, same assertion flow as `setCeilingPolicy`: if `transfer.assertion_sha256` already matches, return `ok` with that row's JSON and do not insert. Otherwise verify the assertion, then in one batch retire the source binding, insert the new `installation` and the next `epoch` as `active`, and insert `transfer` with `package` null and `to_installation_id` set to the new installation. `from_installation_id` must be that org's `active` or `held_for_transfer` row. Open the new DO with `awaiting_transfer` set and `binding_epoch` equal to the new epoch. `detail` is the JSON text of the `transfer` row. `code` is empty and `receipt` is absent.
12. Add DO kind `transfer_out`, dispatched from `GatewayObject.fetch`. `transferOut` requires a `transfer` row. It reads not-ended terms, builds the package in `src/coverage/transfer.ts` with the allowance rules in `data-model.md`, ends those terms with `end_reason` `transferred`, sets `transferred_out_to` to `to_installation_id`, stores the package, inserts `transfer_step` `transfer_out` with the §1.6 receipt, and emits `coverage_event` `kind` `transfer`. `detail` is the JSON text of the package. `buildCoverageSnapshot` returns state `transferred` when `transferred_out_to` is set. A grant whose DO has `transferred_out_to` set is `rejected` with `code` `transferred_out` and writes nothing.
13. A second `transferOut` for the same `transfer_id` is `already_applied` and returns the stored receipt without writing. `transferIn` when no `transfer_out` step exists is `transient` with `detail` `awaiting_transfer_out` and writes nothing.
14. Add DO kind `transfer_in`. It inserts the package terms on the destination DO, `origin_grant_id` copied, new `term_id`s, `grant_id` SHA-256 of `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. It clears `awaiting_transfer`, emits `coverage_event` `kind` `transfer` with `binding_epoch` of the new binding, and inserts `transfer_step` `transfer_in`. The outbox ships `grant_ledger` rows with `source_kind` `transfer` and `installation_id` of the new installation. On `applied`, raise one AL-11 for that `transfer_id` through `src/alert/index.ts` (captured `send_email`, codes and ids only). A retry is `already_applied` and does not raise AL-11 again.
15. Until `transferIn` has applied, a non-transfer `grant` whose binding's DO has `awaiting_transfer` set is `transient` with `detail` `awaiting_transfer` and writes nothing. After `transferIn`, that grant applies and is queued after the moved terms.
16. Add `deleteInstallation` on `VendorEntrypoint` (class HP). It marks the installation `deleted` and then calls `purgeByInstallationId`. With an active, grace, queued, or held term, the binding becomes `held_for_transfer`, the DO sets `transfer_pending`, and AL-18 is sent once. A repeat while the installation is already `deleted` and the binding is still in that status is `ok`, does not insert a binding, and does not send AL-18 again. `detail` is the JSON text of `{installation, tenant_binding}`.
17. In `admitOnHotRow`, after boundaries, a set `transfer_pending` flag returns `coverage_lapsed` with `coverage_reason` `transfer_pending` and does not reserve. A paid `grant` for an org whose live binding is `held_for_transfer` is `transient` with `detail` `transfer_pending` and does not insert a binding. A complimentary `grant` for that same held installation still applies, so the running calendar can be compensated, and it does not create a binding. In `src/identity/index.ts` and the `tenant_bindings` reader, a `held_for_transfer` row is returned and no insert runs. A `deleted` installation whose binding is `held_for_transfer` is still admitted so the DO can refuse. Any other non-active installation stays `unauthenticated`.
18. `deleteInstallation` with no active, grace, queued, or held term sets the binding `retired`. The next token for that org, when no `active` or `held_for_transfer` row exists, inserts epoch `max(epoch) + 1` (2 for the E2E clinic).
19. After `voidGrantRPC` returns `applied`, if that installation's binding is `held_for_transfer` and the DO has no active, grace, queued, or held term, set the binding `retired`. Do not change `voidGrantRPC`.
20. In `voidForReversal`, when choosing the DO, use the latest `grant_ledger` row by `applied_at` whose `grant_id` or `origin_grant_id` equals the paid `grant_id`, and call the existing `void_for_reversal` kind on that `installation_id` with the org's active binding epoch. Do not change `voidForReversalRPC` or the tombstone branch.
21. Change `purgeByInstallationId` so it updates `installation.status` to `deleted` and does not delete that row, `entitlement`, `tenant_binding`, `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, or `transfer_step`. It does not delete or update DO storage. `usage_event` deletes stay, except rows whose `term_id` belongs to a DO term that has not ended. Keep the existing deletes of requests, attempts, rollups, counters, and capability grants.
22. On the existing cron `0 3 * * *`, send AL-18 again for each binding still `held_for_transfer` whose last AL-18 send is at least 24 hours earlier. Do not add a cron. A binding that is no longer held is not sent.
23. Update `test/retention.test.ts`, `test/system/lifecycle-interplay.system.test.ts` (`SYS-2.4`), and `test/e2e/stage-03-revoke-delete-purge.test.ts` so they expect the installation row kept with `status` `deleted`, and expect `entitlement` and `tenant_binding` kept. Leave the `unauthenticated` assertion after purge. Run the unit command and confirm E2E-P3.8-01 through E2E-P3.8-08 pass.
24. Confirm the unit file is the only vitest path in the command above, and that `src/coverage/transfer.ts` is reached from `beginTransfer`, `transferOut`, `transferIn`, and `deleteInstallation`.

## Complexity Tracking

02 §7 records no constitution violation for this unit. Nothing is filled in here.
