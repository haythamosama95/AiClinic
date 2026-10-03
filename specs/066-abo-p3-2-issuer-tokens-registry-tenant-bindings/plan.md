# Implementation Plan: Issuer tokens, issuer-key registry and tenant bindings

**Branch**: `ai/066-abo-p3-2-issuer-tokens-registry-tenant-bindings` | **Date**: 2026-10-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P3.2 replaces per-clinic installation keys with an issuer-key registry and an issuer-token verifier. `registerIssuerKey`, `retireIssuerKey`, and `revokeIssuerKey` are class HP; `listIssuerKeys` is class M. The first valid AI token for an unknown org creates an installation and a `tenant_binding` at epoch 1, capped at 50 such creations per day. Enrollment routes and the `installation_key` table go away. `/control/entitle` stays.

The unit sits in phase P3, size M, **Depends** P3.1, in parallel with P4.1. It freezes AI-token verification, the tenant-binding epoch model, and the issuer-key methods. Spikes are none, so there is no `research.md`.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`).

**Primary Dependencies**: The existing `vendor-contracts` dependency and the existing `VendorEntrypoint` HP and M checks (`negotiate`, Access JWT, WebAuthn assertion). No new library. Vitest `~3.2.4` and `@cloudflare/vitest-pool-workers` `0.8.71` under H-AP. Minting in the harness uses the same compact-JWS `crypto.subtle` sign path as `mintAat`.

**Storage**: D1 (`DB`). New tables `issuer_key` and `tenant_binding`. `installation` is unchanged and gains rows. `token_contract` gains version `2` and retires version `1`. `installation_key` is dropped. `plan`, `entitlement`, and `platform_alert` keep their current columns.

**Testing**: H-AP. E2E-P3.2-01 through E2E-P3.2-08 live in `ai-platform/test/system/issuer-tokens.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the methods and the verifier exist. The unit command is that file only. No new CI job (rule V7). Earlier suites stay on `npm test` and `npm run test:e2e` (rule S2).

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Issuer-key methods are RPC on `VendorEntrypoint`. Clinic routes stay `GET /v1/capabilities` and `GET /v1/requests/{reference}` via `SELF.fetch`.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). The new bound this unit enforces is 50 new-org bindings per 24 hours. Token lifetime is at most 600 s. Revocation is visible within one config-cache TTL, at most 30 s. No separate throughput target.

**Constraints**: Do not modify `packages/vendor-contracts` or the P3.1 credential AL-13 body (rule S7). `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` stay as they are. The config cache still reads `plan` and `entitlement`. `PLAN_TIERS` and `planTierMeetsMinimum` stay. This unit adds no coverage reader. `/control/entitle` and the other `/control/*` routes besides enroll, rotate, and revoke-key stay (rule S9). `src/control/token-contract.ts` stays; version `2` is a migration row, not a new entrypoint method. The test clock binding stays only in `vitest.workers.config.ts` (rule V4). No local scenario sleeps more than 2 s. Successful issuer-key calls are `ok` with empty `code` and no `receipt`.

**Scale/Scope**: Size M (rule S3, 20–32 tasks, 3 user stories, 8 E2E ids, 21 functional requirements). Implied task count is 26.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so Phase 0 writes no `research.md`. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: two D1 tables, the verifier, and the four entrypoint methods. No clinic write and no second service. The check below holds after those artifacts.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  Issuer tokens are how a clinic member's desktop reaches the existing platform worker (spec §4.1, 02 §7 principle I). The creation cap is 50 new orgs per day. No hospital-scale or enterprise requirement.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. New state is D1 rows. Alerts use the existing `platform_alert` table and `send_email` path (02 §5, 02 §7 principle I). No queue, no Kubernetes, and no new service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The verifier has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 only. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 unique keys. `issuer_key.kid` is the primary key. One partial unique index allows one live binding per `org_id`. Clinic RPCs, RLS, and triggers stay as they are.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Clinic routes require the issuer token. `Principal.installationId` comes from the binding for that `org` (02 §3.2, 02 §7 principle IV). Class HP reuses the existing Access JWT and assertion checks. A failed token is the existing `unauthenticated` refusal. `installation` rows are not removed. Revoke sets `status` `revoked` and keeps the key row.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 (02 §7 principles II and V). Register, retire, and revoke are human-plus-passkey (02 §3.3). Lapsing or refusing a token does not block clinical work outside this worker. `/control/entitle` still admits test clinics.

