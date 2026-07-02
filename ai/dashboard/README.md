# AI Control Plane Dashboard

A zero-build static dashboard served by the AI Gateway. It visualizes gateway liveness,
readiness, runner lifecycle, Prometheus metrics, and the endpoint catalog exposed by Phases 1–3.

## Prerequisites

- AI Gateway dependencies installed (`ai/gateway/.venv`)
- Optional: Ollama runner for live readiness and runner cards (see `ai/README.md`)

## Run locally

```bash
cd ai/gateway
GATEWAY_JWT_SECRET=dev-secret .venv/bin/uvicorn gateway.main:create_app --factory --port 8090
```

Open [http://localhost:8090/dashboard](http://localhost:8090/dashboard) in a browser.

The dashboard polls the gateway on the same origin (no extra CORS setup):

| Source | Purpose |
| --- | --- |
| `GET /v1/status` | Gateway snapshot, safe config, runners, endpoint catalog |
| `GET /health` | Liveness badge |
| `GET /ready` | Readiness badge |
| `GET /metrics` | Prometheus counters for inline charts |

If the `ai/dashboard/` directory is missing, the gateway still runs; only the `/dashboard` static
mount is skipped.

## Layout

| File | Role |
| --- | --- |
| `index.html` | Shell and panel scaffolding |
| `styles.css` | Dark-theme layout (no build step) |
| `app.js` | Polling, charts, endpoint explorer, phase gating |

## Extend per phase

The UI is designed to light up new capabilities without a rewrite. Use this checklist when a phase
lands:

### Phase 4 — Auth

- Add protected routes to the backend `endpoints[]` catalog in `gateway/api/status.py` with
  `available: true` once JWT enforcement ships.
- In `app.js`, enable the **Security** panel auth state when `/ready` or a probe route returns
  `401`/`403` instead of anonymous `200`.
- Grey out or label rows in the endpoint explorer that require `Authorization: Bearer`.

### Phase 5 — Capabilities & generate stub

- When `GET /v1/capabilities` returns `200`, flip its catalog row to `available: true` and render
  the Capabilities panel from the live JSON (runner model, digest, features).
- When `POST /v1/ai/generate` stops returning `501`, mark it available and wire the explorer
  “try it” action to the real stub or inference path.

### Phase 6+ — Multi-runner, streaming, commands

- New runner fields from `registry.snapshot()` appear automatically in `/v1/status` → runner cards.
- Add `PHASES` entries in `app.js` mapping section IDs to minimum `phase_active` or endpoint
  availability checks.
- Prefer extending the backend `endpoints[]` catalog over hard-coding paths in the UI.

## Contract

`GET /v1/status` must never include secrets (`jwt_secret`, `internal_shared_secret`, etc.). Contract
tests live in `ai/gateway/tests/contract/test_status.py`.
