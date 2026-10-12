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

Logs: `test-results/<area>/<subcampaign>/<run_id>/tests/*.log` (one file per test case) and `summary.json` (run state; `meta.json` is a copy).

Shared helpers: `test/harness/common.py`.
