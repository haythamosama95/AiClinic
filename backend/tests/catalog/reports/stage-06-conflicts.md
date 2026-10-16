# Stage 06 catalog vs CODE conflicts

Catalog remains the journey spec. CODE (migrations) is authoritative for
assertions in the Stage 06 catalog SQL files. Tests follow CODE.

## 1. B0 usernames: dots → underscores

- Catalog B0 staff usernames: `nadia.h`, `lina.k`, `rami.s`.
- CODE `auth_internal.assert_valid_username` allows `[a-z0-9_-]` only
  (`backend/supabase/migrations/20260521190000_*`).
- Tests use `nadia_h` / `lina_k` / `rami_s` so `bootstrap_finish_setup` can
  succeed. Personas are still Nadia Haddad (doctor), Lina Khoury
  (administrator), Rami Saleh (receptionist), resolved by `full_name` +
  `role`, never by catalog alias UUIDs.
- Files: all three Stage 06 SQL files (B0 helpers).

## 2. Default AAT lifetime is 600 s, not 900 s

- Catalog S06-019 / S06-020 expected `exp − iat = 900` (seed 15 min). Catalog
  S06-032 / S06-040 still say restore lifetime to `15`.
- CODE seed is 10 min (`20260905120000_fix_aat_lifetime_minutes_seed.sql`) →
  **600 s**. Missing-settings fallback is also 10 min
  (`20260905120300_fix_aat_lifetime_fallback.sql`).
- Tests assert 600 s and restore the CODE seed `10`, not catalog `15`.
- Files: `stage-06-happy-path-and-lifecycle.sql` (S06-019/020/026/032),
  `stage-06-verify-and-handoff.sql` (S06-040/043 restore).

## 3. S06-019 side-effect fingerprints (full-row md5, no xmax)

- Catalog: mint writes **only** `ai_internal.ai_token_issuance`; no writes to
  `installation_keys`, `app_settings`, `audit_log`, or any `public.*` table.
- CODE issuer SELECTs keystore / staff / branch / RBAC rows and INSERTs the
  ledger with `iat = to_timestamp(payload iat)`. It does not UPDATE those
  tables.
- Fingerprints are full-row `md5(string_agg(r::text, E'\n' ORDER BY r::text))`
  over `(SELECT t.* FROM <table> t) r` for `installation_keys`,
  `app_settings`, and the five `public.*` tables the issuer reads
  (`staff_members`, `staff_branch_assignments`, `branches`, `organizations`,
  `roles_permissions`). `t.*` / `row::text` excludes system columns.
- Do **not** hash `xmax`: the ledger INSERT takes a KEY SHARE lock on the
  actor's `staff_members` row, which can move xmax without a business UPDATE.
- `audit_log` remains a row-count check (issuer does not audit-log mints).
- Ledger `iat` is asserted as `v_ledger.iat = to_timestamp(payload iat)`
  (CODE insert), not `extract(epoch)::bigint` equality (float epoch can
  off-by-one).
- File: `stage-06-happy-path-and-lifecycle.sql` S06-019.

## 4. S06-026 missing-settings fallback (repo vs applied function)

- Catalog originally expected 15 min (900 s) missing-settings fallback; C-03 /
  CODE `20260905120300_fix_aat_lifetime_fallback.sql` changes
  `ai_app_setting_numeric('ai.aat.lifetime_minutes', 10)` → **600 s**.
- The test asserts 600 s. Runner iteration 1 saw `delta=900` because local
  `schema_migrations` lacked `20260905120300`. The controller applied that
  repo migration to `127.0.0.1:54322` (file not modified) before runner 2.
- File: `stage-06-happy-path-and-lifecycle.sql` S06-026.

## 5. S06-033 uncoded cast SQLSTATE is 22023, not 22P02

- Catalog expected SQLSTATE `22P02` `invalid input syntax for type numeric:
  "abc"` from `value_json::numeric`.
- CODE stores the ceiling as jsonb string `'"abc"'`. Casting a jsonb string
  to numeric raises SQLSTATE **`22023`** `cannot cast jsonb string to type
  numeric` (not a text-to-numeric `22P02`).
- Test asserts `22023` and that message. No issuance row.
- File: `stage-06-verify-and-handoff.sql` S06-033.
