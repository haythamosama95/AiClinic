# Web Services Capability Matrix

**Branch:** `ai/015-ai-layer-foundation`  
**Audience:** Parallel UI agents building the **new gateway dashboard** and **new runner console**  
**Scope:** Audit-only reference — no UI implementation in this file  
**Sources audited:** `ai/gateway/src/gateway/api/*`, `main.py`, routing (`registry`, `health_poller`, `selector`, `lifecycle`), `internal_runners`, `ai/runners/scripts/console_server.py`, `ai/dashboard/*`, `ai/runner-console/*`, `docs/ai/gateway-runner-interaction.md`, `docs/ai/phase-capabilities.md`, `docs/ai/implementation-status.md`

---

## 1. Executive summary

| Surface | Base URL | Auth model | Primary data sources |
| --- | --- | --- | --- |
| **AI Gateway API** | `http://<host>:8090` | Public liveness/metrics; JWT + `ai.access` on control plane; `X-Internal-Secret` on push endpoints | In-memory `RunnerRegistry`, `HealthPoller`, Prometheus, Supabase (sign-in only) |
| **Gateway dashboard (static)** | `GET /dashboard` (same origin) | UI stores staff JWT in `localStorage`; polls gateway APIs | Same as gateway API |
| **Runner console server** | `http://127.0.0.1:11435` | Localhost only; no JWT on Ollama proxy; gateway JWT optional for gateway proxies | Ollama `:11434`, `ollama_compose.sh`, gateway `:8090` via proxy |
| **Ollama (upstream)** | `http://127.0.0.1:11434` | None (localhost bind) | Docker compose / Ollama process |

**Routing spine (gateway → runner, not HTTP-exposed):**

- **Registry** (`RunnerRegistry`): thread-safe in-memory entries from `gateway.yaml` and optional push registration.
- **Health poller** (`HealthPoller`): background `GET {base_url}/v1/models` every `health_poll_interval_s` (default 10s); updates status via `lifecycle.transition`.
- **Selector** (`RunnerSelector`): capability match → READY/DEGRADED → least-busy + round-robin. **No HTTP endpoint today** — used only when generation routing ships (feature 016).
- **Push mode** (`internal_runners`): `POST /internal/runners/register` + `heartbeat` when `enable_push_registration: true`.

**Critical gap for both new UIs:** there is **no live gateway↔runner trace stream**. Poll activity is logged to `gateway.jsonl` (`endpoint=/internal/health-poll`) and reflected indirectly via `/v1/status` + `/metrics` polling.

---

## 2. Gateway capability matrix (MUST expose in new dashboard)

All paths are on the gateway process (`ai/gateway`). **Suggested UI panel** names align with the current `ai/dashboard/` panels so agents can migrate or redesign consistently.

