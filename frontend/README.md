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
python3 tool/run_campaigns.py --list
python3 tool/run_campaigns.py all          # unit then boundary (stack required for boundary)
python3 tool/run_campaigns.py unit
python3 tool/run_campaigns.py boundary     # live Supabase stack required
python3 tool/run_campaigns.py boundary-auth   # or boundary-settings, boundary-patients, …
./tool/run_all_tests.py         # legacy combined runner (campaigns/ layout)
./tool/run_unit_tests.py
./tool/run_boundary_tests.py
flutter analyze
```

Campaign orchestration logs live under `test-results/frontend/<subcampaign>/<run_id>/`
(`combined.log`, `meta.json`). Child runners also write Flutter machine artifacts
(`summary.json`, `failures.json`, …) under the passed `--campaign-dir` (e.g.
`<run_id>/unit` or `<run_id>/boundary`). The legacy `run_all_tests.py` path still
uses `test-results/campaigns/` and `test-results/latest/`.

Pass `--no-artifacts` on `run_unit_tests.py` / `run_boundary_tests.py` to skip suite file output.

## Configuration

See [config/README.md](config/README.md).
