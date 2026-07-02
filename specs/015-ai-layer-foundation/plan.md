# Implementation Plan: AI Layer Foundation — Isolated Gateway Spine + Model Runner (015)

**Branch**: `015-ai-layer-foundation` | **Date**: 2026-07-02 | **Spec**: `specs/015-ai-layer-foundation/spec.md`

**Input**: Feature specification from `specs/015-ai-layer-foundation/spec.md`

## Summary

Deliver the **control plane** of the AI layer as a new, fully isolated `ai/` tree (AI Service Specification v2, Appendix B, Phase 1 → roadmap V2-1). Two logical roles: a **Model Runner** (Ollama serving one digest-pinned model, one-model-in-RAM with on-demand swap, OpenAI-compatible, non-client-routable) and an **AI Gateway** that can **authenticate callers** (offline Supabase-JWT validation via shared-secret *or* JWKS + coarse `ai.access` role gate), **discover/health-poll/route among runners** (in-memory pull-based registry + lifecycle state machine + capability→health→least-busy selection), **report capabilities** (`GET /v1/capabilities`), and **observe itself** (PHI-redacted structured file logs + Prometheus `/metrics`). It ships a **stubbed** `POST /v1/ai/generate` that returns a typed "not implemented" error so clients can feature-detect the route.

This feature produces **no functional AI generation** (no prompts, agents, grammars, structured output, or inference — those are feature 016 / Phase 2). It is nonetheless a complete, independently testable capability. The technical approach chosen after research (Phase 0) is a **Python 3.12 + FastAPI/Uvicorn** Gateway packaged as a Docker service, fronting a **vanilla Ollama** runner, with a heavy `pytest` suite (auth matrix, registry/lifecycle/routing/failover, config validation, runner contract, and an automated isolation scan that gates the build). Delivery is priority-sequenced within this one feature: **P1** (US1 — isolated tree + runner + health/liveness/readiness), **P2** (US2 — auth + typed error contract + CORS), **P3** (US3 — registry/polling/routing/capabilities), with observability and the generate stub woven across P1–P3.

## Technical Context

**Language/Version**: Python 3.12 for the AI Gateway (async). Model Runner is **Ollama** (no bespoke code on the runner host; a `Modelfile` + digest pin only). Bash/PowerShell for install/supervise scripts. *(Gateway language was deferred to planning by the spec; resolved to Python in `research.md` R-001.)*

**Primary Dependencies**: FastAPI + Uvicorn (HTTP/ASGI, async, SSE-ready for Phase 2), `httpx` (async client for runner polling + OpenAI-compatible calls), PyJWT + `cryptography` (offline HS256 **and** JWKS/RS256 validation; `PyJWKClient` with local cache), `pydantic` v2 + `pydantic-settings` + PyYAML (typed config with fail-fast validation), `prometheus-client` (`/metrics`), `structlog` (JSON logs with a PHI-redacting processor). Dev/test: `pytest`, `pytest-asyncio`, `httpx.ASGITransport`/`respx` (fake runner + in-process Gateway), `ruff` (lint/format). **No Supabase SDK, no Postgres driver, no service-role key anywhere in `ai/`.**

**Storage**: Local files only — Gateway config (`gateway.yaml`/env), local structured log files (rotated), and the Ollama model store (`models_dir`). **No database of any kind** in the AI layer.

**Testing**: `pytest` unit + contract suites under `ai/gateway/tests/` using a scriptable **fake runner** fixture (drives every lifecycle transition) and in-process ASGI calls for the auth matrix / error contract / capabilities. A standalone `ai/gateway/scripts/isolation_scan.py` (also runnable in CI) fails if any DB credential/service-role key/DB-client import appears in `ai/`. Runner contract checks assert OpenAI-compatible shapes, one-model-in-RAM swap, and client-subnet non-routability.

**Target Platform**: Clinic **server node** on a trusted LAN (Linux or Windows), default **single-node** (Gateway + one runner co-located). Gateway listens on `8090`; Ollama on `127.0.0.1:11434` (AI-internal only). Packaged via Docker Compose (Linux) or a supervised service (Windows) with `restart: always`.

**Project Type**: New **isolated AI layer** added alongside the existing Flutter client and Supabase/PostgreSQL backend. No changes to Flutter, Supabase, or PostgreSQL in this feature (no migration, no RPC, no new table). The Gateway becomes the single AI URL clients will target in later phases.

