# AI Platform Ops Webservice — Feature Catalog

Inventory of features a **new additive webservice** can expose so operators and developers can invoke AI-platform functionality as if they were:

1. **Clinic side** — installation-authenticated client flows
2. **Control / Admin side** — operator control plane
3. **Debug side** — internal module / stage invocation
4. **E2E / Ops side** — eval, load, gates, scenario replay

**Hard rule:** existing `ai-platform/src/**` files are not modified. The webservice is a sibling package (or separate Worker) that either HTTP-proxies the deployed gateway, imports exported modules / test harnesses, or queries the same D1/R2 bindings from new code.

**Sources:** [`01-ai-platform.md`](./01-ai-platform.md), `ai-platform/src/**`, `ai-platform/test/**`, and parallel inventory passes over clinic, control, debug, and E2E surfaces.

---

## 0. Packaging constraint (how exposure works)

| Mode | What it can do | Notes |
|------|----------------|-------|
| **A. HTTP proxy** | Call live Worker routes as clinic (AAT) or operator (bearer) | No `src` edits; limited by what Worker mounts today |
| **B. Library import** | Call exported functions from `ai-platform/src/*` or `test/eval/*` | New code only; needs Env/bindings where marked |
| **C. Subprocess** | Spawn `npm run verify-manifests`, Vitest suites, load tests | Lowest coupling; label Node vs Workers pool |
| **D. Read models** | D1/R2 SELECT / list UIs not present on Worker | New service code against same bindings |

Recommended layout:

```
ai-platform/          # unchanged Worker + tests
ai-platform-ops/      # NEW webservice catalog implementation
```

### Worker routes that already exist

| Method | Path | Audience |
|--------|------|----------|
| `GET` | `/health` | Anyone (build + environment identity only) |
| `POST` | `/v1/requests` | Clinic (SSE submit) — **transport only today; returns 503 without injected `eventSource`** |
| `GET` | `/v1/requests/{reference}` | Clinic (AAT) — poll terminal / pending state |
| `POST` | `/control/...` | Operator (`OPERATOR_BEARER_TOKEN`) |

Architecture §5.5 surfaces **not** mounted as HTTP yet: capability discovery, usage summary. Library APIs for those exist and belong in Clinic / Debug panes via import.

---

## 1. Clinic Side

Features a clinic installation would use: mint trust, discover capabilities, submit work, cancel, poll outcomes, accept results. Auth is always **AAT** (AI Access Token), never the operator bearer.

### 1.1 Trust & identity (clinic backend + platform verify)

