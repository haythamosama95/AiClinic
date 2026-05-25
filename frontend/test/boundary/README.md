# Flutter ↔ Supabase boundary tests

Live integration tests for repository implementations against local Supabase (GoTrue + PostgREST + RLS + RPC). No UI, no mocks.

## Prerequisites

1. Start stack: `cd backend/local && docker compose up -d`
2. Apply migrations: `cd backend && supabase db reset` (or `supabase migration up`)
3. Copy `backend/local/.env` anon key into `frontend/deployment-profile.json` (see `deployment-profile.boundary.json.example`)
4. Restart auth after hook changes: `cd backend/local && docker compose restart auth`

## Run order (CI / pre-merge)

```bash
./backend/tests/run_all_backend_tests.sh
cd frontend && ./scripts/run_boundary_tests.sh
```

Subset runners:

```bash
./scripts/run_boundary_auth.sh
./scripts/run_boundary_settings.sh
./scripts/run_boundary_patients.sh
```

## Default unit/widget suite

`test-runner.py` and `flutter test` exclude the `boundary` tag. Boundary tests only run with:

```bash
AICLINIC_BOUNDARY_INTEGRATION=1 ./scripts/run_boundary_tests.sh
```

## Coverage manifest

[`boundary_coverage_manifest.md`](boundary_coverage_manifest.md) lists every scenario. `scripts/verify_boundary_manifest.sh` fails CI if a `owner=boundary` row has no matching `ManifestScenario` in tests.

## Remaining work (strict plan gap)

See [`BOUNDARY_REMAINING_WORK.md`](BOUNDARY_REMAINING_WORK.md) for everything not yet implemented (~90–170 scenarios vs the plan’s ~200–280 target), plus CI and live-run tasks.