**Performance Goals**: Control-plane only. Gateway auth + route decision overhead SHOULD be ≤ 50 ms p95 (excludes any runner call; no inference this phase). Health poll cadence default 10 s; a downed runner reaches `UNREACHABLE` within `unreachable_after_failures` (default 3 ≈ 30 s) and readiness flips accordingly. Offline JWT validation adds no network round-trip (JWKS keys cached). Startup (Gateway ready to authenticate/route, excluding model load) SHOULD be < 5 s.

**Constraints**: Absolute AI↔clinic-DB isolation (no DB creds, ever — Q11); runner bound to localhost/AI-internal and never client-routable (§11.3); CORS explicit allowlist (no `*`); PHI-minimized logs by default; plaintext HTTP acceptable on trusted LAN for V2 (TLS optional in installer, mandatory once off-LAN); at most **one** new long-running service type beyond the model runtime (the Gateway) to respect the simplicity budget (§2.7); CPU-only, RAM-conscious (one model resident). Manual clinic UI MUST keep working with the AI layer fully down.

**Scale/Scope**: One clinic, single-node default; a handful of runners at most (multi-node is config-only, out of scope here); tens of staff clients. New code lives entirely in `ai/`: ~1 Gateway service (≈ 8 modules: api, auth, routing, runners, config, obs), 1 example config, 1 runner runbook + Modelfile/digest pin, 1 isolation-scan script, 1 Dockerfile/compose, and a heavy test suite. No client or backend code.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] **Clinic fit / scale**: Targets small-to-mid clinics on modest CPU-only LAN hardware; single-node default; multi-node and cloud models are explicitly out of scope / config-gated-off (spec Assumptions, §3.2). No hospital/enterprise assumptions.
- [x] **Simple operational model**: Adds exactly one new long-running service type (the AI Gateway) beyond the model runtime — the AI-layer service explicitly ratified in the spec (R1); it is **not** a clinic backend and holds no data-plane role. No message queues, no Kubernetes, no custom *primary* backend service. Within the constitution's simplicity budget; justification recorded in Complexity Tracking is not required because the Gateway is the AI layer itself (Principle II: "AI runs as an isolated service"), not a new core backend.
- [x] **Layer ownership explicit**: Flutter unchanged (client work is a later feature); Supabase/PostgreSQL untouched (no migration/RPC/table); the AI layer (Gateway + Runner) is self-contained and communicates only over HTTP. Gateway validates Supabase-issued JWTs **offline** and never connects to Supabase.
- [x] **Backend authority / data integrity**: No protected writes occur in this feature (no generation, no RPC calls). The invariant "AI proposes, human approves, Supabase executes" is preserved trivially — the AI layer has no write path and no DB access at all.
- [x] **Security**: Authenticated (offline JWT), coarse permission-gated (`ai.access` role map; authoritative per-command enforcement stays at Supabase in later phases), explicit CORS allowlist, least-privilege OS accounts, runner non-routable, PHI-minimized auditable local logs. Tenant/branch scoping is enforced authoritatively at Supabase RPC/RLS on later approved actions; the Gateway performs no data reads so it needs none.
- [x] **AI isolation & graceful degradation**: AI holds no DB credentials (enforced by an automated isolation scan that gates the build), executes no writes, and returns structured outputs only. With the AI layer fully down, all manual clinic workflows continue unchanged (the layer is strictly additive).

### Post-Design Re-Check

- [x] Design keeps `ai/` free of any Supabase SDK, Postgres driver, or service-role key; the isolation scan (`scripts/isolation_scan.py`) is a build gate (FR-002, SC-005).
- [x] Runner binds to `127.0.0.1`/AI-internal interface only; contract test asserts client-subnet non-routability (FR-010, SC-008).
- [x] No new database objects, migrations, or RPCs; existing `ai.access` RBAC is reused via an offline role map (§17.2); no Supabase change required.
- [x] Generate route is a **stub** returning a typed error and performs zero inference; capabilities advertises no generation tasks (FR-031, SC-011) — no hidden AI action path is introduced.
- [x] Observability is local-file + `/metrics` only; logs PHI-redacted by default (FR-033–FR-035); nothing is persisted to the clinic DB (FR-032).
- [x] Both JWT validation mechanisms are offline (no network to Supabase); JWKS keys are cached locally (FR-015, SC-004/SC-010).

