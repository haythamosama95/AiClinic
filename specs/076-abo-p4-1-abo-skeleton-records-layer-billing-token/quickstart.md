# ABO skeleton, records layer, billing-token auth and catalogue reads

**Unit**: P4.1 · **Harness**: H-ABO · **Verification**: T029 green

## 1. What was implemented

The `abo/` Worker is the live entry for clinic catalogue reads, append-only records export, AL-16 alerting, and the minute heartbeat (FR-001 through FR-010).

- **Host gate** (`abo/src/worker.ts`) — billing host serves `/v1/`, `/notify/`, and `/return/`; ops host serves `/ops/`; cross-host paths return HTTP 404 with an empty body before version or auth.
- **Contract version** (`abo/src/clinic-api/version.ts`) — `Abo-Contract-Version` negotiation on `/v1/` and `/ops/` via `negotiate` from `vendor-contracts`.
- **Billing-token auth** (`abo/src/clinic-api/auth.ts`) — pinned issuer keys, `validateTokenClaims`, administrator role for catalogue routes.
- **Rate limit** (`abo/src/clinic-api/rate.ts`) — 60 requests per billing token `jti` in D1 `token_use`.
- **Catalogue** — `GET /v1/offers` (`abo/src/clinic-api/offers.ts`) and `GET`/`PUT /v1/billing-contact` (`abo/src/clinic-api/billing-contact.ts`), tenant-scoped by token `org`.
- **Records** — D1 migration `abo/migrations/0001_records.sql`, append writer (`abo/src/records/append.ts`), minute export to R2 `ledger/<fact_seq>.ndjson` (`abo/src/records/export.ts`).
- **Alerts and heartbeat** — export-lag and R2 lock AL-16 (`abo/src/alert/index.ts`, `abo/src/alert/lock.ts`); minute cron pings `HEARTBEAT_URL`; test clock via `abo/src/clock.ts` and H-ABO in `abo/test/system/harness.ts`.
- **CI** — job `abo-system` in `.github/workflows/ci.yml` runs the package harness only.

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/data-model.md` | FR-006, FR-007, FR-008, FR-009 |
| `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/contracts/clinic-api.md` | FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 |
| `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/quickstart.md` | FR-001 through FR-010 |
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

## 3. Harness command for this unit's tests only

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system
```

## 4. Entry point → module chain

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
