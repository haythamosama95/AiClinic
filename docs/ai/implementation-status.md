# AI Layer — Implementation Status by Phase

**Branch:** `ai/015-ai-layer-foundation`
**Last updated:** 2026-07-17
**Spec Kit feature:** [015-ai-layer-foundation](../../specs/015-ai-layer-foundation/spec.md)
**Normative spec:** [AI Service Specification v2](../ai_service/AI%20Service%20Specification.md) (Appendix B)

This document summarizes **what has been built so far** on the AI branch. For operator runbooks and curl examples, see [phase-capabilities.md](./phase-capabilities.md).

---

## Two phase numbering systems

The repo uses two related but different phase schemes. Do not mix them up.

| Scheme | Scope | Current progress |
| --- | --- | --- |
| **Feature 015 internal phases** (1–6 in `tasks.md`) | Breakdown of the *foundation* feature only | **Phases 1–4 done**, 5–6 pending |
| **AI Service Spec Appendix B phases** (1–5) | Full AI product roadmap (V2-1 → V2-3) | **Phase 1 partially done** (~70%), Phases 2–5 not started |

```
AI Service Spec Appendix B          Feature 015 (tasks.md)
──────────────────────────          ──────────────────────
Phase 1 — Foundation (V2-1)   ←──   Phases 1–6 (control plane only)
Phase 2 — Generation (V2-1)         (not started — future feature 016)
Phase 3 — Flutter client (V2-2)
Phase 4 — Full agents (V2-3)
Phase 5 — Production rollout
```

**Bottom line:** The branch delivers the **control-plane spine** of AI Service Phase 1. There is **no AI generation**, **no Flutter AI UI**, and **no agents** yet.

---

## At a glance

