# Phase 0 Research: AI Layer Foundation (015)

This document resolves the one item the spec deferred to planning (Gateway implementation
language/runtime) and records the supporting design decisions for the control plane. All decisions
are subordinate to the three non-negotiable invariants (AI proposes only / no clinic-DB creds /
manual UI works with AI down) and to the AI Service Specification v2.

No `NEEDS CLARIFICATION` markers remain after this phase.

---

## R-001 — Gateway implementation language/runtime

- **Decision**: **Python 3.12 + FastAPI + Uvicorn** for the AI Gateway. The Model Runner is **vanilla
  Ollama** (no custom code on the runner host).
- **Rationale**:
  - The AI Service Spec §13 explicitly permits `main.(py|go)`; both are sanctioned.
  - Phase 2+ (the immediate next feature) needs JSON-schema/GBNF grammar generation, schema + semantic
    validation, and prompt/agent assembly — all markedly more ergonomic in Python (`pydantic`,
    `jsonschema`, grammar tooling) than in Go. Keeping the whole AI layer in one language minimizes
    cognitive load and rework at the Phase-1→Phase-2 seam.
  - The Gateway is **I/O-bound** (proxying to a runner, polling health, validating JWTs); async
    Python (ASGI/Uvicorn) handles this well. The heavy compute lives in the runner, not the Gateway,
    so Go's concurrency/throughput advantage is not decisive here.
  - Mature, well-audited libraries exist for every Phase-1 need: `PyJWT`+`cryptography` (HS256 **and**
    JWKS offline validation), `prometheus-client` (`/metrics`), `structlog` (JSON logs + redaction),
    `pydantic-settings`+`PyYAML` (typed, fail-fast config), `httpx` (async client + streaming for
    Phase 2 SSE), `pytest`+`respx` (fast in-process contract tests).
  - Docker packaging neutralizes Go's single-binary deployment edge for a supervised clinic service.
- **Alternatives considered**:
  - **Go (net/http or Gin)**: single static binary, excellent concurrency, low memory. Rejected as
    primary because the downstream grammar/validation/agent work is Python-centric and splitting the
    AI layer across two languages adds friction; the Gateway is not throughput-bound. Remains a valid
    future re-implementation if the Gateway ever becomes CPU/latency critical (contracts are language-
    agnostic, so a swap would not touch clients).
  - **Node/TypeScript**: viable, but weaker fit for the Phase-2 structured-output ecosystem and adds a
    third language to the project (Dart + SQL already present).

## R-002 — Model runtime & default model

- **Decision**: **Ollama** as the default runner runtime, serving **Qwen3-4B (Q4_K_M)** by default,
  with **Llama 3.2 3B** / **Qwen2.5 1.5B** as documented RAM-constrained fallbacks. Model source is
  **digest-pinned**.
- **Rationale**: Ollama exposes an OpenAI-compatible API (`/v1/chat/completions`, `/v1/models`)
  natively, requires no bespoke agent on the host (enables pull-based polling), keeps one model in RAM
  by default, and supports GBNF/JSON-schema-constrained decoding needed later. Qwen3-4B is strong at
  JSON/tool-calling at ~3–4 GB resident on CPU (AI Service Spec §6.3, Q9). Digest pinning satisfies
  the model-integrity requirement (§11.6).
- **Alternatives considered**: `llama-server` (llama.cpp) — equally valid behind the same contract and
  documented as a config alternative in the runbook; vLLM — GPU-oriented, deferred to a future GPU
  node (no client/Gateway change needed). Runtime is replaceable by design (FR-006).

## R-003 — Offline JWT validation (both mechanisms)

- **Decision**: Support **both** HS256 shared-secret (`jwt_secret`) and asymmetric **JWKS**
  (`jwks_url`, RS/ES family) validation, selected by which config material is present. Use `PyJWT`;
  for JWKS use `PyJWKClient` with a **local key cache** (refreshed on a TTL / on unknown `kid`) so no
  per-request network call occurs. Validate signature + `exp` + `nbf` (+ `iat`) offline; extract
  `staff_role` (and `exp`/`nbf`) claims only.
- **Rationale**: Directly implements clarification session decision and §11.2/§14/Q4/Q14. Shared secret
  matches the current on-LAN Supabase GoTrue default (HS256); JWKS is ready for the off-LAN case
  without a rewrite. Offline validation keeps the isolation invariant (no Supabase network/DB call).
