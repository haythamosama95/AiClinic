# Implementation Plan: `VendorEntrypoint`, authorization classes, operator credentials and platform alerting

**Branch**: `ai/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting` | **Date**: 2026-10-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.1 exports `VendorEntrypoint` as a named `WorkerEntrypoint` on the AI Platform worker and implements `registerOperatorCredential` (HP, or bootstrap), `revokeOperatorCredential` (HP), and `listOperatorCredentials` (M). Every argument is version-gated before authentication, class HP checks the forwarded Access JWT and the 04 §1.5 assertion, and credential, assertion, audit, and alert rows live in D1. `src/alert` sends `platform_alert` through the fixed `send_email` binding, and the `*/5` cron retries an unsent alert, pings `HEARTBEAT_URL`, and raises a platform alert when a job in that run fails.

The unit sits in phase P3, size L, **Depends** P2.2, in parallel with P4.1 and P1.x. It is the platform track's first entrypoint unit. CP-A is the checkpoint it consumes, not a checkpoint it closes.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). The entrypoint class uses `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit calls the frozen exports `negotiate`, `CHANNEL_VERSIONS`, `verifyAccessJwt`, `verifyAssertion`, `parseRegistrationAttestation`, `validateOperation`, `operationChallenge`, `sha256Hex`, and `canonicalize`, and the testkit subpath `createAccessTeam` and `createSoftwareAuthenticator`. No new library. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`, Wrangler `~4.86.0`, Miniflare `kCurrentWorker` for the H-AP self binding.

**Storage**: D1 (`DB`). New tables `operator_credential`, `assertion_used`, and `platform_alert`. `control_audit` gains `actor` and `assertion_sha256`. `operator_id` stays, so the existing `/control/*` inserts keep working (rule S9). No R2 object and no Durable Object change.

