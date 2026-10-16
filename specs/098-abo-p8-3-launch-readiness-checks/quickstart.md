# Quickstart — P8.3 launch readiness checks

**Unit**: P8.3 · **Branch**: `ai/098-abo-p8-3-launch-readiness-checks`

## 1. What was implemented

Read-only `launch-check` script, three JSON fixtures, six procedure runbooks, and the section 5 D3 launch checklist under `ops/launch/`. The harness runs `launch-check.mjs` against fixture paths only. It does not boot wrangler, call Cloudflare, Supabase, or Paymob, or require a live staging or production account.

## 2. Files added under `ops/launch/`

| Path | Role |
| --- | --- |
| `ops/launch/launch-check.mjs` | Read-only launch check (FR-001) |
| `ops/launch/launch-check.test.mjs` | Unit harness (`E2E-P8.3-01`, `E2E-P8.3-02`) |
| `ops/launch/fixtures/production-like.json` | Passing target observation |
| `ops/launch/fixtures/workers-dev-enabled.json` | `workers_dev` failure fixture |
| `ops/launch/fixtures/single-operator-credential.json` | Single-operator failure fixture |
| `ops/launch/pre-launch-installation-deletion.md` | Pre-launch installation deletion runbook |
| `ops/launch/pilot-grant.md` | FR-92 pilot grant runbook |
| `ops/launch/bootstrap-ceremony.md` | Bootstrap ceremony runbook |
| `ops/launch/rotations.md` | Routine credential rotation runbook |
| `ops/launch/compromise-response.md` | Compromise response runbook |
| `ops/launch/rebuilds.md` | Rebuild procedures runbook |
| `ops/launch/checklist.md` | Section 5 D3 launch checklist |

The runbooks and `checklist.md` are the documents the Implements line names. They are not steps the harness runs.

## 3. Harness command (this unit only)

From the repository root:

```bash
node --test ops/launch/launch-check.test.mjs
```

Do not run `npm test` in `e2e/fullstack`. Do not boot wrangler. Do not deploy.

The live H-STG command against a live staging or production account is **not executed** in this workflow because this workflow does not deploy or start wrangler.

## 4. Entry point → module chain per E2E id

| ID | Entry chain | Assertion |
| --- | --- | --- |
| E2E-P8.3-01 | `node ops/launch/launch-check.mjs ops/launch/fixtures/production-like.json` → `ops/launch/launch-check.mjs` | Exit 0 and no failed-condition lines |
| E2E-P8.3-02 | `node ops/launch/launch-check.mjs ops/launch/fixtures/workers-dev-enabled.json` → `ops/launch/launch-check.mjs` | Exit non-zero; stdout is `` `workers_dev` and preview URLs are off `` only |
| E2E-P8.3-02 | `node ops/launch/launch-check.mjs ops/launch/fixtures/single-operator-credential.json` → `ops/launch/launch-check.mjs` | Exit non-zero; stdout is `At least two operator credentials are active` only |
