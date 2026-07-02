# Phase 1 Data Model: AI Layer Foundation (015)

The AI layer persists **no** durable data (no database, no clinical state). The "entities" here are
**in-memory control-plane structures** and **configuration/claim shapes**. They are documented so the
Gateway's registry, auth, and capabilities logic are unambiguous and testable. Nothing below is stored
in PostgreSQL or any database (FR-032, §17.1).

---

## 1. GatewayConfig

Loaded once at startup from `gateway.yaml` (+ env overrides); validated with fail-fast semantics
(FR-003/FR-004, §14). Immutable after load except `RoleAiAccessMap`, which is reloadable (FR-018).

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `port` | int | `8090` | LAN listen port. |
| `runners` | list[RunnerConfig] | `[]` | Static runner endpoints + declared capabilities (pull mode). |
| `health_poll_interval_s` | int | `10` | Poll cadence. |
| `unreachable_after_failures` | int | `3` | Consecutive failed polls → `UNREACHABLE`. |
| `queue_max_depth` | int | `16` | Reserved (Phase 2); parsed now. |
| `queue_max_wait_s` | int | `20` | Reserved (Phase 2); parsed now. |
| `max_inflight_per_caller` | int | `2` | Reserved (Phase 2); parsed now. |
| `timeout_total_s` | int | `45` | Reserved (Phase 2); parsed now. |
| `timeout_first_token_s` | int | `15` | Reserved (Phase 2); parsed now. |
| `confidence_threshold` | float | `0.6` | Reserved (Phase 2); parsed now. |
| `jwt_secret` | str? | — | HS-family shared secret (offline validation). |
| `jwks_url` | str? | — | JWKS/public-key-set URL (offline, cached). Precedence over `jwt_secret` if both set. |
| `allowed_origins` | list[str] | explicit | CORS allowlist; wildcard forbidden (FR-021). |
| `log_verbatim` | bool | `false` | PHI-in-log opt-in (dev only) (FR-034). |
| `enable_push_registration` | bool | `false` | Optional dynamic registry (FR-030). |
| `internal_shared_secret` | str? | — | Required iff push registration enabled. |
| `streaming_enabled` | bool | `true` | Reserved (Phase 2). |
| `enable_multi_command_plans` | bool | `false` | Reserved (Phase 2). |
| `model_swap_first_token_timeout_s` | int | `60` | Reserved (Phase 2). |
| `models_dir` | str? | — | Model store path (used by runner/installer). |
| `role_ai_access` | RoleAiAccessMap | see below | Role → `ai.access` allowlist. |
| `log_dir` | str | `./logs` | Local structured-log directory. |

**Validation rules**: `port` in 1–65535; at least one of `jwt_secret`/`jwks_url` MUST be set (else
fail fast — the Gateway cannot authenticate); `allowed_origins` MUST NOT contain `*`;
`internal_shared_secret` required when `enable_push_registration=true`; unknown keys or type
mismatches → startup error naming the key.

### 1a. RunnerConfig (element of `runners`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | str | Stable runner identifier (unique). |
| `base_url` | str | AI-internal URL (e.g. `http://127.0.0.1:11434`). MUST be LAN-internal. |
| `capabilities` | list[str] | Declared: e.g. `["json_grammar"]` (advisory this phase). |
| `models` | list[ModelDef] | Declared model definitions (name, tag/GGUF path, capabilities, context_tokens, digest). |

### 1b. ModelDef

| Field | Type | Notes |
| --- | --- | --- |
| `name` | str | e.g. `qwen3:4b`. |
| `source` | str | Ollama tag or local GGUF path. |
| `digest` | str | Pinned integrity digest (`sha256:…`) (§11.6). |
| `context_tokens` | int | Advertised context length. |
| `capabilities` | list[str] | e.g. `["json_grammar"]`. |

---

## 2. RunnerRegistryEntry (in-memory)

One per configured runner; owned by the registry, mutated by the health poller. Never persisted.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | str | From `RunnerConfig.id`. |
| `base_url` | str | From config. |
| `status` | RunnerStatus | Lifecycle state (see §3). Starts `UNKNOWN`. |
| `last_seen_at` | datetime? | Last successful poll timestamp. |
| `last_latency_ms` | float? | Most recent poll round-trip. |
| `avg_latency_ms` | float? | Rolling average (for `DEGRADED` detection). |
| `consecutive_failures` | int | Reset to 0 on success; `≥ unreachable_after_failures` → `UNREACHABLE`. |
| `loaded_model` | LoadedModel? | Currently resident model (name + digest + context). |
| `declared_capabilities` | list[str] | Union of config + observed features. |
| `in_flight` | int | Active requests routed to this runner (0 this phase; used by least-busy). |

### 2a. LoadedModel

| Field | Type | Notes |
| --- | --- | --- |
| `name` | str | Reported by runner `/v1/models`. |
| `digest` | str | Reported/pinned digest. |
| `context_tokens` | int? | If discoverable. |
| `features` | list[str] | e.g. `["json_grammar"]`. |

**Derived / aggregate**:
- **Readiness**: `ready == any(entry.status == READY for entry in registry)` (drives `GET /ready`).
- **Capabilities report** (`GET /v1/capabilities`): aggregates each entry's `status`, `loaded_model`
  (name+digest+context), and `features`; `tasks`/`commands` are **empty** while generation is stubbed
  (FR-031).