| Endpoint | Method | Auth | Data source | Response highlights | Suggested UI panel |
| --- | --- | --- | --- | --- | --- |
| `/health` | GET | **None** | Process liveness | `{"status":"ok"}` always 200 | **Overview** — liveness card |
| `/metrics` | GET | **None** | Prometheus (`gateway.obs.metrics`) | `gateway_requests_total`, `gateway_errors_total`, `gateway_runner_health`, `gateway_runner_poll_latency_seconds`, `gateway_inflight_requests` | **Metrics** — charts; **Observability** — scrape status |
| `/ready` | GET | **Bearer JWT** + role `ai.access` | `RunnerRegistry.ready` | 200 `{"status":"ready"}` or 503 `ai_no_capacity` | **Overview** — readiness badge |
| `/v1/status` | GET | **Bearer JWT** + `ai.access` | Registry snapshot + safe config + endpoint catalog | `gateway`, `architecture`, `poller`, `config_safe`, `runners[]`, `endpoints[]` | **Overview**, **Architecture**, **Runners**, **Security** (safe config), **Endpoint explorer** (catalog source) |
| `/v1/capabilities` | GET | **Bearer JWT** + `ai.access` | `build_capabilities_report(registry, config)` | `schema_version`, `streaming`, `tasks[]`, `commands[]`, `runners[]` (id, status, model, digest, features, context_tokens) | **Capabilities** panel |
| `/v1/ai/generate` | POST | **Bearer JWT** + `ai.access` | Stub only | 501 `not_implemented` — no inference | **Generate stub** probe |
| `/v1/runners/{runner_id}/models` | GET | **Bearer JWT** + `ai.access` | Live `httpx` proxy to runner `GET /v1/models` | Envelope: `runner_id`, `upstream`, `poll.latency_ms`, `poll.http_status`, `body` | **Runners** — per-card “Poll /v1/models”; **Endpoint explorer** |
| `/v1/dashboard/auth-config` | GET | **None** | `GatewayConfig` | `sign_in_enabled`, `auto_sign_in`, `default_username`, `supabase_url` | **Security → Auth** — bootstrap hints (internal poll; optional explorer row) |
| `/v1/dashboard/sign-in` | POST | **None** (body: username/password) | Supabase `auth/v1/token` via `httpx` | `access_token`, `expires_in`, `staff_role`, `has_ai_access` | **Security → Auth** — sign-in form |
| `/v1/dashboard/auto-sign-in` | POST | **None** | Gateway dev credentials | Same as sign-in | **Security → Auth** — auto bootstrap |
| `/dashboard` | GET | **None** (static) | `ai/dashboard/` mount | HTML/JS/CSS | Shell (self) |
| `/internal/runners/register` | POST | **`X-Internal-Secret`** + push mode enabled; **blocked from browser `Origin`** | `RunnerRegistry.register_runner` | `{"registered":true,"id":...}` | **Push registration** — informational only (not browser-callable) |
| `/internal/runners/heartbeat` | POST | **`X-Internal-Secret`** + push mode enabled; **blocked from browser `Origin`** | `RunnerRegistry.apply_heartbeat` | `{"acknowledged":true,"id":...}` | **Push registration** — informational only |

### 2.1 Auth matrix (gateway)

| Caller | `/health`, `/metrics`, `/v1/dashboard/*` | `/ready`, `/v1/*` protected | `/internal/runners/*` |
| --- | --- | --- | --- |
| Unauthenticated browser | ✅ | 401 `unauthenticated` | 401 or not mounted |
| Valid JWT, no `ai.access` (e.g. receptionist) | ✅ | 403 `forbidden` | N/A |
| Valid JWT + `ai.access` (doctor/admin) | ✅ | ✅ | N/A (wrong auth scheme) |
| AI-internal agent + secret | N/A | N/A | ✅ when `enable_push_registration: true` |

JWT validation is **offline** (`JwtValidator` + `RoleMapStore`); `require_ai_access` sets `request.state.caller_staff_id`.

### 2.2 Registry fields exposed via `/v1/status` (per runner)

| Field | Source | UI use |
| --- | --- | --- |
| `id`, `base_url` | Config / push | Runner card header |
| `status` | Poller + lifecycle | Lifecycle rail, badges (`UNKNOWN`…`UNREACHABLE`, incl. `BUSY`) |
| `last_seen_at`, `last_latency_ms`, `avg_latency_ms` | Poller | Latency columns, charts fallback |
| `consecutive_failures` | Lifecycle | Failover / warn styling |
| `in_flight` | Registry (future routing) | BUSY / inflight charts |
| `declared_capabilities`, `declared_models` | Config | Chips, digest pin compare |
| `loaded_model` | Poller discovery | Live model name, digest, context, features |

### 2.3 Internal / non-HTTP capabilities (dashboard should document, not call)

| Component | Behavior | Dashboard treatment |
| --- | --- | --- |
| `HealthPoller` | `poll_runner()` → `GET /v1/models` | **Runners** poller caption; future **Live trace** panel |
| `lifecycle.transition` | Maps `PollOutcome` + failures → `RunnerStatus` | Lifecycle rail |
| `RunnerSelector` | Not wired to HTTP yet | **Phase coverage** static row / routing preview |
| Observability middleware | `X-Request-ID`, `log_record`, `record_request` | **Security** — correlation ID in explorer responses |
| `RoleMapReloader` | Reloads `role_ai_access.yaml` every 60s | **Security** checklist hint |

