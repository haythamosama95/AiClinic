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
14. [14. `grace_admission_queue`](#14-grace_admission_queue)
15. [Behavioral verification](#15-behavioral-verification)
   - [15.1 Setup](#151-setup)
   - [15.2 Coverage](#152-coverage)
   - [15.3 Ordered probes](#153-ordered-probes)
     - [15.3.1 Inspect schema (all 14 tables)](#1531-inspect-schema-all-14-tables)
     - [15.3.2 Clients cannot read D1](#1532-clients-cannot-read-d1)
     - [15.3.3 Enroll writes installation, key, and pending entitlement](#1533-enroll-writes-installation-key-and-pending-entitlement)
     - [15.3.4 Entitle writes budgets and live grants](#1534-entitle-writes-budgets-and-live-grants)
     - [15.3.5 Rotate, revoke, suspend, resume, and delete](#1535-rotate-revoke-suspend-resume-and-delete)
     - [15.3.6 Routing policy publish, canary, promote, rollback](#1536-routing-policy-publish-canary-promote-rollback)
     - [15.3.7 Token contract, capability overlay, and kill switch](#1537-token-contract-capability-overlay-and-kill-switch)
     - [15.3.8 Happy-path request (journal, attempts, usage)](#1538-happy-path-request-journal-attempts-usage)
     - [15.3.9 Guard rejection, valid_until, Failed, conversational NULLs](#1539-guard-rejection-valid_until-failed-conversational-nulls)
     - [15.3.10 Crons: counters, rollup, retention, grace](#15310-crons-counters-rollup-retention-grace)

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
| `valid_until`     | TEXT NULL | Hard expiry; enroll/rotate set `valid_from` + 365 days. Identity rejects `now >= valid_until` |
| `revoked_at`      | TEXT NULL | Revocation timestamp       |




## 3. `entitlement`


| Column                 | Type     | Meaning                      |
| ---------------------- | -------- | ---------------------------- |
| `entitlement_id`       | TEXT PK  | UUID                         |
| `installation_id`      | TEXT FK UNIQUE | One row per installation (`idx_entitlement_installation_id`) |
| `plan`                 | TEXT     | `starter`…`enterprise`       |
| `period_start`         | TEXT ISO | Billing period start (entitle: ISO-8601 UTC instant, `< period_end`) |
| `period_end`           | TEXT ISO | Billing period end (entitle: ISO-8601 UTC instant, `> period_start`) |
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
| `version`                 | TEXT PK part | e.g. `1`. Latest-version selection is `active_from DESC, rowid DESC`, not lexical TEXT `version` |
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
| `prompt_artifact_hash` | TEXT         | Composer `promptVersion`: content hash of resolved prompt-artifact bytes at insert |
| `idempotency_key`      | TEXT         | Header value                     |
| `state`                | TEXT         | `Accepted` → terminal states     |
| `created_at`           | TEXT ISO     | Insert time                      |
| `updated_at`           | TEXT ISO     | Last transition                  |
| `completed_at`         | TEXT NULL    | Terminal time                    |
| `terminal_error_code`  | TEXT NULL    | On `Failed`                      |
| `trace_id`             | TEXT         | Correlation id                   |
| `payload_pointer`      | TEXT NULL    | R2 envelope key                  |
| `routing_tier`         | TEXT NULL    | `standard` / `degraded`          |
| `routing_decision`     | TEXT NULL    | JSON `RoutingDecision` written at Stage 10 after routing (selected rule, chain, excluded targets with reasons, override provenance). `NULL` at INSERT. |
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
| `outcome`             | TEXT      | Attempt label (`success`, `truncation`, `retryable_failure`, `terminal_failure`, `timeout`, `repair`). `dashboardRepairRateByCapability` counts `repair` rows as the numerator. |
| `latency_ms`          | INTEGER   | Round-trip ms              |
| `tokens_in`           | INTEGER   | Input tokens               |
| `tokens_out`          | INTEGER   | Output tokens              |
| `cost`                | REAL      | Attempt cost from `priceUsage` (tokens × per-1K rates) |
| `provider_request_id` | TEXT NULL | Provider-side id           |
| `error_code`          | TEXT NULL | Taxonomy on failure        |




## 10. `usage_event`


| Column            | Type         | Meaning                   |
| ----------------- | ------------ | ------------------------- |
| `usage_event_id`  | TEXT PK      | ULID                      |
| `installation_id` | TEXT FK      | Billed installation       |
| `period`          | TEXT         | `YYYY-MM` from admission-time entitlement `period_start`, not wall-clock at credit |
| `request_id`      | TEXT NULL FK | SET NULL on journal purge so ledger money rows survive. Aged usage permanently loses request-level joinability; reconciliation `LEFT JOIN` on `request_id` can never match those rows, so coverage shrinks with age. |
| `quota_weight`    | INTEGER      | Manifest weight           |
| `tokens`          | INTEGER      | Total tokens              |
| `cost`            | REAL         | Total cost from the same helper as `ai_attempt.cost` |
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

Guard-rejection tallies. `recordGuardRejection` increments an **in-isolate** map;
`flushRejectionCounters` (every cron tick) writes only that isolate's snapshot.
Tallies in other isolates are lost on eviction. **`count` is a lower bound, not an
exact rejection count.** Dashboards that consume this table
(`dashboardQuotaRejectionRate`) inherit the same lower-bound semantics. An accurate
count would flush at request end batched with the journal write — not implemented.


| Column          | Type    | Meaning                      |
| --------------- | ------- | ---------------------------- |
| `counter_id`    | TEXT PK | Hash of bucket + dimensions  |
| `dimension_set` | TEXT    | JSON error/installation keys |
| `time_bucket`   | TEXT    | Minute bucket ISO            |
| `count`         | INTEGER | Rejection **lower bound** (isolate-local flush; other isolates' tallies never reach D1) |




## 13. `control_audit`


| Column           | Type      | Meaning                                            |
| ---------------- | --------- | -------------------------------------------------- |
| `audit_id`       | TEXT PK   | UUID                                               |
| `operator_id`    | TEXT      | Single configured `OPERATOR_ID`. Every control action is attributed to this one identity; the trail cannot distinguish operators. |
| `action`         | TEXT      | e.g. `enroll`, `entitle`, `routing_policy_publish` |
| `target`         | TEXT      | Entity id                                          |
| `before_pointer` | TEXT NULL | Prior state ref                                    |
| `after_pointer`  | TEXT NULL | New state ref                                      |
| `recorded_at`    | TEXT ISO  | Audit time                                         |


## 14. `grace_admission_queue`

Durable grace-admission queue (Quota DO unavailable). Cron drains `pending` rows; the healthy path does not read this table.


| Column                       | Type         | Meaning                                              |
| ---------------------------- | ------------ | ---------------------------------------------------- |
| `grace_request_id`           | TEXT PK      | Worker UUID returned as `grace_admitted.requestId`   |
| `installation_id`            | TEXT FK      | Owner; cap is `COUNT(*)` pending per installation    |
| `idempotency_key`            | TEXT         | Client key; UNIQUE with `installation_id`            |
| `jti`                        | TEXT         | AAT jti, presented again at reconcile                |
| `request_reference`          | TEXT         | Original request reference                           |
| `entitlement_json`           | TEXT         | Entitlement snapshot at grace admit                  |
| `usage_tokens`               | INTEGER NULL | Attached at settlement; NULL until then              |
| `usage_cost`                 | REAL NULL    | Attached at settlement                               |
| `partial`                    | INTEGER NULL | `1` / `0` once usage is attached                     |
| `queued_at`                  | TEXT ISO     | Insert time                                          |
| `reconcile_attempts`         | INTEGER      | Failed cron presentations                            |
| `reconcile_first_seen_at_ms` | INTEGER NULL | First cron sighting (TTL origin)                     |
| `status`                     | TEXT         | `pending` / `reconciled` / `dropped`                 |


## 15. Behavioral verification

Live probes against a throwaway local Worker and its local D1. Each probe is an operator action and the D1 outcome you should see — not a unit test. Inspect with `wrangler d1 execute` (schema + rows). Populate with the real control APIs, `POST /v1/requests`, and crons that write each table. Run **[§15.3](#153-ordered-probes) top to bottom**. If every probe matches, this column reference is working.

Clients never open D1. The Worker is the only runtime writer; `wrangler` is the only operator inspect/SQL path. There is no clinic-Supabase or Flutter SELECT against these tables.

### 15.1 Setup

- Local Worker with D1 migrations applied: `cd ai-platform && npx wrangler d1 migrations apply ai-platform-development --local --env development`. Prefer a persist directory you can wipe. `wrangler dev` and `wrangler d1 execute --local` must share the same persist path (default `.wrangler/state`).
- Start the Worker with scheduled testing enabled (needed from [§15.3.10](#15310-crons-counters-rollup-retention-grace)):

```bash
cd ai-platform
npx wrangler dev --env development --test-scheduled
```

- `OPERATOR_BEARER_TOKEN` (`.dev.vars`) and `OPERATOR_ID` (`platform-operator` in `wrangler.toml` `[env.development.vars]`).
- Clinic `org_id` (UUID) and Stage 2 keypair output: `installation_id`, `kid`, `public_jwk.x`. A second org UUID for the lifecycle installation in [§15.3.5](#1535-rotate-revoke-suspend-resume-and-delete).
- Staff AAT from `issue_ai_token` (scope `ai.visit_summary`, role the visit-summary manifest allows). Use `plan: "standard"` (or higher) on enroll — visit summary `minimumPlanTier` is `standard`.
- Helper (run from `ai-platform/`):

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'

d1() {
  npx wrangler d1 execute ai-platform-development --local --env development --command "$1"
}
```

Trigger a cron after `--test-scheduled` (spaces as `+`):

```bash
curl -s "$GATEWAY/cdn-cgi/handler/scheduled?cron=0+4+*+*+*"
```

Use `cron=0+3+*+*+*` for retention, `cron=0+4+*+*+*` for rollup. Every tick also runs `flushRejectionCounters` then `reconcileGraceUsage`.

### 15.2 Coverage

Every table and every column claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| All 14 tables exist after migrations (`installation` … `grace_admission_queue`) | [§15.3.1](#1531-inspect-schema-all-14-tables) |
| `installation.installation_id` TEXT PK | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation.org_id` TEXT | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation.display_name` TEXT | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation.status` `active` / `suspended` / `deleted` | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.5](#1535-rotate-revoke-suspend-resume-and-delete) |
| `installation.region` TEXT | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation.enrolled_at` TEXT ISO | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation_key.key_id` TEXT PK (AAT `kid`) | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation_key.installation_id` TEXT FK | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation_key.public_key` TEXT base64url | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation_key.algorithm` TEXT e.g. `EdDSA` | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation_key.valid_from` TEXT ISO | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `installation_key.valid_until` TEXT NULL; enroll/rotate set `valid_from` + 365 days | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.5](#1535-rotate-revoke-suspend-resume-and-delete) |
| Identity rejects `now >= valid_until` | [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) |
| `installation_key.revoked_at` TEXT NULL | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.5](#1535-rotate-revoke-suspend-resume-and-delete) |
| `entitlement.entitlement_id` TEXT PK UUID | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `entitlement.installation_id` TEXT FK UNIQUE (`idx_entitlement_installation_id`) | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.plan` TEXT `starter`…`enterprise` | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `entitlement.period_start` TEXT ISO; entitle: UTC instant `< period_end` | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.period_end` TEXT ISO; entitle: UTC instant `> period_start` | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.request_quota` INTEGER | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.token_budget` INTEGER | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.cost_budget` REAL | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.allowed_capabilities` TEXT JSON array | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.soft_threshold` REAL [0,1] | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `entitlement.status` `pending` / `active` | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| Duplicate `entitlement.installation_id` INSERT fails UNIQUE | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `capability_grant.grant_id` TEXT PK UUID | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `capability_grant.scope` `installation:{id}` / `plan:{tier}` / `global` | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `capability_grant.capability_id` TEXT | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `capability_grant.capability_version` TEXT | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `capability_grant.granted_at` TEXT ISO | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `capability_grant.revoked_at` TEXT NULL (non-null = inactive) | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `capability_grant.changed_at` TEXT ISO | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `capability_grant.changed_by` TEXT operator id | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `capability_grant.lifecycle_state` TEXT NULL overlay active/deprecated/retired | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch), [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `lifecycle_state = 'active'` as a written overlay value | **Unprobeable** — no control route writes it; live grants leave the column NULL ([§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch)) |
| `capability_grant.successor_id` TEXT NULL | [§15.3.4](#1534-entitle-writes-budgets-and-live-grants), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `capability_grant.deprecated_at` TEXT NULL | [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `capability_grant.retire_after` TEXT NULL | [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch), [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `routing_policy.policy_id` TEXT PK part | [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `routing_policy.version` TEXT PK part; latest-version is `active_from DESC, rowid DESC`, not lexical TEXT | [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `routing_policy.content_pointer` TEXT R2 key | [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `routing_policy.active_from` TEXT ISO | [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `routing_policy.activated_by` TEXT operator id | [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `routing_policy.canary_installation_ids` TEXT NULL JSON array | [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `routing_policy.status` `published` / `canary` / `active` / `superseded` | [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `kill_switch.scope` TEXT PK part `global`/`capability`/`installation`/`provider` | [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `kill_switch.target` TEXT PK part | [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `kill_switch.active` INTEGER `1` = on (fail closed) | [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `kill_switch.changed_at` TEXT ISO | [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `kill_switch.changed_by` TEXT; no HTTP API — direct D1 | [§15.3.2](#1532-clients-cannot-read-d1), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `token_contract.ver` TEXT PK (AAT `ver`) | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `token_contract.added_at` TEXT ISO | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `token_contract.retired_at` TEXT NULL | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| `token_contract.changed_by` TEXT (`seed` then `OPERATOR_ID`) | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch) |
| Seed row `ver=1`, `added_at=2026-08-03T00:00:00.000Z`, `retired_at` NULL, `changed_by=seed` | [§15.3.1](#1531-inspect-schema-all-14-tables) |
| `ai_request.request_id` TEXT PK ULID | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.request_reference` TEXT UNIQUE `XXXX-XXXX` | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.installation_id` TEXT FK | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.actor_id` TEXT (AAT `sub`) | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.branch_id` TEXT NULL | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.capability_id` TEXT | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.capability_version` TEXT | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.prompt_artifact_hash` TEXT (composer `promptVersion`) | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.idempotency_key` TEXT | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.state` `Accepted` → terminal | [§15.3.8](#1538-happy-path-request-journal-attempts-usage), [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) |
| `ai_request.created_at` TEXT ISO | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.updated_at` TEXT ISO | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.completed_at` TEXT NULL (set on terminal) | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.terminal_error_code` TEXT NULL on `Failed` | [§15.3.8](#1538-happy-path-request-journal-attempts-usage), [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) |
| `ai_request.trace_id` TEXT | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.payload_pointer` TEXT NULL then R2 envelope key | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.routing_tier` TEXT NULL `standard` / `degraded` | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.routing_decision` JSON after routing; `NULL` at INSERT | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_request.conversation_id` TEXT NULL (conversational only) | [§15.3.8](#1538-happy-path-request-journal-attempts-usage), [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) |
| `ai_request.turn_ordinal` INTEGER NULL | [§15.3.8](#1538-happy-path-request-journal-attempts-usage), [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) |
| Non-null `conversation_id` / `turn_ordinal` | **Unprobeable** — only published capability is `single_shot` ([§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls)) |
| `ai_attempt.attempt_id` TEXT PK ULID | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.request_id` TEXT FK | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.attempt_no` INTEGER 1-based | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.provider` TEXT `deepseek`/`gemini`/`fake` | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.model` TEXT | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.outcome` `success` / `truncation` / `retryable_failure` / `terminal_failure` / `timeout` / `repair` | [§15.3.8](#1538-happy-path-request-journal-attempts-usage), [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) |
| `dashboardRepairRateByCapability` counts `outcome='repair'` as numerator | **Unprobeable write** — visit-summary `repairPolicy.allowed=false`; no published structured capability ([§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls)) |
| `ai_attempt.latency_ms` INTEGER | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.tokens_in` INTEGER | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.tokens_out` INTEGER | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.cost` REAL from `priceUsage` | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.provider_request_id` TEXT NULL | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `ai_attempt.error_code` TEXT NULL on failure | [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) |
| `usage_event.usage_event_id` TEXT PK ULID | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `usage_event.installation_id` TEXT FK | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `usage_event.period` `YYYY-MM` from admission-time `period_start`, not wall-clock at credit | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `usage_event.request_id` TEXT NULL FK; SET NULL on journal purge | [§15.3.8](#1538-happy-path-request-journal-attempts-usage), [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| Aged usage loses request-level joinability; reconciliation `LEFT JOIN` coverage shrinks | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `usage_event.quota_weight` INTEGER | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `usage_event.tokens` INTEGER | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `usage_event.cost` REAL (same helper as `ai_attempt.cost`) | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `usage_event.recorded_at` TEXT ISO | [§15.3.8](#1538-happy-path-request-journal-attempts-usage) |
| `usage_rollup.rollup_id` TEXT PK hash of dimensions JSON | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `usage_rollup.dimensions` TEXT `{"installation_id","period"}` | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `usage_rollup.request_count` INTEGER | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `usage_rollup.tokens` INTEGER | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `usage_rollup.cost` REAL | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `platform_counter.counter_id` TEXT PK hash of bucket + dimensions | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `platform_counter.dimension_set` TEXT JSON | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `platform_counter.time_bucket` TEXT minute bucket ISO | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `platform_counter.count` INTEGER lower bound (isolate-local flush) | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| Tallies in other isolates never reach D1 | **Unprobeable** on a single local isolate ([§15.3.10](#15310-crons-counters-rollup-retention-grace)) |
| `dashboardQuotaRejectionRate` inherits the same lower-bound semantics | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `control_audit.audit_id` TEXT PK UUID | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `control_audit.operator_id` single configured `OPERATOR_ID` | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `control_audit.action` e.g. `enroll`, `entitle`, `routing_policy_publish` | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants), [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `control_audit.target` TEXT entity id | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `control_audit.before_pointer` TEXT NULL | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.6](#1536-routing-policy-publish-canary-promote-rollback) |
| `control_audit.after_pointer` TEXT NULL | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement), [§15.3.4](#1534-entitle-writes-budgets-and-live-grants) |
| `control_audit.recorded_at` TEXT ISO | [§15.3.3](#1533-enroll-writes-installation-key-and-pending-entitlement) |
| `grace_admission_queue.grace_request_id` TEXT PK | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.installation_id` TEXT FK; cap is `COUNT(*)` pending | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.idempotency_key` TEXT; UNIQUE with `installation_id` | [§15.3.1](#1531-inspect-schema-all-14-tables), [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.jti` TEXT | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.request_reference` TEXT | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.entitlement_json` TEXT | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.usage_tokens` INTEGER NULL until settlement | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.usage_cost` REAL NULL | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.partial` INTEGER NULL `1`/`0` once usage attached | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.queued_at` TEXT ISO | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.reconcile_attempts` INTEGER | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.reconcile_first_seen_at_ms` INTEGER NULL | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| `grace_admission_queue.status` `pending` / `reconciled` / `dropped` | [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| Healthy path does not read `grace_admission_queue` | [§15.3.8](#1538-happy-path-request-journal-attempts-usage), [§15.3.10](#15310-crons-counters-rollup-retention-grace) |
| INSERT via `POST /v1/requests` while Quota DO is unavailable | **Unprobeable** on a healthy local DO — no operator knob to force `stub.fetch` 5xx ([§15.3.10](#15310-crons-counters-rollup-retention-grace)) |
| Settlement attach of `usage_tokens` / `usage_cost` / `partial` on a grace row | **Unprobeable** without that DO-down admit + credit ([§15.3.10](#15310-crons-counters-rollup-retention-grace)) |
| Clients cannot read D1; only Worker / wrangler | [§15.3.2](#1532-clients-cannot-read-d1) |


### 15.3 Ordered probes

#### 15.3.1 Inspect schema (all 14 tables)

**Do:** with migrations applied and the Worker using the same persist dir:

```bash
d1 "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"

for t in installation installation_key entitlement capability_grant routing_policy \
         kill_switch token_contract ai_request ai_attempt usage_event usage_rollup \
         platform_counter control_audit grace_admission_queue; do
  echo "=== $t ==="
  d1 "PRAGMA table_info($t)"
done

d1 "SELECT name, sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name"
d1 "SELECT ver, added_at, retired_at, changed_by FROM token_contract"
```

**Expect:** exactly these 14 platform tables (plus `d1_migrations`). `PRAGMA table_info` names and declared types match [§1](#1-installation)–[§14](#14-grace_admission_queue) and `ai-platform/migrations/*.sql`. In particular:

- `installation_key.valid_until`, `revoked_at` nullable
- `entitlement` has 11 columns; unique index `idx_entitlement_installation_id` on `installation_id`
- `capability_grant` includes overlay columns `lifecycle_state`, `successor_id`, `deprecated_at`, `retire_after`
- `routing_policy` PK `(policy_id, version)`; columns include `canary_installation_ids`, `status`
- `kill_switch` PK `(scope, target)`; `active` INTEGER
- `usage_event.request_id` nullable; `ON DELETE SET NULL`
- `ai_request.request_reference` unique index
- `grace_admission_queue` UNIQUE `(installation_id, idempotency_key)`
- Seed: one `token_contract` row `ver='1'`, `added_at='2026-08-03T00:00:00.000Z'`, `retired_at` NULL, `changed_by='seed'`

Empty clinic tables (`installation`, `ai_request`, …) are expected on a fresh persist dir. `kill_switch` has no seed rows.

#### 15.3.2 Clients cannot read D1

**Do:** as a clinic staff session (AAT, no operator bearer):

```bash
curl -s -o /dev/null -w "%{http_code}" "$GATEWAY/health"
curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $AAT" \
  "$GATEWAY/control/support/lookup?reference=AAAA-AAAA"
curl -s -o /dev/null -w "%{http_code}" \
  "$GATEWAY/control/support/lookup?reference=AAAA-AAAA"
curl -s -o /dev/null -w "%{http_code}" -X POST "$GATEWAY/d1/query"
```

**Expect:** no HTTP API returns `PRAGMA table_info` or `SELECT * FROM installation`. Staff AAT cannot call `/control/*` (401 `unauthorized`). Support lookup is operator-only and, when authorized, returns one request projection — not raw D1. Flutter/Supabase have no inbound path to this database. The only inspect tool is `wrangler d1 execute`. `kill_switch` has no HTTP writer either — next kill-switch write is wrangler SQL ([§15.3.7](#1537-token-contract-capability-overlay-and-kill-switch)).

#### 15.3.3 Enroll writes installation, key, and pending entitlement

**Do:** `POST /control/installations/$INSTALLATION_ID/enroll` with operator bearer (path id **I0**, body `kid` **K0**, `public_key` = Stage 2 `public_jwk.x`, `algorithm` `EdDSA`, `plan` `standard`, `org_id`, `display_name`, `region`):

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "org_id": "<org uuid>",
    "display_name": "Verify Clinic",
    "region": "local",
    "plan": "standard",
    "public_key": "<public_jwk.x>",
    "algorithm": "EdDSA",
    "kid": "<K0>"
  }'
```

**Do:** inspect:

```sql
SELECT installation_id, org_id, display_name, status, region, enrolled_at
FROM installation WHERE installation_id = '<I0>';

SELECT key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at
FROM installation_key WHERE installation_id = '<I0>';

SELECT entitlement_id, installation_id, plan, period_start, period_end,
       request_quota, token_budget, cost_budget, allowed_capabilities,
       soft_threshold, status
FROM entitlement WHERE installation_id = '<I0>';

SELECT audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
FROM control_audit WHERE action = 'enroll' AND target = '<I0>';
```

**Expect:** HTTP 200 `{ "platform_base_url": "http://127.0.0.1:8787" }`. One `installation` row: PK **I0**, `org_id` / `display_name` / `region` from the body, `status='active'`, `enrolled_at` ISO-8601 UTC. One `installation_key`: `key_id=K0`, FK **I0**, `public_key` equals the body, `algorithm='EdDSA'`, `valid_from` equals `enrolled_at`, `revoked_at` NULL, `valid_until` is `valid_from` plus 365 days (same millisecond origin as `handleEnroll`). One `entitlement`: UUID PK, FK **I0**, `plan='standard'`, `period_start` = `period_end` = `enrolled_at`, quotas `0`/`0`/`0.0`, `allowed_capabilities='[]'`, `soft_threshold=0`, `status='pending'`. One `control_audit`: UUID `audit_id`, `operator_id='platform-operator'`, `action='enroll'`, `target=I0`, `before_pointer` and `after_pointer` NULL, `recorded_at` ISO.

#### 15.3.4 Entitle writes budgets and live grants

**Do:** reject a non-ISO period, then entitle. Use a July `period_start` even though today is August 2026 — later usage must journal `period='2026-07'`, not wall-clock `2026-08`.

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "period_start": "2026-07-01T00:00:00.000Z",
    "period_end": "2026-09-01T00:00:00.000Z",
    "request_quota": 1000,
    "token_budget": 500000,
    "cost_budget": 50.0,
    "soft_threshold": 0.8,
    "allowed_capabilities": ["clinic.visit_summary"],
    "grants": [
      {
        "capability_id": "clinic.visit_summary",
        "capability_version": "1.0.0",
        "scope": "installation"
      },
      {
        "capability_id": "clinic.visit_summary",
        "capability_version": "1.0.0",
        "scope": "plan"
      }
    ]
  }'
```

**Do:** inspect `entitlement`, `capability_grant`, `control_audit` where `action='entitle'`. Then as wrangler:

```sql
INSERT INTO entitlement (
  entitlement_id, installation_id, plan, period_start, period_end,
  request_quota, token_budget, cost_budget, allowed_capabilities,
  soft_threshold, status
) VALUES (
  'dup-should-fail', '<I0>', 'standard',
  '2026-07-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z',
  1, 1, 1, '[]', 0, 'pending'
);
```

**Expect:** HTTP 200 `{ "installation_id": "<I0>", "status": "active" }`. Same single entitlement row (UNIQUE): `period_start`/`period_end` are those ISO instants (`period_start < period_end`), quotas 1000 / 500000 / 50.0, `allowed_capabilities` JSON `["clinic.visit_summary"]`, `soft_threshold=0.8`, `status='active'`. **`plan` is still `standard`** — entitle does not rewrite it. Two live grants: `scope='installation:<I0>'` and `scope='plan:standard'`, `capability_id='clinic.visit_summary'`, `capability_version='1.0.0'`, UUID `grant_id`, `granted_at`/`changed_at` ISO, `changed_by='platform-operator'`, `revoked_at` NULL, overlay columns **NULL** (not global overlays). Entitle audit: `action='entitle'`, `target=I0`, `after_pointer` JSON of `allowed_capabilities`, `operator_id='platform-operator'`. Duplicate INSERT fails UNIQUE (`idx_entitlement_installation_id`). Re-entitle → HTTP 409 `not_pending`.

#### 15.3.5 Rotate, revoke, suspend, resume, and delete

**Do:** rotate **I0** to a new kid **K1** (new public key). Inspect both key rows. Then enroll a **second** installation **I1** (different `org_id` and `kid`) and `POST …/I1/suspend`, `…/resume`, `…/delete`.

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/rotate" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"kid":"<K1>","public_key":"<new x>","algorithm":"EdDSA"}'
```

**Expect:** **K0** `revoked_at` is ISO now; **K1** `revoked_at` NULL, `valid_from` now, `valid_until` = that `valid_from` + 365 days, `algorithm='EdDSA'`, `installation_id=I0`. Audit `action='rotate'`. **I0** `status` stays `active`. **I1** after enroll `status='active'`; after suspend `'suspended'`; after resume `'active'`; after delete `'deleted'`. Matching audits `suspend` / `resume` / `delete`. Optional: `POST …/I0/revoke-key` with body `{"kid":"<K0>"}` after rotate → 409 `key_already_revoked` (already stamped). Leave **K1** unrevoked so **I0** can still invoke.

#### 15.3.6 Routing policy publish, canary, promote, rollback

Visit summary resolves `routing/standard` (playbook id `standard`). Publish **v9** then **v1** then **v10** so lexical TEXT `"9" > "10"` would pick the wrong winner if selection used `version DESC`.

**Do:** `POST /control/routing-policies/publish` three times with `{ "document": { … } }` whose `policy_id` is `"standard"` and `policy_version` is `9`, then `1`, then `10` (the document alone carries the identity). Use a `fake` target (`provider_id` `"fake"`, `latency_class` `"standard"`, `min_context_window` ≥ 32000) so local invoke can complete without vendor keys. Then `POST …/versions/1/canary` with `{"installation_ids":["<I0>"]}`, `POST …/versions/1/promote`, `POST …/versions/10/promote`, `POST …/versions/10/rollback`.

Inspect after each step:

```sql
SELECT policy_id, version, content_pointer, active_from, activated_by,
       canary_installation_ids, status, rowid
FROM routing_policy WHERE policy_id = 'standard' ORDER BY active_from DESC, rowid DESC;
```

**Expect:** publish INSERT `status='published'`, `canary_installation_ids` NULL, `content_pointer='control/routing-policy/standard/<version>.json'`, `activated_by='platform-operator'`, `active_from` ISO, PK `(policy_id, version)`. Audit `routing_policy_publish`, `after_pointer` = that R2 key. Canary: v1 `status='canary'`, `canary_installation_ids` JSON `["<I0>"]`, audit `routing_policy_canary`. Promote v1: v1 `status='active'`, `canary_installation_ids` NULL. Promote v10: v10 `active`, prior active **v1** `superseded` (not v9). The `ORDER BY active_from DESC, rowid DESC` winner is **v10**, not lexical `"9"`. Rollback v10 restores the prior superseded row as `active`. Audit actions `routing_policy_promote` / `routing_policy_rollback` populate `before_pointer` / `after_pointer`. Finish this probe with **v1 active** (promote v1 again if needed) so visit summary can route.

#### 15.3.7 Token contract, capability overlay, and kill switch

**Do:** `POST /control/token-contract/begin-rotation` `{"ver":"2"}` then inspect both `token_contract` rows. Then `POST /control/token-contract/retire` `{"ver":"2"}` so seed `ver=1` stays the accepted edition (clinic AATs use `ver=1`). Then `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate` with `{"successor_id":"clinic.visit_summary@1.0.0"}`. Inspect the new global overlay. **Do not retire yet** — overlap is 90 days and a `retired` overlay would block [§15.3.8](#1538-happy-path-request-journal-attempts-usage); retire is [§15.3.10](#15310-crons-counters-rollup-retention-grace).

**Do:** there is no `POST /control/kill-switch`. Insert via wrangler, then `POST /v1/requests` with a valid AAT (wait up to 30 s for config-cache TTL, or restart the Worker):

```sql
INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
VALUES ('global', 'global', 1, '<now ISO>', 'operator-sql');
```

Clear it before the happy-path request:

```sql
UPDATE kill_switch SET active = 0, changed_at = '<now ISO>'
WHERE scope = 'global' AND target = 'global';
```

Repeat once with `scope='installation', target='<I0>'` if you want that PK pair too; set `active=0` again.

**Expect:** after begin-rotation, two live rows (`retired_at` NULL): seed `ver=1` `changed_by='seed'` and `ver=2` `changed_by='platform-operator'`, `added_at` ISO. After retiring **v2**: `ver=2.retired_at` ISO, `changed_by='platform-operator'`; `ver=1` still `retired_at` NULL. Audits `token_contract_begin_rotation` / `token_contract_retire`. Overlay grant: `scope='global'`, `lifecycle_state='deprecated'`, `successor_id` set, `deprecated_at` / `retire_after` ISO (`retire_after` ≈ `deprecated_at` + 90 days), `revoked_at` equal to `changed_at` (overlay is not a live grant). Live entitle grants still have overlay columns NULL. **No row has `lifecycle_state='active'`** — that overlay value is not written by any route. Deprecated still resolves during the overlap window, so later `POST /v1/requests` can proceed. Kill-switch: PK `(scope, target)`, `active=1` fail-closed (`capability_disabled` / `forbidden_capability` JSON, **no** new `ai_request`). `changed_by='operator-sql'`. After `active=0`, invoke is allowed again. `POST /control/kill-switch` → 404.

#### 15.3.8 Happy-path request (journal, attempts, usage)

Kill switch off, **v1** routing active with a `fake` target, **K1** valid, AAT `ver` accepted, entitlement active.

**Do:** immediately after `accepted` (second terminal, or catch the SSE early), inspect `routing_decision` — it may still be NULL until Stage 10 routing UPDATE. Then let the stream finish.

```bash
curl -s -N -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: verify-happy-1" \
  -H "x-capability-version: 1.0.0" \
  -H "x-trace-id: verify-trace-1" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "user_intent": "Summarize today'\''s visit for the chart.",
    "context": {
      "org": "<AAT org>",
      "branch": "<AAT branch>",
      "visit.chief_complaint@v1": "Patient reports headache for 3 days."
    }
  }'
```

**Do:**

```sql
SELECT request_id, request_reference, installation_id, actor_id, branch_id,
       capability_id, capability_version, prompt_artifact_hash, idempotency_key,
       state, created_at, updated_at, completed_at, terminal_error_code, trace_id,
       payload_pointer, routing_tier, routing_decision, conversation_id, turn_ordinal
FROM ai_request WHERE idempotency_key = 'verify-happy-1';

SELECT attempt_id, request_id, attempt_no, provider, model, outcome,
       latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
FROM ai_attempt WHERE request_id = '<from journal>';

SELECT usage_event_id, installation_id, period, request_id, quota_weight,
       tokens, cost, recorded_at
FROM usage_event WHERE request_id = '<from journal>';

SELECT COUNT(*) AS grace_rows FROM grace_admission_queue WHERE installation_id = '<I0>';
```

**Expect:** one `ai_request`: ULID `request_id`, `request_reference` matching `XXXX-XXXX` (unique), `installation_id=I0`, `actor_id` = AAT `sub`, `branch_id` NULL or the AAT branch, `capability_id='clinic.visit_summary'`, `capability_version='1.0.0'`, non-empty `prompt_artifact_hash` (content hash of resolved prompt-artifact bytes), `idempotency_key='verify-happy-1'`, `state` terminal `Completed` (or `Failed` if the fake target was excluded — then use [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls) and fix routing), `created_at`/`updated_at` ISO, `completed_at` set, `terminal_error_code` NULL on Completed, `trace_id='verify-trace-1'`, `payload_pointer` like `request/<request_id>/envelope`, `routing_tier` `standard` or `degraded`, `routing_decision` JSON `RoutingDecision` (selected rule, chain, excluded targets, override provenance) **non-NULL after routing**, `conversation_id` NULL, `turn_ordinal` NULL. At INSERT the Worker binds `routing_decision` implicitly absent / NULL; the later UPDATE writes the JSON.

One or more `ai_attempt` rows: ULID `attempt_id`, FK to the request, `attempt_no` starting at 1, `provider` `fake` (or `deepseek`/`gemini` if you published those targets and have keys), `model` from the policy, `outcome` e.g. `success`, `latency_ms` ≥ 0, token columns integers, `cost` REAL from `priceUsage` (tokens × per-1K rates; 0 when no tokens), `provider_request_id` NULL or provider id, `error_code` NULL on success.

One `usage_event`: ULID PK, `installation_id=I0`, **`period='2026-07'`** (from entitle `period_start`, not `2026-08`), `request_id` still joined, `quota_weight` 1 (visit-summary manifest), `tokens`/`cost` agree with the attempt helper, `recorded_at` ISO.

`grace_admission_queue` still empty for **I0** — healthy admission does not read or write that table.

#### 15.3.9 Guard rejection, valid_until, Failed, conversational NULLs

**Do:** `POST /v1/requests` with a valid AAT but `x-capability-version` for a capability not in `allowed_capabilities` (or `capability_id` you did not grant). Then restore a valid body.

**Do:** expire the live key, invoke, restore:

```sql
UPDATE installation_key SET valid_until = '2020-01-01T00:00:00.000Z'
WHERE key_id = '<K1>';
-- POST /v1/requests (expect unauthenticated)
UPDATE installation_key SET valid_until = '<original ISO>'
WHERE key_id = '<K1>';
```

Wait for config-cache TTL (30 s) or restart the Worker after each key UPDATE.

**Do:** publish/promote a policy version whose only target is `deepseek` (no `DEEPSEEK_API_KEY`) **or** abort after accept; inspect a `Failed` journal row. Sending `conversation_id` / `turn_ordinal` on visit summary must not persist them (`single_shot` ignores conversational fields).

**Expect:** grant/capability guard rejection: taxonomy JSON, **no** new `ai_request` (counters increment in-isolate for [§15.3.10](#15310-crons-counters-rollup-retention-grace)). Expired `valid_until`: identity `unauthenticated`; `now >= valid_until` is the reject. `Failed` row: `state='Failed'`, `completed_at` set, `terminal_error_code` non-null (e.g. `provider_unavailable`), `routing_decision` may be JSON if routing ran. Matching `ai_attempt.outcome` in `{terminal_failure, timeout, retryable_failure, truncation}` and `error_code` set; `repair` will **not** appear — visit-summary `repairPolicy.allowed` is false. `conversation_id` and `turn_ordinal` stay NULL. Re-activate **v1** `fake` policy before the next probe.

`dashboardRepairRateByCapability` would use `SUM(outcome='repair')` as numerator; with zero repair rows the rate is 0. A non-zero numerator cannot be produced from the published catalog.

#### 15.3.10 Crons: counters, rollup, retention, grace

**Do — retire overlay:** journal probes are done. Age the deprecated overlay (public retire cannot elapse 90 days in this session), then `POST /control/capabilities/clinic.visit_summary/versions/1.0.0/retire`:

```sql
UPDATE capability_grant
SET retire_after = '2020-01-01T00:00:00.000Z'
WHERE scope = 'global' AND lifecycle_state = 'deprecated';
```

**Expect:** a second global overlay row with `lifecycle_state='retired'`, same `successor_id` / `deprecated_at` / `retire_after`, `revoked_at` = `changed_at`. Audit `action='retire'`. Later `POST /v1/requests` for visit summary would fail `capability_retired` — do not invoke after this step.

**Do — flush `platform_counter`:** after the guard rejection in [§15.3.9](#1539-guard-rejection-valid_until-failed-conversational-nulls), trigger any scheduled tick (or `0 4 * * *`):

```sql
SELECT counter_id, dimension_set, time_bucket, count FROM platform_counter;
```

**Expect:** at least one row. `counter_id` is a hash of bucket + dimensions, `dimension_set` JSON includes the error code / `installation_id`, `time_bucket` is a minute ISO string, `count` ≥ 1 **on this isolate**. That `count` is a lower bound: this local Worker is one isolate, so you cannot observe another isolate's lost tally. `dashboardQuotaRejectionRate` divides `SUM(count)` for `quota_exhausted` (and the same flush semantics) by in-window `ai_request` rows — it cannot be more exact than this table.

**Do — rollup (`0 4 * * *`):**

```sql
SELECT rollup_id, dimensions, request_count, tokens, cost FROM usage_rollup;
```

**Expect:** one row whose `dimensions` JSON has `installation_id=I0` and `period='2026-07'`. `rollup_id` is the hash of that JSON. `request_count` / `tokens` / `cost` equal the `usage_event` sums for that pair. Re-triggering the same cron does not duplicate the PK (upsert).

**Do — retention SET NULL (`0 3 * * *`):** age one **completed** journal row beyond 90 days, keep its `usage_event`, then trigger `0 3 * * *`:

```sql
UPDATE ai_request SET created_at = '2020-01-01T00:00:00.000Z'
WHERE idempotency_key = 'verify-happy-1';
```

**Expect:** that `ai_request` and its `ai_attempt` rows are gone. The `usage_event` money row remains with **`request_id` NULL**. A `LEFT JOIN usage_event → ai_request ON request_id` no longer matches — coverage shrank with age. (Diagnostic R2 may also drop; that is not a D1 column.)

**Do — grace, healthy path:** `SELECT * FROM grace_admission_queue WHERE installation_id = '<I0>'` after [§15.3.8](#1538-happy-path-request-journal-attempts-usage).

**Expect:** zero rows. The healthy Quota DO path does not read this table.

**Do — grace columns without a DO outage:** there is no control API to make `callAdmissionDo` return unavailable (`stub.fetch` throw or HTTP ≥500). On this local Worker the live INSERT path is unprobeable. Substitute, as [§8.3.6 in Stage 2](04-stage-2-clinic-keypair-enrollment.md#836-single-installation-trigger-failure-path) substitutes SQL when the public RPC cannot produce the row: insert the same columns `admitUnderGrace` would write, then fire any cron tick (reconcile runs every tick).

```sql
INSERT INTO grace_admission_queue (
  grace_request_id, installation_id, idempotency_key, jti, request_reference,
  entitlement_json, usage_tokens, usage_cost, partial, queued_at,
  reconcile_attempts, reconcile_first_seen_at_ms, status
) VALUES (
  '<uuid>', '<I0>', 'verify-grace-1', '<AAT jti>', 'GRCE-0001',
  '{"plan":"standard"}', NULL, NULL, NULL, '<now ISO>',
  0, NULL, 'pending'
);
```

Then insert a duplicate `(installation_id, idempotency_key)` and expect UNIQUE failure. Then trigger scheduled. Inspect the row.

**Expect:** pending insert: PK UUID (this is what `grace_admitted.requestId` would return), FK **I0**, cap is `COUNT(*)` of `status='pending'` per installation (5; you are at 1), `jti` / `request_reference` / `entitlement_json` set, usage columns NULL, `partial` NULL, `queued_at` ISO, `reconcile_attempts=0`, `reconcile_first_seen_at_ms` NULL, `status='pending'`. After cron with a healthy DO: either `status='reconciled'` or `'dropped'`, or still `'pending'` with `reconcile_attempts ≥ 1` and `reconcile_first_seen_at_ms` set (TTL origin). **`usage_tokens` / `usage_cost` / `partial` stay NULL** unless `creditUsage` attached them on a real grace admit — that attach is unprobeable here. Repeating POST `/v1/requests` while the DO is up still does not add grace rows.

---
