# Feature Specification: Staging environment, external monitors and the staging profile

**Feature Branch**: `ai/096-abo-p8-1-staging-environment-external-monitors-profile`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P8.1 — Staging environment, external monitors and the staging profile

## 1. Unit Contract

**Implements** — Read: 05 §6.1; 02 §1.4 (last paragraph); 02 §4.4; 02 §5; 05 §1 (External row); 05 §2 row AL-21; 01 §7 row R-6; 05 §7.

- Staging wrangler envs in a separate Cloudflare account (staging `DURATION_SCALE`, Access application, Email Routing destination, R2 bucket lock); a staging Supabase project + migration deploy; Paymob test-integration secrets and callback URL; external heartbeat monitor (ABO minute, platform 5-min, digest daily) and hourly audit-log watcher with a read-only token, configured as code; the three test offers (20/60/240 credits) published through the console; R-4 confirmed on hosted Supabase; NFR-08 cost check recorded.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P7.1: None. The P7.1 unit row states no Outputs / freezes line.

**Open questions relied on** — None. The Read line and the Implements line name no §6 open question.

**Spikes** — R-4 (rule S6; 01 §7 row R-4): confirm on hosted Supabase that pg_cron at 30 s with two-phase pg_net holds under overlapping runs, response size limits, and growth of `cron.job_run_details`. Fallback if it fails: a longer pull interval within the bound (05 §10 Spike-dependent items, named by rule S6). R-6 (01 §7 row R-6; rule S6): the mitigation is the policy — no CI or stored production token; a separate staging account; a read-only audit-log watcher outside Cloudflare.

## Clarifications

### Session 2026-10-08

- Q: Where do the H-STG scenarios live, and which ones run as code? → A: They live under `e2e/fullstack/staging/`, as the H-FS runner pointed at staging config. E2E-P8.1-04 is one Node test whose title starts with that id: the staging `workers.dev` and preview URLs are unreachable, and the ops host requires Access. E2E-P8.1-01, E2E-P8.1-02, and E2E-P8.1-03 are scripted checklist items in that same directory, one item per id. The monitor item confirms AL-21 on the monitor's own channel after the ABO cron is disabled. The watcher item confirms an alert within the hour of a staging deploy and a secret change. The purchase item uses a Paymob test card, then `get_ai_status`, a term of 30 minutes, and grace of about 7 minutes. The checklist does not add a miss window, an HTTP status code, or an alert body field. `[implementation choice — no §citation]`
- Q: Where do the external heartbeat monitor and the hourly audit watcher live? → A: Checked-in ops scripts in `ops/staging/`, outside both Workers and outside Supabase. The monitor config expects the three pings already named — ABO minute, platform 5-minute, and ABO daily digest — at `HEARTBEAT_URL`, and a missing ping raises AL-21 on the monitor's own channel. The watcher script runs hourly on that same external scheduler, uses a read-only token, and alerts on a production deploy, a secret change, a D1 export, and an Access policy edit. The plan maps those four classes onto the provider's audit read. This clarification adds no vendor SDK inside either Worker, no token field, and no API event name. `[implementation choice — no §citation]`
- Q: How are the staging env, the Supabase project, and the NFR-08 record laid out? → A: Each Worker keeps a single `[env.staging]` in its existing wrangler file. Both blocks set `workers_dev = false` and `preview_urls = false`. The platform block sets `DURATION_SCALE` and `HEARTBEAT_URL`. The ABO block sets `HEARTBEAT_URL`. Access, the Email Routing destination, the R2 bucket lock, Paymob test-integration secrets, and the callback URL stay on the staging checklist, and secret values stay out of git. The checklist deploys the existing backend migrations to the separate Supabase project and records the NFR-08 comparison against that account's plan. No new migration, no new binding name, and no second config file. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Staging profile runs a monthly test purchase (Priority: P1)

A clinic administrator, on the staging profile, buys the Monthly test offer with a Paymob test card. Staging is a separate Cloudflare account and Supabase project. The platform's `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute. The three test offers are published through the console. The purchase leaves AI active in about 1 minute; the term ends after 30 minutes; grace lasts about 7 minutes. R-4 is confirmed on that hosted Supabase project. The NFR-08 cost check is recorded against the account's plan.