---

## 3. Runner console capability matrix (MUST expose in new runner console)

Server: `ai/runners/scripts/console_server.py` on `127.0.0.1:11435` (env: `RUNNER_CONSOLE_HOST`, `RUNNER_CONSOLE_PORT`).

### 3.1 First-party console endpoints

| Endpoint | Method | Auth | Data source | Response / behavior | Suggested UI panel |
| --- | --- | --- | --- | --- | --- |
| `/api/runtime` | GET | **None** (localhost) | `ollama_compose.sh` + `GET {OLLAMA}/v1/models` | `ollama_online`, `ollama_url`, `gpu_enabled`, `gpu_available`, `processor`, `loaded_model`, `loaded_models[]` | **Compute runtime** |
| `/api/runtime/gpu` | POST | **None** | `ollama_compose.sh set-gpu`, `down`, `up` | Restarts Ollama; `{ok, message, ...runtime fields}` | **Compute runtime** — GPU toggle |
| `/api/gateway/capabilities` | GET | **Optional** `Authorization: Bearer` (forwarded) | Proxy → gateway `GET /v1/capabilities` | Gateway JSON or 502 if gateway down | **Gateway discovery** — live mirror |
| `/api/gateway/status` | GET | **Optional** Bearer (forwarded) | Proxy → gateway `GET /v1/status` | Full status snapshot | **Gateway observability** |
| `/api/gateway/metrics` | GET | **Optional** Bearer (forwarded) | Proxy → gateway `GET /metrics` | Prometheus text | **Gateway observability** — per-runner metrics snippet |
| `/api/gateway/auto-sign-in` | POST | **None** | Proxy → gateway `POST /v1/dashboard/auto-sign-in` | Dev JWT bootstrap | **Gateway discovery** — dev sign-in |
| `/*` static | GET | **None** | `ai/runner-console/` | HTML, JS, CSS | Shell |

### 3.2 Ollama transparent proxy (`/api/runner/*`)

| Property | Value |
| --- | --- |
| Prefix | `/api/runner` → strips prefix, forwards to `OLLAMA_BASE_URL` (default `http://127.0.0.1:11434`) |
| Methods | **GET**, **POST** (also supports PUT/PATCH via `_proxy_to_ollama` if extended) |
| Auth | **None** on console; Ollama has no auth |
| Streaming | Forwards `ndjson` and `text/event-stream` with line flushing |
| Timeout | 600s upstream |

**Ollama routes used by current UI (MUST support in new console):**

| Proxied path | Method | Used for | Suggested UI panel |
| --- | --- | --- | --- |
| `/api/runner/v1/models` | GET | Model discovery, connection probe | **Status** / overview metrics |
| `/api/runner/api/tags` | GET | Legacy model list | **API explorer** |
| `/api/runner/api/version` | GET | Ollama version | **API explorer** |
| `/api/runner/api/chat` | POST | Chat playground (stream + non-stream) | **Chat playground** |

**Additional Ollama APIs (proxy-capable, not in current explorer — optional panels):**

| Proxied path | Method | Notes |
| --- | --- | --- |
| `/api/runner/v1/chat/completions` | POST | OpenAI-compatible chat |
| `/api/runner/v1/completions` | POST | Legacy completions |
| `/api/runner/api/generate` | POST | Native Ollama generate |
| `/api/runner/api/pull` | POST | Model pull (operator) |
| `/api/runner/api/ps` | GET | Running models / processor |
| `/api/runner/api/show` | POST | Model manifest |
| `/api/runner/api/embeddings` | POST | Embeddings |

### 3.3 Runner-side gateway mirror (local preview)

