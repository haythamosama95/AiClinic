# Stage 04 — Entitlement and capability grants

Source files read: `ai-platform/src/control/entitle.ts`, `ai-platform/src/control/capability-lifecycle.ts`, `ai-platform/src/control/cohort.ts`, `ai-platform/src/control/auth.ts`, `ai-platform/src/control/http.ts`, `ai-platform/src/control/audit.ts`, `ai-platform/src/control/types.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/control/lifecycle.ts` (enroll's pending-entitlement insert only), `ai-platform/src/entitlement/index.ts`, `ai-platform/src/capability/index.ts` (registry + `OVERLAP_WINDOW_MS`), `ai-platform/src/quota-do/index.ts` (`isSoftThresholdFraction` / `coerceSoftThreshold`), `ai-platform/src/platform-vocabulary.ts` (plan tiers), `ai-platform/src/worker.ts` (control-route gating + registry install), `ai-platform/migrations/20260731120000_platform_schema.sql`, `ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql`, `ai-platform/migrations/20260821130000_entitlement_installation_unique.sql`, `docs/architecture/ai-platform/data-journey/06-stage-4-entitlement-and-capability-grants.md` (orientation only).

## Conventions and shared fixtures

- **I0** = `0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b` — installation enrolled via Stage 3 enroll happy path (`plan: "professional"`), leaving entitlement `pending` with zero quotas, `allowed_capabilities = '[]'`, `soft_threshold = 0` (`control/lifecycle.ts:L274-L280`).
- **I1** = `1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c` — second installation enrolled via Stage 3 enroll happy path (`plan: "standard"`), entitlement `pending`.
- **Operator auth**: header `Authorization: Bearer test-operator-token` against env `OPERATOR_BEARER_TOKEN = "test-operator-token"`, `OPERATOR_ID = "platform-operator"` (`control/auth.ts:L27-L51` — `createSecretOperatorAuth`).
- **Registry seam**: production installs only `clinic.visit_summary@1.0.0` (`worker.ts:L151-L159`). Scenarios needing a second version install an in-memory registry containing `clinic.visit_summary@1.0.0` **and** `clinic.visit_summary@2.0.0` via `setCapabilityRegistry(..., { replace: true })` before the request. This is a code seam, not a D1 seed, and is marked **[REGISTRY]** where used.
- **REF-BODY** (the doc §6 visit-summary entitle body, used as the base for one-field mutations):

```json
{
  "period_start": "2026-08-01T00:00:00.000Z",
  "period_end": "2026-09-01T00:00:00.000Z",
  "request_quota": 1000,
  "token_budget": 500000,
  "cost_budget": 50.0,
  "soft_threshold": 0.8,
  "allowed_capabilities": ["clinic.visit_summary"],
  "grants": [
    { "capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "installation" }
  ]
}
```

- All entitle failure scenarios assert the same negative side effect unless stated otherwise: entitlement row for I0 unchanged (`status = 'pending'`, zero quotas, `allowed_capabilities = '[]'`), zero `capability_grant` rows for I0, no new `control_audit` row with `action = 'entitle'`.
- Lifecycle state machine implemented by `handleDeprecate` / `handleRetire` over the latest `scope = 'global'` overlay row (`capability-lifecycle.ts:L35-L50` — `loadGlobalOverlay`):

| From | Operation | To | Result | Scenario |
|------|-----------|----|--------|----------|
| (no overlay) | deprecate, valid successor | `deprecated` | 200 | S04-086, S04-087 |
| (no overlay) | retire | — | 400 `not_deprecated` | S04-094 |
| `deprecated` | deprecate, same successor | `deprecated` (no-op) | 200 idempotent | S04-088 |
| `deprecated` | deprecate, different successor | — | 409 `already_deprecated` | S04-089 |
| `deprecated`, now < `retire_after` | retire | — | 400 `overlap_window_active` | S04-095 |
| `deprecated`, now ≥ `retire_after` | retire | `retired` | 200 | S04-098 |
| `retired` | deprecate | — | 409 `already_retired` | S04-090 |
| `retired` | retire | — | 400 `not_deprecated` | S04-099 |

## 3. API: `POST /control/installations/{installation_id}/entitle`

**Handler:** `control/entitle.ts` → `handleEntitle`. **Auth:** operator bearer (`requireOperator`).

Malformed control paths fall through to HTTP 404 plain-text `Not Found` at the worker router — not `400 invalid_route` (dispatch pre-filters with handler-identical regexes; the handler's `invalid_route` branch is a direct-invocation seam only — see Doc-drift #7).

#### D1 writes

1. **UPDATE** `entitlement` — budget fields + `status='active'` (`WHERE installation_id = ?`).
2. **INSERT** `capability_grant` per grant item — **plan-scope dedup:** when a grant has `scope: "plan"` and a live row already exists at `plan:{plan}` for the same `capability_id` (`revoked_at IS NULL`), the insert is **skipped** while activation still proceeds (`entitle.ts:L239-L245`; S04-054).
3. **INSERT** `control_audit` — `action='entitle'`, `after_pointer` = JSON of `allowed_capabilities`.

**Not updated:** `entitlement.plan`, `installation.status`.

## 5. Failure paths (entitle)

| HTTP | `error` | Trigger |
| ---- | ------- | ------- |
| 401 | `unauthorized` | Missing / wrong / malformed operator bearer; unconfigured operator secret (S04-001–S04-005) |
| 400 | `invalid_json` | Body does not parse as JSON (S04-006) |
| 400 | `invalid_payload` | Bad numbers, empty `grants`, bad `scope`, non-ISO `period_start`/`period_end`, or `period_start >= period_end` (S04-007–S04-046) |
| 404 | `installation_not_found` | No `installation` row (S04-047) |
| 404 | `entitlement_not_found` | No `entitlement` row (S04-048) |
| 409 | `not_pending` | `status !== 'pending'` (S04-049, S04-051) |
| 500 | `storage_error` | D1 `batch` failure via `runControlBatch` (S04-057) |

## 7. Failure paths (cohort activate)

**Body:** `installation_ids` (required non-empty array); optional `cohort_name` (audit `target` suffix). Duplicate `installation_ids` in one request are deduped before the grant loop (`cohort.ts` — `[...new Set(body.installation_ids)]`; S04-070).

| HTTP | `error` | Trigger |
| ---- | ------- | ------- |
| 401 | `unauthorized` | Missing / wrong operator bearer (S04-058, S04-103) |
| 400 | `invalid_json` | Body not JSON (S04-061) |
| 400 | `missing_installation_ids` | Field absent, not an array, or empty array (S04-062–S04-064) |
| 404 | `capability_not_found` | `{capability_id}@{version}` not in registry (S04-059, S04-060) |
| 404 | `installation_not_found` | Any listed id missing from `installation` (S04-065) |
| 500 | `storage_error` | D1 batch failure via `runControlBatch` |

## 8. Failure paths (cohort promote)

**Request body:** ignored entirely — no `parseJsonBody`; malformed JSON, wrong content type, or any body succeeds identically (S04-079).

| HTTP | `error` | Trigger |
| ---- | ------- | ------- |
| 401 | `unauthorized` | Missing / wrong operator bearer (S04-072, S04-104) |
| 404 | `capability_not_found` | `{capability_id}@{version}` not in registry (S04-073) |
| 500 | `storage_error` | D1 batch failure via `runControlBatch` |

## 9. Failure paths (deprecate)

| HTTP | `error` | Trigger |
| ---- | ------- | ------- |
| 401 | `unauthorized` | Missing / wrong operator bearer (S04-080, S04-101) |
| 400 | `invalid_json` | Body not JSON (S04-082) |
| 400 | `missing_successor_id` | Missing, null, or empty-string `successor_id` (S04-083, S04-084) |
| 400 | `invalid_payload` | Truthy non-string `successor_id` (`requireNonEmptyString` type guard; S04-091) |
| 400 | `unknown_successor` | `successor_id` not in registry (S04-085) |
| 404 | `capability_not_found` | `{capability_id}@{version}` not in registry (S04-081) |
| 409 | `already_retired` | Latest overlay is `retired` (S04-090) |
| 409 | `already_deprecated` | Already deprecated with a **different** `successor_id` (S04-089) |
| 500 | `storage_error` | D1 batch failure via `runControlBatch` |

## 10. Failure paths (retire)

**Request body:** ignored entirely — no `parseJsonBody`; `400 invalid_json` is unreachable (S04-100).

| HTTP | `error` | Trigger |
| ---- | ------- | ------- |
| 401 | `unauthorized` | Missing / wrong operator bearer (S04-092, S04-102) |
| 400 | `not_deprecated` | No prior `deprecated` overlay with successor (S04-094, S04-099) |
| 400 | `overlap_window_active` | Inside overlap window or unparseable/missing `retire_after` (S04-095–S04-097) |
| 404 | `capability_not_found` | `{capability_id}@{version}` not in registry (S04-093) |
| 500 | `storage_error` | D1 batch failure via `runControlBatch` |

## 11. Behavioral verification

### 11.2 Coverage — registry-seam automatable probes

The orientation doc marks several probes **Unprobeable** because local dev ships only `clinic.visit_summary@1.0.0`. In this catalog they are **automatable** via `[REGISTRY]` `setCapabilityRegistry(..., { replace: true })` (two-version registry) and `[SEED]` `retire_after` backdating:

| Orientation §11.2 "Unprobeable" claim | Catalog scenarios |
| ------------------------------------- | ----------------- |
| Cohort split onto a second version | S04-066, S04-069, S04-074 |
| Deprecate with a different successor after deprecation | S04-089 |
| Full retire state machine (overlap window, post-window retire, second retire) | S04-094–S04-099, S04-100 |

Probes blocked by visit-summary `Access.allowedStaffRoles` (quota / degraded / runtime servability) remain **Unprobeable** in live dev — unchanged.

## Scenario S04-001 — Entitle rejects a request with no Authorization header

| Field | Content |
|-------|---------|
| ID | S04-001 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle` with `Content-Type: application/json`, body REF-BODY, **no** `Authorization` header. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None: entitlement stays `pending`; no `capability_grant` rows; no `control_audit` row. |
| Code reference | `ai-platform/src/control/http.ts:L32-L41` — `requireOperator`; `ai-platform/src/control/auth.ts:L33-L48` — `resolve` returns null without `Bearer ` prefix |

## Scenario S04-002 — Entitle rejects a wrong operator bearer token

| Field | Content |
|-------|---------|
| ID | S04-002 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, header `Authorization: Bearer definitely-wrong-token`, body REF-BODY. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` (constant-time compare fails). |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/auth.ts:L4-L14` — `timingSafeEqualString`; `ai-platform/src/control/auth.ts:L44-L46` — mismatch returns null |

## Scenario S04-003 — Entitle rejects a clinic AAT presented as bearer

| Field | Content |
|-------|---------|
| ID | S04-003 |
| Journey setup | Stage 3 enroll happy path → pending installation I0; Stage 6 mint AAT happy path → compact JWS for a doctor at I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, header `Authorization: Bearer <clinic AAT JWS>`, body REF-BODY. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — an AAT is not the operator secret; clinic staff can never entitle. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/auth.ts:L44-L46` — token compared only against `OPERATOR_BEARER_TOKEN` |

## Scenario S04-004 — Entitle rejects malformed Authorization schemes

| Field | Content |
|-------|---------|
| ID | S04-004 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | Three requests to `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle` with body REF-BODY and headers: (a) `Authorization: Basic dGVzdDp0ZXN0`; (b) `Authorization: Bearer` (no token); (c) `Authorization: Bearer    ` (whitespace-only token). |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` for all three: (a) lacks the `Bearer ` prefix; (b) lacks the prefix with trailing space; (c) token trims to empty. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/auth.ts:L37-L43` — prefix check and empty-token check |

## Scenario S04-005 — Entitle rejects every caller when the operator secret is unconfigured

| Field | Content |
|-------|---------|
| ID | S04-005 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. Worker env constructed with `OPERATOR_BEARER_TOKEN = ""` (or unset) — `worker.ts:L1360-L1363` maps missing vars to `""`. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, header `Authorization: Bearer test-operator-token`, body REF-BODY. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — `resolve` returns null when `configuredToken` or `configuredOperatorId` is empty, so no token can ever authenticate. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/auth.ts:L34-L36` — empty-config guard |

## Scenario S04-006 — Entitle rejects a non-JSON body

| Field | Content |
|-------|---------|
| ID | S04-006 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, `Content-Type: application/json`, body `not json at all{`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_json"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/http.ts:L43-L49` — `parseJsonBody`; `ai-platform/src/control/entitle.ts:L166-L169` — `handleEntitle` body parse gate |

## Scenario S04-007 — Entitle rejects a JSON null body

| Field | Content |
|-------|---------|
| ID | S04-007 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body `null`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `null` fails the object check. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L85-L88` — `validateEntitlePayload` object check |

## Scenario S04-008 — Entitle rejects a JSON array body

| Field | Content |
|-------|---------|
| ID | S04-008 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body `[{"period_start":"2026-08-01T00:00:00.000Z"}]`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `Array.isArray` is explicitly rejected. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L85-L88` — `validateEntitlePayload` object check |

## Scenario S04-009 — Entitle rejects a JSON scalar body

| Field | Content |
|-------|---------|
| ID | S04-009 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body `"entitle please"` (valid JSON string). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — a string parses as JSON but is not an object. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L85-L88` — `validateEntitlePayload` object check |

## Scenario S04-010 — Entitle rejects a missing period_start

| Field | Content |
|-------|---------|
| ID | S04-010 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `period_start` key removed. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L90-L94` — `requireNonEmptyString(body.period_start)`; `ai-platform/src/control/http.ts:L51-L56` — `requireNonEmptyString` |

## Scenario S04-011 — Entitle rejects an empty-string period_end

| Field | Content |
|-------|---------|
| ID | S04-011 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_end": ""`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — empty/whitespace strings fail `requireNonEmptyString`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L90-L94`; `ai-platform/src/control/http.ts:L51-L56` — `requireNonEmptyString` trim check |

## Scenario S04-012 — Entitle rejects a non-string period_start

| Field | Content |
|-------|---------|
| ID | S04-012 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_start": 1785513600000`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — epoch numbers are not accepted; the field must be a string. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L90-L94`; `ai-platform/src/control/http.ts:L51-L56` — `typeof value !== "string"` |

## Scenario S04-013 — Entitle rejects a date-only period_start

| Field | Content |
|-------|---------|
| ID | S04-013 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_start": "2026-08-01"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — date-only form fails the strict instant regex even though `Date.parse` could parse it. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L40-L51` — `ISO8601_INSTANT_RE` / `parseIsoInstant`; `ai-platform/src/control/entitle.ts:L54-L64` — `validatePeriodBounds` |

## Scenario S04-014 — Entitle rejects a period with a numeric timezone offset

| Field | Content |
|-------|---------|
| ID | S04-014 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_start": "2026-08-01T02:00:00+02:00"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — only the `Z` suffix is accepted; offsets fail the regex. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L40-L41` — `ISO8601_INSTANT_RE` requires literal `Z` |

## Scenario S04-015 — Entitle rejects a lowercase-z period

| Field | Content |
|-------|---------|
| ID | S04-015 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_end": "2026-09-01t00:00:00.000z"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — the regex is case-sensitive; lowercase `t`/`z` fail. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L40-L41` — `ISO8601_INSTANT_RE` |

## Scenario S04-016 — Entitle rejects a regex-passing but impossible date

| Field | Content |
|-------|---------|
| ID | S04-016 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_start": "2026-13-01T00:00:00.000Z"` (month 13). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — the regex passes but `Date.parse` returns NaN, so `parseIsoInstant` returns null. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L43-L51` — `parseIsoInstant` `Number.isFinite` guard |

## Scenario S04-017 — Entitle rejects period_start equal to period_end

| Field | Content |
|-------|---------|
| ID | S04-017 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with both `period_start` and `period_end` set to `"2026-08-01T00:00:00.000Z"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `startMs >= endMs` is rejected (a zero-length period is not a billing period). |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L54-L64` — `validatePeriodBounds` `startMs >= endMs` |

## Scenario S04-018 — Entitle rejects period_start after period_end

| Field | Content |
|-------|---------|
| ID | S04-018 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_start": "2026-09-01T00:00:00.000Z"`, `"period_end": "2026-08-01T00:00:00.000Z"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L54-L64` — `validatePeriodBounds` |

## Scenario S04-019 — Entitle accepts instants without millisecond precision

| Field | Content |
|-------|---------|
| ID | S04-019 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"period_start": "2026-08-01T00:00:00Z"`, `"period_end": "2026-09-01T00:00:00Z"` (no `.sss` fraction). |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}` — the regex makes the milliseconds group optional. |
| Side effects | Entitlement row updated: `period_start = '2026-08-01T00:00:00Z'` (stored verbatim, not normalized), `period_end = '2026-09-01T00:00:00Z'`, quotas/budgets from body, `status = 'active'`; one `capability_grant` row `scope = 'installation:0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b'`, version `1.0.0`, `revoked_at NULL`; one `control_audit` row `action = 'entitle'`. |
| Code reference | `ai-platform/src/control/entitle.ts:L40-L41` — `(?:\.\d{1,3})?` optional fraction; `ai-platform/src/control/entitle.ts:L151-L283` — `handleEntitle` |

## Scenario S04-020 — Entitle rejects a negative request_quota

| Field | Content |
|-------|---------|
| ID | S04-020 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"request_quota": -1`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `request_quota < 0` check |

## Scenario S04-021 — Entitle rejects a fractional request_quota

| Field | Content |
|-------|---------|
| ID | S04-021 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"request_quota": 1.5`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `Number.isInteger` fails. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `Number.isInteger(request_quota)` |

## Scenario S04-022 — Entitle rejects a string request_quota

| Field | Content |
|-------|---------|
| ID | S04-022 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"request_quota": "1000"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — no coercion; the JSON type must be number. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `Number.isInteger` on a string is false |

## Scenario S04-023 — Entitle rejects a negative token_budget

| Field | Content |
|-------|---------|
| ID | S04-023 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"token_budget": -500000`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `token_budget < 0` check |

## Scenario S04-024 — Entitle rejects a fractional token_budget

| Field | Content |
|-------|---------|
| ID | S04-024 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"token_budget": 500000.5`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — token budget must be an integer. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `Number.isInteger(token_budget)` |

## Scenario S04-025 — Entitle rejects a negative cost_budget

| Field | Content |
|-------|---------|
| ID | S04-025 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"cost_budget": -0.01`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `cost_budget < 0` check |

## Scenario S04-026 — Entitle rejects a string cost_budget

| Field | Content |
|-------|---------|
| ID | S04-026 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"cost_budget": "50.0"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `typeof cost_budget !== "number"` fails. (Note: `NaN`/`Infinity` cannot be expressed in JSON, so the `Number.isFinite` guard is unreachable over HTTP — see Non-automatable notes.) |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `typeof cost_budget !== "number"` |

## Scenario S04-027 — Entitle rejects a missing soft_threshold

| Field | Content |
|-------|---------|
| ID | S04-027 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with the `soft_threshold` key removed. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `undefined` is not a finite number in `[0, 1]`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L116-L118`; `ai-platform/src/quota-do/index.ts:L292-L294` — `isSoftThresholdFraction` |

## Scenario S04-028 — Entitle rejects soft_threshold above 1

| Field | Content |
|-------|---------|
| ID | S04-028 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"soft_threshold": 1.5`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L116-L118`; `ai-platform/src/quota-do/index.ts:L292-L294` — `value <= 1` bound |

## Scenario S04-029 — Entitle rejects a negative soft_threshold

| Field | Content |
|-------|---------|
| ID | S04-029 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"soft_threshold": -0.1`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L116-L118`; `ai-platform/src/quota-do/index.ts:L292-L294` — `value >= 0` bound |

## Scenario S04-030 — Entitle rejects a string soft_threshold

| Field | Content |
|-------|---------|
| ID | S04-030 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"soft_threshold": "0.8"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `Number.isFinite("0.8")` is false. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L116-L118`; `ai-platform/src/quota-do/index.ts:L292-L294` |

## Scenario S04-031 — Entitle accepts soft_threshold 0 (soft degrade disabled)

| Field | Content |
|-------|---------|
| ID | S04-031 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"soft_threshold": 0`. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}`. |
| Side effects | `entitlement.soft_threshold = 0` (boundary: routing never soft-degrades for this installation — downstream Stage 5/quota behavior); entitlement `status = 'active'`; one installation-scope grant; one `control_audit` `entitle` row. |
| Code reference | `ai-platform/src/quota-do/index.ts:L292-L294` — `0` is inside `[0, 1]`; `ai-platform/src/control/entitle.ts:L219-L233` — entitlement UPDATE |

## Scenario S04-032 — Entitle accepts soft_threshold 1 (degrade only at hard ceiling)

| Field | Content |
|-------|---------|
| ID | S04-032 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"soft_threshold": 1`. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}`. |
| Side effects | `entitlement.soft_threshold = 1` (upper inclusive boundary); entitlement `status = 'active'`; one installation-scope grant; one `control_audit` `entitle` row. |
| Code reference | `ai-platform/src/quota-do/index.ts:L292-L294` — inclusive upper bound; `ai-platform/src/control/entitle.ts:L219-L233` — entitlement UPDATE |

## Scenario S04-033 — Entitle accepts all-zero quotas (period admits nothing)

| Field | Content |
|-------|---------|
| ID | S04-033 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"request_quota": 0`, `"token_budget": 0`, `"cost_budget": 0`. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}` — zero is a legal lower boundary for all three ceilings. Downstream effect (Stage quota guard, by behavior): the very first admitted-request check sees `requestsUsed 0 >= request_quota 0` and rejects with `quota_exhausted`; the entitlement is active but admits nothing. |
| Side effects | Entitlement `status = 'active'` with all three ceilings `0`; one installation-scope grant; one `control_audit` `entitle` row. |
| Code reference | `ai-platform/src/control/entitle.ts:L104-L114` — `< 0` rejected, `0` accepted; `ai-platform/src/quota-do/index.ts:L280-L284` — exhaustion predicate `>=` |

## Scenario S04-034 — Entitle rejects a missing allowed_capabilities

| Field | Content |
|-------|---------|
| ID | S04-034 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with the `allowed_capabilities` key removed. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `Array.isArray(undefined)` is false. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L120-L126` — `allowed_capabilities` array check |

