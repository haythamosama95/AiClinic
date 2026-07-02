# Feature Specification: AI Layer Foundation — Isolated Gateway Spine + Model Runner

**Feature Branch**: `015-ai-layer-foundation`

**Created**: 2026-07-02

**Status**: Draft

**Input**: User description: "Phase 1 from AI Service Specification v2 (Appendix B) — AI Layer Foundation: isolated Gateway spine + Model Runner. Roadmap V2-1. Satisfies §2, §3.2.1, §5, §6, §8.1, §8.2, §10.3, §10.4, §11.2, §13, §14, §17.2."

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

> **Scope anchor:** This feature delivers the **control plane** of the AI layer — an isolated
> component tree, a working Model Runner, and an AI Gateway that can **authenticate, discover
> runners, health-check, route, report capabilities, and observe itself**. It deliberately delivers
> **no functional AI generation** (no agents, no prompts, no structured output, no inference). The
> `POST /v1/ai/generate` route exists only as a **stub** that returns a typed "not implemented"
> response so clients can feature-detect it; real generation ships in the next feature (Phase 2 /
> V2-1). This is a complete, independently testable capability even though it produces no AI answer yet.

## Clarifications

### Session 2026-07-02

- Q: How should the Gateway perform offline JWT validation in Phase 1? → A: Implement **both** HS256 shared-secret (`jwt_secret`) and asymmetric JWKS (`jwks_url`) validation, selectable by configuration; on-LAN deployments use the shared secret, JWKS is available for when Supabase leaves the LAN.
- Q: What happens with `POST /v1/ai/generate` in Phase 1 (which delivers no generation)? → A: The route is **present as a stub** that returns a typed "not implemented" / no-capacity error and performs no inference; the capabilities report advertises no generation tasks.
- Q: What observability scope belongs in Phase 1? → A: **Full** — include PHI-redacted structured request/operational logging (local files) and a Prometheus-style `/metrics` endpoint now (§8.4), not deferred to Phase 2.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stand up an isolated, health-reportable AI layer (Priority: P1)

A clinic IT installer deploys the AI layer on the clinic server node: a Model Runner that hosts one
local model and an AI Gateway that fronts it. After starting the services, the installer needs to
confirm — without any AI answer being produced — that the AI layer is **alive**, **isolated from the
clinic database**, and **reporting its own health honestly**. The Gateway exposes a liveness check
and a readiness check; readiness only turns positive once at least one Model Runner has finished
loading its model and is serving.

**Why this priority**: This is the irreducible foundation. Without a running, isolated, health-honest
spine there is nothing to authenticate against, route to, or later generate with. It is also the
phase's central safety guarantee: the AI layer is provably separated from clinic data. It stands
alone as the minimum viable deliverable.

**Independent Test**: Start the Gateway and one Model Runner on a host; confirm the liveness endpoint
returns healthy immediately and the readiness endpoint turns positive only after the model finishes
loading. Run the automated isolation scan and confirm the AI layer contains no clinic-database
credentials or database client dependencies. Confirm the Model Runner is not reachable from a client
subnet.

**Acceptance Scenarios**:

1. **Given** the Gateway process is running but no runner has finished loading a model, **When** an operator checks readiness, **Then** readiness reports "not ready" while liveness still reports "healthy."
2. **Given** a Model Runner has finished loading its configured model, **When** an operator checks readiness, **Then** readiness reports "ready."
3. **Given** the assembled AI layer, **When** the isolation scan runs, **Then** it finds zero clinic-database credentials, service-role keys, or database-client dependencies and passes.
4. **Given** the Model Runner is bound to the AI-internal interface, **When** a request originates from a client subnet address, **Then** the runner is unreachable / refuses the connection.
5. **Given** the AI layer is entirely stopped or unreachable, **When** clinic staff use the standard manual UI, **Then** all manual clinic operations continue unchanged.

---

### User Story 2 - Authenticate and authorize every AI caller (Priority: P2)

