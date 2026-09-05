# Stage 01 — Token contract baseline

Source files read:
- `ai-platform/src/control/token-contract.ts` (begin-rotation + retire handlers)
- `ai-platform/src/control/auth.ts` (`createSecretOperatorAuth`)
- `ai-platform/src/control/http.ts` (`reject`, `ok`, `requireOperator`, `parseJsonBody`)
- `ai-platform/src/control/audit.ts` (`writeAudit` — note: token-contract handlers do **not** use this helper; they write `control_audit` inside the atomic D1 batch)
- `ai-platform/src/control/types.ts`
- `ai-platform/src/control/index.ts` (`TOKEN_CONTRACT_PATTERN`, `dispatchControlRequest`)
- `ai-platform/src/identity/index.ts` (`EnrolledKeyVerifier` — `ver` claim enforcement, consumer side)
- `ai-platform/src/config-cache/index.ts` (`token_contracts` reader key, isolate cache TTL)
- `ai-platform/src/worker.ts` (control-route method gating, 404 fallthrough)
- `ai-platform/src/errors.ts` (taxonomy entry + error body for `unauthenticated`)
- `ai-platform/migrations/20260803120000_token_contract.sql` (table + seed)
- `docs/architecture/ai-platform/data-journey/03-stage-1-token-contract-baseline.md` (orientation only)

Conventions used throughout:
- Operator credentials: `OPERATOR_BEARER_TOKEN = "op-secret-token-7f3c9a"`, `OPERATOR_ID = "platform-operator"` (matches wrangler `[vars]` convention).
- Control-plane base: `http://localhost:8787`.
- The seeded state after migrations is exactly one `token_contract` row: `ver='1'`, `added_at='2026-08-03T00:00:00.000Z'`, `retired_at=NULL`, `changed_by='seed'`.
- Consumer-side scenarios drive `POST /v1/requests` end-to-end; identity (Stage 9's guard, pipeline stage 2) is where the `ver` claim is checked against `token_contract`. AATs are produced by the test AAT-minting helper with full claim control over an installation created by the Stage 3 enrollment happy path.
- The isolate `ConfigCache` caches `token_contracts:{ver}` for `CONFIG_CACHE_TTL_MS` (default 30 000 ms). Every scenario that mutates `token_contract` and then verifies an AAT sets `CONFIG_CACHE_TTL_MS=0` in the test environment so each verify re-reads D1 (see `## Non-automatable notes`).

## Scenario S01-001 — Migration seed establishes the ver=1 baseline

| Field | Content |
|-------|---------|
| ID | S01-001 |
| Journey setup | Apply all D1 migrations to a fresh database (the real migration chain, including `20260803120000_token_contract.sql`). No control-plane calls. |
| Action | D1 read: `SELECT ver, added_at, retired_at, changed_by FROM token_contract` |
| Expected outcome | Exactly one row: `ver='1'`, `added_at='2026-08-03T00:00:00.000Z'`, `retired_at=NULL`, `changed_by='seed'`. This is the Stage 0 handoff — begin-rotation did not create `ver=1`. |
| Side effects | None (read-only assertion). `control_audit` contains no `token_contract_*` rows. |
| Code reference | ai-platform/migrations/20260803120000_token_contract.sql:L1-L10 — table DDL + seed INSERT |

## Scenario S01-002 — begin-rotation without Authorization header is rejected

| Field | Content |
|-------|---------|
| ID | S01-002 |
| Journey setup | S01-001 (seeded baseline). |
| Action | `POST /control/token-contract/begin-rotation` with header `content-type: application/json`, body `{"ver":"2"}`, **no** `Authorization` header. |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}` (control-plane shape — **not** the taxonomy `unauthenticated` body). |
| Side effects | `token_contract` unchanged (only seed row). No `control_audit` row written — auth failure precedes the batch. |
| Code reference | ai-platform/src/control/http.ts:L32-L41 — `requireOperator`; ai-platform/src/control/token-contract.ts:L21-L24 — auth gate in `handleTokenContractBeginRotation` |

## Scenario S01-003 — begin-rotation with wrong bearer secret is rejected

| Field | Content |
|-------|---------|
| ID | S01-003 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/begin-rotation` with `authorization: Bearer op-secret-token-WRONG`, `content-type: application/json`, body `{"ver":"2"}`. |
| Expected outcome | HTTP 401, body `{"error":"unauthorized"}`. The constant-time compare fails and `resolve` returns null. |
| Side effects | No `token_contract` write; no `control_audit` row. |
| Code reference | ai-platform/src/control/auth.ts:L33-L49 — `resolve` + `timingSafeEqualString` |

