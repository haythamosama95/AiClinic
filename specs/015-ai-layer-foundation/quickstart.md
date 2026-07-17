# Quickstart: AI Layer Foundation (015)

Stand up and verify the AI control plane on a single clinic server node. This covers the **operator**
happy path (deploy + verify) and the **developer** loop (run + test). No AI generation happens in this
phase — the goal is a healthy, isolated, observable, discoverable Gateway + one Model Runner.

> Target: single-node default (Gateway + one Ollama runner co-located). CPU-only, trusted LAN.

## 0. Prerequisites

- Docker + Docker Compose (Linux) — or Python 3.12 + Ollama installed directly (dev).
- The Supabase **JWT secret** (HS256) for the clinic, OR a **JWKS URL** if Supabase is off-LAN.
- ~4 GB free RAM for the default model (Qwen3-4B Q4_K_M).

## 1. Start the Model Runner (Ollama)

```bash
cd ai/runners/ollama
# Ollama bound to 127.0.0.1:11434 (AI-internal only), restart: always
docker compose up -d
# Pull the digest-pinned default model (see digests.md for the pinned sha256)
docker compose exec ollama ollama pull qwen3:4b
```

Verify the runner is OpenAI-compatible and NOT client-routable:

```bash
curl -s http://127.0.0.1:11434/v1/models | jq .          # lists qwen3:4b + digest
# From another (client) host on the LAN, this MUST fail/refuse:
curl -s http://SERVER_NODE:11434/v1/models               # expected: connection refused
```

## 2. Configure the Gateway

```bash
cd ai/gateway
cp config/gateway.example.yaml config/gateway.yaml
```

Edit `config/gateway.yaml` — minimum to boot:

```yaml
port: 8090
# Exactly one auth mechanism (JWKS takes precedence if both are set):
jwt_secret: "${SUPABASE_JWT_SECRET}"     # on-LAN default (HS256)
# jwks_url: "https://<supabase-host>/auth/v1/.well-known/jwks.json"   # off-LAN alternative
allowed_origins:
  - "http://localhost"                    # add real Flutter client origins; NEVER "*"
role_ai_access:
  administrator: true
  doctor: true
  receptionist: false
  lab_staff: false
runners:
  - id: runnerA
    base_url: "http://127.0.0.1:11434"
    capabilities: ["json_grammar"]
    models:
      - name: "qwen3:4b"
        source: "qwen3:4b"
        digest: "sha256:<pinned>"
        context_tokens: 8192
        capabilities: ["json_grammar"]
log_dir: "./logs"
log_verbatim: false                       # PHI-minimized logs (keep false in production)
```

Invalid config fails fast at startup with a message naming the offending key (FR-004).

## 3. Start the Gateway

```bash
# Docker (build context is ai/, not ai/gateway):
docker build -t aiclinic-gateway -f ai/gateway/Dockerfile ai
docker run -d --name gateway --restart always -p 8090:8090 \
  -e GATEWAY_JWT_SECRET=... \
  -v "$PWD/ai/gateway/config:/app/config:ro" \
  -v gateway_logs:/var/log/gateway \
  aiclinic-gateway

# Or supervised compose from ai/gateway:
cd ai/gateway && docker compose up -d

# Dev (direct — uses local venv; see scripts/start_dev.sh):
cd ai/gateway
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.lock.txt
.venv/bin/pip install -e . --no-deps
./scripts/start_dev.sh
# equivalent: .venv/bin/uvicorn gateway.main:create_app --factory --host 0.0.0.0 --port 8090
```

## 4. Verify (operator acceptance)

```bash
# Liveness (no auth):
curl -s http://SERVER_NODE:8090/health           # {"status":"ok"}

# Readiness (auth required) — positive only once the model is loaded:
TOKEN="<a valid Supabase JWT for a doctor/admin>"
curl -s -H "Authorization: Bearer $TOKEN" http://SERVER_NODE:8090/ready
#   {"status":"ready"}                 once runnerA is READY
#   503 ai_no_capacity                 while the model is still STARTING

# Capabilities mirror the live registry (tasks/commands empty this phase):
curl -s -H "Authorization: Bearer $TOKEN" http://SERVER_NODE:8090/v1/capabilities | jq .

# Generate is a stub (feature-detect only):
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Authorization: Bearer $TOKEN" http://SERVER_NODE:8090/v1/ai/generate    # 501

# Metrics:
curl -s http://SERVER_NODE:8090/metrics | head
```

### Auth smoke checks

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://SERVER_NODE:8090/ready                       # 401 (no token)
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer tampered.jwt.here" \
  http://SERVER_NODE:8090/ready                                                              # 401
# A valid token whose role lacks ai.access (e.g. receptionist):                              # 403
```

### Failover check

```bash
# Stop the runner; within ~3 polls (~30 s) it goes UNREACHABLE and /ready flips to 503:
docker compose -f ai/runners/ollama/docker-compose.yaml stop ollama
# Restart it; /ready returns to 200 automatically (no operator action):
docker compose -f ai/runners/ollama/docker-compose.yaml start ollama
```

## 5. Verify (developer / CI)

```bash
cd ai/gateway
./scripts/run_tests.sh
# runs: ruff check, isolation_scan.py, pytest -q
# (auth matrix, registry/lifecycle/failover, capabilities, error contract,
#  runner contract, config validation, PHI-redaction)
```

## Success signals (maps to spec Success Criteria)

- `/health` green; `/ready` honest (positive only with a READY runner) — SC-002.
- Runner down → UNREACHABLE within 3 polls → `/ready` 503; restart recovers automatically — SC-003.
- Auth matrix passes under both HS256 and JWKS configs, zero Supabase network calls — SC-004/SC-010.
- Isolation scan green (build gate) — SC-005.
- Capabilities mirrors registry (with empty tasks/commands) — SC-006/SC-011.
- Runner unreachable from client subnet; one model resident during swap — SC-008.
- With `log_verbatim=false`, logs contain no verbatim PHI; `/metrics` reports request/error/latency — SC-012.
- Manual clinic UI keeps working with the whole AI layer stopped — SC-007.
