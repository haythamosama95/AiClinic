# Implementation Plan: ABO skeleton, records layer, billing-token auth and catalogue reads

**Branch**: `ai/076-abo-p4-1-abo-skeleton-records-layer-billing-token` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P4.1 adds the `abo/` Worker: hostname routing, `Abo-Contract-Version` before auth, billing-token checks against pinned `ISSUER_KEYS`, catalogue reads, the records export, the alert engine, and the minute heartbeat. It is phase P4, size L, **Depends** P2.2, in parallel with P3.1–P3.3 and P1.x.

## Technical Context

**Language/Version**: TypeScript ESM on the Workers runtime. New top-level package `abo/`. Entry `abo/src/worker.ts` exports `fetch` and `scheduled`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), the frozen package from P2.2. Wrangler, Vitest, and `@cloudflare/vitest-pool-workers` match the versions in `ai-platform/package.json`. This unit adds no other library and does not change the package.

**Storage**: New D1 binding `DB` and R2 binding `R2`. Tables in [data-model.md](./data-model.md). Terms text and `ledger/<fact_seq>.ndjson` live in R2. `send_email` binding `SEND_EMAIL`.

**Testing**: H-ABO in `abo/test/system/` under `abo/vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the behavior exists. Time moves through `abo/src/clock.ts`. `TEST_CLOCK` is bound only in that vitest config. No local scenario sleeps more than 2 s. `send_email` and the heartbeat are captured (rule V6). H-ABO answers the lock-rules GET. New CI job `abo-system` runs this package's harness only (rule V7).

**Target Platform**: One Cloudflare Worker. Live entries are `SELF.fetch` on `fetch` (billing host and ops host) and `runScheduled` on `scheduled`.

**Project Type**: New Worker in `abo/`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Catalogue reads and contact writes for a clinic administrator. The clinic API allows 60 requests per billing token. The minute cron exports pending facts in `fact_seq` order and pings `HEARTBEAT_URL`.

**Constraints**: Version check and the cross-host rejection run before authentication and before any write. Tokens are checked with `validateTokenClaims` against `ISSUER_KEYS` and `ISSUER_ID`. The tenant is the token `org`. Contact values stay off append-only rows and off `ledger/`. The lock check is a GET only. Hourly and 6-hourly crons are declared and do no other job. Offer publication, erasure, checkouts, and the console stay out of this unit.

**Scale/Scope**: Size L (rule S3: 3–4 user stories, one codebase). Four user stories and ten E2E ids. Implied task count is 30. That is the sequencing below and is not padded (rule S3, plan skill).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is None, so there is no `research.md`. The spec defines entities, so [data-model.md](./data-model.md) is in this phase. **Freezes** includes the clinic-API envelope, so [contracts/clinic-api.md](./contracts/clinic-api.md) is in this phase. No clinic PostgreSQL write and no second service. The same boxes hold after the design below.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  An administrator lists that clinic's sellable offers and keeps one billing contact. The tenant comes from the billing token (spec §4.1, 02 §7 principle I). The unit adds no second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  One new Worker with D1, R2, and crons. Background work is the scheduled handler over D1 and R2. No queue and no extra service (02 §7 principle I and the workflow-automation row).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `abo/` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The Worker has no clinic database credential. The shared package is consumed and not rewritten.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 and R2 only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 append-only triggers. Clinic RPCs, RLS, and triggers stay as they are. Append-only ABO tables abort UPDATE and DELETE.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `/v1` calls require a billing token with `role=administrator` after the version check (02 §7 principle IV, 04 §2.2). The tenant is the token `org`. Cross-host paths are rejected first. Alert bodies carry codes and ids only. This unit does not erase contact rows.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from a model to D1 or R2 (02 §7 principles II and V). Clinical work is outside this Worker.

## Project Structure

### Documentation (this feature)

```text
specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/
├── plan.md
├── data-model.md
├── spec.md
├── contracts/
│   └── clinic-api.md
├── quickstart.md              # implement writes this after verification; outline below
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is None).

#### quickstart.md outline

Implement writes `quickstart.md` after the harness command is green. Sections:

1. What was implemented — the `abo/` Worker: host gate, contract version, billing-token auth, `GET /v1/offers`, `GET`/`PUT /v1/billing-contact`, records export, AL-16, and the heartbeat.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system
```

`npm test` in other packages, and any command that runs more than `abo/test/system`, stay out of this file (rule S8).

4. Entry point to module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P4.1-01 | `SELF.fetch` → `worker.ts` host gate → `clinic-api/version.ts` (`negotiate`) → 400 body. No auth module and no D1 write. |
| E2E-P4.1-02 | `SELF.fetch` → host gate → version gate → `clinic-api/auth.ts` (`validateTokenClaims`, pinned `ISSUER_KEYS`) → 401 or 403. |
| E2E-P4.1-03 | `SELF.fetch` `GET /v1/offers` → host, version, auth, `clinic-api/rate.ts` → `clinic-api/offers.ts` → D1 sellable rows → R2 terms text. |
| E2E-P4.1-04 | `SELF.fetch` `PUT /v1/billing-contact` → the same gate → `clinic-api/billing-contact.ts` → D1 `billing_contact`. |
| E2E-P4.1-05 | `SELF.fetch` `GET`/`PUT /v1/billing-contact` → the same gate → `billing-contact.ts` filtered by the token `org`. |
| E2E-P4.1-06 | `SELF.fetch` → `worker.ts` host gate → 404 empty body. Version and auth do not run. |
| E2E-P4.1-07 | D1 `UPDATE`/`DELETE` hit the abort triggers. `records/append.ts` writes `fact_log`. `runScheduled` minute → `records/export.ts` → R2 `ledger/<fact_seq>.ndjson`. |
| E2E-P4.1-08 | `runScheduled` → `clock.ts` → `alert/index.ts` export-lag and `alert/lock.ts` GET → `SEND_EMAIL` capture. |
| E2E-P4.1-09 | `SELF.fetch` → host, version, auth → `clinic-api/rate.ts` → 429 when `token_use.hits` is 60. |
| E2E-P4.1-10 | `runScheduled` minute → `worker.ts` → outbound fetch to `HEARTBEAT_URL`. |

### Source Code (repository root)

```text
abo/
├── package.json
├── package-lock.json
├── tsconfig.json
├── wrangler.toml
├── vitest.workers.config.ts
├── fixtures/
│   └── offers.json
├── migrations/
│   └── 0001_records.sql
├── src/
│   ├── worker.ts
│   ├── clock.ts
│   ├── clinic-api/
│   │   ├── version.ts
│   │   ├── auth.ts
│   │   ├── rate.ts
│   │   ├── offers.ts
│   │   └── billing-contact.ts
│   ├── records/
│   │   ├── append.ts
│   │   └── export.ts
│   └── alert/
│       ├── index.ts
│       └── lock.ts
└── test/
    └── system/
        ├── harness.ts
        ├── catalogue.system.test.ts
        └── wrangler-clock.system.test.ts

