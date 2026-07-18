# Phase 1 Data Model: AI Generation Pipeline + Scheduling Agent (016)

**Branch**: `ai/016-generation-scheduling` | **Date**: 2026-07-18
**Feature spec**: `specs/016-ai-generation-scheduling/spec.md`
**Plan**: `specs/016-ai-generation-scheduling/plan.md`

This feature adds **no database tables and no clinical persistence** of any kind — the AI layer
remains isolated (spec FR-028/FR-030; constitution Principle V). The "data model" here is the
**in-memory + request/response contract shape**: the request body, the Command Protocol envelope,
the scheduling command parameter shapes, the queue/runner/lifecycle state, the log record shape,
and the capabilities report shape. Fields are described abstractly (no Python/pydantic syntax);
implementations are bound to these shapes via `pydantic` v2 schemas (validated by unit tests).

> All entities below are **ephemeral, in-process, or HTTP-message-shaped**. Nothing here is
> persisted in PostgreSQL/Supabase. The clinic database is untouched by this feature.

---

## 1. Request entities (client → Gateway)

### 1.1 `GenerationRequest` (body of `POST /v1/ai/generate`)

| Field              | Type                                              | Required | Notes                                                            |
| ------------------ | ------------------------------------------------- | -------- | ---------------------------------------------------------------- |
| `task`             | enum: `command` \| `plan` \| `text` \| `clinical_note` \| `analytics` | yes      | In-scope this phase: `command`. Others accepted; `plan`/`analytics` ignored or rejected per spec. |
| `prompt`           | string (length-bounded, default max 8 KB)         | yes      | Untrusted user text; placed in a delimited user region.          |
| `context`          | object (validated when present)                   | no       | Structured context (see §1.2).                                   |
| `conversation_id`  | uuid (string)                                     | no       | Reserved, accepted and ignored this phase.                       |
| `turn`             | integer ≥ 0                                       | no       | Reserved, accepted and ignored this phase.                       |
| `options`          | object (see §1.3)                                 | no       | Defaults apply per spec.                                         |

**Validation rules**:
- `task` MUST be one of the enum values; else `400 bad_request`.
- `prompt` MUST be non-empty and ≤ the configured size cap; else `400 bad_request`.
- `conversation_id` MUST be a valid UUID when present; else `400 bad_request`.
- Any unknown field is ignored (forward-compat, spec §10.5).

### 1.2 `GenerationContext` (nested under `context`)

Field-by-field validated when present. All values the client can know without the Gateway
fetching anything (the Gateway performs zero Supabase reads).

| Field             | Type                                              | Required | Notes                                              |
| ----------------- | ------------------------------------------------- | -------- | -------------------------------------------------- |
| `branch_id`       | uuid string                                       | no       |                                                    |
| `branch_name`     | string                                            | no       |                                                    |
| `now`             | ISO-8601 timestamp with timezone offset           | no       | Used as the reference for "no past date" semantic checks (defaults to Gateway wall-clock if absent). |
| `active_patient`  | `{ id: uuid, name: string }`                      | no       |                                                    |
| `doctors`         | list of `{ id: uuid, name: string }`             | no       |                                                    |
| (future)          | reserved                                          | —        | Other task-tiered context slices per spec §7.2.    |

### 1.3 `GenerationOptions` (nested under `options`)

| Field              | Type                          | Required | Default                            | Notes                                            |
| ------------------ | ----------------------------- | -------- | ---------------------------------- | ------------------------------------------------ |
| `stream`           | bool                          | no       | `false`                            | If `true` *and* `streaming_enabled` is on Gateway-wide, server uses SSE; else serves non-streaming (Q2). |
| `confidence_hint`  | bool                          | no       | `true`                             | Hint to model to emit confidence; this phase always populates `confidence`. |
| `plan_mode`        | enum: `single` \| `multi`     | no       | `single`                           | Accepted and ignored this phase (single commands emitted). |

---

## 2. Response entities (Gateway → client)

### 2.1 `CommandProtocolEnvelope` (single-command, `task:"command"`)

