# AI Platform — System Testing Plan

Status: approved for implementation
Author: test-planning agent (synthesized from `docs/architecture/ai-platform/data-journey/*.md`)
Date: 2026-09-03

---

## 1. Purpose

The data-journey docs (`01`–`20`) define per-stage **behavioral verification** probes:
operator commands (`POST /control/*`), runtime requests (`POST /v1/requests`,
`GET /v1/capabilities`, `GET /v1/requests/{ref}`), cron ticks, and D1/R2/DO
inspections. Existing tests in `ai-platform/test/` cover units, single handlers,
and one-request orchestration. What is missing is a **system test** layer:

> A system test here is a **multi-command, multi-stage scenario**: a scripted
> sequence of control commands and client requests executed against the real
> worker (HTTP via `SELF.fetch`), asserting the **interactions** between
> responses, SSE event streams, D1 journal/config rows, R2 objects, Quota
> Durable Object behavior, and the control audit trail — not any single
> endpoint in isolation.

Each scenario traces back to one or more "Behavioral verification" sections in
the data-journey docs, converted from manual `curl`/`wrangler` probes into
automated vitest cases.

## 2. Scope decisions

**In scope** — everything executable against the Miniflare workers pool:

- Full HTTP surface: all `/control/*` commands, `POST /v1/requests` (SSE),
  `GET /v1/capabilities`, `GET /v1/requests/{ref}`, `/health`.
- Real Miniflare D1 (all 14 tables, all 10 migrations), real R2 bucket,
  real `GatewayObject` Durable Object.
- Cross-store invariants: journal ↔ attempts ↔ usage ↔ envelope ↔ pointer,
  control command ↔ audit row ↔ runtime behavior change, cron ↔ retention/
  rollup/grace reconciliation.
- The full error taxonomy matrix (doc 19) executed end-to-end, asserting both
  wire shape **and** journal side effects (or their absence).

**Out of scope** (stay manual probes in the docs, or covered elsewhere):

- Clinic-side Supabase RPCs (`issue_ai_token`, `enroll_installation_keypair`,
  `record_ai_acceptance`, …). System tests mint AATs directly in-harness with
  WebCrypto Ed25519 (pattern already proven in
  `test/worker-request-orchestrator.test.ts`). The platform only ever verifies
  the enrolled public key, so this is faithful.
- Live-provider (DeepSeek/Gemini) wire behavior — pinned to the `fake`
  provider via routing policy, per doc 12's own probe technique.
- `CONCURRENCY_LIMIT = 16`, grace-admission-under-DO-outage, 2-hour ephemeral
  horizon, prose-guard `validation_failed` trips, real 31-second cache TTL
  waits — documented **Unprobeable** paths in the docs; the suite asserts the
  reachable half of each invariant instead.
- The eval suite and load suite (separate concerns, already exist).

## 3. Harness specification (`ai-platform/test/system/`)

### 3.1 Registration

- New files: `test/system/harness.ts` plus one `*.system.test.ts` per suite.
- Add `test/system/**/*.system.test.ts` to `include` in
  `vitest.workers.config.ts`; add the same glob to `exclude` in
  `vitest.config.ts` (the node config's `test/**/*.test.ts` would otherwise
  pick them up).
- Run command: `npx vitest run --config vitest.workers.config.ts test/system/`.

### 3.2 Harness module responsibilities

`test/system/harness.ts` exports a `newScenario()` factory. Each call returns
a fresh scenario context and **must** generate fresh UUIDs for installation,
org, branch, actor, and kid. Rationale (doc 18 invariant): wiping D1 does
**not** zero Quota DO counters — state is per-`installation_id`, so every test
scenario gets a brand-new installation identity.

Required exports (names may be adjusted by the implementer, semantics may not):

