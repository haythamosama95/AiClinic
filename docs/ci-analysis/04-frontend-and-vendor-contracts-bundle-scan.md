# Agent D — frontend (all + fullstack) and vendor-contracts bundle scan

Run 38695681551, HEAD 953e5e6e. Analysis only; no repo files changed.

## TL;DR

| Campaign | Verified root cause | Category | Fix |
|---|---|---|---|
| frontend/all, 12 FAIL (E2E-P6.3-01..07, E2E-P6.4-01..05) | `run_unit_tests.py` runs everything under `test/integration`, which includes the five `*fullstack*_test.dart` files. Nothing excludes them (no `--exclude-tags fullstack`). With no ABO on :8788 the tests `fail()` on purpose (P6.3-01, P6.4-*), or crash with `LateInitializationError: ctx` (P6.3-02..07). | Campaign routing bug | Remove fullstack files from unit discovery and add `--exclude-tags fullstack` (A1, A2). |
| frontend/all, hidden: exit 1 even after A1/A2 | The **boundary** step never ran: `ERROR: backend/local stack is not running.` (output.log line 24762). It checks `docker compose -f backend/local/docker-compose.yml ps`, but CI starts Supabase with `supabase start`. CI also never writes `frontend/config/local/deployment-profile.json`, and the frontend job installs no `psql`. | CI infra gap (has existed since CI was set up) | A3 (HTTP probe), A4 (write deployment profile), A5 (psql). |
| frontend/fullstack, exit 1, 0 tests | `ERROR: H-FS stack dependencies are missing. Run \`npm ci\` in e2e/fullstack/ before the frontend fullstack campaign.` (the whole output.log). `setup-campaign-area.sh` installs no npm dirs for `frontend`. | CI infra gap | A4 (npm ci in vendor-contracts, ai-platform, abo, e2e/fullstack). Plus A6: add `--machine`, set env, and run P7.3-06 outside the wrapper (port conflict). |
| vendor-contracts/all, E2E-P2.2-08 FAIL | **Nothing leaks testkit.** The bundle build fails: `wrangler deploy --dry-run` in `ai-platform/` gives `Could not resolve "vendor-contracts"` ×12, because `ai-platform/node_modules` is not installed in the vendor-contracts CI job. | CI infra gap (since 880472dd, not a 953e5e6e regression) | B1: add `ai-platform` to the vendor-contracts `npm_dirs`. |

---

## A. frontend

### A.0 How the frontend campaigns are wired (verified)

- `test/run_campaigns.py --full-area frontend` → `full_area_minimal_picks` → roots of `test/harness/campaign_tree.py`: `all` (children `unit` and `boundary`) and `fullstack` (its own root). So CI runs **frontend/all** and **frontend/fullstack**.
- `frontend/tool/run_campaigns.py:_run_all` (lines 177-219) runs a `run_subprocess_sequence` with two steps:
  - `unit` → `frontend/tool/run_unit_tests.py`. This calls `discover_tests.unit_test_files` = `UNIT_TEST_ROOTS = ("test/unit", "test/widget", "test/integration")` (`discover_tests.py:25,157-158`), then `flutter test <files> --machine` with no tag filter (`run_unit_tests.py:45-53`).
  - `boundary` → `frontend/tool/run_boundary_tests.py` (`flutter test test/boundary/** --tags boundary`).
- `_run_fullstack` (`run_campaigns.py:146-174`) runs `fullstack_test_files` = `test/integration/*fullstack*_test.dart` (`discover_tests.py:170-179`). The command is `flutter test … --tags fullstack`, wrapped by `node --import e2e/fullstack/node_modules/tsx/dist/loader.mjs e2e/fullstack/test/hfl-run-flutter.mjs -- …`. The guard at lines 166-172 returns 1 when the tsx loader is missing.
- The catalog states the intent (`test/harness/campaign_catalog.py:38-45`):
  - `unit`: "…integration flows that **do not require the full billing stack**."
  - `fullstack`: "End-to-end UI flows that call a running billing worker and platform worker…"
- The specs agree. `specs/091-…/plan.md:21` says "Harness H-FL on H-FS. One Dart file tagged `fullstack`", run with `--tags fullstack` against the running H-FS stack. **The quickstarts for P6.3, P6.4 and P7.3 all say the command "did not execute … because the H-FS stack was not running"**:
  - `specs/091-…/quickstart.md` §3
  - `specs/092-…/quickstart.md:36`
  - `specs/095-…/quickstart.md:86`

  So these Flutter fullstack tests have **never been run green** anywhere.

The five files tagged `fullstack`, all in `frontend/test/integration/`:

| File | Tests | Count |
|---|---|---|
| `administrator_billing_fullstack_test.dart` | E2E-P6.3-01..07 | 7 |
| `administrator_subscription_fullstack_test.dart` | E2E-P6.4-01..05 | 5 |
| `ai_status_fullstack_test.dart` | E2E-P6.1-01 | 1 |
| `contract_version_matrix_fullstack_test.dart` | E2E-P7.3-06 | 1 |

Total 14, which matches `frontend/fullstack/stats.json` `"total": 14`.

### A.1 frontend/all — the 12 failures (per test)

How the tests detect the stack: `setUpAll` probes `GET $ABO_URL/v1/offers` (default `http://127.0.0.1:8788`) with a 3 s timeout. `_hfsStackReady = status < 500` (`administrator_billing_fullstack_test.dart:92-97, 707-719`; same pattern in `administrator_subscription_fullstack_test.dart:75-80, 494`). `setUp` **returns early** without assigning `late BoundaryTestContext ctx` when the stack is down (`billing:99-107`, `subscription:82-88`). There is no tag skip or env skip. The tests deliberately `fail()`.

| Test | Decisive log line | Code |
|---|---|---|
| E2E-P6.3-01 | `H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack billing tests.` at `administrator_billing_fullstack_test.dart:112:9` (logged in `tests/002-e2e-p6-4-01-e2e-p6-4-01.log`; the governor mis-names the file, see A.7) | explicit `fail` at `billing:111-115` |
| E2E-P6.3-02..07 | `LateInitializationError: Local 'ctx' has not been initialized.` (`tests/003…` to `tests/008…`) | these tests have **no** `_hfsStackReady` guard and use `ctx` at `billing:196, 255, 299, 341, 385, 443` |
| E2E-P6.4-01..05 | `H-FS stack unavailable (ABO at http://127.0.0.1:8788). Start the H-FS stack before running fullstack subscription tests.` at `administrator_subscription_fullstack_test.dart:158:9` (P6.4-02; same at 93, 222, 276, 357) | explicit `fail` in each test |

The same unit step also had two **silent** setUpAll errors that the governor did not count as failures (`(setUpAll)` is a hook pseudo-test, which `live_progress.py:1455` ignores):

- `ai_status_fullstack_test.dart` setUpAll threw `Instance of 'Skip'` from `LiveSupabaseHarness._loadProfile` (`live_supabase_harness.dart:109`), with "Missing deployment profile at config/local/deployment-profile.json".
- `contract_version_matrix_fullstack_test.dart` setUpAll: `Bad state: Could not start the P7.3-06 desktop-window stack … Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'tsx' imported from …/e2e/fullstack/`. Its setUpAll spawns `node --import tsx test/p7-3-06-prepare.mjs` itself.

**Decision: option (1) — route fullstack-tagged files out of `unit`.** This matches the catalog, the spec ("tagged fullstack", run against a running H-FS stack), and the authors' explicit `fail()` design. Option (2), skipping when the stack is absent, would let `frontend/fullstack` go green vacuously, and the authors deliberately rejected that.

#### Edit A1 — `frontend/tool/discover_tests.py` (lines 157-158)

Before:
```python
def unit_test_files(cwd: Path) -> list[str]:
    return discover_test_files(cwd, *UNIT_TEST_ROOTS)
```
After:
```python
def unit_test_files(cwd: Path) -> list[str]:
    fullstack = set(fullstack_test_files(cwd))
    return [
        path
        for path in discover_test_files(cwd, *UNIT_TEST_ROOTS)
        if path not in fullstack
    ]
```
`fullstack_test_files` is defined later in the same module. That is fine because the name is resolved at call time. Both functions return POSIX paths relative to `frontend/` (`test/integration/<name>.dart`), so the set membership test matches.

#### Edit A2 — `frontend/tool/run_unit_tests.py` (lines 45-53), as belt-and-braces

Before:
```python
    cmd = apply_flutter_args(
        [
            "flutter",
            "test",
            *test_files,
            "--machine",
        ],
        config,
    )
```
After:
```python
    cmd = apply_flutter_args(
        [
            "flutter",
            "test",
            *test_files,
            "--machine",
            "--exclude-tags",
            "fullstack",
        ],
        config,
    )
```

Expected effect: frontend/all's unit step has 0 failures. That is 3540 PASS, plus anything that was previously masked. P6.3/P6.4/P6.1-01/P7.3-06 move entirely to frontend/fullstack.

### A.2 frontend/all — the boundary step never ran (keeps exit 1 even after A1/A2)

Evidence, from `frontend/all/output.log`:
```
24761: == boundary ==
24762: ERROR: backend/local stack is not running.
24763:   cd backend/local && docker compose up -d
```
Code: `run_boundary_tests.py:48-58` `ensure_stack_running()` runs `docker compose -f backend/local/docker-compose.yml ps --status running`. CI starts Supabase with `supabase start` in `backend/` (`setup-campaign-area.sh:68-72`), which creates `supabase_*` containers that this compose file does not own. So `ps` is empty and the script exits 1. Two more checks would fail right after:

