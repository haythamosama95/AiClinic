# Quickstart — P8.2 staging acceptance A1–A36

**Unit**: P8.2 · **Branch**: `ai/097-abo-p8-2-staging-acceptance-a1-a36`

## 1. What was implemented

H-STG staging acceptance harness for scenarios STG-A01 through STG-A36 and failure-mode drills STG-FM-12, STG-FM-13, and STG-FM-14. Each scenario is a `node:test` runner under `e2e/fullstack/staging/` that records the operator procedure, `[env.staging]`, `DURATION_SCALE`, Paymob test cards, the entry chain, and the assertion. Runners read an evidence template under `evidence/` and fail while the template, citation, or `## Result` section is absent. STG-A01, STG-A03, STG-A04, and STG-A16 also read a manual checklist under `manual/`. The harness does not boot wrangler, call Cloudflare, Supabase, or Paymob, or require a live staging account.

## 2. Files added

| Path | Role |
| --- | --- |
| `e2e/fullstack/staging/stg-a01.mjs` … `stg-a36.mjs` | STG-A01–STG-A36 runners |
| `e2e/fullstack/staging/stg-fm-12.mjs`, `stg-fm-13.mjs`, `stg-fm-14.mjs` | STG-FM-12–STG-FM-14 runners |
| `e2e/fullstack/staging/evidence/stg-a01.md` … `stg-a36.md` | Evidence templates for STG-A01–STG-A36 |
| `e2e/fullstack/staging/evidence/stg-fm-12.md`, `stg-fm-13.md`, `stg-fm-14.md` | Evidence templates for STG-FM-12–STG-FM-14 |
| `e2e/fullstack/staging/manual/paymob-test-card.md` | STG-A01 checklist |
| `e2e/fullstack/staging/manual/blocked-notify-url.md` | STG-A03 checklist |
| `e2e/fullstack/staging/manual/disabled-platform-route.md` | STG-A04 checklist |
| `e2e/fullstack/staging/manual/dashboard-refund.md` | STG-A16 checklist |
| `specs/097-abo-p8-2-staging-acceptance-a1-a36/quickstart.md` | This file |

No files under `abo/`, `ai-platform/`, `backend/`, `frontend/`, or `packages/vendor-contracts/` were modified. P8.1 files in `e2e/fullstack/staging/` and `e2e/fullstack/package.json` are unchanged.

## 3. Harness command (this unit only)

From the repository root:

```bash
node --test e2e/fullstack/staging/stg-a*.mjs e2e/fullstack/staging/stg-fm-*.mjs
```

Do not run `npm test` in `e2e/fullstack`. Do not boot wrangler. Do not deploy.

The live H-STG command against a live staging account is **not executed** in this workflow because this workflow does not deploy or start wrangler.

## 4. Entry point → module chain per E2E id

| ID | Entry chain |
| --- | --- |
| STG-A01 | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/clinic-api/checkouts.ts`, `abo/src/worker.ts`); `POST /notify/paymob`; `GET /v1/payments`; `public.get_ai_status`; `public.request_ai_status_refresh` |
| STG-A02 | `public.get_ai_status`; `GET /v1/checkouts` (`abo/src/worker.ts`) |
| STG-A03 | `scheduled()` (`abo/src/worker.ts`) |
| STG-A04 | `scheduled()` (`abo/src/worker.ts`) |
| STG-A05 | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) |
| STG-A06 | `GET /v1/payments` (`abo/src/worker.ts`) |
| STG-A07 | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) |
| STG-A08 | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) |
| STG-A09 | Clinic DO term placement after `POST /v1/checkouts` |
| STG-A10 | Clinic DO alarm |
| STG-A11 | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) |
| STG-A12 | `public.issue_billing_token`; `POST /v1/checkouts` (`abo/src/worker.ts`) |
| STG-A13 | Issuer-key rotation, then `POST /v1/checkouts` (`abo/src/worker.ts`) |
| STG-A14 | HP `beginTransfer` (`abo/src/worker.ts`, `abo/src/ops/index.ts`), then `transferOut` and `transferIn` |
| STG-A15 | Ops host HP manual chargeback (`abo/src/worker.ts`) |
| STG-A16 | Checklist `manual/dashboard-refund.md`; `scheduled()` inquiry (`abo/src/worker.ts`) |
| STG-A17 | Ops host HP chargeback, effect `none` (`abo/src/worker.ts`) |
| STG-A18 | Payout import, then ops host HP chargeback (`abo/src/worker.ts`) |
| STG-A19 | Complimentary trial term, then `POST /v1/checkouts` (`abo/src/worker.ts`) |
| STG-A20 | Ops host HP complimentary grant (`abo/src/worker.ts`) |
| STG-A21 | `GET /v1/offers` (`abo/src/worker.ts`) |
| STG-A22 | `public.issue_billing_token`; clinic billing routes (`abo/src/worker.ts`) |
| STG-A23 | `scheduled()` (`abo/src/worker.ts`) |
| STG-A24 | Ops host HP delete (`abo/src/worker.ts`) |
| STG-A25 | Issuer-key expiry path |
| STG-A26 | Ops host HP method (`abo/src/worker.ts`); audit watcher |
| STG-A27 | Ops host HP complimentary grant (`abo/src/worker.ts`) |
| STG-A28 | `public.get_ai_status`; `public.issue_billing_token`; `GET /v1/coverage` |
| STG-A29 | Clinic admission |
| STG-A30 | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) |
| STG-A31 | Clinic admission, then `POST /v1/checkouts` (`abo/src/worker.ts`) |
| STG-A32 | Clinic admission |
| STG-A33 | `GET /v1/offers` (`abo/src/worker.ts`) |
| STG-A34 | Clinic DO admission |
| STG-A35 | PostgREST |
| STG-A36 | ABO routes (`abo/src/worker.ts`) and PostgREST RPCs |
| STG-FM-12 | `scheduled()` (`abo/src/worker.ts`) after the scripted outage window |
| STG-FM-13 | Scripted bad deploy, rollback, and retry of parked rows |
| STG-FM-14 | Scripted bad deploy, rollback, and retry of parked rows |

## 5. Manual steps (four checklists)

These behaviours cannot be verified by the harness alone. Follow the checklist for the scenario, then complete `## Result` in the matching evidence file.

### STG-A01 — `manual/paymob-test-card.md`

Paymob test card for 1, 3, and 12 months on the three staging offers (Monthly, Quarterly, Annual). Complete checkout with a Paymob test card for each term length; confirm AI active within about a minute, payment in history, full allowance, desktop Active, and `public.request_ai_status_refresh()` called.

### STG-A03 — `manual/blocked-notify-url.md`

Blocked notify URL; sweep inquires at +2, +5, +10, and +20 minutes via `scheduled()` and provisions the payment; AL-03 raised.

### STG-A04 — `manual/disabled-platform-route.md`

Platform route disabled for 4 days; grant retries every 15 minutes via `scheduled()`; AL-04 hourly while down; grant applies on return; term starts at activation.

### STG-A16 — `manual/dashboard-refund.md`

Dashboard refund as parent flags or a child transaction, folded into a reversal; inquiry via `scheduled()` confirms; AL-06 raised; lost-callback bounds in 05 §8 A16 respected.