| Feature | How to expose | Status |
|---------|---------------|--------|
| Mint AAT | Proxy / call Supabase `public.issue_ai_token` (clinic LAN) | Clinic-owned; not Worker |
| Decode AAT claims (debug display) | Wrapper-side JWS decode of `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `ver`, `kid` | Safe for ops UI if token is not logged |
| Verify AAT against enrolled key | Import `EnrolledKeyVerifier` (`identity/`) with D1 config | Needs enrolled installation |
| Installation enrollment context | Read clinic settings (platform base URL, enrolled flag) | Clinic DB, not platform |

### 1.2 Capability discovery

| Feature | How to expose | Status |
|---------|---------------|--------|
| Discover manifests for principal | Import `discover` + `buildDiscoveryResponse` (`capability/`) | **Library only** — no Worker route |
| Resolve capability + version pin | Import `resolve` | Library |
| Browse published manifests | Read `manifests/published/` + `load()` | Offline / build assets |
| Published product today | `clinic.visit_summary@1.0.0` | Live registry |
| Conversational product | `clinic.chat_assistant` | Eval fixture only (not in published registry) |

### 1.3 Submit, stream, cancel

| Feature | How to expose | Status |
|---------|---------------|--------|
| Submit capability request (SSE) | Proxy `POST /v1/requests` with headers `x-idempotency-key`, `x-capability-version`, optional `x-trace-id`, body `{ capability_id, capability_version, user_intent, context, … }` | Route exists; **inference not wired** in `worker.ts` (503) |
| Conversational turn | Same endpoint + `conversation_id`, `turn_ordinal`, `transcript` | Code paths exist; needs wired orchestrator |
| Cancel in-flight | Abort SSE / close connection (no separate cancel URL) | Per architecture §5.5 / §8.7 |
| SSE event console | Proxy stream; show `accepted`, `heartbeat`, `text_delta`, `partial_structured`, `regenerating`, `progress`, terminals | Adapter vocabulary ready |
| Terminal kinds | `completed` \| `failed` \| `cancelled` \| `context_requested` (conversational only) | Frozen |

### 1.4 Request lookup & conversation

| Feature | How to expose | Status |
|---------|---------------|--------|
| Get request by reference | Proxy `GET /v1/requests/{ref}` with AAT | **Live** |
| States | `Completed` (+ result), `Failed` (+ code), `Cancelled`, `AwaitingContext`, in-flight `pending` | Live |
| Conversation leg timeline | Import `listConversationLegs` | Library + D1 |
| Human acceptance | Clinic RPC `public.record_ai_acceptance` | Clinic-owned |

### 1.5 Usage / quota (clinic view)

| Feature | How to expose | Status |
|---------|---------------|--------|
| Usage summary for installation | Architecture §5.5 surface | **No HTTP**; would need new additive route or D1/DO read model in ops service |
| Soft-threshold / degraded notice | Observe `degraded_notice` on `accepted` SSE | When pipeline wired |

### 1.6 Suggested Clinic pane sections

1. **Enrollment context** — installation id, platform URL
2. **Token lab** — mint + claim viewer
3. **Discovery** — manifests / etag (import until HTTP exists)
4. **Submit console** — capability picker, context JSON, SSE log
5. **Request lookup** — reference → get-request
6. **Conversation trace** — legs by `conversation_id`
7. **Acceptance** — record acceptance via clinic RPC

### 1.7 Clinic security rules for the webservice

- Scope every journal/get by `installationId` from verified AAT `iss`
- Never mix operator `/control/*` into the Clinic pane
- Never log full AAT, context payloads, or prompt text
- Support lookup remains operator-only (full R2 envelopes)

---

## 2. Control / Admin Side

Operator-authenticated surface (`Authorization: Bearer <OPERATOR_BEARER_TOKEN>` → `OPERATOR_ID`). All Worker control routes are **POST**. Every mutation is audited in `control_audit`.

### 2.1 Installation lifecycle (proxy 1:1)

| Feature | Route | Handler |
|---------|-------|---------|
| Enroll installation | `POST /control/installations/{id}/enroll` | `handleEnroll` |
| Rotate key | `…/rotate` | `handleRotate` |
| Revoke key | `…/revoke-key` | `handleRevokeKey` |
| Suspend | `…/suspend` | `handleSuspend` |
| Resume | `…/resume` | `handleResume` |
| Soft-delete | `…/delete` | `handleDelete` |
| Purge (irreversible wipe) | `…/purge` | `handleInstallationPurge` |

Enroll creates `installation` + key + **pending** entitlement (zero economics). Economics assignment is a separate architecture concern (see gaps).

### 2.2 Token contract (platform-global)

| Feature | Route |
|---------|-------|
| Begin `ver` rotation (accept ≤2) | `POST /control/token-contract/begin-rotation` |
| Retire a `ver` | `POST /control/token-contract/retire` |

Clinic mint side (`ai.aat.ver`) is clinic-deployment only; platform only owns the accepted set.

### 2.3 Capability availability

| Feature | Route |
|---------|-------|
| Deprecate version (needs `successor_id`) | `POST /control/capabilities/{id}/versions/{ver}/deprecate` |
| Retire after overlap window | `…/retire` |
| Cohort activate (installation list) | `…/activate` |
| Cohort promote (plan/installation grants) | `…/promote` |

### 2.4 Routing policy

| Feature | Route |
|---------|-------|
| Publish policy document → R2 + D1 | `POST /control/routing-policies/{policyId}/versions/{version}/publish` |
| Canary to installations | `…/canary` |
| Promote to global active | `…/promote` |
| Rollback | `…/rollback` |

Highest-leverage actions in the system — webservice should require confirmation, diffs, and canary evidence before promote.

### 2.5 Support audit

| Feature | Route | Body |
|---------|-------|------|
| Lookup request + attempts + R2 envelope | `POST /control/support/lookup?reference=` | Full PHI/diagnostic payload |

### 2.6 Admin features without Worker HTTP (expose via import / D1)

| Feature | Module / approach |
|---------|-------------------|
| Installation directory | D1 `SELECT` on `installation`, keys, entitlement |
| Control audit trail browser | D1 `control_audit` |
| Routing policy viewer | D1 `routing_policy` + R2 document |
| Token contract accepted-set viewer | D1 `token_contract` |
| Ops dashboards | Import `runAllDashboardQueries` (`dashboards/`) |
| Rollup + reconciliation | Import `runRollupAndReconciliation` (`rollup/`) |
| Retention purge (manual) | Import `runRetentionPurge` (`retention/`) — already on cron `0 3 * * *` |
| Config cache inspector | `ConfigCache` / `loadConfig` / `createD1ConfigReader` |

Dashboard exports: latency-by-provider, validation-failure-by-prompt, fallback-rate, cost-per-capability-per-installation, quota-rejection-rate. Repair-rate is currently a stub.

### 2.7 Architecture control features **not** available yet

Mark as “not exposed — no platform API” in the UI:

| Feature | Notes |
|---------|-------|
| Entitlement assignment (plan, quota, budget, capabilities, period, soft threshold → active) | Enroll only seeds `pending` zeros |
| Kill-switch CRUD (global / capability / installation / provider) | Read path expects data; no writers / table |
| Explicit capability grant/revoke outside cohort promote | Partial via cohort only |
| Multi-operator RBAC | Single shared bearer today — webservice should add its own identity + MFA before forwarding the platform secret |

### 2.8 Dangerous ops — mandatory webservice guards

| Op | Guard |
|----|-------|
| Purge | Typed confirmation, dry-run counts, break-glass in prod |
| Delete vs purge | Distinct UX; purge is data wipe |
| Token retire | Show accepted set; never retire sole `ver` blindly |
| Routing promote / rollback | Canary evidence, policy diff, post-check |
| Capability retire | Enforce deprecate → wait → retire |
| Suspend | Clear “AI denied” messaging; reversible |

### 2.9 Suggested Admin pane sections

1. **Installations** — enroll / rotate / suspend / resume / delete / purge wizards
2. **Entitlements (read-only + gap notice)**
3. **Token contract** — accepted-set + rotation wizard
4. **Capabilities** — deprecate / retire / cohort
5. **Routing** — publish → canary → promote / rollback
6. **Support lookup**
7. **Dashboards & reconciliation**
8. **Audit log**

---

## 3. Debug Side — internal modules & operations

Invoke pipeline stages and pure helpers without going through clinic or control HTTP. Pattern: **import exported symbols** into the new service (same recipes as `ai-platform/test/*`).

### 3.1 Pipeline stage console (§6.1)

| Stage | Feature | Primary entry |
|-------|---------|---------------|
| 1 | Ingress body parse / size gate | `parseAdapterRequestBody`, `INGRESS_BODY_SIZE_LIMIT` |
| 2 | Identity verify | `EnrolledKeyVerifier` |
| 3 | Entitlement dry-run | `evaluateEntitlement` |
| 4 | Rate-limit probe | `checkRateLimit` |
| 5 | Capability resolve | `resolve`, `discover` |
| 6 | Context / transcript validate | `validateContext`, `buildContextRequiredResponse` |
| 7 | Cost preflight | `runCostPreflight`, `estimateInputTokens` |
| 8 | Admission (quota / jti / idempotency) | `runAdmission`, `admissionRPC` |
| 9 | Journal create | `createRequestRow` |
| 10 | Prompt compose | `composeRequest` |
| 11 | Route + invoke | `selectCandidateChain`, `runInvocation` |
| 12–14 | Stream + validate | `createStreamBroker`, `createStructuredStreamBroker`, `validateAndRepair` |
| 15–16 | Credit + detail | `creditUsage`, `writePostResponseDetail`, `recordTerminalState` |
| Guard bundle | Stages 1–10 | `runGuard` (`pipeline/`) |
| Happy-path settle | FakeAdapter post-guard | `settleHappyPath` |

### 3.2 Contracts & taxonomy tools

| Feature | Symbols |
|---------|---------|
| Canonical encode/decode / lint | `encodeCanonicalRequest`, `assertNoProviderShapedFieldNames`, … (`contracts/canonical.ts`) |
| Error taxonomy browser | `ALL_TAXONOMY_CODES`, `buildErrorBody`, `liveHttpStatusForCode` (`errors.ts`) |
| Request reference mint / normalize | `generateRequestReference`, `normalizeRequestReference` (`reference.ts`) |
| Trace / structured logger | `resolveTraceId`, `createStructuredLogger` (`trace.ts`) |
| SSE event builders | `buildAcceptedSseEvent`, `pushTerminalEvent` (`adapter.ts`) |

### 3.3 Manifest, prompts, context

| Feature | Symbols |
|---------|---------|
| Load / hash / verify manifest tree | `load`, `hashManifest`, `verifyManifestTree`, `verifyPublishedRegistry` |
| Prompt artifact inspect | `resolveArtifact`, `allRegistryPins`, `verifyAllRegistryPins` |
| Compose preview | `composeRequest`, `renderThroughTemplate` |
| Context key shape validate | `validateKey`, `validatePayload`, `publishedShapeForKey` |
| Context-request payload validate | `validateContextRequest` |

### 3.4 Routing, providers, invoke loop

| Feature | Symbols |
|---------|---------|
| Dry-run route chain | `selectCandidateChain`, `preloadRoutingPolicyForInstallation` |
| Soft-threshold / degraded tier | `resolveRoutingTier`, `isSoftThresholdCrossed` |
| Client routing-injection lint | `bodyHasClientRoutingInjection` |
| Provider list | `listWiredProviderIds`, `createProviderAdapter` |
| Fake invoke (no network) | `FakeAdapter` |
| Classify provider failure | `classifyFailure` |
| Wire-map with fixture transport | `GeminiAdapter` / `DeepSeekAdapter` + injected `Transport` |
| Full invoke with scripted chain | `runInvocation` |
| Backoff preview | `computeJitteredBackoff`, `pureExponentialBackoffMs` |

### 3.5 Validation, stream, journal internals

| Feature | Symbols |
|---------|---------|
| Phase-by-phase response validate | `runValidationPhases`, `validateAndRepair` |
| Prose stream guards | `checkIncrementalGuards`, `runFullGuardSet` |
| Journal FSM lint | `isJournalTransitionAllowed`, `canReachAwaitingContext` |
| Support trace (operator) | `supportLookup` |
| Grace / credit diagnostics | `peekPendingGraceAdmissions`, `peekDroppedGraceJournal`, `reconcileGraceUsage` |
| Rejection counters flush | `flushRejectionCounters` |

### 3.6 Bindings vs pure (for UI labeling)

| Kind | Examples |
|------|----------|
| **Pure / CPU** | compose, context validate, canonical codec, taxonomy, soft-threshold math, FakeAdapter |
| **Needs D1** | identity verify, entitlement, journal, discover, dashboards, support lookup |
| **Needs R2** | support envelope, routing policy docs, post-response payloads, purge |
| **Needs Quota DO** | admission / credit / release |
| **Needs Rate Limit bindings** | `checkRateLimit` |
| **Needs provider secrets** | live Gemini / DeepSeek adapters |

### 3.7 Must not expose even in Debug (or gate hard)

- Provider API keys / secret binding values
- Full AAT strings in logs
- Raw context / prompt / R2 envelopes to unprivileged users (PHI)
- Direct Quota DO / GatewayObject RPC from the public internet without operator auth
- `__setArtifactContentForTest` overlays outside a sandbox

### 3.8 Suggested Debug pane sections

1. **Stage runner** — pick stage 1–16 or `runGuard`
2. **Compose lab** — manifest + context → canonical request
3. **Router lab** — policy + installation → candidate chain
4. **Adapter lab** — fixture replay (DeepSeek / Gemini trees under `test/fixtures/`)
5. **Validator lab** — response / repair / context-request
6. **Taxonomy & SSE preview**
7. **Journal / support inspector** (operator-gated)

---

## 4. E2E / Ops Side

Trigger architecture §8 sequences, eval harnesses, load/cost gates, and CI-style checks without editing `src`.

### 4.1 Health & diagnostics

| Feature | How |
|---------|-----|
| Build / environment health | Proxy `GET /health` |
| Deep readiness (D1 / R2 / DO / secrets) | **Additive** in ops service — not on Worker today |
| Cron job status awareness | Document schedules: rejection flush + grace each tick; retention `0 3 * * *`; rollup `0 4 * * *` |

### 4.2 Scenario families (§8 → runnable recipes)

| Scenario | Trigger via |
|----------|-------------|
| Happy-path streaming prose | Adapter/stream/invocation tests; eval golden `visit_summary.happy_path`; **not** live `POST /v1/requests` until orchestrator wired |
| Structured JSON + enrichment | `structured-modes`, response-validator tests |
| Missing-context self-heal | Context validator / pipeline stage 6; eval `insufficient_context` |
| Validation repair → failure | `response-validator`, structured modes |
| Provider fallback / regenerating | `invocation`, router, adapter fixtures |
| Cancel / disconnect | Stream broker + adapter disconnect tests |
| Quota / rate reject / soft threshold | `quota-do`, `rate-limit`, `soft-threshold-routing` |
| Support audit | Control `POST /control/support/lookup` |
| Conversational negotiation | Conversation harness + transcript / context-requested tests |
| Enrollment bootstrap | Control enroll + identity tests |

### 4.3 Eval harness (importable)

| Feature | Entry |
|---------|-------|
| Golden suite | `runGoldenSuite` — `test/eval/harness.ts` |
| Live smoke (real providers) | `runLiveSmokeSuite` — needs `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` |
| Conversation suite | `runConversationSuite` — `test/eval/conversation-harness.ts` |
| List cases / capabilities | `listEvalCapabilities`, `listCapabilityCases`, … |
| Score quality / schema | `scoreQuality`, `scoreSchema` |
| Score reports | `test/eval/score-report.ts`, `conversation-score-report.ts` |
| Prohibitions / R-12 | `prohibitions.test.ts` |

Offline: golden + conversation. Online: live smoke (also GitHub workflow `ai-platform-eval-live-smoke.yml`).

### 4.4 Load & cost

| Feature | Entry |
|---------|-------|
| Concurrent guard+settle N=20 | `runLoadHappyPath` (`test/load/happy-path.ts`) — **Workers/Miniflare only** |
| CI script | `npm run test:load` |
| Measurement report | Guard P95, 1 R2 Class A / request, 2 DO fetches / request, 1 hot-path D1 insert |

### 4.5 Gates & migrations

| Feature | How |
|---------|-----|
| Manifest registry gate | `npm run verify-manifests` / `verifyManifestTree` |
| Prompt registry pin gate | same + `verifyAllRegistryPins` |
| D1 migrations apply / snapshot | `test/migrations.test.ts` |
| Full unit suite | `npm run test:unit` |
| Full test (Node + Workers) | `npm test` |

### 4.6 Provider fixture replay ops

Replay `test/fixtures/{deepseek,gemini}/` trees:

- request-mapping, stream, errors, truncate, malformed, usage, timeout
- DeepSeek visit-summary golden binding

Via Vitest adapter suites or Debug adapter lab with fixture transport.

### 4.7 Suggested E2E Ops pane sections

1. **Health** — shallow + (future) deep
2. **Scenario runner** — §8 families as labeled jobs
3. **Eval** — golden / conversation / live smoke + report download
4. **Load & cost** — Workers-pool job
5. **Gates** — manifests, prompts, migrations
6. **Support audit** — operator lookup
7. **Fixture browser** — provider golden trees

Label every job **Node-only** vs **Workers/Miniflare** vs **Live egress**.

---

## 5. Cross-cutting catalog index

| Category | Proxy Worker | Import `src` | Import `test/eval|load` | Subprocess Vitest | D1/R2 read model |
|----------|:------------:|:------------:|:-----------------------:|:-----------------:|:----------------:|
| Clinic submit/poll | ✓ | partial | | | |
| Clinic discovery | | ✓ | | | |
| Control mutations | ✓ | | | | |
| Support lookup | ✓ | ✓ | | | |
| Dashboards / rollup | | ✓ | | | ✓ |
| Stage / compose / route debug | | ✓ | | | |
| Golden / conversation eval | | | ✓ | ✓ | |
| Live smoke | | | ✓ | ✓ | |
| Load/cost | | | ✓ (Workers) | ✓ | |
| Manifest/prompt gates | | ✓ | | ✓ | |

---

## 6. Explicit gaps the webservice must document

These belong in the UI as “not available” or “library-only until platform mounts them”:

1. **Live E2E inference** via `POST /v1/requests` — adapter requires `eventSource`; Worker does not inject production orchestrator yet
2. **HTTP capability discovery** — `discover()` exists, no route
3. **HTTP usage summary** — §5.5; no route
4. **Entitlement management API** — architecture §4.5; enroll stub only
5. **Kill-switch writers** — no control API / durable table wired
6. **Deep `/ready` probe** — `/health` is identity only
7. **Repair-rate dashboard** — stubbed
8. **Conversational capability** in published registry — eval-only today

---

## 7. Auth model for the webservice itself

The ops webservice should **not** be anonymous just because it wraps internal tools.

| Pane | Credential forwarded / used |
|------|-----------------------------|
| Clinic | Clinic staff session → AAT mint; never operator secret |
| Control / Support / Dashboards with PHI | Operator identity in the ops UI → then platform `OPERATOR_BEARER_TOKEN` server-side |
| Debug pure functions | Local / gated debug role; no secrets |
| Debug with D1/R2/DO | Operator (or environment-scoped) role |
| Live smoke / providers | Separate secret vault; never returned to browser |

Prefer: ops-service identity + MFA + per-action authorization, with the platform bearer held only in the service backend.

---

## 8. Minimal first slice (recommended)

If implementing the webservice incrementally without touching `ai-platform/src`:

1. **Clinic:** health + get-request proxy + AAT mint helper + discovery via `discover()` import
2. **Admin:** proxy all existing `/control/*` routes with confirmation UX for purge / promote / retire
3. **Debug:** compose lab + context validate + route dry-run + taxonomy browser (pure)
4. **E2E:** `verify-manifests`, golden suite import, support lookup proxy

Defer until platform wiring lands: live submit SSE happy-path against deployed Worker, usage summary HTTP, entitlement editor.
