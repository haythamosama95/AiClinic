# AI Platform Data Journey — Taxonomy codes and HTTP mapping


| Code                            | HTTP     | Retry safe         | Consumes quota | Typical triggering data                           |
| ------------------------------- | -------- | ------------------ | -------------- | ------------------------------------------------- |
| `unauthenticated`               | 401      | After re-mint      | No             | Bad AAT, expired `exp`, JTI replay, retired `ver` |
| `installation_suspended`        | 403      | No                 | No             | `installation.status=suspended`                   |
| `forbidden_capability`          | 403      | No                 | No             | `entitlement.status`, plan, grants, missing `requiredCapabilityScope` in `principal.scopes`, `principal.role` not in non-empty `Access.allowedStaffRoles` |
| `rate_limited`                  | 429      | Yes                | No             | Rate limit bindings, or grace-admission cap while the Quota DO is down |
| `quota_exhausted`               | 429      | After period reset | No             | Quota DO counters vs entitlement (not the grace cap) |
| `request_too_large`             | 413      | No                 | No             | Body size, token estimate including prompt-artifact bytes |
| `context_required`              | 422      | Yes                | No             | Missing manifest context keys                     |
| `context_invalid`               | 422      | No                 | No             | `org`/`branch` mismatch, bad shapes               |
| `conversation_budget_exhausted` | 409      | No                 | No             | Transcript limits                                 |
| `capability_unknown`            | 404      | No                 | No             | Bad `capability_id`                               |
| `capability_retired`            | 404      | No                 | No             | Lifecycle retired                                 |
| `capability_disabled`           | 503      | Later              | No             | `Access.killSwitchFlag === true`, or D1 `kill_switch` (global / capability / installation). A `provider:<id>` kill switch is routing exclusion, not this code |
| `provider_unavailable`          | 503      | Yes                | Partially      | Empty routing chain                               |
| `provider_rejected`             | 422      | No                 | Yes            | Provider 401/403, content filter                  |
| `validation_failed`             | 422      | Yes                | Yes            | Prose guards (length, stop, leak, refusal prefix, injection-echo), truncation |
| `cancelled`                     | SSE only | —                  | Partially      | Client disconnect                                 |
| `timeout`                       | 504      | Yes                | Partially      | Provider timeout                                  |
| `internal_error`                | 500      | Yes                | No             | D1/compose/routing miss                           |


**Error body shape (HTTP and SSE** `failed`**):**

```json
{
  "code": "<taxonomy>",
  "request_reference": "<XXXX-XXXX>",
  "trace_id": "<ulid>",
  "retry_safe": <boolean>
}
```

Supplementary fields when applicable: `retry_after`, `period_reset`, `missing_keys`.
Live pre-SSE `rate_limited` (429) includes `retry_after`: the Rate Limit
binding's `retryAfter` hint when `limit()` supplies a positive number, otherwise
the 60s simple-limiter window. The field is attached by
`preAcceptFailureResponse` via `supplementaryFieldsForCode` (same error-body
shape as SSE `failed`).

---

## Table of Contents