Before the AI layer will do anything for a caller, the Gateway must confirm the caller is a
signed-in staff member whose role is permitted to use AI. The Gateway validates the caller's existing
Supabase login token **offline** (no call to Supabase, no database access) and checks that the caller's
role carries the `ai.access` grant. Anyone without a valid token is refused; anyone valid but without
the AI grant is refused with a distinct, typed reason.

**Why this priority**: PHI-bearing prompts will flow through this layer in later phases, so the front
door must be locked first. Establishing the auth boundary and the typed error contract now means every
later endpoint inherits a consistent, tested gate. Depends on US1 (a running Gateway) but is otherwise
independently testable against any protected endpoint.

**Independent Test**: Exercise a protected endpoint with a matrix of tokens — valid, tampered-signature,
expired, not-yet-valid, missing, and valid-but-role-without-`ai.access` — and confirm each maps to the
correct typed outcome (success / unauthenticated / forbidden). Run the matrix under **both** validation
mechanisms (shared-secret and JWKS configurations) to confirm each mode behaves identically. Confirm
validation performs no network call to Supabase.

**Acceptance Scenarios**:

1. **Given** a caller with a valid, unexpired staff token whose role has `ai.access`, **When** they call a protected endpoint, **Then** the request is accepted — regardless of whether the Gateway is configured for shared-secret or JWKS validation.
2. **Given** a caller with a token whose signature is tampered, **When** they call a protected endpoint, **Then** the request is rejected as unauthenticated.
3. **Given** a caller with an expired or not-yet-valid token, **When** they call a protected endpoint, **Then** the request is rejected as unauthenticated.
4. **Given** a caller with no authorization header, **When** they call a protected endpoint, **Then** the request is rejected as unauthenticated.
5. **Given** a caller with a valid token whose role lacks `ai.access`, **When** they call a protected endpoint, **Then** the request is rejected as forbidden (distinct from unauthenticated).
6. **Given** any request that fails, **When** the Gateway responds, **Then** the body carries a typed error with a stable code, a human-readable message, and a request identifier.
7. **Given** an administrator changes which roles hold `ai.access`, **When** the Gateway refreshes its role map, **Then** subsequent authorization decisions reflect the new grants.

---

### User Story 3 - Discover, monitor, and route among Model Runners (Priority: P3)

The Gateway must know, at all times, which Model Runners exist, whether each is healthy, what each can
do, and which one a future request should go to. It learns runners from configuration, polls each one
on a fixed cadence, tracks each runner through a defined lifecycle (starting → ready → busy/degraded →
unreachable → recovered), and can report the aggregate capability of the whole AI layer so a client can
feature-detect. Routing selection logic (capability match, health filter, least-busy) is exercised even
though no generation request is served yet.

**Why this priority**: This is the "control" in control plane. It makes the layer resilient and
observable and is the prerequisite for correct request routing in Phase 2. It builds on US1 and US2 but
is independently testable with simulated runners.

**Independent Test**: Point the Gateway at fake runners whose health responses are scripted to walk the
full lifecycle; confirm the registry reflects each transition, that readiness flips negative when all
runners become unreachable and recovers when a runner returns, that a runner missing a required
capability is excluded from selection, and that the capabilities report mirrors the live registry.

**Acceptance Scenarios**:

1. **Given** runners listed in configuration, **When** the Gateway starts, **Then** it polls each on the configured cadence and records status, last-seen time, and measured latency.
2. **Given** a runner that stops responding, **When** it fails the configured number of consecutive polls, **Then** it is marked unreachable and excluded from routing.
3. **Given** all runners are unreachable, **When** readiness is checked, **Then** readiness reports "not ready"; **When** a runner recovers, **Then** readiness reports "ready" again.
4. **Given** a request declares a required capability, **When** the Gateway selects among healthy runners, **Then** it excludes runners lacking that capability and, among the rest, prefers the least-busy (tie-broken round-robin).
5. **Given** a live registry, **When** a caller requests capabilities, **Then** the response lists each runner's status, loaded model name and version/digest, features, and context length, matching the registry.
6. **Given** a runner is loading or swapping its model, **When** its lifecycle is inspected, **Then** it reports "starting" and is not selected for routing until "ready."

---

### Edge Cases

