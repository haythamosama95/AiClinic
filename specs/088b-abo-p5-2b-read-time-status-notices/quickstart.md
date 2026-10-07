# Read-time status, notices and billing status

**Unit**: P5.2b · **Branch**: `ai/088b-abo-p5-2b-read-time-status-notices` · **Harness**: H-FS · **Verification**: T012 (four E2E ids)

## 1. What was implemented

The Supabase backend computes grace, lapse, `reason`, `days_left`, notices, `as_of`, and `stale` at read time from the P5.2a projection, and exposes an administrator billing RPC that returns the same view plus flat billing fields. Platform and ABO workers are not started in this unit's harness; the puller and projection writes stay with P5.2a.

- **Shared reader** (`auth_internal.get_ai_status`) — `STABLE` `SECURITY DEFINER` function keyed on `current_org_id()`. Captures PostgreSQL `now()` once as `as_of` and reuses it for `days_left`, `grace_days_left`, `next_change_at`, and `stale`. Applies the read-time state clock (`active` → `grace` → `lapsed`), maps `reason`, builds the closed `notices[]` set (`ends_soon`, `in_grace`, `allowance_low`, `allowance_exhausted`, `lapsed`, `ended_reversed`, `suspended`, `status_stale`), and reads `platform_base_url` from `auth_internal.ai_app_setting_text`. Does not `UPDATE` `clinic_ai_coverage` or `feed_state` (FR-001, FR-002, FR-003, FR-005).
- **`public.get_ai_status`** — Version gate (`0` or `1` only; otherwise `CONTRACT_VERSION_UNSUPPORTED`), then the shared reader. No role gate. Success `data` is the status view only: no prices, payments, or references (FR-001, FR-008).
- **`public.get_ai_billing_status`** — Version gate, then `administrator` membership check (`FORBIDDEN_ROLE` with null `data` for other roles), then the shared reader plus flat fields (`plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `abo_base_url`) and SQL `subscription_ref`. No `remaining` key (FR-003, FR-004, FR-005, FR-006, FR-008).
- **`subscription_ref`** — Computed in the billing wrapper: UTF-8 SHA-256 of `sub-ref:` concatenated with `current_org_id()::text`, Crockford base-32 (same algorithm as `crockfordEncode` in `packages/vendor-contracts/src/identifiers.ts`), first 8 characters, prefix `AIC-`. For org `7c9e6679-7425-40de-944b-e07fc1f90ae7` the value is `AIC-2W3W7P9G` (FR-007).
- **H-FS** (`e2e/fullstack/`) — Node runner signs in through local Supabase (`create_staff_account` for each `public.staff_role`), seeds `ai_internal.clinic_ai_coverage` and `ai_internal.feed_state` with `psql`, and calls PostgREST. Workers are not started (FR-001, FR-006).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/088b-abo-p5-2b-read-time-status-notices/quickstart.md` | FR-001, FR-006, FR-007 |
| `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `e2e/fullstack/test/p5-2b.test.mjs` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |

## 3. Harness command for this unit's tests only

From `e2e/fullstack/`:

```bash
node --import tsx --test test/p5-2b.test.mjs
```

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P5.2-03 | PostgREST `public.get_ai_status` → version gate → `auth_internal.get_ai_status` |
| E2E-P5.2-04 | PostgREST `public.get_ai_status` and `public.get_ai_billing_status` → version gate → (`administrator` gate on billing only) → `auth_internal.get_ai_status` |
| E2E-P5.2-09 | PostgREST `public.get_ai_billing_status` → version gate → `administrator` gate → `auth_internal.get_ai_status` → SQL `subscription_ref` |
| E2E-P5.2-11 | PostgREST `public.get_ai_status` (each `public.staff_role`) → version gate → `auth_internal.get_ai_status` |
