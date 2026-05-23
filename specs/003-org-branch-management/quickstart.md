# Quickstart: Organization and Branch Management

Implementation and verification for **V1-2**. Requires completed **V1-1** (`specs/002-auth-rbac`).

## 1. Apply database migrations

From repository root with local Supabase running (`backend/local`):

```bash
cd backend
supabase migration up
# or: supabase db reset
```

Applied migrations:

- `backend/supabase/migrations/20260522100000_org_branch_management.sql` — RPCs, branch code partial unique index, `roles_permissions` SELECT policy
- Prior auth/RBAC migrations from `specs/002-auth-rbac` (schema, RLS, `build_staff_claims`, bootstrap RPCs)

## 2. Run backend verification

```bash
./backend/tests/run_org_branch_management_tests.sh
```

Or individual SQL:

```bash
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_crud.sql
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_rls.sql
```

JWT inactive-branch exclusion (Decision 5): included in `backend/tests/jwt_claims_contract.sql` via `build_staff_claims_excludes_inactive_branch`.

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

## 5. Automated Flutter acceptance (spec test cases 1–13)

```bash
cd frontend
flutter test test/integration/settings/org_branch_management_acceptance_test.dart
```

Covers organization/branch/staff routes, branch switcher, bootstrap visibility, FR-018a delete-label absence, and V1-1 redirect regression smoke. Cases 2 and 11 delegate to backend SQL suites above.

## 6. Operator documentation

- [docs/setup/clinic-administration.md](../../docs/setup/clinic-administration.md) — screen map and access rules
- [docs/setup/bootstrap-admin.md](../../docs/setup/bootstrap-admin.md) — first-run bootstrap (V1-1)

## 7. Test matrix reference

See `spec.md` → Test Cases 1–13 and Acceptance Criteria 1–13. FR-018a manual UI checklist: [checklists/fr-018a-ui-verification.md](./checklists/fr-018a-ui-verification.md).

## Verification gaps (documented 2026-05-23)

| Item                                                     | Status                       | Notes                                                                                        |
| -------------------------------------------------------- | ---------------------------- | -------------------------------------------------------------------------------------------- |
| Manual LAN timing (SC-001, NFR-005)                      | Not automated                | Use quickstart §3 on clinic hardware                                                         |
| Full V1-1 idle-timeout E2E                               | Partial                      | `session_lifecycle_test.dart` + manual table in `specs/002-auth-rbac/quickstart.md` §5       |
| Administrator permission matrix read-only (spec case 10) | UI allows administrator edit | Server allows administrator `update_role_permission`; align product if read-only is required |

## 8. Key documents

| Doc          | Path                                         |
| ------------ | -------------------------------------------- |
| Spec         | `specs/003-org-branch-management/spec.md`    |
| Plan         | `specs/003-org-branch-management/plan.md`    |
| Contracts    | `specs/003-org-branch-management/contracts/` |
| Prerequisite | `specs/002-auth-rbac/quickstart.md`          |
