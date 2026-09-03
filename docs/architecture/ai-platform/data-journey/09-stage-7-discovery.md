# AI Platform Data Journey — Stage 7 — Discovery (`GET /v1/capabilities`)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Request](#2-request)
3. [D1 reads (via config cache)](#3-d1-reads-via-config-cache)
4. [Response shape](#4-response-shape)
  - [4.1 Success — HTTP 200 and `manifests[]`](#41-success--http-200-and-manifests)
  - [4.2 Conditional GET — HTTP 304 Not Modified](#42-conditional-get--http-304-not-modified)
5. [Failure paths](#5-failure-paths)
6. [Behavioral verification](#6-behavioral-verification)
   - [6.1 Setup](#61-setup)
   - [6.2 Coverage](#62-coverage)
   - [6.3 Ordered probes](#63-ordered-probes)
     - [6.3.1 Reset to a known pending installation](#631-reset-to-a-known-pending-installation)
     - [6.3.2 Who may not call (failure paths)](#632-who-may-not-call-failure-paths)
     - [6.3.3 Pending entitlement (empty-state)](#633-pending-entitlement-empty-state)
     - [6.3.4 Stage 4 entitle then discovery (grants appear)](#634-stage-4-entitle-then-discovery-grants-appear)
     - [6.3.5 Entitled happy path (every response field)](#635-entitled-happy-path-every-response-field)
     - [6.3.6 Conditional GET 304 Not Modified](#636-conditional-get-304-not-modified)
     - [6.3.7 Config cache 30 s TTL and shared isolate](#637-config-cache-30-s-ttl-and-shared-isolate)
     - [6.3.8 Kill switches apply on invoke, not discovery](#638-kill-switches-apply-on-invoke-not-discovery)
     - [6.3.9 What this stage does not do](#639-what-this-stage-does-not-do)

---




## 1. Plain language

The client asks "what AI features can I use?" The platform lists capabilities where entitlement + grants pass. Kill switches are **not** applied on discovery (they apply on invoke).

## 2. Request


| Item   | Value                         |
| ------ | ----------------------------- |
| Method | `GET /v1/capabilities`        |
| Auth   | `Authorization: Bearer <AAT>` |


No body. No extra required headers.

## 3. D1 reads (via config cache)


| Cache kind      | Key                | Purpose                          |
| --------------- | ------------------ | -------------------------------- |
| `installations` | `{installationId}` | Installation exists              |
| `entitlements`  | `{installationId}` | `status`, `allowed_capabilities` |
| `grants`        | per capability     | Version grants                   |


Discovery uses the same isolate-scoped `ConfigCache` as `POST /v1/requests` and
`GET /v1/requests/{ref}`. A prior request in the isolate can warm these rows for 30 s.




## 4. Response shape

List of capability manifests the installation may invoke — filtered to entitled, granted, non-retired capabilities.

**Pending entitlement:** typically `{ "manifests": [] }`.

`buildDiscoveryResponse` (`src/capability/index.ts`) sets response headers on every success and not-modified reply.

### 4.1 Success — HTTP 200 and `manifests[]`


| Item           | Value                                              |
| -------------- | -------------------------------------------------- |
| Status         | `200`                                              |
| `Content-Type` | `application/json`                                 |
| `Cache-Control`| `private, must-revalidate`                         |
| `ETag`         | Quoted opaque hash — `"<etag>"` (raw hash without quotes in `discover()`; wire value is always quoted) |
| Body           | `{ "manifests": [ … ] }` — **only** top-level key   |


Each `manifests[]` element is the published §5.1 capability bundle (ten field groups). Visit summary (`clinic.visit_summary@1.0.0`) illustrates every group:


| Group | Field | Type / values | Visit summary example |
| ----- | ----- | ------------- | --------------------- |
| **Identity** | `capabilityId` | string | `clinic.visit_summary` |
| | `version` | semver string | `1.0.0` |
| | `title` | string | `Visit summary` |
| | `lifecycleState` | `active` \| `deprecated` \| `retired` | `active` |
| | `successorId` | string \| null | `null` |
| **Access** | `requiredCapabilityScope` | string | `ai.visit_summary` |
| | `minimumPlanTier` | plan enum | `standard` |
| | `allowedStaffRoles` | string[] | `clinician`, `nurse` |
| | `killSwitchFlag` | boolean | `false` (manifest flag only; D1 kill switches are not applied on discovery) |
| **Interaction** | `interactionMode` | `single_shot` \| `conversational` | `single_shot` |
| **Input** | `userIntentShape` | string | `plain_text` |
| | `priorTurnShape` | object \| null | `null` |
| | `sizeLimits.maxChars` | number | `8000` |
| | `allowedLanguages` | string[] | `["en"]` |
| **Context requirements** | `[].key` | context key | `visit.chief_complaint@v1` |
| | `[].required` | boolean | `true` |
| | `[].shapeRef` | string | `visit.chief_complaint@v1` |
| | `[].maxSize` | bytes | `4096` |
| **Prompt binding** | `systemInstructionArtifactRef` | artifact ref | `clinic.visit_summary/system@v1` |
| | `businessRuleFragmentRefs` | string[] | `clinic.visit_summary/rules-visit-summary@v1` |
| | `contextRenderingTemplateRef` | string | `clinic.visit_summary/template-visit-summary@v1` |
| | `outputFormatInstructionDerivationRule` | string | `derive_from_output_mode` |
| **Output** | `mode` | `prose` \| structured modes | `prose` |
| | `outputSchemaRef` | string \| null | `null` |
| | `businessValidationRuleRefs` | string[] | `[]` |
| | `repairPolicy.allowed` | boolean | `false` |
| | `repairPolicy.maxAttempts` | number | `0` |
| **Routing** | `routingPolicyRef` | policy ref | `routing/standard@v1` |
| | `requiredProviderFeatures.structuredOutput` | boolean | `false` |
| | `requiredProviderFeatures.contextWindow` | number | `32000` |
| | `requiredProviderFeatures.language` | string | `en` |
| | `latencyClass` | string | `standard` |
| | `degradedTierPolicy` | string | `fallback_chain` |
| **Economics** | `maxInputTokens` | number | `8000` |
| | `maxOutputTokens` | number | `1024` |
| | `perRequestTokenCeiling` | number | `9024` |
| | `quotaWeight` | number | `1` |
| **Governance** | `acceptanceMode` | string | `advisory_display` |
| | `retentionClass` | string | `diagnostic_30d` |
| | `evalSuiteRef` | string | `evals/visit-summary@v1` |


Stage 8 sends `Identity.capabilityId` as body `capability_id` and `Identity.version` as header `x-capability-version`.

### 4.2 Conditional GET — HTTP 304 Not Modified

When the client sends `If-None-Match` and the opaque tag still matches the current discovery etag, the handler returns **304** with **no JSON body** — the client keeps its cached `manifests` array.


| Item | Value |
| ---- | ----- |
| Request header | `If-None-Match` — optional on `GET /v1/capabilities` |
| Match rules | Trimmed header equals `*` **or** any comma-separated etag token matches the current raw etag (quoted `"hash"`, weak `W/"hash"`, and list forms per `ifNoneMatchMatches` in `src/capability/index.ts`) |
| Status | `304 Not Modified` |
| Body | **Empty** (`null` — no `manifests` key) |
| Response headers | `ETag: "<same hash as a 200 would carry>"`, `Cache-Control: private, must-revalidate` |
| Absent header | Normal `200` with full `{ "manifests": … }` body |


`handleDiscoveryRequest` logs `if_none_match` when present, then delegates to `buildDiscoveryResponse(request, manifests, etag)`.


## 5. Failure paths

Same as identity stage 2 — invalid AAT → `401 unauthenticated`.

## 6. Behavioral verification

Live probes against a local Worker (`GET /v1/capabilities` in `src/discovery/index.ts`, routed from `src/worker.ts`). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§6.3](#63-ordered-probes) top to bottom** on a throwaway local clinic already enrolled on the platform (Stage 3). If every probe matches, this stage is working.

The live gate is `EnrolledKeyVerifier` plus `discover()`. Any staff who can mint an AAT may call. The operator bearer is not an AAT. Discovery does not mint, entitle, invoke, or write D1.

### 6.1 Setup

- Local Worker (`cd ai-platform && npm run dev`) at `http://127.0.0.1:8787`. Local D1 migrations applied (`npx wrangler d1 migrations apply ai-platform-development --local --env development`).
- Clinic already through Stages 2–3: keypair in clinic Postgres, installation row in D1, a staff session that can `issue_ai_token` (at least one `ai.*` RBAC permission).
- `OPERATOR_BEARER_TOKEN` for Stage 4 entitle only. Clinic `installation_id` from enroll (call it **I0**).
- Published registry on this Worker is `clinic.visit_summary@1.0.0`. Its `Access.minimumPlanTier` is `standard`, so D1 `entitlement.plan` must be `standard`, `professional`, or `enterprise` at enroll time. If an installation was enrolled before plan validation shipped, patch D1 or re-enroll in [§6.3.1](#631-reset-to-a-known-pending-installation).
- After D1 writes that do not go through this isolate’s cache (`POST /control/…/entitle`, `wrangler d1 execute`), either wait **31 s** or restart `npm run dev` before treating discovery as fresh. The isolate `ConfigCache` TTL is 30 s (`CACHE_TTL_MS`); entitle does not invalidate it.

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export INSTALLATION_ID='<I0>'
```

Mint as the named clinic session (PostgREST `POST /rest/v1/rpc/issue_ai_token` with that user’s Bearer token, or SQL while that session is active):

```sql
SELECT set_config('role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  json_build_object('sub', '<auth_user_id>'::text, 'role', 'authenticated')::text,
  true
);
SELECT public.issue_ai_token();
```

Reset `role` to `postgres` before inspecting clinic tables. Save the JWS as `AAT`. Discovery calls:

```bash
curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT" \
  -o /tmp/discovery.json
```

No body. No extra required headers.

### 6.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Method `GET /v1/capabilities`; `Authorization: Bearer <AAT>`; no body; no extra required headers | [§6.3.3](#633-pending-entitlement-empty-state), [§6.3.5](#635-entitled-happy-path-every-response-field) |
| Invalid AAT → `401 unauthenticated` ([§5](#5-failure-paths)) | [§6.3.2](#632-who-may-not-call-failure-paths) |
| Who may call: any valid AAT. Who may not: missing/empty/non-Bearer/operator token; `POST` is not this route | [§6.3.2](#632-who-may-not-call-failure-paths) |
| Pending entitlement → empty list ([§4](#4-response-shape)) | [§6.3.3](#633-pending-entitlement-empty-state) |
| Cache kinds `installations` / `entitlements` / `grants` as in [§3](#3-d1-reads-via-config-cache) | [§6.3.1](#631-reset-to-a-known-pending-installation), [§6.3.4](#634-stage-4-entitle-then-discovery-grants-appear) |
| Same isolate `ConfigCache` as `POST /v1/requests` and `GET /v1/requests/{ref}`; 30 s TTL | [§6.3.7](#637-config-cache-30-s-ttl-and-shared-isolate) |
| Stage 4 entitle + grants → capability appears | [§6.3.4](#634-stage-4-entitle-then-discovery-grants-appear) |
| 200 body `{ "manifests": [...] }` plus `ETag` / `Cache-Control` / `Content-Type`; every visit-summary field group | [§6.3.5](#635-entitled-happy-path-every-response-field) |
| `If-None-Match` matches → HTTP 304, empty body, same `ETag` ([§4.2](#42-conditional-get--http-304-not-modified)) | [§6.3.6](#636-conditional-get-304-not-modified) |
| Filtered to entitled, granted, non-retired | [§6.3.4](#634-stage-4-entitle-then-discovery-grants-appear), [§6.3.9](#639-what-this-stage-does-not-do) |
| Kill switches **not** applied on discovery; they apply on invoke ([§1](#1-plain-language)) | [§6.3.8](#638-kill-switches-apply-on-invoke-not-discovery) |
| Does not mint, entitle, invoke, or write D1 | [§6.3.9](#639-what-this-stage-does-not-do) |
| Stage 8 ingress consumes `capability_id` + version from this list | [§6.3.7](#637-config-cache-30-s-ttl-and-shared-isolate) |


### 6.3 Ordered probes

#### 6.3.1 Reset to a known pending installation

Restart `npm run dev` so the isolate cache is cold.

**Do:** inspect local D1 for **I0**:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id, status FROM installation WHERE installation_id = '$INSTALLATION_ID'"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT status, plan, allowed_capabilities FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT scope, capability_id, capability_version, revoked_at FROM capability_grant WHERE scope = 'installation:$INSTALLATION_ID'"
```

**Expect:** one `installation` row, `status = active` (identity will load cache kind `installations` / `{installationId}`). Entitlement exists. If `plan` is not `standard`/`professional`/`enterprise`:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement SET plan = 'professional' WHERE installation_id = '$INSTALLATION_ID'"
```

**Do:** put entitlement back to the Stage 3 enroll sentinel and drop installation grants / kill switches (entitle is one-shot on `pending`):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM capability_grant WHERE scope = 'installation:$INSTALLATION_ID'"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM kill_switch"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement SET status = 'pending', allowed_capabilities = '[]', request_quota = 0, token_budget = 0, cost_budget = 0, soft_threshold = 0 WHERE installation_id = '$INSTALLATION_ID'"
```

Restart `npm run dev` again after these D1 writes.

**Expect:** `entitlement.status = pending`, `allowed_capabilities = []`, no installation grant rows. This is the empty-state [§4](#4-response-shape) names.

#### 6.3.2 Who may not call (failure paths)

This is the only failure row in [§5](#5-failure-paths): invalid AAT → `401 unauthenticated`. The handler rejects before `discover()`: missing header, non-`Bearer` scheme, empty token, or `EnrolledKeyVerifier` failure. JSON body is `buildErrorBody` (`code`, `request_reference`, `trace_id`, `retry_safe`) — no `manifests`.

**Do:**

```bash
curl -sS -D - "$GATEWAY/v1/capabilities" -o /tmp/disc-missing.json
curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer" \
  -o /tmp/disc-empty.json
curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Basic not-an-aat" \
  -o /tmp/disc-basic.json
curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer not-a-valid-token" \
  -o /tmp/disc-garbage.json
curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -o /tmp/disc-operator.json
curl -sS -D - -X POST "$GATEWAY/v1/capabilities" \
  -o /tmp/disc-post.txt
```

**Expect:** the five GETs are HTTP **401**, `code = "unauthenticated"`, no `manifests` field. Operator bearer is not an AAT — same 401. `POST /v1/capabilities` is **404** `Not Found` (worker matches this path only for `GET`). Nobody else has a discovery route: no extra required headers, no control-plane substitute.

#### 6.3.3 Pending entitlement (empty-state)

**Do:** mint a fresh AAT as doctor (or any staff with `ai.*`). Count journal rows, then GET with only the Authorization header:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT COUNT(*) AS n FROM ai_request"

curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT" \
  -o /tmp/discovery.json
```

**Expect:** HTTP **200**. `Content-Type: application/json`. `Cache-Control: private, must-revalidate`. `ETag` is a quoted hash. Body is `{ "manifests": [] }` — pending / zero grants, so nothing to list. This is not a 401. Identity passed (installation exists; cache kind `installations`). `discover()` loaded `entitlements` / `{installationId}`, saw `status != 'active'`, and returned an empty list.

**Do:** repeat the `ai_request` count.

**Expect:** unchanged. Discovery does not invoke and does not journal.

#### 6.3.4 Stage 4 entitle then discovery (grants appear)

**Do:** entitle **I0** (Stage 4). Grants in this payload are what discovery will list:

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "period_start": "2026-08-01T00:00:00.000Z",
    "period_end": "2026-09-01T00:00:00.000Z",
    "request_quota": 1000,
    "token_budget": 500000,
    "cost_budget": 50.0,
    "soft_threshold": 0.8,
    "allowed_capabilities": ["clinic.visit_summary"],
    "grants": [
      {
        "capability_id": "clinic.visit_summary",
        "capability_version": "1.0.0",
        "scope": "installation"
      }
    ]
  }'
```

**Expect:** HTTP 200, `{ "installation_id": "<I0>", "status": "active" }`.

**Do:** immediately GET `/v1/capabilities` again with the same AAT (do not wait).

**Expect:** still `{ "manifests": [] }` if [§6.3.3](#633-pending-entitlement-empty-state) already warmed `entitlements` in this isolate — entitle writes D1 and does not bust the 30 s cache. That is [§3](#3-d1-reads-via-config-cache).

**Do:** wait 31 s (or restart `npm run dev`), then:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT status, allowed_capabilities FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT capability_id, capability_version, revoked_at FROM capability_grant WHERE scope = 'installation:$INSTALLATION_ID'"

curl -sS "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT" | jq '.manifests | map(.Identity.capabilityId)'
```

**Expect:** D1 `entitlement.status = active`, `allowed_capabilities` contains `clinic.visit_summary`, one grant row `clinic.visit_summary` / `1.0.0` with `revoked_at` null. Discovery lists `["clinic.visit_summary"]` only — entitled, granted, non-retired. Ungranted registry entries cannot appear; this Worker’s published set is that one capability.

#### 6.3.5 Entitled happy path (every response field)

**Do:** after [§6.3.4](#634-stage-4-entitle-then-discovery-grants-appear) is visible:

```bash
curl -sS -D - "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT" \
  -o /tmp/discovery.json
jq '.manifests[0]' /tmp/discovery.json
```

**Expect:** HTTP **200**. Headers: `Content-Type: application/json`, `Cache-Control: private, must-revalidate`, `ETag` matching `/^".+"$/`. Body key is **`manifests`** (array of length 1). That object is the published visit-summary manifest — every field group listed in [§4.1](#41-success--http-200-and-manifests):

- `Identity.capabilityId = "clinic.visit_summary"`
- `Identity.version = "1.0.0"`
- `Identity.title = "Visit summary"`
- `Identity.lifecycleState = "active"`
- `Identity.successorId = null`
- `Access.requiredCapabilityScope = "ai.visit_summary"`
- `Access.minimumPlanTier = "standard"`
- `Access.allowedStaffRoles` includes `clinician` and `nurse`
- `Access.killSwitchFlag = false`
- `Interaction.interactionMode = "single_shot"`
- `Input.userIntentShape = "plain_text"`
- `Input.priorTurnShape = null`
- `Input.sizeLimits.maxChars = 8000`
- `Input.allowedLanguages = ["en"]`
- `Context requirements[0].key = "visit.chief_complaint@v1"` (required, `maxSize` 4096)
- `Prompt binding.systemInstructionArtifactRef = "clinic.visit_summary/system@v1"`
- `Output.mode = "prose"`
- `Routing.routingPolicyRef = "routing/standard@v1"`
- `Economics.perRequestTokenCeiling = 9024`
- `Governance.acceptanceMode = "advisory_display"`

No other top-level body keys. Stage 8 will send this `capabilityId` as `capability_id` and this `version` as `x-capability-version`.

#### 6.3.6 Conditional GET 304 Not Modified

**Do:** after [§6.3.5](#635-entitled-happy-path-every-response-field), capture the `ETag` response header from the first GET (call it **ETAG0**). Issue a second GET with the same AAT:

```bash
curl -sS -D /tmp/disc-304-hdr -o /tmp/disc-304-body \
  -H "Authorization: Bearer $AAT" \
  -H "If-None-Match: $ETAG0" \
  "$GATEWAY/v1/capabilities"
wc -c /tmp/disc-304-body
head -n 20 /tmp/disc-304-hdr
```

**Expect:** HTTP **304 Not Modified**. Response body length **0** (empty — no JSON, no `manifests` key). Headers still include `ETag: $ETAG0` (same quoted value) and `Cache-Control: private, must-revalidate`. This is [§4.2](#42-conditional-get--http-304-not-modified).

**Do:** repeat with a stale tag:

```bash
curl -sS -D /tmp/disc-stale-hdr -o /tmp/disc-stale-body \
  -H "Authorization: Bearer $AAT" \
  -H 'If-None-Match: "stale-etag-not-current"' \
  "$GATEWAY/v1/capabilities"
```

**Expect:** HTTP **200** with a non-empty `{ "manifests": … }` body — mismatch revalidates the full list.

#### 6.3.7 Config cache 30 s TTL and shared isolate

Discovery, `POST /v1/requests`, and `GET /v1/requests/{ref}` share `isolateConfigCache`.

**Do:** with the entitled list still cached from [§6.3.5](#635-entitled-happy-path-every-response-field), flip D1 **without** going through the Worker:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement SET status = 'pending' WHERE installation_id = '$INSTALLATION_ID'"

curl -sS "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT" | jq '.manifests | length'

curl -sS -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "x-idempotency-key: disc-cache-probe" \
  -H "x-capability-version: 9.9.9" \
  -H "Content-Type: application/json" \
  -d '{"capability_id":"clinic.visit_summary","user_intent":"cache probe","context":{}}' \
  -o /tmp/disc-ingress-warm.json

curl -sS -D - "$GATEWAY/v1/requests/ZZZZ-ZZZZ" \
  -H "Authorization: Bearer $AAT" \
  -o /tmp/disc-get-ref.txt
```

**Expect:** discovery still returns **1** manifest (stale `entitlements` row). Ingress `POST` does **not** return `403` `forbidden_capability` — identity and entitlement still read the warm cache; version `9.9.9` fails later as `404` `capability_unknown` (no provider invoke). `GET /v1/requests/ZZZZ-ZZZZ` is **404** after the same AAT check, not 401 — same verifier and cache kinds `installations` / keys.

**Do:** wait 31 s, repeat GET `/v1/capabilities` and the same `POST /v1/requests` (new `x-idempotency-key`).

**Expect:** discovery `{ "manifests": [] }`. Ingress **403** `forbidden_capability` (`ai_disabled` while pending). TTL elapsed; both routes now see D1.

**Do:** restore entitled state for the remaining probes:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement SET status = 'active' WHERE installation_id = '$INSTALLATION_ID'"
```

Wait 31 s (or restart `npm run dev`). GET `/v1/capabilities` lists `clinic.visit_summary` again.

#### 6.3.8 Kill switches apply on invoke, not discovery

**Do:** turn on a capability kill switch in D1 (no HTTP API):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by) VALUES ('capability', 'clinic.visit_summary', 1, '2026-08-21T00:00:00.000Z', 'verify')"

curl -sS "$GATEWAY/v1/capabilities" \
  -H "Authorization: Bearer $AAT" | jq '.manifests | map(.Identity.capabilityId)'

curl -sS -D - -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "x-idempotency-key: disc-kill-probe" \
  -H "x-capability-version: 1.0.0" \
  -H "Content-Type: application/json" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "user_intent": "kill-switch probe",
    "context": {
      "org": "<must match AAT org>",
      "branch": "<must match AAT branch>",
      "visit.chief_complaint@v1": "Probe."
    }
  }' \
  -o /tmp/disc-kill-invoke.json
```

**Expect:** discovery still lists `clinic.visit_summary` (`killSwitchFlag` stays `false`; `discover()` does not load `kill_switches`). Invoke is HTTP **503**, `code = "capability_disabled"` — JSON, no SSE. Kill switches apply on invoke, not on this stage.

**Do:** `DELETE FROM kill_switch` and wait 31 s if an invoke warmed that row.

#### 6.3.9 What this stage does not do

**Do:** as `postgres` on the clinic DB, `SELECT COUNT(*) FROM ai_internal.ai_token_issuance;` before and after several `GET /v1/capabilities` calls (do not call `issue_ai_token` in between).

**Expect:** count unchanged. Discovery does not mint AATs (Stage 6 does).

**Do:** local D1 `SELECT COUNT(*) FROM ai_request` and `SELECT status, allowed_capabilities FROM entitlement WHERE installation_id = '$INSTALLATION_ID'` before and after GET `/v1/capabilities`.

**Expect:** journal count unchanged; entitlement row unchanged. This GET does not entitle, does not invoke, does not write grants.

**Do:** with grants still present, GET `/v1/capabilities` and confirm `Identity.lifecycleState` is `active` (not `retired`).

**Expect:** the listed capability is non-retired. This Worker has no second published capability to omit; filtering is the empty list when pending ([§6.3.3](#633-pending-entitlement-empty-state)) versus `clinic.visit_summary` when entitled and granted ([§6.3.4](#634-stage-4-entitle-then-discovery-grants-appear)).
