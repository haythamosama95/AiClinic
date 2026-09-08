# Stage 06 — Minting an AAT (Supabase token issuer)

Source files read:
- `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql` (issuer RPC, session gate, clinic self-test verifier, grants)
- `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` (keystore, issuance ledger, `app_settings` seed)
- `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` (enroll / rotate / revoke)
- `backend/supabase/migrations/20260803140000_b1_review_resolution.sql` (idempotent re-apply of the above; confirms no added guards)
- `backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql` (`ALREADY_ENROLLED` guard)
- `backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql` (`CANNOT_REVOKE_LAST_ACTIVE_KEY` guard)
- `backend/supabase/migrations/20260903180000_grant_ai_visit_summary_administrator.sql` (`ai.visit_summary` grant)
- `backend/supabase/migrations/20260516100000_auth_rbac_schema.sql` (`roles_permissions`, `staff_role` enum)
- `backend/supabase/migrations/20260516100400_auth_rbac_seed.sql` (permission matrix seed, bootstrap admin)
- `backend/supabase/migrations/20260611150000_remove_owner_role.sql` (live `auth_internal.build_staff_claims`, owner-role removal)
- `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md` (AAT contract)
- `ai-platform/src/identity/index.ts` (`EnrolledKeyVerifier` — the downstream consumer)
- `docs/architecture/ai-platform/data-journey/08-stage-6-minting-an-aat.md` (orientation only)

## 1. Test harness conventions

**Caller simulation (JWT claim injection).** Every scenario runs on local Supabase with all
migrations applied. Callers are simulated per session:

```sql
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims',
  json_build_object(
    'sub', '<auth_user_id>',
    'role', 'authenticated',
    'exp', extract(epoch from now())::bigint + 3600
  )::text, true);
```

`auth.uid()` and `assert_valid_ai_session` both read `request.jwt.claims`; the issuer derives
`staff_member_id`, `organization_id`, role, and scopes **server-side** (via
`auth_internal.build_staff_claims` and table reads), so only `sub` and `exp` in the injected claims
matter. Reset with `SELECT set_config('role', 'postgres', true);` to inspect `ai_internal`.

**Failure shape.** `public.issue_ai_token` returns `text` and fails with bare
`RAISE EXCEPTION '<CODE>'`: psql shows `ERROR:  <CODE>`, SQLSTATE `P0001`; PostgREST returns
HTTP 400 with body `{"code":"P0001","message":"<CODE>",...}`. There is no `rpc_result` envelope.

### 1.1 Issuer error codes (guard order)

All contract failures are raised in this order (`20260801120200…sql:L143-L238`):

| Order | Code | When |
| ----- | ---- | ---- |
| 1 | `UNAUTHENTICATED` | No JWT / missing `sub` (`assert_valid_ai_session`, L87-L100) |
| 2 | `SESSION_EXPIRED` | `exp` claim in the past (L102-L107) |
| 3 | `STAFF_NOT_FOUND` | No active staff row for `auth.uid()` (`build_staff_claims` empty or re-SELECT miss, L145-L160) |
| 4 | `BRANCH_NOT_FOUND` | No active branch assignment (L162-L175) |
| 5 | `INSTALLATION_NOT_ENROLLED` | No non-deleted keystore row, or no active signing key (L177-L199) |
| 6 | `RATE_LIMITED` | Per-actor mint count ≥ ceiling within window (L214-L223) |
| 7 | `AI_ACCESS_DENIED` | Role has no granted `ai.*` permission (L225-L238) |

Non-contract failures (e.g. invalid `ai.issuer.rate_limit.ceiling` JSON → `22023` cast error, S06-033) surface as uncoded Postgres errors.

### 1.2 Branch selection and scope ordering

**Branch claim.** `ORDER BY sba.is_primary DESC, b.name LIMIT 1` (L170) — the primary active assignment wins; when no assignment is flagged primary, the alphabetically first active branch name wins (S06-024).

**Scopes claim.** Derived from `roles_permissions` with `ORDER BY permission_key` (L225-L227) — deterministic alphabetical ordering (S06-020).

**Named personas and aliases** (concrete ids written as fixed aliases for the ids returned by setup):

| Alias | Value | Notes |
| ----- | ----- | ----- |
| ORG | `d2000000-0000-4000-8000-000000000001` | "Sunrise Dental Clinic" |
| BR-A | `e3000000-0000-4000-8000-000000000001` | "Main Branch" |
| BR-B | `e3000000-0000-4000-8000-000000000002` | "North Branch" |
| DOC / DOC-AUTH | `c1000000-0000-4000-8000-000000000001` / `a1000000-0000-4000-8000-000000000001` | Dr. Nadia Haddad, role `doctor` (seed grant `ai.access`), primary branch BR-A |
| ADM / ADM-AUTH | `c1000000-0000-4000-8000-000000000002` / `a1000000-0000-4000-8000-000000000002` | Lina Khoury, role `administrator` (seed grants `ai.access`, `ai.visit_summary`), branch BR-A |
| REC / REC-AUTH | `c1000000-0000-4000-8000-000000000003` / `a1000000-0000-4000-8000-000000000003` | Rami Saleh, role `receptionist` (no `ai.*` grants), branch BR-A |
| BOOT / BOOT-AUTH | `b0000000-0000-4000-8000-000000000001` / `a0000000-0000-4000-8000-000000000001` | Seeded bootstrap admin (`admin@admin`), role `administrator`, `is_bootstrap_admin = true` |
| I0 | `f1000000-0000-4000-8000-000000000001` | Clinic singleton `installation_id` |
| K0 / K1 | `f47ac10b-58cc-4372-a567-0e02b2c3d479` / `f47ac10b-58cc-4372-a567-0e02b2c3d480` | Key ids (first enrolled / rotated-in) |

**Baseline B0** (built once; scenarios reference it plus deltas):

1. Fresh local Supabase, all migrations applied (seeded bootstrap admin, `roles_permissions`
   matrix). B0 pins only `ai.aat.lifetime_minutes` = 10 (600 s). Audience, ver, ceiling, and
   window stay at whatever the seed migration wrote — B0 does not overwrite them.
2. As BOOT: `SELECT public.bootstrap_finish_setup('Sunrise Dental Clinic', 'Main Branch',
   '[{"username":"nadia_h","password":"Cl1nic!pass","full_name":"Nadia Haddad","role":"doctor"},
     {"username":"lina_k","password":"Cl1nic!pass","full_name":"Lina Khoury","role":"administrator"},
     {"username":"rami_s","password":"Cl1nic!pass","full_name":"Rami Saleh","role":"receptionist"}]'::jsonb);`
   → ORG, BR-A, staff rows DOC/ADM/REC each primarily assigned to BR-A.
