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
8. [8. Behavioral verification](#8-behavioral-verification)
   - [8.1 Setup](#81-setup)
   - [8.2 Coverage](#82-coverage)
   - [8.3 Ordered probes](#83-ordered-probes)
     - [8.3.1 Reset to a known empty-airport state](#831-reset-to-a-known-empty-airport-state)
     - [8.3.2 Inspect wrangler.toml and secrets](#832-inspect-wranglertoml-and-secrets)
     - [8.3.3 First boot and GET /health (happy path)](#833-first-boot-and-get-health-happy-path)
     - [8.3.4 Who may and may not invoke](#834-who-may-and-may-not-invoke)
     - [8.3.5 D1 schema bootstrap and seed row](#835-d1-schema-bootstrap-and-seed-row)
     - [8.3.6 Re-apply migrations and restart (idempotent)](#836-re-apply-migrations-and-restart-idempotent)
     - [8.3.7 Independent switches and what this stage does not do](#837-independent-switches-and-what-this-stage-does-not-do)
     - [8.3.8 Cron ticks on an empty airport](#838-cron-ticks-on-an-empty-airport)
     - [8.3.9 Token-contract seed handoff to Stage 1](#839-token-contract-seed-handoff-to-stage-1)
     - [8.3.10 Missing DB, R2, or DO binding (failure path)](#8310-missing-db-r2-or-do-binding-failure-path)
     - [8.3.11 Migrations not applied (failure path)](#8311-migrations-not-applied-failure-path)
     - [8.3.12 Missing provider API key (failure path)](#8312-missing-provider-api-key-failure-path)
9. [9. Failed and cancelled credit](#9-failed-and-cancelled-credit)

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
| every tick  | `flushRejectionCounters` then `reconcileGraceUsage` | Flushes **this isolate's** in-memory guard-rejection tally into `platform_counter`, then drains D1 `grace_admission_queue`. Other isolates' tallies are not drained and are lost on eviction, so `platform_counter` is a **lower bound**, not an exact count. |
| `0 3 * * *` | `runRetentionPurge`          | Deletes old R2 envelopes; nulls `usage_event.request_id` then purges aged D1 journal rows. Aged usage keeps the money row but loses request joinability (reconciliation coverage shrinks with age). |
| `0 4 * * *` | `runRollupAndReconciliation` | Upserts `usage_rollup`; `runReconciliation` LEFT JOINs `usage_event` on `request_id` (nulled aged rows can never match). |




### 3.3 Per-environment bindings

Each of `development`, `staging`, `production` defines:


| Binding / var                          | Type           | Meaning                                            |
| -------------------------------------- | -------------- | -------------------------------------------------- |
| `name`                                 | string         | e.g. `ai-platform-gateway-development`             |
| `BUILD_SHA`                            | var            | Git SHA shown on `/health`                         |
| `ENVIRONMENT`                          | var            | `development` / `staging` / `production`           |
| `CONFIG_CACHE_TTL_MS`                  | var            | Isolate config-cache TTL in milliseconds (`resolveConfigCacheTtlMs` at boot, `config-cache/index.ts:L31-L40`). Unset, empty, non-numeric, or negative → `30_000` (`DEFAULT_CONFIG_CACHE_TTL_MS`). `"0"` disables caching (every `consult` misses). |
| `LOG_VERBOSITY`                        | var            | Log level for the isolate (`verbosityFromEnv`, `logger.ts:L96-L104`). Accepts `0`/`1`/`2` or aliases `V0`/`V1`/`V2` (case-insensitive). Unrecognized values → `V0`. When unset or empty: `ENVIRONMENT=development` → `V2`; otherwise → `V0`. |
| `OPERATOR_ID`                          | var            | Single shared operator principal id written to every `control_audit` row. One bearer + one id: the trail cannot distinguish operators. |
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
| `OPERATOR_BEARER_TOKEN` | All `/control/*` routes | `control/auth.ts` (`createSecretOperatorAuth`: one shared bearer; timing-safe compare; all actions attributed to `OPERATOR_ID`) |
| `DEEPSEEK_API_KEY`      | Live DeepSeek routing   | `provider/deepseek.ts` |
| `GEMINI_API_KEY`        | Live Gemini routing     | `provider/gemini.ts`   |


Provider key resolution: `env[binding]` string lookup in `worker.ts` `secretStore.getSecret`.

## 4. D1 schema bootstrap

**Command:** `npx wrangler d1 migrations apply ai-platform-<env> --env <env>`

The baseline migration `20260731120000_platform_schema.sql` creates **11** tables (`installation`, `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`). Four later migrations add the remaining platform surface:

| Migration | Adds |
| --- | --- |
| `20260803120000_token_contract.sql` | `token_contract` table + seed row (`ver='1'`) |
| `20260807120000_kill_switch.sql` | `kill_switch` |
| `20260821120000_grace_admission_queue.sql` | `grace_admission_queue` |
| `20260821130000_entitlement_installation_unique.sql` | unique index `idx_entitlement_installation_id` on `entitlement(installation_id)` |

After the full chain: **14** tables and exactly one SQL seed row. Column reference: [§18 — Complete D1 column reference](16-complete-d1-column-reference.md#1-installation). Snapshot at `ai-platform/schema.snap.sql`.

**Only SQL seed row:**

```sql
INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed');
```



## 5. Worker module boot (`worker.ts` at load)


| Action                       | Data produced                               | Consumers                    |
| ---------------------------- | ------------------------------------------- | ---------------------------- |
| `assertRequiredBindings`     | Throws if `DB`, `R2`, or `DO` missing       | Process won't serve          |
| `configureIsolateConfigCache` | TTL from `CONFIG_CACHE_TTL_MS`             | Discovery, identity, control config reads |
| `setCapabilityRegistry(...)` | In-memory map: `clinic.visit_summary@1.0.0` | Guard stage 5, discovery     |
| Platform price table         | Bundled `control/pricing/platform-default/1.json` via `src/pricing` | Post-response `ai_attempt.cost`, `usage_event.cost`, cancel credits |
| Prompt artifacts             | **Not loaded** at boot                      | Lazy import on first compose |


**`/health` (method-agnostic).** The fetch handler branches on `url.pathname === "/health"` with **no method conjunct** (`worker.ts:L1565-L1570`), so any HTTP method (`GET`, `POST`, `DELETE`, …) returns the same JSON with no auth:

```json
{
  "build": "<BUILD_SHA>",
  "environment": "<ENVIRONMENT>"
}
```

**Stage-numbering map.** Pipeline-internal identity guard is **stage 2** (`fail(2, …)` in `pipeline/index.ts:L343-L354`). Catalog **Stage 9** is the same component — readers must not conflate the two numbering schemes.

**Two HTTP 404 shapes.** (1) **Null-body 404** — `new Response(null, { status: 404 })`: empty GET reference (`/v1/requests/`), unknown/malformed/cross-installation references on `GET /v1/requests/{ref}` (`worker.ts:L1612-L1613`, `L1636-L1638`). (2) **Plain-text catch-all** — `new Response("Not Found", { status: 404 })`: unknown paths, wrong methods on routed prefixes (`worker.ts:L1675`). No taxonomy envelope on either shape.

**Control-plane 401 (not taxonomy).** Missing or wrong operator bearer on `/control/*` returns HTTP 401 with body exactly `{"error":"unauthorized"}` (`control/http.ts:L3-L8`). This deliberately **bypasses** the clinic taxonomy envelope (`code`, `request_reference`, `trace_id`, `retry_safe`) used on `/v1/*` routes.

### 5.1 Config cache and test guidance

After a control mutation or other D1 config change, a subsequent identity or discovery read may serve a stale isolate-cache entry until TTL expiry. For tests, set `CONFIG_CACHE_TTL_MS=0` in the test environment (wrangler `[vars]` or harness env) so every `loadConfig` re-reads D1 — preferred over restarting `npm run dev` or waiting 30 s. Production default TTL is 30 000 ms when the var is unset or invalid.

## 6. Happy path

```
Provision D1 + R2 + DO in Cloudflare
  → fill database_id in wrangler.toml
  → wrangler secret put OPERATOR_BEARER_TOKEN (+ provider keys)
  → wrangler d1 migrations apply
  → wrangler deploy --var BUILD_SHA:<sha>
  → GET /health returns 200
  → npm run bootstrap:routing-policy   (ops script — publish + promote standard@1; [Stage 5](07-stage-5-routing-policy.md#60-greenfield-bootstrap))
```



## 7. Failure paths


| Condition                      | Effect                           | Field involved    |
| ------------------------------ | -------------------------------- | ----------------- |
| Missing `DB`/`R2`/`DO` binding | Worker isolate throws at load    | Wrangler config   |
| Migrations not applied         | Every AAT fails identity         | D1 tables missing |
| Missing provider API key       | Invoke fails `provider_rejected` | Secret not set    |


## 8. Behavioral verification

Live probes against a local Worker and its local D1. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§8.3](#83-ordered-probes) top to bottom** on a throwaway local persist (or wipe the local D1 first). If every probe matches, this stage is working.

Gates in code (wording in [§5](#5-worker-module-boot-workerts-at-load)–[§7](#7-failure-paths) is slightly looser):

- Required bindings are only `DB`, `R2`, and `DO`. `assertRequiredBindings` throws `Missing required binding: <name>` at **module load**. Rate-limit bindings are not in that check (`?? allowAllRateLimit`).
- `/health` is method-agnostic (pathname-only branch); it does not read D1, R2, operator bearer, or provider keys. It returns JSON `{ build, environment }` with no auth.
- Control-plane 401 is `{"error":"unauthorized"}` — not the clinic taxonomy envelope.
- “Every tick” is not a third cron. `wrangler.toml` has `0 3 * * *` and `0 4 * * *`. Every `scheduled()` invocation runs `flushRejectionCounters` then `reconcileGraceUsage`, then branches on `controller.cron`.
- Missing migrations: `/health` still works. A well-formed AAT then hits D1 and cannot authenticate. Absent tables often surface as a D1 “no such table” **500**, not a clean `unauthenticated`. Garbage Bearers fail JWT parse **before** D1 either way.
- Missing `DEEPSEEK_API_KEY` / `GEMINI_API_KEY`: boot still serves. `secretStore.getSecret` runs only when invoke selects that provider; the adapter then returns taxonomy `provider_rejected` with detail `missing_api_key`.

### 8.1 Setup

- Node 22+. `cd ai-platform` for every command in [§8.3](#83-ordered-probes).
- Prefer a throwaway local D1 you can wipe. Leftover enroll/entitle rows will fail the empty-airport checks.
- Local secrets in `.dev.vars.development` (named env) or `.dev.vars`: at least `OPERATOR_BEARER_TOKEN`. Do **not** put secrets in `wrangler.toml`. Provider keys are optional for this stage.
- Start the Worker with scheduled testing enabled (needed for [§8.3.8](#838-cron-ticks-on-an-empty-airport)):

```bash
cd ai-platform
npm install
npx wrangler d1 migrations apply ai-platform-development --local --env development
npm run dev -- --test-scheduled
# → http://127.0.0.1:8787
```

If `/cdn-cgi/handler/scheduled` 404s, you started without `--test-scheduled` — restart with it.

```bash
export GATEWAY='http://127.0.0.1:8787'
set -a
# Named env wins for `wrangler dev --env development`:
[ -f .dev.vars.development ] && . ./.dev.vars.development || . ./.dev.vars
set +a
```

Inspect D1 as yourself (no clinic role). Always pass `--local --env development` so you hit `ai-platform-development`, not a remote database.

Remote analogs (`wrangler secret put`, `wrangler deploy --var BUILD_SHA:<sha>`, filling a real `database_id`) are the same bindings; these probes use local persist and `BUILD_SHA = "local"` from `wrangler.toml`.

### 8.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| [§6](#6-happy-path) local analog: secrets present, migrations applied, isolate serves, `GET /health` 200 | [§8.3.1](#831-reset-to-a-known-empty-airport-state), [§8.3.3](#833-first-boot-and-get-health-happy-path) |
| `/health` JSON is only `build` + `environment`; no auth | [§8.3.3](#833-first-boot-and-get-health-happy-path) |
| `build` matches `BUILD_SHA`, `environment` matches `ENVIRONMENT` (`local` / `development` here) | [§8.3.3](#833-first-boot-and-get-health-happy-path) |
| [§3.1](#31-top-level-worker-metadata): `name`, `main`, `compatibility_date`, `[dev].ip` `127.0.0.1`, `[dev].port` `8787` | [§8.3.2](#832-inspect-wranglertoml-and-secrets), [§8.3.3](#833-first-boot-and-get-health-happy-path) |
| [§3.2](#32-cron-triggers): toml crons are `0 3 * * *` and `0 4 * * *` (no third schedule) | [§8.3.2](#832-inspect-wranglertoml-and-secrets) |
| Every scheduled tick: `flushRejectionCounters` then `reconcileGraceUsage`; `0 3 * * *` adds purge; `0 4 * * *` adds rollup | [§8.3.8](#838-cron-ticks-on-an-empty-airport) |
| `platform_counter` is a **lower bound** (other isolates’ tallies lost on eviction) | Not probeable on one local isolate — see [§8.3.8](#838-cron-ticks-on-an-empty-airport) |
| [§3.3](#33-per-environment-bindings): worker name, vars, `DB`/`R2`/`DO`, three rate limiters (600 / 120 / 300), D1/R2 names | [§8.3.2](#832-inspect-wranglertoml-and-secrets) |
| [§3.4](#34-secrets-not-in-wranglertoml-set-via-wrangler-secret-put-or-devvars): secrets absent from toml; `OPERATOR_BEARER_TOKEN` present in `.dev.vars*` | [§8.3.2](#832-inspect-wranglertoml-and-secrets) |
| `OPERATOR_BEARER_TOKEN` gates `/control/*`; `OPERATOR_ID` is not written at boot | [§8.3.4](#834-who-may-and-may-not-invoke), [§8.3.7](#837-independent-switches-and-what-this-stage-does-not-do) |
| 14 D1 tables including `grace_admission_queue`; `idx_entitlement_installation_id` UNIQUE | [§8.3.5](#835-d1-schema-bootstrap-and-seed-row) |
| Only SQL seed: `token_contract` `ver=1`, `added_at`, `retired_at` NULL, `changed_by=seed` | [§8.3.5](#835-d1-schema-bootstrap-and-seed-row), [§8.3.9](#839-token-contract-seed-handoff-to-stage-1) |
| Empty airport: no installation, entitlement, routing policy, R2 envelopes, or `control_audit` | [§8.3.1](#831-reset-to-a-known-empty-airport-state), [§8.3.7](#837-independent-switches-and-what-this-stage-does-not-do) |
| First-time boot **and** re-apply / restart still serve `/health` with one seed row | [§8.3.3](#833-first-boot-and-get-health-happy-path), [§8.3.6](#836-re-apply-migrations-and-restart-idempotent) |
| Runtime loads the isolate; anyone may `GET /health`; clinic/Flutter/AAT do not invoke boot | [§8.3.3](#833-first-boot-and-get-health-happy-path), [§8.3.4](#834-who-may-and-may-not-invoke) |
| `/v1/*` needs an AAT; `/control/*` needs the operator bearer (POST only); unknown path 404 | [§8.3.4](#834-who-may-and-may-not-invoke) |
| `GatewayObject` is not a public URL | [§8.3.4](#834-who-may-and-may-not-invoke) |
| In-memory catalog `clinic.visit_summary@1.0.0`; price table bundled; prompts **not** loaded at boot | [§8.3.7](#837-independent-switches-and-what-this-stage-does-not-do) |
| Stage 1 handoff: seed `ver=1` is accepted (`retired_at` NULL); no clinic is registered yet | [§8.3.9](#839-token-contract-seed-handoff-to-stage-1) |
| Missing `DB`/`R2`/`DO` → isolate throws at load; HTTP cannot trigger this | [§8.3.10](#8310-missing-db-r2-or-do-binding-failure-path) |
| Migrations not applied → every AAT fails identity; `/health` still 200 | [§8.3.11](#8311-migrations-not-applied-failure-path) |
| Missing provider API key → invoke `provider_rejected`; `/health` does not read the secret | [§8.3.12](#8312-missing-provider-api-key-failure-path) |


### 8.3 Ordered probes

#### 8.3.1 Reset to a known empty-airport state

**Do:** apply local migrations (safe if already applied), then wipe business rows and restore the seed:

```bash
cd ai-platform
npx wrangler d1 migrations apply ai-platform-development --local --env development

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM ai_attempt;
   DELETE FROM usage_event;
   DELETE FROM grace_admission_queue;
   DELETE FROM ai_request;
   DELETE FROM installation_key;
   DELETE FROM entitlement;
   DELETE FROM capability_grant;
   DELETE FROM routing_policy;
   DELETE FROM kill_switch;
   DELETE FROM platform_counter;
   DELETE FROM control_audit;
   DELETE FROM usage_rollup;
   DELETE FROM installation;
   DELETE FROM token_contract;
   INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
   VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed');"
```

**Expect:** apply reports already-applied or newly applied. The `INSERT` succeeds. `installation` is empty. `token_contract` has exactly the seed row (next probes confirm columns).

#### 8.3.2 Inspect wrangler.toml and secrets

**Do:**

```bash
cd ai-platform
grep -E '^(name|main|compatibility_date) ' wrangler.toml
sed -n '/^\[dev\]/,/^$/p' wrangler.toml
sed -n '/^\[triggers\]/,/^$/p' wrangler.toml
grep -n 'OPERATOR_BEARER_TOKEN\|DEEPSEEK_API_KEY\|GEMINI_API_KEY' wrangler.toml || true
grep -E 'BUILD_SHA|ENVIRONMENT|LOG_VERBOSITY|OPERATOR_ID' wrangler.toml
grep -E 'binding = |database_name = |bucket_name = |class_name = |name = "RATE_LIMITER' wrangler.toml
```

**Expect:** `name = "ai-platform-gateway"`, `main = "src/worker.ts"`, `compatibility_date = "2026-05-03"`, `[dev]` `ip = "127.0.0.1"` `port = 8787`, `crons = ["0 3 * * *", "0 4 * * *"]`. **No** provider or operator secret names in the toml. Development block: `name = "ai-platform-gateway-development"`, `BUILD_SHA = "local"`, `ENVIRONMENT = "development"`, `LOG_VERBOSITY = "2"`, `OPERATOR_ID = "platform-operator"`, `DB` → `ai-platform-development`, `R2` → `ai-platform-development`, `DO` → `GatewayObject`, rate limiters `RATE_LIMITER_INSTALLATION` 600/60s, `_ACTOR` 120/60s, `_CAPABILITY` 300/60s.

**Do:** confirm the operator secret exists without printing it:

```bash
grep -c '^OPERATOR_BEARER_TOKEN=' .dev.vars.development .dev.vars 2>/dev/null
```

**Expect:** at least one file reports `1`. Staging/production vars in the same toml (`ENVIRONMENT`, `LOG_VERBOSITY` `1` / `0`) are config-only here — you are probing the development isolate.

#### 8.3.3 First boot and GET /health (happy path)

**Do:** with `npm run dev -- --test-scheduled` listening on the `[dev]` bind:

```bash
curl -sS -D- "$GATEWAY/health"
curl -sS -D- -X POST "$GATEWAY/health" -H 'Content-Type: application/json' -d '{}'
```

**Expect:** both HTTP 200, `content-type` JSON, body **exactly** the two [§5](#5-worker-module-boot-workerts-at-load) fields:

```json
{"build":"local","environment":"development"}
```

`build` is `BUILD_SHA` from the development vars (the local stand-in for `wrangler deploy --var BUILD_SHA:<sha>`). `environment` is `ENVIRONMENT`. No auth header was required. The process staying up means `assertRequiredBindings` passed and `load(clinic.visit_summary@1.0.0)` did not abort the isolate.

This is [§6](#6-happy-path) on the local analog: bindings already in toml, secret in `.dev.vars*`, migrations applied, Worker serving.

#### 8.3.4 Who may and may not invoke

Boot has no HTTP caller — Wrangler/Cloudflare loads `src/worker.ts`. After it is up:

**Do:** `curl -sS -o /dev/null -w '%{http_code}\n' "$GATEWAY/health"`

**Expect:** `200`. Anyone may call `/health` (no bearer).

**Do:**

```bash
curl -sS -D- "$GATEWAY/v1/capabilities"
curl -sS -D- "$GATEWAY/v1/capabilities" -H "Authorization: Bearer not-a-jwt"
curl -sS -D- -X POST "$GATEWAY/control/token-contract/begin-rotation" \
  -H "Content-Type: application/json" -d '{"ver":"1"}'
curl -sS -D- -X POST "$GATEWAY/control/token-contract/begin-rotation" \
  -H "Authorization: Bearer wrong" -H "Content-Type: application/json" -d '{"ver":"1"}'
curl -sS -o /dev/null -w '%{http_code}\n' "$GATEWAY/control/token-contract/begin-rotation"
curl -sS -o /dev/null -w '%{http_code}\n' "$GATEWAY/cdn-cgi/does-not-exist"
```

**Expect:**

- `GET /v1/capabilities` with no/garbage Bearer → HTTP 401, taxonomy `code: "unauthenticated"`. Clinic AATs are later stages; this stage does not mint them. Discovery never lists the catalog until identity passes.
- `POST /control/token-contract/begin-rotation` with missing or wrong bearer → HTTP 401, `{"error":"unauthorized"}` (plain control-plane body — **not** the clinic taxonomy envelope). Do **not** retry with the real `OPERATOR_BEARER_TOKEN` here (that write is Stage 1). The gate is `createSecretOperatorAuth` (timing-safe compare; all later control actions would attribute to `OPERATOR_ID`).
- `GET /control/token-contract/begin-rotation` → **404** plain-text `Not Found`. Only `POST` + a matching control path enters `dispatchControlRequest`.
- `GET /v1/requests/` (empty reference) → **404** with an **empty body** (`new Response(null, { status: 404 })`), before auth.
- Unknown path or wrong method on a routed prefix → **404** plain-text `Not Found`.

**Do:** `curl -sS -o /dev/null -w '%{http_code}\n' "$GATEWAY/quota-do.internal/rpc"`

**Expect:** 404. `GatewayObject.fetch` is Worker→DO RPC (`kind` `admission` / `credit` / `release`), not a public URL.

Clinic Flutter is not a caller of boot. It must not be required for any probe in this file.

#### 8.3.5 D1 schema bootstrap and seed row

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT name FROM sqlite_master WHERE type='table'
     AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%'
     AND name != 'd1_migrations' ORDER BY name;"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT name FROM sqlite_master WHERE type='index'
     AND name = 'idx_entitlement_installation_id';"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT ver, added_at, retired_at, changed_by FROM token_contract;"
```

**Expect:** exactly these **14** tables: `ai_attempt`, `ai_request`, `capability_grant`, `control_audit`, `entitlement`, `grace_admission_queue`, `installation`, `installation_key`, `kill_switch`, `platform_counter`, `routing_policy`, `token_contract`, `usage_event`, `usage_rollup`. Index `idx_entitlement_installation_id` exists. Seed row: `ver = '1'`, `added_at = '2026-08-03T00:00:00.000Z'`, `retired_at` NULL, `changed_by = 'seed'`. That is the only SQL seed this stage writes.

#### 8.3.6 Re-apply migrations and restart (idempotent)

**Do:** apply migrations again. Stop the Worker, start it again (`npm run dev -- --test-scheduled`). Repeat `GET /health` and the `token_contract` SELECT from [§8.3.5](#835-d1-schema-bootstrap-and-seed-row).

**Expect:** wrangler reports migrations already applied (no second seed insert — a raw `INSERT` without `OR IGNORE` would conflict, which is why apply is tracked in `d1_migrations`). `/health` still `{"build":"local","environment":"development"}`. Still exactly one `token_contract` row, same four columns. First-time success and reuse success are the same empty airport.

#### 8.3.7 Independent switches and what this stage does not do

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT
     (SELECT COUNT(*) FROM installation) AS installations,
     (SELECT COUNT(*) FROM installation_key) AS keys,
     (SELECT COUNT(*) FROM entitlement) AS entitlements,
     (SELECT COUNT(*) FROM capability_grant) AS grants,
     (SELECT COUNT(*) FROM routing_policy) AS policies,
     (SELECT COUNT(*) FROM kill_switch) AS kill_switches,
     (SELECT COUNT(*) FROM ai_request) AS requests,
     (SELECT COUNT(*) FROM control_audit) AS audits,
     (SELECT COUNT(*) FROM platform_counter) AS counters,
     (SELECT COUNT(*) FROM grace_admission_queue) AS grace,
     (SELECT retired_at FROM token_contract WHERE ver = '1') AS seed_retired;"
```

**Expect:** all counts `0`. `seed_retired` NULL. Boot did not enroll a clinic, grant quotas, publish routing, flip a kill switch, journal a request, or write `control_audit` (`OPERATOR_ID` is unused until a control mutation). `retired_at` stays NULL — this stage does not rotate the passport edition ([Stage 1](03-stage-1-token-contract-baseline.md)). Routing is still unset after boot; run `npm run bootstrap:routing-policy` ([Stage 5 §6.0](07-stage-5-routing-policy.md#60-greenfield-bootstrap)) once the Worker is up when you need invoke to route — that is an ops step, not part of Worker load.

**Do:** look at the bundled catalog and price table (not HTTP):

```bash
python3 -c "import json; d=json.load(open('manifests/published/clinic.visit_summary@1.0.0.json')); print(d['Identity']['capabilityId'], d['Identity']['version'])"
python3 -c "import json; d=json.load(open('control/pricing/platform-default/1.json')); print(d['pricing_id'], d['pricing_version'], d['unit'])"
```

**Expect:** `clinic.visit_summary 1.0.0` and `platform-default 1 per_1k_tokens`. `/health` has **no** capability or pricing fields. There is no public catalog list until identity (Stage 9). The price table is bundled for post-response `cost` — not a D1/R2 store and not client-visible. Prompt files under `prompts/` exist on disk; boot does **not** import them (`createProductionPreAccept` lazy-imports `./prompt/composer` on first `POST /v1/requests`).

Rate-limit bindings are **not** flipped by boot: `GET /health` is unauthenticated and unmetered. Exhausting 600/120/300 requires later `/v1` traffic.

This stage does not touch clinic Postgres (no `ai.availability`, no keypair). You do not need Supabase running.

#### 8.3.8 Cron ticks on an empty airport

Watch wrangler stdout. **Do:**

```bash
curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=*+*+*+*+*&format=json"
curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=0+3+*+*+*&format=json"
curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=0+4+*+*+*&format=json"
```

**Expect:** each response `outcome` is `ok`. Logs: every call emits `scheduled_cron_start` (flush + grace reconcile always run). Only `cron=0 3 * * *` emits `scheduled_retention_purge_start`. Only `cron=0 4 * * *` emits `scheduled_rollup_start`. Re-run the counts from [§8.3.7](#837-independent-switches-and-what-this-stage-does-not-do): still zeros, seed unchanged. Empty `grace_admission_queue` / `usage_event` means purge and rollup are no-ops — they must not invent rows.

You **cannot** prove from one isolate that `platform_counter` is a lower bound or that another isolate’s in-memory tally is lost on eviction. That claim is multi-isolate; skip it here.

#### 8.3.9 Token-contract seed handoff to Stage 1

Do **not** call `POST /control/token-contract/begin-rotation` or `retire` (those are Stage 1 writes).

**Do:** re-read the seed; then `GET /v1/capabilities` with a garbage Bearer.

**Expect:** still `ver=1`, `retired_at` NULL, `changed_by=seed`. Identity later loads `token_contracts:{payload.ver}` against this row. Garbage Bearer is still `unauthenticated` — not because the contract is missing, but because no installation exists yet. Stage 0’s job was to seed the edition; it does not register a clinic (Stage 3) or mint an AAT (Stage 6).

#### 8.3.10 Missing DB, R2, or DO binding (failure path)

No public API can trigger module-load. **Forcing:** stop the Worker. Temporarily comment out **one** of `[[env.development.d1_databases]]`, `[[env.development.r2_buckets]]`, or `[[env.development.durable_objects.bindings]]` in `wrangler.toml`. Start `npm run dev` again.

**Expect:** the isolate does not serve. Wrangler/logs show `Missing required binding: DB` (or `R2` / `DO`). `curl "$GATEWAY/health"` fails to connect or does not return the [§8.3.3](#833-first-boot-and-get-health-happy-path) body. Rate-limit stanzas are **not** this failure — omitting them still boots.

**Do:** restore the toml, restart with `--test-scheduled`, wait until `GET /health` is 200 again before the next probe.

#### 8.3.11 Migrations not applied (failure path)

`/health` does not use D1, so skipping apply still looks healthy. Wrangler may auto-apply on `dev`; to force the documented hole, drop the schema on the **local** database only:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT name FROM sqlite_master WHERE type='table' AND name = 'token_contract';"
```

**Do:** drop every platform table (local persist only). A compact force:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "PRAGMA foreign_keys = OFF;
   DROP TABLE IF EXISTS ai_attempt;
   DROP TABLE IF EXISTS usage_event;
   DROP TABLE IF EXISTS grace_admission_queue;
   DROP TABLE IF EXISTS ai_request;
   DROP TABLE IF EXISTS installation_key;
   DROP TABLE IF EXISTS entitlement;
   DROP TABLE IF EXISTS capability_grant;
   DROP TABLE IF EXISTS routing_policy;
   DROP TABLE IF EXISTS kill_switch;
   DROP TABLE IF EXISTS platform_counter;
   DROP TABLE IF EXISTS control_audit;
   DROP TABLE IF EXISTS usage_rollup;
   DROP TABLE IF EXISTS installation;
   DROP TABLE IF EXISTS token_contract;
   PRAGMA foreign_keys = ON;"
```

**Do:** `curl -sS -D- "$GATEWAY/health"` then `curl -sS -D- "$GATEWAY/v1/capabilities" -H "Authorization: Bearer not-a-jwt"`

**Expect:** `/health` still 200 `{build, environment}` — missing tables are not a health failure. `token_contract` SELECT now errors (`no such table`). Any AAT is unable to authenticate: a garbage Bearer is still `unauthenticated` (JWT parse, before D1). A well-formed AAT that passed cheap claim checks would then hit `SELECT * FROM installation` and fail closed (often HTTP 500 / D1 error, not a tidy `unauthenticated`). Either way the request never becomes an admitted job.

**Do:** `npx wrangler d1 migrations apply ai-platform-development --local --env development` and confirm the [§8.3.5](#835-d1-schema-bootstrap-and-seed-row) seed is back before you stop.

#### 8.3.12 Missing provider API key (failure path)

`GET /health` never calls `secretStore.getSecret`. **Do:** confirm the provider secrets are unset without printing other secrets:

```bash
grep -c '^DEEPSEEK_API_KEY=' .dev.vars.development .dev.vars 2>/dev/null
grep -c '^GEMINI_API_KEY=' .dev.vars.development .dev.vars 2>/dev/null
curl -sS "$GATEWAY/health"
```

**Expect:** counts `0` (or the files missing). `/health` still `{"build":"local","environment":"development"}`. Operator bearer may be set; provider keys are independent. Fake-adapter routing does not read these bindings.

Public APIs at this stage **cannot** produce `provider_rejected`. **Forcing (later, not this stage’s happy path):** leave `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` unset, put `deepseek` or `gemini` on the live routing chain (Stage 5), then invoke (Stage 10). The adapter returns taxonomy `provider_rejected` with `missing_api_key` (`DeepSeek API key not found in secret store` / `Gemini API key not found in secret store`) **before** any vendor HTTP. Do not run that invoke here, and do not walk Stage 10’s other failures.

## 9. Failed and cancelled credit

Non-completed terminals still call Quota DO `credit` so `inFlight` is released and the idempotency key leaves `"admitted"`. Request-level settlement taxonomy:

| Terminal | Taxonomy (`ai_request.terminal_error_code`) | `partial` | `idempotencyState` |
| --- | --- | --- | --- |
| Success | — | `false` | `completed` (omitted; mapped from `partial`) |
| `provider_rejected`, `validation_failed` | same code | `false` | `failed` |
| `provider_unavailable`, `cancelled` | same code | `true` | `failed` or `cancelled` |

Per-attempt `timeout` outcomes are retryable-classified (`invocation/index.ts:L104-L110`, `L332`); they appear on `ai_attempt.error_code` only. Chain exhaustion always settles the request as `provider_unavailable`, never `timeout` (`invocation/index.ts:L757-L761`).