- `ensure_deployment_profile()` (`run_boundary_tests.py:61-68`): `frontend/config/local/deployment-profile.json` is gitignored (`frontend/.gitignore:50`, root `.gitignore:54`), and CI never creates it.
- `boundary_force_db_reset()` (`run_boundary_tests.py:71-94`) shells out to `psql`. The frontend matrix entry has `postgresql_client: false` (`.github/workflows/ci.yml:26`).

The Flutter live tests also use `psql`: `SqlFixtureHelper` at `frontend/test/boundary/harness/sql_fixture_helper.dart:27`, and `_readStatusRefreshRequestedAt` in the billing test.

`run_subprocess_sequence(..., continue_on_step_failure=True)` still returns a non-zero overall exit, so **frontend/all stays exit 1 until this is fixed**. `run_boundary_tests.py` has not changed since `258670cc`/`3cf8f4b5`, so this is long-standing, not a regression.

#### Edit A3 — `frontend/tool/run_boundary_tests.py`: accept the Supabase CLI stack

Add these imports at the top (after `import sys`):
```python
import urllib.error
import urllib.request
```
Before (lines 48-58):
```python
def ensure_stack_running():
    result = subprocess.run(
        ["docker", "compose", "-f", str(COMPOSE_FILE), "ps", "--status", "running"],
```
After:
```python
def _supabase_http_ready() -> bool:
    url = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/") + "/rest/v1/"
    try:
        urllib.request.urlopen(url, timeout=3)
        return True
    except urllib.error.HTTPError as error:
        return error.code < 500
    except (urllib.error.URLError, OSError):
        return False


def ensure_stack_running():
    if _supabase_http_ready():
        return
    result = subprocess.run(
        ["docker", "compose", "-f", str(COMPOSE_FILE), "ps", "--status", "running"],
```
Leave the rest of the function unchanged. This mirrors `hfl-run-flutter.mjs:34-54`, which accepts 200/401/404 from `/rest/v1/`. Local docker-compose users are unaffected: the probe passes or falls back to the old check.

#### Edit A4 — `.github/scripts/setup-campaign-area.sh` (frontend case + profile)

Before (lines 29-32):
```bash
  frontend)
    need_supabase=1
    need_flutter=1
    ;;
```
After:
```bash
  frontend)
    need_supabase=1
    need_flutter=1
    npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)
    ;;
```
Then, after the `if [[ "${need_supabase}" -eq 1 ]]; then … fi` block (after line 72), before `echo "Campaign area ${area} ready."`:
```bash
if [[ "${area}" == "frontend" ]]; then
  profile_dir="${repo_root}/frontend/config/local"
  mkdir -p "${profile_dir}"
  anon_key="$(cd "${repo_root}/backend" && supabase status -o env | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')"
  if [[ -z "${anon_key}" ]]; then
    echo "ERROR: could not read ANON_KEY from supabase status" >&2
    exit 1
  fi
  printf '{\n  "deployment_mode": "local",\n  "supabase_url": "http://127.0.0.1:54321",\n  "supabase_anon_key": "%s"\n}\n' \
    "${anon_key}" > "${profile_dir}/deployment-profile.json"
fi
```
The profile shape comes from `frontend/config/examples/deployment-profile.example.json`. The API port 54321 comes from `backend/supabase/config.toml:10`.

#### Edit A5 — `.github/workflows/ci.yml`

- Frontend matrix entry (line 26): `postgresql_client: false` → `postgresql_client: true`.
- Line 82: `sudo apt-get install -y postgresql-client` → `sudo apt-get install -y postgresql-client sqlite3`. The P6.3-04 / P6.4 tests shell out to the `sqlite3` CLI against ABO D1 (`administrator_billing_fullstack_test.dart:840`, `administrator_subscription_fullstack_test.dart:786-810`). This is harmless for backend and e2e-fullstack, which already run this step.

### A.3 frontend/fullstack — exit 1, 0 tests

Its whole `output.log`:
```
ERROR: H-FS stack dependencies are missing. Run `npm ci` in e2e/fullstack/ before the frontend fullstack campaign.
```
This is from `frontend/tool/run_campaigns.py:166-172` (tsx loader missing), because `setup-campaign-area.sh:29-32` installs no npm dirs for `frontend`. Exit came after 0.25 s, and the stack was never attempted.

What the H-FS stack needs, once past that guard (from `hfl-run-flutter.mjs` → `p7-3-stack.mjs` → `wrangler-persist.mjs`):

| Need | Why | Installed by A4? |
|---|---|---|
| `e2e/fullstack/node_modules` (tsx, wrangler 4.86, @supabase/supabase-js, undici (transitive, hoisted, 7.24.8 in lockfile), `vendor-contracts` file: link) | the wrapper, `p7-3-stack.mjs` imports (lines 7-15), harness worker `e2e/fullstack/src/register-issuer.ts`, `p7-3-06-prepare.mjs` via `node --import tsx` | yes |
| `ai-platform/node_modules/vendor-contracts` | `startWorker({config: ai-platform/wrangler.toml})` bundles `ai-platform/src/*`, and esbuild resolves `vendor-contracts` from `ai-platform/`. e2e-fullstack shows exactly this failing: `Could not resolve "vendor-contracts"` at `src/admission/index.ts:14:33` (+11 more, same 12 files as B) | yes |
| `abo/node_modules/vendor-contracts` | `npx wrangler dev --config abo/wrangler.toml` bundles `abo/src/**`, which imports `vendor-contracts` (e.g. `abo/src/clinic-api/auth.ts`). In e2e-fullstack this is masked because the platform worker fails first | yes |
| `packages/vendor-contracts/node_modules` | the target of the file: links. It has no runtime deps (src has no bare imports), so this is just consistency with other areas | yes |
| Local Supabase on :54321/:54322, with a `signing` issuer key | `requireSupabaseReady`; `readIssuerKeyByStatus("signing")` (`p7-3-stack.mjs:859-862`). The migration `20261007180000_issuer_key_custody.sql:119` calls `insert_issuer_kid()` once, so a fresh DB has it | already (supabase start) |
| `psql`, `sqlite3` CLIs | `p7-3-06-prepare.mjs:runPsql`, Dart fixtures, `_bumpSellableOfferVersion` | A5 |
| `frontend/config/local/deployment-profile.json` | `LiveSupabaseHarness.ensureReady` → `_loadProfile` Skip (this is what killed P6.1-01 in the unit run) | A4 |

#### Edit A6 — `frontend/tool/run_campaigns.py` `_run_fullstack` (replace lines 146-174)

Three more defects show up once dependencies are present:

1. **No `--machine`.** `parser_for_command` → `FlutterMachineParser` only understands `--machine` JSON (`test/harness/live_progress.py:1428-1500, 1728`). Without it, even a successful run records 0 per-test results.
2. **P7.3-06 port and persist conflict.** `hfl-run-flutter.mjs` starts the stack once (ports 8787/8788/8789/8790, `e2e/fullstack/.wrangler/*`). It also refuses to start if those ports are taken (`rejectExistingWorkers`, lines 56-72). It holds them for the whole `flutter test` run. But `contract_version_matrix_fullstack_test.dart` setUpAll (`:53-71`, `:158-216`) spawns `p7-3-06-prepare.mjs`, which calls `startStack(...)` **again** on the same ports and persist dirs, with the desktop-window variant configs. Under the wrapper that will fail (EADDRINUSE / D1 persist clash). Both pieces arrived in the same commit, b68299b9 "Fix frontend fullstack test orchestration". This was never observed because the campaign has never got past the npm guard. Fix: run that file in a second step **without** the wrapper, after the wrapper has torn its stack down.
3. **Live-harness env vars are not set.** `run_boundary_tests.py:102-106` sets `AICLINIC_BOUNDARY_INTEGRATION=1` and `AICLINIC_DEPLOYMENT_PROFILE_PATH`. Without the first, `SupabaseBootstrap.ensureInitialized` uses the unit-test stub (`frontend/lib/core/config/supabase_config.dart:64,106-108`). Also reset stale ports and `.wrangler` the way the e2e-fullstack runner does (`e2e/fullstack/run_campaigns.py:45`).

Add near the top (after `import sys`):
```python
import os
```
Add after the `from harness.common import (…)` block:
```python
from harness.local_dev_ports import prepare_fullstack_e2e_stack  # noqa: E402
```
Add next to `BOUNDARY_RUNNER = …`:
```python
SELF_MANAGED_STACK_FILES = frozenset(
    {"test/integration/contract_version_matrix_fullstack_test.dart"}
)
```
Replace `_run_fullstack` with:
```python
def _run_fullstack(_subcampaign: str) -> int:
    run_id = resolve_governor_run_id()
    log_dir = resolve_campaign_log_dir(AREA, "fullstack", run_id)
    config = load_campaign_config(AREA, "fullstack")
    test_files = fullstack_test_files(FRONTEND_ROOT)
    if not test_files:
        print(
            "ERROR: no fullstack integration test files found under "
            f"{FULLSTACK_INTEGRATION_DIR}.",
            file=sys.stderr,
        )
        return 1
    stack_runner = FRONTEND_ROOT.parent / "e2e/fullstack/test/hfl-run-flutter.mjs"
    tsx_loader = (
        FRONTEND_ROOT.parent / "e2e/fullstack/node_modules/tsx/dist/loader.mjs"
    )
    if not tsx_loader.is_file():
        print(
            "ERROR: H-FS stack dependencies are missing. Run `npm ci` in "
            "e2e/fullstack/ before the frontend fullstack campaign.",
            file=sys.stderr,
        )
        return 1

    os.environ.setdefault("AICLINIC_BOUNDARY_INTEGRATION", "1")
    os.environ.setdefault(
        "AICLINIC_DEPLOYMENT_PROFILE_PATH", "config/local/deployment-profile.json"
    )
    prepare_fullstack_e2e_stack()

    def flutter_cmd(files: list[str]) -> list[str]:
        return apply_campaign_args(
            ["flutter", "test", *files, "--tags", "fullstack", "--machine"],
            config,
        )

    shared_stack = [f for f in test_files if f not in SELF_MANAGED_STACK_FILES]
    self_managed = [f for f in test_files if f in SELF_MANAGED_STACK_FILES]
    steps: list[tuple[str, list[str]]] = []
    if shared_stack:
        steps.append(
            (
                "hfs-shared-stack",
                [
                    "node",
                    "--import",
                    str(tsx_loader),
                    str(stack_runner),
                    "--",
                    *flutter_cmd(shared_stack),
                ],
            )
        )
    if self_managed:
        steps.append(("hfs-self-managed-stack", flutter_cmd(self_managed)))

    return run_subprocess_sequence(
        steps,
        FRONTEND_ROOT,
        log_dir,
        status_label=_status_label("fullstack"),
        campaign_config=config,
        config_area=AREA,
        continue_on_step_failure=True,
    )
```
`run_subprocess_sequence` and `apply_campaign_args` are already imported. `nested_subcampaign_config("frontend", "hfs-…")` returns None and falls back to `campaign_config` (`campaign_config.py:216-220`). `_run_all` already uses this exact sequence pattern with Flutter children.

