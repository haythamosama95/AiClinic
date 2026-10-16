# Testing Architecture

- Purpose: Describe how backend SQL tests, Flutter tests, and CI fit together.
- Read this when: adding tests, debugging RPC/RLS failures, or extending CI.
- Canonical for: test layout, runners, harness conventions, and what CI enforces today.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/07-frontend.md`, `docs/architecture/12-roadmap-phases.md`.
- Not covered here: per-feature acceptance criteria (see feature specs).

---

## Overview

AiClinic uses a **backend-first verification** model aligned with spec-kit: PostgreSQL behavior is proven with SQL scripts against a live local Supabase stack before Flutter tests assert UI and client integration.

```
Feature spec acceptance criteria
        │
        ▼
Backend SQL tests (psql against local Docker Postgres)
        │
        ▼
Flutter unit / widget / integration tests
        │
        ▼
CI: flutter analyze + flutter test + windows build (backend tests NOT in CI yet)
```

> **Gap:** Backend SQL suites are manual/local or script-orchestrated, not run in CI. See `ARCHITECTURAL_FLAWS.md` → H3.

---

## Backend Testing

### Location

```
backend/tests/
├── run_all_backend_tests.sh       # Master orchestrator
├── run_auth_backend_tests.sh
├── run_org_branch_management_tests.sh
├── run_patient_management_tests.sh
├── run_appointment_management_tests.sh
├── run_visit_medical_records_tests.sh
├── run_billing_tests.sh
├── *_crud.sql                     # Happy-path RPC scenarios
├── *_rls.sql                      # Row-level security negative tests
├── *_concurrency.sql              # Race / overlap scenarios
└── ...
```

Migrations live in `backend/supabase/migrations/`. Seed data: `backend/supabase/seed.sql`.

### Prerequisites

1. Start the local stack:

```bash
cd backend/local && docker compose up -d
```

2. Ensure `.env` exists (copy from `.env.example`). Default DB port: `54322`.

3. Apply migrations via Supabase CLI or compose init (project uses Docker init + migration workflow per feature specs).

### Running Tests

```bash
# All suites
./backend/tests/run_all_backend_tests.sh

# Per domain
./backend/tests/run_billing_tests.sh
./backend/tests/run_visit_medical_records_tests.sh
```

Tests connect with `psql` to `127.0.0.1:${SUPABASE_DB_PORT:-54322}` as `postgres`.

### What Backend Tests Cover

| Domain | Example files | Focus |
| ------ | ------------- | ----- |
| Auth / RBAC | `auth_rbac_extended.sql`, `jwt_claims_contract.sql` | Claims, bootstrap, permission matrix |
| Org / branch | `org_branch_management_crud.sql`, `org_branch_management_rls.sql` | Branch CRUD, working schedule |
| Patients | `patient_management_crud.sql`, `patient_management_search_advanced.sql` | Search, duplicates, archive |
| Appointments | `appointment_management_crud.sql`, `appointment_queue_qa.sql` | Slot conflicts, status lifecycle |
| Visits | `visit_medical_records_crud.sql`, `visit_encounter_workspace_crud.sql` | Documentation, attachments, safety |
| Billing | `billing_crud.sql`, `billing_concurrency.sql` | Invoice lifecycle, payments, void |
| Shifts | `shift_management_crud.sql`, `shift_management_concurrency.sql` | Overlap detection |

### Backend Test Conventions

- Tests use `BEGIN; ... ROLLBACK;` or fixture helpers where isolation is needed.
- RPC assertions check `rpc_result.success`, `error_code`, and JSON `data` shape.
- RLS tests authenticate as different roles via JWT simulation helpers where provided.
- `dev_reset_clinic_installation()` and related dev RPCs support test teardown (bootstrap admin only).

---

## Frontend Testing

### Location

```
frontend/test/
├── unit/                    # Pure logic, providers, domain rules
├── widget/                  # Screen and component tests
├── integration/             # Multi-widget flows with harness
├── regression/              # Targeted regression guards
├── boundary/harness/        # Live Supabase harness (optional)
├── helpers/                 # Shared test support
└── support/                 # RPC test clients
```

### Conventions

| Layer | Directory | Examples |
| ----- | --------- | -------- |
| Unit | `test/unit/` | `encounter_step_provider_test.dart`, `bmi_test.dart` |
| Widget | `test/widget/` | `encounter_workspace_test.dart`, `appointment_calendar_page_test.dart` |
| Integration | `test/integration/` | Appointment queue with harness support |
| Regression | `test/regression/` | Queue behavior regression suite |

Visit encounter tests use shared support in `test/widget/visits/visit_encounter_test_support.dart`.

### Running Frontend Tests

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
```

### Boundary / Live Harness

`test/boundary/harness/live_supabase_harness.dart` and `sql_fixture_helper.dart` support tests that require a running local Supabase. Most CI tests use mocks/fakes; boundary tests are for local dev verification.

---

## Continuous Integration

File: `.github/workflows/ci.yml`

| Step | Command | Platform |
| ---- | ------- | -------- |
| Analyze | `flutter analyze` | `windows-latest` |
| Test | `flutter test --file-reporter=json:...` | `windows-latest` |
| Build | `flutter build windows --release` | `windows-latest` |

Triggers: push/PR to `main`, `master`, `001-*`, `feature/*`.

**Not in CI today:** backend SQL tests, Linux/macOS builds.

---

## Test Planning per Feature Phase

Per `11-spec-driven-development.md`, each feature spec should include:

1. **Backend test cases** — SQL scenarios mirroring RPC error codes in the spec.
2. **Frontend test cases** — widget tests for each UI state (empty, loading, error, permission-denied).
3. **Acceptance mapping** — numbered acceptance criteria → test file references.

When implementing encounter-scale features (e.g. spec 014), prefer:

- SQL tests for new RPCs and RLS first.
- Widget tests per phase/section for layout and interaction guards.
- Unit tests for client-derived logic (e.g. BMI, submit readiness) without Supabase.

---

## Related Documents

- `docs/architecture/ARCHITECTURAL_FLAWS.md` — CI gaps and test debt
- `docs/architecture/12-roadmap-phases.md` — per-phase deliverables including test utilities
- Feature quickstarts: e.g. `docs/specs/007-billing/quickstart.md`, `docs/specs/014-visit-encounter-workspace/quickstart.md`
