# Implementation Plan: Plan versions, paid-grant intake and the per-clinic coverage ledger

**Branch**: `ai/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger` | **Date**: 2026-10-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.3 adds paid-grant intake on the existing AI Platform worker: HP service-key and plan-version methods, a class M `grant` that places one active or queued term, a platform-signed receipt, and a per-clinic DO outbox that the alarm ships to the coverage feed, the ledger, the mirror, and R2. Month arithmetic and the staging duration scale live in `src/coverage/calendar.ts`. The Worker to DO call carries `contract_version` and the DO echoes it.

The unit sits in phase P3, size L, **Depends** P3.2, in parallel with P4.1. It consumes P3.2's frozen token, binding, and issuer-key contracts and does not close a checkpoint. CP-B is the later falsification gate after P3.4.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit calls the frozen exports `negotiate`, `CHANNEL_VERSIONS`, `acceptedVersions`, `canonicalize`, `sha256Hex`, `signCompactJws`, `validateGrantEnvelope`, `grantEnvelopeHash`, `verifyGrantSignature`, `validateReceipt`, `receiptSigningBytes`, `verifyReceiptSignature`, `validateCoverageSnapshot`, `validateFeedEvent`, `validateResultEnvelope`, and `coverageEventId`. Tests call `createAboGrantSigner` from `vendor-contracts/testkit` and the existing H-AP Access and WebAuthn helpers. No new library. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`. `runDurableObjectAlarm` is the pool helper the spec names (rule V4).

**Storage**: Per-clinic DO SQLite tables `hot`, `term`, `grant`, and `outbox`, created on first versioned access. The existing JSON blob key `state` stays for live admission (rule S9). D1 tables `service_key`, `plan_version`, `coverage_event`, `grant_ledger`, and `coverage_mirror`. R2 prefix `grant-ledger/`. The existing `DB` and `R2` bindings stay.

**Testing**: H-AP. E2E-P3.3-01 through E2E-P3.3-12 live in `ai-platform/test/system/paid-grant-coverage.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the methods and the DO tables exist. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on `npm test` and `npm run test:e2e` (rule S2).

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). New methods are RPC on `VendorEntrypoint`, not HTTP routes. The DO RPC stays `POST https://quota-do.internal/rpc` on `env.DO`. `workers_dev = false` and `preview_urls = false` stay as they are.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). A paid grant is an operator-scale write, not an admission on the AI request path. The alarm ships the outbox. No separate throughput target.

**Constraints**: Do not modify `packages/vendor-contracts` (rule S7). Do not modify the consumed issuer-token verifier, the `tenant_binding` insert in `src/identity/index.ts`, the config-cache kinds, or the issuer-key methods. Successful service-key, plan-version, coverage-read, and list calls stay inside the frozen result envelope: `result` `ok`, `receipt` omitted, payload JSON text in `detail`. `grant` returns `applied` or `already_applied` with the receipt, or `conflict`, `rejected`, or `transient` without a receipt. Vendor-method version checks keep using `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, …)` before authentication and before any write. The DO channel uses `negotiate(CHANNEL_VERSIONS.platformDo, …)` the same way. `TEST_CLOCK` stays only in `vitest.workers.config.ts`. Production wrangler has no `DURATION_SCALE` and no `TEST_CLOCK`. No local scenario sleeps more than 2 s. `/control/entitle` and the quota JSON blob stay (rule S9). This unit does not map a DO version refusal to `coverage_unknown`. FR-003 stops at the DO answer, and the existing callers send the current DO version so they are not refused.