#### Optional hardening — `administrator_billing_fullstack_test.dart` (P6.3-02..07)

Add the same guard P6.3-01 has as the first statement of each `testWidgets` body at lines 195, 254, 298, 340, 384, 441:
```dart
      if (!_hfsStackReady) {
        fail(
          'H-FS stack unavailable (ABO at $_aboUrl). Start the H-FS stack before running fullstack billing tests.',
        );
      }
```
This only changes the failure message, from `LateInitializationError` to an actionable one. It does not affect pass/fail.

### A.4 Cross-impact (frontend edits)

| Edit | Also touches | Checked | Risk |
|---|---|---|---|
| A1 `unit_test_files` | `run_unit_tests.py:203`; `test/harness/campaign_counts.py:176-191`; `test/harness/dynamic_test_counts.py:104-121` | The unit count drops by 14, which equals the fullstack count. No Python harness test asserts a frontend unit count (searched `unit_test_files` / `fullstack_test_files` in `*.py`). | Low. E2E-P6.1-01 moves to fullstack. In unit it was already silently errored (Skip), so nothing that passed is lost. |
| A2 `--exclude-tags fullstack` | unit step only | Only the five files above carry `@Tags(['fullstack'])`. | None |
| A3 boundary probe | boundary, boundary-* subcampaigns | Local compose users: the probe passes or falls back to the old check. | Low for the runner. **Medium for outcomes**: the boundary suite (≈959 tests, inferred as 4511 total − 3552 attempted) has never run in CI and may surface real failures on the Supabase CLI stack. |
| A4 setup script | frontend job only (`case` branch); `npm ci` is lockfile-based and already used for these dirs by the ai-platform, abo and e2e-fullstack jobs | Adds about 2-4 min to a 90-min-budget job that took about 15 min. | Low |
| A5 ci.yml | backend and e2e-fullstack also install sqlite3 | | None |
| A6 `_run_fullstack` | frontend/fullstack only; `prepare_fullstack_e2e_stack` wipes `e2e/fullstack/.wrangler` | Separate CI jobs mean no cross-job sharing. Locally, do not run frontend/fullstack concurrently with e2e-fullstack (true already). | Low for the runner. **High uncertainty for outcomes**: these 14 tests have never passed (see A.6). |

### A.5 Shared H-FS pieces (coordinate with the e2e-fullstack agent)

These are shared between frontend/fullstack and e2e-fullstack:

- `e2e/fullstack/test/p7-3-stack.mjs` (`startStack`; used by `hfl-run-flutter.mjs` with `{createClinics:false, registerIssuer:false}` and by `p7-3-06-prepare.mjs` with the desktop-window variants)
- `e2e/fullstack/test/wrangler-persist.mjs` (`preparePlatformD1`, `execPlatformD1Sql`, `runWranglerSync`)
- `e2e/fullstack/test/hfl-run-flutter.mjs`
- `e2e/fullstack/test/variant/*.toml`
- `test/harness/local_dev_ports.py`
- `.github/scripts/setup-campaign-area.sh`

What the frontend fullstack path needs from them:

1. **The same npm dirs as e2e-fullstack needs.** e2e-fullstack's current list (`packages/vendor-contracts e2e/fullstack`, line 44) is missing `ai-platform` and `abo`. That is exactly the `Could not resolve "vendor-contracts"` in `campaign-e2e-fullstack-…/all-ci/output.log:103-137`. The correct list for both areas is `packages/vendor-contracts ai-platform abo e2e/fullstack`.
2. **`preparePlatformD1` must apply all ai-platform migrations cleanly on a fresh `d1-seed` persist.** If the other agent's duplicate-column issue (`request_fingerprint`) breaks `wrangler d1 migrations apply`, the frontend stack fails at the same call (`p7-3-stack.mjs:795`). Any fix there applies to both. A6 wipes `.wrangler` first, so stale-persist duplicate columns from earlier runs are ruled out on the frontend side.
3. **`npx wrangler` is spawned with `cwd = REPO_ROOT`** (`wrangler-persist.mjs:35`, `p7-3-stack.mjs:222`). The repo root has no `package.json` or `node_modules`, so `npx` will not find the pinned wrangler 4.86 and will fetch `wrangler@latest` from the registry (CI auto-confirms). That brings version drift and a network dependency. I could not confirm this from logs (stderr is buffered). Suggested shared fix: spawn `node e2e/fullstack/node_modules/wrangler/bin/wrangler.js` instead of `npx wrangler`. This is optional, not required for green.

### A.6 What is still unknown or at risk (frontend)

- **The fullstack tests have never passed.** The P6.3, P6.4 and P7.3 quickstarts say so explicitly. After A4-A6 the campaign will actually boot the stack, and test-level failures are likely. Candidates:
  - the HMAC secret `paymob-hmac-unconfigured` must match ABO dev env
  - the `/notify/paymob` host routing
  - `ensureClinic`/seed SQL against the CLI DB
  - the `_bumpSellableOfferVersion` sqlite path `e2e/fullstack/.wrangler/abo/v3/d1/miniflare-D1DatabaseObject`
  - P7.3-06's 2-minute ready timeout on a cold runner

  Treat A4-A6 as "makes the campaign meaningful", not as a guaranteed green.
- **The boundary suite has also never run in CI.** A3-A5 enable it, and its pass rate on the Supabase CLI stack is unknown.
- If the team wants frontend CI green *now*, the only honest options are: land A1/A2 (fixes the 12) plus A3-A5, and accept that boundary/fullstack may then report real failures; or explicitly de-scope `frontend/fullstack` from `--full-area` CI and record that decision. Do not convert the `fail()`s into skips.

### A.7 Harness side-notes (not blocking)

- **Hook errors are misattributed.** `FlutterMachineParser._handle_event` (`live_progress.py:1484-1502`) attributes an `error` event from an ignored hook test (`(setUpAll)`) to `display.current` (whatever test is running), or drops it. That is why P6.3-01's log is in `tests/002-e2e-p6-4-01-…log`, and why the two setUpAll crashes were not counted.
- **Duplicated lines.** Every JSON line appears twice in `frontend/all/output.log` (an echo duplication). It is cosmetic.

### A.8 Confidence and CI confirmation

- A1/A2 fix the 12 P6.3/P6.4 failures: **high (95%)**. Confirm: `frontend/all/unit` has no `E2E-P6.*` or `E2E-P7.3-06` entries, and there are no `fullstack_test.dart` suite lines in `output.log`.
- A3-A5 make the boundary step run: **high** that it runs (no `ERROR: backend/local stack is not running.`). **Unknown** whether it passes.
- A4+A6 make frontend/fullstack boot: **medium-high** that the stack starts (assuming the shared migration issue is fixed). Confirm with `output.log` containing `== hfs-shared-stack ==`, followed by flutter machine JSON and 14 recorded tests. **Low-medium** that all 14 pass on the first try.

---

## B. vendor-contracts/all — E2E-P2.2-08

### B.1 Verified root cause

Test: `packages/vendor-contracts/test/bundle-scan.test.ts:49-76`. It:

1. checks that `package.json` `exports["./testkit"] === "./src/testkit/index.ts"`
2. runs `node packages/vendor-contracts/node_modules/wrangler/bin/wrangler.js deploy --dry-run --outdir <tmp> --env production` with `cwd = ai-platform/` (lines 56-72)
3. asserts the output does not contain `"vendor-contracts-testkit"`, which is `TESTKIT_MARKER` and is defined only in `packages/vendor-contracts/src/testkit/index.ts:1`

Decisive log, from `vendor-contracts/all/output.log:18-33` and `tests/012-test-bundle-scan-test-ts-production-bundle-scan.log`:
```
→ Command failed: …/packages/vendor-contracts/node_modules/wrangler/bin/wrangler.js deploy --dry-run --outdir /tmp/abo-p22-bundle-KcKHAZ --env production
✘ [ERROR] Build failed with 12 errors:
  ✘ [ERROR] Could not resolve "vendor-contracts"
      src/admission/index.ts:14:33:
        14 │ import { CHANNEL_VERSIONS } from "vendor-contracts";
```
The 12 unresolved import sites are all bare `"vendor-contracts"`:
`src/admission/index.ts`, `src/alert/index.ts`, `src/coverage-read/index.ts`, `src/coverage/transfer.ts`, `src/credit/index.ts`, `src/pipeline/index.ts`, `src/quota-do/coverage.ts`, `src/quota-do/index.ts`, `src/support/index.ts`, `src/vendor/contract-version.ts`, `src/vendor/entrypoint.ts`, `src/worker.ts`.

