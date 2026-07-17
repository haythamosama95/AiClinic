# AI Control Plane Dashboard

A zero-build static dashboard served by the AI Gateway. It visualizes gateway liveness,
readiness, runner lifecycle, Prometheus metrics, JWT auth state, Phase 5 capabilities, and the
endpoint catalog exposed by Phases 1–5.

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
| `GET /v1/capabilities` | Bearer JWT | Phase 5 capabilities mirror (runners, stub tasks/commands) |
| `POST /v1/ai/generate` | Bearer JWT | Phase 5 generate stub probe (expect `501 not_implemented`) |
| `GET /v1/runners/{id}/models` | Bearer JWT | On-demand proxy of runner `GET /v1/models` |

Tokens are stored in `localStorage` (`dashboard_jwt_token`) on this origin only.

## Panels (Phases 1–5)

| Panel | Phase | Maps to `phase-capabilities.md` |
| --- | --- | --- |
| Architecture | 1 | Gateway vs runner addresses, client-routability |
| Overview | 2–4 | `/health`, `/ready` (incl. `ai_no_capacity`, `401` without token) |
| Runners | 3–5 | Registry, lifecycle (incl. `BUSY`), poller timing, `/v1/models` poll |
| Metrics | 2–4 | `/metrics`, request rate, status codes, runner health/latency |
| Endpoint explorer | 2–5 | Try-it for live routes; lock icon marks JWT-protected paths |
| Phase coverage | 1–5 | Live checklist vs `docs/ai/phase-capabilities.md` |
| Security | 1–4 | Invariants, JWT auth, error envelope, safe config |
| Capabilities | 5 | Live `GET /v1/capabilities` — runners, empty `tasks`/`commands` stubs |
| Generate stub | 5 | `POST /v1/ai/generate` test button (501 envelope) |

If the `ai/dashboard/` directory is missing, the gateway still runs; only the `/dashboard` static
mount is skipped.

## Layout

| File | Role |
| --- | --- |
| `index.html` | Shell and panel scaffolding |
| `styles.css` | Dark-theme layout (no build step) |
| `app.js` | Polling, charts, endpoint explorer, JWT token entry, phase gating |

## Extend per phase

### Phase 5 — Capabilities & generate stub (shipped)

- **Capabilities** panel polls `GET /v1/capabilities` when a JWT is present; shows per-runner
  `status`, `model`, `digest`, `features`, `context_tokens`, and stub messaging for empty
  `tasks[]` / `commands[]`.
- **Generate stub** panel POSTs a minimal body to `/v1/ai/generate` and displays the
  `501 not_implemented` envelope.
- Lifecycle rail includes **BUSY**; runner cards use a distinct busy badge.
- Phase 5 endpoints unlock in the explorer when `/v1/capabilities` responds `200`.

## Contract

`GET /v1/status` must never include secrets (`jwt_secret`, `internal_shared_secret`, etc.). Contract
tests live in `ai/gateway/tests/contract/test_status.py`.
