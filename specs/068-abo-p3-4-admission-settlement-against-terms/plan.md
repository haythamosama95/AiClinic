# Implementation Plan: Admission and settlement against terms

**Branch**: `ai/068-abo-p3-4-admission-settlement-against-terms` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/068-abo-p3-4-admission-settlement-against-terms/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.4 admits and settles each live AI request against the clinic's term on the per-clinic DO `hot` row, returns the frozen admission answer, and journals `usage_event` by `term_id`. It is phase P3, size L, **Depends** P3.3, in parallel with P4.1 and P4.2, and it is checkpoint CP-B.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. Band strings stay the consumed set `ok`, `75`, `90`, `exhausted`. Tests use the existing H-AP helpers `vendorCall`, `newClinic`, `setTestClock`, `createAboGrantSigner` from `vendor-contracts/testkit`, and `runDurableObjectAlarm` / `runInDurableObject` from `cloudflare:test`. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`.

**Storage**: The existing per-clinic DO SQLite tables `hot`, `term`, `grant`, and `outbox`. Live admission stops using the JSON blob key `state`. D1 `usage_event` (`term_id` in place of `period`, unique `request_id`) and `usage_rollup` (dimensions `{installation_id, term_id}`). `coverage_mirror` is read by primary key. The existing `DB`, `R2`, and `DO` bindings stay.

**Testing**: H-AP. E2E-P3.4-01 through E2E-P3.4-12 live in `ai-platform/test/system/admission-settlement.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before term admission exists. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on `npm test` and `npm run test:e2e` (rule S2). Time moves with `setTestClock` and `clockNowMs` (rule V4). No local scenario sleeps more than 2 s.

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Clinic calls are `SELF.fetch` `GET /v1/capabilities` and `SELF.fetch` `POST /v1/requests`. Paid setup is `VendorEntrypoint.grant` over the H-AP self service binding. The DO RPC stays `POST https://quota-do.internal/rpc` on `env.DO`. `workers_dev = false` and `preview_urls = false` stay as they are.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). One admission runs per AI request, after rate limits. The DO serializes that admission. No separate throughput target. Load and the write budget stay in P3.11.

**Constraints**: Do not modify `packages/vendor-contracts`. Do not rewrite consumed `grant`, `getCoverage`, `listGrants`, `readCoverageEvents`, service-key methods, plan-version methods, the DO table list, or event and receipt shapes (rule S7). Do not implement expiry, grace, or boundary alarms (P3.5), setting `suspended` (P3.6), fallback admission (P3.9), or dropping entitlement tables and `/control/*` (P3.10). `reconcileGraceUsage` stays. Vendor and DO version checks keep using `negotiate` before authentication and before any write. Production admission sends `contract_version: CHANNEL_VERSIONS.platformDo`. `TEST_CLOCK` stays only in `vitest.workers.config.ts`. Production wrangler has no clock control. `hot.reservations` holds at most 16. The quota DO keeps `EPHEMERAL_HORIZON_MS` (2 hours) and `CONCURRENCY_LIMIT`. The limit used at admission is the plan snapshot's `concurrency_limit`.

