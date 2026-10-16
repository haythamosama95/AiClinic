# Console relays: complimentary grants, adjustments, voids, suspension, deletion and the transfer saga

**Unit**: P4.8 · **Harness**: H-XW · **Verification**: T015 green

## 1. What was implemented

Console relays on the ops host forward operator actions to the platform without ABO-side HP verification. `handleOps` in `abo/src/ops/index.ts` verifies Access JWT, records `operator_action`, and calls the matching `PLATFORM` method. Complimentary grants and term adjustments write `grant_request` and `grant_outcome`. Suspend, resume, list-for-void, void, and release-held forward to the platform. Delete-installation and begin-transfer enqueue a `transfer_step` work row; the minute cron drives `runDueTransferSteps` through transient `awaiting_transfer_out` to epoch 2 (FR-001 through FR-011).

- **Console relays and transfer saga** (`abo/src/ops/index.ts`) — `POST` routes for complimentary grant (including ceiling override and term adjustment), suspend, resume, list-for-void, void, release-held, delete-installation, and begin-transfer. `runDueTransferSteps` drives the transfer saga. `GET /ops/clinics/:orgId` adds `binding_epoch` from `getCoverage`.
- **Worker PLATFORM methods and cron** (`abo/src/worker.ts`) — `PLATFORM` gains `grant`, `beginTransfer`, `transferOut`, `transferIn`, `releaseHeld`, `voidGrant`, `listGrantsForVoid`, `suspend`, `resume`, and `deleteInstallation`. The minute `scheduled()` branch calls `runDueTransferSteps`.
- **Vitest include** (`abo/vitest.cross-worker.config.ts`) — adds `test/system/console-relays.cross-worker.test.ts` to H-XW.
- **Harness** — eight E2E scenarios in `abo/test/system/console-relays.cross-worker.test.ts` (H-XW platform worker). The harness observes every scenario; no manual steps.

### 1.1 Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/src/ops/index.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/src/worker.ts` | FR-004, FR-005, FR-009 |
| `abo/vitest.cross-worker.config.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/test/system/console-relays.cross-worker.test.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `specs/083-abo-p4-8-console-relays-complimentary-grants-adjustments/quickstart.md` | FR-001–FR-011 |

## 2. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/console-relays.cross-worker.test.ts
```

## 3. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.8-01 | `opsFetch` complimentary grant (`duration` day 14) → `handleOps` → `PLATFORM.grant`. Same session: `opsFetch` term adjustment → the same route with `kind` `term_adjustment`. 14-day extension applied. AL-11 is a `platform_alert` row on `PLATFORM_DB`. `operator_action` and `grant_request` share the action id |
| E2E-P4.8-02 | `opsFetch` complimentary grant, day count 365, then the same route with `ceiling_override` and `ceiling_override_operation` → `PLATFORM.grant`. First result `rejected`, code `exceeds_ceiling`. Second result applied. AL-12 is a `platform_alert` row |
| E2E-P4.8-03 | `opsFetch` trial complimentary grant → `PLATFORM.grant`. Then `billingFetch` `POST /v1/checkouts` and the existing paid-grant path (`runDueGrantWork` / the paid `grant` work row) on the real platform worker. The paid term queues after the trial |
| E2E-P4.8-04 | Fixture binding starts at epoch 1. `opsFetch` `beginTransfer` → `handleOps` inserts one `transfer_step` row. `runScheduled("* * * * *")` → `runDueTransferSteps` → `PLATFORM.transferIn` then, on the later run, `PLATFORM.transferOut` and `PLATFORM.transferIn`. Clinic page: `opsFetch` `GET /ops/clinics/:orgId` shows `binding_epoch` 2. One `grant_request` per package element, `source_kind` `transfer` |
| E2E-P4.8-05 | `opsFetch` `deleteInstallation` → `PLATFORM.deleteInstallation`. Then `opsFetch` `beginTransfer` with `from_installation_id` of that held binding, and the same `scheduled()` driver. Platform `detail` shows the binding `held_for_transfer`. The transfer runs from that binding |
| E2E-P4.8-06 | `env.PLATFORM.revokeOperatorCredential` on the real platform worker (credential Y revokes X). Then `opsFetch` `list-for-void` with the fixture window, then `opsFetch` `void` for each returned `grant_id` → `PLATFORM.voidGrant`. Listed grants end `voided` |
| E2E-P4.8-07 | `opsFetch` suspend → `PLATFORM.suspend`. Refusal: `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker. Then `opsFetch` resume → `PLATFORM.resume`, and the same platform request again. After suspend the admission outcome is `suspended`. After resume that refusal is gone |
| E2E-P4.8-08 | `opsFetch` complimentary grant with `assertion` omitted → `handleOps` → `PLATFORM.grant`. The platform rejects the call. The test does not expect a new ABO refusal code |
