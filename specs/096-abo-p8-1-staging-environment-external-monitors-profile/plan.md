# Implementation Plan: Staging environment, external monitors and the staging profile

**Branch**: `ai/096-abo-p8-1-staging-environment-external-monitors-profile` | **Date**: 2026-10-08 | **Spec**: `specs/096-abo-p8-1-staging-environment-external-monitors-profile/spec.md`

**Input**: Feature specification from `specs/096-abo-p8-1-staging-environment-external-monitors-profile/spec.md`

## Summary

P8.1 stands up the staging profile in the existing Worker `[env.staging]` blocks, records the account checklist (separate Cloudflare account, Supabase project, Paymob test integration, three console offers, NFR-08), and adds the external heartbeat monitor and hourly audit watcher as ops scripts. It depends on P7.1 (phase P8, size M). P7.1 freezes nothing, so this unit consumes no module.

## Technical Context

**Language/Version**: Existing Worker TypeScript (`abo/`, `ai-platform/`), TOML wrangler config, Node checklist runner under `e2e/fullstack/staging/`, plain Node scripts under `ops/staging/`

**Primary Dependencies**: Existing `scheduled()` handlers, `pingHeartbeat`, `pingPlatformHeartbeat`, `handlePostCheckout`, `handleOps` / `verifyOpsAccess`, and `public.get_ai_status`. No new library, vendor SDK, binding name, or second config file.

**Storage**: No new store and no new migration. Staging deploys the existing `backend/supabase/migrations/` set. `ai_coverage_feed_pull` stays `30 seconds` (research §1).

**Testing**: H-STG (`e2e/fullstack/staging/`). E2E-P8.1-04 is one Node test. E2E-P8.1-01, E2E-P8.1-02, and E2E-P8.1-03 are scripted checklist items, one per id. Title prefix is the E2E id (rule V3). Live staging runs and H-STG against a live account are not executed in this workflow. The harness does not boot wrangler and does not call Cloudflare, Supabase, or Paymob.

**Target Platform**: Repo configuration, ops scripts, and the H-STG directory. The unit row names wrangler envs (`ai-platform`, `abo`), backend config (the existing migration set, cited by the checklist), `e2e/fullstack/staging/`, and ops scripts.

**Project Type**: Staging profile plus external monitor and watcher (02 §5, 05 §1 External row)

**Performance Goals**: Staging `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute (05 §6.1). A monthly test purchase leaves AI active in about 1 minute, the term ends after 30 minutes, and grace lasts about 7 minutes. The watcher schedule is hourly. The checklist adds no miss window.

**Constraints**: Both `[env.staging]` blocks set `workers_dev = false` and `preview_urls = false`. The platform block sets `DURATION_SCALE` and `HEARTBEAT_URL`. The ABO block sets `HEARTBEAT_URL`. Access, the Email Routing destination, the R2 bucket lock, Paymob test-integration secrets, and the callback URL stay on the checklist. Secret values stay out of git. Alert output is the code `AL-21` on the script's own stdout. No alert body field, HTTP status, token field, or API event name. No test clock binding on staging.

**Scale/Scope**: Four H-STG scenarios. Steady load recorded for NFR-08 is the 05 §7 list: about 1,440 ABO cron runs, 288 platform cron runs, 2,880 backend pulls, about 2,250 reversal inquiries a day at the stated o/L/P example, and about two DO row writes per AI request. That record states this load stays inside the Cloudflare Workers Paid plan and the Supabase project's included allowances.

### Audit-read classes

The watcher does not call a provider API. It classifies audit-read entries the checklist supplies. The plan maps the four FR-009 classes onto these entry classes:

| FR-009 class | Entry class |
| --- | --- |
| Production deploy | `deploy` |
| Secret change | `secret` |
| D1 export | `d1_export` |
| Access policy edit | `access_policy` |

A staging deploy uses class `deploy`. Any of the four classes prints `AL-21`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after design. 02 §7 records no violation. This unit adds no service, queue, store, or migration.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — 02 §7 principle I and spec §4 Clinic Fit: one administrator buys the Monthly test offer on the compressed staging profile.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — 02 §7 principle I and 05 §7. The monitor and watcher are ops scripts outside Cloudflare and Supabase, the parts 02 §5 and 05 §1 already name. No queue and no new server.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — 02 §7 principle II. Wrangler envs stay on the Workers. The migration set stays in backend config. The scripts do not take a database credential.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — 02 §7 principle III. This unit adds no write path. The pull schedule stays the existing `cron.schedule` of `auth_internal.pull_coverage_feed()`.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — 02 §7 principle IV. The ops host path calls `verifyOpsAccess`. `workers_dev` and preview URLs stay off. The watcher token is an environment value, not a git file. R-6 keeps production rights off CI and off stored tokens (02 §4.4).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — 02 §7 principles II and V. The monthly purchase uses the existing checkout and grant path. A missing heartbeat raises AL-21 outside Cloudflare and does not lock the clinic.

## Project Structure

### Documentation (this feature)

```text
specs/096-abo-p8-1-staging-environment-external-monitors-profile/
├── plan.md
├── spec.md
├── research.md          # R-4 and R-6, written in this phase
└── quickstart.md        # Outline only here. Implement writes it after harness green
```

`data-model.md` is omitted (no entities). `contracts/` is omitted (Freezes: None). `tasks.md` is not created in this phase.

#### Quickstart outline

Implement writes `quickstart.md` after this unit's harness is green. Sections only:

- What was implemented; files added and modified
- Harness commands for this unit's tests only (the commands in Sequencing)
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour
- The live H-STG command against a live account is not executed in this workflow

### Source Code (repository root)

```text
ai-platform/wrangler.toml          # [env.staging] flags and existing DURATION_SCALE, HEARTBEAT_URL
abo/wrangler.toml                  # [env.staging] flags and existing HEARTBEAT_URL
abo/src/worker.ts                  # minute cron calls pingHeartbeat

