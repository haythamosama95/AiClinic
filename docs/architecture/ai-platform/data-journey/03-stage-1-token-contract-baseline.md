# AI Platform Data Journey — Stage 1 — Token contract baseline

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [D1 row (`token_contract`)](#3-d1-row-token_contract)
4. [Control-plane token-contract rotation](#4-control-plane-token-contract-rotation)
   - [`POST /control/token-contract/begin-rotation`](#41-post-controltoken-contractbegin-rotation)
   - [`POST /control/token-contract/retire`](#42-post-controltoken-contractretire)
5. [Runtime consumption (identity stage 2)](#5-runtime-consumption-identity-stage-2)

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



### 4.1 `POST /control/token-contract/begin-rotation`

**Request:**

```json
{ "ver": "<new version string>" }
```


| Field | Required       | Meaning                   |
| ----- | -------------- | ------------------------- |
| `ver` | yes, non-empty | New AAT version to accept |


**Success (200):** `{ "ver": "<ver>" }`

**D1 writes:** INSERT `token_contract` if fewer than 2 non-retired versions exist.


| Failure | `error`                 | Triggering field                        |
| ------- | ----------------------- | --------------------------------------- |
| 401     | `unauthorized`          | Missing/invalid `OPERATOR_BEARER_TOKEN` |
| 400     | `invalid_ver`           | Empty `ver`                             |
| 409     | `ver_already_exists`    | `ver` already in table                  |
| 409     | `rotation_already_open` | Already 2 accepted versions             |




### 4.2 `POST /control/token-contract/retire`

**Request:** `{ "ver": "<version>" }`

**Success (200):** `{ "ver": "<ver>", "retired_at": "<ISO>" }`


| Failure | `error`               | Trigger                        |
| ------- | --------------------- | ------------------------------ |
| 404     | `ver_not_found`       | `ver` not in table             |
| 409     | `ver_already_retired` | `retired_at` already set       |
| 409     | `no_rotation_open`    | Only one accepted version left |




## 5. Runtime consumption (identity stage 2)

After signature verify, load `token_contracts:{payload.ver}`:


| D1 state             | Result            |
| -------------------- | ----------------- |
| Row missing          | `unauthenticated` |
| `retired_at != null` | `unauthenticated` |
| `retired_at == null` | Continue          |


**AAT field:** `ver` (string, required in JWT payload).

---