**Scale/Scope**: Size L (rule S3, 32–40 tasks, 4 user stories, 12 E2E ids, 14 functional requirements). Implied task count is 32.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: DO SQLite and D1 on the existing AI Platform worker. No clinic write and no second service. The same boxes hold after those artifacts.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  Admission charges one clinic's AI request to that clinic's active term (spec §4.1, 02 §7 principle I). The concurrency limit and the capability list are the ones snapshotted for that plan. No second clinic product and no hospital-scale control plane.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. The 15-minute charge is the next admission, and the outbox still ships on the existing DO alarm (02 §7 principle I). No Kubernetes and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 and DO SQLite only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 unique keys and the DO's serialized writer. Admission steps that change `hot` run inside `blockConcurrencyWhile`. `usage_event.request_id` is unique so the journal and a `usage_adjustment` count a request once. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `POST /v1/requests` and `GET /v1/capabilities` still require the issuer token (spec §4.1). A paid grant still enters through the consumed `grant` method. Denial paths write nothing unless step 2 or step 3 changed state. Replay returns the stored answer and does not write. Entitlement rows stay until P3.10. No hard delete of ledger or event rows.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). A lapsed or exhausted term refuses the AI request inline. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/068-abo-p3-4-admission-settlement-against-terms/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── admission-answer.md
│   └── clinic-denial-codes.md
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). `data-model.md` records the entities in spec §3.2. `contracts/` freezes the admission answer and the clinic denial codes.

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — term admission and settlement, the denial codes, exhaustion and bands, `usage_event.term_id`, and `coverClinic()`.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/admission-settlement.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.4-01 | `coverClinic()` → `vendorCall` `grant` → `runDurableObjectAlarm` → `GET /v1/capabilities` → `src/discovery/index.ts` → `discover` reads `coverage_mirror` → `POST /v1/requests` → `src/pipeline/index.ts` stage 8 → `admissionRPC` → stage 15 `creditUsage` → `usage_event.term_id` |
| E2E-P3.4-02 | `newClinic()` → `POST /v1/requests` → `admissionRPC` step 4 → 403 `coverage_lapsed` |
| E2E-P3.4-03 | `coverClinic()` with a snapshot that omits the capability → `POST /v1/requests` → step 4 `forbidden_capability` |
| E2E-P3.4-04 | `coverClinic()` with `concurrency_limit` 16 → 17 concurrent `POST /v1/requests` → step 4 `concurrency_limited` |
| E2E-P3.4-05 | `coverClinic()` → `POST /v1/requests` until allowance → step 6 → next `POST` → `allowance_exhausted` |
| E2E-P3.4-06 | `coverClinic()` twice → `POST` that reaches the allowance → queued term `ends_at` |
| E2E-P3.4-07 | `coverClinic()` twice → two concurrent `POST`s near the allowance → one exhaustion |
| E2E-P3.4-08 | `coverClinic()` → `POST`s that cross 75% and 90% → one `band_crossed` each → a later `POST` emits nothing |
| E2E-P3.4-09 | `coverClinic()` → empty provider chain → `creditUsage` releases the reservation |
| E2E-P3.4-10 | `coverClinic()` → `POST` left unsettled → `setTestClock` past 15 minutes → next `POST` step 2 → `runDurableObjectAlarm` → late credit |
| E2E-P3.4-11 | `POST /v1/requests` twice with the same `x-idempotency-key` or the same token `jti` → step 1 |
| E2E-P3.4-12 | `POST /v1/requests` while the DO fetch returns `result` `rejected` → `coverage_unknown` |

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261006120000_usage_term.sql
├── schema.snap.sql
├── src/
│   ├── admission/index.ts
│   ├── adapter.ts
│   ├── capability/index.ts
│   ├── credit/index.ts
│   ├── dashboards/index.ts
│   ├── discovery/index.ts
│   ├── entitlement/index.ts
│   ├── errors.ts
│   ├── identity/index.ts
│   ├── journal/index.ts
│   ├── manifest/index.ts
│   ├── pipeline/index.ts
│   ├── quota-do/
│   │   ├── coverage.ts
│   │   └── index.ts
│   ├── rollup/index.ts
│   ├── soft-threshold/index.ts
│   ├── usage-summary/index.ts
│   └── worker.ts
└── test/
    ├── e2e/harness/d1.ts
    ├── system/
    │   ├── admission-settlement.system.test.ts
    │   ├── capability-lifecycle.system.test.ts
    │   ├── entitlement-grant-interplay.system.test.ts
    │   ├── failure-taxonomy-matrix.system.test.ts
    │   ├── golden-journey.system.test.ts
    │   ├── harness.ts
    │   ├── lifecycle-interplay.system.test.ts
    │   ├── quota-admission-interplay.system.test.ts
    │   ├── routing-policy-traffic.system.test.ts
    │   └── settlement-integrity.system.test.ts
    └── (migration lists and assertion updates named in Files)
