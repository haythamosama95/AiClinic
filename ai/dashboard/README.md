# AI Control Plane Dashboard

A zero-build static dashboard served by the AI Gateway. It visualizes gateway liveness,
readiness, runner lifecycle, Prometheus metrics, JWT auth state, and the endpoint catalog exposed
by Phases 1–4.

## Prerequisites

- AI Gateway dependencies installed (`ai/gateway/.venv`)
- A Supabase staff JWT with `ai.access` (doctor or administrator) for protected API polls
- Optional: Ollama runner for live readiness and runner cards (see `ai/README.md`)

## Run locally

```bash
cd ai/gateway
GATEWAY_JWT_SECRET=dev-secret .venv/bin/uvicorn gateway.main:create_app --factory --port 8090
```

Open [http://localhost:8090/dashboard](http://localhost:8090/dashboard) in a browser.

Paste a staff JWT under **Security → JWT auth** so the dashboard can poll `/v1/status`, `/ready`,
and runner probe routes. `/health` and `/metrics` remain unauthenticated.

The dashboard polls the gateway on the same origin (no extra CORS setup):

| Source | Auth | Purpose |
| --- | --- | --- |
| `GET /health` | None | Liveness badge |
| `GET /metrics` | None | Charts |
| `GET /v1/status` | Bearer JWT | Gateway snapshot, safe config, runners, endpoint catalog |
| `GET /ready` | Bearer JWT | Readiness badge |
| `GET /v1/runners/{id}/models` | Bearer JWT | On-demand proxy of runner `GET /v1/models` |

Tokens are stored in `localStorage` (`dashboard_jwt_token`) on this origin only.

## Panels (Phases 1–4)

| Panel | Phase | Maps to `phase-capabilities.md` |
| --- | --- | --- |
| Architecture | 1 | Gateway vs runner addresses, client-routability |
| Overview | 2–4 | `/health`, `/ready` (incl. `ai_no_capacity`, `401` without token) |
| Runners | 3–4 | Registry, lifecycle, poller timing, `/v1/models` poll |
| Metrics | 2–4 | `/metrics`, request rate, status codes, runner health/latency |
| Endpoint explorer | 2–4 | Try-it for live routes; lock icon marks JWT-protected paths |
| Phase coverage | 1–4 | Live checklist vs `docs/ai/phase-capabilities.md` |
| Security | 1–4 | Invariants, JWT auth, error envelope, safe config |

If the `ai/dashboard/` directory is missing, the gateway still runs; only the `/dashboard` static
mount is skipped.

## Layout

| File | Role |
| --- | --- |
| `index.html` | Shell and panel scaffolding |
| `styles.css` | Dark-theme layout (no build step) |
| `app.js` | Polling, charts, endpoint explorer, JWT token entry, phase gating |

## Extend per phase

### Phase 4 — Auth (shipped)

- Protected routes send `Authorization: Bearer` when a token is saved in **Security → JWT auth**.
- Error envelope table marks `unauthenticated` and `forbidden` as active.
- Anonymous `GET /ready` returns `401` when auth is enforced.

### Phase 5 — Capabilities & generate stub

- When `GET /v1/capabilities` returns `200`, render the Capabilities panel from live JSON.
- Wire `POST /v1/ai/generate` in the endpoint explorer when the stub is available.

## Contract

`GET /v1/status` must never include secrets (`jwt_secret`, `internal_shared_secret`, etc.). Contract
tests live in `ai/gateway/tests/contract/test_status.py`.
