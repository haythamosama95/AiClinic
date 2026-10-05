# Contract: Clinic denial codes

**Unit**: P3.4 · **Requirements**: FR-005, FR-006, FR-012

These are the clinic codes for `POST /v1/requests` after this unit. `GET /v1/capabilities` reads `coverage_mirror` by `installation_id` and does not use the config-cache TTL.

## 1. Codes

| Code | HTTP | Extra fields | Replaces |
| --- | --- | --- | --- |
| `allowance_exhausted` | 403 | — | `quota_exhausted` for allowance |
| `coverage_lapsed` | 403 | `coverage_reason` | `quota_exhausted` on a config miss |
| `forbidden_capability` | 403 | — | existing capability refusal, now from the plan snapshot |
| `suspended` | 403 | — | `installation_suspended` |
| `concurrency_limited` | 429 | `retry_after` | `quota_exhausted` for concurrency |
| `coverage_unknown` | 503 | `retry_after` | a DO `result` `rejected` version answer |
| `rate_limited` | 429 | `retry_after`, unchanged | unchanged |

`coverage_reason` is `none`, `expired`, `grace_exhausted`, `reversed`, `transferred`, or `transfer_pending`. An org that was never granted uses `none`.

`retry_after` is a positive integer of seconds. When the DO sends one, the HTTP body uses it. When it does not, the body uses `DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS` (60). `concurrency_limited` is a different `code` from `rate_limited`.

`quota_exhausted` and `period_reset` are removed from `src/errors.ts`. `suspended` is the taxonomy code. The flag is set in P3.6. This unit only maps it.

## 2. Dashboard and counters

`dashboardQuotaRejectionRate` counts `allowance_exhausted`, `coverage_lapsed`, `forbidden_capability`, `suspended`, `concurrency_limited`, and `coverage_unknown`. It does not count `quota_exhausted`. Guard rejections record those same codes through the existing `recordGuardRejection`.

## 3. Soft threshold

The admission `band` is the soft-threshold input. Band `75`, `90`, or `exhausted` sets the degraded notice. Band `ok` does not. The entitlement `soft_threshold` fraction is not read on the request path.