**Testing**: H-AP. E2E-P3.1-01 through E2E-P3.1-10 live in `ai-platform/test/system/vendor-entrypoint.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before `VendorEntrypoint` exists. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on their current commands (rule S2).

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). `VendorEntrypoint` is an RPC entrypoint, not a `fetch` route. `workers_dev = false` and `preview_urls = false` (04 §6.4).

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). Credential calls are operator actions. The new cron is `*/5 * * * *`. No separate throughput target.

**Constraints**: Do not modify `packages/vendor-contracts` (rule S7). Successful register, revoke, and list stay inside the frozen result envelope: `result` `ok`, `receipt` omitted, payload JSON text in `detail` (04 §1.2, rule S7). This unit implements no class H method. A missing, expired, or wrong-`aud` Access JWT on `revokeOperatorCredential` is `rejected` with code `unauthenticated` and writes nothing; the same refusal applies to every class H or HP call this unit makes (FR-016). Version check uses `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, …)` and runs before authentication and before any write. The test clock binding exists only in `vitest.workers.config.ts`. Production and staging wrangler envs carry no clock control (rule V4, OQ-5 default). No local scenario sleeps more than 2 s. Enrollment, `/control/entitle`, and `/control/*` stay (rule S9). `0 5 1 * *` stays until P3.10. `ISSUER_ID`, `DURATION_SCALE`, `PLATFORM_SIGNING_KEY`, and removal of `OPERATOR_BEARER_TOKEN` stay with their owning units.

**Scale/Scope**: Size L (rule S3, 32–40 tasks, 3 user stories, 10 E2E ids, 25 functional requirements). Implied task count is 34.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). `research.md` records this unit's R-5 outcome. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: D1 tables, the entrypoint, and `send_email`. No clinic write and no second service.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One operator credential registry and one out-of-band email path on the existing platform worker (spec §4.1, 02 §7 principle I). Sized for a few orders a day and one operator. No hospital-scale or enterprise requirement.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. Background work is the existing `scheduled()` handler plus a `*/5` branch. Alerts are rows in D1 retried by that cron (02 §5, 02 §7 principle I). No queue, no Kubernetes, and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The entrypoint has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 unique keys. `credential_id` and `challenge_sha256` are primary keys. `status` and `alg` are checked. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Class M is the service binding. Class HP checks the Access JWT (team certs, `aud`, expiry) and the WebAuthn assertion (04 §1.5, 02 §3.3). A failed Access JWT writes nothing, including no `control_audit` row (FR-016). A call that passes the JWT writes `control_audit.actor` as the Access email and `assertion_sha256` (FR-012). Revoke sets `status` `revoked` and keeps the row. No hard delete.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 (02 §7 principles II and V). Register and revoke are human-plus-passkey, except bootstrap while `operator_credential` is empty (02 §3.3). The clinic request path is unchanged, so AI being unavailable leaves clinical work where it is today.

## Project Structure

### Documentation (this feature)

```text
specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/
├── plan.md
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── class-table.md
│   ├── refusal-codes.md
│   ├── credential-lifecycle.md
│   ├── alert-body.md
│   └── platform-alert.md
└── tasks.md                   # /abo-tasks, not this phase
```

`research.md` records this unit's R-5 spike (rule S6). `data-model.md` records the entities in spec §3.2. `contracts/` is the freeze later units bind to: method dispatch and the class table, auth refusal codes, the credential lifecycle, the alert body, and `platform_alert`. The result envelope is not rewritten; credential `ok` results use the P2.2 envelope (rule S7).

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — `VendorEntrypoint`, the three methods, the D1 tables, the `*/5` branch, and the H-AP helpers.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/vendor-entrypoint.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point → module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.1-01 | `vendorCall` → `env.VENDOR.registerOperatorCredential` → `src/vendor/entrypoint.ts` bootstrap insert → `src/alert/index.ts` AL-13 → `src/alert/email.ts` `SEND_EMAIL.send` |
| E2E-P3.1-02 | `setTestClock` → `src/clock.ts` → `vendorCall` `revokeOperatorCredential` → signer credential read in `src/vendor/entrypoint.ts`. The test also reads `wrangler.toml` and asserts the production and staging envs have no `TEST_CLOCK` |
| E2E-P3.1-03 | `vendorCall` `revokeOperatorCredential` → `verifyAccessJwt` → `verifyAssertion` → `assertion_used` insert → `src/control/audit.ts` |
| E2E-P3.1-04 | `vendorCall` `revokeOperatorCredential` → `src/clock.ts` freshness and Access email comparison in `src/vendor/entrypoint.ts` |
| E2E-P3.1-05 | `vendorCall` `revokeOperatorCredential` with a bad Access JWT → `verifyAccessJwt` → `rejected` `unauthenticated` before any D1 write |
| E2E-P3.1-06 | `vendorCall` on each of the three methods → `negotiate` in `src/vendor/entrypoint.ts` before `verifyAccessJwt` |
| E2E-P3.1-07 | `vendorCall` `revokeOperatorCredential` (signer A, target B) → revoke update → `src/alert/email.ts` → a later `vendorCall` whose signer is B |
| E2E-P3.1-08 | `src/alert/email.ts` throws → `platform_alert` stays `unsent` → `runScheduled("*/5 * * * *")` → `src/worker.ts` `scheduled` → `src/alert/index.ts` retry → `src/alert/email.ts` |
| E2E-P3.1-09 | `runScheduled("*/5 * * * *")` → `src/worker.ts` → heartbeat `fetch` captured in the harness; a thrown heartbeat `fetch` → JSON `console.log` → `platform_alert` insert |
| E2E-P3.1-10 | `vendorCall` `listOperatorCredentials` → promote-due read → active-key JSON in `detail` |

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261003120000_operator_credential_and_platform_alert.sql
├── schema.snap.sql
├── src/
│   ├── alert/
│   │   ├── email.ts
│   │   └── index.ts
│   ├── clock.ts
│   ├── control/
│   │   └── audit.ts
│   ├── vendor/
│   │   ├── contract-version.ts    # P2.1, unchanged
│   │   └── entrypoint.ts
│   └── worker.ts
├── test/
│   ├── worker-entry.test.ts       # S2: export WorkerEntrypoint from the existing mock
│   └── system/
│       ├── harness.ts
│       └── vendor-entrypoint.system.test.ts
├── vitest.workers.config.ts
└── wrangler.toml
```

