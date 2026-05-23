# Quickstart: Patient Management

Implementation and verification for **V1-3**. Requires completed **V1-2** (`specs/003-org-branch-management`) and **V1-1** (`specs/002-auth-rbac`).

## 1. Apply database migrations

From repository root with local Supabase running (`backend/local`):

```bash
cd backend
supabase migration up
# or: supabase db reset
```

Expected new migration:

- `backend/supabase/migrations/20260523140000_patient_management.sql` — `patients` table, RLS, indexes, patient RPCs

Prior migrations: auth/RBAC (002), org/branch management (003).

## 2. Run backend verification

```bash
./backend/tests/run_patient_management_tests.sh
```

Or individual SQL:

```bash
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/patient_management_crud.sql
psql -h 127.0.0.1 -p "${SUPABASE_DB_PORT:-54322}" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f backend/tests/patient_management_rls.sql
```

**Scenarios** (maps to spec test cases):

- Register at active branch; list branch-scoped
- Name contains + phone prefix search; min length validation
- Org-wide scope finds cross-branch patient
- Edit patient at another registering branch
- Stale `updated_at` rejection
- National ID hard block; phone duplicate advisory
- Archive hides from list
- Cross-org denial
- `lab_staff` view-only

## 3. Run the Flutter client

```bash
cd frontend
flutter pub get
flutter run -d windows
```

1. Sign in as receptionist (or role with patient permissions)
2. Open **Patients** from shell navigation
3. Confirm default scope **This branch only**
4. Search by name (≥ 3 chars) and phone prefix (≥ 2 digits)
5. Toggle **All branches** — confirm registering branch column
6. **Register patient** — minimum full name; exercise duplicate warning
7. Open detail — notes + visits placeholder
8. **Edit** phone/notes — verify save
9. Second session edit same patient — confirm stale conflict (optional manual)
10. **Archive** with confirmation — patient leaves list
11. Sign in as `lab_staff` — list/detail only, no register/edit/archive

## 4. Regression checks (V1-1 / V1-2)

- Settings, branch switcher, and auth flows unchanged
- Permission matrix still seeds `patients.*` keys
- Bootstrap and staff provisioning unaffected

## 5. Automated Flutter tests

```bash
cd frontend
flutter test test/unit/patients/
flutter test test/widget/patients/
flutter test test/integration/patients/patient_management_acceptance_test.dart
```

## 6. Operator documentation

After implementation, link from `docs/architecture/12-roadmap-phases.md` V1-3 to this quickstart for desk staff training: scope toggle, duplicate warnings, archive is irreversible in UI.