- **AI layer fully down**: When the Gateway is unreachable, all standard (manual) clinic UI operations MUST continue to work unchanged; the AI layer is strictly additive.
- **No healthy runner**: With zero `READY` runners, readiness reports "not ready" and the layer advertises no serving capacity, rather than failing opaquely.
- **Runner cold-start / model swap**: Model loading takes seconds; the runner reports "starting" (not "ready") during the window and the Gateway does not route to it until it is ready.
- **Concurrent model swap**: Requests arriving at a runner mid-swap queue or receive a busy/retry signal until the runner returns to ready; no more than one model is resident in memory at any time.
- **Role map drift**: When an administrator changes the AI permission matrix, the Gateway's offline role→grant map is refreshed (reload or periodic refresh) so authorization decisions do not silently go stale.
- **Malformed / oversized request**: Requests with malformed bodies or oversized payloads are rejected with a typed `bad_request`, not a crash.
- **Expired session during use**: A caller whose token expires mid-session is rejected as unauthenticated and prompted to re-login.
- **Config error at startup**: Invalid or unparseable Gateway configuration fails fast at startup with a clear, actionable error rather than starting in an undefined state.
- **Non-client-routable runners**: A Model Runner MUST remain unreachable from client subnets even if misconfigured elsewhere; the deployment binds runners to localhost / AI-internal interfaces only.

## Requirements *(mandatory)*

### Functional Requirements

**Isolation, structure, and configuration**

- **FR-001**: The AI layer MUST be an isolated component tree (a dedicated `ai/` area with a Gateway part and a Runner part) that is separate from the clinic backend and the Flutter client, and MUST NOT contain, import, or depend on any clinic-database credentials, service-role keys, or database client/driver libraries.
- **FR-002**: An automated isolation check MUST be runnable and MUST fail if any clinic-database credential, service-role key, or database-client dependency appears anywhere in the AI layer.
- **FR-003**: The Gateway MUST be configurable through a single documented configuration surface that exposes every defined configuration key with its documented default (listen port default `8090`; runner list; health poll interval default `10s`; unreachable-after-failures default `3`; queue depth/wait defaults; max-in-flight-per-caller default; inference timeout defaults; confidence threshold default; JWT validation material; allowed origins; verbatim-logging flag default off; push-registration flag default off; streaming flag; multi-command-plans flag default off; model-swap first-token timeout default; models directory; role→`ai.access` map).
- **FR-004**: Invalid or unparseable configuration MUST cause the Gateway to fail fast at startup with a clear, human-readable error identifying the offending key, rather than starting in an undefined state.
- **FR-005**: The Gateway MUST run as a supervised service with an automatic-restart policy so that, after a crash or restart, it returns to service and its readiness recovers automatically once a runner is ready.

**Model Runner**

- **FR-006**: A Model Runner MUST expose an OpenAI-compatible inference interface (chat-completions and model-listing endpoints) so that the underlying runtime (Ollama by default) is replaceable without client or Gateway contract changes.
- **FR-007**: A Model Runner MUST keep at most one model resident in memory at any time; loading a different model MUST unload the previous one, and requests arriving during a swap MUST queue or receive a busy/retry response until the runner is ready again.
- **FR-008**: The default Model Runner MUST serve the designated default local model (Qwen3-4B, Q4_K_M quantization) sourced from an integrity-pinned (digest-pinned) source.
- **FR-009**: A Model Runner MUST expose a liveness signal reachable by the Gateway and MUST report a "starting" state (not "ready") while a model is loading or swapping.
- **FR-010**: A Model Runner MUST bind only to localhost or the AI-internal interface and MUST NOT be reachable or routable from client subnets.
- **FR-011**: A Model Runner MUST NOT hold clinic-database credentials or clinic-database access.
- **FR-012**: The procedure to install/add models — via runtime pull for tagged models and/or by pointing at a local model file path — MUST be documented in an operator-facing runbook, including where model files live and how the source digest is pinned.
- **FR-013**: Each runner's currently loaded model name and version/digest MUST be discoverable by the Gateway; configured-but-unloaded models MAY be reported as unloaded with their declared capabilities.

**Gateway health and authentication**