- **Precedence rule** (documented per FR-015): if both `jwt_secret` and `jwks_url` are set, **JWKS
  takes precedence** and the Gateway logs a startup warning; operators should configure exactly one.
- **`ai.access` gate**: current Supabase claims carry `staff_role`, not permission keys (§17.2), so the
  Gateway maps role → `ai.access` via a config table (`role_ai_access`) mirroring
  `roles_permissions` defaults (administrator/doctor granted; receptionist/lab_staff denied). The map
  is reloadable (SIGHUP/file-watch or periodic re-read) so admin changes are not stale (FR-018).
- **Alternatives considered**: dedicated static AI token (rejected in Q4 — worse auditability, another
  secret to manage); embedding a `permissions` array in the JWT (optional future migration, §17.2 —
  not required for V2; role map suffices).

## R-004 — Registry & health discovery (pull-based)

- **Decision**: **Pull-based** health polling of statically configured runners (default every 10 s)
  into an **in-memory** registry holding status, last-seen, measured latency, loaded model + digest,
  and advertised features. Poll uses the runner's OpenAI-compatible `/v1/models` (and/or `/health`).
  Push registration (`/internal/runners/register|heartbeat`) is implemented behind
  `enable_push_registration` (default **off**), guarded by an internal shared secret and bound
  LAN-internal only.
- **Rationale**: Works with vanilla Ollama (no agent on the host), matches the static-IP discovery
  principle (A5), and yields the liveness/registry the design needs (§6.2/F3). In-memory only —
  registry is ephemeral control state, never persisted (Principle: stateless w.r.t. clinical data).
