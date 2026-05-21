# Quickstart: Organization and Branch Management

Implementation and verification for **V1-2**. Requires completed **V1-1** (`specs/002-auth-rbac`).

## 1. Apply database migrations

From repository root with local Supabase running (`backend/local`):

```bash
cd backend
supabase migration up
# or: supabase db reset
```

Expected new migration (planned):

- `*_org_branch_management_functions.sql` — RPCs, branch code unique index
- Optional RLS/policy tweaks for `organizations` UPDATE and `roles_permissions` owner writes

## 2. Run backend verification

```bash
./backend/tests/run_org_branch_management_tests.sh
```

Or individual SQL (paths planned in implementation):

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_crud.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_rls.sql
```

**Scenarios**:

- Owner updates organization name/timezone
- `manage_create_branch` + deactivate non-last branch
- `LAST_ACTIVE_BRANCH` on sole active branch deactivate
- Staff create/update/deactivate lifecycle
- Owner toggles permission; RPC denies immediately; claims unchanged until reload
- Cross-org management denied

## 3. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

1. Sign in as owner or administrator after V1-1 bootstrap complete
2. Open **Settings** → Organization — edit name/currency/timezone, save
3. **Branches** — create second branch, edit, deactivate (not last), reactivate
4. Attempt deactivate last active branch — confirm block + edit shortcut
5. **Staff** — create receptionist with two branches; deactivate; reactivate
6. Sign in as receptionist — use **branch switcher** in shell status area
7. **Permissions** (owner) — revoke a grant; sign in as affected role after reload
8. **Permissions** (administrator) — view only, no save

## 4. Regression checks (V1-1)

- Bootstrap wizard still works on fresh install (`setup_required`)
- `create_staff_account` / `admin_reset_staff_password` from new staff screens
- Idle timeout and no session restore on app close unchanged
- Expired subscription cache does not block login

## 5. Test matrix reference

See `spec.md` → Test Cases 1–13 and Acceptance Criteria 1–13.

## 6. Key documents

| Doc          | Path                                         |
| ------------ | -------------------------------------------- |
| Spec         | `specs/003-org-branch-management/spec.md`    |
| Plan         | `specs/003-org-branch-management/plan.md`    |
| Contracts    | `specs/003-org-branch-management/contracts/` |
| Prerequisite | `specs/002-auth-rbac/quickstart.md`          |