| Field                  | Type                                | Required | Notes                                                              |
| ---------------------- | ----------------------------------- | -------- | ------------------------------------------------------------------ |
| `schema_version`       | string (`"1.0"`)                    | yes      | Always `"1.0"` this phase.                                          |
| `task`                 | `"command"`                         | yes      | A single-command response is defined as a length-1 plan; clients MUST treat it so. |
| `command_type`         | enum (scheduling catalog)           | yes      | `create_appointment` / `reschedule_appointment` / `cancel_appointment` / `update_appointment_status`. Off-catalog values are impossible (grammar + catalog allowlist). |
| `confidence`           | float `[0,1]`                       | yes      | Raw model output; always present (even when `needs_clarification` is true). |
| `display_summary`      | string (human-readable, non-actionable) | yes  | A sentence for the (future) approval card; MUST match `params` (semantic validator asserts referenced names appear in `params` or `requires_resolution`). |
| `params`               | object matching the command schema  | yes      | See §3 for per-command shape.                                       |
| `requires_resolution`  | `dict<string, "lookup_required">`   | yes      | Bare-string form only this phase; structured-directive form reserved (§9.1). Always carries the entity-id fields the model could not resolve (e.g. `patient_id`, `doctor_id`). |
| `warnings`             | list of `Warning`                   | yes      | May be empty.                                                       |
| `needs_clarification`  | bool                                | yes      | Set by Gateway: `true` when `confidence < ai.confidence_threshold`; destructively `true` for destructive commands (`cancel_*`, `reschedule_*`) with any ambiguous resolved field (per /clarify Q1). |

**`Warning` object**:
| Field   | Type   | Notes                            |
| ------- | ------ | -------------------------------- |
| `code`  | string | Stable machine-readable code.    |
| `message` | string | Human-readable explanation.     |

### 2.2 `Warning` (referenced above)

Fields as listed.

### 2.3 Capabilities report (`GET /v1/capabilities`)

Same shape as Phase 1, with two changes:

- `streaming` reflects `streaming_enabled`.
- `tasks` includes `"command"`.
- `commands` lists the four scheduling command types.
- `runners[]` is unchanged (status, model, digest, features, context_tokens) and now is the
  live registry after Phase 1.

### 2.4 Typed error body (`error-contract.md`)

```json
{ "error": { "code": "<stable-code>", "message": "<human-readable>", "request_id": "<uuid>" } }
```

Codes (Phase 2 additions in **bold**):

| HTTP | code                  | Meaning                                                                                      |
| ---- | --------------------- | -------------------------------------------------------------------------------------------- |
| 400  | `bad_request`         | Malformed/oversized input (Phase 1).                                                        |
| 401  | `unauthenticated`     | Missing/invalid/expired JWT (Phase 1).                                                       |
| 403  | `forbidden`           | Caller lacks `ai.access` (Phase 1).                                                          |
| **422** | **`ai_unusable`**   | Output failed schema or semantic validation; not retried (per /clarify Q3).                  |
| 429  | `rate_limited`        | Per-caller rate exceeded (reserved; this phase uses `max_inflight_per_caller`).              |
| **503** | **`ai_busy`**       | Queue full (backpressure); carries `Retry-After`.                                            |
| **503** | **`ai_no_capacity`**| No `READY` capability match *after* auto-swap attempt, or no candidate runner.                |
| **504** | **`ai_timeout`**    | Inference exceeded first-token / total / model-swap timeout.                                 |

---

## 3. Scheduling command parameter shapes

