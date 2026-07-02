# AiClinic AI Layer

The AI layer is an **isolated control plane** that sits alongside the Flutter client and
Supabase/PostgreSQL backend. It authenticates clinic staff, discovers and health-polls model
runners, routes requests, and reports capabilities — without holding clinic data or database
credentials.

## Components

| Component | Role |
| --- | --- |
| **AI Gateway** (`gateway/`) | FastAPI service on port 8090 — auth, routing, health, capabilities |
| **Model Runners** (`runners/`) | Ollama (or any OpenAI-compatible runtime) serving digest-pinned models |

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

See `specs/015-ai-layer-foundation/quickstart.md` for the operator runbook.

```bash
cd ai/gateway

# First time only (use the lock file — avoids slow pip backtracking):
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.lock.txt
.venv/bin/pip install -e . --no-deps

# Every time after that — just run (no reinstall needed):
GATEWAY_JWT_SECRET=dev-secret .venv/bin/uvicorn gateway.main:create_app --factory --port 8090

# Run lint + tests (CI gate):
./scripts/run_tests.sh
```

If you have [uv](https://github.com/astral-sh/uv), the first-time install is much faster:

```bash
cd ai/gateway && uv venv && uv pip install -r requirements-dev.lock.txt && uv pip install -e . --no-deps
```
