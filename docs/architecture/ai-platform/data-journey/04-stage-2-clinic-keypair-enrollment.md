# AI Platform Data Journey — Stage 2 — Clinic keypair enrollment (Supabase)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [API: `public.enroll_installation_keypair()`](#3-api-publicenroll_installation_keypair)
4. [Clinic availability flag (manual step)](#4-clinic-availability-flag-manual-step)
5. [Failure paths](#5-failure-paths)
6. [Happy path](#6-happy-path)
7. [Who calls this RPC and how the platform learns `installation_id`](#7-who-calls-this-rpc-and-how-the-platform-learns-installation_id)
   - [7.1 Caller](#71-caller)
   - [7.2 End-to-end flow (intended production)](#72-end-to-end-flow-intended-production)
   - [7.3 How the platform learns `installation_id`](#73-how-the-platform-learns-installation_id)
   - [7.4 Duplicate `installation_id` across clinics](#74-duplicate-installation_id-across-clinics)
   - [7.5 What this stage does not do](#75-what-this-stage-does-not-do)
8. [Behavioral verification](#8-behavioral-verification)
   - [8.1 Setup](#81-setup)
   - [8.2 Coverage](#82-coverage)
   - [8.3 Ordered probes](#83-ordered-probes)
     - [8.3.1 Reset to a known clinic state](#831-reset-to-a-known-clinic-state)
     - [8.3.2 Before any key exists](#832-before-any-key-exists)
     - [8.3.3 Enroll failure paths](#833-enroll-failure-paths)
     - [8.3.4 First enroll (happy path)](#834-first-enroll-happy-path)
     - [8.3.5 Administrator enroll and `installation_id` reuse (happy path)](#835-administrator-enroll-and-installation_id-reuse-happy-path)
     - [8.3.6 Single-installation trigger (failure path)](#836-single-installation-trigger-failure-path)
     - [8.3.7 Mint an AAT from this key (happy path for the handoff fields)](#837-mint-an-aat-from-this-key-happy-path-for-the-handoff-fields)
     - [8.3.8 Platform does not know the clinic yet](#838-platform-does-not-know-the-clinic-yet)
     - [8.3.9 Stage 3 enroll using this RPC’s output (happy path §6)](#839-stage-3-enroll-using-this-rpcs-output-happy-path-6)
     - [8.3.10 Availability flag after the key exists](#8310-availability-flag-after-the-key-exists)

---




## 1. Plain language

The clinic generates an Ed25519 keypair **inside Supabase**. The private key never leaves the clinic database. The public key and `kid` are later copied to the platform enroll call.

## 2. Metaphor

The clinic prints its own **signing stamp** (private key) and sends a **stamp specimen** (public key) to the platform passport office.

## 3. API: `public.enroll_installation_keypair()`


| Item         | Value                       |
| ------------ | --------------------------- |
| Method       | RPC (PostgREST)             |
| Auth         | Authenticated admin session |
| Request body | **None**                    |


**Success** `data` **object — every field:**


| Field             | Type   | Origin                                                 | Meaning                                                                                                                                                                          |
| ----------------- | ------ | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kid`             | string | `gen_random_uuid()::text`                              | **Key ID** (standard JWS/JWK `kid` header). Names one row in `ai_internal.installation_keys`; copied to AAT header `kid` and platform `installation_key.key_id`. See note below. |
| `installation_id` | string | Existing key's installation or new `gen_random_uuid()` | Platform installation id; becomes AAT `iss`                                                                                                                                      |
| `public_jwk.kty`  | string | `"OKP"`                                                | JWK key type                                                                                                                                                                     |
| `public_jwk.crv`  | string | `"Ed25519"`                                            | Curve                                                                                                                                                                            |
| `public_jwk.x`    | string | base64url(raw 32-byte public key)                      | **This becomes platform enroll** `public_key`                                                                                                                                    |
| `public_jwk.kid`  | string | Same as top-level `kid`                                | JWK kid mirror                                                                                                                                                                   |


**About** `kid`**:** `installation_id` identifies *which clinic*; `kid` identifies *which signing key* for that
clinic. Steady state is one active key. Clinic keystore rotation mints a new `kid`; platform
`POST …/rotate` then **immediately** stamps `revoked_at` on prior D1 keys in the same batch as the
new-key insert ([§7 in Stage 3](05-stage-3-platform-installation-enrollment.md#7-key-rotation)).
In-flight AATs signed with the old `kid` fail identity as soon as rotate returns — there is no
platform dual-key overlap. Operators mint new AATs with the new `kid`. The platform selects the
public key by AAT header `kid` (with payload `iss`). Revoked keys are rejected regardless of `exp`.

**Postgres writes (**`ai_internal.installation_keys`**):**


| Column                                   | Value                                                  |
| ---------------------------------------- | ------------------------------------------------------ |
| `kid`                                    | New UUID text                                          |
| `installation_id`                        | As above                                               |
| `public_key`                             | bytea (raw public bytes)                               |
| `secret_key`                             | bytea (raw private bytes) — **never sent to platform** |
| `algorithm`                              | `EdDSA`                                                |
| `valid_from`                             | `clock_timestamp()`                                    |
| `created_at`, `created_by`, `updated_by` | Audit columns                                          |




## 4. Clinic availability flag (manual step)

**Table:** `ai_internal.app_settings` key `ai.availability`


| Field               | Default | Set by                        |
| ------------------- | ------- | ----------------------------- |
| `enrolled`          | `false` | See **Who writes this** below |
| `platform_base_url` | `null`  | See **Who writes this** below |


**Read RPC:** `public.get_ai_availability()` returns the same JSON (any authenticated staff session).
Flutter calls this to decide whether to show AI UI — it **never** probes the AI platform to discover
enrollment.

**Who writes this:**


| Actor                                                 | Writes?                 | When                                                                                                                                                                               |
| ----------------------------------------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Migration (`20260802140000_ai_availability_flag.sql`) | **Yes** — seed only     | Clinic Supabase first deploy; default `{ enrolled: false, platform_base_url: null }`                                                                                               |
| AI platform (Stage 3 enroll)                          | **No**                  | Enroll returns `platform_base_url` in the HTTP response only; D1 is updated, not clinic Postgres                                                                                   |
| `enroll_installation_keypair` ([§3](#3-api-publicenroll_installation_keypair))                  | **No**                  | Keypair RPC does not touch `app_settings`                                                                                                                                          |
| Flutter (intended production)                         | **Yes** — not built yet | After successful platform enroll ([§7.2 step 4](#72-end-to-end-flow-intended-production)): owner/admin flow sets `enrolled: true` and stores `platform_base_url` from the enroll response                                     |
| Vendor onboarding (today)                             | **Yes**                 | Manual `UPDATE ai_internal.app_settings … WHERE key = 'ai.availability'` until Flutter writes it ([04-ai-platform-operator-runbook.md §5.3](../04-ai-platform-operator-runbook.md#53-clinic-flip-availability)) |


There is **no** `set_ai_availability` write RPC today — only the read path exists. The section title
**manual step** reflects that gap: until Flutter (or a small settings RPC) is built, something outside
the app must flip the flag after platform enroll completes.

**Purpose:** a clinic-local switch so the desktop client can hide or show AI affordances without
calling Cloudflare on every launch. It does not grant quotas; entitlement on the platform (Stage 4)
is separate.

## 5. Failure paths


| Condition                         | Code                            | Field                          |
| --------------------------------- | ------------------------------- | ------------------------------ |
| Non-admin caller                  | `FORBIDDEN`                     | Session role                   |
| Second distinct `installation_id` | `SINGLE_INSTALLATION_VIOLATION` | Trigger on `installation_keys` |




## 6. Happy path

```
Owner/admin session (Flutter)
  → enroll_installation_keypair()
  → { kid, installation_id, public_jwk }
  → Flutter POST /control/installations/{installation_id}/enroll with public_jwk.x + kid
```



## 7. Who calls this RPC and how the platform learns `installation_id`

This subsection answers the production question: after a clinic buys the app and AI add-on, **who** invokes
`enroll_installation_keypair()`, and **how** the Cloudflare AI platform ends up with the same
`installation_id` the clinic minted.

### 7.1 Caller


| Actor                                           | Calls this RPC?                    | Why                                                                                                                                                                                                |
| ----------------------------------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Clinic **owner or administrator** (via Flutter) | **Yes** — intended production path | Gated by `auth_internal.assert_owner_or_administrator()`; only these roles may create the installation keypair                                                                                     |
| Clinic staff / doctors                          | No                                 | They call `issue_ai_token` (Stage 6) only **after** enrollment is complete                                                                                                                         |
| AI platform (Cloudflare Worker)                 | No                                 | The platform has **no inbound path** to clinic Postgres ([01-ai-platform.md §1.3.1](../01-ai-platform.md#131-the-ai-platform-cannot-reach-the-clinics-database)); data flows client → platform only |
| `anon` / unauthenticated clients                | No                                 | `GRANT EXECUTE` is to `authenticated` only                                                                                                                                                         |


**Today:** no Flutter screen calls this RPC yet. Enrollment is a vendor onboarding step (direct
`POST /control/.../enroll` plus manual clinic DB updates) until a verified purchase flow exists
([01-ai-platform.md §12.5 — Self-service enrollment](../01-ai-platform.md#125-explicitly-not-to-be-built-yet)).

**Intended production path:** the clinic owner or administrator taps **Buy / Enable AI** in Flutter;
after payment verification, Flutter calls this RPC on **that clinic's Supabase** using the owner's or
administrator's authenticated session. Flutter is only the HTTP client — the RPC still runs inside
clinic Postgres and the private key never leaves it.

### 7.2 End-to-end flow (intended production)

```
Clinic owner/admin in Flutter
  │
  ├─1─► Payment / purchase verified (billing gate — not built yet)
  │
  ├─2─► Clinic Supabase: enroll_installation_keypair()
  │         mints installation_id (UUID), kid, Ed25519 pair in ai_internal.installation_keys
  │         returns { installation_id, kid, public_jwk }
  │
  ├─3─► AI Platform: POST /control/installations/{installation_id}/enroll
  │         body: org_id, display_name, region, plan, public_key (= public_jwk.x), algorithm, kid
  │         Auth: Bearer OPERATOR_BEARER_TOKEN (today; `control/auth.ts` — future: purchase token)
  │         Handler: `control/lifecycle.ts` `handleEnroll` → D1 batch; returns `platform_base_url`
  │
  ├─4─► Clinic Supabase: set ai.availability { enrolled: true, platform_base_url }
  │         ([§4](#4-clinic-availability-flag-manual-step) — Flutter or a small settings RPC; platform enroll does not write this)
  │
  └─5─► POST /control/installations/{installation_id}/entitle (Stage 4) — vendor or automation;
        enroll alone leaves entitlement `pending` / zero quota
```

Stage 2 stops at step 2. Steps 3–5 are downstream; step 3 is documented in [Stage 3 — Platform installation enrollment](05-stage-3-platform-installation-enrollment.md#3-api-post-controlinstallationsinstallation_idenroll).

### 7.3 How the platform learns `installation_id`

The platform does **not** assign `installation_id`. The clinic mints it:


| Step         | Where                                           | What happens                                                                                                                                                       |
| ------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Mint         | Clinic Postgres (`enroll_installation_keypair`) | On first enroll, `installation_id := gen_random_uuid()` when no active key row exists; reused on later key rotations for the same deployment                       |
| Carry        | Flutter (client)                                | Reads `installation_id` from the RPC response                                                                                                                      |
| Register     | AI platform D1                                  | Flutter passes the same value as the **path parameter** on `POST /control/installations/{installation_id}/enroll`; D1 `installation.installation_id` is that value |
| Verify later | Every AAT                                       | Payload claim `iss` must equal the enrolled `installation_id`; header `kid` selects the public key row                                                             |


The platform learns the id because **Flutter tells it** during platform enroll — not because the
platform generated or polled clinic Postgres.

### 7.4 Duplicate `installation_id` across clinics

Two clinics generating the same id is not a practical risk:


| Layer           | Protection                                                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Clinic mint     | `gen_random_uuid()` — UUID v4; collision probability is negligible across independent clinics                                    |
| Platform enroll | `handleEnroll` rejects if `installation_id` **or** `org_id` already exists in D1 → **409** `already_enrolled`; no row is written |


A duplicate would require the same UUID to be minted in two clinic databases **and** the second enroll
attempt to reach the platform before the first — effectively impossible in practice. If a clinic
re-runs enrollment for an already-registered installation/org, the platform returns 409 and the clinic
DB state is unchanged on the platform side.

### 7.5 What this stage does not do

- Does **not** register the installation on the AI platform (Stage 3).
- Does **not** grant quotas or capabilities (Stage 4 entitle).
- Does **not** set `ai.availability` ([§4](#4-clinic-availability-flag-manual-step)).
- Does **not** mint AATs for staff use (Stage 6 — `issue_ai_token` requires an existing keypair from this stage).

## 8. Behavioral verification

Live probes against a running clinic Supabase (and a local Worker from [§8.3.8](#838-platform-does-not-know-the-clinic-yet) onward). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§8.3](#83-ordered-probes) top to bottom** on a throwaway local clinic. If every probe matches, this stage is working.

The gate in code is `auth_internal.assert_owner_or_administrator()`: `staff_members.role = 'administrator'` **or** `is_bootstrap_admin = true` (the first installer; the “owner” this document names). Non-admin roles (`doctor`, and any other non-administrator who is not bootstrap admin) must fail enroll.

### 8.1 Setup

- Local clinic Supabase with migrations applied. Prefer a database you can wipe; several probes insert extra key rows and enroll the local Worker.
- Three authenticated sessions (look up `auth_user_id` from `staff_members`):
  - **Owner** — `is_bootstrap_admin = true`
  - **Administrator** — `role = 'administrator'` and a different `auth_user_id` than the owner (create one if the bootstrap admin is the only administrator)
  - **Doctor** — `role = 'doctor'` (or any non-administrator who is not bootstrap admin)
- SQL as `postgres` only to inspect `ai_internal`, reset rows, and force the single-installation trigger.
- Local Worker (`npm run dev`) with `OPERATOR_BEARER_TOKEN` from [§8.3.8](#838-platform-does-not-know-the-clinic-yet). Clinic `organizations.id` for the enroll body.
- Staff who will mint an AAT must have at least one `ai.*` RBAC permission.

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

### 8.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Seed `ai.availability` is `{ enrolled: false, platform_base_url: null }` | [§8.3.1](#831-reset-to-a-known-clinic-state), [§8.3.2](#832-before-any-key-exists) |
| `get_ai_availability()` works for any authenticated staff (including doctor) | [§8.3.2](#832-before-any-key-exists) |
| Flutter hides AI and does not probe the Worker while `enrolled` is false | [§8.3.2](#832-before-any-key-exists) |
| `issue_ai_token` before any key → `INSTALLATION_NOT_ENROLLED` | [§8.3.2](#832-before-any-key-exists) |
| Non-admin enroll → `FORBIDDEN`; no key row | [§8.3.3](#833-enroll-failure-paths) |
| `anon` cannot call `enroll_installation_keypair` | [§8.3.3](#833-enroll-failure-paths) |
| Empty keystore: owner enroll mints a new `installation_id`, `kid`, Ed25519 JWK | [§8.3.4](#834-first-enroll-happy-path) |
| Success `data` has every field in [§3](#3-api-publicenroll_installation_keypair); no `secret_key` | [§8.3.4](#834-first-enroll-happy-path) |
| Postgres write: `algorithm = EdDSA`, `secret_key` present, audit columns, `public_key` = `public_jwk.x` | [§8.3.4](#834-first-enroll-happy-path) |
| Authenticated clients cannot `SELECT` the keystore | [§8.3.4](#834-first-enroll-happy-path) |
| Keypair RPC does not write `ai.availability` | [§8.3.4](#834-first-enroll-happy-path) |
| Administrator may enroll; same `installation_id`, new `kid` | [§8.3.5](#835-administrator-enroll-and-installation_id-reuse-happy-path) |
| Second distinct `installation_id` → `SINGLE_INSTALLATION_VIOLATION` | [§8.3.6](#836-single-installation-trigger-failure-path) |
| AAT `iss` = `installation_id`; header `kid` selects this key | [§8.3.7](#837-mint-an-aat-from-this-key-happy-path-for-the-handoff-fields) |
| Clinic enroll does not register D1; capability POST fails identity | [§8.3.8](#838-platform-does-not-know-the-clinic-yet) |
| [§6](#6-happy-path) handoff: path `installation_id`, body `public_jwk.x` + `kid` → platform 200 | [§8.3.9](#839-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| Platform does not write clinic `app_settings` | [§8.3.9](#839-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| Re-enroll same installation/org → 409 `already_enrolled` ([§7.4](#74-duplicate-installation_id-across-clinics)) | [§8.3.9](#839-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| Enroll leaves entitlement `pending` / zero quota ([§7.5](#75-what-this-stage-does-not-do)) | [§8.3.9](#839-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| Manual `UPDATE` flips the flag; no `set_ai_availability` RPC; flag does not grant quotas | [§8.3.10](#8310-availability-flag-after-the-key-exists) |


### 8.3 Ordered probes

#### 8.3.1 Reset to a known clinic state

**Do:** as `postgres` on the throwaway local database:

```sql
DELETE FROM ai_internal.ai_token_issuance;
DELETE FROM ai_internal.installation_keys;

UPDATE ai_internal.app_settings
SET value_json = '{"enrolled": false, "platform_base_url": null}'::jsonb
WHERE key = 'ai.availability';
```

**Expect:** `installation_keys` is empty. `get_ai_availability()` (next probe) can see the seeded default.

#### 8.3.2 Before any key exists

**Do:** as **doctor**, `SELECT public.get_ai_availability();`

**Expect:** `{ "enrolled": false, "platform_base_url": null }`. Any authenticated staff may read this RPC.

**Do:** open the Flutter AI surface with that flag (do not flip it).

**Expect:** AI affordances stay hidden. The client does **not** call the Worker (`/health`, `/v1/*`, `/control/*` all absent). Enrollment is not discovered from Cloudflare.

**Do:** as doctor (or any staff with `ai.*`), `SELECT public.issue_ai_token();`

**Expect:** `success = false`, `error_code = 'INSTALLATION_NOT_ENROLLED'`. This stage’s keypair is a prerequisite for Stage 6; this RPC does not mint AATs.

#### 8.3.3 Enroll failure paths

**Do:** as **doctor**, `SELECT public.enroll_installation_keypair();`

**Expect:** `success = false`, `error_code = 'FORBIDDEN'`, message that only administrators may enroll. As `postgres`, `installation_keys` is still empty.

**Do:** as `anon` (no JWT), `POST /rest/v1/rpc/enroll_installation_keypair`.

**Expect:** PostgREST 401 / permission denied. `GRANT EXECUTE` is to `authenticated` only. The AI platform has no inbound path to this RPC either — there is nothing to call from the Worker.

#### 8.3.4 First enroll (happy path)

**Do:** as **owner** (`is_bootstrap_admin`), with `installation_keys` still empty:

```sql
SELECT public.enroll_installation_keypair();
```

**Expect:** `success = true`. `data` contains **every** field from [§3](#3-api-publicenroll_installation_keypair):

- `kid` — UUID text
- `installation_id` — UUID text (fresh; no prior active row existed)
- `public_jwk.kty = "OKP"`
- `public_jwk.crv = "Ed25519"`
- `public_jwk.x` — non-empty base64url
- `public_jwk.kid` — same string as top-level `kid`

`data` has **no** `secret_key` (and no other private material). Save `kid`, `installation_id`, and `public_jwk.x` — later probes reuse them. Call this saved `installation_id` **I0** and this `kid` **K0**.

**Do:** as `postgres`:

```sql
SELECT
  kid,
  installation_id::text,
  algorithm,
  secret_key IS NOT NULL AS has_secret,
  octet_length(public_key) AS public_len,
  octet_length(secret_key) AS secret_len,
  created_by,
  updated_by,
  valid_from,
  auth_internal.base64url_encode(public_key) AS x_from_row
FROM ai_internal.installation_keys
WHERE is_deleted = false;
```

**Expect:** exactly one row. `kid = K0`, `installation_id = I0`, `algorithm = 'EdDSA'`, `has_secret = true`, `public_len = 32`, `secret_len = 64`, `created_by` and `updated_by` equal the owner’s `auth_user_id`, `valid_from` is now, `x_from_row` equals RPC `public_jwk.x`. The private key exists only in this row.

**Do:** as the same authenticated owner, `SELECT * FROM ai_internal.installation_keys;`

**Expect:** denied (no schema `USAGE` / RLS deny-all). Clients cannot read the stamp out of the drawer.

**Do:** as doctor, `SELECT public.get_ai_availability();`

**Expect:** still `{ "enrolled": false, "platform_base_url": null }`. `enroll_installation_keypair` does not touch `app_settings`.

#### 8.3.5 Administrator enroll and `installation_id` reuse (happy path)

**Do:** as **administrator** (different `auth_user_id` from the owner):

```sql
SELECT public.enroll_installation_keypair();
```

**Expect:** `success = true`. New `kid` (**K1** ≠ **K0**). **Same** `installation_id` **I0**. Two rows in `installation_keys`. The RPC never mints a second installation id, so this happy path does not raise `SINGLE_INSTALLATION_VIOLATION`. Both owner and administrator are allowed callers ([§7.1](#71-caller)).

#### 8.3.6 Single-installation trigger (failure path)

The public RPC cannot produce a second id. After at least one key exists, **do** as `postgres`:

```sql
INSERT INTO ai_internal.installation_keys (
  kid, installation_id, public_key, secret_key, algorithm
) VALUES (
  gen_random_uuid()::text,
  gen_random_uuid(),
  decode('00', 'hex'),
  decode('00', 'hex'),
  'EdDSA'
);
```

**Expect:** `SINGLE_INSTALLATION_VIOLATION` (`P0001`). Still exactly two rows (K0 and K1); `installation_id` remains **I0** on both.

#### 8.3.7 Mint an AAT from this key (happy path for the handoff fields)

**Do:** as doctor with `ai.*`, `SELECT public.issue_ai_token();`

**Expect:** `success = true` and a JWS. Decode header and payload:

- Header `alg = EdDSA`
- Header `kid` is **K0** or **K1** (the issuer picks the latest active key)
- Payload `iss` = **I0**

This is Stage 6 using the key this stage minted. `enroll_installation_keypair` itself still does not return a token.

#### 8.3.8 Platform does not know the clinic yet

Do **not** call Stage 3 yet.

**Do:** inspect local D1 for **I0**:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id FROM installation WHERE installation_id = '<I0>'"
```

**Expect:** no row. The platform did not assign or poll `installation_id`.

**Do:** `POST /v1/requests` to the local Worker with the AAT from [§8.3.7](#837-mint-an-aat-from-this-key-happy-path-for-the-handoff-fields) as `Authorization: Bearer`.

**Expect:** identity failure (`unauthenticated`). Same shape as retiring a token-contract version then invoking: the border guard has no file for this passport.

#### 8.3.9 Stage 3 enroll using this RPC’s output (happy path §6)

**Do:** copy **I0**, **K0**, and `public_jwk.x` from the **first** enroll (do not invent a platform id). Local Worker up:

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export INSTALLATION_ID='<I0>'

curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "org_id": "<clinic organizations.id>",
    "display_name": "Verify Clinic",
    "region": "local",
    "plan": "verify",
    "public_key": "<public_jwk.x from first enroll>",
    "algorithm": "EdDSA",
    "kid": "<K0>"
  }'
```

**Expect:** HTTP 200, `{ "platform_base_url": "http://127.0.0.1:8787" }` (the origin you posted to). D1 `installation.installation_id = I0`, `installation_key.key_id = K0`, `installation_key.public_key` equals that `x`. Entitlement `status = pending`, quotas `0`, `allowed_capabilities = []`. Stage 2’s job was to mint those three values; Stage 3 only registers what you copied.

**Do:** as doctor, `SELECT public.get_ai_availability();`

**Expect:** still `{ "enrolled": false, "platform_base_url": null }`. Platform enroll does not write clinic Postgres.

**Do:** repeat the same `POST …/enroll` (same `installation_id` and `org_id`).

**Expect:** HTTP 409, `already_enrolled`. Clinic `installation_keys` unchanged. This is [§7.4](#74-duplicate-installation_id-across-clinics) on the platform side.

**Do:** `POST /v1/requests` again with a valid AAT (do **not** entitle).

**Expect:** identity can pass (key is on the platform) but entitlement/quota fails (`forbidden_capability` / `ai_disabled` while pending). This stage does not grant quotas ([§7.5](#75-what-this-stage-does-not-do)).

#### 8.3.10 Availability flag after the key exists

**Do:** try to find a write RPC: `\df public.set_ai_availability` (or call it).

**Expect:** it does not exist. Only the read path exists.

**Do:** vendor update ([runbook §5.3](../04-ai-platform-operator-runbook.md#53-clinic-flip-availability)):

```sql
UPDATE ai_internal.app_settings
SET value_json = jsonb_build_object(
  'enrolled', true,
  'platform_base_url', 'http://127.0.0.1:8787'
)
WHERE key = 'ai.availability';

SELECT public.get_ai_availability();
```

**Expect:** `{ "enrolled": true, "platform_base_url": "http://127.0.0.1:8787" }` for **doctor** as well as owner/admin.

**Do:** open the Flutter AI surface.

**Expect:** AI chrome is no longer hidden for non-enrollment. The client may `GET {platform_base_url}/health`. It still must not treat Worker reachability as a substitute for this flag (the flag was already true before any probe).

**Do:** `POST /v1/requests` with a valid AAT, still without Stage 4 entitle.

**Expect:** still not entitled. The availability flag does not grant quotas.
