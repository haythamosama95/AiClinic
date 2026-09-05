# Stage 05 — Routing policy (publish, canary, promote, rollback, kill switch)

Source files read: `ai-platform/src/control/routing-policy.ts`, `ai-platform/src/router/index.ts`, `ai-platform/src/control/auth.ts`, `ai-platform/src/control/http.ts`, `ai-platform/src/control/audit.ts`, `ai-platform/src/control/types.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/config-cache/index.ts`, `ai-platform/src/worker.ts` (invoke-path routing consumption, L685–L771, L920–L1023), `ai-platform/src/capability/index.ts` (kill-switch collection, L355–L437), `ai-platform/src/pipeline/index.ts` (guard stage 5 hand-off, L384–L390, L546–L556), `ai-platform/control/routing-policy/platform-default/1.json`, `ai-platform/migrations/20260731120000_platform_schema.sql` (routing_policy, control_audit), `ai-platform/migrations/20260803100000_routing_policy_canary.sql`, `ai-platform/migrations/20260805190000_routing_policy_status.sql`, `ai-platform/migrations/20260807120000_kill_switch.sql`, `ai-platform/scripts/bootstrap-routing-policy.sh`, `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`, `docs/architecture/ai-platform/data-journey/07-stage-5-routing-policy.md` (orientation only).

## Conventions and shared concrete values

- Operator auth: `Authorization: Bearer op_secret_9f27c1a84b3d4e5f8a0b6c7d8e9f0a1b` maps to operator id `platform-operator` (`createSecretOperatorAuth`). Wrong/absent credentials → 401 `{"error":"unauthorized"}`.
- Control base URL: `http://127.0.0.1:8787` (local `npm run dev`). All control routes are POST unless noted.
- Reference policy document: `ai-platform/control/routing-policy/platform-default/1.json` — `policy_id: "standard"`, `policy_version: 1`, single catch-all rule `platform-default-fallback` with targets `deepseek/deepseek-v4-flash` then `gemini/gemini-3.5-flash` (both: structured_output true, min_context_window 128000, languages `["en"]`, latency_class `"standard"`, cost_class `"standard"`, max_attempts 2, timeout_ms 30000), `overrides: []`.
- The only published capability manifest is `clinic.visit_summary@1.0.0` with `Routing.routingPolicyRef = "routing/standard"` and `Routing.latencyClass = "standard"` — this drives the publish-warning matrix (`latencyMismatchWarnings` matches manifests by policy id only).
- Installations used below: `018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f` ("inst-A", canary cohort member) and `018e4f2a-9d4c-7a2b-8e3f-6d7b9c1e2f3a` ("inst-B", non-canary). Both are honestly built via the installation-lifecycle chapter's enroll happy path plus the entitlement chapter's entitle happy path (grant for `clinic.visit_summary@1.0.0`).
- Invoke journeys use `POST /v1/requests` per Stage 10 (request ingress) accepted-request behavior: headers `Authorization: Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6ImtleS0yMDI2LTA4In0.eyJvcmdfaWQiOiJvcmctN2YzYSIsInNjb3BlIjoiYWkudmlzaXRfc3VtbWFyeSJ9.c2lnbmF0dXJl` (AAT minted per Stage 6 — AAT minting behavior), `Content-Type: application/json`, `x-idempotency-key: idem-s05-<suffix>`, `x-capability-version: 1.0.0`; body `{"capability_id":"clinic.visit_summary","user_intent":"Summarize today's visit for the chart.","context":{"org":"org-7f3a","branch":"branch-01","visit.chief_complaint@v1":"Patient reports headache for 3 days."}}`. Expected accept: HTTP 202 with a Crockford `request_reference`; post-accept outcomes are observed on the request's SSE stream and in D1 (`ai_request.state`, `ai_request.routing_decision`, `ai_attempt`).
- Invoke-path hardwiring (from `worker.ts` L754–L755, code is truth): `manifestCostClass` is always `"standard"`, `entitlementMaxCostClass` is always `"premium"`; therefore the effective cost class on any un-overridden invoke is `standard` with `cost_class_source: "manifest"`.
- Routing errors thrown post-accept (`ConfigCacheMissError`, any `RoutingPolicyError`) are caught by the `runFreshEventSource` `.catch` (`worker.ts` L685–L697) and surface only as an SSE `failed` terminal event with code `internal_error`; router error codes never appear on the wire.

## Scenario S05-001 — Publish platform-default policy (happy path)

| Field | Content |
|-------|---------|
| ID | S05-001 |
| Journey setup | D1 migrations applied; `routing_policy` table empty; R2 bucket empty; Worker running with `OPERATOR_BEARER_TOKEN=op_secret_9f27c1a84b3d4e5f8a0b6c7d8e9f0a1b`, `OPERATOR_ID=platform-operator`. |
| Action | `POST /control/routing-policies/publish` with operator bearer, `Content-Type: application/json`, body `{"document": <verbatim contents of ai-platform/control/routing-policy/platform-default/1.json>}` |
| Expected outcome | HTTP 200, body `{}` (policy id `standard` is referenced by the visit-summary manifest and target latency classes include `"standard"`, so no warnings). |
| Side effects | R2 object `control/routing-policy/standard/1.json` written with contentType `application/json`, body byte-identical to `JSON.stringify(document)`. D1 `routing_policy` row: `policy_id='standard'`, `version='1'`, `content_pointer='control/routing-policy/standard/1.json'`, `active_from=<now ISO>`, `activated_by='platform-operator'`, `canary_installation_ids=NULL`, `status='published'`. D1 `control_audit` row: `action='routing_policy_publish'`, `operator_id='platform-operator'`, `target='standard@1'`, `before_pointer=NULL`, `after_pointer='control/routing-policy/standard/1.json'`. No other tables touched. |
| Code reference | ai-platform/src/control/routing-policy.ts:L152-L241 — handleRoutingPolicyPublish |

## Scenario S05-002 — Publish policy id no capability references → unreferenced_policy warning

| Field | Content |
|-------|---------|
| ID | S05-002 |
| Journey setup | Same as S05-001 (empty tables). |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_id":"premium-eu","policy_version":1,"defaults":{"cost_class":"premium","max_parallel_attempts":1},"rules":[{"rule_id":"catch-all","match":{},"requires":{"structured_output":false,"min_context_window":0,"languages":[]},"targets":[{"provider_id":"gemini","model_id":"gemini-3.5-pro","features":{"structured_output":true,"min_context_window":200000,"languages":["en"],"latency_class":"standard","cost_class":"premium"},"max_attempts":2,"timeout_ms":30000}]}],"overrides":[]}}` |
| Expected outcome | HTTP 200, body `{"warnings":["unreferenced_policy"]}` — no published manifest's `routingPolicyRef` parses to policy id `premium-eu`. |
| Side effects | Same writes as S05-001 but for `premium-eu@1`: R2 key `control/routing-policy/premium-eu/1.json`; D1 row `status='published'`; audit `target='premium-eu@1'`. Warning does not block the write. |
| Code reference | ai-platform/src/control/routing-policy.ts:L89-L111 — latencyMismatchWarnings; L34-L46 — parseRoutingPolicyRef |

## Scenario S05-003 — Publish referenced policy whose targets miss the manifest latency class → latency_class_mismatch