So **the test fails at `execFileSync` (step 2) and never reaches the marker assertion.** `ai-platform/package.json` declares `"vendor-contracts": "file:../packages/vendor-contracts"`. esbuild resolves it through `ai-platform/node_modules/vendor-contracts`, which only exists after `npm ci` in `ai-platform/`. `setup-campaign-area.sh:46-48` installs only `packages/vendor-contracts` for this area. That line has been unchanged since 880472dd (2026-10-12). Developer machines have `ai-platform/node_modules`, which is why the test passes locally.

### B.2 Suspects ruled out (testkit leak, 953e5e6e / 771ceed7)

- `rg testkit ai-platform/src` finds no matches. `rg 'from ".*(test|testkit|harness|stub)' ai-platform/src` finds no matches.
- 953e5e6e touched `src/rollup/index.ts`, `src/vendor/entrypoint.ts` and `src/worker.ts`. It only adds `import { clockNowMs } from "../clock"` / `"./clock"` and calls to it. `ai-platform/src/clock.ts` is production code from P3.1/P3.2 (2e06880f, e27b60a1). It reads `env.TEST_CLOCK` and `harness_test_clock`, and has no imports at all. The send-email stub lives in `ai-platform/test/stub-send-email-binding.ts` and is only wired through vitest configs, not `src`.
- 771ceed7 adds no imports to `worker.ts`.
- The `vendor-contracts` root (`src/index.ts`) only re-exports local `./*.js` modules. No file in `src/` outside `testkit/` imports testkit, and `src/` has no bare (external) imports.

Therefore, once the bundle builds, the marker check will pass.

### B.3 Fix

#### Edit B1 — `.github/scripts/setup-campaign-area.sh` (lines 46-48)

Before:
```bash
  vendor-contracts)
    npm_dirs+=(packages/vendor-contracts)
    ;;
```
After:
```bash
  vendor-contracts)
    npm_dirs+=(packages/vendor-contracts ai-platform)
    ;;
```
This is the same pair the `ai-platform` area already installs (line 37), and its lockfile is proven to `npm ci` cleanly in this very run. The order matters a little: install `packages/vendor-contracts` first so the file: link target is ready, which the list above already does.

Rejected alternatives:
- an `alias` in `ai-platform/wrangler.toml` (changes the production build config)
- `--alias` in the test (the test would then no longer scan the real production resolution path)

### B.4 Cross-impact

- `setup-campaign-area.sh` `case` branches are per-area. Only the vendor-contracts job changes, adding about 1 min of `npm ci`.
- vendor-contracts `node` and `workers` subcampaigns (`packages/vendor-contracts/campaigns/*.json`, `vitest.config.ts`, `vitest.workers.config.ts`) don't read `ai-platform/node_modules`. No change.
- The ai-platform tests that depend on the clock code checked here (rollup/retention/support-lookup via `clockNowMs`) are not touched by B1. B1 changes no source, so currently-passing ai-platform, abo, eval and version-matrix campaigns are unaffected.
- Shared lesson with A.5: **every job that bundles `ai-platform/src` or `abo/src` with wrangler needs that package's own `node_modules`.**
  - Already correct: ai-platform and abo jobs.
  - Fix needed: vendor-contracts (B1), frontend (A4), e2e-fullstack (other agent).

### B.5 Confidence and CI confirmation

**High (95%).** Confirm: the `vendor-contracts/all` setup log shows `npm ci in ai-platform`, and E2E-P2.2-08 passes in about 2-5 s, with no `Could not resolve` in `output.log`. The residual risk is that wrangler's production dry-run hits a different, previously masked bundling error. That is unlikely: esbuild reports all resolve errors in one pass, and only `vendor-contracts` was unresolved.

---

## FOLLOW-UP: full frontend wiring

Decision implemented here: wire **both** the boundary step (inside `frontend/all`) and `frontend/fullstack` in CI, with nothing excluded. Analysis only. Nothing below has been executed, because vitest, flutter, wrangler and supabase cannot run here.

### F.0 TL;DR and what changes versus section A

Section A's edits A1–A6 stay, with revisions. The investigation found **four new blockers** that would have made the first CI run fail even with A1–A6 applied:

| # | New blocker | Where | Effect if not fixed | Fix |
|---|---|---|---|---|
| N1 | GoTrue `sign_in_sign_ups = 30` per 5 min per IP on the Supabase CLI stack | `backend/supabase/config.toml:203` | Boundary and fullstack fixtures sign in hundreds of times from 127.0.0.1. HTTP 429 `over_request_rate_limit` starts within the first minute and cascades through the boundary suite. Compose (`backend/local`) sets no GoTrue rate-limit env, which is why this never showed locally. | F4 |
| N2 | `p7-3-06-prepare.mjs` calls `startStack()` with the default `createClinics: true`, which runs `createTwoOrgClinics()` | `p7-3-06-prepare.mjs:154-157`, `p7-3-stack.mjs:887` | `auth_internal.bootstrap_create_organization` returns `ORG_ALREADY_EXISTS` whenever any non-deleted org exists (`20261009120000_fix_staff_membership_session_rls.sql`, guard via `auth_internal.organization_exists()`, `20260521110000_…:130-141`). The orgB call **always** fails, so prepare exits 1 and the P7.3-06 setUpAll fails. | F8 |
| N3 | No ABO offers are seeded for the frontend path | `hfl-run-flutter.mjs:228` starts the stack but never calls `seedAboOffers()`; `abo/migrations/*.sql` insert no offers | The P6.3 offers screen is empty. `_readCurrentSellablePriceMinor` (`expect(offers, isNotEmpty)`) and every purchase flow fail. | F9 |
| N4 | Platform grant prerequisites are missing: global `service_key` (ABO grant kid) and `plan_version`, plus a per-org `tenant_binding` | `ai-platform/src/vendor/entrypoint.ts:362, 540, 552` (`readActiveTenantBinding(orgId)`); `abo/src/clinic-api/checkouts.ts:792-816` returns `"Active"` only if `grant_outcome.result ∈ {applied, already_applied}` | P6.3-01, P6.3-02 and P6.3-05 time out in `_pumpUntilCheckoutShownState('Active')` after 30 s. | F9 (globals) + F10 (per org) |

There are also two **silent-green traps** to close:
- `LiveSupabaseHarness` turns every misconfiguration into `throw Skip(...)` (`live_supabase_harness.dart:42-117`).
- `FlutterMachineParser` counts `testDone{result:"success", skipped:true}` as PASS.

A broken CI stack would therefore show the boundary suite as "passed". F5/F6 fix this by making the harness fail loudly in CI.

Corrections to section A that matter for the decisions below:
- The boundary suite is **≈170 tests in 17 files** (151 static declarations plus 4 enum loops; manifest says 172), not ≈959.
- frontend/fullstack is **4 files / 14 tests** (`administrator_billing` 7, `administrator_subscription` 5, `ai_status` 1, `contract_version_matrix` 1), not five files.

### F.1 Boundary step (`frontend/all` → `== boundary ==`)

#### F.1.1 History

`run_boundary_tests.py` has not changed since `258670cc`/`3cf8f4b5`, and every CI run of `frontend/all` has stopped at `ERROR: backend/local stack is not running.`. `frontend/test/boundary/BOUNDARY_REMAINING_WORK.md` says *"Live green run on CI/local stack: Not verified"*, with INF-1/2/3/6 open. **There is no commit at which the boundary step last passed in CI. It has never run there.** Local runs used `backend/local` docker compose (`frontend/test/boundary/README.md`).

#### F.1.2 Supabase CLI stack (CI) versus `backend/local` compose (where the tests were written)

| Aspect | compose (`backend/local`) | CLI (`supabase start` in `backend/`) | Impact on boundary/fullstack | Pre-emptive fix |
|---|---|---|---|---|
| Ports | Kong `54321`, PG `54322` (`.env.example`) | `[api] 54321`, `[db] 54322` (`config.toml`) | Same; `sql_fixture_helper.dart` `-h 127.0.0.1 -p 54322 -U postgres` works | none |
| PG password | `postgres` | `postgres` | `PGPASSWORD` defaults to `postgres` in Dart helpers | none |
| JWT secret / anon key | `your-super-secret-jwt-token-with-at-least-32-characters-long` + its demo keys | CLI default secret + CLI demo anon key | Profile anon key **must** be the CLI's | F2 (from `supabase status -o env`) |
| GoTrue rate limits | none set (effectively unlimited) | `sign_in_sign_ups=30`, `token_refresh=150`, `token_verifications=30` per 5 min per IP | **Blocker N1** | F4 |
| Custom access token hook | `GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_URI=pg-functions://postgres/public/get_custom_claims` | `[auth.hook.custom_access_token] enabled` (same function) | `_assertStaffClaimsAfterBootstrapSignIn` checks `staff_member_id`; CLI path is the one e2e-fullstack also relies on | none (verify on first run) |
| Email confirmation | off | `[auth.email] enable_confirmations=false` | `create_staff_account` users can sign in | none |
| PostgREST pre-request | `PGRST_DB_PRE_REQUEST=public.local_dev_pre_request`, connects as `postgres` | connects as `authenticator`, no pre-request | Handled by the harness: `SqlFixtureHelper.ensureLocalDevelopmentEnvironment()` creates the function, `ALTER ROLE authenticator SET pgrst.db_pre_request`, `NOTIFY pgrst` | none |
| Roles/schemas | `init.sql` creates anon/authenticated/service_role, auth, storage | built into CLI image | Same `supabase/postgres` 15.x family; migrations are written for the CLI anyway (backend campaign) | none |
| Seed | migrations only via init | `[db.seed] sql_paths=["./seed.sql"]`, applied by `supabase start` on a fresh DB | `admin/admin` bootstrap user comes from seed + migrations, same as backend and e2e-fullstack rely on | none |
| Refresh-token rotation | GoTrue defaults | `enable_refresh_token_rotation=true`, `refresh_token_reuse_interval=10` | Low: tests call `refreshSession()` sequentially, not concurrently | none |
| Storage / edge functions / realtime | partly absent in compose | enabled | Boundary tests don't use edge functions; extra services only add start time | none |
| Service-role key | not used by the frontend harness | | `rg service_role frontend/test/boundary/harness` finds only SQL role names, and fixtures use psql as `postgres` | none |