3. Stage 2 enroll happy path, as BOOT: `SELECT public.enroll_installation_keypair();`
   → `rpc_success` with `kid` K0, `installation_id` I0, `public_jwk`; one active
   `ai_internal.installation_keys` row.

Blockers are ordered as the issuer trips them (session → staff → branch → installation → rate →
scopes); the happy path follows, then key-lifecycle, config, self-test, and handoff journeys.

## Scenario S06-001 — Anonymous role cannot execute the issuer at all

| Field | Content |
|-------|---------|
| ID | S06-001 |
| Journey setup | Baseline B0. Session as `anon`: `SELECT set_config('role', 'anon', true);` with no `request.jwt.claims`. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | SQLSTATE `42501` `permission denied for function issue_ai_token` — `EXECUTE` is granted to `authenticated` only and revoked from `anon`/`PUBLIC`. Via PostgREST with no/invalid JWT: HTTP 401/403 before the function body runs. The function body (and its `UNAUTHENTICATED` raise) is never reached. |
| Side effects | None. No `ai_internal.ai_token_issuance` row; no table touched. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L405-L406 — REVOKE/GRANT on public.issue_ai_token` |

## Scenario S06-002 — Authenticated role without JWT claims is UNAUTHENTICATED

| Field | Content |
|-------|---------|
| ID | S06-002 |
| Journey setup | Baseline B0. `SELECT set_config('role', 'authenticated', true);` with `request.jwt.claims` unset (or set to `'{}'`). |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  UNAUTHENTICATED` (SQLSTATE `P0001`). `auth.uid()` is NULL because the claims carry no `sub`. (The second `UNAUTHENTICATED` raise for claims-without-`sub` at L96-L100 is defensive: `auth.uid()` derives from the same `sub` claim, so any claims shape that reaches it has already failed the first check.) |
| Side effects | None. Ledger stays empty for this caller. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L73-L112 — auth_internal.assert_valid_ai_session` |

## Scenario S06-003 — Expired clinic session JWT is SESSION_EXPIRED

| Field | Content |
|-------|---------|
| ID | S06-003 |
| Journey setup | Baseline B0. Inject claims for DOC-AUTH with an expired session: `'exp', extract(epoch from now())::bigint - 60`. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  SESSION_EXPIRED` (SQLSTATE `P0001`). The `exp` claim is compared to `now()` before any staff/branch/key lookup. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L101-L108 — exp check in assert_valid_ai_session` |

## Scenario S06-004 — Auth user with no staff row is STAFF_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S06-004 |
| Journey setup | Baseline B0. As `postgres`, create a bare auth user that was never provisioned as staff: insert into `auth.users`/`auth.identities` id `a1000000-0000-4000-8000-000000000099`, username `ghost.user` (mirrors `auth_internal.create_auth_user` minus the `staff_members` insert). Inject claims with that `sub`. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  STAFF_NOT_FOUND` (SQLSTATE `P0001`). `auth_internal.build_staff_claims` returns `{}` because no active, non-deleted `staff_members` row references this `auth_user_id`. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L145-L149 — build_staff_claims empty-check; backend/supabase/migrations/20260611150000_remove_owner_role.sql:L846-L907 — auth_internal.build_staff_claims` |

## Scenario S06-005 — Deactivated staff member is STAFF_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S06-005 |
| Journey setup | Baseline B0. As ADM: `SELECT public.set_staff_active('<DOC>', false);` (production deactivation path). Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  STAFF_NOT_FOUND` (SQLSTATE `P0001`). `build_staff_claims` filters `is_active = true`, so the deactivated doctor looks identical to a non-existent one. |
| Side effects | Only the S06-005 setup write (`staff_members.is_active = false` + `audit_log` row `staff.deactivate`). No issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L145-L160 — staff resolution gates` |

## Scenario S06-006 — Soft-deleted staff member is STAFF_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S06-006 |
| Journey setup | Baseline B0. As ADM, deactivate the doctor via `public.set_staff_active('<DOC>', false)`, then delete via the production delete path (`public.delete_staff_member`, migration `20260613210000`), which soft-deletes the `staff_members` row. (Delete of an still-active staff member raises `STAFF_STILL_ACTIVE`.) Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  STAFF_NOT_FOUND` (SQLSTATE `P0001`) — `is_deleted = false` filter in `build_staff_claims`. |
| Side effects | Only the setup soft-delete. No issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L145-L160 — staff resolution gates` |

## Scenario S06-007 — Bootstrap admin before clinic setup is BRANCH_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S06-007 |
| Journey setup | Fresh migrated database **without** step 2 of B0 (no organization, no branches). Stage 2 enroll happy path as BOOT still runs (keystore does not require an org) → K0/I0 exist. Inject claims for BOOT-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  BRANCH_NOT_FOUND` (SQLSTATE `P0001`). BOOT is role `administrator` with seed `ai.access` and passes the session/staff gates, but no `staff_branch_assignments` row can exist before `bootstrap_finish_setup`. (`build_staff_claims` would also strip `organization_id` while `setup_required`, but the branch gate fires first.) |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L162-L175 — branch resolution` |

## Scenario S06-008 — Staff with no branch assignment is BRANCH_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S06-008 |
| Journey setup | Baseline B0. As `postgres`, insert a throwaway doctor (`auth.users` + `staff_members`, role `doctor`, `is_active = true`) with **no** `staff_branch_assignments` row — [SEED]: `create_staff_account` requires ≥1 branch, so a branch-less staff row is not reachable through the public RPC; direct insert simulates a data-repair accident. Inject claims for that auth user. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  BRANCH_NOT_FOUND` (SQLSTATE `P0001`). The issuer reads `staff_branch_assignments` joined to active branches — not the JWT `branch_ids` claim. |
| Side effects | None beyond the seeded staff row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L162-L175 — branch resolution` |

## Scenario S06-009 — Staff whose only branch is inactive is BRANCH_NOT_FOUND

| Field | Content |
|-------|---------|
| ID | S06-009 |
| Journey setup | Baseline B0. As `postgres`: `UPDATE public.branches SET is_active = false WHERE id = '<BR-A>';` — [SEED]: branch deactivation is an admin settings operation; doing it as `postgres` keeps the catalog independent of the settings RPC surface. Inject claims for DOC-AUTH (BR-A is the doctor's only assignment). |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  BRANCH_NOT_FOUND` (SQLSTATE `P0001`) — the branch join requires `b.is_active = true AND b.is_deleted = false`. Same result if the assignment row itself is soft-deleted instead. |
| Side effects | None beyond the setup update. No issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L162-L175 — branch resolution` |

## Scenario S06-010 — Mint before any key is enrolled is INSTALLATION_NOT_ENROLLED

| Field | Content |
|-------|---------|
| ID | S06-010 |
| Journey setup | B0 steps 1–2 only (clinic bootstrapped; **skip** the Stage 2 enroll). `ai_internal.installation_keys` is empty. Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  INSTALLATION_NOT_ENROLLED` (SQLSTATE `P0001`). The first keystore lookup (any non-deleted row) finds nothing, so `v_installation_id` is NULL. Stage 2 enrollment is a hard prerequisite for minting. |
| Side effects | None. Ledger empty. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L177-L186 — installation lookup` |

## Scenario S06-011 — Mint when the only key is revoked is INSTALLATION_NOT_ENROLLED

| Field | Content |
|-------|---------|
| ID | S06-011 |
| Journey setup | Baseline B0, then as BOOT: `SELECT public.revoke_installation_key('<K0>');` → `rpc_success`. **Corrected (Register 4 item 1):** the last-active-key guard DOES exist (`20260902130100`, L35-L45), so plain revoke cannot produce a zero-active keystore — instead **[SEED]** `UPDATE ai_internal.installation_keys SET revoked_at = now() WHERE kid = '<K0>'` directly (justification: no production operation can reach this state; the issuer's behavior under it is still contract-relevant). Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  INSTALLATION_NOT_ENROLLED` (SQLSTATE `P0001`). The installation lookup (which ignores `revoked_at`) still finds I0, but the signing-key lookup (`revoked_at IS NULL`) finds no row. Same code, second raise site. |
| Side effects | Only the setup `revoked_at` write on K0. No issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L188-L199 — signing-key selection` |

## Scenario S06-012 — Mint when the only key is soft-deleted is INSTALLATION_NOT_ENROLLED

| Field | Content |
|-------|---------|
| ID | S06-012 |
| Journey setup | Baseline B0, then as `postgres`: `UPDATE ai_internal.installation_keys SET is_deleted = true, deleted_at = now() WHERE kid = '<K0>';` — [SEED]: no RPC soft-deletes keystore rows; this simulates operator cleanup. Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  INSTALLATION_NOT_ENROLLED` (SQLSTATE `P0001`) — both keystore lookups filter `is_deleted = false`, so the soft-deleted key is invisible and even `v_installation_id` is NULL. |
| Side effects | None beyond the setup update. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L177-L199 — installation and signing-key lookups` |

## Scenario S06-013 — Minting at the per-actor ceiling is RATE_LIMITED (boundary)

| Field | Content |
|-------|---------|
| ID | S06-013 |
| Journey setup | Baseline B0. As `postgres`: `UPDATE ai_internal.app_settings SET value_json = '2'::jsonb WHERE key = 'ai.issuer.rate_limit.ceiling';` (operator tuning to make the boundary reachable). As DOC-AUTH, mint twice — both succeed (counts 0 and 1 < 2). |
| Action | Third call as DOC-AUTH: `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  RATE_LIMITED` (SQLSTATE `P0001`). The count of non-deleted ledger rows for this actor within the window is `2 >= 2`. Boundary: `count = ceiling − 1` mints; `count = ceiling` raises. The `pg_advisory_xact_lock(87201401, hashtext(staff_id))` serializes count+insert per actor. |
| Side effects | Exactly two `ai_token_issuance` rows for DOC; the failed call inserts nothing. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L201-L223 — rate settings, advisory lock, ceiling check` |