## Scenario S04-035 — Entitle rejects a string allowed_capabilities

| Field | Content |
|-------|---------|
| ID | S04-035 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"allowed_capabilities": "clinic.visit_summary"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L120-L126` — `Array.isArray` check |

## Scenario S04-036 — Entitle rejects non-string entries in allowed_capabilities

| Field | Content |
|-------|---------|
| ID | S04-036 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"allowed_capabilities": ["clinic.visit_summary", 1]`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `every(entry => typeof entry === "string")` fails. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L120-L126` — entry type check |

## Scenario S04-037 — Entitle accepts an empty allowed_capabilities list

| Field | Content |
|-------|---------|
| ID | S04-037 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"allowed_capabilities": []` (grants unchanged — still grants `clinic.visit_summary@1.0.0`). |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}` — `every` on an empty array passes. Downstream effect (Stage guard 3, by behavior): every request fails `evaluateEntitlement` check 3 with `forbidden_capability` (path `capability_not_granted`) because the allow-list contains nothing, even though a grant row exists. |
| Side effects | `entitlement.allowed_capabilities = '[]'`, `status = 'active'`; grant row still inserted (grants and allow-list are independent inputs); one `control_audit` `entitle` row with `after_pointer = '[]'`. |
| Code reference | `ai-platform/src/control/entitle.ts:L120-L126`; `ai-platform/src/entitlement/index.ts:L172-L178` — allow-list membership check |

## Scenario S04-038 — Entitle rejects a missing grants field

| Field | Content |
|-------|---------|
| ID | S04-038 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with the `grants` key removed. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L128-L130` — `grants` non-empty array check |