**`supabase db reset` is not needed.** `setup-campaign-area.sh` runs `supabase start` on a fresh runner, which applies all migrations and `seed.sql`. `run_boundary_tests.boundary_force_db_reset()` (psql, at start and atexit) handles intra-run hygiene.

**Env vars:** `SUPABASE_URL` and `POSTGRES_PASSWORD` defaults (`http://127.0.0.1:54321`, `postgres`) match the CLI. Only the profile file is required.

#### Edit F1 (= A3, unchanged) — `frontend/tool/run_boundary_tests.py` HTTP probe

Apply A3 exactly as written in section A.

#### Edit F2 (supersedes A4's profile block) — `.github/scripts/setup-campaign-area.sh`

The frontend `case` change is unchanged from A4:
```bash
  frontend)
    need_supabase=1
    need_flutter=1
    npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)
    ;;
```
Then add the profile generator **after** the `if [[ "${need_supabase}" -eq 1 ]]; then … fi` block and **before** `echo "Campaign area ${area} ready."`. This version falls back to the CLI's well-known demo anon key, which is identical for every `supabase start` that uses the default JWT secret:
```bash
if [[ "${area}" == "frontend" ]]; then
  profile_dir="${repo_root}/frontend/config/local"
  mkdir -p "${profile_dir}"
  status_env="$(cd "${repo_root}/backend" && supabase status -o env 2>/dev/null || true)"
  anon_key="$(printf '%s\n' "${status_env}" | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p' | head -n 1)"
  api_url="$(printf '%s\n' "${status_env}" | sed -n 's/^API_URL="\(.*\)"$/\1/p' | head -n 1)"
  if [[ -z "${anon_key}" ]]; then
    echo "WARN: ANON_KEY not found in 'supabase status -o env'; using CLI demo anon key" >&2
    anon_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
  fi
  api_url="${api_url:-http://127.0.0.1:54321}"
  printf '{\n  "deployment_mode": "local",\n  "supabase_url": "%s",\n  "supabase_anon_key": "%s"\n}\n' \
    "${api_url}" "${anon_key}" > "${profile_dir}/deployment-profile.json"
  echo "Wrote ${profile_dir}/deployment-profile.json (supabase_url=${api_url})"
fi
```
Notes:
- `API_URL` from `supabase status` is `http://127.0.0.1:54321`.
- `DeploymentProfile.isLocalOnly` must accept a loopback URL with `deployment_mode: "local"`. That is the shape of `frontend/config/examples/deployment-profile.example.json`.
- If the CLI starts printing `PUBLISHABLE_KEY` instead of `ANON_KEY` (newer CLI versions print both), the fallback still yields a valid legacy anon JWT for the default secret.

#### Edit F3 (= A5, unchanged) — `.github/workflows/ci.yml`

- Line 26 (frontend matrix entry): `postgresql_client: false` → `postgresql_client: true`.
- Line 82: `run: sudo apt-get update && sudo apt-get install -y postgresql-client` → `run: sudo apt-get update && sudo apt-get install -y postgresql-client sqlite3`.
- Line 23: `timeout_minutes: 90` → `timeout_minutes: 120`. See F.4.

#### Edit F4 (NEW, mandatory) — `backend/supabase/config.toml` `[auth.rate_limit]` (lines 193-207)

Before:
```toml
# Number of sessions that can be refreshed in a 5 minute interval per IP address.
token_refresh = 150
# Number of sign up and sign-in requests that can be made in a 5 minute interval per IP address (excludes anonymous users).
sign_in_sign_ups = 30
# Number of OTP / Magic link verifications that can be made in a 5 minute interval per IP address.
token_verifications = 30
```
After:
```toml
# Number of sessions that can be refreshed in a 5 minute interval per IP address.
token_refresh = 100000
# Number of sign up and sign-in requests that can be made in a 5 minute interval per IP address (excludes anonymous users).
sign_in_sign_ups = 100000
# Number of OTP / Magic link verifications that can be made in a 5 minute interval per IP address.
token_verifications = 100000
```
Why: the boundary harness signs in as `admin` and as role users on almost every test. `BoundaryTestContext` reset, `FixtureFactory.bootstrapOnly`, `RoleSessions.signInAs` and `boundaryRefreshSessionForClinic` give about 214 sign-in call sites, and each test hits several, all from 127.0.0.1. At concurrency 1 that is far more than 30 per 5 minutes.

Safety:
- This file configures **local CLI only**. Hosted projects ignore it.
- No test anywhere asserts GoTrue 429. The `429` assertions in `p7-2-untrusted-callers.test.mjs:116,134` are worker-level, and `ai.issuer.rate_limit.*` in `backend/tests/catalog/stage-06-*.sql` is an SQL setting.
- It helps backend and e2e-fullstack too, both of which sign in repeatedly.

#### Edit F5 (NEW) — `frontend/test/boundary/harness/live_supabase_harness.dart:116-118` (fail instead of skip in CI)

Before:
```dart
void markTestSkipped(String message) {
  throw Skip(message);
}
```
After:
```dart
void markTestSkipped(String message) {
  if (Platform.environment['AICLINIC_BOUNDARY_REQUIRE_LIVE'] == '1') {
    throw StateError('Live Supabase stack required (AICLINIC_BOUNDARY_REQUIRE_LIVE=1): $message');
  }
  throw Skip(message);
}
```
`dart:io` is already imported (line 1). This is the **only** `Skip` site in `frontend/test`, so it covers boundary and the fullstack tests that go through `BoundaryTestContext`/`LiveSupabaseHarness.ensureReady`. The P6.1-01 setUpAll Skip came from here. Local developers keep today's skip behaviour.

#### Edit F6 (NEW) — set `AICLINIC_BOUNDARY_REQUIRE_LIVE` in CI

`frontend/tool/run_boundary_tests.py` `run_tests` (lines 102-106), before:
```python
    env = {
        **os.environ,
        "AICLINIC_BOUNDARY_INTEGRATION": "1",
        "AICLINIC_DEPLOYMENT_PROFILE_PATH": "config/local/deployment-profile.json",
    }
```
After:
```python
    env = {
        **os.environ,
        "AICLINIC_BOUNDARY_INTEGRATION": "1",
        "AICLINIC_DEPLOYMENT_PROFILE_PATH": "config/local/deployment-profile.json",
    }
    if os.environ.get("CI"):
        env.setdefault("AICLINIC_BOUNDARY_REQUIRE_LIVE", "1")
```
GitHub Actions sets `CI=true`. The same default is added to `_run_fullstack` in F7.

#### F.1.3 Predicted boundary failure classes on first CI run

| Class | Likelihood after F1–F6 | Symptom | Pre-emptive fix |
|---|---|---|---|
| GoTrue 429 | ~0 after F4, near-certain without | `AuthException(over_request_rate_limit)` | F4 |
| Wrong anon key | low | 401 `Invalid API key` from `/auth/v1` and `/rest/v1` | F2 |
| Hook claims missing (`staff_member_id`) | low (same hook config e2e uses) | StateError from F5 "JWT missing staff_member_id" | none; if it occurs, check `[auth.hook.custom_access_token] uri` |
| PostgREST not ready after pre-request DDL (20 × 250 ms = 5 s) | low-medium on cold runner | F5 StateError "PostgREST did not become ready" | optional: raise `_waitForPostgrestReady` attempts 20 → 80 (5 s → 20 s) |
| psql concurrency (`tuple concurrently updated`, `deadlock detected`) | low (retries exist; concurrency 1) | psql error in fixture | none |
| `ORG_ALREADY_EXISTS` in `bootstrapOnly` | low (retry + `forcePurgeInstallation`) | RpcFailure | none |
| Real product/test defects never seen on the CLI stack | **unknown, likely some** | assertion failures | none; this is what the decision accepts |
| AAT issuer ceiling (`ai.issuer.rate_limit.ceiling`) | low (boundary does not mint AATs at scale) | `issuer_rate_limited` | none |

### F.2 `frontend/fullstack`

#### F.2.1 Hidden setUpAll crashes — root cause and fix

- **E2E-P6.1-01** (`ai_status_fullstack_test.dart`):
  - **Cause:** in the unit run, `LiveSupabaseHarness._loadProfile` found no `frontend/config/local/deployment-profile.json` and threw `Skip`. Without `AICLINIC_BOUNDARY_INTEGRATION=1`, `SupabaseBootstrap` also used the test stub. The parser dropped the hook's error (see F.3).
  - **Fix:** A1/A2 move it out of unit; F2 writes the profile; F7 sets the env vars; F5/F6 turn any remaining misconfiguration into a loud failure.
- **E2E-P7.3-06** (`contract_version_matrix_fullstack_test.dart` setUpAll spawns `p7-3-06-prepare.mjs`). There were three stacked causes:
  1. `tsx` was missing because `e2e/fullstack` was not installed. Fixed by F2/A4.
  2. The port and persist clash with the `hfl-run-flutter.mjs` wrapper. Fixed by A6/F7, which runs the file in its own step after the wrapper exits.
  3. **N2:** `startStack()` defaults to `createClinics: true`, and orgB creation always hits `ORG_ALREADY_EXISTS`. Fixed by F8.

  It also needs `psql`, for `readIssuerKeyByStatus` and `applyDesktopRpcGates` (F3).

