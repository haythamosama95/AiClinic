# Implementation Plan: AI Generation Pipeline + Scheduling Agent (016)

**Branch**: `ai/016-generation-scheduling` | **Date**: 2026-07-18 | **Spec**: `specs/016-ai-generation-scheduling/spec.md`

**Input**: Feature specification from `specs/016-ai-generation-scheduling/spec.md`

## Summary

Deliver the **production-robust generation pipeline** for the AI layer (AI Service Spec v2, Appendix B, Phase 2 → roadmap V2-1), exercised end-to-end by **one agent (scheduling)**. Building on the Phase 1 control plane (`ai/gateway/` — auth, routing, registry, health polling, observability, the `POST /v1/ai/generate` *stub*), this feature replaces the stub with a real **non-streaming + SSE streaming** generation path backed by a **scheduling agent**: server-side system prompt + JSON-schema/grammar-constrained decoding + schema & semantic validation, emitting the **Command Protocol envelope** (with the `needs_clarification` field settled in `/clarify`).

The full resilience envelope ships here: a **bounded FIFO queue per capability class** with `503 ai_busy`+`Retry-After` backpressure, per-caller in-flight caps, configurable first-token / total / model-swap timeouts (`504 ai_timeout`), a single idempotent retry preferring a different healthy runner (never after a partial stream; never on `422 ai_unusable`), end-to-end cancellation propagation (logged `cancelled`, not `error`), and **auto-triggered model swap** when no `READY` runner advertises the required capability but a candidate runner could. PHI-redacted structured logs and Prometheus `/metrics` now carry generation signals (queue depth, first-token/total latencies, token counts, outcome, model+digest).

This phase produces **proposals only** — the Gateway still never calls Supabase, never resolves entity ids, and never executes commands. The Flutter approval UI, `lookup_required` resolution, and degradation UX are the Phase 3 feature. The technical approach (Phase 0 research) extends the existing **Python 3.12 + FastAPI/Uvicorn** Gateway with new `pipeline/`, `agents/`, and `validation/` modules; streaming uses FastAPI `StreamingResponse` over SSE; constrained decoding uses Ollama's `format: <json_schema>` (and a GBNF alternative is documented for `llama-server`); tests extend the Phase 1 `pytest` harness with a scriptable fake runner that emits scripted token streams.

## Technical Context

**Language/Version**: Python 3.12 for the AI Gateway (async, extends Phase 1 implementation). Model Runner is **Ollama** (Phase 1 baseline; Qwen3-4B Q4_K_M, digest-pinned). No new runtime language introduced. *(Reuses Phase 1 R-001 decision; no NEEDS CLARIFICATION.)*

**Primary Dependencies**: Existing Phase 1 stack — FastAPI + Uvicorn (HTTP/ASGI, streaming via `StreamingResponse`), `httpx` (async OpenAI-compatible runner client, extended for SSE consumption + grammar-constrained request format), PyJWT + `cryptography` (auth, unchanged), `pydantic` v2 + `pydantic-settings` + PyYAML (config; also used for response-envelope schema validation), `prometheus-client` (`/metrics`, extended), `structlog` (logs, extended for generation fields). New: `jsonschema` (defense-in-depth schema validation even though grammar makes structurally invalid JSON impossible), and Ollama's native **`format: <json_schema>`** parameter for constrained decoding (no extra library — it is an Ollama API field). Dev/test: `pytest` + `pytest-asyncio` + `httpx.ASGITransport` (extended), `respx` (scripted runner streams), `pytest-timeout`. **Still no Supabase SDK, no Postgres driver, no service-role key anywhere in `ai/`.**

**Storage**: Local files only — unchanged from Phase 1. Gateway config (`gateway.yaml`/env) gains new keys (queue depth/wait, per-caller in-flight cap, timeouts, confidence threshold, `log_verbatim_retention_hours`); structured log files are rotated with retention policy (verbatim mode default off, 24h retention when enabled). The Ollama model store (`models_dir`) is unchanged. **No database of any kind in the AI layer.**