- **Alternatives considered**: push-only heartbeats (v1's approach) — rejected as default because it
  requires custom code on every model host; kept as an optional mode for future dynamic scaling.

## R-005 — Runner lifecycle state machine

- **Decision**: Implement states `UNKNOWN → STARTING → READY → BUSY → DEGRADED → UNREACHABLE` with
  transitions per AI Service Spec §8.2. `UNREACHABLE` after `unreachable_after_failures` (default 3)
  consecutive failed polls; `DEGRADED` on elevated latency / sporadic errors (deprioritized, still
  routable); `STARTING` during model load/swap (not routable). Route only to `READY`/`DEGRADED`.
  `/ready` is true iff ≥ 1 runner is `READY`.
- **Rationale**: Directly normative; makes health honest and routing safe. Encapsulated in
  `lifecycle.py` as a pure, unit-testable transition function so the fake-runner suite can drive every
  edge deterministically.
- **Latency/error thresholds** (chosen defaults, configurable): `DEGRADED` when rolling-average poll
  latency exceeds a configurable ceiling (default 2× baseline or > 2 s) or on intermittent poll
  errors below the `UNREACHABLE` threshold. These are advisory defaults for the control plane; tuning
  is a deployment concern.

## R-006 — Routing / model selection

- **Decision**: `selector.py` applies, in order: (1) **capability match** (required) — runner must
  advertise the requested `task`/features (e.g. `json_grammar`, context length); (2) **health filter**
  (required) — `READY` preferred, `DEGRADED` deprioritized, exclude `STARTING`/`UNREACHABLE`;
  (3) **least-busy** (in-flight counter) with **round-robin** tie-break. Session affinity is a
  reserved hook (optional, off).
- **Rationale**: §5 normative. Because no generation runs this phase, selection is **exercised via
  tests** (fake runners with declared capabilities/in-flight) rather than serving real traffic; this
  proves the logic is correct before Phase 2 wires it to `/v1/ai/generate`.
- **Note**: clients cannot influence routing beyond declaring logical `task`/capabilities and are
  never configured with runner addresses (FR-028).

## R-007 — Typed error contract & the generate stub

- **Decision**: A single error envelope `{ "error": { "code", "message", "request_id" } }` with the
  §10.4 code↔status mapping, implemented as FastAPI exception handlers so **every** endpoint emits it
  uniformly. The stubbed `POST /v1/ai/generate` returns **HTTP 501** with code `not_implemented`
  (a Phase-1-specific addition to the §10.4 table) and performs zero inference; `GET /v1/capabilities`
  reports `tasks: []` / `commands: []` while generation is stubbed.
- **Rationale**: Establishing the contract now (with a `request_id` on every response) means Phase 2
  endpoints inherit consistent, tested error behavior. The 501 stub lets the future Flutter client
  feature-detect the route without special-casing a missing endpoint (clarification decision).
- **Alternatives considered**: omit the route entirely (rejected per clarification — forces clients to
  distinguish "route absent" from "not enabled"); return 503 `ai_no_capacity` (reserved for "no healthy
  runner"; `not_implemented` is semantically clearer for "feature not built yet").

## R-008 — Observability (full, this phase)

- **Decision**: `structlog`-based **JSON structured logs to local rotating files** with a
  **PHI-redaction processor** active by default (`log_verbatim=false`); a Prometheus `/metrics`
  endpoint via `prometheus-client`. Log fields available this phase: `request_id`, `caller_staff_id`
  (from JWT), endpoint, outcome (`ok`/`error`/`unauthenticated`/`forbidden`/`not_implemented`), chosen
  runner, runner status transitions, and latencies. Metrics: request rate, error rate by code, queue
  depth (reserved/0 this phase), per-runner health/latency, in-flight.
- **Rationale**: Clarification decision to include full observability now (§8.4). Local files only (no
  DB — §17.1). Redaction-by-default protects any future PHI-bearing fields and is verified by a test
  asserting patient-name fixtures never appear verbatim when `log_verbatim=false`.
- **Alternatives considered**: deferring logging/metrics to Phase 2 (Appendix B's default split) —
  overridden by the user's clarification; building it now costs little and makes P1 operable.

## R-009 — Configuration surface & fail-fast

- **Decision**: A single `pydantic-settings` model loads from `gateway.yaml` (path via env) with env
  overrides, exposing **all §14 keys** with documented defaults. Unknown/invalid keys or type errors
  **fail fast at startup** with a message naming the offending key. `gateway.example.yaml` documents
  every key. Phase-2-only keys (queue depth/wait, timeouts, `streaming_enabled`,
  `enable_multi_command_plans`, `confidence_threshold`, `model_swap_first_token_timeout_s`) are
  present and parsed now (so the surface is stable) but several are inert until generation exists.
- **Rationale**: FR-003/FR-004; stabilizing the full config surface now avoids churn when Phase 2
  activates the inert keys. `pydantic` gives fail-fast validation for free.

## R-010 — Packaging, supervision & isolation enforcement

- **Decision**: Ship a Gateway `Dockerfile` and a `runners/ollama/docker-compose.yaml` (Ollama bound
  to `127.0.0.1:11434`, `restart: always`); document a Windows-service equivalent. Run under a
  least-privilege OS account with filesystem access limited to config, log dir, and model store.
  Enforce isolation with `scripts/isolation_scan.py` — a static scan (imports + secret patterns) that
  **fails CI** if any Supabase/Postgres client or DB credential/service-role key appears under `ai/`.
- **Rationale**: §3.2/§8.3/§11.3 + the isolation invariant. Making the scan a build gate turns the most
  important safety property (SC-005) into an automated, non-optional check.
- **Alternatives considered**: relying on code review for isolation (rejected — not enforceable/
  repeatable); systemd-only supervision (Docker `restart: always` is cross-platform-friendly and
  matches the Supabase stack's supervision model).

---

## Consolidated decisions

| Topic | Decision |
| --- | --- |
| Gateway runtime | Python 3.12 + FastAPI + Uvicorn |
| Runner runtime / model | Ollama; Qwen3-4B Q4_K_M (digest-pinned); 3B/1.5B fallbacks |
| JWT validation | Offline HS256 **and** JWKS (`PyJWT`/`PyJWKClient`, cached); JWKS precedence if both set |
| Authorization | `role → ai.access` map (reloadable), mirrors `roles_permissions` |
| Discovery | Pull-poll static runners (10 s) → in-memory registry; push mode off by default |
| Lifecycle | UNKNOWN→STARTING→READY→BUSY→DEGRADED→UNREACHABLE (3 failed polls) |
| Routing | capability → health → least-busy (round-robin tie-break); exercised via tests |
| Error contract | Uniform `{error:{code,message,request_id}}`; generate stub → 501 `not_implemented` |
| Observability | structlog JSON local files (PHI-redacted default) + Prometheus `/metrics` |
| Config | pydantic-settings, all §14 keys + defaults, fail-fast |
| Packaging/isolation | Docker + supervised restart; `isolation_scan.py` as a CI gate |

All Technical Context unknowns are resolved; ready for Phase 1 design.