| Field | Content |
|-------|---------|
| ID | S05-003 |
| Journey setup | Same as S05-001 (empty tables). |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_id":"standard","policy_version":7,"defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[{"rule_id":"catch-all","match":{},"requires":{"structured_output":false,"min_context_window":0,"languages":[]},"targets":[{"provider_id":"deepseek","model_id":"deepseek-v4-flash","features":{"structured_output":true,"min_context_window":128000,"languages":["en"],"latency_class":"batch","cost_class":"economy"},"max_attempts":2,"timeout_ms":30000}]}],"overrides":[]}}` |
| Expected outcome | HTTP 200, body `{"warnings":["latency_class_mismatch"]}` — manifest `clinic.visit_summary@1.0.0` references `routing/standard` with `latencyClass "standard"`, but no target in the document declares `latency_class: "standard"`. |
| Side effects | R2 key `control/routing-policy/standard/7.json` written; D1 row `standard@7` `status='published'`; audit `target='standard@7'`. |
| Code reference | ai-platform/src/control/routing-policy.ts:L48-L82 — collectTargetLatencyClasses; L89-L111 — latencyMismatchWarnings |

## Scenario S05-004 — Duplicate publish → 409 already_published, R2 bytes untouched

| Field | Content |
|-------|---------|
| ID | S05-004 |
| Journey setup | S05-001 completed (`standard@1` published). |
| Action | `POST /control/routing-policies/publish` with operator bearer; body carries a *modified* document with the same identity: `{"document": {"schema_version":1,"policy_id":"standard","policy_version":1,"defaults":{"cost_class":"economy","max_parallel_attempts":1},"rules":[{"rule_id":"catch-all","match":{},"requires":{"structured_output":false,"min_context_window":0,"languages":[]},"targets":[{"provider_id":"gemini","model_id":"gemini-3.5-flash","features":{"structured_output":true,"min_context_window":128000,"languages":["en"],"latency_class":"standard","cost_class":"economy"},"max_attempts":1,"timeout_ms":15000}]}],"overrides":[]}}` |
| Expected outcome | HTTP 409, body `{"error":"already_published"}`. The D1 `SELECT` on `(policy_id, version)` runs before `R2.put`, so the published object is never overwritten. |
| Side effects | R2 object `control/routing-policy/standard/1.json` MUST remain byte-identical to the S05-001 write. No new `routing_policy` row. No `control_audit` row. |
| Code reference | ai-platform/src/control/routing-policy.ts:L199-L210 — pre-R2 duplicate check |

## Scenario S05-005 — Publish with unparseable JSON body → 400 invalid_json

| Field | Content |
|-------|---------|
| ID | S05-005 |
| Journey setup | Same as S05-001 (empty tables). |
| Action | `POST /control/routing-policies/publish` with operator bearer, `Content-Type: application/json`, raw body `{"document": {"policy_id": "standard",` (truncated JSON). |
| Expected outcome | HTTP 400, body `{"error":"invalid_json"}`. |
| Side effects | None — no R2 write, no D1 row, no audit row. |
| Code reference | ai-platform/src/control/http.ts:L42-L48 — parseJsonBody |

## Scenario S05-006 — Publish without the document key → 400 missing_document

| Field | Content |
|-------|---------|
| ID | S05-006 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"policy_id":"standard","policy_version":1}` (identity at top level, no `document`). |
| Expected outcome | HTTP 400, body `{"error":"missing_document"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L175-L178 — missing_document check |

## Scenario S05-007 — Publish with document:null → 400 missing_document

| Field | Content |
|-------|---------|
| ID | S05-007 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": null}`. |
| Expected outcome | HTTP 400, body `{"error":"missing_document"}` (`!body.document` catches `null`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L175-L178 — missing_document check |

## Scenario S05-008 — Publish with a string document → 400 missing_document

| Field | Content |
|-------|---------|
| ID | S05-008 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": "standard@1"}`. |
| Expected outcome | HTTP 400, body `{"error":"missing_document"}` (`typeof "standard@1" !== "object"`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L175-L178 — missing_document check |

## Scenario S05-009 — Publish with an array document → 400 invalid_policy_identity

| Field | Content |
|-------|---------|
| ID | S05-009 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": []}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_policy_identity"}` — arrays pass the `typeof === "object"` missing_document gate, then fail identity because `policy_id` is `undefined`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L180-L191 — invalid_policy_identity check |

## Scenario S05-010 — Publish with missing policy_id → 400 invalid_policy_identity

| Field | Content |
|-------|---------|
| ID | S05-010 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_version":1,"defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[],"overrides":[]}}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_policy_identity"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L180-L191 — invalid_policy_identity check |

## Scenario S05-011 — Publish with empty-string policy_id → 400 invalid_policy_identity

| Field | Content |
|-------|---------|
| ID | S05-011 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_id":"","policy_version":1,"defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[],"overrides":[]}}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_policy_identity"}` (`policyId.length === 0`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L180-L191 — invalid_policy_identity check |

## Scenario S05-012 — Publish with numeric policy_id → 400 invalid_policy_identity

| Field | Content |
|-------|---------|
| ID | S05-012 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_id":42,"policy_version":1,"defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[],"overrides":[]}}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_policy_identity"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L180-L191 — invalid_policy_identity check |

## Scenario S05-013 — Publish with string policy_version "1" → 400 invalid_policy_identity

| Field | Content |
|-------|---------|
| ID | S05-013 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_id":"standard","policy_version":"1","defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[],"overrides":[]}}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_policy_identity"}` — version must be a JSON **number**; the string `"1"` is rejected even though D1 stores versions as TEXT. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L180-L191 — invalid_policy_identity check |

## Scenario S05-014 — Publish with fractional policy_version 1.5 → 400 invalid_policy_identity

| Field | Content |
|-------|---------|
| ID | S05-014 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_id":"standard","policy_version":1.5,"defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[],"overrides":[]}}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_policy_identity"}` (`Number.isInteger` fails). |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L180-L191 — invalid_policy_identity check |

## Scenario S05-015 — Publish with policy_version 0 or negative → 400 invalid_policy_identity

| Field | Content |
|-------|---------|
| ID | S05-015 |
| Journey setup | Same as S05-001. Run twice (boundary pair). |
| Action | `POST /control/routing-policies/publish` with operator bearer; body A `{"document": {"schema_version":1,"policy_id":"standard","policy_version":0,"defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[],"overrides":[]}}`; body B identical with `"policy_version":-3`. |
| Expected outcome | Both: HTTP 400, body `{"error":"invalid_policy_identity"}` (`policyVersion < 1`). Boundary: `1` is the smallest accepted version (proven by S05-001). |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L180-L191 — invalid_policy_identity check |

## Scenario S05-016 — Publish without an R2 binding → 500 missing_r2_binding

| Field | Content |
|-------|---------|
| ID | S05-016 |
| Journey setup | Same as S05-001, but the handler is invoked with `ControlBindings` lacking `R2` (direct handler invocation seam — see Non-automatable notes; production wrangler always binds R2). |
| Action | Call `handleRoutingPolicyPublish(request, { DB }, operatorAuth)` with a well-formed publish request for `standard@1`. |
| Expected outcome | HTTP 500, body `{"error":"missing_r2_binding"}`. Checked before body parsing, so even a malformed body would yield this error — but the journey uses a valid body to isolate the branch. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L167-L169 — missing_r2_binding check |

## Scenario S05-017 — Publish without Authorization header → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-017 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with **no** `Authorization` header; well-formed body from S05-001. |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}`. Auth runs before route parsing, R2 checks, and body parsing. |
| Side effects | None. |
| Code reference | ai-platform/src/control/http.ts:L31-L40 — requireOperator; ai-platform/src/control/auth.ts:L26-L51 — createSecretOperatorAuth |

## Scenario S05-018 — Publish with wrong bearer token → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-018 |
| Journey setup | Same as S05-001. |
| Action | `POST /control/routing-policies/publish` with `Authorization: Bearer op_secret_00000000000000000000000000000000ff` (well-formed but wrong token); body from S05-001. |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}` (constant-time compare fails). |
| Side effects | None. |
| Code reference | ai-platform/src/control/auth.ts:L44-L47 — timingSafeEqualString gate |

## Scenario S05-019 — Publish with non-Bearer scheme and empty bearer → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-019 |
| Journey setup | Same as S05-001. Pairwise auth-shape probe, two requests. |
| Action | (a) `POST /control/routing-policies/publish` with `Authorization: Basic Zm9vOmJhcg==`; (b) same with `Authorization: Bearer ` (scheme prefix, empty token). Body from S05-001 both times. |
| Expected outcome | Both: HTTP 401, body `{"error":"unauthorized"}` — (a) fails the `startsWith("Bearer ")` check, (b) fails the empty-token check. |
| Side effects | None. |
| Code reference | ai-platform/src/control/auth.ts:L37-L43 — scheme and empty-token gates |

## Scenario S05-020 — Concurrent first publish of the same version → exactly one 200, one 409

| Field | Content |
|-------|---------|
| ID | S05-020 |
| Journey setup | Same as S05-001 (empty tables). |
| Action | Two simultaneous `POST /control/routing-policies/publish` requests with operator bearer, both carrying the S05-001 document (`standard@1`). |
| Expected outcome | Exactly one request returns HTTP 200 `{}`; the other returns HTTP 409 `{"error":"already_published"}` — either via the pre-R2 SELECT or via the `DB.batch` UNIQUE-constraint mapping (`isUniqueConstraint`). |
| Side effects | Exactly one `routing_policy` row `standard@1`, exactly one `control_audit` row with `action='routing_policy_publish'`, exactly one R2 object. See Non-automatable notes for the determinism seam. |
| Code reference | ai-platform/src/control/routing-policy.ts:L84-L87 — isUniqueConstraint; L232-L238 — batch error mapping |

## Scenario S05-021 — Publish with unknown extra keys → stored verbatim, ignored at routing

| Field | Content |
|-------|---------|
| ID | S05-021 |
| Journey setup | Same as S05-001 (empty tables). |
| Action | `POST /control/routing-policies/publish` with operator bearer; body is the S05-001 document plus `"future_field": {"experimental": true}` at the top level and `"note": "ops-only"` inside the rule. |
| Expected outcome | HTTP 200, body `{}`. Extra keys are not validated. |
| Side effects | R2 object `control/routing-policy/standard/1.json` contains the extra keys verbatim (`JSON.stringify(document)` of the submitted document). D1 row + audit row as in S05-001. When this version is later promoted and served (S05-051 journey shape), routing output is identical to the unmodified document — the router reads only known fields. |
| Code reference | ai-platform/src/control/routing-policy.ts:L207-L209 — R2.put of raw document; ai-platform/src/router/index.ts:L150-L168 — RoutingPolicyDocument known fields |

## Scenario S05-022 — Publish a shape-malformed document succeeds (no catch-all/target validation at publish)

| Field | Content |
|-------|---------|
| ID | S05-022 |
| Journey setup | Same as S05-001 (empty tables). |
| Action | `POST /control/routing-policies/publish` with operator bearer; body `{"document": {"schema_version":1,"policy_id":"standard","policy_version":9,"defaults":{"cost_class":"standard","max_parallel_attempts":1},"rules":[{"rule_id":"narrow","match":{"capability_ids":["clinic.nonexistent"]},"requires":{"structured_output":false,"min_context_window":0,"languages":[]},"targets":[{"provider_id":"deepseek","model_id":"deepseek-v4-flash","features":{"structured_output":"yes","min_context_window":"big","languages":"en","latency_class":"standard","cost_class":"cheap"},"max_attempts":2,"timeout_ms":30000}]}],"overrides":[]}}` — no catch-all rule, wrong-typed feature fields. |
| Expected outcome | HTTP 200, body `{}` (target latency_class `"standard"` is present, so no warning). Publish validates identity only; malformed rules/targets are accepted and stored. This scenario is the seed for the fail-closed invoke journeys S05-057, S05-061–S05-068. |
| Side effects | R2 key `control/routing-policy/standard/9.json` written verbatim; D1 row `standard@9` `status='published'`; audit `target='standard@9'`. |
| Code reference | ai-platform/src/control/routing-policy.ts:L175-L241 — publish validates identity only; ai-platform/src/router/index.ts:L242-L270 — validatePolicyDocument runs at serve time, not publish time |

## Scenario S05-023 — Canary happy path from published

| Field | Content |
|-------|---------|
| ID | S05-023 |
| Journey setup | S05-001 completed (`standard@1` published); inst-A `018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f` enrolled per the installation-lifecycle chapter's enroll happy path. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"],"cohort_name":"early-adopters"}`. |
| Expected outcome | HTTP 200, body `{}`. When `cohort_name` is present it is persisted in the audit row `after_pointer` JSON under `details.cohort_name` (the `installation_ids` array is also stored in the same object). |
| Side effects | D1 `routing_policy` row `standard@1`: `status='canary'`, `canary_installation_ids='["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"]'`. `control_audit` row: `action='routing_policy_canary'`, `target='standard@1'`, `before_pointer=NULL` (no prior canary row), `after_pointer='{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"],"details":{"cohort_name":"early-adopters"}}'`. No R2 write. |
| Code reference | ai-platform/src/control/routing-policy.ts:L243-L326 — handleRoutingPolicyCanary |

