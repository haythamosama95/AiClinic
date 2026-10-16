# Console passkey ceremony and ABO-side HP actions

**Unit**: P4.7 · **Harness**: H-XW · **Verification**: T013 green

## 1. What was implemented

HP actions on the ops console require a WebAuthn passkey ceremony before any write. `handleOps` in `abo/src/ops/index.ts` verifies the operation and assertion, records `operator_action`, and calls `recordOperatorAction` on the platform. Catalogue actions publish, retire, and reinstate offers. Release applies a withheld payment grant. Manual chargeback runs the reversal pipeline. Erasure blanks tenant contact data (FR-001 through FR-011).

- **HP verification and routes** (`abo/src/ops/index.ts`) — six `POST` routes under `/ops/*` with passkey ceremony checks (`assertion_required`, `assertion_expired`, `credential_not_active`, `assertion_used`, and related refusals). Catalogue, release, manual chargeback, and erasure handlers commit `operator_action` then call `recordPlatformOperatorAction`.
- **Schema** (`abo/migrations/0007_hp_actions.sql`) — append-only `assertion_used` (`challenge_sha256` primary key) and `payment_release` (`payment_id` primary key, `operator_action_id`, `at`).
- **Sellable offer check** (`abo/src/clinic-api/checkouts.ts`) — `sellableOfferVersion` returns null when the latest `offer_event` is not `published`.
- **Grant after release** (`abo/src/work/grant.ts`) — `runDueGrantWork` also runs when a `payment_release` row exists for the payment.
- **Vitest include** (`abo/vitest.cross-worker.config.ts`) — adds `test/system/hp-actions.cross-worker.test.ts` to H-XW.
- **Harness** — seven E2E scenarios in `abo/test/system/hp-actions.cross-worker.test.ts` (H-XW platform worker). The harness observes every scenario; no manual steps.

### 1.1 Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0007_hp_actions.sql` | FR-002, FR-008 |
| `abo/src/ops/index.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/src/clinic-api/checkouts.ts` | FR-006 |
| `abo/src/work/grant.ts` | FR-008 |
| `abo/vitest.cross-worker.config.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/test/system/hp-actions.cross-worker.test.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/quickstart.md` | FR-001–FR-011 |

## 2. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/hp-actions.cross-worker.test.ts
```

## 3. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.7-01 | `opsFetch` publish → `handleOps` catalogue action → `offer_event` / `offer_version` / terms R2 / `operator_action` / `recordOperatorAction`. Outcome: `billingFetch` `GET /v1/offers` (`listOffers`) and the open v1 checkout's existing charge and grant |
| E2E-P4.7-02 | `opsFetch` retire → `handleOps` catalogue action. Outcome: `billingFetch` `GET /v1/offers` and `POST /v1/checkouts` (`sellableOfferVersion`), and existing platform terms on the real platform worker |
| E2E-P4.7-03 | `opsFetch` three HP calls → `handleOps` verification → `operator_action`. One call omits `assertion`. One call's operation does not match the challenge. The test clock places one `issued_at` more than 5 minutes in the past |
| E2E-P4.7-04 | `opsFetch` release → `handleOps` → `payment_release` and grant `work` → `runDueGrantWork`. The refusal case uses a withheld payment whose reversal rows are already fully reversed |
| E2E-P4.7-05 | A real H-XW purchase so the payment funds the current term. `opsFetch` chargeback → `handleOps` → `reversal` → `determineReversalEffect`, `raiseAlert`, `insertReverseWorkRow`, `processReverseWork` → platform `voidForReversal` |
| E2E-P4.7-06 | `opsFetch` erase → `handleOps` → `billing_contact` and R2 evidence keys. Outcome: D1 hashes, `ledger/` export, then `billingFetch` `POST /v1/checkouts` |
| E2E-P4.7-07 | Platform `revokeOperatorCredential` on the real `VendorEntrypoint`, then `opsFetch` HP → `handleOps` calls `listOperatorCredentials` again |
