# Data Model: P3.1 operator credentials, assertion use, audit, and platform alerts

**Unit**: P3.1

Vendor D1 on the existing `DB` binding. Clinic PostgreSQL is unchanged. Wire shapes are in `contracts/`.

## 1. `operator_credential`

New table. One row per passkey. (FR-009, 03 §3.2)

| Column | Type | Rule |
| --- | --- | --- |
| `credential_id` | TEXT primary key | Caller-supplied. The consumed attestation parser returns `alg` and the public key only, so the id is a method argument. |
| `operator_email` | TEXT NOT NULL | The Access email verified on the registering call. |
| `public_key_cose` | TEXT NOT NULL | Base64url of the attestation public-key bytes the consumed parser accepts: SPKI for ES256, raw 32 bytes for EdDSA. The column name is the spec's. The bytes stay in that form so `parseRegistrationAttestation` can import them again. |
| `alg` | TEXT NOT NULL | `ES256` or `EdDSA`. |
| `status` | TEXT NOT NULL | `pending`, `active`, or `revoked`. Insert is `pending`. The signer read and `listOperatorCredentials` are the only `pending` → `active` writes, and only when `activates_at` is at or before now. Revoke sets `revoked`. |
| `activates_at` | TEXT NOT NULL | ISO-8601 UTC, 24 hours after the clock module's now at insert. |
| `approved_by` | TEXT | Null on bootstrap. Otherwise the Access email of the approving assertion. |
| `revoked_by` | TEXT | Null until revoke, then the Access email of that call. |

## 2. `assertion_used`

New table. Single-use guard. (FR-010, 03 §3.2)

| Column | Type | Rule |
| --- | --- | --- |
| `challenge_sha256` | TEXT primary key | Hex SHA-256 of the canonical operation object, the same digest `operationChallenge` base64url-encodes. |
| `credential_id` | TEXT NOT NULL | `signer_credential_id` of the call that consumed the assertion. |
| `used_at` | TEXT NOT NULL | ISO-8601 UTC from the clock module. |

A replay finds the primary key and is `rejected` with code `assertion_used`. The insert happens only after the signer is active and the assertion checks have passed. `credential_not_active`, `assertion_expired`, `actor_email_mismatch`, `credential_revoked`, and `credential_not_found` do not insert a row, so E2E-P3.1-02 can repeat the same assertion after the clock moves.

The design note that rows are swept after a day is not a `*/5` job in this unit. The cron branch is alert retry and the heartbeat ping.

## 3. `control_audit`

Existing table. This unit adds two nullable columns and leaves `operator_id` in place so `/control/*` inserts keep their column list (rule S9). (FR-012, 03 §3.2)

| Column | Change |
| --- | --- |
| `actor` | Added, TEXT, nullable. H/HP calls that pass the Access JWT check store the Access email here. |
| `assertion_sha256` | Added, TEXT, nullable. Hex SHA-256 of the canonical operation when the call had an assertion. Null for bootstrap, which has no assertion. |
| `operator_id` | Unchanged, NOT NULL. `writeEntrypointAudit` sets it to the same Access email. Existing `writeAudit` is unchanged. |

A missing, expired, or wrong-`aud` Access JWT writes no row. A `contract_version` refusal writes no row. Every other H/HP call that passed the JWT check writes a row, including a later `rejected` result.

`action` is the method name. `target` is the method's `credential_id`.

## 4. `platform_alert`

New table. Same columns as the ABO `alert` (03 §3.2, 03 §2.10). (FR-019)

| Column | Type | Rule |
| --- | --- | --- |
| `alert_key` | TEXT primary key | Code plus subject. AL-13 uses `AL-13:` + `credential_id` + `:` + `bootstrap`, `register`, or `revoke`. A failed `*/5` job uses `scheduled_job_failed:` + the job name. |
| `code` | TEXT NOT NULL | `AL-13` or `scheduled_job_failed`. |
| `severity` | TEXT NOT NULL | `high` for every row this unit inserts. The copied shape requires the column; this unit does not grade a second severity. |
| `first_at` | TEXT NOT NULL | ISO-8601 UTC from the clock module. |
| `last_at` | TEXT NOT NULL | Updated when a duplicate `alert_key` is raised again. |
| `count` | INTEGER NOT NULL | Starts at 1. A duplicate key increments it and does not insert a second row. |
| `send_state` | TEXT NOT NULL | `unsent` or `sent`. |
| `next_send_at` | TEXT | Clock time of the last failed send. The `*/5` retry selects `send_state = unsent`. |
| `resolved_at` | TEXT | Null. This unit does not resolve alerts. |

`send_email` throwing leaves `send_state` `unsent`. The next `*/5` run sends that row once and sets `sent`. AL-13's repeat is once, so a `sent` row is not sent again. The email text is rebuilt from the key at send time (`contracts/alert-body.md`), so the retry carries the same codes, ids, and decoded operation without a body column the ABO shape does not have.