ops/staging/
├── heartbeat-monitor.mjs
├── audit-watcher.mjs
├── nfr-08.md
└── fixtures/
    ├── abo-cron-disabled.json
    └── deploy-and-secret.json

e2e/fullstack/staging/
├── p8-1-04.test.mjs
├── p8-1-01.checklist.md
├── p8-1-02.checklist.md
├── p8-1-03.checklist.md
└── run-checklists.mjs
```

**Structure Decision**: Each Worker keeps its single `[env.staging]` block. Ops scripts live under `ops/staging/`, outside both Workers and outside Supabase. H-STG lives under `e2e/fullstack/staging/`. Backend config is the existing `backend/supabase/migrations/` tree the checklist names. No file is added under `backend/`, and `e2e/fullstack/package.json` is not edited.

## Consumes Binding

| Consumes | Binding |
| --- | --- |
| P7.1 | None. The unit row states no Outputs / freezes line. |

This unit does not modify a consumed module.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `e2e/fullstack/staging/p8-1-04.test.mjs` | Create. Node test, title prefix `E2E-P8.1-04` | FR-010 |
| `e2e/fullstack/staging/p8-1-01.checklist.md` | Create. One checklist item, heading prefix `E2E-P8.1-01` | FR-008 |
| `e2e/fullstack/staging/p8-1-02.checklist.md` | Create. One checklist item, heading prefix `E2E-P8.1-02` | FR-009 |
| `e2e/fullstack/staging/p8-1-03.checklist.md` | Create. One checklist item, heading prefix `E2E-P8.1-03` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 |
| `e2e/fullstack/staging/run-checklists.mjs` | Create. Runs the three checklist items against the ops scripts and fixtures | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `ops/staging/heartbeat-monitor.mjs` | Create. Three expected pings; a missing ping prints `AL-21` | FR-008 |
| `ops/staging/fixtures/abo-cron-disabled.json` | Create. ABO minute ping absent | FR-008 |
| `ops/staging/audit-watcher.mjs` | Create. Hourly entry; classifies the four entry classes; prints `AL-21` | FR-009 |
| `ops/staging/fixtures/deploy-and-secret.json` | Create. Classes `deploy` and `secret` | FR-009 |
| `ops/staging/nfr-08.md` | Create. 05 §7 load compared with the Workers Paid plan and the Supabase allowances | FR-007 |
| `ai-platform/wrangler.toml` | Modify `[env.staging]` only: set `workers_dev = false` and `preview_urls = false` on that block. Keep `DURATION_SCALE = "staging"` and `HEARTBEAT_URL` | FR-002, FR-010 |
| `abo/wrangler.toml` | Modify `[env.staging]` only: set `workers_dev = false` and `preview_urls = false` on that block. Keep `HEARTBEAT_URL` | FR-002, FR-010 |
| `abo/src/worker.ts` | Modify the `* * * * *` branch so it calls `pingHeartbeat` | FR-008 |
| `specs/096-abo-p8-1-staging-environment-external-monitors-profile/research.md` | Written in this phase | FR-006, FR-009 |
| `specs/096-abo-p8-1-staging-environment-external-monitors-profile/quickstart.md` | Implement writes this after harness green, from the outline above | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 |

No new migration, no new binding, no second wrangler or Supabase config file, no edit to `e2e/fullstack/package.json`, and no secret value committed.

`ops/staging/nfr-08.md` is the NFR-08 record. It copies the steady-load figures from 05 §7 and states they stay inside the included allowances. It does not call a billing API.

The E2E-P8.1-03 checklist is the account record: separate Cloudflare account and Supabase project, Paymob test integration, test cards and callback URL configured outside git, Email Routing destination, R2 bucket lock, Access application on the ops host, deploy of the existing migrations, the three offers (Monthly 20 credits / 30 minutes / grace about 7 minutes, Quarterly 60 credits / 90 minutes / grace about 7 minutes, Annual 240 credits / 6 hours / grace about 7 minutes), the monthly purchase outcome (`get_ai_status` active in about 1 minute, term 30 minutes, grace about 7 minutes), and a line that the hosted R-4 command is not executed here while the pull stays `30 seconds`.

## Test Layout

Tests and checklist items are authored first and fail before the script, fixture, wrangler flag, or minute ping they require. One item per id. The checklist runner does not add a miss window, an HTTP status, or an alert body field.

| ID | Harness | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P8.1-01 | H-STG checklist `p8-1-01.checklist.md` via `run-checklists.mjs` | `ops/staging/heartbeat-monitor.mjs` on fixture `abo-cron-disabled.json`. Expected pings: ABO minute (`abo/src/worker.ts` `scheduled()` `* * * * *` → `pingHeartbeat`), platform 5-minute (`ai-platform/src/worker.ts` `scheduled()` `*/5 * * * *` → `runFiveMinuteCron` → `pingPlatformHeartbeat`), ABO daily digest (`scheduled()` `0 6 * * *` → `pingHeartbeat`). Config names `HEARTBEAT_URL` | ABO minute ping absent → stdout is `AL-21`. The checklist also requires the minute branch to call `pingHeartbeat` |
| E2E-P8.1-02 | H-STG checklist `p8-1-02.checklist.md` via `run-checklists.mjs` | `ops/staging/audit-watcher.mjs` on fixture `deploy-and-secret.json`. Hourly entry. Token is not read in fixture mode | Classes `deploy` and `secret` → stdout is `AL-21`. The checklist states the job is hourly and the token is read-only and not stored in git |
| E2E-P8.1-03 | H-STG checklist `p8-1-03.checklist.md` via `run-checklists.mjs` | Checklist text. Purchase chain, not executed live: `POST /v1/checkouts` → `handleBillingV1` → `handlePostCheckout`; AI active is `public.get_ai_status`; term and grace follow platform `[env.staging]` `DURATION_SCALE = "staging"` | The item names the Paymob test card, active in about 1 minute, term 30 minutes, grace about 7 minutes, the three offers, the account checklist, `ops/staging/nfr-08.md`, and the unexecuted hosted R-4 command |
| E2E-P8.1-04 | H-STG Node test `p8-1-04.test.mjs` (`node:test`) | Parse `[env.staging]` in `ai-platform/wrangler.toml` and `abo/wrangler.toml`. Ops chain, read as source: `abo/src/worker.ts` `fetch` → `handleOps` → `dispatchOps` → `verifyOpsAccess` | Both staging blocks set `workers_dev = false` and `preview_urls = false`. The ops path calls `verifyOpsAccess`. No live hostname is opened |

E2E-P8.1-01 reaches `heartbeat-monitor.mjs` and the minute `pingHeartbeat` call. E2E-P8.1-02 reaches `audit-watcher.mjs`. E2E-P8.1-03 reaches the account checklist and `nfr-08.md`. E2E-P8.1-04 reaches the two `[env.staging]` blocks and the ops Access path.

## Sequencing

1. Author `p8-1-04.test.mjs` and the three checklist files plus `run-checklists.mjs` so they fail before the flags, minute ping, scripts, and fixtures exist.
2. Add the wrangler flags, the minute `pingHeartbeat` call, the ops scripts, the fixtures, and `nfr-08.md`.
3. This plan workflow does not run the harness, does not boot wrangler, and does not deploy. Implement runs the commands below until they pass, then writes `quickstart.md`.

Commands, this unit only. They do not boot a worker and they do not call a live account:

- `node --test e2e/fullstack/staging/p8-1-04.test.mjs`
- `node e2e/fullstack/staging/run-checklists.mjs`

Do not point these commands at earlier suites or at `npm test` in `e2e/fullstack/`.

Task grain for the next phase is one task per path in Files, excluding `research.md` (already written) and including the later quickstart task. That is 14 tasks. The work is the files above; it is not padded to the M minimum.

## Complexity Tracking

None. 02 §7 records no constitution violation for this unit.