## Scenario S04-039 — Entitle rejects a non-array grants field

| Field | Content |
|-------|---------|
| ID | S04-039 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": {"capability_id": "clinic.visit_summary", "capability_version": "1.0.0"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — a single grant object is not accepted in place of an array. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L128-L130` — `Array.isArray(body.grants)` |

## Scenario S04-040 — Entitle rejects an empty grants array

| Field | Content |
|-------|---------|
| ID | S04-040 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": []`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — at least one grant is required so activation never leaves a capability-less entitlement. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L128-L130` — `grants.length === 0` check |

## Scenario S04-041 — Entitle rejects a grant missing capability_id

| Field | Content |
|-------|---------|
| ID | S04-041 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_version": "1.0.0"}]`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L66-L73` — `validateGrantInput` `requireNonEmptyString(grant.capability_id)` |

## Scenario S04-042 — Entitle rejects a grant with an empty capability_id

| Field | Content |
|-------|---------|
| ID | S04-042 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "   ", "capability_version": "1.0.0"}]`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — whitespace-only strings fail `requireNonEmptyString`. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L66-L73`; `ai-platform/src/control/http.ts:L51-L56` — trim check |

## Scenario S04-043 — Entitle rejects a grant with a non-string capability_version

| Field | Content |
|-------|---------|
| ID | S04-043 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "clinic.visit_summary", "capability_version": 1.0}]`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — versions are opaque strings; numbers are rejected. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L66-L73` — `requireNonEmptyString(grant.capability_version)` |

## Scenario S04-044 — Entitle rejects grant scope "global"

| Field | Content |
|-------|---------|
| ID | S04-044 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "global"}]`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — only `installation`, `plan`, or omitted are legal; `global` is reserved for lifecycle overlay rows written by deprecate/retire. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L74-L77` — scope whitelist |

## Scenario S04-045 — Entitle rejects a mis-cased grant scope

| Field | Content |
|-------|---------|
| ID | S04-045 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "Plan"}]`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — the scope comparison is case-sensitive. |
| Side effects | None (same negative assertions as S04-001). |
| Code reference | `ai-platform/src/control/entitle.ts:L74-L77` — scope whitelist |

## Scenario S04-046 — Entitle rejects a multi-grant payload when any one grant is invalid

| Field | Content |
|-------|---------|
| ID | S04-046 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "clinic.visit_summary", "capability_version": "1.0.0"}, {"capability_id": "clinic.chat_assistant"}]` (second grant missing `capability_version`). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — validation of all grants completes before any D1 statement is built, so the valid first grant is not partially applied. |
| Side effects | None: zero `capability_grant` rows (including for the valid first grant); entitlement still `pending`; no audit row. |
| Code reference | `ai-platform/src/control/entitle.ts:L131-L138` — per-grant validation loop before batch construction |

## Scenario S04-047 — Entitle rejects an unknown installation id