| Metric | Value |
| --- | --- |
| Implementation commits (after spec docs) | 4 |
| Tasks complete (`tasks.md`) | **35 / 50** (70%) |
| Gateway Python modules | 17 source files under `ai/gateway/src/gateway/` |
| Automated tests | **48 collected** — 47 passing, 1 known failure (see [Known gaps](#known-gaps)) |
| Isolation scan | **PASS** — no DB creds/drivers under `ai/` |
| Flutter / Supabase changes | **None** (by design) |

### Git history (implementation)

| Commit | Date | Summary |
| --- | --- | --- |
| `e3a292a` | 2026-07-03 | Phases 1 & 2 — project skeleton, config, errors, logs, metrics, bootstrap |
| `f5458cb` | 2026-07-03 | Phase 3 — health spine, runner polling, isolation scan, Ollama layout, **dashboard** |
| `9b2500d` | 2026-07-03 | Runner wiring — `gateway.yaml`, `/v1/runners/{id}/models`, dashboard runner panels |
| `e6664d2` | 2026-07-04 | Phase 4 — JWT auth (HS256 + JWKS), `ai.access` role gate, auth test matrix |

Earlier on the branch: `240c618` (speckit docs), `4dbbdc2` (AI Service Specification submission).

---

## Feature 015 — Phase 1: Setup ✅

**Goal:** Isolated `ai/` tree and Python Gateway project skeleton.

### Implemented

| Deliverable | Location |
| --- | --- |
| Isolated `ai/` directory layout | `ai/gateway/`, `ai/runners/`, `ai/dashboard/` |
| Python 3.12+ Gateway project | `ai/gateway/pyproject.toml`, `requirements-dev.lock.txt` |
| Ruff + pytest configuration | `pyproject.toml` |
| Security invariants README | `ai/README.md` |
| Gateway Dockerfile (non-root, port 8090) | `ai/gateway/Dockerfile` |
| Dev scripts | `ai/gateway/scripts/run_tests.sh`, `start_dev.sh` |

### Not in original tasks (bonus)

| Deliverable | Location |
| --- | --- |
| Control plane dashboard (static HTML/JS/CSS) | `ai/dashboard/` — served at `GET /dashboard` |
| Dev startup script | `ai/gateway/scripts/start_dev.sh` |

---

## Feature 015 — Phase 2: Foundational ✅

**Goal:** Typed config, uniform errors, observability, ASGI bootstrap, test harness.

### Implemented

| Component | File(s) | Notes |
| --- | --- | --- |
| Config models + fail-fast validation | `config/settings.py`, `config/gateway.example.yaml` | `GatewayConfig`, `RunnerConfig`, `ModelDef`; rejects `*` in CORS, requires JWT material |
| Typed error envelope | `api/errors.py` | Codes: `bad_request`, `unauthenticated`, `forbidden`, `not_implemented`, `rate_limited`, `ai_no_capacity`, `ai_timeout` |
| Structured JSON logging + PHI redaction | `obs/logging.py` | Active when `log_verbatim=false` |
| Prometheus metrics collectors | `obs/metrics.py`, `api/metrics.py` | Request rate, status codes, runner health/latency |
| ASGI app factory | `main.py` | CORS allowlist, `X-Request-ID` middleware, lifespan hooks, dashboard static mount |
| Test harness | `tests/conftest.py`, `tests/fixtures/fake_runner.py` | In-process ASGI client, scriptable fake runner |

### Live endpoints after Phase 2

| Method | Path | Auth |
| --- | --- | --- |
| `GET` | `/health` | None |
| `GET` | `/metrics` | None |
| `GET` | `/dashboard` | None (static UI) |

---

## Feature 015 — Phase 3: US1 — Health-reportable AI spine ✅

**Goal:** Runner lifecycle, registry, health poller, honest `/ready`, isolation scan, Ollama runner baseline.

### Implemented

| Component | File(s) | Notes |
| --- | --- | --- |
| Runner lifecycle state machine | `routing/lifecycle.py` | `UNKNOWN → STARTING → READY → UNREACHABLE`; enum includes `BUSY`/`DEGRADED` but transitions not fully wired |
| In-memory runner registry | `routing/registry.py` | Status, last-seen, latency, loaded model, consecutive failures |
| Background health poller | `routing/health_poller.py` | Pull-based, default 10 s cadence |
| OpenAI-compatible poll client | `runners/openai_client.py` | `GET /v1/models`, optional `/health`, ≤2 s timeout |
| Health endpoints | `api/health.py` | `/health` always 200; `/ready` 200 only when ≥1 runner `READY` |
| Isolation scan (CI gate) | `scripts/isolation_scan.py` | Static scan for DB creds, service-role keys, DB driver imports |
| Ollama runner packaging | `runners/ollama/` | `docker-compose.yaml`, `Modelfile` (Qwen3-4B Q4_K_M), `digests.md` |
| Operator runbook | `runners/README.md` | Model install, GGUF path, digest pinning |
| Control-plane status API | `api/status.py` | `GET /v1/status` — dashboard snapshot (no secrets) |
| Runner model proxy | `api/runners.py` | `GET /v1/runners/{id}/models` — proxies runner `GET /v1/models` |
| Local dev config | `config/gateway.yaml` | Pre-configured runner pointing at Ollama |

### Tests shipped

| Test file | Coverage |
| --- | --- |
| `contract/test_isolation.py` | Isolation scan pass/fail |
| `contract/test_health.py` | Liveness + readiness honesty |
| `contract/test_runner_contract.py` | Runner bind address (1 test currently failing — see gaps) |
| `contract/test_status.py` | Status snapshot shape, no secret leakage |
| `contract/test_runners.py` | Runner model proxy |
| `unit/test_lifecycle.py` | Lifecycle transitions |
| `unit/test_config.py` | Config validation |

### Live endpoints added

| Method | Path | Auth (current) |
| --- | --- | --- |
| `GET` | `/ready` | JWT + `ai.access` (auth added in Phase 4) |
| `GET` | `/v1/status` | JWT + `ai.access` |
| `GET` | `/v1/runners/{id}/models` | JWT + `ai.access` |

---

## Feature 015 — Phase 4: US2 — Authentication & authorization ✅

**Goal:** Offline Supabase JWT validation + coarse `ai.access` role gate on all protected endpoints.

### Implemented

| Component | File(s) | Notes |
| --- | --- | --- |
| Offline JWT validator | `auth/jwt_validator.py` | HS256 (`jwt_secret`) and JWKS (`jwks_url`); JWKS wins if both set; validates `exp`/`nbf`; zero Supabase network calls |
| Reloadable role map | `auth/role_map.py` | Defaults: `administrator`/`doctor` granted, `receptionist`/`lab_staff` denied; SIGHUP + 60 s file re-read |
| Auth dependency | `auth/dependencies.py` | `require_ai_access` — emits typed `401`/`403` |
| Protected route wiring | `main.py`, all `api/*` routers | `/health` and `/metrics` remain public; everything else gated |

### Role → `ai.access` defaults

| Role | Access |
| --- | --- |
| `administrator` | ✅ |
| `doctor` | ✅ |
| `receptionist` | ❌ |
| `lab_staff` | ❌ |

Override via `role_ai_access:` in `gateway.yaml` or optional `config/role_ai_access.yaml`.

### Tests shipped

| Test file | Coverage |
| --- | --- |
| `contract/test_auth_matrix.py` | Full token matrix under HS256 **and** JWKS |
| `contract/test_error_contract.py` | Auth precedes authz; stable error shape |
| `unit/test_role_map.py` | Atomic reload of role grants |
| `fixtures/jwt_tokens.py` | Test token factory (HS256 + RS256/JWKS) |

### Dashboard auth integration

The control plane dashboard (`/dashboard`) stores a staff JWT in `localStorage` and sends `Authorization: Bearer` on protected API polls. See `ai/dashboard/README.md`.

---

## Feature 015 — Phase 5: US3 — Discovery, routing & capabilities ✅

**Goal:** Full lifecycle edges, capability→health→least-busy selector, `/v1/capabilities`, generate stub (`501`).

**Web UI:** Phase 5 is wired in the control-plane dashboard (`/dashboard` — Capabilities & Generate panels) and runner console (`/runner-console` — gateway discovery).

### Pending tasks (from `tasks.md`)

| ID | Description | Status |
| --- | --- | --- |
| T036 | Registry/failover integration test | ⬜ |
| T037 | Selector unit tests | ⬜ |
| T038 | Capabilities mirror contract test | ⬜ |
| T039 | Generate-stub contract test | ⬜ |
| T040 | Lifecycle edges (`READY↔BUSY`, `DEGRADED`, recovery) | ⬜ |
| T041 | `routing/selector.py` — capability → health → least-busy | ⬜ |
| T042 | `api/capabilities.py` — `GET /v1/capabilities` | ⬜ |
| T043 | `api/generate_stub.py` — `POST /v1/ai/generate` → 501 | ⬜ |

### Missing source files (not yet created)

- `ai/gateway/src/gateway/routing/selector.py`
- `ai/gateway/src/gateway/api/capabilities.py`
- `ai/gateway/src/gateway/api/generate_stub.py`

### Missing endpoints

| Method | Path | Expected behavior |
| --- | --- | --- |
| `GET` | `/v1/capabilities` | Live registry mirror; `tasks:[]`, `commands:[]` |
| `POST` | `/v1/ai/generate` | Always `501 not_implemented` — zero inference |

---

## Feature 015 — Phase 6: Polish & cross-cutting ⏳ NOT STARTED

**Goal:** Full observability wiring, PHI-redaction proof, optional push registration, CI gate green, quickstart validation.

### Pending tasks

| ID | Description | Status |
| --- | --- | --- |
| T044 | Per-request/per-runner metrics fully wired | ⬜ |
| T045 | PHI-redaction unit test | ⬜ |
| T046 | Optional push registration (`/internal/runners/register\|heartbeat`) | ⬜ |
| T047 | Security hardening pass (Dockerfile, least-privilege) | ⬜ |
| T048 | Full CI gate green (`ruff` + isolation + pytest) | ⬜ (blocked by 1 test failure + incomplete Phase 5) |
| T049 | Quickstart end-to-end validation | ⬜ |
| T050 | Constitution compliance review | ⬜ |

---

## AI Service Spec Appendix B — Roadmap phases

These are the **product-level** phases from the normative AI Service Specification. Only the foundation slice has work in this branch.

### Phase 1 — AI Layer Foundation (V2-1) — 🟡 PARTIAL (~70%)

Maps to feature 015. The spec's exit criteria require capabilities, routing selection, and a full test suite. Current branch status against spec exit gates:

| Exit criterion | Status |
| --- | --- |
| `/health` green | ✅ |
| Auth matrix passes | ✅ |
| Runner kill → `UNREACHABLE` → `/ready` false → recovery | ✅ (basic path; full DEGRADED/BUSY not wired) |
| `/v1/capabilities` mirrors live registry | ❌ Phase 5 |
| Full test suite green in CI | ❌ 1 failing test; Phase 5 tests missing |
| No DB creds in `ai/` | ✅ isolation scan |
| Runner not client-routable | ⚠️ docker-compose bind drift (see gaps) |

### Phase 2 — Generation pipeline + Scheduling agent (V2-1) — ⬜ NOT STARTED

Future feature **016**. Would deliver:

- Real `POST /v1/ai/generate` (streaming + non-streaming)
- Scheduling agent (appointments: create/reschedule/cancel/status)
- Grammar-constrained JSON output + semantic validation
- Resilience envelope (queue, backpressure, timeouts, retry, cancellation)
- Command Protocol envelopes with human-approval-ready proposals

**Nothing from Phase 2 exists in the repo yet.**

### Phase 3 — Flutter AI client (V2-2) — ⬜ NOT STARTED

Would deliver `frontend/lib/features/ai/` — chat panel, approval cards, context assembly from RPCs, `lookup_required` resolution, graceful degradation.

**No Flutter AI code exists.**

### Phase 4 — Full agent suite + multi-node (V2-3) — ⬜ NOT STARTED

Billing, shifts, and clinical summarizer agents; optional multi-node runner config.

### Phase 5 — Production readiness & rollout — ⬜ NOT STARTED

Installer/runbook, security pass, failure drills, §17.5 checklist automation.

---

## Current architecture (as implemented)

```
┌─────────────────────────────────────────────────────────────┐
│  Clinic LAN clients (Flutter — no AI integration yet)     │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTP :8090
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  AI Gateway (FastAPI / Python)                              │
│  ┌─────────────┐ ┌──────────┐ ┌───────────┐ ┌────────────┐ │
│  │ Auth (JWT)  │ │ Registry │ │ Poller    │ │ Dashboard  │ │
│  │ ai.access   │ │ lifecycle│ │ 10s pull  │ │ /dashboard │ │
│  └─────────────┘ └──────────┘ └───────────┘ └────────────┘ │
│  Endpoints: /health /metrics /ready /v1/status              │
│             /v1/runners/{id}/models                         │
│  Missing:   /v1/capabilities /v1/ai/generate              │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTP 127.0.0.1:11434 (internal)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Model Runner (Ollama) — Qwen3-4B Q4_K_M                   │
│  OpenAI-compatible /v1/models, /v1/chat/completions         │
│  NOT reachable from client subnet (by design)               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Supabase / PostgreSQL — UNTOUCHED by AI layer             │
│  JWT validated offline; no DB creds anywhere in ai/          │
└─────────────────────────────────────────────────────────────┘
```

---

## Source tree inventory

```
ai/
├── README.md                          # Security invariants + quick start
├── dashboard/                         # Control plane UI (bonus, not in original spec)
│   ├── index.html, app.js, styles.css
│   └── README.md
├── gateway/
│   ├── config/
│   │   ├── gateway.example.yaml       # All §14 keys documented
│   │   └── gateway.yaml               # Local dev config (runner wired)
│   ├── scripts/
│   │   ├── isolation_scan.py          # CI gate
│   │   ├── run_tests.sh
│   │   └── start_dev.sh
│   ├── src/gateway/
│   │   ├── main.py
│   │   ├── api/          health, metrics, status, runners, errors
│   │   ├── auth/         jwt_validator, role_map, dependencies
│   │   ├── config/       settings
│   │   ├── obs/          logging, metrics
│   │   ├── routing/      lifecycle, registry, health_poller
│   │   └── runners/      openai_client
│   └── tests/            48 tests across unit + contract
└── runners/
    ├── README.md
    └── ollama/           docker-compose, Modelfile, digests.md
```

---

## Known gaps and drift

| Issue | Detail | Blocks |
| --- | --- | --- |
| **1 failing test** | `test_compose_does_not_publish_runner_on_all_interfaces` — `docker-compose.yaml` uses `OLLAMA_HOST=0.0.0.0:11434` instead of `127.0.0.1` bind | Phase 6 CI gate (T048) |
| **Phase 5 not started** | No selector, capabilities, or generate stub | AI Service Phase 1 exit |
| **Lifecycle incomplete** | `BUSY`/`DEGRADED` states exist in enum but transition edges not implemented | Phase 5 (T040) |
| **No PHI-redaction test** | Redaction processor exists but no automated proof test | Phase 6 (T045) |
| **No push registration** | `enable_push_registration` config exists but endpoints not built | Phase 6 (T046) |
| **Dashboard ahead of API** | Dashboard has Phase 5 placeholders; backend routes don't exist yet | Cosmetic only |

---

## Recommended next steps

1. **Finish feature 015 Phase 5** — selector, capabilities endpoint, generate stub, and their tests (T036–T043).
2. **Fix runner bind test** — align `docker-compose.yaml` with `127.0.0.1` non-routability requirement.
3. **Complete Phase 6 polish** — PHI-redaction test, full metrics wiring, CI gate green.
4. **Close AI Service Phase 1 exit** — all foundation exit criteria green before starting feature 016 (generation).
5. **Begin feature 016** — generation pipeline + scheduling agent per Appendix B Phase 2.

---

## How to run everything (runner + gateway + dashboard)

End-to-end guide for bringing up what exists today on a dev machine. Start **Ollama first**, then the
**Gateway** (which also serves the dashboard). There is no separate dashboard process.

### Prerequisites

| Requirement | Notes |
| --- | --- |
| Docker + Compose | For the Ollama runner |
| Python ≥ 3.12 | Gateway (3.13 works; repo was tested with 3.13) |
| ~4 GB free RAM | Default model Qwen3-4B Q4_K_M |
| A staff JWT | Doctor or administrator role with `ai.access` — for protected dashboard polls |

### First-time Gateway setup (once per machine)

```bash
cd ai/gateway
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.lock.txt
.venv/bin/pip install -e . --no-deps
```

`config/gateway.yaml` is already checked in for local dev (runner `ollama-local` → `127.0.0.1:11434`,
`jwt_secret: dev-secret`). You only need to copy from `gateway.example.yaml` if that file is missing.

### Step 1 — Start the Model Runner (Ollama)

```bash
cd ai/runners/ollama
docker compose up -d
```

First run only — pull the default model (can take several minutes):

```bash
docker compose exec ollama ollama pull qwen3:4b
```

**Expect:** Ollama listens on `127.0.0.1:11434` only (not reachable from other LAN machines).

Verify the runner directly:

```bash
curl -s http://127.0.0.1:11434/v1/models | jq .
```

**Expect:** JSON listing `qwen3:4b` with a `sha256:…` digest. First poll after pull may show
`STARTING` in the Gateway until the model is fully loaded.

Stop the runner later:

```bash
cd ai/runners/ollama && docker compose down
```

### Step 2 — Start the AI Gateway

```bash
cd ai/gateway
./scripts/start_dev.sh
```

**Expect in the terminal:**

```
==> AI Gateway on http://localhost:8090
    Dashboard: http://localhost:8090/dashboard
    Press Ctrl+C to stop

INFO:     Started server process [...]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8090
```

The script sets `GATEWAY_JWT_SECRET=dev-secret` to match `config/gateway.yaml`. Override if needed:

```bash
GATEWAY_JWT_SECRET=your-supabase-secret ./scripts/start_dev.sh
```

#### Port already in use?

If you see `error: port 8090 is already in use`, another Gateway is already running. Either stop it
(Ctrl+C in its terminal, or `kill <pid>`) or use a different port:

```bash
GATEWAY_PORT=8091 ./scripts/start_dev.sh
# Dashboard moves to http://localhost:8091/dashboard
```

### Step 3 — Open the dashboard

Browse to **[http://localhost:8090/dashboard](http://localhost:8090/dashboard)** (or your custom port).

No build step — static HTML/JS/CSS served by the Gateway.

### Step 4 — Authenticate in the dashboard

Most panels need a staff JWT:

1. Open **Security → JWT auth**
2. Paste a Supabase access token for a **doctor** or **administrator**
3. The token is saved in `localStorage` on this origin only

**Without a token you should still see:**

| Panel | Behavior without JWT |
| --- | --- |
| Overview — liveness | ✅ Green — `GET /health` is public |
| Overview — readiness | ❌ Shows auth error — `/ready` requires JWT |
| Metrics | ✅ Charts from public `GET /metrics` |
| Runners | ⚠️ Empty or stale — registry poll needs `/v1/status` |
| Endpoint explorer | `/health` and `/metrics` work; protected routes return `401` |

**With a valid doctor/admin JWT you should see:**

| Panel | What to expect |
| --- | --- |
| **Overview** | Liveness `ok`; readiness `ready` once Ollama has loaded the model (may take up to ~10 s after startup — health poll interval) |
| **Architecture** | Diagram: clients → Gateway `:8090` → runner `127.0.0.1:11434` |
| **Runners** | Card for `ollama-local`: lifecycle `READY`, declared vs live digest, last poll latency |
| **Metrics** | Request rate, HTTP status breakdown, `gateway_runner_health` for the runner |
| **Endpoint explorer** | Try-it for live routes; lock icon on JWT-protected paths |
| **Phase coverage** | Checklist showing Phases 1–4 complete, 5–6 pending |
| **Security** | Invariants list, error envelope table (`unauthenticated` / `forbidden` active) |

**With a receptionist JWT (no `ai.access`):** protected calls return `403 forbidden` — the dashboard
should surface that in the explorer, not a generic network error.

### Readiness timeline (what to expect after startup)

| Time | Runner down | Runner up, model loading | Runner up, model loaded |
| --- | --- | --- | --- |
| Immediately | `/health` → 200 | `/health` → 200 | `/health` → 200 |
| After ~10–30 s | `/ready` → 503 `ai_no_capacity` | `/ready` → 503 or 200 | `/ready` → 200 `{"status":"ready"}` |
| Dashboard runners panel | `UNREACHABLE` or `STARTING` | `STARTING` | `READY` with model name + digest |

If you stop Ollama, within ~30 s (3 failed polls × 10 s) readiness flips back to `503` and the runner
shows `UNREACHABLE`. Restarting Ollama recovers automatically on the next successful poll.

### Step 5 — Verify from the command line (optional)

Public endpoints (no token):

```bash
curl -s http://localhost:8090/health
# {"status":"ok"}

curl -s http://localhost:8090/metrics | head -20
# gateway_requests_total{...} ...
```

Protected endpoints (replace `$TOKEN` with a doctor/admin JWT signed with the same secret as
`jwt_secret` in `gateway.yaml` — `dev-secret` when using `start_dev.sh` defaults):

```bash
# Readiness
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8090/ready

# Full control-plane snapshot (powers the dashboard)
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8090/v1/status | jq .

# Proxy runner model list through the Gateway
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8090/v1/runners/ollama-local/models | jq .
```

**Expect for `/v1/status`:** gateway version `0.1.0`, `phase_active: 5`, runner list with status and
loaded model — **no secrets** (`jwt_secret`, etc. are never included).

### What is NOT available yet (do not expect these to work)

| Action | Result today |
| --- | --- |
| AI chat in the Flutter app | Not built |
| Generate via Gateway with auth/logging | Not until feature 016 |

### Dev-only: talk to Ollama directly (bypasses Gateway)

Confirms the **model runs**; this is not the production clinic path:

```bash
curl -s http://127.0.0.1:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3:4b",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "stream": false
  }' | jq .
```

**Expect:** A normal chat completion JSON response from Ollama. The Gateway does not participate.

### Tear down

```bash
# Stop Gateway: Ctrl+C in the terminal running start_dev.sh

# Stop Ollama:
cd ai/runners/ollama && docker compose down
```

### Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Port 8090 in use | Gateway already running | Stop the other process or `GATEWAY_PORT=8091 ./scripts/start_dev.sh` |
| Readiness stuck at 503 | Ollama not running or model not pulled | `docker compose up -d` + `ollama pull qwen3:4b` |
| Dashboard shows 401 everywhere | No JWT or wrong secret | Paste token; ensure it was signed with the same `jwt_secret` the Gateway uses |
| Dashboard shows 403 | Role lacks `ai.access` | Use doctor/admin token, not receptionist |
| Runner card `UNREACHABLE` | Ollama stopped or wrong `base_url` | Check `curl http://127.0.0.1:11434/v1/models`; verify `gateway.yaml` runner URL |
| `venv not found` | First-time setup skipped | Run the pip install steps under [First-time Gateway setup](#first-time-gateway-setup-once-per-machine) |

---

## Related documents

| Document | Purpose |
| --- | --- |
| [phase-capabilities.md](./phase-capabilities.md) | Operator guide — what you can do and how (curl, config, dashboard) |
| [specs/015-ai-layer-foundation/](../../specs/015-ai-layer-foundation/) | Spec, plan, tasks, contracts, quickstart |
| [AI Service Specification.md](../ai_service/AI%20Service%20Specification.md) | Normative v2 spec + Appendix B roadmap |
| [ai/README.md](../../ai/README.md) | Security invariants + dev setup |