#### Edit F7 (supersedes A6) — `frontend/tool/run_campaigns.py` `_run_fullstack`

Apply A6 exactly, with two changes.

(a) Env defaults. Replace the A6 block:
```python
    os.environ.setdefault("AICLINIC_BOUNDARY_INTEGRATION", "1")
    os.environ.setdefault(
        "AICLINIC_DEPLOYMENT_PROFILE_PATH", "config/local/deployment-profile.json"
    )
    prepare_fullstack_e2e_stack()
```
with:
```python
    os.environ.setdefault("AICLINIC_BOUNDARY_INTEGRATION", "1")
    os.environ.setdefault(
        "AICLINIC_DEPLOYMENT_PROFILE_PATH", "config/local/deployment-profile.json"
    )
    if os.environ.get("CI"):
        os.environ.setdefault("AICLINIC_BOUNDARY_REQUIRE_LIVE", "1")
    prepare_fullstack_e2e_stack()
```
(b) Explicit per-test timeout. No fullstack file has `@Timeout`, and `dart_test.yaml` sets none, so package:test's default 30 s applies to each test **and to setUpAll**. P7.3-06's setUpAll boots a whole stack and waits up to 2 min for "ready". The P6.3 tests run a 30-iteration `_pumpUntilCheckoutShownState` loop on top of the UI flow. Replace the A6 `flutter_cmd` with:
```python
    def flutter_cmd(files: list[str]) -> list[str]:
        return apply_campaign_args(
            [
                "flutter",
                "test",
                *files,
                "--tags",
                "fullstack",
                "--timeout",
                "6m",
                "--machine",
            ],
            config,
        )
```
`run_boundary_tests.py` uses the same `--timeout` mechanism with `3m`.

Execution order is guaranteed: shared-stack files first, then `contract_version_matrix_fullstack_test.dart`. This matters because `p7-3-06-prepare.mjs` `applyDesktopRpcGates()` rewrites Supabase RPC gates (`get_ai_status` and others) and only restores them on SIGINT/SIGTERM cleanup. Running it last means a failed restore cannot poison P6.x. It is also the last campaign in the frontend job.

#### Edit F8 (NEW, mandatory) — `e2e/fullstack/test/p7-3-06-prepare.mjs:154-157`

Before:
```js
  stack = await startStack({
    aboConfig: ABO_DESKTOP_CONFIG,
    platformConfig: PLATFORM_DESKTOP_CONFIG,
  });
```
After:
```js
  stack = await startStack({
    aboConfig: ABO_DESKTOP_CONFIG,
    platformConfig: PLATFORM_DESKTOP_CONFIG,
    createClinics: false,
  });
```
Why this is safe:
- `p7-3-06-prepare.mjs` never reads `stack.clinics`; `rg 'clinics|orgA|orgB' p7-3-06-prepare.mjs` finds no matches.
- The Dart test creates its own clinic through `ctx.ensureClinic` after `ctx.resetInstallation()`.
- `registerIssuer` stays at its default `true`. That path only needs the Access mock and operator credential, not clinics.
- Only the frontend uses this file. No `e2e/fullstack/test/*.test.mjs` imports it.

#### Edit F9 (NEW) — seed global ABO and platform fixtures in the wrapper

**(a) `e2e/fullstack/test/p7-3-stack.mjs`: an additive export.** Insert it immediately **after** the closing `}` of `ensurePlatformGrantPrerequisites` (which starts at line 1107). Do **not** modify `ensurePlatformGrantPrerequisites` itself, so e2e behaviour is untouched:
```js
export function seedPlatformGrantGlobals() {
  runPlatformD1Command(`
    INSERT OR REPLACE INTO service_key (
      kid, service, public_key, status, not_before, not_after,
      registered_by, assertion_sha256
    ) VALUES (
      ${sqlLiteral(ABO_GRANT_KEY.kid)},
      'abo',
      ${sqlLiteral(ABO_GRANT_KEY.public_key)},
      'active',
      '2020-01-01T00:00:00.000Z',
      '2099-01-01T00:00:00.000Z',
      ${sqlLiteral(OPERATOR_EMAIL)},
      'harness'
    );
    INSERT OR IGNORE INTO plan_version (
      plan_id, version, display_name, capabilities, max_cost_class,
      concurrency_limit, max_allowance_per_month, status, published_by,
      assertion_sha256
    ) VALUES (
      '${PLAN_ID}', ${PLAN_VERSION}, 'Clinic Pro',
      ${sqlLiteral(JSON.stringify([CAPABILITY_ID]))},
      '2', 4, ${ALLOWANCE_CREDITS}, 'published',
      ${sqlLiteral(OPERATOR_EMAIL)}, 'harness'
    );
  `);
}
```
This is the global half of `ensurePlatformGrantPrerequisites`, copied verbatim and using the same module constants.

**(b) `e2e/fullstack/test/hfl-run-flutter.mjs`.**

Imports (lines 7-14), before:
```js
import {
  ABO_URL,
  HARNESS_URL,
  PAYMOB_URL,
  PLATFORM_URL,
  startStack,
  SUPABASE_URL,
} from "./p7-3-stack.mjs";
```
After:
```js
import {
  ABO_URL,
  HARNESS_URL,
  PAYMOB_URL,
  PLATFORM_URL,
  seedAboOffers,
  seedPlatformGrantGlobals,
  startStack,
  SUPABASE_URL,
} from "./p7-3-stack.mjs";
```
`main()` (lines 234-243), before:
```js
      try {
        await stackStartup;
      } finally {
        stackStartup = null;
      }
      if (requestedSignal) {
```
After:
```js
      try {
        await stackStartup;
      } finally {
        stackStartup = null;
      }
      if (!requestedSignal) {
        seedAboOffers();
        seedPlatformGrantGlobals();
      }
      if (requestedSignal) {
```
`seedAboOffers` uses `INSERT OR IGNORE` / `INSERT OR REPLACE` against the ABO persist through `wrangler d1 execute`. That is the same call e2e `p7-3-01/02/04/05` make after `startStack()`. `runPlatformD1Command` → `execPlatformD1Sql` writes `d1-seed` and copies it over the live platform persist. This is also the e2e pattern, used after `startStack()` in `p7-2-*` and `p7-3-*`.

#### Edit F10 (NEW, test change, recommended) — per-org platform tenant binding for P6.3 "Active"

A grant can only apply once the platform has an **active `tenant_binding` for the org** (`entrypoint.ts:546-558`). Each P6.3 test creates a fresh org, so no wrapper-level seed can cover it. Add a helper to `administrator_billing_fullstack_test.dart` next to `_seedEndsSoonCoverage`, and call it right after `_seedEndsSoonCoverage(...)` in P6.3-01, P6.3-02 and P6.3-05. The helper uses the same `sqlite3` technique as `administrator_subscription_fullstack_test.dart:765-810`, against the platform persist:
```dart
Future<void> _seedPlatformTenantBinding({required String orgId, required String installationId}) async {
  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final dbDir = Directory('$repoRoot/e2e/fullstack/.wrangler/platform/v3/d1/miniflare-D1DatabaseObject');
  final files = dbDir.existsSync()
      ? (dbDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sqlite') && !f.path.endsWith('metadata.sqlite'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  if (files.isEmpty) {
    fail('Local platform D1 database not found under e2e/fullstack/.wrangler/platform');
  }
  final now = DateTime.now().toUtc().toIso8601String();
  final sql = '''
INSERT OR IGNORE INTO installation (installation_id, org_id, status, display_name, region, enrolled_at)
VALUES ('$installationId', '$orgId', 'active', '', '', '$now');
INSERT OR REPLACE INTO tenant_binding (org_id, installation_id, epoch, status, retired_at, reason, created_at)
VALUES ('$orgId', '$installationId', 1, 'active', NULL, NULL, '$now');
''';
  final result = await Process.run('sqlite3', [files.first.path, sql]);
  if (result.exitCode != 0) {
    fail('platform sqlite3 seed failed: ${result.stderr}');
  }
}
```
Call site (P6.3-01, after line 123; the same pattern applies in -02/-05):
```dart
      await _seedPlatformTenantBinding(orgId: clinic.organizationId, installationId: installationId);
```
I could not verify that the platform D1 durable object picks up an external `sqlite3` write without a restart. The e2e helpers do something stronger (they overwrite the whole file), which suggests it works, but treat this as **R5**. If it does not work, the only robust alternative is a harness worker route (`e2e/fullstack/src/register-issuer.ts`) that writes `tenant_binding` through the platform binding. That is a larger change.

**P6.3-01 also cannot pass its last assertion as written.** `_expectAiRequestSucceeds` (line 694) invokes the SDK built by `buildLiveVisitSummaryComposition` without `platformBaseUrl` or `submitPortOverride` (lines 128-133). It therefore submits to the default `https://ai.example.workers.dev` (`ai_page.dart:69`), not to `http://127.0.0.1:8787`. Even pointed at 8787, a completed invocation needs a fully enrolled tenant (cohort/routing policy, entitlement, provider stub) that no frontend fixture seeds. This is a **test-design gap, not wiring**. Options for the spec owner:
- (a) pass `platformBaseUrl: Platform.environment['PLATFORM_URL'] ?? 'http://127.0.0.1:8787'` and add full platform enrollment (large);
- (b) narrow the assertion to "AAT mint succeeds and `get_ai_status` is `active`", which the test already checks just above;
- (c) accept the failure.

I did not write an edit because this changes test intent.

#### F.2.2 Exposure to the e2e-fullstack issues