| Field | Content |
|-------|---------|
| ID | S04-047 |
| Journey setup | Stage 3 enroll happy path → pending installation I0 (a different id than the one targeted). |
| Action | `POST /control/installations/00000000-0000-0000-0000-000000000000/entitle`, operator bearer, body REF-BODY. |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}` — the `installation` table lookup misses. Payload validation runs first, so this body must be fully valid to reach the 404. |
| Side effects | None: no entitlement update, no grants, no audit row. |
| Code reference | `ai-platform/src/control/entitle.ts:L177-L185` — installation lookup and 404 |

## Scenario S04-048 — Entitle rejects an installation whose entitlement row is missing

| Field | Content |
|-------|---------|
| ID | S04-048 |
| Journey setup | Stage 3 enroll happy path → pending installation I0; then **[SEED]** `DELETE FROM entitlement WHERE installation_id = '0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b'`. Justification: enroll always inserts the entitlement row atomically with the installation, so no production operation leaves an installation without an entitlement; the missing row simulates operator repair after a bad purge. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY. |
| Expected outcome | HTTP 404, body exactly `{"error":"entitlement_not_found"}` — installation exists but the entitlement lookup misses. |
| Side effects | None: no grants, no audit row. Restore the seeded row afterwards for other scenarios. |
| Code reference | `ai-platform/src/control/entitle.ts:L187-L196` — entitlement lookup and 404 |

## Scenario S04-049 — Entitle rejects a non-pending entitlement

| Field | Content |
|-------|---------|
| ID | S04-049 |
| Journey setup | Stage 3 enroll happy path → pending installation I0; then **[SEED]** `UPDATE entitlement SET status = 'suspended' WHERE installation_id = '0a1f4c2e-…'`. Justification: no control-plane route writes entitlement `status` other than entitle itself (`pending → active`), so a `suspended` entitlement state is only reachable via direct D1 operator action; the seed exercises the `status !== 'pending'` guard for a non-`active` value. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY. |
| Expected outcome | HTTP 409, body exactly `{"error":"not_pending"}`. |
| Side effects | None: entitlement row unchanged (`status = 'suspended'`); no grants; no audit row. |
| Code reference | `ai-platform/src/control/entitle.ts:L198-L200` — `entitlement.status !== "pending"` guard |

## Scenario S04-050 — Entitle happy path activates a pending installation

| Field | Content |
|-------|---------|
| ID | S04-050 |
| Journey setup | Stage 3 enroll happy path → pending installation I0 (`plan = 'professional'`, zero quotas, `allowed_capabilities = '[]'`, `soft_threshold = 0`). |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY verbatim. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}`. |
| Side effects | **Must occur:** (1) `UPDATE entitlement` for I0 — `period_start = '2026-08-01T00:00:00.000Z'`, `period_end = '2026-09-01T00:00:00.000Z'`, `request_quota = 1000`, `token_budget = 500000`, `cost_budget = 50.0`, `allowed_capabilities = '["clinic.visit_summary"]'`, `soft_threshold = 0.8`, `status = 'active'`; (2) `INSERT capability_grant` — `scope = 'installation:0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b'`, `capability_id = 'clinic.visit_summary'`, `capability_version = '1.0.0'`, `granted_at = changed_at = <now>`, `revoked_at NULL`, `changed_by = 'platform-operator'`, lifecycle columns NULL; (3) `INSERT control_audit` — `action = 'entitle'`, `target = '0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b'`, `operator_id = 'platform-operator'`, `before_pointer NULL`, `after_pointer = '["clinic.visit_summary"]'`. **Must not occur:** `entitlement.plan` unchanged (`professional`); `installation.status` unchanged (`active`); no `routing_policy` rows; no AAT minted (Stage 6 concern); no clinic Postgres writes. |
| Code reference | `ai-platform/src/control/entitle.ts:L151-L283` — `handleEntitle` (UPDATE L219-L233, grant INSERT L235-L261, audit INSERT L263-L274) |

## Scenario S04-051 — Re-entitle of an active installation is rejected, not idempotent

| Field | Content |
|-------|---------|
| ID | S04-051 |
| Journey setup | S04-050 completed → I0 entitlement `active` with one grant row. |
| Action | Repeat the exact S04-050 request: `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY. |
| Expected outcome | HTTP 409, body exactly `{"error":"not_pending"}` — entitle is one-shot; reuse is not idempotent. |
| Side effects | None: entitlement row unchanged (still `active` with S04-050 values); `capability_grant` count for I0 unchanged (no second insert); no second `control_audit` `entitle` row. |
| Code reference | `ai-platform/src/control/entitle.ts:L198-L200` — status guard runs before any statement is built |

## Scenario S04-052 — Entitle succeeds while the installation itself is suspended

| Field | Content |
|-------|---------|
| ID | S04-052 |
| Journey setup | Stage 3 enroll happy path → pending installation I0; Stage 3 suspend happy path → `installation.status = 'suspended'` (entitlement remains `pending` — suspend does not touch the entitlement row). |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}` — `handleEntitle` never reads `installation.status`; only entitlement status gates. |
| Side effects | Same entitlement UPDATE + grant INSERT + audit INSERT as S04-050; `installation.status` stays `suspended` (entitle does not resume the installation; runtime requests still fail identity as `installation_suspended` at Stage 8/9 ingress until Stage 3 resume). |
| Code reference | `ai-platform/src/control/entitle.ts:L177-L200` — installation existence check selects only `installation_id` |

## Scenario S04-053 — Entitle writes a plan-scope grant at plan:{plan}

| Field | Content |
|-------|---------|
| ID | S04-053 |
| Journey setup | Stage 3 enroll happy path → pending installation I0 (`plan = 'professional'`). |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "plan"}]`. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}`. |
| Side effects | `INSERT capability_grant` with `scope = 'plan:professional'` (the plan name is read from the stored entitlement row, not from the request); no installation-scope grant row; entitlement UPDATE and audit INSERT as S04-050. Downstream effect (Stage guard 3, by behavior): `evaluateEntitlement` finds the grant via the `plan:{plan}` fallback when no installation-scope grant exists. |
| Code reference | `ai-platform/src/control/entitle.ts:L203-L216` — `planScope` derivation; `ai-platform/src/control/entitle.ts:L235-L261` — scope resolution `plan:{plan}`; `ai-platform/src/entitlement/index.ts:L190-L199` — plan-grant fallback |

## Scenario S04-054 — Entitle skips a plan-scope grant that already exists live

| Field | Content |
|-------|---------|
| ID | S04-054 |
| Journey setup | Stage 3 enroll happy path → pending installation I0 (`plan = 'professional'`); then **[SEED]** `INSERT INTO capability_grant (grant_id, scope, capability_id, capability_version, granted_at, revoked_at, changed_at, changed_by) VALUES ('seed-plan-grant-1', 'plan:professional', 'clinic.visit_summary', '1.0.0', '2026-07-01T00:00:00.000Z', NULL, '2026-07-01T00:00:00.000Z', 'seed')`. Justification: the dedup branch requires a pre-existing live plan grant, but the only code path that creates plan grants is entitle/promote on an already-entitled installation — a chicken-and-egg state for a pending I0; the seed represents a plan grant created earlier via another professional installation's entitle. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "plan"}]`. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}`. |
| Side effects | **Must not occur:** no second `capability_grant` row for `scope = 'plan:professional'` + `clinic.visit_summary` (the seeded row remains the only one, unchanged). **Must occur:** entitlement UPDATE to `active` and the `control_audit` `entitle` row — the dedup skip does not skip activation. |
| Code reference | `ai-platform/src/control/entitle.ts:L203-L216` — existing live plan-grant lookup; `ai-platform/src/control/entitle.ts:L239-L243` — `continue` on duplicate |

## Scenario S04-055 — Entitle writes mixed installation-scope and plan-scope grants in one call

| Field | Content |
|-------|---------|
| ID | S04-055 |
| Journey setup | Stage 3 enroll happy path → pending installation I0 (`plan = 'professional'`); **[REGISTRY]** registry contains `clinic.visit_summary@1.0.0` and `clinic.visit_summary@2.0.0`. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY with `"grants": [{"capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "installation"}, {"capability_id": "clinic.visit_summary", "capability_version": "2.0.0", "scope": "plan"}]`. |
| Expected outcome | HTTP 200, body exactly `{"installation_id":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","status":"active"}`. |
| Side effects | Two `capability_grant` rows in one batch: `scope = 'installation:0a1f4c2e-…'` version `1.0.0`, and `scope = 'plan:professional'` version `2.0.0`; both `revoked_at NULL`, `changed_by = 'platform-operator'`; entitlement UPDATE + one audit row. |
| Code reference | `ai-platform/src/control/entitle.ts:L235-L261` — per-grant scope resolution in the batch loop |

## Scenario S04-056 — A second entitlement row for the same installation violates UNIQUE(installation_id)

| Field | Content |
|-------|---------|
| ID | S04-056 |
| Journey setup | S04-050 completed → I0 entitlement `active`. |
| Action | **[SEED-probe]** Direct D1: `INSERT INTO entitlement (entitlement_id, installation_id, plan, period_start, period_end, request_quota, token_budget, cost_budget, allowed_capabilities, soft_threshold, status) VALUES ('probe-dup-entitlement', '0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b', 'professional', '2026-08-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z', 0, 0, 0, '[]', 0, 'pending')`. Justification: no HTTP route inserts entitlement rows except Stage 3 enroll (which rejects existing installations); this probe verifies the migration constraint itself. |
| Expected outcome | The INSERT fails with a UNIQUE constraint violation on index `idx_entitlement_installation_id`; exactly one entitlement row for I0 remains. |
| Side effects | None — the constraint guarantees `handleEntitle`'s `UPDATE … WHERE installation_id = ?` can never silently multi-update a duplicate row set. |
| Code reference | `ai-platform/migrations/20260821130000_entitlement_installation_unique.sql:L1-L5` — `CREATE UNIQUE INDEX idx_entitlement_installation_id`; `ai-platform/src/control/entitle.ts:L219-L233` — single-row UPDATE |