## Scenario S01-004 — A clinic AAT is not an operator credential

| Field | Content |
|-------|---------|
| ID | S01-004 |
| Journey setup | S01-001; Stage 3 enrollment happy path for installation `inst-4c1d9e20-7a1b-4f0e-9c3d-2b8a6e5f10aa`; AAT minted via the test helper with claims `iss=inst-4c1d9e20-7a1b-4f0e-9c3d-2b8a6e5f10aa`, `aud="ai-platform"`, `sub="staff-0001"`, `org="org-0001"`, `branch="branch-0001"`, `role="doctor"`, `scopes=["ai.visit_summary"]`, `jti="s01-004-jti"`, `iat=<now>`, `exp=<now+300>`, `ver="1"`, signed with the enrolled Ed25519 key. |
| Action | `POST /control/token-contract/begin-rotation` with `authorization: Bearer <that AAT compact JWS>`, `content-type: application/json`, body `{"ver":"2"}`. Repeat against `POST /control/token-contract/retire` with body `{"ver":"1"}`. |
| Expected outcome | HTTP 401 `{"error":"unauthorized"}` on both routes. The operator bearer is a shared secret string, not a JWT; any well-formed AAT fails the string compare. |
| Side effects | None. `token_contract` still holds only the seed row; `control_audit` empty of token-contract actions. |
| Code reference | ai-platform/src/control/auth.ts:L40-L48 — bearer slice + timing-safe compare |

## Scenario S01-005 — retire without / with wrong bearer is rejected

| Field | Content |
|-------|---------|
| ID | S01-005 |
| Journey setup | S01-001. |
| Action | (a) `POST /control/token-contract/retire`, no `Authorization` header, body `{"ver":"1"}`. (b) Same with `authorization: Bearer op-secret-token-WRONG`. |
| Expected outcome | Both: HTTP 401 `{"error":"unauthorized"}`. |
| Side effects | `token_contract.ver='1'` row untouched (`retired_at` stays NULL); no `control_audit` row. |
| Code reference | ai-platform/src/control/token-contract.ts:L76-L79 — auth gate in `handleTokenContractRetire` |

## Scenario S01-006 — Malformed Authorization schemes are rejected

| Field | Content |
|-------|---------|
| ID | S01-006 |
| Journey setup | S01-001. |
| Action | Three requests to `POST /control/token-contract/begin-rotation`, body `{"ver":"2"}`: (a) `authorization: bearer op-secret-token-7f3c9a` (lowercase scheme); (b) `authorization: Bearer` (scheme only, no token); (c) `authorization: Bearer    ` (scheme + whitespace only). |
| Expected outcome | All three: HTTP 401 `{"error":"unauthorized"}`. (a) fails the case-sensitive `startsWith("Bearer ")` check; (b) fails the prefix check; (c) trims to an empty token and is rejected. |
| Side effects | None. |
| Code reference | ai-platform/src/control/auth.ts:L37-L44 — scheme prefix + empty-token guards |

## Scenario S01-007 — Wrong HTTP method on token-contract routes falls through to 404

| Field | Content |
|-------|---------|
| ID | S01-007 |
| Journey setup | S01-001. |
| Action | `GET /control/token-contract/begin-rotation` with a valid `authorization: Bearer op-secret-token-7f3c9a` header. Also `DELETE /control/token-contract/retire` with the same header. |
| Expected outcome | HTTP 404 with plain-text body `Not Found` (not JSON). The worker gates control dispatch to `POST` (plus `GET` only for the quota-inspect route), so non-POST token-contract requests fall through the entire router. Auth is never evaluated. |
| Side effects | None. |
| Code reference | ai-platform/src/worker.ts:L1353-L1373 — method gate on `isControlRoute`; ai-platform/src/worker.ts:L1440-L1444 — `route_not_found` fallthrough |

## Scenario S01-008 — Unknown token-contract action and trailing slash are 404