**Testing**: `pytest` unit + contract suites under `ai/gateway/tests/`, extending Phase 1's harness. A scriptable **fake runner** (extended) emits scripted token streams, scripted validations, scripted first-token delays, and lifecycle transitions; an in-process ASGI client drives the auth matrix, error contract, capabilities, SSE event-shape conformance, resilience (saturation/timeout/cancel/retry), prompt-injection fuzzing, and PHI-redaction assertions. Property/fuzz tests over many scheduling prompts assert grammar enforcement (structurally invalid JSON is impossible with grammar on). The Phase 1 isolation scan remains a build gate and is unchanged in scope. End-to-end "book Ahmed with Dr Ali tomorrow 5pm" → schema-valid `create_appointment` envelope with `requires_resolution: "lookup_required"` and matching `display_summary` gates the feature exit.

**Target Platform**: Clinic **server node** on a trusted LAN (Linux or Windows), default **single-node** (Gateway + one runner co-located, unchanged from Phase 1). Ports unchanged — Gateway `8090`, Ollama `127.0.0.1:11434` (AI-internal only). Packaged via the existing Docker Compose (Linux) or supervised service (Windows) with `restart: always`; graceful SIGTERM drain is added in this phase.

**Project Type**: **Extends the existing isolated AI layer** introduced by feature 015. No changes to Flutter, Supabase, or PostgreSQL in this feature (no migration, no RPC, no new table). The Gateway remains the single AI URL; the generate route evolves from stub to real, and the capabilities report begins advertising `command` tasks and the four scheduling command types.

**Performance Goals**: On a modest clinic CPU node with one Qwen3-4B runner — first-token latency **≤ 15 s** default timeout (model-swap window extended to 60 s), total inference **≤ 45 s**; queue wait **≤ 20 s**; saturated callers receive `503 ai_busy`+`Retry-After` with bounded memory (queue depth ≤ `queue_max_depth` default 16). Streaming token deltas begin reaching the client as soon as the first token is produced. The per-request Gateway overhead (excluding inference) SHOULD stay **≤ 50 ms p95** (Phase 1 budget preserved). Cancellation frees the queue slot within one poll cycle.

**Constraints**: Absolute AI↔clinic-DB isolation preserved (no DB creds, no Supabase calls — the AI layer is **proposal-only** this phase); runner stays non-client-routable; CORS explicit allowlist unchanged; PHI-minimized logs by default (`log_verbatim=false`); verbatim mode opt-in with default 24h retention; plaintext HTTP on trusted LAN (TLS a Phase 5 concern); at most **one** model resident in runner RAM at any time (Phase 1 invariant); no new long-running service types (the Gateway is the same service from Phase 1); manual clinic UI MUST keep working with the AI layer fully down; all failures map to the typed error contract.