| Export | Behavior |
|---|---|
| `applyAllMigrations(db)` | Applies all 10 files in `ai-platform/migrations/` in filename order via `?raw` imports + the split-on-`;` pattern already used in `test/control.test.ts`. Called once in `beforeAll`. |
| `resetPlatformState()` | Deletes rows from all 14 tables in FK-safe order (existing per-file `clearLifecycleTables` patterns, generalized), and re-asserts the seeded `token_contract` row (`ver='1'`, `retired_at` NULL). Called in `beforeEach`. `isolateConfigCache.clear()` is already wired per-test via `test/setup-isolate-config-cache.ts`. |
| `newScenario()` | Returns `{ installationId, orgId, branchId, actorId, kid, keypair }` with a generated Ed25519 keypair. |
| `mintAat(scenario, overrides?)` | Signs a compact EdDSA JWS. Defaults: `aud="ai-platform"`, `ver="1"`, `role="clinician"`, `scopes=["ai.visit_summary","ai.access"]`, `exp-iat=300`. Overrides cover every claim (for negative probes: bad aud, bad ver, oversized lifetime, wrong alg, missing org, etc.). |
| `operatorFetch(path, body?)` | `SELF.fetch` POST to `/control/...` with `Authorization: Bearer test-operator-bearer-token` and JSON body; returns `{ status, json }`. A no-auth variant `operatorFetchRaw(path, body?, headers?)` supports the 401 matrix. |
| `invoke(scenario, opts)` | `SELF.fetch` `POST /v1/requests` with required headers (`x-idempotency-key` defaulting to a fresh UUID, `x-capability-version` default `"1.0.0"`, optional `x-trace-id`) and the visit-summary body wired to the scenario's org/branch. Returns `{ status, headers, body, events }` where `events` is parsed SSE (`{ event, data }[]`, empty for non-SSE). Generalizes `fetchLivePost`/`parseSseEvents` from `worker-request-orchestrator.test.ts`. |
| `flushBackgroundWork()` | Generalized export of the orchestrator's waitUntil drainer so settlement assertions are deterministic. |
| `getCapabilities(token, ifNoneMatch?)` | `GET /v1/capabilities`; returns `{ status, etag, body }`. |
| `getRequest(token, ref)` | `GET /v1/requests/{ref}`; returns `{ status, body }`. |
| `publishPolicy(policyId, version, document)` / `canary` / `promote` / `rollback` | Thin wrappers over the routing control routes; `publishPolicy` asserts the D1 row + R2 object exist on success. |
| `fakePolicyDocument(policyId, version, opts?)` | Routing policy document pinned to `provider_id: "fake"` with a proper catch-all; `opts` supports canary rules, overrides, malformed targets, per-target `requires` for exclusion tests. |
| `d1` helpers | `queryOne(sql, params)`, `queryAll`, `count(table, where)`, and typed readers: `getAiRequest(ref)`, `getAttempts(requestId)`, `getUsageEvents(requestId)`, `getEntitlement(installationId)`, `getGrants(scope)`, `getAudits(action, target)`, `getRoutingPolicy(policyId, version)`. |
| `getR2Json(key)` / `r2Exists(key)` | R2 object assertions for `control/routing-policy/...` and `request/{id}/envelope`. |
| `runScheduled(cron)` | Trigger the worker's `scheduled()` handler for the given cron expression (e.g. `"0 3 * * *"` retention, `"0 4 * * *"` rollup). Implementer validates the best mechanism available in `@cloudflare/vitest-pool-workers` (e.g. `SELF.scheduled(...)`); falling back to importing the module entry and invoking `scheduled` with the pool `env`/`ctx` is acceptable. |

### 3.3 Cross-cutting harness rules

1. **Prompt registry**: `vi.mock("../../src/prompt/registry", ...)` exactly as
   `worker-request-orchestrator.test.ts` does; register the visit-summary
   manifest via `setCapabilityRegistry` in `beforeAll`.