## Scenario S04-057 — Entitle returns storage_error when the D1 batch fails

| Field | Content |
|-------|---------|
| ID | S04-057 |
| Journey setup | Stage 3 enroll happy path → pending installation I0. Fault-injection seam: wrap the `DB` binding in a proxy whose `batch()` throws (e.g. `new Error("D1 unavailable")`) for this request only — see Non-automatable notes. |
| Action | `POST /control/installations/0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b/entitle`, operator bearer, body REF-BODY. |
| Expected outcome | HTTP 500, body exactly `{"error":"storage_error"}` — `runControlBatch` catches the batch exception and maps it to a taxonomy-safe 500. |
| Side effects | None observable: the batch is atomic, so the entitlement stays `pending`, no grant rows, no audit row. |
| Code reference | `ai-platform/src/control/entitle.ts:L29-L37` — `runControlBatch`; `ai-platform/src/control/entitle.ts:L276-L279` — batch error return |

## Scenario S04-058 — Cohort activate rejects a missing operator bearer

| Field | Content |
|-------|---------|
| ID | S04-058 |
| Journey setup | S04-050 completed → I0 active with installation-scope grant at `1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/activate`, `Content-Type: application/json`, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b"]}`, **no** `Authorization` header. **[REGISTRY]** `2.0.0` registered. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None: grant stays at `1.0.0`; no `control_audit` row with `action = 'cohort_activate'`. |
| Code reference | `ai-platform/src/control/cohort.ts:L79-L82` — `requireOperator` gate in `handleCohortActivate` |

## Scenario S04-059 — Cohort activate rejects an unregistered capability version

| Field | Content |
|-------|---------|
| ID | S04-059 |
| Journey setup | S04-050 completed → I0 active. Registry contains only `clinic.visit_summary@1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/9.9.9/activate`, operator bearer, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b"]}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"capability_not_found"}` — the in-memory registry (not D1) decides whether a pin exists. |
| Side effects | None: no grant mutation, no audit row. |
| Code reference | `ai-platform/src/control/cohort.ts:L88-L91` — `isCapabilityVersionRegistered` check; `ai-platform/src/capability/index.ts:L533-L539` — registry lookup |

## Scenario S04-060 — Cohort activate rejects an unregistered capability id

| Field | Content |
|-------|---------|
| ID | S04-060 |
| Journey setup | S04-050 completed → I0 active. |
| Action | `POST /control/capabilities/clinic.not_in_registry/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b"]}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"capability_not_found"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/cohort.ts:L88-L91` — registry check runs before body parsing |

## Scenario S04-061 — Cohort activate rejects a non-JSON body

| Field | Content |
|-------|---------|
| ID | S04-061 |
| Journey setup | S04-050 completed → I0 active. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_json"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/cohort.ts:L93-L96` — `parseJsonBody` gate; `ai-platform/src/control/http.ts:L43-L49` |

## Scenario S04-062 — Cohort activate rejects a missing installation_ids field

| Field | Content |
|-------|---------|
| ID | S04-062 |
| Journey setup | S04-050 completed → I0 active. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"cohort_name":"pilot-clinics"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"missing_installation_ids"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/cohort.ts:L98-L100` — `installation_ids` non-empty array check |

## Scenario S04-063 — Cohort activate rejects an empty installation_ids array

| Field | Content |
|-------|---------|
| ID | S04-063 |
| Journey setup | S04-050 completed → I0 active. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":[]}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"missing_installation_ids"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/cohort.ts:L98-L100` — `length === 0` check |

## Scenario S04-064 — Cohort activate rejects a non-array installation_ids

| Field | Content |
|-------|---------|
| ID | S04-064 |
| Journey setup | S04-050 completed → I0 active. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"missing_installation_ids"}` — a bare string is not accepted in place of an array. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/cohort.ts:L98-L100` — `Array.isArray` check |

## Scenario S04-065 — Cohort activate rejects an unknown installation id in the cohort

| Field | Content |
|-------|---------|
| ID | S04-065 |
| Journey setup | S04-050 completed → I0 active. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","00000000-0000-0000-0000-000000000000"]}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}` — every listed id is checked against the `installation` table before any write. |
| Side effects | None: I0's grant unchanged; no audit row — the existence loop runs before the batch is built. |
| Code reference | `ai-platform/src/control/cohort.ts:L17-L33` — `assertInstallationsExist`; `ai-platform/src/control/cohort.ts:L102-L108` — call site |

## Scenario S04-066 — Cohort activate happy path updates an existing live grant

| Field | Content |
|-------|---------|
| ID | S04-066 |
| Journey setup | S04-050 completed → I0 active with installation-scope grant at `1.0.0`. **[REGISTRY]** `clinic.visit_summary@2.0.0` registered. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/activate`, operator bearer, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b"]}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | **Must occur:** (1) `UPDATE capability_grant` on I0's existing grant row — `capability_version = '2.0.0'`, `changed_at = <now>`, `changed_by = 'platform-operator'` (same `grant_id`, no new row); (2) `INSERT control_audit` — `action = 'cohort_activate'`, `target = 'clinic.visit_summary@2.0.0'`, `before_pointer = '{"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b":"1.0.0"}'`, `after_pointer = '2.0.0'`. **Must not occur:** no entitlement change; no new grant row for I0. Downstream effect (Stage guard 3, by behavior): requests pinning `1.0.0` now fail `version_mismatch` → `forbidden_capability`; requests pinning `2.0.0` pass the grant check. |
| Code reference | `ai-platform/src/control/cohort.ts:L119-L156` — existing-grant UPDATE branch; `ai-platform/src/control/cohort.ts:L158-L178` — audit insert |

## Scenario S04-067 — Cohort activate records cohort_name on the audit target

| Field | Content |
|-------|---------|
| ID | S04-067 |
| Journey setup | S04-050 completed → I0 active with grant at `1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b"],"cohort_name":"pilot-clinics"}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | `control_audit` row with `target = 'clinic.visit_summary@1.0.0:pilot-clinics'` (cohort label appended after `:`); grant row UPDATE bumps `changed_at`/`changed_by` even though the version is unchanged. |
| Code reference | `ai-platform/src/control/cohort.ts:L111-L114` — target construction with `cohort_name` |

## Scenario S04-068 — Cohort activate inserts a grant when none is live

| Field | Content |
|-------|---------|
| ID | S04-068 |
| Journey setup | Stage 3 enroll happy path → pending installation I1 (never entitled, zero grant rows). Note: activate does not require an active entitlement — it operates on `installation` + `capability_grant` only. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":["1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c"]}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | **Must occur:** `INSERT capability_grant` — new `grant_id`, `scope = 'installation:1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c'`, version `1.0.0`, `revoked_at NULL`; `control_audit` row with `before_pointer = NULL` (no prior live version for any listed installation) and `after_pointer = '1.0.0'`. **Must not occur:** I1's entitlement stays `pending` — activate alone does not enable runtime access (Stage guard 3 still rejects with `ai_disabled`). |
| Code reference | `ai-platform/src/control/cohort.ts:L130-L155` — INSERT branch; `ai-platform/src/control/cohort.ts:L158-L163` — `before_pointer` null rule |

## Scenario S04-069 — Cohort activate handles a mixed cohort (update + insert) in one call

| Field | Content |
|-------|---------|
| ID | S04-069 |
| Journey setup | S04-050 completed → I0 active with grant at `1.0.0`; Stage 3 enroll happy path → pending I1 with no grants. **[REGISTRY]** `2.0.0` registered. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/activate`, operator bearer, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b","1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c"],"cohort_name":"pilot-clinics"}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | I0's grant row UPDATEd to `2.0.0`; new INSERT grant row for I1 at `2.0.0`; one `control_audit` row — `target = 'clinic.visit_summary@2.0.0:pilot-clinics'`, `before_pointer = '{"0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b":"1.0.0","1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c":null}'`, `after_pointer = '2.0.0'`. |
| Code reference | `ai-platform/src/control/cohort.ts:L119-L156` — per-installation UPDATE-or-INSERT loop |

## Scenario S04-070 — Cohort activate dedupes duplicate installation ids

| Field | Content |
|-------|---------|
| ID | S04-070 |
| Journey setup | Stage 3 enroll happy path → pending I1 with zero grant rows. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":["1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c","1b2e5d3f-8c4e-5f6a-ab7c-2d3e4f5a6b7c"]}`. |
| Expected outcome | HTTP 200, body exactly `{}` — duplicate installation ids in the request are deduped before the grant loop runs, so only one live grant row is written per installation. |
| Side effects | One `capability_grant` row (`scope = 'installation:1b2e5d3f-…'`, version `1.0.0`, `revoked_at NULL`); one audit row whose `before_pointer` is NULL. |
| Code reference | `ai-platform/src/control/cohort.ts` — `[...new Set(body.installation_ids)]` dedup before the per-installation loop; `runControlBatch` at the end |

## Scenario S04-071 — Cohort activate onto the already-current version succeeds and re-stamps the grant

