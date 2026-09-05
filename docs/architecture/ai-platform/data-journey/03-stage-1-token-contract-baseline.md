# AI Platform Data Journey — Stage 1 — Token contract baseline

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [D1 row (`token_contract`)](#3-d1-row-token_contract)
4. [Control-plane token-contract rotation](#4-control-plane-token-contract-rotation)
   - [`POST /control/token-contract/begin-rotation`](#41-post-controltoken-contractbegin-rotation)
   - [`POST /control/token-contract/retire`](#42-post-controltoken-contractretire)
5. [Runtime consumption (identity stage 2)](#5-runtime-consumption-identity-stage-2)
6. [Behavioral verification](#6-behavioral-verification)
   - [6.1 Setup](#61-setup)
   - [6.2 Coverage](#62-coverage)
   - [6.3 Ordered probes](#63-ordered-probes)
     - [6.3.1 Reset to the seeded contract](#631-reset-to-the-seeded-contract)
     - [6.3.2 Seed baseline](#632-seed-baseline)
     - [6.3.3 Who may not call control APIs](#633-who-may-not-call-control-apis)
     - [6.3.4 Failure paths on the stable set](#634-failure-paths-on-the-stable-set)
     - [6.3.5 First rotation](#635-first-rotation)
     - [6.3.6 Rotation already open](#636-rotation-already-open)
     - [6.3.7 Dual-accept and minting handoff](#637-dual-accept-and-minting-handoff)
     - [6.3.8 Retire the prior version](#638-retire-the-prior-version)
     - [6.3.9 Identity failure after retiring ver](#639-identity-failure-after-retiring-ver)
     - [6.3.10 Rotation reuse and what this stage does not do](#6310-rotation-reuse-and-what-this-stage-does-not-do)

---

## 1. Plain language

The platform maintains a list of **accepted AAT versions** (`ver` claim). Today only `ver=1` is seeded. When you rotate to `ver=2`, both can be accepted briefly; retiring `ver=1` rejects old tokens.

## 2. Metaphor

**Passport booklet edition.** The border guard checks your passport is a current edition, not expired booklet type.

## 3. D1 row (`token_contract`)


| Column       | Seed value                 | Meaning                                    |
| ------------ | -------------------------- | ------------------------------------------ |
| `ver`        | `1`                        | Must match AAT payload `ver` claim         |
| `added_at`   | `2026-08-03T00:00:00.000Z` | When this version became accepted          |
| `retired_at` | `NULL`                     | `NULL` = still accepted; non-null = reject |
| `changed_by` | `seed`                     | Who added it (`OPERATOR_ID` on rotation)   |




## 4. Control-plane token-contract rotation

Same single-operator auth as every `/control/*` route: one `OPERATOR_BEARER_TOKEN` maps to one
`OPERATOR_ID` on `token_contract.changed_by` / `control_audit`. The trail cannot distinguish
operators (see [Stage 3 enroll auth](05-stage-3-platform-installation-enrollment.md#3-api-post-controlinstallationsinstallation_idenroll)).

Both routes use operator Bearer auth (`requireOperator`), parse a JSON body, and validate `ver` via
`requireNonEmptyString` followed by `.trim()` before any D1 work. The `ver` contract is
**non-empty after trim** only — surrounding whitespace is stripped and the trimmed value is
inserted, returned, and used for duplicate checks; there is no length or charset validation beyond
that. Malformed paths and unknown actions fall through to HTTP 404 plain-text `Not Found` at the
worker router — not `400 invalid_route` (dispatch pre-filters with `TOKEN_CONTRACT_PATTERN`).

### 4.1 `POST /control/token-contract/begin-rotation`

**Request:**

```json
{ "ver": "<new version string>" }
```


| Field | Required       | Meaning                   |
| ----- | -------------- | ------------------------- |
| `ver` | yes, non-empty after trim | New AAT version to accept |


**Success (200):** `{ "ver": "<ver>" }` (trimmed value)

**D1 writes:** INSERT `token_contract` if fewer than 2 non-retired versions exist.


| Failure | `error`                 | Triggering field                        |
| ------- | ----------------------- | --------------------------------------- |
| 401     | `unauthorized`          | Missing/invalid `OPERATOR_BEARER_TOKEN` |
| 400     | `invalid_json`          | Body not JSON                           |
| 400     | `invalid_ver`           | `ver` missing, empty, whitespace-only, or non-string |
| 409     | `ver_already_exists`    | `ver` (after trim) already in table (including retired rows) |
| 409     | `rotation_already_open` | Already 2 non-retired versions          |




### 4.2 `POST /control/token-contract/retire`

**Request:** `{ "ver": "<version>" }`

**Success (200):** `{ "ver": "<ver>", "retired_at": "<ISO>" }` (`ver` is the trimmed value)

Retire parses and validates the body the same way as begin-rotation (`parseJsonBody` →
`requireNonEmptyString` → `.trim()`).


| Failure | `error`               | Trigger                        |
| ------- | --------------------- | ------------------------------ |
| 401     | `unauthorized`        | Missing/invalid `OPERATOR_BEARER_TOKEN` |
| 400     | `invalid_json`        | Body not JSON                  |
| 400     | `invalid_ver`         | `ver` missing, empty, whitespace-only, or non-string |
| 404     | `ver_not_found`       | `ver` (after trim) not in table |
| 409     | `ver_already_retired` | `retired_at` already set       |
| 409     | `no_rotation_open`    | Only one non-retired version left |




## 5. Runtime consumption (identity stage 2)

After signature verify, load `token_contracts:{payload.ver}`:


| D1 state             | Result            |
| -------------------- | ----------------- |
| Row missing          | `unauthenticated` |
| `retired_at != null` | `unauthenticated` |
| `retired_at == null` | Continue          |


**AAT field:** `ver` (string, required in JWT payload).

## 6. Behavioral verification

Live probes against a running local Worker (and clinic mint from [§6.3.7](#637-dual-accept-and-minting-handoff) onward). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§6.3](#63-ordered-probes) top to bottom** on throwaway local D1 `token_contract` rows. If every probe matches, this stage is working.

Identity loads `token_contracts:{payload.ver}` **after** signature verify ([§5](#5-runtime-consumption-identity-stage-2)). A missing installation or bad signature also returns `unauthenticated` and never reaches this table. Identity probes therefore need an enrolled active installation (Stages 2–3) and a well-signed AAT so the token-contract check is the one that fires.

The isolate `ConfigCache` holds `token_contracts:{ver}` for 30 s (`CACHE_TTL_MS`). After a control mutation of a `ver` this isolate already served, restart `npm run dev` or wait 30 seconds before the next identity POST.

### 6.1 Setup

- Local Worker (`cd ai-platform && npm run dev`) with D1 migrations applied. `OPERATOR_BEARER_TOKEN` from `.dev.vars`. Wrangler `OPERATOR_ID` is `platform-operator`.
- Prefer a D1 you can wipe for `token_contract` / token-contract `control_audit` rows. Do **not** delete the enrolled `installation` / `installation_key` — later probes need them.
- Clinic Supabase already through Stage 2 (keypair) and Stage 3 (platform enroll) on this Worker. Staff who will mint an AAT must have at least one `ai.*` RBAC permission.
- SQL as `postgres` only to inspect `ai_internal.app_settings` (`ai.aat.ver`) and mint as a named session.

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
```

Inspect D1 from `ai-platform/`:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT ver, added_at, retired_at, changed_by FROM token_contract ORDER BY ver"
```

Capability POST (identity probe — Stage 8 headers; this stage only cares whether identity continues or returns `unauthenticated`):

```bash
curl -s -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: probe-$(date +%s)" \
  -H "x-capability-version: 1.0.0" \
  -d '{"capability_id":"clinic.visit_summary","user_intent":"token-contract probe"}'
```

Call clinic RPCs as the named staff session (PostgREST or SQL while that session is active):

```sql
SELECT set_config('role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  json_build_object('sub', '<auth_user_id>'::text, 'role', 'authenticated')::text,
  true
);
```

Reset `role` to `postgres` before inspecting `ai_internal`.

### 6.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Seed is only `ver=1`; `added_at = 2026-08-03T00:00:00.000Z`; `retired_at` NULL; `changed_by = seed` ([§3](#3-d1-row-token_contract), [§1](#1-plain-language)) | [§6.3.1](#631-reset-to-the-seeded-contract), [§6.3.2](#632-seed-baseline) |
| `ver` must match AAT payload `ver` ([§3](#3-d1-row-token_contract), [§5](#5-runtime-consumption-identity-stage-2)) | [§6.3.7](#637-dual-accept-and-minting-handoff) |
| `retired_at` NULL = still accepted; Continue ([§3](#3-d1-row-token_contract), [§5](#5-runtime-consumption-identity-stage-2)) | [§6.3.7](#637-dual-accept-and-minting-handoff) |
| `retired_at` non-null = reject as `unauthenticated` ([§3](#3-d1-row-token_contract), [§5](#5-runtime-consumption-identity-stage-2), [§1](#1-plain-language)) | [§6.3.9](#639-identity-failure-after-retiring-ver) |
| Rotation `changed_by` is `OPERATOR_ID` (`platform-operator`), not `seed` and not the bearer string ([§3](#3-d1-row-token_contract), [§4](#4-control-plane-token-contract-rotation)) | [§6.3.5](#635-first-rotation), [§6.3.8](#638-retire-the-prior-version) |
| Same single-operator auth as every `/control/*`: missing/invalid bearer → 401 `unauthorized`; trail cannot distinguish operators ([§4](#4-control-plane-token-contract-rotation), [§4.1](#41-post-controltoken-contractbegin-rotation)) | [§6.3.3](#633-who-may-not-call-control-apis), [§6.3.5](#635-first-rotation) |
| Operator bearer may call begin-rotation and retire; AAT Bearer and anon may not | [§6.3.3](#633-who-may-not-call-control-apis) |
| begin-rotation empty / missing / non-string `ver` → 400 `invalid_ver` ([§4.1](#41-post-controltoken-contractbegin-rotation)) | [§6.3.4](#634-failure-paths-on-the-stable-set) |
| begin-rotation body not JSON → 400 `invalid_json` ([§4.1](#41-post-controltoken-contractbegin-rotation)) | [§6.3.4](#634-failure-paths-on-the-stable-set) |
| begin-rotation 409 `ver_already_exists` (`ver` already in table, including retired rows) ([§4.1](#41-post-controltoken-contractbegin-rotation)) | [§6.3.4](#634-failure-paths-on-the-stable-set), [§6.3.10](#6310-rotation-reuse-and-what-this-stage-does-not-do) |
| begin-rotation 409 `rotation_already_open` (already 2 accepted versions) ([§4.1](#41-post-controltoken-contractbegin-rotation)) | [§6.3.6](#636-rotation-already-open) |
| begin-rotation success 200 `{ "ver" }`; D1 INSERT when fewer than 2 non-retired versions ([§4.1](#41-post-controltoken-contractbegin-rotation)) | [§6.3.5](#635-first-rotation), [§6.3.10](#6310-rotation-reuse-and-what-this-stage-does-not-do) |
| Rotate to `ver=2`: both `ver=1` and `ver=2` accepted briefly ([§1](#1-plain-language)) | [§6.3.5](#635-first-rotation), [§6.3.7](#637-dual-accept-and-minting-handoff) |
| retire 404 `ver_not_found` ([§4.2](#42-post-controltoken-contractretire)) | [§6.3.4](#634-failure-paths-on-the-stable-set) |
| retire 409 `no_rotation_open` (only one accepted version left) ([§4.2](#42-post-controltoken-contractretire)) | [§6.3.4](#634-failure-paths-on-the-stable-set), [§6.3.10](#6310-rotation-reuse-and-what-this-stage-does-not-do) |
| retire success 200 `{ "ver", "retired_at" }` (ISO); D1 stamps `retired_at` ([§4.2](#42-post-controltoken-contractretire)) | [§6.3.8](#638-retire-the-prior-version) |
| retire 409 `ver_already_retired` ([§4.2](#42-post-controltoken-contractretire)) | [§6.3.8](#638-retire-the-prior-version) |
| Identity loads `token_contracts:{payload.ver}` after signature verify ([§5](#5-runtime-consumption-identity-stage-2)) | [§6.3.7](#637-dual-accept-and-minting-handoff) |
| Row missing → `unauthenticated` ([§5](#5-runtime-consumption-identity-stage-2)) | [§6.3.7](#637-dual-accept-and-minting-handoff) |
| Stage 6 handoff: clinic mints `ver` from `ai.aat.ver` (default `1`); this stage does not mint AATs | [§6.3.7](#637-dual-accept-and-minting-handoff) |
| Retire `ver=1`, then POST a capability with that AAT → identity `unauthenticated` ([§1](#1-plain-language), [§5](#5-runtime-consumption-identity-stage-2)) | [§6.3.9](#639-identity-failure-after-retiring-ver) |
| Request path does not write `token_contract`; this stage does not enroll, entitle, or write clinic `ai.aat.ver` | [§6.3.7](#637-dual-accept-and-minting-handoff), [§6.3.9](#639-identity-failure-after-retiring-ver), [§6.3.10](#6310-rotation-reuse-and-what-this-stage-does-not-do) |
| First-time baseline is the seed (not begin-rotation); rotation reuse inserts a **new** `ver` after retire, never re-inserts an existing one | [§6.3.2](#632-seed-baseline), [§6.3.10](#6310-rotation-reuse-and-what-this-stage-does-not-do) |


### 6.3 Ordered probes

#### 6.3.1 Reset to the seeded contract

**Do:** from `ai-platform/`, as local D1. Do not delete `installation` / `installation_key`.

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM control_audit WHERE action IN ('token_contract_begin_rotation', 'token_contract_retire')"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM token_contract"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
   VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed')"
```

Restart `npm run dev` so the isolate cache is empty.

**Expect:** `token_contract` has exactly one row. Next probe can see the Stage 0 seed.

#### 6.3.2 Seed baseline

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT ver, added_at, retired_at, changed_by FROM token_contract"
```

**Expect:** one row, every [§3](#3-d1-row-token_contract) column: `ver = '1'`, `added_at = 2026-08-03T00:00:00.000Z`, `retired_at` NULL (still accepted), `changed_by = 'seed'`. This is the Stage 0 handoff — begin-rotation did not create `ver=1`. Today only `ver=1` is seeded ([§1](#1-plain-language)).

**Do:** `curl -s "$GATEWAY/health"`

**Expect:** HTTP 200. The Worker is up; the passport office rulebook is the seed row, not a clinic.

#### 6.3.3 Who may not call control APIs

Same operator auth as every `/control/*` route ([§4](#4-control-plane-token-contract-rotation)). Both begin-rotation and retire call `requireOperator`.

**Do:** no `Authorization` header:

```bash
curl -s -X POST "$GATEWAY/control/token-contract/begin-rotation" \
  -H "Content-Type: application/json" \
  -d '{"ver":"2"}'

curl -s -X POST "$GATEWAY/control/token-contract/retire" \
  -H "Content-Type: application/json" \
  -d '{"ver":"1"}'
```

**Expect:** HTTP 401, `{ "error": "unauthorized" }` on both. Not taxonomy `unauthenticated` — that code is identity, not control.

**Do:** `Authorization: Bearer definitely-not-the-operator-token` (wrong secret), then again with a clinic AAT as `Bearer` (mint one if you already have it; any compact JWS that is not `OPERATOR_BEARER_TOKEN`).

**Expect:** HTTP 401 `{ "error": "unauthorized" }` on begin-rotation and retire. An AAT is not the operator bearer. Anon and AAT callers cannot rotate the booklet edition.

**Do:** inspect D1 `token_contract` and token-contract `control_audit`.

**Expect:** still the single seed row. No audit row. Failed auth writes nothing.

#### 6.3.4 Failure paths on the stable set

One accepted version (`ver=1`). These failures do not open a rotation.

**Do:** operator bearer, empty `ver`:

```bash
curl -s -X POST "$GATEWAY/control/token-contract/begin-rotation" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ver":""}'
```

**Expect:** HTTP 400, `{ "error": "invalid_ver" }`. `ver` is required and non-empty ([§4.1](#41-post-controltoken-contractbegin-rotation)). Seed row unchanged.

**Do:** begin-rotation of the seed itself: `{ "ver": "1" }`.

**Expect:** HTTP 409, `{ "error": "ver_already_exists" }`. `ver` is already in the table.

**Do:** retire a version that was never inserted: `{ "ver": "never-existed" }`.

**Expect:** HTTP 404, `{ "error": "ver_not_found" }`.

**Do:** retire the sole accepted version: `{ "ver": "1" }`.

**Expect:** HTTP 409, `{ "error": "no_rotation_open" }`. Only one accepted version left — you cannot retire the last booklet edition. `retired_at` on `ver=1` is still NULL.

#### 6.3.5 First rotation

**Do:** operator bearer:

```bash
curl -s -X POST "$GATEWAY/control/token-contract/begin-rotation" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ver":"2"}'
```

**Expect:** HTTP 200, `{ "ver": "2" }` — every success field in [§4.1](#41-post-controltoken-contractbegin-rotation).

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT ver, added_at, retired_at, changed_by FROM token_contract ORDER BY ver"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT operator_id, action, target FROM control_audit
   WHERE action = 'token_contract_begin_rotation'"
```

**Expect:** two non-retired rows (`retired_at` NULL on both). `ver=1` unchanged (`changed_by` still `seed`, seed `added_at`). `ver=2` inserted: `added_at` is now (ISO), `retired_at` NULL, `changed_by = 'platform-operator'` (`OPERATOR_ID`, not the bearer secret). Audit: `operator_id = 'platform-operator'`, `action = 'token_contract_begin_rotation'`, `target = '2'`. The trail cannot tell operators apart — every control write uses that one id. INSERT ran because fewer than two non-retired versions existed.

#### 6.3.6 Rotation already open

**Do:** begin-rotation `{ "ver": "3" }` with the operator bearer (two versions already accepted).

**Expect:** HTTP 409, `{ "error": "rotation_already_open" }`. No `ver=3` row. Accepted set still `{1, 2}`.

**Do:** begin-rotation `{ "ver": "2" }` again.

**Expect:** HTTP 409, `{ "error": "ver_already_exists" }` (`ver` already in the table takes precedence over counting accepted rows). Still two accepted versions. No extra audit row for the failed calls.

#### 6.3.7 Dual-accept and minting handoff

Both booklet editions are accepted. This stage does not mint tokens — Stage 6 `issue_ai_token` reads clinic `ai.aat.ver`.

**Do:** as `postgres`, `SELECT value_json FROM ai_internal.app_settings WHERE key = 'ai.aat.ver';` then as staff with `ai.*`:

```sql
SELECT public.issue_ai_token();
```

Decode the payload (second JWS segment, base64url JSON). Save this token as **AAT_V1**. Do **not** re-mint it later.

**Expect:** compact JWS. Payload `ver` is `"1"` (default `ai.aat.ver`). Payload `iss` is the enrolled `installation_id`. This stage did not return a token.

**Do:** `POST /v1/requests` as in [§6.1](#61-setup) with `Authorization: Bearer` **AAT_V1**. Then inspect `token_contract`.

**Expect:** identity **continues** (`retired_at` on `ver=1` is NULL). HTTP is **not** 401 with `code: unauthenticated`. If the clinic is still pending entitlement you may get a later guard code (`forbidden_capability`, …); if entitled, SSE may open. Either way the border guard accepted this edition. `token_contract` rows are unchanged — the request path does not write this table.

**Do:** as `postgres`:

```sql
UPDATE ai_internal.app_settings
SET value_json = '"2"'::jsonb
WHERE key = 'ai.aat.ver';
```

Mint again. Decode payload `ver`. Save as **AAT_V2**. `POST /v1/requests` with **AAT_V2**.

**Expect:** payload `ver` is `"2"`. Identity continues for **AAT_V2** as well. Rotate-to-`ver=2` overlap: both editions accepted ([§1](#1-plain-language)). The platform did not write `ai.aat.ver` — you did, on clinic Postgres.

**Do:** set `ai.aat.ver` to `"99"`, mint **AAT_MISSING**, `POST /v1/requests` with it. Then set `ai.aat.ver` back to `"1"`.

**Expect:** HTTP 401, JSON `code` is `unauthenticated` (taxonomy body, not control `{ "error": "unauthorized" }`). Row missing for `token_contracts:99` ([§5](#5-runtime-consumption-identity-stage-2)). Keep **AAT_V1** and **AAT_V2** for the next probes.

#### 6.3.8 Retire the prior version

**Do:**

```bash
curl -s -X POST "$GATEWAY/control/token-contract/retire" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ver":"1"}'
```

**Expect:** HTTP 200, `{ "ver": "1", "retired_at": "<ISO>" }` — every success field in [§4.2](#42-post-controltoken-contractretire). `retired_at` is a non-null ISO timestamp.

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT ver, retired_at, changed_by FROM token_contract ORDER BY ver"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT operator_id, action, target FROM control_audit
   WHERE action = 'token_contract_retire'"
```

**Expect:** `ver=1` has `retired_at` equal to the response ISO, `changed_by = 'platform-operator'`. `ver=2` still `retired_at` NULL. Accepted count is 1. Audit: `action = 'token_contract_retire'`, `target = '1'`, `operator_id = 'platform-operator'`.

**Do:** retire `{ "ver": "1" }` again.

**Expect:** HTTP 409, `{ "error": "ver_already_retired" }`. `retired_at` unchanged.

#### 6.3.9 Identity failure after retiring ver

This is the canonical probe for this stage: retire a token-contract version, then POST a capability, and identity fails.

**Do:** restart `npm run dev` (or wait 30 seconds) so identity re-reads D1. Then `POST /v1/requests` with the **same** **AAT_V1** from [§6.3.7](#637-dual-accept-and-minting-handoff). Do not re-mint.

**Expect:** HTTP 401, `code: unauthenticated`. The passport is a retired booklet edition — `retired_at != null` ([§5](#5-runtime-consumption-identity-stage-2)). Signature, `iss`, and `kid` can all still be valid; the guard stops at the token contract. Old tokens are rejected ([§1](#1-plain-language)).

**Do:** `POST /v1/requests` with **AAT_V2** (still accepted). Inspect `token_contract`.

**Expect:** identity continues for `ver=2`. `ver=1` stays retired — the capability POST did not un-retire or insert rows.

#### 6.3.10 Rotation reuse and what this stage does not do

Accepted set is `{2}`; `ver=1` remains in the table as retired.

**Do:** begin-rotation `{ "ver": "1" }`.

**Expect:** HTTP 409, `{ "error": "ver_already_exists" }`. Begin-rotation does not revive a retired row. Reuse is a **new** version string, not a second insert of `1`.

**Do:** begin-rotation `{ "ver": "3" }`.

**Expect:** HTTP 200, `{ "ver": "3" }`. D1 INSERT: `ver=3`, `retired_at` NULL, `changed_by = 'platform-operator'`. Accepted set is `{2, 3}`. This is rotation reuse of the same API after the first-time seed.

**Do:** retire `{ "ver": "2" }`, then retire `{ "ver": "3" }`.

**Expect:** first retire HTTP 200 (`ver=2` stamped). Second retire HTTP 409 `{ "error": "no_rotation_open" }` — again only one accepted version left, now `ver=3`. Same failure as [§6.3.4](#634-failure-paths-on-the-stable-set), after a full rotate/retire cycle.

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id, status FROM installation"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT status, request_quota, token_budget, cost_budget, allowed_capabilities FROM entitlement"
```

As `postgres`: `SELECT value_json FROM ai_internal.app_settings WHERE key = 'ai.aat.ver';`

**Expect:** the enrolled installation is still there (this stage does not enroll or delete it — Stage 3). Entitlement is whatever Stage 4 last wrote (pending / zero quota if you never entitled) — this stage does not grant quotas. Clinic `ai.aat.ver` is still the value you set in [§6.3.7](#637-dual-accept-and-minting-handoff) (`"1"` after the restore). The Worker never wrote clinic Postgres.

