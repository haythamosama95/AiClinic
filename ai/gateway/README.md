# AI Gateway

The AI Gateway is the **client-facing control plane** for the AiClinic AI layer. It authenticates
clinic staff, discovers and health-polls model runners, routes generation requests through a
resilience pipeline, and returns **proposal-only** Command Protocol envelopes — without holding
clinic database credentials or calling Supabase.

**Phase 2 (feature 016)** replaces the Phase 1 generate stub with a real scheduling agent backed
by grammar-constrained decoding, schema and semantic validation, non-streaming and SSE streaming
responses, and a production-robust resilience envelope.

See `specs/016-ai-generation-scheduling/quickstart.md` for the end-to-end operator runbook.

## Quick start

```bash
cd ai/gateway

# First time only:
python3.13 -m venv .venv
.venv/bin/pip install -r requirements-dev.lock.txt
.venv/bin/pip install -e . --no-deps

# Copy and edit config (runners, JWT material, CORS):
cp config/gateway.example.yaml config/gateway.yaml

# Start (serves the control-plane dashboard at /dashboard):
./scripts/start_dev.sh
```

Or start the full AI stack (Ollama + gateway + runner console) from `ai/start.sh`.

| URL | Purpose |
| --- | --- |
| `http://localhost:8090/health` | Liveness (no auth) |
| `http://localhost:8090/ready` | Readiness — ≥ 1 runner READY |
| `http://localhost:8090/v1/capabilities` | Advertised tasks, commands, runners |
| `http://localhost:8090/v1/ai/generate` | Scheduling generation (non-stream + SSE) |
| `http://localhost:8090/metrics` | Prometheus metrics (no auth) |
| `http://localhost:8090/dashboard` | Operator control-plane UI |

## Client API (Phase 2)

OpenAPI contract: `config/openapi.yaml` (source spec:
`specs/016-ai-generation-scheduling/contracts/gateway-openapi.yaml`).

### `POST /v1/ai/generate`

Real scheduling generation. Requires `Authorization: Bearer <Supabase JWT>` with `ai.access`.

**Request** — `task` must be `"command"` this phase; `prompt` ≤ 8 KB; optional `context`
(branch, `now`, active patient, doctors list). Streaming is negotiated via
`options.stream` (not `Accept`):

```json
{
  "task": "command",
  "prompt": "book Ahmed Hassan with Dr Ali tomorrow 5pm",
  "context": {
    "branch_name": "Main",
    "now": "2026-07-18T09:00:00+03:00",
    "active_patient": { "name": "Ahmed Hassan" },
    "doctors": [ { "name": "Dr. Ali" } ]
  },
  "options": { "stream": false }
}
```

**Non-streaming** (`options.stream=false`, or `stream=true` while `streaming_enabled=false`)
→ `200 application/json` with the Command Protocol envelope:

```json
{
  "schema_version": "1.0",
  "task": "command",
  "command_type": "create_appointment",
  "confidence": 0.9,
  "display_summary": "Book Ahmed Hassan with Dr. Ali tomorrow at 5:00 PM.",
  "params": {
    "patient_name": "Ahmed Hassan",
    "doctor_name": "Dr. Ali",
    "date": "2026-07-19",
    "time": "17:00",
    "type": "planned"
  },
  "requires_resolution": {
    "patient_id": "lookup_required",
    "doctor_id": "lookup_required"
  },
  "warnings": [],
  "needs_clarification": false
}
```

**Streaming** (`options.stream=true` and `streaming_enabled=true`) → `200 text/event-stream`.
Event types: `summary` (optional, zero or more), `final` (exactly one on success), `error`
(exactly one on failure). For `task="command"`, `token` events are never emitted. The `final`
event body matches the non-streaming envelope byte-for-byte (SC-002).

```
event: summary
data: {"delta":"Looking up tomorrow's availability..."}

event: final
data: { ...Command Protocol envelope... }
```

**Errors** — typed `error` envelope per `specs/016-ai-generation-scheduling/contracts/error-contract.md`.
On streams, failures are a terminal `error` SSE event with the same JSON body.

| HTTP | Code | When |
| --- | --- | --- |
| 400 | `bad_request` | Malformed or oversized input |
| 401 | `unauthenticated` | Missing/invalid/expired JWT |
| 403 | `forbidden` | Role lacks `ai.access` |
| 422 | `ai_unusable` | Schema/semantic validation failed (not retried) |
| 429 | `rate_limited` | Per-caller in-flight cap exceeded |
| 503 | `ai_busy` | Queue full or wait timeout (`Retry-After` header) |
| 503 | `ai_no_capacity` | No READY runner after swap attempt |
| 504 | `ai_timeout` | First-token, total, or model-swap timeout |

### `GET /v1/capabilities`

Extended in Phase 2 to advertise streaming, the `command` task, and four scheduling command types:

```json
{
  "schema_version": "1.0",
  "streaming": true,
  "tasks": ["command"],
  "commands": [
    "create_appointment",
    "reschedule_appointment",
    "cancel_appointment",
    "update_appointment_status"
  ],
  "runners": [
    {
      "id": "ollama-local",
      "model": "qwen3:4b",
      "digest": "sha256:…",
      "status": "READY",
      "features": ["json_grammar"],
      "context_tokens": 8192
    }
  ]
}
```

`streaming` reflects `streaming_enabled` config. `runners[]` mirrors the live registry (Phase 1
shape unchanged).

### Unchanged from Phase 1

| Endpoint | Notes |
| --- | --- |
| `GET /health` | Liveness — no auth |
| `GET /ready` | Readiness — JWT required |
| `GET /metrics` | Prometheus exposition — no auth |

