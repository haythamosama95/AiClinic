# AiClinic AI Layer

The AI layer is an **isolated control plane** that sits alongside the Flutter client and
Supabase/PostgreSQL backend. It authenticates clinic staff, discovers and health-polls model
runners, routes requests, and reports capabilities — without holding clinic data or database
credentials.

## Components

| Component | Role |
| --- | --- |
| **AI Gateway** (`gateway/`) | FastAPI service on port 8090 — auth, routing, health, capabilities |
| **Gateway dashboard** (`dashboard/`) | Control plane UI at `GET /dashboard` (served by the gateway) |
| **Model Runners** (`runners/`) | Ollama (or any OpenAI-compatible runtime) serving digest-pinned models |
| **Runner console** (`runner-console/`) | Localhost inference playground at port 11435 (operator-only) |

## Security Invariants

These three rules are non-negotiable and enforced mechanically (including an automated isolation
scan that gates CI):

1. **AI proposes only** — The AI layer never writes to the clinic database. All protected writes
   go through Supabase RPC with human approval. This phase ships a stubbed generate endpoint (501).

2. **No clinic-DB credentials** — Nothing under `ai/` may import Postgres drivers, hold
   service-role keys, or reference Supabase connection strings. JWT validation is offline only.

3. **Manual UI works with AI down** — The clinic application MUST remain fully usable when the
   entire AI layer is stopped. AI is strictly additive.

## Quick Start

Start the full stack (Ollama runner, gateway, and runner console) from one script:

```bash
cd ai
./start.sh
```

- Gateway dashboard: http://localhost:8090/dashboard
- Runner console: http://127.0.0.1:11435
- First run bootstraps the gateway Python venv automatically

See `specs/015-ai-layer-foundation/quickstart.md` for the operator runbook.

### Gateway only (development)

```bash
cd ai/gateway

# First time only (use the lock file — avoids slow pip backtracking):
python3.13 -m venv .venv
.venv/bin/pip install -r requirements-dev.lock.txt
.venv/bin/pip install -e . --no-deps

# Every time after that — just run (no reinstall needed):
./scripts/start_dev.sh

# Run lint + tests (CI gate):
./scripts/run_tests.sh
```

If you have [uv](https://github.com/astral-sh/uv), the first-time install is much faster:

```bash
cd ai/gateway && uv venv && uv pip install -r requirements-dev.lock.txt && uv pip install -e . --no-deps
```