| Field | Content |
|-------|---------|
| ID | S01-008 |
| Journey setup | S01-001. |
| Action | (a) `POST /control/token-contract/rotate` with valid operator bearer, body `{"ver":"2"}`. (b) `POST /control/token-contract/retire/` (trailing slash) with valid operator bearer, body `{"ver":"1"}`. |
| Expected outcome | Both: HTTP 404 plain-text `Not Found`. `TOKEN_CONTRACT_PATTERN` (`^/control/token-contract/(begin-rotation|retire)$`) matches neither, so `isControlRoute` is false and the request falls through the router. The `reject(400, "invalid_route")` inside the dispatcher's token-contract branch is unreachable dead code (the regex already constrains the action). |
| Side effects | None. |
| Code reference | ai-platform/src/control/index.ts:L76-L77 — `TOKEN_CONTRACT_PATTERN`; ai-platform/src/control/index.ts:L165-L174 — dispatch branch (note unreachable `invalid_route`); ai-platform/src/worker.ts:L1440-L1444 — fallthrough |

## Scenario S01-009 — begin-rotation with malformed JSON body

| Field | Content |
|-------|---------|
| ID | S01-009 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, `content-type: application/json`, body `{"ver": ` (truncated JSON). |
| Expected outcome | HTTP 400, body `{"error":"invalid_json"}`. `parseJsonBody` catches the parse throw and rejects before any validation. |
| Side effects | None; no `control_audit` row. |
| Code reference | ai-platform/src/control/http.ts:L43-L49 — `parseJsonBody`; ai-platform/src/control/token-contract.ts:L26-L29 |

## Scenario S01-010 — begin-rotation with missing ver key

| Field | Content |
|-------|---------|
| ID | S01-010 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_ver"}`. `body.ver?.trim()` is `undefined`, which is falsy. |
| Side effects | None. |
| Code reference | ai-platform/src/control/token-contract.ts:L31-L34 — `ver` presence guard |

## Scenario S01-011 — begin-rotation with empty ver string

| Field | Content |
|-------|---------|
| ID | S01-011 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":""}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_ver"}`. |
| Side effects | None. Seed row unchanged. |
| Code reference | ai-platform/src/control/token-contract.ts:L31-L34 |

## Scenario S01-012 — begin-rotation with whitespace-only ver

| Field | Content |
|-------|---------|
| ID | S01-012 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":"   "}`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_ver"}`. `.trim()` reduces the value to the empty string. |
| Side effects | None. |
| Code reference | ai-platform/src/control/token-contract.ts:L31-L34 — trim-then-check |

## Scenario S01-013 — begin-rotation with non-string ver throws (no graceful 400)

| Field | Content |
|-------|---------|
| ID | S01-013 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":2}` (JSON number). |
| Expected outcome | The handler throws `TypeError: body.ver.trim is not a function` — `?.` only guards null/undefined, so a number reaches `.trim()`. There is no `invalid_ver` response for wrong-type input; in the vitest pool the `fetch` promise rejects (in production, an unhandled 500). This documents actual code behavior, not a taxonomy outcome. |
| Side effects | None — the throw happens before the D1 batch. No `control_audit` row. |
| Code reference | ai-platform/src/control/token-contract.ts:L31 — unguarded `.trim()` on a typed-but-unvalidated payload (`TokenContractBeginPayload.ver` is `string` at compile time only, ai-platform/src/control/types.ts:L65-L67) |

## Scenario S01-014 — begin-rotation of the already-live seed ver

| Field | Content |
|-------|---------|
| ID | S01-014 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":"1"}`. |
| Expected outcome | HTTP 409, body `{"error":"ver_already_exists"}`. The conditional INSERT writes 0 rows (`NOT EXISTS ... WHERE ver = '1'` fails); the post-batch probe finds the existing row and maps to `ver_already_exists`. |
| Side effects | No new `token_contract` row. **No `control_audit` row** — the audit INSERT is conditioned on the new-row fingerprint (`ver` + `added_at`), which does not exist when the guard fails. |
| Code reference | ai-platform/src/control/token-contract.ts:L43-L66 — atomic batch + `ver_already_exists` branch |

## Scenario S01-015 — retire with malformed JSON body