```

**Structure Decision**: Source stays the existing Worker. Admission steps 1–7 and settlement by reservation id live in `src/quota-do/index.ts`, which the quota-do row already names. `src/quota-do/coverage.ts` gains the `usage_adjustment` ship on the existing alarm and computes `term.band` from `used` and `allowance`. No new source file. `coverClinic()` lives in `src`-adjacent harness `test/system/harness.ts`. `src/coverage/calendar.ts` stays as P3.3 left it; successor `ends_at` calls `addDuration`.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| `grant` (paid) | `VendorEntrypoint.grant` in `ai-platform/src/vendor/entrypoint.ts`. Frozen contract: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/grant-paid.md`. `coverClinic()` calls it. This unit does not edit the method. |
| `getCoverage` | `VendorEntrypoint.getCoverage` in `ai-platform/src/vendor/entrypoint.ts`. Frozen contract: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/get-coverage.md`. |
| `listGrants` | `VendorEntrypoint.listGrants` in `ai-platform/src/vendor/entrypoint.ts`. Frozen contract: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/list-grants.md`. |
| `readCoverageEvents` | `VendorEntrypoint.readCoverageEvents` in `ai-platform/src/vendor/entrypoint.ts`. Frozen contract: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/read-coverage-events.md`. |
| Service-key methods | `registerServiceKey`, `revokeServiceKey`, and `listServiceKeys` on `VendorEntrypoint`. Frozen contract: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/service-key-methods.md`. |
| Plan-version methods | `publishPlanVersion` and `retirePlanVersion` on `VendorEntrypoint`. Frozen contract: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/plan-version-methods.md`. |
| DO schema | Tables created by `ensureCoverageDoTables` in `ai-platform/src/quota-do/index.ts`. Frozen contract: `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/do-schema.md`. This unit writes `hot` and appends `outbox` rows. It does not add or rename a table. |
| Event shapes | `band_crossed` and the coverage snapshot, including `term.band` of `ok`, `75`, `90`, or `exhausted`, as `validateCoverageSnapshot` in `packages/vendor-contracts/src/coverage-snapshot.ts` and `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/coverage-event.md`. This unit emits those kinds. It does not add snapshot keys. |
| Receipt shapes | `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/receipt-production.md`. This unit does not sign or reshape receipts. |

## Files

| File | FR |
| --- | --- |
| `specs/068-abo-p3-4-admission-settlement-against-terms/data-model.md` | FR-001, FR-003, FR-009, FR-011 |
| `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/admission-answer.md` | FR-002, FR-004, FR-006, FR-009 |
| `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/clinic-denial-codes.md` | FR-005, FR-006, FR-012 |
| `specs/068-abo-p3-4-admission-settlement-against-terms/quickstart.md` (implement, after verification) | FR-001 through FR-014 |
| `ai-platform/migrations/20261006120000_usage_term.sql` | FR-011 |
| `ai-platform/schema.snap.sql` | FR-011 |
| `ai-platform/src/quota-do/index.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008, FR-009 |
| `ai-platform/src/quota-do/coverage.ts` | FR-003, FR-009 |
| `ai-platform/src/admission/index.ts` | FR-005, FR-006, FR-010, FR-013 |
| `ai-platform/src/credit/index.ts` | FR-004 |
| `ai-platform/src/pipeline/index.ts` | FR-010 |
| `ai-platform/src/worker.ts` | FR-010 |
| `ai-platform/src/journal/index.ts` | FR-011 |
| `ai-platform/src/rollup/index.ts` | FR-011 |
| `ai-platform/src/capability/index.ts` | FR-013 |
| `ai-platform/src/discovery/index.ts` | FR-013 |
| `ai-platform/src/entitlement/index.ts` | FR-013 |
| `ai-platform/src/manifest/index.ts` | FR-010 |
| `ai-platform/src/errors.ts` | FR-005, FR-012 |
| `ai-platform/src/adapter.ts` | FR-012 |
| `ai-platform/src/dashboards/index.ts` | FR-012 |
| `ai-platform/src/soft-threshold/index.ts` | FR-012 |
| `ai-platform/src/identity/index.ts` | FR-005 |
| `ai-platform/src/usage-summary/index.ts` | FR-005 |
| `ai-platform/test/system/harness.ts` | FR-011, FR-014 |
| `ai-platform/test/e2e/harness/d1.ts` | FR-011 |
| `ai-platform/test/system/admission-settlement.system.test.ts` | FR-001 through FR-014 |
| `ai-platform/test/system/capability-lifecycle.system.test.ts` | FR-014 |
| `ai-platform/test/system/entitlement-grant-interplay.system.test.ts` | FR-014 |
| `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts` | FR-014 |
| `ai-platform/test/system/golden-journey.system.test.ts` | FR-014 |
| `ai-platform/test/system/lifecycle-interplay.system.test.ts` | FR-014 |
| `ai-platform/test/system/quota-admission-interplay.system.test.ts` | FR-014 |
| `ai-platform/test/system/routing-policy-traffic.system.test.ts` | FR-014 |
| `ai-platform/test/system/settlement-integrity.system.test.ts` | FR-014 |
| `ai-platform/test/usage-summary.test.ts` | FR-011 |
| `ai-platform/test/identity.test.ts` | FR-011 |
| `ai-platform/test/plan-catalogue.test.ts` | FR-011 |
| `ai-platform/test/control.test.ts` | FR-011 |
| `ai-platform/test/token-contract-control.test.ts` | FR-011 |
| `ai-platform/test/entitle-grant.test.ts` | FR-011 |
| `ai-platform/test/config-readers.test.ts` | FR-011 |
| `ai-platform/test/worker-request-orchestrator.test.ts` | FR-011 |
| `ai-platform/test/discovery-http.test.ts` | FR-011 |
| `ai-platform/test/retention.test.ts` | FR-011 |

