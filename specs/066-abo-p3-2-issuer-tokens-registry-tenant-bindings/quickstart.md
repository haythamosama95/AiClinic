# Issuer tokens, issuer-key registry, and tenant bindings

**Unit**: P3.2 · **Harness**: H-AP · **Verification**: T024 green

## 1. What was implemented

P3.2 replaces per-clinic installation keys with an issuer-key registry and an issuer-token verifier (FR-001 through FR-021).

- **Issuer-key methods** — `registerIssuerKey`, `retireIssuerKey`, and `revokeIssuerKey` (class HP) and `listIssuerKeys` (class M) on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`.
- **D1 tables** — `issuer_key` and `tenant_binding`; `installation_key` is dropped. `token_contract` gains version `2` and retires version `1` (migration `20261003130000_issuer_key_tenant_binding.sql`, snapshot in `schema.snap.sql`).
- **`IssuerTokenVerifier`** — in `ai-platform/src/identity/index.ts`; replaces `EnrolledKeyVerifier`. Config-cache kinds `issuer_keys` and `tenant_bindings` in `ai-platform/src/config-cache/index.ts`. The first valid token for an unknown org creates an `installation` and a `tenant_binding` at epoch 1, capped at 50 per 24 hours.
- **Enroll removal** — `POST /control/installations/{id}/enroll`, rotate, and revoke-key routes are gone from `ai-platform/src/worker.ts` and control handlers; retention no longer deletes `installation_key`.
- **H-AP `newClinic()`** — registers a harness issuer key via `vendorCall("registerIssuerKey", …)`, mints issuer tokens (`ver` `"2"`, `aud` `ai-platform`), and resolves `installation_id` from the first successful `GET /v1/capabilities` instead of enroll.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/data-model.md` | FR-001, FR-005, FR-007, FR-009, FR-015 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/issuer-key-methods.md` | FR-002, FR-003, FR-018, FR-019, FR-020, FR-021 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/ai-token-verification.md` | FR-004, FR-005, FR-006, FR-011, FR-012 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/contracts/tenant-binding.md` | FR-007, FR-008, FR-009, FR-014 |
| `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/quickstart.md` | FR-001–FR-021 |
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

`src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are not modified.

## 3. Harness command for this unit's tests only

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/issuer-tokens.system.test.ts
```

Every scenario is asserted by H-AP; this file records harness commands only.

## 4. How to inspect the change

- **Issuer-key RPC:** `ai-platform/src/vendor/entrypoint.ts` — `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`, and `listIssuerKeys`.
- **Token verification:** `IssuerTokenVerifier` in `ai-platform/src/identity/index.ts` — signature, claims, binding resolution, and first-seen org creation.
- **Config cache:** `issuer_keys` and `tenant_bindings` kinds in `ai-platform/src/config-cache/index.ts`.
- **Deploy config:** `ISSUER_ID` under `[env.development.vars]`, `[env.staging.vars]`, and `[env.production.vars]` in `ai-platform/wrangler.toml`.
- **Harness output:** run the command in §3 and confirm E2E-P3.2-01 through E2E-P3.2-08 pass.

## 5. Entry point → module chain

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
