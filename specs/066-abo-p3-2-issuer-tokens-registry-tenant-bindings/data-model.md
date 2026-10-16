# Data Model: P3.2 issuer keys, tenant bindings, and installation

**Unit**: P3.2

Vendor D1 on the existing `DB` binding. Clinic PostgreSQL is unchanged. `installation` is not altered and is not dropped. `plan` and `entitlement` stay. Wire shapes are in `contracts/`.

## 1. `issuer_key`

New table. One row per issuer `kid`. (FR-001, 03 §3.2)

| Column | Type | Rule |
| --- | --- | --- |
| `kid` | TEXT primary key | Caller-supplied. Not rewritten to a UUID. |
| `issuer` | TEXT NOT NULL | The configured `ISSUER_ID` at register time. |
| `public_key` | TEXT NOT NULL | The base64url encoding of the raw 32-byte Ed25519 public key, stored unchanged. |
| `status` | TEXT NOT NULL | `active`, `retiring`, or `revoked`. `registerIssuerKey` inserts `active`. `retireIssuerKey` is the only writer of `retiring`. `revokeIssuerKey` sets `revoked`. |
| `not_before` | TEXT NOT NULL | ISO-8601 UTC from the register input. |
| `not_after` | TEXT NOT NULL | ISO-8601 UTC from the register input. A retiring `kid` is accepted while `not_before` ≤ now < `not_after`. |
| `registered_by` | TEXT NOT NULL | The Access email of the registering call. |
| `assertion_sha256` | TEXT NOT NULL | The assertion challenge hash of the registering call. |

No `created_at` column. This unit does not add one.

## 2. `tenant_binding`

New table. The platform clinic binding for an org. (FR-007, FR-008, 03 §3.2)

| Column | Type | Rule |
| --- | --- | --- |
| `org_id` | TEXT NOT NULL | The token `org` claim. |
| `installation_id` | TEXT NOT NULL | The platform clinic UUID created with the binding. |
| `epoch` | INTEGER NOT NULL | `1` for the first binding of an org. Later re-creation uses a higher epoch. This unit only inserts `1`. |
| `status` | TEXT NOT NULL | `active`, `held_for_transfer`, or `retired`. The first binding is `active`. This unit does not write `held_for_transfer` or `retired`. |
| `retired_at` | TEXT | Null on the first binding. |
| `reason` | TEXT | Null on the first binding. |
| `created_at` | TEXT NOT NULL | The UTC ISO-8601 time of the insert. The 50-per-day cap counts rows with `epoch` `1` whose `created_at` falls in the last 24 hours. |

Primary key is `(org_id, epoch)`.

A partial unique index `tenant_binding_one_live_org` on `org_id` WHERE `status` IN (`active`, `held_for_transfer`) allows at most one live binding per org. This unit only inserts `active` at epoch `1`.

## 3. `installation`

Existing table. No migration changes its columns. The row is never removed. (FR-009, 03 §3.2)

The first valid token for an unknown org inserts:

| Column | Value |
| --- | --- |
| `installation_id` | A new platform clinic UUID (`crypto.randomUUID()`). |
| `org_id` | The token `org` claim. |
| `status` | `active` |
| `display_name` | `""` |
| `region` | `""` |
| `enrolled_at` | The same UTC ISO-8601 instant stored on the binding's `created_at`. |

`Principal.installationId` is the binding's `installation_id`, not the token `iss`.

## 4. `token_contract`

Existing table. This unit does not change its columns. The new migration retires version `1` and inserts version `2` with `retired_at` null. (FR-005)

## 5. `installation_key`

Dropped by the new migration. Existing migrations are not edited. `INSTALLATION_KEY_TTL_DAYS` is removed with the enroll, rotate, and revoke-key handlers. (FR-015)

## 6. Unchanged tables

`plan`, `entitlement`, `operator_credential`, `assertion_used`, `platform_alert`, and `control_audit` keep their current columns. `platform_alert.next_send_at` records the AL-20 daily repeat. No new alert column.