## Scenario S06-014 — The rate ceiling is per actor, not per installation

| Field | Content |
|-------|---------|
| ID | S06-014 |
| Journey setup | S06-013 end state (ceiling 2; DOC at ceiling). Inject claims for ADM-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | A compact JWS for ADM succeeds. The ledger count is grouped by `actor_staff_id`; ADM has zero recent mints. |
| Side effects | One new `ai_token_issuance` row with `actor_staff_id = '<ADM>'`. Restore afterwards as `postgres`: ceiling back to `'100'`, `DELETE FROM ai_internal.ai_token_issuance;`. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L214-L223 — per-actor count` |

## Scenario S06-015 — Mints older than the window do not count

| Field | Content |
|-------|---------|
| ID | S06-015 |
| Journey setup | S06-013 end state (ceiling 2, DOC has 2 rows). As `postgres`: `UPDATE ai_internal.ai_token_issuance SET iat = now() - interval '2 hours';` — [SEED]: backdating simulates window passage without waiting an hour (equivalently set `ai.issuer.rate_limit.window_seconds` to `1` and sleep 2 s). Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | A compact JWS succeeds — the count predicate `iat >= now() - make_interval(secs => 3600)` excludes the backdated rows. |
| Side effects | One new issuance row with current `iat`. Restore ceiling/window to seed values afterwards. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L214-L220 — window predicate` |

## Scenario S06-016 — Rate check fires before the scope check

| Field | Content |
|-------|---------|
| ID | S06-016 |
| Journey setup | Baseline B0 with ceiling 2 (as S06-013). As `postgres`, grant then use: temporarily grant `ai.access` to `receptionist` (`is_granted = true`), mint twice as REC-AUTH (both succeed), then as ADM `SELECT public.update_role_permission('receptionist', 'ai.access', false);` — a realistic permission-lost-after-use sequence. Inject claims for REC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  RATE_LIMITED` (SQLSTATE `P0001`), **not** `AI_ACCESS_DENIED` — the rate-limit branch (L214-L223) precedes the scopes branch (L225-L238). Pairwise blocker ordering is observable. |
| Side effects | No new issuance row. Restore: ceiling 100, re-grant revoked, ledger cleared. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L209-L238 — branch ordering` |

## Scenario S06-017 — Role without any ai.* grant is AI_ACCESS_DENIED

| Field | Content |
|-------|---------|
| ID | S06-017 |
| Journey setup | Baseline B0. Inject claims for REC-AUTH (receptionist; the seeded matrix grants no `ai.*` key to `receptionist` or `lab_staff`). |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  AI_ACCESS_DENIED` (SQLSTATE `P0001`). The scopes aggregate over `roles_permissions WHERE role = 'receptionist' AND permission_key LIKE 'ai.%' AND is_granted = true` is empty (`[]`), and `jsonb_array_length < 1` raises. |
| Side effects | None. No issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L225-L238 — RBAC scope derivation and gate; backend/supabase/migrations/20260516100400_auth_rbac_seed.sql:L71-L82 — receptionist/lab_staff matrix` |