- **FR-014**: The Gateway MUST expose a liveness endpoint (process is up) and a readiness endpoint whose positive result requires at least one Model Runner in the "ready" state.
- **FR-015**: The Gateway MUST validate the caller's Supabase login token **offline** — verifying signature and expiry/not-before — with **no network call to Supabase and no database access**. It MUST support **both** validation mechanisms, selectable by configuration: (a) a **symmetric shared secret** (HS-family, via the GoTrue JWT secret / `jwt_secret`) for the on-LAN default, and (b) **asymmetric JWKS / public-key-set** validation (via `jwks_url`) for when Supabase runs off the LAN. Exactly one mechanism is active per deployment based on which material is configured; if both are configured the precedence MUST be documented.
- **FR-016**: The Gateway MUST reject any caller lacking a valid token with a typed "unauthenticated" outcome.
- **FR-017**: The Gateway MUST check the `ai.access` grant using a configurable role→grant map that mirrors the clinic's permission defaults, and MUST reject an authenticated caller whose role lacks the grant with a typed "forbidden" outcome (distinct from unauthenticated).
- **FR-018**: The Gateway MUST re-read the role→grant map when the clinic's permission matrix changes (via reload or periodic refresh) so authorization decisions do not go stale.
- **FR-019**: All client-facing Gateway endpoints except the liveness endpoint MUST require a valid token.
- **FR-020**: The Gateway MUST return a consistent typed error contract on every failure: an HTTP status plus a body carrying a stable machine-readable code, a human-readable message, and a request identifier. At minimum it MUST support codes for malformed/oversized input, unauthenticated, forbidden, rate-limited, no-capacity/busy, timeout, and a "not implemented" code for the stubbed generation route, as applicable to the endpoints shipped in this phase.
- **FR-021**: Cross-origin access MUST be governed by an explicit allowlist of permitted client origins; wildcard origins MUST NOT be used.
- **FR-022**: The Gateway and Model Runner MUST run under least-privilege OS accounts with no filesystem access beyond model files, the local log directory, and their configuration.

**Registry, health polling, and routing**

- **FR-023**: The Gateway MUST maintain an in-memory registry of the runners listed in configuration, populated by pull-based health polling on a configurable cadence (default every 10 seconds); no bespoke agent on the runner host may be required (must work with a vanilla runtime).
- **FR-024**: The registry MUST record, per runner, its lifecycle status, last-seen timestamp, and measured latency.
- **FR-025**: The Gateway MUST implement the defined runner lifecycle: unknown → starting → ready → busy (at max in-flight) → degraded (elevated latency/sporadic errors) → unreachable (after N consecutive failed polls, default 3) → recovery back to starting/ready.
- **FR-026**: The Gateway MUST route only to runners in "ready" (preferred) or "degraded" (deprioritized) states and MUST never route to "unreachable" or "starting" runners.
- **FR-027**: Runner selection MUST apply, in order: capability match (required), health filter (required), then least-busy preference with round-robin tie-breaking (recommended). Session affinity MAY be applied but is optional.
- **FR-028**: Clients MUST NOT be able to influence routing beyond declaring the logical task/capabilities they require; clients MUST NOT be configured with, or able to select, individual runner addresses.
- **FR-029**: The Gateway MUST expose an aggregate capabilities report listing, per runner, its status, loaded model name and version/digest, advertised features, and context length; the report MUST mirror the live registry so clients can feature-detect.
- **FR-030**: Optional push-based runner registration/heartbeat MAY be supported behind a configuration flag defaulting to off; when enabled it MUST require an internal shared secret and be reachable only on the AI-internal interface, never from client subnets.

**Explicit scope boundary**

