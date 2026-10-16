# Implementation Plan: Staging acceptance A1–A36

**Branch**: `ai/097-abo-p8-2-staging-acceptance-a1-a36` | **Date**: 2026-10-08 | **Spec**: `specs/097-abo-p8-2-staging-acceptance-a1-a36/spec.md`

**Input**: Feature specification from `specs/097-abo-p8-2-staging-acceptance-a1-a36/spec.md`

## Summary

P8.2 adds one H-STG Node runner per staging scenario under `e2e/fullstack/staging/`, four scripted manual checklists, and one evidence-report template per scenario. The runners point the existing H-FS runner at the staging profile. It depends on P8.1, P7.2, and P7.3 (phase P8, size L). Those three rows freeze nothing, so this unit consumes no module.

## Technical Context

**Language/Version**: Node runner scripts (`node:test`, `node:assert/strict`, `node:fs`) under `e2e/fullstack/staging/`. Evidence templates and manual checklists are markdown.

**Primary Dependencies**: The existing H-FS Node scenario runner under `e2e/fullstack/test/` (P5.1), pointed at the staging profile. Existing names only: `[env.staging]`, `DURATION_SCALE`, Paymob test cards. No new library, no second runner, no new configuration name, and no import of a test file that boots a worker.

**Storage**: N/A. No table, migration, credential, or secret.

**Testing**: H-STG (`e2e/fullstack/staging/`). One `node:test` per scenario id, title prefix `STG-A01` … `STG-A36`, `STG-FM-12`, `STG-FM-13`, `STG-FM-14` (rule V3). The test reads the evidence template and, for four ids, the manual checklist. It does not boot wrangler and does not call Cloudflare, Supabase, or Paymob. A missing live account is expected. Live staging is not executed in this workflow.

**Target Platform**: `e2e/fullstack/staging/` only. The unit row names no other codebase.

**Project Type**: Staging acceptance runners and evidence-report templates (05 §8 on the 05 §6.1 profile)

**Performance Goals**: `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute (05 §6.1, FR-042). A1 keeps AI on within about a minute of payment. A3 inquires at +2, +5, +10, and +20 minutes. A4 retries the grant every 15 minutes for 4 days and raises AL-04 hourly. A23 raises AL-02 within 15 minutes.

**Constraints**: Offers keep production units. The three staging offers are Monthly (1 month, 30 minutes, grace about 7 minutes, 20 credits), Quarterly (3 months, 90 minutes, grace about 7 minutes, 60 credits), and Annual (12 months, 6 hours, grace about 7 minutes, 240 credits). A26 stays Partial. A36 cites the Conditional as met by P1. Scripts add no Worker, schema, desktop screen, or recovery path. Secret values stay out of git.

**Scale/Scope**: Thirty-six acceptance runners, three failure-mode runners, four manual checklists, and thirty-nine evidence templates. Passing A1–A36 on this profile is the launch gate (FR-90, CP-G).

### Staging profile names

Every runner names the existing profile and no new key:

| Name already in the design | What the runner records |
| --- | --- |
| `[env.staging]` | Staging config the H-FS runner is pointed at |
| `DURATION_SCALE` | 1 month = 30 minutes, 1 day = 1 minute |
| Paymob test cards | The 05 §6.1 test integration, scripted for STG-A01 in `manual/paymob-test-card.md` |

The runner does not copy `startStack`, does not call `fetch`, and does not spawn wrangler. The operator procedure in the script is the H-FS runner pointed at that profile. This workflow checks the procedure text, the checklist inclusion, and the evidence citation.

### Evidence template

One file per scenario under `e2e/fullstack/staging/evidence/`, named with the scenario id (`stg-a01.md` … `stg-a36.md`, `stg-fm-12.md`, `stg-fm-13.md`, `stg-fm-14.md`). The template cites that scenario's ids and leaves the result for the operator:

```markdown
# STG-A01

## Cited E2E ids

P4.4-01 (full stack P6.3-01)

## Result

Operator completes this section when the scenario is run.
```

An A# template cites that row's D2 cell and no other A#'s cell. An FM template cites `P3.5-06, P4.4-04`. The `node:test` fails when the citation or the `## Result` section is absent.

### Manual checklists