---

## 3. RunnerStatus (lifecycle state machine)

Enum: `UNKNOWN`, `STARTING`, `READY`, `BUSY`, `DEGRADED`, `UNREACHABLE` (AI Service Spec §8.2).

```
[*] --> UNKNOWN
UNKNOWN     --> STARTING     : process up, model loading
STARTING    --> READY        : model loaded, health OK
READY       --> BUSY         : at max in-flight
BUSY        --> READY        : capacity freed
READY       --> DEGRADED     : elevated latency / sporadic errors
DEGRADED    --> READY        : recovered
READY       --> UNREACHABLE  : N consecutive failed polls (default 3)
DEGRADED    --> UNREACHABLE  : N consecutive failed polls
UNREACHABLE --> STARTING     : process/health recovers
UNREACHABLE --> [*]          : removed from registry (config change)
```

**Routing eligibility**: `READY` (preferred) and `DEGRADED` (deprioritized) are routable; `STARTING`,
`UNREACHABLE`, `UNKNOWN` are not. `BUSY` is a transient READY sub-state (at max in-flight) and is
tracked for least-busy selection; it becomes relevant in Phase 2 when requests are actually served.

**Transition function** is pure and unit-testable: `(current_status, poll_outcome, counters, config)
→ next_status`. Poll outcomes: `ok(latency, model)`, `loading`, `error`, `timeout`.

---

## 4. CallerIdentity (from JWT, transient per request)

Extracted by offline JWT validation; used only for authorization + logging. Never used for DB access.

| Field | Type | Source | Notes |
| --- | --- | --- | --- |
| `staff_id` | str | JWT `sub` / staff claim | Logged as `caller_staff_id` (not PHI). |
| `staff_role` | str | JWT `staff_role` claim | Used against `RoleAiAccessMap`. |
| `exp` | int | JWT `exp` | Expiry (validated). |
| `nbf` | int? | JWT `nbf` | Not-before (validated if present). |
| `has_ai_access` | bool | derived | `role_ai_access[staff_role]`. |

**Validation outcomes** (map to error contract): missing/invalid/expired/nbf-future signature →
`unauthenticated` (401); valid token but `has_ai_access == false` → `forbidden` (403).

---

## 5. RoleAiAccessMap (reloadable config)

`dict[str, bool]` mapping `staff_role` → whether `ai.access` is granted. Mirrors `roles_permissions`
defaults (§17.2).

| Role | Default `ai.access` |
| --- | --- |
| `administrator` | `true` |
| `doctor` | `true` |
| `receptionist` | `false` |
| `lab_staff` | `false` |

Reloaded on file change / SIGHUP / periodic refresh (FR-018); reload must be atomic (no request sees a
half-updated map).

---

## 6. ErrorEnvelope (response shape)

Uniform failure body (FR-020, §10.4):

```json
{ "error": { "code": "string", "message": "string", "request_id": "string" } }
```

| `code` | HTTP | When (this phase) |
| --- | --- | --- |
| `bad_request` | 400 | Malformed/oversized body. |
| `unauthenticated` | 401 | Missing/invalid/expired/nbf-future token. |
| `forbidden` | 403 | Valid token, role lacks `ai.access`. |
| `not_implemented` | 501 | Stubbed `POST /v1/ai/generate`. |
| `rate_limited` | 429 | Per-caller rate exceeded (if enabled). |
| `ai_no_capacity` | 503 | No healthy runner (relevant once generation exists; may surface via `/ready`). |
| `ai_timeout` | 504 | Reserved (Phase 2). |

Every response (success or error) carries a `request_id` (also emitted in structured logs).

---

## 7. LogRecord (structured, local file, PHI-minimized)

JSON per event (FR-033/FR-034). Redaction processor active unless `log_verbatim=true`.

| Field | Notes |
| --- | --- |
| `ts` | ISO-8601 timestamp. |
| `request_id` | Correlates response + logs. |
| `caller_staff_id` | From JWT (id only; not a name). |
| `endpoint` | e.g. `/v1/capabilities`. |
| `outcome` | `ok`/`error`/`unauthenticated`/`forbidden`/`not_implemented`/`cancelled`. |
| `error_code` | Present on failures. |
| `runner_id` | Chosen/affected runner, when applicable. |
| `runner_status_change` | e.g. `READY→UNREACHABLE`, when applicable. |
| `latency_ms` | Endpoint / poll latency. |
| `redacted` | `true` when any field was redacted/hashed. |

**Invariant**: with `log_verbatim=false`, no caller-supplied text/PHI (e.g. patient names) appears
verbatim — enforced by a test using name fixtures (SC-012).

---

## Entity relationships (summary)

```
GatewayConfig 1─── * RunnerConfig 1─── * ModelDef
GatewayConfig 1──1 RoleAiAccessMap
Registry 1─── * RunnerRegistryEntry 0..1── LoadedModel
RunnerRegistryEntry.status : RunnerStatus (state machine)
Request → CallerIdentity (transient)  ; Request/Poll → LogRecord (transient, file)
```

No entity is written to a database. All are process-local and reconstructable from config + live
polling on restart.
