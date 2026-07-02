# AI Layer — Features by Phase

This document describes **what you can do after each implementation phase** of feature
**015-ai-layer-foundation** (Isolated Gateway Spine + Model Runner), and **how to access it**.

Use it as a progress checklist: find your current phase, see what's available, and see what's still
blocked.

> **Current repo state (2026-07-03):** Phases **1–3 are complete**. Phases **4–6 are not yet
> implemented. There is **no AI generation** anywhere in feature 015 — inference arrives in a later
> feature (016 / AI Service Phase 2).

---

## Architecture at a glance

| Component | Default address | Who can reach it |
| --- | --- | --- |
| **AI Gateway** | `http://<server>:8090` | Clinic clients on the LAN (Flutter app, curl, monitoring) |
| **Model Runner (Ollama)** | `http://127.0.0.1:11434` | Gateway only (localhost / AI-internal — **not** client-routable) |

The Gateway is the **only client-facing AI URL**. Runners are polled internally for health and model
discovery; clients never talk to Ollama directly in production.

---

## Phase summary

| Phase | Name | Status | One-line outcome |
| --- | --- | --- | --- |
| 1 | Setup | ✅ Done | Project skeleton, Docker, deps |
| 2 | Foundational | ✅ Done | Config, errors, logs, metrics, app bootstrap |
| 3 | US1 — Health spine (MVP) | ✅ Done | Run a model runner; Gateway reports honest health/readiness |
| 4 | US2 — Auth | ⏳ Pending | JWT + `ai.access` gate on protected endpoints |
| 5 | US3 — Discovery & routing | ⏳ Pending | Capabilities report, routing selection, generate **stub** (501) |
| 6 | Polish | ⏳ Pending | Full observability wiring, CI gate, hardening |

---

## Phase 1 — Setup

**Delivered:** Isolated `ai/` tree, Python Gateway project (`ai/gateway/`), Ollama runner layout
(`ai/runners/ollama/`), Dockerfile, dev tooling (ruff, pytest).

### What you can do