**Scale/Scope**: Size L (rule S3, 32–40 tasks, 4 user stories, 12 E2E ids, 16 functional requirements). Implied task count is 32.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: DO SQLite, D1, R2, and `VendorEntrypoint`. No clinic write and no second service. The same boxes hold after those artifacts.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One coverage ledger per clinic org on the worker the clinic already calls (spec §4.1, 02 §7 principle I). Sized for a few orders a day and one operator. No second clinic product and no hospital-scale control plane.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. Background work is the DO alarm shipping a D1 outbox (02 §7 principle I: a D1 outbox, not Cloudflare Queues). No Kubernetes and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1, DO SQLite, and R2 only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 unique keys and the DO's serialized writer. `grant` applies inside `blockConcurrencyWhile`. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Class M `grant` and the coverage reads ride the service binding and, for `grant`, an ABO Ed25519 signature checked against `service_key` (spec §4.1, 04 §1.4). Plan publish, plan retire, service-key register, and service-key revoke are class HP and reuse the existing Access JWT and assertion checks. Register and revoke raise AL-13. Receipts are signed by `PLATFORM_SIGNING_KEY`. Ledger and event rows are append-only. Revoke and retire update `status` and keep the row. No hard delete of those rows.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). Paid grants are operator-signed platform writes. Live admission still uses the JSON blob and `/control/entitle` (rule S9), so AI availability is unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── grant-paid.md
│   ├── get-coverage.md
│   ├── list-grants.md
│   ├── read-coverage-events.md
│   ├── service-key-methods.md
│   ├── plan-version-methods.md
│   ├── do-schema.md
│   ├── coverage-event.md
│   └── receipt-production.md
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). `data-model.md` records the entities in spec §3.2. `contracts/` is the freeze later units bind to. Receipt field rules and the feed-event object stay the P2.2 contracts. This unit's receipt and event files add only the production rules those contracts leave to the producer (rule S7).

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — paid `grant`, plan-version and service-key methods, the DO tables, the alarm ship, the calendar, and the coverage reads.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/paid-grant-coverage.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.3-01 | `vendorCall` `publishPlanVersion` then `registerServiceKey` then `grant` → `src/vendor/entrypoint.ts` → binding insert → `GatewayObject.fetch` `apply_grant` → `src/coverage/calendar.ts` → `signCompactJws` |
| E2E-P3.3-02 | `vendorCall` `grant` twice → `runDurableObjectAlarm` → `GatewayObject.alarm` → `grant_ledger` |
| E2E-P3.3-03 | `vendorCall` `grant` with a changed allowance → DO `conflict` |
| E2E-P3.3-04 | `vendorCall` `grant` twice → `vendorCall` `getCoverage` → DO `read_coverage` |
| E2E-P3.3-05 | `vendorCall` `grant` with an unknown `kid`; `vendorCall` `revokeServiceKey` then `grant` |
| E2E-P3.3-06 | `vendorCall` `grant` for each named refusal |
| E2E-P3.3-07 | `vendorCall` `grant` → `runDurableObjectAlarm` → D1 and R2 → `vendorCall` `readCoverageEvents` |
| E2E-P3.3-08 | `vendorCall` `grant` → `runDurableObjectAlarm` → `src/alert/index.ts` AL-11; a fourth paid grant → AL-17 |
| E2E-P3.3-09 | `setTestClock` → `vendorCall` `grant` → `src/coverage/calendar.ts`; the 30-minute case sets `env.DURATION_SCALE` for that call only |
| E2E-P3.3-10 | `vendorCall` `retirePlanVersion` → `vendorCall` `grant` → existing `term.plan_snapshot` |
| E2E-P3.3-11 | `env.DO.get(env.DO.idFromName(...)).fetch` POST with `contract_version` 1 → `negotiate(CHANNEL_VERSIONS.platformDo)` → echoed `contract_version` |
| E2E-P3.3-12 | The same `fetch` with `contract_version` missing or 2 → `rejected` `contract_version_unsupported` before any DO write |

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261003140000_plan_version_paid_grant_coverage.sql
├── schema.snap.sql
├── src/
│   ├── alert/
│   │   └── index.ts
│   ├── coverage/
│   │   └── calendar.ts
│   ├── quota-do/
│   │   └── index.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   ├── admission/index.ts
│   ├── credit/index.ts
│   ├── pipeline/index.ts
│   ├── usage-summary/index.ts
│   ├── control/quota-inspect.ts
│   └── worker.ts
├── test/
│   ├── system/
│   │   ├── harness.ts
│   │   └── paid-grant-coverage.system.test.ts
│   └── e2e/harness/
│       ├── d1.ts
│       └── gateway-object.ts
├── vitest.workers.config.ts
├── vitest.e2e.config.ts
└── wrangler.toml
```

**Structure Decision**: Source stays the existing Worker. `src/coverage/calendar.ts` is the only new source file the spec names. Grant placement, the DO tables, and the alarm ship are functions in `src/quota-do/index.ts`, which the unit row already names, and `GatewayObject` in `src/worker.ts` calls them. New `VendorEntrypoint` methods stay in `src/vendor/entrypoint.ts`. Alerts stay in `src/alert/index.ts` beside the existing AL-13 and AL-20 functions. The JSON blob helpers in `src/quota-do/index.ts` stay. `src/identity/index.ts` stays.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| AI-token verification rules | `IssuerTokenVerifier` in `ai-platform/src/identity/index.ts`. Frozen contract: `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/ai-token-verification.md`. This unit does not call or edit the verifier. |
| `tenant_binding` model (epoch) | Table `tenant_binding` from `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql`, including `tenant_binding_one_live_org`. Frozen contract: `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/tenant-binding.md`. A paid grant for an org with no active row inserts one `installation` and one `epoch` 1 `active` binding using that contract's column list. It does not edit `resolveInstallationId`, the 50-per-day cap, or AL-20. |
| Issuer-key methods | `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`, and `listIssuerKeys` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`. Frozen contract: `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/issuer-key-methods.md`. This unit does not change those methods or their AL-13 bodies. |