## Scenario S05-024 — Re-canary replaces the cohort list (before_pointer = prior list)

| Field | Content |
|-------|---------|
| ID | S05-024 |
| Journey setup | S05-023 completed (`standard@1` canary with inst-A); inst-B `018e4f2a-9d4c-7a2b-8e3f-6d7b9c1e2f3a` enrolled. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f","018e4f2a-9d4c-7a2b-8e3f-6d7b9c1e2f3a"]}`. |
| Expected outcome | HTTP 200, body `{}` — `status='canary'` is a legal source state for canary. |
| Side effects | Row `standard@1`: `canary_installation_ids` replaced with the two-id JSON array. Audit row: `before_pointer='["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"]'` (latest canary row's list), `after_pointer` = new two-id JSON. |
| Code reference | ai-platform/src/control/routing-policy.ts:L282-L284 — published\|canary source gate; L294-L304 — priorCanary lookup |

## Scenario S05-025 — Canary a second version while the first is still canary (two live canary rows)

| Field | Content |
|-------|---------|
| ID | S05-025 |
| Journey setup | S05-001 + S05-023 completed (`standard@1` canary for inst-A); `standard@2` published (repeat S05-001 with the fixture edited to `"policy_version": 2`); inst-B enrolled. |
| Action | `POST /control/routing-policies/standard/versions/2/canary` with operator bearer; body `{"installation_ids":["018e4f2a-9d4c-7a2b-8e3f-6d7b9c1e2f3a"]}`. |
| Expected outcome | HTTP 200, body `{}`. The canary handler updates only the addressed row — `standard@1` stays `canary` with its own list. Two canary rows now coexist for policy `standard`. |
| Side effects | Row `standard@2`: `status='canary'`, list `[inst-B]`. Row `standard@1` unchanged. Audit row `target='standard@2'`, `before_pointer='["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"]'` (the prior canary row's list — note the audit before-pointer names v1's cohort on a v2 action). Serving consequence covered in S05-051: the config-cache reader scans canary rows `ORDER BY active_from DESC, rowid DESC` and serves the first row whose list contains the installation. |
| Code reference | ai-platform/src/control/routing-policy.ts:L306-L324 — single-row UPDATE; ai-platform/src/config-cache/index.ts:L349-L364 — canary row scan |

## Scenario S05-026 — Canary an unknown policy version → 404 policy_version_not_found

| Field | Content |
|-------|---------|
| ID | S05-026 |
| Journey setup | S05-001 completed; inst-A enrolled. |
| Action | `POST /control/routing-policies/standard/versions/99/canary` with operator bearer; body `{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"]}`. |
| Expected outcome | HTTP 404, body `{"error":"policy_version_not_found"}`. |
| Side effects | None — no UPDATE, no audit row. |
| Code reference | ai-platform/src/control/routing-policy.ts:L270-L280 — existence check |

## Scenario S05-027 — Canary an active version → 409 illegal_policy_transition

| Field | Content |
|-------|---------|
| ID | S05-027 |
| Journey setup | S05-001 completed, then `standard@1` promoted (S05-035); inst-A enrolled. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"]}`. |
| Expected outcome | HTTP 409, body `{"error":"illegal_policy_transition"}` — source status `active` is neither `published` nor `canary`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L282-L284 — transition gate |

## Scenario S05-028 — Canary a superseded version → 409 illegal_policy_transition

| Field | Content |
|-------|---------|
| ID | S05-028 |
| Journey setup | `standard@1` and `standard@2` published; both promoted in order so `standard@1` is `superseded` and `standard@2` is `active` (S05-035 then S05-036); inst-A enrolled. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"]}`. |
| Expected outcome | HTTP 409, body `{"error":"illegal_policy_transition"}` — source status `superseded`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L282-L284 — transition gate |

## Scenario S05-029 — Canary with unparseable JSON body → 400 invalid_json

| Field | Content |
|-------|---------|
| ID | S05-029 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; raw body `{"installation_ids": [`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_json"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/http.ts:L42-L48 — parseJsonBody |

## Scenario S05-030 — Canary without installation_ids → 400 missing_installation_ids

| Field | Content |
|-------|---------|
| ID | S05-030 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"cohort_name":"early-adopters"}`. |
| Expected outcome | HTTP 400, body `{"error":"missing_installation_ids"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L263-L265 — installation_ids presence gate |

## Scenario S05-031 — Canary with empty installation_ids array → 400 missing_installation_ids

| Field | Content |
|-------|---------|
| ID | S05-031 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"installation_ids":[]}`. |
| Expected outcome | HTTP 400, body `{"error":"missing_installation_ids"}` (`length === 0`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L263-L265 — installation_ids presence gate |

## Scenario S05-032 — Canary with non-array installation_ids → 400 missing_installation_ids

| Field | Content |
|-------|---------|
| ID | S05-032 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"installation_ids":"018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"}`. |
| Expected outcome | HTTP 400, body `{"error":"missing_installation_ids"}` (`Array.isArray` fails). |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L263-L265 — installation_ids presence gate |

## Scenario S05-033 — Canary with an unknown installation id → 404 installation_not_found, no writes

| Field | Content |
|-------|---------|
| ID | S05-033 |
| Journey setup | S05-001 completed; inst-A enrolled. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with operator bearer; body `{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f","9e9e9e9e-0000-4000-8000-000000000000"]}` (second id never enrolled). Pairwise variant: a non-string entry (`42`) in the list fails identically because no `installation` row matches it. |
| Expected outcome | HTTP 404, body `{"error":"installation_not_found"}` — every listed id is checked against the `installation` table before any write. |
| Side effects | None — row `standard@1` keeps `status='published'`, `canary_installation_ids=NULL`; no audit row. |
| Code reference | ai-platform/src/control/routing-policy.ts:L114-L130 — assertInstallationsExist; L286-L292 — call site |

## Scenario S05-034 — Canary without operator auth → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-034 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with no `Authorization` header; body `{"installation_ids":["018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f"]}`. |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}` — auth precedes route parsing and body parsing in every routing-policy handler. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L248-L251 — requireOperator first |

## Scenario S05-035 — Promote the first version to active (before_pointer NULL)

| Field | Content |
|-------|---------|
| ID | S05-035 |
| Journey setup | S05-001 completed (`standard@1` published; no active version). |
| Action | `POST /control/routing-policies/standard/versions/1/promote` with operator bearer; no body. |
| Expected outcome | HTTP 200, body `{}`. |
| Side effects | Row `standard@1`: `status='active'`, `canary_installation_ids=NULL`. `control_audit` row: `action='routing_policy_promote'`, `target='standard@1'`, `before_pointer=NULL` (no prior active), `after_pointer='standard@1'`. No R2 write. This is the state the bootstrap script reaches for greenfield bring-up. |
| Code reference | ai-platform/src/control/routing-policy.ts:L328-L401 — handleRoutingPolicyPromote; ai-platform/scripts/bootstrap-routing-policy.sh — publish+promote bring-up |

## Scenario S05-036 — Promote v2 over active v1 (supersede; audit before_pointer)

| Field | Content |
|-------|---------|
| ID | S05-036 |
| Journey setup | S05-035 completed (`standard@1` active); `standard@2` published (fixture with `"policy_version": 2`). |
| Action | `POST /control/routing-policies/standard/versions/2/promote` with operator bearer; no body. |
| Expected outcome | HTTP 200, body `{}`. |
| Side effects | Row `standard@1`: `status='superseded'`, `canary_installation_ids=NULL`. Row `standard@2`: `status='active'`. Audit row: `target='standard@2'`, `before_pointer='standard@1'` (latest active by `active_from DESC, rowid DESC` — not lexical version order), `after_pointer='standard@2'`. |
| Code reference | ai-platform/src/control/routing-policy.ts:L358-L368 — priorActive lookup; L371-L386 — supersede + activate batch |

## Scenario S05-037 — Promote a canary version clears its cohort and supersedes other canary rows

| Field | Content |
|-------|---------|
| ID | S05-037 |
| Journey setup | S05-025 completed: `standard@1` canary (inst-A), `standard@2` canary (inst-B); no active version. |
| Action | `POST /control/routing-policies/standard/versions/2/promote` with operator bearer; no body. |
| Expected outcome | HTTP 200, body `{}`. |
| Side effects | Row `standard@2`: `status='active'`, `canary_installation_ids=NULL`. Row `standard@1`: `status='superseded'`, `canary_installation_ids=NULL` (the batch supersedes *all* other canary rows of the policy). Audit row: `target='standard@2'`, `before_pointer=NULL` (no prior active), `after_pointer='standard@2'`. After the config-cache TTL, inst-A and inst-B both serve v2 (S05-051 resolution rules). |
| Code reference | ai-platform/src/control/routing-policy.ts:L376-L386 — supersede-canary + activate statements |

## Scenario S05-038 — Promote an unknown policy version → 404 policy_version_not_found

