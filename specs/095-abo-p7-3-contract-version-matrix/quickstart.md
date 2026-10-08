# Quickstart — P7.3 contract version matrix

**Unit**: P7.3 · **Branch**: `ai/095-abo-p7-3-contract-version-matrix` · **Verification**: T028 (seven E2E ids)

## 1. What was implemented

- **Version-matrix variant modules** — Test-only `vendor-contracts` aliases set channel currents for N+1 receivers, DO N+1, feed-window, and desktop-window scenarios without editing `packages/vendor-contracts/`.
- **Wrangler variant configs** — H-FS and workers-pool harnesses start ABO and platform workers with the alias each scenario needs.
- **H-FS stack boot** — `p7-3-stack.mjs` starts the worker pair a scenario names on the existing H-FS registry and ports.
- **Workers-pool configs** — `abo/vitest.version-matrix.config.ts`, `ai-platform/vitest.version-matrix.config.ts`, and `ai-platform/vitest.version-matrix-do.config.ts` run the per-codebase channel tests with the correct alias.
- **Desktop prepare script** — `p7-3-06-prepare.mjs` starts desktop-window workers and applies `(2, 3)` RPC gates for E2E-P7.3-06, then restores `(0, 1)` before exit.
- **Seven failing E2E tests** — One test per E2E id across H-FS, ABO workers pool, platform workers pool, backend SQL, and Flutter fullstack. Each title starts with its E2E id.

## 2. Files this unit adds

| File | FR |
| --- | --- |
| `e2e/fullstack/test/variant/vendor-contracts-n-plus-1.ts` | FR-001 |
| `e2e/fullstack/test/variant/vendor-contracts-do-receiver.ts` | FR-002 |
| `e2e/fullstack/test/variant/vendor-contracts-feed-window.ts` | FR-006 |
| `e2e/fullstack/test/variant/vendor-contracts-desktop-window.ts` | FR-003 |
| `e2e/fullstack/test/variant/abo-n-plus-1.toml` | FR-001, FR-005 |
| `e2e/fullstack/test/variant/platform-n-plus-1.toml` | FR-001, FR-005 |
| `e2e/fullstack/test/variant/platform-worker-n.toml` | FR-002 |
| `e2e/fullstack/test/variant/platform-do-receiver.toml` | FR-002 |
| `e2e/fullstack/test/variant/platform-feed-window.toml` | FR-006 |
| `e2e/fullstack/test/variant/abo-desktop-window.toml` | FR-003 |
| `e2e/fullstack/test/variant/platform-desktop-window.toml` | FR-003 |
| `e2e/fullstack/test/p7-3-stack.mjs` | FR-001, FR-002, FR-004, FR-005, FR-006, FR-007 |
| `e2e/fullstack/test/p7-3-01.test.mjs` | FR-001 |
| `e2e/fullstack/test/p7-3-02.test.mjs` | FR-005 |
| `e2e/fullstack/test/p7-3-03.test.mjs` | FR-006 |
| `e2e/fullstack/test/p7-3-04.test.mjs` | FR-007 |
| `e2e/fullstack/test/p7-3-05.test.mjs` | FR-002 |
| `e2e/fullstack/test/p7-3-06-prepare.mjs` | FR-003 |
| `e2e/fullstack/test/p7-3-07.test.mjs` | FR-004 |
| `abo/vitest.version-matrix.config.ts` | FR-001 |
| `abo/test/version-matrix/channels.system.test.ts` | FR-001 |
| `ai-platform/vitest.version-matrix.config.ts` | FR-001 |
| `ai-platform/vitest.version-matrix-do.config.ts` | FR-002 |
| `ai-platform/test/version-matrix/channels.system.test.ts` | FR-001 |
| `ai-platform/test/version-matrix/worker-do.system.test.ts` | FR-002 |
| `backend/tests/contract_version_matrix.sql` | FR-001 |
| `frontend/test/integration/contract_version_matrix_fullstack_test.dart` | FR-003 |
| `specs/095-abo-p7-3-contract-version-matrix/quickstart.md` | FR-001–FR-007 |