- **`.wrangler/d1-seed` duplicate-column race:** **not exposed**.
  - The governor runs campaigns sequentially (`interactive_run_dashboard.py:223-270`).
  - `frontend/fullstack` steps run sequentially in one `run_subprocess_sequence`.
  - Flutter `--concurrency` is 1 (A6 inherits `parallel_tests`), and each step starts one stack. `p7-3-06-prepare.mjs` is the only `preparePlatformD1` caller in step 2.
  - `prepare_fullstack_e2e_stack()` wipes `e2e/fullstack/.wrangler` before step 1.
  - It **is** still exposed to a *deterministic* migration failure in `ai-platform/migrations` (any fix lands for both areas).
- **5 variant tomls without `migrations_dir`:** **not exposed**. The frontend uses only `ai-platform/wrangler.toml`, `abo/wrangler.toml`, `variant/platform-desktop-window.toml` and `variant/abo-desktop-window.toml`, and both variants declare `migrations_dir`.

#### F.2.3 Predicted further fullstack blockers

| Item | Status | Notes |
|---|---|---|
| Base URLs | OK | Dart defaults `ABO_URL=http://127.0.0.1:8788`, `PAYMOB_URL=http://127.0.0.1:8789` match `spawnAboProcess`/paymob ports; `BILLING_HOST=billing.vendor.test` header used by tests and dev vars |
| Paymob HMAC | OK by construction | ABO dev vars `PAYMOB_HMAC_SECRET="paymob-hmac-unconfigured"`; `_replayPaymobFixture` must sign with the same value (shared with e2e p7-3, which uses the same fixtures) |
| sqlite3 path | OK | `ABO_PERSIST=e2e/fullstack/.wrangler/abo` → `v3/d1/miniflare-D1DatabaseObject/*.sqlite`; `sqlite3 -json` needs ≥ 3.33 (ubuntu-24.04 apt: 3.45) |
| Issuer signing key | OK | `20261007180000_issuer_key_custody.sql:119` inserts one on fresh DB; `readIssuerKeyByStatus("signing")` reads via psql |
| Billing token / AAT minting | likely OK | Uses Supabase RPCs with the hook-claims session |
| ABO ↔ platform service binding | OK | ABO `[[env.development.services]] PLATFORM → ai-platform-gateway-development#VendorEntrypoint`, found via `WRANGLER_REGISTRY_PATH=.wrangler/registry` (same as e2e) |
| Stack boot time | 1–3 min per step on a cold runner | wrangler bundles ai-platform and abo; P7.3-06 setUpAll waits ≤ 2 min for "ready" (covered by `--timeout 6m`) |
| `npx wrangler` from repo root | risk R6 | May fetch `wrangler@latest`; shared with e2e (A.5 item 3) |
| P6.3 "Active" | needs F9 + F10 | otherwise P6.3-01/02/05 fail at 30 s |
| P6.3-01 AI call | expected FAIL as written | test-design gap above |
| P6.4-01..05 | medium | Read/patch ABO D1 directly via sqlite3 (`applied_at` seeded at `:865`); depend on F9(a) offers |
| P7.3-06 | medium after F8 | Expects 400 `contract_version_unsupported` from both ABO and platform under desktop-window variants (shim `CHANNEL_VERSIONS` platformClinic/aboClinic 3) |

### F.3 Governor harness fix — attribute setUpAll and loading failures

**Root cause** (`test/harness/live_progress.py:1441-1502`). `testStart` for hook pseudo-tests (`(setUpAll)`, `(tearDownAll)`, …) and loading pseudo-tests is put in `_ignored_ids` and discarded. A later `error` event for that ID is not in `_active`, so it is attributed to `display.current`, which is whatever test last started, or `"flutter test error"`. The hook's own `testDone{result:"error"}` is dropped, and suite events aren't tracked, so the file can't be named.

Top-level hooks are the broken case. Group-level hooks are named `"<group> (setUpAll)"`, which `is_flutter_hook_pseudo_test` doesn't match, so they are already recorded under their own name. Compile failures (`loading <file>` errors) are misattributed the same way.

#### Edit H1 — `test/harness/flutter_machine_labels.py` (append at end of file)

```python
def flutter_pseudo_test_failure_label(test: dict, suite_path: str | None) -> str:
    """Label for a failed loading/hook pseudo-test, e.g. ``foo_test.dart (setUpAll)``."""
    name = (test.get("name") or "").strip()
    if is_loading_pseudo_test(test):
        loaded = name.split(" ", 1)[1] if " " in name else name
        return f"{Path(loaded).name} (loading)"
    suite_file = Path(suite_path).name if suite_path else _filename_from_url(test.get("url"))
    if suite_file:
        return f"{suite_file} {name}".strip()
    return name or "flutter hook"
```

#### Edit H2 — `test/harness/live_progress.py` `FlutterMachineParser`

`__init__`, before (lines 1419-1420):
```python
        self._active: dict[int, str] = {}
        self._ignored_ids: set[int] = set()
```
After:
```python
        self._active: dict[int, str] = {}
        self._ignored_ids: set[int] = set()
        self._pseudo: dict[int, str] = {}
        self._failed_pseudo: set[int] = set()
        self._suite_paths: dict[int, str] = {}
```
Replace the whole `_handle_event` method (lines 1441-1502) with:
```python
    def _handle_event(self, event: dict) -> None:
        from harness.flutter_machine_labels import (
            flutter_pseudo_test_failure_label,
            flutter_test_label,
            is_flutter_hook_pseudo_test,
            is_loading_pseudo_test,
        )

        kind = event.get("type")
        if kind == "suite":
            suite = event.get("suite") or {}
            suite_id = suite.get("id")
            if suite_id is not None and suite.get("path"):
                self._suite_paths[int(suite_id)] = str(suite["path"])
            return
        if kind == "testStart":
            test = event.get("test") or {}
            test_id = test.get("id")
            if test_id is None:
                return
            tid = int(test_id)
            if is_loading_pseudo_test(test) or is_flutter_hook_pseudo_test(test):
                suite_id = test.get("suiteID")
                suite_path = (
                    self._suite_paths.get(int(suite_id)) if suite_id is not None else None
                )
                self._pseudo[tid] = flutter_pseudo_test_failure_label(test, suite_path)
                return
            label = flutter_test_label(test)
            if label is None:
                self._ignored_ids.add(tid)
                return
            self._active[tid] = label
            if self.log_session is not None:
                self.log_session.start_test(label)
            self.display.set_current(label)
        elif kind == "testDone":
            test_id = event.get("testID")
            if test_id is None:
                return
            tid = int(test_id)
            if tid in self._pseudo:
                label = self._pseudo.pop(tid)
                already_failed = tid in self._failed_pseudo
                self._failed_pseudo.discard(tid)
                result = event.get("result")
                if not already_failed and result not in (None, "success"):
                    self._record_failure(label, f"{label} finished with result {result}")
                return
            if event.get("hidden"):
                return
            if tid in self._ignored_ids:
                self._ignored_ids.discard(tid)
                return
            name = self._active.pop(tid, None)
            if name is None:
                return
            result = event.get("result")
            status = "PASS" if result == "success" else "FAIL"
            self.display.add_finished(name, status)
            if self.log_session is not None:
                self.log_session.end_test(name, status=status)
        elif kind == "error":
            test_id = event.get("testID")
            tid = int(test_id) if test_id is not None else None
            name: str | None = None
            if tid is not None and tid in self._pseudo:
                if tid in self._failed_pseudo:
                    return
                self._failed_pseudo.add(tid)
                name = self._pseudo[tid]
            elif tid is not None and tid in self._active:
                name = self._active.pop(tid, None)
            if name is None:
                name = self.display.current
                if name in ("(starting…)", "starting…", "Interrupted"):
                    name = "flutter test error"
            err = (event.get("error") or "flutter test error").strip()
            self._record_failure(name, err, stack_trace=event.get("stackTrace"))

    def _record_failure(
        self, name: str, err: str, *, stack_trace: object = None
    ) -> None:
        if self.log_session is not None:
            if not self.log_session.has_active():
                self.log_session.start_test(name)
            if stack_trace:
                self.log_session.append_line(str(stack_trace))
            self.log_session.append_line(err)
            self.log_session.end_test(name, status="FAIL", error=err)
        self.display.add_finished(name, "FAIL")
```
Behaviour preserved:
- Normal tests: identical branches.
- Unknown-ID `error`: same `display.current` / `"flutter test error"` fallback. `test_runner_crash.py::test_crash_inspect_clears_fatal_on_flutter_success` relies on this.
- Passing hooks and loads: never counted. They finish with `result:"success"` (and `hidden:true`).

New behaviour:
- A failing top-level hook is recorded once as `"<file>.dart (setUpAll)"`.
- A failing load is recorded as `"<file>.dart (loading)"`.

The PASS/FAIL semantics of `skipped` tests are deliberately unchanged, to avoid shifting unit totals. F5/F6 close the skip trap at the source instead.

#### Edit H3 — new tests in `test/harness/test_flutter_machine_parser.py` (append)

