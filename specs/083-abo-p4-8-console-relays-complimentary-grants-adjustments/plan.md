# Implementation Plan: Console relays: complimentary grants, adjustments, voids, suspension, deletion and the transfer saga

**Branch**: `ai/083-abo-p4-8-console-relays-complimentary-grants-adjustments` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/spec.md`

## Summary

The operator console relays complimentary grants, term adjustments, a ceiling override, suspend and resume, `listGrantsForVoid`, `voidGrant`, `releaseHeld`, `deleteInstallation`, and `beginTransfer`. Depends on P4.7 and P3.8, phase P4, size M. `beginTransfer` records one `transfer_step` work row, and the existing minute `scheduled()` drives `transferOut` then `transferIn` until both are applied. The platform verifies every relay. This unit does not add a worker, a hostname, or a scheduler.

## Technical Context

**Language/Version**: TypeScript on the existing ABO Cloudflare Worker (`abo/`).

**Primary Dependencies**: `vendor-contracts` (`canonicalize`, `sha256Hex`). Existing `PLATFORM` binding methods on the real platform worker: `grant`, `beginTransfer`, `transferOut`, `transferIn`, `releaseHeld`, `voidGrant`, `listGrantsForVoid`, `suspend`, `resume`, `deleteInstallation`, `revokeOperatorCredential`, `getCoverage`, `inspectCoverage`. Existing Access check `verifyOpsAccess`. Existing clock (`clockNowIso`).

**Storage**: Existing ABO D1 tables `grant_request`, `grant_outcome`, `operator_action`, and `work`. No new table. `transfer_step` is a `work.kind`. Transfer `n` is the 0-based index of that element in the transfer package (03 §7, as amended).

**Testing**: Harness H-XW. One vitest file, titles prefixed with the E2E id. Red tests before implementation.

**Target Platform**: ABO ops host (`OPS_HOST`), `/ops/*`, delegated by the existing worker fetch. The clinic purchase in E2E-P4.8-03 is the existing `POST /v1/checkouts` on `BILLING_HOST`. The transfer saga is the existing minute cron on that same worker.

**Project Type**: ABO worker module extension. Codebase is `abo`. No second codebase.

**Performance Goals**: One operator and a few orders a day (02 §7). One `transfer_step` row per `transfer_id`. A `transient` result waits for the next minute `scheduled()` run.

**Constraints**: The console forwards the Access JWT. Each HP method also forwards `assertion`. The platform verifies. These relays do not call `recordOperatorAction`. A missing HP `assertion` is still forwarded. The platform's existing rejection is the result. No new refusal code. Complimentary `grant_id` is SHA-256 over `"grant:comp:"` ‖ the operator action id. Transfer `grant_id` is SHA-256 over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n, with n decimal digits and no leading zeros. One `grant_request` per package element, and none when the package is empty. A later run does not insert a second row for the same n. `assertion` on `grant_request` is complimentary only.

**Scale/Scope**: Eight H-XW scenarios. Relays live in `abo/src/ops/`. The saga driver is called from `scheduled()` in `abo/src/worker.ts`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked again against 02 §7 and constitution v2.0.0. 02 §7 records no violation for this unit.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — One operator grants complimentary coverage, adjusts a term, overrides the ceiling, suspends or resumes a clinic, voids grants, deletes an installation, and transfers the remaining coverage (02 §7 principle I; spec §4.1 Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — The work stays in the existing ABO worker and D1. The transfer is the existing two-step saga on one work row, driven by the minute cron (02 §7 principle I and the workflow-automation row).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — Codebase is `abo`. The platform is called only through the frozen `PLATFORM` binding. No clinical data and no database credential (02 §7 principle II).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — Clinic-side state is unchanged. Vendor-side integrity uses the existing D1 append-only triggers on `grant_request`, `grant_outcome`, and `operator_action` (02 §7 principle III).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — `verifyOpsAccess` requires the Access JWT. HP relays also forward `assertion`. The platform writes `control_audit`. One `operator_action` is written per action. `deleteInstallation` marks the installation `deleted` and, with time left, holds the binding (02 §7 principle IV).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — Value-moving relays are class HP and the platform checks the passkey. Suspend and resume are class H. This unit does not add an AI write path into clinic data (02 §7 principle V).

## Project Structure

### Documentation (this feature)

```text
specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/
├── plan.md
├── data-model.md
└── quickstart.md          # implement writes this after the eight H-XW tests pass
```

`research.md` is omitted. Spikes are none. `contracts/` is omitted. Freezes has no wire shape. `tasks.md` is not created in this phase.

#### Quickstart outline

Implement writes `quickstart.md` after the harness is green. Sections only:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only: `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/console-relays.cross-worker.test.ts` from `abo/`
- Entry point → module chain per E2E id (the Test Layout chains below)
- Manual steps: none. The harness can see every behaviour in the test plan

### Source Code (repository root)

```text
abo/src/ops/index.ts
abo/src/worker.ts
abo/test/system/console-relays.cross-worker.test.ts
abo/vitest.cross-worker.config.ts
```

**Structure Decision**: Codebase is `abo`. `handleOps` in `abo/src/ops/index.ts` gains the relays. The worker fetch already delegates `OPS_HOST` + `/ops/*`. `scheduled()` on `* * * * *` calls the transfer driver in that same ops module. `opsFetch` and `billingFetch` stay in `abo/test/system/harness.ts`. `VendorEntrypoint` stays unchanged.

## Consumes Binding

| Consumes | Bound to | This unit |
| --- | --- | --- |
| P4.7 | None. The unit row states no Outputs / freezes line. | Not a frozen contract. `abo/src/ops/index.ts` gains routes. Existing HP verification and `recordOperatorAction` stay as they are for ABO-verified actions. |
| P3.8 | None. The unit row states no Outputs / freezes line. | Not a frozen output to bind. This unit calls the platform methods named in the Read rows. It does not change those methods. |

## Files

| Path | Change | FR |
| --- | --- | --- |
| `abo/src/ops/index.ts` | Relays and the `transfer_step` driver below. `PLATFORM` on `OpsEnv` gains `grant`, `beginTransfer`, `transferOut`, `transferIn`, `releaseHeld`, `voidGrant`, `listGrantsForVoid`, `suspend`, `resume`, `deleteInstallation`. `GET /ops/clinics/:orgId` adds `binding_epoch` from the existing `getCoverage` snapshot. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/src/worker.ts` | `PLATFORM` gains the same methods. The minute `scheduled()` branch calls `runDueTransferSteps`. | FR-004, FR-005, FR-009 |
| `abo/test/system/console-relays.cross-worker.test.ts` | H-XW tests E2E-P4.8-01 through E2E-P4.8-08. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/vitest.cross-worker.config.ts` | Add the new test file to the H-XW `include` list. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |

No migration. `grant_request`, `grant_outcome`, `operator_action`, and `work` already exist.

### Relay shape

Every new route runs the existing `verifyOpsAccess` first. The verified Access JWT is the `access_jwt` forwarded to the platform. These routes do not use the ABO-side HP verifier and do not call `recordOperatorAction`. The platform writes `control_audit` when it verifies the call.

The body carries `action_id`. The handler inserts one `operator_action` with that id, the Access email as `actor_email`, and the platform result. A second insert of the same `action_id` does not run. `subject` is the org id or grant id in the path. `listGrantsForVoid` uses `credential_id` as `subject`.

`grant_request` and `grant_outcome` inserts also write `fact_log` the same way `abo/src/work/grant.ts` already does for those tables.

| Route | Platform method | Class |
| --- | --- | --- |
| `POST /ops/orgs/:orgId/complimentary-grant` | `grant` | HP |
| `POST /ops/orgs/:orgId/suspend` | `suspend` | H |
| `POST /ops/orgs/:orgId/resume` | `resume` | H |
| `POST /ops/grants/list-for-void` | `listGrantsForVoid` | H |
| `POST /ops/grants/:grantId/void` | `voidGrant` | HP |
| `POST /ops/grants/:grantId/release-held` | `releaseHeld` | HP |
| `POST /ops/orgs/:orgId/delete-installation` | `deleteInstallation` | HP |
| `POST /ops/orgs/:orgId/begin-transfer` | `beginTransfer` | HP |

`releaseHeld` and `voidGrant` are one function. The path chooses the method. E2E-P4.8-06 enters that function through `void`.

### Complimentary grant and term adjustment

`POST /ops/orgs/:orgId/complimentary-grant` forwards `envelope`, `operation`, `assertion`, `signer_credential_id`, and, when present, `ceiling_override_operation`. The envelope's `grant_id` is SHA-256 hex over `"grant:comp:"` ‖ `action_id`. `source.kind` is `complimentary`. `source.ref` is `action_id`. `kind` `term` is the complimentary grant. `kind` `term_adjustment` is the adjustment, with `adjustment` on the envelope. Both write `grant_request` with `source_kind` `complimentary`, `source_ref` the action id, the canonical envelope, `envelope_sha256`, and `assertion`. `grant_outcome` records the platform `result`, the platform `receipt` when present, `term_ids`, and `at`. `abo_kid` and `abo_signature` stay null.

A 14-day extension is `duration` `{unit: "day", count: 14}`. The same route accepts one term adjustment in the same session. A 365-day grant is `duration` `{unit: "day", count: 365}`. The first response is the platform's `exceeds_ceiling`. The second request puts the second passkey on `envelope.ceiling_override` and forwards `ceiling_override_operation`. The platform applies it and raises AL-12. A trial is the same route with a `day` count the fixture chooses inside the current ceiling. That count is fixture data, not a product default.

The console response returns the platform result, including `code` when the result is `rejected`.

### Class H and the other HP relays

`suspend` and `resume` forward `org_id` and `reason` with `access_jwt` and no assertion. `listGrantsForVoid` forwards `credential_id` and `window` as `{applied_from, applied_to}`. The window values are the fixture's inclusive UTC ISO-8601 timestamps. `voidGrant` and `releaseHeld` forward `grant_id`, `reason`, `operation`, `assertion`, and `signer_credential_id`. `deleteInstallation` forwards `org_id`, `reason`, and the HP assertion fields, and the console response includes the platform `detail`. `beginTransfer` forwards `org_id`, `from_installation_id`, `reason`, and the HP assertion fields.

### Transfer saga

On `beginTransfer` `ok`, read `transfer_id` from the platform `detail`. Insert one `work` row: `kind` `transfer_step`, `subject_id` and the dedupe key `transfer_step:` ‖ `transfer_id`, `state` `open`, `next_attempt_at` null. If that dedupe key already exists, do not insert another row.

`runDueTransferSteps` runs from the minute cron only. It takes each open `transfer_step` row whose `next_attempt_at` is null or already due, with the existing lease update. It does not change `next_attempt_at` and it does not insert another row.

- When that row has not yet seen `transferOut` `applied` or `already_applied`, call `transferIn` once. `transient` with `detail` `awaiting_transfer_out` is stored on `last_error`. The lease is cleared and the row stays `open`. That run does not call `transferOut`.
- A later run calls `transferOut`. `applied` or `already_applied` writes one `grant_request` per element of the package JSON array in `detail`, when `detail` is that array. `n` is the element's index. `grant_id` is SHA-256 hex over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. `source_kind` is `transfer`, `source_ref` is `transfer_id`, `assertion` is null, and `org_id` is the transfer's org. An `n` whose `grant_id` already exists is skipped. An empty array writes none. The run then calls `transferIn`.
- A `transient` `transferIn` after that stores `last_error`, clears the lease, and leaves the row `open`.
- When `transferIn` is `applied` or `already_applied`, the row is `done` and the lease is cleared.

`GET /ops/clinics/:orgId` includes `binding_epoch` from `getCoverage` `detail.snapshot.binding_epoch`.

### Assertion omitted

E2E-P4.8-08 calls `POST /ops/orgs/:orgId/complimentary-grant` through `opsFetch` with `assertion` omitted. `handleOps` still calls `PLATFORM.grant`. The platform rejects that call. The handler writes `operator_action` and does not add a refusal code.

## Test Layout

Tests are written first and observed failing. Each title is prefixed with its E2E id. Harness H-XW (`abo/test/system/`, cross-worker vitest, real platform worker from source). Entry is `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`, except where a row also names `billingFetch`, `scheduled()`, or a direct `VendorEntrypoint` call.

| ID | Title prefix | Entry → module chain | Assertion |
| --- | --- | --- | --- |
| E2E-P4.8-01 | `E2E-P4.8-01` | `opsFetch` complimentary grant (`duration` day 14) → `handleOps` → `PLATFORM.grant`. Same session: `opsFetch` term adjustment → the same route with `kind` `term_adjustment`. | 14-day extension applied. AL-11 is a `platform_alert` row on `PLATFORM_DB`. `operator_action` and `grant_request` share the action id (`source_ref`, and `grant_id` is the comp form). The adjustment is applied. |
| E2E-P4.8-02 | `E2E-P4.8-02` | `opsFetch` complimentary grant, day count 365, then the same route with `ceiling_override` and `ceiling_override_operation` → `PLATFORM.grant`. | First result `rejected`, code `exceeds_ceiling`. Second result applied. AL-12 is a `platform_alert` row. |
| E2E-P4.8-03 | `E2E-P4.8-03` | `opsFetch` trial complimentary grant → `PLATFORM.grant`. Then `billingFetch` `POST /v1/checkouts` and the existing paid-grant path (`runDueGrantWork` / the paid `grant` work row) on the real platform worker. | The paid term queues after the trial. |
| E2E-P4.8-04 | `E2E-P4.8-04` | The fixture binding starts at epoch 1 with coverage to move. `opsFetch` `beginTransfer` → `handleOps` inserts one `transfer_step` row. `runScheduled("* * * * *")` → `runDueTransferSteps` → `PLATFORM.transferIn` then, on the later run, `PLATFORM.transferOut` and `PLATFORM.transferIn`. Clinic page: `opsFetch` `GET /ops/clinics/:orgId`. | The first run leaves `last_error` `awaiting_transfer_out` and the row `open`. Later runs reach `applied` or `already_applied` for both calls. The clinic page `binding_epoch` is 2. One `grant_request` per package element, `source_kind` `transfer`. |
| E2E-P4.8-05 | `E2E-P4.8-05` | `opsFetch` `deleteInstallation` → `PLATFORM.deleteInstallation`. Then `opsFetch` `beginTransfer` with `from_installation_id` of that held binding, and the same `scheduled()` driver. | Platform `detail` shows the binding `held_for_transfer`. The transfer runs from that binding. |
| E2E-P4.8-06 | `E2E-P4.8-06` | `env.PLATFORM.revokeOperatorCredential` on the real platform worker (credential Y revokes X). Then `opsFetch` `list-for-void` with the fixture window, then `opsFetch` `void` for each returned `grant_id` → `PLATFORM.voidGrant`. | Listed grants end `voided`. |
| E2E-P4.8-07 | `E2E-P4.8-07` | `opsFetch` suspend → `PLATFORM.suspend`. Refusal: `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker, the same call shape as `platformHttpInvoke` in `abo/test/system/grant.cross-worker.test.ts`. Then `opsFetch` resume → `PLATFORM.resume`, and the same platform request again. | After suspend the admission outcome is `suspended`. After resume that refusal is gone. |
| E2E-P4.8-08 | `E2E-P4.8-08` | `opsFetch` complimentary grant with `assertion` omitted → `handleOps` → `PLATFORM.grant`. | The platform rejects the call. The test does not expect a new ABO refusal code. |

## Sequencing

1. Add the H-XW test file and its vitest include. Run it and observe E2E-P4.8-01 through E2E-P4.8-08 failing.
2. Extend `PLATFORM` on `OpsEnv` and on the worker `Env`.
3. Implement the complimentary-grant relay, `operator_action`, `grant_request`, and `grant_outcome`, so E2E-P4.8-01 and E2E-P4.8-03 pass. E2E-P4.8-03's purchase stays on the existing checkout and paid-grant path.
4. Forward `ceiling_override` on that same relay so E2E-P4.8-02 passes.
5. Implement suspend, resume, list, void, and release-held so E2E-P4.8-06 and E2E-P4.8-07 pass.
6. Implement delete and begin-transfer, the one `transfer_step` row, and `runDueTransferSteps` on the minute cron, including package `grant_request` rows and `binding_epoch` on the clinic page, so E2E-P4.8-04 and E2E-P4.8-05 pass.
7. The assertion-less forward is the complimentary-grant relay with `assertion` omitted, so E2E-P4.8-08 passes with step 3.
8. After all eight tests pass, implement writes `quickstart.md`. That file is not part of this phase.

## Complexity Tracking

02 §7 records no constitution violation for this unit. No row.
