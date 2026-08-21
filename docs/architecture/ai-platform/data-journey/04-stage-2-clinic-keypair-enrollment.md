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
clinic. Steady state is one active key; multiple keys exist only during **rotation overlap** — a new
keypair gets a new `kid` while the old row remains so in-flight AATs (short-lived, ~5 min) still verify.
The platform selects the public key by AAT header `kid` (with payload `iss`). After overlap, the old
key is **revoked** and AATs bearing that `kid` are rejected regardless of `exp`.

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
