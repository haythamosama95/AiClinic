# Stage 02 catalog-vs-code conflicts

## S02-024

- **Catalog claim:** Side effects of `set_ai_availability(true, …)` are one `ai_internal.app_settings` upsert for `ai.availability` with `created_by`/`updated_by` = BOOT's auth user.
- **Code behavior:** Seed `INSERT` into `ai_internal.app_settings` omits `created_by` (column default is NULL). `auth_internal.set_ai_availability` inserts with both `created_by` and `updated_by` set to the caller, but `ON CONFLICT (key) DO UPDATE` writes `value_json`, `updated_at`, `updated_by`, and undelete columns only — not `created_by`. After the seed row, BOOT's call therefore sets `updated_by` = BOOT and leaves `created_by` NULL.
- **File:line:** `backend/supabase/migrations/20260802140000_ai_availability_flag.sql:3-8` (seed omits `created_by`); `backend/supabase/migrations/20260905120100_set_ai_availability_rpc.sql:41-50` (`ON CONFLICT` updates `updated_by` only).

## S02-027

- **Catalog claim:** Action SQL reconstructs the Stage 3 handoff from `ai_internal.installation_keys` `WHERE ik.kid = '<K0>'` and compares it to S02-009 enroll output. Journey setup note says that if rotation has occurred, use the newest active key — K2 from S02-020.
- **Code behavior:** This file's journey continues through S02-022 (recovery re-enroll KX) and S02-023 (rotate while every key is revoked). After S02-023 the only non-deleted active row is the rotate-minted K3, not K0 (revoked in S02-014) or K2 (revoked in S02-020 / seed revoke-all). Handoff is reconstructed from `revoked_at IS NULL` ordered by `valid_from DESC` and compared to S02-023 RPC `data`.
- **File:line:** `docs/testing/catalog/stage-02-clinic-keypair.md` S02-027 Action SQL (`WHERE ik.kid = '<K0>'`); `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` rotate success payload (same JWK shape as enroll); sequential keystore after S02-023 in `backend/tests/catalog/stage-02-revoke-rotate-availability.sql`.
