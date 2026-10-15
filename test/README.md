# Test campaigns

Root governor (live one-line status on stderr):

```bash
python3 test/run_campaigns.py --list          # full table + descriptions
python3 test/run_campaigns.py <area> --list # one area
python3 test/run_campaigns.py backend all
python3 test/run_campaigns.py frontend unit
```

Optional Rich live progress (same interpreter as above):

```bash
python3 -m pip install --user -r test/requirements.txt
```

Areas: `frontend`, `backend`, `ai-platform`, `abo`, `e2e-fullstack`, `vendor-contracts`, `ops-launch`.

Logs for a governor run live under `test-results/governor/<run_id>/`. Start with
`README.md` for the artifact index, `console.log` for the compact campaign status
ledger, `stats.json` for run totals, and `run.json` for the selected campaigns and
configuration. Each `<area>/<subcampaign>/` contains `summary.json` (commands,
per-test outcomes, timings, and links), `output.log` (complete merged stdout and
stderr, including setup and runner output), `stats.json`, and `tests/*.log` (parsed
test-specific output where boundaries are available). Logs are flushed as output
arrives and remain useful after a failure or interruption without rerunning tests.

Standalone area runs store `summary.json`, `output.log`, and per-test logs under
`test-results/<area>/<subcampaign>/<run_id>/`.

Shared helpers: `test/harness/common.py`.

## CI

GitHub Actions runs named campaign subcampaign jobs. Frontend runs `unit`, `boundary`, and `fullstack` separately; AI Platform runs `unit`, `workers`, `e2e`, and `version-matrix`; E2E Fullstack runs `p5-core`, `p5-2b`, `p7-2`, and `p7-3`. Backend, ABO, vendor-contracts, and ops-launch remain whole-area jobs.

Split jobs invoke one campaign directly:

```bash
python3 test/run_campaigns.py <area> <subcampaign>
```

Whole-area jobs use `--full-area <area>`.

Per-area setup on Linux CI:

```bash
bash .github/scripts/setup-campaign-area.sh <area> <subcampaign>
```

Frontend setup uses the subcampaign to install only its prerequisites: `unit` sets up Flutter without Supabase or npm packages, `boundary` adds Supabase, and `fullstack` installs the worker packages and starts Supabase. Omitting the subcampaign retains full-area setup.

Failed cases are listed in the job log, GitHub **Step summary**, and `::error` annotations via:

```bash
python3 test/report_campaign_ci.py --area <area> --run latest --github-summary
```

Download **campaign-&lt;area&gt;-&lt;subcampaign&gt;-&lt;run_id&gt;** artifacts for governor logs (`console.log`, per-test `tests/*.log`, `summary.json`, `stats.json`).

On CI (`CI` / `GITHUB_ACTIONS`), the Rich batch dashboard is disabled so logs stay readable; use `AICLINIC_PLAIN_CAMPAIGN_LOG=1` locally for the same behavior.

Full-machine setup (all areas on one runner):

```bash
bash .github/scripts/setup-test-campaign-environment.sh
python3 test/run_campaigns.py all
```
