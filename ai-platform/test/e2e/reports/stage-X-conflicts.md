# Stage X catalog-vs-code conflicts

## SX-002

- **Catalog claim:** Stage 11 Completed settlement R1 has `usage_event` tokens 30, cost **0.003**, period `2026-08`; cron `"0 4 * * *"` writes `usage_rollup` with `request_count=1`, `tokens=30`, `cost=0.003`.
- **Code behavior:** FakeAdapter `fake-v1` settlement writes 10 input + 20 output tokens. Platform pricing yields `usage_event.cost=0.005`. Rollup copies that ledger sum. Tests follow code (assert 0.005).
- **File:line:** `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts:423` and `:455`; catalog `docs/testing/catalog/stage-X-cron-and-failure-journeys.md` SX-002 expected outcome.

## SX-035

- **Catalog claim:** `[SEED]` one aged live installation-scoped `capability_grant` and a fresh live counterpart of the same grant (same installation + capability), plus aged/fresh `control_audit` and aged/fresh global `lifecycle_state='retired'` overlays. Direct `runRetentionPurge`: `ledger_deleted=3`; aged three deleted; fresh controls survive.
- **Code behavior:** Unique index `idx_capability_grant_live_installation` on `(scope, capability_id)` WHERE `revoked_at IS NULL AND scope LIKE 'installation:%'` forbids two unrevoked live grants for the same installation+capability. Seed therefore ages one live installation grant, uses a different `capability_id` for the fresh live control, and seeds retired overlays on global scope (outside the live unique index). `ledger_deleted=3` is unchanged.
- **File:line:** `ai-platform/migrations/20260805190000_routing_policy_status.sql:20-22` (`idx_capability_grant_live_installation`); `docs/testing/catalog/stage-X-cron-and-failure-journeys.md:480` (SX-035 journey setup: aged+fresh live pair); `ai-platform/src/retention/index.ts:260-263` (grant ledger delete is `changed_at` only); `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts:563-675` (SX-035).