## Scenario S06-018 — Role whose ai.* grant was revoked is AI_ACCESS_DENIED

| Field | Content |
|-------|---------|
| ID | S06-018 |
| Journey setup | Baseline B0. As ADM: `SELECT public.update_role_permission('doctor', 'ai.access', false);` → `rpc_success` (production permission-management path; sets `is_granted = false`). Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | `ERROR:  AI_ACCESS_DENIED` (SQLSTATE `P0001`). The `is_granted = true` filter excludes the revoked row; a soft-deleted permission row behaves identically via the `is_deleted = false` filter. Restore afterwards: `update_role_permission('doctor', 'ai.access', true)`. |
| Side effects | Only the setup writes (`roles_permissions.is_granted` + `audit_log` row `role_permission.update`). No issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L225-L238 — scopes aggregate filters` |

## Scenario S06-019 — Happy path: doctor mints a fully-populated AAT

| Field | Content |
|-------|---------|
| ID | S06-019 |
| Journey setup | Baseline B0, pristine ledger. Inject claims for DOC-AUTH. Pre-compute expectations: doctor staff id DOC, primary active branch BR-A, org ORG, doctor `ai.*` grants (`ai.access` only), active signing key K0 of installation I0. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | Returns `text`: a compact JWS `<b64url(header)>.<b64url(payload)>.<b64url(signature)>` — exactly three non-empty segments, no JSON envelope, no key material. Decoded header is exactly `{"alg":"EdDSA","kid":"<K0>"}` (two members, no more). Decoded payload has **exactly** these 11 claims: `iss = "<I0>"`; `aud = "ai-platform"`; `sub = "<DOC>"`; `org = "<ORG>"`; `branch = "<BR-A>"`; `role = "doctor"`; `scopes = ["ai.access"]`; `jti = <fresh UUID text>`; `iat = <unix seconds, ≈ now>`; `exp = iat + 600` (seed `ai.aat.lifetime_minutes = 10`); `ver = "1"`. `iat`/`exp` are JSON numbers. **Absent:** any patient identifier, `quota`, `provider`/`model`/`routing_tier` hint. The signature verifies against K0's public key (proven in S06-034). |
| Side effects | Exactly one new row in `ai_internal.ai_token_issuance`: `installation_id = I0`, `jti = <payload jti>`, `actor_staff_id = DOC`, `iat = to_timestamp(<payload iat>)`, `created_by = updated_by = DOC-AUTH`. **No** writes to `installation_keys`, `app_settings`, `audit_log`, or any `public.*` table (the issuer does not audit-log mints). |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L240-L292 — claim assembly, EdDSA sign, ledger insert` |

## Scenario S06-020 — Administrator mint carries both granted ai.* scopes, sorted

| Field | Content |
|-------|---------|
| ID | S06-020 |
| Journey setup | Baseline B0. Inject claims for ADM-AUTH. The seeded matrix plus migration `20260903180000` grant `administrator` both `ai.access` and `ai.visit_summary`. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | Compact JWS; payload `role = "administrator"`, `scopes = ["ai.access","ai.visit_summary"]` — the aggregate's `ORDER BY permission_key` guarantees deterministic alphabetical ordering. All other claims shaped as in S06-019 (`sub = ADM`, `branch = BR-A`, `org = ORG`, `iss = I0`, `kid = K0`, `exp − iat = 600`, `ver = "1"`). |
| Side effects | One `ai_token_issuance` row with `actor_staff_id = ADM`. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L225-L238 — jsonb_agg ORDER BY; backend/supabase/migrations/20260903180000_grant_ai_visit_summary_administrator.sql:L1-L7 — ai.visit_summary grant` |

## Scenario S06-021 — Caller-supplied p_scopes subset is ignored

| Field | Content |
|-------|---------|
| ID | S06-021 |
| Journey setup | Baseline B0. Inject claims for ADM-AUTH (role has `ai.access` + `ai.visit_summary`). |
| Action | `SELECT public.issue_ai_token(p_scopes := ARRAY['ai.access']);` |
| Expected outcome | Compact JWS whose `scopes` is still the full RBAC-derived `["ai.access","ai.visit_summary"]` — the parameter is never read inside the function body (declared at L115, referenced nowhere). Identical result for the NULL default `SELECT public.issue_ai_token();`. |
| Side effects | One issuance row for ADM. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L114-L115 — unused parameter declaration` |

## Scenario S06-022 — Caller-supplied scope the role lacks (or bogus scope) is ignored

| Field | Content |
|-------|---------|
| ID | S06-022 |
| Journey setup | Baseline B0. Inject claims for DOC-AUTH (doctor lacks `ai.visit_summary`). |
| Action | `SELECT public.issue_ai_token(p_scopes := ARRAY['ai.visit_summary', 'ai.forge']);` |
| Expected outcome | Compact JWS whose `scopes = ["ai.access"]` — no privilege escalation through the parameter; `ai.forge` appears nowhere in the token. |
| Side effects | One issuance row for DOC. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L225-L238 — scopes come only from roles_permissions` |

## Scenario S06-023 — Caller-supplied empty scope array is ignored

| Field | Content |
|-------|---------|
| ID | S06-023 |
| Journey setup | Baseline B0. Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token(p_scopes := ARRAY[]::text[]);` |
| Expected outcome | Compact JWS with `scopes = ["ai.access"]` — an empty array does **not** zero out the scopes and does **not** trip `AI_ACCESS_DENIED`; the gate evaluates the RBAC-derived array only. |
| Side effects | One issuance row for DOC. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L225-L238 — scopes aggregate and gate` |

## Scenario S06-024 — Branch claim is the primary active branch, not an arbitrary one

| Field | Content |
|-------|---------|
| ID | S06-024 |
| Journey setup | Baseline B0, plus as ADM create BR-B "North Branch" and assign DOC to it as non-primary (`public.create_staff_account`/`update_staff_member` path or direct insert as `postgres` of a `staff_branch_assignments` row `is_primary = false`). DOC now has BR-A (primary) and BR-B. Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | Payload `branch = "<BR-A>"` — selection is `ORDER BY sba.is_primary DESC, b.name LIMIT 1`. (Tie-break: with no primary flag on any assignment, the alphabetically first active branch name wins — "Main Branch" over "North Branch".) |
| Side effects | One issuance row for DOC. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L162-L175 — branch ordering` |

## Scenario S06-025 — Successive mints get unique jti with stable identity claims