## Files

| File | FR |
| --- | --- |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/data-model.md` | FR-001, FR-002, FR-004, FR-006, FR-011, FR-012, FR-014 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/grant-paid.md` | FR-005, FR-007, FR-008, FR-009, FR-010 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/get-coverage.md` | FR-014 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/list-grants.md` | FR-016 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/read-coverage-events.md` | FR-016 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/service-key-methods.md` | FR-004 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/plan-version-methods.md` | FR-006, FR-015 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/do-schema.md` | FR-001, FR-002, FR-003 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/coverage-event.md` | FR-011, FR-012, FR-013 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/receipt-production.md` | FR-005 |
| `specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/quickstart.md` (implement, after verification) | FR-001 through FR-016 |
| `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/schema.snap.sql` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/src/coverage/calendar.ts` | FR-010 |
| `ai-platform/src/quota-do/index.ts` | FR-001, FR-002, FR-008, FR-010, FR-011 |
| `ai-platform/src/worker.ts` | FR-003, FR-011, FR-013 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-014, FR-015, FR-016 |
| `ai-platform/src/alert/index.ts` | FR-004, FR-013 |
| `ai-platform/src/admission/index.ts` | FR-003 |
| `ai-platform/src/credit/index.ts` | FR-003 |
| `ai-platform/src/pipeline/index.ts` | FR-003 |
| `ai-platform/src/usage-summary/index.ts` | FR-003 |
| `ai-platform/src/control/quota-inspect.ts` | FR-003 |
| `ai-platform/wrangler.toml` | FR-005, FR-010 |
| `ai-platform/vitest.workers.config.ts` | FR-005 |
| `ai-platform/vitest.e2e.config.ts` | FR-005 |
| `ai-platform/test/system/harness.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/e2e/harness/d1.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/e2e/harness/gateway-object.ts` | FR-003 |
| `ai-platform/test/migrations.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/system/paid-grant-coverage.system.test.ts` | FR-001 through FR-016 |
| `ai-platform/test/worker-request-orchestrator.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/token-contract-control.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/usage-summary.test.ts` | FR-003, FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/retention.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/plan-catalogue.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/identity.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/entitle-grant.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/config-readers.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/discovery-http.test.ts` | FR-004, FR-006, FR-011, FR-012 |
| `ai-platform/test/control.test.ts` | FR-004, FR-006, FR-011, FR-012 |