**Why this priority**: The external monitor, the audit watcher, and the ops-host Access check run against this staging profile. This is the story those checks use.

**Independent Test**: E2E-P8.1-03 in H-STG.

**Acceptance Scenarios**:

1. **Given** the staging profile (separate Cloudflare account and Supabase project, Paymob test integration, migrations deployed, test-integration secrets and callback URL configured) and the three console-published test offers — Monthly (1 month, runs 30 minutes, grace about 7 minutes, 20 credits), Quarterly (3 months, runs 90 minutes, grace about 7 minutes, 60 credits), and Annual (12 months, runs 6 hours, grace about 7 minutes, 240 credits) — **When** the administrator completes a monthly test purchase with a Paymob test card, **Then** AI is active in about 1 minute, the term ends after 30 minutes, and grace lasts about 7 minutes. (E2E-P8.1-03, 05 §6.1, 02 §1.4)

### 2.2 User Story 2 - Staging hostnames stay closed (Priority: P2)

An operator finds `workers.dev` and preview URLs unreachable. The ops host requires Access. Both Workers set `workers_dev = false` and `preview_urls = false`, so the Access-protected console has no bypass hostname.

**Why this priority**: User Story 1's purchase uses the billing host. This story is the exposure check on the same staging account.

**Independent Test**: E2E-P8.1-04 in H-STG.

**Acceptance Scenarios**:

1. **Given** the staging Workers, **When** a caller opens a `workers.dev` URL or a preview URL, **Then** that URL is unreachable. **When** a caller opens the ops host, **Then** the host requires Access. (E2E-P8.1-04, 02 §1.4)

### 2.3 User Story 3 - External monitor and audit watcher alert (Priority: P3)

The external heartbeat monitor, outside Cloudflare and Supabase, watches pings to `HEARTBEAT_URL` from the ABO minute cron, the platform 5-minute cron, and the ABO daily digest. With the ABO cron disabled, the monitor raises AL-21 over its own channel. The same external scheduler runs the hourly audit-log watcher with a read-only token. A staging deploy and a secret change make the watcher alert within the hour.

**Why this priority**: User Story 1 stands up the account and `HEARTBEAT_URL`. This story is the dead-man's-switch and the A26 detection on that account.

**Independent Test**: E2E-P8.1-01 and E2E-P8.1-02 in H-STG. Earlier suites stay green (rule S2).

**Acceptance Scenarios**:

1. **Given** the ABO cron is disabled, **When** the heartbeat monitor runs, **Then** it raises AL-21 over its own channel. (E2E-P8.1-01, 05 §2 row AL-21, 02 §5) [NFR-04]
2. **Given** the hourly audit-log watcher with a read-only token, **When** a staging deploy and a secret change occur, **Then** the watcher alerts within the hour. (E2E-P8.1-02, 02 §4.4, 05 §1 External row, 05 §2 row AL-21) [A26 detection]

### 2.4 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P8.1-01 | H-STG (`e2e/fullstack/staging/`) | External heartbeat monitor, configured as code, on the external scheduler (05 §1 External row). It watches missing pings to `HEARTBEAT_URL` (02 §5). ABO pings from `scheduled()` (`abo/src/worker.ts` `pingHeartbeat`); platform pings from `scheduled()` cron `*/5 * * * *` → `runFiveMinuteCron` → `pingPlatformHeartbeat` (`ai-platform/src/worker.ts`, `ai-platform/src/alert/index.ts`) | ABO cron disabled → the heartbeat monitor raises AL-21 over its own channel [NFR-04] | FR-008 | User Story 3 |
| E2E-P8.1-02 | H-STG (`e2e/fullstack/staging/`) | Hourly audit-log watcher, configured as code, on the same external scheduler (05 §1 External row), with a read-only token (01 §7 row R-6, Implements) | A staging deploy and a secret change → the watcher alerts within the hour [A26 detection] | FR-009 | User Story 3 |
| E2E-P8.1-03 | H-STG (`e2e/fullstack/staging/`) | Billing host `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/clinic-api/checkouts.ts`) via `handleBillingV1` (`abo/src/worker.ts`), Paymob test card (05 §6.1). AI active is `public.get_ai_status`. Term and grace follow the platform staging `DURATION_SCALE` (`ai-platform/wrangler.toml` `[env.staging]`) | Smoke: monthly test purchase with a Paymob test card → AI active in about 1 min; term ends after 30 min; grace about 7 min | FR-005 | User Story 1 |
| E2E-P8.1-04 | H-STG (`e2e/fullstack/staging/`) | HTTP to the Workers' `workers.dev` and preview URLs, and to the ops host `handleOps` (`abo/src/worker.ts`) → `verifyOpsAccess` (`abo/src/ops/index.ts`) | `workers.dev` and preview URLs unreachable; the ops host requires Access | FR-010 | User Story 2 |