Four files. The matching runner reads the file (it includes that checklist). The other runners read no checklist.

| File | Scenario | Steps the checklist scripts |
| --- | --- | --- |
| `e2e/fullstack/staging/manual/paymob-test-card.md` | STG-A01 | Paymob test card for 1, 3, and 12 months on the three staging offers |
| `e2e/fullstack/staging/manual/blocked-notify-url.md` | STG-A03 | Blocked notify URL; sweep inquires at +2, +5, +10, and +20 minutes |
| `e2e/fullstack/staging/manual/disabled-platform-route.md` | STG-A04 | Platform route disabled for 4 days; grant retries every 15 minutes |
| `e2e/fullstack/staging/manual/dashboard-refund.md` | STG-A16 | Dashboard refund as parent flags or a child transaction, folded into a reversal |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after design. 02 §7 records no violation. This unit adds no service, queue, store, or migration.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — 02 §7 principle I and spec §4 Clinic Fit: an administrator, staff member, or operator sees each A1–A36 outcome on the compressed staging profile.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — 02 §7 principle I. The runners are H-STG scripts. They add no Worker and no server.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — 02 §7 principle II. Scripts call the existing billing routes, RPCs, DO alarm, and ops-host actions. They add no screen and no schema.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — 02 §7 principle III. This unit adds no write path, table, or grant.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — 02 §7 principle IV. STG-A22, STG-A26, STG-A28, STG-A35, and STG-A36 restate the session-tenant, passkey, staff, and database-credential boundaries. Scripts add no credential.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — 02 §7 principles II and V. Neither service holds a database credential (A35). Grace and lapse stay on stored dates when the ABO is down (A10). The unit records those outcomes and adds no recovery path.

## Project Structure

### Documentation (this feature)

```text
specs/097-abo-p8-2-staging-acceptance-a1-a36/
├── plan.md
├── spec.md
└── quickstart.md        # Outline only here. Implement writes it after harness green
```

`research.md` is omitted (Spikes: None). `data-model.md` is omitted (no entities). `contracts/` is omitted (Freezes: None). `tasks.md` is not created in this phase.

#### Quickstart outline

Implement writes `quickstart.md` after this unit's harness is green. Sections only:

- What was implemented; files added and modified
- Harness command for this unit's tests only (the command in Sequencing)
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour (the four checklists)
- The live H-STG command against a live account is not executed in this workflow

### Source Code (repository root)

```text
e2e/fullstack/staging/
├── stg-a01.mjs … stg-a36.mjs
├── stg-fm-12.mjs
├── stg-fm-13.mjs
├── stg-fm-14.mjs
├── manual/
│   ├── paymob-test-card.md
│   ├── blocked-notify-url.md
│   ├── disabled-platform-route.md
│   └── dashboard-refund.md
└── evidence/
    ├── stg-a01.md … stg-a36.md
    ├── stg-fm-12.md
    ├── stg-fm-13.md
    └── stg-fm-14.md
```

**Structure Decision**: H-STG for this unit is only `e2e/fullstack/staging/`. Each scenario id is one Node script, the H-STG entry, pointing the existing H-FS runner at `[env.staging]`, Paymob test cards, and `DURATION_SCALE`. Evidence templates live under `evidence/`. The four manual checklists live under `manual/`. Existing P8.1 files in `e2e/fullstack/staging/` stay as they are. `e2e/fullstack/package.json` is not edited. No file is added under `abo/`, `ai-platform/`, `backend/`, `frontend/`, or `packages/vendor-contracts/`.

## Consumes Binding

| Consumes | Binding |
| --- | --- |
| P8.1 | None. The unit row states no Outputs / freezes line. |
| P7.2 | None. The unit row states no Outputs / freezes line. |
| P7.3 | None. The unit row states no Outputs / freezes line. |

This unit does not modify a consumed module.

## Files

Each runner is a `node:test` whose title starts with the scenario id. It records the entry chain below, the staging profile names, and the evidence path. STG-A01, STG-A03, STG-A04, and STG-A16 also read their checklist. The test fails while the evidence template, or that checklist, is absent.