**Structure Decision**: Source stays the existing Worker. `src/vendor/entrypoint.ts` exports `VendorEntrypoint`, and `src/worker.ts` re-exports that class so Wrangler sees the named entrypoint on `main`. `src/control/index.ts` is the HTTP `/control/*` dispatcher and stays as it is (rule S9). The class table is a const in `entrypoint.ts`, one class per method this unit implements. `src/alert/` is the `src/alert` module from the unit row: `index.ts` stores and retries `platform_alert` and pings the heartbeat; `email.ts` is the only call to `env.SEND_EMAIL.send`, so the harness can capture or throw at that call. `src/clock.ts` is the one clock module (rule V4). The H-AP self binding is Miniflare `serviceBindings.VENDOR = { name: kCurrentWorker, entrypoint: "VendorEntrypoint" }` in `vitest.workers.config.ts` only. Production wrangler has no self-binding; the ABO's binding is a later unit.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Message types of 04 §1.2–§1.7 and §2.1 | `validateResultEnvelope` in `packages/vendor-contracts/src/result-envelope.ts`; `validateOperation` and `operationChallenge` in `src/operation.ts`; `validateReceipt` in `src/receipt.ts`; `validateGrantEnvelope` in `src/grant-envelope.ts`; `validateCoverageSnapshot` in `src/coverage-snapshot.ts`; `validateFeedEvent` in `src/feed-event.ts`; `validateTokenClaims` in `src/token-claims.ts`. Frozen contracts: `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/`. This unit calls `negotiate` and `CHANNEL_VERSIONS.vendorEntrypoint` from `src/version.ts` and does not change the envelope. `receipt` stays absent unless `result` is `applied` or `already_applied`. |
| Verification APIs | `verifyAccessJwt` and `AccessCertsDocument` in `packages/vendor-contracts/src/access-jwt.ts`. `verifyAssertion`, `parseRegistrationAttestation`, and `Assertion` in `src/webauthn.ts`. `sha256Hex` and `canonicalize` in `src/canonical.ts`. |
| Testkit API | `createAccessTeam` and `createSoftwareAuthenticator` from `vendor-contracts/testkit` (`packages/vendor-contracts/src/testkit/access-team.ts`, `src/testkit/authenticator.ts`, `src/testkit/index.ts`). Production `src/worker.ts` does not import the testkit. |
| CP-A | The P2.2 package conformance suite, both `packages/vendor-contracts/vitest.config.ts` and `vitest.workers.config.ts`. This unit does not re-run or edit that suite. |

## Files

