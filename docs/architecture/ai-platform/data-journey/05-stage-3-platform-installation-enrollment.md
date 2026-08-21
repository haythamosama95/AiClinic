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
