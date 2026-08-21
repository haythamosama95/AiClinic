# AI Platform Data Journey — Stage 0 — Platform configuration and boot

## Table of Contents

1. [1. Plain language](#1-plain-language)
2. [2. Metaphor](#2-metaphor)
3. [3. Wrangler configuration (`ai-platform/wrangler.toml`)](#3-wrangler-configuration-ai-platformwranglertoml)
   - [3.1 Top-level Worker metadata](#31-top-level-worker-metadata)
   - [3.2 Cron triggers](#32-cron-triggers)
   - [3.3 Per-environment bindings](#33-per-environment-bindings)
   - [3.4 Secrets (not in wrangler.toml — set via `wrangler secret put` or `.dev.vars`)](#34-secrets-not-in-wranglertoml-set-via-wrangler-secret-put-or-devvars)
4. [4. D1 schema bootstrap](#4-d1-schema-bootstrap)
5. [5. Worker module boot (`worker.ts` at load)](#5-worker-module-boot-workerts-at-load)
6. [6. Happy path](#6-happy-path)
7. [7. Failure paths](#7-failure-paths)

---

## 1. Plain language

Before any clinic exists, operators provision Cloudflare resources and deploy the Worker. The Worker loads its product catalog (visit summary manifest) into memory. D1 gets empty tables plus one seeded passport standard (`token_contract ver=1`).

## 2. Metaphor

You are building an **airport** before airlines arrive: runways (bindings), a passport office rulebook (token contract), and a flight manual for one route (visit summary manifest). No passengers, no tickets yet.

## 3. Wrangler configuration (`ai-platform/wrangler.toml`)



### 3.1 Top-level Worker metadata


| Field                | Example / value       | Meaning                   | Read in code    |
| -------------------- | --------------------- | ------------------------- | --------------- |
| `name`               | `ai-platform-gateway` | Base worker name          | Wrangler deploy |
| `main`               | `src/worker.ts`       | Entry module              | Wrangler        |
| `compatibility_date` | `2026-05-03`          | Workers runtime API level | Runtime         |
| `[dev].ip`           | `127.0.0.1`           | Local dev bind address    | `wrangler dev`  |
| `[dev].port`         | `8787`                | Local dev port            | `wrangler dev`  |




### 3.2 Cron triggers


| Cron        | Handler                      | Data effect                                           |
| ----------- | ---------------------------- | ----------------------------------------------------- |
| `0 3 * * *` | `runRetentionPurge`          | Deletes old R2 envelopes, purges aged D1 journal rows |
| `0 4 * * *` | `runRollupAndReconciliation` | Upserts `usage_rollup`, reconciles grace admissions   |




### 3.3 Per-environment bindings

Each of `development`, `staging`, `production` defines:


| Binding / var                          | Type           | Meaning                                            |
| -------------------------------------- | -------------- | -------------------------------------------------- |
| `name`                                 | string         | e.g. `ai-platform-gateway-development`             |
| `BUILD_SHA`                            | var            | Git SHA shown on `/health`                         |
| `ENVIRONMENT`                          | var            | `development` / `staging` / `production`           |
| `LOG_VERBOSITY`                        | var            | `0` (minimal) / `1` / `2` (verbose)                |
| `OPERATOR_ID`                          | var            | Stable operator principal id written to audit rows |
| `DB`                                   | D1             | SQLite database binding                            |
| `R2`                                   | R2 bucket      | Object storage binding                             |
| `DO`                                   | Durable Object | `GatewayObject` class                              |
| `RATE_LIMITER_INSTALLATION`            | Rate limit     | 600 req / 60s per installation                     |
| `RATE_LIMITER_INSTALLATION_ACTOR`      | Rate limit     | 120 req / 60s per installation+actor               |
| `RATE_LIMITER_INSTALLATION_CAPABILITY` | Rate limit     | 300 req / 60s per installation+capability          |


D1 `database_name` per env: `ai-platform-development`, `ai-platform-staging`, `ai-platform-production`.

R2 `bucket_name` matches the same pattern.

### 3.4 Secrets (not in wrangler.toml — set via `wrangler secret put` or `.dev.vars`)


| Secret                  | Required when           | Read in                |
| ----------------------- | ----------------------- | ---------------------- |
| `OPERATOR_BEARER_TOKEN` | All `/control/*` routes | `control/auth.ts`      |
| `DEEPSEEK_API_KEY`      | Live DeepSeek routing   | `provider/deepseek.ts` |
| `GEMINI_API_KEY`        | Live Gemini routing     | `provider/gemini.ts`   |


Provider key resolution: `env[binding]` string lookup in `worker.ts` `secretStore.getSecret`.

## 4. D1 schema bootstrap

**Command:** `npx wrangler d1 migrations apply ai-platform-<env> --env <env>`

Creates 14 tables (see [§18 — Complete D1 column reference](16-complete-d1-column-reference.md#1-installation)). Migration order matters; snapshot at `ai-platform/schema.snap.sql`.

**Only SQL seed row:**

```sql
INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed');
```



## 5. Worker module boot (`worker.ts` at load)


| Action                       | Data produced                               | Consumers                    |
| ---------------------------- | ------------------------------------------- | ---------------------------- |
| `assertRequiredBindings`     | Throws if `DB`, `R2`, or `DO` missing       | Process won't serve          |
| `setCapabilityRegistry(...)` | In-memory map: `clinic.visit_summary@1.0.0` | Guard stage 5, discovery     |
| Prompt artifacts             | **Not loaded** at boot                      | Lazy import on first compose |


`**/health` response:**

```json
{
  "build": "<BUILD_SHA>",
  "environment": "<ENVIRONMENT>"
}
```



## 6. Happy path

```
Provision D1 + R2 + DO in Cloudflare
  → fill database_id in wrangler.toml
  → wrangler secret put OPERATOR_BEARER_TOKEN (+ provider keys)
  → wrangler d1 migrations apply
  → wrangler deploy --var BUILD_SHA:<sha>
  → GET /health returns 200
```



## 7. Failure paths


| Condition                      | Effect                           | Field involved    |
| ------------------------------ | -------------------------------- | ----------------- |
| Missing `DB`/`R2`/`DO` binding | Worker isolate throws at load    | Wrangler config   |
| Migrations not applied         | Every AAT fails identity         | D1 tables missing |
| Missing provider API key       | Invoke fails `provider_rejected` | Secret not set    |


---