| File | FR |
| --- | --- |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/research.md` | FR-001, FR-004, FR-011 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/data-model.md` | FR-009, FR-010, FR-012, FR-019 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/class-table.md` | FR-001, FR-004, FR-005 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/refusal-codes.md` | FR-002, FR-016, FR-017 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/credential-lifecycle.md` | FR-003, FR-006, FR-007, FR-008, FR-011, FR-013, FR-018 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/alert-body.md` | FR-019, FR-022, FR-025 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/platform-alert.md` | FR-019, FR-020, FR-021, FR-023 |
| `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/quickstart.md` (implement, after verification) | FR-001–FR-025 |
| `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` | FR-009, FR-010, FR-012, FR-019 |
| `ai-platform/schema.snap.sql` | FR-009, FR-010, FR-012, FR-019 |
| `ai-platform/src/clock.ts` | FR-014 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-011, FR-013, FR-015, FR-016, FR-017, FR-018 |
| `ai-platform/src/alert/index.ts` | FR-019, FR-020, FR-021, FR-022, FR-023 |
| `ai-platform/src/alert/email.ts` | FR-019, FR-020, FR-025 |
| `ai-platform/src/control/audit.ts` | FR-012 |
| `ai-platform/src/worker.ts` | FR-001, FR-021, FR-023 |
| `ai-platform/wrangler.toml` | FR-001, FR-021, FR-023, FR-024 |
| `ai-platform/vitest.workers.config.ts` | FR-014, FR-025 |
| `ai-platform/test/system/harness.ts` | FR-014, FR-025 |
| `ai-platform/test/system/vendor-entrypoint.system.test.ts` | FR-001–FR-025 |
| `ai-platform/test/worker-entry.test.ts` | S2 |

`schema.snap.sql` is replaced with the post-migration `CREATE TABLE` dump so the existing `T-A5-13 schema_snapshot_matches` test stays green. New `control_audit` columns are nullable. Existing inserts name their columns and keep writing `operator_id`. `src/control/index.ts`, `src/vendor/contract-version.ts`, `src/logger.ts`, and `packages/vendor-contracts/**` stay as they are.

`src/worker.ts` keeps `export { VendorEntrypoint } from "./vendor/entrypoint"`. That re-export loads `src/vendor/entrypoint.ts`, and `VendorEntrypoint` extends `WorkerEntrypoint` from `cloudflare:workers`. `ai-platform/test/worker-entry.test.ts` is the only `vi.mock("cloudflare:workers")` under `ai-platform`. Its factory returns `{ DurableObject, env: runtimeEnv }`. The allowed S2 fix, applied in T033 before `npm test`, adds a `WorkerEntrypoint` class in that same factory with the same `(ctx, env)` constructor as the `DurableObject` stub already there, and returns `{ DurableObject, WorkerEntrypoint, env: runtimeEnv }`. `DurableObject` and `env` stay. This file is not a Test Layout scenario. Consumes contracts stay unchanged.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/vendor-entrypoint.system.test.ts` under H-AP. Each test calls the entry point below and fails while `VendorEntrypoint` is absent.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.1-01 | H-AP | Title `E2E-P3.1-01 Empty registry: bootstrap registration without approval returns pending and AL-13 bootstrap; a second unapproved registration is rejected`. `vendorCall("registerOperatorCredential", args, { accessJwt })` with no assertion. `result` `ok`, `code` `""`, `receipt` omitted, `detail` JSON of the row with `status` `pending`. Captured `send_email` text is the AL-13 bootstrap body. A second call with a valid Access JWT and no assertion is `rejected` with code `assertion_required`, and no second row is inserted. |
| E2E-P3.1-02 | H-AP | Title `E2E-P3.1-02 HP call using a credential under 24 hours is rejected; after the test clock passes 24 hours it is ok`. Bootstrap a credential, then `revokeOperatorCredential` signed by that credential. Before `activates_at`, `rejected` with code `credential_not_active` and the row stays `pending`. `setTestClock` moves now to `activates_at`. The same call is `ok`, `code` `""`, `receipt` omitted, and `detail` is that row. No `sleep` over 2 s. The test imports `wrangler.toml` as text and asserts the `[env.production]` and `[env.staging]` blocks contain no `TEST_CLOCK`. |
| E2E-P3.1-03 | H-AP | Title `E2E-P3.1-03 HP with a valid Access JWT and an assertion over the exact operation is ok; replaying the assertion is rejected`. After the credential is active, `revokeOperatorCredential` is `ok`, `detail` is that row's JSON, `code` `""`, `receipt` omitted, and `contract_version` is the negotiated version. `control_audit.actor` is the Access email and `assertion_sha256` is the hex SHA-256 of the canonical operation. The same assertion again is `rejected` with code `assertion_used`. |
| E2E-P3.1-04 | H-AP | Title `E2E-P3.1-04 Assertion issued_at 6 minutes old is rejected; actor_email other than the Access email is rejected`. One call with `issued_at` six minutes before the test clock is `rejected` with code `assertion_expired`. Another call whose operation `actor_email` differs from the Access JWT email is `rejected` with code `actor_email_mismatch`. |
| E2E-P3.1-05 | H-AP | Title `E2E-P3.1-05 revokeOperatorCredential with a missing, expired, or wrong-aud Access JWT is unauthenticated and writes nothing`. Three calls. Each result is `rejected`, code `unauthenticated`, `receipt` omitted. Counts of `operator_credential`, `assertion_used`, and `control_audit` are unchanged. |
| E2E-P3.1-06 | H-AP | Title `E2E-P3.1-06 A method with contract_version missing or 2 is rejected contract_version_unsupported and writes nothing`. Each of the three methods, once with the field omitted and once with `2`. `rejected`, code `contract_version_unsupported`, and no D1 change. The refusal is asserted by a missing or wrong-`aud` JWT still producing `contract_version_unsupported` rather than `unauthenticated`. |
| E2E-P3.1-07 | H-AP | Title `E2E-P3.1-07 Credential A revokes B, then an HP call that uses B fails, and AL-13 is sent`. A is bootstrapped and aged to active, B is registered with A's assertion and aged to active, then A revokes B. The revoke is `ok`, `detail` is B's row with `status` `revoked`, `control_audit.actor` is the Access email, and `assertion_sha256` is stored. The captured body is AL-13 kind `revoke`. A later HP call whose `signer_credential_id` is B is `rejected` with code `credential_revoked`. |
| E2E-P3.1-08 | H-AP | Title `E2E-P3.1-08 When send_email throws the alert stays unsent and the next five-minute run sends it once`. The harness makes `sendPlatformEmail` throw. A bootstrap still stores `platform_alert` with `send_state` `unsent`. The next `runScheduled("*/5 * * * *")` sends that body once. The captured text has the code, the credential id, and the decoded operation. A second `*/5` run does not send it again. |
| E2E-P3.1-09 | H-AP | Title `E2E-P3.1-09 The five-minute cron pings the heartbeat URL and a failing job raises a platform alert`. One `runScheduled("*/5 * * * *")` records an outbound fetch to `HEARTBEAT_URL`. A later run whose heartbeat `fetch` throws writes one JSON `console.log` line and inserts `platform_alert` with code `scheduled_job_failed`. |
| E2E-P3.1-10 | H-AP | Title `E2E-P3.1-10 listOperatorCredentials returns ok with the active keys in detail`. With one `pending` row and one `active` row, `listOperatorCredentials` is `ok`, `code` `""`, `receipt` omitted, `contract_version` present, and `detail` is the JSON text of `[{credential_id, public_key_cose, alg}]` for the active row only. |