| Field | Content |
|-------|---------|
| ID | S04-071 |
| Journey setup | S04-050 completed → I0 active with grant at `1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/activate`, operator bearer, body `{"installation_ids":["0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b"]}`. |
| Expected outcome | HTTP 200, body exactly `{}` — activating the current version is not an error. |
| Side effects | Grant row UPDATEd in place: `capability_version` stays `1.0.0`, `changed_at` and `changed_by` refreshed; audit row `before_pointer = '{"0a1f4c2e-…":"1.0.0"}'`, `after_pointer = '1.0.0'`. |
| Code reference | `ai-platform/src/control/cohort.ts:L130-L138` — unconditional UPDATE of the existing grant |

## Scenario S04-072 — Cohort promote rejects a missing operator bearer

| Field | Content |
|-------|---------|
| ID | S04-072 |
| Journey setup | S04-050 completed → I0 active. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/promote`, body `{}`, **no** `Authorization` header. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None: no grant mutations, no `cohort_promote` audit row. |
| Code reference | `ai-platform/src/control/cohort.ts:L186-L190` — `requireOperator` gate in `handleCohortPromote` |

## Scenario S04-073 — Cohort promote rejects an unregistered capability version

| Field | Content |
|-------|---------|
| ID | S04-073 |
| Journey setup | S04-050 completed → I0 active. Registry contains only `clinic.visit_summary@1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/9.9.9/promote`, operator bearer, body `{}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"capability_not_found"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/cohort.ts:L197-L199` — registry check in `handleCohortPromote` |

## Scenario S04-074 — Cohort promote happy path ends a cohort split fleet-wide

| Field | Content |
|-------|---------|
| ID | S04-074 |
| Journey setup | S04-050 completed → I0 active (`plan = 'professional'`, allow-list `["clinic.visit_summary"]`, installation grant at `1.0.0`); S04-055-style entitle of a second professional installation I1 (Stage 3 enroll + entitle with plan-scope grant) → live `plan:professional` grant at `2.0.0` and I1 installation grant absent or at `2.0.0`; **[REGISTRY]** `1.0.0` and `2.0.0` registered. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/promote`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | **Must occur:** (1) every live `installation:*` grant for `clinic.visit_summary` UPDATEd to `capability_version = '2.0.0'` with fresh `changed_at`/`changed_by`; (2) every live `plan:*` grant for the capability UPDATEd to `2.0.0`; (3) for each distinct plan on `active` entitlements whose `allowed_capabilities` contains `clinic.visit_summary` and which had no live plan grant → INSERT `plan:{plan}` grant at `2.0.0`; (4) for each entitled installation with no live installation grant → INSERT `installation:{id}` grant at `2.0.0`; (5) `control_audit` row — `action = 'cohort_promote'`, `target = 'clinic.visit_summary@2.0.0'`, `before_pointer = '{"installation":[{"scope":"installation:0a1f4c2e-…","version":"1.0.0"},…],"plan":[{"scope":"plan:professional","version":"2.0.0"}]}'` (pre-batch snapshot), `after_pointer = '2.0.0'`. **Must not occur:** `entitlement` rows unchanged; pending entitlements untouched. |
| Code reference | `ai-platform/src/control/cohort.ts:L205-L252` — live grant sweep and UPDATEs; `ai-platform/src/control/cohort.ts:L254-L364` — plan/installation upsert materialization; `ai-platform/src/control/cohort.ts:L366-L380` — audit insert |

## Scenario S04-075 — Cohort promote with no live grants and no active entitlements writes only an audit row

| Field | Content |
|-------|---------|
| ID | S04-075 |
| Journey setup | Fresh D1 (migrations applied); no installations enrolled; registry default (`1.0.0`). |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/promote`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}` — an empty fleet is not an error. |
| Side effects | Exactly one write: `control_audit` row `action = 'cohort_promote'`, `target = 'clinic.visit_summary@1.0.0'`, `before_pointer = '{"installation":[],"plan":[]}'`, `after_pointer = '1.0.0'`. Zero `capability_grant` rows. |
| Code reference | `ai-platform/src/control/cohort.ts:L205-L230` — empty result sets; `ai-platform/src/control/cohort.ts:L366-L383` — audit-only batch |

## Scenario S04-076 — Cohort promote skips active entitlements whose allow-list lacks the capability

| Field | Content |
|-------|---------|
| ID | S04-076 |
| Journey setup | S04-037 completed → I0 active with `allowed_capabilities = '[]'` and an installation grant at `1.0.0`. **[REGISTRY]** `2.0.0` registered. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/promote`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | I0's existing live installation grant IS UPDATEd to `2.0.0` (the live-grant sweep does not consult the allow-list); **must not occur:** no new `plan:professional` grant and no new installation grant materialized for I0 via the entitlement-driven upsert, because `allowed_capabilities` does not include `clinic.visit_summary`. |
| Code reference | `ai-platform/src/control/cohort.ts:L205-L213` — unconditional live-grant sweep; `ai-platform/src/control/cohort.ts:L275-L284` — `allowed.includes(route.capabilityId)` filter |

## Scenario S04-077 — Cohort promote skips pending entitlements

| Field | Content |
|-------|---------|
| ID | S04-077 |
| Journey setup | Stage 3 enroll happy path → pending I1 (entitlement `pending`, `allowed_capabilities = '[]'`, no grants); S04-050 completed → I0 active at `1.0.0`. **[REGISTRY]** `2.0.0` registered. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/promote`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | I0's grant UPDATEd to `2.0.0`; **must not occur:** no grant rows for I1 — the entitlement sweep filters `WHERE status = 'active'`. |
| Code reference | `ai-platform/src/control/cohort.ts:L254-L261` — `WHERE status = 'active'` entitlement query |

## Scenario S04-078 — Cohort promote ignores revoked grants

