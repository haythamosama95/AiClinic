# Stage 00 — Platform configuration and boot

Source files read: `ai-platform/src/worker.ts`, `ai-platform/src/capability/index.ts`, `ai-platform/src/manifest/index.ts`, `ai-platform/src/config-cache/index.ts`, `ai-platform/src/logger.ts`, `ai-platform/src/trace.ts`, `ai-platform/src/errors.ts`, `ai-platform/src/discovery/index.ts`, `ai-platform/src/control/auth.ts`, `ai-platform/src/control/http.ts`, `ai-platform/wrangler.toml`, `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`, `ai-platform/manifests/published-registry.json`, `ai-platform/migrations/20260731120000_platform_schema.sql`, `ai-platform/migrations/20260803120000_token_contract.sql`, `ai-platform/migrations/20260807120000_kill_switch.sql`, `ai-platform/migrations/20260821120000_grace_admission_queue.sql`, `ai-platform/migrations/20260821130000_entitlement_installation_unique.sql`, `docs/architecture/ai-platform/data-journey/02-stage-0-platform-configuration-and-boot.md`

Canonical values used throughout: installation `I0` = `inst_01J4ZEXAMPLE0000000000000`; capability `clinic.visit_summary@1.0.0`; request references use the A2 `XXXX-XXXX` Crockford-base32 format (e.g. `9J3K-7Q2M`); trace ids are ULIDs (e.g. `01J4ZF3Q8K2M4N6P8R0T2W4Y6A`). Where a response mints a fresh reference/trace per call, the concrete value shown is illustrative and must be matched by shape, not equality.

Boot-failure scenarios (S00-001…S00-014) are ordered first per blocker escalation: each trips exactly one boot-time or configuration blocker. Routing/auth boundary scenarios (S00-015…S00-023) trip route-table and unauthenticated boundaries that require no prior business state. Schema and cron scenarios (S00-024…S00-029) verify the empty-airport baseline. Build-gate scenarios (S00-030…S00-033) cover the manifest publication gate. Happy paths come last (S00-034…S00-037).

## Scenario S00-001 — Boot aborts when the DB (D1) binding is missing

| Field | Content |
|-------|---------|
| ID | S00-001 |
| Journey setup | None — this is the first operation: the Cloudflare runtime loads `src/worker.ts`. The isolate is started with an environment that declares every binding except `DB` (R2, DO, rate limiters, and all vars present). |
| Action | Evaluate the worker module (isolate startup) with `env.DB === undefined`. |
| Expected outcome | Module evaluation throws `Error: Missing required binding: DB` at module top level, before any fetch handler is registered. The isolate never serves: every subsequent HTTP request (including `GET /health`) fails to connect / never returns a response. |
| Side effects | None. No D1/DO/R2 access occurs; no log line is emitted by application code (the throw precedes logger construction in any request path). |
| Code reference | `ai-platform/src/worker.ts:L134-L146` — `assertRequiredBindings` and its module-top call |

## Scenario S00-002 — Boot aborts when the R2 binding is missing

| Field | Content |
|-------|---------|
| ID | S00-002 |
| Journey setup | None — isolate startup. Environment declares `DB` and `DO` but omits the `R2` bucket binding. |
| Action | Evaluate the worker module with `env.R2 === undefined`. |
| Expected outcome | Module evaluation throws `Error: Missing required binding: R2`. The isolate never serves any route. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L134-L146` — `assertRequiredBindings` |

## Scenario S00-003 — Boot aborts when the DO (Durable Object) binding is missing

| Field | Content |
|-------|---------|
| ID | S00-003 |
| Journey setup | None — isolate startup. Environment declares `DB` and `R2` but omits the `DO` namespace binding (`GatewayObject`). |
| Action | Evaluate the worker module with `env.DO === undefined`. |
| Expected outcome | Module evaluation throws `Error: Missing required binding: DO`. The isolate never serves any route. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L134-L146` — `assertRequiredBindings` |

## Scenario S00-004 — Missing rate-limiter bindings do not block boot (allow-all fallback)

| Field | Content |
|-------|---------|
| ID | S00-004 |
| Journey setup | Isolate startup with `DB`, `R2`, `DO` present but all three `[[env.*.ratelimits]]` stanzas (`RATE_LIMITER_INSTALLATION`, `RATE_LIMITER_INSTALLATION_ACTOR`, `RATE_LIMITER_INSTALLATION_CAPABILITY`) omitted. |
| Action | Boot the worker, then `GET http://127.0.0.1:8787/health` with no headers. |
| Expected outcome | Boot succeeds; HTTP 200 with body `{"build":"local","environment":"development"}`. The rate-limit stage later falls back to `allowAllRateLimit` (`limit()` always returns `{ success: true }`), so no request is ever rejected `rate_limited` by the binding path — the full-path proof of the fallback is a Stage 8 (rate-limit guard) scenario; here we prove only that boot and health are unaffected. |
| Side effects | None. `platform_counter` remains empty. |
| Code reference | `ai-platform/src/worker.ts:L326-L341` — `allowAllRateLimit` and `productionRateLimitBindings` (`?? allowAllRateLimit` per binding) |

## Scenario S00-005 — Missing OPERATOR_BEARER_TOKEN does not block boot; control plane fails closed

| Field | Content |
|-------|---------|
| ID | S00-005 |
| Journey setup | Isolate startup with all bindings present but the `OPERATOR_BEARER_TOKEN` secret unset. `OPERATOR_ID` var is `platform-operator` (wrangler `[vars]`). |
| Action | (1) `GET /health` — no headers. (2) `POST /control/token-contract/begin-rotation` with headers `Content-Type: application/json`, `Authorization: Bearer any-presented-token`, body `{"ver":"1"}`. |
| Expected outcome | (1) HTTP 200 `{"build":"local","environment":"development"}` — the secret is not a required binding. (2) HTTP 401 with body exactly `{"error":"unauthorized"}` (`content-type: application/json`): `createSecretOperatorAuth` is constructed with `bearerToken: ""`, and the timing-safe compare of any non-empty presented token against `""` fails; an empty presented token is rejected before compare. No control handler runs. |
| Side effects | None — critically, no `control_audit` row and no `token_contract` mutation. |
| Code reference | `ai-platform/src/worker.ts:L1360-L1363` — `createSecretOperatorAuth({ bearerToken: runtimeEnv.OPERATOR_BEARER_TOKEN ?? "", ... })`; `ai-platform/src/control/auth.ts:L26-L49` — `createSecretOperatorAuth`; `ai-platform/src/control/http.ts:L3-L8` — `unauthorized()` |

