# Stage 12 — Lookup and support

Source files read: `ai-platform/src/worker.ts`, `ai-platform/src/journal/index.ts`, `ai-platform/src/control/support-purge.ts`, `ai-platform/src/control/quota-inspect.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/control/http.ts`, `ai-platform/src/control/auth.ts`, `ai-platform/src/quota-do/index.ts`, `ai-platform/src/dashboards/index.ts`, `ai-platform/src/config-cache/index.ts`, `ai-platform/src/identity/index.ts`, `ai-platform/src/reference.ts`, `ai-platform/src/errors.ts`, `ai-platform/src/support/index.ts`, `ai-platform/src/retention/index.ts`, `ai-platform/migrations/20260731120000_platform_schema.sql`, `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`, `docs/architecture/ai-platform/data-journey/14-stage-12-lookup-and-support.md`

Conventions used throughout:

- **AAT helper** — the Stage 6 minting helper with full claim control (`iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`, `kid`, Ed25519 signing key).
- **I0** — enrolled, entitled, `active` installation `inst-aaa-001` with Ed25519 key `key-aaa-001` (token contract `ver` = `v1`, not retired). **I1** — second enrolled installation `inst-bbb-002` with key `key-bbb-002`.
- **REF** — a real request reference minted by an earlier stage (e.g. `8K2P-9QRT`); **RID** its `request_id`.
- Auth-failure bodies are produced by `getRequestAuthErrorBody` → `buildErrorBody`: `request_reference` is a **freshly minted** reference (never the path reference) and `trace_id` a fresh ULID. Shown as `<fresh-ref>` / `<fresh-ulid>`.
- Dashboard scenarios (S12-066…S12-072) are **SQL-contract scenarios**: they call the exported dashboard functions directly against a migrated D1 — there is no HTTP route.

---

## 1. `GET /v1/requests/{request_reference}`

Poll the journal for a settled or in-flight request. Auth is `authenticateGetRequest` (same `EnrolledKeyVerifier` as discovery/ingress). The row must belong to the token's `installation_id`; a mismatch returns **404** with an empty body (same as unknown reference — no cross-tenant leak).

### 1.1 Failure responses

| HTTP | Body | When |
| ---- | ---- | ---- |
| 401 | Taxonomy JSON `{ "code": "unauthenticated", "request_reference": "<fresh-ref>", "trace_id": "<fresh-ulid>", "retry_safe": true }` | Missing/invalid AAT (`getRequestAuthErrorBody` mints a **new** reference, never the path reference) |
| 403 | Taxonomy JSON `{ "code": "installation_suspended", …, "retry_safe": false }` | Suspended installation — `liveHttpStatusForCode("installation_suspended")` = **403**, not 401 (`worker.ts` GET branch, `errors.ts`) |
| 404 | **Empty body** (`new Response(null, { status: 404 })`) | Unknown/malformed/cross-installation reference, empty path segment (`/v1/requests/`), or unrecognized `ai_request.state` string |

Non-GET methods on `/v1/requests/{ref}` and `/v1/requests` (no trailing slash) return plain-text **`Not Found`** — the catch-all route, not the empty-body GET 404 (S12-013 vs S12-014/S12-018).

### 1.2 Reference normalization (clinic GET)

The path param is the raw pathname slice — **no whitespace trim**. `normalizeRequestReference` uppercases and maps ambiguous Crockford chars (`I`/`L`→`1`, `O`→`0`) only. A padded reference 404s on GET (S12-016).

### 1.3 Code-only GET branches

| Branch | HTTP outcome | Scenario |
| ------ | ------------ | -------- |
| `Failed` with NULL `terminal_error_code` | 200 `{ "state": "Failed", "terminal_error_code": "internal_error" }` | S12-006 |
| Unrecognized `state` string | 404 empty body | S12-010 |
| `Completed` with corrupt/missing R2 envelope | 200 `{ "state": "Completed" }` (no `result`) | S12-002…S12-004 |

## 2. `POST /control/support/lookup`

Operator diagnostic dump by `request_reference` across **all** installations. Auth: `requireOperator` → `{"error":"unauthorized"}` (not the taxonomy envelope).

### 2.1 Reference normalization (support lookup)

Query param `reference` is **trimmed**, then normalized and validated (`support-purge.ts`). Whitespace-padded references succeed on lookup but 404 on the clinic GET — **intentional**: machine clients send exact references; operator tooling is forgiving (S12-042 vs S12-016).

### 2.2 Failure responses

| HTTP | `error` | When |
| ---- | ------- | ---- |
| 401 | `unauthorized` | Missing/wrong operator bearer or clinic AAT |
| 400 | `missing_reference` | Absent or blank-after-trim query param |
| 400 | `invalid_reference` | Fails Crockford `XXXX-XXXX` after normalize |
| 404 | `not_found` | No journal row (JSON body — unlike clinic GET 404) |
| 500 | `missing_r2_binding` | Worker misconfiguration (R2 unbound) |

Lookup writes **no** `control_audit` row (read-only).

## 3. Control-plane route dispatch

`worker.ts` admits control routes when `isControlRoute(pathname)` and **either** `method === "POST"` **or** (`method === "GET"` **and** `isQuotaInspectRoute(pathname)`). Every other `/control/*` path on GET returns plain-text `Not Found` before auth (S12-055). The claim that "`/control/*` is POST-only" is accurate for support lookup but **overbroad** — quota inspect is GET-only inside the dispatcher (`quota-inspect.ts` rejects non-GET with 405).

## 4. `GET /control/installations/{id}/quota` (quota inspect)

Operator read of D1 entitlement + Quota DO state. `verbose=true` adds `maps` (idempotency, jti_replay, admitted_requests, credited_requests) capped at **500 entries per map** (`capMap`); counts in the top-level body are never truncated.

### 4.1 Success response (200)

Top-level keys: `installation_id`, `bound_installation_id`, `period_bounds`, `period_counters` (`requests_used`, `tokens_used`, `cost_used`, `in_flight`), `entitlement` (D1 row or **null** when installation exists but entitlement row is missing — S12-061), `remaining` (null when entitlement null), `idempotency_keys`, `jti_replay_entries`, `admitted_requests`, `credited_requests`. Optional `maps` when `verbose=true`.

`inspectRPC` runs ephemeral sweeps **in memory only** — no DO `storage.put` (S12-065).

### 4.2 Failure responses

Dispatch pre-filters with the same regex as the handler (`QUOTA_INSPECT_PATTERN`), so **`400 invalid_route` is unreachable via HTTP** (A-01; direct handler invocation only). Reachable failures:

| HTTP | `error` | When |
| ---- | ------- | ---- |
| 401 | `unauthorized` | Missing/wrong operator bearer (runs before method check — S12-063) |
| 405 | `method_not_allowed` | POST to this path (worker admits POST to control dispatch; handler rejects — S12-064) |
| 404 | `installation_not_found` | No `installation` row — DO never contacted (S12-062) |
| 503 | `quota_do_unavailable` | DO binding missing or stub fetch failed/non-OK |

### 4.3 Support lookup envelope fallback (code-only)

When `payload_pointer` is NULL, support lookup still reads R2 at the derived key `request/{request_id}/envelope` (`support/index.ts`). The clinic GET returns `{ "state": "Completed" }` without `result` for the same row (S12-052 vs S12-002).

## 5. Dashboard SQL functions (no HTTP route)

Exported from `dashboards/index.ts`; scenarios S12-066…S12-072 call them directly against migrated D1.

| Function | Reads | Contract |
| -------- | ----- | -------- |
| `dashboardQuotaRejectionRate(db, now?)` | `platform_counter` (LIKE `%quota_exhausted%`) ÷ in-window `ai_request` count | Numerator is a **lower bound** — only cron-flushed tallies appear (S12-068); 90-day window matches `JOURNAL_HORIZON_DAYS` |
| `dashboardRepairRateByCapability(db, now?)` | `ai_attempt` LEFT JOIN `ai_request` | Repair attempts ÷ Completed+Failed requests per `capability_id`; Cancelled/in-flight excluded (S12-071); `{}` when denominator empty (S12-072) |