The last block is every file that already imports `20261003140000_plan_version_paid_grant_coverage.sql`. Each applies `20261006120000_usage_term.sql` after it. `src/vendor/entrypoint.ts`, `src/coverage/calendar.ts`, `src/rate-limit/index.ts`, `src/platform-vocabulary.ts`, and `packages/vendor-contracts/**` stay as they are. Guard-rejection counters stay `recordGuardRejection` in `src/rate-limit/index.ts`; admission passes the new codes into it. `entitleScenario` and `/control/entitle` stay defined until P3.10. Call sites move to `coverClinic()`.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/admission-settlement.system.test.ts` under H-AP (`vitest.workers.config.ts`). Each test calls the entry point below and fails while term admission is absent. `coverClinic()` is the paid-grant helper in `test/system/harness.ts`. It signs with `createAboGrantSigner`, calls `vendorCall` `grant`, then `runDurableObjectAlarm` so the consumed ship writes `coverage_mirror`. Issuer tokens come from `newClinic()`. Clinic calls use `SELF.fetch`. The test clock is `setTestClock`. No `sleep` over 2 s.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.4-01 | H-AP | Title `E2E-P3.4-01 CP-B paid grant then issuer token lists the plan and completes a request charged to the term`. `coverClinic()` then `newClinic()` for that org. `GET /v1/capabilities` lists `clinic.visit_summary` from `coverage_mirror`. `POST /v1/requests` completes. `usage_event.term_id` is the active term. `hot.used` increases by the capability `quotaWeight` (`w`). |
| E2E-P3.4-02 | H-AP | Title `E2E-P3.4-02 An org that was never granted is coverage_lapsed and writes no journal row`. `newClinic()` and no `coverClinic()`. `POST /v1/requests` is 403, body `code` `coverage_lapsed`, `coverage_reason` `none`. No `usage_event` row and no `ai_request` row for that call. |
| E2E-P3.4-03 | H-AP | Title `E2E-P3.4-03 A capability outside the plan snapshot is forbidden_capability`. `coverClinic()` publishes a plan whose `capabilities` omit `clinic.visit_summary`. `POST` asking for that capability is 403 `forbidden_capability`. |
| E2E-P3.4-04 | H-AP | Title `E2E-P3.4-04 The 17th in-flight request is concurrency_limited`. `coverClinic()` with `concurrency_limit` 16. `Promise.all` of 17 `POST /v1/requests`. One response is 429 `concurrency_limited` with `retry_after`, and its `code` is not `rate_limited`. |
| E2E-P3.4-05 | H-AP | Title `E2E-P3.4-05 Reaching the allowance with nothing queued exhausts the term`. `coverClinic()` once, small allowance. `POST` until `used + reserved` reaches the allowance. The term `state` is `exhausted`. The next `POST` is 403 `allowance_exhausted`. There is no grace term. |
| E2E-P3.4-06 | H-AP | Title `E2E-P3.4-06 Exhaustion activates the queued term at that instant`. `coverClinic()` twice. The `POST` that reaches the allowance leaves the queued term `active` with a full allowance. `ends_at` is that instant plus 1 month from `addDuration`. |
| E2E-P3.4-07 | H-AP | Title `E2E-P3.4-07 Two concurrent requests near the allowance exhaust once`. `coverClinic()` twice. Two concurrent `POST`s when one credit remains. One `term_ended` or single exhaustion. Overshoot is at most `w_max - 1`. The other request is charged to the successor or refused. |
| E2E-P3.4-08 | H-AP | Title `E2E-P3.4-08 Crossing 75 percent and 90 percent emits one band event each`. `coverClinic()` with allowance 10. After the alarm, one `coverage_event` of kind `band_crossed` whose snapshot `term.band` is `75`, and one whose band is `90`. A further `POST` still inside a crossed band adds no second event for that band. |
| E2E-P3.4-09 | H-AP | Title `E2E-P3.4-09 A provider call that consumes nothing releases the reservation`. `coverClinic()`, then `publishPolicy` / `promote` of `fakePolicyDocument` with an empty target list. `POST` admits, the provider chain is empty, and settlement releases. `hot.used` is unchanged and the reservation is gone. |
| E2E-P3.4-10 | H-AP | Title `E2E-P3.4-10 A reservation older than 15 minutes is charged once`. `coverClinic()`, then `POST` whose first `kind: "credit"` is swallowed by a test wrapper on `GatewayObject.fetch` so the reservation stays. `setTestClock` more than 15 minutes later. The next `POST` charges it. `runDurableObjectAlarm` leaves one `usage_event` for that `request_id`. Replaying the swallowed credit changes neither `hot` nor that row. |
| E2E-P3.4-11 | H-AP | Title `E2E-P3.4-11 A replayed jti or idempotency key returns the stored answer`. Two `POST`s with the same `x-idempotency-key`, and two with the same bearer token. The second response matches the stored answer. `hot` SQL is unchanged across the replay. |
| E2E-P3.4-12 | H-AP | Title `E2E-P3.4-12 A DO version rejection is coverage_unknown`. For this test, `GatewayObject.fetch` returns the P3.3 refusal `{result: "rejected", code: "contract_version_unsupported"}` for `kind` `admission` and does not touch storage. `POST /v1/requests` is 503 `coverage_unknown` with `retry_after`. |

## Sequencing

Tests are written and observed failing before term admission exists. Each step is one task. The implied count is 32, inside size L (32–40).

1. Add `test/system/admission-settlement.system.test.ts` with E2E-P3.4-01. Run the unit command. It fails because `coverClinic` is missing and `POST /v1/requests` is not charged to a term.
2. Add E2E-P3.4-02. The run fails because a never-granted org is not refused `coverage_lapsed`.
3. Add E2E-P3.4-03. The run fails because a capability outside the snapshot is not `forbidden_capability`.
4. Add E2E-P3.4-04. The run fails because the 17th in-flight request is not `concurrency_limited`.
5. Add E2E-P3.4-05. The run fails because reaching the allowance does not end the term `exhausted`.
6. Add E2E-P3.4-06. The run fails because exhaustion does not activate the queued term.
7. Add E2E-P3.4-07. The run fails because two concurrent requests do not exhaust once.
8. Add E2E-P3.4-08. The run fails because band crossings do not emit one `band_crossed` each.
9. Add E2E-P3.4-09. The run fails because an empty provider chain still changes `hot.used`.
10. Add E2E-P3.4-10. The run fails because a reservation older than 15 minutes is not charged on the next admission.
11. Add E2E-P3.4-11. The run fails because a replayed key writes again.
12. Add E2E-P3.4-12. The run fails because a DO `rejected` version answer is not `coverage_unknown`.
13. Add `coverClinic()` in `test/system/harness.ts` and switch `setupPromotedFakePolicy` plus the eight system suites in Files off `entitleScenario`. `coverClinic()` calls consumed `publishPlanVersion`, `registerServiceKey`, and `grant`, then `runDurableObjectAlarm`. The twelve E2E tests still fail on admission.
14. Add `migrations/20261006120000_usage_term.sql` as `data-model.md` describes. Replace `schema.snap.sql` with the post-migration dump. Append that SQL after `20261003140000_plan_version_paid_grant_coverage.sql` in every file listed for FR-011. The twelve E2E tests still fail.
15. In `admissionRPC`, step 1 reads `hot.replay` and `hot.idempotency` and returns the stored answer without writing. Sweep those maps on each write that does happen, keeping entries for at least `EPHEMERAL_HORIZON_MS`. Pass `now` from `clockNowMs`. E2E-P3.4-11 still fails until the HTTP path stores the answer.
16. Step 2 charges reservations whose `admitted_at` is more than 15 minutes before `now`. Append outbox kind `usage_adjustment` with the payload in `data-model.md`. Do not insert `usage_event` inside the DO.
17. In `shipCoverageOutboxAlarm`, ship `usage_adjustment` with `INSERT OR IGNORE` on `usage_event.request_id`, then delete the outbox row. Leave `coverage_event`, `grant_ledger`, and `alert` as they are. E2E-P3.4-10 still fails until the next admission charges.
18. Step 4 refuses in the order in `contracts/clinic-denial-codes.md`. A refusal writes nothing unless step 2 changed state. Step 3 runs and applies no expiry or grace transition. `hot.suspended` maps to `suspended`; this unit does not set the flag. Capabilities and `concurrency_limit` come from `term.plan_snapshot`.
19. Steps 5–7 reserve `w`, end an active term `exhausted` in that same transaction when `used + reserved >= allowance`, activate the next unheld queued term with `addDuration`, emit one `band_crossed` per band, and return `contracts/admission-answer.md`. E2E-P3.4-01 and E2E-P3.4-05 through E2E-P3.4-08 still need the worker path.
20. `credit` settles by `reservation_id`. Provider capacity adds `w` to `used`. Nothing consumed releases the reservation. The reservation keeps its `term_id` after the term has ended. A credit after the step-2 charge changes nothing.
21. Remove the `state` blob, `maybeResetPeriod`, and `isQuotaExhausted`. Denial and replay do not call the blob writer.
22. `src/admission/index.ts` maps DO outcomes through `contracts/clinic-denial-codes.md`, including `result: "rejected"` to `coverage_unknown`. Remove `mapEntitlementSnapshot`. Send `contract_version` and `now` from `clockNowMs`. E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 pass once the worker uses this mapper.
23. `src/errors.ts` and `src/adapter.ts` carry `retry_after` and `coverage_reason` and drop `quota_exhausted` and `period_reset`. Rename `installation_suspended` to `suspended` in `src/identity/index.ts`, `src/usage-summary/index.ts`, and the journal union. Token verification stays.
24. Pipeline stage 3 reads `coverage_mirror` by `installation_id` and does not read `entitlement`. Stage 8 keeps `term_id`, `reservation_id`, and the snapshot from the DO. Stage 15 passes them to `creditUsage`.
25. In `src/worker.ts`, replace `periodFromIso` and `SELECT period_start FROM entitlement` on the handoff settlement with the admission `term_id`. Take the cost class from the snapshot `max_cost_class`. Drop the `minimumPlanTier: "standard"` argument. `src/manifest/index.ts` no longer requires `minimumPlanTier` and ignores it when present.
26. `src/journal/index.ts` inserts `term_id` with `INSERT OR IGNORE` on `request_id`. `authenticateGetRequest` keeps `IssuerTokenVerifier`.
27. `src/rollup/index.ts` aggregates by `{installation_id, term_id}`.
28. `discover` reads `coverage_mirror` by primary key. `src/discovery/index.ts` passes `env.DB`. Remove tier checks and the `plan:` grant fallback in `src/capability/index.ts`. `src/entitlement/index.ts` drops tier and status checks and keeps kill switches. The capability check reads the plan snapshot.
29. `dashboardQuotaRejectionRate` counts the codes in `contracts/clinic-denial-codes.md`. `degradedNoticeFromAdmission` is true for band `75`, `90`, or `exhausted`. Admission records those codes through the existing `recordGuardRejection`.
30. Re-run the unit command and confirm E2E-P3.4-01 through E2E-P3.4-12 pass together.
31. Run `cd ai-platform && npm test && npm run test:e2e`. Update assertions that still expect `quota_exhausted`, `period_reset`, `installation_suspended`, or `usage_event.period`, and `discover` call sites that omit `db`. Earlier suites stay green (rule S2).
32. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