## Project Structure

### Documentation (this feature)

```text
specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── issuer-key-methods.md
│   ├── ai-token-verification.md
│   └── tenant-binding.md
└── tasks.md                   # /abo-tasks, not this phase
```

`data-model.md` records the entities in spec §3.2. `contracts/` is the freeze later units bind to: issuer-key methods, AI-token verification rules, and the tenant-binding epoch model. `research.md` is not produced.

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — issuer-key methods, `issuer_key` and `tenant_binding`, the issuer-token verifier, enroll removal, and H-AP `newClinic()`.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/issuer-tokens.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point → module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P3.2-01 | `SELF.fetch` `GET /v1/capabilities` → `src/discovery/index.ts` → `IssuerTokenVerifier` → `src/config-cache` `issuer_key` → D1 insert of `installation` and `tenant_binding` epoch 1 → a second fetch resolves the same `installation_id` |
| E2E-P3.2-02 | Unknown `kid` on `GET /v1/capabilities` → verifier → 401 `unauthenticated`. `vendorCall` `revokeIssuerKey` → `src/vendor/entrypoint.ts` → `issuer_key.status` `revoked`. A fetch inside the TTL still accepts the cached row. `setTestClock` advances one TTL → the next fetch reads `revoked` and returns 401 |
| E2E-P3.2-03 | `GET /v1/capabilities` with `aud` `abo` or `ai-platform-feed`, lifetime 601 s, or `ver` `"1"` → verifier checks in `contracts/ai-token-verification.md` → 401 before any `installation` or `tenant_binding` insert |
| E2E-P3.2-04 | Two `registerIssuerKey` calls → two `GET /v1/capabilities` tokens accepted → `vendorCall` `retireIssuerKey` → retiring `kid` still accepted → `tenant_binding` row unchanged |
| E2E-P3.2-05 | Fifty first-seen orgs via `GET /v1/capabilities` inside one test-clock window → the 51st fetch inserts nothing, returns 401 `unauthenticated`, and `src/alert/index.ts` sends AL-20 |
| E2E-P3.2-06 | `SELF.fetch` `GET /v1/requests/{reference}` → `authenticateGetRequest` → `IssuerTokenVerifier` → `getRequest` returns 200 for the owner installation and 404 for another org |
| E2E-P3.2-07 | `SELF.fetch` `POST /control/installations/{id}/enroll` → `src/worker.ts` 404. D1 has no `installation_key` table |
| E2E-P3.2-08 | `vendorCall` `registerIssuerKey` → HP checks in `src/vendor/entrypoint.ts` → `issuer_key` insert → `src/alert/index.ts` AL-13 email with `code`, `kid`, and `operation` |

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261003130000_issuer_key_tenant_binding.sql
├── schema.snap.sql
├── src/
│   ├── alert/
│   │   └── index.ts
│   ├── config-cache/
│   │   └── index.ts
│   ├── control/
│   │   ├── index.ts
│   │   └── lifecycle.ts
│   ├── discovery/
│   │   └── index.ts
│   ├── identity/
│   │   └── index.ts
│   ├── journal/
│   │   └── index.ts
│   ├── retention/
│   │   └── index.ts
│   ├── usage-summary/
│   │   └── index.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   ├── platform-vocabulary.ts
│   └── worker.ts
├── test/
│   ├── system/
│   │   ├── harness.ts
│   │   └── issuer-tokens.system.test.ts
│   └── e2e/
│       └── harness/
├── vitest.e2e.config.ts
├── vitest.workers.config.ts
└── wrangler.toml
```

**Structure Decision**: Source stays the existing Worker. `IssuerTokenVerifier` replaces `EnrolledKeyVerifier` in `src/identity/index.ts`. The four methods are added to the existing `METHOD_CLASS` table in `src/vendor/entrypoint.ts`. `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are not in this tree. `src/control/token-contract.ts` is not in this tree. H-AP remains `ai-platform/test/system/` plus `ai-platform/test/e2e/`.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Method dispatch + class table | `METHOD_CLASS` and `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`. This unit adds four keys. `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, …)` and the HP Access and assertion checks stay. Frozen contract: `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/class-table.md`. |
| Auth refusal codes | `unauthenticated` in `ai-platform/src/errors.ts` (`liveHttpStatusForCode` → 401) and the entrypoint `rejected` / `unauthenticated` result. No new taxonomy code. Frozen contract: `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/refusal-codes.md`. |
| Credential lifecycle | `runHpAssertionChecks`, `assertion_used`, and `operator_credential` in `src/vendor/entrypoint.ts`. Issuer-key HP methods call that path. They do not change credential status rules. Frozen contract: `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/credential-lifecycle.md`. |
| Alert body format | Credential `Al13Body` in `ai-platform/src/alert/index.ts` and `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/alert-body.md`. Issuer-key AL-13 and AL-20 are separate JSON objects. The credential fields `credential_id`, `operator_email`, and `kind` stay. |
| `platform_alert` | Table in `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` and `upsertPlatformAlert` in `src/alert/index.ts`. This unit inserts rows. It does not change the table. Frozen contract: `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/platform-alert.md`. |