| Action | How |
| --- | --- |
| Inspect the AI layer layout | Read `ai/README.md` |
| Install Gateway dev dependencies | See [Developer setup](#developer-setup) below |
| Build the Gateway Docker image | `docker build -t aiclinic-gateway ai/gateway` |
| Lint the Gateway code | `cd ai/gateway && .venv/bin/ruff check src tests` |

### What you cannot do yet

- Start a useful Gateway process (needs Phase 2 config/bootstrap).
- Health-check or poll runners.

---

## Phase 2 — Foundational

**Delivered:** Typed config with fail-fast validation, uniform error envelope, structured JSON logs
(PHI-redacted by default), Prometheus metrics collectors, ASGI app with CORS allowlist and
`request_id` middleware, test harness.

### What you can do

| Action | How |
| --- | --- |
| Boot the Gateway (minimal) | `GATEWAY_JWT_SECRET=dev-secret .venv/bin/uvicorn gateway.main:create_app --factory --port 8090` |
| Check liveness | `curl -s http://localhost:8090/health` → `{"status":"ok"}` |
| Scrape Prometheus metrics | `curl -s http://localhost:8090/metrics` |
| Validate config keys | Copy `ai/gateway/config/gateway.example.yaml` → `gateway.yaml`; invalid keys fail at startup |
| Inspect structured logs | Logs written under `log_dir` (default `./logs`) as JSON |

### Endpoints available after Phase 2

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| `GET` | `/health` | None | Liveness — always `200` while process is up |
| `GET` | `/metrics` | None | Prometheus text exposition |

### Example: liveness

```bash
curl -s http://localhost:8090/health
# {"status":"ok"}
```

### Example: metrics (partial — full wiring in Phase 6)

```bash
curl -s http://localhost:8090/metrics | head -20
# gateway_requests_total{...}  ...
# gateway_runner_health{...}     ...  (populated once Phase 3 poller runs)
```

### What you cannot do yet

- `/ready` (meaningful readiness — needs runner registry, Phase 3).
- Poll or discover model runners.
- Authenticate callers (Phase 4).
- Call `/v1/capabilities` or `/v1/ai/generate` (Phase 5).

---

## Phase 3 — US1: Isolated, health-reportable AI layer (MVP) ✅ **You are here**

**Delivered:** Runner lifecycle state machine, in-memory registry, OpenAI-compatible poll client,
background health poller, `/ready` endpoint, isolation scan CI gate, Ollama docker-compose +
Modelfile + operator runbook.

### What you can do

| Action | How |
| --- | --- |
| **Run Ollama locally (AI-internal)** | [Start the model runner](#1-start-the-model-runner-ollama) |
| **Pull / load the default model** | `docker compose exec ollama ollama pull qwen3:4b` |
| **Start the Gateway with runner config** | [Configure and start Gateway](#2-configure-the-gateway) |
| **Check liveness** (immediate) | `GET /health` → always `200` |
| **Check readiness** (honest) | `GET /ready` → `200` only when ≥1 runner is `READY` |
| **Verify model discovery** (direct, bypass Gateway) | `curl -s http://127.0.0.1:11434/v1/models \| jq .` |
| **Confirm runner is non-routable** | From another LAN host: `curl http://<server>:11434/v1/models` → connection refused |
| **Run isolation scan** | `cd ai/gateway && .venv/bin/python scripts/isolation_scan.py` |
| **Run full dev/CI gate** | `cd ai/gateway && ./scripts/run_tests.sh` |
| **Observe runner failover** | Stop Ollama → within ~3 polls (~30 s) `/ready` → `503`; restart → recovers |
| **Open control plane dashboard** | Start Gateway → [http://localhost:8090/dashboard](http://localhost:8090/dashboard) (see `ai/dashboard/README.md`) — covers Phases 1–3 checklist, architecture, endpoints, runners, `/v1/models` probe, metrics, and error envelope |

### Endpoints available after Phase 3

| Method | Path | Auth (now) | Auth (after Phase 4) | Description |
| --- | --- | --- | --- | --- |
| `GET` | `/health` | None | None | Liveness |
| `GET` | `/ready` | **None** ⚠️ | JWT + `ai.access` | Readiness — `200` or `503 ai_no_capacity` |
| `GET` | `/metrics` | None | None | Prometheus metrics |

> **Note:** Phase 4 will protect `/ready`. Until then, `/ready` is open (same as `/health` from an
> auth perspective). Plan monitoring accordingly.

### 1. Start the Model Runner (Ollama)

```bash
cd ai/runners/ollama
docker compose up -d
docker compose exec ollama ollama pull qwen3:4b
```

Verify the runner is up and lists the model:

```bash
curl -s http://127.0.0.1:11434/v1/models | jq .
```

Expected shape (OpenAI-compatible):

```json
{
  "object": "list",
  "data": [
    {
      "id": "qwen3:4b",
      "object": "model",
      "digest": "sha256:…",
      "context_length": 8192
    }
  ]
}
```

Pin the digest in `ai/runners/ollama/digests.md` and in Gateway config — see
`ai/runners/README.md`.

Verify non-routability from a client workstation:

```bash
curl -s http://<server-node>:11434/v1/models
# Expected: connection refused (runner bound to 127.0.0.1 only)
```

### 2. Configure the Gateway

```bash
cd ai/gateway
cp config/gateway.example.yaml config/gateway.yaml
```

Minimum `gateway.yaml` for Phase 3:

```yaml
port: 8090
jwt_secret: "${SUPABASE_JWT_SECRET}"   # required to boot; not enforced on /ready until Phase 4
allowed_origins:
  - "http://localhost:3000"
runners:
  - id: runnerA
    base_url: "http://127.0.0.1:11434"
    capabilities: ["json_grammar"]
    models:
      - name: "qwen3:4b"
        source: "qwen3:4b"
        digest: "sha256:REPLACE_WITH_PINNED_DIGEST"
        context_tokens: 8192
        capabilities: ["json_grammar"]
log_dir: "./logs"
log_verbatim: false
health_poll_interval_s: 10
unreachable_after_failures: 3
```

Start the Gateway:

```bash
cd ai/gateway
GATEWAY_JWT_SECRET=dev-secret .venv/bin/uvicorn gateway.main:create_app --factory --host 0.0.0.0 --port 8090
```

Or with Docker:

```bash
docker build -t aiclinic-gateway ai/gateway
docker run -d --name gateway --restart always -p 8090:8090 \
  -e GATEWAY_JWT_SECRET=dev-secret \
  -v "$PWD/ai/gateway/config:/app/config" \
  -v "$PWD/ai/gateway/logs:/app/logs" \
  --network host \
  aiclinic-gateway
```

> Use `--network host` (or equivalent) so the Gateway container can reach `127.0.0.1:11434` on the
> host. Adjust if runner and Gateway share a Docker network instead.

### 3. Verify health and readiness

**Liveness** — works immediately, even before Ollama is up:

```bash
curl -s http://localhost:8090/health
# {"status":"ok"}
```

**Readiness** — depends on the health poller (default every 10 s):

```bash
# While model is loading or runner is down:
curl -s -w "\nHTTP %{http_code}\n" http://localhost:8090/ready
# {
#   "error": {
#     "code": "ai_no_capacity",
#     "message": "No healthy model runners available",
#     "request_id": "…"
#   }
# }
# HTTP 503

# After runner reports a loaded model (status READY):
curl -s -w "\nHTTP %{http_code}\n" http://localhost:8090/ready
# {"status":"ready"}
# HTTP 200
```

**Failover test:**

```bash
docker compose -f ai/runners/ollama/docker-compose.yaml stop ollama
# Wait ~30 s (3 failed polls × 10 s interval)
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8090/ready   # 503

docker compose -f ai/runners/ollama/docker-compose.yaml start ollama
# Wait for model reload + poll
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8090/ready   # 200
```

### 4. Developer / CI verification

```bash
cd ai/gateway
./scripts/run_tests.sh
# ruff check ✓
# isolation_scan.py ✓  (no DB creds/drivers under ai/)
# pytest ✓             (25 tests as of Phase 3)
```

Run isolation scan alone:

```bash
cd ai/gateway
.venv/bin/python scripts/isolation_scan.py
# isolation_scan: PASS (/path/to/ai)
```

### What you cannot do after Phase 3

| Blocked action | Why | Available after |
| --- | --- | --- |
| Generate text / chat via Gateway | No `/v1/ai/generate` yet | Phase 5 (stub 501); real inference in feature 016 |
| List capabilities via Gateway | No `/v1/capabilities` yet | Phase 5 |
| Authenticate with Supabase JWT | Auth gate not wired | Phase 4 |
| Enforce `ai.access` role check | Role map not enforced | Phase 4 |
| Route requests among multiple runners | Selector not implemented | Phase 5 |
| Use AI from Flutter client securely | Client integration + auth pending | Phase 4+ and client feature |

### Direct Ollama inference (dev only, bypasses Gateway)

You can call Ollama's OpenAI-compatible chat API **directly on localhost** for manual testing. This
is **not** the production clinic path and bypasses auth, logging, and routing:

```bash
curl -s http://127.0.0.1:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3:4b",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "stream": false
  }' | jq .
```

This confirms the **model runs**; it does not mean the Gateway AI product path is ready.

---

## Phase 4 — US2: Authenticate and authorize every AI caller ⏳

**Goal:** Offline Supabase JWT validation (HS256 or JWKS) + coarse `ai.access` role gate. Zero
network calls to Supabase.

### What you will be able to do

| Action | How |
| --- | --- |
| Call protected endpoints with a valid staff JWT | `Authorization: Bearer <token>` |
| Get typed `401 unauthenticated` | Missing / tampered / expired / not-yet-valid token |
| Get typed `403 forbidden` | Valid token but role lacks `ai.access` (e.g. receptionist) |
| Use HS256 or JWKS config | `jwt_secret` or `jwks_url` in `gateway.yaml` (JWKS wins if both set) |
| Reload role map without restart | File watch / SIGHUP / periodic re-read of `role_ai_access` |

### Endpoints after Phase 4

| Method | Path | Auth |
| --- | --- | --- |
| `GET` | `/health` | None |
| `GET` | `/metrics` | None |
| `GET` | `/ready` | **JWT + `ai.access`** |
| `GET` | `/v1/capabilities` | JWT + `ai.access` (endpoint added Phase 5) |
| `POST` | `/v1/ai/generate` | JWT + `ai.access` (endpoint added Phase 5) |

### Example commands (once Phase 4 lands)

```bash
TOKEN="<valid Supabase JWT for doctor/admin>"

# Success
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8090/ready

# 401 — no token
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8090/ready

# 401 — bad token
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer tampered.jwt.here" http://localhost:8090/ready

# 403 — valid token, role without ai.access
curl -s -H "Authorization: Bearer $RECEPTIONIST_TOKEN" http://localhost:8090/ready
# {"error":{"code":"forbidden","message":"…","request_id":"…"}}
```

### Still blocked after Phase 4

- Capabilities report, routing, generate stub (Phase 5).
- Actual AI inference (feature 016).

---

## Phase 5 — US3: Discover, monitor, and route among Model Runners ⏳

**Goal:** Full lifecycle tracking, capability→health→least-busy routing selection, live capabilities
mirror, and a **feature-detectable generate stub**.

### What you will be able to do

| Action | How |
| --- | --- |
| **Discover live runner capabilities** | `GET /v1/capabilities` (JWT required) |
| **Feature-detect generation route** | `POST /v1/ai/generate` → always `501 not_implemented` |
| **Observe multi-runner failover** | Registry walks `READY` → `DEGRADED` → `UNREACHABLE` → recovery |
| **Verify routing selection in tests** | Capability match → health filter → least-busy tie-break |

### New endpoints after Phase 5

| Method | Path | Auth | Response |
| --- | --- | --- | --- |
| `GET` | `/v1/capabilities` | JWT + `ai.access` | Live registry mirror; `tasks:[]`, `commands:[]` |
| `POST` | `/v1/ai/generate` | JWT + `ai.access` | `501 not_implemented` — **zero inference** |

### Example: capabilities (once Phase 5 lands)

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8090/v1/capabilities | jq .
```

Expected shape (illustrative):

```json
{
  "runners": [
    {
      "id": "runnerA",
      "status": "READY",
      "model": "qwen3:4b",
      "digest": "sha256:…",
      "context_tokens": 8192,
      "features": ["json_grammar"]
    }
  ],
  "tasks": [],
  "commands": []
}
```

### Example: generate stub

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"hello"}' \
  http://localhost:8090/v1/ai/generate
# 501
# {"error":{"code":"not_implemented","message":"…","request_id":"…"}}
```

### Still blocked after Phase 5

- **Functional AI generation** through the Gateway (prompts, streaming, structured output) — feature
  **016** / AI Service Appendix B Phase 2.
- Flutter client AI features wired end-to-end.

---

## Phase 6 — Polish & cross-cutting ⏳

**Goal:** Complete observability wiring, PHI-redaction proof, optional push registration, security
hardening, full CI gate, quickstart validation.

### What you will be able to do

| Action | How |
| --- | --- |
| Full CI gate (single command) | `cd ai/gateway && ./scripts/run_tests.sh` — ruff + isolation + full pytest |
| Verify PHI never appears verbatim in logs | Automated redaction test (`log_verbatim=false`) |
| Optional push-based runner registration | `enable_push_registration=true` + `internal_shared_secret` |
| End-to-end operator validation | Follow `specs/015-ai-layer-foundation/quickstart.md` acceptance path |

### Additional capabilities

- Per-request and per-runner metrics/log records fully wired across poller and endpoints.
- Push endpoints (AI-internal only, when enabled):
  - `POST /internal/runners/register`
  - `POST /internal/runners/heartbeat`

### Still blocked after Phase 6 (by design)

Feature 015 intentionally delivers the **control plane only**. Even when Phase 6 is complete:

- `POST /v1/ai/generate` returns **501** — no inference.
- Capabilities advertise **no tasks or commands**.
- Clinic Flutter app has **no built-in AI UI** until a separate client feature ships.

Real model inference via the Gateway requires **feature 016** (AI generation layer).

---

## Dashboard coverage (Phases 1–3)

The control plane at `/dashboard` maps to this document:

| Phase | Capability | Dashboard panel |
| --- | --- | --- |
| 1 | Gateway vs runner architecture | **Architecture** |
| 1 | Isolated `ai/` layout | **Phase coverage** checklist |
| 2 | `GET /health` | **Overview** + **Endpoint explorer** |
| 2 | `GET /metrics` | **Metrics** + **Endpoint explorer** |
| 2 | Typed config / CORS / logs | **Security → Safe config** |
| 2 | Error envelope + `X-Request-ID` | **Security → Error envelope** + explorer response headers |
| 3 | `GET /ready` (`ai_no_capacity`) | **Overview** readiness card |
| 3 | Runner registry & lifecycle | **Runners** panel |
| 3 | Health poller / failover timing | **Runners** poller caption |
| 3 | `GET /v1/models` discovery | **Runners → Poll /v1/models** + `GET /v1/runners/{id}/models` in explorer |
| 3 | Digest pinning | Runner card declared vs live digest |
| 3 | `gateway_runner_health` metric | **Metrics → Runner health** chart |
| 3 | Isolation scan | **Phase coverage** (operator runs locally) |

---

## Developer setup

First-time Gateway install:

```bash
cd ai/gateway
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.lock.txt
.venv/bin/pip install -e . --no-deps
```

Every subsequent run:

```bash
cd ai/gateway
GATEWAY_JWT_SECRET=dev-secret .venv/bin/uvicorn gateway.main:create_app --factory --port 8090
```

---

## Error envelope reference

All Gateway failures use a uniform shape (implemented Phase 2; populated by later phases):

```json
{
  "error": {
    "code": "ai_no_capacity",
    "message": "No healthy model runners available",
    "request_id": "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

| Code | HTTP | When |
| --- | --- | --- |
| `bad_request` | 400 | Malformed request |
| `unauthenticated` | 401 | Auth failure (Phase 4+) |
| `forbidden` | 403 | Valid token, no `ai.access` (Phase 4+) |
| `not_implemented` | 501 | Generate stub (Phase 5+) |
| `rate_limited` | 429 | Rate limit exceeded |
| `ai_no_capacity` | 503 | No READY runner (`/ready`, future routing) |
| `ai_timeout` | 504 | Reserved for inference timeouts (feature 016) |

Every response includes an `X-Request-ID` header for log correlation.

---

## Related documents

| Document | Purpose |
| --- | --- |
| `ai/README.md` | AI layer overview and security invariants |
| `ai/runners/README.md` | Model install, GGUF path, digest pinning |
| `specs/015-ai-layer-foundation/quickstart.md` | Operator deploy + verify runbook |
| `specs/015-ai-layer-foundation/tasks.md` | Full task list and phase definitions |
| `docs/ai_service/AI Service Specification.md` | Normative AI service spec (v2) |

---

## Quick reference: "Can I …?" after each phase

| Question | P1–2 | P3 ✅ | P4 | P5 | P6 | Feature 016 |
| --- | --- | --- | --- | --- | --- | --- |
| Boot the Gateway | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `GET /health` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `GET /metrics` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Run Ollama + load a model | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| `GET /ready` (honest) | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| Isolation scan in CI | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| JWT auth on protected routes | — | — | ✅ | ✅ | ✅ | ✅ |
| `GET /v1/capabilities` | — | — | — | ✅ | ✅ | ✅ |
| `POST /v1/ai/generate` (stub) | — | — | — | ✅ | ✅ | ✅ |
| **Real AI generation** | — | — | — | — | — | ✅ |
| Flutter client AI features | — | — | — | — | — | ✅+ |