| Path | Action | FR |
| --- | --- | --- |
| `e2e/fullstack/staging/stg-a01.mjs` | Create. Title prefix `STG-A01`. Three term lengths. Reads `manual/paymob-test-card.md` | FR-001, FR-040, FR-041, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a01.md` | Create. Cites `P4.4-01 (full stack P6.3-01)` | FR-040 |
| `e2e/fullstack/staging/manual/paymob-test-card.md` | Create. Heading prefix `STG-A01` | FR-041 |
| `e2e/fullstack/staging/stg-a02.mjs` | Create. Title prefix `STG-A02` | FR-002, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a02.md` | Create. Cites `P4.4-08, P5.2-01, P6.3-02` | FR-040 |
| `e2e/fullstack/staging/stg-a03.mjs` | Create. Title prefix `STG-A03`. Reads `manual/blocked-notify-url.md` | FR-003, FR-040, FR-041, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a03.md` | Create. Cites `P4.5-01` | FR-040 |
| `e2e/fullstack/staging/manual/blocked-notify-url.md` | Create. Heading prefix `STG-A03` | FR-041 |
| `e2e/fullstack/staging/stg-a04.mjs` | Create. Title prefix `STG-A04`. Reads `manual/disabled-platform-route.md` | FR-004, FR-040, FR-041, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a04.md` | Create. Cites `P4.4-02` | FR-040 |
| `e2e/fullstack/staging/manual/disabled-platform-route.md` | Create. Heading prefix `STG-A04` | FR-041 |
| `e2e/fullstack/staging/stg-a05.mjs` | Create. Title prefix `STG-A05` | FR-005, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a05.md` | Create. Cites `P4.3-04, P6.3-05` | FR-040 |
| `e2e/fullstack/staging/stg-a06.mjs` | Create. Title prefix `STG-A06` | FR-006, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a06.md` | Create. Cites `P4.3-07, P4.4-05, P6.4-01` | FR-040 |
| `e2e/fullstack/staging/stg-a07.mjs` | Create. Title prefix `STG-A07` | FR-007, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a07.md` | Create. Cites `P4.3-05` | FR-040 |
| `e2e/fullstack/staging/stg-a08.mjs` | Create. Title prefix `STG-A08` | FR-008, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a08.md` | Create. Cites `P4.2-04, P4.7-01, P6.3-04` | FR-040 |
| `e2e/fullstack/staging/stg-a09.mjs` | Create. Title prefix `STG-A09` | FR-009, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a09.md` | Create. Cites `P3.5-01` | FR-040 |
| `e2e/fullstack/staging/stg-a10.mjs` | Create. Title prefix `STG-A10` | FR-010, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a10.md` | Create. Cites `P3.5-02, P5.2-03` | FR-040 |
| `e2e/fullstack/staging/stg-a11.mjs` | Create. Title prefix `STG-A11` | FR-011, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a11.md` | Create. Cites `P3.5-05` | FR-040 |
| `e2e/fullstack/staging/stg-a12.mjs` | Create. Title prefix `STG-A12` | FR-012, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a12.md` | Create. Cites `P4.2-07, P6.3-02` | FR-040 |
| `e2e/fullstack/staging/stg-a13.mjs` | Create. Title prefix `STG-A13` | FR-013, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a13.md` | Create. Cites `P3.2-04, P5.1-06` | FR-040 |
| `e2e/fullstack/staging/stg-a14.mjs` | Create. Title prefix `STG-A14` | FR-014, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a14.md` | Create. Cites `P3.8-01, P4.8-04, P5.2-05` | FR-040 |
| `e2e/fullstack/staging/stg-a15.mjs` | Create. Title prefix `STG-A15` | FR-015, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a15.md` | Create. Cites `P3.7-01, P4.7-05` | FR-040 |
| `e2e/fullstack/staging/stg-a16.mjs` | Create. Title prefix `STG-A16`. Reads `manual/dashboard-refund.md` | FR-016, FR-040, FR-041, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a16.md` | Create. Cites `P4.5-04/05, P6.4-02` | FR-040 |
| `e2e/fullstack/staging/manual/dashboard-refund.md` | Create. Heading prefix `STG-A16` | FR-041 |
| `e2e/fullstack/staging/stg-a17.mjs` | Create. Title prefix `STG-A17` | FR-017, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a17.md` | Create. Cites `P3.7-03, P4.5-06` | FR-040 |
| `e2e/fullstack/staging/stg-a18.mjs` | Create. Title prefix `STG-A18` | FR-018, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a18.md` | Create. Cites `P4.10-05` | FR-040 |
| `e2e/fullstack/staging/stg-a19.mjs` | Create. Title prefix `STG-A19` | FR-019, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a19.md` | Create. Cites `P3.6-07, P4.8-03` | FR-040 |
| `e2e/fullstack/staging/stg-a20.mjs` | Create. Title prefix `STG-A20` | FR-020, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a20.md` | Create. Cites `P3.6-01, P4.8-01` | FR-040 |
| `e2e/fullstack/staging/stg-a21.mjs` | Create. Title prefix `STG-A21` | FR-021, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a21.md` | Create. Cites `P4.1-03, P4.2-04, P4.7-02` | FR-040 |
| `e2e/fullstack/staging/stg-a22.mjs` | Create. Title prefix `STG-A22` | FR-022, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a22.md` | Create. Cites `P4.2-07, P7.2-03` | FR-040 |
| `e2e/fullstack/staging/stg-a23.mjs` | Create. Title prefix `STG-A23` | FR-023, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a23.md` | Create. Cites `P4.3-03, P4.5-02` | FR-040 |
| `e2e/fullstack/staging/stg-a24.mjs` | Create. Title prefix `STG-A24` | FR-024, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a24.md` | Create. Cites `P3.8-04, P4.8-05` | FR-040 |
| `e2e/fullstack/staging/stg-a25.mjs` | Create. Title prefix `STG-A25` | FR-025, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a25.md` | Create. Cites `P4.11-02, P5.1-06` | FR-040 |
| `e2e/fullstack/staging/stg-a26.mjs` | Create. Title prefix `STG-A26`. Status Partial | FR-026, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a26.md` | Create. Cites `P7.2-09, P8.1-02 (Partial: policy)` | FR-040 |
| `e2e/fullstack/staging/stg-a27.mjs` | Create. Title prefix `STG-A27` | FR-027, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a27.md` | Create. Cites `P3.6-02, P4.8-02, P7.2-06` | FR-040 |
| `e2e/fullstack/staging/stg-a28.mjs` | Create. Title prefix `STG-A28` | FR-028, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a28.md` | Create. Cites `P5.2-03/04, P6.1-03, P6.2-06` | FR-040 |
| `e2e/fullstack/staging/stg-a29.mjs` | Create. Title prefix `STG-A29` | FR-029, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a29.md` | Create. Cites `P3.4-08, P5.2-11, P6.1-04` | FR-040 |
| `e2e/fullstack/staging/stg-a30.mjs` | Create. Title prefix `STG-A30` | FR-030, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a30.md` | Create. Cites `P4.2-02, P6.3-03` | FR-040 |
| `e2e/fullstack/staging/stg-a31.mjs` | Create. Title prefix `STG-A31` | FR-031, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a31.md` | Create. Cites `P3.4-05` | FR-040 |
| `e2e/fullstack/staging/stg-a32.mjs` | Create. Title prefix `STG-A32` | FR-032, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a32.md` | Create. Cites `P3.4-06` | FR-040 |
| `e2e/fullstack/staging/stg-a33.mjs` | Create. Title prefix `STG-A33` | FR-033, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a33.md` | Create. Cites `P4.1-03, P4.7-02` | FR-040 |
| `e2e/fullstack/staging/stg-a34.mjs` | Create. Title prefix `STG-A34` | FR-034, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a34.md` | Create. Cites `P3.4-07, P3.11-05` | FR-040 |
| `e2e/fullstack/staging/stg-a35.mjs` | Create. Title prefix `STG-A35` | FR-035, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a35.md` | Create. Cites `P7.2-07` | FR-040 |
| `e2e/fullstack/staging/stg-a36.mjs` | Create. Title prefix `STG-A36` | FR-036, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-a36.md` | Create. Cites `P1.1-05, P1.2-02, P4.4-09, P7.2-03 (Conditional → met by P1)` | FR-040 |
| `e2e/fullstack/staging/stg-fm-12.mjs` | Create. Title prefix `STG-FM-12` | FR-037, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-fm-12.md` | Create. Cites `P3.5-06, P4.4-04` | FR-040 |
| `e2e/fullstack/staging/stg-fm-13.mjs` | Create. Title prefix `STG-FM-13` | FR-038, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-fm-13.md` | Create. Cites `P3.5-06, P4.4-04` | FR-040 |
| `e2e/fullstack/staging/stg-fm-14.mjs` | Create. Title prefix `STG-FM-14` | FR-039, FR-040, FR-042 |
| `e2e/fullstack/staging/evidence/stg-fm-14.md` | Create. Cites `P3.5-06, P4.4-04` | FR-040 |
| `specs/097-abo-p8-2-staging-acceptance-a1-a36/quickstart.md` | Implement writes this after harness green, from the outline above | FR-040, FR-041, FR-042 |