| Field | Content |
|-------|---------|
| ID | S05-038 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/42/promote` with operator bearer; no body. |
| Expected outcome | HTTP 404, body `{"error":"policy_version_not_found"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L347-L356 — existence check |

## Scenario S05-039 — Promote an already-active version → 409 illegal_policy_transition

| Field | Content |
|-------|---------|
| ID | S05-039 |
| Journey setup | S05-035 completed (`standard@1` active). |
| Action | `POST /control/routing-policies/standard/versions/1/promote` with operator bearer; no body. |
| Expected outcome | HTTP 409, body `{"error":"illegal_policy_transition"}` — promote rejects an already-active version. |
| Side effects | None — row `standard@1` stays `active`; no audit row (reject happens before the batch). |
| Code reference | ai-platform/src/control/routing-policy.ts — status gate before batch |

## Scenario S05-040 — Promote a superseded version → 409 illegal_policy_transition

| Field | Content |
|-------|---------|
| ID | S05-040 |
| Journey setup | S05-036 completed (`standard@1` superseded, `standard@2` active). |
| Action | `POST /control/routing-policies/standard/versions/1/promote` with operator bearer; no body. |
| Expected outcome | HTTP 409, body `{"error":"illegal_policy_transition"}` — superseded versions cannot be re-activated via promote. |
| Side effects | None — rows unchanged (`standard@1` stays `superseded`, `standard@2` stays `active`); no audit row. |
| Code reference | ai-platform/src/control/routing-policy.ts — status gate before batch |

## Scenario S05-041 — Promote without operator auth → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-041 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/1/promote` with `Authorization: Bearer op_secret_00000000000000000000000000000000ff`; no body. |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L333-L336 — requireOperator first |

## Scenario S05-042 — Rollback a canary version → back to published, active untouched

| Field | Content |
|-------|---------|
| ID | S05-042 |
| Journey setup | `standard@1` active (S05-035); `standard@2` published then canaried for inst-A (S05-023 shape on v2). |
| Action | `POST /control/routing-policies/standard/versions/2/rollback` with operator bearer; no body. |
| Expected outcome | HTTP 200, body `{}`. |
| Side effects | Row `standard@2`: `status='published'`, `canary_installation_ids=NULL`. Row `standard@1` stays `active`. Audit row: `action='routing_policy_rollback'`, `target='standard@2'`, `before_pointer='standard@2'`, `after_pointer='standard@1'` (the currently active version). The trailing clear-split UPDATE finds no remaining canary rows. |
| Code reference | ai-platform/src/control/routing-policy.ts:L437-L456 — canary rollback branch; L502-L510 — clear-split statement |

## Scenario S05-043 — Rollback a canary version with no active version → after_pointer NULL

| Field | Content |
|-------|---------|
| ID | S05-043 |
| Journey setup | S05-023 completed (`standard@1` canary; nothing ever promoted). |
| Action | `POST /control/routing-policies/standard/versions/1/rollback` with operator bearer; no body. |
| Expected outcome | HTTP 200, body `{}`. |
| Side effects | Row `standard@1`: `status='published'`, `canary_installation_ids=NULL`. Audit row: `before_pointer='standard@1'`, `after_pointer=NULL` (no active row exists). |
| Code reference | ai-platform/src/control/routing-policy.ts:L438-L456 — canary branch with absent active |

## Scenario S05-044 — Rollback an active version with a superseded prior → version swap

| Field | Content |
|-------|---------|
| ID | S05-044 |
| Journey setup | S05-036 completed (`standard@1` superseded, `standard@2` active). |
| Action | `POST /control/routing-policies/standard/versions/2/rollback` with operator bearer; no body. |
| Expected outcome | HTTP 200, body `{}`. |
| Side effects | Row `standard@2`: `status='superseded'`. Row `standard@1`: `status='active'` (latest superseded by `active_from DESC, rowid DESC`). Audit row: `target='standard@2'`, `before_pointer='standard@2'`, `after_pointer='standard@1'`. Serving flips to v1 after the config-cache TTL (S05-059). |
| Code reference | ai-platform/src/control/routing-policy.ts:L457-L484 — active rollback branch |

## Scenario S05-045 — Rollback an active version with no superseded prior → 409 illegal_policy_transition

| Field | Content |
|-------|---------|
| ID | S05-045 |
| Journey setup | S05-035 completed (`standard@1` active; it is the only version). |
| Action | `POST /control/routing-policies/standard/versions/1/rollback` with operator bearer; no body. |
| Expected outcome | HTTP 409, body `{"error":"illegal_policy_transition"}` — there is no superseded row to resurrect. |
| Side effects | None — row `standard@1` stays `active`; no audit row (the reject happens before the batch). |
| Code reference | ai-platform/src/control/routing-policy.ts:L458-L468 — prior-superseded lookup and reject |

## Scenario S05-046 — Rollback a published version → 409 illegal_policy_transition

| Field | Content |
|-------|---------|
| ID | S05-046 |
| Journey setup | `standard@1` active (S05-035); `standard@2` canary for inst-A; `standard@3` published. |
| Action | `POST /control/routing-policies/standard/versions/3/rollback` with operator bearer; no body. |
| Expected outcome | HTTP 409, body `{"error":"illegal_policy_transition"}` — rollback applies only to `canary` or `active` rows; published is rejected. |
| Side effects | None — all rows unchanged (including `standard@2` canary split); no audit row. |
| Code reference | ai-platform/src/control/routing-policy.ts — published/superseded rollback branch |

## Scenario S05-047 — Rollback a superseded version → 409 illegal_policy_transition

| Field | Content |
|-------|---------|
| ID | S05-047 |
| Journey setup | S05-036 completed (`standard@1` superseded, `standard@2` active). |
| Action | `POST /control/routing-policies/standard/versions/1/rollback` with operator bearer; no body. |
| Expected outcome | HTTP 409, body `{"error":"illegal_policy_transition"}` — superseded rows cannot be rolled back. |
| Side effects | None — no status changes; no audit row. |
| Code reference | ai-platform/src/control/routing-policy.ts — published/superseded rollback branch |

## Scenario S05-048 — Rollback an unknown policy version → 404 policy_version_not_found

| Field | Content |
|-------|---------|
| ID | S05-048 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/77/rollback` with operator bearer; no body. |
| Expected outcome | HTTP 404, body `{"error":"policy_version_not_found"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L424-L432 — existence check |

## Scenario S05-049 — Rollback without operator auth → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-049 |
| Journey setup | S05-001 completed. |
| Action | `POST /control/routing-policies/standard/versions/1/rollback` with no `Authorization` header; no body. |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/routing-policy.ts:L409-L412 — requireOperator first |

## Scenario S05-050 — Published-but-never-promoted policy is not served (post-accept internal_error)

| Field | Content |
|-------|---------|
| ID | S05-050 |
| Journey setup | S05-001 completed (`standard@1` `published`, never promoted); inst-A fully entitled and AAT-minted per Conventions. |
| Action | `POST /v1/requests` with the Conventions invoke headers/body for inst-A (`x-idempotency-key: idem-s05-050-0001`), then read the SSE stream for the returned `request_reference`. |
| Expected outcome | HTTP 202 accept (Stage 10 behavior — guards do not touch routing policy). On the stream: a `failed` terminal event with code `internal_error`. Root cause: `preloadRoutingPolicyForInstallation` → reader finds no `canary` row naming inst-A and no `active` row → `ConfigCacheMissError("active_routing_policy", "routing/standard/…")` → caught by the `runFreshEventSource` catch-all. |
| Side effects | `ai_request` row exists from accept. No `ai_request.routing_decision` write (routing never resolved). See Doc-drift observations on missing settlement in this catch path. |
| Code reference | ai-platform/src/config-cache/index.ts:L366-L378 — active-row lookup returns "miss"; ai-platform/src/worker.ts:L731-L736 — preload; L685-L697 — catch → internal_error |

## Scenario S05-051 — Canary installation served canary version; sibling installation served active version

| Field | Content |
|-------|---------|
| ID | S05-051 |
| Journey setup | `standard@1` active (S05-035) with the fixture's two targets; `standard@2` published with a single-target document (`gemini/gemini-3.5-flash` only, rule_id `v2-catch-all`) and canaried for inst-A (S05-023 shape on v2). Both installations entitled; config cache cold (cleared or TTL elapsed). |
| Action | Two invoke journeys: (a) `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-051a-0001`); (b) `POST /v1/requests` as inst-B (`x-idempotency-key: idem-s05-051b-0001`). |
| Expected outcome | Both HTTP 202 and eventually `completed`. D1 `ai_request.routing_decision` for (a): `policy_version: 2`, `rule_id: "v2-catch-all"`, chain `[{ordinal:0, provider_id:"gemini", model_id:"gemini-3.5-flash", max_attempts:2, timeout_ms:30000}]`. For (b): `policy_version: 1`, `rule_id: "platform-default-fallback"`, chain `[deepseek/deepseek-v4-flash (ordinal 0), gemini/gemini-3.5-flash (ordinal 1)]`. |
| Side effects | Config cache gains key `active_routing_policy:routing/standard/018e4f2a-…e2f` holding the v2 row+document, and `…/018e4f2a-…f3a` holding the v1 row+document. Two `routing_decision` UPDATEs on the respective `ai_request` rows (Stage 10 persistence behavior). |
| Code reference | ai-platform/src/config-cache/index.ts:L349-L364 — canary scan before active fallback; ai-platform/src/router/index.ts:L594-L601 — installation key consulted first |

## Scenario S05-052 — Malformed canary_installation_ids JSON in D1 → installation falls through to active

| Field | Content |
|-------|---------|
| ID | S05-052 |
| Journey setup | `standard@1` active (S05-035); `standard@2` published. [SEED] `UPDATE routing_policy SET status='canary', canary_installation_ids='not-json{' WHERE policy_id='standard' AND version='2'` — justified: the control API only ever writes `JSON.stringify` output, so a malformed list is reachable only via out-of-band D1 edits or partial migrations; the reader's `parseCanaryIds` fail-closed path exists precisely for this. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-052-0001`); observe `ai_request.routing_decision`. |
| Expected outcome | HTTP 202 → `completed`; `routing_decision.policy_version: 1` (active v1 served). `parseCanaryIds('not-json{')` returns `[]`, so inst-A matches no canary row and the reader falls through to the active row. |
| Side effects | Cache key for inst-A holds the v1 document. |
| Code reference | ai-platform/src/config-cache/index.ts:L160-L173 — parseCanaryIds fail-closed; L357-L364 — canary scan skip |

## Scenario S05-053 — Active row whose R2 object is missing → post-accept internal_error

| Field | Content |
|-------|---------|
| ID | S05-053 |
| Journey setup | S05-035 completed (`standard@1` active). [SEED] delete the R2 object `control/routing-policy/standard/1.json` directly via the R2 binding — justified: models R2 object loss/tombstoning outside the control plane; no control API deletes R2 objects. Config cache cold. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-053-0001`); read the SSE stream. |
| Expected outcome | HTTP 202 → SSE `failed` terminal with code `internal_error`. The reader logs `routing_policy_r2_miss` with `content_pointer='control/routing-policy/standard/1.json'` and returns "miss", which becomes `ConfigCacheMissError`. |
| Side effects | No `routing_decision` write. Error log `routing_policy_r2_miss` emitted. |
| Code reference | ai-platform/src/config-cache/index.ts:L176-L194 — loadRoutingPolicyDocument R2 miss; ai-platform/src/worker.ts:L685-L697 — catch → internal_error |

## Scenario S05-054 — Canary row whose R2 object is missing → miss, no fallback to active

| Field | Content |
|-------|---------|
| ID | S05-054 |
| Journey setup | S05-051 setup (v1 active, v2 canary for inst-A). [SEED] delete R2 object `control/routing-policy/standard/2.json` only. Config cache cold. |
| Action | (a) `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-054a-0001`); (b) `POST /v1/requests` as inst-B (`x-idempotency-key: idem-s05-054b-0001`). |
| Expected outcome | (a) HTTP 202 → SSE `failed`/`internal_error`: the reader returns `"miss"` directly from the canary branch when the R2 get fails — it does **not** fall through to the active row. (b) HTTP 202 → `completed` on v1 (inst-B never consults the canary row's document). |
| Side effects | (a) error log `routing_policy_r2_miss` for the v2 pointer; no routing_decision. (b) normal v1 routing_decision. |
| Code reference | ai-platform/src/config-cache/index.ts:L357-L363 — canary branch returns loadRoutingPolicyDocument result directly |

## Scenario S05-055 — R2 document identity overwritten out-of-band → policy_identity_mismatch → internal_error

| Field | Content |
|-------|---------|
| ID | S05-055 |
| Journey setup | S05-035 completed (`standard@1` active). [SEED] overwrite R2 object `control/routing-policy/standard/1.json` with a document whose header reads `"policy_id":"standard","policy_version":2` (identity tamper) — justified: models an out-of-band R2 edit; the control plane never rewrites a published pointer (S05-004). Config cache cold. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-055-0001`); read the SSE stream. |
| Expected outcome | HTTP 202 → SSE `failed`/`internal_error`. `validatePolicyDocument` throws `RoutingPolicyError` code `policy_identity_mismatch` ("Document identity standard@2 does not match row standard@1"); the worker catch-all maps it to `internal_error` — the router code never reaches the wire. |
| Side effects | No `routing_decision` write. |
| Code reference | ai-platform/src/router/index.ts:L246-L255 — identity check; ai-platform/src/worker.ts:L685-L697 — catch → internal_error |

