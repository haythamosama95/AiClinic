# AI Platform Data Journey — Complete D1 Column Reference

## Table of Contents

1. [1. `installation`](#1-installation)
2. [2. `installation_key`](#2-installation_key)
3. [3. `entitlement`](#3-entitlement)
4. [4. `capability_grant`](#4-capability_grant)
5. [5. `routing_policy`](#5-routing_policy)
6. [6. `kill_switch`](#6-kill_switch)
7. [7. `token_contract`](#7-token_contract)
8. [8. `ai_request`](#8-ai_request)
9. [9. `ai_attempt`](#9-ai_attempt)
10. [10. `usage_event`](#10-usage_event)
11. [11. `usage_rollup`](#11-usage_rollup)
12. [12. `platform_counter`](#12-platform_counter)
13. [13. `control_audit`](#13-control_audit)

---

Quick lookup for every table. For narrative, see stages above and [07-ai-platform-d1-r2-storage.md](../07-ai-platform-d1-r2-storage.md).

## 1. `installation`


| Column            | Type     | Meaning                            |
| ----------------- | -------- | ---------------------------------- |
| `installation_id` | TEXT PK  | Clinic deployment id               |
| `org_id`          | TEXT     | Organization UUID                  |
| `display_name`    | TEXT     | Human label                        |
| `status`          | TEXT     | `active` / `suspended` / `deleted` |
| `region`          | TEXT     | Declared region                    |
| `enrolled_at`     | TEXT ISO | Enrollment timestamp               |




## 2. `installation_key`


| Column            | Type      | Meaning                    |
| ----------------- | --------- | -------------------------- |
| `key_id`          | TEXT PK   | AAT header `kid`           |
| `installation_id` | TEXT FK   | Owner                      |
| `public_key`      | TEXT      | Ed25519 public (base64url) |
| `algorithm`       | TEXT      | e.g. `EdDSA`               |
| `valid_from`      | TEXT ISO  | Key valid from             |
| `valid_until`     | TEXT NULL | Optional expiry            |
| `revoked_at`      | TEXT NULL | Revocation timestamp       |




## 3. `entitlement`


| Column                 | Type     | Meaning                      |
| ---------------------- | -------- | ---------------------------- |
| `entitlement_id`       | TEXT PK  | UUID                         |
| `installation_id`      | TEXT FK  | One row per installation     |
| `plan`                 | TEXT     | `starter`…`enterprise`       |
| `period_start`         | TEXT ISO | Billing period start         |
| `period_end`           | TEXT ISO | Billing period end           |
| `request_quota`        | INTEGER  | Max requests per period      |
| `token_budget`         | INTEGER  | Max tokens per period        |
| `cost_budget`          | REAL     | Max cost per period          |
| `allowed_capabilities` | TEXT     | JSON array of capability ids |
| `soft_threshold`       | REAL     | Degrade fraction [0,1]       |
| `status`               | TEXT     | `pending` / `active`         |




## 4. `capability_grant`


| Column               | Type      | Meaning                                      |
| -------------------- | --------- | -------------------------------------------- |
| `grant_id`           | TEXT PK   | UUID                                         |
| `scope`              | TEXT      | `installation:{id}`, `plan:{tier}`, `global` |
| `capability_id`      | TEXT      | e.g. `clinic.visit_summary`                  |
| `capability_version` | TEXT      | e.g. `1.0.0`                                 |
| `granted_at`         | TEXT ISO  | Grant time                                   |
| `revoked_at`         | TEXT NULL | Non-null = inactive                          |
| `changed_at`         | TEXT ISO  | Last mutation                                |
| `changed_by`         | TEXT      | Operator id                                  |
| `lifecycle_state`    | TEXT NULL | Global overlay: active/deprecated/retired    |
| `successor_id`       | TEXT NULL | Migration target                             |
| `deprecated_at`      | TEXT NULL | Deprecation time                             |
| `retire_after`       | TEXT NULL | Hard retire-after                            |




## 5. `routing_policy`


| Column                    | Type         | Meaning                                    |
| ------------------------- | ------------ | ------------------------------------------ |
| `policy_id`               | TEXT PK part | e.g. `standard`                            |
| `version`                 | TEXT PK part | e.g. `1`                                   |
| `content_pointer`         | TEXT         | R2 key                                     |
| `active_from`             | TEXT ISO     | Activation time                            |
| `activated_by`            | TEXT         | Operator id                                |
| `canary_installation_ids` | TEXT NULL    | JSON array                                 |
| `status`                  | TEXT         | `published`/`canary`/`active`/`superseded` |




## 6. `kill_switch`


| Column       | Type         | Meaning                                         |
| ------------ | ------------ | ----------------------------------------------- |
| `scope`      | TEXT PK part | `global`/`capability`/`installation`/`provider` |
| `target`     | TEXT PK part | Scope-specific id                               |
| `active`     | INTEGER      | `1` = on (fail closed)                          |
| `changed_at` | TEXT ISO     | Last change                                     |
| `changed_by` | TEXT         | Actor (no HTTP API — direct D1)                 |




## 7. `token_contract`


| Column       | Type      | Meaning         |
| ------------ | --------- | --------------- |
| `ver`        | TEXT PK   | AAT `ver` claim |
| `added_at`   | TEXT ISO  | Accepted at     |
| `retired_at` | TEXT NULL | Retired at      |
| `changed_by` | TEXT      | Operator id     |




## 8. `ai_request`


| Column                 | Type         | Meaning                          |
| ---------------------- | ------------ | -------------------------------- |
| `request_id`           | TEXT PK      | Internal ULID                    |
| `request_reference`    | TEXT UNIQUE  | Client handle `XXXX-XXXX`        |
| `installation_id`      | TEXT FK      | Submitter                        |
| `actor_id`             | TEXT         | Staff from AAT `sub`             |
| `branch_id`            | TEXT NULL    | Branch scope                     |
| `capability_id`        | TEXT         | Invoked capability               |
| `capability_version`   | TEXT         | Invoked version                  |
| `prompt_artifact_hash` | TEXT         | Manifest artifact ref at insert  |
| `idempotency_key`      | TEXT         | Header value                     |
| `state`                | TEXT         | `Accepted` → terminal states     |
| `created_at`           | TEXT ISO     | Insert time                      |
| `updated_at`           | TEXT ISO     | Last transition                  |
| `completed_at`         | TEXT NULL    | Terminal time                    |
| `terminal_error_code`  | TEXT NULL    | On `Failed`                      |
| `trace_id`             | TEXT         | Correlation id                   |
| `payload_pointer`      | TEXT NULL    | R2 envelope key                  |
| `routing_tier`         | TEXT NULL    | `standard` / `degraded`          |
| `routing_decision`     | TEXT NULL    | Column exists; not written today |
| `conversation_id`      | TEXT NULL    | Conversational only              |
| `turn_ordinal`         | INTEGER NULL | Turn order                       |




## 9. `ai_attempt`


| Column                | Type      | Meaning                    |
| --------------------- | --------- | -------------------------- |
| `attempt_id`          | TEXT PK   | ULID                       |
| `request_id`          | TEXT FK   | Parent request             |
| `attempt_no`          | INTEGER   | 1-based sequence           |
| `provider`            | TEXT      | `deepseek`/`gemini`/`fake` |
| `model`               | TEXT      | Model id                   |
| `outcome`             | TEXT      | Attempt label              |
| `latency_ms`          | INTEGER   | Round-trip ms              |
| `tokens_in`           | INTEGER   | Input tokens               |
| `tokens_out`          | INTEGER   | Output tokens              |
| `cost`                | REAL      | Attempt cost               |
| `provider_request_id` | TEXT NULL | Provider-side id           |
| `error_code`          | TEXT NULL | Taxonomy on failure        |




## 10. `usage_event`


| Column            | Type         | Meaning                   |
| ----------------- | ------------ | ------------------------- |
| `usage_event_id`  | TEXT PK      | ULID                      |
| `installation_id` | TEXT FK      | Billed installation       |
| `period`          | TEXT         | `YYYY-MM`                 |
| `request_id`      | TEXT NULL FK | SET NULL on journal purge |
| `quota_weight`    | INTEGER      | Manifest weight           |
| `tokens`          | INTEGER      | Total tokens              |
| `cost`            | REAL         | Total cost                |
| `recorded_at`     | TEXT ISO     | Ledger time               |




## 11. `usage_rollup`


| Column          | Type    | Meaning                        |
| --------------- | ------- | ------------------------------ |
| `rollup_id`     | TEXT PK | Hash of dimensions JSON        |
| `dimensions`    | TEXT    | `{"installation_id","period"}` |
| `request_count` | INTEGER | Aggregated count               |
| `tokens`        | INTEGER | Sum tokens                     |
| `cost`          | REAL    | Sum cost                       |




## 12. `platform_counter`


| Column          | Type    | Meaning                      |
| --------------- | ------- | ---------------------------- |
| `counter_id`    | TEXT PK | Hash of bucket + dimensions  |
| `dimension_set` | TEXT    | JSON error/installation keys |
| `time_bucket`   | TEXT    | Minute bucket ISO            |
| `count`         | INTEGER | Rejection count              |




## 13. `control_audit`


| Column           | Type      | Meaning                                            |
| ---------------- | --------- | -------------------------------------------------- |
| `audit_id`       | TEXT PK   | UUID                                               |
| `operator_id`    | TEXT      | `OPERATOR_ID`                                      |
| `action`         | TEXT      | e.g. `enroll`, `entitle`, `routing_policy_publish` |
| `target`         | TEXT      | Entity id                                          |
| `before_pointer` | TEXT NULL | Prior state ref                                    |
| `after_pointer`  | TEXT NULL | New state ref                                      |
| `recorded_at`    | TEXT ISO  | Audit time                                         |


---