| Field | Content |
|-------|---------|
| ID | S01-015 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/retire` with valid operator bearer, body `not-json`. |
| Expected outcome | HTTP 400, body `{"error":"invalid_json"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/http.ts:L43-L49; ai-platform/src/control/token-contract.ts:L81-L84 |

## Scenario S01-016 — retire with missing / whitespace-only ver

| Field | Content |
|-------|---------|
| ID | S01-016 |
| Journey setup | S01-001. |
| Action | (a) `POST /control/token-contract/retire` with valid operator bearer, body `{}`. (b) Same route, body `{"ver":"  "}`. |
| Expected outcome | Both: HTTP 400, body `{"error":"invalid_ver"}`. |
| Side effects | None; `ver='1'` row untouched. |
| Code reference | ai-platform/src/control/token-contract.ts:L86-L89 |

## Scenario S01-017 — retire with non-string ver throws (no graceful 400)

| Field | Content |
|-------|---------|
| ID | S01-017 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/retire` with valid operator bearer, body `{"ver":1}` (JSON number). |
| Expected outcome | Handler throws `TypeError: body.ver.trim is not a function` (fetch promise rejects in the vitest pool; unhandled 500 in production). Same robustness gap as S01-013. |
| Side effects | None. |
| Code reference | ai-platform/src/control/token-contract.ts:L86 — unguarded `.trim()` |

## Scenario S01-018 — retire of a ver that was never inserted

| Field | Content |
|-------|---------|
| ID | S01-018 |
| Journey setup | S01-001. |
| Action | `POST /control/token-contract/retire` with valid operator bearer, body `{"ver":"never-existed"}`. |
| Expected outcome | HTTP 404, body `{"error":"ver_not_found"}`. The conditional UPDATE changes 0 rows; the post-batch probe finds no row and maps to `ver_not_found`. |
| Side effects | None. No `control_audit` row (audit INSERT conditioned on the `retired_at` fingerprint). |
| Code reference | ai-platform/src/control/token-contract.ts:L118-L126 — 0-changes probe + `ver_not_found` branch |

## Scenario S01-019 — retire of the sole live version is refused

| Field | Content |
|-------|---------|
| ID | S01-019 |
| Journey setup | S01-001 (only `ver='1'`, live). |
| Action | `POST /control/token-contract/retire` with valid operator bearer, body `{"ver":"1"}`. |
| Expected outcome | HTTP 409, body `{"error":"no_rotation_open"}`. The UPDATE's guard `(SELECT COUNT(*) ... WHERE retired_at IS NULL) >= 2` fails with only one live row; the post-batch probe finds the row with `retired_at IS NULL`, so it is neither not-found nor already-retired. |
| Side effects | `retired_at` on `ver='1'` stays NULL; `changed_by` stays `'seed'`. No `control_audit` row. |
| Code reference | ai-platform/src/control/token-contract.ts:L98-L106 — live-count guard; L127-L131 — `no_rotation_open` branch |

## Scenario S01-020 — begin-rotation happy path opens the ver=2 rotation

| Field | Content |
|-------|---------|
| ID | S01-020 |
| Journey setup | S01-001; auth, routing, and payload blockers cleared by S01-002…S01-014. |
| Action | `POST /control/token-contract/begin-rotation` with `authorization: Bearer op-secret-token-7f3c9a`, `content-type: application/json`, body `{"ver":"2"}`. |
| Expected outcome | HTTP 200, body `{"ver":"2"}` (exactly one key). |
| Side effects | D1: new `token_contract` row `ver='2'`, `added_at=<now ISO-8601>`, `retired_at=NULL`, `changed_by='platform-operator'` (the configured `OPERATOR_ID`, never the bearer string). Seed row `ver='1'` fully unchanged. One `control_audit` row: `operator_id='platform-operator'`, `action='token_contract_begin_rotation'`, `target='2'`, `before_pointer=NULL`, `after_pointer=NULL`, `recorded_at≈added_at`, `audit_id` a UUID. Both writes land in the same D1 batch. |
| Code reference | ai-platform/src/control/token-contract.ts:L36-L69 — batch INSERT + conditioned audit + `ok({ ver })` |

## Scenario S01-021 — begin-rotation while a rotation is already open

| Field | Content |
|-------|---------|
| ID | S01-021 |
| Journey setup | S01-020 (live set is now `{1, 2}`). |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":"3"}`. |
| Expected outcome | HTTP 409, body `{"error":"rotation_already_open"}`. The INSERT's live-count guard (`< 2`) fails; the post-batch probe finds no `ver='3'` row, so the handler distinguishes this from the duplicate case. |
| Side effects | No `ver='3'` row. Live set remains `{1, 2}`. No `control_audit` row for the failed call. |
| Code reference | ai-platform/src/control/token-contract.ts:L43-L67 — count guard + `rotation_already_open` branch |

## Scenario S01-022 — duplicate ver takes precedence over the open-rotation guard

| Field | Content |
|-------|---------|
| ID | S01-022 |
| Journey setup | S01-020 (live set `{1, 2}` — both guards would fail). |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":"2"}`. |
| Expected outcome | HTTP 409, body `{"error":"ver_already_exists"}` — **not** `rotation_already_open`. The post-batch probe checks row existence first, so the duplicate code wins when both conditions hold. |
| Side effects | None; no audit row. |
| Code reference | ai-platform/src/control/token-contract.ts:L59-L66 — existing-row check ordered before the count fallback |

## Scenario S01-023 — begin-rotation trims surrounding whitespace from ver

| Field | Content |
|-------|---------|
| ID | S01-023 |
| Journey setup | S01-020, then S01-027 (retire `ver='1'`) so the live set is `{2}` and one more rotation slot is open. (Alternatively run on a fresh database after S01-001 with body `{"ver":" 2 "}`; the behavior is identical.) |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":" 3 "}`. |
| Expected outcome | HTTP 200, body `{"ver":"3"}` — the trimmed value is what gets inserted and returned. |
| Side effects | `token_contract` row is `ver='3'` (no whitespace); audit `target='3'`. A subsequent `{"ver":"3"}` returns 409 `ver_already_exists` and `{"ver":" 3 "}` also returns 409 (trimmed before the duplicate check). |
| Code reference | ai-platform/src/control/token-contract.ts:L31 — `body.ver?.trim()` normalizes before insert |

## Scenario S01-024 — begin-rotation accepts a long ver string (no length guard)

| Field | Content |
|-------|---------|
| ID | S01-024 |
| Journey setup | Fresh database, S01-001 only (live set `{1}`, one slot open). |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":"2026-09-05-emergency-rotation-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}` (118 chars). |
| Expected outcome | HTTP 200, `{"ver":"2026-09-05-emergency-rotation-aaaa…"}`. The code performs no length or charset validation beyond non-empty-after-trim; the D1 `TEXT` primary key accepts the value. Boundary scenario documenting the absence of a length contract. |
| Side effects | Row inserted with the full 118-char `ver`; audit `target` equals the same string. |
| Code reference | ai-platform/src/control/token-contract.ts:L31-L48 — no length check; ai-platform/migrations/20260803120000_token_contract.sql:L2-L6 — `ver TEXT PRIMARY KEY` |

## Scenario S01-025 — Dual-accept window: AATs with ver=1 and ver=2 both pass identity

| Field | Content |
|-------|---------|
| ID | S01-025 |
| Journey setup | S01-020 (live set `{1, 2}`). Stage 3 enrollment happy path for installation `inst-4c1d9e20-7a1b-4f0e-9c3d-2b8a6e5f10aa` (status `active`, enrolled Ed25519 key `kid="key-2026-08"`). Stage 4 entitlement happy path for `clinic.visit_summary@1.0.0` so later guards do not mask the identity outcome. Mint AAT_V1 via the test helper (`ver="1"`, `iss=inst-4c1d9e20-…`, `aud="ai-platform"`, `sub="staff-0001"`, `org="org-0001"`, `branch="branch-0001"`, `role="doctor"`, `scopes=["ai.visit_summary"]`, `jti="s01-025-v1"`, `exp-iat=300`) and AAT_V2 identically except `ver="2"`, `jti="s01-025-v2"`. Test env sets `CONFIG_CACHE_TTL_MS=0`. |
| Action | `POST /v1/requests` with `authorization: Bearer <AAT_V1>`, `content-type: application/json`, `x-idempotency-key: s01-025-v1`, `x-capability-version: 1.0.0`, body `{"capability_id":"clinic.visit_summary","user_intent":"token-contract dual-accept probe"}`. Then the identical request with `authorization: Bearer <AAT_V2>`, `x-idempotency-key: s01-025-v2`. |
| Expected outcome | Neither response is HTTP 401 with taxonomy `code:"unauthenticated"` — identity (Stage 9's guard, pipeline stage 2) loads `token_contracts:1` and `token_contracts:2`, finds both rows with `retired_at=NULL`, and continues. Downstream outcome (SSE stream or a later guard code) is whatever Stages 3–8 produce; this scenario asserts only that the token-contract check passes for both versions during the overlap window. |
| Side effects | `token_contract` is **not** written by the request path (both rows unchanged). Request-path side effects (journal/attempt rows, SSE) belong to later stages' chapters. |
| Code reference | ai-platform/src/identity/index.ts:L363-L377 — `token_contracts` load + `retired_at` check; ai-platform/src/config-cache/index.ts:L232-L237 — `token_contracts` reader key |

## Scenario S01-026 — AAT carrying an unknown ver is rejected as unauthenticated

| Field | Content |
|-------|---------|
| ID | S01-026 |
| Journey setup | Same as S01-025 (live set `{1, 2}`). Mint AAT_MISSING identically to AAT_V1 except `ver="99"`, `jti="s01-026-missing"`. Signature, `iss`, `kid`, and time claims are all valid — the token-contract row is the only thing missing. |
| Action | `POST /v1/requests` with `authorization: Bearer <AAT_MISSING>`, `x-idempotency-key: s01-026-missing`, `x-capability-version: 1.0.0`, body `{"capability_id":"clinic.visit_summary","user_intent":"token-contract missing-ver probe"}`. |
| Expected outcome | HTTP 401 with taxonomy body `{"code":"unauthenticated","request_reference":<id>,"trace_id":<id>,"retry_safe":true}` (`retryable: "After re-mint"` maps to `retry_safe: true`). `loadConfig` raises `ConfigCacheMissError` for `token_contracts:99`, which the verifier maps to `unauthenticated`. This is Stage 9's identity rejection, triggered by Stage 1 state. |
| Side effects | A guard-rejection metric is recorded for `error_code="unauthenticated"` attributed to `inst-4c1d9e20-…` (signature verified before the contract load, so attribution is safe). No `token_contract` write. |
| Code reference | ai-platform/src/identity/index.ts:L363-L371 — miss → `rejectUnauthenticated`; ai-platform/src/errors.ts:L29-L34 — `unauthenticated` taxonomy entry; ai-platform/src/errors.ts:L217-L230 — `buildErrorBody` |

## Scenario S01-027 — retire happy path stamps ver=1

| Field | Content |
|-------|---------|
| ID | S01-027 |
| Journey setup | S01-020 (live set `{1, 2}`). |
| Action | `POST /control/token-contract/retire` with `authorization: Bearer op-secret-token-7f3c9a`, `content-type: application/json`, body `{"ver":"1"}`. |
| Expected outcome | HTTP 200, body `{"ver":"1","retired_at":"<ISO-8601 timestamp>"}` — exactly two keys; `retired_at` parses as a valid ISO timestamp ≈ now. |
| Side effects | D1: `token_contract.ver='1'` row updated — `retired_at` equals the response value, `changed_by='platform-operator'` (overwrites `'seed'`). `ver='2'` row untouched (`retired_at` NULL). One `control_audit` row: `action='token_contract_retire'`, `target='1'`, `operator_id='platform-operator'`, pointers NULL, written in the same batch as the UPDATE. Live count drops to 1. |
| Code reference | ai-platform/src/control/token-contract.ts:L92-L134 — atomic UPDATE + conditioned audit + `ok({ ver, retired_at })` |

## Scenario S01-028 — retire of an already-retired ver is a no-op conflict

| Field | Content |
|-------|---------|
| ID | S01-028 |
| Journey setup | S01-027 (`ver='1'` retired, `ver='2'` live). |
| Action | `POST /control/token-contract/retire` with valid operator bearer, body `{"ver":"1"}`. |
| Expected outcome | HTTP 409, body `{"error":"ver_already_retired"}`. The UPDATE's `retired_at IS NULL` predicate matches nothing; the post-batch probe finds the row with non-null `retired_at`. |
| Side effects | `retired_at` on `ver='1'` is **unchanged** (still the S01-027 timestamp — the failed retire does not re-stamp). No second `control_audit` row. |
| Code reference | ai-platform/src/control/token-contract.ts:L118-L129 — probe + `ver_already_retired` branch |

## Scenario S01-029 — Full path: retiring ver=1 breaks previously valid AATs at identity

| Field | Content |
|-------|---------|
| ID | S01-029 |
| Journey setup | The canonical Stage 1 journey: S01-001 seed → Stage 3 enrollment happy path + Stage 4 entitlement happy path for `inst-4c1d9e20-7a1b-4f0e-9c3d-2b8a6e5f10aa` → mint AAT_V1 (`ver="1"`, `jti="s01-029-v1"`, helper-controlled claims as in S01-025) → `POST /v1/requests` with AAT_V1 succeeds past identity (not 401/`unauthenticated`; S01-025 proves this state) → S01-020 begin-rotation `ver='2'` → S01-027 retire `ver='1'`. Test env `CONFIG_CACHE_TTL_MS=0` so the next verify re-reads D1. Do **not** re-mint AAT_V1. |
| Action | `POST /v1/requests` with `authorization: Bearer <AAT_V1>` (the original token), `content-type: application/json`, `x-idempotency-key: s01-029-after-retire`, `x-capability-version: 1.0.0`, body `{"capability_id":"clinic.visit_summary","user_intent":"token-contract post-retire probe"}`. |
| Expected outcome | HTTP 401 with taxonomy body `{"code":"unauthenticated","request_reference":<id>,"trace_id":<id>,"retry_safe":true}`. Signature, `iss`, `kid`, and time claims are all still valid; Stage 9's identity guard stops at the token contract because `token_contracts:1` now has `retired_at != null`. A follow-up `POST /v1/requests` with AAT_V2 (`ver="2"`, `jti="s01-029-v2"`) still passes identity (not 401/`unauthenticated`) — the retire is version-scoped, not installation-scoped. |
| Side effects | Guard-rejection metric for `error_code="unauthenticated"` on `inst-4c1d9e20-…`. `token_contract` unchanged by the request path — `ver='1'` stays retired, `ver='2'` stays live; the capability POST neither un-retires nor inserts rows. No clinic-side write (the Worker never touches Supabase `ai_internal.app_settings`). |
| Code reference | ai-platform/src/identity/index.ts:L373-L376 — `retired_at != null` → `rejectUnauthenticated`; ai-platform/src/control/token-contract.ts:L98-L106 — the retire that caused it |

## Scenario S01-030 — begin-rotation does not revive a retired ver

| Field | Content |
|-------|---------|
| ID | S01-030 |
| Journey setup | S01-027 (`ver='1'` retired and still present in the table; live set `{2}`). |
| Action | `POST /control/token-contract/begin-rotation` with valid operator bearer, body `{"ver":"1"}`. |
| Expected outcome | HTTP 409, body `{"error":"ver_already_exists"}`. The INSERT's `NOT EXISTS` predicate matches rows regardless of `retired_at`, so a retired row blocks re-insertion. Rotation reuse means a **new** version string, never a second life for `ver='1'`. |
| Side effects | `ver='1'` row untouched (`retired_at` still the S01-027 value, `changed_by='platform-operator'`). No audit row. |
| Code reference | ai-platform/src/control/token-contract.ts:L44-L48 — `NOT EXISTS` has no `retired_at` filter; L62-L64 — duplicate branch |

## Scenario S01-031 — Full rotation-reuse cycle ends at no_rotation_open again

| Field | Content |
|-------|---------|
| ID | S01-031 |
| Journey setup | S01-027 (live set `{2}`, `ver='1'` retired). |
| Action | In order, all with the valid operator bearer: (1) `POST /control/token-contract/begin-rotation` body `{"ver":"3"}`; (2) `POST /control/token-contract/retire` body `{"ver":"2"}`; (3) `POST /control/token-contract/retire` body `{"ver":"3"}`. |
| Expected outcome | (1) HTTP 200 `{"ver":"3"}` — the retired `ver='1'` row does not count toward the live-count guard, so the slot is open. (2) HTTP 200 `{"ver":"2","retired_at":<ISO>}` — live set becomes `{3}`. (3) HTTP 409 `{"error":"no_rotation_open"}` — `ver='3'` is now the sole live version, same terminal guard as S01-019 after a full rotate/retire cycle. |
| Side effects | After (1): `token_contract` row `ver='3'` inserted (`changed_by='platform-operator'`), audit row `token_contract_begin_rotation` target `'3'`. After (2): `ver='2'` stamped, audit row `token_contract_retire` target `'2'`. After (3): nothing — `ver='3'` stays live with `retired_at=NULL`, no audit row. Final table: `ver='1'` retired, `ver='2'` retired, `ver='3'` live; exactly one live version, which can never be retired (S01-019 invariant holds forever). |
| Code reference | ai-platform/src/control/token-contract.ts:L43-L48 — live-count guard ignores retired rows; L98-L106 — retire live-count guard; L130 — `no_rotation_open` |

## Doc-drift observations

1. **Missing failure rows in the doc tables.** The orientation doc's §4.1/§4.2 failure tables omit `400 invalid_json` (malformed body) for both routes and omit `400 invalid_ver` / `401 unauthorized` from the §4.2 retire table (retire performs the same auth, JSON-parse, and `ver` validation as begin-rotation — `ai-platform/src/control/token-contract.ts:L76-L89`). Code is authoritative; the doc under-documents retire's failure surface.
2. **Wrong-type `ver` crashes instead of rejecting.** Neither the doc nor the taxonomy mentions that a non-string `ver` (e.g. `{"ver":2}`) throws an uncaught `TypeError` at `body.ver?.trim()` (`token-contract.ts:L31`, `L86`) rather than returning `400 invalid_ver`. Documented as S01-013/S01-017; a `typeof` guard (or the existing `requireNonEmptyString` helper in `http.ts`, which token-contract.ts does not use) would close the gap.
3. **Stage numbering collision.** The orientation doc §5 calls identity "identity stage 2" (pipeline-internal numbering — `fail(2, …)` in `ai-platform/src/pipeline/index.ts:L344`), while the data-journey/catalog convention numbers the request-ingress guard as Stage 9. Same component, two numbers; readers should map doc "stage 2" = catalog "Stage 9 identity guard".
4. **Unreachable `invalid_route` branch.** `dispatchControlRequest` contains `reject(400, "invalid_route")` for the token-contract pattern (`ai-platform/src/control/index.ts:L172-L173`), but `TOKEN_CONTRACT_PATTERN` already constrains the action to `begin-rotation|retire`, so the branch is dead code. The doc does not list `invalid_route` for token-contract routes — consistent with behavior, but the dead branch is worth flagging.
5. **Cache-flush guidance is incomplete.** The doc (§6 intro) says to restart `npm run dev` or wait 30 s after a control mutation before an identity probe. Code exposes `CONFIG_CACHE_TTL_MS` (`ai-platform/src/config-cache/index.ts:L26-L40`), and `0` is accepted (`parsed < 0` is rejected, `0` is not), which disables caching outright — the doc never mentions this lever. Tests should set `CONFIG_CACHE_TTL_MS=0` instead of waiting.
6. **Whitespace-trim acceptance undocumented.** The doc says `ver` must be "non-empty" but does not state that surrounding whitespace is silently trimmed and the trimmed value inserted/returned (`token-contract.ts:L31`). S01-023 pins the behavior.
7. **No length/charset contract documented or enforced.** The doc's "non-empty" is the entire `ver` contract; code matches (S01-024). Not a drift, but an explicitly undocumented boundary worth recording.
8. **`control_audit` helper divergence.** `ai-platform/src/control/audit.ts` exports `writeAudit`, but the token-contract handlers deliberately do **not** use it — they inline a conditioned audit INSERT into the atomic batch so failed guards leave no audit row. The doc's claim "no extra audit row for the failed calls" (§6.3.6) is correct, but only because of this inlined conditioning; chapters for other control routes should not assume the same mechanism.

## Non-automatable notes

1. **Isolate cache staleness between control mutation and identity verify.** `isolateConfigCache` is a module-global with a 30 s default TTL (`config-cache/index.ts:L153`). In `@cloudflare/vitest-pool-workers` the isolate persists across tests in a file, so S01-025/S01-026/S01-029 would flake without intervention. **Automatable seam:** set `CONFIG_CACHE_TTL_MS="0"` in the test environment (`resolveConfigCacheTtlMs` accepts 0), making every `loadConfig` re-read D1. No production seam needed.
2. **Uncaught-TypeError scenarios (S01-013, S01-017).** In the vitest pool the `fetch` promise rejects rather than returning a Response, so the assertion is "rejects with TypeError", not an HTTP status/body. The production 500 body shape (runtime-generated HTML/text) is not meaningfully assertable and should not be pinned.
3. **Timing-safe compare (S01-003, S01-006).** `timingSafeEqualString` (`auth.ts:L4-L14`) is a side-channel mitigation; its constant-time property is not observable through HTTP and cannot be asserted in this environment. Only the functional outcome (401) is asserted.
4. **Concurrent begin-rotation race.** Two simultaneous begin-rotation calls with different `ver` values when one slot is open rely on D1 batch atomicity (exactly one succeeds, the other gets `rotation_already_open`). Deterministic concurrent dispatch against a single D1 database is not reliably orchestrable in the vitest pool; proposed seam: invoke the two handler batches directly against the same D1 instance and assert exactly one `meta.changes > 0`. Marked as a candidate rather than a catalog scenario.
5. **`added_at`/`recorded_at` clock values.** These come from `new Date().toISOString()` at handler time; scenarios assert format and approximate equality, not exact values. Fully deterministic clock control would require a clock-injection seam that does not exist in the current handlers.