Depends is P3.1, not none. The rows above are that unit's freezes.

## Files

| File | FR |
| --- | --- |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/data-model.md` | FR-001, FR-005, FR-007, FR-009, FR-015 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/issuer-key-methods.md` | FR-002, FR-003, FR-018, FR-019, FR-020, FR-021 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/ai-token-verification.md` | FR-004, FR-005, FR-006, FR-011, FR-012 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/tenant-binding.md` | FR-007, FR-008, FR-009, FR-014 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/quickstart.md` (implement, after verification) | FR-001–FR-021 |
| `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` | FR-001, FR-005, FR-007, FR-015 |
| `ai-platform/schema.snap.sql` | FR-001, FR-007, FR-015 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-002, FR-003, FR-018, FR-019, FR-020, FR-021 |
| `ai-platform/src/alert/index.ts` | FR-003, FR-014 |
| `ai-platform/src/identity/index.ts` | FR-004, FR-005, FR-008, FR-009, FR-011, FR-012 |
| `ai-platform/src/config-cache/index.ts` | FR-006 |
| `ai-platform/src/discovery/index.ts` | FR-004, FR-010 |
| `ai-platform/src/journal/index.ts` | FR-004, FR-010 |
| `ai-platform/src/worker.ts` | FR-004, FR-010 |
| `ai-platform/src/usage-summary/index.ts` | FR-004 |
| `ai-platform/src/control/lifecycle.ts` | FR-015 |
| `ai-platform/src/control/index.ts` | FR-015 |
| `ai-platform/src/retention/index.ts` | FR-015 |
| `ai-platform/src/platform-vocabulary.ts` | FR-016 |
| `ai-platform/wrangler.toml` | FR-004 |
| `ai-platform/vitest.workers.config.ts` | FR-004 |
| `ai-platform/vitest.e2e.config.ts` | FR-004, FR-017 |
| `ai-platform/test/system/harness.ts` | FR-017 |
| `ai-platform/test/system/issuer-tokens.system.test.ts` | FR-001–FR-021 |
| `ai-platform/test/migrations.test.ts` | FR-001, FR-007, FR-015 |
| `ai-platform/test/e2e/harness/d1.ts` | FR-015, FR-017 |
| `ai-platform/test/e2e/harness/control.ts` | FR-017 |
| `ai-platform/test/e2e/harness/env.ts` | FR-015, FR-017 |
| `ai-platform/test/e2e/harness/aat.ts` | FR-004, FR-017 |
| `ai-platform/test/e2e/harness/scenario.ts` | FR-017 |
| `ai-platform/test/e2e/harness/index.ts` | FR-017 |
| `ai-platform/test/e2e/harness/faults.ts` | FR-015 |
| `ai-platform/test/system/settlement-integrity.system.test.ts` | FR-017 |
| `ai-platform/test/system/quota-admission-interplay.system.test.ts` | FR-017 |
| `ai-platform/test/system/contract-version.system.test.ts` | FR-017 |
| `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts` | FR-017 |
| `ai-platform/test/system/golden-journey.system.test.ts` | FR-017 |
| `ai-platform/test/system/routing-policy-traffic.system.test.ts` | FR-017 |
| `ai-platform/test/system/lifecycle-interplay.system.test.ts` | FR-017 |
| `ai-platform/test/system/entitlement-grant-interplay.system.test.ts` | FR-017 |
| `ai-platform/test/system/token-contract-rotation.system.test.ts` | FR-005, FR-017 |
| `ai-platform/test/system/capability-lifecycle.system.test.ts` | FR-017 |
| `ai-platform/test/worker-entry.test.ts` | FR-015 |
| `ai-platform/test/worker-request-orchestrator.test.ts` | FR-004, FR-015, FR-017 |
| `ai-platform/test/discovery-http.test.ts` | FR-004, FR-015 |
| `ai-platform/test/identity.test.ts` | FR-004, FR-015 |
| `ai-platform/test/token-contract-rotation.test.ts` | FR-004, FR-005 |
| `ai-platform/test/token-contract-control.test.ts` | FR-004, FR-005 |
| `ai-platform/test/config-readers.test.ts` | FR-006, FR-015 |
| `ai-platform/test/config-cache.test.ts` | FR-006 |
| `ai-platform/test/usage-summary.test.ts` | FR-004, FR-015 |
| `ai-platform/test/control.test.ts` | FR-015 |
| `ai-platform/test/retention.test.ts` | FR-015 |
| `ai-platform/test/plan-catalogue.test.ts` | FR-015 |
| `ai-platform/test/entitle-grant.test.ts` | FR-015 |
| `ai-platform/test/cohort-activate-promote.test.ts` | FR-015 |
| `ai-platform/test/capability.test.ts` | FR-015 |
| `ai-platform/test/capability-deprecation.test.ts` | FR-015 |
| `ai-platform/test/routing-policy-canary.test.ts` | FR-015 |
| `ai-platform/test/entitlement.test.ts` | FR-015 |
| `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts` | FR-015, FR-017 |
| `ai-platform/test/e2e/stage-00-boot-bindings-routing.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-01-auth-validation.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-03-enroll-validation.test.ts` | FR-015 |
| `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts` | FR-015 |
| `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` | FR-015 |
| `ai-platform/test/e2e/stage-03-auth-routing.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-04-entitle-happy-cohort-activate.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-04-cohort-promote-deprecate.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-04-deprecate-retire-auth.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-05-rollback-serving.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-05-canary-promote.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-07-etag-cache.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-07-entitlement-filters.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-07-routing-identity.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-09-adapter-identity.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` | FR-012, FR-017 |
| `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-12-get-auth.test.ts` | FR-010, FR-017 |
| `ai-platform/test/e2e/stage-12-get-lookup.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-12-support-lookup.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-12-quota-inspect-dashboard.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts` | FR-017 |
| `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts` | FR-017 |
| `ai-platform/test/e2e/phase-00-exemplars.test.ts` | FR-017 |

`src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are not modified. They keep loading `entitlements`. Capability keeps the `plan:` grant fallback and `planTierMeetsMinimum`. Entitlement keeps the active-status check and `planTierMeetsMinimum`. `src/control/token-contract.ts`, `src/alert/email.ts`, `src/clock.ts`, and `packages/vendor-contracts/**` stay as they are. `migrations/20260731120000_platform_schema.sql` and `migrations/20260803120000_token_contract.sql` are not edited.