## Scheduling agent

The scheduling agent (`agents/scheduling/`) is the only in-scope agent this phase:

- **Immutable server-side system prompt** with delimited untrusted user/context regions
- **Grammar-constrained decoding** via Ollama `format: <json_schema>` (`grammar.py`)
- **Schema validation** (`validation/schema_check.py`) and **semantic validation**
  (`agents/scheduling/validators.py` — no past dates, legal enums, summary matches params)
- **Command catalog allowlist** — only the four scheduling `command_type` values are accepted
- **Proposal-only** — entity ids are never fabricated; `requires_resolution` carries
  `"lookup_required"` directives for the Phase 3 client to resolve

Contracts: `specs/016-ai-generation-scheduling/contracts/command-protocol.md`,
`scheduling-schema.md`.

## Resilience envelope

Generation requests pass through an in-process pipeline (`pipeline/`):

| Module | Responsibility |
| --- | --- |
| `queue.py` | Bounded FIFO per capability class; `503 ai_busy` + `Retry-After` backpressure; per-caller in-flight cap |
| `timeout.py` | First-token, total, and model-swap first-token timeouts |
| `retry.py` | Single idempotent retry preferring a different healthy runner (never after partial stream; never on `422`) |
| `cancel.py` | Client disconnect frees queue slot; logged `outcome=cancelled` |
| `swap.py` | Auto-trigger model swap when no READY runner advertises the required capability |

Graceful shutdown: SIGTERM handler drains in-flight work within `shutdown_grace_s` (default 10 s).

## Observability

| Signal | Location | Notes |
| --- | --- | --- |
| Structured JSON logs | `log_dir` (default `./logs`) | PHI-redacted by default via `obs/redaction.py` |
| Verbatim mode | `log_verbatim=true` | Opt-in full prompt/context logging; `log_verbatim_retention_hours` (default 24 h) |
| Prometheus metrics | `GET /metrics` | Queue depth, first-token/total latencies, token counts, outcome, model+digest |
| Generation fields | `obs/logging.py` | `agent`, `model`, `digest`, `queue_wait_seconds`, `outcome`, `retried`, etc. |

Nothing is persisted to the clinic database.

## Configuration

All keys are documented in `config/gateway.example.yaml`. Copy to `config/gateway.yaml` and
adjust. Environment overrides use the `GATEWAY_` prefix (e.g. `GATEWAY_JWT_SECRET`,
`GATEWAY_STREAMING_ENABLED`).

### Phase 2 keys (generation pipeline)

| Key | Default | Purpose |
| --- | --- | --- |
| `queue_max_depth` | 16 | Max queued requests per capability class |
| `queue_max_wait_s` | 20 | Max time a request waits in queue |
| `max_inflight_per_caller` | 2 | Per-caller concurrent generation cap |
| `timeout_total_s` | 45 | Total inference timeout |
| `timeout_first_token_s` | 15 | First-token timeout |
| `model_swap_first_token_timeout_s` | 60 | Extended first-token window during model swap |
| `confidence_threshold` | 0.6 | Below this, `needs_clarification=true` |
| `shutdown_grace_s` | 10 | SIGTERM drain window |
| `streaming_enabled` | true | When false, `options.stream=true` silently serves non-streaming path |
| `log_verbatim_retention_hours` | 24 | Retention for verbatim log files when enabled |
| `enable_multi_command_plans` | false | Reserved — single-command envelopes only this phase |
| `models_dir` | null | Operator reference path for model artifacts (see `ai/runners/README.md`) |

Phase 1 keys (`port`, `runners`, `jwt_secret`/`jwks_url`, `allowed_origins`, `health_poll_interval_s`,
`role_ai_access`, `log_dir`, etc.) are unchanged.

At least one of `jwt_secret` or `jwks_url` must be set. CORS `allowed_origins` must not contain
`*`.

## Security invariants

1. **AI proposes only** — returns Command Protocol envelopes; never writes to the clinic DB.
2. **No clinic-DB credentials** — no Supabase SDK, Postgres driver, or service-role key in
   `ai/`. Enforced by `scripts/isolation_scan.py` (CI gate).
3. **Manual UI works with AI down** — the clinic app remains fully usable when the Gateway is
   stopped.

## Development

```bash
# Lint + full test suite (CI gate):
./scripts/run_tests.sh

# Isolation scan only:
python scripts/isolation_scan.py

# Contract tests for generation:
pytest tests/contract/generate_non_stream.py tests/contract/generate_stream.py -v
```

## Deployment

### Docker Compose

```bash
cd ai/gateway
cp config/gateway.example.yaml config/gateway.yaml   # edit runners + JWT
docker compose up -d
```

Mounts `config/` read-only and persists logs to the `gateway_logs` volume. Pipeline and
streaming settings live in `gateway.yaml` (see `gateway.example.yaml`); optional env overrides:
`GATEWAY_LOG_VERBATIM`, `GATEWAY_LOG_VERBATIM_RETENTION_HOURS`, `GATEWAY_STREAMING_ENABLED`.

### Docker image

Build context is `ai/` (parent directory):

```bash
docker build -f gateway/Dockerfile -t aiclinic-gateway ai/
```

## Related docs

| Document | Purpose |
| --- | --- |
| `specs/016-ai-generation-scheduling/quickstart.md` | End-to-end verification runbook |
| `specs/016-ai-generation-scheduling/contracts/` | Command protocol, error contract, OpenAPI |
| `config/openapi.yaml` | Machine-readable client API contract |
| `ai/README.md` | AI layer overview and security invariants |
| `ai/runners/README.md` | Model runner install, digest pinning, model swap |