| Field | Content |
|-------|---------|
| ID | S06-025 |
| Journey setup | S06-019 end state (one token J0 minted for DOC). Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | A second compact JWS: `jti` J1 ≠ J0 (fresh `gen_random_uuid()` per mint); `iss`, `kid`, `sub`, `org`, `branch`, `role`, `scopes` identical to J0; `iat` ≥ J0's. Re-minting is always allowed while under the rate ceiling. |
| Side effects | A second `ai_token_issuance` row (J1); the ledger's `UNIQUE (jti)` constraint holds with distinct values. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L240-L242 — jti generation; backend/supabase/migrations/20260801120000_ai_keystore_schema.sql:L122-L136 — ledger UNIQUE(jti)` |

## Scenario S06-026 — Missing app_settings rows fall back to built-in defaults

| Field | Content |
|-------|---------|
| ID | S06-026 |
| Journey setup | Baseline B0. As `postgres`: `DELETE FROM ai_internal.app_settings WHERE key IN ('ai.aat.lifetime_minutes','ai.aat.audience','ai.aat.ver','ai.issuer.rate_limit.ceiling','ai.issuer.rate_limit.window_seconds');` — [SEED]: no RPC manages these rows; simulates a lost-settings restore. Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | Compact JWS with `aud = "ai-platform"`, `ver = "1"`, `exp − iat = 600` — the `COALESCE(..., p_default)` in `ai_app_setting_*` supplies 10 / `ai-platform` / `1` / 100 / 3600. Same fallback when rows exist with `is_deleted = true`. Re-run the seed INSERT afterwards to restore. |
| Side effects | One issuance row for DOC. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L31-L71 — settings readers with defaults; backend/supabase/migrations/20260905120300_fix_aat_lifetime_fallback.sql — lifetime fallback 10 min (600 s platform ceiling); backend/supabase/migrations/20260801120000_ai_keystore_schema.sql:L38-L46 — seed values` |

## Scenario S06-027 — After additive rotation the new kid signs and old tokens still verify

| Field | Content |
|-------|---------|
| ID | S06-027 |
| Journey setup | Baseline B0 + S06-019 (token AAT0 under K0 saved). Stage 2 rotation, as BOOT: `SELECT public.rotate_installation_key();` → `rpc_success` with new `kid` K1, same `installation_id` I0 (additive: K0 row untouched, `revoked_at` still NULL). Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` then `SELECT auth_internal.verify_aat('<AAT0>');` as `postgres`. |
| Expected outcome | New token's header `kid = "<K1>"` — signing-key selection is `valid_from DESC, kid DESC LIMIT 1` among non-revoked rows, and rotation stamps `valid_from = clock_timestamp()`. Payload `iss` is still I0. `verify_aat(AAT0)` returns `true`: the previous key remains valid clinic-side until revoked (contract T05). |
| Side effects | One issuance row (new jti). The rotation itself added one `installation_keys` row; no key row was updated or removed. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L188-L199 — signing-key selection; backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L88-L172 — rotate_installation_key` |

## Scenario S06-028 — After revoking the old kid, minting continues on the new kid and old-kid tokens die

| Field | Content |
|-------|---------|
| ID | S06-028 |
| Journey setup | S06-027 end state (K0 and K1 present; AAT0 under K0 saved). As BOOT: `SELECT public.revoke_installation_key('<K0>');` → `rpc_success`. Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` then as `postgres`: `SELECT auth_internal.verify_aat('<AAT0>');` |
| Expected outcome | Mint succeeds; header `kid = "<K1>"` (K0 is excluded by `revoked_at IS NULL`). `verify_aat(AAT0)` returns `false` — a revoked kid fails verification regardless of `exp` (contract T06). Downstream, Stage 9 guard identity verification likewise rejects AAT0 as `unauthenticated` once the platform's key row shows `revoked_at`. |
| Side effects | One issuance row. Setup wrote `revoked_at`/`updated_at`/`updated_by` on K0 only. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L188-L199 — signing-key selection; L343-L353 — verify_aat revoked-kid rejection` |

## Scenario S06-029 — Re-enrollment after a zero-active-keystore recovers minting with the same installation id

| Field | Content |
|-------|---------|
| ID | S06-029 |
| Journey setup | S06-011 end state (only key K0 revoked; minting fails `INSTALLATION_NOT_ENROLLED`). Recovery path, as BOOT: `SELECT public.enroll_installation_keypair();` — **corrected (Register 4 item 1):** the `ALREADY_ENROLLED` guard exists (`20260902120000`, L19-L29) but fires only when an **active** key exists; from this zero-active state enroll succeeds and, because the installation lookup ignores `revoked_at`, the existing I0 is reused rather than a fresh uuid (matches S02-022). Alternatively, `rotate_installation_key` also recovers from the same state (S02-023) by minting a new active key under I0 without re-enrolling. |
| Action | Enroll (above), then inject claims for DOC-AUTH and `SELECT public.issue_ai_token();` |
| Expected outcome | Enroll returns `rpc_success` with a **new** kid K2 and `installation_id = "<I0>"` (unchanged). The subsequent mint succeeds: header `kid = "<K2>"`, payload `iss = "<I0>"` — platform-side continuity of the installation identity is preserved across the recovery. |
| Side effects | One new `installation_keys` row (K2, active); one issuance row. |
| Code reference | `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql:L4-L86 — enroll_installation_keypair (installation reuse at L20-L29)` |

## Scenario S06-030 — The ver claim comes from ai.aat.ver

| Field | Content |
|-------|---------|
| ID | S06-030 |
| Journey setup | Baseline B0. As `postgres`: `UPDATE ai_internal.app_settings SET value_json = '"2"'::jsonb WHERE key = 'ai.aat.ver';` (operator stages a contract-version bump). Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | Payload `ver = "2"` — the claim is `ai_app_setting_text('ai.aat.ver', '1')`, read fresh per mint. Nothing else in the token changes; the issuer stamps whatever the clinic config says and performs no version validation of its own. Restore `ver` to `"1"` afterwards. |
| Side effects | One issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L249-L261 — payload assembly (ver at L260)` |

## Scenario S06-031 — The aud claim comes from ai.aat.audience

