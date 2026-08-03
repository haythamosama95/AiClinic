# Quickstart: Auth and RBAC

Implementation and verification flow for **V1-1: Auth and RBAC**. Requires completed **V1-0** (local Supabase stack + Flutter startup).

## 1. Apply database migrations

From repository root, with local stack running (`backend/local` — see [001 quickstart](../001-project-scaffolding/quickstart.md)):

```bash
cd backend
supabase db reset   # or: supabase migration up
```

Migrations (planned paths):

- `backend/supabase/migrations/*_auth_rbac_schema.sql`
- `*_auth_rbac_rls.sql`
- `*_auth_rbac_functions.sql`
- `*_auth_rbac_seed.sql`

Verify bootstrap admin exists (credentials from `backend/seed/bootstrap_admin.env.example` / setup docs).

## 2. Configure GoTrue custom claims hook

Ensure `backend/supabase/config.toml` (or local stack equivalent) registers the `get_custom_claims` hook pointing at the migration-defined function. Restart auth service after changes.

## 3. Run backend verification

```bash
./backend/tests/auth_flow_smoke.sh
./backend/tests/run_auth_backend_tests.sh
```

Or individual SQL files:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/rls_isolation.sql
```

Expected: sign-in succeeds; claims populated after setup; cross-organization reads denied.

## 4. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

1. Complete V1-0 startup (valid deployment profile + healthy backend)
2. Navigate to **Login**
3. Sign in as bootstrap administrator
4. Dismiss first-sign-in password warning (optional change later)
5. Complete **Clinic setup** (organization + first branch)
6. Create a receptionist (or other role) staff account
7. Sign out; sign in as new staff
8. Confirm placeholder shell shows role, branch, logout

## 5. Session policy checks

| Check               | Steps                                     | Expected              |
| ------------------- | ----------------------------------------- | --------------------- |
| App close           | Sign in → quit app → relaunch             | Login required        |
| Idle timeout        | Sign in → no input 15 min                 | Auto sign-out         |
| Forgot password     | Login → Forgot password                   | Contact admin message |
| Subscription expiry | Seed expired `subscription_cache` → login | Login still succeeds  |

## 6. Automated tests

```bash
cd frontend
flutter test test/unit/auth
flutter test test/widget/auth
flutter test test/integration/auth
```

## 7. Role matrix smoke test

Sign in as each seeded role (after provisioning test users) and confirm:

- Permission cache matches `data-model.md` matrix for sample keys
- Unauthorized demo action shows permission-denied message

## 8. Phase 11 acceptance notes (2026-05-21)

Automated verification for polish/cross-cutting tasks:

| Check                     | Command / artifact                                                                  | Expected                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Bootstrap admin docs      | [docs/setup/bootstrap-admin.md](../../docs/setup/bootstrap-admin.md)                | First-run credentials and flow documented                                |
| Subscription non-blocking | `backend/tests/subscription_cache_nonblocking.sql` (via `auth_flow_smoke.sh`)       | All `passed = t`; expired/missing cache does not strip `staff_member_id` |
| RPC contract alignment    | `backend/tests/rpc_contract_alignment.sql`                                          | Public RPC signatures match contracts                                    |
| JWT hook contract         | `backend/tests/jwt_claims_contract.sql`                                             | `staff_role` claim; no ambiguous `get_custom_claims(uuid)`               |
| Full backend suite        | `backend/tests/run_auth_backend_tests.sh`                                           | Exit 0                                                                   |
| Flutter auth tests        | `cd frontend && flutter test test/unit/auth test/widget/auth test/integration/auth` | All green                                                                |

Manual quickstart steps (§4–§5) still require a running local stack and interactive Flutter run; record pass/fail in your release checklist when cutting a build.

## References

- Spec: [spec.md](./spec.md)
- Contracts: [auth-session.md](./contracts/auth-session.md), [bootstrap-provisioning.md](./contracts/bootstrap-provisioning.md), [rbac-permissions.md](./contracts/rbac-permissions.md)
- Architecture: `docs/architecture/09-security-rbac.md`, `docs/architecture/05-database.md`
