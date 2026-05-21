# Supabase Advisor — Remediation Summary

**Source report:** [`supabase-warnings.md`](./supabase-warnings.md)
**Fix migrations:**

- `20260521100000_auth_rbac_supabase_linter_fixes.sql` — search_path, anon grants, RLS initplan, pg_graphql
- `20260521110000_auth_rbac_definer_internal_schema.sql` — lint **0029** (DEFINER in `public`)

**Also updated:** migrations `20260516100100`, `20260516100200`, `20260516100300` (greenfield installs)

Apply on an existing database:

```bash
cd backend && supabase db push
# or: supabase migration up
```

---

## 1. Function search path mutable (lint 0011)
| X                   | X                                                                                                                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Functions affected  | `jwt_*`, `request_jwt_claims`, `rpc_success`, `rpc_error`, `set_updated_at`, `set_audit_user`, `apply_standard_audit_triggers`                                                                                                                                      |
| **What it means**   | PostgreSQL resolves unqualified names using `search_path`. If `search_path` is not fixed on a function, a privileged caller (or attacker who can change `search_path`) could trick the function into resolving objects in the wrong schema (search-path hijacking). |
| **Fix**             | `SET search_path = public` (or `public, auth` where `auth.jwt()` is used) on every flagged function via `ALTER FUNCTION` / `CREATE OR REPLACE`.                                                                                                                     |
| **Risk if ignored** | Low on a locked-down Supabase instance, but Supabase flags it as a standard hardening requirement for `SECURITY DEFINER` and helper functions.                                                                                                                      |

---

## 2. Public GraphQL table exposure (lint 0026 / 0027)

| Lint | Role            | Tables                     |
| ---- | --------------- | -------------------------- |
| 0026 | `anon`          | All `public` tenant tables |
| 0027 | `authenticated` | Same tables                |

**What it means**
If a role has `SELECT` on a table, Supabase’s **pg_graphql** extension can expose that table in the GraphQL schema (`/graphql/v1`). That does not bypass RLS on REST, but it increases **API surface** (schema discovery, extra query path). Migration 3 had granted `SELECT` to `anon` on all `public` tables while RLS was enabled — anon still should not read clinic data before login.

**Fix**

1. **Removed** `GRANT SELECT … TO anon` from migration 3 (and `REVOKE` in migration 6 for existing DBs).
2. **Dropped** `pg_graphql` — AiClinic uses PostgREST REST + RPC only (Flutter SDK), not GraphQL.

**Remaining 0027 for authenticated**
If `pg_graphql` is re-enabled on hosted Supabase, authenticated users may still see table names in the GraphQL schema. **Row data remains protected by RLS** on REST; this is acceptable for our PostgREST-first design. To clear 0027 entirely without losing REST `SELECT`, disable `pg_graphql` in the dashboard or keep it dropped.

---

## 3. SECURITY DEFINER callable via API (lint 0028 / 0029)

| Category                   | Examples                                                                                                                                 |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Must **not** be public RPC | `assert_*`, `build_staff_claims`, `create_auth_user`, `organization_exists`, `owner_exists`, `set_audit_user`, `get_custom_claims(uuid)` |
| **Authenticated-only** RPC | `bootstrap_create_*`, `create_staff_account`, `admin_reset_staff_password`                                                               |
| **Auth hook only**         | `get_custom_claims(jsonb)` → `supabase_auth_admin`                                                                                       |
| **RLS helper**             | `current_staff_member_row()` → `authenticated` only (not `anon`)                                                                         |

**What it means**
`SECURITY DEFINER` functions run as the owner (typically superuser-like), so they **bypass RLS**. PostgREST exposes any function in `public` that has `EXECUTE` for the caller at `/rest/v1/rpc/<name>`. Default Postgres grants `EXECUTE` to `PUBLIC`, so **unauthenticated** callers could invoke sensitive RPCs (e.g. `create_staff_account`) before our fix.

**Fix**

- `REVOKE EXECUTE … FROM anon, authenticated, PUBLIC` on internal helpers.
- `REVOKE` from `anon` on staff admin RPCs; `GRANT` only to `authenticated`.
- `ALTER DEFAULT PRIVILEGES` so new functions are not auto-exposed to `anon` / `authenticated`.
- Re-`GRANT EXECUTE` on JWT helper functions to `authenticated` (required for RLS policy expressions after revoking from `PUBLIC`).

**0029 follow-up (migration 7)**
Privileged logic moved to schema `auth_internal` (not in `config.toml` `schemas`, so not exposed on `/rest/v1/rpc`). `public` keeps the same RPC names as thin **`SECURITY INVOKER`** wrappers the Flutter app calls; they delegate to `auth_internal.*` **`SECURITY DEFINER`** implementations. `current_staff_member_row()` is **`SECURITY INVOKER`** only (RLS applies; not a privilege-escalation RPC).

---

## 4. Auth RLS initialization plan (lint 0003) — performance

| Policies | `staff_members_select`, `staff_members_update`, `audit_log_select` |
| **What it means** | Bare `auth.uid()` in a policy is treated as a volatile per-row call. PostgreSQL re-evaluates it for **every row**, which slows large scans. |
| **Fix** | Use `(SELECT auth.uid())` so the value is computed once per statement (initplan). |
| **Risk if ignored** | Correctness unchanged; performance degrades as `staff_members` / `audit_log` grow. |

---

## Verification

After applying migrations 6 and 7:

1. Re-run **Security Advisor** and **Performance Advisor** in the Supabase dashboard.
2. Local smoke test:

   ```bash
   backend/tests/auth_flow_smoke.sh
   ```

3. Confirm login + `staff_members` / `roles_permissions` reads still work in the Flutter app (PostgREST `SELECT` with JWT).

---

## Checklist vs original report

| Issue group                         | Addressed                                            |
| ----------------------------------- | ---------------------------------------------------- |
| 0011 search_path (9 functions)      | Yes                                                  |
| 0026 anon GraphQL / SELECT          | Yes (revoke + drop graphql)                          |
| 0027 authenticated GraphQL          | Mitigated (drop graphql); REST `SELECT` kept for app |
| 0028 anon DEFINER execute           | Yes                                                  |
| 0029 authenticated DEFINER execute  | Yes (migration 7 — DEFINER only in `auth_internal`)  |
| 0003 auth_rls_initplan (3 policies) | Yes                                                  |