## Scenario S05-056 — Unsupported schema_version in served document → internal_error

| Field | Content |
|-------|---------|
| ID | S05-056 |
| Journey setup | Publish `standard@3` with `"schema_version": 2` (otherwise identical to the fixture) — publish accepts it (identity-only validation, S05-022); promote it (S05-035 shape). Config cache cold. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-056-0001`); read the SSE stream. |
| Expected outcome | HTTP 202 → SSE `failed`/`internal_error`. Router throws `RoutingPolicyError` code `unsupported_schema_version` ("Unsupported routing policy schema_version 2"); mapped to `internal_error` on the wire. |
| Side effects | No `routing_decision` write. |
| Code reference | ai-platform/src/router/index.ts:L257-L263 — schema version gate; L214 — SUPPORTED_SCHEMA_VERSIONS = {1} |

## Scenario S05-057 — Served document without a catch-all last rule → missing_catch_all → internal_error

| Field | Content |
|-------|---------|
| ID | S05-057 |
| Journey setup | S05-022 completed (`standard@9` published; its only rule matches `capability_ids:["clinic.nonexistent"]` — not a catch-all); promote `standard@9`. Config cache cold. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-057-0001`); read the SSE stream. |
| Expected outcome | HTTP 202 → SSE `failed`/`internal_error`. Router throws `RoutingPolicyError` code `missing_catch_all` ("Routing policy document must end with a catch-all rule (empty/absent match)") before any rule matching. |
| Side effects | No `routing_decision` write. |
| Code reference | ai-platform/src/router/index.ts:L229-L240 — isCatchAllMatch; L265-L270 — missing_catch_all throw |

## Scenario S05-058 — no_matching_rule is unreachable through the serving path (defensive code)

| Field | Content |
|-------|---------|
| ID | S05-058 |
| Journey setup | Any served document journey (e.g. S05-051). Attempt to construct a request context that matches no rule. |
| Action | Invoke with capability/installation/tier/language/latency combinations intended to miss every rule. |
| Expected outcome | Unreachable: `validatePolicyDocument` runs before rule matching and rejects any document whose last rule is not a catch-all (S05-057); a catch-all match clause passes every `matchClause`/`matchAllLanguages` check, so `document.rules.find(...)` always succeeds. `RoutingPolicyError` code `no_matching_rule` ("No routing policy rule matched for installation …") can only fire if the validation gate is bypassed — it is dead defensive code on the production path. Recorded for taxonomy completeness; no production-faithful trigger exists. |
| Side effects | None. |
| Code reference | ai-platform/src/router/index.ts:L619-L624 — no_matching_rule throw; L606 — validatePolicyDocument runs first |

## Scenario S05-059 — Config-cache staleness window after promote/rollback (30 s TTL)

| Field | Content |
|-------|---------|
| ID | S05-059 |
| Journey setup | S05-036 completed (v2 active, v1 superseded); inst-A entitled. First: `POST /v1/requests` as inst-A and confirm `routing_decision.policy_version: 2` (warms cache key `active_routing_policy:routing/standard/<inst-A>` with the v2 row). Then roll back v2 (S05-044) so v1 is active in D1. |
| Action | Within 30 s of the warm-up request, `POST /v1/requests` again as inst-A (`x-idempotency-key: idem-s05-059a-0001`). Then wait 31 s (or restart the Worker / clear the isolate cache) and `POST /v1/requests` a third time (`x-idempotency-key: idem-s05-059b-0001`). |
| Expected outcome | Second request: `routing_decision.policy_version: 2` — the cached row is served until `expiresAt` (`DEFAULT_CONFIG_CACHE_TTL_MS = 30_000`, overridable via `CONFIG_CACHE_TTL_MS`). Third request: `routing_decision.policy_version: 1` — TTL expiry forces a D1 reload that sees the rollback. Same window applies after promote and canary changes. |
| Side effects | Cache entry evicted at expiry (`consult` deletes on `now >= expiresAt`). |
| Code reference | ai-platform/src/config-cache/index.ts:L26-L28 — default TTL; L89-L103 — consult expiry; ai-platform/src/router/index.ts:L594-L601 — consult order |

## Scenario S05-060 — Legacy @vN suffix on the policy cache key is tolerated and stripped

| Field | Content |
|-------|---------|
| ID | S05-060 |
| Journey setup | S05-035 completed (`standard@1` active). Seam: call `createD1ConfigReader(DB, R2).read(...)` directly (production manifests emit `routing/standard` without a suffix; the suffix path exists for legacy callers). |
| Action | `read("active_routing_policy:routing/standard@v1")` and `read("active_routing_policy:routing/standard@v1/018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f")`. |
| Expected outcome | Both resolve the same `standard@1` active row with its R2 document attached — the `@v\d+` suffix is stripped before the D1 query and never pins a version. |
| Side effects | None (read-only). |
| Code reference | ai-platform/src/config-cache/index.ts:L338-L348 — key-shape regex and suffix strip |

## Scenario S05-061 — Target without structured_output excluded as feature_unsupported (structured capability)

| Field | Content |
|-------|---------|
| ID | S05-061 |
| Journey setup | Publish + promote `standard@4`: catch-all rule with two targets — T1 `deepseek/deepseek-v4-flash` with `features.structured_output: false` (other features as fixture), T2 `gemini/gemini-3.5-flash` as fixture. Invoke uses a structured-output capability context: seam note — the bundled visit-summary manifest is `Output.mode: "prose"`, so this journey drives `selectCandidateChain` with `requirements.structured_output_required: true` via the router seam (same inputs `worker.ts` builds, with `Output.mode !== "prose"` simulated), backed by the real D1 reader and real R2 document. |
| Action | Resolve routing for inst-A, capability `clinic.visit_summary`, tier `standard`, requirements `{structured_output_required: true, min_context_window: 32000, languages: ["en"], latency_class: "standard"}`. |
| Expected outcome | `routing_decision.chain = [{ordinal:0, provider_id:"gemini", model_id:"gemini-3.5-flash", max_attempts:2, timeout_ms:30000}]`; `excluded = [{provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"feature_unsupported"}]`. |
| Side effects | None beyond the decision (router is pure). |
| Code reference | ai-platform/src/router/index.ts:L487-L497 — structured-output gate |

## Scenario S05-062 — Target with missing/non-numeric min_context_window fails closed as feature_unsupported