| Field | Content |
|-------|---------|
| ID | S06-031 |
| Journey setup | Baseline B0. As `postgres`: `UPDATE ai_internal.app_settings SET value_json = '"clinic-portal"'::jsonb WHERE key = 'ai.aat.audience';` Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | Payload `aud = "clinic-portal"`. The issuer does not pin the audience; misconfiguration produces a perfectly signed token that every correctly configured platform verifier rejects (journey continued in S06-041). Restore audience to `"ai-platform"` afterwards. |
| Side effects | One issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L249-L261 — payload assembly (aud at L251)` |

## Scenario S06-032 — Lifetime boundary: exp − iat exactly 600 seconds

| Field | Content |
|-------|---------|
| ID | S06-032 |
| Journey setup | Baseline B0. As `postgres`: `UPDATE ai_internal.app_settings SET value_json = '10'::jsonb WHERE key = 'ai.aat.lifetime_minutes';` Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | Payload satisfies `exp − iat = 600` exactly (`iat + (10 * 60)`). The issuer itself imposes **no** cap — any positive `lifetime_minutes` mints. The boundary matters downstream: the platform verifier rejects only `exp − iat > 600` (`MAX_AAT_LIFETIME_SECONDS`), so a 600-second token is the largest the platform accepts; Stage 9 guard identity verification accepts this token's lifetime shape. Fractional values also work (`0.5` → 30 s). Restore lifetime to `10` afterwards. |
| Side effects | One issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L201-L201 — lifetime read; L242 — exp computation; ai-platform/src/identity/index.ts:L42 and L292-L294 — platform cap` |

## Scenario S06-033 — Non-numeric rate-ceiling setting fails with an uncoded cast error

| Field | Content |
|-------|---------|
| ID | S06-033 |
| Journey setup | Baseline B0. As `postgres`: `UPDATE ai_internal.app_settings SET value_json = '"abc"'::jsonb WHERE key = 'ai.issuer.rate_limit.ceiling';` — [SEED]: no RPC writes these settings, so no input validation ever guards them. Inject claims for DOC-AUTH. |
| Action | `SELECT public.issue_ai_token();` |
| Expected outcome | SQLSTATE `22023` `invalid input syntax for type numeric: "abc"` — the `value_json::numeric` cast in `ai_app_setting_numeric` throws **before** any coded gate. Not a contract error code; surfaces as a generic PostgREST 400. Restore the ceiling to `'100'` afterwards. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L31-L50 — ai_app_setting_numeric cast` |

## Scenario S06-034 — Clinic self-test verify_aat accepts a freshly minted token

| Field | Content |
|-------|---------|
| ID | S06-034 |
| Journey setup | S06-019 (AAT0 minted under K0). As `postgres` (the function is revoked from `authenticated`). |
| Action | `SELECT auth_internal.verify_aat('<AAT0>');` |
| Expected outcome | `true`. Three segments, `alg = "EdDSA"`, kid K0 found non-revoked, payload `iss` equals K0's `installation_id` (I0), and `pgsodium.crypto_sign_verify_detached` succeeds over `header_b64 || '.' || payload_b64` with K0's public key. This proves the issuer's signature is well-formed against the keystore. |
| Side effects | None (function is `STABLE`, read-only). |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L295-L385 — auth_internal.verify_aat` |

## Scenario S06-035 — verify_aat rejects a tampered payload

| Field | Content |
|-------|---------|
| ID | S06-035 |
| Journey setup | S06-019 (AAT0). Forge a variant: decode AAT0's payload, flip `role` to `"administrator"`, re-encode base64url, and re-join with AAT0's original header and signature segments (pure string surgery in SQL). |
| Action | `SELECT auth_internal.verify_aat('<forged>');` |
| Expected outcome | `false` — the Ed25519 signature no longer matches the altered signing input. Claim tampering is detectable without any database state change. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L370-L383 — signature verification` |

## Scenario S06-036 — verify_aat rejects malformed tokens without throwing

| Field | Content |
|-------|---------|
| ID | S06-036 |
| Journey setup | Baseline B0. As `postgres`. |
| Action | `SELECT auth_internal.verify_aat(NULL);` `SELECT auth_internal.verify_aat('');` `SELECT auth_internal.verify_aat('abc');` `SELECT auth_internal.verify_aat('a.b');` `SELECT auth_internal.verify_aat('a.b.c.d');` `SELECT auth_internal.verify_aat('!!!.@@@.###');` |
| Expected outcome | All return `false`, never an exception: NULL/empty short-circuit; segment count ≠ 3 or any empty segment → `false`; non-base64url/non-JSON header or payload hits the `EXCEPTION WHEN OTHERS THEN RETURN false` handlers. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L314-L337 — structural guards` |

## Scenario S06-037 — verify_aat rejects alg ≠ EdDSA or a missing kid

| Field | Content |
|-------|---------|
| ID | S06-037 |
| Journey setup | S06-019 (AAT0). Hand-build two tokens reusing AAT0's payload/signature segments with a re-encoded header: (a) `{"alg":"HS256","kid":"<K0>"}`, (b) `{"alg":"EdDSA"}` (no `kid`). |
| Action | `SELECT auth_internal.verify_aat('<token-a>');` `SELECT auth_internal.verify_aat('<token-b>');` |
| Expected outcome | Both `false` — the header gate requires `kid` non-null and `alg` exactly `EdDSA`; algorithm substitution (`none`, HMAC) is rejected before any key lookup. |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L339-L342 — alg/kid gate` |

## Scenario S06-038 — verify_aat rejects unknown, revoked, and soft-deleted kids

| Field | Content |
|-------|---------|
| ID | S06-038 |
| Journey setup | S06-028 end state (K0 revoked; AAT0 under K0 saved). Mint under K1 (signing continues on the rotated kid). Also hand-build a token whose header kid is a random uuid `f47ac10b-58cc-4372-a567-0e02b2c3d999` with AAT0's payload/signature. Then as `postgres`: `UPDATE ai_internal.installation_keys SET is_deleted = true, deleted_at = now() WHERE kid = '<K1>';` — [SEED]: no RPC soft-deletes keystore rows. |
| Action | `SELECT auth_internal.verify_aat('<AAT0>');` `SELECT auth_internal.verify_aat('<unknown-kid token>');` `SELECT auth_internal.verify_aat('<K1 token>');` |
| Expected outcome | All `false`: the key lookup requires a non-deleted `installation_keys` row with `revoked_at IS NULL` — unknown kid misses, revoked kid is filtered, and a soft-deleted K1 row is invisible (`is_deleted = false`), the same reject as an unknown kid. |
| Side effects | None beyond the setup mint and the setup soft-delete of K1. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L344-L353 — key lookup and revocation check` |

## Scenario S06-039 — verify_aat rejects an iss that does not match the key's installation