These are the shapes the AI **may** populate in `params`. They mirror the *existing* Supabase
appointment RPCs the manual UI already uses (the AI never calls them this phase, but the catalog
is aligned to Phase 3's approved-execution path). All entity **id** fields carry
`requires_resolution: "lookup_required"` (bare-string form) — the AI MUST NOT fabricate ids.

### 3.1 `create_appointment`

| Field            | Type / format                              | Required | Notes                                                              |
| ---------------- | ------------------------------------------ | -------- | ------------------------------------------------------------------ |
| `patient_name`   | string                                     | yes      | From context/prompt; client resolves to `patient_id` later.       |
| `doctor_name`    | string                                     | yes      | From context (branch doctor list) or prompt; resolves to `doctor_id`. |
| `date`           | ISO date `YYYY-MM-DD`                      | yes      | MUST NOT be earlier than `context.now` (date) (semantic check).   |
| `time`           | ISO time `HH:MM` (24h)                     | yes      |                                                                    |
| `type`           | enum (planned \| emergency \| follow_up)  | yes      | Legal enum values only.                                            |
| `notes`          | string, optional                           | no       |                                                                    |

`requires_resolution` (typical): `{ "patient_id": "lookup_required", "doctor_id": "lookup_required" }`.

### 3.2 `reschedule_appointment`

| Field            | Type / format                              | Required | Notes                                                              |
| ---------------- | ------------------------------------------ | -------- | ------------------------------------------------------------------ |
| `appointment_ref`| string (date+time+patient_name OR appointment identifier from prompt) | yes | The model references an existing appointment the client resolves. |
| `new_date`       | ISO date `YYYY-MM-DD`                      | yes      | MUST NOT be earlier than `context.now` (date).                     |
| `new_time`       | ISO time `HH:MM` (24h)                     | yes      |                                                                    |
| `reason`         | string, optional                           | no       |                                                                    |

`requires_resolution` (typical): `{ "appointment_id": "lookup_required",
"patient_id": "lookup_required", "doctor_id": "lookup_required" }`. **Destructive-class**:
`needs_clarification` is forced `true` if any resolved field is ambiguous.

### 3.3 `cancel_appointment`

| Field            | Type / format                              | Required | Notes                                                              |
| ---------------- | ------------------------------------------ | -------- | ------------------------------------------------------------------ |
| `appointment_ref`| string                                     | yes      | Same as reschedule.                                                |
| `reason`         | string                                     | no       |                                                                    |

`requires_resolution` (typical): `{ "appointment_id": "lookup_required" }`. **Destructive-class**:
`needs_clarification` forced `true` on ambiguity; client (Phase 3) additional typed confirmation
required per spec §9.4.

### 3.4 `update_appointment_status`

| Field            | Type / format                              | Required | Notes                                                              |
| ---------------- | ------------------------------------------ | -------- | ------------------------------------------------------------------ |
| `appointment_ref`| string                                     | yes      |                                                                    |
| `status`         | enum (scheduled \| arrived \| completed \| cancelled \| no_show) | yes | Legal enum values only.                                    |

`requires_resolution` (typical): `{ "appointment_id": "lookup_required" }`. Treated as destructive
when `status="cancelled"` (forces `needs_clarification` on ambiguity).

---

## 4. Pipeline state and lifecycle

### 4.1 In-flight request lifecycle (per request)

```
accepted ──► queued ──► runner_request_in_flight ──► validating ──► completed
   │            │              │                          │
   │            └─► ai_busy (queue full / wait timeout)    └─► ai_unusable (schema/semantic fail)
   │                           │
   │                           ├─► ai_timeout (first-token / total)
   │                           ├─► retry_once (connection/5xx/first-token) ─► runner_request_in_flight
   │                           └─► cancelled (client abort) ─► queue_slot_freed
```

| State                         | Notes                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `accepted`                    | Auth + body validation passed.                                                       |
| `queued`                      | Waiting for a runner slot (capability-class queue) within `queue_max_wait_s`.        |
| `runner_request_in_flight`    | Runner HTTP request open; subject to first-token and total timeouts.                |
| `validating`                  | Runner returned; schema + semantic validation in progress. Idempotent and fast.     |
| `completed`                   | Final envelope ready; emitted (non-streaming body or SSE `final` event).            |
| `ai_busy` / `ai_no_capacity` / `ai_timeout` / `ai_unusable` | Terminal errors per the typed contract. |
| `retry_once`                  | At most one retry on connection error / runner 5xx / first-token timeout, preferring a different healthy runner; never after a partial stream; never on `ai_unusable`. |
| `cancelled`                   | Client aborted HTTP; runner call aborted; queue slot freed; logged `cancelled` (not `error`). |

### 4.2 Per-capability queue entry

| Field            | Type      | Notes                                                            |
| ---------------- | --------- | ---------------------------------------------------------------- |
| `capability`     | string    | e.g. `"command"` (scheduling capability class).                 |
| `request_id`      | uuid      |                                                                  |
| `caller_staff_id`| uuid      | From JWT; used for `max_inflight_per_caller` fairness.           |
| `enqueue_at`     | timestamp | For `queue_max_wait_s` enforcement.                              |
| `task`           | `asyncio.Task` | The awaiting coroutine; cancellable for backpressure overflow. |

### 4.3 Per-caller in-flight tracker

A `dict<caller_staff_id, int>` (or equivalent in-process structure) tracking live
`runner_request_in_flight` requests by caller; incremented on accept, decremented on terminal
state. Enforced at the **accept** gate (before queueing) — exceeding `max_inflight_per_caller`
(default 2) yields `429 rate_limited` (or `503 ai_busy` per implementation choice; spec lists
both — we use `429` for per-caller cap, `503 ai_busy` for queue depth).

---

## 5. Generation log record (operator-facing, structured JSON)

Written to **local files only** by `obs/logging.py` (Phase 1 skeleton extended). PHI-redacted by
default (`prompt`/`context`/`params`-text/`display_summary` hashed or dropped per
`log_verbatim=false`).

| Field                  | Type                              | Always present | Notes                                          |
| ---------------------- | --------------------------------- | -------------- | ---------------------------------------------- |
| `request_id`           | uuid                              | yes            |                                                |
| `caller_staff_id`      | uuid (from JWT)                   | yes            |                                                |
| `task`                 | enum (see §1.1)                   | yes            |                                                |
| `agent`                | string                            | yes            | e.g. `"scheduling"`.                           |
| `runner`               | string (runner id)                | yes            |                                                |
| `model`                | string                            | yes            | Resolved model name (e.g. `qwen3:4b`).         |
| `digest`               | string                            | yes            | Resolved model digest (per Phase 1 R-008 pin). |
| `queue_wait_seconds`   | float                             | yes            | Time spent in the capability queue.            |
| `first_token_seconds`  | float                             | yes (when applicable) | For streaming tasks; null for buffered command bodies. |
| `total_seconds`        | float                             | yes            | End-to-end generation latency.                 |
| `prompt_tokens`        | int                               | yes            |                                                |
| `completion_tokens`    | int                               | yes            |                                                |
| `outcome`              | enum: `ok` \| `error` \| `timeout` \| `cancelled` | yes   |                                                |
| `error_class`          | string                            | on failure     | Stable code from the error contract.           |
| `retried`              | bool                              | yes            | Whether a retry was attempted.                 |
| `verbatim`             | bool                              | yes            | The active `log_verbatim` flag at log time.    |

---

## 6. Metrics (Prometheus `/metrics`, extended from Phase 1)

| Metric                                  | Type        | Labels                                | Notes |
| --------------------------------------- | ----------- | ------------------------------------- | ----- |
| `ai_requests_total`                     | counter     | `task`, `outcome`                     |       |
| `ai_errors_total`                       | counter     | `code`                                |       |
| `ai_queue_depth`                        | gauge       | `capability`                          | Current depth per capability class. |
| `ai_queue_wait_seconds`                 | histogram   | `capability`                          | Time spent waiting in the queue. |
| `ai_first_token_seconds`                | histogram   | `runner`                              | Only for streaming tasks. |
| `ai_total_seconds`                      | histogram   | `runner`, `task`                      | End-to-end latency. |
| `ai_inflight`                           | gauge       | `capability`                          | Current in-flight per capability. |
| `ai_tokens_per_sec`                     | histogram   | `runner`, `task`                      | Throughput during generation. |
| `ai_model_swaps_total`                  | counter     | `runner`, `outcome`                   | Auto-triggered swap attempts per spec Q5. |

---

## 7. State transitions: model swap auto-trigger (FR-019, per /clarify Q5)

```
routing_request_arrives
     │
     ├─► capability_match_in_READY_runners ─► route_to_least_busy ─► runner_request_in_flight
     │
     └─► no_READY_match_but_candidate_runner_with_model_UNLOADED
            │
            ├─► emit_swap_request_to_candidate ─► candidate enters STARTING
            │       │
            │       ├─► runner_reaches_READY_within_model_swap_first_token_timeout
            │       │        ─► route_to_candidate ─► runner_request_in_flight
            │       │
            │       └─► swap_window_times_out_or_fails
            │                ─► return 503 ai_no_capacity
            │
            └─► no_candidate_runner_able_to_serve_capability
                    ─► return 503 ai_no_capacity
```

Invariant: during `STARTING`, **at most one model** is resident in runner RAM (Phase 1 invariant;
Ollama unloads the previous model before loading the new one; concurrent requests during `STARTING`
queue or receive `503 ai_busy`).