Other exports (`dashboardAvgAttemptLatencyByProvider`, `dashboardValidationFailureByPromptVersion`, `dashboardFallbackRateByProvider`, `dashboardCostPerCapabilityPerInstallation`, `runAllDashboardQueries`) follow the same SQL-contract pattern but have no catalog scenarios in this chapter.

---

## Scenario S12-001 — GET Completed returns the R2 envelope result

| Field | Content |
|-------|---------|
| ID | S12-001 |
| Journey setup | Stage 11 Completed settlement: `POST /v1/requests` with AAT(I0), `x-idempotency-key: idem-s12-001`, `x-capability-version: 1.0.0`, body `{"capability_id":"clinic.visit_summary","user_intent":"Summarize the visit for the chart.","context":{"org":"org-aaa","branch":"branch-aaa","visit.chief_complaint@v1":"Patient reports headache for 3 days."}}`; consume the SSE stream to `completed`; drain `waitUntil` so `writePostResponseDetail` persists attempts, `usage_event`, and the R2 envelope at `request/{RID}/envelope`. Capture REF from the `accepted` event. |
| Action | `GET /v1/requests/8K2P-9QRT` with header `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200. Body has exactly two top-level keys: `{"state":"Completed","result":{...}}` where `result` is the envelope's `CanonicalResult` with every field: `finalContent`, `usage.input`, `usage.output`, `usage.cached`, `providerModel.provider`, `providerModel.model`, `finishReason`, `providerRequestId`, `timing.queue_ms`, `timing.provider_ms`, `timing.total_ms`. No `attempts`, no `envelope`, no `request_id`, no `installation_id`. |
| Side effects | None. D1 read-only (`ai_request` by `request_reference`); one R2 `get` on `payload_pointer`. No writes to D1/DO/R2. |
| Code reference | `ai-platform/src/worker.ts:1412-1420` — fetch GET Completed branch; `ai-platform/src/journal/index.ts:487-507` — getRequest Completed + envelope read |

## Scenario S12-002 — GET Completed with NULL payload_pointer omits result

| Field | Content |
|-------|---------|
| ID | S12-002 |
| Journey setup | S12-001 settled row. [SEED] `UPDATE ai_request SET payload_pointer = NULL WHERE request_reference = '8K2P-9QRT'` — justified: the NULL-pointer branch is otherwise unreachable on a settled row because `persistPostResponseDetail` always writes the pointer; this simulates the documented partial-write window. |
| Action | `GET /v1/requests/8K2P-9QRT` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body exactly `{"state":"Completed"}` — no `result` key. |
| Side effects | None. No R2 read attempted (pointer is NULL). |
| Code reference | `ai-platform/src/journal/index.ts:488-490` — getRequest `payload_pointer === null` → `resultMissing`; `ai-platform/src/worker.ts:1418-1419` — `{ state: "Completed" }` without result |

## Scenario S12-003 — GET Completed with missing R2 object omits result

| Field | Content |
|-------|---------|
| ID | S12-003 |
| Journey setup | S12-001 settled row. [SEED] delete the R2 object at `request/{RID}/envelope` while leaving `payload_pointer` set — justified: simulates R2 purge/eviction racing the journal row (retention deletes R2 before D1). |
| Action | `GET /v1/requests/8K2P-9QRT` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body exactly `{"state":"Completed"}` — R2 `get` returned null → `resultMissing`. |
| Side effects | One R2 `get` (miss). No writes. |
| Code reference | `ai-platform/src/journal/index.ts:492-495` — getRequest R2 miss → `resultMissing` |

## Scenario S12-004 — GET Completed with corrupt envelope JSON omits result

| Field | Content |
|-------|---------|
| ID | S12-004 |
| Journey setup | S12-001 settled row. [SEED] overwrite R2 object `request/{RID}/envelope` with the bytes `not-json{` — justified: covers the `JSON.parse` throw branch, unreachable from well-formed settlement writes. |
| Action | `GET /v1/requests/8K2P-9QRT` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body exactly `{"state":"Completed"}` — parse failure is swallowed into `resultMissing`. |
| Side effects | One R2 `get`. No writes. |
| Code reference | `ai-platform/src/journal/index.ts:497-506` — getRequest try/catch around envelope parse |

## Scenario S12-005 — GET Failed returns terminal_error_code

| Field | Content |
|-------|---------|
| ID | S12-005 |
| Journey setup | Stage 11 Failed settlement: `POST /v1/requests` with AAT(I0) routed so the provider chain fails terminally (e.g. all candidates excluded → `provider_unavailable`); consume SSE to `failed`. Row has `state='Failed'`, `terminal_error_code='provider_unavailable'`. Capture REF2. |
| Action | `GET /v1/requests/<REF2>` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body exactly `{"state":"Failed","terminal_error_code":"provider_unavailable"}`. |
| Side effects | None. D1 read-only; no R2 read (Failed never reads the envelope). |
| Code reference | `ai-platform/src/worker.ts:1426-1431` — fetch GET Failed branch; `ai-platform/src/journal/index.ts:509-519` — getRequest Failed mapping |

## Scenario S12-006 — GET Failed with NULL terminal_error_code falls back to internal_error

| Field | Content |
|-------|---------|
| ID | S12-006 |
| Journey setup | S12-005 failed row. [SEED] `UPDATE ai_request SET terminal_error_code = NULL WHERE request_reference = '<REF2>'` — justified: C3-R3 (`recordTerminalState`) makes Failed-without-code unreachable through the pipeline; this covers the defensive `?: "internal_error"` branch. |
| Action | `GET /v1/requests/<REF2>` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body exactly `{"state":"Failed","terminal_error_code":"internal_error"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/journal/index.ts:510-514` — getRequest NULL/empty code fallback |

## Scenario S12-007 — GET Cancelled

| Field | Content |
|-------|---------|
| ID | S12-007 |
| Journey setup | Stage 10 cancelled stream: `POST /v1/requests` with AAT(I0), abort the client connection mid-stream; settlement records `state='Cancelled'`, `terminal_error_code=NULL`. Capture REF3. |
| Action | `GET /v1/requests/<REF3>` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body exactly `{"state":"Cancelled"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1438` — fetch GET terminal fallthrough; `ai-platform/src/journal/index.ts:521-523` — getRequest Cancelled mapping |

## Scenario S12-008 — GET AwaitingContext

| Field | Content |
|-------|---------|
| ID | S12-008 |
| Journey setup | [SEED] insert an `ai_request` row for I0 with `state='AwaitingContext'` (all NOT NULL columns populated: `request_id='01JZS12AWAIT0000000000008'`, `request_reference='3VBM-7KPD'`, capability `clinic.visit_summary@1.0.0`, `idempotency_key='idem-s12-008'`, `trace_id` ULID, timestamps) — justified: `AwaitingContext` is conversational-only (`canReachAwaitingContext`), and the worker registers only the `single_shot` manifest `clinic.visit_summary@1.0.0`, so no live pipeline can produce this state. |
| Action | `GET /v1/requests/3VBM-7KPD` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body exactly `{"state":"AwaitingContext"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1433-1435` — fetch GET AwaitingContext branch; `ai-platform/src/journal/index.ts:525-527` — getRequest AwaitingContext mapping |

## Scenario S12-009 — GET in-flight request returns pending:true

| Field | Content |
|-------|---------|
| ID | S12-009 |
| Journey setup | `POST /v1/requests` with AAT(I0); capture REF4 from the SSE `accepted` event and issue the GET immediately, before terminal settlement lands (row is in a non-terminal state such as `Accepted`/`Invoking`/`Streaming`). If timing proves flaky, [SEED] a row with `state='Invoking'` — justified only as a determinism fallback; prefer the live race. |
| Action | `GET /v1/requests/<REF4>` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200, body `{"state":"<non-terminal state>","pending":true}` — e.g. `{"state":"Accepted","pending":true}`. All six non-terminal states (`Accepted`, `Composing`, `Invoking`, `Streaming`, `Validating`, `Repairing`) map identically. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1422-1424` — fetch GET pending branch; `ai-platform/src/journal/index.ts:529-532` — getRequest non-terminal mapping |

## Scenario S12-010 — GET row with unknown state string returns 404

| Field | Content |
|-------|---------|
| ID | S12-010 |
| Journey setup | [SEED] insert an `ai_request` row for I0 with `state='Bogus'`, `request_reference='6HND-4WQC'` — justified: covers the defensive `isTransitionState` guard; unreachable through `journalTransition`/`recordTerminalState`. |
| Action | `GET /v1/requests/6HND-4WQC` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 404, **empty body** — `getRequest` returns `{found:false}` for an unrecognized state. |
| Side effects | None. |
| Code reference | `ai-platform/src/journal/index.ts:529-534` — getRequest unknown-state fallthrough to `found:false`; `ai-platform/src/worker.ts:1405-1408` — 404 on not-found |

## Scenario S12-011 — GET unknown well-formed reference returns empty 404

| Field | Content |
|-------|---------|
| ID | S12-011 |
| Journey setup | I0 enrolled; valid AAT(I0). No journal row for `AAAA-BBBB`. |
| Action | `GET /v1/requests/AAAA-BBBB` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 404, **empty body** (`new Response(null, {status:404})`) — no `{"error":"not_found"}` JSON. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1405-1408` — not-found 404; `ai-platform/src/journal/index.ts:475-477` — getRequest no row |

## Scenario S12-012 — GET malformed reference returns empty 404 (no format validation)

| Field | Content |
|-------|---------|
| ID | S12-012 |
| Journey setup | I0 enrolled; valid AAT(I0). |
| Action | `GET /v1/requests/SHORT` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 404, empty body. The GET route never runs `isValidRequestReference`; the malformed string simply matches no row. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1396-1408` — raw reference passed to getRequest; `ai-platform/src/journal/index.ts:466-477` — normalize + lookup only |

## Scenario S12-013 — GET /v1/requests/ (empty reference) returns 404 before auth

| Field | Content |
|-------|---------|
| ID | S12-013 |
| Journey setup | None (no installation, no token needed). |
| Action | `GET /v1/requests/` with **no** `Authorization` header |
| Expected outcome | HTTP 404, empty body — the empty-reference check runs **before** `authenticateGetRequest`, so no 401 and no taxonomy body. |
| Side effects | None. No D1 read. |
| Code reference | `ai-platform/src/worker.ts:1380-1383` — empty-reference 404 |

## Scenario S12-014 — GET /v1/requests (no trailing slash) falls to route-not-found

| Field | Content |
|-------|---------|
| ID | S12-014 |
| Journey setup | None. |
| Action | `GET /v1/requests` with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 404 with plain-text body `Not Found` — pathname lacks the `/v1/requests/` prefix, so the GET branch is skipped and the catch-all runs. Distinct from S12-013's empty-body 404. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1376-1379` — prefix match; `ai-platform/src/worker.ts:1440-1444` — route_not_found |

## Scenario S12-015 — GET reference normalization (case + I/L/O ambiguity)

| Field | Content |
|-------|---------|
| ID | S12-015 |
| Journey setup | S12-001 settled row whose stored reference contains `1` and `0` (re-run settlement until REF matches, or [SEED] settle then `UPDATE ai_request SET request_reference='81S0-1MNP'` — justified: reference minting is random; the normalization contract is what is under test). |
| Action | `GET /v1/requests/8iso-lmnp` (lowercase, `i`→`1`, `o`→`0`, `l`→`1`) with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 200 with the same body as S12-001 — `normalizeRequestReference` uppercases and maps `I`/`L`→`1`, `O`→`0` before the D1 lookup. |
| Side effects | None. |
| Code reference | `ai-platform/src/journal/index.ts:466` — getRequest normalization; `ai-platform/src/reference.ts:20-26` — normalizeRequestReference |

## Scenario S12-016 — GET whitespace-padded path reference returns 404

| Field | Content |
|-------|---------|
| ID | S12-016 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/%208K2P-9QRT` (leading space, URL-encoded) with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 404, empty body — unlike support lookup, the GET path does **not** trim; normalization is case/substitution only, so the padded string matches nothing. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1380` — raw `url.pathname.slice`; `ai-platform/src/reference.ts:20-26` — no trim in normalizeRequestReference |

## Scenario S12-017 — Cross-installation GET returns empty 404

| Field | Content |
|-------|---------|
| ID | S12-017 |
| Journey setup | S12-001 settled row owned by I0. I1 enrolled with its own key; mint valid AAT(I1) (`iss='inst-bbb-002'`). |
| Action | `GET /v1/requests/8K2P-9QRT` with `Authorization: Bearer <AAT(I1)>` |
| Expected outcome | HTTP 404, empty body — installation mismatch is indistinguishable from an unknown reference (no cross-tenant leak, no 403). |
| Side effects | None. |
| Code reference | `ai-platform/src/journal/index.ts:480-485` — installationId scope → `found:false`; `ai-platform/src/worker.ts:1396-1408` — principal passed as scope |

## Scenario S12-018 — Non-GET method on /v1/requests/{ref} returns route-not-found

| Field | Content |
|-------|---------|
| ID | S12-018 |
| Journey setup | S12-001 settled row. |
| Action | `POST /v1/requests/8K2P-9QRT` with `Authorization: Bearer <AAT(I0)>` (repeat with `DELETE`) |
| Expected outcome | HTTP 404, plain-text body `Not Found` — the lookup branch requires `request.method === "GET"`; `/v1/requests/<ref>` is not the POST live route and not a control route. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1376-1379` — method gate; `ai-platform/src/worker.ts:1440-1444` — route_not_found |

## Scenario S12-019 — GET without Authorization header returns 401 unauthenticated

| Field | Content |
|-------|---------|
| ID | S12-019 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with no `Authorization` header |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated","request_reference":"<fresh-ref>","trace_id":"<fresh-ulid>","retry_safe":true}`. `getRequest` is never reached. |
| Side effects | None (guard-rejection metric recorded in-isolate only). |
| Code reference | `ai-platform/src/journal/index.ts:550-554` — missing header; `ai-platform/src/worker.ts:1389-1393` — `liveHttpStatusForCode ?? 401` mapping; `ai-platform/src/journal/index.ts:580-588` — getRequestAuthErrorBody |

## Scenario S12-020 — GET with non-Bearer scheme returns 401

| Field | Content |
|-------|---------|
| ID | S12-020 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with header `Authorization: Token abc123` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated","request_reference":"<fresh-ref>","trace_id":"<fresh-ulid>","retry_safe":true}` — header must start with literal `Bearer `. |
| Side effects | None. |
| Code reference | `ai-platform/src/journal/index.ts:551-554` — `startsWith("Bearer ")` check |

## Scenario S12-021 — GET with empty Bearer token returns 401

| Field | Content |
|-------|---------|
| ID | S12-021 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with header `Authorization: Bearer ` (trailing whitespace only) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — token trims to length 0. |
| Side effects | None. |
| Code reference | `ai-platform/src/journal/index.ts:556-560` — empty-token check |

## Scenario S12-022 — GET with structurally malformed token returns 401

| Field | Content |
|-------|---------|
| ID | S12-022 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with `Authorization: Bearer <token>` where the token is, in variants: (a) `abc.def` (two segments); (b) three segments with non-base64url header (`!!!.e30.sig`); (c) header decodes to non-JSON; (d) payload decodes to non-JSON; (e) payload JSON missing required claims (`iss`/`aud`/`sub`/`org`/`branch`/`role`/`jti`/`ver`/`scopes`/`iat`/`exp`). |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` for every variant — all structural failures collapse to `unauthenticated` before any D1 read. |
| Side effects | None. |
| Code reference | `ai-platform/src/identity/index.ts:238-278` — segment/base64/JSON/claims guards in EnrolledKeyVerifier.verify |

## Scenario S12-023 — GET with wrong alg header returns 401

| Field | Content |
|-------|---------|
| ID | S12-023 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with a token whose header is `{"alg":"HS256","kid":"key-aaa-001"}` (AAT helper with header override) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — only `EdDSA` is accepted. |
| Side effects | None. |
| Code reference | `ai-platform/src/identity/index.ts:257-259` — alg check |

## Scenario S12-024 — GET with missing or empty kid returns 401

| Field | Content |
|-------|---------|
| ID | S12-024 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with a token whose header omits `kid` (variant: `"kid":""`) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/identity/index.ts:261-263` — kid check |

## Scenario S12-025 — GET with wrong audience returns 401

| Field | Content |
|-------|---------|
| ID | S12-025 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT(I0) minted with `aud='other-service'` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — audience must be `ai-platform`; rejected before any config load. |
| Side effects | None. |
| Code reference | `ai-platform/src/identity/index.ts:282-285` — aud check; `ai-platform/src/journal/index.ts:563-569` — verify context audience |

## Scenario S12-026 — GET with expired token returns 401

| Field | Content |
|-------|---------|
| ID | S12-026 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT(I0) minted with `exp = now - 120` (beyond the 60 s clock skew) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/identity/index.ts:287-291` — exp/skew check |

## Scenario S12-027 — GET with future iat beyond skew returns 401

| Field | Content |
|-------|---------|
| ID | S12-027 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT(I0) minted with `iat = now + 120`, `exp = iat + 300` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `iat - 60 > now` rejects. |
| Side effects | None. |
| Code reference | `ai-platform/src/identity/index.ts:287-291` — iat/skew check |

## Scenario S12-028 — GET with token lifetime over 600 s returns 401

| Field | Content |
|-------|---------|
| ID | S12-028 |
| Journey setup | S12-001 settled row. |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT(I0) minted with `iat = now`, `exp = now + 900` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `exp - iat > MAX_AAT_LIFETIME_SECONDS (600)`. |
| Side effects | None. |
| Code reference | `ai-platform/src/identity/index.ts:293-295` — lifetime cap; `ai-platform/src/identity/index.ts:41` — MAX_AAT_LIFETIME_SECONDS |

## Scenario S12-029 — GET with unknown installation (iss) returns 401

| Field | Content |
|-------|---------|
| ID | S12-029 |
| Journey setup | S12-001 settled row. No `installation` row for `inst-ghost-999`. |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT minted with `iss='inst-ghost-999'` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `loadConfig("installations", iss)` misses (ConfigCacheMissError). |
| Side effects | One D1 read on `installation` (miss). |
| Code reference | `ai-platform/src/identity/index.ts:297-305` — installation load miss |

## Scenario S12-030 — GET with unknown kid returns 401

| Field | Content |
|-------|---------|
| ID | S12-030 |
| Journey setup | S12-001 settled row. No `installation_key` row for `key-ghost-999`. |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT(I0) whose header `kid='key-ghost-999'` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `loadConfig("keys", kid)` misses. |
| Side effects | D1 reads on `installation` (hit) and `installation_key` (miss). |
| Code reference | `ai-platform/src/identity/index.ts:307-315` — key load miss |

## Scenario S12-031 — GET with revoked key returns 401

| Field | Content |
|-------|---------|
| ID | S12-031 |
| Journey setup | S12-001 settled row. Stage 3 key revocation: `UPDATE installation_key SET revoked_at = <now> WHERE key_id='key-aaa-001'` (or the Stage 3 revoke-key control route), then clear the config cache so the next verify re-reads D1. |
| Action | `GET /v1/requests/8K2P-9QRT` with a validly signed AAT(I0) under `kid='key-aaa-001'` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `revoked_at != null` rejects before signature verification. |
| Side effects | D1 reads on `installation` and `installation_key`. |
| Code reference | `ai-platform/src/identity/index.ts:317-319` — revoked_at check |

## Scenario S12-032 — GET with key outside its validity window returns 401

| Field | Content |
|-------|---------|
| ID | S12-032 |
| Journey setup | S12-001 settled row. [SEED] `UPDATE installation_key SET valid_until = <past ISO> WHERE key_id='key-aaa-001'` (variant: `valid_from` in the future) — justified: validity windows are set at enroll/rotate time (Stage 3); direct update is the deterministic trigger. Clear config cache. |
| Action | `GET /v1/requests/8K2P-9QRT` with validly signed AAT(I0) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `now >= valid_until` (or `now < valid_from`). |
| Side effects | D1 reads on `installation` and `installation_key`. |
| Code reference | `ai-platform/src/identity/index.ts:321-323` — window check; `ai-platform/src/identity/index.ts:212-232` — isKeyWithinValidityWindow |

## Scenario S12-033 — GET with key bound to a different installation returns 401

| Field | Content |
|-------|---------|
| ID | S12-033 |
| Journey setup | I0 and I1 enrolled. Mint a token with `iss='inst-aaa-001'` but header `kid='key-bbb-002'` (I1's key), signed with I1's private key. |
| Action | `GET /v1/requests/8K2P-9QRT` with that token |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `keyRow.installation_id !== payload.iss` binds key ownership before verification. |
| Side effects | D1 reads on `installation` and `installation_key`. |
| Code reference | `ai-platform/src/identity/index.ts:326-328` — iss/kid binding check |

## Scenario S12-034 — GET with invalid signature returns 401

| Field | Content |
|-------|---------|
| ID | S12-034 |
| Journey setup | S12-001 settled row. Mint AAT(I0) then tamper one character in the payload segment (signature no longer matches). |
| Action | `GET /v1/requests/8K2P-9QRT` with the tampered token |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `crypto.subtle.verify` returns false. |
| Side effects | D1 reads on `installation` and `installation_key`. |
| Code reference | `ai-platform/src/identity/index.ts:340-350` — Ed25519 verify |

## Scenario S12-035 — GET with suspended installation returns 403 installation_suspended

| Field | Content |
|-------|---------|
| ID | S12-035 |
| Journey setup | S12-001 settled row. Stage 3 suspend: `POST /control/installations/inst-aaa-001/suspend` with the operator bearer (or [SEED] `UPDATE installation SET status='suspended'`); clear config cache so the status re-reads. |
| Action | `GET /v1/requests/8K2P-9QRT` with a validly signed AAT(I0) |
| Expected outcome | HTTP **403**, body `{"code":"installation_suspended","request_reference":"<fresh-ref>","trace_id":"<fresh-ulid>","retry_safe":false}` — `liveHttpStatusForCode("installation_suspended")` = 403 overrides the 401 default. |
| Side effects | D1 reads on `installation` and `installation_key`. Restore with Stage 3 resume for later scenarios. |
| Code reference | `ai-platform/src/identity/index.ts:356-358` — suspended check; `ai-platform/src/worker.ts:1390-1393` — status mapping; `ai-platform/src/errors.ts:35-40` — taxonomy entry 403 |

## Scenario S12-036 — GET with non-active, non-suspended installation status returns 401

| Field | Content |
|-------|---------|
| ID | S12-036 |
| Journey setup | S12-001 settled row. [SEED] `UPDATE installation SET status='deleted' WHERE installation_id='inst-aaa-001'` — justified: the `deleted` status is written by Stage 3 delete flows; direct update avoids cascading side effects. Clear config cache. |
| Action | `GET /v1/requests/8K2P-9QRT` with validly signed AAT(I0) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — fail-closed: only `active` authenticates; `suspended` is the sole 403 carve-out. |
| Side effects | D1 reads on `installation` and `installation_key`. Restore status afterwards. |
| Code reference | `ai-platform/src/identity/index.ts:359-361` — non-active fallthrough |

## Scenario S12-037 — GET with unknown token contract version returns 401

| Field | Content |
|-------|---------|
| ID | S12-037 |
| Journey setup | S12-001 settled row. No `token_contract` row for `ver='v99'`. |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT(I0) minted with `ver='v99'` |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `loadConfig("token_contracts", ver)` misses after signature verification. |
| Side effects | D1 reads on `installation`, `installation_key`, `token_contract` (miss). |
| Code reference | `ai-platform/src/identity/index.ts:363-371` — contract load miss |

## Scenario S12-038 — GET with retired token contract returns 401

| Field | Content |
|-------|---------|
| ID | S12-038 |
| Journey setup | S12-001 settled row. Stage 3 token-contract retire for `v1` (or [SEED] `UPDATE token_contract SET retired_at = <now> WHERE ver='v1'`); clear config cache. |
| Action | `GET /v1/requests/8K2P-9QRT` with validly signed AAT(I0, `ver='v1'`) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — `retired_at != null` rejects. |
| Side effects | D1 reads on `installation`, `installation_key`, `token_contract`. Restore `retired_at` afterwards. |
| Code reference | `ai-platform/src/identity/index.ts:373-375` — retired contract check |

## Scenario S12-039 — Revoked key still authenticates within the config-cache TTL

| Field | Content |
|-------|---------|
| ID | S12-039 |
| Journey setup | S12-001 settled row. Warm the isolate cache: one successful GET with AAT(I0) (caches `keys:key-aaa-001` for `CONFIG_CACHE_TTL_MS`, default 30 000 ms). Then Stage 3 revocation: `UPDATE installation_key SET revoked_at = <now> WHERE key_id='key-aaa-001'` **without** clearing the cache. |
| Action | Within the TTL, `GET /v1/requests/8K2P-9QRT` with AAT(I0) |
| Expected outcome | HTTP 200 with the S12-001 body — the cached (pre-revocation) key row still authenticates. Staleness is bounded by the 30 s isolate TTL. |
| Side effects | No D1 read on `installation_key` (cache hit). |
| Code reference | `ai-platform/src/config-cache/index.ts:89-104` — consult TTL; `ai-platform/src/config-cache/index.ts:26` — DEFAULT_CONFIG_CACHE_TTL_MS; `ai-platform/src/journal/index.ts:548` — default cache is isolateConfigCache |

## Scenario S12-040 — Revoked key rejected after the config-cache TTL expires

| Field | Content |
|-------|---------|
| ID | S12-040 |
| Journey setup | Continue S12-039. Run the test isolate with `CONFIG_CACHE_TTL_MS=500` (documented `[vars]` override) and wait > 500 ms after revocation (or wait out the default 30 s). |
| Action | `GET /v1/requests/8K2P-9QRT` with AAT(I0) |
| Expected outcome | HTTP 401, body `{"code":"unauthenticated",...,"retry_safe":true}` — the expired entry is evicted, D1 is re-read, and `revoked_at` now rejects. |
| Side effects | D1 re-read on `installation_key` after TTL expiry. |
| Code reference | `ai-platform/src/config-cache/index.ts:96-101` — expiry eviction; `ai-platform/src/config-cache/index.ts:31-40` — resolveConfigCacheTtlMs |

## Scenario S12-041 — Support lookup happy path returns every field

| Field | Content |
|-------|---------|
| ID | S12-041 |
| Journey setup | S12-001 settled row (Completed, one `ai_attempt` row, R2 envelope present, within `diagnostic_30d` retention for `clinic.visit_summary@1.0.0`). |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with header `Authorization: Bearer <OPERATOR_BEARER_TOKEN>`; no body |
| Expected outcome | HTTP 200, body keys exactly `request`, `attempts`, `envelope`. `request`: `requestId`=RID, `requestReference`=`8K2P-9QRT`, `installationId`=`inst-aaa-001`, `actorId`, `branchId`, `capabilityId`=`clinic.visit_summary`, `capabilityVersion`=`1.0.0`, `promptArtifactHash`, `state`=`Completed`, `createdAt`, `updatedAt`, `completedAt`, `terminalErrorCode`=null, `traceId`, `payloadPointer`=`request/{RID}/envelope`. `attempts[0]`: `attemptNo`=1, `provider`, `model`, `outcome`, `latencyMs`, `tokensIn`, `tokensOut`, `cost`, `providerRequestId`, `errorCode`. `envelope`: `{context, prompt, attempts, result}` from R2; `envelope.result` deep-equals S12-001's `result`. |
| Side effects | D1 read (`ai_request` LEFT JOIN `ai_attempt`); one R2 `get`. **No** `control_audit` row (verify count unchanged). |
| Code reference | `ai-platform/src/control/support-purge.ts:14-54` — handleSupportLookup; `ai-platform/src/support/index.ts:99-174` — supportLookup |

## Scenario S12-042 — Support lookup normalizes mixed-case ambiguous references

| Field | Content |
|-------|---------|
| ID | S12-042 |
| Journey setup | S12-015's row (stored reference `81S0-1MNP`). |
| Action | `POST /control/support/lookup?reference=%208iso-lmnp%20` (whitespace-padded, lowercase, ambiguous chars) with the operator bearer |
| Expected outcome | HTTP 200 with the full S12-041 body — lookup **trims** then normalizes (`I`/`L`→`1`, `O`→`0`, uppercase) before validating and querying. Contrast with S12-016 (GET does not trim). |
| Side effects | Same reads as S12-041. |
| Code reference | `ai-platform/src/control/support-purge.ts:29-37` — trim + normalize + validate; `ai-platform/src/support/index.ts:103` — supportLookup re-normalizes |

## Scenario S12-043 — Support lookup without operator bearer returns 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S12-043 |
| Journey setup | S12-001 settled row. |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with no `Authorization` header |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — control-plane error shape, **not** the taxonomy body used by the GET route. |
| Side effects | None. Handler exits before any D1/R2 read. |
| Code reference | `ai-platform/src/control/support-purge.ts:19-22` — requireOperator; `ai-platform/src/control/http.ts:4-9` — unauthorized(); `ai-platform/src/control/http.ts:33-41` — requireOperator |

## Scenario S12-044 — Support lookup with wrong bearer or clinic AAT returns 401

| Field | Content |
|-------|---------|
| ID | S12-044 |
| Journey setup | S12-001 settled row. |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with (a) `Authorization: Bearer wrong-token`, (b) `Authorization: Bearer <AAT(I0)>` — a valid clinic AAT is not the operator secret |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}` for both — constant-time compare against `OPERATOR_BEARER_TOKEN` fails. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/auth.ts:27-52` — createSecretOperatorAuth timing-safe compare |

## Scenario S12-045 — Support lookup without reference param returns 400 missing_reference

| Field | Content |
|-------|---------|
| ID | S12-045 |
| Journey setup | None beyond operator token. |
| Action | `POST /control/support/lookup` (no query string) with the operator bearer |
| Expected outcome | HTTP 400, body exactly `{"error":"missing_reference"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/support-purge.ts:28-32` — missing/blank reference check |

## Scenario S12-046 — Support lookup with blank or whitespace reference returns 400 missing_reference

| Field | Content |
|-------|---------|
| ID | S12-046 |
| Journey setup | None beyond operator token. |
| Action | `POST /control/support/lookup?reference=` and `POST /control/support/lookup?reference=%20%20` with the operator bearer |
| Expected outcome | HTTP 400, body exactly `{"error":"missing_reference"}` for both — empty-after-trim is `missing_reference`, not `invalid_reference`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/support-purge.ts:29-32` — `raw.trim() === ""` branch |

## Scenario S12-047 — Support lookup with malformed reference returns 400 invalid_reference

| Field | Content |
|-------|---------|
| ID | S12-047 |
| Journey setup | None beyond operator token. |
| Action | `POST /control/support/lookup?reference=SHORT` with the operator bearer (variants: `AAAA-BBB` too short; `AAAA-BBBBB` too long; `AAAA!BBBB` bad charset) |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_reference"}` — normalized value fails the Crockford `XXXX-XXXX` pattern. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/support-purge.ts:34-37` — isValidRequestReference gate; `ai-platform/src/reference.ts:2` — REFERENCE_PATTERN |

## Scenario S12-048 — Support lookup with unknown well-formed reference returns 404 not_found

| Field | Content |
|-------|---------|
| ID | S12-048 |
| Journey setup | No journal row for `AAAA-BBBB`. |
| Action | `POST /control/support/lookup?reference=AAAA-BBBB` with the operator bearer |
| Expected outcome | HTTP 404, body exactly `{"error":"not_found"}` — unlike the clinic GET, lookup 404s carry a JSON error body. |
| Side effects | One D1 read (no rows). No R2 read. |
| Code reference | `ai-platform/src/control/support-purge.ts:45-47` — not_found reject; `ai-platform/src/support/index.ts:110-112` — zero rows → found:false |

## Scenario S12-049 — Support lookup reads across installations

| Field | Content |
|-------|---------|
| ID | S12-049 |
| Journey setup | S12-001 settled row owned by I0. [SEED] `UPDATE ai_request SET installation_id='inst-bbb-002' WHERE request_reference='8K2P-9QRT'` — justified: mirrors the doc's cross-installation probe without running a second full settlement; restore afterwards. |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with the operator bearer |
| Expected outcome | HTTP 200; `request.installationId` = `inst-bbb-002` — the lookup SQL has **no** installation predicate, unlike the clinic GET (S12-017). |
| Side effects | Same reads as S12-041. Restore `installation_id` afterwards. |
| Code reference | `ai-platform/src/support/index.ts:84-93` — LOOKUP_SQL `WHERE r.request_reference = ?` only |

## Scenario S12-050 — Support lookup of in-flight request returns empty attempts and null envelope

| Field | Content |
|-------|---------|
| ID | S12-050 |
| Journey setup | Same live in-flight race as S12-009: `POST /v1/requests` with AAT(I0), hang FakeAdapter, capture REF4 from SSE `accepted`, then lookup immediately (row is non-terminal, no `ai_attempt` rows yet, `payload_pointer` NULL, no R2 object). If timing proves flaky, [SEED] a row with `state='Invoking'` — justified only as a determinism fallback; prefer the live race. |
| Action | `POST /control/support/lookup?reference=<REF4>` with the operator bearer |
| Expected outcome | HTTP 200. `request.state` is the in-flight state, `completedAt`=null, `payloadPointer`=null. `attempts` = `[]` (LEFT JOIN rows with NULL `attempt_no` are skipped). `envelope` = null — fallback key `request/{RID}/envelope` misses in R2. |
| Side effects | D1 read; one R2 `get` (miss) on the derived fallback key. |
| Code reference | `ai-platform/src/support/index.ts:134-151` — attempt filtering; `ai-platform/src/support/index.ts:163-170` — fallback pointer + R2 miss |

## Scenario S12-051 — Support lookup outside diagnostic retention returns null envelope

| Field | Content |
|-------|---------|
| ID | S12-051 |
| Journey setup | S12-001 settled row. [SEED] `UPDATE ai_request SET completed_at = <now − 31 days>, created_at = <now − 31 days> WHERE request_reference='8K2P-9QRT'` — justified: `clinic.visit_summary@1.0.0` is `diagnostic_30d`; waiting 31 days is not an option. R2 object left in place. |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with the operator bearer |
| Expected outcome | HTTP 200. `request` and `attempts` fully populated; `envelope` = null — outside the diagnostic horizon the R2 read is skipped entirely (age measured from `completed_at ?? created_at`). |
| Side effects | D1 read only — **no** R2 `get` (assert via R2 spy/log absence). |
| Code reference | `ai-platform/src/support/index.ts:153-167` — retention gate; `ai-platform/src/retention/index.ts:86-94` — isWithinDiagnosticRetention; `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json:75` — diagnostic_30d |

## Scenario S12-052 — Support lookup falls back to derived envelope key when payload_pointer is NULL

| Field | Content |
|-------|---------|
| ID | S12-052 |
| Journey setup | S12-001 settled row. [SEED] `UPDATE ai_request SET payload_pointer=NULL WHERE request_reference='8K2P-9QRT'` while leaving the R2 object at `request/{RID}/envelope` — justified: covers the `?? envelopeKey(request_id)` fallback, unreachable when settlement always writes the pointer. |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with the operator bearer |
| Expected outcome | HTTP 200 with `envelope` fully populated — the derived key hits R2 even though `request.payloadPointer` is null. (Contrast S12-002: the clinic GET returns no `result` here.) |
| Side effects | D1 read; one R2 `get` (hit) on the derived key. |
| Code reference | `ai-platform/src/support/index.ts:164` — `first.payload_pointer ?? envelopeKey(first.request_id)` |

## Scenario S12-053 — Support lookup with missing R2 object returns null envelope

| Field | Content |
|-------|---------|
| ID | S12-053 |
| Journey setup | S12-001 settled row within retention. [SEED] delete the R2 object at `request/{RID}/envelope` (retention-style R2 delete without the D1 delete). |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with the operator bearer |
| Expected outcome | HTTP 200. `request` and `attempts` populated; `envelope` = null. |
| Side effects | D1 read; one R2 `get` (miss). |
| Code reference | `ai-platform/src/support/index.ts:165-169` — R2 miss leaves envelope null |

## Scenario S12-054 — Support lookup writes no control_audit row

| Field | Content |
|-------|---------|
| ID | S12-054 |
| Journey setup | S12-001 settled row. Record `SELECT COUNT(*) FROM control_audit` before. |
| Action | `POST /control/support/lookup?reference=8K2P-9QRT` with the operator bearer |
| Expected outcome | HTTP 200 (S12-041 body). `control_audit` count is unchanged — lookup is read-only diagnostics; only mutating control routes audit. |
| Side effects | **Must not** insert into `control_audit`; no D1/DO/R2 writes of any kind. |
| Code reference | `ai-platform/src/control/support-purge.ts:14-54` — handleSupportLookup contains no writeAudit call (contrast handleInstallationPurge at `ai-platform/src/control/support-purge.ts:81-86`) |

## Scenario S12-055 — GET method on the support-lookup route never reaches the handler

| Field | Content |
|-------|---------|
| ID | S12-055 |
| Journey setup | S12-001 settled row. |
| Action | `GET /control/support/lookup?reference=8K2P-9QRT` with the operator bearer |
| Expected outcome | HTTP 404, plain-text body `Not Found` — the worker dispatches control routes only for POST (or GET on the quota-inspect route), so the lookup handler never runs and no `{"error":...}` JSON is produced. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1354-1362` — control-route method gate; `ai-platform/src/control/index.ts:80` — SUPPORT_LOOKUP_PATTERN; `ai-platform/src/worker.ts:1440-1444` — route_not_found |

## Scenario S12-056 — Quota inspect of a fresh installation returns zeroed DO state

| Field | Content |
|-------|---------|
| ID | S12-056 |
| Journey setup | Stage 3 enroll: installation `inst-ccc-003` with entitlement row (`plan='standard'`, `status='active'`, `period_start='2026-09-01T00:00:00.000Z'`, `period_end='2026-10-01T00:00:00.000Z'`, `request_quota=1000`, `token_budget=500000`, `cost_budget=25.0`). No traffic yet — the Quota DO for this installation has never been touched. |
| Action | `GET /control/installations/inst-ccc-003/quota` with the operator bearer |
| Expected outcome | HTTP 200, body: `{"installation_id":"inst-ccc-003","bound_installation_id":null,"period_bounds":null,"period_counters":{"requests_used":0,"tokens_used":0,"cost_used":0,"in_flight":0},"entitlement":{"plan":"standard","status":"active","period_start":"2026-09-01T00:00:00.000Z","period_end":"2026-10-01T00:00:00.000Z","request_quota":1000,"token_budget":500000,"cost_budget":25.0},"remaining":{"requests":1000,"tokens":500000,"cost":25.0},"idempotency_keys":0,"jti_replay_entries":0,"admitted_requests":0,"credited_requests":0}`. No `maps` key (no `verbose=true`). |
| Side effects | DO `inspectRPC` runs the ephemeral sweep **in memory only** — no `storage.put`; D1 reads on `installation` and `entitlement`. No writes anywhere. |
| Code reference | `ai-platform/src/control/quota-inspect.ts:19-141` — handleInstallationQuotaGet; `ai-platform/src/quota-do/index.ts:615-622` — inspectRPC; `ai-platform/src/quota-do/index.ts:185-192` — initialState |

## Scenario S12-057 — Quota inspect after settled traffic reflects counters and maps counts

| Field | Content |
|-------|---------|
| ID | S12-057 |
| Journey setup | S12-001's full journey on I0: one Completed settlement (credit applied: `requests_used=1`, `tokens_used`>0, `cost_used`>0, `in_flight` back to 0; one idempotency entry in `completed` state; one `creditedRequests` entry; DO bound to `inst-aaa-001`; period bounds set from the entitlement snapshot). |
| Action | `GET /control/installations/inst-aaa-001/quota` with the operator bearer |
| Expected outcome | HTTP 200. `bound_installation_id`=`inst-aaa-001`; `period_bounds` matches the entitlement snapshot period; `period_counters.requests_used`=1, `tokens_used`/`cost_used` equal the settled usage, `in_flight`=0; `idempotency_keys`=1, `jti_replay_entries`=1, `admitted_requests`=0, `credited_requests`=1; `remaining.requests`=`request_quota − 1` etc. |
| Side effects | Read-only (in-memory sweep only). |
| Code reference | `ai-platform/src/control/quota-inspect.ts:88-121` — response assembly; `ai-platform/src/quota-do/index.ts:462-541` — creditRPC counter effects |

## Scenario S12-058 — Quota inspect shows an in-flight admission

| Field | Content |
|-------|---------|
| ID | S12-058 |
| Journey setup | Drive the Quota DO for I0 directly via its stub (`POST https://quota-do.internal/rpc` with `{"kind":"admission","jti":"jti-s12-058","installationId":"inst-aaa-001","idempotencyKey":"idem-s12-058","requestReference":"5TPX-8RND","entitlement":<snapshot>}`) and do **not** credit — justified: there is no deterministic HTTP way to hold a live request mid-flight; the DO RPC is the same call the pipeline makes (Stage 8). |
| Action | `GET /control/installations/inst-aaa-001/quota` with the operator bearer |
| Expected outcome | HTTP 200. `period_counters.in_flight`=1, `admitted_requests`=1, `idempotency_keys`=1 (state `admitted`), `jti_replay_entries`=1, `credited_requests`=0; `requests_used` unchanged. |
| Side effects | The admission RPC itself writes DO state (setup); the inspect is read-only. |
| Code reference | `ai-platform/src/quota-do/index.ts:359-461` — admissionRPC; `ai-platform/src/control/quota-inspect.ts:119` — admitted_requests count |

## Scenario S12-059 — Quota inspect verbose=true includes the state maps

| Field | Content |
|-------|---------|
| ID | S12-059 |
| Journey setup | S12-057's settled I0 state. |
| Action | `GET /control/installations/inst-aaa-001/quota?verbose=true` with the operator bearer |
| Expected outcome | HTTP 200. All S12-057 fields plus `maps`: `{"idempotency":{"idem-s12-001":{...}},"jti_replay":{"<jti>":{"expiresAt":...}},"admitted_requests":{},"credited_requests":{"<requestId>":{"expiresAt":...}},"truncated":false}`. With `verbose` absent or any value other than `true`, `maps` is omitted. |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/control/quota-inspect.ts:123-139` — verbose branch; `ai-platform/src/control/quota-inspect.ts:5-17` — capMap |

## Scenario S12-060 — Quota inspect verbose truncates maps beyond 500 entries

| Field | Content |
|-------|---------|
| ID | S12-060 |
| Journey setup | Seed the I0 Quota DO with 501 idempotency entries via 501 direct `admission` RPCs with distinct `idempotencyKey`/`jti` (expensive but deterministic; quota must admit them — use a high-quota entitlement snapshot). |
| Action | `GET /control/installations/inst-aaa-001/quota?verbose=true` with the operator bearer |
| Expected outcome | HTTP 200. `maps.idempotency` contains exactly 500 entries; `maps.truncated`=true. Non-verbose GET still reports `idempotency_keys`=501 (counts are never truncated). |
| Side effects | Setup RPCs write DO state; inspect is read-only. |
| Code reference | `ai-platform/src/control/quota-inspect.ts:5-17` — capMap 500-entry cap |

## Scenario S12-061 — Quota inspect with installation but no entitlement row returns nulls

| Field | Content |
|-------|---------|
| ID | S12-061 |
| Journey setup | [SEED] `INSERT INTO installation (...) VALUES ('inst-ddd-004', ...)` with **no** matching `entitlement` row — justified: enroll always writes both; this covers the `entitlement ? … : null` defensive branch. |
| Action | `GET /control/installations/inst-ddd-004/quota` with the operator bearer |
| Expected outcome | HTTP 200. `entitlement`=null, `remaining`=null; DO-derived fields present and zeroed (fresh DO). |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/control/quota-inspect.ts:55-68` — entitlement query; `ai-platform/src/control/quota-inspect.ts:98-116` — null branches |

## Scenario S12-062 — Quota inspect of unknown installation returns 404 installation_not_found

| Field | Content |
|-------|---------|
| ID | S12-062 |
| Journey setup | No `installation` row for `inst-ghost-999`. |
| Action | `GET /control/installations/inst-ghost-999/quota` with the operator bearer |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}` — the DO is never contacted. |
| Side effects | One D1 read (miss). No DO call. |
| Code reference | `ai-platform/src/control/quota-inspect.ts:45-53` — installation existence check |

## Scenario S12-063 — Quota inspect without/with wrong operator bearer returns 401

| Field | Content |
|-------|---------|
| ID | S12-063 |
| Journey setup | S12-057's I0 state. |
| Action | `GET /control/installations/inst-aaa-001/quota` (a) with no `Authorization` header, (b) with `Authorization: Bearer <AAT(I0)>` |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` for both — auth runs before the method check and before any D1/DO access. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/quota-inspect.ts:24-27` — requireOperator first |

## Scenario S12-064 — POST to the quota-inspect route returns 405 method_not_allowed

| Field | Content |
|-------|---------|
| ID | S12-064 |
| Journey setup | S12-057's I0 state. |
| Action | `POST /control/installations/inst-aaa-001/quota` with the operator bearer |
| Expected outcome | HTTP 405, body exactly `{"error":"method_not_allowed"}` — the worker's control gate lets POST through to the dispatcher, and the handler rejects non-GET. |
| Side effects | None. |
| Code reference | `ai-platform/src/worker.ts:1354-1358` — POST admitted to control dispatch; `ai-platform/src/control/quota-inspect.ts:29-31` — method check |

## Scenario S12-065 — inspectRPC sweeps expired ephemeral entries in memory without persisting

| Field | Content |
|-------|---------|
| ID | S12-065 |
| Journey setup | DO-direct scenario (no HTTP route can inject `now`): seed the I0 Quota DO with one admission at time T via direct `admission` RPC with `now: T`; then call `inspectRPC(storage, T + EPHEMERAL_HORIZON_MS + 1)` (7 200 000 ms horizon) — or equivalently `stub.fetch` with `{"kind":"inspect","now":T+7_200_001}` since `GatewayObject.fetch` honors an injectable `now`. |
| Action | Direct DO RPC `{"kind":"inspect","now":<T+7_200_001>}` against the I0 stub |
| Expected outcome | Response `{"kind":"inspect","state":{...}}` where the abandoned admission is swept: `admitted_requests`=0, `in_flight` decremented to 0, and the matching idempotency entry flipped to `state:"failed"` with a renewed expiry. A subsequent plain inspect shows the same swept values **only if** a later RPC persisted them — `inspectRPC` itself never calls `storage.put` (verify DO storage directly: `state` key unchanged by the inspect call). |
| Side effects | **Must not** write DO storage. |
| Code reference | `ai-platform/src/quota-do/index.ts:615-622` — inspectRPC (no storage.put); `ai-platform/src/quota-do/index.ts:208-231` — sweepAbandonedAdmissions; `ai-platform/src/worker.ts:1264-1268` — injectable now |

## Scenario S12-066 — dashboardQuotaRejectionRate returns counter/requests ratio (D1-contract)

| Field | Content |
|-------|---------|
| ID | S12-066 |
| Journey setup | SQL-contract scenario (no HTTP route). Seed D1 directly: 4 `ai_request` rows with `created_at` inside the 90-day window; 2 `platform_counter` rows with `dimension_set='{"error_code":"quota_exhausted","installation_id":"inst-aaa-001"}'`, `time_bucket` in-window, `count`=2 and `count`=1. |
| Action | `await dashboardQuotaRejectionRate(db, new Date("2026-09-05T00:00:00Z"))` |
| Expected outcome | Returns `(2+1)/4 = 0.75`. The numerator matches any `dimension_set` LIKE `'%quota_exhausted%'`; both tables are bounded to the same window. |
| Side effects | Read-only SELECT. |
| Code reference | `ai-platform/src/dashboards/index.ts:166-190` — dashboardQuotaRejectionRate |

## Scenario S12-067 — dashboardQuotaRejectionRate returns 0 for an empty window (NULLIF guard)

| Field | Content |
|-------|---------|
| ID | S12-067 |
| Journey setup | SQL-contract scenario. Freshly migrated D1: no `ai_request` rows, no `platform_counter` rows (variant: counter rows present but zero `ai_request` rows in-window). |
| Action | `await dashboardQuotaRejectionRate(db)` |
| Expected outcome | Returns `0` — `NULLIF(count, 0)` yields NULL rate, and `?? 0` coalesces. No division-by-zero, no throw. |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/dashboards/index.ts:183-189` — NULLIF + `?? 0` |

## Scenario S12-068 — dashboardQuotaRejectionRate numerator is a lower bound (unflushed tallies invisible)

| Field | Content |
|-------|---------|
| ID | S12-068 |
| Journey setup | SQL-contract scenario. Seed 10 in-window `ai_request` rows and **no** `platform_counter` rows — simulating quota rejections that occurred in isolates whose in-memory tallies were never flushed by the cron isolate (`flushRejectionCounters`). |
| Action | `await dashboardQuotaRejectionRate(db)` |
| Expected outcome | Returns `0` even though rejections "happened" — the function documents the numerator as a lower bound; only D1-flushed counts appear. This pins the documented approximation, not a bug. |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/dashboards/index.ts:156-165` — lower-bound contract comment; `ai-platform/src/rate-limit` flushRejectionCounters (cron-only flush) |

## Scenario S12-069 — dashboardQuotaRejectionRate excludes out-of-window rows from both sides

| Field | Content |
|-------|---------|
| ID | S12-069 |
| Journey setup | SQL-contract scenario. Seed: 2 in-window `ai_request` rows; 5 `ai_request` rows with `created_at` = now − 91 days; 1 in-window `platform_counter` `quota_exhausted` row (`count`=1); 4 counter rows with `time_bucket` = now − 91 days (`count`=10 each). |
| Action | `await dashboardQuotaRejectionRate(db, now)` |
| Expected outcome | Returns `1/2 = 0.5` — the 91-day-old requests and counters (beyond `JOURNAL_HORIZON_DAYS`=90) are excluded from denominator and numerator alike, so the aged counters cannot inflate the rate. |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/dashboards/index.ts:170-186` — windowStart binds; `ai-platform/src/retention/index.ts:15` — JOURNAL_HORIZON_DAYS |

## Scenario S12-070 — dashboardRepairRateByCapability counts synthetic repair attempts (D1-contract)

| Field | Content |
|-------|---------|
| ID | S12-070 |
| Journey setup | SQL-contract scenario. Seed in-window: one `ai_request` row (`capability_id='clinic.visit_summary'`, `state='Completed'`, `created_at` in-window) with two `ai_attempt` rows — `attempt_no=1, outcome='terminal_failure'` and `attempt_no=2, outcome='repair'` — plus one `Failed` request (same capability) with no attempts. |
| Action | `await dashboardRepairRateByCapability(db, now)` |
| Expected outcome | Returns `{"clinic.visit_summary": 0.5}` — 1 repair attempt ÷ 2 distinct Completed+Failed requests for the capability. |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/dashboards/index.ts:71-98` — dashboardRepairRateByCapability |

## Scenario S12-071 — dashboardRepairRateByCapability excludes Cancelled and in-flight requests

| Field | Content |
|-------|---------|
| ID | S12-071 |
| Journey setup | SQL-contract scenario. Seed in-window: one `Completed` request (capability `clinic.visit_summary`) with one `repair` attempt; one `Cancelled` request (same capability) with one `repair` attempt; one `Invoking` request (same capability) with one `repair` attempt. |
| Action | `await dashboardRepairRateByCapability(db, now)` |
| Expected outcome | Returns `{"clinic.visit_summary": 1.0}` — only the Completed row enters the denominator (`COUNT(DISTINCT r.request_id)` over `state IN ('Completed','Failed')`); the Cancelled and in-flight rows and their attempts are excluded entirely. |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/dashboards/index.ts:84-88` — state filter + LEFT JOIN |

## Scenario S12-072 — dashboardRepairRateByCapability returns {} for an empty window

| Field | Content |
|-------|---------|
| ID | S12-072 |
| Journey setup | SQL-contract scenario. Freshly migrated D1 (variant: only `ai_request` rows older than 90 days). |
| Action | `await dashboardRepairRateByCapability(db, now)` |
| Expected outcome | Returns `{}` — the GROUP BY yields no rows; the empty object is the documented contract, not a stub or an error. |
| Side effects | Read-only. |
| Code reference | `ai-platform/src/dashboards/index.ts:64-70` — empty-window contract; `ai-platform/src/dashboards/index.ts:93-97` — result assembly |

## Doc-drift observations

1. **[FIXED — D-17]** `installation_suspended` is documented as HTTP **403** in [§1.1](#11-failure-responses) (was incorrectly grouped under 401 in orientation doc §1).
2. **[FIXED — D-17]** Quota-inspect route and dashboard functions documented in [§4](#4-get-controlinstallationsidquota-quota-inspect) and [§5](#5-dashboard-sql-functions-no-http-route); scenarios S12-056…S12-072.
3. **[FIXED — D-17]** Control dispatch nuance documented in [§3](#3-control-plane-route-dispatch) — GET only for quota inspect, not all `/control/*`.
4. **[FIXED — D-17]** Reference trim asymmetry documented in [§1.2](#12-reference-normalization-clinic-get) and [§2.1](#21-reference-normalization-support-lookup).
5. **[FIXED — D-17]** Two distinct GET 404 bodies documented in [§1.1](#11-failure-responses).
6. **[FIXED — D-17]** Code-only branches catalogued in [§1.3](#13-code-only-get-branches), [§4.3](#43-support-lookup-envelope-fallback-code-only), and entitlement-null in [§4.1](#41-success-response-200).
7. **[FIXED — D-09]** Quota-inspect failure table omits unreachable `400 invalid_route` — dispatch pre-filter; see [§4.2](#42-failure-responses).
8. **Doc §3 (`record_ai_acceptance`) is clinic-side Supabase RPC**, not AI-platform code — outside this catalog's automatable surface; noted here for completeness only.
9. **No drift found** on: installation-scope 404 for cross-tenant GET; freshly minted `request_reference` in GET auth-failure bodies; lookup writing no `control_audit` row.

## Non-automatable notes

1. **`500 missing_r2_binding` (support lookup)** — `@cloudflare/vitest-pool-workers` always provides the R2 binding from the test wrangler config; the branch is reachable only by calling `handleSupportLookup` directly with a bindings object lacking `R2`, which is a unit test of the handler, not a production-faithful HTTP journey.
2. **`503 quota_do_unavailable` (quota inspect)** — requires the DO stub fetch to throw or return non-OK; with a real DO namespace in the test pool the inspect RPC always succeeds. Reachable only with a stubbed `DO` binding (unit-level), not via the real worker.
3. **`400 invalid_route` (quota inspect)** — unreachable through the worker: the same regex (`QUOTA_INSPECT_PATTERN`) gates both `isControlRoute`/`dispatchControlRequest` and the handler's re-parse, so no HTTP request can pass the gate and fail the handler's match.
4. **Config-cache TTL scenarios (S12-039/S12-040)** are automatable but time-sensitive: use `CONFIG_CACHE_TTL_MS` set to a few hundred milliseconds in the test environment rather than waiting out the 30 s default; the shared module-scope `isolateConfigCache` also means test ordering must avoid cross-test cache pollution (clear the cache between unrelated auth scenarios — but *not* between S12-039's warm and revoke steps).
5. **Isolate-identity claim** (GET and POST share the same module-scope `isolateConfigCache` object) is a code-identity property, not HTTP-observable — same limitation the orientation doc records as unprobeable.
6. **S12-060 (verbose truncation)** is automatable but slow (501 direct DO admissions); consider marking it as an extended/slow suite case.
7. **S12-009 (pending in-flight) and S12-050 (support lookup of in-flight)** prefer a live race (GET/lookup between `accepted` and settlement, with FakeAdapter hung); if the test runner proves too fast/flaky, the documented [SEED] fallback (insert a row in `Invoking`) preserves the assertion at the cost of journey fidelity.
