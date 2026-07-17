# AI Control Plane Dashboard

A zero-build static dashboard served by the AI Gateway. It visualizes gateway liveness,
readiness, runner lifecycle, Prometheus metrics, JWT auth state, and the endpoint catalog exposed
by Phases 1–4.

## Prerequisites

- AI Gateway dependencies installed (`ai/gateway/.venv`)
- Local Supabase running when using **Sign in** (see `backend/local/.env` for URL/port)
- Optional: paste a staff JWT manually if sign-in is not configured

## Run locally

```bash
cd ai/gateway
./scripts/start_dev.sh
```

`start_dev.sh` loads `SUPABASE_JWT_SECRET` from `backend/local/.env` when present so
tokens from dashboard sign-in validate against the Gateway.

Open [http://localhost:8090/dashboard](http://localhost:8090/dashboard) in a browser.

### Sign in (automatic)

When `dashboard_auto_sign_in: true` in `gateway.yaml` (enabled in local dev), the dashboard
**signs in as bootstrap admin on load** — no manual step. Tokens are refreshed automatically when
they expire.

You can still use the manual form to sign in as a different user, or **Clear** to reset the token.

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