2. **Cache**: never sleep 31 s. `isolateConfigCache.clear()` after any direct
   D1 mutation (the harness's D1 write helpers do this automatically).
3. **SSE assertions**: every SSE scenario asserts event **order**
   (`accepted` first, exactly one terminal, nothing after terminal) and the
   two-trace-identifier rule (doc 12: SSE `trace_id` = client trace;
   envelope `prompt.correlationIds.trace_id` = AAT `jti`).
4. **Journal non-writes**: every pre-SSE failure case asserts
   `count(ai_request)` unchanged.
5. **Time**: retention/aging probes backdate via direct D1 `UPDATE`, per docs
   14/16/17.
6. `fileParallelism: false` is already set for the workers pool; tests must
   still be order-independent within a file (fresh scenario per test).

## 4. Suite catalog

Traceability key: `DJ-nn §x.y` = data-journey doc `nn`, section x.y.

---

### Suite 1 — `golden-journey.system.test.ts`
**The full happy path, stages 0→12, as one continuous interaction chain.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-1.1 | Boot & health | `GET /health` 200 with `environment`; 14 platform tables exist (DJ-02 §8, DJ-16 §15.3.1). |
| SYS-1.2 | Enroll → storage truth | `POST /control/installations/{id}/enroll` 200 `{platform_base_url}`; D1: installation `active`, key `valid_until = valid_from + 365d`, entitlement `pending` with zero quotas and `allowed_capabilities='[]'`; audit `enroll` with `operator_id='operator-test-principal'`. Re-enroll → 409 `already_enrolled` (DJ-05 §8.3, DJ-16 §15.3.3). |
| SYS-1.3 | Pending gates runtime | `GET /v1/capabilities` → 200 `{manifests: []}`; `POST /v1/requests` → 403 `forbidden_capability`; zero `ai_request` rows (DJ-06 §11.3.4, DJ-09 §6.3.3). |
| SYS-1.4 | Entitle → grants | Entitle 200 `{status:"active"}`; D1 entitlement budgets exact; two grants (`installation:` + `plan:` scopes) `revoked_at` NULL, overlay columns NULL; audit `entitle` with `after_pointer`; re-entitle → 409 `not_pending` (DJ-06 §11.3.5–6, DJ-16 §15.3.4). |
| SYS-1.5 | Discovery after entitle | `manifests[0]` carries full field set (`Identity`, `Access`, `Interaction`, `Input`, `Routing.routingPolicyRef="routing/standard"`, `Economics`, `Governance`); `ETag` present; second GET with `If-None-Match` → 304 empty body (DJ-09 §6.3.4–6). |
| SYS-1.6 | Publish → not served | Publish fake policy 200; D1 row `status=published`, `content_pointer` correct; R2 object round-trips. Invoke → SSE `accepted` then `failed` `internal_error` (published is not served) (DJ-07 §9.3.4/9.3.7, DJ-12 §19.3.2). |
| SYS-1.7 | Promote → invoke completes | Promote 200; invoke → SSE order `accepted` → `text_delta` → `completed` with `finalContent.text="Fake adapter summary."`; headers `text/event-stream` (DJ-12 §19.3.5). |
| SYS-1.8 | Journal + settlement consistency | `ai_request`: `state=Completed`, `completed_at` set, `terminal_error_code` NULL, `payload_pointer='request/{id}/envelope'`, `routing_decision` JSON with `policy_id/rule_id/chain`; exactly one `ai_attempt` (`outcome=success`); exactly one `usage_event` with `period` = `YYYY-MM` of entitle `period_start`, `tokens = tokens_in+tokens_out`, `cost` equal to attempt cost (DJ-11 §14.3.10, DJ-13 §10.3.2–4). |
| SYS-1.9 | Envelope completeness | R2 `request/{request_id}/envelope` top-level keys exactly `{context, prompt, attempts, result}`; context contains only permitted keys; one object only (no `envelope.json`, no `attempts` sidecar) (DJ-17 §3.3.10–11). |
| SYS-1.10 | Client GET + support lookup | `GET /v1/requests/{ref}` → 200 `{state:"Completed", result:{…}}`, no `attempts`/`envelope` keys; `POST /control/support/lookup` → `{request, attempts, envelope}` with `requestId` matching; `control_audit` count unchanged by lookup (DJ-14 §5.3.2–3). |

---

### Suite 2 — `lifecycle-interplay.system.test.ts`
**Control-plane lifecycle commands against live runtime traffic.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-2.1 | Suspend blocks, resume restores | Enroll+entitle+promote; invoke OK. `suspend` → 200, D1 `status=suspended`; invoke → 403 `installation_suspended`, `retry_safe=false`, no journal row; discovery behavior per identity stage. `resume` → invoke OK again (DJ-11 §14.3.4, DJ-14 §5.3.4). |
| SYS-2.2 | Illegal transitions | Suspend twice → 409 `illegal_lifecycle_transition`; resume while active → 409; resume after delete → 409 (DJ-05 §8.3.11–12). |
| SYS-2.3 | Rotate additive overlap and revoke-key | Enroll+entitle+promote; invoke OK with K0 AAT. Rotate to K1 → 200; K1 `valid_until=+365d`; K0 `revoked_at` still NULL. K0 and K1 AATs both invoke OK (dual-key overlap). `revoke-key` K0 → 200; K0 AAT → 401 `unauthenticated`; repeat revoke K0 → 409 `key_already_revoked`; revoke last active key K1 → 409 `cannot_revoke_last_active_key` (DJ-05 §8.3, DJ-15 §11.3.2). |
| SYS-2.4 | Delete then purge | Delete → `status=deleted`, invoke → 401. Complete one request first, then purge → 200 `{}`: all D1 rows for the installation gone (installation, key, entitlement, grants, ai_request, ai_attempt, usage_event), R2 envelope gone, audit contains `purge_installation`; old AAT → 401 (DJ-05 §8.3.12–13, DJ-17 §3.3.16). |
| SYS-2.5 | Re-enroll after purge is fresh | Same UUID enrolls cleanly; entitlement `pending` again; runtime gated until entitle (DJ-05 §8.3.13 invariant). |
| SYS-2.6 | Operator auth matrix | Every `/control/*` route used in this suite: no bearer / wrong bearer / staff AAT → 401 `unauthorized`; no audit rows written on auth failure (DJ-06 §11.3.2, DJ-07 §9.3.2). |

---

### Suite 3 — `entitlement-grant-interplay.system.test.ts`
**Stage 4 commands vs guard stage 3 / stage 5 runtime behavior.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-3.1 | Independent switches matrix | Direct D1 flips (cache-clear each time): `allowed_capabilities='[]'` → 403; delete installation grant → 403; grant version `9.9.9` → 403 at stage 3 (and forced-stage-5 variant → 404 `capability_unknown`); `plan='starter'` → 403 (`plan_tier`); entitlement `status='suspended'` → 403 (`ai_disabled`). Restore-and-pass after each (DJ-06 §11.3.7, DJ-11 §14.3.5–6). |
| SYS-3.2 | Role & scope enforcement | Doctor-role AAT (no `ai.visit_summary` scope) → 403; minted AAT with scope but `role='doctor'` → 403 (`allowedStaffRoles` clinician/nurse); clinician + scope → passes (DJ-06 §11.3.8, DJ-11 §14.3.6). |
| SYS-3.3 | Kill-switch scopes vs discovery/invoke | `installation`-scoped row → invoke 503 `capability_disabled`, discovery **still lists** the capability; `capability`-scoped → same; `global` → same; delete rows → invoke passes again (DJ-06 §11.3.9, DJ-09 §6.3.8, DJ-11 §14.3.5). |
| SYS-3.4 | Entitle does not overreach | Entitle leaves `routing_policy` count unchanged, `installation.status=active`, `entitlement.plan` unchanged; no AAT minted (nothing to assert client-side beyond absence of token in response) (DJ-06 §11.3.10). |
| SYS-3.5 | Entitlement uniqueness & validation | Direct duplicate INSERT → unique-index failure; entitle payload failures (bad ISO dates, `period_start>=period_end`, negative quotas, `soft_threshold` 1.5, non-string capabilities, empty grants, `scope:"global"`) → 400 `invalid_payload` with row unchanged; unknown installation → 404 `installation_not_found` (DJ-06 §11.3.3, DJ-16 §15.3.4). |
| SYS-3.6 | Multi-installation same-plan entitle | Two installations on `plan:standard`; entitle both with dual-scope payload → both 200; D1 has exactly one live `plan:standard` grant for `clinic.visit_summary` and one live installation grant per installation; publish+promote fake policy → both installations invoke to `completed`. |

---

### Suite 4 — `routing-policy-traffic.system.test.ts`
**Stage 5 control lifecycle driving stage 10 routing decisions on live traffic.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-4.1 | Publish validation & immutability | 400 `invalid_json`/`missing_document`/`invalid_policy_identity`; 200 `warnings: ["unreferenced_policy"]` when no capability references the policy id; duplicate publish → 409 `already_published` and R2 bytes unchanged; publish is R2-put only after D1 existence check (DJ-07 §9.3.3–5, DJ-17 §3.3.3–6). |
| SYS-4.2 | Canary split two installations | I0 and I1 both entitled; publish v1+v2; promote v1, canary v2 onto I0. Invoke as I0 → `routing_decision.policy_version=2`; invoke as I1 → `policy_version=1` (DJ-07 §9.3.9, DJ-12 §19.3.14). |
| SYS-4.3 | Promote & rollback semantics | Promote v2 → v2 `active`, v1 `superseded`; canary on active → 409 `illegal_policy_transition`; rollback → v1 active again; rollback with no superseded → 409 (DJ-07 §9.3.10–11). |
| SYS-4.4 | Version tie-break | Publish versions 9, 10, 11 with equal `active_from`; rollback picks **10** not 9 (`active_from DESC, rowid DESC`) (DJ-07 §9.3.11, DJ-16 §15.3.6). |
| SYS-4.5 | Missing R2 document | Delete the R2 object for the active policy; invoke → SSE `accepted` → `failed` `internal_error`, `routing_decision` NULL; restore object (DJ-07 §9.3.13). |
| SYS-4.6 | Fail-closed target filters | Targets with missing `min_context_window`, string `languages`, bad `cost_class`, `latency_class` mismatch → each excluded with its reason (`feature_unsupported`, `language_unsupported`, …); all-excluded → SSE `failed` `provider_unavailable` **not** `internal_error` (DJ-07 §9.3.18, DJ-12 §19.3.11, DJ-20 §1.3.14). |
| SYS-4.7 | Overrides & exclusions | Installation override `exclude_providers:["fake"]` → chain empty, `installation_excluded`, `provider_unavailable`; `force_cost_class` → `cost_class_source="installation_override"`; first matching override wins (DJ-07 §9.3.17). |
| SYS-4.8 | Provider kill-switch failover | `kill_switch` row `provider:deepseek` with chain `[deepseek, fake]` → invoke passes guard (no 503), `accepted` → fake completes, deepseek excluded with reason `kill_switch`. Contrast: `provider:fake` kill → 503 `capability_disabled` pre-SSE (DJ-07 §9.3.19, DJ-19 §1.3.13). |

---

### Suite 5 — `quota-admission-interplay.system.test.ts`
**Quota DO admission × entitlement ceilings × routing tier × journal.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-5.1 | Request-quota exhaustion | Entitle `request_quota=2`; two fresh admits OK; third (fresh AAT+key) → 429 `quota_exhausted`, `retry_safe=true`, **no** `retry_after`; `ai_request` count stays 2 (DJ-18 §5.3.6, DJ-19 §1.3.6). |
| SYS-5.2 | Soft-threshold degraded tier | `soft_threshold` such that second admit crosses it → SSE `accepted` carries `degraded_notice: true`; D1 `routing_tier='degraded'` and `routing_decision.routing_tier='degraded'`; rule with `tiers:["standard"]` skipped; `soft_threshold=0` disables (DJ-11 §14.3.12, DJ-12 §19.3.14). |
| SYS-5.3 | Client cannot inject tier | Body `routing_tier/degraded/degraded_notice` set → admitted `standard` with no degraded notice; journal `routing_tier` from admission only (DJ-10 §8.3.8, DJ-20 §1.3.6). |
| SYS-5.4 | JTI replay | Same AAT twice with **different** idempotency keys → second → 401 `unauthenticated`; no new journal row (DJ-18 §5.3.4, DJ-15 §11.3.5). |
| SYS-5.5 | Idempotent replay of completed | Same key, **new** AAT → SSE `accepted` → `completed` placeholder `"Prior request completed."`; counts of `ai_request`/`ai_attempt`/`usage_event` unchanged; envelope not rewritten (DJ-12 §19.3.8, DJ-13 §10.3.6). |
| SYS-5.6 | Replay of failed and cancelled | Failed terminal replay → SSE `failed` (not the completed placeholder); cancelled terminal replay → SSE `cancelled` (DJ-12 §19.3.12–13, DJ-13 §10.3.7–8). |
| SYS-5.7 | Token & cost ceilings | `token_budget=1` → 429; `cost_budget=0` → 429; each distinguishable from `rate_limited` by absence of `retry_after` (DJ-18 §5.3.7). |
| SYS-5.8 | Period rollover | Move entitlement period to a new month via D1; next admit → new `usage_event.period=YYYY-MM(new)`; request counter effectively reset for the new period (admitted despite prior exhaustion) (DJ-18 §5.3.8). |

---

### Suite 6 — `failure-taxonomy-matrix.system.test.ts`
**Doc 19's full taxonomy as a table-driven cross-stage contract test.**

Table rows (each asserts: HTTP status, `code`, `retry_safe`, body shape
(`request_reference` Crockford format, `trace_id` echo), presence/absence of
`retry_after`, SSE vs non-SSE, and **journal unchanged for pre-SSE codes**):

| ID | Trigger | Expected |
|---|---|---|
| SYS-6.1 | Missing/garbage/expired/`aud`-mismatch/`ver`-unknown/lifetime>600s/wrong-alg/missing-org/unknown-kid/unknown-installation/key-revoked/key-expired/key-installation-mismatch AAT | 401 `unauthenticated`, `retry_safe=true` (DJ-11 §14.3.3–4, DJ-19 §1.3.2). |
| SYS-6.2 | Suspended installation | 403 `installation_suspended`, `retry_safe=false`. |
| SYS-6.3 | Pending entitlement / plan / grants / role / scope | 403 `forbidden_capability`, `retry_safe=false`. |
| SYS-6.4 | `Content-Length: 1048577`; oversize stream without header; oversize with missing headers still 413 | 413 `request_too_large`, **empty** `request_reference`/`trace_id` (DJ-10 §8.3.2). |
| SYS-6.5 | Non-JSON / array / null / empty body; missing or blank `x-idempotency-key`, `x-capability-version`; blank `x-trace-id` | 422, `text/plain`, **empty body**, no reference (DJ-10 §8.3.3–4). |
| SYS-6.6 | Missing `capability_id` (or non-string) | 500 `internal_error` **with** Crockford reference; `x-trace-id` echoed exactly (DJ-10 §8.3.5/8.3.7). |
| SYS-6.7 | Oversized `user_intent` passing adapter (stage-7 cost preflight) | 413 `request_too_large` with **non-empty** reference (DJ-11 §14.3.8, DJ-19 §1.3.7). |
| SYS-6.8 | Missing `visit.chief_complaint@v1` | 422 `context_required`, `retry_safe=true`, **no** `missing_keys` on the body. |
| SYS-6.9 | Wrong org / wrong branch / wrong complaint shape / complaint > 4096 bytes | 422 `context_invalid`, `retry_safe=false` (DJ-11 §14.3.7). |
| SYS-6.10 | Unknown `capability_id` (forced past stage 3) / `x-capability-version: 9.9.9` | 404 `capability_unknown` (DJ-11 §14.3.6, DJ-10 §8.3.11). |
| SYS-6.11 | Global overlay `lifecycle_state='retired'` | 404 `capability_retired` (DJ-19 §1.3.12). |
| SYS-6.12 | Kill switch global/capability/installation | 503 `capability_disabled`, `retry_safe=true`. |
| SYS-6.13 | Empty routing chain / all targets excluded | 200 SSE → `failed` `provider_unavailable`, `retry_safe=true`; `state=Failed`; usage written with partial credit (DJ-19 §1.3.14). |
| SYS-6.14 | No active/canary routing policy | 200 SSE → `failed` `internal_error` (DJ-19 §1.3.19). |
| SYS-6.15 | Client abort mid-stream | D1 `state=Cancelled`, `terminal_error_code` NULL, `usage_event` still written (DJ-19 §1.3.17). |
| SYS-6.16 | Rate-limit burst (121 POSTs failing stage 6) | 429 `rate_limited` **with** `retry_after`; not `quota_exhausted`. If the pool's rate-limit bindings do not enforce, the test must `it.skip` with a printed reason rather than fail (DJ-11 §14.3.15, DJ-19 §1.3.5). |

---

### Suite 7 — `settlement-integrity.system.test.ts`
**Stage 11 write-order and exactly-once invariants across all three terminals.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-7.1 | Completed settlement | All `ai_attempt` columns (`attempt_no=1`, `provider='fake'`, `outcome='success'`, latency ≥ 0); `usage_event` exact columns (`quota_weight=1`, `period` from entitle start); R2 envelope `result.usage`/`finishReason='stop'`; `payload_pointer` has no `.json` suffix (DJ-13 §10.3.3–5, DJ-17 §3.3.10). |
| SYS-7.2 | Failed settlement (empty chain) | `state='Failed'`, `terminal_error_code='provider_unavailable'`; ≥1 attempt with `outcome='terminal_failure'`, zeros, `error_code` set; exactly one `usage_event` (tokens/cost 0 allowed); envelope `attempts[0].payload.reason='no_provider_attempt'`; GET → `{state:'Failed', terminal_error_code}` (DJ-13 §10.3.7, DJ-17 §3.3.13). |
| SYS-7.3 | Cancelled settlement | Abort after `accepted`; `state='Cancelled'`, `completed_at` set, `terminal_error_code` NULL; exactly one `usage_event`; one envelope (DJ-13 §10.3.8). |
| SYS-7.4 | Exactly-once under replay | Replay each terminal with its original key; attempt/usage counts unchanged; no second envelope write (DJ-13 §10.3.6–8, DJ-18 §5.3.5). |
| SYS-7.5 | Client cannot read internals | GET response never contains `attempts`/`envelope`/`request_id`/`installation_id`; unauthenticated GET → 401; wrong-installation AAT → 404 empty body; `GET /v1/requests/` → 404 (DJ-13 §10.3.10, DJ-14 §5.3.6). |

---

### Suite 8 — `cron-retention-interplay.system.test.ts`
**Scheduled crons interacting with journal, ledger, R2, and grace queue.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-8.1 | Retention purge | Complete a request; backdate `created_at` −91d; run `0 3 * * *`; `ai_request`/`ai_attempt` gone; `usage_event` survives with `request_id` NULL; R2 envelope deleted; client GET → 404; support lookup → 404 `not_found`; money values unchanged (DJ-14 §5.3.8–9, DJ-17 §3.3.15). |
| SYS-8.2 | Usage rollup | Complete requests; run `0 4 * * *`; `usage_rollup` row has `dimensions={installation_id, period}`, counts/tokens/cost equal to `usage_event` sums; re-run does not duplicate (upsert) (DJ-16 §15.3.10). |
| SYS-8.3 | Grace queue reconciliation | SQL-insert pending grace row (unique `(installation_id, idempotency_key)` enforced — duplicate insert fails); run scheduled tick; row transitions to `reconciled`/`dropped` or stays `pending` with `reconcile_attempts≥1` and `reconcile_first_seen_at_ms` set; healthy path leaves zero grace rows (DJ-15 §11.3.6, DJ-16 §15.3.10). |
| SYS-8.4 | Rejection counters lower bound | Cause guard rejections; run scheduled tick; `platform_counter` gains a row whose `dimension_set` includes the error code with `count ≥ 1` (DJ-15 §11.3.10, DJ-16 §15.3.10). |

---

### Suite 9 — `token-contract-rotation.system.test.ts`
**Stage 1 token contract lifecycle against live identity verification.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-9.1 | Begin-rotation dual-accept | `POST /control/token-contract/begin-rotation` `{ver:"2"}` → 200; two live `token_contract` rows; AAT `ver=1` and AAT `ver=2` both verify (invoke passes identity) (DJ-03 §6.3, DJ-16 §15.3.7). |
| SYS-9.2 | Retire cuts old ver | Retire `ver=2` → row `retired_at` set; `ver=2` AAT → 401 `unauthenticated`; `ver=1` still passes; audits `token_contract_begin_rotation`/`token_contract_retire` (DJ-03, DJ-16 §15.3.7). |
| SYS-9.3 | Auth & validation | No bearer → 401 `unauthorized`; staff AAT → 401 `unauthorized` (DJ-03 §6.3). |

---

### Suite 10 — `capability-lifecycle.system.test.ts`
**Stage 4 cohort/deprecate/retire overlays against discovery and invoke.**

| ID | Scenario | Key assertions |
|---|---|---|
| SYS-10.1 | Cohort activate & promote | `activate` validation: 401 no-auth, 400 `missing_installation_ids`, 404 `installation_not_found`, 404 `capability_not_found` on `9.9.9`; named-cohort activate → 200 + audit `target=clinic.visit_summary@1.0.0:<cohort>` with `before_pointer` map; `promote` → 200 + audit `after_pointer` (DJ-06 §11.3.12–13). |
| SYS-10.2 | Deprecate lifecycle | 400 `missing_successor_id`; 400 `unknown_successor`; 404 `capability_not_found`; success → global overlay `lifecycle_state='deprecated'`, `retire_after ≈ +90d`; repeat same successor idempotent 200; different successor → 409 `already_deprecated`; **invoke still works** while deprecated-in-window (DJ-06 §11.3.14). |
| SYS-10.3 | Retire lifecycle | Retire without deprecate → 400 `not_deprecated`; immediately after deprecate → 400 `overlap_window_active`; backdate `retire_after` then retire → 200, overlay `retired`; invoke → 404 `capability_retired`; discovery no longer lists; deprecate after retire → 409 `already_retired` (DJ-06 §11.3.15, DJ-19 §1.3.12). |

---

## 5. Non-goals & explicit unprobeable register

Carried over from the docs; the suites must **not** attempt these (assert the
reachable complement instead, and note the gap in a comment):

- `concurrency_exhausted` (16 in-flight), grace admission with DO down,
  abandoned-admission 2h sweep, idempotency TTL expiry.
- `validation_failed` via prose guards, `provider_rejected` via real provider
  credentials, live `heartbeat`/`regenerating`, 16 KiB raw-body truncation.
- `period_reset` on live `quota_exhausted` JSON (docs note it is computed but
  never forwarded — assert its **absence**).
- Config-cache 30s TTL real-time behavior (covered by
  `test/config-cache.test.ts` unit suite).
- Any clinic Supabase interaction.

## 6. Implementation waves

1. **Wave 1 (foundation)**: one agent builds `test/system/harness.ts`,
   registers the suite in both vitest configs, and implements **Suite 1** as
   the exemplar. Must run green:
   `npx vitest run --config vitest.workers.config.ts test/system/`.
2. **Wave 2 (parallel suites)**: four agents, each implementing suites
   against the landed harness:
   - Agent A: Suites 2 + 9
   - Agent B: Suites 3 + 10
   - Agent C: Suites 4 + 5
   - Agent D: Suites 6 + 7 + 8

Each implementer must: reuse harness helpers (extend them in `harness.ts`
only when a capability is genuinely missing), keep one `it` per SYS-ID with
the SYS-ID in the test title, and run the workers suite to green before
finishing. Any deviation from this plan discovered during implementation
(e.g. a documented behavior that the code does not actually implement) must
be reported back verbatim, not silently worked around.