No new migration, binding, package dependency, or secret. P8.1 files in `e2e/fullstack/staging/` are not modified.

## Test Layout

Tests are authored first and fail before the evidence template, and before the checklist when the row has one. One test per id. The harness does not open a live hostname.

| ID | Harness | Entry → chain | Assertion |
| --- | --- | --- | --- |
| STG-A01 | H-STG `stg-a01.mjs` | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/clinic-api/checkouts.ts`, `abo/src/worker.ts`); `POST /notify/paymob`; `GET /v1/payments`; `public.get_ai_status`; `public.request_ai_status_refresh`. Checklist `manual/paymob-test-card.md` | Three term lengths on the staging offers. AI on within about a minute; payment in history; full allowance; desktop Active; refresh called. Template cites `P4.4-01 (full stack P6.3-01)` |
| STG-A02 | H-STG `stg-a02.mjs` | `public.get_ai_status`; `GET /v1/checkouts` (`abo/src/worker.ts`) | Provisioned with the desktop closed; active on next open; open checkout shows the outcome. Template cites `P4.4-08, P5.2-01, P6.3-02` |
| STG-A03 | H-STG `stg-a03.mjs` | `scheduled()` (`abo/src/worker.ts`). Checklist `manual/blocked-notify-url.md` | Sweep inquires at +2, +5, +10, and +20 minutes and provisions; AL-03. Template cites `P4.5-01` |
| STG-A04 | H-STG `stg-a04.mjs` | `scheduled()` (`abo/src/worker.ts`). Checklist `manual/disabled-platform-route.md` | Grant retries every 15 minutes for 4 days; AL-04 hourly; grant applies on return; term starts at activation. Template cites `P4.4-02` |
| STG-A05 | H-STG `stg-a05.mjs` | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | `attempt_declined`; checkout stays open; one later payment and one grant; nothing cancelled. Template cites `P4.3-04, P6.3-05` |
| STG-A06 | H-STG `stg-a06.mjs` | `GET /v1/payments` (`abo/src/worker.ts`) | Second payment `likely_duplicate`; next term; `duplicate_payment` notice; AL-09. Template cites `P4.3-07, P4.4-05, P6.4-01` |
| STG-A07 | H-STG `stg-a07.mjs` | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | Monthly term at the monthly price; annual checkout expires unpaid. Template cites `P4.3-05` |
| STG-A08 | H-STG `stg-a08.mjs` | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | Intention amount fixed at creation; grant uses that snapshot. Template cites `P4.2-04, P4.7-01, P6.3-04` |
| STG-A09 | H-STG `stg-a09.mjs` | Clinic DO term placement after `POST /v1/checkouts` | Current allowance unchanged; new term starts at the old end with its own allowance. Template cites `P3.5-01` |
| STG-A10 | H-STG `stg-a10.mjs` | Clinic DO alarm | Grace at the end date; grace ends at `grace_ends_at` with no ABO involvement; lapse from dates. Template cites `P3.5-02, P5.2-03` |
| STG-A11 | H-STG `stg-a11.mjs` | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | New term starts at activation, seconds after payment. Template cites `P3.5-05` |
| STG-A12 | H-STG `stg-a12.mjs` | `public.issue_billing_token`; `POST /v1/checkouts` (`abo/src/worker.ts`) | Tenant from the backend session; nothing stored on the desktop. Template cites `P4.2-07, P6.3-02` |
| STG-A13 | H-STG `stg-a13.mjs` | Issuer-key rotation, then `POST /v1/checkouts` (`abo/src/worker.ts`) | Rotation leaves the tenant binding and the terms unchanged; renewal works. Template cites `P3.2-04, P5.1-06` |
| STG-A14 | H-STG `stg-a14.mjs` | HP `beginTransfer` (`abo/src/worker.ts`, `abo/src/ops/index.ts`), then `transferOut` and `transferIn` | Remaining time moves; old identity ends `transferred`; AL-11; reconciliation matches the authorisation. Template cites `P3.8-01, P4.8-04, P5.2-05` |
| STG-A15 | H-STG `stg-a15.mjs` | Ops host HP manual chargeback (`abo/src/worker.ts`) | Effect `end_current`: grant voided; term `reversed` with no grace; queued terms held; AL-06. Template cites `P3.7-01, P4.7-05` |
| STG-A16 | H-STG `stg-a16.mjs` | Checklist `manual/dashboard-refund.md`; `scheduled()` inquiry (`abo/src/worker.ts`) | Folded into a `reversal`, never a payment; inquiry confirms; AL-06; lost-callback bounds in 05 §8 A16. Template cites `P4.5-04/05, P6.4-02` |
| STG-A17 | H-STG `stg-a17.mjs` | Ops host HP chargeback, effect `none` (`abo/src/worker.ts`) | Recorded and alerted; no service change. Template cites `P3.7-03, P4.5-06` |
| STG-A18 | H-STG `stg-a18.mjs` | Payout import, then ops host HP chargeback (`abo/src/worker.ts`) | `unrecorded_reversal`; effect applies; reconciliation clean once linked. Template cites `P4.10-05` |
| STG-A19 | H-STG `stg-a19.mjs` | Complimentary trial term, then `POST /v1/checkouts` (`abo/src/worker.ts`) | Purchase queues after the trial; no gap and no overlap. Template cites `P3.6-07, P4.8-03` |
| STG-A20 | H-STG `stg-a20.mjs` | Ops host HP complimentary grant (`abo/src/worker.ts`) | 14 days, unit `day`, within the 31-day ceiling, queued; AL-11; digest; reconciliation matches `operator_action`. Template cites `P3.6-01, P4.8-01` |
| STG-A21 | H-STG `stg-a21.mjs` | `GET /v1/offers` (`abo/src/worker.ts`) | Retired offer leaves the list; existing terms keep their snapshot; stale id answers `offer_unavailable`. Template cites `P4.1-03, P4.2-04, P4.7-02` |
| STG-A22 | H-STG `stg-a22.mjs` | `public.issue_billing_token`; clinic billing routes (`abo/src/worker.ts`) | No token for another tenant; foreign ids `not_found`; open checkout locks nothing. Template cites `P4.2-07, P7.2-03` |
| STG-A23 | H-STG `stg-a23.mjs` | `scheduled()` (`abo/src/worker.ts`) | AL-02 within 15 minutes; sweeps confirm by inquiry. Template cites `P4.3-03, P4.5-02` |
| STG-A24 | H-STG `stg-a24.mjs` | Ops host HP delete (`abo/src/worker.ts`) | Installation `deleted`; binding `held_for_transfer`; AL-18; `transfer_pending`; renewal waits `transient`; no second binding. Template cites `P3.8-04, P4.8-05` |
| STG-A25 | H-STG `stg-a25.mjs` | Issuer-key expiry path | AL-14 30 days ahead; rotation without an outage; no per-clinic credential. Template cites `P4.11-02, P5.1-06` |
| STG-A26 | H-STG `stg-a26.mjs` | Ops host HP method (`abo/src/worker.ts`); audit watcher | Stored tokens have no production rights by policy; HP needs a passkey; watcher alerts on deploys. Status Partial. Template cites `P7.2-09, P8.1-02 (Partial: policy)` |
| STG-A27 | H-STG `stg-a27.mjs` | Ops host HP complimentary grant (`abo/src/worker.ts`) | No grant without the passkey; 31-day ceiling blocks a year; override needs a second assertion and raises AL-12; AL-11 within minutes; grants listable and voidable. Template cites `P3.6-02, P4.8-02, P7.2-06` |
| STG-A28 | H-STG `stg-a28.mjs` | `public.get_ai_status`; `public.issue_billing_token`; `GET /v1/coverage` | Staff `ends_soon` at 7, 3, and 1 days; lapse from stored dates; no billing token; `/v1/coverage` refuses staff; `/v1/usage` is gone. Template cites `P5.2-03/04, P6.1-03, P6.2-06` |
| STG-A29 | H-STG `stg-a29.mjs` | Clinic admission | Band events at 75% and 90% produce `allowance_low` for every role; admission continues. Template cites `P3.4-08, P5.2-11, P6.1-04` |
| STG-A30 | H-STG `stg-a30.mjs` | `POST /v1/checkouts` → `handlePostCheckout` (`abo/src/worker.ts`) | `starts: after_current`; nothing charged or changed now. Template cites `P4.2-02, P6.3-03` |
| STG-A31 | H-STG `stg-a31.mjs` | Clinic admission, then `POST /v1/checkouts` (`abo/src/worker.ts`) | Exhaustion ends the term on that request with no grace; new term starts at activation; remaining calendar forfeited. Template cites `P3.4-05` |
| STG-A32 | H-STG `stg-a32.mjs` | Clinic admission | Prepaid term starts at the exhaustion instant with its full allowance and runs one month from then. Template cites `P3.4-06` |
| STG-A33 | H-STG `stg-a33.mjs` | `GET /v1/offers` (`abo/src/worker.ts`) | Retired offers are not listed; the owner picks a current offer. Template cites `P4.1-03, P4.7-02` |
| STG-A34 | H-STG `stg-a34.mjs` | Clinic DO admission | Exhaustion recorded once; overshoot at most `w_max − 1`; the other request takes the successor or `allowance_exhausted`. Template cites `P3.4-07, P3.11-05` |
| STG-A35 | H-STG `stg-a35.mjs` | PostgREST | Neither service holds a database credential or Supabase JWT; the backend only pulls. Template cites `P7.2-07` |
| STG-A36 | H-STG `stg-a36.mjs` | ABO routes (`abo/src/worker.ts`) and PostgREST RPCs | Tenant only from the session; `not_found` across tenants; clinic B unchanged and not visible. Template cites `P1.1-05, P1.2-02, P4.4-09, P7.2-03 (Conditional → met by P1)` |
| STG-FM-12 | H-STG `stg-fm-12.mjs` | `scheduled()` (`abo/src/worker.ts`) after the scripted outage window | Catch-up after an outage window. Template cites `P3.5-06, P4.4-04` |
| STG-FM-13 | H-STG `stg-fm-13.mjs` | Scripted bad deploy, rollback, and retry of parked rows | Bad deploy, rollback, retry parked. Template cites `P3.5-06, P4.4-04` |
| STG-FM-14 | H-STG `stg-fm-14.mjs` | Scripted bad deploy, rollback, and retry of parked rows | Bad deploy, rollback, retry parked. Template cites `P3.5-06, P4.4-04` |

Each id's runner is the module that test reaches. The four checklists are reached from STG-A01, STG-A03, STG-A04, and STG-A16. Each evidence template is reached from its runner.

## Sequencing

1. For one scenario id, author the runner so its `node:test` fails because the evidence template is absent, and because the checklist is absent when that id has one.
2. Add that id's evidence template and, for STG-A01, STG-A03, STG-A04, and STG-A16, its checklist. Re-run that id's file and confirm the test passes. The test still does not call a live account.
3. Repeat steps 1 and 2 for the remaining ids. Earlier suites are untouched, so they stay as they were (rule S2).
4. This plan workflow does not run the harness, does not boot wrangler, and does not deploy. Implement runs the command below until it passes, then writes `quickstart.md`.

Command, this unit only. It does not boot a worker and it does not call a live account:

```bash
node --test e2e/fullstack/staging/stg-a*.mjs e2e/fullstack/staging/stg-fm-*.mjs
```

Do not point this command at earlier suites, at P8.1 files, or at `npm test` in `e2e/fullstack/`.

Task grain for the next phase is one task per scenario id. That task writes the failing runner, observes the failure, then adds the evidence template and the checklist when the id has one. The quickstart task is separate. That is 40 tasks, inside the L band (32–40). The count is the 39 scenario ids plus quickstart. It is not padded, and it is not one task per path.

## Complexity Tracking

None. 02 §7 records no constitution violation for this unit.
