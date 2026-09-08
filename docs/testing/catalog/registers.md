# AI Platform E2E Scenario Catalog — Registers

Companion to the 14 chapter files (`stage-00` … `stage-12`, `stage-X`; 818 scenarios).
This file consolidates five cross-chapter registers. Every scenario ID cited below was
verified to exist in the chapter files; every GAP was double-checked against the chapters
(including synonym greps) before being marked. Line anchors use `path:Lstart-Lend`.

- Register 1 — Error-Code Inventory
- Register 2 — Auth-Boundary Matrix
- Register 3 — Input-Field Appendix
- Register 4 — Doc-Drift Register
- Register 5 — Non-Automatable Register

---

## Register 1 — Error-Code Inventory

### 1A. Taxonomy codes (`ai-platform/src/errors.ts:L1-L18`, entries `L28-L137`; closed list `ALL_TAXONOMY_CODES` at `L140`)

| Code | HTTP | Producing scenario(s) | Reachability |
|------|------|------------------------|--------------|
| `unauthenticated` | 401 | S00-019, S00-020, S00-022; S01-025, S01-026, S01-029; S06-041…S06-047 (minted-then-rejected, platform half); S07-003…S07-022, S07-024…S07-026, S07-049; S08-035…S08-039; S09-004…S09-022, S09-024…S09-026, S09-065; S12-019…S12-034, S12-036…S12-038, S12-040; SX-048 | Reachable |
| `installation_suspended` | 403 | S07-023; S08-040; S09-023; S12-035 | Reachable |
| `forbidden_capability` | 403 | S08-034, S08-041, S08-042, S08-043; S09-028…S09-034, S09-048, S09-049 | Reachable — non-granted unknown/unpublished ids fail stage 3 before registry |
| `rate_limited` | 429 | S08-044; S09-040…S09-043, S09-077 | Reachable |
| `quota_exhausted` | 429 | S08-045; S09-070…S09-073, S09-078; SX-014 (reconcile-time, internal retry — never on the wire) | Reachable. Note: never carries `period_reset` on the live path (`worker.ts:L1087-L1096` forwards only `retryAfter`; `errors.ts:L193-L200`) — see Register 4 #30 |
| `request_too_large` | 413 | S08-003…S08-008; S09-001, S09-062, S09-064 | Reachable |
| `context_required` | 422 | S08-046, S08-062; S09-052 | Reachable. Live body omits `missing_keys`/`shapes`/`manifest_version` (`adapter.ts:L213-L229`; `buildContextRequiredResponse` at `context/validator.ts:L541-L557` has no caller) — Register 4 #34 |
| `context_invalid` | 422 | S08-047, S08-048; S09-053…S09-060 | Reachable |
| `conversation_budget_exhausted` | 409 | **none** — mentioned only in S09-085 (exhaustiveness context) | **UNREACHABLE (dead path)** — confirmed. Only produced inside `validateConversationalContext` (`context/validator.ts:L378, L412, L416, L420`), entered only when `manifest.interactionMode === "conversational"` (`context/validator.ts:L437-L452`); the guard passes conversational options only when the manifest is conversational **and** `turn_ordinal` is present (`pipeline/index.ts:L394-L395`). The sole published manifest `clinic.visit_summary@1.0.0` is `single_shot` (`manifests/published/clinic.visit_summary@1.0.0.json:L19-L21`). Reachable only after a conversational capability ships. Stage 9 claim **confirmed** |
| `capability_unknown` | 404 | S00-007, S00-008 (entitlement passed, registry miss); S09-044, S09-045 | Reachable only when entitlement passes and the registry misses. Non-granted unknown/unpublished ids are 403 `forbidden_capability` (S08-034, S08-042, S08-043) |
| `capability_retired` | 404 | S09-046 | Reachable |
| `capability_disabled` | 503 | S09-036…S09-039, S09-050 | Reachable |
| `provider_unavailable` | 503 | S05-070, S05-071, S05-074; S10-004, S10-005, S10-008, S10-012; S11-003, S11-004 | Reachable |
| `provider_rejected` | 422 | S10-009; S11-005 | Reachable |
| `validation_failed` | 422 | S10-020, S10-022…S10-028; S11-006, S11-007 | Reachable |
| `cancelled` | 499 (no live HTTP status — `liveHttpStatusForCode` returns `null`, `errors.ts:L163-L168`) | S08-056; S10-013, S10-014, S10-019; S11-008…S11-011 | Reachable as SSE terminal/journal state only; never a pre-accept HTTP response (latent 500 mapping at `adapter.ts:L224` is unreachable — Register 4 #29) |
| `timeout` | 504 | **none as a terminal code.** Attempt-level `timeout` outcomes: S10-010, S10-011, S11-004 | **UNREACHABLE (dead path) as a terminal code** — confirmed. `timeout` is retryable-classified per attempt (`invocation/index.ts:L104-L110`, `L332`); chain exhaustion always returns `createProviderUnavailableError()` (`invocation/index.ts:L755-L761`), so `ai_request.terminal_error_code = 'timeout'` cannot be produced by the invocation path. Stage 11 claim **confirmed** (S11-004 encodes exactly this) |
| `internal_error` | 500 | S05-050, S05-053…S05-057; S08-029…S08-031; S09-003, S09-027 (uncaught `ConfigCacheMissError` → bare runtime 500), S09-079, S09-082, S09-083; S10-003, S10-007, S10-018, S10-034; S11-014; S12-006 | Reachable (also the `classifyErrorCode` fallback for any non-taxonomy string, `errors.ts:L147-L152`) |

### 1B. Non-taxonomy error strings (control plane, adapter, worker/GatewayObject)

Control-plane envelope is `{"error": "<string>"}` via `reject()` (`control/http.ts:L10-L15`); 401 body `{"error":"unauthorized"}` (`control/http.ts:L3-L8`) deliberately bypasses the taxonomy envelope.

| String | Status | Source (code) | Producing scenario(s) | Notes |
|--------|--------|---------------|------------------------|-------|
| `unauthorized` | 401 | `control/http.ts:L3-L8`; auth in `control/auth.ts:L30-L49` | S00-021; S01-002…S01-006; S03-001…S03-016; S04-001…S04-005, S04-058, S04-072, S04-080, S04-092; S05-017…S05-019, S05-034, S05-041, S05-049; S12-043, S12-044, S12-063 | Reachable on every control route |
| `invalid_json` | 400 | `control/http.ts:L43-L48` | S01-009, S01-015; S03-020, S03-048, S03-060; S04-006, S04-061, S04-082; S05-005, S05-029 | Reachable (routes that parse a body) |
| `invalid_payload` | 400 | `control/lifecycle.ts:L52-L150`; `control/entitle.ts:L61-L128` | S03-021…S03-036, S03-049…S03-055, S03-061…S03-063; S04-007…S04-046 | Reachable |
| `invalid_route` | 400 | `control/index.ts:L128, L139, L154, L173`; `control/lifecycle.ts:L49`; `control/entitle.ts:L164`; `control/capability-lifecycle.ts:L84, L170`; `control/cohort.ts:L86, L195`; `control/routing-policy.ts:L164, L255, L340, L416`; `control/support-purge.ts:L75`; `control/quota-inspect.ts:L38` | **none** (mentions in S01-008, S03-083, S04-100, S05-083, S12-072 are doc-drift/seam notes, not outcomes) | **UNREACHABLE via HTTP (dead path)** — confirmed. `isControlRoute` pre-filters with regexes identical in shape to each handler's own parser (`control/index.ts:L69-L103`), so the no-match branch can never fire through the worker. Chapters agree (Stage 1 drift #4, Stage 3 drift #1, Stage 4 drift #7, Stage 5 drift #9, Stage 12 non-automatable #3). Seam: direct handler invocation |
| `storage_error` | 500 | `control/lifecycle.ts:L195` (via `runControlBatch` `L181-L196`); `control/entitle.ts:L36`; `control/routing-policy.ts:L236` | S04-057 (fault-injection seam); seam variants noted in S03-083, S05-083 | Reachable in code for enroll/rotate/revoke-key/suspend/resume/delete/entitle/publish; **not inducible with real D1** (Register 5). NOT produced by purge or by cohort/capability-lifecycle handlers (unguarded `DB.batch` — Register 4 #13, #17) |
| `already_enrolled` | 409 | `control/lifecycle.ts:L193, L237` | S03-038, S03-039 | Reachable (platform-side; distinct from the Supabase `ALREADY_ENROLLED` rpc_error — see Register 4 #1) |
| `duplicate_kid` | 409 | `control/lifecycle.ts:L191, L345` | S03-040, S03-057 | Reachable |
| `installation_not_found` | 404 | `control/lifecycle.ts:L332, L411, L489, L542, L592`; `control/cohort.ts:L29`; `control/entitle.ts:L185`; `control/routing-policy.ts:L126`; `control/quota-inspect.ts:L52` | S03-041, S03-044, S03-056, S03-064, S03-071; S04-047, S04-065; S05-033; S12-062 | Reachable |
| `illegal_lifecycle_transition` | 409 | `control/lifecycle.ts:L336, L415, L496, L546, L596` | S03-043, S03-046, S03-073…S03-077 | Reachable |
| `key_not_found` | 404 | `control/lifecycle.ts:L426` | S03-065, S03-066 | Reachable |
| `key_already_revoked` | 409 | `control/lifecycle.ts:L430` | S03-068 | Reachable |
| `cannot_revoke_last_active_key` | 409 | `control/lifecycle.ts:L441` | S03-069 | Reachable (platform-side guard; mirrors the Supabase guard — Register 4 #1) |
| `invalid_ver` | 400 | `control/token-contract.ts:L33, L89` | S01-010…S01-012, S01-016 | Reachable; non-string `ver` throws uncaught TypeError instead (`token-contract.ts:L31, L86` — S01-013, S01-017) |
| `ver_already_exists` | 409 | `control/token-contract.ts:L64` | S01-014, S01-022 | Reachable |
| `rotation_already_open` | 409 | `control/token-contract.ts:L66` | S01-021 | Reachable |
| `ver_not_found` | 404 | `control/token-contract.ts:L125` | S01-018 | Reachable |
| `ver_already_retired` | 409 | `control/token-contract.ts:L128` | S01-028 | Reachable |
| `no_rotation_open` | 409 | `control/token-contract.ts:L130` | S01-019, S01-031 | Reachable |
| `entitlement_not_found` | 404 | `control/entitle.ts:L195` | S04-048 | Reachable |
| `not_pending` | 409 | `control/entitle.ts:L199` | S04-049, S04-051 | Reachable |
| `capability_not_found` | 404 | `control/capability-lifecycle.ts:L57`; `control/cohort.ts:L90, L199` | S04-059, S04-060, S04-073, S04-081, S04-093 | Reachable |
| `missing_installation_ids` | 400 | `control/cohort.ts:L99`; `control/routing-policy.ts:L264` | S04-062…S04-064; S05-030…S05-032 | Reachable |
| `missing_successor_id` | 400 | `control/capability-lifecycle.ts:L101` | S04-083, S04-084 | Reachable |
| `unknown_successor` | 400 | `control/capability-lifecycle.ts:L104` | S04-085 | Reachable; truthy non-string `successor_id` crashes instead (S04-091) |
| `already_deprecated` | 409 | `control/capability-lifecycle.ts:L116` | S04-089 | Reachable |
| `already_retired` | 409 | `control/capability-lifecycle.ts:L110` | S04-090 | Reachable |
| `not_deprecated` | 400 | `control/capability-lifecycle.ts:L190` | S04-094, S04-099 | Reachable |
| `overlap_window_active` | 400 | `control/capability-lifecycle.ts:L197` | S04-095…S04-097 | Reachable (via `retire_after` SEED; Register 5) |
| `missing_document` | 400 | `control/routing-policy.ts:L177` | S05-006…S05-008 | Reachable |
| `invalid_policy_identity` | 400 | `control/routing-policy.ts:L190` | S05-009…S05-015 | Reachable |
| `already_published` | 409 | `control/routing-policy.ts:L205, L234` | S05-004, S05-020 | Reachable |
| `policy_version_not_found` | 404 | `control/routing-policy.ts:L279, L355, L431` | S05-026, S05-038, S05-048 | Reachable |
| `illegal_policy_transition` | 409 | `control/routing-policy.ts:L283, L467` | S05-027, S05-028, S05-045 | Reachable |
| `missing_r2_binding` | 500 | `control/support-purge.ts:L25, L67`; `control/routing-policy.ts:L168` | S03-083, S05-016 (both direct-invocation seams; not reachable via `SELF.fetch` with the standard test wrangler config) | Reachable in code; deployment always binds R2 |
| `missing_reference` | 400 | `control/support-purge.ts:L31` | S12-045, S12-046 | Reachable |
| `invalid_reference` | 400 | `control/support-purge.ts:L36` | S12-047 | Reachable |
| `not_found` | 404 | `control/support-purge.ts:L46` | S12-048 | Reachable |
| `method_not_allowed` | 405 | `control/quota-inspect.ts:L30` | S12-064 | Reachable (POST to the quota-inspect path passes the worker's control gate, then fails the handler's GET check) |
| `quota_do_unavailable` | 503 | `control/quota-inspect.ts:L42, L80-L83` | **none** (S12-072 mention is the dashboard empty-window case, unrelated) | **GAP** — reachable only with a stubbed/failing DO binding; the in-pool DO always answers (Stage 12 non-automatable #2). No HTTP-level scenario exists |
| `invalid_json` (GatewayObject) | 400 | `worker.ts:L1254-L1259` | SX-058 | Reachable via the direct `GatewayObject` RPC seam (no public route reaches the DO — `worker.ts:L1247-L1321` is Worker→DO only, proven by S00-015) |
| `bad_request` (GatewayObject arg validation) | 400 | `worker.ts:L1141-L1147` (`ArgValidationError`), `L1150-L1161` (incl. `installation_id_mismatch`), `L1311-L1315` | SX-060 (admission), SX-061 (credit, both failure modes), SX-062 (release) — all against the **real** DO asserts; S09-079 (namespace double; the admission path maps it to `internal_error`) | Reachable at DO level |
| `internal_error` (GatewayObject catch-all) | 500 | `worker.ts:L1311-L1317` | SX-063 (storage-fault seam; Register 5 #45); S09-079 (folded; wrong-kind/5xx variants need a scripted DO double — Stage 9 non-automatable #3) | Reachable at DO level |
| `unknown_kind` (GatewayObject) | 400 | `worker.ts:L1319-L1320` | SX-059 | Reachable via the direct DO RPC seam |
| `Method Not Allowed` (GatewayObject non-POST) | 405 | `worker.ts:L1251-L1253` | SX-057 | Reachable via the direct DO RPC seam |
| bare 422 (adapter parse/header failures, no body) | 422 | `adapter.ts:L205-L211` | S08-010…S08-022, S08-059 | Reachable; deliberately not a taxonomy body |
| `request_too_large` body with empty reference/trace | 413 | `adapter.ts:L191-L203` | S08-003…S08-008 | Reachable; size gate runs before headers/reference by design (FR-006 exception) |
| `event source required` | 503 | `adapter.ts:L230-L235` | S08-058 (direct `handleAdapterRequest` invocation only) | Unreachable via production wiring — `handleLivePostRequest` always supplies an event source (`worker.ts:L1130-L1138`) |

---

## Register 2 — Auth-Boundary Matrix

Route table derived from `worker.ts:L1324-L1445` (fetch dispatch), `worker.ts:L1447-L1495` (scheduled),
and `control/index.ts:L69-L200` (control route patterns + dispatch).
Columns: **No creds** / **Wrong creds** / **Insufficient scope** / **Cross-installation**.
Control-plane auth is a single shared bearer → single operatorId (`control/auth.ts:L16-L51`);
clinic-facing auth is the AAT verifier (`identity/index.ts`, via `journal/index.ts:L544-L577` for GET
and guard stage 2 for POST).

| Route | No credentials | Wrong credentials | Insufficient scope | Cross-installation access |
|-------|----------------|-------------------|--------------------|---------------------------|
| `/health` (any method — no method check, `worker.ts:L1334-L1340`) | N/A — no auth on this route (200 always; S00-034, S00-035, S00-023) | N/A — no auth | N/A — no auth | N/A — no tenant data read |
| `GET /v1/capabilities` (`worker.ts:L1342-L1347`) | 401 taxonomy `unauthenticated` — S00-019, S07-003 | 401 `unauthenticated` — S00-020, S07-004…S07-022 (scheme/segments/alg/kid/claims/aud/exp/iat/iss/key/signature variants) | N/A — discovery deliberately does not filter by staff role or token scopes (those gates live in `assertPlanAllowance` on the invoke path); confirmed by S07-041 | N/A — response is scoped to the caller's own installation entitlement; there is no reference/tenant input to cross. (ETag is content-derived, shared across identically entitled installations — S07-050) |
| `POST /v1/requests` (`worker.ts:L1349-L1351` → adapter → guard) | 401 taxonomy `unauthenticated` from guard stage 2 (ingress itself passes) — S08-035, S09-004 | 401 `unauthenticated` — S08-036…S08-039 (non-JWS, Basic, bare Bearer, operator bearer), S09-005…S09-022 (JWS/claims/aud/iat/exp/lifetime/iss/kid/revoked/window/signature) | 403 `forbidden_capability` — S09-048 (missing `requiredCapabilityScope`), S09-049 (role outside `allowedStaffRoles`); entitlement-level denials S09-028…S09-034; suspended installation 403 `installation_suspended` S09-023 | 422 `context_invalid` on tenant mismatch between supplied context and token principal — S08-047, S09-053 (org), S09-054 (branch); key bound to a different installation → 401 S09-021 |
| `GET /v1/requests/{ref}` (`worker.ts:L1376-L1438`) | 401 taxonomy `unauthenticated` — S00-022, S12-019 | 401 `unauthenticated` — S12-020…S12-034; suspended installation 403 `installation_suspended` — S12-035 | N/A — `authenticateGetRequest` verifies the AAT only; no scope/role evaluation exists on this route (`journal/index.ts:L544-L577`) | Empty-body 404 (indistinguishable from unknown reference) — S12-017 |
| `POST /control/installations/{id}/enroll` | 401 `{"error":"unauthorized"}` — S03-001 | 401 — S03-002 (wrong bearer), S03-015 (malformed schemes/empty token) | N/A — no scope concept; any valid operator bearer maps to the single configured operatorId (`control/auth.ts:L16-L26`). Closest: clinic AAT as bearer → 401 (S01-004, S04-003) | N/A — operator credential is platform-scoped; the path `{id}` is a target, not a tenant boundary |
| `POST /control/installations/{id}/rotate` | 401 — S03-003 | 401 — S03-004, S03-015 | N/A — as above | N/A — as above |
| `POST /control/installations/{id}/revoke-key` | 401 — S03-005 | 401 — S03-006, S03-015 | N/A — as above | N/A — as above |
| `POST /control/installations/{id}/suspend` | 401 — S03-007 | 401 — S03-008, S03-015 | N/A — as above | N/A — as above |
| `POST /control/installations/{id}/resume` | 401 — S03-009 | 401 — S03-010, S03-015 | N/A — as above | N/A — as above |
| `POST /control/installations/{id}/delete` | 401 — S03-011 | 401 — S03-012, S03-015 | N/A — as above | N/A — as above |
| `POST /control/installations/{id}/purge` | 401 — S03-013 | 401 — S03-014, S03-015 | N/A — as above | N/A — as above |
| `POST /control/installations/{id}/entitle` | 401 — S04-001 | 401 — S04-002 (wrong bearer), S04-003 (clinic AAT), S04-004 (malformed scheme), S04-005 (unconfigured secret fails closed; also S00-005) | N/A — as above | N/A — as above |
| `POST /control/capabilities/{id}/versions/{v}/deprecate` | 401 — S04-080 | 401 — S04-101 (wrong bearer) | N/A — as above | N/A — as above |
| `POST /control/capabilities/{id}/versions/{v}/retire` | 401 — S04-092 | 401 — S04-102 (wrong bearer) | N/A — as above | N/A — as above |
| `POST /control/capabilities/{id}/versions/{v}/activate` (cohort) | 401 — S04-058 | 401 — S04-103 (wrong bearer) | N/A — as above | N/A — as above |
| `POST /control/capabilities/{id}/versions/{v}/promote` (cohort) | 401 — S04-072 | 401 — S04-104 (wrong bearer) | N/A — as above | N/A — as above |
| `POST /control/routing-policies/publish` | 401 — S05-017 | 401 — S05-018 (wrong bearer), S05-019 (non-Bearer scheme, empty bearer) | N/A — as above | N/A — as above |
| `POST /control/routing-policies/{id}/versions/{v}/canary` | 401 — S05-034 | 401 — S05-084 (wrong bearer) | N/A — as above | N/A — as above |
| `POST /control/routing-policies/{id}/versions/{v}/promote` | 401 — S05-041 (uses a wrong bearer value — covers both cells) | 401 — S05-041 | N/A — as above | N/A — as above |
| `POST /control/routing-policies/{id}/versions/{v}/rollback` | 401 — S05-049 | 401 — S05-085 (wrong bearer) | N/A — as above | N/A — as above |
| `POST /control/token-contract/begin-rotation` | 401 — S01-002 | 401 — S01-003 (wrong secret), S01-004 (clinic AAT), S01-006 (malformed schemes) | N/A — as above | N/A — as above |
| `POST /control/token-contract/retire` | 401 — S01-005 | 401 — S01-005 (covers without/with wrong bearer), S01-006 | N/A — as above | N/A — as above |
| `POST /control/support/lookup?reference=…` | 401 — S12-043 | 401 — S12-044 (wrong bearer and clinic AAT) | N/A — as above | By design — support lookup explicitly reads across installations (S12-049); no cross-tenant denial exists on this route |
| `GET /control/installations/{id}/quota` (quota inspect; the only GET control route — `worker.ts:L1353-L1358`, `control/index.ts:L89-L91`) | 401 — S12-063(a) | 401 — S12-063(b) (clinic AAT as bearer) | N/A — as above | N/A — as above (any installation id inspectable by the operator; unknown id → 404 S12-062) |
| `POST /control/installations/{id}/quota` | 405 `method_not_allowed` after auth — S12-064 (auth still runs first: 401 without bearer) | 405 after auth — S12-064 | N/A | N/A |
| Wrong method on any other control route (e.g. `GET /control/installations/{id}/suspend`) | 404 plain text — method gate precedes auth (`worker.ts:L1353-L1358`); S00-018, S03-018, S01-007, S12-055 | same | N/A | N/A |
| Unknown token-contract action / trailing slashes / unknown paths | 404 plain text — S01-008, S03-017, S03-019, S00-015, S07-001, S07-002, S08-001, S08-002, S12-014, S12-018 | same | N/A | N/A |
| `GatewayObject` DO (`worker.ts:L1247-L1321`) | N/A — not publicly reachable; Worker→DO RPC only, no auth header evaluated (proven: S00-015 probes `/quota-do.internal/rpc` → 404) | N/A | N/A | N/A |
| `scheduled` (cron trigger, `worker.ts:L1447-L1495`) | N/A — no HTTP credential surface; fired by the platform cron or the dev-only wrangler trigger (`/__scheduled` vs `/cdn-cgi/handler/scheduled` — the two docs disagree, Register 4 #49). Covered by S00-024…S00-026, SX-001…SX-003 | N/A | N/A | N/A |

**GAP cells: none remaining.** The six wrong-credentials cells flagged in the first registers pass (deprecate, retire, cohort activate, cohort promote, canary, rollback) are now covered by S04-101…S04-104 and S05-084/S05-085, added in the post-verification fix pass. All six share the same `requireOperator` path (`control/http.ts:L33-L40`).

---

## Register 3 — Input-Field Appendix

Validation rules are derived from code (not docs); boundary values are the code-level ones.
Coverage column lists the scenario(s) exercising that field/rule; **GAP** = no covering scenario
(double-checked with synonym greps).

### 3.1 `POST /v1/requests` (adapter `adapter.ts:L373-L568`; extractors `worker.ts:L241-L277`; guard `pipeline/index.ts`)

| Field | Validation rule (code) | Boundary values | Coverage |
|-------|------------------------|-----------------|----------|
| Body size | `Content-Length` pre-check, else stream-read abort at first over-cap chunk; never buffers past cap (`adapter.ts:L318-L358`); limit `INGRESS_BODY_SIZE_LIMIT = 1_048_576` (`adapter.ts:L13`) | exactly 1 048 576 B admitted; +1 B → 413; UTF-8 bytes counted, not characters; non-numeric Content-Length ignored | S08-003…S08-009; S09-001 |
| Body shape | must parse as a JSON plain object (`adapter.ts:L288-L297, L390-L399`) | empty/malformed/array/null/scalar → bare 422 | S08-010…S08-015, S08-059 |
| `Content-Type` header | **never checked** (`adapter.ts:L373-L399`) | any value with parseable body passes | S08-016 |
| `x-idempotency-key` | required, non-empty after trim (`adapter.ts:L244-L247`) | whitespace-only → 422; no length/charset bound (1 char and 512 chars pass) | S08-017, S08-018, S08-023…S08-025 |
| `x-capability-version` | required, non-empty after trim (`adapter.ts:L249-L252`) | whitespace-only → 422; non-semver strings pass ingress (404 `capability_unknown` at guard if unpublished) | S08-019, S08-020, S08-024, S08-042 |
| `x-trace-id` | optional; present-but-empty-after-trim → 422; any non-empty value accepted verbatim; ULID minted when absent (`adapter.ts:L254-L263`, `trace.ts` via `resolveTraceId`) | empty string rejected; non-ULID echoed | S08-021, S08-026…S08-028 |
| `Authorization` | not required at ingress; guard stage 2 requires `Bearer <AAT>` (case-insensitive scheme match, `worker.ts:L241-L249`) | missing/non-JWS/Basic/bare `Bearer`/operator token → 401 `unauthenticated` at guard | S08-035…S08-039; S09-004…S09-026 |
| `capability_id` (body) | string; alias `capability` honored when absent; `capability_id` wins when both present; missing/empty/non-string (with no valid alias) → pre-accept `internal_error` 500 before the guard (`worker.ts:L251-L259, L1043-L1046`) | empty string → 500; number falls through to alias | S08-029…S08-034; S09-003 |
| `user_intent` (body) | string; wrong-type falls through to `intent` alias; default `""` (`worker.ts:L261-L269`); oversized intent trips guard stage-7 preflight | over token boundary → 413 `request_too_large` | S08-054; S09-062…S09-064 |
| `context` (body) | plain object else `{}` (`worker.ts:L271-L277`); per-key shape/size/tenant rules at guard stage 6 (`context/validator.ts`) | non-object → `{}`; required key missing → `context_required`; org/branch mismatch, wrong shape, over-maxLength/maxSize, malformed iso8601 → `context_invalid` | S08-055; S09-052…S09-061 |
| `turn_ordinal` / `turnOrdinal` (body) | read at `pipeline/index.ts:L255`; conversational options forwarded only when `interactionMode === "conversational"` AND `turn_ordinal` present (`pipeline/index.ts:L394-L395`) | ignored entirely for `single_shot` | S09-061 |
| routing-injection body keys | adapter consults no body fields for routing (`ADAPTER_ROUTING_BODY_FIELDS = []`, `adapter.ts:L277-L280`) | silently ignored | S08-050 |
| AAT JWT claims (stage 2) | header `alg` must be EdDSA, `kid` non-empty; payload requires full claim set; `aud` = `ai-platform`; `exp` with 60 s skew; `iat` not future beyond skew; `exp − iat` ≤ 600 s; `iss` known installation; `kid` known, unrevoked, in validity window, bound to `iss`; Ed25519 signature; `ver` known and unretired (`identity/index.ts`) | lifetime 600 s ok / 601 s rejected; skew ±60 s | S09-004…S09-026; S07-003…S07-026; S12-019…S12-038; minted variants S06-041…S06-047 |

### 3.2 `GET /v1/requests/{ref}` (`worker.ts:L1376-L1438`; `journal/index.ts:L544-L577`)

| Field | Validation rule (code) | Boundary values | Coverage |
|-------|------------------------|-----------------|----------|
| `{ref}` path param | raw path slice, no format validation; empty → 404 before auth (`worker.ts:L1380-L1383`); normalization (case + I/L/O ambiguity) applied inside `getRequest`; **no whitespace trim** | padded reference → 404; malformed → empty 404 | S12-011…S12-016; S12-013 (empty), S12-017 (cross-installation) |
| `Authorization` | `Bearer <AAT>` required; same verifier as discovery (`journal/index.ts:L550-L577`) | missing/malformed/expired/etc. → 401; suspended → 403 | S12-019…S12-038; cache-TTL windows S12-039, S12-040 |

### 3.3 `GET /v1/capabilities` (`worker.ts:L1342-L1347`; `discovery/index.ts`)

| Field | Validation rule (code) | Boundary values | Coverage |
|-------|------------------------|-----------------|----------|
| `Authorization` | `Bearer <AAT>` required before any D1 read | see 3.1 JWT claims | S00-019, S00-020; S07-003…S07-026 |
| `If-None-Match` | optional; strong/weak/list/`*` matching → 304; malformed → 200 full body; never evaluated when auth fails | `W/"etag"`, multi-tag list, `*` all 304 | S07-043…S07-049 |

### 3.4 Control-plane operations (common: `Authorization: Bearer <OPERATOR_BEARER_TOKEN>` — timing-safe compare, unconfigured secret fails closed; `control/auth.ts:L30-L49`, `control/http.ts:L33-L48`; coverage S00-005, S00-021, S03-015, S04-005)

| Operation | Fields and rules (code) | Coverage |
|-----------|--------------------------|----------|
| `POST /control/installations/{id}/enroll` | path `{id}`: canonical UUID, case-insensitive (`/i` flag) → else 400 `invalid_payload` (`lifecycle.ts:L38-L55`). Body (all `requireNonEmptyString`): `org_id` (UUID), `display_name`, `region`, `plan` (known tier), `public_key` (base64url, 32-byte Ed25519), `algorithm` (supported list), `kid` (UUID) (`lifecycle.ts:L85-L128`) | S03-020…S03-040; uppercase UUID boundary S03-036 |
| `…/rotate` | body `kid` (UUID), `public_key` (32-byte b64url), `algorithm` (supported) (`lifecycle.ts:L130-L153`) | S03-048…S03-057 |
| `…/revoke-key` | body `kid` non-empty + canonical UUID (`lifecycle.ts:L64-L82`) | S03-060…S03-068 |
| `…/suspend`, `…/resume`, `…/delete` | path id only; **body never read** | S03-041…S03-047, S03-071…S03-078 |
| `…/purge` | path id captured by regex, **not UUID-validated** (`support-purge.ts:L70-L78`); no body | S03-079…S03-082 |
| `…/entitle` | `period_start`/`period_end`: ISO-8601 instant `YYYY-MM-DDTHH:MM:SS(.mmm)Z`, ms optional, `start < end` (`entitle.ts:L40-L65`); `request_quota`/`token_budget`: non-negative integers; `cost_budget`: finite number ≥ 0 (NaN/Infinity branch unreachable over HTTP — Register 5); `soft_threshold`: 0…1 inclusive; `allowed_capabilities`: string array (empty allowed); `grants`: non-empty array of `{capability_id, capability_version, scope?: "installation"\|"plan"}` (`entitle.ts:L68-L137`) | S04-006…S04-046; boundaries S04-031…S04-033 |
| `…/capabilities/{id}/versions/{v}/activate` | body `installation_ids`: required, non-empty array (`cohort.ts:L99`); unknown id → 404; duplicate ids write duplicate grants | S04-061…S04-065, S04-070 |
| `…/promote` (cohort) | **body ignored** | S04-074…S04-079 |
| `…/deprecate` | body `successor_id`: non-empty string resolving in the registry (`capability-lifecycle.ts:L101-L104`); truthy non-string → uncaught TypeError 500 | S04-082…S04-085, S04-091 |
| `…/retire` | **body ignored** (`capability-lifecycle.ts:L159-L230`) | S04-094…S04-100 |
| `POST /control/routing-policies/publish` | body `document`: required object; `document.policy_id` non-empty string; `document.policy_version` positive integer; unknown extra keys stored verbatim (`routing-policy.ts:L177-L190`) | S05-005…S05-015, S05-021, S05-022 |
| `…/versions/{v}/canary` | body `installation_ids`: required non-empty array (`routing-policy.ts:L264`); `cohort_name` accepted but **discarded** | S05-029…S05-033; S05-023 |
| `…/versions/{v}/promote`, `…/rollback` | no body required | S05-035…S05-047 |
| `POST /control/token-contract/begin-rotation`, `…/retire` | body `ver`: non-empty after trim; trimmed value stored; **no length/charset guard**; non-string → uncaught TypeError (`token-contract.ts:L31, L86`) | S01-009…S01-017, S01-023, S01-024 |
| `POST /control/support/lookup` | query `reference`: required, non-blank after trim, normalized (Crockford) then validated (`support-purge.ts:L29-L40`) — note the **trim asymmetry** vs the clinic GET (Register 4 #46) | S12-045…S12-048 |
| `GET /control/installations/{id}/quota` | GET only (405 otherwise, `quota-inspect.ts:L30`); path id any non-empty segment; query `verbose=true` includes state maps (500-entry truncation, `quota-inspect.ts:L7-L19`) | S12-056…S12-064 |

### 3.5 `GatewayObject` RPC kinds (`worker.ts:L1247-L1321`; arg asserts `L1164-L1220`)

| Field | Validation rule (code) | Coverage |
|-------|------------------------|----------|
| HTTP method | POST only → else plain-text 405 (`L1251-L1253`) | SX-057 |
| body JSON | parseable → else 400 `invalid_json` (`L1254-L1259`) | SX-058 |
| `kind` | `admission` \| `credit` \| `release` \| `inspect` → else 400 `unknown_kind` (`L1275-L1320`) | admission: S09-065…S09-081 (via guard), SX-046…SX-048, SX-051 (DO-direct); credit: S11-001, S11-012, S11-021, SX-052; release: S09-082 (journal-failure release path); inspect: S12-056…S12-061, S12-065, SX-050; `unknown_kind`: SX-059 |
| `now` | optional finite number → injectable clock (`L1263-L1267`) | S11-012, S12-065, SX-020, SX-046…SX-050 |
| admission args | `jti`, `installationId`, `idempotencyKey`, `requestReference`: strings; `entitlement`: object (`L1164-L1175`) → else `ArgValidationError` → 400 `bad_request` | SX-060 (real-DO rejects); S09-079 (bad_request mapping); happy paths S09-065…S09-081 |
| credit args | `installationId`, `requestId`, `requestReference`: strings; `usage`: object; `partial`: boolean; `idempotencyState` ∈ `{failed, cancelled, completed}` when present; `entitlement`: optional object (`L1178-L1208`) | SX-061 (real-DO rejects, both failure modes); S11-001, S11-005, S11-012, S11-017 |
| release args | `installationId`, `requestId`, `idempotencyKey`, `jti`: strings (`L1211-L1220`) | SX-062 (real-DO rejects); S09-082 |

### 3.6 Supabase RPCs (`backend/supabase/migrations/`)

| RPC | Fields and rules (code) | Coverage |
|-----|--------------------------|----------|
| `enroll_installation_keypair()` | no params. Gate: `assert_owner_or_administrator` (role `administrator` OR `is_bootstrap_admin`) → `FORBIDDEN`; active-key guard → `ALREADY_ENROLLED` (`20260902120000…sql:L19-L29`); reuses earliest non-deleted `installation_id`, else mints (`L30-L40`) | S02-004, S02-007…S02-009, S02-012, S02-022, S02-027 |
| `rotate_installation_key()` | no params. Same gate; `INSTALLATION_NOT_ENROLLED` only when **no non-deleted rows at all** (no `revoked_at` filter — `20260801120100…sql:L103-L115`) | S02-003, S02-005, S02-013, S02-020, S02-023 |
| `revoke_installation_key(p_kid text)` | `p_kid` blank → `INVALID_INPUT`; unknown/soft-deleted → `KEY_NOT_FOUND`; already revoked → idempotent success; last active key → `CANNOT_REVOKE_LAST_ACTIVE_KEY` (`20260902130100…sql:L15-L45`); role gate precedes all validation | S02-006, S02-014…S02-019 |
| `issue_ai_token(p_scopes text[] DEFAULT NULL)` | JWT session: `UNAUTHENTICATED` (no/invalid claims), `SESSION_EXPIRED`, `STAFF_NOT_FOUND` (no/deactivated/deleted staff row), `BRANCH_NOT_FOUND` (no active branch; alphabetical tie-break), `INSTALLATION_NOT_ENROLLED` (no active key), `RATE_LIMITED` (per-actor ceiling, advisory-lock serialized), `AI_ACCESS_DENIED` (no `ai.*` grant) — all RAISEd (`20260801120200…sql:L88-L237`); `p_scopes` **ignored** | S06-001…S06-026, S06-030…S06-033; p_scopes S06-021…S06-023 |
| `get_ai_availability()` | no params; COALESCE default when row missing/soft-deleted (`20260802140000…sql:L10-L40`, security-definer fix `20260821120000`) | S02-001, S02-024, S02-025 |
| `get_visit_chief_complaint(p_visit_id uuid)` | branch scope first (`NOT_FOUND` for unknown **or** out-of-scope visit), then clinical permission (`FORBIDDEN`); omits `complaint`/`recorded_at` keys when NULL; ignores soft-deleted notes (`20260802120000…sql:L3-L53`) | S08-061…S08-069 |
| `record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb)` | reference must match `XXXX-XXXX` Crockford regex → `INVALID_INPUT`; unregistered target → `INVALID_INPUT`; duplicate `(reference, table)` pre-check (broader than the UNIQUE constraint); org context required → `FORBIDDEN`; domain-write failure → rollback + raise (`20260802150000…sql:L144-L230`) | S11-022…S11-029 |

---

## Register 4 — Doc-Drift Register

Consolidated and deduplicated from the `## Doc-drift observations` sections of all 14 chapters.
Both directions are recorded (docs describe what code lacks; code implements what docs omit).
Chapter attribution in brackets. **Item #1 is the reconciled Stage 2/Stage 6 cross-chapter conflict.**

1. **[RESOLVED CONFLICT — Stage 6 vs Stage 2] `ALREADY_ENROLLED` / `CANNOT_REVOKE_LAST_ACTIVE_KEY` guards.**
   Stage 6 drift #1 claims the contract-specified guards "don't exist in code" (citing
   `20260801120100` and `20260803140000`). **That claim is stale.** The guards were added by two
   later migrations that `CREATE OR REPLACE` the original routines:
   `backend/supabase/migrations/20260902120000_enroll_installation_keypair_already_enrolled_guard.sql:L19-L29`
   (enroll returns `rpc_error('ALREADY_ENROLLED', …)` when any non-deleted, unrevoked key exists)
   and `backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:L35-L45`
   (revoke returns `rpc_error('CANNOT_REVOKE_LAST_ACTIVE_KEY', …)` when the active-key count is 1).
   Verified: the original `20260801120100_ai_installation_keypair_routines.sql` contains neither
   guard (grep: 0 hits), so Stage 6's reading of *those two migrations* was accurate, but it
   predates/misses the 2026-09-02 guard migrations. **Stage 2 is correct** (S02-012, S02-019 cover
   both guards). Downstream corrections to Stage 6's drift text: (a) a zero-active keystore is
   **no longer** reachable by revoking the only key — S06-011's state must be built another way
   (e.g. soft-delete, S06-012); (b) a second enroll while an active key exists now **fails** with
   `ALREADY_ENROLLED` (S02-012) — S06-029's recovery path remains valid only because the guard
   permits re-enroll once *zero* active keys remain (S02-022). The platform-side mirrors of both
   guards also exist in the worker (`control/lifecycle.ts:L441`, `L193/L237`; S03-069, S03-038/039).
2. **`/health` accepts any HTTP method** — pathname-only branch (`worker.ts:L1334-L1340`); docs describe only GET (S00-034). [Stage 0]
3. **Boot registry-install failure is swallowed** — `try/catch` around `setCapabilityRegistry` (`worker.ts:L150-L159`); a runtime-invalid bundled manifest leaves a possibly-empty registry degrading all resolution to `capability_unknown` while `/health` stays 200 (S00-007, S00-008). No doc states the degraded end-state. [Stage 0]
4. **`CONFIG_CACHE_TTL_MS` parsing undocumented** — unset/empty/non-numeric/negative → 30 000 ms default; `"0"` accepted and disables caching (`config-cache/index.ts:L26-L40`); the orientation doc's cache-flush guidance (restart/wait 30 s) never mentions this lever (S00-010, S00-011). [Stage 0, Stage 1 #5]
5. **`LOG_VERBOSITY` parsing undocumented** — `V0/V1/V2` aliases, case-insensitivity, invalid → V0, development default V2 (S00-012…S00-014). [Stage 0]
6. **Schema bootstrap conflates migrations** — doc §4 says "creates 14 tables" citing the baseline; `20260731120000_platform_schema.sql` creates 12; `token_contract`(+seed), `kill_switch`, `grace_admission_queue`, `idx_entitlement_installation_id` arrive in four later migrations. End state correct (S00-027); attribution loose. [Stage 0]
7. **Two distinct 404 shapes on the GET path** — empty reference (`/v1/requests/`) and unknown/malformed/cross-installation references return a **null-body** 404; the catch-all returns plain-text `Not Found` (S00-017, S12-013 vs S12-014/S12-018). No doc distinguishes them. [Stage 0, Stage 12 #5]
8. **Control-plane 401 bypasses the taxonomy envelope** — `{"error":"unauthorized"}` lacks `code`/`request_reference`/`trace_id`/`retry_safe` (S00-021). [Stage 0]
9. **Token-contract doc failure tables incomplete** — omit `400 invalid_json` for both routes and `400 invalid_ver` / `401 unauthorized` from the retire table (`control/token-contract.ts:L76-L89`). [Stage 1 #1]
10. **Wrong-type `ver` crashes instead of rejecting** — non-string `ver` throws uncaught `TypeError` at `body.ver?.trim()` (`token-contract.ts:L31, L86`), not `400 invalid_ver` (S01-013, S01-017). [Stage 1 #2]
11. **Stage-numbering collision** — orientation doc §5 "identity stage 2" (pipeline-internal `fail(2, …)`, `pipeline/index.ts:L344`) = catalog Stage 9 identity guard. [Stage 1 #3]
12. **`invalid_route` branches are dead code via HTTP** — dispatch pre-filters with handler-identical regexes (`control/index.ts:L69-L103` vs handler parsers); applies to token-contract (`control/index.ts:L172-L173`), lifecycle, entitle, capability-lifecycle, cohort, routing-policy, purge, and quota-inspect handlers. The only reachable path-shape 400 is `invalid_payload` for a non-UUID lifecycle path id (S03-033); purge doesn't even validate that (S03-082). [Stage 1 #4, Stage 3 #1, Stage 4 #7, Stage 5 #9, Stage 12 non-automatable #3]
13. **Purge `500 storage_error` documented but not in code** — `handleInstallationPurge`/`purgeByInstallationId` have no error mapping; a D1/R2 failure throws to a non-JSON runtime 500. `storage_error` exists only in `runControlBatch` (`lifecycle.ts:L195`), `entitle.ts:L36`, `routing-policy.ts:L236`. [Stage 3 #2; related Stage 4 #1]
14. **Suspend/resume/delete/promote/retire ignore the request body** — doc shows `{}` bodies; handlers never read them; any content type or malformed JSON succeeds identically (S03-047, S04-079, S04-100). The retire doc failure table's `400 invalid_json` entry is unreachable. [Stage 3 #3, Stage 4 #2, #9]
15. **Rotate and revoke-key permitted on suspended installations** — code blocks only `status = deleted` (S03-059, S03-070); doc silent. [Stage 3 #4]
16. **Delete has no suspend precondition; purge has no delete precondition** — `active → deleted` direct (S03-072), `suspended → deleted` (S03-078), purge on active (S03-080). Doc silent. [Stage 3 #5]
17. **`500 storage_error` listed for cohort activate/promote, deprecate/retire, and routing canary/promote/rollback — not in code** — `cohort.ts:L179, L382`, `capability-lifecycle.ts:L129, L203`, and `routing-policy.ts:L305-L324, L370-L399, L526-L528` all call `DB.batch` unguarded → unhandled exception, non-JSON 500. (Verification pass extended the original Stage 4 finding to the routing-policy handlers.) [Stage 4 #1; verification]
18. **Entitle failure table omits reachable `401 unauthorized` and `400 invalid_json`** (S04-001…S04-006). [Stage 4 #3]
19. **Plan-scope grant dedup undocumented** — a live duplicate plan grant is silently skipped while activation proceeds (`entitle.ts:L239-L243`, S04-054). [Stage 4 #4]
20. **Duplicate installation ids in one activate write duplicate live grants** (`cohort.ts:L119-L156`, S04-070). [Stage 4 #5]
21. **Truthy non-string `successor_id` crashes deprecate** — unhandled TypeError → non-JSON 500 (S04-091); falsy check is not a type check. [Stage 4 #6]
22. **Doc §11.2 "Unprobeable" labels that ARE automatable** — cohort split onto a second version, deprecate-with-different-successor, full retire state machine, all via the two-version in-memory registry seam (`worker.ts:L150-L159`) plus `retire_after` SQL seeding. [Stage 4 #8]
23. **Post-accept routing failures surface as `internal_error`, never router codes** — every throw from the routing block is caught at `worker.ts:L685-L697` and pushed as SSE `failed/internal_error`; `policy_identity_mismatch`/`no_matching_rule` never appear on the wire (S05-050, S05-053…S05-058). [Stage 5 #1]
24. **The post-accept routing catch skips settlement** — no `settleTerminal`/`recordTerminalState`, no `ai_attempt`, no ledger entry; the request is left `Accepted` (contrast the empty-chain path, which settles — S05-070/071). [Stage 5 #2; same gap restated for Stage 10 in #37]
25. **`no_matching_rule` is dead code on the serving path** — catch-all validation runs before rule matching, so `rules.find` can never miss (S05-058). [Stage 5 #3]
26. **Promote has no status precondition; rollback of published/superseded is a 200 no-op** (S05-039, S05-040, S05-046, S05-047). Doc describes only happy transitions. [Stage 5 #4]
27. **Canary failure table incomplete** — omits `400 invalid_json` (S05-029), `404 policy_version_not_found` (S05-026), and `missing_installation_ids` for absent/non-array values (S05-030, S05-032). [Stage 5 #5]
28. **`cohort_name` accepted but discarded** — never read or stored (S05-023). [Stage 5 #6]
29. **Two canary versions can coexist; audit `before_pointer` can name another version's cohort** (S05-025); serving order `active_from DESC, rowid DESC` undocumented. Canary R2 miss does **not** fall back to active (`config-cache/index.ts:L357-L363`, S05-054). [Stage 5 #7, #8]
30. **`quota_exhausted` never carries `period_reset` on the wire** — admission computes it (`admission/index.ts:L461-L482`) and `supplementaryFieldsForCode` supports it (`errors.ts:L193-L200`), but `runGuard`'s `fail()` (`pipeline/index.ts:L191-L213, L444-L449`) and the worker preAccept (`worker.ts:L1087-L1096`) forward only `retryAfter`. The orientation doc's stage-8 table describes an internal value dropped before serialization. [Stage 8 #5, Stage 9 #1]
31. **Guard stage-1 `internal_error` for non-object JSON is unreachable via `POST /v1/requests`** — the adapter's parse gate answers bare 422 first (`adapter.ts:L390-L394` vs `pipeline/index.ts:L314-L317`). [Stage 9 #2]
32. **Missing entitlement row escapes as an uncaught `ConfigCacheMissError` → bare runtime 500** (`entitlement/index.ts:L154-L160`), not a stage-3 `internal_error` GuardFailure; consequently the admission entitlement-miss → `quota_exhausted` branch (`admission/index.ts:L604-L620`) is unreachable in the ordered pipeline (S09-027). [Stage 9 #3]
33. **`conversation_budget_exhausted` unreachable with the published manifest set** — see Register 1A. [Stage 9 #4]
34. **`context_required` omits `missing_keys`/`shapes`/`manifest_version` on the live body** — `buildContextRequiredResponse` (`context/validator.ts:L541-L557`) has no caller; `preAcceptFailureResponse` emits base fields only (`adapter.ts:L213-L229`). [Stage 9 #10]
35. **Stage-5 D1 kill-switch re-checks are defensive dead code in the ordered guard** — stage 3 evaluates the same rows first (`capability/index.ts:L418-L429` vs `entitlement/index.ts:L201-L224`); only the manifest `killSwitchFlag` and provider-collection halves of stage 5 are live. [Stage 9 #5]
36. **`perRequestTokenCeiling` not independently trippable with the published manifest** — 9 024 − 1 024 = 8 000 = `maxInputTokens`; both stage-7 predicates trip together (`context/preflight.ts:L101-L112`). [Stage 9 #6]
37. **Missing-policy / missing-handoff post-accept failures leave `ai_request` `Accepted`** — Stage 10 doc §16/§19.3.2 claims `Failed`; code only pushes the SSE `failed` event (S10-003, S10-015, S10-034). [Stage 10 #1, #2; superset of #24]
38. **`ai_attempt.selection_reason` is not a D1 column** — values exist only on the in-memory `AttemptRecord` (`invocation/index.ts:L21-L24`); migration `20260731120000_platform_schema.sql:L86-L100` has no such column (S10-008, S10-011, S10-030). [Stage 10 #3]
39. **`text_delta.data` omits `trace_id`** — the broker puts it on the event wrapper; `encodeSseEvent` serializes only `event.data` (S10-001). Doc §4.1/§11.4 contract tables not updated. [Stage 10 #4]
40. **Structured relay path documented as live but never wired** — `createStructuredStreamBroker` (`stream/structured.ts:L177`) and `validateAndRepair` (`validate/index.ts:L87`) have no caller in `worker.ts`; `progress`/`partial_structured`/commit-time validation/reask are unreachable on `POST /v1/requests`. Conversely `regenerating` IS reachable for visit summary (invocation-loop origin, S10-029…S10-031). [Stage 10 #5]
41. **`AdapterDisconnectReason "network_drop"` is dead** — all three adapter call sites pass `"client_close"` (`adapter.ts:L529, L543, L555`). [Stage 10 #6]
42. **Unknown-provider fallback token misnamed but behavior-correct** — `resolveProviderPort` scripts `terminal:provider_unavailable` for unknown ids (`worker.ts:L358`), but retryability is recomputed from the taxonomy → treated as retryable, retries/falls back (S10-005). [Stage 10 #7]
43. **`cancelled` on a true client drop is emitted into a dead stream** — unobservable on the dropped connection (`adapter.ts:L472-L474`); replay-based observation documented (S10-013/014/019). [Stage 10 #8]
44. **Stage-12 doc §1 lists `installation_suspended` under HTTP 401 — code maps 403** (`worker.ts:L1391`, `errors.ts:L35-L40`); the doc's own probe §5.3.4 correctly expects 403 (internal inconsistency). [Stage 12 #1]
45. **Stage-12 doc omits the quota-inspect route and the dashboards entirely** (S12-056…S12-072). [Stage 12 #2]
46. **Reference normalization asymmetry** — support lookup **trims** before normalizing (`support-purge.ts:L34`); the clinic GET does not (`worker.ts:L1380`); a padded reference 404s on GET (S12-016) but succeeds on lookup (S12-042). Also: doc §5.3.4's "worker dispatches `/control/*` only on POST" is overbroad — GET is dispatched for quota inspect (`worker.ts:L1353-L1358`). [Stage 12 #3, #4]
47. **Defensive/code-only branches with no doc mention** — Failed with NULL `terminal_error_code` → `internal_error` fallback (S12-006); unknown state string → 404 (S12-010); corrupt R2 envelope → `{state:"Completed"}` (S12-004); lookup envelope fallback key when `payload_pointer` NULL (S12-052); quota inspect with missing entitlement row → nulls (S12-061). [Stage 12 #6]
48. **Credit RPC fields doc self-contradiction** — Stage 11 doc §3 lists `jti`/`idempotencyKey` on `kind: credit`; `CreditRequest` has neither (`quota-do/index.ts`); the doc's own §10.3.6 is correct. [Stage 11 #1]
49. **Trigger-URL doc-vs-doc conflict** — doc 15 §11.3.6 fires `/cdn-cgi/handler/scheduled?cron=…`, doc 17 §3.3.15 fires `/__scheduled?cron=…`; code-agnostic (wrangler test endpoint) but the docs disagree. Also doc 17 §3.3.15 compresses the two purges (pointer NULLing happens at the diagnostic horizon, SX-024; the 90 d journal purge deletes the row, SX-028). [Stage X]
50. **Terminal `timeout` unreachable** — see Register 1A; the orientation doc §9 table lists `timeout` as a failed-settlement taxonomy, but chain exhaustion always settles `provider_unavailable` (`invocation/index.ts:L755-L761`; S11-004). [Stage 11 #2]
51. **Cancelled-during-invoke writes an attempt row** — caller-abort is terminal-classified, so an abort during an in-flight invoke records `outcome 'terminal_failure', error_code 'cancelled'` (S11-008); only a pre-attempt abort yields zero rows (S11-009). Doc §9 under-specifies. [Stage 11 #3]
52. **`usage_event` is never written by the Quota DO** — only by `persistPostResponseDetail` (journal, D1); the DO mutates only its own storage (S11-001, S11-012). [Stage 11 #4]
53. **Replay of a failed request loses the original code** — `replayIdempotentTerminal` emits `failed/internal_error` for any prior failed state (`worker.ts:L631-L634`); the DO idempotency entry stores state, not the code (S11-014). [Stage 11 #5]
54. **`record_ai_acceptance` duplicate pre-check is broader than the UNIQUE constraint** — rejects on `(ai_request_reference, table_name)` alone vs constraint `(table_name, record_id, ai_request_reference)` (S11-025 case b). Provenance records the **visit id** under `table_name 'visit_clinical_notes'` (S11-022). [Stage 11 #6, #7]
55. **Worker cancelled branch's non-skipCredit sub-path is defensive** — `broker.disconnect()` synchronously sets `brokerTerminal` before the check (`worker.ts:L931-L945`, `stream/index.ts:L472-L488`). [Stage 11 #8]
56. **`repair` attempt outcome unreachable for `clinic.visit_summary`** — `repairPolicy.allowed: false, maxAttempts: 0`. [Stage 11 #9]
57. **Doc 15 incomplete on grace-reconcile outcomes** — code has five `GraceDropReason`s (`credit/index.ts:L51-L57`); doc mentions only TTL/max-attempts and the happy reconcile (SX-015…SX-017 code-derived, doc-silent). Doc also silent on reconcile-time `quota_exhausted` retry-churn (SX-014) and the SX-018 leak (admit succeeds, credit transport fails → replay-drop next tick; in-flight leaks until the abandoned sweep, SX-046). [Stage X]
58. **Docs omit most of the retention surface** — code also purges `usage_rollup` (SX-034), `control_audit` and `capability_grant` at 2555 d including live grants (SX-035), and `platform_counter` at 90 d (SX-036); `kill_switch` is never purged (SX-036). [Stage X]
59. **`reconcile_first_seen_at_ms` TTL origin** — TTL cannot fire on first sighting; `queued_at` age is irrelevant (SX-021). Docs don't state this. [Stage X]
60. **Sweep ordering nit** — `sweepEphemeral` deletes expired `jtiReplay` entries *before* the abandoned-admission sweep (`quota-do/index.ts:L233-L254`); doc 18 §4's ordering claim is imprecise. [Stage X]
61. **`usage_rollup` has no in-repo reader** — dashboards read `ai_attempt`/`ai_request`/`platform_counter` only; the rollup cron writes a table nothing consumes. [Stage X]
62. **No injection through the scheduled handler** — `bindings.now`/`window`/`ReconcileGraceContext.now` are unreachable via cron (`worker.ts:L1447-L1495` passes none); only direct job-function calls inject time. Also: **no `try/catch` in `scheduled()`** — a flush failure aborts the tick (SX-004); **no DO `alarm()`** — all sweeps are lazy. [Stage X]
63. **Discovery D1-reads table incomplete** — the code additionally reads `keys`, `token_contracts`, and the lifecycle overlay grant shape (`identity/index.ts:L307-L315, L363-L371`; `capability/index.ts:L88-L116`). Failure-paths section omits `403 installation_suspended` (`identity/index.ts:L356-L358`, S07-023). [Stage 7 #1, #2]
64. **Discovery revocation semantics undocumented** — the production reader filters `revoked_at IS NULL` (`config-cache/index.ts:L319-L332`), so the `grant.revoked_at != null → skip` branch in `discover()` (`capability/index.ts:L724-L726`) is unreachable via the production reader, and an installation-scope revocation does not remove the capability when a plan grant exists (S07-034). [Stage 7 #3]
65. **Discovery cosmetics** — TTL constant named `DEFAULT_CONFIG_CACHE_TTL_MS`, not `CACHE_TTL_MS` (deprecated alias); bare `Bearer` vs `Bearer `+whitespace log-reason distinction (`invalid_authorization_scheme` vs `empty_bearer_token`); role/scope non-filtering implied but never stated (S07-041); ETag contains no per-installation input (S07-050). [Stage 7 #4…#7]
66. **No Content-Type check and no header length/charset bounds at ingress** — mission brief overstated; code validates only non-empty-after-trim (`adapter.ts:L242-L268`); any content type passes (S08-016, S08-024, S08-025). [Stage 8 #1, #2]
67. **Doc probe 8.3.9 contradicts code on `user_intent` fall-through** — `extractUserIntent` falls through to the `intent` alias when `user_intent` is non-string (`worker.ts:L261-L269`); the doc claims the alias value is ignored (S08-054). [Stage 8 #3]
68. **Unreachable second parse check in the adapter** — `adapter.ts:L409-L413` re-parses what `L390-L393` already proved; dead code, flagged for cleanup. [Stage 8 #4]
69. **Latent unreachable mappings** — `cancelled` would map to HTTP 500 at preAccept (`liveHttpStatusForCode` null → fallback, `adapter.ts:L224`); the guard never returns `cancelled` from preAccept. `context_requested`/`AwaitingContext` are not reachable at ingress (conversational-only). [Stage 8 #6, #7]
70. **Stage-8 defensive `exp` recheck unreachable via `POST /v1/requests`; `input.principal` harness path undocumented** — stage 2 rejects expired tokens first (`admission/index.ts:L591-L601` vs `identity/index.ts:L286-L291`); the harness-only `input.principal` path (`pipeline/index.ts:L328-L330`) is never used by the production worker. [Stage 9 #7]
71. **Idempotent replay of an in-flight prior state is replayed as a synthetic `completed`** with canned content `"Prior request completed."` (`worker.ts:L623-L630`) — doc §14.3.11's "replays the prior terminal outcome" is inaccurate for non-terminal prior states (S10-017). [Stage 9 #8]
72. **Stage-10 compose failure leaks the admission reservation until the 2 h sweep** — stage-9 journal failure releases the DO reservation (`pipeline/index.ts:L499-L505`); stage-10 compose failure only records `Failed` (`pipeline/index.ts:L519-L528`); `inFlight` persists until the sweep (`quota-do/index.ts:L209-L231`). [Stage 9 #9]
73. **Composed `correlationIds.trace_id` is the AAT `jti`, not the `x-trace-id` header** (`prompt/composer.ts:L413-L416`); the journaled `ai_request.trace_id` IS the header value. No doc calls out the divergence. [Stage 9 #11]
74. **Rejection-tally coverage is uneven by stage** — stages 2–4 and admission failures call `recordGuardRejection`; capability (5), context (6), preflight (7) do not — a second, undocumented `platform_counter` lower-bound reason beyond isolate eviction. [Stage 9 #12]
75. **`rotate_installation_key` guard scope (doc wrong, code authoritative)** — doc says rotate requires an active key; code looks up ANY non-deleted row with no `revoked_at` filter (`20260801120100…sql:L103-L115`), so rotate succeeds when all keys are revoked but rows remain (S02-023); `INSTALLATION_NOT_ENROLLED` only with an empty/fully-soft-deleted keystore (S02-003). [Stage 2 #1]
76. **`issue_ai_token` error shape misdescribed** — doc expects an `rpc_result` envelope; the function returns `text` and RAISEs (`INSTALLATION_NOT_ENROLLED` etc., P0001) → PostgREST HTTP error, not an envelope. Stage 6 doc §5's error table is also incomplete (omits `UNAUTHENTICATED`, `SESSION_EXPIRED`, `STAFF_NOT_FOUND`). [Stage 2 #2, Stage 6 #3]
77. **`SINGLE_INSTALLATION_VIOLATION` is not an envelope error and is unreachable via RPC** — the trigger RAISEs it; callers see a raised Postgres error, never `error_code = 'SINGLE_INSTALLATION_VIOLATION'` (S02-021). [Stage 2 #3]
78. **~~Revoke success payload timestamp~~ — Fixed (BUG-11).** Fresh-revoke re-SELECTs after UPDATE and returns the stored `revoked_at` (`20260905120600_revoke_fresh_return_stored_revoked_at.sql`), matching the idempotent branch. [Stage 2 #4]
79. **"Owner" terminology** — the `owner` role was removed (`20260611150000`); the gate accepts `role = 'administrator'` OR `is_bootstrap_admin = true`. Doc §3/§5 error tables still say "owner or administrator"; Stage 6 doc calls the bootstrap admin "Owner". [Stage 2 #5, Stage 6 #4]
80. **No `set_ai_availability` write RPC exists** — doc §4's "manual step" gap is real; enroll/rotate/revoke never write `app_settings` (S02-011). Also: role check precedes ALL other validation in every keypair RPC (S02-005, S02-006, S02-012). [Stage 2 #6, #7]
81. **Seed default AAT lifetime is platform-incompatible** — `ai.aat.lifetime_minutes = 15` (→ 900 s) while `EnrolledKeyVerifier` rejects `exp − iat > 600`; a default-configured clinic mints tokens the platform always rejects (S06-043). [Stage 6 #2]
82. **Branch tie-break undocumented** — alphabetical branch-name fallback when no assignment is primary (S06-024). [Stage 6 #5]
83. **Defensive dead branches in the issuer** — the second `UNAUTHENTICATED` raise (claims without `sub`) and the second `STAFF_NOT_FOUND` raise are unreachable; recorded so no chapter invents scenarios for them. [Stage 6 #6]
84. **Control-dispatch default 404 is dead code** — `control/index.ts:L194-L197` (`default:` in the install-action switch) can never fire: `isControlRoute`'s `CONTROL_ACTION_PATTERN` (`control/index.ts:L69-L71`) pre-filters to exactly the eight handled actions. [Verification pass]
85. **Guard stage-8 unexpected-outcome `internal_error` is dead code** — `pipeline/index.ts:L466-L469` handles an admission outcome that is neither allow nor refusal; `admissionRPC`/`admission/index.ts` produce no third outcome. [Verification pass]

**Other inter-chapter contradictions found (beyond #1):** none remaining. The apparent
Stage 8 (#30) vs Stage 9 period_reset entries agree; the Stage 3/4/5 `invalid_route` entries agree;
Stage 5 #2 and Stage 10 #1/#2 describe the same skip-settlement gap (merged as #24/#37);
Stage 11 #1 and Stage X's trigger-URL item are intra-doc (not inter-chapter) contradictions,
recorded as #48/#49.

---

## Register 5 — Non-Automatable Register

Consolidated and deduplicated from the `## Non-automatable notes` sections of all 14 chapters.
"Cannot run against the real worker" means against the real worker/bindings under
`@cloudflare/vitest-pool-workers`. Repeated items are merged with all attributions.

| # | Scenario / behavior | Why it cannot run against the real worker in the pool | Proposed seam | Chapters |
|---|---------------------|--------------------------------------------------------|---------------|----------|
| 1 | Missing DB/R2/DO bindings at boot (S00-001…S00-003) | The pool always supplies the bindings declared in the test `wrangler.toml`; a binding cannot be removed per-test | Module-level mock of `cloudflare:workers` (`env`) in a plain (non-pool) vitest suite importing `src/worker.ts` and asserting the throw; or the ops probe (comment out a binding stanza and observe boot failure) | Stage 0 |
| 2 | Missing-binding branches inside handlers: `missing_r2_binding` (S03-083, S05-016, support lookup), `503 quota_do_unavailable` (quota inspect), S03-083 binding shape | The deployed/test worker always binds R2 and DO via wrangler config | Direct handler/`dispatchControlRequest` invocation with a partial `ControlBindings` object (unit-level workers test; not via `SELF.fetch`) | Stages 3, 5, 12 |
| 3 | Malformed bundled manifest at runtime (S00-007) | The manifest is a static JSON import baked at build time; cannot become malformed in a running isolate | Harness registry seam `setCapabilityRegistry(new Map(), { replace: true })` reproduces the end-state; the throwing-`load()` arm is covered at build time by S00-032 | Stage 0 |
| 4 | Migration re-apply idempotency (S00-028); grant-migration `ON CONFLICT DO UPDATE` branch (Stage 2 note 3) | The pool applies migrations once per test database; `d1_migrations` tracking is platform behavior; migrations run exactly once in order | Wrangler CLI ops probe (`wrangler d1 migrations apply` twice against a throwaway local D1); migration-replay test | Stages 0, 2 |
| 5 | Log-verbosity behavior (S00-012…S00-014) | Requires capturing the worker isolate's `console` output, which the pool may not expose per-isolate | Drive the same handlers through a logger factory built with an injected `LogSink` (seam exists in `createLoggerFactory`) | Stage 0 |
| 6 | **Multi-isolate limits** — cross-isolate `isolateConfigCache` sharing/eviction, `platform_counter` lower bound from evicted unflushed tallies, cache divergence between isolates | The pool runs a single isolate; there is no second isolate whose state can diverge or be evicted | None in-pool; document-only (code comments: `rate-limit/index.ts:L149-L158`). Single-isolate staleness IS automatable via injected `ConfigCache` / `cache.clear()` | Stages 0, 5, 7, 12, X |
| 7 | Isolate-cache staleness between a control mutation and a subsequent identity/discovery read (S01-025/026/029, S05-059, S07-051/052, S12-039/040) | Module-global cache persists across tests in a file → flakes; per-test TTL variation impossible through the worker entrypoint (boot-time wiring, `worker.ts:L147-L149`) | `CONFIG_CACHE_TTL_MS="0"` (or a few hundred ms) in the test env; injected `new ConfigCache(...)`; `isolateConfigCache.clear()` between tests | Stages 1, 5, 7, 12 |
| 8 | Uncaught-TypeError scenarios (S01-013, S01-017, S04-091) | In the pool the `fetch` promise rejects instead of returning a Response; the production 500 body shape is runtime-generated and not meaningfully assertable | Assert "rejects with TypeError"; do not pin an HTTP body | Stages 1, 4 |
| 9 | **Timing-safe compare** (`timingSafeEqualString`, `control/auth.ts:L4-L14`) | Side-channel property; constant-time behavior is not observable over HTTP in the test environment | Assert only functional outcomes (exact 401 body for every non-matching credential) | Stages 1, 3, 4 |
| 10 | **Concurrency races** — concurrent begin-rotation (Stage 1 note 4), concurrent publish → UNIQUE 409 (S05-020), concurrent-mint advisory lock (Stage 6 note 1), S12-009 live in-flight race | Single-threaded local D1/miniflare serializes requests; deterministic interleaving cannot be forced | Direct handler-batch invocation against one D1 asserting exactly one `meta.changes > 0`; fault-injecting D1 wrapper throwing the UNIQUE error; load harness for the advisory lock; [SEED] fallback for S12-009 | Stages 1, 5, 6, 12 |
| 11 | Handler clock values (`added_at`, `recorded_at` from `new Date().toISOString()`) | No clock-injection seam exists in the control handlers | Assert format and approximate equality only | Stage 1 |
| 12 | **PostgREST-level HTTP shape** — anon 401/403 (S02-002, S06-001), raised-exception status/body (S11-028), `issue_ai_token` raise-vs-envelope | Requires a running PostgREST instance; the exact HTTP mapping is API-gateway behavior, not pinned by migrations | Assert SQL-level denial (42501/P0001) in `supabase test db`; treat HTTP mapping as PostgREST convention / manual verification | Stages 2, 6, 8, 11 |
| 13 | `is_bootstrap_admin` escape hatch for a non-administrator | No migration or RPC can produce that state (seeded bootstrap admin is always `administrator`); reaching it needs a privileged direct UPDATE | Recorded, not scenarized | Stage 2 |
| 14 | **Non-deterministic values** — JWK `x`, kid, installation_id, jti (`gen_random_uuid`, `pgsodium.crypto_sign_new_keypair`) | Random by design | Assert shapes, encodings (43-char unpadded base64url), lengths, and round-trip relationships — never literals | Stages 2, 6 |
| 15 | pgsodium availability | Enroll/rotate require the `pgsodium` extension + `pgsodium_keymaker` grant; a bare-Postgres rig without pgsodium cannot execute S02-009/013/020/022/023 | Use the local Supabase CLI stack (pgsodium present by default) | Stages 2, 6 |
| 16 | jti collision (SQLSTATE 23505 from the ledger's `UNIQUE (jti)`) | Not reproducible on demand; not a coded issuer error | None | Stage 6 |
| 17 | Platform half of the minted-then-rejected journeys (S06-041…S06-047) | Requires the ai-platform worker with D1 config rows; belongs to Stage 9's executable surface | Scenarios pin the exact token variants; Stage 9 executes the rejection half | Stage 6 |
| 18 | Flutter-side behavior (hiding AI chrome while `enrolled = false`) | Client behavior outside this repo's SQL contract surface | Manual probes (orientation doc §8.3.2/§8.3.13) | Stage 2 |
| 19 | **`500 storage_error` and unguarded-batch 500s** — `runControlBatch` non-constraint failure (all six lifecycle handlers, entitle, publish); cohort/capability-lifecycle unguarded batches | Real D1 in the pool does not fail on demand for valid statements | Fault-injecting `D1Database` wrapper/proxy whose `batch()` throws a non-constraint error (e.g. `Error("disk I/O error")`), passed via the `bindings` parameter — no module mocking needed. Note the publish orphan window (R2.put precedes the batch) | Stages 3, 4, 5 |
| 20 | `requireValidPublicKey` import-failure branch (enroll/rotate) | `crypto.subtle.importKey("raw", <any 32 bytes>, "Ed25519")` succeeds for every length-valid input in the Workers runtime | Stub `crypto.subtle.importKey` to throw for one test | Stage 3 |
| 21 | **`400 invalid_route` branches** in all control handlers | Unreachable through the worker's HTTP surface — dispatch pre-filters with identical regexes (Register 1B, Register 4 #12) | Invoke handlers directly with a crafted `Request` bypassing dispatch | Stages 1, 3, 4, 5, 12 |
| 22 | Purge mid-sequence failure (partial purge) | Real R2/D1 bindings cannot be forced to fail selectively | Stub `R2Bucket.delete` to throw on the first object; assert the intent audit row exists, the completion row does not, non-JSON 500 | Stage 3 |
| 23 | **Wall-clock waits** — 90-day retire overlap window, 30 s config-cache TTL, 2 h DO ephemeral horizons (abandoned-admission sweep, jtiReplay/creditedRequests expiry), retention horizons (7/30/90/2555 d), reconciliation windows, 15 s heartbeat (S10-033) | The Workers clock cannot be advanced by the pool; hardcoded intervals (`capability/index.ts:L45-L46`, `worker.ts:L285-L306`) are not controllable via `vi.useFakeTimers` | [SEED] backdating (`retire_after`, aged rows); injectable `now` on DO RPCs (`worker.ts:L1263-L1266`) and direct job-function args; `new ConfigCache(0/50)` / `cache.clear()`; heartbeat only at wall-clock cost (~16 s) unless a ticker-injection code change is made. The un-seeded overlap boundary (`now == retire_after`) remains uncovered | Stages 4, 5, 7, 9, 10, 11, X |
| 24 | `cost_budget` `Number.isFinite` guard (`entitle.ts:L110`) | JSON cannot encode `NaN`/`Infinity`; `request.json()` rejects them as `invalid_json` first | Documented only; no HTTP scenario possible | Stage 4 |
| 25 | Multi-operator audit attribution | Single-operator deployment: every valid bearer maps to one configured `operatorId` (`control/auth.ts:L16-L26`); no `control_operator` table, no per-operator rotation/revocation | None — not implemented | Stage 4 |
| 26 | Router-seam scenarios (S05-060, S05-061, S05-078, S05-082) | Inputs the bundled manifest set cannot produce (legacy `@vN` refs, structured-output requirement, multi-language floors, non-hardwired cost sources) | Call `selectCandidateChain`/`createD1ConfigReader` directly against real migrated D1 + real R2; re-express as full-path journeys if such manifests ship | Stage 5 |
| 27 | Kill-switch writes (S05-069, S05-070) | No control-plane endpoint writes `kill_switch` in this codebase | [SEED] direct D1 inserts; grow a control-plane variant if a route is added | Stage 5 |
| 28 | **Quota DO failure injection** — DO outage at credit time (S11-021 e2e variant), DO 4xx/wrong-kind/5xx on admission (S09-079 variants), genuine DO outage/eviction (SX-013, SX-017, SX-018, SX-022), mid-flush/mid-tick D1 failure (SX-004, SX-008) | One `env.DO` binding per suite; the in-pool DO cannot be taken down mid-request; real D1 does not fail on demand | Stub/facade `DurableObjectNamespace` whose `stub.fetch` throws or scripts responses; proxy shim around the D1 binding throwing on targeted SQL; component-level coverage with the real GatewayObject for state-machine assertions | Stages 9, 11, X |
| 29 | S09-082 (stage-9 journal INSERT failure) | The DO-issued `request_id` cannot collide; the DO idempotency check prevents duplicate inserts | Wrapping `D1Database` double whose `prepare` throws only for the `ai_request` INSERT, or a test-only migration adding a marker-trigger | Stage 9 |
| 30 | S09-050 (manifest `killSwitchFlag: true`) | The published registry contains only `clinic.visit_summary@1.0.0` (`killSwitchFlag: false`) | Test-authored second manifest via `createCapabilityRegistry`/`setCapabilityRegistry({ replace: true })` — a fixture, not production state | Stage 9 |
| 31 | CF rate-limiter hint semantics (S08-044, S09-040, S09-042) | The real `RateLimit.limit()` outcome's `retryAfter` presence/shape is not forceable in the local pool | Doubled bindings injecting `{success:false, retryAfter}` explicitly; the fallback-to-60 path (S09-041) is fully automatable with a hint-less double | Stages 8, 9 |
| 32 | Stage-8 defensive `exp` recheck and the `input.principal` harness path | Not reachable as a full-path `POST /v1/requests` journey; would require invoking `runGuard` directly (violates the full-path principle) | Recorded, not scenarized | Stage 9 |
| 33 | **Live provider wire behavior** — DeepSeek/Gemini request shaping, HTTP failure classification, SSE parsing, `finish_reason`/usage edge cases, 1 MiB provider-body limit, raw-body 16 KiB cap truncation (S11-018/019), provider `Retry-After` honored in backoff | Requires real provider HTTP traffic | Stub `globalThis.fetch` in the pool isolate (`createFetchTransport` binds it lazily, `fetch-transport.ts:L33-L55`) plus `DEEPSEEK_API_KEY`/`GEMINI_API_KEY` test bindings; until then only the missing-key terminal path is covered (S10-009). Real-provider settlement belongs to `test/eval/live-smoke.test.ts` / manual verification | Stages 10, 11 |
| 34 | Deadline-driven invocation branches (deadline-exhausted skip, `sleepWithinDeadline` truncation, `min(timeout_ms, remaining)`) | Production pre-accept never sets `GuardInput.deadline`; `CanonicalRequest.deadline` is always `null` on the live path (`worker.ts:L1052-L1085`) | Unit tests of `runInvocation` with an injected deadline; no POST-level seam without a code change | Stage 10 |
| 35 | Missing accept context (S10-034) | The store is request-scoped and pre-accept always populates it before the event source runs in the same call | `Map.prototype.get` spy seam (described in the scenario) | Stage 10 |
| 36 | **`context_requested` terminal / `AwaitingContext` rows / unpublished-capability rows** (S08 note 7, S10 note 7, SX-031, SX-043, SX-025) | The sole published manifest is `single_shot`; neither broker emits `context_requested` and `pushTerminalEvent` throws for `single_shot` (`adapter.ts:L122-L128`) | [SEED] with justification for cron/retention coverage; cover the terminal properly when a conversational capability ships | Stages 8, 10, X |
| 37 | Content-Length header control (S08-003, S08-005, S08-009) | Workerd may normalize or strip a user-supplied `Content-Length` on constructed `Request` objects | Raw TCP/HTTP client or undici with explicit headers against `wrangler dev`; rely on stream-path scenarios (S08-004/006/007) in-pool | Stage 8 |
| 38 | Disconnect timing races (S08-056, S08-057) | Client-abort races are timing-sensitive | Assert steady-state outcomes (stream closed, no `cancelled` frame, single `disconnect("client_close")`, eventual `Cancelled` journal state) | Stage 8 |
| 39 | Adapter-contract scenarios (S08-058, S08-060) | Unreachable through production wiring — `handleLivePostRequest` always supplies both `preAccept` and `eventSource` | Invoke the real `handleAdapterRequest` directly (no internal functions called) | Stage 8 |
| 40 | SSE `connection: keep-alive` header (S08-049) | Some runtimes/proxies strip hop-by-hop headers on constructed responses | Assert `content-type`/`cache-control` in-pool; verify `connection` against `wrangler dev` | Stage 8 |
| 41 | Context-provider RPC scenarios (S08-061…S08-069) | They run against Supabase/PostgreSQL, not the workers pool; need role/claims impersonation (`request.jwt.claims`) | pgTAP suite or PostgREST harness in the backend test stack | Stage 8 |
| 42 | Journal write failure is log-only; R2/D1 write-order interleaving (pointer without object, object without pointer) | `writePostResponseDetail` catches and logs; forcing a D1/R2 fault mid-settlement or a crash between steps is not available in the pool | Fault injection / process-kill in a manual run; cron reconciliation later flags the missing rows | Stage 11 |
| 43 | S12-060 (verbose truncation at 500 entries) | Automatable but slow (501 direct DO admissions) | Mark as extended/slow suite | Stage 12 |
| 44 | Platform cron triggering (`0 3 * * *` firing at 03:00 UTC); `ScheduledController.retry`/`noRetry` semantics | Platform behavior; the handler never calls `retry`/`noRetry` | Invoke `worker.scheduled({cron})` directly in all scenarios | Stage X |
| 45 | SX-063 (GatewayObject catch-all 500 `internal_error` via storage fault) | Real DO storage cannot be forced to throw in the pool | DO `storage` double whose `get`/`put` throws (same family as Register 5 #28's fault-injection seams) | Stage X |

---

*End of registers. Scenario counts per chapter: S00=37, S01=31, S02=27, S03=83, S04=104, S05=85, S06=47, S07=52, S08=69, S09=85, S10=34, S11=29, S12=72, SX=63 (total 818). Post-verification fix pass: added S04-101…S04-104, S05-084/S05-085 (wrong-bearer auth cells), SX-057…SX-063 (GatewayObject DO branches), corrected 8 drifted line anchors, fixed the S09-084 missing Action row, and corrected the stale Stage 6 guard claim at its source.*