The console builds a **local capability entry** from `/v1/models` probe + user-editable `runner_id` and `declared_capabilities` (localStorage). This is **not** sent to the gateway — it previews how the runner should appear in `GET /v1/capabilities`.

| UI input | Storage key | Maps to gateway config |
| --- | --- | --- |
| Runner ID | `runner_console_gateway_runner_id` | `gateway.yaml` → `runners[].id` |
| Declared caps | `runner_console_declared_caps` | `runners[].capabilities` |
| Gateway JWT | `runner_console_gateway_jwt` | Bearer for gateway proxies only |

---

## 4. Gap analysis — what current UIs miss

### 4.1 Gateway dashboard (`ai/dashboard/`) gaps

| Area | Current behavior | Gap for new dashboard |
| --- | --- | --- |
| **Live trace** | 5s poll of `/v1/status`, `/metrics`, `/health`, `/ready`, `/v1/capabilities` | No streaming view of gateway→runner HTTP (poll, proxy, future client) |
| **403 probe** | Documented as static checklist hint | No one-click “test forbidden role” UX |
| **Selector / routing** | Static phase-coverage row | No API for selection decisions; cannot visualize routing until feature 016 |
| **Push registration** | Informational panel when `enable_push_registration` | Cannot invoke internal endpoints from browser (by design); no “last heartbeat received” API |
| **Log viewer** | Shows `log_dir` path only | No tail of `gateway.jsonl` or poll events in UI |
| **Auth config endpoint** | Used internally, not in explorer catalog | `/v1/dashboard/auth-config` absent from try-it table |
| **Per-poll history** | Sparklines from Prometheus counters | No per-runner poll timeline (only latest registry state) |
| **Declarative vs live** | Digest pin compare on runner cards | No aggregate “config drift” summary across runners |

### 4.2 Runner console (`ai/runner-console/`) gaps

| Area | Current behavior | Gap for new runner console |
| --- | --- | --- |
| **Gateway proxies** | `status` + `metrics` implemented in server; **not documented in README** | Document and expose consistently in UI |
| **Gateway sign-in** | Auto sign-in only; no proxy for `POST /v1/dashboard/sign-in` | Manual username/password sign-in requires direct gateway URL or new proxy |
| **Ollama explorer** | Fixed 3 GET buttons | No generic method/path/body explorer for full proxy |
| **Live gateway poll trace** | Observability polls status/metrics on interval | Cannot see individual `HealthPoller` cycles hitting this runner |
| **POST Ollama APIs** | Chat only | No UI for pull/show/generate/embeddings |
| **Runtime errors** | GPU toggle errors inline | No structured event log for compose restarts |
| **Security** | JWT in localStorage | No token expiry refresh except manual re-fetch |

### 4.3 Cross-cutting gaps (both UIs)

| Gap | Impact |
| --- | --- |
| No shared **trace event schema** or ingest API | Agents cannot build a unified “wire tap” panel |
| Polling-only updates | Stale UI between intervals; high load on `/v1/status` + `/metrics` |
| `implementation-status.md` drift | Doc still lists some Phase 5 items as missing; **code has them** — treat code as truth |
| Selector unused | `BUSY` / `in_flight` rarely change until generation routing exists |

---

## 5. Recommended backend additions — LIVE gateway↔runner trace

Goal: expose a **bounded, redacted, append-only event stream** for dashboard and runner console live panels.

### 5.1 Instrumentation points (priority order)

| Location | File | Phase tag | What to emit |
| --- | --- | --- | --- |
| **Health poller** | `ai/gateway/src/gateway/routing/health_poller.py` | `poll` | After each `poll_runner()`: runner_id, method `GET`, path `/v1/models`, status, latency_ms, poll_outcome, status_change |
| **Runner proxy** | `ai/gateway/src/gateway/api/runners.py` | `proxy` | On `get_runner_models`: same fields + `request_id` from caller |
| **OpenAI/poll client** | `ai/gateway/src/gateway/runners/openai_client.py` | `poll` | Optional low-level httpx hook (shared by poller) — avoid duplicate events if poller already emits |
| **HTTP middleware** | `ai/gateway/src/gateway/main.py` | `client` | Incoming gateway requests that trigger runner I/O (future generate) — already has `request_id`, latency |
| **Push heartbeat** | `ai/gateway/src/gateway/api/internal_runners.py` | `push` | register/heartbeat accepted/rejected (no runner HTTP) |
| **Runner console proxy** | `ai/runners/scripts/console_server.py` | `console_proxy` | Optional: Ollama proxied calls from operator UI (localhost only) |