`schema.snap.sql` is replaced with the post-migration `CREATE TABLE` dump so `T-A5-13 schema_snapshot_matches` stays green. `PLATFORM_ENTITIES` in `test/migrations.test.ts` drops `installation_key` and adds `issuer_key` and `tenant_binding`.

`src/retention/index.ts` drops only the `DELETE FROM installation_key` statement. The `entitlement` and `installation` deletes in that function stay.

`src/platform-vocabulary.ts` renames `INSTALLATION_KEY_ALGORITHM` to `ISSUER_KEY_ALGORITHM`. The value stays `"EdDSA"`. `isSupportedInstallationKeyAlgorithm` compares against the new constant. `PLAN_TIERS`, `planTierMeetsMinimum`, and `isKnownPlanTier` stay.

`ISSUER_ID` is added under `[env.development.vars]`, `[env.staging.vars]`, and `[env.production.vars]` with the value `issuer-test`, and to the workers and e2e Miniflare bindings. `registerIssuerKey` stores that var on `issuer`. The verifier compares `iss` to it. `vitest.e2e.config.ts` also gains the H-AP `VENDOR` self binding and the existing Access, WebAuthn, and `ALERT_EMAIL_TO` bindings so `newClinic()` can call `registerIssuerKey`. `TEST_CLOCK` stays only on `vitest.workers.config.ts`.