```python
def _feed(parser: FlutterMachineParser, event: dict) -> None:
    parser.feed(json.dumps(event) + "\n")


def test_setup_all_error_is_attributed_to_suite_file() -> None:
    display = CampaignProgressDisplay("[frontend/fullstack]")
    parser = FlutterMachineParser(display)
    _feed(parser, {"type": "suite", "suite": {"id": 0, "platform": "vm", "path": "/proj/test/integration/foo_fullstack_test.dart"}})
    _feed(parser, {"type": "testStart", "test": {"id": 3, "name": "(setUpAll)", "suiteID": 0}})
    _feed(parser, {"type": "error", "testID": 3, "error": "Bad state: prepare exited 1"})
    _feed(parser, {"type": "testDone", "testID": 3, "result": "error", "hidden": False})
    assert display.failed == 1
    assert display.passed == 0
    assert display.current == "foo_fullstack_test.dart (setUpAll)"


def test_passing_setup_all_is_not_counted() -> None:
    display = CampaignProgressDisplay("[frontend/fullstack]")
    parser = FlutterMachineParser(display)
    _feed(parser, {"type": "suite", "suite": {"id": 0, "path": "/proj/a_test.dart"}})
    _feed(parser, {"type": "testStart", "test": {"id": 1, "name": "(setUpAll)", "suiteID": 0}})
    _feed(parser, {"type": "testDone", "testID": 1, "result": "success", "hidden": True})
    assert display.failed == 0
    assert display.passed == 0


def test_loading_failure_is_attributed_to_file() -> None:
    display = CampaignProgressDisplay("[frontend/unit]")
    parser = FlutterMachineParser(display)
    _feed(parser, {"type": "testStart", "test": {"id": 1, "name": "loading /proj/test/broken_test.dart", "suiteID": 0}})
    _feed(parser, {"type": "error", "testID": 1, "error": "Compilation failed"})
    _feed(parser, {"type": "testDone", "testID": 1, "result": "error", "hidden": False})
    assert display.failed == 1
    assert display.current == "broken_test.dart (loading)"
```
These use the same synchronous `CampaignProgressDisplay` assertions as the existing `test_test_done_uses_test_id` (`display.passed`, `display.current`). The existing tests in `test_flutter_machine_parser.py` and `test_runner_crash.py` keep passing:
- `test_skip_*_pseudo_test` only call `flutter_test_label`, which is unchanged.
- The `error`-without-start cases take the unchanged fallback.

**Which campaign runs these?** None in CI. No workflow, `setup-campaign-area.sh`, `campaign_catalog.py` or `campaign_tree.py` entry invokes pytest on `test/harness`. They are developer-run only, so the CI risk is zero. Run them locally the way the repo already does, for example `python -m pytest test/harness/test_flutter_machine_parser.py test/harness/test_runner_crash.py`, with `test/` on `sys.path` as the existing imports `from harness....` require.

### F.4 Frontend CI time budget

| Phase | Estimate | Basis |
|---|---|---|
| Setup (checkout, Flutter, `supabase start`, 4 extra `npm ci` dirs, apt) | 6–10 min | +2–4 min versus today for npm dirs |
| `frontend/all` unit | ~14.6 min | `summary.json` `elapsed_seconds` 876 (minus 14 fullstack tests after A1) |
| `frontend/all` boundary | 15–25 min | 17 files compiled serially (concurrency 1, ~20–40 s each) plus ≈170 tests × 2–5 s (reset, bootstrap, sign-ins); `--timeout 3m` per test caps pathological hangs |
| `frontend/fullstack` | 8–15 min | 4 files; 2 stack boots × 1–3 min; 14 tests including up-to-30 s state polls |
| **Nominal total** | **~45–65 min** | |
| Pessimistic (several 3 m / 6 m timeouts, slow cold stack) | 80–100 min | |

Recommendation: `timeout_minutes: 120` for the frontend matrix entry (F3). Splitting frontend into separate jobs is not needed yet.

### F.5 Shared-file edits and the invariant each preserves

| File | Edit | Shared with | Invariant preserved |
|---|---|---|---|
| `.github/scripts/setup-campaign-area.sh` | F2: frontend `case` npm dirs; frontend-only profile block guarded by `[[ "${area}" == "frontend" ]]`. B1: vendor-contracts npm dirs | all CI jobs | Each area's `case` branch is independent; no other area's npm dirs, Supabase or Flutter setup changes; the profile block is a no-op for other areas |
| `.github/workflows/ci.yml` | F3: frontend `postgresql_client: true`, `timeout_minutes: 120`; apt line adds `sqlite3` | backend, e2e-fullstack (the apt step) | Extra apt package only; no step order/conditions change for other areas |
| `backend/supabase/config.toml` | F4: raise 3 GoTrue rate limits | backend, e2e-fullstack, frontend, local dev | Local-only config; no test asserts GoTrue 429; DB schema/migrations untouched |
| `e2e/fullstack/test/p7-3-stack.mjs` | F9(a): **new** export `seedPlatformGrantGlobals()` | e2e-fullstack | Purely additive; `startStack`, `ensurePlatformGrantPrerequisites`, `seedAboOffers` unchanged, so every e2e test behaves identically |
| `e2e/fullstack/test/hfl-run-flutter.mjs` | F9(b): import plus two seed calls after stack start | frontend only (e2e tests do not use the wrapper) | Signal/cleanup/exit-code flow unchanged; seeds skipped if a signal arrived during startup |
| `e2e/fullstack/test/p7-3-06-prepare.mjs` | F8: `createClinics: false` | frontend only | Same configs, ports, issuer registration, RPC gates and cleanup |
| `e2e/fullstack/test/wrangler-persist.mjs` | **none** | | |
| `test/harness/flutter_machine_labels.py`, `live_progress.py` | H1/H2 | every Flutter campaign (frontend/all unit and boundary, fullstack) | Normal test PASS/FAIL accounting is identical; only pseudo-test failures change, from misattributed or dropped to attributed |
| `test/harness/local_dev_ports.py` | none (used by F7) | e2e-fullstack runner | |

### F.6 Ordered apply checklist

1. B1 + F2 (`setup-campaign-area.sh`)
2. F3 (`ci.yml`)
3. F4 (`config.toml`)
4. A1 + A2 (unit exclusion)
5. F1 (= A3), F6 (`run_boundary_tests.py`)
6. F5 (`live_supabase_harness.dart`)
7. F7 (`_run_fullstack`)
8. F8 (`p7-3-06-prepare.mjs`)
9. F9 a + b (`p7-3-stack.mjs`, `hfl-run-flutter.mjs`)
10. F10 (`administrator_billing_fullstack_test.dart`, recommended)
11. H1 + H2 + H3 (harness; run harness pytest locally)
12. *Shared prerequisite owned by the e2e-fullstack agent:* `preparePlatformD1` must apply `ai-platform/migrations` cleanly on a fresh `d1-seed`.

How to check the first CI run:
- `frontend/all/output.log` shows `== boundary ==` followed by machine JSON. It must not contain `backend/local stack is not running`, `over_request_rate_limit` or `AICLINIC_BOUNDARY_REQUIRE_LIVE`.
- `frontend/fullstack/output.log` shows `== hfs-shared-stack ==` and `== hfs-self-managed-stack ==`, with 14 recorded tests. Any hook failure appears as `<file>.dart (setUpAll)`.

### F.7 Residual risks (explicit)

| ID | Risk | Likelihood | Mitigation / next action |
|---|---|---|---|
| R1 | Boundary suite surfaces real failures on the CLI stack (never run green anywhere in CI) | high that ≥1 fails | Accepted by decision; triage per test |
| R2 | P6.3-01 `_expectAiRequestSucceeds` targets `ai.example.workers.dev` and needs full platform enrollment | **near-certain FAIL** as written | Spec-owner decision (F.2, options a/b/c) |
| R3 | Paymob fixture replay/HMAC or `/notify/paymob` routing differs from what the Dart test assumes (never executed) | medium | Compare with e2e p7-3 use of the same fixtures |
| R4 | `testWidgets` fake-clock `tester.pump(Duration)` loops may not let real HTTP/timers progress (`_pumpUntilCheckoutShownState`) | medium | If "Timed out waiting for checkout shown_state" appears with grant applied in ABO D1, wrap polling in `tester.runAsync` |
| R5 | External `sqlite3` writes (F10, and P6.4's ABO writes) are not seen by the running workerd D1 object | low-medium | Fallback: harness-worker route writing via the platform binding |
| R6 | `npx wrangler` from repo root resolves `wrangler@latest` (network, version drift) | medium | Shared fix: spawn `e2e/fullstack/node_modules/wrangler/bin/wrangler.js` |
| R7 | Ports 8787–8790 not yet released when step 2 starts (wrapper awaits `stack.stop()`, so unlikely) | low | Insert a `[sys.executable, "<repo>/test/harness/local_dev_ports.py"]` step between the two fullstack steps (adds one PASS step entry) |
| R8 | `applyDesktopRpcGates` not restored if the P7.3-06 prepare child is SIGKILLed | low (it is last in the job) | none needed in CI |
| R9 | PostgREST readiness wait (5 s) too short on a cold runner | low-medium | Raise attempts 20 → 80 in `_waitForPostgrestReady` |
| R10 | Job exceeds 120 min if many tests hit their 3 m / 6 m timeouts | low | Lower fullstack `--timeout` to 4m once timings are known |
| R11 | The shared `ai-platform` migration-apply problem (e2e agent) blocks `startStack` | depends on the other fix | Coordinate; the frontend stack fails at `preparePlatformD1` with the same error |

### F.8 Cross-finding for the coordinator (affects e2e-fullstack)

`createTwoOrgClinics()` in **both** `p7-2-stack.mjs:537-550` and `p7-3-stack.mjs:682-` creates orgA and then orgB through `bootstrap_create_organization`. That function has returned `ORG_ALREADY_EXISTS` when any non-deleted org exists since `20260516100300_auth_rbac_functions.sql`. The current definition is `20261009120000_fix_staff_membership_session_rls.sql`, and its guard is `auth_internal.organization_exists()`. So **every e2e test that calls `startStack()` without `createClinics: false` should fail in `before()`** with `bootstrap_create_organization failed for p7-2-b`. Both stacks use the `p7-2-*` prefixes. I checked the options: none of these disable it.
- `p7-2-credential-isolation`, `p7-2-untrusted-callers`, `p7-2-vendor-entrypoint`;
- `p7-3-01`, `p7-3-02`, `p7-3-03`, `p7-3-04`, `p7-3-05`, `p7-3-07`.

This has not been observed because e2e-fullstack currently fails earlier, at the vendor-contracts bundle. The e2e agent should confirm, since fixing it needs either SQL-side multi-org creation in the harness or a test-only bypass, which is outside frontend scope.