| Field | Content |
|-------|---------|
| ID | S06-039 |
| Journey setup | Baseline B0. As `postgres`, craft a token: header `{"alg":"EdDSA","kid":"<K0>"}`, payload identical to S06-019 but `iss = "f1000000-0000-4000-8000-000000000099"`, signed with K0's `secret_key` read from `ai_internal.installation_keys` via `pgsodium.crypto_sign_detached` — [SEED]: only `postgres` can read the secret key; this simulates an issuer bug or key misuse, not an outside attacker. |
| Action | `SELECT auth_internal.verify_aat('<crafted>');` |
| Expected outcome | `false` — payload `iss` must equal the key row's `installation_id` as text; a valid signature under K0 cannot launder a foreign installation id (contract T05d). |
| Side effects | None. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L364-L368 — iss binding` |

## Scenario S06-040 — verify_aat does not evaluate exp

| Field | Content |
|-------|---------|
| ID | S06-040 |
| Journey setup | Baseline B0 with `ai.aat.lifetime_minutes` set to a tiny value (`'0.01'` → 0.6 s, rounds to `exp = iat`). Mint as DOC-AUTH, then `SELECT pg_sleep(2);` so the token is unambiguously past `exp`. |
| Action | `SELECT auth_internal.verify_aat('<expired token>');` |
| Expected outcome | `true` — the clinic self-test deliberately skips expiry (code comment: "platform verifier (B3) enforces expiry"). The same token is rejected downstream: Stage 9 guard identity verification returns `unauthenticated` for `now > exp + clockSkewSeconds`. Expiry enforcement is exclusively platform-side. Restore lifetime to `10`. |
| Side effects | One issuance row from the setup mint. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L369-L369 — exp comment; ai-platform/src/identity/index.ts:L286-L291 — platform expiry check` |

## Scenario S06-041 — Minted-then-rejected: wrong audience