- [Taxonomy mapping table (intro, unnumbered)](#ai-platform-data-journey--taxonomy-codes-and-http-mapping)
1. [Behavioral verification](#1-behavioral-verification)
   - [1.1 Setup](#11-setup)
   - [1.2 Coverage](#12-coverage)
   - [1.3 Ordered probes](#13-ordered-probes)
     - [1.3.1 Reset to a known invoke-ready state](#131-reset-to-a-known-invoke-ready-state)
     - [1.3.2 unauthenticated](#132-unauthenticated)
     - [1.3.3 installation_suspended](#133-installation_suspended)
     - [1.3.4 forbidden_capability](#134-forbidden_capability)
     - [1.3.5 rate_limited](#135-rate_limited)
     - [1.3.6 quota_exhausted](#136-quota_exhausted)
     - [1.3.7 request_too_large](#137-request_too_large)
     - [1.3.8 context_required](#138-context_required)
     - [1.3.9 context_invalid](#139-context_invalid)
     - [1.3.10 conversation_budget_exhausted](#1310-conversation_budget_exhausted)
     - [1.3.11 capability_unknown](#1311-capability_unknown)
     - [1.3.12 capability_retired](#1312-capability_retired)
     - [1.3.13 capability_disabled](#1313-capability_disabled)
     - [1.3.14 provider_unavailable](#1314-provider_unavailable)
     - [1.3.15 provider_rejected](#1315-provider_rejected)
     - [1.3.16 validation_failed](#1316-validation_failed)
     - [1.3.17 cancelled](#1317-cancelled)
     - [1.3.18 timeout](#1318-timeout)
     - [1.3.19 internal_error](#1319-internal_error)

---

## 1. Behavioral verification

Live probes against a local Worker (`POST /v1/requests`). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§1.3](#13-ordered-probes) top to bottom** on a throwaway local installation. If every probe matches, the mapping table above is what the wire does.

Guard failures (stages 1–10) never open SSE: HTTP JSON, `Content-Type: application/json`, status from `liveHttpStatusForCode` (`errors.ts`). Post-accept failures already sent `200 text/event-stream` + `accepted`; the taxonomy then lives on SSE `failed` (same `{code, request_reference, trace_id, retry_safe}` body). `cancelled` is SSE-only (`liveHttpStatusForCode` returns `null`). `retry_safe` is `isRetrySafe(entry.retryable)`: true unless the taxonomy string is exactly `"No"` or `"—"`.

`consumes quota` is **not** a JSON field. Pre-accept refusals leave `ai_request` unchanged. Post-accept terminals call `creditUsage` with `partial: true` unless the taxonomy `consumesQuota` is `"Yes"`.

### 1.1 Setup

- Local Worker (`cd ai-platform && npm run dev`) at `http://127.0.0.1:8787`. D1 migrations applied (`--local --env development`). `OPERATOR_BEARER_TOKEN` for `/control/*`.
- Clinic already enrolled and entitled for `clinic.visit_summary@1.0.0` with `entitlement.status = active`, plan at least `standard` (Worker preAccept hardcodes `minimumPlanTier: "standard"`), `request_quota` > 0, and an active/canary routing policy for `routing/standard@v1`.
- One AAT from `public.issue_ai_token()`. Decode payload `org`, `branch`, `role`, `scopes`, `iss` (installation id). Visit summary `Access.allowedStaffRoles` is `["clinician", "nurse"]` and `requiredCapabilityScope` is `ai.visit_summary`. A `doctor` / `administrator` token is a ready-made [§1.3.4](#134-forbidden_capability) failure. Probes that must **pass** stage 5 need an AAT whose `role` is `clinician` or `nurse` and whose `scopes` include `ai.visit_summary`.
- `jq`, `uuidgen`, `npx wrangler`. After D1 writes, wait **30 s** (config-cache TTL) or restart the Worker isolate.
- Restore mutating probes (suspend, quota 0, kill switch, retired overlay) before continuing, or re-run [§1.3.1](#131-reset-to-a-known-invoke-ready-state).

Shared env and a JSON POST helper. Save the body as `/tmp/tax-body` and the status line as `/tmp/tax-status`:

```bash
export GATEWAY='http://127.0.0.1:8787'
export AAT='…'
export INSTALLATION_ID='…'   # AAT iss
export ORG='…'               # AAT org
export BRANCH='…'            # AAT branch
export OPERATOR_BEARER_TOKEN='…'

# Visit-summary context: published shape is an object, not a string.
export CTX=$(jq -nc --arg org "$ORG" --arg branch "$BRANCH" '{
  org: $org,
  branch: $branch,
  "visit.chief_complaint@v1": {
    visit_id: "550e8400-e29b-41d4-a716-446655440000",
    complaint: "Headache for three days.",
    recorded_at: "2026-08-21T00:00:00.000Z"
  }
}')

post_json() {
  local body="$1"
  curl -sS -D /tmp/tax-headers -o /tmp/tax-body \
    -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $(uuidgen)" \
    -H "x-capability-version: 1.0.0" \
    --data "$body"
  awk 'NR==1 { print $2 }' /tmp/tax-headers | tee /tmp/tax-status
  cat /tmp/tax-body; echo
}

visit_body() {
  jq -nc --argjson ctx "$CTX" '{
    capability_id: "clinic.visit_summary",
    user_intent: "Summarize today visit for the chart.",
    context: $ctx
  }'
}
```

Expect every **pre-accept** taxonomy JSON body to contain exactly the four core fields (plus `retry_after` only for `rate_limited` — see [§1.3.5](#135-rate_limited)). `request_reference` is `XXXX-XXXX` except the adapter 1 MiB gate, which sends empty `request_reference` and `trace_id` by design.

```bash
jq '{code, request_reference, trace_id, retry_safe, retry_after, period_reset, missing_keys}' /tmp/tax-body
```

D1 (local):

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT COUNT(*) AS n FROM ai_request WHERE installation_id = '$INSTALLATION_ID'"
```

### 1.2 Coverage

Every table row and every supplementary claim in the prose under the table maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| `unauthenticated` → HTTP 401, `retry_safe` true, no quota, no journal | [§1.3.2](#132-unauthenticated) |
| `installation_suspended` → HTTP 403, `retry_safe` false, no quota | [§1.3.3](#133-installation_suspended) |
| `forbidden_capability` → HTTP 403, `retry_safe` false, no quota (entitlement / plan / grants / scope / staff role) | [§1.3.4](#134-forbidden_capability) |
| `rate_limited` → HTTP 429, `retry_safe` true, no quota; live pre-SSE body includes `retry_after` (binding hint or 60) | [§1.3.5](#135-rate_limited) |
| Grace-admission cap while Quota DO is down is `rate_limited`, not `quota_exhausted` | [§1.3.5](#135-rate_limited) |
| `quota_exhausted` → HTTP 429, `retry_safe` true, no quota (DO counters vs entitlement; not the grace cap) | [§1.3.6](#136-quota_exhausted) |
| `period_reset` on live `quota_exhausted` JSON | [§1.3.6](#136-quota_exhausted) (admission computes it; live adapter does **not** attach it) |
| `request_too_large` → HTTP 413, `retry_safe` false, no quota (adapter 1 MiB and/or stage-7 token estimate) | [§1.3.7](#137-request_too_large) |
| `context_required` → HTTP 422, `retry_safe` true, no quota | [§1.3.8](#138-context_required) |
| `missing_keys` on live `context_required` JSON | [§1.3.8](#138-context_required) (`buildContextRequiredResponse` is unused on POST; field is log-only) |
| `context_invalid` → HTTP 422, `retry_safe` false, no quota (`org`/`branch` mismatch or bad shape) | [§1.3.9](#139-context_invalid) |
| `conversation_budget_exhausted` → HTTP 409, no quota (transcript limits) | [§1.3.10](#1310-conversation_budget_exhausted) |
| `capability_unknown` → HTTP 404, `retry_safe` false, no quota | [§1.3.11](#1311-capability_unknown) |
| `capability_retired` → HTTP 404, `retry_safe` false, no quota | [§1.3.12](#1312-capability_retired) |
| `capability_disabled` → HTTP 503, `retry_safe` true, no quota (`Access.killSwitchFlag` or D1 global / capability / installation) | [§1.3.13](#1313-capability_disabled) |
| `provider:<id>` kill switch is routing exclusion, **not** `capability_disabled` | [§1.3.13](#1313-capability_disabled) |
| `provider_unavailable` → SSE `failed` (HTTP 200), `retry_safe` true, quota partial (empty chain / unknown provider) | [§1.3.14](#1314-provider_unavailable) |
| `provider_rejected` → SSE `failed`, `retry_safe` false, quota yes (provider 401/403, missing API key, content filter) | [§1.3.15](#1315-provider_rejected) |
| `validation_failed` → SSE `failed`, `retry_safe` true, quota yes (prose guards / truncation) | [§1.3.16](#1316-validation_failed) |
| `cancelled` → SSE-only; client disconnect; quota partial | [§1.3.17](#1317-cancelled) |
| `timeout` → table HTTP 504 / SSE `failed.code=timeout`; quota partial | [§1.3.18](#1318-timeout) |
| `internal_error` → HTTP 500 pre-accept (missing `capability_id`) or SSE `failed` (routing miss); `retry_safe` true; no quota pre-accept | [§1.3.19](#1319-internal_error) |
| Error body shape `{code, request_reference, trace_id, retry_safe}` on HTTP JSON and SSE `failed` | every pre-accept probe + [§1.3.14](#1314-provider_unavailable)–[§1.3.16](#1316-validation_failed), [§1.3.19](#1319-internal_error) |


### 1.3 Ordered probes

#### 1.3.1 Reset to a known invoke-ready state

**Do:** confirm the Worker and decode the AAT:

```bash
curl -s "$GATEWAY/health"
python3 -c "import json,base64,sys; p=sys.argv[1].split('.')[1]+'=='; print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))" "$AAT"
```

**Expect:** health JSON. Payload has `iss`, `org`, `branch`, `role`, `scopes`, `jti`, `exp`. Set `INSTALLATION_ID`/`ORG`/`BRANCH` from that.

**Do:** `post_json "$(visit_body)"` with a clinician/nurse AAT.

**Expect:** HTTP 200, `Content-Type: text/event-stream`, first event `accepted` with `request_reference` and `trace_id`. (A doctor token stops at [§1.3.4](#134-forbidden_capability) instead — that is still a valid baseline for identity/entitlement probes.)

**Do:** note `SELECT COUNT(*) FROM ai_request WHERE installation_id = '$INSTALLATION_ID'` as **N0**. Pre-accept probes must leave this count unchanged.

#### 1.3.2 unauthenticated

**Do:** POST with a garbage bearer (headers otherwise valid):

```bash
curl -sS -D - -o /tmp/tax-body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer not-a-jwt" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -H "x-capability-version: 1.0.0" \
  --data "$(visit_body)" | head -n 1
jq . /tmp/tax-body
```

**Expect:** HTTP **401**. JSON `code=unauthenticated`, `retry_safe=true`, `request_reference` `XXXX-XXXX`, `trace_id` non-empty. No `retry_after` / `period_reset` / `missing_keys`. `ai_request` count still **N0**. Same code for missing `Authorization`, expired `exp`, retired token-contract `ver`, or Quota DO **jti replay** (reuse the same AAT on a **new** idempotency key after a successful admit — stage 8 maps `replay` onto `unauthenticated`, not a dedicated code).

#### 1.3.3 installation_suspended

**Do:** suspend, then invoke with a still-valid AAT:

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/suspend" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
# wait 30s or restart wrangler
post_json "$(visit_body)"
```

**Expect:** HTTP **403**. `code=installation_suspended`, `retry_safe=false`. No journal increment. Identity maps `installation.status=suspended` here; a bad signature is still `unauthenticated`, not this code.

**Do:** resume before later probes:

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/resume" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

#### 1.3.4 forbidden_capability

**Do:** POST `visit_body` with a **doctor** (or any role not in `["clinician","nurse"]`) AAT that is otherwise entitled.

**Expect:** HTTP **403**. `code=forbidden_capability`, `retry_safe=false`. Stage 5 `assertPlanAllowance` — published `Access.allowedStaffRoles` is non-empty.

**Do:** with a clinician/nurse AAT, omit `ai.visit_summary` from scopes (mint from staff without that RBAC), or D1-update `entitlement.allowed_capabilities` to `[]` / `status` away from `active` / `plan` to `starter`.

**Expect:** same 403 `forbidden_capability`. Stage 3 uses entitlement/plan/grants; stage 5 adds scope and staff role. No journal.

#### 1.3.5 rate_limited

Development bindings (`wrangler.toml`): installation 600/60s, actor **120**/60s, capability 300/60s. Stage 4 runs after identity+entitlement and **before** staff-role resolve, so a doctor AAT still trips the limiter.

**Do:** burst past the actor cap (same AAT, new idempotency key each time):

```bash
for i in $(seq 1 125); do
  code=$(curl -sS -o /tmp/tax-rl-$i -w '%{http_code}' \
    -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $(uuidgen)" \
    -H "x-capability-version: 1.0.0" \
    --data "$(visit_body)")
  echo "$i $code"
  if [ "$code" = "429" ]; then jq . /tmp/tax-rl-$i; break; fi
done
```

**Expect:** HTTP **429**. `code=rate_limited`, `retry_safe=true`, **`retry_after` present** (positive integer: Cloudflare `limit().retryAfter` when supplied, otherwise `DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS` = 60). This is the live pre-SSE field from `preAcceptFailureResponse` → `supplementaryFieldsForCode`. No journal for the 429. This is **not** `quota_exhausted` (budget is unused).

Grace-admission cap (same code, different trigger): `GRACE_ADMISSION_CAP = 5`. Only when the Quota DO fetch throws or returns 5xx. The 6th pending grace insert is `rate_limited` with `retryAfter: 60`, **not** `quota_exhausted`. Local wrangler keeps the DO up, so this path is usually idle; do not use `request_quota=0` to simulate it.

#### 1.3.6 quota_exhausted

Needs stages 1–7 to pass (clinician/nurse AAT, valid context).

**Do:** zero the period request ceiling, wait for cache TTL, then POST `visit_body`:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement SET request_quota = 0 WHERE installation_id = '$INSTALLATION_ID'"
# wait 30s
post_json "$(visit_body)"
```

**Expect:** HTTP **429**. `code=quota_exhausted`, `retry_safe=true`. **No `retry_after`.** **No `period_reset` on the live JSON** — admission fills `periodReset` from the entitlement snapshot (`period_end`) or DO `period_end`, but `GuardFailure` / `PreAcceptResult` only forward `retryAfter`, and `preAcceptFailureResponse` never passes `periodReset` into `supplementaryFieldsForCode`. No journal. Restore `request_quota` (entitle-time value) before continuing.

This is Quota DO counters vs entitlement (or `concurrency_exhausted` mapped onto the same code). It is not the grace-cap 429.

#### 1.3.7 request_too_large

**Do (adapter 1 MiB gate, before the guard):**

```bash
python3 -c "import json; print(json.dumps({'capability_id':'clinic.visit_summary','user_intent':'x'*2_000_000,'context':{}}))" \
  | curl -sS -D /tmp/tax-headers -o /tmp/tax-body -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $(uuidgen)" \
    -H "x-capability-version: 1.0.0" \
    --data-binary @-
awk 'NR==1 { print $2 }' /tmp/tax-headers
jq . /tmp/tax-body
```

**Expect:** HTTP **413**. `code=request_too_large`, `retry_safe=false`. Adapter-gate body uses **empty** `request_reference` and `trace_id` (FR-006). No journal.

**Do (stage-7 preflight, body under 1 MiB):** `user_intent` of ~40k `x` with a valid context so stage 6 passes. Estimator is `ceil((utf8(context+intent) + prompt scaffold bytes) / 4) * 1.15` vs `maxInputTokens` 8000 / `perRequestTokenCeiling` 9024.

**Expect:** HTTP **413**, same code, **non-empty** `request_reference` / `trace_id`. Still no journal. Token estimate includes prompt-artifact bytes (`promptScaffoldByteLength`).

#### 1.3.8 context_required

**Do:** omit the required manifest key; keep `org`/`branch` so this is not `context_invalid`:

```bash
post_json "$(jq -nc --arg org "$ORG" --arg branch "$BRANCH" '{
  capability_id: "clinic.visit_summary",
  user_intent: "Summarize.",
  context: {org: $org, branch: $branch}
}')"
```

**Expect:** HTTP **422**. `code=context_required`, `retry_safe=true`. **No `missing_keys` on the live body.** Validator logs `missing_keys: ["visit.chief_complaint@v1"]` and `buildContextRequiredResponse` can attach `missing_keys` / `shapes` / `manifest_version` / `manifest_capability_id`, but `createProductionPreAccept` returns only `{ok:false, code}` and the adapter uses `buildErrorBody` + `supplementaryFieldsForCode`. No journal. Not SSE `context_requested` (that event is conversational, after accept).

#### 1.3.9 context_invalid

**Do:** required key present but wrong shape (string instead of the published object):

```bash
post_json "$(jq -nc --arg org "$ORG" --arg branch "$BRANCH" '{
  capability_id: "clinic.visit_summary",
  user_intent: "Summarize.",
  context: {
    org: $org,
    branch: $branch,
    "visit.chief_complaint@v1": "not-an-object"
  }
}')"
```

**Expect:** HTTP **422**. `code=context_invalid`, `retry_safe=false`. No journal.

**Do:** object shape but `org` or `branch` ≠ AAT claims.

**Expect:** same 422 `context_invalid`.

#### 1.3.10 conversation_budget_exhausted

Published registry is only `clinic.visit_summary@1.0.0` (`worker.ts` `setCapabilityRegistry`). `interactionMode` is `single_shot`. Pipeline passes conversational options only when the manifest is conversational **and** `turn_ordinal` is present; visit summary never enters transcript-budget checks.

**Do:** POST visit summary with a huge `transcript` / `turn_ordinal`.

**Expect:** not this code. Oversized/omitted conversational fields are ignored on single-shot, or you still get `context_required` / `context_invalid` from the visit-summary keys. **HTTP 409 `conversation_budget_exhausted` is unprobeable on this Worker** until a conversational capability is published. Forcing action in code: register a conversational manifest with numeric `Interaction.maxHistoryTurns`, `maxContextRoundsPerTurn`, `transcriptSizeLimit`, then POST a transcript that exceeds one of those. Wire: HTTP **409**, `retry_safe=true` (`retryable` is `"No, within this conversation"`, which `isRetrySafe` treats as true because it is not exactly `"No"`), no quota, no `missing_keys`.

#### 1.3.11 capability_unknown

**Do:** entitle/grant a bogus id so stage 3 does not 403 first, then invoke it (or skip entitle and accept `forbidden_capability` — that is **not** this probe). Easiest operator path that still hits stage 5: keep visit-summary entitlement and POST a different `capability_id` **after** adding that id to `allowed_capabilities` **and** inserting a matching `capability_grant` (otherwise stage 3 wins):

```bash
post_json "$(jq -nc --argjson ctx "$CTX" '{
  capability_id: "clinic.does_not_exist",
  user_intent: "Summarize.",
  context: $ctx
}')"
```

If stage 3 still returns `forbidden_capability`, add the id to `allowed_capabilities` + a grant row, wait 30 s, retry.

**Expect:** HTTP **404**. `code=capability_unknown`, `retry_safe=false`. Registry key is `{capability_id}@{x-capability-version}`. No journal.

#### 1.3.12 capability_retired

Control `POST …/deprecate` then `…/retire` needs a registered successor and an elapsed overlap window — not practical with a single published capability. Force the overlay the resolver actually reads (`grants` cache key `global/{id}/{version}`):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT INTO capability_grant (
     grant_id, scope, capability_id, capability_version,
     granted_at, revoked_at, changed_at, changed_by,
     lifecycle_state, successor_id, deprecated_at, retire_after
   ) VALUES (
     'retire-probe', 'global', 'clinic.visit_summary', '1.0.0',
     datetime('now'), datetime('now'), datetime('now'), 'operator',
     'retired', 'clinic.visit_summary@1.0.0', datetime('now'), datetime('now')
   )"
# wait 30s
post_json "$(visit_body)"
```

**Expect:** HTTP **404**. `code=capability_retired`, `retry_safe=false`. Effective lifecycle `retired` short-circuits before kill switches. Delete the overlay row before continuing.

#### 1.3.13 capability_disabled

**Do:** D1 kill switch, capability scope (same pattern for `global`/`global` or `installation`/`$INSTALLATION_ID`):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
   VALUES ('capability', 'clinic.visit_summary', 1, datetime('now'), 'operator')"
# wait 30s
post_json "$(visit_body)"
```

**Expect:** HTTP **503**. `code=capability_disabled`, `retry_safe=true`. Stage 3 `evaluateEntitlement` and stage 5 `evaluateCapabilityKillSwitches` both map global / capability / installation (and manifest `Access.killSwitchFlag === true`) onto this code. No journal. Delete the row (or `active=0`) before continuing.

**Do (footnote — provider kill switch is not this code):**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
   VALUES ('provider', 'deepseek', 1, datetime('now'), 'operator')"
# wait 30s
post_json "$(visit_body)"
```

**Expect:** **not** `capability_disabled`. Stage 5 collects `provider:<id>` into `killedProviderIds`; the router excludes those targets with `reason_code: kill_switch`. If that empties the chain, you get post-accept SSE `failed` `provider_unavailable` ([§1.3.14](#1314-provider_unavailable)). Worker preAccept hardcodes `entitlement.providerId: "fake"`: killing **`provider:fake`** is the exception — stage 3 maps it to `capability_disabled`. Kill a provider named in the routing document (`deepseek` / `gemini`), not `fake`, to observe routing exclusion.

#### 1.3.14 provider_unavailable

Post-accept. Guard must pass (clinician/nurse, valid context, quota).

**Do:** publish (or D1/R2-replace) `routing/standard` so the matched rule’s only target is an unwired id. `resolveProviderPort` uses `FakeAdapter(["terminal:provider_unavailable"])` for unknown providers; an empty chain after exclusions is the same terminal:

```bash
curl -sS -X POST "$GATEWAY/control/routing-policies/standard/versions/2/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "schema_version": 1,
      "policy_id": "standard",
      "policy_version": 2,
      "defaults": {"cost_class": "standard", "max_parallel_attempts": 1},
      "rules": [{
        "rule_id": "empty-chain",
        "match": {},
        "requires": {"structured_output": false, "min_context_window": 0, "languages": ["en"]},
        "targets": [{
          "provider_id": "nonexistent-provider",
          "model_id": "x",
          "features": {
            "structured_output": false,
            "min_context_window": 0,
            "languages": ["en"],
            "latency_class": "standard",
            "cost_class": "standard"
          },
          "max_attempts": 1,
          "timeout_ms": 1000
        }]
      }],
      "overrides": []
    }
  }'
# promote/canary so this version is the one the router loads, then:
curl -sN -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -H "x-capability-version: 1.0.0" \
  --data "$(visit_body)"
```

**Expect:** HTTP **200** `text/event-stream` (table 503 is `liveHttpStatusForCode`; this code is not a pre-accept failure). Event `accepted`, then exactly one terminal `failed` whose data is `{code: "provider_unavailable", request_reference, trace_id, retry_safe: true}`. `ai_request.state = Failed`. `usage_event` written; credit `partial: true` (`consumesQuota` is `"Partially, recorded"`). Roll the routing policy back.

#### 1.3.15 provider_rejected

DeepSeek/Gemini map missing API key and HTTP 401/403 / content-filter to `provider_rejected` (`retryability: false` → terminal, no fallback).

**Do:** route the catch-all (or visit-summary rule) at `deepseek` / `gemini` **without** `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` in the Worker env, then SSE-POST `visit_body`.

**Expect:** HTTP **200** SSE. Terminal `failed` `code=provider_rejected`, `retry_safe=false`. Quota **yes** (`consumesQuota: "Yes"` → credit `partial: false`). Stock `FakeAdapter(["success"])` never emits this code.

#### 1.3.16 validation_failed

Production prose thresholds (`worker.ts`): max length 128_000; stop `<|end|>`; refusal prefixes `I'm sorry, I can't help with that` and `I'm sorry, I can't assist` (start of assembled text); injection needle `Ignore previous instructions`; leak needles from the composed system instruction. Truncation (`finish_reason=length`) also ends the chain as `validation_failed`.

**Do:** SSE-POST `visit_body` against a provider that emits one of those needles (DeepSeek user_intent that elicits the refusal prefix, or that echoes `Ignore previous instructions`). Stock `new FakeAdapter(["success"])` always returns `"Fake adapter summary."` and **does not** trip the guards.

**Expect:** HTTP **200** SSE. Terminal `failed` `code=validation_failed`, `retry_safe=true`. Quota **yes**. Tests force this by stubbing `FakeAdapter.invoke`; that stub is not on the live `resolveProviderPort("fake")` path.

#### 1.3.17 cancelled

Adapter `ReadableStream.cancel` / request abort: “nobody left to receive `cancelled` on the wire.” Journal still settles `Cancelled` with partial credit.

**Do:** start an in-flight invoke (DeepSeek, not the instant fake success), then abort the client:

```bash
curl -sN --max-time 1 -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $CANCEL_KEY" \
  -H "x-capability-version: 1.0.0" \
  --data "$(visit_body)"
# CANCEL_KEY must be a fresh uuid; abort during provider fetch, after accepted.
```

**Expect:** HTTP 200 stream starts (`accepted`). Disconnect. Worker log `sse_client_disconnect`. D1 `ai_request.state = Cancelled`. Credit `partial: true`. The aborting curl does **not** see SSE `event: cancelled`. Idempotent replay of the same `x-idempotency-key` can emit `cancelled` with data `{trace_id}` only — not the four-field error body. Table HTTP is 499 internally; `liveHttpStatusForCode("cancelled")` is `null`.

If fake success completes before you abort, you get `completed` instead — retry against a slow provider.

#### 1.3.18 timeout

`invokeWithTimeout` races the port against `timeout_ms` and classifies the **attempt** as `timeout` (`retryable: "Yes"`). Invocation then retries/falls back; when the chain is exhausted it returns `provider_unavailable`, not `timeout`. `liveHttpStatusForCode("timeout")` is 504, but POST never uses that status (timeout is post-accept).

**Do:** publish a single target with `timeout_ms: 1` against DeepSeek (or a FakeAdapter that `await`s a sleeper longer than `timeout_ms` — tests do this; production `resolveProviderPort("fake")` is `new FakeAdapter(["success"])` with **no** sleep). SSE-POST `visit_body`.

**Expect:** attempt row `outcome = timeout` / `error_code = timeout`. Live terminal SSE `failed` is **`provider_unavailable`**, HTTP **200**. You will **not** observe HTTP 504 or `failed.code=timeout` on this Worker. Quota for the exhausted chain is the `provider_unavailable` partial path.

#### 1.3.19 internal_error

**Do (pre-accept, missing capability id):**

```bash
post_json "$(jq -nc --argjson ctx "$CTX" '{user_intent: "Summarize.", context: $ctx}')"
```

**Expect:** HTTP **500**. `code=internal_error`, `retry_safe=true`. `createProductionPreAccept` returns this when `capability_id` / `capability` is absent. No SSE. No journal.

**Do (post-accept routing miss):** delete/unpublish the active routing policy for `standard`, then SSE-POST a guard-passing `visit_body`.

**Expect:** HTTP 200 SSE `failed` `code=internal_error` (no active/canary policy or R2 miss — [Stage 5 routing failure paths](07-stage-5-routing-policy.md#8-routing-failure-paths-post-accept)). Compose failure at guard stage 10 is the other pre-SSE 500 (`runGuard` `internal_error`). Restore the policy.