| Field | Content |
|-------|---------|
| ID | S04-078 |
| Journey setup | S04-050 completed → I0 active at `1.0.0`; then **[SEED]** `UPDATE capability_grant SET revoked_at = '2026-08-15T00:00:00.000Z' WHERE scope = 'installation:0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b'` (simulates a prior operator revocation; no Stage 4 route revokes grants). **[REGISTRY]** `2.0.0` registered. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/promote`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | The revoked row is untouched (`capability_version` stays `1.0.0`, `revoked_at` preserved) — both sweep queries filter `revoked_at IS NULL`; because I0 is active and allows the capability, a NEW live installation grant at `2.0.0` is INSERTed by the materialization loop. |
| Code reference | `ai-platform/src/control/cohort.ts:L205-L219` — `revoked_at IS NULL` filters; `ai-platform/src/control/cohort.ts:L325-L364` — materialization of a replacement grant |

## Scenario S04-079 — Cohort promote ignores the request body entirely

| Field | Content |
|-------|---------|
| ID | S04-079 |
| Journey setup | S04-050 completed → I0 active at `1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/promote`, operator bearer, body `not json{`. |
| Expected outcome | HTTP 200, body exactly `{}` — `handleCohortPromote` never calls `parseJsonBody`; malformed bodies are accepted. |
| Side effects | Normal promote writes (grant UPDATE + audit row). |
| Code reference | `ai-platform/src/control/cohort.ts:L182-L200` — no body parse before the grant sweep |

## Scenario S04-080 — Deprecate rejects a missing operator bearer

| Field | Content |
|-------|---------|
| ID | S04-080 |
| Journey setup | Registry default (`clinic.visit_summary@1.0.0`). No D1 state required. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, body `{"successor_id":"clinic.visit_summary"}`, **no** `Authorization` header. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None: no overlay row, no `deprecate` audit row. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L76-L80` — `requireOperator` gate in `handleDeprecate` |

## Scenario S04-081 — Deprecate rejects an unregistered capability version

| Field | Content |
|-------|---------|
| ID | S04-081 |
| Journey setup | Registry contains only `clinic.visit_summary@1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/9.9.9/deprecate`, operator bearer, body `{"successor_id":"clinic.visit_summary"}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"capability_not_found"}` — the registry check runs before body parsing, so even a valid body cannot save an unknown pin. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L86-L92` — `requireRegisteredVersion`; `ai-platform/src/control/capability-lifecycle.ts:L52-L60` — 404 mapping |

## Scenario S04-082 — Deprecate rejects a non-JSON body

| Field | Content |
|-------|---------|
| ID | S04-082 |
| Journey setup | Registry default (`1.0.0` registered). |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_json"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L94-L97` — `parseJsonBody` gate |

## Scenario S04-083 — Deprecate rejects a missing successor_id

| Field | Content |
|-------|---------|
| ID | S04-083 |
| Journey setup | Registry default. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"missing_successor_id"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L100-L102` — falsy `successor_id` check |

## Scenario S04-084 — Deprecate rejects an empty-string successor_id

| Field | Content |
|-------|---------|
| ID | S04-084 |
| Journey setup | Registry default. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":""}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"missing_successor_id"}` — the check is falsy-based, not type-based. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L100-L102` — `!body.successor_id` |

## Scenario S04-085 — Deprecate rejects a successor unknown to the registry

| Field | Content |
|-------|---------|
| ID | S04-085 |
| Journey setup | Registry default (`clinic.visit_summary@1.0.0` only). |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":"clinic.not_in_registry"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"unknown_successor"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L103-L105` — `isSuccessorRegistered` check; `ai-platform/src/capability/index.ts:L541-L555` — successor resolution |

## Scenario S04-086 — Deprecate happy path with a bare capability id as successor

| Field | Content |
|-------|---------|
| ID | S04-086 |
| Journey setup | Registry default (`clinic.visit_summary@1.0.0`); no global overlay rows for the capability. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":"clinic.visit_summary"}`. |
| Expected outcome | HTTP 200, body exactly `{}`. A bare id is a valid successor when any version of it is registered. |
| Side effects | **Must occur:** (1) `INSERT capability_grant` overlay — `scope = 'global'`, `capability_id = 'clinic.visit_summary'`, `capability_version = '1.0.0'`, `lifecycle_state = 'deprecated'`, `successor_id = 'clinic.visit_summary'`, `deprecated_at = <now>`, `retire_after = <now + 90 days>`, `granted_at = revoked_at = changed_at = <now>` (overlay stamp so `revoked_at IS NULL` grant readers never treat it as a live grant), `changed_by = 'platform-operator'`; (2) `INSERT control_audit` — `action = 'deprecate'`, `target = 'clinic.visit_summary@1.0.0'`, `before_pointer NULL`, `after_pointer = 'clinic.visit_summary'`. **Must not occur:** installation/plan grant rows untouched; manifest bytes untouched. Downstream effect (Stage 7 discovery, by behavior): the version is still listed but marked `lifecycleState: 'deprecated'` with the successor id; (Stage 9 resolve, by behavior): still servable inside the overlap window. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L118-L156` — overlay + audit batch; `ai-platform/src/capability/index.ts:L45-L46` — `OVERLAP_WINDOW_MS` (90 days) |

## Scenario S04-087 — Deprecate happy path with an id@version successor

| Field | Content |
|-------|---------|
| ID | S04-087 |
| Journey setup | **[REGISTRY]** `clinic.visit_summary@1.0.0` and `clinic.visit_summary@2.0.0` registered; no global overlay rows. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":"clinic.visit_summary@2.0.0"}`. |
| Expected outcome | HTTP 200, body exactly `{}` — the `id@version` form is accepted when that exact pin is registered. |
| Side effects | Overlay row with `successor_id = 'clinic.visit_summary@2.0.0'` (stored verbatim); audit `after_pointer = 'clinic.visit_summary@2.0.0'`; `retire_after = deprecated_at + 90 days`. |
| Code reference | `ai-platform/src/capability/index.ts:L545-L548` — `successorId.includes("@")` exact-pin branch; `ai-platform/src/control/capability-lifecycle.ts:L118-L156` — overlay insert |

## Scenario S04-088 — Deprecate with the same successor is idempotent

| Field | Content |
|-------|---------|
| ID | S04-088 |
| Journey setup | S04-086 completed → global overlay `deprecated` with `successor_id = 'clinic.visit_summary'`. |
| Action | Repeat the exact S04-086 request. |
| Expected outcome | HTTP 200, body exactly `{}` — same successor on an already-deprecated version is a no-op success. |
| Side effects | **Must not occur:** no second overlay row (still exactly one global overlay for the pin; `deprecated_at`/`retire_after` unchanged); no second `deprecate` audit row. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L108-L116` — same-successor early `ok()` return |

## Scenario S04-089 — Deprecate with a different successor after deprecation is rejected

| Field | Content |
|-------|---------|
| ID | S04-089 |
| Journey setup | **[REGISTRY]** `1.0.0` and `2.0.0` registered; S04-086 completed → overlay `deprecated` with `successor_id = 'clinic.visit_summary'`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":"clinic.visit_summary@2.0.0"}`. |
| Expected outcome | HTTP 409, body exactly `{"error":"already_deprecated"}` — the successor cannot be changed once announced. |
| Side effects | None: overlay row unchanged; no new audit row. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L112-L116` — different-successor 409 |

## Scenario S04-090 — Deprecate after retire is rejected as already_retired

| Field | Content |
|-------|---------|
| ID | S04-090 |
| Journey setup | S04-098 completed → latest global overlay for `clinic.visit_summary@1.0.0` is `retired`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":"clinic.visit_summary"}`. |
| Expected outcome | HTTP 409, body exactly `{"error":"already_retired"}` — retirement is terminal; the version cannot re-enter deprecation. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L108-L111` — `lifecycle_state === "retired"` check |

## Scenario S04-091 — Deprecate with a truthy non-string successor_id returns invalid_payload

| Field | Content |
|-------|---------|
| ID | S04-091 |
| Journey setup | Registry default; no overlay rows. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate`, operator bearer, body `{"successor_id":123}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` — `requireNonEmptyString` rejects any non-string `successor_id` before registry lookup. (Truthy non-strings such as `123` or `["clinic.visit_summary"]` both receive `invalid_payload`; only missing/null/empty-string values receive `missing_successor_id`.) |
| Side effects | None: the rejection happens before any D1 statement executes. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts` — `requireNonEmptyString(body.successor_id)` type guard |

## Scenario S04-092 — Retire rejects a missing operator bearer

| Field | Content |
|-------|---------|
| ID | S04-092 |
| Journey setup | S04-086 completed → overlay `deprecated`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, body `{}`, **no** `Authorization` header. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None: overlay unchanged; no `retire` audit row. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L163-L167` — `requireOperator` gate in `handleRetire` |

## Scenario S04-093 — Retire rejects an unregistered capability version

| Field | Content |
|-------|---------|
| ID | S04-093 |
| Journey setup | Registry contains only `clinic.visit_summary@1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/9.9.9/retire`, operator bearer, body `{}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"capability_not_found"}`. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L173-L178` — `requireRegisteredVersion` in `handleRetire` |

## Scenario S04-094 — Retire without a prior deprecate is rejected

| Field | Content |
|-------|---------|
| ID | S04-094 |
| Journey setup | Registry default; no global overlay rows for `clinic.visit_summary@1.0.0`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, operator bearer, body `{}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"not_deprecated"}` — retire requires a prior `deprecated` overlay with a non-empty string successor. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L180-L191` — overlay existence/state/successor guard |

## Scenario S04-095 — Retire inside the 90-day overlap window is rejected

| Field | Content |
|-------|---------|
| ID | S04-095 |
| Journey setup | S04-086 completed moments ago → overlay `deprecated` with `retire_after ≈ now + 90 days`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, operator bearer, body `{}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"overlap_window_active"}` — the request path never auto-retires; the operator must wait out the window. |
| Side effects | None: overlay stays `deprecated`; no audit row. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L193-L198` — `overlapWindowStillActive` gate; `ai-platform/src/control/capability-lifecycle.ts:L62-L70` — epoch-ms comparison |

## Scenario S04-096 — Retire with an unparseable retire_after is treated as still in-window

| Field | Content |
|-------|---------|
| ID | S04-096 |
| Journey setup | S04-086 completed → overlay `deprecated`; then **[SEED]** `UPDATE capability_grant SET retire_after = 'not-a-date' WHERE scope = 'global' AND capability_id = 'clinic.visit_summary' AND lifecycle_state = 'deprecated'`. Justification: no code path writes an unparseable `retire_after`; the seed exercises the fail-closed branch of the window gate directly. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, operator bearer, body `{}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"overlap_window_active"}` — an unparseable `retire_after` is treated as "not yet elapsed" (fail closed). |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L62-L70` — `Number.isFinite` fail-closed branch |

## Scenario S04-097 — Retire with a missing retire_after is rejected

| Field | Content |
|-------|---------|
| ID | S04-097 |
| Journey setup | S04-086 completed → overlay `deprecated`; then **[SEED]** `UPDATE capability_grant SET retire_after = NULL WHERE scope = 'global' AND capability_id = 'clinic.visit_summary' AND lifecycle_state = 'deprecated'`. Justification: deprecate always writes `retire_after`; the seed exercises the `!retireAfter` guard. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, operator bearer, body `{}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"overlap_window_active"}` — a non-string/absent `retire_after` maps to the same fail-closed rejection. |
| Side effects | None. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L193-L198` — `!retireAfter` guard |

## Scenario S04-098 — Retire happy path after the overlap window has elapsed

| Field | Content |
|-------|---------|
| ID | S04-098 |
| Journey setup | S04-086 completed → overlay `deprecated` (`successor_id = 'clinic.visit_summary'`); then **[SEED]** `UPDATE capability_grant SET retire_after = '2020-01-01T00:00:00.000Z' WHERE scope = 'global' AND capability_id = 'clinic.visit_summary' AND lifecycle_state = 'deprecated'`. Justification: `OVERLAP_WINDOW_MS` is a hardcoded 90 days (`capability/index.ts:L45-L46`, "not a configuration surface"); moving the clock via SQL is the only practical way to reach the elapsed-window branch in a test. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | **Must occur:** (1) `INSERT capability_grant` overlay — `scope = 'global'`, `lifecycle_state = 'retired'`, `capability_version = '1.0.0'`, `successor_id`/`deprecated_at`/`retire_after` carried over from the deprecate overlay, `granted_at = revoked_at = changed_at = <now>`, `changed_by = 'platform-operator'` (a second overlay row; readers take the latest by `changed_at DESC`); (2) `INSERT control_audit` — `action = 'retire'`, `target = 'clinic.visit_summary@1.0.0'`, `after_pointer = 'clinic.visit_summary'`. **Must not occur:** the deprecate overlay row is not mutated; installation/plan grants untouched. Downstream effects (by behavior): Stage 7 discovery omits the retired version; Stage 9 resolve returns `capability_retired` for pins of `1.0.0`. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L200-L229` — retired overlay + audit batch; `ai-platform/src/control/capability-lifecycle.ts:L35-L50` — latest-overlay read semantics |