| Field | Content |
|-------|---------|
| ID | S05-062 |
| Journey setup | Publish + promote `standard@5`: catch-all with T1 `deepseek/deepseek-v4-flash` whose `features.min_context_window` is the string `"128000"` (pairwise variant: key absent; variant: `NaN`-producing non-finite), T2 `gemini/gemini-3.5-flash` as fixture. Inst-A entitled; invoke journey per Conventions. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-062-0001`) → HTTP 202 → `completed`; inspect `ai_request.routing_decision`. |
| Expected outcome | `excluded[0] = {provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"feature_unsupported"}` — a missing/unknown window fails closed rather than throwing or being treated as infinite. Chain contains only gemini. |
| Side effects | `ai_request.routing_decision` JSON persisted with the exclusion (Stage 10 persistence behavior). |
| Code reference | ai-platform/src/router/index.ts:L499-L507 — isFiniteNumber fail-closed gate |

## Scenario S05-063 — Target window below the required floor → context_window_too_small

| Field | Content |
|-------|---------|
| ID | S05-063 |
| Journey setup | Publish + promote `standard@6`: catch-all with T1 `deepseek/deepseek-v4-flash` `features.min_context_window: 16000` (declared, finite, but below the manifest floor 32000), T2 gemini as fixture. Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-063-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `excluded[0] = {provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"context_window_too_small"}` — a declared-but-too-small window keeps the distinct reason code (contrast S05-062). Chain = gemini only. Boundary pair: a target with exactly `32000` is **not** excluded (`<` comparison). |
| Side effects | Persisted routing_decision with exclusion. |
| Code reference | ai-platform/src/router/index.ts:L508-L515 — window comparison |

## Scenario S05-064 — Target with non-array languages fails closed as feature_unsupported

| Field | Content |
|-------|---------|
| ID | S05-064 |
| Journey setup | Publish + promote `standard@7`: catch-all with T1 `deepseek/deepseek-v4-flash` `features.languages: "en"` (string, not array; pairwise variant: key absent), T2 gemini as fixture. Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-064-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `excluded[0].reason_code = "feature_unsupported"` for deepseek — non-array languages fail closed instead of throwing TypeError or treating the string as a list. Chain = gemini only. |
| Side effects | Persisted routing_decision with exclusion. |
| Code reference | ai-platform/src/router/index.ts:L518-L526 — Array.isArray guard |

## Scenario S05-065 — Target missing a required language → language_unsupported

| Field | Content |
|-------|---------|
| ID | S05-065 |
| Journey setup | Publish + promote `standard@8`: catch-all with T1 `deepseek/deepseek-v4-flash` `features.languages: ["fr"]`, T2 gemini (`["en"]`) as fixture. Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-065-0001`; manifest requires language `en`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `excluded[0] = {provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"language_unsupported"}`. Chain = gemini only. |
| Side effects | Persisted routing_decision with exclusion. |
| Code reference | ai-platform/src/router/index.ts:L527-L539 — language subset check |

## Scenario S05-066 — Target latency_class mismatch → feature_unsupported (no dedicated reason code)

| Field | Content |
|-------|---------|
| ID | S05-066 |
| Journey setup | Publish + promote `standard@9b` (use version 10 to avoid the S05-022 identity): catch-all with T1 `deepseek/deepseek-v4-flash` `features.latency_class: "batch"`, T2 gemini (`"standard"`) as fixture. Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-066-0001`; manifest latencyClass `standard`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `excluded[0].reason_code = "feature_unsupported"` for deepseek — the frozen `ExcludedReasonCode` enum has no `latency_unsupported`, so latency mismatch maps to `feature_unsupported`. Chain = gemini only. |
| Side effects | Persisted routing_decision with exclusion. |
| Code reference | ai-platform/src/router/index.ts:L541-L549 — latency gate with mapping comment |

## Scenario S05-067 — Target with unknown cost_class fails closed as feature_unsupported

| Field | Content |
|-------|---------|
| ID | S05-067 |
| Journey setup | Publish + promote `standard@11`: catch-all with T1 `deepseek/deepseek-v4-flash` `features.cost_class: "cheap"` (not in `economy|standard|premium`; pairwise variant: key absent), T2 gemini as fixture. Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-067-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `excluded[0].reason_code = "feature_unsupported"` for deepseek — unknown cost class fails closed (contrast S05-068). Chain = gemini only. |
| Side effects | Persisted routing_decision with exclusion. |
| Code reference | ai-platform/src/router/index.ts:L552-L560 — isKnownCostClass gate; L199-L201 — known-class set |

## Scenario S05-068 — Target cost_class above the effective ceiling → cost_class_excluded

| Field | Content |
|-------|---------|
| ID | S05-068 |
| Journey setup | Publish + promote `standard@12`: catch-all with T1 `deepseek/deepseek-v4-pro` `features.cost_class: "premium"` (other features as fixture), T2 gemini (`"standard"`) as fixture. Inst-A entitled. Invoke path hardwires `manifestCostClass: "standard"`, `entitlementMaxCostClass: "premium"` → effective `standard`. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-068-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `effective_cost_class: "standard"`, `cost_class_source: "manifest"`; `excluded[0] = {provider_id:"deepseek", model_id:"deepseek-v4-pro", reason_code:"cost_class_excluded"}` (premium > standard). Chain = gemini only. |
| Side effects | Persisted routing_decision with exclusion. |
| Code reference | ai-platform/src/router/index.ts:L561-L568 — cost ceiling comparison; L307-L339 — resolveEffectiveCostClass; ai-platform/src/worker.ts:L754-L755 — hardwired cost inputs |

## Scenario S05-069 — Provider kill switch excludes the first target; request fails over to the next

| Field | Content |
|-------|---------|
| ID | S05-069 |
| Journey setup | S05-035 completed (`standard@1` active, fixture targets deepseek→gemini). [SEED] `INSERT INTO kill_switch (scope, target, active, changed_at, changed_by) VALUES ('provider','deepseek',1,'2026-09-05T03:00:00.000Z','platform-operator')` — justified: no control-plane endpoint writes `kill_switch` in this codebase (verified: no `INSERT INTO kill_switch` in `ai-platform/src/`); the table's producer is out of scope (§3.1.1). Inst-A entitled; config cache cold so the guard reloads kill switches. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-069-0001`) per Stage 10 accepted-request behavior → stream to completion; inspect `ai_request.routing_decision`. |
| Expected outcome | HTTP 202 → `completed` (served by gemini). Guard stage 5 collects `killedProviderIds: ["deepseek"]` (capability resolve behavior of the guard chapter); the router excludes deepseek: `excluded = [{provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"kill_switch"}]`; `chain = [{ordinal:0, provider_id:"gemini", model_id:"gemini-3.5-flash", ...}]`. |
| Side effects | Persisted routing_decision showing the kill_switch exclusion; settlement proceeds against gemini (invocation/settlement chapters' behavior). |
| Code reference | ai-platform/src/capability/index.ts:L380-L400 — collectActiveProviderKillSwitches; ai-platform/src/router/index.ts:L477-L485 — kill_switch filter; L447-L463 — mergeKilledProviderIds |

## Scenario S05-070 — Kill switch on every target → empty chain → provider_unavailable with synthetic attempt row

| Field | Content |
|-------|---------|
| ID | S05-070 |
| Journey setup | S05-069 setup plus a second [SEED] row `('provider','gemini',1,'2026-09-05T03:01:00.000Z','platform-operator')` — both fixture providers killed. Config cache cold. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-070-0001`) → read the SSE stream; inspect D1. |
| Expected outcome | HTTP 202 → SSE `failed` terminal with code `provider_unavailable` (empty chain, not `internal_error`). `routing_decision.chain = []`; `excluded` lists both targets with `reason_code: "kill_switch"`. D1: one `ai_attempt` row with `outcome='terminal_failure'`, `error_code='provider_unavailable'`, `rawBody.payload.reason='no_provider_attempt'` and `rawBody.payload.excluded` echoing both exclusions (failed settlement always persists an attempt). |
| Side effects | `ai_request` terminal state `Failed` with `terminal_error_code='provider_unavailable'`; journal + ledger writes per the settlement chapter's failed-settlement behavior (same persisted terminal settlement as the empty-chain path). |
| Code reference | ai-platform/src/worker.ts:L381-L411 — attemptsForFailedSettlement no_provider_attempt; L956-L979 — provider_unavailable terminal path |

## Scenario S05-071 — All targets feature-excluded → empty chain → provider_unavailable (not internal_error)

| Field | Content |
|-------|---------|
| ID | S05-071 |
| Journey setup | Publish + promote `standard@13`: catch-all whose only target is `deepseek/deepseek-v4-flash` with `features.min_context_window: 8000` (below the 32000 floor). Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-071-0001`) → read the SSE stream; inspect D1. |
| Expected outcome | HTTP 202 → SSE `failed`/`provider_unavailable`. `chain = []`; `excluded = [{provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"context_window_too_small"}]`. Synthetic `ai_attempt` row as in S05-070 with the exclusion echoed. |
| Side effects | `ai_request` terminal state `Failed` with `terminal_error_code='provider_unavailable'`; journal + ledger writes per S05-070 (persisted terminal settlement, not left `Accepted`). |
| Code reference | ai-platform/src/router/index.ts:L570-L580 — chain construction (empty); ai-platform/src/worker.ts:L956-L966 — taxonomy fallback |

## Scenario S05-072 — Installation override exclude_providers → installation_excluded

| Field | Content |
|-------|---------|
| ID | S05-072 |
| Journey setup | Publish + promote `standard@14`: fixture document plus `overrides: [{"installation_id":"018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f","exclude_providers":["deepseek"]}]`. Inst-A and inst-B entitled. |
| Action | (a) `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-072a-0001`); (b) as inst-B (`x-idempotency-key: idem-s05-072b-0001`). Inspect both `routing_decision` rows. |
| Expected outcome | (a) `excluded[0] = {provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"installation_excluded"}`; chain = gemini only. (b) No exclusions; full two-target chain — overrides apply only to the named installation. |
| Side effects | Two persisted routing_decisions demonstrating per-installation divergence from one policy version. |
| Code reference | ai-platform/src/router/index.ts:L375-L392 — exclude_providers branch; L608-L610 — override lookup |

## Scenario S05-073 — Installation override pin_target → pinned chain, all others installation_excluded