## Scenario S00-006 — Missing provider API keys do not block boot (failure deferred to invoke)

| Field | Content |
|-------|---------|
| ID | S00-006 |
| Journey setup | Isolate startup with all bindings present and `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` secrets unset. |
| Action | `GET /health` — no headers. |
| Expected outcome | HTTP 200 `{"build":"local","environment":"development"}`. Boot never calls `secretStore.getSecret`; the lookup runs only when `resolveProviderPort` wires a live provider during invoke, where the missing secret surfaces as taxonomy `provider_rejected` (`missing_api_key`) — that terminal outcome is owned by the invocation-stage chapter and is cross-referenced here only to prove boot is independent of provider secrets. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L343-L359` — `resolveProviderPort` and its `secretStore.getSecret` env lookup |

## Scenario S00-007 — Bundled manifest failing validation aborts isolate boot (fail closed)

| Field | Content |
|-------|---------|
| ID | S00-007 |
| Journey setup | Hypothetical build in which the statically imported `manifests/published/clinic.visit_summary@1.0.0.json` is valid JSON but fails `load()` validation (e.g. the `Economics` group is deleted, so `validate` throws `Missing manifest group: Economics`). Reachability: in production this is blocked by the `verifyManifestTree` build gate (S00-032); the runtime path exists only as defense-in-depth. In the test environment the equivalent **degraded end-state** (empty registry, `capability_unknown` everywhere) is still produced via the harness seam: `setCapabilityRegistry(new Map(), { replace: true })` before the worker module is evaluated. |
| Action | (a) Boot the worker with a throwing `load()` manifest (hypothetical). (b) Harness seam: install an empty registry before worker eval, then drive `GET /health` and `GET /v1/capabilities`. |
| Expected outcome | (a) Isolate boot aborts after a V0 `boot_registry_install_failed` log — the worker does **not** serve with a silently empty registry (C-18). (b) Harness seam: HTTP 200 `/health`; discovery `{"manifests":[]}`; `POST /v1/requests` → `capability_unknown` at the guard stage. |
| Side effects | (a) No requests served. (b) None beyond Stage 3/4 setup reads. |
| Code reference | `ai-platform/src/worker.ts` — boot `try/catch` rethrows on `load()` failure; `ai-platform/src/capability/index.ts:L558-L573` — `resolve` returning `capability_unknown` on registry miss |

## Scenario S00-008 — Pre-installed registry is retained when boot installation throws (replace semantics)

| Field | Content |
|-------|---------|
| ID | S00-008 |
| Journey setup | Test harness installs a registry containing only a harness manifest (e.g. `test.echo@9.9.9`, loaded via `load()` and installed with `createCapabilityRegistry` + `setCapabilityRegistry`) **before** the worker module is evaluated. This is the documented reason for the boot `try/catch` ("Test harness may install the registry first with { replace: true }"). |
| Action | Evaluate the worker module (boot attempts `setCapabilityRegistry` without `{ replace: true }`, which throws `CapabilityRegistry is already installed; pass { replace: true } to replace`; the catch swallows it). Then `GET /v1/capabilities` with a valid AAT whose entitlement allows `test.echo` (Stage 3/4/6 happy paths with `allowed_capabilities: ["test.echo"]`). |
| Expected outcome | Boot completes; the harness registry survives (the "already installed" throw is caught and swallowed — this is the **only** boot catch that does not rethrow). Discovery HTTP 200 lists `test.echo@9.9.9` and does **not** list `clinic.visit_summary@1.0.0`. Requests naming `clinic.visit_summary` resolve to `capability_unknown`. |
| Side effects | None beyond Stage 3/4 setup rows. |
| Code reference | `ai-platform/src/worker.ts:L150-L159` — boot try/catch; `ai-platform/src/capability/index.ts:L515-L531` — `setCapabilityRegistry` |

## Scenario S00-009 — Installed registry and its manifests are immutable

| Field | Content |
|-------|---------|
| ID | S00-009 |
| Journey setup | Worker booted normally (registry holds `clinic.visit_summary@1.0.0`, deep-frozen at load). |
| Action | From the same isolate, attempt three mutations against the installed registry handle and a resolved manifest: (1) `registry.set("clinic.visit_summary@2.0.0", anything)`; (2) `registry.delete("clinic.visit_summary@1.0.0")` / `registry.clear()`; (3) assign `manifest.Identity.lifecycleState = "retired"` on the manifest object returned by capability resolution (Stage 9 resolve path, strict-mode module). |
| Expected outcome | (1) and (2) throw `TypeError: CapabilityRegistry is immutable` (the Proxy traps `set`/`delete`/`clear`). (3) throws `TypeError` in strict mode (object is deep-frozen by `freezeManifest`). Registry contents and the discovery ETag are unchanged afterwards. |
| Side effects | None. |
| Code reference | `ai-platform/src/capability/index.ts:L483-L498` — `unmodifiableRegistry` Proxy; `ai-platform/src/capability/index.ts:L452-L464` — `deepFreeze`/`freezeManifest`; `ai-platform/src/capability/index.ts:L500-L513` — `createCapabilityRegistry` |

## Scenario S00-010 — CONFIG_CACHE_TTL_MS unset, empty, or invalid resolves to the 30 000 ms default

| Field | Content |
|-------|---------|
| ID | S00-010 |
| Journey setup | Three isolate boots (or three `resolveConfigCacheTtlMs` evaluations against the boot env): (a) `CONFIG_CACHE_TTL_MS` unset; (b) `CONFIG_CACHE_TTL_MS = ""`; (c) `CONFIG_CACHE_TTL_MS = "abc"` and (d) `CONFIG_CACHE_TTL_MS = "-50"`. |
| Action | Boot the worker under each env and observe the configured isolate cache TTL (the value `configureIsolateConfigCache` installs on `isolateConfigCache`). |
| Expected outcome | All four variants resolve to `30_000` (`DEFAULT_CONFIG_CACHE_TTL_MS`): unset/empty short-circuit; `Number.parseInt("abc")` is `NaN`; negative parses are rejected by the `< 0` guard. Behavioral cross-check (full path): with the default TTL, a D1 config change (e.g. Stage 4 re-entitle) remains invisible to discovery for up to ~30 s — the positive TTL-honoring proof is S00-037. |
| Side effects | None. |
| Code reference | `ai-platform/src/config-cache/index.ts:L26-L40` — `DEFAULT_CONFIG_CACHE_TTL_MS` and `resolveConfigCacheTtlMs`; `ai-platform/src/worker.ts:L147-L149` — `configureIsolateConfigCache` at boot |

## Scenario S00-011 — CONFIG_CACHE_TTL_MS = "0" disables caching (every consult misses)

| Field | Content |
|-------|---------|
| ID | S00-011 |
| Journey setup | Isolate booted with `CONFIG_CACHE_TTL_MS = "0"` (boundary: `0` is accepted — only `< 0` falls back). Stage 3 enrollment happy path for `I0`; Stage 4 entitle happy path (active entitlement, `allowed_capabilities: ["clinic.visit_summary"]`); Stage 6 AAT mint (scopes `[ai.visit_summary]`). |
| Action | `GET /v1/capabilities` with the AAT (warm pass, HTTP 200 lists the capability). Then execute the Stage 4 re-entitle operation replacing `allowed_capabilities` with `[]`, and immediately re-issue `GET /v1/capabilities` with the same AAT — no waiting. |
| Expected outcome | TTL `0` means every remembered entry is already expired at the next consult (`now >= expiresAt`), so the second discovery re-reads D1 and returns HTTP 200 `{"manifests":[]}` immediately — no staleness window. |
| Side effects | Stage 4 re-entitle writes its own rows (owned by that stage); this scenario adds no writes. |
| Code reference | `ai-platform/src/config-cache/index.ts:L31-L40` — `resolveConfigCacheTtlMs` (`parsed < 0` guard admits `0`); `ai-platform/src/config-cache/index.ts:L89-L103` — `consult` expiry check |

## Scenario S00-012 — LOG_VERBOSITY invalid or unset outside development resolves to V0 (errors only)

| Field | Content |
|-------|---------|
| ID | S00-012 |
| Journey setup | Two isolate boots: (a) `ENVIRONMENT = "production"`, `LOG_VERBOSITY` unset; (b) `ENVIRONMENT = "production"`, `LOG_VERBOSITY = "verbose"` (unrecognized token). |
| Action | Drive one `GET /health` and one `GET /definitely-not-a-route` per isolate while capturing worker stdout/stderr (console sink). |
| Expected outcome | Verbosity resolves to `0` in both boots (unset → non-development fallback `0`; `"verbose"` matches none of `0/V0/1/V1/2/V2` → fallback `0`). No `[Info]` or `[Debug]` lines are emitted — specifically the `health_check` and `route_not_found` debug lines are suppressed. Only `[Error]` lines would appear (none on these paths). Responses are unaffected: 200 and 404 respectively. |
| Side effects | None. |
| Code reference | `ai-platform/src/logger.ts:L76-L105` — `resolveLogVerbosity` and `verbosityFromEnv`; `ai-platform/src/logger.ts:L68-L73` — `STATUS_MIN_VERBOSITY`; `ai-platform/src/worker.ts:L128-L131` — `createWorkerLogFactory` |

## Scenario S00-013 — LOG_VERBOSITY unset with ENVIRONMENT=development defaults to V2

| Field | Content |
|-------|---------|
| ID | S00-013 |
| Journey setup | Isolate booted with `ENVIRONMENT = "development"` and `LOG_VERBOSITY` unset/empty (the wrangler development env sets `"2"` explicitly; this scenario covers the code-level default when the var is absent). |
| Action | `GET /health` while capturing worker stdout. |
| Expected outcome | Verbosity resolves to `2` (`ENVIRONMENT === "development" ? 2 : 0`). A `[Debug]` line `health_check` formatted as `[hh:mm:ss] [worker.ts] [Debug] health_check` is emitted; data payloads render as JSON blobs (V2 formatting). Response is still HTTP 200 `{"build":"local","environment":"development"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/logger.ts:L97-L105` — `verbosityFromEnv`; `ai-platform/src/logger.ts:L148-L168` — `formatData` V2 JSON rendering; `ai-platform/src/worker.ts:L1334-L1340` — `/health` handler emitting `health_check` debug |

## Scenario S00-014 — Explicit LOG_VERBOSITY values parse case-insensitively (V1 emits info, suppresses debug)

| Field | Content |
|-------|---------|
| ID | S00-014 |
| Journey setup | Isolate booted with `ENVIRONMENT = "staging"`, `LOG_VERBOSITY = "v1"` (lowercase — exercises case-insensitive normalization; `"1"` behaves identically). Stage 3/4/6 happy paths for `I0` so an authenticated discovery can run. |
| Action | (1) `GET /v1/capabilities` with the valid AAT (emits `discovery_succeeded` info and `config_cache_miss` debug on cold cache). (2) `GET /health` (emits only the `health_check` debug). |
| Expected outcome | Verbosity resolves to `1`. The `[Info]` line `discovery_succeeded` appears with flat `key=value` data formatting (V1 rendering); `[Debug]` lines (`health_check`, `config_cache_miss`, `discovery_auth_rejected`) are suppressed. Responses unaffected (200 with manifest list; 200 health body). |
| Side effects | None. |
| Code reference | `ai-platform/src/logger.ts:L76-L94` — `resolveLogVerbosity` (`toUpperCase` normalization); `ai-platform/src/logger.ts:L164-L168` — V1 `key=value` formatting; `ai-platform/src/discovery/index.ts:L103-L111` — `discovery_succeeded` info line |

## Scenario S00-015 — Unknown path falls through to plain-text 404

| Field | Content |
|-------|---------|
| ID | S00-015 |
| Journey setup | Worker booted normally (bindings, registry, migrations all healthy). No business state required. |
| Action | `GET /cdn-cgi/does-not-exist` — no headers. Also `GET /quota-do.internal/rpc` (proves `GatewayObject` is not a public URL). |
| Expected outcome | HTTP 404 with plain-text body `Not Found` (not a taxonomy JSON body, no `code` field). A `route_not_found` debug log is emitted at V2. The DO RPC kinds (`admission`/`credit`/`release`/`inspect`) are unreachable from public HTTP. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1440-L1444` — 404 fallthrough; `ai-platform/src/worker.ts:L1247-L1321` — `GatewayObject.fetch` (Worker→DO RPC only) |

## Scenario S00-016 — Wrong method on /v1/capabilities returns 404, not 405

| Field | Content |
|-------|---------|
| ID | S00-016 |
| Journey setup | Worker booted normally. |
| Action | `POST /v1/capabilities` with `Content-Type: application/json`, body `{}`. |
| Expected outcome | HTTP 404 `Not Found`. The route guard requires `pathname === "/v1/capabilities" && method === "GET"`; a POST fails the conjunct, matches no later branch (not a control route, not the `GET /v1/requests/` prefix), and lands in the fallthrough. No auth is attempted and no taxonomy body is produced. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1342-L1347` — discovery route conjunct; `ai-platform/src/worker.ts:L1440-L1444` — fallthrough |

## Scenario S00-017 — GET /v1/requests without a reference (or with an empty one) returns 404

| Field | Content |
|-------|---------|
| ID | S00-017 |
| Journey setup | Worker booted normally. |
| Action | (1) `GET /v1/requests` — no trailing slash. (2) `GET /v1/requests/` — trailing slash, empty reference segment. |
| Expected outcome | (1) HTTP 404 `Not Found`: `"/v1/requests"` does not satisfy `startsWith("/v1/requests/")`, so it falls through. (2) HTTP 404 with an **empty body** (`new Response(null, { status: 404 })`): the prefix matches, the sliced reference is `""`, and the handler short-circuits before any auth or D1 access. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1376-L1383` — GET-by-reference route and empty-reference 404 |

## Scenario S00-018 — GET on a POST-only control route returns 404 (method gate precedes auth)

| Field | Content |
|-------|---------|
| ID | S00-018 |
| Journey setup | Worker booted normally; `OPERATOR_BEARER_TOKEN` secret set to `op-token-9f27c1`. |
| Action | `GET /control/token-contract/begin-rotation` with header `Authorization: Bearer op-token-9f27c1` (a **valid** operator bearer, wrong method). |
| Expected outcome | HTTP 404 `Not Found`. The control gate admits only `POST` (plus `GET` solely for quota-inspect routes); a GET on a mutation path never reaches `dispatchControlRequest` or the auth check, so even a valid bearer gets 404. |
| Side effects | None — no `control_audit` row. |
| Code reference | `ai-platform/src/worker.ts:L1354-L1374` — control route method conjunct (`isControlRoute` + `POST`/`isQuotaInspectRoute`) |

## Scenario S00-019 — Discovery without an Authorization header returns taxonomy unauthenticated

| Field | Content |
|-------|---------|
| ID | S00-019 |
| Journey setup | Worker booted normally with migrations applied. No enrollment or entitlement exists (empty airport) — proving this rejection needs no prior state and never touches D1. |
| Action | `GET /v1/capabilities` — no `Authorization` header. |
| Expected outcome | HTTP 401 with taxonomy body `{"code":"unauthenticated","request_reference":"9J3K-7Q2M","trace_id":"01J4ZF3Q8K2M4N6P8R0T2W4Y6A","retry_safe":true}` (reference and trace freshly minted per response; match by shape). Discovery emits a `discovery_auth_rejected` debug line with `reason: "missing_authorization_header"`. |
| Side effects | None — header checks run before `EnrolledKeyVerifier` and before any D1 read. |
| Code reference | `ai-platform/src/discovery/index.ts:L24-L48` — `unauthenticatedResponse` and missing-header branch; `ai-platform/src/errors.ts:L29-L34` — `unauthenticated` taxonomy entry (HTTP 401); `ai-platform/src/errors.ts:L217-L230` — `buildErrorBody` |

## Scenario S00-020 — Discovery with a garbage bearer returns taxonomy unauthenticated before any D1 read

| Field | Content |
|-------|---------|
| ID | S00-020 |
| Journey setup | Worker booted normally. Deliberately **no** migrations-dependent state is needed: the token fails JWT parse/signature verification inside `EnrolledKeyVerifier` before the `token_contracts`/`installations` config reads. |
| Action | `GET /v1/capabilities` with header `Authorization: Bearer not-a-jwt`. |
| Expected outcome | HTTP 401 with taxonomy body `{"code":"unauthenticated","request_reference":"7H2F-4X8D","trace_id":"01J4ZF5R1C3N5P7Q9S1V3X5Z7B","retry_safe":true}` (freshly minted; match by shape). Debug log `discovery_auth_rejected` with `reason: "token_verification_failed"`. The response is byte-identical in shape to S00-019 — the platform does not distinguish missing vs. unverifiable credentials to callers. |
| Side effects | None. |
| Code reference | `ai-platform/src/discovery/index.ts:L50-L95` — scheme/empty-token checks and `verifier.verify` rejection mapping |

## Scenario S00-021 — Control route with missing or wrong operator bearer returns 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S00-021 |
| Journey setup | Worker booted normally; `OPERATOR_BEARER_TOKEN = op-token-9f27c1`, `OPERATOR_ID = platform-operator`. |
| Action | (1) `POST /control/token-contract/begin-rotation` with `Content-Type: application/json`, body `{"ver":"1"}`, **no** Authorization header. (2) Same request with `Authorization: Bearer wrong-token`. |
| Expected outcome | Both: HTTP 401, body exactly `{"error":"unauthorized"}`, `content-type: application/json`. This is a plain control-plane body, **not** a §5.4 taxonomy body (no `code`/`request_reference`/`trace_id`/`retry_safe`). The timing-safe compare runs for (2); no handler, no audit attribution. |
| Side effects | None — no `control_audit` row, no `token_contract` mutation. |
| Code reference | `ai-platform/src/control/http.ts:L3-L8` — `unauthorized()`; `ai-platform/src/control/http.ts:L34-L41` — auth gate before dispatch; `ai-platform/src/control/auth.ts:L4-L49` — `timingSafeEqualString` and `createSecretOperatorAuth` |

## Scenario S00-022 — GET /v1/requests/{ref} without a token returns taxonomy unauthenticated

| Field | Content |
|-------|---------|
| ID | S00-022 |
| Journey setup | Worker booted normally. No `ai_request` row needs to exist — auth precedes lookup. |
| Action | `GET /v1/requests/9J3K-7Q2M` — no `Authorization` header. |
| Expected outcome | HTTP 401 with taxonomy body `{"code":"unauthenticated","request_reference":"3K9P-2M7Q","trace_id":"01J4ZF7T5E7R9T1W3Y5U7I9O1P","retry_safe":true}` (freshly minted by `getRequestAuthErrorBody`; match by shape). Status comes from `liveHttpStatusForCode("unauthenticated")` → 401. No D1 read occurs. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1385-L1393` — `authenticateGetRequest` gate and 401 mapping; `ai-platform/src/journal/index.ts:L580-L588` — `getRequestAuthErrorBody`; `ai-platform/src/errors.ts:L163-L168` — `liveHttpStatusForCode` |

## Scenario S00-023 — /health stays 200 when D1 migrations were never applied

| Field | Content |
|-------|---------|
| ID | S00-023 |
| Journey setup | Worker booted against a D1 database with **no** platform migrations applied. [SEED] Justification: the unmigrated state cannot be produced by any real platform operation — it is a provisioning omission; simulated by pointing the isolate at an empty D1 (or dropping all platform tables). |
| Action | (1) `GET /health`. (2) `GET /v1/capabilities` with `Authorization: Bearer not-a-jwt`. |
| Expected outcome | (1) HTTP 200 `{"build":"local","environment":"development"}` — `/health` reads only `BUILD_SHA`/`ENVIRONMENT` vars and proves nothing about D1, R2, DO reachability, secrets, or registry content. (2) HTTP 401 `unauthenticated` — JWT parse fails before any D1 read, so even the missing `token_contract` table is not exercised by garbage tokens. (A well-formed AAT would proceed to `SELECT * FROM installation …` and fail closed with a D1 `no such table` 500-class error — that degraded-identity path is owned by the identity-stage chapter.) |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1334-L1340` — `/health` handler (vars only); `ai-platform/src/config-cache/index.ts:L200-L244` — `createD1ConfigReader` table reads that would fail on unmigrated D1 |

## Scenario S00-024 — Cron tick with an unrecognized schedule runs only flush + grace reconcile

| Field | Content |
|-------|---------|
| ID | S00-024 |
| Journey setup | Worker booted on the empty-airport baseline (S00-027 state: schema applied, only the `token_contract` seed row exists). |
| Action | Invoke the `scheduled` handler directly with `controller.cron = "* * * * *"` (the wrangler.toml `[triggers]` declares only `0 3 * * *` and `0 4 * * *`; this exercises the fall-through branch). |
| Expected outcome | Handler completes without throwing. Log sequence: `scheduled_cron_start` (info, `{ cron: "* * * * *" }`), then `scheduled_cron_complete` (debug). Neither `scheduled_retention_purge_start` nor `scheduled_rollup_start` is emitted. `flushRejectionCounters` and `reconcileGraceUsage` run on every tick regardless of schedule. |
| Side effects | None: with zero in-isolate rejection tallies, `platform_counter` stays empty; with an empty `grace_admission_queue`, reconcile writes nothing. All business-table counts remain 0; the seed row is untouched. |
| Code reference | `ai-platform/src/worker.ts:L1447-L1495` — `scheduled` handler (unconditional flush + reconcile, then cron branch) |

## Scenario S00-025 — 03:00 cron tick runs the retention purge as a no-op on an empty airport

| Field | Content |
|-------|---------|
| ID | S00-025 |
| Journey setup | Empty-airport baseline (S00-027). |
| Action | Invoke the `scheduled` handler directly with `controller.cron = "0 3 * * *"`. |
| Expected outcome | Log sequence: `scheduled_cron_start`, `scheduled_retention_purge_start`, `scheduled_retention_purge_complete`, `scheduled_cron_complete`. `runRetentionPurge` executes against empty journal/R2 state and must not invent rows or throw. |
| Side effects | None: `ai_request`, `usage_event`, `platform_counter`, `usage_rollup`, `control_audit` all remain empty; no R2 objects are deleted or created; the `token_contract` seed is unchanged. |
| Code reference | `ai-platform/src/worker.ts:L1469-L1477` — retention branch; `ai-platform/wrangler.toml:L9-L10` — cron declaration |

## Scenario S00-026 — 04:00 cron tick runs rollup + reconciliation as a no-op on an empty airport

| Field | Content |
|-------|---------|
| ID | S00-026 |
| Journey setup | Empty-airport baseline (S00-027). |
| Action | Invoke the `scheduled` handler directly with `controller.cron = "0 4 * * *"`. |
| Expected outcome | Log sequence: `scheduled_cron_start`, `scheduled_rollup_start`, `usage_rollup_reconciliation` (info, with `rollups_written: 0`, `missing_attempt_rows: 0`, `missing_usage_credit: 0`), `scheduled_cron_complete`. No retention-purge log lines appear. |
| Side effects | `usage_rollup` remains empty (zero usage events → zero rollups written); reconciliation reports empty discrepancy lists; all other tables unchanged. |
| Code reference | `ai-platform/src/worker.ts:L1478-L1492` — rollup branch |

## Scenario S00-027 — Fresh migration apply produces the 14-table baseline plus the token_contract seed

| Field | Content |
|-------|---------|
| ID | S00-027 |
| Journey setup | A brand-new empty D1 database; the worker's migration set is applied once (in the test environment: real D1 migrations applied by the pool; in ops: `npx wrangler d1 migrations apply ai-platform-<env> --env <env>`). |
| Action | Query `sqlite_master` for tables (excluding `sqlite_%`, `_cf_%`, `d1_migrations`), for the index `idx_entitlement_installation_id`, and `SELECT ver, added_at, retired_at, changed_by FROM token_contract;`. |
| Expected outcome | Exactly 14 tables: `ai_attempt`, `ai_request`, `capability_grant`, `control_audit`, `entitlement`, `grace_admission_queue`, `installation`, `installation_key`, `kill_switch`, `platform_counter`, `routing_policy`, `token_contract`, `usage_event`, `usage_rollup`. The unique index `idx_entitlement_installation_id` exists on `entitlement(installation_id)`. Exactly one `token_contract` row: `ver = '1'`, `added_at = '2026-08-03T00:00:00.000Z'`, `retired_at = NULL`, `changed_by = 'seed'` — the only SQL seed in the platform. Every other table is empty. |
| Side effects | The migration itself is the side effect under test; no runtime writes follow. |
| Code reference | `ai-platform/migrations/20260731120000_platform_schema.sql` — 12-table baseline; `ai-platform/migrations/20260803120000_token_contract.sql:L9-L10` — seed insert; `ai-platform/migrations/20260807120000_kill_switch.sql` — `kill_switch`; `ai-platform/migrations/20260821120000_grace_admission_queue.sql` — `grace_admission_queue`; `ai-platform/migrations/20260821130000_entitlement_installation_unique.sql` — unique index |

## Scenario S00-028 — Re-applying migrations is idempotent (no duplicate seed)

| Field | Content |
|-------|---------|
| ID | S00-028 |
| Journey setup | S00-027 completed (schema + seed present). |
| Action | Apply the same migration set a second time (ops: `wrangler d1 migrations apply`, which consults `d1_migrations`; the raw seed `INSERT` has no `OR IGNORE`, so untracked re-execution would PK-conflict on `token_contract.ver = '1'` — the tracking table is what makes re-apply safe). Then re-run the S00-027 queries and `GET /health`. |
| Expected outcome | The apply reports already-applied (no statement re-executed). Still exactly one `token_contract` row with the same four column values; all other tables still empty; `/health` still 200 `{"build":"local","environment":"development"}`. First-time success and reuse success are the same empty airport. |
| Side effects | None beyond `d1_migrations` bookkeeping from S00-027. |
| Code reference | `ai-platform/migrations/20260803120000_token_contract.sql:L9-L10` — unguarded seed INSERT (why tracking matters) |

## Scenario S00-029 — Boot plus health plus all cron ticks writes zero business rows

| Field | Content |
|-------|---------|
| ID | S00-029 |
| Journey setup | S00-027 baseline. Worker booted normally. |
| Action | In sequence: `GET /health`; the three scheduled invocations from S00-024…S00-026 (`* * * * *`, `0 3 * * *`, `0 4 * * *`); then count rows in `installation`, `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `kill_switch`, `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`, `grace_admission_queue`, and re-read `token_contract.retired_at` for `ver = '1'`. |
| Expected outcome | All counts are `0`; `retired_at` is still `NULL`. Boot does not enroll a clinic, grant quotas, publish routing, flip a kill switch, journal a request, or write `control_audit` (`OPERATOR_ID = "platform-operator"` is inert until a control mutation). Health and empty-cron paths are read-only/no-op. |
| Side effects | None — that is the assertion. |
| Code reference | `ai-platform/src/worker.ts:L146-L159` — boot performs only binding assertion, cache configuration, registry install; `ai-platform/src/worker.ts:L1447-L1495` — scheduled handler |

## Scenario S00-030 — Build gate accepts the published manifest tree (hash matches the registry)

| Field | Content |
|-------|---------|
| ID | S00-030 |
| Journey setup | Repository checkout at a healthy commit: `manifests/published/clinic.visit_summary@1.0.0.json` and `manifests/published-registry.json` as committed. |
| Action | Run the manifest-tree verification (the build/CI gate): load every `manifests/published/*.json` through `load()`, compute `hashManifest` over each raw file, and assert each `(capabilityId, version)` → hash entry against `published-registry.json` via `verifyManifestTree`. |
| Expected outcome | Verification resolves without throwing. The single entry `clinic.visit_summary@1.0.0` hashes to `ce28a0b478fbcbb8eec7a2a975ebd9e2f52c6b8bb7dd7ecd1c2ec42981bab0fe`, matching the registry. The loaded manifest passes all ten field-group validations (exact keys, enums, `diagnostic_30d` retention band, no provider/model naming). |
| Side effects | None (read-only gate). |
| Code reference | `ai-platform/src/manifest/index.ts:L659-L698` — `verifyManifestTree`; `ai-platform/src/manifest/index.ts:L637-L655` — `verifyPublishedRegistry`; `ai-platform/src/manifest/index.ts:L630-L635` — `hashManifest`; `ai-platform/manifests/published-registry.json` |

## Scenario S00-031 — Build gate rejects a tampered published manifest (hash mismatch)

| Field | Content |
|-------|---------|
| ID | S00-031 |
| Journey setup | S00-030 checkout, then one byte of `manifests/published/clinic.visit_summary@1.0.0.json` is changed in a way that keeps it schema-valid (e.g. `Economics.quotaWeight` `1` → `2`) without updating the registry. |
| Action | Run `verifyManifestTree` again. |
| Expected outcome | It throws `Error: Published manifest hash mismatch for clinic.visit_summary@1.0.0: on-disk <new hash>, registry ce28a0b4…`. The deploy/build is blocked — a mutated manifest can never reach the boot path in S00-007 through the gated pipeline. (A manifest deleted from the registry mapping instead throws `No published registry entry for clinic.visit_summary@1.0.0`.) |
| Side effects | None. |
| Code reference | `ai-platform/src/manifest/index.ts:L637-L655` — `verifyPublishedRegistry` mismatch and missing-entry throws |

## Scenario S00-032 — Build gate rejects a malformed manifest (validation failure is reachable at build time only)

| Field | Content |
|-------|---------|
| ID | S00-032 |
| Journey setup | S00-030 checkout, then the published manifest is edited to violate the loader (e.g. the `Governance` group is removed, or `Governance.retentionClass` is set to `"diagnostic_400d"` — outside the 1–90 day band, or a `Routing.provider` key is added). |
| Action | Run `verifyManifestTree` (which calls `load(json)` per file before hashing). |
| Expected outcome | `load` throws before any hash comparison: respectively `Missing manifest group: Governance`, `Malformed manifest Governance.retentionClass: diagnostic horizon must be 1–90 days`, or `Manifest must not name provider or model at manifest.Routing.provider`. This answers the reachability question for malformed manifests: at runtime the boot `try/catch` (S00-007) swallows a load failure and degrades to an empty registry; the **enforcing** surface is this build gate, which aborts the pipeline. |
| Side effects | None. |
| Code reference | `ai-platform/src/manifest/index.ts:L511-L601` — `validate`; `ai-platform/src/manifest/index.ts:L470-L496` — retention-class band; `ai-platform/src/manifest/index.ts:L241-L261` — provider/model naming ban; `ai-platform/src/manifest/index.ts:L680-L682` — `verifyManifestTree` invoking `load` |

## Scenario S00-033 — Loader normalizes the legacy perRequestCostCeiling alias

| Field | Content |
|-------|---------|
| ID | S00-033 |
| Journey setup | A previously published manifest revision whose `Economics` group carries the legacy key `perRequestCostCeiling: 9024` instead of `perRequestTokenCeiling` (compatibility fixture presented to the loader — the alias exists for already-published manifests and is exercised through the same `load()` entry point the boot path uses). |
| Action | `load()` the aliased manifest JSON. |
| Expected outcome | Load succeeds. The resulting frozen `Manifest.Economics` contains `perRequestTokenCeiling: 9024` and **no** `perRequestCostCeiling` key (the alias is copied then deleted before exact-key validation). If both keys were present, the canonical one wins and the alias is still removed. |
| Side effects | None. |
| Code reference | `ai-platform/src/manifest/index.ts:L320-L344` — `normalizeEconomicsGroup`; `ai-platform/src/manifest/index.ts:L79-L85` — alias constant |

## Scenario S00-034 — /health answers any HTTP method (no method check)

| Field | Content |
|-------|---------|
| ID | S00-034 |
| Journey setup | Worker booted normally. |
| Action | `POST /health` with body `{}` (also reproducible with `DELETE`/`PUT`). |
| Expected outcome | HTTP 200 with the identical JSON body `{"build":"local","environment":"development"}`. The route test is `url.pathname === "/health"` with no method conjunct, so any method is served. (Doc drift: the orientation doc describes only `GET /health`.) |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1334-L1340` — `/health` pathname-only branch |

## Scenario S00-035 — Happy path: first boot serves GET /health

| Field | Content |
|-------|---------|
| ID | S00-035 |
| Journey setup | Full provisioning analog: bindings declared (`DB`, `R2`, `DO`, three rate limiters), `OPERATOR_BEARER_TOKEN` secret present, migrations applied (S00-027 baseline), worker deployed/started with `BUILD_SHA = "local"`, `ENVIRONMENT = "development"`. |
| Action | `GET /health` — no headers, no auth. |
| Expected outcome | HTTP 200, `content-type: application/json`, body exactly `{"build":"local","environment":"development"}` — the two vars and nothing else (no capability, pricing, or readiness fields). The response proves: the isolate loaded, `assertRequiredBindings` passed, and the boot registry installation did not abort the isolate. It does **not** prove D1 readability, R2 access, DO reachability, operator-secret correctness, provider keys, or registry contents (see S00-005/006/007/023). |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:L1334-L1340` — `/health` handler; `ai-platform/wrangler.toml:L24-L29` — development vars |

## Scenario S00-036 — Happy path: the boot-loaded registry serves the bundled capability through authenticated discovery

| Field | Content |
|-------|---------|
| ID | S00-036 |
| Journey setup | Worker booted normally on the S00-027 baseline. Stage 3 enrollment happy path (installation `I0` = `inst_01J4ZEXAMPLE0000000000000`, enrolled key). Stage 4 entitle happy path (active entitlement for `I0`, plan `standard`, `allowed_capabilities: ["clinic.visit_summary"]`, plus the matching capability grant). Stage 6 AAT mint (clinician, scopes `[ai.visit_summary]`). No routing policy is needed — discovery never reads routing. |
| Action | `GET /v1/capabilities` with header `Authorization: Bearer <the minted AAT>`. |
| Expected outcome | HTTP 200, headers `ETag: "<64-hex>"` and `Cache-Control: private, must-revalidate`, body `{"manifests":[<public projection>]}`. The single entry is the public projection of the boot-bundled manifest: `Identity.capabilityId = "clinic.visit_summary"`, `Identity.version = "1.0.0"`, `Identity.lifecycleState = "active"`, plus `Interaction`, `Input`, `Context requirements`, and — restricted to the public subset — `Output: {"mode":"prose","outputSchemaRef":null}` and `Governance: {"acceptanceMode":"advisory_display"}`. Non-public groups (`Access`, `Prompt binding`, `Routing`, `Economics`) never appear. This proves the boot registry install populated the in-memory catalog from the bundled JSON. |
| Side effects | Read-only: entitlement/grant config reads populate the isolate config cache; no D1/DO/R2 writes. |
| Code reference | `ai-platform/src/worker.ts:L150-L159` — boot registry install; `ai-platform/src/capability/index.ts:L466-L481` — `toPublicManifest` projection; `ai-platform/src/capability/index.ts:L638-L783` — `discover`; `ai-platform/src/capability/index.ts:L868-L895` — `buildDiscoveryResponse` headers |

## Scenario S00-037 — Happy path: configured cache TTL bounds config staleness end-to-end

| Field | Content |
|-------|---------|
| ID | S00-037 |
| Journey setup | Worker booted with `CONFIG_CACHE_TTL_MS = "100"` (the development value in wrangler.toml). Stage 3 enrollment happy path (`I0`); Stage 4 entitle happy path (active entitlement, `allowed_capabilities: ["clinic.visit_summary"]`, grant present); Stage 6 AAT mint (scopes `[ai.visit_summary]`). |
| Action | (1) `GET /v1/capabilities` with the AAT → warms the isolate cache with the entitlement row. (2) Execute the Stage 4 re-entitle operation setting `allowed_capabilities: []`. (3) Immediately (within 100 ms) re-issue `GET /v1/capabilities`. (4) After >100 ms have elapsed, issue it a third time. |
| Expected outcome | (1) HTTP 200 listing `clinic.visit_summary@1.0.0`. (3) HTTP 200 **still listing** the capability — the cached entitlement row is served inside its TTL (stale read is the designed behavior, not a bug). (4) HTTP 200 with `{"manifests":[]}` — the TTL expired, `consult` evicted the entry, D1 was re-read, and the new entitlement excludes the capability. The ETag at (4) differs from (1)/(3). |
| Side effects | Stage 4 re-entitle writes are owned by that stage. This scenario adds only cache entries (isolate-local memory, no D1/DO/R2 writes). |
| Code reference | `ai-platform/src/config-cache/index.ts:L89-L115` — `consult`/`remember` TTL mechanics; `ai-platform/src/config-cache/index.ts:L386-L413` — `loadConfig` miss path; `ai-platform/src/worker.ts:L147-L149` — boot TTL configuration; `ai-platform/wrangler.toml:L28` — development `CONFIG_CACHE_TTL_MS = "100"` |

## Doc-drift observations

- **`/health` accepts any method.** The orientation doc (§5, §8.3.3) describes only `GET /health`; `worker.ts` branches on pathname alone, so `POST /health` (and any other method) returns the same 200 body (S00-034). No doc mentions this.
- **Boot registry-install failure mode — fixed (C-18).** A bundled manifest that fails `load()` at runtime now logs `boot_registry_install_failed` and rethrows (isolate boot aborts). The harness empty-registry seam (S00-007 variant b) remains the way to test the degraded discovery end-state without a throwing manifest. The "already installed" catch for harness pre-install (S00-008) is unchanged.
- **`CONFIG_CACHE_TTL_MS` parsing rules are undocumented.** The doc (§3.3) lists the var but not `resolveConfigCacheTtlMs` semantics: unset/empty/non-numeric/negative all fall back to 30 000 ms, and `"0"` is accepted and disables caching (S00-010, S00-011).
- **`LOG_VERBOSITY` parsing rules are undocumented.** The doc lists `0/1/2` but not the `V0/V1/V2` aliases, case-insensitivity, invalid-value fallback to V0, or the code-level default of V2 when `ENVIRONMENT=development` and the var is absent (S00-012…S00-014).
- **Schema bootstrap section conflates migrations.** Doc §4 says "Creates 14 tables" citing the §7.3 baseline, but `20260731120000_platform_schema.sql` creates 12; `token_contract` (+seed), `kill_switch`, `grace_admission_queue`, and `idx_entitlement_installation_id` arrive in four later migrations. The end state the doc asserts is correct (verified in S00-027); the attribution to a single bootstrap step is loose.
- **Empty-reference 404 body shape undocumented.** `GET /v1/requests/` returns 404 with a **null body**, distinct from the plain-text `Not Found` fallthrough (S00-017); no doc distinguishes the two 404 shapes.
- **Control-plane 401 is not a taxonomy body.** `{"error":"unauthorized"}` lacks `code`/`request_reference`/`trace_id`/`retry_safe` (S00-021). The doc shows the body correctly but does not call out that it deliberately bypasses the §5.4 taxonomy envelope used everywhere else at this stage.
- **Doc-accurate behaviors confirmed against code (no drift):** required bindings are exactly DB/R2/DO with rate limiters exempt; cron set is exactly `0 3 * * *` + `0 4 * * *` with flush+reconcile on every tick; wrong-method on control routes is 404; `GatewayObject` is not publicly reachable; the `token_contract` seed is the only SQL seed; `/health` reads no storage or secrets; missing provider keys defer to invoke-time `provider_rejected`.

## Non-automatable notes

- **S00-001…S00-003 (missing DB/R2/DO bindings).** `@cloudflare/vitest-pool-workers` always supplies the bindings declared in the test `wrangler.toml`, so a binding cannot be removed per-test. Proposed seam: a module-level mock of `cloudflare:workers` (`env`) in a plain (non-pool) vitest suite that imports `src/worker.ts` and asserts the throw — or the documented ops probe (orientation doc §8.3.10: comment out one binding stanza and observe the isolate fail to boot).
- **S00-007 (malformed bundled manifest at runtime).** The manifest is a static JSON import baked at build time; it cannot become malformed in a running test isolate without rebuilding the bundle. Proposed seam: the harness registry seam already used by the scenario (`setCapabilityRegistry(new Map(), { replace: true })`) reproduces the observable end-state (empty registry, `capability_unknown` everywhere, `/health` 200). The throwing-`load()` arm is covered at build time by S00-032.
- **S00-028 (migration re-apply idempotency).** The pool applies migrations once per test database; `d1_migrations` tracking is wrangler/D1-platform behavior, not worker code. Proposed seam: wrangler CLI ops probe (doc §8.3.6) — run `wrangler d1 migrations apply` twice against a throwaway local D1 and assert a single seed row.
- **S00-012…S00-014 (log verbosity).** Automatable only if the test runner can capture the worker isolate's `console` output (the logger's default sink writes to `console.log`/`console.error`). If the pool does not expose per-isolate console capture, proposed seam: run the affected request through a logger factory constructed with an injected `LogSink` (the seam already exists in `createLoggerFactory`) while driving the same route handlers.
- **Multi-isolate `platform_counter` lower-bound claim** (doc §3.2: other isolates' in-memory rejection tallies are lost on eviction) is not provable from a single test isolate and belongs to the cron/rate-limit stage chapters; noted here because the claim originates in this stage's wrangler/cron configuration.
