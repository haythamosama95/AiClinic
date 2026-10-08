# Feature Specification: Staging acceptance A1–A36

**Feature Branch**: `ai/097-abo-p8-2-staging-acceptance-a1-a36`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P8.2 — Staging acceptance A1–A36

## 1. Unit Contract

**Implements** — Read: 05 §8; 05 §6.1; 00 §11.

- STG-A01…STG-A36 as runner scripts, with scripted manual steps (dashboard refund, test cards, blocked notify URL, disabled platform route); an evidence report per scenario citing the earlier E2E IDs (section 5, D2); FM drills STG-FM-12 (catch-up after an outage window), STG-FM-13/14 (bad deploy, rollback, retry parked).

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P8.1: None. P7.2: None. P7.3: None. Those unit rows state no Outputs / freezes line.

**Open questions relied on** — None. The Read line and the Implements line name no §6 open question.

**Spikes** — None. Rule S6 names no spike for P8.2.

## Clarifications

### Session 2026-10-08

- Q: Where do the thirty-nine staging scenario runners live, and how is each one split from the others? → A: One Node runner script per scenario id directly under `e2e/fullstack/staging/`, named with the scenario id (`stg-a01` through `stg-a36`, `stg-fm-12`, `stg-fm-13`, `stg-fm-14`). Each script is the H-STG entry for that id: the existing H-FS runner pointed at the staging profile (staging config, Paymob test cards, `DURATION_SCALE`). No second runner and no new configuration names. `[implementation choice — no §citation]`
- Q: Where do the scripted manual steps for the dashboard refund, Paymob test cards, the blocked notify URL, and the disabled platform route live? → A: Four checklist files in `e2e/fullstack/staging/manual/`: `paymob-test-card.md` (STG-A01), `blocked-notify-url.md` (STG-A03), `disabled-platform-route.md` (STG-A04), and `dashboard-refund.md` (STG-A16). The matching runner script includes that checklist. The other scenario scripts have no manual checklist. `[implementation choice — no §citation]`
- Q: What artifact is the evidence report this unit writes for each scenario? → A: One markdown template per scenario under `e2e/fullstack/staging/evidence/`, named with the scenario id. The template already cites that scenario's ids from the spec evidence table (the D2 cell for an A#; P3.5-06 and P4.4-04 for an FM drill) and leaves a result section for the operator to complete when the scenario is run. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Staging runner covers A1–A36 (Priority: P1)

An operator runs STG-A01…STG-A36 from `e2e/fullstack/staging/` against the staging profile. Each script is one acceptance scenario. A1 runs all three term lengths. Scripted manual steps cover a Paymob test card, a dashboard refund, a blocked notify URL, and a disabled platform route. Passing every §8 scenario on that profile is the launch gate (FR-90).

**Why this priority**: CP-G is this story. P8.3 depends on A1–A36 passing on staging.

**Independent Test**: STG-A01 … STG-A36 in H-STG.

**Acceptance Scenarios**:

1. **Given** the three staging test offers — Monthly (1 month, 30 minutes, grace about 7 minutes, 20 credits), Quarterly (3 months, 90 minutes, grace about 7 minutes, 60 credits), and Annual (12 months, 6 hours, grace about 7 minutes, 240 credits) — **When** the administrator completes checkout with a Paymob test card for 1, 3, and 12 months, **Then** AI is on within about a minute of payment, the payment is in history (`GET /v1/payments`), the term is active at once with the full offer allowance, the admin desktop shows Active by polling the checkout, and the desktop calls `request_ai_status_refresh()`. (STG-A01, 00 §11 A1, 05 §8 A1, 05 §6.1)
2. **Given** the owner pays and closes the app before confirmation, **When** any desktop next opens, **Then** provisioning has completed without the desktop on the path, `get_ai_status()` shows active, and `GET /v1/checkouts?open=1` shows the outcome. (STG-A02, 00 §11 A2, 05 §8 A2)
3. **Given** the provider notification is lost or delayed by a blocked notify URL, **When** the checkout sweep runs, **Then** it inquires at +2, +5, +10, and +20 minutes, provisions the payment, and raises AL-03. (STG-A03, 00 §11 A3, 05 §8 A3, 05 §6.1)
4. **Given** the platform route is disabled for 4 days after a payment, **When** the grant row retries every 15 minutes for 4 days and the platform returns, **Then** AL-04 is raised hourly while it is down, the grant applies on return, and the term starts at activation so no paid days are lost. (STG-A04, 00 §11 A4, 05 §8 A4, 05 §6.1)
5. **Given** a card decline and then a successful retry on the same page, **When** both attempts finish, **Then** the decline is an `attempt_declined` event, the checkout stays open, the success is one payment and one grant, and nothing is cancelled. (STG-A05, 00 §11 A5, 05 §8 A5)
6. **Given** the owner pays twice for the same term, **When** both payments are recorded, **Then** the second is `likely_duplicate`, it stacks as the next term, and it raises a `duplicate_payment` notice and AL-09. (STG-A06, 00 §11 A6, 05 §8 A6, 05 §6.1)
7. **Given** a monthly checkout and a later switch to annual, **When** the owner pays the stale monthly tab, **Then** the payment binds to the monthly order and snapshot, the monthly term is granted at the monthly price, and the annual checkout expires unpaid. (STG-A07, 00 §11 A7, 05 §8 A7)
8. **Given** a price change between opening a checkout and paying, **When** the owner pays that checkout, **Then** the intention amount fixed at creation from the snapshot is what is charged, and the grant uses the same snapshot. (STG-A08, 00 §11 A8, 05 §8 A8)
9. **Given** a renewal paid 5 days early, **When** the renewal queues, **Then** the current allowance is unchanged and the new term starts at the old end date with its own allowance. (STG-A09, 00 §11 A9, 05 §8 A9)
10. **Given** a term reaches its end date unpaid, **When** the end date and `grace_ends_at` arrive, **Then** the DO enters grace and ends it on its own alarm and on admission with no ABO involvement, and the backend computes the lapse from dates, including when the ABO is down. (STG-A10, 00 §11 A10, 05 §8 A10)
11. **Given** a lapsed clinic pays 2 months later, **When** payment completes, **Then** the new term starts at activation, seconds after payment. (STG-A11, 00 §11 A11, 05 §8 A11)
12. **Given** the owner renews from a different branch desktop or after reinstall, **When** the renewal runs, **Then** the tenant comes from the backend session, nothing is stored on the desktop, and no vendor contact is required. (STG-A12, 00 §11 A12, 05 §8 A12)
13. **Given** the credentials the shared backend uses for a clinic were rotated since the first purchase, **When** the clinic renews, **Then** issuer-key rotation does not touch the tenant binding or the terms, and renewal works. (STG-A13, 00 §11 A13, 05 §8 A13)
14. **Given** a clinic's platform identity must be re-created while it has paid time, **When** the operator runs same-org `beginTransfer` (HP), **Then** the old binding is retired, a new binding is created at the next epoch, the new DO waits in `awaiting_transfer`, `transferOut` and `transferIn` move the terms with their `origin_grant_id`, the old identity ends `transferred` and refuses new grants, the status projection follows the higher epoch, AL-11 is raised, and reconciliation matches the transfer to its authorisation. (STG-A14, 00 §11 A14, 05 §8 A14)
15. **Given** a chargeback on the payment funding the current term, **When** the operator records a manual chargeback (HP) with effect `end_current`, **Then** the grant is voided, the term ends `reversed` with no grace, queued terms are held, and AL-06 is raised. (STG-A15, 00 §11 A15, 05 §8 A15, 05 §6.1)
16. **Given** a test-card refund made from the provider dashboard, **When** the refund arrives as parent flags or a child transaction, **Then** the adapter folds it into a `reversal`, never a payment, inquiry confirms, the effect follows 03 §5.5 through transfer lineage if the term moved, AL-06 is raised, and a lost callback is caught within an hour in the payment's first 7 days, within 6 hours while it funds a live, queued, or held term, and within a week otherwise up to 180 days. (STG-A16, 00 §11 A16, 05 §8 A16, 05 §6.1)
17. **Given** a chargeback on an old payment, **When** it is recorded with effect `none`, **Then** it is recorded and alerted, with no service change. (STG-A17, 00 §11 A17, 05 §8 A17)
18. **Given** a chargeback found only in the payout report, **When** payout import runs and the operator records the chargeback (HP), **Then** import raises `unrecorded_reversal`, the effect applies, and reconciliation is clean once the line is linked. (STG-A18, 00 §11 A18, 05 §8 A18)
19. **Given** a trial clinic converts to paid, **When** the purchase queues after the complimentary trial term, **Then** there is no gap and no overlap. (STG-A19, 00 §11 A19, 05 §8 A19)
20. **Given** a paying clinic, **When** the operator grants an HP complimentary grant of 14 days (unit `day`) within the 31-day ceiling, queued after existing coverage, **Then** AL-11 and the digest report it, and reconciliation matches it to the `operator_action`. (STG-A20, 00 §11 A20, 05 §8 A20)
21. **Given** a plan retired while clinics are on it, **When** the offer is retired, **Then** it leaves `/v1/offers`, existing terms keep their plan snapshot until they end, and a stale offer id answers `offer_unavailable`. (STG-A21, 00 §11 A21, 05 §8 A21)
22. **Given** someone who knows a clinic's identifier tries to order for it, **When** they request a token or present foreign ids, **Then** no token can be obtained for another tenant, foreign ids answer `not_found`, and nothing is locked by an open checkout. (STG-A22, 00 §11 A22, 05 §8 A22)
23. **Given** the provider changes a notification field and verification starts failing, **When** the failure is detected, **Then** AL-02 is raised within 15 minutes and sweeps confirm by inquiry. (STG-A23, 00 §11 A23, 05 §8 A23)
24. **Given** a clinic is deleted on the platform while it still has paid time, **When** HP delete runs, **Then** the installation is marked `deleted`, the binding is `held_for_transfer`, AL-18 is raised, AI is refused with `transfer_pending`, a renewal paid meanwhile waits as `transient`, no second binding appears, and the operator moves the time with `beginTransfer` from the held binding or voids the remaining grants, which retires it. (STG-A24, 00 §11 A24, 05 §8 A24)
25. **Given** a credential the shared backend uses for a clinic reaches its expiry while the clinic is paying, **When** expiry approaches, **Then** no per-clinic credential exists, and issuer keys raise AL-14 30 days ahead and rotate without an outage. (STG-A25, 00 §11 A25, 05 §8 A25)
26. **Given** a deploy secret or CI token leaks, **When** it is used, **Then** stored tokens have no production rights by policy, HP needs a passkey, and the watcher alerts on deploys. Status stays Partial. (STG-A26, 00 §11 A26, 05 §8 A26)
27. **Given** an operator session is hijacked and used to grant a year of access, **When** the grant is attempted, **Then** without the passkey no grant is possible; with it, the 31-day ceiling blocks a year; an override needs a second assertion and raises AL-12; AL-11 fires within minutes; grants can be listed and voided. (STG-A27, 00 §11 A27, 05 §8 A27)
28. **Given** the term nears its end date while only staff use the app, **When** staff open the app, **Then** staff get `ends_soon` at 7, 3, and 1 days in the staff form, the lapse shows from stored dates, staff cannot mint billing tokens, `/v1/coverage` refuses them, and `/v1/usage` is gone. (STG-A28, 00 §11 A28, 05 §8 A28)
29. **Given** an annual buyer uses 90% of the allowance by month 3, **When** band events at 75% and 90% fire, **Then** `allowance_low` is produced for every role and admission continues. (STG-A29, 00 §11 A29, 05 §8 A29)
30. **Given** an annual buyer with allowance left tries to upgrade at month 5, **When** the app offers the change, **Then** it is for the next term only, `POST /v1/checkouts` answers `starts: after_current`, and nothing changes now. (STG-A30, 00 §11 A30, 05 §8 A30)
31. **Given** an annual buyer uses up the allowance at month 4 with no prepaid term, **When** that request arrives and the owner later buys a current offer, **Then** exhaustion ends the term on that request with no grace, the new purchase starts at activation, and the rest of the calendar is forfeited. (STG-A31, 00 §11 A31, 05 §8 A31)
32. **Given** a monthly buyer prepaid next month and then uses up the allowance on day 20, **When** exhaustion is recorded, **Then** the prepaid term activates at that instant with its full allowance and runs one month from then. (STG-A32, 00 §11 A32, 05 §8 A32)
33. **Given** a clinic on a retired plan uses up its allowance, **When** the owner looks for a new offer, **Then** retired offers are not listed and the owner picks a current offer. (STG-A33, 00 §11 A33, 05 §8 A33)
34. **Given** two concurrent requests near the allowance limit, **When** the DO admits them, **Then** one crosses, exhaustion is recorded once, overshoot is at most `w_max − 1`, and the other request goes to the successor or is refused `allowance_exhausted`. (STG-A34, 00 §11 A34, 05 §8 A34)
35. **Given** the ABO or the AI Platform is compromised, **When** the attacker uses either service, **Then** neither service holds any database credential or Supabase JWT, and the backend only pulls. (STG-A35, 00 §11 A35, 05 §8 A35)
36. **Given** a bug or crafted request in clinic A's session targets clinic B's billing, **When** the ABO or an RPC handles it, **Then** the tenant is taken only from the session, the call answers `not_found` across tenants, and clinic B's status, allowance, and payments are unchanged and not visible. D2 records this Conditional as met by P1. (STG-A36, 00 §11 A36, 05 §8 A36)