## Scenario S04-099 — A second retire after retirement is rejected as not_deprecated

| Field | Content |
|-------|---------|
| ID | S04-099 |
| Journey setup | S04-098 completed → latest overlay `retired`. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, operator bearer, body `{}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"not_deprecated"}` — the latest overlay is `retired`, not `deprecated`, so the state guard rejects; retire is not idempotent. |
| Side effects | None: no third overlay row, no new audit row. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L183-L191` — `lifecycle_state !== "deprecated"` guard |

## Scenario S04-100 — Retire ignores the request body entirely

| Field | Content |
|-------|---------|
| ID | S04-100 |
| Journey setup | S04-086 completed → overlay `deprecated`; **[SEED]** `retire_after` moved to `'2020-01-01T00:00:00.000Z'` (same justification as S04-098). |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`, operator bearer, body `not json{`. |
| Expected outcome | HTTP 200, body exactly `{}` — `handleRetire` never calls `parseJsonBody`; malformed bodies are accepted. (Contrasts with the orientation doc's retire failure table — see Doc-drift observations.) |
| Side effects | Normal retire writes (retired overlay + audit row), identical to S04-098. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L159-L200` — no body parse anywhere in `handleRetire` |

## Scenario S04-101 — Deprecate with a wrong operator bearer → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S04-101 |
| Journey setup | Stage 0 boot happy path (registry holds `clinic.visit_summary@1.0.0`). No lifecycle state needed — the auth gate runs before route parsing and payload validation (same ordering proven for enroll in Stage 3). |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate` with headers `Authorization: Bearer op_wrong-secret-9f8d7c6b5a` (valid format, wrong secret), `Content-Type: application/json`; body `{"successor_id": "clinic.visit_summary"}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — `timingSafeEqualString` rejects the token and `requireOperator` returns the 401 before any route/body handling. |
| Side effects | None: no lifecycle overlay row, no `control_audit` row, no R2 write. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L77-L80` — `handleDeprecate` auth gate; `ai-platform/src/control/auth.ts:L45-L47` — `timingSafeEqualString` bearer compare |

## Scenario S04-102 — Retire with a wrong operator bearer → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S04-102 |
| Journey setup | S04-086 completed (overlay `deprecated` exists). |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire` with header `Authorization: Bearer op_wrong-secret-9f8d7c6b5a`; body `{}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. The existing `deprecated` overlay is untouched. |
| Side effects | None: no overlay transition, no `control_audit` row. |
| Code reference | `ai-platform/src/control/capability-lifecycle.ts:L163-L166` — `handleRetire` auth gate; `ai-platform/src/control/auth.ts:L45-L47` — bearer compare |

## Scenario S04-103 — Cohort activate with a wrong operator bearer → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S04-103 |
| Journey setup | Stage 3 enroll happy path → installation I0; Stage 4 entitle happy path (S04-050) → active entitlement with a live `1.0.0` grant. |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/activate` with header `Authorization: Bearer op_wrong-secret-9f8d7c6b5a`, `Content-Type: application/json`; body `{"installation_ids": ["8f3c2a1e-4b5d-4e6f-9a0b-1c2d3e4f5a6b"], "cohort_name": "beta-ring-1"}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — rejected before the cohort route parse and before the version-existence check. |
| Side effects | None: I0's grant stays on `1.0.0`; no `capability_grant` UPDATE/INSERT; no `control_audit` row. |
| Code reference | `ai-platform/src/control/cohort.ts:L79-L82` — `handleCohortActivate` auth gate; `ai-platform/src/control/auth.ts:L45-L47` — bearer compare |

## Scenario S04-104 — Cohort promote with a wrong operator bearer → 401 unauthorized

| Field | Content |
|-------|---------|
| ID | S04-104 |
| Journey setup | S04-074's preconditions (version `2.0.0` registered, fleet entitled). |
| Action | `POST /control/capabilities/clinic.visit_summary/versions/2.0.0/promote` with header `Authorization: Bearer op_wrong-secret-9f8d7c6b5a`; body `{}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — rejected before the fleet sweep. |
| Side effects | None: no grant materialization, no plan-scope upserts, no `control_audit` snapshot row. |
| Code reference | `ai-platform/src/control/cohort.ts:L188-L191` — `handleCohortPromote` auth gate; `ai-platform/src/control/auth.ts:L45-L47` — bearer compare |

## Doc-drift observations

Orientation doc: `docs/architecture/ai-platform/data-journey/06-stage-4-entitlement-and-capability-grants.md`. Code is authoritative; catalog-side reference sections above mirror corrected behavior. Remaining orientation-only gaps:

1. **~~`500 storage_error` listed for activate / promote / deprecate / retire — not in code.~~** **Fixed (C-08, D-11):** `cohort.ts` and `capability-lifecycle.ts` route `DB.batch` through `runControlBatch`; catalog §7–§10 failure tables list `storage_error` (S04-057 seam applies to entitle; cohort/lifecycle batches use the same mapping).
2. **~~Retire failure table lists `400 invalid_json` "(if body sent)" — unreachable.~~** **Fixed (D-09, D-11):** catalog §10 documents body-ignore; promote likewise in §8 (S04-079, S04-100). Orientation doc §10 still lists `invalid_json` — pending orientation pass.
3. **~~Entitle failure table (doc §5) omits `401 unauthorized` and `400 invalid_json`.~~** **Fixed (D-11):** catalog §5 includes both (S04-001–S04-006).
4. **~~Doc §3 omits plan-scope grant dedup.~~** **Fixed (D-11):** catalog §3 D1-writes bullet documents the skip (S04-054).
5. **~~Duplicate installation ids in one activate produce duplicate live grant rows.~~** **Fixed (C-19, D-11):** catalog §7 documents dedup (S04-070).
6. **~~Truthy non-string `successor_id` crashes deprecate.~~** **Fixed (C-06, D-11):** catalog §9 lists `400 invalid_payload` (S04-091).
7. **~~`invalid_route` in Stage 4 failure tables — unreachable via HTTP.~~** **Fixed (D-09):** catalog §3–§10 failure tables omit `invalid_route`; defensive branches remain in code (A-01). Malformed paths → worker 404.
8. **~~Doc §11.2 "Unprobeable" labels that ARE automatable.~~** **Fixed (D-11):** catalog §11.2 relabels registry-seam probes (see table above).
9. **Doc §10 says retire body is "Empty JSON `{}`"** — code ignores any body; catalog §10 states this (S04-100). Orientation doc wording pending.

## Non-automatable notes

1. **Real 90-day wall-clock wait for the overlap window.** `OVERLAP_WINDOW_MS` is a hardcoded constant (`capability/index.ts:L45-L46`) and the Workers clock cannot be advanced by `@cloudflare/vitest-pool-workers`. Seam used instead: **[SEED]** `UPDATE capability_grant SET retire_after = <past>` after a real deprecate (S04-098, S04-100) — this exercises the exact production comparison in `overlapWindowStillActive`. The un-seeded boundary (`now` exactly equal to `retire_after` → eligible, since the gate is `nowMs < retireAfterMs`) is not reliably schedulable and remains uncovered.
2. **`500 storage_error` from entitle, cohort activate/promote, and capability deprecate/retire (S04-057+).** All handlers use `runControlBatch`; real D1 in the vitest pool does not fail on demand for valid statements. Proposed seam: wrap the `DB` binding in a proxy whose `batch()` throws a non-constraint error, passed through `dispatchControlRequest`'s `bindings` parameter.
3. **Timing-safe bearer comparison.** `timingSafeEqualString` (`auth.ts:L4-L14`) is a side-channel mitigation; its timing behavior is not observable in the test environment. Only functional outcomes (401 vs proceed) are asserted (S04-001–S04-005).
4. **`cost_budget` `Number.isFinite` guard unreachable over HTTP.** JSON cannot encode `NaN`/`Infinity` (`request.json()` rejects them as `invalid_json` first), so the `!Number.isFinite(cost_budget)` branch in `entitle.ts:L110` is defensive-only; no HTTP scenario can reach it. Covered here by documentation, not by a scenario.
5. **Multi-operator audit attribution.** `createSecretOperatorAuth` maps every valid bearer to one configured `operatorId` (`auth.ts:L16-L26` comment: single-operator deployment; no `control_operator` table). Per-operator token rotation/revocation is not implemented, so no scenario can distinguish operators in `control_audit`.
6. **Downstream runtime effects of Stage 4 writes** (guard-stage-3 `forbidden_capability` paths, discovery annotation/omission of deprecated/retired versions, `capability_retired` at resolve, quota exhaustion at zero ceilings) are asserted in the Stage 7/8/9 chapters by behavior; this chapter references them but does not duplicate their HTTP-level assertions.
