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

---




## 1. Plain language

A staff member with AI permissions requests a short-lived signed token. Supabase signs it with the clinic private key. The platform never sees the private key — only verifies with the enrolled public key.

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
| `exp`    | number   | `iat + lifetime_minutes * 60`             | `exp`                                 | Expires at — when the token stops being valid (Unix timestamp)          |
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

See [§5 Stage 2 — Identity](11-stage-9-the-guard.md#5-stage-2-identity) for every check and failure.
