# Stage 02 — Clinic keypair enrollment (Supabase side)

Source files read:
- `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` (keystore schema, `enforce_single_installation` trigger, base64url helpers)
- `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` (enroll / rotate / revoke RPCs, public wrappers, grants)
- `backend/supabase/migrations/20260802140000_ai_availability_flag.sql` (`ai.availability` seed, `get_ai_availability`)
- `backend/supabase/migrations/20260803140000_b1_review_resolution.sql` (idempotent re-apply of the same routines; confirms final shape)
- `backend/supabase/migrations/20260821120000_fix_get_ai_availability_security_definer.sql` (SECURITY DEFINER fix on the public wrapper)
- `backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql` (final `enroll_installation_keypair` with `ALREADY_ENROLLED` guard)
- `backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql` (`revoke_installation_key` with `CANNOT_REVOKE_LAST_ACTIVE_KEY` guard)
- `backend/supabase/migrations/20260905120600_revoke_fresh_return_stored_revoked_at.sql` (fresh-revoke payload returns stored `revoked_at`)
- `backend/supabase/migrations/20260903180000_grant_ai_visit_summary_administrator.sql` (`ai.visit_summary` grant)
- `backend/supabase/migrations/20260905120100_set_ai_availability_rpc.sql` (`set_ai_availability`, administrator-gated write path)
- `backend/supabase/migrations/20260516100000_auth_rbac_schema.sql` (`rpc_result` type, `staff_members.is_bootstrap_admin`)
- `backend/supabase/migrations/20260516100300_auth_rbac_functions.sql` (`rpc_success` / `rpc_error` shapes)
- `backend/supabase/migrations/20260516100400_auth_rbac_seed.sql` (bootstrap admin seed, `ai.*` permission seed)
- `backend/supabase/migrations/20260611150000_remove_owner_role.sql` (final `auth_internal.assert_owner_or_administrator`: administrator-only; owner role removed)
- `backend/supabase/migrations/20260613140000_role_permissions_full_matrix.sql` (full role×permission matrix insert)
- Orientation doc: `docs/architecture/ai-platform/data-journey/04-stage-2-clinic-keypair-enrollment.md`

## Common journey setup (referenced by scenarios below)

Unless a scenario says otherwise, every scenario starts from this state, built with real operations on a throwaway local Supabase with all migrations applied:

1. **Seeded bootstrap admin** (created by migration `20260516100400_auth_rbac_seed.sql`, not by us): `auth.users.id = a0000000-0000-4000-8000-000000000001` (login `admin@admin`), `staff_members.id = b0000000-0000-4000-8000-000000000001`, `role = 'administrator'`, `is_bootstrap_admin = true`. Referred to below as **BOOT** (bootstrap administrator).
2. **Clinic bootstrap** (pre-AI clinic onboarding journey, real RPC): as BOOT, `SELECT public.bootstrap_finish_setup('Sunrise Dental Clinic', 'Main Branch', '[{"username":"nadia_karim","password":"Nadia#Karim2026!","full_name":"Nadia Karim","role":"administrator"},{"username":"omar_haddad","password":"Omar#Haddad2026!","full_name":"Omar Haddad","role":"doctor"}]'::jsonb, '{}'::jsonb, NULL, 'EGP', 'Africa/Cairo', 'MAIN', '12 Nile St, Cairo', '+201000000010', NULL);` → org **ORG** "Sunrise Dental Clinic", branch **B-MAIN** "Main Branch", staff **ADMIN** (Nadia Karim, administrator) and **DOCTOR** (Dr. Omar Haddad, doctor). Look up their `auth_user_id` from `public.staff_members`.
3. **Empty keystore** ([SEED] reset on a throwaway database, per orientation doc §8.3.1 — justified because scenarios must start from a known keystore and no RPC deletes key rows): as `postgres`, `DELETE FROM ai_internal.ai_token_issuance; DELETE FROM ai_internal.installation_keys;` and `UPDATE ai_internal.app_settings SET value_json = '{"enrolled": false, "platform_base_url": null}'::jsonb, is_deleted = false, deleted_at = NULL, deleted_by = NULL WHERE key = 'ai.availability';`
4. **JWT claim injection** (repo's backend test pattern, per orientation doc §8.1): to act as a staff member, run `SELECT set_config('role', 'authenticated', true); SELECT set_config('request.jwt.claims', json_build_object('sub', '<auth_user_id>'::text, 'role', 'authenticated')::text, true);` in the same transaction/session, then call the RPC. Reset to `postgres` to inspect `ai_internal`.
5. Saved values: **I0** = the `installation_id` minted in S02-009; **K0**, **K1**, **K2**, **KX** = kids minted in S02-009, S02-013, S02-020, S02-022 respectively.

All `rpc_result` expectations below name the four columns of the composite type `(success, data, error_code, error_message)` exactly as `public.rpc_success` / `public.rpc_error` produce them.

**Administrator gate and guard ordering.** Enroll, rotate, and revoke each call `auth_internal.assert_owner_or_administrator()` as their first statement. The caller must be an active, non-deleted staff member with `role = 'administrator'` **or** `is_bootstrap_admin = true` (the `owner` role was removed in `20260611150000`). The role check precedes all other validation — unauthorized callers always receive `FORBIDDEN`, never input or state errors (S02-005, S02-006, S02-012).

**Keypair `rpc_result` error codes** (envelope only — not raised errors): `FORBIDDEN`, `INSTALLATION_NOT_ENROLLED`, `ALREADY_ENROLLED`, `INVALID_INPUT`, `KEY_NOT_FOUND`, `CANNOT_REVOKE_LAST_ACTIVE_KEY`. `SINGLE_INSTALLATION_VIOLATION` is **not** an envelope code — the `installation_keys_single_installation` trigger raises it (P0001) on a direct INSERT with a second `installation_id`; no RPC reaches that branch (S02-021).

**Rotate with all keys revoked.** `rotate_installation_key` looks up any non-deleted row with no `revoked_at` filter (`20260801120100…sql:L103-L115`). Rotation succeeds when historical rows exist but every key is revoked — the recovery path alongside re-enroll (S02-022, S02-023). `INSTALLATION_NOT_ENROLLED` fires only when no non-deleted rows exist (S02-003).

**`issue_ai_token` (Stage 6).** Returns `text` on success; on failure it RAISEs contract codes (SQLSTATE `P0001`) — including `UNAUTHENTICATED`, `SESSION_EXPIRED`, and `STAFF_NOT_FOUND` — not an `rpc_result` envelope. PostgREST surfaces these as HTTP errors.

---

## Scenario S02-001 — Availability flag returns the seeded default before any enrollment

| Field | Content |
|-------|---------|
| ID | S02-001 |
| Journey setup | Common journey setup; keystore empty; no enroll has ever run. |
| Action | As DOCTOR: `SELECT public.get_ai_availability();` |
| Expected outcome | Plain `jsonb` (NOT an `rpc_result` envelope): `{"enrolled": false, "platform_base_url": null}` — exactly the value seeded by `20260802140000_ai_availability_flag.sql`. This call also proves the `20260821120000` SECURITY DEFINER fix: an `authenticated` caller reaches `auth_internal.get_ai_availability()` even though EXECUTE on it is revoked from `authenticated`; without the fix this call raises `permission denied for function get_ai_availability`. |
| Side effects | None. No write to any table (`STABLE` read of `ai_internal.app_settings` only). |
| Code reference | backend/supabase/migrations/20260802140000_ai_availability_flag.sql:L10-L26 — `auth_internal.get_ai_availability`; backend/supabase/migrations/20260821120000_fix_get_ai_availability_security_definer.sql:L4-L11 — `public.get_ai_availability` (SECURITY DEFINER) |

## Scenario S02-002 — Availability flag and keypair RPCs are denied to anon

| Field | Content |
|-------|---------|
| ID | S02-002 |
| Journey setup | Common journey setup. |
| Action | As `anon` (`SELECT set_config('role', 'anon', true);` with no JWT claims): `SELECT public.get_ai_availability();` then `SELECT public.enroll_installation_keypair();` |
| Expected outcome | Both raise `permission denied for function get_ai_availability` / `permission denied for function enroll_installation_keypair` (SQLSTATE `42501`). No `rpc_result` is produced — the GRANTs are to `authenticated` only, so the function bodies never execute. Via PostgREST this surfaces as HTTP 401/403, not as an envelope. |
| Side effects | None. `ai_internal.installation_keys` stays empty; `ai_internal.app_settings` unchanged. |
| Code reference | backend/supabase/migrations/20260802140000_ai_availability_flag.sql:L39-L40 — REVOKE/GRANT on `public.get_ai_availability`; backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L260-L266 — REVOKE/GRANT on the public keypair wrappers |

## Scenario S02-003 — Rotate before any enroll fails with INSTALLATION_NOT_ENROLLED

| Field | Content |
|-------|---------|
| ID | S02-003 |
| Journey setup | Common journey setup; `ai_internal.installation_keys` is empty (no rows at all, not even revoked ones). |
| Action | As BOOT: `SELECT public.rotate_installation_key();` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'INSTALLATION_NOT_ENROLLED'`, `error_message = 'Enroll an installation keypair before rotating.'` — the guard fires because the lookup over non-deleted rows finds nothing (`v_installation_id IS NULL`). |
| Side effects | No row inserted into `ai_internal.installation_keys` (verify as `postgres`: `SELECT count(*) FROM ai_internal.installation_keys;` = 0). No other table touched. |
| Code reference | backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L102-L115 — `auth_internal.rotate_installation_key` empty-keystore guard |

## Scenario S02-004 — Enroll as a non-administrator (doctor) is FORBIDDEN

| Field | Content |
|-------|---------|
| ID | S02-004 |
| Journey setup | Common journey setup; keystore empty. DOCTOR holds the `ai.access` permission (seeded) — proving that permission grants do NOT substitute for the role gate. |
| Action | As DOCTOR: `SELECT public.enroll_installation_keypair();` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'FORBIDDEN'`, `error_message = 'Only administrators may enroll installation keys.'` — `auth_internal.assert_owner_or_administrator()` raises `FORBIDDEN` (P0001) because `role <> 'administrator' AND NOT is_bootstrap_admin`; the function's EXCEPTION block converts it to the envelope. |
| Side effects | No row in `ai_internal.installation_keys` (count = 0). No write anywhere. |
| Code reference | backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L17-L17 — guard call; backend/supabase/migrations/20260611150000_remove_owner_role.sql:L58-L86 — `auth_internal.assert_owner_or_administrator` (final, administrator-only version); backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L85-L96 — FORBIDDEN exception mapping |

## Scenario S02-005 — Rotate as a non-administrator (doctor) is FORBIDDEN

| Field | Content |
|-------|---------|
| ID | S02-005 |
| Journey setup | Common journey setup; keystore empty. |
| Action | As DOCTOR: `SELECT public.rotate_installation_key();` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'FORBIDDEN'`, `error_message = 'Only administrators may rotate installation keys.'` Note the ordering: the role check runs BEFORE the empty-keystore guard, so a doctor gets `FORBIDDEN`, never `INSTALLATION_NOT_ENROLLED`. |
| Side effects | No row in `ai_internal.installation_keys`. |
| Code reference | backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L101-L101 — guard call; L161-L171 — FORBIDDEN exception mapping |

## Scenario S02-006 — Revoke as a non-administrator (doctor) is FORBIDDEN, even with a blank kid

| Field | Content |
|-------|---------|
| ID | S02-006 |
| Journey setup | Common journey setup; keystore empty. |
| Action | As DOCTOR: `SELECT public.revoke_installation_key('');` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'FORBIDDEN'`, `error_message = 'Only administrators may revoke installation keys.'` — the role check precedes the `INVALID_INPUT` blank-kid check, so authorization always wins over validation. |
| Side effects | None. |
| Code reference | backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L13-L17 — guard call before input validation; L58-L68 — FORBIDDEN exception mapping |

## Scenario S02-007 — Enroll as a deactivated administrator is FORBIDDEN

| Field | Content |
|-------|---------|
| ID | S02-007 |
| Journey setup | Common journey setup; then as BOOT: `SELECT public.set_staff_active('<ADMIN staff_members.id>', false);` (real RPC) so ADMIN's row has `is_active = false`. |
| Action | As ADMIN (JWT `sub` = ADMIN's `auth_user_id`): `SELECT public.enroll_installation_keypair();` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'FORBIDDEN'`, `error_message = 'Only administrators may enroll installation keys.'` — the staff lookup filters `is_active = true`, so the row is NOT FOUND and the gate raises `FORBIDDEN` via the first branch (not the role branch). |
| Side effects | No row in `ai_internal.installation_keys`. (The `set_staff_active` call itself writes `staff_members` + `audit_log` as part of setup, not as a result of the action.) |
| Code reference | backend/supabase/migrations/20260611150000_remove_owner_role.sql:L66-L77 — `is_active = true` filter and NOT FOUND raise in `auth_internal.assert_owner_or_administrator` |

## Scenario S02-008 — Enroll as an auth user with no staff row is FORBIDDEN

| Field | Content |
|-------|---------|
| ID | S02-008 |
| Journey setup | Common journey setup; keystore empty. |
| Action | Inject JWT with a `sub` that has no `staff_members` row, e.g. `a0000000-0000-4000-8000-00000000dead`: `SELECT public.enroll_installation_keypair();` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'FORBIDDEN'`, `error_message = 'Only administrators may enroll installation keys.'` — same NOT FOUND branch as S02-007. |
| Side effects | No row in `ai_internal.installation_keys`. |
| Code reference | backend/supabase/migrations/20260611150000_remove_owner_role.sql:L66-L77 — NOT FOUND raise in `auth_internal.assert_owner_or_administrator` |

## Scenario S02-009 — First enroll (happy path) mints installation I0 and key K0

| Field | Content |
|-------|---------|
| ID | S02-009 |
| Journey setup | Common journey setup; keystore empty; all blocker scenarios S02-003…S02-008 already tripped. |
| Action | As BOOT: `SELECT public.enroll_installation_keypair();` |
| Expected outcome | `success = true`, `error_code = NULL`, `error_message = NULL`. `data` is exactly `{"kid": "<K0>", "installation_id": "<I0>", "public_jwk": {"kty": "OKP", "crv": "Ed25519", "x": "<base64url, 43 chars, no padding>", "kid": "<K0>"}}` where I0 and K0 are fresh UUID v4 strings (`gen_random_uuid()`), and `public_jwk.kid` equals top-level `kid`. `data` contains NO `secret_key` or other private material. Save I0 and K0 for all later scenarios. |
| Side effects | Exactly ONE new row in `ai_internal.installation_keys`: `kid = K0`, `installation_id = I0` (fresh — no prior row existed), `algorithm = 'EdDSA'`, `octet_length(public_key) = 32`, `octet_length(secret_key) = 64`, `revoked_at IS NULL`, `is_deleted = false`, `created_by = updated_by = a0000000-0000-4000-8000-000000000001` (BOOT's auth user), `valid_from`/`created_at` ≈ now. `auth_internal.base64url_encode(public_key)` of the stored row equals the returned `public_jwk.x`. NO write to `ai_internal.app_settings`, `ai_internal.ai_token_issuance`, or `public.audit_log`. |
| Code reference | backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L4-L97 — `auth_internal.enroll_installation_keypair` (final version with ALREADY_ENROLLED guard); backend/supabase/migrations/20260801120000_ai_keystore_schema.sql:L148-L157 — `auth_internal.base64url_encode` |

## Scenario S02-010 — Keystore is not readable by authenticated clients

| Field | Content |
|-------|---------|
| ID | S02-010 |
| Journey setup | S02-009 completed (K0/I0 exist). |
| Action | As BOOT (role `authenticated`): `SELECT * FROM ai_internal.installation_keys;` |
| Expected outcome | Raises `permission denied for schema ai_internal` (SQLSTATE `42501`) — USAGE on `ai_internal` is revoked from `authenticated`; even if schema access existed, the `installation_keys_deny_all` RLS policy (`USING (false)`) returns zero rows. The private key is unreachable from any client session. |
| Side effects | None. |
| Code reference | backend/supabase/migrations/20260801120000_ai_keystore_schema.sql:L14-L16 — schema REVOKE; L113-L117 — `installation_keys_deny_all` policy |

## Scenario S02-011 — Keypair enrollment does not touch the availability flag

| Field | Content |
|-------|---------|
| ID | S02-011 |
| Journey setup | S02-009 completed (clinic holds an active key). |
| Action | As DOCTOR: `SELECT public.get_ai_availability();` |
| Expected outcome | Still exactly `{"enrolled": false, "platform_base_url": null}`. Enrolling a keypair is not platform enrollment: the flag flips only after Stage 3 platform enrollment of installation I0 plus `set_ai_availability` (S02-024). |
| Side effects | None. |
| Code reference | backend/supabase/migrations/20260802140000_ai_availability_flag.sql:L10-L26 — `auth_internal.get_ai_availability`; backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L4-L97 — enroll body contains no `app_settings` write |

**Availability write path (C-16):** `public.set_ai_availability(p_enrolled, p_platform_base_url)` (migration `20260905120100_set_ai_availability_rpc.sql`) closes the former manual `UPDATE ai_internal.app_settings` gap — administrators call it after Stage 3 platform enrollment. Enroll/rotate/revoke still do not touch the flag (this scenario unchanged).

## Scenario S02-012 — Second enroll while an active key exists fails with ALREADY_ENROLLED

| Field | Content |
|-------|---------|
| ID | S02-012 |
| Journey setup | S02-009 completed (K0 active). Caller is ADMIN (a plain administrator, not the bootstrap admin) to prove the role gate passes and the guard itself fires. |
| Action | As ADMIN: `SELECT public.enroll_installation_keypair();` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'ALREADY_ENROLLED'`, `error_message = 'An active installation key already exists. Use rotate_installation_key() to rotate keys.'` — the guard checks `EXISTS (... is_deleted = false AND revoked_at IS NULL)` before minting anything. |
| Side effects | Still exactly ONE row in `ai_internal.installation_keys` (`kid = K0`, `revoked_at IS NULL`); no new keypair generated, no write of any kind. |
| Code reference | backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L19-L29 — ALREADY_ENROLLED guard |

## Scenario S02-013 — Rotate (happy path) adds key K1 under the same installation I0

| Field | Content |
|-------|---------|
| ID | S02-013 |
| Journey setup | S02-012 completed (K0 active, ALREADY_ENROLLED observed). |
| Action | As ADMIN: `SELECT public.rotate_installation_key();` |
| Expected outcome | `success = true`, `error_code = NULL`, `error_message = NULL`. `data` has the same shape as enroll: `{"kid": "<K1>", "installation_id": "<I0>", "public_jwk": {"kty": "OKP", "crv": "Ed25519", "x": "<base64url>", "kid": "<K1>"}}` with K1 ≠ K0 and `installation_id` IDENTICAL to I0 (reused from the existing non-deleted row, never re-minted). Save K1. |
| Side effects | Exactly ONE new row in `ai_internal.installation_keys` (now two rows total): new row `kid = K1`, `installation_id = I0`, `algorithm = 'EdDSA'`, `revoked_at IS NULL`, `created_by = updated_by` = ADMIN's `auth_user_id`. The K0 row is completely untouched (still active — rotation is additive). No write to `app_settings` or `ai_token_issuance`. |
| Code reference | backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L89-L172 — `auth_internal.rotate_installation_key` |

## Scenario S02-014 — Revoke the superseded key K0 (happy path)

| Field | Content |
|-------|---------|
| ID | S02-014 |
| Journey setup | S02-013 completed (K0 and K1 both active). |
| Action | As BOOT: `SELECT public.revoke_installation_key('<K0>');` |
| Expected outcome | `success = true`, `error_code = NULL`, `error_message = NULL`, `data = {"kid": "<K0>", "revoked_at": "<T0>"}` where T0 is EXACTLY the `revoked_at` stored on the K0 row (the fresh-revoke path re-SELECTs after UPDATE and returns `v_row.revoked_at`, matching the idempotent branch). |
| Side effects | The K0 row is UPDATEd: `revoked_at` set, `updated_at` set, `updated_by = a0000000-0000-4000-8000-000000000001`. The K1 row is untouched (`revoked_at IS NULL`). No row is deleted; no other table written. |
| Code reference | backend/supabase/migrations/20260905120600_revoke_fresh_return_stored_revoked_at.sql — UPDATE, re-SELECT, and success return of `auth_internal.revoke_installation_key` |

## Scenario S02-015 — Re-revoking an already-revoked key is idempotent

| Field | Content |
|-------|---------|
| ID | S02-015 |
| Journey setup | S02-014 completed (K0 revoked at time T0, stored on the row). |
| Action | As BOOT: `SELECT public.revoke_installation_key('<K0>');` |
| Expected outcome | `success = true`, `data = {"kid": "<K0>", "revoked_at": "<T0>"}` where T0 is EXACTLY the `revoked_at` stored on the row by S02-014 (the idempotent branch returns `v_row.revoked_at`, not a fresh timestamp). |
| Side effects | NONE — no UPDATE fires on this path (verify the row's `updated_at` is unchanged from S02-014). |
| Code reference | backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L29-L33 — idempotent early return |

## Scenario S02-016 — Revoke with a blank kid fails with INVALID_INPUT

| Field | Content |
|-------|---------|
| ID | S02-016 |
| Journey setup | S02-013 completed (keys exist). Caller is BOOT (authorized) so the input validation branch is what fires. |
| Action | As BOOT, two calls: `SELECT public.revoke_installation_key('');` and `SELECT public.revoke_installation_key('   ');` (whitespace-only — the `trim()` boundary). |
| Expected outcome | Both return `success = false`, `data = NULL`, `error_code = 'INVALID_INPUT'`, `error_message = 'Key id is required.'` — `NULLIF(trim(p_kid), '') IS NULL` catches NULL, empty, and whitespace-only input. |
| Side effects | None — no row read or written beyond the (fruitless) validation. |
| Code reference | backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L15-L17 — blank-kid guard |

## Scenario S02-017 — Revoke with an unknown kid fails with KEY_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S02-017 |
| Journey setup | S02-013 completed. |
| Action | As BOOT: `SELECT public.revoke_installation_key('00000000-0000-0000-0000-000000000000');` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'KEY_NOT_FOUND'`, `error_message = 'Installation key was not found.'` — well-formed but nonexistent kid; the lookup over `is_deleted = false` rows finds nothing. |
| Side effects | None. Both key rows unchanged. |
| Code reference | backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L19-L27 — lookup and NOT FOUND return |

## Scenario S02-018 — Revoke with a soft-deleted kid fails with KEY_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S02-018 |
| Journey setup | S02-013 completed; then [SEED] as `postgres`: `UPDATE ai_internal.installation_keys SET is_deleted = true, deleted_at = now() WHERE kid = '<K0>';` — justified because no RPC soft-deletes key rows; this state is only reachable via privileged maintenance, and it exercises the `ik.is_deleted = false` filter in the lookup. (K0 was already revoked in S02-014, so soft-deleting it leaves the active-key count at 1 and does not disturb later guards.) |
| Action | As BOOT: `SELECT public.revoke_installation_key('<K0>');` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'KEY_NOT_FOUND'`, `error_message = 'Installation key was not found.'` — a soft-deleted row is invisible to the RPC even though the kid physically exists. |
| Side effects | None beyond the [SEED] update itself. Afterwards, as `postgres`, restore: `UPDATE ai_internal.installation_keys SET is_deleted = false, deleted_at = NULL, deleted_by = NULL WHERE kid = '<K0>';` |
| Code reference | backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L19-L23 — `is_deleted = false` filter in the lookup |

## Scenario S02-019 — Revoking the last active key fails with CANNOT_REVOKE_LAST_ACTIVE_KEY

| Field | Content |
|-------|---------|
| ID | S02-019 |
| Journey setup | S02-015 completed: K0 revoked, K1 is the ONLY active key (`is_deleted = false AND revoked_at IS NULL` count = 1). |
| Action | As BOOT: `SELECT public.revoke_installation_key('<K1>');` |
| Expected outcome | `success = false`, `data = NULL`, `error_code = 'CANNOT_REVOKE_LAST_ACTIVE_KEY'`, `error_message = 'Cannot revoke the last active installation key. Rotate a replacement key first.'` — the guard counts active rows BEFORE updating and rejects when the count is exactly 1. |
| Side effects | NONE — K1 keeps `revoked_at IS NULL` (verify as `postgres`). No UPDATE fires. |
| Code reference | backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L35-L45 — last-active-key guard |

## Scenario S02-020 — Production rotation order: rotate to K2, then revoke K1 succeeds

| Field | Content |
|-------|---------|
| ID | S02-020 |
| Journey setup | S02-019 completed (K1 sole active key, guard observed). This is the documented production order: rotate first, revoke the superseded key second. |
| Action | As ADMIN: `SELECT public.rotate_installation_key();` → save new kid as K2. Then as BOOT: `SELECT public.revoke_installation_key('<K1>');` |
| Expected outcome | Rotate: `success = true`, `data.installation_id = I0`, `data.kid = K2` (≠ K0, K1). Revoke of K1 now succeeds because two active keys existed at guard time: `success = true`, `data = {"kid": "<K1>", "revoked_at": "<T1>"}` where T1 is EXACTLY the `revoked_at` stored on the K1 row. |
| Side effects | New row K2 (`revoked_at IS NULL`, `created_by` = ADMIN's auth user). K1 row UPDATEd (`revoked_at`, `updated_at`, `updated_by` = BOOT's auth user). End state: K0 revoked, K1 revoked, K2 active — exactly one active key, three non-deleted rows, all sharing I0. |
| Code reference | backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L89-L172 — `auth_internal.rotate_installation_key`; backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L35-L56 — guard passes with count = 2, then UPDATE |

## Scenario S02-021 — Single-installation trigger rejects a second installation_id

| Field | Content |
|-------|---------|
| ID | S02-021 |
| Journey setup | S02-020 completed (rows exist under I0). No RPC can reach this branch — enroll and rotate always reuse the existing `installation_id` — so the trigger is exercised by a privileged direct insert, matching orientation doc §8.3.9. This is the ACTION (an attack/bug simulation), not state seeding. |
| Action | As `postgres`: `INSERT INTO ai_internal.installation_keys (kid, installation_id, public_key, secret_key, algorithm) VALUES (gen_random_uuid()::text, gen_random_uuid(), decode('00','hex'), decode('00','hex'), 'EdDSA');` |
| Expected outcome | The statement fails with RAISED exception `SINGLE_INSTALLATION_VIOLATION`, SQLSTATE `P0001` — NOT an `rpc_result` envelope (the trigger raises before the row lands; the enroll RPC's exception handler would re-raise this rather than wrap it, since SQLERRM ≠ 'FORBIDDEN'). |
| Side effects | The INSERT is rolled back: all non-deleted rows still share installation_id I0 (verify: `SELECT count(DISTINCT installation_id) FROM ai_internal.installation_keys WHERE is_deleted = false;` = 1). |
| Code reference | backend/supabase/migrations/20260801120000_ai_keystore_schema.sql:L76-L111 — `ai_internal.enforce_single_installation` and trigger `installation_keys_single_installation` (re-applied in backend/supabase/migrations/20260803140000_b1_review_resolution.sql:L14-L49) |

## Scenario S02-022 — Recovery re-enroll after all keys are revoked reuses installation I0

| Field | Content |
|-------|---------|
| ID | S02-022 |
| Journey setup | S02-020 completed; then [SEED] as `postgres`: `UPDATE ai_internal.installation_keys SET revoked_at = clock_timestamp() WHERE is_deleted = false AND revoked_at IS NULL;` — justified because the zero-active-key state is UNREACHABLE through the revoke RPC (S02-019 guard); it arises only from disaster recovery / privileged maintenance, exactly as orientation doc §8.3.15 prescribes. Verify count of active rows = 0. |
| Action | As BOOT: `SELECT public.enroll_installation_keypair();` → save new kid as KX. |
| Expected outcome | `success = true`. The ALREADY_ENROLLED guard passes (no ACTIVE key exists). `data.installation_id = I0` — REUSED from the existing non-deleted (but revoked) rows, not re-minted. `data.kid = KX` (≠ K0, K1, K2), `data.public_jwk` in the usual OKP/Ed25519 shape. |
| Side effects | Exactly ONE new row: `kid = KX`, `installation_id = I0`, `revoked_at IS NULL` — now the sole active key. Prior rows unchanged (all revoked). No `app_settings` write. |
| Code reference | backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L19-L40 — guard passes on zero active keys; installation_id reuse from non-deleted rows |

## Scenario S02-023 — Rotate succeeds when every key is revoked but rows exist

| Field | Content |
|-------|---------|
| ID | S02-023 |
| Journey setup | Same zero-active state as S02-022's setup (re-apply the [SEED] revoke-all after S02-022, since S02-022 minted active key KX): as `postgres`, revoke KX directly. Rows exist, all revoked. |
| Action | As ADMIN: `SELECT public.rotate_installation_key();` |
| Expected outcome | `success = true` with a new kid and `installation_id = I0`. Rotate's lookup selects any non-deleted row (no `revoked_at` filter), so `v_installation_id` is found and rotation proceeds even when every existing key is revoked — the authoritative recovery path (S02-022). `INSTALLATION_NOT_ENROLLED` fires only when the table has zero non-deleted rows (S02-003). |
| Side effects | One new active row under I0; the previously revoked rows untouched. |
| Code reference | backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L103-L115 — lookup without revoked filter, guard on NULL only |

## Scenario S02-024 — Availability flag flip after Stage 3 platform enrollment

| Field | Content |
|-------|---------|
| ID | S02-024 |
| Journey setup | S02-009 completed (I0/K-material exist); Stage 3 platform enrollment of installation I0 has completed on the AI platform side (the Worker returned `platform_base_url`, e.g. `http://127.0.0.1:8787`). |
| Action | As BOOT: `SELECT public.set_ai_availability(true, 'http://127.0.0.1:8787');` then as DOCTOR (any authenticated role): `SELECT public.get_ai_availability();` |
| Expected outcome | `set_ai_availability` returns `success = true`, `data = {"enrolled": true, "platform_base_url": "http://127.0.0.1:8787"}`. `get_ai_availability` returns the same plain `jsonb` — readable by every authenticated role (doctor, receptionist, administrator alike). |
| Side effects | One `ai_internal.app_settings` upsert for key `ai.availability` (`created_by`/`updated_by` = BOOT's auth user). The flag does NOT grant quotas or capabilities — platform-side entitlement remains a Stage 4 concern; the flag only unhides the Flutter AI surface. Enroll/rotate/revoke still do not write this row (S02-011). |
| Code reference | backend/supabase/migrations/20260905120100_set_ai_availability_rpc.sql:L3-L65 — `auth_internal.set_ai_availability`; backend/supabase/migrations/20260905120400_fix_set_ai_availability_created_by.sql — `ON CONFLICT` fills `created_by` from the first writer when the seed left it NULL; backend/supabase/migrations/20260802140000_ai_availability_flag.sql:L10-L26 — read path; backend/supabase/migrations/20260821120000_fix_get_ai_availability_security_definer.sql:L4-L11 — definer wrapper |

## Scenario S02-025 — Availability falls back to the COALESCE default when the row is missing/soft-deleted

| Field | Content |
|-------|---------|
| ID | S02-025 |
| Journey setup | Common journey setup; then [SEED] as `postgres`: `UPDATE ai_internal.app_settings SET is_deleted = true, deleted_at = now() WHERE key = 'ai.availability';` — justified because no RPC mutates this row; this exercises the `is_deleted = false` filter plus the `COALESCE` fallback branch in the SQL. |
| Action | As ADMIN: `SELECT public.get_ai_availability();` |
| Expected outcome | `{"enrolled": false, "platform_base_url": null}` — the hard-coded fallback literal, identical in shape to the seeded default. The function never returns NULL and never errors when the row is absent. |
| Side effects | None. Restore afterwards as `postgres`: `UPDATE ai_internal.app_settings SET is_deleted = false, deleted_at = NULL, deleted_by = NULL WHERE key = 'ai.availability';` |
| Code reference | backend/supabase/migrations/20260802140000_ai_availability_flag.sql:L17-L25 — COALESCE fallback and `is_deleted` filter |

## Scenario S02-026 — Administrator holds the ai.visit_summary grant; doctor does not

| Field | Content |
|-------|---------|
| ID | S02-026 |
| Journey setup | Common journey setup (all migrations applied, including `20260903180000`). |
| Action | As ADMIN: `SELECT role, permission_key, is_granted FROM public.roles_permissions WHERE permission_key LIKE 'ai.%' AND is_deleted = false ORDER BY role, permission_key;` |
| Expected outcome | Rows include `('administrator', 'ai.access', true)`, `('administrator', 'ai.visit_summary', true)` (the `20260903180000` grant, `ON CONFLICT DO UPDATE` keeping `is_granted = true`, `is_deleted = false`), and `('doctor', 'ai.access', true)`; there is NO granted `ai.visit_summary` row for `doctor`, `receptionist`, or `lab_staff` (the full-matrix migration inserted those combos with `is_granted = false`, which the RLS policy hides from non-administrators but ADMIN can see). Who can call what: the keypair RPCs (enroll/rotate/revoke) consult ONLY the role gate — these `ai.*` grants instead scope Stage 6 AAT minting (`issue_ai_token` collects `ai.%` granted keys as token scopes). |
| Side effects | None (read). |
| Code reference | backend/supabase/migrations/20260903180000_grant_ai_visit_summary_administrator.sql:L3-L8 — grant upsert; backend/supabase/migrations/20260516100400_auth_rbac_seed.sql:L59-L70 — original `ai.*` seed; backend/supabase/migrations/20260613140000_role_permissions_full_matrix.sql:L4-L18 — false-filled matrix |

## Scenario S02-027 — Stage 3 handoff: enroll output is exactly what platform enrollment consumes

| Field | Content |
|-------|---------|
| ID | S02-027 |
| Journey setup | S02-023 completed; I0 and the rotate-minted K3 (newest active key) plus its `public_jwk` were saved. By this point K0 (S02-014) and K2 (S02-020) are revoked; the live key is K3. |
| Action | As `postgres`, reconstruct the Stage 3 enroll payload from clinic state: `SELECT jsonb_build_object('installation_id', ik.installation_id, 'kid', ik.kid, 'public_key', auth_internal.base64url_encode(ik.public_key), 'algorithm', 'EdDSA') FROM ai_internal.installation_keys ik WHERE ik.is_deleted = false AND ik.revoked_at IS NULL ORDER BY ik.valid_from DESC, ik.kid DESC LIMIT 1;` and compare against the values the RPC returned in S02-023. |
| Expected outcome | The reconstructed object matches the S02-023 RPC output field-for-field: `installation_id` = I0 (becomes the Stage 3 path parameter `POST /control/installations/{installation_id}/enroll` and later every AAT's `iss`), `kid` = K3 (becomes `installation_key.key_id` on the platform and the AAT header `kid`), `public_key` = the `public_jwk.x` string from S02-023 (base64url of the raw 32-byte Ed25519 public key), `algorithm` = 'EdDSA'. The handoff carries NO secret material: `secret_key` never appears in any RPC response — Stage 3 platform enrollment of installation I0 receives only the public half. |
| Side effects | None (read-only verification). |
| Code reference | backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L60-L84 — JWK construction and success payload; backend/supabase/migrations/20260801120000_ai_keystore_schema.sql:L148-L157 — `auth_internal.base64url_encode` |

---

## Doc-drift observations

1. **~~`rotate_installation_key` guard scope~~ — Fixed (D-24).** Code looks up any non-deleted row with no `revoked_at` filter; rotate succeeds when all keys are revoked but rows remain (S02-023). `INSTALLATION_NOT_ENROLLED` only with an empty/fully-soft-deleted keystore (S02-003). Documented in Common journey setup.
2. **~~`issue_ai_token` error shape misdescribed~~ — Fixed (D-24).** The function returns `text` and RAISEs contract codes (P0001), not an `rpc_result` envelope; Stage 6 catalog documents the full error table including `UNAUTHENTICATED`, `SESSION_EXPIRED`, and `STAFF_NOT_FOUND`.
3. **~~`SINGLE_INSTALLATION_VIOLATION` is not an envelope error~~ — Fixed (D-24).** Trigger-level only (S02-021); excluded from the keypair envelope error list in Common journey setup.
4. **~~Revoke success payload timestamp~~ — Fixed (BUG-11).** Fresh-revoke re-SELECTs after UPDATE and returns the stored `revoked_at` (`20260905120600…sql`), matching the idempotent branch (S02-014, S02-015, S02-020).
5. **~~"Owner" terminology~~ — Fixed (D-24).** Catalog uses **BOOT** (bootstrap administrator: `role = 'administrator'`, `is_bootstrap_admin = true`); the `owner` role was removed (`20260611150000`).
6. **~~`set_ai_availability` write RPC / guard ordering~~ — Fixed (D-24).** Migration `20260905120100_set_ai_availability_rpc.sql` adds an administrator-gated write path (S02-024); enroll/rotate/revoke still never write `app_settings` (S02-011). Role check precedes all validation — documented in Common journey setup and S02-005/S02-006/S02-012.

## Non-automatable notes

1. **PostgREST-level 401/403 for `anon` (S02-002).** SQL-level `SET ROLE anon` proves the GRANT contract (`42501` permission denied), but the exact HTTP status/body shape requires a running PostgREST instance; assert the SQL-level denial in `supabase test db` and treat the HTTP mapping as covered by PostgREST convention.
2. **`is_bootstrap_admin` escape hatch for a non-administrator.** The gate's `NOT v_staff.is_bootstrap_admin` disjunct would let a non-administrator bootstrap admin enroll, but no migration or RPC can produce that state (the seeded bootstrap admin is always `role = 'administrator'`); reaching it requires direct privileged UPDATE of `staff_members`, which contradicts "realistic state honestly built." Recorded here rather than as a scenario.
3. **Grant-migration conflict branch.** `20260903180000`'s `ON CONFLICT (role, permission_key) DO UPDATE` path (restoring `is_granted = true` after an admin flipped it to false via `update_role_permission`) cannot be observed, because migrations run exactly once in order; re-running it by hand is a migration-replay test, not a contract scenario. The resulting STATE is covered by S02-026.
4. **JWK `x` / kid / installation_id literal values.** `gen_random_uuid()` and `pgsodium.crypto_sign_new_keypair()` are non-deterministic; scenarios assert shape, encoding (43-char unpadded base64url), lengths (32/64 bytes), and round-trip equality with the stored row (S02-009, S02-027) rather than literal values.
5. **Flutter-side behavior** (hiding AI chrome while `enrolled = false`, never probing the Worker) is client behavior outside this repo's SQL contract surface; orientation doc §8.3.2/§8.3.13 covers it as manual probes.
6. **pgsodium availability.** All enroll/rotate scenarios require the `pgsodium` extension and the `pgsodium_keymaker` grant to the function owner (`20260801120000...sql:L5-L11`); on a local Supabase CLI stack this is present by default, but a bare-Postgres test rig without pgsodium cannot execute S02-009/S02-013/S02-020/S02-022/S02-023.
