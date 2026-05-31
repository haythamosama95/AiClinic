# AiClinic frontend

Flutter desktop client for the clinic LAN deployment.

## Layout

| Path             | Purpose                                                |
| ---------------- | ------------------------------------------------------ |
| `lib/app/`       | App shell, router, cross-feature providers and widgets |
| `lib/core/`      | Shared infrastructure (config, auth guards, widgets)   |
| `lib/features/`  | Feature modules (`data` / `domain` / `presentation`)   |
| `test/helpers/`  | Test-only fakes and pump utilities                     |
| `test/boundary/` | Live Supabase integration tests (`boundary` tag)       |
| `tool/`          | Test runners and boundary scripts                      |
| `config/`        | Deployment profile examples and local config           |

## Tests

```bash
cd frontend
./tool/run_all_tests.py         # unit + boundary (boundary needs local stack)
./tool/run_unit_tests.py
./tool/run_boundary_tests.py    # live Supabase stack required
flutter analyze
```

Test campaigns write machine-readable artifacts under `test-results/latest/` (and
`test-results/campaigns/<timestamp>/`): `raw.jsonl`, `summary.json`, `failures.json`,
plus Markdown companions. Use these for triage without re-running tests. Pass
`--no-artifacts` to skip file output.

Boundary subsets: `./tool/boundary/run_boundary_auth.sh`, `run_boundary_settings.sh`, `run_boundary_patients.sh`.

## Configuration

See [config/README.md](config/README.md).