**Scale/Scope**: One clinic, single-node default; a handful of runners at most (multi-node exercised only with fake runners in tests — not a production requirement of this phase); tens of staff clients; low concurrency (a few simultaneous generation requests). New code lives entirely in `ai/gateway/src/gateway/` (new `pipeline/`, `agents/`, `validation/` modules; the `api/generate_stub.py` is replaced by `api/generate.py` with non-streaming + SSE handlers) plus a heavy test suite. No client or backend code.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] **Clinic fit / scale**: Targets small-to-mid clinics on modest CPU-only LAN hardware; single-node default; multi-node and cloud models explicitly out of scope (spec Assumptions). No hospital/enterprise assumptions.
- [x] **Simple operational model**: Adds **no new long-running service** — the Gateway is the same Phase 1 service, extended with new modules. No message queues (the per-capability FIFO queue is an in-process bounded buffer with backpressure, **not** a queue service/broker — explicitly within the constitution's "no message queues" rule, which targets infrastructure sprawl, not in-process data structures), no Kubernetes, no custom *primary* backend service.
- [x] **Layer ownership explicit**: Flutter unchanged (client integration is feature 018 / Phase 3); Supabase/PostgreSQL untouched (no migration/RPC/table); the AI layer (Gateway + Runner) remains self-contained and communicates only over HTTP. The Gateway still validates Supabase-issued JWTs offline and makes **zero** outbound calls to Supabase.
- [x] **Backend authority / data integrity**: No protected writes occur in this feature (the AI layer is **proposal-only**: it returns Command Protocol envelopes but does not call Supabase, resolve entities, or execute commands). The invariant "AI proposes, human approves, Supabase executes" is preserved trivially — there is no write path from the AI layer. Authoritative permission enforcement stays at the eventual approved-RPC execution (Phase 3).
- [x] **Security**: Authenticated (offline JWT, reused from Phase 1), coarse permission-gated (`ai.access` role map, reused), explicit CORS allowlist (unchanged), runner non-routable (unchanged), PHI-minimized auditable local logs (extended with generation fields + 24h verbatim retention), prompt-injection mitigations (immutable server-side system prompt + delimited untrusted regions + command catalog allowlist + grammar/schema enforcement). Tenant/branch scoping still enforced authoritatively at Supabase RPC/RLS in Phase 3; the Gateway performs no data reads so needs none.
- [x] **AI isolation & graceful degradation**: AI holds no DB credentials (isolation scan remains a build gate), executes no writes, returns structured outputs only (Command Protocol envelope). With the AI layer fully down, all manual clinic workflows continue unchanged (the layer is strictly additive; FR-029, SC-007).

### Post-Design Re-Check

- [x] Design keeps `ai/` free of any Supabase SDK, Postgres driver, or service-role key; the Phase 1 isolation scan (`scripts/isolation_scan.py`) remains a build gate and is **unchanged** in scope (still fails on any DB credential / service-role key / DB-client import anywhere in `ai/`).
- [x] The Gateway still makes **zero** outbound calls to Supabase and **zero** calls off the clinic LAN across all generation paths (asserted by the test suite; SC-010).
- [x] No new database objects, migrations, or RPCs; existing `ai.access` RBAC reused; the four scheduling command types map to **existing** appointment RPCs that the manual UI already uses (the AI never calls them in this phase — execution is Phase 3 — but the catalog is aligned to §9.3 so later approval-gated execution needs no new Supabase feature).
- [x] Real generation replaces the stub; the capabilities report advertises `command` + the four scheduling command types + `streaming` consistent with `streaming_enabled` (FR-026, SC-011) — no hidden AI action path; the Gateway remains proposal-only (FR-027).
- [x] Observability is local-file + `/metrics` only; logs PHI-redacted by default with 24h verbatim retention when opted in (FR-022/FR-023, SC-009); nothing is persisted to the clinic DB (FR-030).
- [x] Resilience envelope uses an **in-process** bounded per-capability FIFO queue (not a broker) with backpressure — within the simplicity budget; cancellation propagates; timeouts and single idempotent retry are bounded; `422 ai_unusable` is terminal and not retried; model-swap auto-trigger preserves one-model-in-RAM invariant.

**No constitution violations — Complexity Tracking is omitted.** The in-process bounded queue is not a "message queue" in the constitution's sense (no broker, no infrastructure, no separate process); it is backpressure bookkeeping inside the single Gateway service already ratified in feature 015.

## Project Structure

### Documentation (this feature)

```text
specs/016-ai-generation-scheduling/
├── plan.md              # This file (/speckit-plan output)
├── research.md         # Phase 0 output — pipeline + constrained-decoding decisions
├── data-model.md        # Phase 1 output — request/envelope entities + state transitions
├── quickstart.md        # Phase 1 output — generate request + verify runbook
├── contracts/           # Phase 1 output — Gateway generate API + command envelope + scheduling schemas
│   ├── gateway-openapi.yaml   # extends Phase 1 with /v1/ai/generate (both modes)
│   ├── command-protocol.md     # Command Protocol envelope (incl. needs_clarification)
│   ├── scheduling-schema.md   # JSON schemas for the 4 scheduling commands + grammar mapping
│   └── error-contract.md       # extends Phase 1 with ai_busy / ai_no_capacity / ai_timeout / ai_unusable
├── checklists/
│   └── requirements.md  # /speckit-specify output (already present, validated)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
ai/gateway/                              # Existing Phase 1 service, EXTENDED in place
├── pyproject.toml                       # +jsonschema (defense-in-depth); deps otherwise unchanged
├── Dockerfile                           # unchanged (auto-restart + SIGTERM grace already baseline)
├── config/
│   └── gateway.example.yaml             # +queue_max_depth/_wait, max_inflight_per_caller,
│                                         #  timeout_total_s/_first_token_s/_model_swap,
│                                         #  confidence_threshold, log_verbatim_retention_hours
├── src/gateway/
│   ├── main.py                          # lifespan: start pipeline supervisors + signal handlers
│   ├── api/
│   │   ├── generate.py                  # NEW — POST /v1/ai/generate (non-stream + SSE); replaces stub
│   │   ├── generate_stub.py             # REMOVED (logic migrated to generate.py)
│   │   ├── capabilities.py             # EXTENDED — advertise `streaming`, `command`, 4 command types
│   │   └── errors.py                    # EXTENDED — ai_busy / ai_no_capacity / ai_timeout / ai_unusable
│   ├── agents/                          # NEW — per-agent prompt + schema + grammar (§9.3)
│   │   ├── __init__.py
│   │   ├── base.py                      # Agent interface: system_prompt + grammar + schema + validators
│   │   └── scheduling/
│   │       ├── __init__.py
│   │       ├── agent.py                 # system prompt (immutable; delimited untrusted regions)
│   │       ├── schemas.py               # pydantic models for create/reschedule/cancel/update_status
│   │       ├── grammar.py               # JSON-schema → Ollama `format:` mapping (GBNF alt documented)
│   │       └── validators.py            # semantic checks: no past date, legal enums, summary matches params
│   ├── pipeline/                        # NEW — resilience envelope (§7)
│   │   ├── __init__.py
│   │   ├── queue.py                     # bounded FIFO per capability class + backpressure + per-caller cap
│   │   ├── timeout.py                   # first-token / total / model-swap timeout orchestration
│   │   ├── retry.py                     # single idempotent retry preferring different healthy runner
│   │   ├── cancel.py                    # cancellation propagation client→Gateway→runner; queue slot free
│   │   └── swap.py                      # auto-trigger model swap when no READY capability match
│   ├── validation/                      # NEW — defense-in-depth (§7.3)
│   │   ├── __init__.py
│   │   ├── schema_check.py              # jsonschema validation against command schema
│   │   ├── semantic.py                  # agent-agnostic semantic gate then agent-specific validators
│   │   └── envelope.py                  # assemble Command Protocol envelope incl. needs_clarification
│   ├── routing/
│   │   └── selector.py                  # EXTENDED — choose by capability + health + least-busy + swap trigger
│   ├── runners/
│   │   └── openai_client.py             # EXTENDED — grammar-constrained chat completion + SSE streaming
│   ├── obs/
│   │   ├── logging.py                   # EXTENDED — generation fields: agent, model+digest, latencies, tokens, outcome
│   │   ├── redaction.py                 # NEW — PHI-redacting processor surfaced for reuse/inspection
│   │   └── metrics.py                   # EXTENDED — queue depth, first-token/total latencies, tokens/sec, outcome
│   └── auth/ dependencies.py            # unchanged — offline JWT + ai.access gate
└── tests/
    ├── fixtures/
    │   └── fake_runner.py               # EXTENDED — scripted token streams, first-token delays, swap events
    ├── unit/
    │   ├── pipeline/                    # queue/timeout/retry/cancel/swap unit tests
    │   ├── agents/scheduling/           # schema/grammar/validator tests
    │   └── validation/                  # envelope assembly + semantic gate
    └── contract/
        ├── generate_non_stream.py       # happy path per command type → schema-valid envelope
        ├── generate_stream.py           # SSE event shape + final==non-stream + error-event contract
        ├── resilience.py                # saturation/backpressure/timeouts/retry-no-retry/cancel
        ├── prompt_injection.py          # off-catalog command impossible; system prompt immutable
        ├── phi_redaction.py             # verbatim off → no patient-name fixtures; verbatim on → retention
        ├── isolation_reaffirm.py        # zero Supabase calls across generation tests
        └── phase1_regression.py          # /health, /ready, /v1/capabilities, auth matrix still pass

ai/runners/                              # Existing — unchanged (Qwen3-4B Q4_K_M, digest-pinned)
```

**Structure Decision**: The feature **extends the existing Phase 1 `ai/gateway/` service in place** — no new service, no new top-level tree, no new runtime. Three new source modules (`agents/`, `pipeline/`, `validation/`) own the new behavior; the stub `api/generate_stub.py` is replaced by a real `api/generate.py` that serves both non-streaming and SSE paths. The runner is untouched (constrained decoding is a request parameter to the existing OpenAI-compatible runtime, not a code change on the runner host). The Phase 1 isolation scan, auth, routing/registry, health/ready, capabilities, and observability skeletons are all reused and extended, preserving the replaceable layer boundaries: the Gateway still talks to runners only over the OpenAI-compatible HTTP contract (runtime swappable), still validates Supabase JWTs offline (backend swappable, never coupled), and now exposes one stable client-facing generation endpoint. Nothing in `ai/` imports or references the Flutter or Supabase/PostgreSQL code trees, and the unchanged isolation scan continues to enforce this mechanically.

## Complexity Tracking

> No Constitution Check violations. Section intentionally omitted.