**No constitution violations — Complexity Tracking is omitted.** The single new service (Gateway) is the AI layer mandated by Principle II and ratified in the source spec (R1), not a new core backend, so it does not require a complexity justification.

## Project Structure

### Documentation (this feature)

```text
specs/015-ai-layer-foundation/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 output — runtime + design decisions
├── data-model.md        # Phase 1 output — control-plane entities & state machine
├── quickstart.md        # Phase 1 output — stand-up + verify runbook
├── contracts/           # Phase 1 output — Gateway API + runner poll contracts
│   ├── gateway-openapi.yaml
│   ├── runner-poll.md
│   └── error-contract.md
├── checklists/
│   └── requirements.md  # /speckit-specify output (already present)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
ai/                                     # New, isolated AI layer (NO Supabase creds anywhere)
├── README.md                           # AI layer overview + security invariants
├── gateway/
│   ├── pyproject.toml                  # Python 3.12 project; pinned deps; ruff/pytest config
│   ├── Dockerfile
│   ├── config/
│   │   └── gateway.example.yaml        # ALL §14 keys + documented defaults
│   ├── src/gateway/
│   │   ├── main.py                     # ASGI app bootstrap, lifespan (start/stop poller), signal handling
│   │   ├── config/
│   │   │   └── settings.py             # pydantic-settings model; fail-fast validation (FR-003/FR-004)
│   │   ├── api/
│   │   │   ├── health.py               # GET /health, GET /ready (FR-014)
│   │   │   ├── capabilities.py         # GET /v1/capabilities (FR-029)
│   │   │   ├── generate_stub.py        # POST /v1/ai/generate -> 501 not_implemented (FR-031)
│   │   │   ├── metrics.py              # GET /metrics (FR-035)
│   │   │   └── errors.py               # typed error envelope + exception handlers (FR-020)
│   │   ├── auth/
│   │   │   ├── jwt_validator.py        # HS256 + JWKS offline validation (FR-015/FR-016)
│   │   │   └── role_map.py             # role -> ai.access; reloadable (FR-017/FR-018)
│   │   ├── routing/
│   │   │   ├── registry.py             # in-memory runner registry (FR-023/FR-024)
│   │   │   ├── lifecycle.py            # state machine UNKNOWN..UNREACHABLE (FR-025)
│   │   │   ├── health_poller.py        # pull-based poll loop (FR-023)
│   │   │   └── selector.py             # capability -> health -> least-busy (FR-026/FR-027/FR-028)
│   │   ├── runners/
│   │   │   └── openai_client.py        # OpenAI-compatible client (poll /v1/models, /health) (FR-006/FR-013)
│   │   └── obs/
│   │       ├── logging.py              # structlog JSON + PHI-redaction processor (FR-033/FR-034)
│   │       └── metrics.py              # prometheus collectors (FR-035)
│   ├── scripts/
│   │   └── isolation_scan.py           # CI gate: no DB creds / service-role / DB drivers (FR-002)
│   └── tests/
│       ├── conftest.py                 # in-process ASGI client, config fixtures
│       ├── fixtures/
│       │   └── fake_runner.py          # scriptable runner (health responses, lifecycle walk)
│       ├── unit/                       # config, jwt, role_map, lifecycle, selector, redaction
│       └── contract/                   # auth matrix, registry/failover, capabilities, error contract, runner contract, isolation
└── runners/
    ├── ollama/
    │   ├── docker-compose.yaml         # Ollama service, LAN-internal bind, restart: always
    │   ├── Modelfile                   # Qwen3-4B Q4_K_M definition
    │   └── digests.md                  # pinned model digests (FR-008/§11.6)
    └── README.md                       # model install / GGUF-path runbook (FR-012)
```

**Structure Decision**: A single new top-level `ai/` tree per AI Service Spec §13, split into `gateway/` (the only new long-running service) and `runners/` (vanilla Ollama config + runbook, no custom code). This preserves replaceable layer boundaries: the Gateway talks to runners only over the OpenAI-compatible HTTP contract (runtime swappable), validates Supabase JWTs offline (backend swappable, never coupled), and exposes a stable client-facing API (`/health`, `/ready`, `/v1/capabilities`, stubbed `/v1/ai/generate`, `/metrics`). Nothing in `ai/` imports or references the Flutter or Supabase/PostgreSQL code trees, and the isolation scan enforces this mechanically.

## Complexity Tracking

> No Constitution Check violations. Section intentionally omitted.
