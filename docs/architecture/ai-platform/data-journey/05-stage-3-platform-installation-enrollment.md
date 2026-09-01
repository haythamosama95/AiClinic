# AI Platform Data Journey — Stage 3 — Platform installation enrollment

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [API: `POST /control/installations/{installation_id}/enroll`](#3-api-post-controlinstallationsinstallation_idenroll)
   - [Path parameter](#path-parameter)
   - [Request body — every field](#request-body-every-field)
   - [Success response (200)](#success-response-200)
   - [D1 writes (atomic batch)](#d1-writes-atomic-batch)
   - [How `platform_base_url` reaches Flutter (summary)](#how-platform_base_url-reaches-flutter-summary)
4. [Failure paths](#4-failure-paths)
5. [Post-enroll runtime effect](#5-post-enroll-runtime-effect)
6. [Happy path diagram](#6-happy-path-diagram)
7. [Key rotation](#7-key-rotation)
8. [Behavioral verification](#8-behavioral-verification)
   - [8.1 Setup](#81-setup)
   - [8.2 Coverage](#82-coverage)
   - [8.3 Ordered probes](#83-ordered-probes)
     - [8.3.1 Reset to a known platform state](#831-reset-to-a-known-platform-state)
     - [8.3.2 Obtain the Stage 2 handoff fields](#832-obtain-the-stage-2-handoff-fields)
     - [8.3.3 Who may not call enroll](#833-who-may-not-call-enroll)
     - [8.3.4 Validation failure paths](#834-validation-failure-paths)
     - [8.3.5 First enroll (happy path)](#835-first-enroll-happy-path)
     - [8.3.6 Re-enroll already_enrolled](#836-re-enroll-already_enrolled)
     - [8.3.7 Duplicate kid](#837-duplicate-kid)
     - [8.3.8 Post-enroll effect and what this stage does not do](#838-post-enroll-effect-and-what-this-stage-does-not-do)
     - [8.3.9 Key rotation](#839-key-rotation)

---




## 1. Plain language

The **control-plane caller** registers the installation: "this `installation_id` exists; here is the
public key we will verify AATs against." **No AI spend rights** are granted — entitlement stays
`pending` with zero quotas.

## 2. Metaphor

The **passport office registers the airline** (installation) and files the **stamp specimen** (public key). No flight tickets (quotas) yet.

## 3. API: `POST /control/installations/{installation_id}/enroll`

**Auth:** `Authorization: Bearer <OPERATOR_BEARER_TOKEN>` — verified by `requireOperator` in
`control/http.ts` via `createSecretOperatorAuth` (timing-safe compare against one configured
secret). `operator_id` on audit rows is the single Worker env `OPERATOR_ID` (see [§3 in Stage 0](02-stage-0-platform-configuration-and-boot.md#3-wrangler-configuration-ai-platformwranglertoml)).
This is a **single-operator** deployment: every control-plane action is attributed to that one id.
`control_audit` cannot distinguish operators, and the bearer cannot be rotated or revoked
per-operator. A future `control_operator` table (per-operator token hashes + ids) would be
required for a wider ops team — not implemented.

#### Path parameter


| Field             | Source                                                                         | Meaning                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `installation_id` | **URL path** — value minted in Stage 2 ([§3 in Stage 2](04-stage-2-clinic-keypair-enrollment.md#3-api-publicenroll_installation_keypair)) and carried by the enroll caller | Primary key for all platform rows; must equal clinic `installation_keys.installation_id` and later AAT `iss` |


**How this POST gets** `installation_id`**:** the platform does **not** generate, assign, or discover it.
There is no callback from clinic Supabase to Cloudflare. The **enroll caller** must place the id in
the URL after reading it from the Stage 2 RPC response:

```
Stage 2 (clinic Supabase):  enroll_installation_keypair()
                                    │
                                    ▼
                            { installation_id, kid, public_jwk, … }
                                    │
                                    ▼
                         Flutter (owner/admin session)
                         reads data.installation_id from RPC response
                                    │
                                    ▼
POST /control/installations/{installation_id}/enroll
     ────────────────────────^^^^^^^^^^^^^^^^^^^^
     same UUID string from the RPC `data.installation_id` field
```


| Caller                                       | How it obtains `installation_id`                                                                                              |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Flutter** (intended production)            | `enroll_installation_keypair()` → `data.installation_id` → URL path on `handleEnroll` request ([§7 in Stage 2](04-stage-2-clinic-keypair-enrollment.md#7-who-calls-this-rpc-and-how-the-platform-learns-installation_id))                          |
| **Vendor onboarding** (today, no Flutter UI) | Same RPC via clinic Supabase, then direct `POST /control/installations/{installation_id}/enroll` with `OPERATOR_BEARER_TOKEN` |


The platform only **registers** the id it receives; it never talks to clinic Postgres to learn it.
See also [§7.3 in Stage 2](04-stage-2-clinic-keypair-enrollment.md#73-how-the-platform-learns-installation_id).

#### Request body — every field


| Field          | Required | Source (enroll request body)                                                                                                                 | D1 destination                                        |
| -------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `org_id`       | yes      | Clinic `organizations.id` — Flutter auth session (`organizationId`); validated non-empty in `validateEnrollPayload` (`control/lifecycle.ts`) | `installation.org_id` — metadata only; see note below |
| `display_name` | yes      | Clinic org `name` — Flutter session / `organizations` row                                                                                    | `installation.display_name`                           |
| `region`       | yes      | Caller-supplied string (product/billing config); no Worker default — must be non-empty                                                       | `installation.region`                                 |
| `plan`         | yes      | Caller-supplied string (purchase / subscription tier); stored on entitlement, not interpreted at enroll                                      | `entitlement.plan` (not changed on entitle)           |
| `public_key`   | yes      | Stage 2 RPC `public_jwk.x` (base64url Ed25519 public bytes)                                                                                  | `installation_key.public_key`                         |
| `algorithm`    | yes      | `"EdDSA"` (fixed by clinic keystore)                                                                                                         | `installation_key.algorithm`                          |
| `kid`          | yes      | Stage 2 RPC `kid`                                                                                                                            | `installation_key.key_id`                             |


**About** `org_id` **vs** `installation_id` **(needs review):** these are **not** the same id and do not
play the same role. Each clinic runs its **own** Supabase ([01-ai-platform.md F2](../01-ai-platform.md));
`org_id` is minted in **that** database (`organizations.id`) and is only guaranteed unique **within
that deployment**. The AI platform's global tenant key is path `installation_id` (Stage 2, AAT `iss`).
`org_id` in the body is **metadata** copied for display, support, and the AAT `org` claim — Flutter
reads it from the clinic session and sends it in the enroll JSON body; the platform does not fetch
it from Supabase (`handleEnroll` only reads the request path and body).


| Concern                                                     | Keyed by                                                   |
| ----------------------------------------------------------- | ---------------------------------------------------------- |
| Quota, entitlement, grants, journal, signature verification | `installation_id` (`iss` + `kid`)                          |
| Enroll dedup today                                          | `installation_id` **or** `org_id` → 409 `already_enrolled` |


**Practical impact:** day-to-day AI traffic is unaffected — nothing critical keys off `org_id` alone.
**Risks to review:** (1) two independent clinic deployments could theoretically mint the same
`org_id` UUID, blocking the second enroll; (2) same clinic re-enrolling with a new `installation_id`
but the same `org_id` (e.g. disaster recovery) also hits 409 until the old platform row is removed.
Consider tightening enroll dedup to `**installation_id` only** (or installation plus a clinic-origin
signal) rather than treating clinic-local `org_id` as globally unique.

#### Success response (200)

```json
{ "platform_base_url": "https://<worker-origin>" }
```


| Field               | Origin                        |
| ------------------- | ----------------------------- |
| `platform_base_url` | `new URL(request.url).origin` |




#### D1 writes (atomic batch)

`**installation` INSERT:**


| Column            | Value      |
| ----------------- | ---------- |
| `installation_id` | path param |
| `org_id`          | body       |
| `display_name`    | body       |
| `status`          | `active`   |
| `region`          | body       |
| `enrolled_at`     | ISO now    |


`**installation_key` INSERT:**


| Column            | Value                                                |
| ----------------- | ---------------------------------------------------- |
| `key_id`          | body `kid`                                           |
| `installation_id` | path                                                 |
| `public_key`      | body                                                 |
| `algorithm`       | body                                                 |
| `valid_from`      | `enrolled_at`                                        |
| `valid_until`     | `valid_from` + 365 days (`INSTALLATION_KEY_TTL_DAYS`) |
| `revoked_at`      | `NULL`                                               |


`**entitlement` INSERT:**


| Column                 | Value         | Meaning                                     |
| ---------------------- | ------------- | ------------------------------------------- |
| `entitlement_id`       | new UUID      | PK                                          |
| `installation_id`      | path          | FK; **UNIQUE** — one entitlement row per installation (`idx_entitlement_installation_id`). A second insert for the same installation fails the constraint; enroll already 409s on `already_enrolled` before this write. |
| `plan`                 | body `plan`   | Tier for later checks                       |
| `period_start`         | `enrolled_at` | Placeholder until entitle                   |
| `period_end`           | `enrolled_at` | Placeholder until entitle                   |
| `request_quota`        | `0`           | No requests allowed                         |
| `token_budget`         | `0`           | No tokens                                   |
| `cost_budget`          | `0`           | No cost                                     |
| `allowed_capabilities` | `'[]'`        | JSON empty array                            |
| `soft_threshold`       | `0`           | Sentinel: never degrade-route while pending |
| `status`               | `pending`     | Not AI-enabled                              |


`**control_audit` INSERT:**


| Column        | Value                 |
| ------------- | --------------------- |
| `action`      | `enroll`              |
| `target`      | `installation_id`     |
| `operator_id` | `OPERATOR_ID` env var |


**R2 writes:** none.

#### How `platform_base_url` reaches Flutter (summary)

The enroll response is **not** a discovery mechanism. The caller must already know the gateway
origin to POST enroll; `platform_base_url` is the Worker echoing that origin back
(`new URL(request.url).origin`) so it can be stored canonically in clinic settings. The same
Worker serves `/control/*` and `/v1/*` on that origin.

Flutter **never** learns the gateway URL from a live enroll HTTP response at runtime. Every
client reads `{ enrolled, platform_base_url }` from clinic Postgres via
`public.get_ai_availability()` ([§4 in Stage 2](04-stage-2-clinic-keypair-enrollment.md#4-clinic-availability-flag-manual-step)) and uses `platform_base_url` for `/health` and `/v1/*`
calls. The platform enroll handler does not write clinic `app_settings`.


| Phase                         | Who calls enroll                            | Who receives the enroll JSON | How Flutter gets `platform_base_url`                                                                                                                                                                                                                                                                          |
| ----------------------------- | ------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Today** (vendor onboarding) | Operator (`curl` + `OPERATOR_BEARER_TOKEN`) | Operator terminal            | Manual `UPDATE ai_internal.app_settings …` key `ai.availability` after enroll ([04-ai-platform-operator-runbook.md §5.3](../04-ai-platform-operator-runbook.md#53-clinic-flip-availability)). Operator can paste the enroll response value or the same `GATEWAY` host used for the POST — there is no `set_ai_availability` write RPC yet. |
| **Intended production**       | Flutter (owner/admin, after purchase)       | Flutter in memory            | Flutter writes `ai.availability` after successful enroll ([§7.2 step 4 in Stage 2](04-stage-2-clinic-keypair-enrollment.md#72-end-to-end-flow-intended-production)); all staff clients then read it via `get_ai_availability()`.                                                                                                                                                                           |


Until self-service enrollment ships ([01-ai-platform.md §12.5](../01-ai-platform.md#125-explicitly-not-to-be-built-yet)), operator enroll plus a manual clinic DB update is the deliberate bridge: enroll registers trust on the platform; clinic settings tell every Flutter session where to call.

## 4. Failure paths


| HTTP | `error`            | Triggering input                                            |
| ---- | ------------------ | ----------------------------------------------------------- |
| 401  | `unauthorized`     | Missing/invalid `OPERATOR_BEARER_TOKEN` (`requireOperator`) |
| 400  | `invalid_payload`  | Any required body field empty                               |
| 400  | `invalid_json`     | Body not JSON                                               |
| 409  | `already_enrolled` | `installation_id` or `org_id` already exists                |
| 409  | `duplicate_kid`    | `kid` UNIQUE violation                                      |
| 500  | `storage_error`    | D1 failure                                                  |




## 5. Post-enroll runtime effect

Any `/v1/*` call with valid AAT still fails entitlement stage 3:

- `entitlement.status !== 'active'` → `forbidden_capability`, path `ai_disabled`

**Important:** `installation.status = active` ≠ AI enabled.

## 6. Happy path diagram

```
Authorization: Bearer <OPERATOR_BEARER_TOKEN> + enroll JSON body
  → handleEnroll (control/lifecycle.ts)
  → D1: installation(active) + installation_key + entitlement(pending, quotas=0) + control_audit
  → 200 { platform_base_url }  ← new URL(request.url).origin
  → Flutter sets ai.availability.enrolled=true, platform_base_url ([§4 in Stage 2](04-stage-2-clinic-keypair-enrollment.md#4-clinic-availability-flag-manual-step))
```

## 7. Key rotation

`POST /control/installations/{installation_id}/rotate` inserts a new `installation_key` with
`valid_from = now`, `valid_until = valid_from + 365 days`, `revoked_at = NULL`. In the **same**
D1 batch (`runControlBatch`), it stamps `revoked_at = now` on every currently unrevoked key for
that installation (`WHERE installation_id = ? AND revoked_at IS NULL`), then inserts the new
row. There is no dual-key overlap: in-flight AATs signed with the old `kid` fail identity as
soon as rotate returns. Operators mint new AATs with the new `kid`. See
[§1 in Alternative and failure journeys](15-alternative-and-failure-journeys.md#1-lifecycle-alternatives-control-plane).

## 8. Behavioral verification

Live probes against a local Worker (`npm run dev`) and the throwaway clinic that minted the Stage 2 keypair. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§8.3](#83-ordered-probes) top to bottom**. If every probe matches, this stage is working.

`handleEnroll` / `handleRotate` gate on `requireOperator`: only `Authorization: Bearer` equal to the configured `OPERATOR_BEARER_TOKEN` is accepted (`createSecretOperatorAuth`, timing-safe compare). Staff AATs, missing headers, and wrong secrets all return **401** `{ "error": "unauthorized" }` — there is no control-plane 403. Enroll itself never returns taxonomy codes; `/v1/*` after a successful enroll still fails entitlement with **403** `forbidden_capability` (path `ai_disabled`) until Stage 4 entitle.

### 8.1 Setup

- Local Worker: `cd ai-platform && npm run dev` (port **8787**). Migrations applied on local D1 `ai-platform-development`. Prefer a D1 you can wipe.
- `OPERATOR_BEARER_TOKEN` from `ai-platform/.dev.vars` (same value `wrangler secret put` uses). `OPERATOR_ID` is `platform-operator` in `[env.development.vars]`.
- Throwaway clinic Supabase with Stage 2 available. Prefer a clinic keystore with **one** `installation_keys` row (Stage 2 through [first enroll](04-stage-2-clinic-keypair-enrollment.md#834-first-enroll-happy-path) only). Extra clinic kids from Stage 2 [§8.3.5](04-stage-2-clinic-keypair-enrollment.md#835-administrator-enroll-and-installation_id-reuse-happy-path) make `issue_ai_token` sign the latest `kid`, which will not match a platform enroll of the first key.
- Owner or administrator session to call `enroll_installation_keypair()` (or read the existing row). Doctor (or any staff with `ai.*`) to mint an AAT and to call `get_ai_availability()`.
- Clinic `organizations.id` for enroll body `org_id` (metadata; not the platform tenant key).
- SQL as `postgres` only to inspect clinic `ai_internal.app_settings` / `installation_keys`. Reset `role` to `postgres` after session-scoped RPC calls ([Stage 2 §8.1](04-stage-2-clinic-keypair-enrollment.md#81-setup)).

Shell exports used by every curl below:

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export ORG_ID='<clinic organizations.id>'
```

After [§8.3.2](#832-obtain-the-stage-2-handoff-fields), also export `INSTALLATION_ID`, `KID`, and `PUBLIC_KEY`. Capability POSTs need the compact JWS from `issue_ai_token` plus the Stage 8 required headers (`x-idempotency-key`, `x-capability-version`) so the adapter does not 422 before the guard:

```bash
post_v1() {
  local aat="$1"
  curl -s -D - -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $aat" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $(uuidgen)" \
    -H "x-capability-version: 1.0.0" \
    -d '{"capability_id":"clinic.visit_summary","user_intent":"probe enroll","context":{}}'
}
```

Inspect local D1:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "<SQL>"
```

### 8.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out. `500 storage_error` cannot be forced on a healthy local D1 — do not sabotage the database.


| Claim | Probe |
| ----- | ----- |
| Missing / invalid / staff / anon bearer → 401 `unauthorized`; no D1 write | [§8.3.3](#833-who-may-not-call-enroll) |
| Operator bearer is the only accepted caller | [§8.3.3](#833-who-may-not-call-enroll), [§8.3.5](#835-first-enroll-happy-path) |
| Body not JSON → 400 `invalid_json` | [§8.3.4](#834-validation-failure-paths) |
| Any required body field empty → 400 `invalid_payload` | [§8.3.4](#834-validation-failure-paths) |
| Platform does not generate `installation_id`; D1 empty until this POST | [§8.3.2](#832-obtain-the-stage-2-handoff-fields) |
| AAT before enroll → identity `unauthenticated` (no D1 file for this passport) | [§8.3.2](#832-obtain-the-stage-2-handoff-fields) |
| Clinic `get_ai_availability()` still `{ enrolled: false, platform_base_url: null }` before enroll | [§8.3.2](#832-obtain-the-stage-2-handoff-fields) |
| [§6](#6-happy-path-diagram) POST with clinic `installation_id` + `public_jwk.x` + `kid` → 200 `{ platform_base_url }` equal to the origin you posted | [§8.3.5](#835-first-enroll-happy-path) |
| Success body has **only** `platform_base_url` (no AAT, no quotas) | [§8.3.5](#835-first-enroll-happy-path) |
| D1 `installation`: path id, body `org_id` / `display_name` / `region`, `status = active`, `enrolled_at` | [§8.3.5](#835-first-enroll-happy-path) |
| D1 `installation_key`: `key_id = kid`, `public_key = x`, `algorithm`, `valid_from = enrolled_at`, `valid_until = valid_from + 365 days`, `revoked_at` NULL | [§8.3.5](#835-first-enroll-happy-path) |
| D1 `entitlement`: `pending`, quotas `0`, `allowed_capabilities = []`, `soft_threshold = 0`, `plan` from body; one row (`idx_entitlement_installation_id`) | [§8.3.5](#835-first-enroll-happy-path) |
| D1 `control_audit`: `action = enroll`, `target = installation_id`, `operator_id = OPERATOR_ID` (not the bearer) | [§8.3.5](#835-first-enroll-happy-path) |
| R2 writes: none | [§8.3.5](#835-first-enroll-happy-path) |
| No `control_operator` table (single-operator secret) | [§8.3.5](#835-first-enroll-happy-path) |
| Re-enroll same `installation_id` → 409 `already_enrolled`; row counts unchanged | [§8.3.6](#836-re-enroll-already_enrolled) |
| Different `installation_id`, same `org_id` → 409 `already_enrolled` | [§8.3.6](#836-re-enroll-already_enrolled) |
| New installation + new `org_id`, reused `kid` → 409 `duplicate_kid`; no extra installation row | [§8.3.7](#837-duplicate-kid) |
| 500 `storage_error` on D1 failure | Unprobeable on a healthy local D1 |
| Platform enroll does not write clinic `app_settings` / `ai.availability` | [§8.3.8](#838-post-enroll-effect-and-what-this-stage-does-not-do) |
| `installation.status = active` ≠ AI enabled; entitlement stays `pending` / zero quota | [§8.3.8](#838-post-enroll-effect-and-what-this-stage-does-not-do) |
| Valid AAT `/v1/requests` before entitle → `forbidden_capability` (path `ai_disabled`) | [§8.3.8](#838-post-enroll-effect-and-what-this-stage-does-not-do) |
| This stage does not entitle, grant capabilities, mint AATs, or route/invoke | [§8.3.5](#835-first-enroll-happy-path), [§8.3.8](#838-post-enroll-effect-and-what-this-stage-does-not-do) |
| Rotate stamps `revoked_at` on prior keys in the same batch; new key `revoked_at` NULL, TTL 365 days | [§8.3.9](#839-key-rotation) |
| No dual-key overlap: exactly one unrevoked key after rotate | [§8.3.9](#839-key-rotation) |
| In-flight AAT with the old `kid` fails identity after rotate | [§8.3.9](#839-key-rotation) |


### 8.3 Ordered probes

#### 8.3.1 Reset to a known platform state

**Do:** wipe local D1 enrollment rows (children first). Do **not** delete clinic `installation_keys` — this stage registers what Stage 2 already minted.

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM capability_grant"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM entitlement"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM installation_key"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM installation"
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM control_audit"
```

**Expect:** those tables are empty. The Worker still has no file for any clinic.

**Do:** as `postgres` on the throwaway clinic, if `ai.availability` is not the seed default:

```sql
UPDATE ai_internal.app_settings
SET value_json = '{"enrolled": false, "platform_base_url": null}'::jsonb
WHERE key = 'ai.availability';
```

**Expect:** clinic flag is the Stage 2 seed. Platform enroll must not be the thing that flips it later.

#### 8.3.2 Obtain the Stage 2 handoff fields

Enroll needs clinic-minted `installation_id`, `kid`, and `public_jwk.x`. The platform does not assign or discover them.

**Do:** if `ai_internal.installation_keys` is empty, as **owner** (or administrator):

```sql
SELECT public.enroll_installation_keypair();
```

If a single active row already exists, read it instead of minting a second `kid`. Save:

- `installation_id` → **I0** (`INSTALLATION_ID`)
- `kid` → **K0** (`KID`)
- `public_jwk.x` → **X0** (`PUBLIC_KEY`)

```bash
export INSTALLATION_ID='<I0>'
export KID='<K0>'
export PUBLIC_KEY='<X0>'
```

**Expect:** three non-empty strings. `public_jwk.kty = "OKP"`, `crv = "Ed25519"`. No `secret_key` in the RPC `data`. Path `installation_id` on the coming POST is this **I0**, not a platform-generated id.

**Do:** as doctor with `ai.*`, `SELECT public.issue_ai_token();` Save the compact JWS as **AAT0**. Decode header and payload:

- Header `kid` = **K0** (the key you will enroll)
- Payload `iss` = **I0**

If the header `kid` is not **K0**, stop and enroll *that* `kid` instead — or go back to a one-key clinic. Do **not** call `enroll_installation_keypair()` again until [§8.3.9](#839-key-rotation).

**Do:** inspect D1 for **I0**:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id FROM installation WHERE installation_id = '$INSTALLATION_ID'"
```

**Expect:** no row. The clinic minted **I0**; the platform has not registered it.

**Do:** `post_v1 "$AAT0"` (do **not** enroll yet).

**Expect:** HTTP 401, `code = unauthenticated`. Same shape as Stage 2 [§8.3.8](04-stage-2-clinic-keypair-enrollment.md#838-platform-does-not-know-the-clinic-yet): the border guard has no file for this passport.

**Do:** as doctor, `SELECT public.get_ai_availability();`

**Expect:** `{ "enrolled": false, "platform_base_url": null }`. Flutter still reads this flag, not the Worker, to decide whether AI chrome is shown.

#### 8.3.3 Who may not call enroll

Use a well-formed body so a 401 is auth, not validation. No D1 row for **I0** yet.

```bash
ENROLL_JSON=$(cat <<EOF
{
  "org_id": "$ORG_ID",
  "display_name": "Verify Clinic",
  "region": "local",
  "plan": "verify",
  "public_key": "$PUBLIC_KEY",
  "algorithm": "EdDSA",
  "kid": "$KID"
}
EOF
)
```

**Do:** omit `Authorization`:

```bash
curl -s -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Content-Type: application/json" \
  -d "$ENROLL_JSON"
```

**Expect:** HTTP 401, `{ "error": "unauthorized" }`.

**Do:** `Authorization: Bearer ` (empty token), then `Bearer not-the-operator-secret`, then `Bearer $AAT0` (staff AAT).

**Expect:** 401 `{ "error": "unauthorized" }` each time. An AAT is not an operator credential. `requireOperator` does not return 403.

**Do:** inspect D1 `installation` / `installation_key` / `entitlement` / `control_audit`.

**Expect:** still empty. Failed auth does not write.

#### 8.3.4 Validation failure paths

**Do:** as operator, send a non-JSON body:

```bash
curl -s -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d 'not-json'
```

**Expect:** HTTP 400, `{ "error": "invalid_json" }` (`parseJsonBody`). D1 still empty.

**Do:** as operator, send JSON that omits `kid` (or sets `"kid": ""`). Repeat once with `"kid"` present and `"org_id": ""` (any required field empty is enough).

```bash
curl -s -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"org_id\": \"$ORG_ID\",
    \"display_name\": \"Verify Clinic\",
    \"region\": \"local\",
    \"plan\": \"verify\",
    \"public_key\": \"$PUBLIC_KEY\",
    \"algorithm\": \"EdDSA\"
  }"
```

**Expect:** HTTP 400, `{ "error": "invalid_payload" }` (`validateEnrollPayload` / `requireNonEmptyString`). D1 still empty. `[]` or `null` JSON also yields `invalid_payload`.

#### 8.3.5 First enroll (happy path)

**Do:** copy **I0**, **K0**, and **X0** from Stage 2 — do not invent a platform id:

```bash
curl -s -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"org_id\": \"$ORG_ID\",
    \"display_name\": \"Verify Clinic\",
    \"region\": \"local\",
    \"plan\": \"verify\",
    \"public_key\": \"$PUBLIC_KEY\",
    \"algorithm\": \"EdDSA\",
    \"kid\": \"$KID\"
  }"
```

**Expect:** HTTP 200, body **exactly** `{ "platform_base_url": "http://127.0.0.1:8787" }` (the origin you posted to — `new URL(request.url).origin`). No token, no entitlement fields. This is the only success field in [§3](#success-response-200).

**Do:** inspect D1:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id, org_id, display_name, status, region, enrolled_at
   FROM installation WHERE installation_id = '$INSTALLATION_ID'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at
   FROM installation_key WHERE installation_id = '$INSTALLATION_ID'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id, plan, request_quota, token_budget, cost_budget,
          allowed_capabilities, soft_threshold, status, period_start, period_end
   FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT action, target, operator_id FROM control_audit ORDER BY recorded_at DESC LIMIT 5"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'control_operator'"
```

**Expect:**

- `installation`: `installation_id = I0`, `org_id = $ORG_ID`, `display_name = Verify Clinic`, `status = active`, `region = local`, `enrolled_at` ISO now.
- `installation_key`: exactly one row. `key_id = K0`, `public_key = X0`, `algorithm = EdDSA`, `valid_from = enrolled_at`, `revoked_at` NULL, `valid_until` ≈ `valid_from` + 365 days (`INSTALLATION_KEY_TTL_DAYS`).
- `entitlement`: exactly one row. `plan = verify`, `request_quota = 0`, `token_budget = 0`, `cost_budget = 0`, `allowed_capabilities = []`, `soft_threshold = 0`, `status = pending`, `period_start` and `period_end` equal `enrolled_at` (placeholders until Stage 4).
- `control_audit`: `action = enroll`, `target = I0`, `operator_id = platform-operator` (the env `OPERATOR_ID`, never the bearer secret).
- `control_operator`: no table. Single-operator secret; `control_audit` cannot distinguish operators.

**Do:** try a second entitlement row for **I0**:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT INTO entitlement (
     entitlement_id, installation_id, plan, period_start, period_end,
     request_quota, token_budget, cost_budget, allowed_capabilities,
     soft_threshold, status
   ) VALUES (
     '00000000-0000-0000-0000-000000000001', '$INSTALLATION_ID', 'verify',
     datetime('now'), datetime('now'), 0, 0, 0, '[]', 0, 'pending'
   )"
```

**Expect:** UNIQUE failure on `idx_entitlement_installation_id`. Still exactly one entitlement row. Enroll already 409s before this write on a second HTTP enroll ([§8.3.6](#836-re-enroll-already_enrolled)).

**Expect (R2):** enroll does not create R2 objects. This POST is D1-only ([§3](#d1-writes-atomic-batch) — **R2 writes:** none).

#### 8.3.6 Re-enroll already_enrolled

**Do:** repeat the **same** `POST …/enroll` (same `installation_id` and `org_id`).

**Expect:** HTTP 409, `{ "error": "already_enrolled" }`. D1 row counts for `installation`, `installation_key`, `entitlement` unchanged (still one each). Clinic `installation_keys` unchanged.

**Do:** new path id, **same** `org_id`:

```bash
NEW_INSTALLATION_ID="$(uuidgen)"
curl -s -D - -X POST "$GATEWAY/control/installations/$NEW_INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"org_id\": \"$ORG_ID\",
    \"display_name\": \"Verify Clinic 2\",
    \"region\": \"local\",
    \"plan\": \"verify\",
    \"public_key\": \"$PUBLIC_KEY\",
    \"algorithm\": \"EdDSA\",
    \"kid\": \"$(uuidgen)\"
  }"
```

**Expect:** HTTP 409, `{ "error": "already_enrolled" }` (`handleEnroll` SELECT `installation_id = ? OR org_id = ?`). No row for `$NEW_INSTALLATION_ID`. Dedup today is **installation_id or org_id** ([§3](#request-body--every-field)).

#### 8.3.7 Duplicate kid

**Do:** new `installation_id` **and** new `org_id`, but reuse **K0** (already in `installation_key.key_id`):

```bash
curl -s -D - -X POST "$GATEWAY/control/installations/$(uuidgen)/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"org_id\": \"$(uuidgen)\",
    \"display_name\": \"Other Clinic\",
    \"region\": \"local\",
    \"plan\": \"verify\",
    \"public_key\": \"$PUBLIC_KEY\",
    \"algorithm\": \"EdDSA\",
    \"kid\": \"$KID\"
  }"
```

**Expect:** HTTP 409, `{ "error": "duplicate_kid" }` (`runControlBatch` UNIQUE on `installation_key.key_id`). Still exactly one `installation` row (**I0**). The batch does not leave an orphan installation.

#### 8.3.8 Post-enroll effect and what this stage does not do

**Do:** as doctor, `SELECT public.get_ai_availability();`

**Expect:** still `{ "enrolled": false, "platform_base_url": null }`. Platform enroll does not write clinic Postgres. The 200 body’s `platform_base_url` is an echo for the caller to store later ([§3](#how-platform_base_url-reaches-flutter-summary)); Flutter does not learn the gateway from this HTTP response at runtime. There is still no `set_ai_availability` write RPC.

**Do:** `post_v1 "$AAT0"` — do **not** call `POST …/entitle`.

**Expect:** identity can pass (key is on the platform) but entitlement stage 3 fails: HTTP 403, `code = forbidden_capability` (path `ai_disabled` because `entitlement.status !== 'active'`). `installation.status = active` is not AI enabled. `allowed_capabilities` is `[]`; quotas are `0`. This stage does not entitle, does not insert `capability_grant` rows, does not mint AATs (`issue_ai_token` is clinic Stage 6), and does not reach routing/invoke.

**Do:** confirm D1 `capability_grant` is still empty and `ai_request` has no new journal row for that reject.

**Expect:** empty grants; guard rejection writes **no** `ai_request` row.

#### 8.3.9 Key rotation

Mint a **new** clinic key for the same **I0**. Do **not** enroll it with `POST …/enroll`.

**Do:** as owner or administrator:

```sql
SELECT public.enroll_installation_keypair();
```

**Expect:** `success = true`. New `kid` **K1** ≠ **K0**. Same `installation_id` **I0**. New `public_jwk.x` → **X1**. Save **K1** and **X1**. **AAT0** remains signed with **K0**.

**Do:** as operator:

```bash
curl -s -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/rotate" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"kid\": \"<K1>\",
    \"public_key\": \"<X1>\",
    \"algorithm\": \"EdDSA\"
  }"
```

**Expect:** HTTP 200, `{}`. Rotate shares `requireOperator` with enroll (a staff AAT here would 401 `unauthorized`).

**Do:** inspect keys:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT key_id, revoked_at IS NULL AS active, valid_from, valid_until
   FROM installation_key
   WHERE installation_id = '$INSTALLATION_ID'
   ORDER BY valid_from"
```

**Expect:** two rows. **K0** has `revoked_at` set (stamped in the same `runControlBatch` as the insert). **K1** has `revoked_at` NULL, `valid_until` ≈ `valid_from` + 365 days. `COUNT(*) WHERE installation_id = I0 AND revoked_at IS NULL` is **1**. There is no dual-key overlap. Entitlement is still `pending` / zero quota — rotate does not entitle.

The isolate `ConfigCache` TTL is 30 s. If [§8.3.8](#838-post-enroll-effect-and-what-this-stage-does-not-do) already loaded **K0**, restart `npm run dev` (or wait 30 s) so the next `/v1/requests` reads D1 `revoked_at`, not a warm copy.

**Do:** `post_v1 "$AAT0"` (old `kid`).

**Expect:** HTTP 401, `code = unauthenticated`. In-flight AATs signed with the old `kid` fail identity as soon as rotate is visible to identity ([§7](#7-key-rotation)). Revoked keys are rejected regardless of `exp`.

**Do:** as doctor, `SELECT public.issue_ai_token();` Save as **AAT1**. Header `kid` should be **K1**. `post_v1 "$AAT1"`.

**Expect:** identity can pass (new specimen is on file) but entitlement still fails `forbidden_capability` / `ai_disabled`. Operators mint new AATs with the new `kid`; this stage still does not grant spend rights.
