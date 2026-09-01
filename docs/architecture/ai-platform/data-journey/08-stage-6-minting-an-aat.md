# AI Platform Data Journey — Stage 6 — Minting an AAT (clinic-side)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [API: `public.issue_ai_token()`](#3-api-publicissue_ai_token)
4. [JWS structure](#4-jws-structure)
   - [Header — every field](#header-every-field)
   - [Payload — every claim](#payload-every-claim)
   - [Clinic DB write (`ai_internal.ai_token_issuance`)](#clinic-db-write-ai_internalai_token_issuance)
5. [Mint failure codes](#5-mint-failure-codes)
6. [Platform verification summary](#6-platform-verification-summary)
7. [Behavioral verification](#7-behavioral-verification)
   - [7.1 Setup](#71-setup)
   - [7.2 Coverage](#72-coverage)
   - [7.3 Ordered probes](#73-ordered-probes)
     - [7.3.1 Reset to a known clinic state](#731-reset-to-a-known-clinic-state)
     - [7.3.2 Before any key exists](#732-before-any-key-exists)
     - [7.3.3 Who may not call](#733-who-may-not-call)
     - [7.3.4 Stage 2 keypair prerequisite](#734-stage-2-keypair-prerequisite)
     - [7.3.5 Caller gates after a key exists](#735-caller-gates-after-a-key-exists)
     - [7.3.6 First mint (happy path)](#736-first-mint-happy-path)
     - [7.3.7 Issuance row and clients cannot read ai_internal](#737-issuance-row-and-clients-cannot-read-ai_internal)
     - [7.3.8 Reuse mint, ignored scopes, omitted claims](#738-reuse-mint-ignored-scopes-omitted-claims)
     - [7.3.9 RATE_LIMITED](#739-rate_limited)
     - [7.3.10 Platform does not know the clinic yet](#7310-platform-does-not-know-the-clinic-yet)
     - [7.3.11 Identity accepts a valid AAT after enroll](#7311-identity-accepts-a-valid-aat-after-enroll)
     - [7.3.12 Platform rejects oversized lifetime, bad ver, other alg](#7312-platform-rejects-oversized-lifetime-bad-ver-other-alg)
     - [7.3.13 What this stage does not do](#7313-what-this-stage-does-not-do)

---




## 1. Plain language

A staff member with AI permissions requests a short-lived signed token. Supabase signs it with the clinic private key. The platform never sees the private key — only verifies with the enrolled public key. The issuer MUST mint minutes-scale lifetime (`exp = iat + lifetime_minutes * 60`). The platform independently rejects any token whose `exp − iat` exceeds 600 seconds (`MAX_AAT_LIFETIME_SECONDS`).

## 2. Metaphor

A **boarding pass** — short-lived, tied to one passenger (staff), one airline (installation), stamped with the clinic's key.

## 3. API: `public.issue_ai_token()`

**Auth:** Authenticated staff session with `ai.`* RBAC permissions.

**Request:** No client-supplied scopes (ignored if present).

## 4. JWS structure

```
<base64url(header)>.<base64url(payload)>.<base64url(signature)>
```



#### Header — every field


| Field | Value   | Meaning                                     |
| ----- | ------- | ------------------------------------------- |
| `alg` | `EdDSA` | Mandatory — other algorithms rejected       |
| `kid` | string  | Selects `installation_keys` row for signing |




#### Payload — every claim


| Claim    | Type     | Source at mint                            | Platform Principal field              | Meaning                                                                 |
| -------- | -------- | ----------------------------------------- | ------------------------------------- | ----------------------------------------------------------------------- |
| `iss`    | string   | `installation_id` of signing key          | `installationId`                      | Issuer — which enrolled clinic installation signed this token           |
| `aud`    | string   | `ai.aat.audience` (default `ai-platform`) | Must match verifier audience          | Audience — intended recipient; only the AI platform should accept it    |
| `sub`    | string   | `staff_members.id`                        | `actorId`                             | Subject — the staff member acting on behalf of the clinic             |
| `org`    | string   | Staff `organization_id`                   | `organizationId`                      | Organization — the clinic tenant the staff member belongs to            |
| `branch` | string   | Primary active branch                     | `branchId`                            | Branch — the staff member's primary active branch for this session      |
| `role`   | string   | `staff_members.role`                      | `role`                                | Role — the staff member's job role (e.g. doctor, admin)                 |
| `scopes` | string[] | RBAC `ai.*` permissions                   | `scopes`                              | Scopes — which AI permissions this token grants (from RBAC `ai.*`)      |
| `jti`    | string   | `gen_random_uuid()`                       | `jti` — replay protection in Quota DO | JWT ID — unique id for audit trail and one-time-use replay protection   |
| `iat`    | number   | Unix seconds now                          | `iat`                                 | Issued at — when the token was minted (Unix timestamp in seconds)       |
| `exp`    | number   | `iat + lifetime_minutes * 60`             | `exp`                                 | Expires at — Unix timestamp. Issuer mints short-lived (minutes). Platform rejects `exp − iat > 600` (`MAX_AAT_LIFETIME_SECONDS`) as `unauthenticated`. |
| `ver`    | string   | `ai.aat.ver` (default `1`)                | `ver` → token_contract lookup         | Version — token contract version; selects validation rules on platform  |


**Deliberately omitted:** patient ids, quotas, provider hints.

#### Clinic DB write (`ai_internal.ai_token_issuance`)

One row per `jti` for audit.

## 5. Mint failure codes


| Code                        | Trigger                       |
| --------------------------- | ----------------------------- |
| `INSTALLATION_NOT_ENROLLED` | No keypair in clinic DB       |
| `AI_ACCESS_DENIED`          | Staff lacks `ai.*` permission |
| `BRANCH_NOT_FOUND`          | No primary branch             |
| `RATE_LIMITED`              | Issuance rate limit           |




## 6. Platform verification summary

The issuer mints a short-lived AAT. Independently, `EnrolledKeyVerifier` rejects `exp − iat > 600` (`MAX_AAT_LIFETIME_SECONDS`) as `unauthenticated` in the cheap claim-check region before any D1 or config-cache load.

See [§5 Stage 2 — Identity](11-stage-9-the-guard.md#5-stage-2-identity) for every check and failure.

## 7. Behavioral verification

Live probes against a running clinic Supabase (and a local Worker from [§7.3.10](#7310-platform-does-not-know-the-clinic-yet) onward). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§7.3](#73-ordered-probes) top to bottom** on a throwaway local clinic. If every probe matches, this stage is working.

`public.issue_ai_token()` returns **`text`** (the compact JWS). Failures are bare `RAISE EXCEPTION '<CODE>'` (`P0001`); `SQLERRM` is the code string. There is no `rpc_result` envelope — unlike `enroll_installation_keypair`. Any authenticated staff session whose role has at least one granted `ai.*` permission may mint. Seed `ai.aat.lifetime_minutes` is **15** (900 s). Independently, `EnrolledKeyVerifier` rejects `exp − iat > 600`. Do not dump the rest of the Stage 9 guard matrix here.

### 7.1 Setup

- Local clinic Supabase with migrations applied. Prefer a database you can wipe; several probes delete keystore and issuance rows, and enroll the local Worker.
- Keep **one** active `installation_keys` row after [§7.3.4](#734-stage-2-keypair-prerequisite). Extra kids make the issuer sign the latest key, which will not match a platform enroll of the first `kid`.
- Authenticated sessions (look up `auth_user_id` from `staff_members`). Every minting actor needs at least one active branch assignment — the issuer reads `staff_branch_assignments`, not the JWT `branch_ids` claim.
  - **Owner** — `is_bootstrap_admin = true` (has seed `ai.access`)
  - **Administrator** — `role = 'administrator'` and a different `auth_user_id` than the owner (create one if needed; grant a primary branch)
  - **Doctor** — `role = 'doctor'` with seed `ai.access` and a primary active branch
  - **Receptionist** (staff without `ai.*`) — `role = 'receptionist'` with a branch assignment; seed has no `ai.*` grants
- SQL as `postgres` only to inspect `ai_internal`, reset rows, lower the issuer ceiling, and create a no-branch staff row.
- Local Worker (`npm run dev`) with `OPERATOR_BEARER_TOKEN` from [§7.3.10](#7310-platform-does-not-know-the-clinic-yet). Clinic `organizations.id` for the enroll body.
- PostgREST origin (local Supabase API, typically `http://127.0.0.1:54321`) for the `anon` probe.

Call RPCs as the named session: PostgREST `POST /rest/v1/rpc/<name>` with that user’s Bearer token, or SQL while that session is active:

```sql
SELECT set_config('role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  json_build_object('sub', '<auth_user_id>'::text, 'role', 'authenticated')::text,
  true
);
```

Reset `role` to `postgres` before inspecting `ai_internal`.

This RPC does not return `rpc_result`. Capture mint failures as `SQLERRM` (psql prints `ERROR:  <CODE>`). PostgREST JSON `message` is that same string, `code` is `P0001`.

Decode a compact JWS (header = first segment, payload = second):

```sql
SELECT convert_from(
  decode(
    rpad(
      translate(split_part('<token>', '.', 1), '-_', '+/'),
      length(split_part('<token>', '.', 1))
        + ((4 - length(split_part('<token>', '.', 1)) % 4) % 4),
      '='
    ),
    'base64'
  ),
  'utf8'
)::jsonb AS header;
-- Repeat with split_part(..., '.', 2) for the payload.
```

Shell helpers from [§7.3.10](#7310-platform-does-not-know-the-clinic-yet):

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export ORG_ID='<clinic organizations.id>'

get_cap() {
  local aat="$1"
  curl -s -D - "$GATEWAY/v1/capabilities" \
    -H "Authorization: Bearer $aat"
}

post_v1() {
  local aat="$1"
  curl -s -D - -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $aat" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $(uuidgen)" \
    -H "x-capability-version: 1.0.0" \
    -d '{"capability_id":"clinic.visit_summary","user_intent":"probe mint","context":{}}'
}
```

`GET /v1/capabilities` is the identity-only probe (Bearer AAT, no extra headers). `POST /v1/requests` is the Stage 8 handoff and needs those adapter headers so the call reaches the guard.

### 7.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| `issue_ai_token` before any key → `INSTALLATION_NOT_ENROLLED` | [§7.3.2](#732-before-any-key-exists) |
| `anon` cannot call; `GRANT EXECUTE` is to `authenticated` only | [§7.3.3](#733-who-may-not-call) |
| AI platform has no inbound path to this RPC | [§7.3.3](#733-who-may-not-call) |
| Stage 2 keypair is a prerequisite; enroll returns public JWK only | [§7.3.4](#734-stage-2-keypair-prerequisite) |
| Staff without `ai.*` (receptionist) → `AI_ACCESS_DENIED` | [§7.3.5](#735-caller-gates-after-a-key-exists) |
| No primary/active branch → `BRANCH_NOT_FOUND` | [§7.3.5](#735-caller-gates-after-a-key-exists) |
| Owner (bootstrap admin) and administrator with `ai.*` may mint | [§7.3.5](#735-caller-gates-after-a-key-exists) |
| Doctor (authenticated staff with `ai.*`) may mint | [§7.3.6](#736-first-mint-happy-path) |
| Compact JWS `header.payload.signature`; private key absent from the response | [§7.3.6](#736-first-mint-happy-path) |
| Header `alg = EdDSA`, `kid` selects the latest active `installation_keys` row | [§7.3.6](#736-first-mint-happy-path) |
| Every [§4](#4-jws-structure) payload claim (`iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`) | [§7.3.6](#736-first-mint-happy-path) |
| `exp = iat + lifetime_minutes * 60` (seed 15 minutes) | [§7.3.6](#736-first-mint-happy-path) |
| `scopes` from RBAC `ai.*`; client-supplied `p_scopes` ignored | [§7.3.6](#736-first-mint-happy-path), [§7.3.8](#738-reuse-mint-ignored-scopes-omitted-claims) |
| Deliberately omitted: patient ids, quotas, provider hints | [§7.3.8](#738-reuse-mint-ignored-scopes-omitted-claims) |
| One `ai_token_issuance` row per `jti`; clients cannot `SELECT` `ai_internal` | [§7.3.7](#737-issuance-row-and-clients-cannot-read-ai_internal) |
| Reuse mint: new `jti`, second ledger row, same `iss` / `kid` / `sub` | [§7.3.8](#738-reuse-mint-ignored-scopes-omitted-claims) |
| Issuance rate limit → `RATE_LIMITED`; a different actor can still mint | [§7.3.9](#739-rate_limited) |
| Clinic mint does not register D1; identity fails until Stage 3 enroll | [§7.3.10](#7310-platform-does-not-know-the-clinic-yet) |
| Platform never receives the private key; D1 stores `public_key` only | [§7.3.11](#7311-identity-accepts-a-valid-aat-after-enroll) |
| Identity accepts a valid AAT after enroll when `exp − iat ≤ 600` | [§7.3.11](#7311-identity-accepts-a-valid-aat-after-enroll) |
| Stage 8 uses the AAT; pending entitlement still `forbidden_capability` / `ai_disabled` | [§7.3.11](#7311-identity-accepts-a-valid-aat-after-enroll), [§7.3.13](#7313-what-this-stage-does-not-do) |
| `EnrolledKeyVerifier` rejects `exp − iat > 600` (`MAX_AAT_LIFETIME_SECONDS`) as `unauthenticated` | [§7.3.12](#7312-platform-rejects-oversized-lifetime-bad-ver-other-alg) |
| Payload `ver` → `token_contract` lookup; unknown `ver` → `unauthenticated` | [§7.3.12](#7312-platform-rejects-oversized-lifetime-bad-ver-other-alg) |
| Header `alg` other than `EdDSA` → `unauthenticated` | [§7.3.12](#7312-platform-rejects-oversized-lifetime-bad-ver-other-alg) |
| Payload `aud` must match verifier audience (`ai-platform`) | [§7.3.6](#736-first-mint-happy-path), [§7.3.12](#7312-platform-rejects-oversized-lifetime-bad-ver-other-alg) |
| Mint does not entitle, does not write D1, does not set `ai.availability` | [§7.3.13](#7313-what-this-stage-does-not-do) |
| Cheap claim-check **before** any D1 / config-cache load ([§6](#6-platform-verification-summary) sequencing) | Unprobeable via HTTP — `401 unauthenticated` is the same whether the 600 s check or a later D1 miss fired |
| `jti` replay protection in Quota DO ([§4](#payload-every-claim)) | Unprobeable here — admission is guard stage 8 and needs Stage 4 entitle |
| Every other Stage 9 identity row | Cross-ref only — [§5 in Stage 9](11-stage-9-the-guard.md#5-stage-2-identity); not this file’s checklist |


### 7.3 Ordered probes

#### 7.3.1 Reset to a known clinic state

**Do:** as `postgres` on the throwaway local database:

```sql
DELETE FROM ai_internal.ai_token_issuance;
DELETE FROM ai_internal.installation_keys;

UPDATE ai_internal.app_settings
SET value_json = '15'::jsonb
WHERE key = 'ai.aat.lifetime_minutes';

UPDATE ai_internal.app_settings
SET value_json = '"ai-platform"'::jsonb
WHERE key = 'ai.aat.audience';

UPDATE ai_internal.app_settings
SET value_json = '"1"'::jsonb
WHERE key = 'ai.aat.ver';

UPDATE ai_internal.app_settings
SET value_json = '100'::jsonb
WHERE key = 'ai.issuer.rate_limit.ceiling';

UPDATE ai_internal.app_settings
SET value_json = '3600'::jsonb
WHERE key = 'ai.issuer.rate_limit.window_seconds';
```

**Expect:** `installation_keys` and `ai_token_issuance` are empty. Lifetime, audience, `ver`, and issuer ceiling are the seed defaults.

#### 7.3.2 Before any key exists

**Do:** as **doctor** (or any staff with `ai.*` and a branch), `SELECT public.issue_ai_token();`

**Expect:** exception, `SQLERRM = 'INSTALLATION_NOT_ENROLLED'` (`P0001`). PostgREST `message` is that same string. No JWS. As `postgres`, `ai_token_issuance` is still empty. This stage’s keypair is a prerequisite ([§5](#5-mint-failure-codes)).

#### 7.3.3 Who may not call

**Do:** as `anon` (no JWT), `POST /rest/v1/rpc/issue_ai_token`.

**Expect:** PostgREST 401 / permission denied. `GRANT EXECUTE` is to `authenticated` only.

**Do:** from the local Worker, try to reach clinic `issue_ai_token` (there is no Worker route, binding, or Hyperdrive to clinic Postgres).

**Expect:** nothing to call. The AI platform has no inbound path to this RPC. Staff mint on clinic Supabase; the Worker only verifies the resulting JWS.

#### 7.3.4 Stage 2 keypair prerequisite

**Do:** as **owner** (`is_bootstrap_admin`), with `installation_keys` still empty:

```sql
SELECT public.enroll_installation_keypair();
```

**Expect:** `success = true`. Save `kid` **K0**, `installation_id` **I0**, `public_jwk.x` **X0**. `data` has **no** `secret_key`. This is Stage 2; `issue_ai_token` still has not run. Leave this the only active key.

#### 7.3.5 Caller gates after a key exists

**Do:** as **receptionist** (branch assigned, seed has no `ai.*`):

```sql
SELECT public.issue_ai_token();
```

**Expect:** `SQLERRM = 'AI_ACCESS_DENIED'`. As `postgres`, no new `ai_token_issuance` row. Authenticated staff without `ai.*` may not mint ([§3](#3-api-publicissue_ai_token), [§5](#5-mint-failure-codes)).

**Do:** as `postgres`, insert a throwaway **doctor** (`ai.access` via seed) with **no** `staff_branch_assignments` row. Impersonate that user and `SELECT public.issue_ai_token();`

**Expect:** `SQLERRM = 'BRANCH_NOT_FOUND'`. No issuance row for that actor. Restore `role` to `postgres`. Leave the real doctor’s assignments untouched.

**Do:** as **administrator** (with `ai.*` and a branch):

```sql
SELECT public.issue_ai_token();
```

**Expect:** a compact JWS (three `.` segments). Administrator is an allowed caller. Do **not** save this token as the happy-path AAT — [§7.3.6](#736-first-mint-happy-path) mints the doctor token used later. Delete this administrator issuance row as `postgres` if you want a clean ledger count, or just remember it when counting rows in [§7.3.7](#737-issuance-row-and-clients-cannot-read-ai_internal).

**Do:** as **owner** (`is_bootstrap_admin`, seed `ai.access`, with a branch), `SELECT public.issue_ai_token();`

**Expect:** a compact JWS. Owner and administrator are allowed callers the same way doctor is — this RPC is not admin-gated. Delete that issuance row too if you want a clean doctor-only count in [§7.3.7](#737-issuance-row-and-clients-cannot-read-ai_internal).

#### 7.3.6 First mint (happy path)

Look up the doctor’s `staff_members.id`, primary active branch, org, and granted `ai.*` keys (you will match these on the payload):

```sql
SELECT sm.id, sm.role
FROM public.staff_members sm
WHERE sm.auth_user_id = '<doctor auth_user_id>'
  AND sm.is_deleted = false;

SELECT b.id
FROM public.staff_branch_assignments sba
JOIN public.branches b ON b.id = sba.branch_id
WHERE sba.staff_member_id = '<doctor staff id>'
  AND sba.is_deleted = false
  AND b.is_deleted = false
  AND b.is_active = true
ORDER BY sba.is_primary DESC, b.name
LIMIT 1;

SELECT o.id
FROM public.organizations o
WHERE o.is_deleted = false
ORDER BY o.created_at
LIMIT 1;

SELECT permission_key
FROM public.roles_permissions
WHERE role = 'doctor'
  AND permission_key LIKE 'ai.%'
  AND is_granted = true
  AND is_deleted = false
ORDER BY permission_key;

SELECT kid FROM ai_internal.installation_keys
WHERE is_deleted = false AND revoked_at IS NULL
ORDER BY valid_from DESC, kid DESC
LIMIT 1;
```

**Do:** as **doctor**:

```sql
SELECT public.issue_ai_token();
```

**Expect:** a compact JWS. Save it as **AAT0**. Decode header and payload. Response is **text**, not a JSON object — **no** `secret_key`, and no other private material.

Header ([§4](#header-every-field)):

- `alg = "EdDSA"`
- `kid = K0` (the only active key; the issuer picks the latest active row)

Payload — **every** claim in [§4](#payload-every-claim):

- `iss = I0` (`installation_id` of the signing key)
- `aud = "ai-platform"` (`ai.aat.audience` seed)
- `sub` = doctor `staff_members.id`
- `org` = that organization id
- `branch` = that primary active branch id
- `role = "doctor"`
- `scopes` = the doctor `ai.*` array (seed is `["ai.access"]`)
- `jti` = UUID text
- `iat` = Unix seconds now
- `exp = iat + 900` (seed `lifetime_minutes = 15`)
- `ver = "1"` (`ai.aat.ver` seed)

Three base64url segments. This is the first mint. Call this payload `jti` **J0**.

#### 7.3.7 Issuance row and clients cannot read ai_internal

**Do:** as `postgres`:

```sql
SELECT
  installation_id::text,
  jti::text,
  actor_staff_id::text,
  extract(epoch FROM iat)::bigint AS iat_epoch,
  created_by
FROM ai_internal.ai_token_issuance
WHERE jti = '<J0>'::uuid
  AND is_deleted = false;
```

**Expect:** exactly one row. `installation_id = I0`, `jti = J0`, `actor_staff_id` = doctor `staff_members.id`, `iat_epoch` equals payload `iat`, `created_by` equals the doctor’s `auth_user_id`. One row per `jti` for audit ([§4](#clinic-db-write-ai_internalai_token_issuance)).

**Do:** as the same authenticated doctor, `SELECT * FROM ai_internal.ai_token_issuance;` and `SELECT * FROM ai_internal.installation_keys;`

**Expect:** denied (no schema `USAGE` / RLS deny-all). Clients cannot read the ledger or the stamp. Reset `role` to `postgres`.

#### 7.3.8 Reuse mint, ignored scopes, omitted claims

**Do:** as **doctor**, `SELECT public.issue_ai_token();` Save as **AAT1**. Decode.

**Expect:** a new compact JWS. Payload `jti` **J1** ≠ **J0**. `iss`, `kid`, `sub`, `org`, `branch`, `role` still match [§7.3.6](#736-first-mint-happy-path). As `postgres`, two issuance rows for this doctor (`J0` and `J1`). Reuse is allowed; each mint is a new boarding pass.

**Do:** as doctor:

```sql
SELECT public.issue_ai_token(p_scopes := ARRAY['ai.forge']);
```

**Expect:** a JWS whose `scopes` still equal the RBAC `ai.*` list from [§7.3.6](#736-first-mint-happy-path) and do **not** contain `ai.forge`. Client-supplied scopes are ignored ([§3](#3-api-publicissue_ai_token)). Payload has **no** `patient_id` / `patient`, **no** `quota`, **no** `provider` (or `provider_hint` / `model`). Deliberate omissions from [§4](#payload-every-claim).

#### 7.3.9 RATE_LIMITED

**Do:** as `postgres`:

```sql
DELETE FROM ai_internal.ai_token_issuance;

UPDATE ai_internal.app_settings
SET value_json = '2'::jsonb
WHERE key = 'ai.issuer.rate_limit.ceiling';
```

Then as **doctor**, mint twice (`SELECT public.issue_ai_token();` × 2). Both succeed. Third call: `SELECT public.issue_ai_token();`

**Expect:** third call `SQLERRM = 'RATE_LIMITED'`. Two issuance rows for the doctor.

**Do:** as **administrator** (different `staff_members.id`), `SELECT public.issue_ai_token();`

**Expect:** a JWS. The ceiling is per actor. Then as `postgres` restore the seed:

```sql
UPDATE ai_internal.app_settings
SET value_json = '100'::jsonb
WHERE key = 'ai.issuer.rate_limit.ceiling';

DELETE FROM ai_internal.ai_token_issuance;
```

**AAT0** remains a valid compact JWS until its `exp` — deleting the ledger does not un-sign it. Remint **AAT0** as doctor if you wiped it from memory; you need a **15-minute** token (`lifetime_minutes` still 15) for [§7.3.12](#7312-platform-rejects-oversized-lifetime-bad-ver-other-alg). Save that remint as **AAT0**.

#### 7.3.10 Platform does not know the clinic yet

Do **not** call Stage 3 yet. Local Worker up. Export `GATEWAY` / `OPERATOR_BEARER_TOKEN` / `ORG_ID` as in [§7.1](#71-setup).

**Do:** inspect local D1 for **I0**:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id FROM installation WHERE installation_id = '<I0>'"
```

**Expect:** no row. Minting an AAT does not register the installation.

**Do:** `get_cap "$AAT0"` (and `post_v1 "$AAT0"` if you want the Stage 8 shape).

**Expect:** HTTP 401, `code = unauthenticated`. Same as [Stage 2 §8.3.8](04-stage-2-clinic-keypair-enrollment.md#838-platform-does-not-know-the-clinic-yet): the border guard has no file for this passport.

#### 7.3.11 Identity accepts a valid AAT after enroll

**Do:** copy **I0**, **K0**, and **X0** from [§7.3.4](#734-stage-2-keypair-prerequisite) (do not invent a platform id):

```bash
export INSTALLATION_ID='<I0>'
export KID='<K0>'
export PUBLIC_KEY='<X0>'

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

**Expect:** HTTP 200, `{ "platform_base_url": "http://127.0.0.1:8787" }`. D1 `installation.installation_id = I0`, `installation_key.key_id = K0`, `installation_key.public_key = X0`. There is **no** secret-key column — the platform verifies with the enrolled public key only ([§1](#1-plain-language)). Entitlement stays `pending` / quotas `0`.

**Do:** as `postgres`, set a platform-acceptable lifetime, then remint as **doctor**:

```sql
UPDATE ai_internal.app_settings
SET value_json = '10'::jsonb
WHERE key = 'ai.aat.lifetime_minutes';
```

```sql
SELECT public.issue_ai_token();
```

Save as **AAT2**. Decode: `exp − iat = 600`. Header `kid = K0`, payload `iss = I0`, `ver = "1"`.

**Do:** `get_cap "$AAT2"`. Then `post_v1 "$AAT2"` (do **not** entitle).

**Expect:** `GET /v1/capabilities` is **not** `401 unauthenticated` — identity accepted the AAT (discovery may be an empty list while entitlement is pending). `POST /v1/requests` is HTTP 403, `code = forbidden_capability` (path `ai_disabled`) — Stage 8 consumed the Bearer AAT; Stage 4 has not granted spend rights. This is [§6](#6-platform-verification-summary) as far as identity is concerned, not the rest of the guard.

#### 7.3.12 Platform rejects oversized lifetime, bad ver, other alg

**Do:** `get_cap "$AAT0"` — the **15-minute** token from [§7.3.6](#736-first-mint-happy-path) / remint in [§7.3.9](#739-rate_limited). Installation **I0** is already on the platform. `AAT0` is still unexpired (`exp − iat = 900`).

**Expect:** HTTP 401, `code = unauthenticated`. `EnrolledKeyVerifier` rejects `exp − iat > 600` (`MAX_AAT_LIFETIME_SECONDS`) independently of the issuer ([§1](#1-plain-language), [§6](#6-platform-verification-summary)). Contrast [§7.3.11](#7311-identity-accepts-a-valid-aat-after-enroll): the same installation accepts **AAT2** (`exp − iat = 600`).

**Do:** as `postgres`, `UPDATE ai_internal.app_settings SET value_json = '"99"'::jsonb WHERE key = 'ai.aat.ver';` then as doctor `SELECT public.issue_ai_token();` Save as **AAT3**. Decode `ver = "99"` and `exp − iat = 600`. `get_cap "$AAT3"`. Restore `ver` to `"1"` afterwards.

**Expect:** HTTP 401, `code = unauthenticated`. Payload `ver` selects `token_contract`; `99` is missing ([§4](#payload-every-claim)). Restart `npm run dev` (or wait 30 s) if a warm isolate cached `token_contracts:99` as a miss — the reject is still `unauthenticated`.

**Do:** `get_cap` with a three-segment compact JWS whose header is `{"alg":"HS256","kid":"K0"}` (any payload/signature; do not use `EdDSA`).

**Expect:** HTTP 401, `code = unauthenticated`. Header `alg` is mandatory `EdDSA` — other algorithms are rejected ([§4](#header-every-field)).

**Do:** as `postgres`, `UPDATE ai_internal.app_settings SET value_json = '"other"'::jsonb WHERE key = 'ai.aat.audience';` then as doctor mint **AAT4**. Decode `aud = "other"` and `exp − iat = 600`. `get_cap "$AAT4"`. Restore audience to `"ai-platform"`.

**Expect:** HTTP 401, `code = unauthenticated`. Payload `aud` must match the verifier audience `ai-platform` ([§4](#payload-every-claim)).

#### 7.3.13 What this stage does not do

**Do:** as `postgres`, mint once more as doctor, then inspect D1 `installation` / `installation_key` / `entitlement` / `capability_grant` / `ai_request` counts for **I0**.

**Expect:** D1 row counts unchanged by `issue_ai_token`. Minting does not enroll, entitle, grant capabilities, or journal a request. Clinic `get_ai_availability()` is still whatever it was (this RPC does not touch `ai.availability`).

**Do:** `post_v1 "$AAT2"` again without Stage 4 entitle.

**Expect:** still `forbidden_capability` / `ai_disabled`. This stage mints the boarding pass; it does not open the gate, grant quotas, or put patient ids / quotas / provider hints on the token ([§4](#payload-every-claim)). Stage 8/9 **use** the AAT as `Authorization: Bearer`. Restore seed lifetime when finished:

```sql
UPDATE ai_internal.app_settings
SET value_json = '15'::jsonb
WHERE key = 'ai.aat.lifetime_minutes';
```