## 3. Harness commands (this unit only)

From `e2e/fullstack/`:

```bash
node --import tsx --test test/p7-3-01.test.mjs test/p7-3-02.test.mjs test/p7-3-03.test.mjs test/p7-3-04.test.mjs test/p7-3-05.test.mjs test/p7-3-07.test.mjs
```

From `abo/`:

```bash
npx vitest run --config vitest.version-matrix.config.ts
```

From `ai-platform/`:

```bash
npx vitest run --config vitest.version-matrix.config.ts
npx vitest run --config vitest.version-matrix-do.config.ts
```

E2E-P7.3-06:

```bash
node --import tsx e2e/fullstack/test/p7-3-06-prepare.mjs
```

Then from `frontend/`:

```bash
flutter test --tags fullstack test/integration/contract_version_matrix_fullstack_test.dart
```

Backend SQL (does not boot a worker):

```bash
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/contract_version_matrix.sql
```

**Harness commands were not executed** because the stack was not running and this workflow does not start wrangler. Do not boot wrangler. Do not run `npm test` in `e2e/fullstack`.

## 4. Entry point → module chain (E2E ids)

| ID | Chain |
| --- | --- |
| E2E-P7.3-01 | H-FS `p7-3-01.test.mjs` → `p7-3-stack.mjs` on `abo-n-plus-1.toml` and `platform-n-plus-1.toml`. ABO `channels.system.test.ts`. Platform `channels.system.test.ts`. Backend `contract_version_matrix.sql`. ABO `handleBillingV1` → `checkContractVersion` `aboClinic`; ABO `handleOps` → `checkContractVersion` `aboConsole`; platform `fetch` → `requireAipContractVersion`; `GET /v1/feed/coverage` → `negotiate(CHANNEL_VERSIONS.platformFeed)`; `VendorEntrypoint`; `GatewayObject.fetch`; `handleGetReturnPaymob` and `paymobReturnUrl`; `POST /notify/paymob`; platform `token_contract` and ABO `authenticateBilling`; `runDueGrantWork` for unknown-answer rule. SQL: five `public` RPCs |
| E2E-P7.3-02 | H-FS `p7-3-02.test.mjs` → `scheduled()` → `runMinuteInquiryBudget` → `runDueGrantWork` → `VendorEntrypoint.grant`. AL-07 from `send_email`. Retry via `POST /ops/parked/{id}/retry` |
| E2E-P7.3-03 | H-FS `p7-3-03.test.mjs` with `platform-feed-window.toml` → `auth_internal.pull_coverage_feed()` → `GET /v1/feed/coverage`. Cursor is `ai_internal.feed_state.cursor` |
| E2E-P7.3-04 | H-FS `p7-3-04.test.mjs` on published configs → `scheduled()` → `runDueGrantWork`, and `POST /ops/parked/{id}/retry` |
| E2E-P7.3-05 | H-FS `p7-3-05.test.mjs` and platform `worker-do.system.test.ts` → `POST /v1/requests` on published-constant worker → `DO` on receiver bundle → `GatewayObject.fetch` |
| E2E-P7.3-06 | `p7-3-06-prepare.mjs` on `abo-desktop-window.toml` and `platform-desktop-window.toml` with `(2, 3)` RPC gates, then Flutter `contract_version_matrix_fullstack_test.dart`. `AboClient` on `AdministratorBillingPage`; `AiAvailabilityReader`, `BillingTokenClient`, and `SubscriptionSummary` on `AiPage` and `CheckoutScreen`; `DiscoveryClient` and `HttpsSubmitPort` on `AiPage`. Update state is `AiDegradedView` mode `appUpdate` |
| E2E-P7.3-07 | H-FS `p7-3-07.test.mjs` → `GET /return/paymob` (`handleGetReturnPaymob`). `v` is the query on the `return_url` from `paymobReturnUrl` |