### 2.5 Edge Cases

- With the ABO cron disabled, the heartbeat monitor raises AL-21 over its own channel. The monitor sits outside Cloudflare and Supabase. Alert bodies carry codes and ids only. (E2E-P8.1-01, 02 §5, 05 §2 row AL-21) [NFR-04]
- AL-21 also covers an audit event: production deploy, secret change, D1 export, Access policy edit. Raised by External, repeated per event. (05 §2 row AL-21, 02 §4.4)
- A staging deploy and a secret change make the hourly watcher alert within the hour. The watcher uses a read-only token. (E2E-P8.1-02, 05 §1 External row, 01 §7 row R-6) [A26 detection]
- A26 holds under this operating policy: production deploys and secret changes happen only from the developer's interactive session with hardware-key MFA; no CI system or stored token has production rights. (02 §4.4, 01 §7 row R-6)
- `workers.dev` and preview URLs are unreachable. The ops host requires Access. Both Workers set `workers_dev = false` and `preview_urls = false`. (E2E-P8.1-04, 02 §1.4)
- The ABO rejects `/ops/*` on the billing hostname and `/v1/*` on the console hostname. Both crossings answer HTTP 404 with an empty body, before the contract-version check and before authentication. That body is not an 04 §2.3 error. (02 §1.4 last paragraph)
- If the R-4 spike fails, the fallback is a longer pull interval within the bound. (01 §7 row R-4, rule S6, 05 §10 Spike-dependent items)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: Staging MUST run in a separate Cloudflare account and Supabase project with the Paymob test integration. (02 §1.4 last paragraph, 01 §7 row R-6)
- **FR-002**: Staging wrangler envs MUST include the platform staging `DURATION_SCALE`, which maps 1 month to 30 minutes and 1 day to 1 minute, an Access application, an Email Routing destination, and an R2 bucket lock. Both Workers MUST set `workers_dev = false` and `preview_urls = false`. (Implements, 05 §6.1, 02 §1.4, 02 §5)
- **FR-003**: A staging Supabase project MUST receive the migration deploy. Paymob test-integration secrets and the callback URL MUST be configured. The Paymob test integration supplies test cards. (Implements, 05 §6.1)
- **FR-004**: The three test offers MUST be published through the console. Offers use the production units and validation. Monthly: offer term 1 month, runs 30 minutes, grace about 7 minutes, allowance 20 credits. Quarterly: offer term 3 months, runs 90 minutes, grace about 7 minutes, allowance 60 credits. Annual: offer term 12 months, runs 6 hours, grace about 7 minutes, allowance 240 credits. (05 §6.1, Implements)
- **FR-005**: A monthly test purchase with a Paymob test card MUST leave AI active in about 1 minute. The term MUST end after 30 minutes. Grace MUST last about 7 minutes. (E2E-P8.1-03, 05 §6.1)
- **FR-006**: R-4 MUST be confirmed on hosted Supabase: pg_cron at 30 s with two-phase pg_net, covering overlapping runs, response size limits, and growth of `cron.job_run_details`. If the spike fails, the pull interval MUST lengthen and MUST stay within the bound. (Implements, 01 §7 row R-4, rule S6, 05 §10 Spike-dependent items)
- **FR-007**: The NFR-08 cost check MUST be recorded against the account's plan. The steady load in 05 §7 stays inside the included allowances of the Cloudflare Workers Paid plan and the Supabase project. (05 §7, Implements)
- **FR-008**: An external heartbeat monitor, outside Cloudflare and Supabase and configured as code, MUST alert on any missing ping. The ABO minute cron, the platform 5-minute cron, and the ABO daily digest each ping `HEARTBEAT_URL`. A missing ping MUST raise AL-21 over the monitor's own channel. With the ABO cron disabled, the monitor MUST raise AL-21. (02 §5, 05 §1 External row, 05 §2 row AL-21, Implements, E2E-P8.1-01) [NFR-04]
- **FR-009**: The same external scheduler MUST run the hourly audit-log watcher with a read-only token, configured as code. The watcher MUST alert on a production deploy, a secret change, a D1 export, and an Access policy edit. A staging deploy and a secret change MUST make the watcher alert within the hour. (02 §4.4, 02 §5, 05 §1 External row, 05 §2 row AL-21, 01 §7 row R-6, Implements, E2E-P8.1-02) [A26 detection]
- **FR-010**: `workers.dev` and preview URLs MUST be unreachable. The ops host MUST require Access. (02 §1.4, E2E-P8.1-04)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: wrangler envs (ai-platform, abo), backend config, `e2e/fullstack/staging/`, ops scripts. That is the codebase cell the unit row names (rule S3). `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic administrator can buy the Monthly test offer on staging and see AI become active, the term end, and grace elapse in compressed time. The profile serves a small-to-mid-size clinic checking purchase, lapse, and grace before launch. (05 §6.1, E2E-P8.1-03)
- **Layer Placement**: Staging wrangler envs live on the AI Platform and ABO Workers. The staging Supabase project and migration deploy live in backend config. The heartbeat monitor and audit watcher are ops scripts outside Cloudflare and Supabase, configured as code. H-STG is the full-stack runner with staging config under `e2e/fullstack/staging/`. (Implements, 02 §5, rule V1)
- **Data Integrity & Security**: Staging uses a separate Cloudflare account and Supabase project. The watcher holds a read-only token. The ops host is a Cloudflare Access application, and the Worker validates the Access JWT. `workers_dev` and preview URLs stay off. Cross-host paths answer HTTP 404 with an empty body before the contract-version check and before authentication. Production deploys and secret changes stay on the 02 §4.4 operating policy. (02 §1.4, 02 §4.4, 01 §7 row R-6)
- **Failure Handling**: A missing heartbeat ping raises AL-21 on the monitor's own channel, outside Cloudflare and Supabase. A staging deploy or secret change raises the watcher alert within the hour. The R-4 fallback, if the hosted spike fails, is a longer pull interval within the bound. (E2E-P8.1-01, E2E-P8.1-02, 02 §5, rule S6)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P7.1 states no Outputs / freezes line.
- No module that no test-plan row reaches (rule S8). The P2.2 and package-half P2.1 exception does not apply. The heartbeat monitor is reached by E2E-P8.1-01. The audit watcher is reached by E2E-P8.1-02. The monthly test purchase, the three offers, and the platform `DURATION_SCALE` are reached by E2E-P8.1-03. `workers.dev`, preview URLs, and the ops host Access application are reached by E2E-P8.1-04.
- The local HMAC replay fixture, the inquiry stub, and the version matrix in 05 §6.1 ("Before staging") stay with P4.2/P4.3 and P7.3. This unit owns the staging profile (section 5, D1, 05 §6.1).
- §8 acceptance scenarios are staging tests on this profile (05 §6.1, FR-90). Section 5, D1 assigns 05 §8 to P8.2. This unit's E2E list is E2E-P8.1-01 through E2E-P8.1-04. D2 assigns A26 detection to E2E-P8.1-02 and leaves the policy part Partial.
- No S9 transitional path is named on this unit row.
- No codebase beyond wrangler envs (ai-platform, abo), backend config, `e2e/fullstack/staging/`, and ops scripts.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P8.1-01 is green in H-STG.
- **SC-002**: E2E-P8.1-02 is green in H-STG.
- **SC-003**: E2E-P8.1-03 is green in H-STG.
- **SC-004**: E2E-P8.1-04 is green in H-STG.
- **SC-005**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- None. The Read line and the Implements line name no §6 default. The unit row names no S9 transitional path.