- **FR-031**: This feature MUST NOT implement functional AI generation: no prompt assembly, no agents, no structured-output enforcement, and no inference behavior. The `POST /v1/ai/generate` route MUST nonetheless be **present as a stub** that returns a typed "not implemented" / no-capacity error and performs no inference, so clients can feature-detect the route. The capabilities report MUST advertise **no** generation tasks/commands while generation is stubbed. Real generation is delivered by the subsequent phase.
- **FR-032**: No AI-layer component MUST write to, or persist clinical data in, the clinic database; the AI layer holds no durable clinical state in this phase.
- **FR-033**: The Gateway MUST emit **structured (machine-parseable) logs** to **local files only** (never the clinic database) covering operational and per-request events available in this phase — at minimum request identifier, caller staff identity from the token, endpoint/outcome, chosen runner, runner status transitions, and latencies.
- **FR-034**: Logs MUST be **PHI-minimized by default**: any caller-supplied text or context is redacted or hashed unless a verbatim-logging flag (default off) is explicitly enabled with bounded retention.
- **FR-035**: The Gateway MUST expose a Prometheus-style `/metrics` endpoint reporting at least request rate, error rate by code, per-runner health/latency, and in-flight counts.

### Key Entities *(include if feature involves data)*

- **AI Gateway (control-plane service)**: The single AI entry point on the clinic LAN. Owns caller authentication/authorization, the runner registry, health polling, routing selection, and capability reporting. Holds no clinic-database credentials.
- **Model Runner**: A process hosting exactly one resident model behind an OpenAI-compatible interface. Attributes: reachable internal endpoint, declared and loaded model (name + version/digest), advertised features (e.g., grammar/JSON support, context length), lifecycle status, last-seen, measured latency. Not client-reachable.
- **Runner Registry Entry**: The Gateway's in-memory record of one runner: identity, endpoint, declared capabilities, lifecycle status, last-seen timestamp, measured latency, and loaded model + digest.
- **Gateway Configuration**: The set of operator-controlled keys and defaults governing ports, runners, poll cadence, failure thresholds, timeouts, allowlists, feature flags, model directory, and the role→`ai.access` map.
- **Role → `ai.access` Map**: The offline authorization table mapping staff roles to whether they may use AI, mirroring the clinic permission defaults (administrator/doctor granted; receptionist/lab-staff denied, by default and configurable).
- **Caller Identity (from token)**: The validated claims extracted offline from the Supabase login token — at minimum the staff role and token validity window — used for authorization only; never used to read the clinic database.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Targets small-to-mid-size multi-branch clinics running on modest, CPU-only hardware on a trusted LAN. The default deployment collapses the Gateway and one Model Runner onto the single server node, adding at most one new long-running service type (the Gateway) beyond the model runtime — within the constitution's simplicity budget (no microservice sprawl, no queues/Kubernetes). Multi-node runner spread is a later, config-only option and explicitly out of scope here.
- **Layer Placement**: Everything in this feature lives in the **AI layer** (`ai/` tree): the Gateway and the Model Runner. **Supabase** is untouched and remains AI-unaware — no migration is required, and the AI layer never connects to it (it only validates Supabase-issued tokens offline). **PostgreSQL** owns no new objects. **Flutter** is not modified in this phase (client work is a later phase); the Gateway simply becomes the single AI URL clients will later target.
- **Data Integrity & Security**: The AI layer holds **no** clinic-database credentials, service-role keys, or DB access (enforced by an automated isolation scan). Authorization is defense-in-depth: the Gateway performs a coarse offline `ai.access` gate (via shared-secret or JWKS token validation, per deployment config), while authoritative per-command permission enforcement remains at Supabase RPC/RLS in later phases. Callers are authenticated via offline token validation. Model Runners are non-client-routable and bound to internal interfaces. CORS uses an explicit allowlist. No clinical data is persisted by the AI layer; structured logs are local files only and PHI-minimized by default (verbatim logging is opt-in, default off).
- **Failure Handling & Observability**: The AI layer is strictly additive — if the Gateway or runners are down, all manual clinic UI continues to work unchanged. Readiness honestly reports "not ready" when no runner is serving. Runner cold-start/model-swap windows are represented as "starting" rather than failing opaquely. Services are supervised with auto-restart, and invalid configuration fails fast with a clear error. The Gateway is observable from day one: PHI-minimized structured logs (local files) and a `/metrics` endpoint expose request/health/latency signals for operators. There is no functional AI generation in this phase (the generate route is a stub returning "not implemented"), so there is no AI-originated action to gate yet; the human-approval and same-RPC execution guarantees are established in later phases.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can deploy the AI layer (Gateway + one Model Runner) on a fresh server node and confirm it is healthy and isolated in under 30 minutes using the runbook.
- **SC-002**: The liveness endpoint returns healthy whenever the Gateway process is up; the readiness endpoint returns positive only when at least one runner is serving a loaded model — verified in 100% of start-up and runner-down scenarios.
- **SC-003**: A Model Runner that stops responding is reflected as unreachable, and readiness turns negative, within the configured number of failed polls (default 3 polls ≈ 30 seconds at the default cadence); when the runner recovers, readiness returns positive automatically without operator intervention.
- **SC-004**: 100% of unauthenticated requests are rejected as unauthenticated and 100% of authenticated-but-ungranted requests are rejected as forbidden, across the full token test matrix; token validation completes with zero network calls to Supabase.
- **SC-005**: The automated isolation scan reports zero clinic-database credentials, service-role keys, or database-client dependencies in the AI layer, and this check gates the build.
- **SC-006**: The capabilities report matches the live registry in 100% of tested registry states (including model name/version/digest, features, context length, and status).
- **SC-007**: With the AI layer fully stopped, 100% of standard manual clinic UI operations continue to function unchanged (verified against the existing manual workflows).
- **SC-008**: A Model Runner is confirmed unreachable from any client-subnet address in 100% of connectivity tests, and at no point is more than one model resident in memory during model-swap tests.
- **SC-009**: Every failure response carries a typed error with a stable code, message, and request identifier, and every documented configuration key parses with its default while invalid configuration fails fast with a clear error.
- **SC-010**: The auth test matrix passes identically under both validation configurations (shared-secret and JWKS) in 100% of cases, with zero network calls to Supabase in either mode.
- **SC-011**: The stubbed `POST /v1/ai/generate` route returns the typed "not implemented" error in 100% of calls and performs zero inference, and the capabilities report advertises no generation tasks while stubbed.
- **SC-012**: With verbatim logging off (default), 100% of sampled log records contain no verbatim caller-supplied text/PHI (verified against name fixtures), and the `/metrics` endpoint reports request rate, error rate by code, and per-runner latency/health.

