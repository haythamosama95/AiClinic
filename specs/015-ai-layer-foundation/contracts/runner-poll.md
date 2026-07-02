# Contract: Gateway ↔ Model Runner (internal, pull-based)

This is the **internal** inference-plane contract between the AI Gateway and a Model Runner. It is
**not client-facing**; runners are bound to localhost / the AI-internal interface and MUST NOT be
reachable from client subnets (FR-010, §11.3). In Phase 1 the Gateway only **polls** the runner for
health/model discovery — it does **not** send inference requests (that begins in Phase 2).

The Model Runner is a **vanilla OpenAI-compatible** server (Ollama by default). No bespoke agent runs
on the runner host; the Gateway adapts to the standard endpoints below.

## Endpoints the runner exposes (OpenAI-compatible)

### `GET /v1/models` (used for health poll + model discovery — Phase 1)

- **Purpose**: liveness signal + currently available/loaded model discovery.
- **Success (200)** — example (Ollama-compatible):

```json
{
  "object": "list",
  "data": [
    { "id": "qwen3:4b", "object": "model", "digest": "sha256:...", "context_length": 8192 }
  ]
}
```

- **Gateway interpretation**:
  - Reachable + parseable within poll timeout → candidate `READY` (subject to lifecycle rules).
  - Reports the loaded model `id` + `digest` → populates `RunnerRegistryEntry.loaded_model`.
  - Model still loading / not present → treat as `STARTING` (not routable).
  - Connection error / non-2xx / timeout → increment `consecutive_failures`; at
    `unreachable_after_failures` (default 3) → `UNREACHABLE`.
  - Elevated/rising latency or intermittent errors (below the unreachable threshold) → `DEGRADED`.

> A runner MAY additionally expose `GET /health`; if configured, the Gateway MAY use it instead of / in
> addition to `/v1/models`. `/v1/models` is the default because it also yields model+digest.

### `POST /v1/chat/completions` (Phase 2 — NOT called in Phase 1)

- Documented here only to fix the contract boundary. In Phase 1 the Gateway MUST NOT call this.
- In Phase 2 the Gateway will call it (optionally grammar-constrained, optionally streaming). The
  runner MUST keep at most one model resident and swap on demand (FR-007); during a swap it MUST
  return `503` + `Retry-After` or queue, and report `STARTING` via the poll endpoint.

## Poll behavior (Gateway side — Phase 1 normative)

| Aspect | Rule |
| --- | --- |
| Cadence | `health_poll_interval_s` (default 10 s), per runner. |
| Timeout | Poll request has a short bounded timeout (recommend ≤ 2 s). |
| Failure accounting | Consecutive failures counter; reset on success. |
| Unreachable threshold | `unreachable_after_failures` (default 3). |
| Latency tracking | Record `last_latency_ms` + rolling `avg_latency_ms`. |
| Model discovery | Capture loaded model `id` + `digest` + `context_length` when present. |
| No inference | Gateway performs NO `chat/completions` calls this phase. |

## Optional push registration (config-gated, default OFF)

Only when `enable_push_registration=true` (FR-030, §6.2/§10.6):

- `POST /internal/runners/register` — body: `{ id, base_url, capabilities[], models[] }`
- `POST /internal/runners/heartbeat` — body: `{ id, status, loaded_model }`

Requirements when enabled:
- MUST require the `internal_shared_secret` (separate from client JWT path).
- MUST be bound to the AI-internal interface only; MUST reject client-subnet origins.
- These endpoints are internal-plane, never exposed in the client-facing OpenAPI.

## Isolation invariants (both directions)

- The runner holds **no** Supabase/clinic-DB credentials and has no DB access (FR-011).
- The runner is **not client-routable** (bind localhost/AI-internal) (FR-010).
- The Gateway↔runner link carries only health polls in Phase 1; no PHI, no clinical data.