## Sequencing

Tests are written and observed failing before `VendorEntrypoint` exists. Each step is one task. The implied count is 34, inside size L (32–40).

1. Add the `VENDOR` self binding and `TEST_CLOCK` binding in `vitest.workers.config.ts`. Add `vendorCall`, the Access team fixture, and email capture in `test/system/harness.ts`. Add `test/system/vendor-entrypoint.system.test.ts` with E2E-P3.1-01. Run the unit command. It fails because `VendorEntrypoint` is not exported.
2. Add E2E-P3.1-02 and `setTestClock`. The run fails on the missing entrypoint.
3. Add E2E-P3.1-03. The run fails on the missing entrypoint.
4. Add E2E-P3.1-04. The run fails on the missing entrypoint.
5. Add E2E-P3.1-05. The run fails on the missing entrypoint.
6. Add E2E-P3.1-06. The run fails on the missing entrypoint.
7. Add E2E-P3.1-07. The run fails on the missing entrypoint.
8. Add E2E-P3.1-08 and the harness switch that makes `sendPlatformEmail` throw. The run fails on the missing entrypoint.
9. Add E2E-P3.1-09 and heartbeat fetch capture around `runScheduled`. The run fails because the `*/5` branch does not ping or alert.
10. Add E2E-P3.1-10. The run fails on the missing entrypoint.
11. Add `migrations/20261003120000_operator_credential_and_platform_alert.sql` with the three tables and the two `control_audit` columns.
12. Replace `schema.snap.sql` with the post-migration `CREATE TABLE` dump so `T-A5-13` matches.
13. Make `test/system/harness.ts` apply the new migration and delete the new tables in its reset. The ten E2E tests still fail.
14. Add `src/clock.ts`. When `env.TEST_CLOCK` is absent it returns `Date.now()`. When it is `"1"` it reads the harness clock row.
15. Implement `setTestClock` as a D1 row the harness creates. E2E-P3.1-02 still fails on the missing entrypoint. The wrangler assertion in that test reads `[env.production]` and `[env.staging]` and passes once those blocks have no `TEST_CLOCK`, which step 16 keeps true.
16. Add `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `WEBAUTHN_RP_ID`, `WEBAUTHN_ORIGIN`, `HEARTBEAT_URL`, and `ALERT_EMAIL_TO` under `[env.development.vars]`, `[env.staging.vars]`, and `[env.production.vars]`. `ALERT_EMAIL_TO` is the same address as the `send_email` destination. No `TEST_CLOCK` in any wrangler env.
17. Add a `send_email` binding named `SEND_EMAIL` with `destination_address` `alerts@clinic.invalid` on development, staging, and production. The address is the local stand-in for the verified destination; deploy replaces the binding and `ALERT_EMAIL_TO` together.
18. Set top-level `workers_dev = false`, `preview_urls = false`, and `[observability] enabled = true`. Append `*/5 * * * *` to the existing `[triggers]` cron list. Leave `0 3 * * *`, `0 4 * * *`, and `0 5 1 * *` in place.
19. Add `writeEntrypointAudit` in `src/control/audit.ts`. It inserts `actor`, `assertion_sha256`, and `operator_id` set to that same Access email. The existing `writeAudit` function stays.
20. Add `src/vendor/entrypoint.ts` and re-export `VendorEntrypoint` from `src/worker.ts`. The first lines of every method call `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, requested)`. A missing version or `2` returns `rejected` / `contract_version_unsupported` with `contract_version` `1`, empty `detail`, no `receipt`, and no D1 write. E2E-P3.1-06 passes.
21. Load Access certs from `https://${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`, map them into `AccessCertsDocument` with issuer `https://${ACCESS_TEAM_DOMAIN}`, and call `verifyAccessJwt`. A missing token, `{ ok: false }`, or a certs fetch failure returns `unauthenticated` and writes nothing. The H-AP fixture answers that URL from `createAccessTeam`. E2E-P3.1-05 passes.
22. Implement bootstrap `registerOperatorCredential`: empty table, no assertion, Access JWT still required, insert `pending` with `activates_at` 24 hours ahead, `approved_by` null, `operator_email` the Access email. `detail` is the row JSON. A second call without an assertion is `assertion_required`.
23. Add `src/alert/email.ts` and the AL-13 bootstrap insert in `src/alert/index.ts`. The email `text` is the bootstrap body in `contracts/alert-body.md`. E2E-P3.1-01 passes.
24. Implement the HP assertion path for register and revoke: `signer_credential_id`, `verifyAssertion` with `WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN`, `actor_email` against the Access email, and `issued_at` within five minutes of `src/clock.ts`. E2E-P3.1-04 passes once the signer can be active (step 25). Until then this step is observed failing on `credential_not_active`, which is the clock gate and not an assertion bug.
25. On the signer read, and inside `listOperatorCredentials`, set `pending` to `active` when `activates_at` is at or before now, and raise no alert. A signer still `pending` is `credential_not_active` and does not insert `assertion_used`. E2E-P3.1-02 passes, and E2E-P3.1-04 passes.
26. After the signer is active and the assertion checks pass, insert `assertion_used.challenge_sha256`. A duplicate is `assertion_used` and does not change the credential. Write `control_audit` for every H/HP call that passed the Access JWT check, including the rejected ones in E2E-P3.1-04. E2E-P3.1-03 passes.
27. `revokeOperatorCredential` sets `status` `revoked` and `revoked_by` to the Access email, returns `ok` when the row is already `revoked`, and raises AL-13 kind `revoke`. A missing target is `rejected` / `credential_not_found` with no `assertion_used` insert. An HP call whose signer is `revoked` is `credential_revoked`. Same `credential_id` and same `public_key_cose` on register returns the existing row and does not insert another; a different key is `conflict` / `public_key_cose_mismatch` with empty `detail`. E2E-P3.1-07 passes.
28. `listOperatorCredentials` returns `ok` and the active `{credential_id, public_key_cose, alg}` array in `detail`. E2E-P3.1-10 passes.
29. `sendPlatformEmail` throwing leaves `send_state` `unsent` and does not mark the `*/5` job failed.
30. `src/worker.ts` `scheduled` handles cron `*/5 * * * *` by calling alert retry, then the heartbeat ping. Existing `0 3`, `0 4`, and `0 5 1` branches stay. Retry sends each `unsent` row once and sets `sent`. E2E-P3.1-08 passes.
31. The heartbeat job `fetch`es `HEARTBEAT_URL`. The harness records that fetch.
32. A thrown job in the `*/5` branch logs one JSON line through `console.log` and inserts `platform_alert` code `scheduled_job_failed`. E2E-P3.1-09 passes. `src/logger.ts` stays on its current line format so earlier suites keep their log shape.
33. Re-run the unit command and confirm E2E-P3.1-01 through E2E-P3.1-10 pass together. Before `cd ai-platform && npm test && npm run test:e2e`, apply the Files-section S2 fix in `ai-platform/test/worker-entry.test.ts`: the existing `vi.mock("cloudflare:workers")` factory also exports `WorkerEntrypoint`. The `VendorEntrypoint` re-export in `src/worker.ts` stays.
34. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