### 5.2 Suggested in-process collector

```text
ai/gateway/src/gateway/obs/trace_buffer.py
  - ring buffer (e.g. 500 events)
  - thread-safe append
  - redact bodies (see schema)
  - subscribe API for SSE
```

### 5.3 New gateway endpoints (proposed)

| Endpoint | Method | Auth | Purpose |
| --- | --- | --- | --- |
| `/v1/trace` | GET | JWT + `ai.access` | Paginated snapshot of recent events (fallback) |
| `/v1/trace/stream` | GET | JWT + `ai.access` | **SSE** live stream (see §7) |

Runner console can add `GET /api/gateway/trace/stream` proxy mirroring other gateway proxies.

### 5.4 Redaction rules (all phases)

- Truncate bodies to ≤2 KB; replace with `"[truncated]"` beyond limit.
- Strip `Authorization`, `X-Internal-Secret`, JWT-like strings from any captured header dump.
- Never log prompt/completion text from future generate — hash or omit (`log_verbatim=false` policy).

---

## 6. Suggested trace event schema

Use a single JSON object per event (SSE `data:` line or JSONL).

```json
{
  "event_id": "uuid",
  "ts": "2026-07-17T12:34:56.789Z",
  "phase": "poll",
  "direction": "gateway_to_runner",
  "runner_id": "ollama-local",
  "method": "GET",
  "path": "/v1/models",
  "status": 200,
  "latency_ms": 42.5,
  "request_body_redacted": null,
  "response_body_redacted": "{\"object\":\"list\",\"data\":[{\"id\":\"qwen3:4b\",\"digest\":\"sha256:…\"}]}",
  "poll_outcome": "ok",
  "runner_status_change": "STARTING→READY",
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "caller_staff_id": null,
  "error": null
}
```

### 6.1 Field definitions

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `event_id` | string (UUID) | yes | Unique event id |
| `ts` | ISO-8601 UTC | yes | Event timestamp |
| `phase` | enum | yes | `poll` \| `proxy` \| `client` \| `push` \| `console_proxy` |
| `direction` | enum | yes | `gateway_to_runner` \| `client_to_gateway` \| `runner_to_gateway` (push) |
| `runner_id` | string \| null | when applicable | Registry id |
| `method` | string | yes | HTTP method |
| `path` | string | yes | Path only (no secrets in query) |
| `status` | int \| null | yes | HTTP status or null on connection error |
| `latency_ms` | float \| null | yes | Round-trip milliseconds |
| `request_body_redacted` | string \| null | no | Truncated/redacted request body |
| `response_body_redacted` | string \| null | no | Truncated/redacted response body |
| `poll_outcome` | string \| null | poll only | `ok` \| `loading` \| `error` \| `timeout` |
| `runner_status_change` | string \| null | poll/push | e.g. `READY→UNREACHABLE` |
| `request_id` | string \| null | client/proxy | Correlates with `X-Request-ID` |
| `caller_staff_id` | string \| null | client | From JWT when present |
| `error` | string \| null | on failure | Sanitized error message |

### 6.2 Phase → direction mapping

| `phase` | Typical `direction` | Source |
| --- | --- | --- |
| `poll` | `gateway_to_runner` | `HealthPoller` |
| `proxy` | `gateway_to_runner` | `/v1/runners/{id}/models` |
| `client` | `client_to_gateway` | Middleware (+ future generate upstream) |
| `push` | `runner_to_gateway` | Internal register/heartbeat |
| `console_proxy` | `gateway_to_runner` (conceptually operator→Ollama) | Runner console server |

