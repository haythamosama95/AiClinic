# Quickstart: Admission and settlement against terms (P3.4)

## 1. What was implemented

This unit admits and settles each live AI request against the clinic’s **term** on the per-clinic quota Durable Object `hot` row, returns the frozen admission answer to the worker pipeline, and journals **`usage_event.term_id`** (replacing entitlement-period `usage_event.period`).

Clinic-facing denial codes now include **`allowance_exhausted`** (403), **`coverage_lapsed`**, **`forbidden_capability`**, **`concurrency_limited`**, **`coverage_unknown`**, and **`suspended`** (403, replacing `installation_suspended`). Identity guard rejections use **`error_code: "suspended"`** with taxonomy code **`suspended`**.

Term **exhaustion** ends the active term when allowance is consumed with no successor queued; a queued successor activates at exhaustion. **Band crossings** (`75`, `90`, `exhausted`) emit at most one `band_crossed` coverage event per band per term. Stale reservations older than 15 minutes are charged once on the next admission.

Paid setup in H-AP uses **`coverClinic()`** in `ai-platform/test/system/harness.ts`: publish plan version, vendor `grant`, alarm ship to `coverage_mirror`, then clinic enrollment via `newClinic()`.

## 2. Files this unit adds or modifies

See the **Files** table in [`plan.md`](./plan.md). Primary touchpoints:

- Migration `ai-platform/migrations/20261006120000_usage_term.sql` and `schema.snap.sql`
- DO admission and settlement: `ai-platform/src/quota-do/index.ts`, `ai-platform/src/quota-do/coverage.ts`
- Worker path: `ai-platform/src/admission/index.ts`, `ai-platform/src/pipeline/index.ts`, `ai-platform/src/worker.ts`, `ai-platform/src/credit/index.ts`, `ai-platform/src/journal/index.ts`, `ai-platform/src/rollup/index.ts`
- Taxonomy and surfaces: `ai-platform/src/errors.ts`, `ai-platform/src/adapter.ts`, `ai-platform/src/identity/index.ts`, `ai-platform/src/discovery/index.ts`, `ai-platform/src/capability/index.ts`, `ai-platform/src/dashboards/index.ts`, `ai-platform/src/soft-threshold/index.ts`, `ai-platform/src/usage-summary/index.ts`
- H-AP harness and tests: `ai-platform/test/system/harness.ts`, `ai-platform/test/system/admission-settlement.system.test.ts`, plus assertion updates in the system and unit test files listed in the plan **Files** table.

Unchanged by this unit (per plan): `packages/vendor-contracts/**`, `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/coverage/calendar.ts`, `ai-platform/src/rate-limit/index.ts`, `ai-platform/src/platform-vocabulary.ts`. `entitleScenario` and `/control/entitle` remain defined until P3.10.

## 3. Harness command (this unit only)

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/admission-settlement.system.test.ts
```

Earlier platform suites and `npm test` / `npm run test:e2e` are out of scope for this command.

## 4. Entry point → module chain (by E2E id)

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