| Field | Content |
|-------|---------|
| ID | S06-041 |
| Journey setup | S06-031 end state (token minted with `aud = "clinic-portal"`; signature valid, installation I0 enrolled platform-side per Stage 3 enroll happy path). |
| Action | Present the token as `Authorization: Bearer` to the platform (Stage 8 ingress → Stage 9 guard identity verification, e.g. `GET /v1/capabilities`). |
| Expected outcome | Stage 9 rejects as `unauthenticated` (HTTP 401): `payload.aud !== ctx.audience` is a cheap pre-signature claim check. The clinic-side mint succeeded; only the handoff fails — a clinic misconfiguration of `ai.aat.audience` bricks every minted token. |
| Side effects | Platform-side: a guard-rejection metric in the `unverified` bucket (no installation attribution before signature verification). No clinic-side writes beyond the S06-031 issuance row. |
| Code reference | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:L251 — aud source; ai-platform/src/identity/index.ts:L282-L284 — audience check` |

## Scenario S06-042 — Minted-then-rejected: expired AAT

| Field | Content |
|-------|---------|
| ID | S06-042 |
| Journey setup | S06-040 end state (expired but well-formed token; I0/K0 enrolled platform-side). |
| Action | Present the token to the platform (Stage 9 guard identity verification). |
| Expected outcome | Stage 9 rejects as `unauthenticated`: `ctx.now > payload.exp + ctx.clockSkewSeconds`. Contrast S06-040 — clinic self-test still says `true`; expiry is enforced only downstream. Also rejected: a future-dated token with `iat − skew > now` (not producible by this issuer, which stamps `iat = now()`). |
| Side effects | Platform guard-rejection metric only. |
| Code reference | `ai-platform/src/identity/index.ts:L286-L291 — iat/exp window` |

## Scenario S06-043 — Default lifetime within platform cap: seed-default tokens are accepted

| Field | Content |
|-------|---------|
| ID | S06-043 |
| Journey setup | S06-019 end state (AAT0 minted with seed defaults: `exp − iat = 600`, unexpired; I0/K0 enrolled platform-side). Seed `ai.aat.lifetime_minutes = 10` (10 min → 600 s). |
| Action | Present AAT0 to the platform (Stage 9 guard identity verification). |
| Expected outcome | Stage 9 accepts the token's lifetime shape: `payload.exp − payload.iat = 600` equals `MAX_AAT_LIFETIME_SECONDS (600)` — the strict `>` check does not fire. Default-configured clinics mint platform-compatible tokens without tuning `ai.aat.lifetime_minutes`. Contrast S06-032 (explicit 10-minute setting reaches the same boundary). |
| Side effects | None beyond normal guard admission. |
| Code reference | `backend/supabase/migrations/20260905120000_fix_aat_lifetime_minutes_seed.sql — seed 10 min (600 s platform ceiling); ai-platform/src/identity/index.ts:L42, L292-L294 — lifetime cap` |

## Scenario S06-044 — Minted-then-rejected: kid unknown to the platform

| Field | Content |
|-------|---------|
| ID | S06-044 |
| Journey setup | S06-027 end state (clinic rotated to K1; token minted under K1 with `iss = I0`). Platform-side, only K0 was enrolled (Stage 3 enroll happy path) — the rotation's `public_jwk` handoff to the platform has not happened yet. |
| Action | Present the K1 token to the platform (Stage 9 guard identity verification). |
| Expected outcome | Stage 9 rejects as `unauthenticated`: the `keys` config lookup by header `kid` misses (`ConfigCacheMissError`). The token is perfectly signed clinic-side; the platform simply has no public key for K1 until the operator completes the rotation handoff. |
| Side effects | Platform guard-rejection metric only. |
| Code reference | `ai-platform/src/identity/index.ts:L307-L315 — key lookup by kid` |

## Scenario S06-045 — Minted-then-rejected: kid revoked platform-side

| Field | Content |
|-------|---------|
| ID | S06-045 |
| Journey setup | S06-019 end state (AAT0 under K0, unexpired, 600 s-compliant lifetime per S06-032 tuning). Platform-side, the operator has marked K0's key row `revoked_at` (platform key-management flow, mirroring clinic S06-028). |
| Action | Present AAT0 to the platform (Stage 9 guard identity verification). |
| Expected outcome | Stage 9 rejects as `unauthenticated`: `keyRow.revoked_at != null` short-circuits before signature verification — revocation trumps validity window and `exp`, matching clinic-side S06-038. |
| Side effects | Platform guard-rejection metric only. |
| Code reference | `ai-platform/src/identity/index.ts:L317-L319 — revoked key rejection` |

## Scenario S06-046 — Minted-then-rejected: ver unknown or retired platform-side

| Field | Content |
|-------|---------|
| ID | S06-046 |
| Journey setup | S06-030 end state (token minted with `ver = "2"`; signature valid, I0/K0 enrolled, 600 s-compliant lifetime). Platform `token_contracts` has no row for `"2"` (or a row with `retired_at` set). |
| Action | Present the token to the platform (Stage 9 guard identity verification). |
| Expected outcome | Stage 9 rejects as `unauthenticated`: the `token_contracts` lookup by `payload.ver` misses, or the row's `retired_at != null`. Note the ordering — this check runs **after** signature verification, so the rejection is attributed to installation I0, unlike the cheap pre-signature rejections. The issuer stamps whatever `ai.aat.ver` says (S06-030); a clinic that bumps `ver` before the platform supports it self-DoSes. |
| Side effects | Platform guard-rejection metric attributed to I0. |
| Code reference | `ai-platform/src/identity/index.ts:L363-L375 — token_contract lookup and retired check` |

## Scenario S06-047 — Minted-then-rejected: installation unknown to the platform

| Field | Content |
|-------|---------|
| ID | S06-047 |
| Journey setup | S06-019 end state (AAT0 minted; **no** Stage 3 enroll performed — the platform has never seen I0). |
| Action | Present AAT0 to the platform (Stage 9 guard identity verification). |
| Expected outcome | Stage 9 rejects as `unauthenticated`: the `installations` config lookup by `payload.iss` misses. Minting is purely clinic-side — it does not register the installation, write any platform state, or entitle anything; a valid signature is necessary but not sufficient. |
| Side effects | Platform guard-rejection metric in the `unverified` bucket (rejection precedes signature verification, so no I0 attribution). No platform rows created. |
| Code reference | `ai-platform/src/identity/index.ts:L296-L304 — installation lookup; L46-L48, L63-L69 — unverified bucket` |

## Doc-drift observations

1. **Contract specifies keypair guards — implemented, but only by the later guard migrations.** `aat-token.md` §8.2/§9.1 require
   `revoke_installation_key` to reject revoking the last active key with
   `CANNOT_REVOKE_LAST_ACTIVE_KEY`, and `enroll_installation_keypair` to return `ALREADY_ENROLLED`
   when an active key exists. Neither guard exists in the original `20260801120100` routines nor in the review-resolution
   re-apply `20260803140000` — but both were added afterwards by
   `20260902120000_enroll_installation_keypair_already_enrolled_guard.sql` (L19-L29) and
   `20260902130100_revoke_last_active_key_guard.sql` (L35-L45), which `CREATE OR REPLACE` the routines.
   **Correction (registers pass, Register 4 item 1):** an earlier version of this chapter claimed the guards
   do not exist at all; that claim predates/misses the 2026-09-02 migrations and is stale. Consequences for this
   chapter's scenarios: S06-011's setup as written (revoking the only key) is blocked by
   `CANNOT_REVOKE_LAST_ACTIVE_KEY` — the zero-active keystore must instead be reached by a `[SEED]` direct
   `UPDATE ... SET revoked_at` on the key row; and S06-029's recovery re-enroll is valid only from a
   zero-active keystore (with an active key present, enroll fails `ALREADY_ENROLLED` — matching S02-012/S02-022).
2. **~~Seed default and missing-settings fallback lifetime aligned with platform ceiling~~ — Fixed (C-03).** Migration
   `20260905120000_fix_aat_lifetime_minutes_seed.sql` sets `ai.aat.lifetime_minutes = 10`
   (→ `exp − iat = 600`), matching `MAX_AAT_LIFETIME_SECONDS`; migration
   `20260905120300_fix_aat_lifetime_fallback.sql` changes the issuer's missing-settings fallback from 15 to 10 minutes.
   Default-configured clinics and clinics with a lost settings row mint platform-compatible tokens (S06-026, S06-043).
   The contract (§4, T12) caps `exp − iat` at the configured lifetime; operators must still keep
   `lifetime_minutes ≤ 10` if they override the seed.
3. **~~Stage-6 doc §5 error table is incomplete~~ — Fixed (D-24).** Catalog §1.1 documents all seven contract codes including `UNAUTHENTICATED`, `SESSION_EXPIRED`, and `STAFF_NOT_FOUND` (scenarios S06-002…S06-004).
4. **~~Stage-6 doc calls the bootstrap admin "Owner"~~ — Fixed (D-24).** Catalog persona **BOOT** is `role = 'administrator'` with `is_bootstrap_admin = true` (the `owner` role was removed in `20260611150000`).
5. **~~Doc omits the branch tie-break~~ — Fixed (D-24).** Documented in §1.2 and S06-024: `ORDER BY sba.is_primary DESC, b.name` — alphabetical branch-name fallback when no assignment is primary.
6. **Defensive dead branches in the issuer (code reality, not doc).** The second
   `UNAUTHENTICATED` raise (claims without `sub`) is unreachable via JWT injection because
   `auth.uid()` derives from the same `sub` claim; the second `STAFF_NOT_FOUND` raise is
   unreachable absent a concurrent delete between `build_staff_claims` and the re-SELECT. Both are
   recorded here so no chapter invents a scenario for them.
7. **Consistent (no drift), worth pinning:** `p_scopes` is ignored exactly as contract §4/T08 says
   (S06-021–S06-023); `verify_aat`'s lack of an `exp` check matches contract §6.3 and the code
   comment (S06-040); issuer bare-exception surface matches contract §9.2.

## Non-automatable notes

- **Concurrent-mint serialization.** The `pg_advisory_xact_lock(87201401, hashtext(staff_id))`
  guarantee (two parallel sessions racing at `ceiling − 1` → exactly one succeeds) requires true
  concurrency and timing control; assert it in a load harness, not a scripted SQL catalog run.
- **jti collision.** A `gen_random_uuid()` collision would surface as SQLSTATE `23505` from the
  ledger's `UNIQUE (jti)` — not reproducible on demand and not a coded issuer error.
- **Platform half of S06-041–S06-047.** The minting half of every minted-then-rejected journey is
  executable from this repo (local Supabase + JWT injection). The rejection half requires the
  ai-platform Worker with D1 config rows (installations/keys/token_contracts) and belongs to the
  Stage 9 chapter's executable surface; these scenarios exist to pin the exact token variants that
  chapter must reject.
- **PostgREST status for `anon` (S06-001).** The SQL-level assertion (42501) is stable; the exact
  HTTP status (401 vs 403) depends on API-gateway configuration and is not pinned by migrations.
- **pgsodium randomness.** Keypairs, kids, and jtis are non-deterministic; all scenarios assert
  shapes, relationships, and decoded claim values relative to captured setup output — never fixed
  key material.