| Field | Content |
|-------|---------|
| ID | S05-073 |
| Journey setup | Publish + promote `standard@15`: fixture document plus `overrides: [{"installation_id":"018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f","pin_target":{"provider_id":"gemini","model_id":"gemini-3.5-flash"}}]`. Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-073-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `chain = [{ordinal:0, provider_id:"gemini", model_id:"gemini-3.5-flash", max_attempts:2, timeout_ms:30000}]`; `excluded = [{provider_id:"deepseek", model_id:"deepseek-v4-flash", reason_code:"installation_excluded"}]`. |
| Side effects | Persisted routing_decision. |
| Code reference | ai-platform/src/router/index.ts:L394-L417 — pin_target branch |

## Scenario S05-074 — pin_target naming a target absent from the matched rule → empty chain → provider_unavailable

| Field | Content |
|-------|---------|
| ID | S05-074 |
| Journey setup | Publish + promote `standard@16`: fixture document plus `overrides: [{"installation_id":"018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f","pin_target":{"provider_id":"openai","model_id":"gpt-6"}}]` — the pin matches no rule target. Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-074-0001`) → read the SSE stream. |
| Expected outcome | HTTP 202 → SSE `failed`/`provider_unavailable`. Both real targets excluded with `installation_excluded`; `pinned` lookup finds nothing → `chain = []`. Synthetic `ai_attempt` row per S05-070. |
| Side effects | As S05-070. |
| Code reference | ai-platform/src/router/index.ts:L395-L415 — pinned find + remaining = [] |

## Scenario S05-075 — Override force_cost_class lowers the ceiling → cost_class_excluded, source installation_override

| Field | Content |
|-------|---------|
| ID | S05-075 |
| Journey setup | Publish + promote `standard@17`: catch-all with T1 `deepseek/deepseek-v4-flash` `features.cost_class: "economy"`, T2 gemini `"standard"`; `overrides: [{"installation_id":"018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f","force_cost_class":"economy"}]`. Inst-A and inst-B entitled. |
| Action | (a) `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-075a-0001`); (b) as inst-B (`x-idempotency-key: idem-s05-075b-0001`). |
| Expected outcome | (a) `effective_cost_class: "economy"`, `cost_class_source: "installation_override"`; gemini excluded with `cost_class_excluded`; chain = deepseek only. (b) `effective_cost_class: "standard"`, `cost_class_source: "manifest"`; full chain, no exclusions. |
| Side effects | Two persisted routing_decisions. |
| Code reference | ai-platform/src/router/index.ts:L307-L339 — three-source minimum; L317-L322 — override candidate |

## Scenario S05-076 — Rule match: capability_ids clause skips a non-matching rule; catch-all serves

| Field | Content |
|-------|---------|
| ID | S05-076 |
| Journey setup | Publish + promote `standard@18`: rule 1 `rule_id: "image-only"`, `match: {"capability_ids":["clinic.image_caption"]}`, target `deepseek/deepseek-v4-flash`; rule 2 = fixture catch-all (`rule_id: "platform-default-fallback"`, both fixture targets). Inst-A entitled. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-076-0001`, capability `clinic.visit_summary`) → inspect `ai_request.routing_decision`. |
| Expected outcome | `rule_id: "platform-default-fallback"` — rule 1's `capability_ids` clause rejects `clinic.visit_summary`; first-match-wins walks to the catch-all. Chain = both fixture targets. |
| Side effects | Persisted routing_decision with rule attribution. |
| Code reference | ai-platform/src/router/index.ts:L272-L301 — ruleMatches; L281-L283 — capability_ids clause; L616-L618 — first-match find |

## Scenario S05-077 — Rule match: tiers clause skips a standard-only rule for a degraded request

