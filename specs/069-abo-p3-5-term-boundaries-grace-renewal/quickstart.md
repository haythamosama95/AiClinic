# Quickstart: Term boundaries, grace and renewal (P3.5)

## 1. What was implemented

This unit runs the per-clinic **boundary loop** on the quota Durable Object **alarm** and on **admission** (`applyDueBoundaries` in step 3). When an active term’s `ends_at` is due, a queued renewal becomes active at that instant; otherwise the term enters **grace** with a proportional cap, then **lapses** at `grace_ends_at` or when the grace allowance is exhausted. A **grant during grace** renews with the prior term’s calendar anchor; a **grant after lapse** opens a term at payment time. **Staging** `DURATION_SCALE` compresses month and grace-day windows on admission and alarm. Shipped coverage snapshots drive **`coverage_mirror.hard_stop_at`** (`ends_at` while active, `grace_ends_at` while in grace).

## 2. Files this unit adds or modifies

See the **Files** table in [`plan.md`](./plan.md). Primary touchpoints:

- `ai-platform/src/quota-do/coverage.ts` — boundary loop, snapshot grace/lapse, alarm scheduling, grant-during-grace, mirror `hard_stop_at`
- `ai-platform/src/quota-do/index.ts` — admission step 3 boundaries, grace exhaustion on reservation
- `ai-platform/src/worker.ts` — admission `durationScale` and alarm ship scale from `DURATION_SCALE=staging`
- `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — H-AP E2E-P3.5-01 through E2E-P3.5-08

Unchanged by this unit (per plan): `packages/vendor-contracts/**`, `ai-platform/src/coverage/calendar.ts`, `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/admission/index.ts`, `ai-platform/src/errors.ts`, `ai-platform/test/system/harness.ts`, and `coverClinic()`.

## 3. Harness command (this unit only)

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/term-boundaries-grace-renewal.system.test.ts
```

Earlier platform suites and `npm test` / `npm run test:e2e` are out of scope for this command.

## 4. Entry point → module chain (by E2E id)

| ID | Chain |
| --- | --- |
| E2E-P3.5-01 | `coverClinic()` → `vendorCall` `grant` while T1 is active → `setTestClock` to T1 `ends_at` → `runDurableObjectAlarm` → `GatewayObject.alarm` → `applyDueBoundaries` → successor `term` row |
| E2E-P3.5-02 | `coverClinic()` once → `setTestClock` to `ends_at` → `runDurableObjectAlarm` → `POST /v1/requests` → `admissionRPC` step 3 then step 5 → `setTestClock` to `grace_ends_at` → `runDurableObjectAlarm` → `POST /v1/requests` → `coverage_lapsed` |
| E2E-P3.5-03 | `coverClinic()` → boundary into grace → `POST /v1/requests` until the grace allowance is taken → next `POST` → `coverage_lapsed` reason `grace_exhausted` |
| E2E-P3.5-04 | `coverClinic()` into grace → `setTestClock` to day 3 → `coverClinic()` → `applyGrantRPC` grace branch → new `term.calendar_start` |
| E2E-P3.5-05 | `coverClinic()` → clock through grace to lapse → `setTestClock` two months later → `coverClinic()` → `applyGrantRPC` no-coverage branch |
| E2E-P3.5-06 | `setTestClock` past `grace_ends_at` with no `runDurableObjectAlarm` → `POST /v1/requests` → `admissionRPC` step 3 → `coverage_lapsed` |
| E2E-P3.5-07 | `DURATION_SCALE=staging` on the worker binding → `coverClinic()` → `setTestClock` to the scaled `ends_at` and `grace_ends_at` → `runDurableObjectAlarm` and `POST /v1/requests` |
| E2E-P3.5-08 | `runDurableObjectAlarm` on activate, end, and grace start → D1 `coverage_event` → `coverage_mirror.hard_stop_at` |
