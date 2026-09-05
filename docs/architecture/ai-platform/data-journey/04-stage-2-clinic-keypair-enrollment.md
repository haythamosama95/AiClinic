# AI Platform Data Journey — Stage 2 — Clinic keypair enrollment (Supabase)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [API: `public.enroll_installation_keypair()`](#3-api-publicenroll_installation_keypair)
   - [3.1 API: `public.rotate_installation_key()`](#31-api-publicrotate_installation_key)
   - [3.2 API: `public.revoke_installation_key(p_kid text)`](#32-api-publicrevoke_installation_keyp_kid-text)
   - [3.3 API: `public.get_ai_availability()`](#33-api-publicget_ai_availability)
   - [3.4 API: `public.set_ai_availability()`](#34-api-publicset_ai_availability)
4. [Clinic availability flag](#4-clinic-availability-flag)
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
     - [8.3.5 Second enroll while active key exists](#835-second-enroll-while-active-key-exists)
     - [8.3.6 Key rotation via `rotate_installation_key` (happy path)](#836-key-rotation-via-rotate_installation_key-happy-path)
     - [8.3.7 Revoke installation key (happy path)](#837-revoke-installation-key-happy-path)
     - [8.3.8 Rotate before enroll fails (`INSTALLATION_NOT_ENROLLED`)](#838-rotate-before-enroll-fails-installation_not_enrolled)
     - [8.3.9 Single-installation trigger (failure path)](#839-single-installation-trigger-failure-path)
     - [8.3.10 Mint an AAT from this key (happy path for the handoff fields)](#8310-mint-an-aat-from-this-key-happy-path-for-the-handoff-fields)
     - [8.3.11 Platform does not know the clinic yet](#8311-platform-does-not-know-the-clinic-yet)
     - [8.3.12 Stage 3 enroll using this RPC’s output (happy path §6)](#8312-stage-3-enroll-using-this-rpcs-output-happy-path-6)
     - [8.3.13 Availability flag after the key exists](#8313-availability-flag-after-the-key-exists)
     - [8.3.14 Cannot revoke last active key](#8314-cannot-revoke-last-active-key)
     - [8.3.15 Recovery re-enroll after all keys revoked (postgres simulation)](#8315-recovery-re-enroll-after-all-keys-revoked-postgres-simulation)
     - [8.3.16 Rotate succeeds when every key is revoked](#8316-rotate-succeeds-when-every-key-is-revoked)

---




## 1. Plain language

The clinic generates an Ed25519 keypair **inside Supabase**. The private key never leaves the clinic database. The public key and `kid` are later copied to the platform enroll call.

After the first enroll, operators **rotate** keys with `rotate_installation_key()` (adds a new signing key, keeps the same `installation_id`) and **revoke** old keys with `revoke_installation_key(kid)` when overlap ends. Revoke cannot remove the **last** active key (`is_deleted = false` and `revoked_at IS NULL`) — rotate a replacement first, then revoke the old `kid`. Normal ops never reach zero active keys via the revoke API. When every key is revoked (disaster recovery / privileged maintenance), **`rotate_installation_key()`** or **`enroll_installation_keypair()`** both recover under the same `installation_id` ([§8.3.15](#8315-recovery-re-enroll-after-all-keys-revoked-postgres-simulation), [§8.3.16](#8316-rotate-succeeds-when-every-key-is-revoked)).

## 2. Metaphor

The clinic prints its own **signing stamp** (private key) and sends a **stamp specimen** (public key) to the platform passport office. Rotation orders a **new stamp** with the same clinic identity; revocation **voids** one stamp specimen while others may still be valid during overlap.

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
clinic. Steady state is one active key. Production rotation uses `rotate_installation_key()` ([§3.1](#31-api-publicrotate_installation_key)). A second `enroll_installation_keypair()` while an active key exists (`is_deleted = false` and `revoked_at IS NULL`) fails with `ALREADY_ENROLLED`. When **no** active key remains, **`rotate_installation_key()`** or **`enroll_installation_keypair()`** both recover under the same `installation_id` ([§8.3.15](#8315-recovery-re-enroll-after-all-keys-revoked-postgres-simulation), [§8.3.16](#8316-rotate-succeeds-when-every-key-is-revoked)). That zero-active state cannot be produced by revoking every key through `revoke_installation_key` — the RPC rejects the last active key with `CANNOT_REVOKE_LAST_ACTIVE_KEY` ([§8.3.14](#8314-cannot-revoke-last-active-key)).

Clinic keystore rotation is **additive**: old keys stay until revoked ([§3.2](#32-api-publicrevoke_installation_keyp_kid-text)). On the platform, `POST …/rotate` stamps `revoked_at` on prior D1 keys in the same batch as the new-key insert ([§7 in Stage 3](05-stage-3-platform-installation-enrollment.md#7-api-post-controlinstallationsinstallation_idrotate)). In-flight AATs signed with an old `kid` fail identity on the platform as soon as rotate returns — there is no platform dual-key overlap. Operators mint new AATs with the new `kid`. The platform selects the public key by AAT header `kid` (with payload `iss`). Revoked keys are rejected regardless of `exp`.

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


**Errors:**


| Code               | When                                                                 |
| ------------------ | -------------------------------------------------------------------- |
| `FORBIDDEN`        | Caller is not an administrator (`role = 'administrator'`) and not `is_bootstrap_admin = true` |
| `ALREADY_ENROLLED` | An active key row exists — use `rotate_installation_key()` ([§8.3.5](#835-second-enroll-while-active-key-exists)) |

`SINGLE_INSTALLATION_VIOLATION` is **not** an envelope code — the `installation_keys_single_installation` trigger raises it (P0001) on a direct INSERT with a second `installation_id`; no RPC reaches that branch ([§8.3.9](#839-single-installation-trigger-failure-path)).


### 3.1 API: `public.rotate_installation_key()`

Adds a new signing key for the clinic’s existing `installation_id`. Use this after the first enroll when you need a fresh `kid` and keypair. Requires at least one non-deleted keystore row — succeeds even when every existing key is revoked (recovery path, [§8.3.16](#8316-rotate-succeeds-when-every-key-is-revoked)). Returns `INSTALLATION_NOT_ENROLLED` only when no non-deleted rows exist.


| Item         | Value                       |
| ------------ | --------------------------- |
| Method       | RPC (PostgREST)             |
| Auth         | Authenticated admin session |
| Request body | **None**                    |


**Success** `data` **object — same shape as enroll:**


| Field             | Type   | Meaning                                                                 |
| ----------------- | ------ | ----------------------------------------------------------------------- |
| `kid`             | string | New key id for this rotation                                            |
| `installation_id` | string | Same clinic installation id as existing keys (never mints a new one)    |
| `public_jwk`      | object | Ed25519 JWK (`kty`, `crv`, `x`, `kid`) — hand off to platform rotate   |


**Errors:**


| Code                        | When                                                                 |
| --------------------------- | -------------------------------------------------------------------- |
| `FORBIDDEN`                 | Caller is not an administrator and not `is_bootstrap_admin = true`   |
| `INSTALLATION_NOT_ENROLLED` | No non-deleted `installation_keys` row — run enroll first ([§8.3.8](#838-rotate-before-enroll-fails-installation_not_enrolled)) |


Rotation is **additive**: the previous key row stays until you revoke it ([§3.2](#32-api-publicrevoke_installation_keyp_kid-text)). The issuer signs with the newest non-revoked key (`valid_from DESC, kid DESC`).

### 3.2 API: `public.revoke_installation_key(p_kid text)`

Marks one key row as revoked. Tokens signed with that `kid` must not verify after revocation.


| Item         | Value                       |
| ------------ | --------------------------- |
| Method       | RPC (PostgREST)             |
| Auth         | Authenticated admin session |
| Parameters   | `p_kid` — `installation_keys.kid` text |


**Success** `data` **object:**


| Field        | Type   | Meaning                                      |
| ------------ | ------ | -------------------------------------------- |
| `kid`        | string | The key id you passed (or already revoked)   |
| `revoked_at` | string | Stored `revoked_at` from the key row         |


Fresh revocation returns the **stored** `revoked_at` from the row (`RETURNING` after the UPDATE). If the key was already revoked, the RPC returns success with the same stored value (idempotent).

Revoking the **last** active key (`is_deleted = false` and `revoked_at IS NULL`) is rejected — operators must `rotate_installation_key()` first, then revoke the superseded `kid`. Idempotent revoke of an already-revoked key still succeeds even when it is the only key row left.

**Errors:**


| Code                            | When                                                                 |
| ------------------------------- | -------------------------------------------------------------------- |
| `FORBIDDEN`                     | Caller is not an administrator and not `is_bootstrap_admin = true`   |
| `INVALID_INPUT`                 | `p_kid` is null or blank after trim                                  |
| `KEY_NOT_FOUND`                 | No non-deleted row with that `kid`                                   |
| `CANNOT_REVOKE_LAST_ACTIVE_KEY` | Revoke would leave zero active keys — rotate a replacement first     |


### 3.3 API: `public.get_ai_availability()`

Read-only clinic switch for the Flutter client. Returns **plain `jsonb`**, not the `rpc_result` envelope used by enroll / rotate / revoke.


| Item         | Value                              |
| ------------ | ---------------------------------- |
| Method       | RPC (PostgREST)                    |
| Auth         | Any authenticated staff session    |
| Request body | **None**                           |
| Returns      | `jsonb` object (not `rpc_success`) |


**Response object — every field:**


| Field               | Type    | Default when unset | Meaning                                              |
| ------------------- | ------- | ------------------ | ---------------------------------------------------- |
| `enrolled`          | boolean | `false`            | Whether the clinic considers AI enabled in the UI    |
| `platform_base_url` | string or null | `null`        | Base URL of the enrolled AI platform Worker          |


**Errors:**


| Condition              | Result                                      |
| ---------------------- | ------------------------------------------- |
| `anon` / no JWT        | PostgREST permission denied (no `GRANT`)    |
| Valid staff session    | Always returns the current JSON (no error code) |


Flutter calls this to decide whether to show AI UI — it **never** probes the AI platform to discover enrollment. Who may **write** the flag is documented in [§4](#4-clinic-availability-flag); this RPC is read-only.

### 3.4 API: `public.set_ai_availability(p_enrolled, p_platform_base_url)`

Administrator-gated write path for the clinic availability flag (migration `20260905120100_set_ai_availability_rpc.sql`). Returns the standard `rpc_result` envelope.


| Item         | Value                       |
| ------------ | --------------------------- |
| Method       | RPC (PostgREST)             |
| Auth         | Authenticated admin session |
| Parameters   | `p_enrolled` (boolean, required); `p_platform_base_url` (text, required when `p_enrolled = true`) |


**Success** `data` **object — same shape as** [§3.3](#33-api-publicget_ai_availability):


| Field               | Type    | Meaning                                              |
| ------------------- | ------- | ---------------------------------------------------- |
| `enrolled`          | boolean | Whether the clinic considers AI enabled in the UI    |
| `platform_base_url` | string or null | Base URL of the enrolled AI platform Worker   |


When `p_enrolled = false`, `platform_base_url` in the stored JSON is set to `null`.

**Errors:**


| Code            | When                                                                 |
| --------------- | -------------------------------------------------------------------- |
| `FORBIDDEN`     | Caller is not an administrator and not `is_bootstrap_admin = true`   |
| `INVALID_INPUT` | `p_enrolled` is null, or `p_enrolled = true` with blank/missing URL  |


Enroll, rotate, and revoke still do not touch `app_settings` — call this RPC (or Flutter wiring to it) after Stage 3 platform enrollment ([§8.3.13](#8313-availability-flag-after-the-key-exists)).

## 4. Clinic availability flag

**Table:** `ai_internal.app_settings` key `ai.availability`


| Field               | Default | Set by                        |
| ------------------- | ------- | ----------------------------- |
| `enrolled`          | `false` | See **Who writes this** below |
| `platform_base_url` | `null`  | See **Who writes this** below |


**Read path:** [§3.3 `public.get_ai_availability()`](#33-api-publicget_ai_availability).

**Who writes this:**


| Actor                                                 | Writes?                 | When                                                                                                                                                                               |
| ----------------------------------------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Migration (`20260802140000_ai_availability_flag.sql`) | **Yes** — seed only     | Clinic Supabase first deploy; default `{ enrolled: false, platform_base_url: null }`                                                                                               |
| AI platform (Stage 3 enroll)                          | **No**                  | Enroll returns `platform_base_url` in the HTTP response only; D1 is updated, not clinic Postgres                                                                                   |
| `enroll_installation_keypair` ([§3](#3-api-publicenroll_installation_keypair))                  | **No**                  | Keypair RPC does not touch `app_settings`                                                                                                                                          |
| `rotate_installation_key` / `revoke_installation_key` | **No**                  | Keystore RPCs do not touch `app_settings`                                                                                                                                            |
| `set_ai_availability` ([§3.4](#34-api-publicset_ai_availability)) | **Yes** | Intended production path after Stage 3 platform enrollment: administrator or bootstrap admin sets `enrolled: true` and stores `platform_base_url` from the enroll response |
| Flutter (intended production)                         | **Yes** — not built yet | Should call [§3.4 `set_ai_availability`](#34-api-publicset_ai_availability) after successful platform enroll ([§7.2 step 4](#72-end-to-end-flow-intended-production))                                     |
| Vendor onboarding (today)                             | **Yes**                 | `SELECT public.set_ai_availability(true, '<platform_base_url>');` as an administrator, or manual `UPDATE ai_internal.app_settings …` until Flutter calls the RPC ([04-ai-platform-operator-runbook.md §5.3](../04-ai-platform-operator-runbook.md#53-clinic-flip-availability)) |


The write RPC closes the former manual-only gap. Until Flutter wires it, operators may still flip the flag with a privileged SQL `UPDATE`, but **`set_ai_availability`** is the supported contract surface.

**Purpose:** a clinic-local switch so the desktop client can hide or show AI affordances without
calling Cloudflare on every launch. It does not grant quotas; entitlement on the platform (Stage 4)
is separate.

## 5. Failure paths


| RPC                               | Condition                         | Code                            | Field / notes                  |
| --------------------------------- | --------------------------------- | ------------------------------- | ------------------------------ |
| `enroll_installation_keypair`     | Non-admin caller                  | `FORBIDDEN`                     | Session role                   |
| `enroll_installation_keypair`     | Active key already exists         | `ALREADY_ENROLLED`              | Use `rotate_installation_key`  |
| `rotate_installation_key`         | Non-admin caller                  | `FORBIDDEN`                     | Session role                   |
| `rotate_installation_key`         | No active key row yet             | `INSTALLATION_NOT_ENROLLED`     | Enroll first                   |
| `revoke_installation_key`         | Non-admin caller                  | `FORBIDDEN`                     | Session role                   |
| `revoke_installation_key`         | Blank `p_kid`                     | `INVALID_INPUT`                 | Parameter                      |
| `revoke_installation_key`         | Unknown or soft-deleted `kid`     | `KEY_NOT_FOUND`                 | Parameter                      |
| `revoke_installation_key`         | Last active key for installation  | `CANNOT_REVOKE_LAST_ACTIVE_KEY` | Rotate replacement first       |
| `get_ai_availability`             | `anon` / unauthenticated          | PostgREST denied                | No `GRANT` to `anon`           |




## 6. Happy path

```
Bootstrap administrator or administrator session (Flutter)
  → enroll_installation_keypair()
  → { kid, installation_id, public_jwk }
  → Flutter POST /control/installations/{installation_id}/enroll with public_jwk.x + kid
```

Later key changes:

```
Bootstrap administrator or administrator session
  → rotate_installation_key()     # new kid + public_jwk, same installation_id
  → revoke_installation_key(kid)  # retire an old kid when overlap ends (not the last active key)
```



## 7. Who calls this RPC and how the platform learns `installation_id`

This subsection answers the production question: after a clinic buys the app and AI add-on, **who** invokes
`enroll_installation_keypair()`, and **how** the Cloudflare AI platform ends up with the same
`installation_id` the clinic minted.

### 7.1 Caller


| Actor                                           | Calls this RPC?                    | Why                                                                                                                                                                                                |
| ----------------------------------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Clinic **administrator or bootstrap admin** (via Flutter) | **Yes** — intended production path | Gated by `auth_internal.assert_owner_or_administrator()` as the **first** statement in each RPC — the role check precedes all other validation; only `role = 'administrator'` or `is_bootstrap_admin = true` may create, rotate, or revoke installation keys |                                                                         |
| Clinic staff / doctors                          | No                                 | They call `issue_ai_token` (Stage 6) only **after** enrollment is complete; they may call `get_ai_availability` ([§3.3](#33-api-publicget_ai_availability))                                      |
| AI platform (Cloudflare Worker)                 | No                                 | The platform has **no inbound path** to clinic Postgres ([01-ai-platform.md §1.3.1](../01-ai-platform.md#131-the-ai-platform-cannot-reach-the-clinics-database)); data flows client → platform only |
| `anon` / unauthenticated clients                | No                                 | `GRANT EXECUTE` is to `authenticated` only                                                                                                                                                         |


**Today:** no Flutter screen calls this RPC yet. Enrollment is a vendor onboarding step (direct
`POST /control/.../enroll` plus manual clinic DB updates) until a verified purchase flow exists
([01-ai-platform.md §12.5 — Self-service enrollment](../01-ai-platform.md#125-explicitly-not-to-be-built-yet)).

**Intended production path:** a clinic administrator or bootstrap admin taps **Buy / Enable AI** in Flutter;
after payment verification, Flutter calls this RPC on **that clinic's Supabase** using that staff member's
authenticated session. Flutter is only the HTTP client — the RPC still runs inside
clinic Postgres and the private key never leaves it.

### 7.2 End-to-end flow (intended production)

```
Clinic administrator or bootstrap admin in Flutter
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
  ├─4─► Clinic Supabase: set_ai_availability(true, platform_base_url)
  │         ([§3.4](#34-api-publicset_ai_availability) — Flutter wiring not built yet; platform enroll does not write this)
  │
  └─5─► POST /control/installations/{installation_id}/entitle (Stage 4) — vendor or automation;
        enroll alone leaves entitlement `pending` / zero quota
```

Stage 2 stops at step 2. Steps 3–5 are downstream; step 3 is documented in [Stage 3 — Platform installation enrollment](05-stage-3-platform-installation-enrollment.md#3-api-post-controlinstallationsinstallation_idenroll).

### 7.3 How the platform learns `installation_id`

The platform does **not** assign `installation_id`. The clinic mints it:


| Step         | Where                                           | What happens                                                                                                                                                       |
| ------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Mint         | Clinic Postgres (`enroll_installation_keypair`) | On first enroll, `installation_id := gen_random_uuid()` when no active key row exists; reused on `rotate_installation_key` and on recovery re-enroll when no active key remains (typically postgres/admin — not via revoke API) |
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
- Does **not** set `ai.availability` ([§4](#4-clinic-availability-flag); use [§3.4](#34-api-publicset_ai_availability) after Stage 3).
- Does **not** mint AATs for staff use (Stage 6 — `issue_ai_token` requires an existing keypair from this stage).

## 8. Behavioral verification

Live probes against a running clinic Supabase (and a local Worker from [§8.3.11](#8311-platform-does-not-know-the-clinic-yet) onward). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§8.3](#83-ordered-probes) top to bottom** on a throwaway local clinic. If every probe matches, this stage is working.

The gate in code is `auth_internal.assert_owner_or_administrator()`: `staff_members.role = 'administrator'` **or** `is_bootstrap_admin = true` (bootstrap administrator — the first installer). Non-admin roles (`doctor`, and any other non-administrator who is not bootstrap admin) must fail enroll, rotate, and revoke with `FORBIDDEN` **before** any input or state validation runs.

### 8.1 Setup

- Local clinic Supabase with migrations applied. Prefer a database you can wipe; several probes insert extra key rows and enroll the local Worker.
- Three authenticated sessions (look up `auth_user_id` from `staff_members`):
  - **Bootstrap administrator (BOOT)** — `is_bootstrap_admin = true`
  - **Administrator** — `role = 'administrator'` and a different `auth_user_id` than the bootstrap admin (create one if the bootstrap admin is the only administrator)
  - **Doctor** — `role = 'doctor'` (or any non-administrator who is not bootstrap admin)
- SQL as `postgres` only to inspect `ai_internal`, reset rows, and force the single-installation trigger.
- Local Worker (`npm run dev`) with `OPERATOR_BEARER_TOKEN` from [§8.3.11](#8311-platform-does-not-know-the-clinic-yet). Clinic `organizations.id` for the enroll body.
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

---

### 8.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Seed `ai.availability` is `{ enrolled: false, platform_base_url: null }` | [§8.3.1](#831-reset-to-a-known-clinic-state), [§8.3.2](#832-before-any-key-exists) |
| `get_ai_availability()` works for any authenticated staff (including doctor) | [§8.3.2](#832-before-any-key-exists) |
| Flutter hides AI and does not probe the Worker while `enrolled` is false | [§8.3.2](#832-before-any-key-exists) |
| `issue_ai_token` before any key → `INSTALLATION_NOT_ENROLLED` (P0001, not `rpc_result`) | [§8.3.2](#832-before-any-key-exists) |
| `rotate_installation_key` before any key → `INSTALLATION_NOT_ENROLLED` | [§8.3.3](#833-enroll-failure-paths), [§8.3.8](#838-rotate-before-enroll-fails-installation_not_enrolled) |
| Non-admin enroll → `FORBIDDEN`; no key row | [§8.3.3](#833-enroll-failure-paths) |
| `anon` cannot call `enroll_installation_keypair` | [§8.3.3](#833-enroll-failure-paths) |
| Empty keystore: bootstrap admin enroll mints a new `installation_id`, `kid`, Ed25519 JWK | [§8.3.4](#834-first-enroll-happy-path) |
| Success `data` has every field in [§3](#3-api-publicenroll_installation_keypair); no `secret_key` | [§8.3.4](#834-first-enroll-happy-path) |
| Postgres write: `algorithm = EdDSA`, `secret_key` present, audit columns, `public_key` = `public_jwk.x` | [§8.3.4](#834-first-enroll-happy-path) |
| Authenticated clients cannot `SELECT` the keystore | [§8.3.4](#834-first-enroll-happy-path) |
| Keypair RPC does not write `ai.availability` | [§8.3.4](#834-first-enroll-happy-path) |
| Second enroll while active key exists → `ALREADY_ENROLLED`; no new row | [§8.3.5](#835-second-enroll-while-active-key-exists) |
| Administrator may rotate; same `installation_id`, new `kid` via `rotate_installation_key` | [§8.3.6](#836-key-rotation-via-rotate_installation_key-happy-path) |
| `rotate_installation_key` success `data` matches [§3.1](#31-api-publicrotate_installation_key) | [§8.3.6](#836-key-rotation-via-rotate_installation_key-happy-path) |
| `revoke_installation_key(kid)` returns `{ kid, revoked_at }` (stored row value); idempotent on second call | [§8.3.7](#837-revoke-installation-key-happy-path) |
| Revoked `kid` fails `verify_aat`; unrevoked sibling `kid` still verifies | [§8.3.7](#837-revoke-installation-key-happy-path) |
| Blank / unknown `p_kid` on revoke → `INVALID_INPUT` / `KEY_NOT_FOUND` | [§8.3.7](#837-revoke-installation-key-happy-path) |
| Revoke last active key → `CANNOT_REVOKE_LAST_ACTIVE_KEY`; K1 stays unrevoked | [§8.3.7](#837-revoke-installation-key-happy-path), [§8.3.14](#8314-cannot-revoke-last-active-key) |
| Second distinct `installation_id` → trigger `SINGLE_INSTALLATION_VIOLATION` (P0001, not envelope) | [§8.3.9](#839-single-installation-trigger-failure-path) |
| AAT `iss` = `installation_id`; header `kid` selects this key | [§8.3.10](#8310-mint-an-aat-from-this-key-happy-path-for-the-handoff-fields) |
| Clinic enroll does not register D1; capability POST fails identity | [§8.3.11](#8311-platform-does-not-know-the-clinic-yet) |
| [§6](#6-happy-path) handoff: path `installation_id`, body `public_jwk.x` + `kid` → platform 200 | [§8.3.12](#8312-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| Platform does not write clinic `app_settings` | [§8.3.12](#8312-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| Re-enroll same installation/org → 409 `already_enrolled` ([§7.4](#74-duplicate-installation_id-across-clinics)) | [§8.3.12](#8312-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| Enroll leaves entitlement `pending` / zero quota ([§7.5](#75-what-this-stage-does-not-do)) | [§8.3.12](#8312-stage-3-enroll-using-this-rpcs-output-happy-path-6) |
| `set_ai_availability` flips the flag; flag does not grant quotas | [§8.3.13](#8313-availability-flag-after-the-key-exists) |
| Recovery re-enroll when no active key remains reuses `installation_id`, mints new `kid` (postgres simulation) | [§8.3.15](#8315-recovery-re-enroll-after-all-keys-revoked-postgres-simulation) |
| Rotate when every key is revoked still succeeds under the same `installation_id` | [§8.3.16](#8316-rotate-succeeds-when-every-key-is-revoked) |

---

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

---

#### 8.3.2 Before any key exists

**Do:** as **doctor**, `SELECT public.get_ai_availability();`

**Expect:** `{ "enrolled": false, "platform_base_url": null }`. Any authenticated staff may read this RPC ([§3.3](#33-api-publicget_ai_availability)).

**Do:** open the Flutter AI surface with that flag (do not flip it).

**Expect:** AI affordances stay hidden. The client does **not** call the Worker (`/health`, `/v1/*`, `/control/*` all absent). Enrollment is not discovered from Cloudflare.

**Do:** as doctor (or any staff with `ai.*`), `SELECT public.issue_ai_token();`

**Expect:** exception `INSTALLATION_NOT_ENROLLED` (SQLSTATE `P0001`; PostgREST `message` is that string). There is no `rpc_result` envelope — unlike enroll / rotate / revoke. This stage’s keypair is a prerequisite for Stage 6; this RPC does not mint AATs.

---

#### 8.3.3 Enroll failure paths

**Do:** as **bootstrap administrator (BOOT)**, with `installation_keys` still empty, `SELECT public.rotate_installation_key();`

**Expect:** `success = false`, `error_code = 'INSTALLATION_NOT_ENROLLED'`, message to enroll first. No new key row ([§3.1](#31-api-publicrotate_installation_key)).

**Do:** as **doctor**, `SELECT public.enroll_installation_keypair();`

**Expect:** `success = false`, `error_code = 'FORBIDDEN'`, message that only administrators may enroll. As `postgres`, `installation_keys` is still empty.

**Do:** as **doctor**, `SELECT public.rotate_installation_key();` and `SELECT public.revoke_installation_key('any');`

**Expect:** both `FORBIDDEN` — the role check runs before the empty-keystore / blank-kid guards, so non-admins never see `INSTALLATION_NOT_ENROLLED` or `INVALID_INPUT`. Non-admins cannot rotate or revoke.

**Do:** as `anon` (no JWT), `POST /rest/v1/rpc/enroll_installation_keypair`.

**Expect:** PostgREST 401 / permission denied. `GRANT EXECUTE` is to `authenticated` only. The AI platform has no inbound path to this RPC either — there is nothing to call from the Worker.

---

#### 8.3.4 First enroll (happy path)

**Do:** as **bootstrap administrator (BOOT)** (`is_bootstrap_admin`), with `installation_keys` still empty:

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
  revoked_at,
  auth_internal.base64url_encode(public_key) AS x_from_row
FROM ai_internal.installation_keys
WHERE is_deleted = false;
```

**Expect:** exactly one row. `kid = K0`, `installation_id = I0`, `algorithm = 'EdDSA'`, `has_secret = true`, `public_len = 32`, `secret_len = 64`, `created_by` and `updated_by` equal BOOT’s `auth_user_id`, `valid_from` is now, `revoked_at IS NULL`, `x_from_row` equals RPC `public_jwk.x`. The private key exists only in this row.

**Do:** as the same authenticated bootstrap admin, `SELECT * FROM ai_internal.installation_keys;`

**Expect:** denied (no schema `USAGE` / RLS deny-all). Clients cannot read the stamp out of the drawer.

**Do:** as doctor, `SELECT public.get_ai_availability();`

**Expect:** still `{ "enrolled": false, "platform_base_url": null }`. `enroll_installation_keypair` does not touch `app_settings`.

---

#### 8.3.5 Second enroll while active key exists

**Do:** as **bootstrap administrator (BOOT)**, with **K0** still active from [§8.3.4](#834-first-enroll-happy-path):

```sql
SELECT public.enroll_installation_keypair();
```

**Expect:** `success = false`, `error_code = 'ALREADY_ENROLLED'`. As `postgres`, still exactly one non-deleted row with `kid = K0` and `revoked_at IS NULL`. Use `rotate_installation_key()` for a new signing key while any active key remains.

---

#### 8.3.6 Key rotation via `rotate_installation_key` (happy path)

**Do:** as **administrator** (different `auth_user_id` from BOOT):

```sql
SELECT public.rotate_installation_key();
```

**Expect:** `success = true`. New `kid` (**K1** ≠ **K0**). **Same** `installation_id` **I0**. `data` matches [§3.1](#31-api-publicrotate_installation_key) (`kid`, `installation_id`, `public_jwk` with `kty`, `crv`, `x`, `kid`). Two rows in `installation_keys`, both with `revoked_at IS NULL`. This is the production rotation path — do **not** call `enroll_installation_keypair()` while an active key exists ([§8.3.5](#835-second-enroll-while-active-key-exists)).

---

#### 8.3.7 Revoke installation key (happy path)

**Do:** as **bootstrap administrator (BOOT)**, revoke the first key:

```sql
SELECT public.revoke_installation_key('K0');
```

**Expect:** `success = true`, `data.kid = 'K0'`, `data.revoked_at` equals the **stored** `revoked_at` on the K0 row (same value as `SELECT revoked_at FROM ai_internal.installation_keys WHERE kid = 'K0'`). As `postgres`, the K0 row has `revoked_at IS NOT NULL`; K1 is still unrevoked.

**Do:** call `revoke_installation_key('K0')` again.

**Expect:** `success = true` with the **same** `revoked_at` as the first call (idempotent).

**Do:** as **doctor**, `SELECT public.revoke_installation_key('');`

**Expect:** `success = false`, `error_code = 'INVALID_INPUT'`.

**Do:** as **bootstrap administrator (BOOT)**, `SELECT public.revoke_installation_key('00000000-0000-0000-0000-000000000000');`

**Expect:** `success = false`, `error_code = 'KEY_NOT_FOUND'`.

**Do:** mint an AAT as doctor. Decode header `kid`. If it is **K0**, `SELECT auth_internal.verify_aat('<token>');` must be `false`. Mint again (or use a token with **K1**) — `verify_aat` is `true` while K1 remains unrevoked.

**Do:** as **bootstrap administrator (BOOT)**, attempt to revoke the last active key:

```sql
SELECT public.revoke_installation_key('K1');
```

**Expect:** `success = false`, `error_code = 'CANNOT_REVOKE_LAST_ACTIVE_KEY'`, message *Cannot revoke the last active installation key. Rotate a replacement key first.* As `postgres`, **K1** still has `revoked_at IS NULL`. Normal rotation retires old keys only after a successor exists ([§8.3.14](#8314-cannot-revoke-last-active-key)).

---

#### 8.3.8 Rotate before enroll fails (`INSTALLATION_NOT_ENROLLED`)

Empty-keystore guard for `rotate_installation_key()`. **Performed in [§8.3.3](#833-enroll-failure-paths)** before first enroll so the probe sequence stays top-to-bottom without a mid-run reset.

---

#### 8.3.9 Single-installation trigger (failure path)

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

**Expect:** `SINGLE_INSTALLATION_VIOLATION` (`P0001`). Active rows still share one `installation_id` (**I0**).

---

#### 8.3.10 Mint an AAT from this key (happy path for the handoff fields)

**Do:** as doctor with `ai.*`, `SELECT public.issue_ai_token();`

**Expect:** `success = true` and a JWS. Decode header and payload:

- Header `alg = EdDSA`
- Header `kid` is an unrevoked key (**K1** if K0 was revoked in [§8.3.7](#837-revoke-installation-key-happy-path))
- Payload `iss` = **I0**

This is Stage 6 using the key this stage minted. `enroll_installation_keypair` itself still does not return a token.

---

#### 8.3.11 Platform does not know the clinic yet

Do **not** call Stage 3 yet.

**Do:** inspect local D1 for **I0**:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id FROM installation WHERE installation_id = '<I0>'"
```

**Expect:** no row. The platform did not assign or poll `installation_id`.

**Do:** `POST /v1/requests` to the local Worker with the AAT from [§8.3.10](#8310-mint-an-aat-from-this-key-happy-path-for-the-handoff-fields) as `Authorization: Bearer`.

**Expect:** identity failure (`unauthenticated`). Same shape as retiring a token-contract version then invoking: the border guard has no file for this passport.

---

#### 8.3.12 Stage 3 enroll using this RPC’s output (happy path §6)

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
    "plan": "standard",
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

---

#### 8.3.13 Availability flag after the key exists

**Do:** as **bootstrap administrator (BOOT)** after Stage 3 platform enroll returns `platform_base_url`:

```sql
SELECT public.set_ai_availability(true, 'http://127.0.0.1:8787');
SELECT public.get_ai_availability();
```

**Expect:** `set_ai_availability` returns `success = true`, `data = {"enrolled": true, "platform_base_url": "http://127.0.0.1:8787"}`. `get_ai_availability()` returns the same plain `jsonb` for **doctor** as well as administrators.

**Do:** open the Flutter AI surface.

**Expect:** AI chrome is no longer hidden for non-enrollment. The client may `GET {platform_base_url}/health`. It still must not treat Worker reachability as a substitute for this flag (the flag was already true before any probe).

**Do:** `POST /v1/requests` with a valid AAT, still without Stage 4 entitle.

**Expect:** still not entitled. The availability flag does not grant quotas.

---

#### 8.3.14 Cannot revoke last active key

The revoke API enforces at least one active key per installation. After [§8.3.7](#837-revoke-installation-key-happy-path) revokes **K0**, **K1** is the sole active key — `revoke_installation_key('K1')` must fail with `CANNOT_REVOKE_LAST_ACTIVE_KEY` (probe performed there).

**Do:** as **bootstrap administrator (BOOT)**, with only **K1** still active, call `revoke_installation_key('K1')` again if needed.

**Expect:** same failure. Operators rotate first (`rotate_installation_key()` → **K2**), revoke **K1**, and may revoke **K0** if still present — never the last unrevoked key via RPC.

---

#### 8.3.15 Recovery re-enroll after all keys revoked (postgres simulation)

Recovery re-enroll (`enroll_installation_keypair` when no active key remains) is **not** reachable by revoking every key through the API ([§8.3.14](#8314-cannot-revoke-last-active-key)). Simulate disaster recovery as `postgres`:

**Do:** stamp `revoked_at` on every non-deleted row (including **K1**):

```sql
UPDATE ai_internal.installation_keys
SET revoked_at = clock_timestamp()
WHERE is_deleted = false AND revoked_at IS NULL;

SELECT count(*) FROM ai_internal.installation_keys
WHERE is_deleted = false AND revoked_at IS NULL;
```

**Expect:** count = 0.

**Do:** as **bootstrap administrator (BOOT)**:

```sql
SELECT public.enroll_installation_keypair();
```

**Expect:** `success = true`. **Same** `installation_id` **I0**. New `kid` (**Kx** ≠ **K0**, **K1**). As `postgres`, exactly one active row (`revoked_at IS NULL`). This is the recovery path when every prior key has been revoked outside normal revoke RPC flow.

---

#### 8.3.16 Rotate succeeds when every key is revoked

Same zero-active state as [§8.3.15](#8315-recovery-re-enroll-after-all-keys-revoked-postgres-simulation) — rows exist under **I0**, all with `revoked_at` set (not an empty keystore).

**Do:** as **administrator**, without calling `enroll_installation_keypair()`:

```sql
SELECT public.rotate_installation_key();
```

**Expect:** `success = true`. **Same** `installation_id` **I0**. New `kid` (**Kr**). Rotate’s lookup selects any non-deleted row (no `revoked_at` filter), so rotation proceeds even when every existing key is revoked — the authoritative recovery path alongside re-enroll. `INSTALLATION_NOT_ENROLLED` fires only when no non-deleted rows exist ([§8.3.8](#838-rotate-before-enroll-fails-installation_not_enrolled)).
