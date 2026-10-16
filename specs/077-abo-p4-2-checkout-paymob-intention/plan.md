# Implementation Plan: Checkout creation, Paymob intention, coverage view and the cross-worker harness

**Branch**: `ai/077-abo-p4-2-checkout-paymob-intention` | **Date**: 2026-10-06 | **Spec**: `specs/077-abo-p4-2-checkout-paymob-intention/spec.md`

**Input**: Feature specification from `specs/077-abo-p4-2-checkout-paymob-intention/spec.md`

## Summary

An administrator opens a checkout for the current sellable offer. The ABO stores the snapshot, reads coverage from the real platform `VendorEntrypoint` (falling back to `coverage_view`), and calls the Paymob adapter `createCheckout`. Depends on P4.1 and P3.3. Phase P4, size L. The R-2 expiry outcome is already recorded in `research.md`: `expiration` 1800 s, `expires_at` = creation plus 30 minutes, checked on the H-PAY stub.

## Technical Context

**Language/Version**: TypeScript on the existing `abo/` Cloudflare Worker (wrangler, workers types, vitest workers pool already in `abo/package.json`).

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`) for the clinic envelope helpers already used by `abo/src/clinic-api/version.ts`, `ulid`, `humanRef`, `CHANNEL_VERSIONS`, and `validateResultEnvelope` shapes. No new library.

**Storage**: ABO D1 (`DB`) for `checkout`, `checkout_event`, `checkout_status`, `paymob_intention`, `coverage_view`, `feed_cursor`, plus the consumed `fact_log`. Platform D1 and the per-clinic DO stay on the ai-platform worker, reached only through `VendorEntrypoint`.

**Testing**: H-XW + H-PAY for E2E-P4.2-01 through E2E-P4.2-07. H-XW for E2E-P4.2-08. Import-boundary CI for E2E-P4.2-09. Titles are prefixed with the E2E id. The ABO clock is the consumed `clockNowMs`. `TEST_CLOCK` stays off production and staging wrangler envs.

**Target Platform**: `abo/` Worker. Billing hostname `SELF.fetch`. Minute cron `runScheduled` for `* * * * *`.

**Project Type**: One Cloudflare Worker (`abo`). No second codebase.

**Performance Goals**: 10 checkouts per tenant per hour, on top of the consumed 60 requests per token. A local scenario spends at most 2 seconds of real time. The intention abort is 500 ms when `TEST_CLOCK` is `"1"`.

**Constraints**: Provider HTTP stays inside `abo/src/provider/paymob/client.ts`. The domain does not import the adapter. `return_url` carries `v` = `CHANNEL_VERSIONS.paymobReturn` (1). `billing_token_jti` stores the token `jti`. Checkout `expires_at` is the ABO clock plus 30 minutes. Append-only checkout facts follow the consumed `fact_log` and abort triggers.

**Scale/Scope**: One clinic administrator opening and reading checkouts, and one minute cron copying the platform coverage feed. Codebase `abo` only.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution v2.0.0 and 02 §7. 02 §7 records that this design complies. No box is unchecked.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

02 §7 I: one Worker, D1, crons, no queues or Kubernetes. This unit adds checkout routes on that Worker. 02 §7 II: the provider sits behind the port; the ABO is vendor-side and holds no clinic database credential. 02 §7 III: vendor-side integrity is D1 append-only triggers and unique keys; clinic state stays in PostgreSQL, which this unit does not write. 02 §7 IV: the billing token is verified by the consumed auth path; the tenant is the token `org`; another tenant's id is `not_found`; checkout facts are not hard-deleted. 02 §7 V: a `getCoverage` failure still creates the checkout from `coverage_view`, so a platform outage does not block the sale.

## Project Structure

### Documentation (this feature)

```text
specs/077-abo-p4-2-checkout-paymob-intention/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md          # implement writes this after the harness is green
├── contracts/
│   ├── checkout-api.md
│   ├── provider-port.md
│   └── harness.md
└── tasks.md               # not created in this phase
```

`quickstart.md` sections, written after verification:

- What was implemented, and the files added or modified
- The harness commands for this unit's tests only: `npm run test:cross-worker` and `npm run test:import-boundary` from `abo/`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- No manual steps; the harness observes every scenario

### Source Code (repository root)

```text
abo/
├── migrations/0002_checkout.sql
├── scripts/
│   ├── build-platform-for-hxw.mjs
│   └── check-import-boundary.mjs
├── src/
│   ├── worker.ts                          # modify
│   ├── clinic-api/checkouts.ts
│   ├── coverage/view.ts
│   └── provider/
│       ├── port.ts
│       ├── registry.ts
│       └── paymob/
│           ├── adapter.ts
│           └── client.ts
├── test/
│   ├── fixtures/import-boundary/bad/src/
│   ├── import-boundary/boundary.test.mjs
│   ├── stubs/
│   │   ├── paymob/worker.ts
│   │   └── platform-throw/worker.ts
│   └── system/
│       ├── cross-worker-harness.ts
│       ├── checkout.cross-worker.test.ts
│       ├── checkout-throw.cross-worker.test.ts
│       └── coverage-view.cross-worker.test.ts
├── vitest.cross-worker.config.ts
├── vitest.platform-throw.config.ts
├── wrangler.toml                          # modify
└── package.json                           # modify