The test files in the last block apply `20261003130000_issuer_key_tenant_binding.sql` themselves. Each also applies `20261003140000_plan_version_paid_grant_coverage.sql` after it. `usage-summary.test.ts` also sends `contract_version` on its direct DO `fetch`. `src/identity/index.ts`, `src/config-cache/index.ts`, `src/vendor/contract-version.ts`, and `packages/vendor-contracts/**` stay as they are. The quota JSON blob helpers stay.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/paid-grant-coverage.system.test.ts` under H-AP. Each test calls the entry point below and fails while the method or the DO behaviour is absent. HP calls reuse `mintVendorAccessJwt`, `encodeVendorAssertion`, `createSoftwareAuthenticator`, and `setTestClock` the way `issuer-tokens.system.test.ts` reaches an active credential. The ABO signer is `createAboGrantSigner` from `vendor-contracts/testkit`. `vendorCall` gains the new method names on `VendorMethod`. Alarm tests import `runDurableObjectAlarm` from `cloudflare:test`.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.3-01 | H-AP | Title `E2E-P3.3-01 Publish plan v1 then a paid grant for a new org is applied, the receipt verifies, and the term is active`. `vendorCall` `publishPlanVersion` and `registerServiceKey`, then `vendorCall` `grant` with the testkit ABO key. `result` is `applied`, `verifyReceiptSignature` accepts the receipt with the platform public key, and the DO term is `active` with `starts_at` equal to the test clock. |
| E2E-P3.3-02 | H-AP | Title `E2E-P3.3-02 The same grant resent is already_applied with the identical receipt and one ledger row`. The second `vendorCall` `grant` is `already_applied` and the receipt JSON equals the first. `runDurableObjectAlarm` then leaves one `grant_ledger` row for that `grant_id`. |
| E2E-P3.3-03 | H-AP | Title `E2E-P3.3-03 The same grant_id with a changed allowance is conflict and nothing changes`. `result` is `conflict`. Term count, `hot.clinic_seq`, and the stored envelope hash stay as they were. |
| E2E-P3.3-04 | H-AP | Title `E2E-P3.3-04 A second paid grant is queued without dates and getCoverage shows queued_count 1 and coverage_through extended`. The new `term` row has null `starts_at` and `ends_at`. `getCoverage` is `ok`, `code` is empty, `receipt` is absent, and `detail` JSON has `queued_count` 1 and a `coverage_through` later than the active term's `ends_at`. |
| E2E-P3.3-05 | H-AP | Title `E2E-P3.3-05 An unregistered signing kid is transient unknown_kid and a revoked kid is rejected bad_signature`. The unknown-kid `grant` is `transient`, `detail` `unknown_kid`, and writes nothing. After `revokeServiceKey`, that key's `grant` is `rejected` `bad_signature`. |
| E2E-P3.3-06 | H-AP | Title `E2E-P3.3-06 Unpublished plan, allowance or grace over the bound, paid unit day, and placement immediate are refused`. The results are `plan_not_published`, `exceeds_plan_bound` for allowance above max times months and for grace of 8 days, `unit_not_allowed`, and `placement_not_supported`. Each writes nothing. |
| E2E-P3.3-07 | H-AP | Title `E2E-P3.3-07 After the alarm, coverage events, the ledger, the mirror, and R2 exist, and readCoverageEvents pages by feed_seq`. `clinic_seq` rises across the new `coverage_event` rows. `readCoverageEvents` is `ok` and `detail` JSON lists those events in ascending `feed_seq`. An R2 object exists at `grant-ledger/<grant_id>.ndjson`. |
| E2E-P3.3-08 | H-AP | Title `E2E-P3.3-08 AL-11 email per grant carries the decoded operation and org, and the fourth paid grant within 24 hours raises AL-17`. After `runDurableObjectAlarm`, captured `send_email` text is the AL-11 body. The fourth paid `grant` for that org, then the alarm, adds an AL-17 email. The grant `result` is still `applied`. No `sleep` over 2 s. |
| E2E-P3.3-09 | H-AP | Title `E2E-P3.3-09 A grant at 31 January 10:00 ends 28 February 10:00, or 29 February in a leap year, and the staging scale makes a month 30 minutes`. `setTestClock("2026-01-31T10:00:00.000Z")` with `DURATION_SCALE` unset ends `2026-02-28T10:00:00.000Z`. `setTestClock("2024-01-31T10:00:00.000Z")` ends `2024-02-29T10:00:00.000Z`. With `env.DURATION_SCALE` set, a monthly term's `ends_at` is 30 minutes after `starts_at`. |
| E2E-P3.3-10 | H-AP | Title `E2E-P3.3-10 retirePlanVersion refuses the next grant on that version and the existing term keeps its snapshot`. `retirePlanVersion` is `ok`. The next paid `grant` that names that version is `rejected` `plan_not_published`. The existing term's `plan_snapshot` is unchanged. |
| E2E-P3.3-11 | H-AP | Title `E2E-P3.3-11 A Worker to DO RPC with the current contract version is accepted and the answer echoes it`. `fetch` POST with `contract_version` 1 and `kind` `inspect` returns JSON whose `contract_version` is 1. |
| E2E-P3.3-12 | H-AP | Title `E2E-P3.3-12 A Worker to DO RPC with contract_version missing or 2 is rejected contract_version_unsupported before any write`. Both calls return `result` `rejected`, `code` `contract_version_unsupported`, and `accepted_versions` `[0, 1]`. DO SQL tables are unchanged and the JSON blob is unchanged. |

## Sequencing

Tests are written and observed failing before the paid-grant path exists. Each step is one task. The implied count is 32, inside size L (32–40).

1. Add `test/system/paid-grant-coverage.system.test.ts` with E2E-P3.3-01. Extend `VendorMethod` in `test/system/harness.ts`. Run the unit command. It fails because `publishPlanVersion` and `grant` are not on `VendorEntrypoint`.
2. Add E2E-P3.3-02. The run fails on the missing `grant` replay and the missing alarm ship.
3. Add E2E-P3.3-03. The run fails on the missing conflict path.
4. Add E2E-P3.3-04. The run fails on the missing queue and `getCoverage`.
5. Add E2E-P3.3-05. The run fails on the missing kid checks and `revokeServiceKey`.
6. Add E2E-P3.3-06. The run fails on the missing bound checks.
7. Add E2E-P3.3-07. The run fails on the missing alarm ship and `readCoverageEvents`.
8. Add E2E-P3.3-08. The run fails on the missing AL-11 and AL-17 emails.
9. Add E2E-P3.3-09, using `setTestClock` and assigning `env.DURATION_SCALE` only around the 30-minute grant. The run fails on the missing calendar.
10. Add E2E-P3.3-10. The run fails on the missing `retirePlanVersion`.
11. Add E2E-P3.3-11. The run fails because `GatewayObject.fetch` does not echo `contract_version`.
12. Add E2E-P3.3-12. The run fails because a missing version is still dispatched.
13. Add `migrations/20261003140000_plan_version_paid_grant_coverage.sql` with `service_key`, `plan_version`, `coverage_event`, `grant_ledger`, `coverage_mirror`, and the indexes in `data-model.md`. Replace `schema.snap.sql` with the post-migration dump. Add those tables to `PLATFORM_ENTITIES` in `test/migrations.test.ts`. The twelve E2E tests still fail.
14. Apply that migration from `test/system/harness.ts`, `test/e2e/harness/d1.ts`, and every other test file that applies `20261003130000_issuer_key_tenant_binding.sql`, in timestamp order. Reset deletes the new tables. The twelve E2E tests still fail.
15. Add `src/coverage/calendar.ts` with unscaled month clamping and day multiples of 24 hours. The staging scale is step 29. E2E-P3.3-09 still fails on the missing grant path.
16. At the start of `GatewayObject.fetch`, before any storage read or write, `negotiate(CHANNEL_VERSIONS.platformDo, contract_version)`. Missing or unsupported, including 2, returns the refusal in `contracts/do-schema.md` and writes nothing. A supported call echoes that version on the JSON answer. Add `contract_version: CHANNEL_VERSIONS.platformDo` to the DO bodies in `src/admission/index.ts`, `src/credit/index.ts`, `src/pipeline/index.ts`, `src/usage-summary/index.ts`, `src/control/quota-inspect.ts`, and the direct fetch in `test/usage-summary.test.ts`. `gatewayObjectRpc` sets the same field when the body omits it. E2E-P3.3-11 and E2E-P3.3-12 pass.
17. On the first `GatewayObject.fetch` that has passed the version check, create `hot`, `term`, `grant`, and `outbox` with `CREATE TABLE IF NOT EXISTS` inside `blockConcurrencyWhile`. Leave the `state` blob and `admissionRPC`, `creditRPC`, `releaseRPC`, and `inspectRPC` in place.
18. Add `PLATFORM_SIGNING_KEY` to the three wrangler env var blocks and to both vitest binding sets, using the local stand-in JSON in `contracts/receipt-production.md`. Add `DURATION_SCALE` = `staging` only under `[env.staging.vars]`. Development, production, and both vitest configs omit `DURATION_SCALE`. No `TEST_CLOCK` in wrangler.
19. Add `registerServiceKey`, `revokeServiceKey`, and `listServiceKeys` using the existing HP and M paths. Results match `contracts/service-key-methods.md`. E2E-P3.3-05 still fails until `grant` checks the key.
20. Raise service-key AL-13 from `src/alert/index.ts` without changing the credential or issuer-key AL-13 bodies. Repeat once. Unsent retry rebuilds an `AL-13:service_key:` key from `service_key` and `control_audit`.
21. Add `publishPlanVersion` and `retirePlanVersion` using the existing HP path. Results match `contracts/plan-version-methods.md`.
22. Implement paid `grant` checks in `contracts/grant-paid.md` through step 3, before any binding or DO write. E2E-P3.3-05 and E2E-P3.3-06 pass.
23. After those checks, resolve or insert the active binding with the consumed contract's column list. Do not edit `src/identity/index.ts`. A unique conflict re-reads the active row.
24. Add DO kind `apply_grant`. Place the term, sign the receipt, and write `grant`, `term`, `hot`, and `outbox` in one `blockConcurrencyWhile`. The same hash returns the stored receipt and writes nothing else. A different hash returns `conflict` and writes nothing. E2E-P3.3-01, E2E-P3.3-03, the unscaled half of E2E-P3.3-09, and E2E-P3.3-10 pass.
25. Add `GatewayObject.alarm`. Ship outbox rows as `contracts/coverage-event.md` describes, then delete them. `setAlarm` runs only when `next_alarm_at` changes. E2E-P3.3-02 passes. E2E-P3.3-07 still fails on the missing `readCoverageEvents` method.
26. Add `getCoverage` and DO kind `read_coverage`. E2E-P3.3-04 passes.
27. Add `listGrants` and `readCoverageEvents` over D1. E2E-P3.3-07 passes.
28. On apply, enqueue AL-11 and, when the velocity condition holds, AL-17. The alarm sends them through `src/alert/index.ts`. AL-17's `next_send_at` is one hour ahead. `runFiveMinuteCron` retries a due AL-17 without changing the AL-20 path. E2E-P3.3-08 passes.
29. Honour `env.DURATION_SCALE` inside `src/coverage/calendar.ts` for the 30-minute case. E2E-P3.3-09 passes.
30. Re-run the unit command and confirm E2E-P3.3-01 through E2E-P3.3-12 pass together.
31. Run `cd ai-platform && npm test && npm run test:e2e`. Earlier suites stay green (rule S2). Admission still uses the JSON blob. A DO JSON equality assertion that fails only because `contract_version` was added to an existing kind's answer is updated to expect that field. Outcomes of `admission`, `credit`, `release`, and `inspect` stay as they are.
32. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