`newClinic()` registers one harness issuer key through `vendorCall("registerIssuerKey", …)` and mints issuer tokens (`iss` = `ISSUER_ID`, `aud` = `ai-platform`, `ver` = `"2"`, header `alg` `EdDSA`, `kid`, `typ` `JWT`). It presents one token on `GET /v1/capabilities` with `Aip-Contract-Version: 1`, reads `installation_id` from `tenant_binding`, and writes that id back onto the scenario. `entitleScenario` then uses that id. The platform assigns the id. Callers stop sending a chosen installation id to enroll. `setupPromotedFakePolicy` calls `newClinic()` and then `entitleScenario`.

Suites whose subject is enroll, rotate, or revoke-key assert HTTP 404 and do not touch `installation_key`. Other enrolling suites call `newClinic()`, then the existing entitle path.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/issuer-tokens.system.test.ts` under H-AP. Each test calls the entry point below and fails while the method or the verifier is absent.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.2-01 | H-AP | Title `E2E-P3.2-01 Token from a registered kid for a new org with ver 2 authenticates; installation and binding epoch 1 are created; a second token resolves the same installation`. `vendorCall` `registerIssuerKey`, then `SELF.fetch` `GET /v1/capabilities` with `ver` `"2"`. The response is 200. D1 has one `installation` (`status` `active`, `display_name` `""`, `region` `""`, `enrolled_at` the insert time) and one `tenant_binding` (`status` `active`, `epoch` 1, `created_at` that same time). A second token for that org returns 200 and the same `installation_id`, with no second binding. |
| E2E-P3.2-02 | H-AP | Title `E2E-P3.2-02 Unknown kid is 401 unauthenticated; a kid revoked through HP is rejected after one config-cache TTL`. An unknown `kid` on `GET /v1/capabilities` is 401 `unauthenticated` and inserts nothing. A registered `kid` is fetched once so the cache holds the active row. `vendorCall` `revokeIssuerKey` is `ok`, `code` `""`, `receipt` absent, and `detail` is the row with `status` `revoked`. A fetch before the TTL still accepts. `setTestClock` moves now by `CONFIG_CACHE_TTL_MS` plus one millisecond. The next fetch is 401. No `sleep` over 2 s. |
| E2E-P3.2-03 | H-AP | Title `E2E-P3.2-03 aud abo or ai-platform-feed, lifetime 601 seconds, or ver 1 is 401 before any installation or tenant_binding write`. Four `GET /v1/capabilities` calls, one for each defect. Each response is 401. `installation` and `tenant_binding` counts are unchanged. |
| E2E-P3.2-04 | H-AP | Title `E2E-P3.2-04 Tokens of two active kids are accepted; a retiring kid is accepted until not_after and the tenant binding is unchanged`. Both kids return 200. `vendorCall` `retireIssuerKey` is `ok` and `detail` has `status` `retiring`. The retiring `kid` still returns 200 while now is before `not_after`. `tenant_binding` `epoch`, `installation_id`, and `created_at` are unchanged. |
| E2E-P3.2-05 | H-AP | Title `E2E-P3.2-05 The 51st new-org creation within 24 hours is 401 unauthenticated, inserts nothing, and raises AL-20`. `setTestClock` stays inside that window. Fifty new orgs each create one epoch-1 binding. The 51st `GET /v1/capabilities` is 401 `unauthenticated`. The epoch-1 count stays 50. Captured email `text` is `{"code":"AL-20"}` and `platform_alert.code` is `AL-20`. No `sleep` over 2 s. |
| E2E-P3.2-06 | H-AP | Title `E2E-P3.2-06 GET /v1/requests/{ref} with the owner org token is 200 and another org token is not found`. After two orgs exist, the test inserts one `ai_request` row for the owner `installation_id`. `GET /v1/requests/{reference}` with the owner token, header `Aip-Contract-Version: 1`, is 200. The same reference with the other org's token is 404. |
| E2E-P3.2-07 | H-AP | Title `E2E-P3.2-07 POST /control/installations/{id}/enroll is 404 and installation_key is gone`. `SELF.fetch` that path is 404. `sqlite_master` has no `installation_key` row. |
| E2E-P3.2-08 | H-AP | Title `E2E-P3.2-08 AL-13 on issuer-key registration carries the decoded operation and kid`. `vendorCall("registerIssuerKey", …)` uses the same Access JWT and WebAuthn assertion helpers as the H-AP vendor tests. `result` is `ok`, `code` is `""`, `receipt` is absent, and `detail` is the `issuer_key` row JSON with `status` `active`. Captured email `text` is JSON with `code` `"AL-13"`, that `kid`, and the decoded `operation`. |

## Sequencing

Tests are written and observed failing before the issuer-key methods and `IssuerTokenVerifier` exist. Each step is one task. The implied count is 26, inside size M (20–32).

1. Add `test/system/issuer-tokens.system.test.ts` with E2E-P3.2-08. Run the unit command. It fails because `registerIssuerKey` is not on `VendorEntrypoint`.
2. Add E2E-P3.2-01. The run fails on the missing verifier and the missing binding write.
3. Add E2E-P3.2-02, using `setTestClock` for the TTL advance. The run fails on the missing revoke method and verifier.
4. Add E2E-P3.2-03. The run fails on the missing verifier.
5. Add E2E-P3.2-04. The run fails on the missing retire method and verifier.
6. Add E2E-P3.2-05. The run fails on the missing cap and AL-20.
7. Add E2E-P3.2-06. The run fails on the missing verifier. The owner row is inserted by the test into `ai_request`.
8. Add E2E-P3.2-07. The run fails because enroll still exists and `installation_key` is still in the schema.
9. Add `migrations/20261003130000_issuer_key_tenant_binding.sql` with `issuer_key`, `tenant_binding` (including `created_at` and `tenant_binding_one_live_org`), the drop of `installation_key`, the retire of `token_contract` version `1`, and the insert of version `2`. Replace `schema.snap.sql`. Update `PLATFORM_ENTITIES` in `test/migrations.test.ts`. The eight E2E tests still fail.
10. Apply that migration from `test/system/harness.ts` and `test/e2e/harness/d1.ts`, and from every other harness that applies `20261003120000_operator_credential_and_platform_alert.sql`. Reset lists drop `installation_key` and include `issuer_key` and `tenant_binding`.
11. Add `ISSUER_ID` = `issuer-test` to the three wrangler env var blocks and to both vitest binding sets. Add the `VENDOR` self binding and the Access, WebAuthn, and `ALERT_EMAIL_TO` bindings to `vitest.e2e.config.ts`. Do not add `TEST_CLOCK` to wrangler or to the e2e config.
12. Add `registerIssuerKey` to `METHOD_CLASS` as HP. Reuse the existing HP checks. Implement the `ok`, `conflict`, and `public_key_invalid` results in `contracts/issuer-key-methods.md`. E2E-P3.2-08 still fails until step 15 sends AL-13.
13. Add `retireIssuerKey` and `revokeIssuerKey` as HP, including `kid_not_found` and `kid_revoked`.
14. Add `listIssuerKeys` as M. `detail` is the active and retiring array ordered by `kid`. No `receipt`.
15. Raise issuer-key AL-13 and AL-20 from `src/alert/index.ts` without changing the credential `Al13Body`. Unsent retry rebuilds an `AL-13:issuer_key:` key from `issuer_key` and `control_audit`. AL-20 uses `next_send_at` as `contracts/tenant-binding.md` describes. E2E-P3.2-08 passes.
16. Replace `EnrolledKeyVerifier` with `IssuerTokenVerifier` in `src/identity/index.ts`, using the check order in `contracts/ai-token-verification.md`. `VerifyContext` gains `issuerId`. `now` stays seconds. Replay stays on `principal.jti` in the Durable Object.
17. Add config-cache kinds `issuer_keys` and `tenant_bindings`. Remove the `keys` reader. Keep `plans` and `entitlements`. `loadConfig` takes an optional `nowMs` and defaults to `Date.now()` so admission, capability, and entitlement keep their current calls. The verifier passes `ctx.now * 1000`. Discovery, `authenticateGetRequest`, `src/worker.ts` `createProductionPreAccept`, and `src/usage-summary/index.ts` construct `IssuerTokenVerifier`, pass `ISSUER_ID`, and set `now` from `clockNowSeconds`. E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, and E2E-P3.2-04 pass.
18. The first-seen org path inserts the installation and the epoch-1 binding, enforces the 50-per-day cap, and raises AL-20. E2E-P3.2-05 and E2E-P3.2-06 pass.
19. Remove `handleEnroll`, `handleRotate`, `handleRevokeKey`, and `INSTALLATION_KEY_TTL_DAYS`. Remove `enroll`, `rotate`, and `revoke-key` from the control route pattern and switch. Remove the `installation_key` delete in `src/retention/index.ts`. Rename `INSTALLATION_KEY_ALGORITHM` to `ISSUER_KEY_ALGORITHM`. E2E-P3.2-07 passes. Re-run the unit command and confirm E2E-P3.2-01 through E2E-P3.2-08 pass together.
20. Add `newClinic()` and issuer-token minting to `test/system/harness.ts`. `enrollScenario` becomes `newClinic()`. `setupPromotedFakePolicy` uses it and still calls `entitleScenario`.
21. Point the system suites listed in Files at `newClinic()` and the returned `installation_id`.
22. Add the same `newClinic()` behavior to `test/e2e/harness/control.ts` and mint issuer tokens from `test/e2e/harness/aat.ts`. Drop the `installation_key` fault target in `test/e2e/harness/faults.ts`.
23. Migrate the remaining Files test rows: enrolling e2e stages call `newClinic()`; enroll, rotate, and revoke-key assertions expect 404; unit fixtures stop inserting `installation_key` and stop constructing `EnrolledKeyVerifier`. `src/worker-entry.test.ts` expects 404 for the enroll URL.
24. Re-run the unit command. All eight tests pass.
25. Run `cd ai-platform && npm test && npm run test:e2e`. Earlier suites stay green (rule S2). Admission, capability, and entitlement sources are untouched, and entitle still runs after `newClinic()`.
26. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