### 2.2 User Story 2 - Evidence report cites the earlier E2E ids (Priority: P2)

Each staging scenario writes an evidence report. The report cites the earlier E2E ids from section 5, D2, for that A#. The FM drills cite the local ids D1 names beside P8.2: P3.5-06 and P4.4-04.

**Why this priority**: User Story 1 produces the staging result. This story is the trace from that result back to the local E2E that first verified it.

**Independent Test**: The evidence-report clause of STG-A01 … STG-A36, STG-FM-12, STG-FM-13, and STG-FM-14 in H-STG.

**Acceptance Scenarios**:

1. **Given** a finished STG-A scenario, **When** its evidence report is written, **Then** the report cites the D2 cell for that A# and no other A#'s cell:

| A# | D2 ids the report cites |
| --- | --- |
| A1 | P4.4-01 (full stack P6.3-01) |
| A2 | P4.4-08, P5.2-01, P6.3-02 |
| A3 | P4.5-01 |
| A4 | P4.4-02 |
| A5 | P4.3-04, P6.3-05 |
| A6 | P4.3-07, P4.4-05, P6.4-01 |
| A7 | P4.3-05 |
| A8 | P4.2-04, P4.7-01, P6.3-04 |
| A9 | P3.5-01 |
| A10 | P3.5-02, P5.2-03 |
| A11 | P3.5-05 |
| A12 | P4.2-07, P6.3-02 |
| A13 | P3.2-04, P5.1-06 |
| A14 | P3.8-01, P4.8-04, P5.2-05 |
| A15 | P3.7-01, P4.7-05 |
| A16 | P4.5-04/05, P6.4-02 |
| A17 | P3.7-03, P4.5-06 |
| A18 | P4.10-05 |
| A19 | P3.6-07, P4.8-03 |
| A20 | P3.6-01, P4.8-01 |
| A21 | P4.1-03, P4.2-04, P4.7-02 |
| A22 | P4.2-07, P7.2-03 |
| A23 | P4.3-03, P4.5-02 |
| A24 | P3.8-04, P4.8-05 |
| A25 | P4.11-02, P5.1-06 |
| A26 | P7.2-09, P8.1-02 (Partial: policy) |
| A27 | P3.6-02, P4.8-02, P7.2-06 |
| A28 | P5.2-03/04, P6.1-03, P6.2-06 |
| A29 | P3.4-08, P5.2-11, P6.1-04 |
| A30 | P4.2-02, P6.3-03 |
| A31 | P3.4-05 |
| A32 | P3.4-06 |
| A33 | P4.1-03, P4.7-02 |
| A34 | P3.4-07, P3.11-05 |
| A35 | P7.2-07 |
| A36 | P1.1-05, P1.2-02, P4.4-09, P7.2-03 (Conditional → met by P1) |

(STG-A01 … STG-A36, Implements, section 5 D2)

2. **Given** a finished STG-FM-12, STG-FM-13, or STG-FM-14 run, **When** its evidence report is written, **Then** the report cites the local ids D1 names for FM-12/13/14: P3.5-06 and P4.4-04. (STG-FM-12, STG-FM-13, STG-FM-14, section 5 D1)