## Assumptions

- **Deployment shape**: The default and in-scope deployment is single-node — Gateway plus one Model Runner co-located on the clinic server node. Multi-node runner spread and push-based dynamic registration are reserved (config flags exist, default off) and validated in a later phase.
- **Runtime & model**: Inference is CPU-only and local. The default runtime is Ollama and the default model is Qwen3-4B (Q4_K_M), with smaller fallbacks (e.g., Llama 3.2 3B / Qwen2.5 1.5B) available for RAM-constrained nodes. The runtime is treated as replaceable behind the OpenAI-compatible interface.
- **Network posture**: The clinic LAN is trusted; plaintext HTTP on the LAN is acceptable for this phase, with TLS support desirable in the installer and mandatory only if any component later leaves the LAN. Model Runners are never exposed to client subnets.
- **Authentication material**: The Gateway supports both offline validation mechanisms — a shared HS-family secret (GoTrue JWT secret) and a JWKS/public-key-set — selectable by which config is provided; the on-LAN default uses the shared secret and JWKS is available for off-LAN Supabase. The Gateway also has a role→`ai.access` map that mirrors current clinic permission defaults (administrator/doctor granted; receptionist/lab-staff denied). Individual permission keys are not yet embedded in the token, so the role map is authoritative for the Gateway's coarse gate.
- **No Supabase changes**: No database migration, new table, or new RPC is required to introduce the AI layer; existing RBAC (`ai.access`) already exists in the clinic schema.
- **Implementation choices deferred to planning**: The Gateway's implementation language/runtime, project scaffolding specifics, and exact test tooling are deliberately left to the planning phase; this specification constrains behavior and boundaries, not technology.
- **No functional generation this phase**: Prompt handling, agents, grammars, structured output, and inference are explicitly out of scope and delivered by the next phase. The `POST /v1/ai/generate` route ships only as a "not implemented" stub for feature-detection; this phase is a testable control plane (with observability) only.
