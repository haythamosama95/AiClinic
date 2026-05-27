# Boundary integration tests

Live Flutter ↔ Supabase tests (`@Tags(['boundary'])`). They require a running `backend/local` stack and valid credentials.

## Prerequisites

1. `cd backend/local && docker compose up -d`
2. Apply migrations (including dev-reset helpers used by the harness).
3. Copy `backend/local/.env` anon key into `frontend/config/local/deployment-profile.json` (see `config/examples/deployment-profile.boundary.json.example`).

## Run

```bash
cd frontend
./tool/run_boundary_tests.py
```

Subsets:

```bash
./tool/boundary/run_boundary_auth.sh
./tool/boundary/run_boundary_settings.sh
./tool/boundary/run_boundary_patients.sh
```

## Tags

`tool/run_unit_tests.py` and `flutter test` exclude the `boundary` tag. Boundary tests only run via the runner above (sets `AICLINIC_BOUNDARY_INTEGRATION=1`).

## Manifest

[`boundary_coverage_manifest.md`](boundary_coverage_manifest.md) lists every scenario. `tool/boundary/verify_boundary_manifest.sh` fails if a `owner=boundary` row has no matching `ManifestScenario` in tests.