---

## 7. SSE vs WebSocket — recommendation for live panel

**Recommendation: Server-Sent Events (SSE) via `GET /v1/trace/stream`.**

| Criterion | SSE | WebSocket |
| --- | --- | --- |
| Traffic pattern | Server → browser (trace feed) | Bidirectional |
| Implementation | `EventSource` in browser; FastAPI `StreamingResponse` | Starlette WS + heartbeat |
| Reconnect | Built-in `EventSource` retry | Manual |
| Auth | Pass Bearer via cookie or short-lived query token* | Same complexity |
| Proxies | Works through gateway; runner console can proxy as `text/event-stream` | May need upgrade headers |
| Use case fit | **Trace tail / live log** | Needed only if UI sends control messages over same socket |

\* Browsers cannot set custom headers on `EventSource`; options: (a) mount trace stream behind same-origin dashboard with session cookie, (b) issue short-lived trace ticket via `POST /v1/trace/token`, or (c) rely on same-origin `/dashboard` only.

**When to add WebSocket later:** interactive runner selection debugging, cancelling in-flight inference, or multiplexing metrics + trace on one connection.

**Interim (no backend yet):** both UIs should keep **poll-based** `/v1/status` + `/metrics` (5–8s) and document that trace panel is blocked on §5.

---

## 8. UI agent quick-reference — minimum viable panels

### 8.1 New gateway dashboard (must-have)

1. **Overview** — `/health`, `/ready`, runner counts, connection state  
2. **Runners** — registry from `/v1/status`, lifecycle, poll-all via `/v1/runners/{id}/models`  
3. **Metrics** — `/metrics` charts  
4. **Capabilities** — `/v1/capabilities`  
5. **Generate stub** — `POST /v1/ai/generate`  
6. **Security / Auth** — auth-config, sign-in, JWT storage, safe config, error envelope  
7. **Endpoint explorer** — try-it for all public/protected routes in §2  
8. **Push registration** — read-only when enabled  
9. **Live trace** (placeholder → SSE when §5 ships)

### 8.2 New runner console (must-have)

1. **Compute runtime** — `/api/runtime`, GPU POST  
2. **Status** — `/api/runner/v1/models` probe  
3. **Chat playground** — `/api/runner/api/chat` (stream + non-stream)  
4. **Telemetry** — request/raw/parsed panes (inference-local)  
5. **Gateway discovery** — local preview + `/api/gateway/capabilities`  
6. **Gateway observability** — `/api/gateway/status` + `/api/gateway/metrics`  
7. **API explorer** — at minimum `/v1/models`, `/api/tags`, `/api/version`  
8. **Live trace** (placeholder → proxy gateway SSE or localhost Ollama tap)

---

## 9. File map (implementation reference)

| Path | Role |
| --- | --- |
| `ai/gateway/src/gateway/main.py` | App factory, middleware, router mount, dashboard static |
| `ai/gateway/src/gateway/api/*.py` | HTTP routes (see §2) |
| `ai/gateway/src/gateway/routing/registry.py` | In-memory runner state |
| `ai/gateway/src/gateway/routing/health_poller.py` | Pull health loop |
| `ai/gateway/src/gateway/routing/lifecycle.py` | Status state machine |
| `ai/gateway/src/gateway/routing/selector.py` | Routing selection (pre-016) |
| `ai/gateway/src/gateway/runners/openai_client.py` | `poll_runner()` httpx client |
| `ai/runners/scripts/console_server.py` | Runner console HTTP server |
| `ai/dashboard/app.js` | Current gateway dashboard client |
| `ai/runner-console/app.js` | Current runner console client |
| `docs/ai/gateway-runner-interaction.md` | Normative interaction doc |
| `docs/ai/phase-capabilities.md` | Phase ↔ panel mapping |

---

*Generated for parallel UI agent consumption. Update this file when gateway or console_server routes change.*
