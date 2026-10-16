# Complimentary grants, ceilings, term adjustments and suspension

## 1. What was implemented

Complimentary grants (queued or active terms with operator attention AL-11), versioned ceiling policy with a 90-day rolling window, ceiling override with a second HP assertion (AL-12), term adjustment on the active term, clinic suspend and resume (AL-19), and `inspectCoverage` for the coverage ledger.

## 2. Files this unit adds or modifies

| File | Role |
| --- | --- |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/data-model.md` | Entities and ceiling numbers |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/complimentary-and-adjustment-grant.md` | Complimentary and adjustment grant contract |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/ceiling-policy.md` | `ceiling_policy` / `setCeilingPolicy` |
| `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/contracts/suspend-resume-inspect.md` | Suspend, resume, inspect |
| `ai-platform/migrations/20261006130000_ceiling_policy.sql` | D1 `ceiling_policy` seed |
| `ai-platform/src/vendor/entrypoint.ts` | HP gates, `setCeilingPolicy`, complimentary/adjustment grant, suspend, resume, inspect |
| `ai-platform/src/quota-do/coverage.ts` | Apply, ceilings, adjustment, suspend flag, inspect ledger |
| `ai-platform/src/worker.ts` | DO RPC dispatch and outbox alarm (AL-11, AL-12, AL-19) |
| `ai-platform/src/alert/index.ts` | AL-12 and AL-19 email raisers |
| `ai-platform/test/system/harness.ts` | `VendorMethod` names and `coverClinicSigner()` |
| `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` | H-AP E2E-P3.6-01 through E2E-P3.6-09 |

## 3. Harness command (this unit only)

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/complimentary-grants-ceilings.system.test.ts
```

## 4. Entry point → module chain per E2E id

Every scenario is asserted by H-AP; use the harness command above only.

| ID | Chain |
| --- | --- |
| E2E-P3.6-01 | `coverClinic()` → `vendorCall("grant")` complimentary 14-day HP → `applyGrantRPC` queues the term → `runDurableObjectAlarm` → `raiseAl11GrantFromOutbox` → `getCapturedVendorEmails` |
| E2E-P3.6-02 | `vendorCall("grant")` 365-day → DO ceiling check `exceeds_ceiling` → same grant with `ceiling_override` and a second assertion → `applied` + AL-12 → same assertion reused as the override → `rejected` |
| E2E-P3.6-03 | two `vendorCall("grant")` 31-day calls, then a 1-day grant → `exceeds_ceiling`; a second org's `term_adjustment` `extend_days` is inside the same day sum |
| E2E-P3.6-04 | `vendorCall("grant")` with `reason` omitted, then with `operator_email` omitted → `rejected` `bad_request` |
| E2E-P3.6-05 | `vendorCall("grant")` `term_adjustment` +7 days, then a negative `extend_days`, then `adjustment.plan` → `runDurableObjectAlarm` → `getCapabilities` |
| E2E-P3.6-06 | `vendorCall("suspend")` → `invoke` `POST /v1/requests` 403 `suspended` → `setTestClock` to `ends_at` → `runDurableObjectAlarm` still 403 `suspended` → `vendorCall("resume")` → `invoke` 200 |
| E2E-P3.6-07 | complimentary 14-day `vendorCall("grant")` on an uncovered org → paid `vendorCall("grant")` queues |
| E2E-P3.6-08 | `vendorCall("inspectCoverage")` with an Access JWT → DO terms, grants, reservations → same call without the JWT → `rejected` |
| E2E-P3.6-09 | `vendorCall("setCeilingPolicy")` twice with one assertion → `vendorCall("grant")` 30-day `day` → `applied` |