### 2.3 User Story 3 - Failure-mode drills on staging (Priority: P3)

An operator runs the three failure-mode drills on staging. STG-FM-12 is catch-up after an outage window. STG-FM-13 and STG-FM-14 are a bad deploy, rollback, and retry of parked rows.

**Why this priority**: User Stories 1 and 2 cover A1–A36 and their reports. These drills are the remaining E2E ids. D1 assigns FM-12, FM-13, and FM-14 to this unit.

**Independent Test**: STG-FM-12, STG-FM-13, and STG-FM-14 in H-STG. Earlier suites stay green (rule S2).

**Acceptance Scenarios**:

1. **Given** an outage window on staging, **When** the window ends, **Then** the drill records catch-up. (STG-FM-12, Implements) [FM-12]
2. **Given** a bad deploy, **When** the operator rolls it back, **Then** parked rows are retried. (STG-FM-13, Implements) [FM-13]
3. **Given** a bad deploy, **When** the operator rolls it back, **Then** parked rows are retried. (STG-FM-14, Implements) [FM-14]
4. **Given** the earlier suites are green, **When** STG-FM-12, STG-FM-13, and STG-FM-14 have finished, **Then** those earlier suites are still green. (rule S2)

### 2.4 Test plan

Every row's evidence-report clause proves User Story 2 (FR-040). Harness for every row is H-STG (`e2e/fullstack/staging/`).

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| STG-A01 | H-STG (`e2e/fullstack/staging/`) | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/clinic-api/checkouts.ts`, `abo/src/worker.ts`); `POST /notify/paymob` (`abo/src/worker.ts`); `GET /v1/payments` (`abo/src/worker.ts`); `public.get_ai_status`; `public.request_ai_status_refresh`. Paymob test card. All three term lengths | AI on within about a minute; payment in history; full allowance; desktop Active; refresh called. Report cites P4.4-01 (full stack P6.3-01) [A1] [FR-90] | FR-001, FR-040, FR-041 | User Story 1 |
| STG-A02 | H-STG (`e2e/fullstack/staging/`) | `public.get_ai_status`; `GET /v1/checkouts` (`abo/src/worker.ts`) | Provisioned with the desktop closed; active on next open; open checkout shows the outcome. Report cites P4.4-08, P5.2-01, P6.3-02 [A2] [FR-90] | FR-002, FR-040 | User Story 1 |
| STG-A03 | H-STG (`e2e/fullstack/staging/`) | `scheduled()` (`abo/src/worker.ts`); scripted blocked notify URL | Sweep inquires at +2, +5, +10, +20 minutes and provisions; AL-03. Report cites P4.5-01 [A3] [FR-90] | FR-003, FR-040, FR-041 | User Story 1 |
| STG-A04 | H-STG (`e2e/fullstack/staging/`) | `scheduled()` (`abo/src/worker.ts`); scripted disabled platform route | Grant retries every 15 minutes for 4 days; AL-04 hourly; grant applies on return; term starts at activation. Report cites P4.4-02 [A4] [FR-90] | FR-004, FR-040, FR-041 | User Story 1 |
| STG-A05 | H-STG (`e2e/fullstack/staging/`) | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | `attempt_declined`; checkout stays open; one later payment and one grant; nothing cancelled. Report cites P4.3-04, P6.3-05 [A5] [FR-90] | FR-005, FR-040 | User Story 1 |
| STG-A06 | H-STG (`e2e/fullstack/staging/`) | `GET /v1/payments` (`abo/src/worker.ts`) | Second payment `likely_duplicate`; next term; `duplicate_payment` notice; AL-09. Report cites P4.3-07, P4.4-05, P6.4-01 [A6] [FR-90] | FR-006, FR-040 | User Story 1 |
| STG-A07 | H-STG (`e2e/fullstack/staging/`) | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | Monthly term at the monthly price; annual checkout expires unpaid. Report cites P4.3-05 [A7] [FR-90] | FR-007, FR-040 | User Story 1 |
| STG-A08 | H-STG (`e2e/fullstack/staging/`) | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | Intention amount fixed at creation; grant uses that snapshot. Report cites P4.2-04, P4.7-01, P6.3-04 [A8] [FR-90] | FR-008, FR-040 | User Story 1 |
| STG-A09 | H-STG (`e2e/fullstack/staging/`) | Clinic DO term placement after checkout (`POST /v1/checkouts`) | Current allowance unchanged; new term starts at the old end with its own allowance. Report cites P3.5-01 [A9] [FR-90] | FR-009, FR-040 | User Story 1 |
| STG-A10 | H-STG (`e2e/fullstack/staging/`) | Clinic DO alarm | Grace at the end date; grace ends at `grace_ends_at` with no ABO involvement; lapse from dates. Report cites P3.5-02, P5.2-03 [A10] [FR-90] | FR-010, FR-040 | User Story 1 |
| STG-A11 | H-STG (`e2e/fullstack/staging/`) | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | New term starts at activation, seconds after payment. Report cites P3.5-05 [A11] [FR-90] | FR-011, FR-040 | User Story 1 |
| STG-A12 | H-STG (`e2e/fullstack/staging/`) | `public.issue_billing_token`; `POST /v1/checkouts` (`abo/src/worker.ts`) | Tenant from the backend session; nothing stored on the desktop. Report cites P4.2-07, P6.3-02 [A12] [FR-90] | FR-012, FR-040 | User Story 1 |
| STG-A13 | H-STG (`e2e/fullstack/staging/`) | Issuer-key rotation, then `POST /v1/checkouts` (`abo/src/worker.ts`) | Rotation leaves the tenant binding and the terms unchanged; renewal works. Report cites P3.2-04, P5.1-06 [A13] [FR-90] | FR-013, FR-040 | User Story 1 |
| STG-A14 | H-STG (`e2e/fullstack/staging/`) | HP `beginTransfer` (`abo/src/worker.ts`, `abo/src/ops/index.ts`), then `transferOut` and `transferIn` | Remaining time moves to the new identity; old identity ends `transferred`; AL-11; reconciliation matches the authorisation. Report cites P3.8-01, P4.8-04, P5.2-05 [A14] [FR-90] | FR-014, FR-040 | User Story 1 |
| STG-A15 | H-STG (`e2e/fullstack/staging/`) | Ops host HP manual chargeback (`abo/src/worker.ts`) | Effect `end_current`: grant voided; term `reversed` with no grace; queued terms held; AL-06. Report cites P3.7-01, P4.7-05 [A15] [FR-90] | FR-015, FR-040 | User Story 1 |
| STG-A16 | H-STG (`e2e/fullstack/staging/`) | Scripted dashboard refund; `scheduled()` inquiry (`abo/src/worker.ts`) | Folded into a `reversal`, never a payment; inquiry confirms; AL-06; lost-callback bounds in 05 §8 A16. Report cites P4.5-04/05, P6.4-02 [A16] [FR-90] | FR-016, FR-040, FR-041 | User Story 1 |
| STG-A17 | H-STG (`e2e/fullstack/staging/`) | Ops host HP chargeback, effect `none` (`abo/src/worker.ts`) | Recorded and alerted; no service change. Report cites P3.7-03, P4.5-06 [A17] [FR-90] | FR-017, FR-040 | User Story 1 |
| STG-A18 | H-STG (`e2e/fullstack/staging/`) | Payout import, then ops host HP chargeback (`abo/src/worker.ts`) | `unrecorded_reversal`; effect applies; reconciliation clean once linked. Report cites P4.10-05 [A18] [FR-90] | FR-018, FR-040 | User Story 1 |
| STG-A19 | H-STG (`e2e/fullstack/staging/`) | Complimentary trial term, then `POST /v1/checkouts` (`abo/src/worker.ts`) | Purchase queues after the trial; no gap and no overlap. Report cites P3.6-07, P4.8-03 [A19] [FR-90] | FR-019, FR-040 | User Story 1 |
| STG-A20 | H-STG (`e2e/fullstack/staging/`) | Ops host HP complimentary grant (`abo/src/worker.ts`) | 14 days, unit `day`, within the 31-day ceiling, queued; AL-11; digest; reconciliation matches `operator_action`. Report cites P3.6-01, P4.8-01 [A20] [FR-90] | FR-020, FR-040 | User Story 1 |
| STG-A21 | H-STG (`e2e/fullstack/staging/`) | `GET /v1/offers` (`abo/src/worker.ts`) | Retired offer leaves the list; existing terms keep their snapshot; stale id answers `offer_unavailable`. Report cites P4.1-03, P4.2-04, P4.7-02 [A21] [FR-90] | FR-021, FR-040 | User Story 1 |
| STG-A22 | H-STG (`e2e/fullstack/staging/`) | `public.issue_billing_token`; clinic billing routes (`abo/src/worker.ts`) | No token for another tenant; foreign ids `not_found`; open checkout locks nothing. Report cites P4.2-07, P7.2-03 [A22] [FR-90] | FR-022, FR-040 | User Story 1 |
| STG-A23 | H-STG (`e2e/fullstack/staging/`) | `scheduled()` (`abo/src/worker.ts`) | AL-02 within 15 minutes; sweeps confirm by inquiry. Report cites P4.3-03, P4.5-02 [A23] [FR-90] | FR-023, FR-040 | User Story 1 |
| STG-A24 | H-STG (`e2e/fullstack/staging/`) | Ops host HP delete (`abo/src/worker.ts`) | Installation `deleted`; binding `held_for_transfer`; AL-18; `transfer_pending`; renewal waits `transient`; no second binding. Report cites P3.8-04, P4.8-05 [A24] [FR-90] | FR-024, FR-040 | User Story 1 |
| STG-A25 | H-STG (`e2e/fullstack/staging/`) | Issuer-key expiry path | AL-14 30 days ahead; rotation without an outage; no per-clinic credential. Report cites P4.11-02, P5.1-06 [A25] [FR-90] | FR-025, FR-040 | User Story 1 |
| STG-A26 | H-STG (`e2e/fullstack/staging/`) | Ops host HP method (`abo/src/worker.ts`); audit watcher | Stored tokens have no production rights by policy; HP needs a passkey; watcher alerts on deploys. Status Partial. Report cites P7.2-09, P8.1-02 (Partial: policy) [A26] [FR-90] | FR-026, FR-040 | User Story 1 |
| STG-A27 | H-STG (`e2e/fullstack/staging/`) | Ops host HP complimentary grant (`abo/src/worker.ts`) | No grant without the passkey; 31-day ceiling blocks a year; override needs a second assertion and raises AL-12; AL-11 within minutes; grants listable and voidable. Report cites P3.6-02, P4.8-02, P7.2-06 [A27] [FR-90] | FR-027, FR-040 | User Story 1 |
| STG-A28 | H-STG (`e2e/fullstack/staging/`) | `public.get_ai_status`; `public.issue_billing_token`; `GET /v1/coverage` | Staff `ends_soon` at 7, 3, and 1 days; lapse from stored dates; no billing token; `/v1/coverage` refuses staff; `/v1/usage` is gone. Report cites P5.2-03/04, P6.1-03, P6.2-06 [A28] [FR-90] | FR-028, FR-040 | User Story 1 |
| STG-A29 | H-STG (`e2e/fullstack/staging/`) | Clinic admission | Band events at 75% and 90% produce `allowance_low` for every role; admission continues. Report cites P3.4-08, P5.2-11, P6.1-04 [A29] [FR-90] | FR-029, FR-040 | User Story 1 |
| STG-A30 | H-STG (`e2e/fullstack/staging/`) | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | `starts: after_current`; nothing charged or changed now. Report cites P4.2-02, P6.3-03 [A30] [FR-90] | FR-030, FR-040 | User Story 1 |
| STG-A31 | H-STG (`e2e/fullstack/staging/`) | Clinic admission, then `POST /v1/checkouts` (`abo/src/worker.ts`) | Exhaustion ends the term on that request with no grace; new term starts at activation; remaining calendar forfeited. Report cites P3.4-05 [A31] [FR-90] | FR-031, FR-040 | User Story 1 |
| STG-A32 | H-STG (`e2e/fullstack/staging/`) | Clinic admission | Prepaid term starts at the exhaustion instant with its full allowance and runs one month from then. Report cites P3.4-06 [A32] [FR-90] | FR-032, FR-040 | User Story 1 |
| STG-A33 | H-STG (`e2e/fullstack/staging/`) | `GET /v1/offers` (`abo/src/worker.ts`) | Retired offers are not listed; the owner picks a current offer. Report cites P4.1-03, P4.7-02 [A33] [FR-90] | FR-033, FR-040 | User Story 1 |
| STG-A34 | H-STG (`e2e/fullstack/staging/`) | Clinic DO admission | Exhaustion recorded once; overshoot at most `w_max − 1`; the other request takes the successor or `allowance_exhausted`. Report cites P3.4-07, P3.11-05 [A34] [FR-90] | FR-034, FR-040 | User Story 1 |
| STG-A35 | H-STG (`e2e/fullstack/staging/`) | PostgREST | Neither service holds a database credential or Supabase JWT; the backend only pulls. Report cites P7.2-07 [A35] [FR-90] | FR-035, FR-040 | User Story 1 |
| STG-A36 | H-STG (`e2e/fullstack/staging/`) | ABO routes (`abo/src/worker.ts`) and PostgREST RPCs | Tenant only from the session; `not_found` across tenants; clinic B unchanged and not visible. Report cites P1.1-05, P1.2-02, P4.4-09, P7.2-03 (Conditional → met by P1) [A36] [FR-90] | FR-036, FR-040 | User Story 1 |
| STG-FM-12 | H-STG (`e2e/fullstack/staging/`) | `scheduled()` (`abo/src/worker.ts`) after the scripted outage window | Catch-up after an outage window. Report cites P3.5-06, P4.4-04 [FM-12] | FR-037, FR-040 | User Story 3 |
| STG-FM-13 | H-STG (`e2e/fullstack/staging/`) | Scripted bad deploy, rollback, and retry of parked rows | Bad deploy, rollback, retry parked. Report cites P3.5-06, P4.4-04 [FM-13] | FR-038, FR-040 | User Story 3 |
| STG-FM-14 | H-STG (`e2e/fullstack/staging/`) | Scripted bad deploy, rollback, and retry of parked rows | Bad deploy, rollback, retry parked. Report cites P3.5-06, P4.4-04 [FM-14] | FR-039, FR-040 | User Story 3 |

### 2.5 Edge Cases

- A blocked notify URL still provisions: the checkout sweep inquires at +2, +5, +10, and +20 minutes and raises AL-03. (STG-A03, 05 §8 A3, 05 §6.1)
- A disabled platform route for 4 days leaves the grant retrying every 15 minutes; AL-04 is hourly; the term starts at activation when the platform returns. (STG-A04, 05 §8 A4, 05 §6.1)
- A decline is `attempt_declined`. The checkout stays open. A later success on the same page is one payment and one grant. (STG-A05, 05 §8 A5)
- Grace starts and ends on the DO alarm with no ABO involvement, including when the ABO is down. (STG-A10, 00 §11 A10, 05 §8 A10)
- A dashboard refund is a `reversal`, never a payment. (STG-A16, 05 §8 A16, 05 §6.1)
- A stale offer id answers `offer_unavailable`. Foreign ids answer `not_found`. Staff cannot mint a billing token, and `/v1/coverage` refuses them. (STG-A21, STG-A22, STG-A28, 05 §8)
- Exhaustion ends the term on that request with no grace. Two concurrent requests record exhaustion once; overshoot is at most `w_max − 1`. (STG-A31, STG-A34, 05 §8)
- A26 stays Partial: stored tokens have no production rights by policy; HP needs a passkey; the watcher alerts on deploys. (STG-A26, 05 §8 A26)
- A36 answers `not_found` across tenants. D2 records the Conditional as met by P1. (STG-A36, 05 §8 A36, section 5 D2)
- After an outage window the drill records catch-up. A bad deploy is rolled back and parked rows are retried. (STG-FM-12, STG-FM-13, STG-FM-14, Implements)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: STG-A01 MUST run the first purchase for 1, 3, and 12 months on the staging offers. AI MUST be on within about a minute of payment. The payment MUST appear in `GET /v1/payments`. The term MUST be active at once with the full offer allowance. The admin desktop MUST show Active by polling and MUST call `request_ai_status_refresh()`. (00 §11 A1, 05 §8 A1, 05 §6.1)
- **FR-002**: STG-A02 MUST provision when the owner closes the app before confirmation. Any desktop's `get_ai_status()` MUST show active on open. `GET /v1/checkouts?open=1` MUST show the outcome. (00 §11 A2, 05 §8 A2)
- **FR-003**: STG-A03 MUST treat a lost or delayed provider notification, scripted as a blocked notify URL, as found by the checkout sweep at +2, +5, +10, and +20 minutes. The sweep MUST provision and MUST raise AL-03. (00 §11 A3, 05 §8 A3, 05 §6.1, Implements)
- **FR-004**: STG-A04 MUST keep the grant row retrying every 15 minutes for 4 days while the platform route is disabled, MUST raise AL-04 hourly, and MUST apply the grant when the platform returns, with the term starting at activation. (00 §11 A4, 05 §8 A4, 05 §6.1, Implements)
- **FR-005**: STG-A05 MUST record the declined attempt as `attempt_declined`, MUST leave the checkout open, and MUST turn the later success into one payment and one grant, with nothing cancelled. (00 §11 A5, 05 §8 A5)
- **FR-006**: STG-A06 MUST record both payments. The second MUST be `likely_duplicate`, MUST stack as the next term, and MUST raise a `duplicate_payment` notice and AL-09. (00 §11 A6, 05 §8 A6)
- **FR-007**: STG-A07 MUST grant the monthly term at the monthly price from that checkout's order and snapshot, and MUST let the annual checkout expire unpaid. (00 §11 A7, 05 §8 A7)
- **FR-008**: STG-A08 MUST charge and grant the intention amount fixed at creation from the checkout snapshot. (00 §11 A8, 05 §8 A8)
- **FR-009**: STG-A09 MUST queue the early renewal, MUST leave the current allowance unchanged, and MUST start the new term at the old end date with its own allowance. (00 §11 A9, 05 §8 A9)
- **FR-010**: STG-A10 MUST enter grace at the end date and end it at `grace_ends_at` on the DO alarm and on admission, with no ABO involvement. The backend MUST compute the lapse from dates. AI MUST stop at grace end even if the ABO is down. (00 §11 A10, 05 §8 A10)
- **FR-011**: STG-A11 MUST start the new term at activation, seconds after payment. (00 §11 A11, 05 §8 A11)
- **FR-012**: STG-A12 MUST take the tenant from the backend session, MUST store nothing on the desktop, and MUST renew without vendor contact. (00 §11 A12, 05 §8 A12)
- **FR-013**: STG-A13 MUST leave the tenant binding and the terms untouched by issuer-key rotation, and renewal MUST work. (00 §11 A13, 05 §8 A13)
- **FR-014**: STG-A14 MUST move remaining time and allowance to the new identity through same-org `beginTransfer`, `transferOut`, and `transferIn`, MUST end the old identity `transferred`, MUST raise AL-11, and MUST match reconciliation to the authorisation. (00 §11 A14, 05 §8 A14)
- **FR-015**: STG-A15 MUST record a manual chargeback with effect `end_current`, MUST void the grant, MUST end the term `reversed` with no grace, MUST hold queued terms, and MUST raise AL-06. (00 §11 A15, 05 §8 A15, 05 §6.1)
- **FR-016**: STG-A16 MUST recognise a dashboard refund as a `reversal`, never a payment, MUST confirm by inquiry, MUST apply the 05 §8 A16 effect and lost-callback bounds, and MUST raise AL-06. (00 §11 A16, 05 §8 A16, 05 §6.1, Implements)
- **FR-017**: STG-A17 MUST record an old-payment chargeback with effect `none` and MUST alert, with no service change. (00 §11 A17, 05 §8 A17)
- **FR-018**: STG-A18 MUST raise `unrecorded_reversal` from payout import, MUST apply the effect when the operator records the chargeback, and MUST be clean once the payout line is linked. (00 §11 A18, 05 §8 A18)
- **FR-019**: STG-A19 MUST queue the paid purchase after the complimentary trial so there is no gap and no overlap. (00 §11 A19, 05 §8 A19)
- **FR-020**: STG-A20 MUST apply an HP complimentary grant of 14 days (unit `day`) within the 31-day ceiling, queued after existing coverage, MUST raise AL-11, MUST include it in the digest, and MUST match it to the `operator_action`. (00 §11 A20, 05 §8 A20)
- **FR-021**: STG-A21 MUST drop a retired offer from `/v1/offers`, MUST keep existing terms on their plan snapshot until they end, and MUST answer a stale offer id with `offer_unavailable`. (00 §11 A21, 05 §8 A21)
- **FR-022**: STG-A22 MUST refuse a token for another tenant, MUST answer foreign ids with `not_found`, and MUST NOT lock a clinic by an open checkout. (00 §11 A22, 05 §8 A22)
- **FR-023**: STG-A23 MUST raise AL-02 within 15 minutes when notification verification fails, and sweeps MUST confirm by inquiry. (00 §11 A23, 05 §8 A23)
- **FR-024**: STG-A24 MUST mark the installation `deleted` on HP delete when paid time remains, MUST hold the binding for transfer, MUST raise AL-18, MUST refuse AI with `transfer_pending`, MUST hold a meanwhile renewal as `transient`, and MUST NOT create a second binding. (00 §11 A24, 05 §8 A24)
- **FR-025**: STG-A25 MUST keep no per-clinic credential, MUST raise AL-14 30 days before issuer-key expiry, and MUST rotate without an outage. (00 §11 A25, 05 §8 A25)
- **FR-026**: STG-A26 MUST show that stored tokens have no production rights by policy, that HP needs a passkey, and that the watcher alerts on deploys. Status stays Partial. (00 §11 A26, 05 §8 A26, section 5 D2)
- **FR-027**: STG-A27 MUST make a grant impossible without the passkey, MUST block a year at the 31-day ceiling, MUST require a second assertion for an override and raise AL-12, MUST raise AL-11 within minutes, and MUST leave grants listable and voidable. (00 §11 A27, 05 §8 A27)
- **FR-028**: STG-A28 MUST show staff `ends_soon` at 7, 3, and 1 days, MUST show lapse from stored dates, MUST stop staff minting billing tokens, MUST refuse staff at `/v1/coverage`, and MUST leave `/v1/usage` gone. (00 §11 A28, 05 §8 A28)
- **FR-029**: STG-A29 MUST produce `allowance_low` for every role at the 75% and 90% band events, and admission MUST continue. (00 §11 A29, 05 §8 A29)
- **FR-030**: STG-A30 MUST offer an upgrade only for the next term. `POST /v1/checkouts` MUST answer `starts: after_current`. Nothing MUST change now. (00 §11 A30, 05 §8 A30)
- **FR-031**: STG-A31 MUST end the term on the exhausting request with no grace, MUST start a later purchase at activation, and MUST forfeit the rest of the calendar. (00 §11 A31, 05 §8 A31)
- **FR-032**: STG-A32 MUST activate the prepaid term at the exhaustion instant with its full allowance and MUST run it one month from then. (00 §11 A32, 05 §8 A32)
- **FR-033**: STG-A33 MUST NOT list retired offers, and the owner MUST pick a current offer. (00 §11 A33, 05 §8 A33)
- **FR-034**: STG-A34 MUST record exhaustion once, MUST keep overshoot at most `w_max − 1`, and MUST send the other request to the successor or refuse it `allowance_exhausted`. (00 §11 A34, 05 §8 A34)
- **FR-035**: STG-A35 MUST leave neither service holding a database credential or a Supabase JWT. The backend MUST only pull. (00 §11 A35, 05 §8 A35)
- **FR-036**: STG-A36 MUST take the tenant only from the session, MUST answer `not_found` across tenants, and MUST leave clinic B's status, allowance, and payments unchanged and not visible. (00 §11 A36, 05 §8 A36, section 5 D2)
- **FR-037**: STG-FM-12 MUST record catch-up after an outage window. (Implements) [FM-12]
- **FR-038**: STG-FM-13 MUST roll back a bad deploy and MUST retry parked rows. (Implements) [FM-13]
- **FR-039**: STG-FM-14 MUST roll back a bad deploy and MUST retry parked rows. (Implements) [FM-14]
- **FR-040**: Each STG-A and STG-FM scenario MUST write an evidence report. An A# report MUST cite that row's D2 ids. An FM report MUST cite P3.5-06 and P4.4-04. (Implements, section 5 D1, section 5 D2)
- **FR-041**: The runner scripts MUST include scripted manual steps for a dashboard refund, Paymob test cards, a blocked notify URL, and a disabled platform route. (Implements, 05 §6.1)
- **FR-042**: Every 05 §8 scenario MUST run as a staging test on the 05 §6.1 profile. Offers use the production units and validation. `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute. Passing all of them in staging is the launch gate (FR-90). (05 §6.1, 00 §11, 05 §8)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: `e2e/fullstack/staging/`. That is the codebase cell the unit row names (rule S3). No wiring exception is named. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic administrator, staff member, or operator can see each A1–A36 outcome on the staging profile, in compressed time, before the launch gate. The profile serves a small-to-mid-size multi-branch clinic. (00 §11, 05 §6.1, 05 §8)
- **Layer Placement**: Runner scripts and evidence-report templates live under `e2e/fullstack/staging/`. They call the existing billing routes on `abo/src/worker.ts`, `public.get_ai_status`, `public.request_ai_status_refresh`, `public.issue_billing_token`, the clinic DO alarm, and the ops-host HP actions. This unit adds no Worker, no Supabase schema, and no desktop screen. (Implements, rule V1)
- **Data Integrity & Security**: The scripts do not add tables, grants, or credentials. STG-A22, STG-A26, STG-A28, STG-A35, and STG-A36 restate the session-tenant, passkey, staff, and database-credential boundaries already defined for those scenarios. (05 §8)
- **Failure Handling**: Lost notify, a disabled platform route, grace while the ABO is down, decline, refund, exhaustion, and the FM-12/13/14 drills are the degraded outcomes this unit records. The unit does not add a new recovery path. (05 §8, 05 §6.1, Implements)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P8.1, P7.2, and P7.3 state no Outputs / freezes line.
- No module that no test-plan row reaches (rule S8). The P2.2 and package-half P2.1 exception does not apply.
- No S9 transitional path is named on this unit row.
- No codebase beyond `e2e/fullstack/staging/`.
- The local HMAC replay fixture, the inquiry stub, and the version matrix in 05 §6.1 ("Before staging") stay where section 5 D1 places them: P4.2/P4.3 and P7.3. This unit runs the §8 scenarios on the staging profile.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: STG-A01 … STG-A36 are green in H-STG.
- **SC-002**: STG-FM-12, STG-FM-13, and STG-FM-14 are green in H-STG.
- **SC-003**: Each of those scenarios has an evidence report citing the ids in FR-040.
- **SC-004**: CP-G — all A1–A36 pass on staging. Launch gate (FR-90). (rule S11, 00 §11, 05 §6.1)
- **SC-005**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- None. The Read line and the Implements line name no §6 default. The unit row names no S9 transitional path.