| Field | Content |
|-------|---------|
| ID | S05-077 |
| Journey setup | Publish + promote `standard@19`: rule 1 `rule_id: "standard-tier-only"`, `match: {"tiers":["standard"]}`, single target `deepseek/deepseek-v4-flash`; rule 2 = fixture catch-all. Inst-A entitled with a soft-threshold/grace admission state so the guard derives `routingTier: "degraded"` (soft-threshold chapter's degraded-admission behavior; `routingTierFromAdmission`). |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-077-0001`) while admission is degraded → inspect `ai_request.routing_decision`. |
| Expected outcome | `routing_tier: "degraded"`, `rule_id: "platform-default-fallback"` — rule 1 rejects the degraded tier. Pairwise control: the same policy under standard admission yields `rule_id: "standard-tier-only"`, chain = deepseek only. |
| Side effects | Persisted routing_decision; `ai_request.routing_tier` matches the decision's tier. |
| Code reference | ai-platform/src/router/index.ts:L290-L292 — tiers clause; ai-platform/src/worker.ts:L748 — routingTierFromAdmission wiring |

## Scenario S05-078 — Rule match: languages clause requires every required language

| Field | Content |
|-------|---------|
| ID | S05-078 |
| Journey setup | Publish + promote `standard@20`: rule 1 `rule_id: "en-only"`, `match: {"languages":["en"]}`, single target deepseek; rule 2 = fixture catch-all. Inst-A entitled. Seam: drive `selectCandidateChain` with `requirements.languages: ["en","ar"]` (manifests declare one language today; the multi-language floor is reachable via rule `requires` union — see S05-081 — so the router seam is used to exercise the match clause directly). |
| Action | Resolve routing for inst-A with languages `["en","ar"]`, other requirements as Conventions. |
| Expected outcome | `rule_id: "platform-default-fallback"` — `matchAllLanguages` requires *every* required language in the clause; `["en"]` does not cover `ar`. Control: languages `["en"]` matches rule 1. |
| Side effects | None beyond the decision. |
| Code reference | ai-platform/src/router/index.ts:L220-L227 — matchAllLanguages; L293-L295 — languages clause |

## Scenario S05-079 — Rule requires floor raises min_context_window above the manifest floor

| Field | Content |
|-------|---------|
| ID | S05-079 |
| Journey setup | Publish + promote `standard@21`: catch-all with `requires: {"structured_output": false, "min_context_window": 64000, "languages": []}`, T1 deepseek with `features.min_context_window: 32000`, T2 gemini with 128000. Inst-A entitled (manifest floor 32000). |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-079-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | Merged floor is `max(32000, 64000) = 64000`: deepseek excluded `context_window_too_small` despite satisfying the manifest floor; chain = gemini only. Note `routing_decision.required_features` still shows the manifest-only floor (32000) — filtering uses the merged floor, the journal field does not (known gap). |
| Side effects | Persisted routing_decision. |
| Code reference | ai-platform/src/router/index.ts:L344-L363 — mergeRequirementFloors; L629-L632 — merge applied; L674 — required_features is context.requirements |

## Scenario S05-080 — Rule requires structured_output forces the OR floor on a prose capability

| Field | Content |
|-------|---------|
| ID | S05-080 |
| Journey setup | Publish + promote `standard@22`: catch-all with `requires: {"structured_output": true, "min_context_window": 0, "languages": []}`, T1 deepseek `features.structured_output: false`, T2 gemini `true`. Inst-A entitled; visit-summary manifest is `Output.mode: "prose"` → manifest requirement is false. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-080-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | OR-merge forces `structured_output_required: true` for filtering: deepseek excluded `feature_unsupported`; chain = gemini only. |
| Side effects | Persisted routing_decision. |
| Code reference | ai-platform/src/router/index.ts:L353-L355 — OR merge; L487-L497 — structured-output gate |

## Scenario S05-081 — Rule requires languages union adds a language the target lacks → language_unsupported

| Field | Content |
|-------|---------|
| ID | S05-081 |
| Journey setup | Publish + promote `standard@23`: catch-all with `requires: {"structured_output": false, "min_context_window": 0, "languages": ["ar"]}`, T1 deepseek `features.languages: ["en"]`, T2 gemini `["en","ar"]`. Inst-A entitled (manifest language `en`). |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-081-0001`) → inspect `ai_request.routing_decision`. |
| Expected outcome | Merged languages `["en","ar"]` (union — rules can add, never remove): deepseek excluded `language_unsupported`; chain = gemini only. |
| Side effects | Persisted routing_decision. |
| Code reference | ai-platform/src/router/index.ts:L349-L351 — language union; L527-L539 — subset check |

## Scenario S05-082 — Effective cost class: three-source minimum with source-priority tie-break

| Field | Content |
|-------|---------|
| ID | S05-082 |
| Journey setup | Publish + promote `standard@24`: catch-all with three targets — `deepseek/econ` (economy), `gemini/std` (standard), `anthropic/prem` (premium) — and no overrides. Seam: drive `selectCandidateChain` directly with controlled cost inputs (worker hardwires manifest=standard/entitlement=premium, so ties and entitlement-cap binding are only exercisable via the router seam today). |
| Action | Four resolutions for inst-A: (a) manifest standard + entitlement premium → expect effective `standard`, source `manifest`; (b) manifest premium + entitlement standard → effective `standard`, source `entitlement_cap`; (c) manifest standard + entitlement standard (tie) → effective `standard`, source `entitlement_cap` (SOURCE_PRIORITY: installation_override 0 < entitlement_cap 1 < manifest 2); (d) like (a) plus document override `force_cost_class: "premium"` for inst-A → effective `standard` (minimum still wins — override lowers, never raises). |
| Expected outcome | (a) chain `[deepseek/econ, gemini/std]`, anthropic/prem `cost_class_excluded`, source `manifest`. (b) same chain, source `entitlement_cap`. (c) same chain, source `entitlement_cap`. (d) same chain as (a) — `force_cost_class` premium does not raise the ceiling. |
| Side effects | None beyond decisions. |
| Code reference | ai-platform/src/router/index.ts:L208-L212 — SOURCE_PRIORITY; L307-L339 — resolveEffectiveCostClass |

## Scenario S05-083 — Chain ordinals, attempt bounds, and RoutingDecision persistence end-to-end

| Field | Content |
|-------|---------|
| ID | S05-083 |
| Journey setup | S05-035 completed (fixture active). Inst-A entitled; config cache cold. |
| Action | `POST /v1/requests` as inst-A (`x-idempotency-key: idem-s05-083-0001`) → `completed`; then `SELECT routing_decision FROM ai_request WHERE request_id = …`. |
| Expected outcome | Persisted JSON: `policy_id: "standard"`, `policy_version: 1`, `rule_id: "platform-default-fallback"`, `effective_cost_class: "standard"`, `cost_class_source: "manifest"`, `routing_tier: "standard"`, `required_features` = manifest requirements `{structured_output_required: false, min_context_window: 32000, languages: ["en"], latency_class: "standard"}`, `chain: [{ordinal:0, provider_id:"deepseek", model_id:"deepseek-v4-flash", max_attempts:2, timeout_ms:30000},{ordinal:1, provider_id:"gemini", model_id:"gemini-3.5-flash", max_attempts:2, timeout_ms:30000}]`, `excluded: []`. Ordinals are assigned after filtering (0-based, gapless); `max_parallel_attempts` appears nowhere on the decision. |
| Side effects | One UPDATE on `ai_request.routing_decision` (Stage 10 persistence behavior); info log `Routing decision resolved` with `chain_length: 2`. |
| Code reference | ai-platform/src/router/index.ts:L570-L578 — ordinal/attempt-bound carry; L667-L679 — decision assembly; ai-platform/src/worker.ts:L764-L767 — persistRoutingDecision |

## Scenario S05-084 — Canary with a wrong operator bearer → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-084 |
| Journey setup | S05-001 completed (`standard@1` published); Stage 3 enroll happy path → installation I0 exists. |
| Action | `POST /control/routing-policies/standard/versions/1/canary` with header `Authorization: Bearer op_wrong-secret-9f8d7c6b5a` (valid format, wrong secret), `Content-Type: application/json`; body `{"installation_ids": ["8f3c2a1e-4b5d-4e6f-9a0b-1c2d3e4f5a6b"]}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — `requireOperator` rejects before route parsing and before the `policy_version_not_found` / `illegal_policy_transition` checks. |
| Side effects | None: no canary cohort row, no status change on `routing_policy`, no `control_audit` row, no R2 write. |
| Code reference | `ai-platform/src/control/routing-policy.ts:L247-L250` — `handleRoutingPolicyCanary` auth gate; `ai-platform/src/control/auth.ts:L45-L47` — `timingSafeEqualString` bearer compare |

## Scenario S05-085 — Rollback with a wrong operator bearer → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S05-085 |
| Journey setup | S05-035 completed (`standard@1` active). |
| Action | `POST /control/routing-policies/standard/versions/1/rollback` with header `Authorization: Bearer op_wrong-secret-9f8d7c6b5a`; body `{}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — rejected before the version lookup. |
| Side effects | None: `standard@1` stays `active`; no `control_audit` row. |
| Code reference | `ai-platform/src/control/routing-policy.ts:L409-L412` — `handleRoutingPolicyRollback` auth gate; `ai-platform/src/control/auth.ts:L45-L47` — bearer compare |

## Doc-drift observations

1. **Post-accept routing failures all surface as `internal_error`, not router codes.** Doc §8 (`07-stage-5-routing-policy.md` L932–L947) lists `policy_identity_mismatch` and `no_matching_rule` in a way that implies distinct terminal codes. Code: every throw from the routing block (`ConfigCacheMissError`, any `RoutingPolicyError`) is caught by the `runFreshEventSource` `.catch` (`worker.ts` L685–L697) and pushed as SSE `failed`/`internal_error`. Router error codes are never on the wire. Scenarios S05-050, S05-053–S05-058 encode the code behavior.
2. **The post-accept routing catch path skips settlement.** ~~`worker.ts` L685–L697 pushes the failed terminal but never calls `settleTerminal`/`recordTerminalState` — a request whose routing throws (missing policy, missing R2 doc, identity mismatch, bad schema, missing catch-all) is left without terminal-state persistence, no `ai_attempt`, and no ledger entry. Doc §8 does not mention this. (Contrast the empty-chain path, which *does* settle — S05-070/S05-071.)~~ **Fixed (C-01):** post-accept routing / missing-policy / missing-handoff failures now settle the request as `Failed`/`internal_error` with journal + terminal-state persistence (`recordTerminalState`, `ai_attempt`, ledger entry), mirroring the empty-chain path. The SSE `failed`/`internal_error` event on the wire is unchanged; scenarios S05-050, S05-053–S05-058 should pin the persisted terminal state alongside the stream event.
3. **`no_matching_rule` is dead code on the production path.** `validatePolicyDocument` (catch-all requirement) runs before rule matching, and a catch-all matches everything, so `document.rules.find(...)` can never return undefined. Doc §8 lists it as a live failure path. Recorded as S05-058.
4. **Promote has no status precondition; rollback of published/superseded is a 200 no-op.** ~~Doc §6.3–6.4 describe only the happy transitions. Code: promote requires only existence (S05-039 self-promote yields a self-referential audit pair; S05-040 re-activates a superseded version); rollback's `else` branch (published/superseded) succeeds without touching the addressed row (S05-046, S05-047).~~ **Fixed (C-13):** promote rejects `active` and `superseded` sources with 409 `illegal_policy_transition`; rollback of `published`/`superseded` rows returns 409 (S05-039, S05-040, S05-046, S05-047).
5. **Doc §6.2 canary failure table is incomplete.** It omits 400 `invalid_json` (S05-029) and 404 `policy_version_not_found` (S05-026), and documents `missing_installation_ids` only for the empty array — code also rejects absent and non-array values (S05-030, S05-032).
6. **`cohort_name` is accepted but discarded.** ~~Doc §6.2 shows it in the canary body; `CohortPayload.cohort_name` is never read or stored (S05-023).~~ **Fixed (C-20):** when present, `cohort_name` is persisted in the canary audit row `after_pointer` JSON under `details.cohort_name` (S05-023).
7. **Two canary versions can coexist; audit before_pointer can name another version's cohort.** The canary handler updates only the addressed row (S05-025), and `priorCanary` reads the latest canary row of the *policy*, so a v2 canary's audit `before_pointer` is v1's cohort list. Neither doc §6.2 nor §5 mentions multi-canary coexistence or the serving order (`active_from DESC, rowid DESC` scan in the config-cache reader).
8. **Canary R2 miss does not fall back to active.** The config-cache reader returns `"miss"` directly from the canary branch when the R2 object is gone (`config-cache/index.ts` L357–L363); doc §9.3.13 covers a missing R2 document generally but not this no-fallback asymmetry (S05-054).
9. **`invalid_route` rejections in the routing-policy handlers are unreachable via the dispatcher.** `dispatchControlRequest` (`control/index.ts` L146–L163) pre-filters with regexes that only match `publish`/`canary`/`promote`/`rollback` shapes, so `parseRoutingPolicyRoute` cannot fail inside a handler reached through the Worker. The 400 `invalid_route` branches exist only for direct handler invocation. Not documented either way; noted here so no chapter invents a trigger.
10. **Doc §4.5 already-accurate items confirmed against code:** `defaults.cost_class` ignored; `max_parallel_attempts` ignored; `manifestCostClass`/`entitlementMaxCostClass` hardwired in `worker.ts` (L754–L755); latency mismatch maps to `feature_unsupported`; malformed target features fail closed; publish validates identity only. No drift in these rows.
11. **Bootstrap script semantics match code**: publish 409 treated as success, promote required for serving, idempotent skip when another version is active (`scripts/bootstrap-routing-policy.sh`). Consistent with S05-004/S05-035/S05-050.

## Non-automatable notes

1. **S05-020 (concurrent publish race → UNIQUE-mapped 409).** `@cloudflare/vitest-pool-workers` runs against a single local D1 (miniflare) where requests serialize; two simultaneous publishes cannot be forced to interleave deterministically between the SELECT and the batch. Proposed seam: a fault-injecting `D1Database` wrapper whose `batch` throws `Error("UNIQUE constraint failed: routing_policy.policy_id, routing_policy.version")` on the insert, asserting the 409 `already_published` mapping (`isUniqueConstraint`) directly.
2. **S05-016 (missing R2 binding → 500).** The deployed Worker always has R2 bound via wrangler; the branch is reachable only by invoking `handleRoutingPolicyPublish` with `ControlBindings` lacking `R2`. Proposed seam: direct handler invocation in a unit-style workers test (automatable at that level; not through `SELF.fetch`).
3. **500 `storage_error` (non-unique D1 failure during the publish batch).** No production-faithful trigger exists in the local pool. Proposed seam: the same fault-injecting D1 wrapper throwing a non-constraint error (e.g. `Error("disk I/O error")`); also note the orphan window — R2.put precedes the batch, so this path leaves an R2 object with no D1 row (worth asserting in the seam test).
4. **S05-059 (30 s TTL staleness) is automatable but slow.** A full-path run needs a real 31 s wait against `isolateConfigCache`. Acceptable seams: construct `new ConfigCache(50)` for router-level TTL proof, or call `isolateConfigCache.clear()` to simulate expiry — both are production code paths (`ConfigCache` TTL and `clear` are the documented test reset). Multi-isolate cache divergence (each isolate holds its own cache) cannot be reproduced in the single-isolate pool at all.
5. **S05-060, S05-061, S05-078, S05-082 (router-seam scenarios).** These exercise inputs the bundled manifest set cannot produce today (legacy `@vN` refs, structured-output requirement from a prose-only manifest catalog, multi-language floors, non-hardwired cost sources). They are automatable by calling `selectCandidateChain`/`createD1ConfigReader` directly against real migrated D1 and real R2 — production functions, production storage, but a direct-call seam rather than `POST /v1/requests`. If a structured-output or multi-language manifest is published later, S05-061/S05-078 should be re-expressed as full-path invoke journeys.
6. **Kill-switch writes (S05-069, S05-070).** No control-plane endpoint writes `kill_switch` in this codebase; the `[SEED]` direct D1 inserts are the only way to arm a provider kill. If a kill-switch control route is added, these scenarios should grow a control-plane-driven variant.