.github/workflows/ci.yml                   # modify
```

**Structure Decision**: All of this unit lives in `abo/`. Checkout routes sit next to the existing clinic API. The Paymob HTTP client is the only provider module. The cross-worker vitest configs are separate from `abo/vitest.workers.config.ts`, so the existing H-ABO include (`test/system/**/*.system.test.ts`) does not pick up these tests.

## Consumes Binding

| Consumes | Existing module |
| --- | --- |
| Clinic-API envelope, auth, and error rules | `abo/src/clinic-api/version.ts` (`checkContractVersion`, `clinicJsonResponse`, `clinicErrorResponse`); `abo/src/clinic-api/auth.ts` (`authenticateBilling`, `BillingClaims.jti`); `abo/src/clinic-api/rate.ts` (`checkTokenRate`, 60 per token) |
| Records conventions | `abo/src/records/append.ts` (`fact_log` insert shape); `abo/migrations/0001_records.sql` (append-only trigger form); `vendor-contracts` `ulid`, `humanRef`, `canonicalize`, `sha256Hex` |
| Alert engine | `abo/src/alert/index.ts` (`markExportLagIfDue`, `sendDueAlerts`). This unit does not change it. The minute cron keeps calling it. |
| H-ABO | `abo/test/system/harness.ts` (`mintBilling`, `setClock`, `SELF` fetch helpers). New tests import it. This unit does not change the file. |
| `grant` (paid), `getCoverage`, `listGrants`, `readCoverageEvents` | `ai-platform/src/vendor/entrypoint.ts` class `VendorEntrypoint`, re-exported from `ai-platform/src/worker.ts` |
| Service-key and plan-version methods | `VendorEntrypoint.registerServiceKey`, `revokeServiceKey`, `listServiceKeys`, `publishPlanVersion`, `retirePlanVersion` |
| DO schema | `ai-platform/src/quota-do/index.ts` `COVERAGE_DO_SCHEMA_STATEMENTS` (`hot`, `term`, `grant`, `outbox`) via `ensureCoverageDoTables` |
| Event and receipt shapes | `packages/vendor-contracts/src/feed-event.ts` `validateFeedEvent`; `packages/vendor-contracts/src/coverage-snapshot.ts` `validateCoverageSnapshot` (`state`, `coverage_through`, `binding_epoch`, `clinic_seq`); `packages/vendor-contracts/src/receipt.ts` `validateReceipt`; `packages/vendor-contracts/src/result-envelope.ts` `validateResultEnvelope` (`transient` detail `unavailable`) |
| Catalogue and contact rows this unit reads | `abo/src/clinic-api/offers.ts` sellable query (latest `published` `offer_event`); `abo/src/clinic-api/billing-contact.ts` latest version. Neither file is modified. |
| Clock | `abo/src/clock.ts` `clockNowMs` / `clockNowIso` |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `abo/migrations/0002_checkout.sql` | Create | FR-001, FR-005, FR-008 |
| `abo/src/provider/port.ts` | Create | FR-005 |
| `abo/src/provider/registry.ts` | Create | FR-001, FR-005 |
| `abo/src/provider/paymob/client.ts` | Create | FR-001, FR-009 |
| `abo/src/provider/paymob/adapter.ts` | Create | FR-001, FR-005, FR-009 |
| `abo/src/clinic-api/checkouts.ts` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 |
| `abo/src/coverage/view.ts` | Create | FR-003, FR-008 |
| `abo/src/worker.ts` | Modify | FR-001, FR-002, FR-007, FR-008 |
| `abo/wrangler.toml` | Modify | FR-001, FR-002 |
| `abo/test/stubs/paymob/worker.ts` | Create | FR-001, FR-005, FR-009 |
| `abo/test/stubs/platform-throw/worker.ts` | Create | FR-003 |
| `abo/test/system/cross-worker-harness.ts` | Create | FR-002, FR-009 |
| `abo/test/system/checkout.cross-worker.test.ts` | Create | FR-001, FR-002, FR-004, FR-005, FR-006, FR-007 |
| `abo/test/system/checkout-throw.cross-worker.test.ts` | Create | FR-003 |
| `abo/test/system/coverage-view.cross-worker.test.ts` | Create | FR-008 |
| `abo/vitest.cross-worker.config.ts` | Create | FR-002, FR-009 |
| `abo/vitest.platform-throw.config.ts` | Create | FR-003, FR-009 |
| `abo/scripts/build-platform-for-hxw.mjs` | Create | FR-002, FR-009 |
| `abo/scripts/check-import-boundary.mjs` | Create | FR-009 |
| `abo/test/fixtures/import-boundary/bad/src/**` | Create | FR-009 |
| `abo/test/import-boundary/boundary.test.mjs` | Create | FR-009 |
| `abo/package.json` | Modify | FR-009 |
| `.github/workflows/ci.yml` | Modify | FR-009 |
| `specs/077-abo-p4-2-checkout-paymob-intention/research.md` | Created this phase | FR-001 |
| `specs/077-abo-p4-2-checkout-paymob-intention/data-model.md` | Created this phase | FR-001, FR-005, FR-008 |
| `specs/077-abo-p4-2-checkout-paymob-intention/contracts/checkout-api.md` | Created this phase | FR-001, FR-004, FR-006, FR-007 |
| `specs/077-abo-p4-2-checkout-paymob-intention/contracts/provider-port.md` | Created this phase | FR-001, FR-005 |
| `specs/077-abo-p4-2-checkout-paymob-intention/contracts/harness.md` | Created this phase | FR-002, FR-003, FR-009 |

Wire shapes, table columns, and harness routes are those three contracts plus `data-model.md`. `quickstart.md` is not written in this phase.

`worker.ts` keeps the consumed version, auth, and per-token rate gates, then dispatches `POST /v1/checkouts`, `GET /v1/checkouts/{id}`, and `GET /v1/checkouts?open=1` on the billing host. The minute branch of `scheduled` keeps export, heartbeat, and alerts, and adds `refreshCoverageView`. A throw from the platform feed is caught so those consumed steps still run.

`wrangler.toml` gains `PAYMOB_BASE_URL`, `PAYMOB_SECRET_KEY`, `PAYMOB_PUBLIC_KEY`, and `PAYMOB_CARD_INTEGRATION_ID` on development, staging, and production, plus a `PLATFORM` service binding (`entrypoint = "VendorEntrypoint"`) to `ai-platform-gateway-development`, `ai-platform-gateway-staging`, and `ai-platform-gateway-production`. No `TEST_CLOCK` var is added.

`package.json` scripts: `test:cross-worker` runs the build script, then `vitest run --config vitest.cross-worker.config.ts`, then `vitest run --config vitest.platform-throw.config.ts`. `test:import-boundary` runs `node scripts/check-import-boundary.mjs src` and `node --test test/import-boundary/boundary.test.mjs`.

CI adds job `abo-cross-worker` (npm ci in `abo/` and `ai-platform/`, then `npm run test:cross-worker`) and job `abo-import-boundary` (`npm run test:import-boundary` in `abo/`).

## Test Layout

| ID | Harness | Title prefix | Entry | Proves |
| --- | --- | --- | --- | --- |
| E2E-P4.2-01 | H-XW + H-PAY | `E2E-P4.2-01` | `SELF.fetch` `POST /v1/checkouts`, billing host | FR-001. 201, `redirect_url`, `CK-` reference, `expires_at` = clock + 30 min. Stub body has piastres and `special_reference` = reference, `expiration` = 1800 |
| E2E-P4.2-02 | H-XW + H-PAY | `E2E-P4.2-02` | Same POST; real `PLATFORM` `VendorEntrypoint` | FR-002. Active snapshot → `starts=after_current`, `projected_start` = `coverage_through` |
| E2E-P4.2-03 | H-XW + H-PAY | `E2E-P4.2-03` | Same POST; throw config | FR-003. Throw → checkout created, `coverage_source=view`. A second org ending `aa` gets `transient` and the same fallback |
| E2E-P4.2-04 | H-XW + H-PAY | `E2E-P4.2-04` | Same POST | FR-004. Superseded version → 409 `offer_unavailable` and `current_version`. No contact → `billing_contact_required`. Stale terms → `terms_not_accepted` |
| E2E-P4.2-05 | H-XW + H-PAY | `E2E-P4.2-05` | Same POST; stub `refuse` then `timeout` | FR-005. 503 `provider_unavailable`, `open_failed` event, shown `Abandoned` |
| E2E-P4.2-06 | H-XW + H-PAY | `E2E-P4.2-06` | Same POST | FR-006. Same `client_request_id` returns the same `checkout_id`. The 11th distinct id in the hour → 429 `rate_limited` |
| E2E-P4.2-07 | H-XW + H-PAY | `E2E-P4.2-07` | `GET /v1/checkouts/{id}` and `GET /v1/checkouts?open=1` | FR-007. Other tenant → 404 `not_found`. Two open checkouts for A are both listed |
| E2E-P4.2-08 | H-XW | `E2E-P4.2-08` | `runScheduled` cron `* * * * *`; real `PLATFORM` | FR-008. `coverage_view` updates. After the test raises the stored pair and resets `feed_cursor`, the older pair is ignored |
| E2E-P4.2-09 | import-boundary CI | `E2E-P4.2-09` | `check-import-boundary.mjs` on the bad fixture | FR-009. Exit 1 |

E2E-P4.2-01 through E2E-P4.2-07 except E2E-P4.2-03 live in `checkout.cross-worker.test.ts`. E2E-P4.2-03 lives in `checkout-throw.cross-worker.test.ts`. E2E-P4.2-08 lives in `coverage-view.cross-worker.test.ts`. E2E-P4.2-09 lives in `boundary.test.mjs`. Each file's test title starts with the E2E id. Tests are written and run first, and they fail before the implementation exists.

Module chains the quickstart will record:

- E2E-P4.2-01, 04, 05, 06: `worker.ts` → `checkouts.ts` → `registry.ts` → `adapter.ts` → `client.ts` → H-PAY
- E2E-P4.2-02: that chain, plus `PLATFORM.getCoverage`
- E2E-P4.2-03: `checkouts.ts` reads `coverage_view` after the throw or `transient` result
- E2E-P4.2-07: `worker.ts` → `checkouts.ts` read paths
- E2E-P4.2-08: `worker.ts` `scheduled` → `coverage/view.ts` → `PLATFORM.readCoverageEvents`
- E2E-P4.2-09: `check-import-boundary.mjs` on the fixture tree

## Sequencing

Tests are added and run before the production modules, and the run is expected to fail.

1. Cross-worker and import-boundary tests (red): the nine E2E titles above, the paymob and platform-throw stubs, both vitest configs, the build script, and the boundary script with the bad fixture.
2. Migration `0002_checkout.sql`.
3. Port, registry, Paymob client, and adapter, including `paymob_intention` writes.
4. `checkouts.ts` and the `worker.ts` routes (`POST`, GET one, GET `open=1`).
5. `coverage/view.ts` and the minute-cron call.
6. `wrangler.toml` bindings and `package.json` scripts.
7. CI jobs `abo-cross-worker` and `abo-import-boundary`.
8. Re-run `npm run test:cross-worker` and `npm run test:import-boundary` from `abo/` until those tests are green. Then write `quickstart.md`.

`abo/vitest.workers.config.ts`, `abo/src/clinic-api/auth.ts`, `version.ts`, `rate.ts`, `offers.ts`, `billing-contact.ts`, `abo/src/records/append.ts`, `abo/src/alert/`, `abo/src/clock.ts`, and `abo/test/system/harness.ts` stay as they are. Platform and `vendor-contracts` sources stay as they are.

## Complexity Tracking

02 §7 records no constitution violation for this design. Nothing to justify.
