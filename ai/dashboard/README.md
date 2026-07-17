# AI Gateway Signal Monitor

Zero-build static dashboard served by the AI Gateway at `/dashboard`. Operators use it
to watch gateway health, runner registry, Prometheus metrics, and **live trace traffic**
between clients, the gateway, and Ollama runners.

## Prerequisites

- AI Gateway dependencies (`ai/gateway/.venv`)
- Local Supabase when using dashboard sign-in (`backend/local/.env`)
- Or paste a staff JWT with `ai.access` manually

## Run locally

```bash
cd ai/gateway
./scripts/start_dev.sh
```

Open [http://localhost:8090/dashboard](http://localhost:8090/dashboard).

With `dashboard_auto_sign_in: true` in `gateway.yaml`, the dashboard signs in on load.
Tokens are stored in `localStorage` on this origin only.

## Panels

| Panel | Endpoint(s) | Auth |
| --- | --- | --- |
| System strip | `/health`, `/ready`, uptime from `/v1/status` | JWT for `/ready` |
| **Live trace** | `GET /v1/trace/stream` (fetch + Bearer), `/v1/trace/events` | JWT |
| Runner registry | `/v1/status` runners + poller config | JWT |
| Capabilities | `GET /v1/capabilities` | JWT |
| Metrics | `GET /metrics` | None |
| Endpoint workbench | Any catalog route | JWT when required |
| Generate stub | `POST /v1/ai/generate` | JWT |
| Runner models | `GET /v1/runners/{id}/models` | JWT |
| Dashboard auth | `/v1/dashboard/sign-in`, token paste | Mixed |
| Security snapshot | `/v1/status` `config_safe` | JWT |

## Live trace

The trace panel connects via **fetch streaming** (not `EventSource`) so the Bearer JWT
is sent on every stream request. Health poller `GET /v1/models` calls appear as
`gateway_to_runner` / `runner_to_gateway` with `kind: poll`. Dashboard proxy calls use
`kind: proxy`. Client API traffic on `/v1/*` plus `/health`, `/ready`, and `/metrics` appears as
`client_to_gateway` / `gateway_to_client`.

Filter chips map to query params on `/v1/trace/stream` and `/v1/trace/events`.
Bodies are PHI-redacted using the same rules as structured logs.

## Files

| File | Role |
| --- | --- |
| `index.html` | Panel shell |
| `styles.css` | Oscilloscope-inspired layout (no build step) |
| `app.js` | Polling, auth, trace stream, workbench |

## Contract tests

```bash
cd ai/gateway
.venv/bin/pytest tests/contract/test_status.py tests/contract/test_trace.py -q
```