.github/workflows/ci.yml
```

**Structure Decision**: New Worker under `abo/`. Clinic API code is the `/v1` gate and the two catalogue routes. Records code is the append writer and the minute exporter. Alert code is dedupe, send, retry, the export-lag condition, and the daily lock GET. Notification intake, the pipeline, provider adapters, the operator console, and reconciliation matching have no folders and no code. `ai-platform/wrangler.toml` is the pattern for env layout, `workers_dev`, `preview_urls`, observability, D1, R2, `send_email`, and cron declarations.

## Consumes Binding

The package is already frozen (CP-A). This unit depends on it and does not modify it.

| Consumes entry | Existing module |
| --- | --- |
| 04 §1.2 result envelope | `packages/vendor-contracts/src/result-envelope.ts` (`validateResultEnvelope`), exported from `src/index.ts` |
| 04 §1.3 method catalogue | `packages/vendor-contracts/src/index.ts` (the frozen message validators below). This unit does not add a method and does not call `VendorEntrypoint` |
| 04 §1.4 grant envelope | `packages/vendor-contracts/src/grant-envelope.ts` (`validateGrantEnvelope`) |
| 04 §1.5 operator assertion | `packages/vendor-contracts/src/operation.ts` (`validateOperation`), `packages/vendor-contracts/src/webauthn.ts` (`verifyAssertion`) |
| 04 §1.6 receipt | `packages/vendor-contracts/src/receipt.ts` (`validateReceipt`) |
| 04 §1.7 coverage snapshot | `packages/vendor-contracts/src/coverage-snapshot.ts` (`validateCoverageSnapshot`) |
| 04 §2.1 token claims | `packages/vendor-contracts/src/token-claims.ts` (`validateTokenClaims`) |
| Verification APIs | `validateTokenClaims`; `negotiate`, `acceptedVersions`, and `CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts`; `canonicalize` and `sha256Hex` in `packages/vendor-contracts/src/canonical.ts`; `ulid` in `packages/vendor-contracts/src/identifiers.ts` |
| Testkit API | `packages/vendor-contracts/src/testkit/index.ts` (`createIssuer`) |
| CP-A | `packages/vendor-contracts/` as frozen by P2.2. This unit's harness does not re-run the package suite |

## Files

| File | FR |
| --- | --- |
| `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/data-model.md` | FR-006, FR-007, FR-008, FR-009 |
| `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/contracts/clinic-api.md` | FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 |
| `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/quickstart.md` (implement, after verification) | FR-001 through FR-010 |
| `abo/package.json` | FR-001, FR-010 |
| `abo/package-lock.json` | FR-001, FR-010 |
| `abo/tsconfig.json` | FR-001 |
| `abo/wrangler.toml` | FR-001, FR-002, FR-004, FR-009, FR-010 |
| `abo/vitest.workers.config.ts` | FR-010 |
| `abo/migrations/0001_records.sql` | FR-006, FR-007, FR-008, FR-009 |
| `abo/fixtures/offers.json` | FR-006 |
| `abo/src/worker.ts` | FR-001, FR-002, FR-010 |
| `abo/src/clock.ts` | FR-010 |
| `abo/src/clinic-api/version.ts` | FR-003 |
| `abo/src/clinic-api/auth.ts` | FR-004 |
| `abo/src/clinic-api/rate.ts` | FR-005 |
| `abo/src/clinic-api/offers.ts` | FR-006 |
| `abo/src/clinic-api/billing-contact.ts` | FR-007 |
| `abo/src/records/append.ts` | FR-008 |
| `abo/src/records/export.ts` | FR-008 |
| `abo/src/alert/index.ts` | FR-009 |
| `abo/src/alert/lock.ts` | FR-009 |
| `abo/test/system/harness.ts` | FR-004, FR-009, FR-010 |
| `abo/test/system/catalogue.system.test.ts` | FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 |
| `abo/test/system/wrangler-clock.system.test.ts` | FR-010 |
| `.github/workflows/ci.yml` | FR-010 |

`packages/vendor-contracts/**` stays. No file under `backend/`, `frontend/`, or `ai-platform/` changes.

## Test Layout

Titles start with the E2E id (rule V3). All ten E2E tests live in `abo/test/system/catalogue.system.test.ts` under H-ABO (`vitest.workers.config.ts`). Each calls the entry below and fails while the behavior it names is absent. The clock config test lives in `abo/test/system/wrangler-clock.system.test.ts` in the same harness. No scenario sleeps more than 2 s. The harness advances `harness_test_clock` through `abo/src/clock.ts`.

Hosts are `billing.vendor.test` and `ops.vendor.test` (`BILLING_HOST`, `OPS_HOST`). Billing tokens come from `createIssuer().mintBilling`. AI tokens come from `mintAi`. The harness writes the pinned `{kid, public_key}` rows into D1 `harness_issuer_pin` (at least two kids). `auth.ts` reads that table only when `TEST_CLOCK` is `"1"`. Otherwise it reads `ISSUER_KEYS`.

The harness answers `GET https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/r2/buckets/{R2_BUCKET_NAME}/lock`. Unless a test sets another body, the body is `{"success":true,"result":{"rules":[{"enabled":true,"condition":{"type":"Indefinite"},"prefix":"ledger/"}]}}`.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P4.1-01 | H-ABO | Title `E2E-P4.1-01 missing or unsupported Abo-Contract-Version is 400 before auth`. `SELF.fetch` `/v1/offers` on the billing host and `/ops/lookup` on the ops host, each with an invalid bearer and no `Abo-Contract-Version`, then again with `Abo-Contract-Version: 2`. Both are HTTP 400 `contract_version_unsupported`. Body is `{code, message, contract_version, accepted_versions}` with `contract_version` 1 and `accepted_versions` `[0, 1]`. Response header `Abo-Contract-Version` is `1`. `token_use` and `billing_contact` stay unchanged. |
| E2E-P4.1-02 | H-ABO | Title `E2E-P4.1-02 AI token and unpinned kid are 401 and doctor is 403`. Header `Abo-Contract-Version: 1` on the billing host. `mintAi` → 401 `unauthenticated`. `mintBilling` from an issuer whose kid is not in `harness_issuer_pin` → 401 `unauthenticated`. `mintBilling` with `role` `doctor` on a pinned kid → 403 `forbidden_role`. |
| E2E-P4.1-03 | H-ABO | Title `E2E-P4.1-03 GET offers lists the sellable latest version and echoes version 1`. After the fixture, `GET /v1/offers` returns the published offer's latest version, `plan_display_name`, terms `version` and text, and omits the retired offer and the older price. Response header `Abo-Contract-Version` is `1` and body `contract_version` is `1`. |
| E2E-P4.1-04 | H-ABO | Title `E2E-P4.1-04 PUT billing contact is idempotent and rejects a non-E.164 phone`. Two `PUT`s with the same `client_request_id` leave one row at version 1. A new `client_request_id` creates version 2. Phone `12345` → 422 `invalid_request` and does not insert a version. |
| E2E-P4.1-05 | H-ABO | Title `E2E-P4.1-05 tenant B does not receive tenant A contact`. After A has a contact, B's `GET` is `not_found`. B's `PUT` whose body includes A's `org` stores B's `org` from the token. A's `GET` still returns A's contact. |
| E2E-P4.1-06 | H-ABO | Title `E2E-P4.1-06 cross-host paths are 404 before version and auth`. `/ops/lookup` on the billing host and `/v1/offers` on the ops host → HTTP 404, empty body, no `Abo-Contract-Version` response header. A missing version header on those crossings still yields that 404. No D1 write. |
| E2E-P4.1-07 | H-ABO | Title `E2E-P4.1-07 append-only rejects update and delete and the minute cron exports facts`. `UPDATE` and `DELETE` on `offer` abort. An append insert has one `fact_log` row. `runScheduled("* * * * *")` writes R2 `ledger/<fact_seq>.ndjson` in `fact_seq` order, one JSON line, and the object text has no `name`, `email`, or `phone`. |
| E2E-P4.1-08 | H-ABO | Title `E2E-P4.1-08 export lag raises AL-16 once then daily and a failed send is retried`. With the default lock body, advance the clock more than one hour past an unexported fact and run the minute cron: one AL-16 email whose body is the code and that `fact_seq`. Advance the clock 24 hours and run the minute cron again: a second email. A `send_email` failure leaves the alert due; the next minute run sends it. The daily cron with the default lock body does not send a lock AL-16. The daily cron with `{"success":true,"result":{"rules":[]}}` sends a lock AL-16 whose body is the code and `r2-lock`. A non-success lock response sends no lock AL-16. |
| E2E-P4.1-09 | H-ABO | Title `E2E-P4.1-09 the 61st request with one billing token is 429`. The same pinned administrator token on `GET /v1/offers` is accepted 60 times. The 61st is HTTP 429 `rate_limited`. `token_use.hits` stays 60. |
| E2E-P4.1-10 | H-ABO | Title `E2E-P4.1-10 minute cron pings the heartbeat URL`. `runScheduled("* * * * *")` performs one outbound fetch to `HEARTBEAT_URL`. |

`wrangler-clock.system.test.ts` title: `P4.1 production and staging wrangler envs carry no TEST_CLOCK`. It reads `abo/wrangler.toml` and asserts the `[env.production]` and `[env.staging]` text do not contain `TEST_CLOCK`.

## Sequencing

Tests are written and observed failing before the gates, the catalogue, the exporter, and the alert engine exist. Each step is one task. The implied count is 30.

1. Add `abo/package.json` (`vendor-contracts` file dependency, and the same devDependency versions as `ai-platform/package.json`), `abo/tsconfig.json`, `abo/wrangler.toml`, and `abo/vitest.workers.config.ts`. Wrangler `name` `abo`, `main` `src/worker.ts`, `compatibility_date` `2026-05-03`, `workers_dev = false`, `preview_urls = false`, `[observability] enabled = true`. Envs `development`, `staging`, and `production`. Each env binds D1 `DB`, R2 `R2`, and `send_email` `SEND_EMAIL` with `destination_address` `alerts@clinic.invalid`. Vars: `BILLING_HOST` `billing.vendor.test`, `OPS_HOST` `ops.vendor.test`, `HEARTBEAT_URL` `https://heartbeat.test/ping`, `ALERT_EMAIL_TO` `alerts@clinic.invalid`, `ISSUER_ID` `issuer-test`, `ISSUER_KEYS` `[]`, `CLOUDFLARE_ACCOUNT_ID`, `R2_BUCKET_NAME`. `R2_LOCK_READ_TOKEN` is a secret name on staging and production and a vitest binding in development tests. Crons on every env: `* * * * *`, `0 * * * *`, `0 */6 * * *`, `0 6 * * *`. No env's wrangler text contains `TEST_CLOCK`. The vitest config sets `wrangler.environment` to `development`, binds `TEST_CLOCK` to `"1"`, and includes `test/system/**/*.system.test.ts`. `package.json` script `test` is `vitest run --config vitest.workers.config.ts test/system`. `src/worker.ts` exports `fetch` and `scheduled` that return 404 and do nothing.
2. Add `abo/src/clock.ts` with `clockNowMs` and `clockNowIso`. When `TEST_CLOCK` is `"1"`, read `harness_test_clock.now_iso` for `id` `default`. Otherwise use `Date.now()`. A missing table returns `Date.now()`.
3. Add `abo/test/system/harness.ts`: billing and ops `SELF.fetch` helpers, `createIssuer` mint helpers, D1 `applySql` / migration apply, R2 get/put helpers, `runScheduled(cron)`, `send_email` capture and a fail switch, heartbeat fetch capture, and the lock-rules GET with the default body. `setLockRulesBody` replaces that body for one scenario. `pinIssuer` inserts into `harness_issuer_pin`. `setClock` writes `harness_test_clock`.
4. Add E2E-P4.1-01 to `catalogue.system.test.ts`. Run the harness command. It fails because the response is not 400 `contract_version_unsupported`.
5. Add E2E-P4.1-02. The run fails because the three tokens are not refused as specified.
6. Add E2E-P4.1-06. The run fails because the crossings are not an empty 404.
7. Add E2E-P4.1-09. The run fails because the 61st request is not 429.
8. Add E2E-P4.1-03. The run fails because `GET /v1/offers` does not list the sellable version.
9. Add E2E-P4.1-04. The run fails because the contact versions and the 422 are absent.
10. Add E2E-P4.1-05. The run fails because tenant isolation is absent.
11. Add E2E-P4.1-07. The run fails because UPDATE/DELETE are not aborted and `ledger/` is empty.
12. Add E2E-P4.1-08. The run fails because AL-16 is not sent.
13. Add E2E-P4.1-10. The run fails because the heartbeat URL is not fetched.
14. Add `wrangler-clock.system.test.ts`. Run the harness command and confirm the new tests fail.
15. In `worker.ts`, resolve the host from the `Host` header against `BILLING_HOST` and `OPS_HOST`. The billing host accepts `/v1/`, `/notify/`, and `/return/`. The ops host accepts `/ops/`. `/ops/` on the billing host and `/v1/` on the ops host return HTTP 404 with an empty body and perform no version check, no auth, and no write. Any other path on the matching host returns the same empty 404 in this unit.
16. In `clinic-api/version.ts`, on `/v1/` and `/ops/` only, parse `Abo-Contract-Version`. Missing or non-integer becomes `null`. Current N is `CHANNEL_VERSIONS.aboClinic` for `/v1/` and `CHANNEL_VERSIONS.aboConsole` for `/ops/` (both 1). Call `negotiate`. On failure respond 400 with `code` `contract_version_unsupported`, `message` `contract_version_unsupported`, `contract_version` N, `accepted_versions` from `acceptedVersions(N)`, and header `Abo-Contract-Version` N. Write nothing.
17. In `clinic-api/auth.ts`, after the version gate on `/v1/` only: read `kid` from the JWT header. Load pins from `harness_issuer_pin` when `TEST_CLOCK` is `"1"` and that table has rows; otherwise parse `ISSUER_KEYS` as `{kid, public_key}[]` (`public_key` is base64url of the raw 32-byte Ed25519 key). An unknown `kid` is 401 `unauthenticated`. Import the pinned key and call `validateTokenClaims` with `audience` `"abo"` and `issuerId` `ISSUER_ID`. `ok: true` accepts the token. On `ok: false`, verify the Ed25519 signature over the 04 §2.1 signing input with that pinned key. A bad signature is 401. A good signature with `aud` other than `abo`, `ver` other than `"2"`, or `exp - iat` outside 0..300 is 401. A good signature whose `role` is not `administrator` is 403 `forbidden_role`. Any other failure is 401. Do not fetch keys from the platform.
18. In `clinic-api/rate.ts`, after a token is accepted: if `token_use.hits` for that `jti` is already 60, respond 429 `rate_limited` and leave the row at 60. Otherwise increment `hits` and continue. The version refusal and the 401/403 paths do not write `token_use`.
19. Add `migrations/0001_records.sql` with the tables, keys, indexes, and abort triggers in [data-model.md](./data-model.md). The harness applies it before catalogue tests.
20. Add `records/append.ts`. It inserts one append-only row and one `fact_log` row in a single D1 batch. `row_sha256` is `sha256Hex(canonicalize(row))`. `created_at` is `clockNowIso`. Ids that the spec calls ULIDs use `ulid(clockNowMs(), 10 random bytes)`.
21. Add `fixtures/offers.json` and `clinic-api/offers.ts`. The harness loads the fixture through `append.ts` and puts the terms text in R2 at `text_r2_key`. `GET /v1/offers` returns the shape in [contracts/clinic-api.md](./contracts/clinic-api.md). `plan_display_name` is `copy.en.name`. Terms `text` is the R2 object decoded as UTF-8.
22. Add `clinic-api/billing-contact.ts` for `GET` and `PUT` as in the contract. `contact_sha256` is `sha256Hex(canonicalize({name, email, phone}))`. E.164 is `^\+[1-9][0-9]{1,14}$`. The same `client_request_id` for one `org_id` returns the stored version and does not insert. `created_by_sub` is the token `sub`. `contract_version` on the row is the accepted request version.
23. Add `records/export.ts`. The minute cron selects `fact_log` rows with no `fact_export` row, ascending `fact_seq`, and puts each at `ledger/<fact_seq>.ndjson` as one JSON line of `{fact_seq, table, key, row_sha256}`. Then it inserts `fact_export`. A failed put stops the run so a later `fact_seq` is not written first.
24. Add `alert/index.ts`. One `alert` row per `alert_key`. A due row is sent through `SEND_EMAIL` to `ALERT_EMAIL_TO`. The body is the code and the ids named in the data model, with no contact values. Success sets `last_sent_at` and `next_send_at` 24 hours later. A thrown send leaves `unsent` at 1 so the next scheduled run retries.
25. On the minute cron, after export, if the oldest unexported `fact_log.created_at` is more than one hour before `clockNowMs`, mark `AL-16:export-lag` due. When no such fact remains, set that row `active` 0 so it is not sent again.
26. Add `alert/lock.ts` and call it from the daily cron `0 6 * * *` only. GET the lock URL with `Authorization: Bearer` and `R2_LOCK_READ_TOKEN`. The lock is present when `success` is true and `result.rules` contains an enabled rule whose `condition.type` is `Indefinite` and whose `prefix` is `ledger/` or `""`. Present clears `AL-16:r2-lock` (`active` 0). `success` true with no such rule marks that alert due. Any other outcome, including a thrown fetch, changes nothing about that alert. The Worker sends no other method to that URL.
27. The minute cron, after export and the lag check, pings `HEARTBEAT_URL` with `fetch` and then sends due alerts. The daily cron runs the lock check and then sends due alerts. `0 * * * *` and `0 */6 * * *` return without export, lock, alert, or heartbeat work.
28. Add job `abo-system` to `.github/workflows/ci.yml`: `ubuntu-latest`, `working-directory: abo`, Node 22, `npm ci`, `npm test`. Leave the existing jobs in that file unchanged.
29. Run the harness command and confirm E2E-P4.1-01 through E2E-P4.1-10 and the wrangler clock test pass.
30. Write `quickstart.md` from the outline above.

## Complexity Tracking

02 §7 records no constitution violation for this unit. Nothing is filled in here.
